// -----------------------------------------------------------------------------
// tcp_client_sm.sv — One-connection TCP client control (TX/session side)
// CLOSED -> SYN_SENT -> ESTABLISHED -> (send data, track ACK) -> FIN_WAIT_1
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tcp_client_sm
  import tcp_pkg::*;
#(
  parameter logic [31:0] ISS = 32'h1000_0000,
  parameter logic [15:0] RCV_WND = 16'd65535
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        connect_req,
  input  logic        close_req,

  // From RX parser
  input  logic        seg_valid,
  input  logic        seg_csum_bad,
  input  logic [31:0] seg_seq,
  input  logic [31:0] seg_ack,
  input  logic [7:0]  seg_flags,
  input  logic [15:0] seg_window,
  input  logic [15:0] seg_payload_len,

  // Order send app
  input  logic        order_send_req,
  input  logic [15:0] order_len,
  output logic        order_send_ready, // ESTABLISHED && !outstanding && tx free
  output logic        order_send_done,  // peer ACKed our data

  // To TX engine
  output logic        tx_req_valid,
  input  logic        tx_req_ready,
  output pkt_kind_e   tx_req_kind,
  output logic [31:0] tx_req_seq,
  output logic [31:0] tx_req_ack,
  output logic [15:0] tx_req_window,
  output logic [15:0] tx_req_payload_len,
  input  logic        tx_done_pulse,

  // Status
  output tcp_state_e  state,
  output logic        established,
  output logic [31:0] snd_una,
  output logic [31:0] snd_nxt,
  output logic [31:0] rcv_nxt,
  output logic        outstanding
);

  tcp_state_e state_r;
  logic [31:0] snd_una_r, snd_nxt_r, rcv_nxt_r;
  logic        outstanding_r;
  logic [15:0] outstanding_len_r;
  logic        tx_pending;
  pkt_kind_e   pending_kind;
  logic [15:0] pending_plen;
  pkt_kind_e   inflight_kind;   // kind accepted by TX, used at tx_done
  logic [15:0] inflight_plen;
  logic        need_ack_tx; // send pure ACK after SYN-ACK
  logic        tx_busy;     // accepted by TX until tx_done

  assign state        = state_r;
  assign established  = (state_r == ST_ESTABLISHED);
  assign snd_una      = snd_una_r;
  assign snd_nxt      = snd_nxt_r;
  assign rcv_nxt      = rcv_nxt_r;
  assign outstanding  = outstanding_r;

  assign order_send_ready = (state_r == ST_ESTABLISHED)
                         && !outstanding_r
                         && !tx_pending
                         && !tx_busy
                         && !need_ack_tx;

  assign tx_req_valid       = tx_pending;
  assign tx_req_kind        = pending_kind;
  assign tx_req_seq         = snd_nxt_r;
  assign tx_req_ack         = rcv_nxt_r;
  assign tx_req_window      = RCV_WND;
  assign tx_req_payload_len = pending_plen;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_r           <= ST_CLOSED;
      snd_una_r         <= ISS;
      snd_nxt_r         <= ISS;
      rcv_nxt_r         <= '0;
      outstanding_r     <= 1'b0;
      outstanding_len_r <= '0;
      tx_pending        <= 1'b0;
      pending_kind      <= PKT_NONE;
      pending_plen      <= '0;
      inflight_kind     <= PKT_NONE;
      inflight_plen     <= '0;
      need_ack_tx       <= 1'b0;
      tx_busy           <= 1'b0;
      order_send_done   <= 1'b0;
    end else begin
      order_send_done <= 1'b0;

      // Accept TX request
      if (tx_pending && tx_req_ready) begin
        tx_pending    <= 1'b0;
        tx_busy       <= 1'b1;
        inflight_kind <= pending_kind;
        inflight_plen <= pending_plen;
      end

      // Advance seq on successful emit
      if (tx_done_pulse) begin
        tx_busy <= 1'b0;
        unique case (inflight_kind)
          PKT_SYN:  snd_nxt_r <= snd_nxt_r + 32'd1;
          PKT_FIN:  snd_nxt_r <= snd_nxt_r + 32'd1;
          PKT_DATA: snd_nxt_r <= snd_nxt_r + {16'd0, inflight_plen};
          default: ;
        endcase
      end

      // Issue delayed ACK after handshake
      if (need_ack_tx && !tx_pending && !tx_busy) begin
        tx_pending   <= 1'b1;
        pending_kind <= PKT_ACK;
        pending_plen <= 16'd0;
        need_ack_tx  <= 1'b0;
      end

      // Host connect
      if (connect_req && state_r == ST_CLOSED && !tx_pending && !tx_busy) begin
        snd_una_r    <= ISS;
        snd_nxt_r    <= ISS;
        tx_pending   <= 1'b1;
        pending_kind <= PKT_SYN;
        pending_plen <= 16'd0;
        state_r      <= ST_SYN_SENT;
      end

      // Host close
      if (close_req && state_r == ST_ESTABLISHED && !outstanding_r
          && !tx_pending && !tx_busy && !need_ack_tx) begin
        tx_pending   <= 1'b1;
        pending_kind <= PKT_FIN;
        pending_plen <= 16'd0;
        state_r      <= ST_FIN_WAIT_1;
      end

      // Order send
      if (order_send_req && order_send_ready && order_len != 16'd0) begin
        tx_pending        <= 1'b1;
        pending_kind      <= PKT_DATA;
        pending_plen      <= order_len;
        outstanding_r     <= 1'b1;
        outstanding_len_r <= order_len;
      end

      // Stub TIME_WAIT → CLOSED (no 2MSL timer in v1)
      if (state_r == ST_TIME_WAIT) begin
        state_r <= ST_CLOSED;
      end

      // RX segments
      if (seg_valid && !seg_csum_bad) begin
        // RST
        if (seg_flags & TCP_RST) begin
          state_r       <= ST_CLOSED;
          outstanding_r <= 1'b0;
          tx_pending    <= 1'b0;
          tx_busy       <= 1'b0;
          need_ack_tx   <= 1'b0;
        end else begin
          unique case (state_r)
            ST_SYN_SENT: begin
              // Expect SYN+ACK with ack = ISS+1
              if ((seg_flags & TCP_SYN) && (seg_flags & TCP_ACK)
                  && (seg_ack == ISS + 32'd1)) begin
                rcv_nxt_r   <= seg_seq + 32'd1;
                snd_una_r   <= ISS + 32'd1;
                need_ack_tx <= 1'b1;
                state_r     <= ST_ESTABLISHED;
              end
            end

            ST_ESTABLISHED: begin
              // Advance rcv_nxt for in-order payload / FIN (v1: require seq==rcv_nxt)
              if (seg_seq == rcv_nxt_r) begin
                if (seg_payload_len != 16'd0)
                  rcv_nxt_r <= rcv_nxt_r + {16'd0, seg_payload_len};
                if (seg_flags & TCP_FIN) begin
                  rcv_nxt_r   <= rcv_nxt_r + {16'd0, seg_payload_len} + 32'd1;
                  need_ack_tx <= 1'b1;
                end else if (seg_payload_len != 16'd0) begin
                  need_ack_tx <= 1'b1;
                end
              end
              // Track ACK of our data (one outstanding segment)
              if ((seg_flags & TCP_ACK) && outstanding_r) begin
                if (seg_ack == snd_una_r + {16'd0, outstanding_len_r}) begin
                  snd_una_r       <= seg_ack;
                  outstanding_r   <= 1'b0;
                  order_send_done <= 1'b1;
                end
              end
            end

            ST_FIN_WAIT_1: begin
              if ((seg_flags & TCP_ACK) && (seg_ack == snd_nxt_r)) begin
                snd_una_r <= seg_ack;
                if (seg_flags & TCP_FIN) begin
                  rcv_nxt_r   <= seg_seq + 32'd1;
                  need_ack_tx <= 1'b1;
                end
                state_r <= ST_TIME_WAIT;
              end else if ((seg_flags & TCP_FIN) && (seg_seq == rcv_nxt_r)) begin
                rcv_nxt_r   <= seg_seq + 32'd1;
                need_ack_tx <= 1'b1;
              end
            end

            default: ;
          endcase
        end
      end
    end
  end

endmodule
