// -----------------------------------------------------------------------------
// tcp_frame_tx.sv — Build and emit one Ethernet/IPv4/TCP frame on AXIS-64
// Store-and-forward: latch request, compute checksums, fill buffer, stream out.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tcp_frame_tx
  import tcp_pkg::*;
#(
  parameter int MAX_PAYLOAD = 512,
  parameter int MAX_FRAME   = 14 + 20 + 20 + MAX_PAYLOAD
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic [47:0] local_mac,
  input  logic [47:0] remote_mac,
  input  logic [31:0] local_ip,
  input  logic [31:0] remote_ip,
  input  logic [15:0] local_port,
  input  logic [15:0] remote_port,

  input  logic        req_valid,
  output logic        req_ready,
  input  pkt_kind_e   req_kind,
  input  logic [31:0] req_seq,
  input  logic [31:0] req_ack,
  input  logic [15:0] req_window,
  input  logic [15:0] req_payload_len,

  // Payload RAM read (1 byte / cycle during CSUM and COPY)
  output logic [15:0] pl_addr,
  input  logic [7:0]  pl_data,

  output logic [63:0] m_axis_tdata,
  output logic [7:0]  m_axis_tkeep,
  output logic        m_axis_tvalid,
  output logic        m_axis_tlast,
  input  logic        m_axis_tready,

  output logic        tx_done_pulse
);

  logic [7:0]  frame [0:MAX_FRAME-1];
  logic [15:0] frame_len;
  logic [15:0] rd_ptr;
  logic [15:0] pl_idx;

  typedef enum logic [2:0] {
    ST_IDLE  = 3'd0,
    ST_CSUM  = 3'd1,
    ST_HDR   = 3'd2,
    ST_COPY  = 3'd3,
    ST_SEND  = 3'd4
  } state_t;

  state_t state;

  logic [7:0]  flags_r;
  logic [15:0] plen_r;
  logic [15:0] ip_csum_r;
  logic [15:0] tcp_csum_r;
  logic [31:0] seq_r, ack_r;
  logic [15:0] window_r;
  logic [31:0] tcp_acc_r;
  logic        csum_pending; // need one extra cycle after last byte for pl_data

  assign req_ready = (state == ST_IDLE);

  integer bi;

  // Pure IP header checksum
  function automatic logic [15:0] calc_ip_csum(
      input logic [31:0] sip,
      input logic [31:0] dip,
      input logic [15:0] total_len
  );
    logic [31:0] acc;
    acc = '0;
    acc = acc_add16(acc, 16'h4500);
    acc = acc_add16(acc, total_len);
    acc = acc_add16(acc, 16'h0001);
    acc = acc_add16(acc, 16'h4000);
    acc = acc_add16(acc, 16'h4006);
    acc = acc_add16(acc, sip[31:16]);
    acc = acc_add16(acc, sip[15:0]);
    acc = acc_add16(acc, dip[31:16]);
    acc = acc_add16(acc, dip[15:0]);
    calc_ip_csum = finalize_csum(acc);
  endfunction

  // Pseudo-header + TCP header (no payload) accumulator seed
  function automatic logic [31:0] tcp_hdr_seed(
      input logic [31:0] sip, input logic [31:0] dip,
      input logic [15:0] sport, input logic [15:0] dport,
      input logic [31:0] seq, input logic [31:0] ack,
      input logic [7:0] flags, input logic [15:0] window,
      input logic [15:0] tcp_len
  );
    logic [31:0] acc;
    acc = '0;
    acc = acc_add16(acc, sip[31:16]);
    acc = acc_add16(acc, sip[15:0]);
    acc = acc_add16(acc, dip[31:16]);
    acc = acc_add16(acc, dip[15:0]);
    acc = acc_add16(acc, {8'd0, IP_PROTO_TCP});
    acc = acc_add16(acc, tcp_len);
    acc = acc_add16(acc, sport);
    acc = acc_add16(acc, dport);
    acc = acc_add16(acc, seq[31:16]);
    acc = acc_add16(acc, seq[15:0]);
    acc = acc_add16(acc, ack[31:16]);
    acc = acc_add16(acc, ack[15:0]);
    acc = acc_add16(acc, {8'h50, flags});
    acc = acc_add16(acc, window);
    acc = acc_add16(acc, 16'h0000); // urg ptr
    tcp_hdr_seed = acc;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state         <= ST_IDLE;
      frame_len     <= '0;
      rd_ptr        <= '0;
      pl_idx        <= '0;
      pl_addr       <= '0;
      m_axis_tdata  <= '0;
      m_axis_tkeep  <= '0;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast  <= 1'b0;
      tx_done_pulse <= 1'b0;
      flags_r       <= '0;
      plen_r        <= '0;
      ip_csum_r     <= '0;
      tcp_csum_r    <= '0;
      seq_r         <= '0;
      ack_r         <= '0;
      window_r      <= '0;
      tcp_acc_r     <= '0;
      csum_pending  <= 1'b0;
    end else begin
      tx_done_pulse <= 1'b0;

      unique case (state)
        ST_IDLE: begin
          m_axis_tvalid <= 1'b0;
          m_axis_tlast  <= 1'b0;
          pl_addr       <= '0;
          pl_idx        <= '0;
          csum_pending  <= 1'b0;
          if (req_valid) begin
            seq_r    <= req_seq;
            ack_r    <= req_ack;
            window_r <= req_window;
            unique case (req_kind)
              PKT_SYN:  begin flags_r <= TCP_SYN;             plen_r <= 16'd0; end
              PKT_ACK:  begin flags_r <= TCP_ACK;             plen_r <= 16'd0; end
              PKT_DATA: begin flags_r <= (TCP_ACK | TCP_PSH); plen_r <= req_payload_len; end
              PKT_FIN:  begin flags_r <= (TCP_FIN | TCP_ACK); plen_r <= 16'd0; end
              default:  begin flags_r <= TCP_ACK;             plen_r <= 16'd0; end
            endcase
            // Enter CSUM on a dedicated "seed" cycle via csum_pending=0, pl_idx=0
            // Use bit0 of filling flag substitute: set csum_pending=0 and mark seed
            // by leaving state transition; ST_CSUM uses !csum_pending && !seed_done
            state <= ST_CSUM;
          end
        end

        ST_CSUM: begin
          // Seed cycle: csum_pending==0 and we have not started walking payload yet.
          // Use tcp_csum_r[0] isn't available; track with pl_addr==0 && !csum_pending
          // after IDLE always resets pl_*. First cycle always seeds.
          if (!csum_pending) begin
            ip_csum_r <= calc_ip_csum(local_ip, remote_ip, 16'd40 + plen_r);
            tcp_acc_r <= tcp_hdr_seed(
                local_ip, remote_ip, local_port, remote_port,
                seq_r, ack_r, flags_r, window_r, 16'd20 + plen_r);
            if (plen_r == 16'd0) begin
              tcp_csum_r <= finalize_csum(tcp_hdr_seed(
                  local_ip, remote_ip, local_port, remote_port,
                  seq_r, ack_r, flags_r, window_r, 16'd20));
              state <= ST_HDR;
            end else begin
              pl_addr      <= 16'd0;
              pl_idx       <= 16'd0;
              csum_pending <= 1'b1; // next cycle consume pl_data[0]
            end
          end else begin
            // csum_pending: accumulate pl_data for current pl_idx
            tcp_acc_r <= acc_add8(tcp_acc_r, pl_data, ~pl_idx[0]);
            if (pl_idx + 16'd1 >= plen_r) begin
              tcp_csum_r   <= finalize_csum(acc_add8(tcp_acc_r, pl_data, ~pl_idx[0]));
              csum_pending <= 1'b0;
              pl_idx       <= '0;
              pl_addr      <= '0;
              state        <= ST_HDR;
            end else begin
              pl_idx  <= pl_idx + 16'd1;
              pl_addr <= pl_idx + 16'd1;
            end
          end
        end

        ST_HDR: begin
          frame[0]  <= remote_mac[47:40];
          frame[1]  <= remote_mac[39:32];
          frame[2]  <= remote_mac[31:24];
          frame[3]  <= remote_mac[23:16];
          frame[4]  <= remote_mac[15:8];
          frame[5]  <= remote_mac[7:0];
          frame[6]  <= local_mac[47:40];
          frame[7]  <= local_mac[39:32];
          frame[8]  <= local_mac[31:24];
          frame[9]  <= local_mac[23:16];
          frame[10] <= local_mac[15:8];
          frame[11] <= local_mac[7:0];
          frame[12] <= 8'h08;
          frame[13] <= 8'h00;
          frame[14] <= 8'h45;
          frame[15] <= 8'h00;
          frame[16] <= (16'd40 + plen_r) >> 8;
          frame[17] <= (16'd40 + plen_r) & 16'hFF;
          frame[18] <= 8'h00;
          frame[19] <= 8'h01;
          frame[20] <= 8'h40;
          frame[21] <= 8'h00;
          frame[22] <= 8'h40;
          frame[23] <= IP_PROTO_TCP;
          frame[24] <= ip_csum_r[15:8];
          frame[25] <= ip_csum_r[7:0];
          frame[26] <= local_ip[31:24];
          frame[27] <= local_ip[23:16];
          frame[28] <= local_ip[15:8];
          frame[29] <= local_ip[7:0];
          frame[30] <= remote_ip[31:24];
          frame[31] <= remote_ip[23:16];
          frame[32] <= remote_ip[15:8];
          frame[33] <= remote_ip[7:0];
          frame[34] <= local_port[15:8];
          frame[35] <= local_port[7:0];
          frame[36] <= remote_port[15:8];
          frame[37] <= remote_port[7:0];
          frame[38] <= seq_r[31:24];
          frame[39] <= seq_r[23:16];
          frame[40] <= seq_r[15:8];
          frame[41] <= seq_r[7:0];
          frame[42] <= ack_r[31:24];
          frame[43] <= ack_r[23:16];
          frame[44] <= ack_r[15:8];
          frame[45] <= ack_r[7:0];
          frame[46] <= 8'h50;
          frame[47] <= flags_r;
          frame[48] <= window_r[15:8];
          frame[49] <= window_r[7:0];
          frame[50] <= tcp_csum_r[15:8];
          frame[51] <= tcp_csum_r[7:0];
          frame[52] <= 8'h00;
          frame[53] <= 8'h00;
          frame_len <= 16'd54 + plen_r;
          if (plen_r == 16'd0) begin
            rd_ptr <= '0;
            state  <= ST_SEND;
          end else begin
            pl_idx       <= '0;
            pl_addr      <= '0;
            csum_pending <= 1'b1;
            state        <= ST_COPY;
          end
        end

        ST_COPY: begin
          // pl_addr was set previous cycle; pl_data is combo from order_buffer
          frame[16'd54 + pl_idx] <= pl_data;
          if (pl_idx + 16'd1 >= plen_r) begin
            rd_ptr  <= '0;
            pl_addr <= '0;
            state   <= ST_SEND;
          end else begin
            pl_idx  <= pl_idx + 16'd1;
            pl_addr <= pl_idx + 16'd1;
          end
        end

        ST_SEND: begin
          if (!m_axis_tvalid) begin
            begin
              automatic logic [15:0] remain = frame_len - rd_ptr;
              automatic int nbytes = (remain > 16'd8) ? 8 : int'(remain);
              automatic logic [63:0] data = 64'h0;
              automatic logic [7:0] keep = 8'h00;
              for (bi = 0; bi < 8; bi++) begin
                if (bi < nbytes) begin
                  data[bi*8 +: 8] = frame[rd_ptr + bi[15:0]];
                  keep[bi] = 1'b1;
                end
              end
              m_axis_tdata  <= data;
              m_axis_tkeep  <= keep;
              m_axis_tvalid <= 1'b1;
              m_axis_tlast  <= (remain <= 16'd8);
              rd_ptr        <= rd_ptr + nbytes[15:0];
            end
          end else if (m_axis_tready) begin
            if (m_axis_tlast) begin
              m_axis_tvalid <= 1'b0;
              m_axis_tlast  <= 1'b0;
              state         <= ST_IDLE;
              tx_done_pulse <= 1'b1;
            end else begin
              automatic logic [15:0] remain = frame_len - rd_ptr;
              automatic int nbytes = (remain > 16'd8) ? 8 : int'(remain);
              automatic logic [63:0] data = 64'h0;
              automatic logic [7:0] keep = 8'h00;
              for (bi = 0; bi < 8; bi++) begin
                if (bi < nbytes) begin
                  data[bi*8 +: 8] = frame[rd_ptr + bi[15:0]];
                  keep[bi] = 1'b1;
                end
              end
              m_axis_tdata  <= data;
              m_axis_tkeep  <= keep;
              m_axis_tvalid <= 1'b1;
              m_axis_tlast  <= (remain <= 16'd8);
              rd_ptr        <= rd_ptr + nbytes[15:0];
            end
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
