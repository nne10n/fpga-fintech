// -----------------------------------------------------------------------------
// eth_ipv4_tcp_rx.sv — Store-and-forward Ethernet/IPv4/TCP RX for ONE flow
// AXIS-64: first wire byte in tdata[7:0]. Filters by MAC + 5-tuple, verifies
// IPv4 and TCP (pseudo-header) checksums, pulses seg_valid / seg_csum_bad.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module eth_ipv4_tcp_rx
  import tcp_pkg::*;
#(
  parameter int MAX_FRAME = 1536
) (
  input  logic        clk,
  input  logic        rst_n,

  input  logic [47:0] local_mac,
  input  logic [31:0] local_ip,
  input  logic [15:0] local_port,
  input  logic [31:0] remote_ip,
  input  logic [15:0] remote_port,

  input  logic [63:0] s_axis_tdata,
  input  logic [7:0]  s_axis_tkeep,
  input  logic        s_axis_tvalid,
  input  logic        s_axis_tlast,
  output logic        s_axis_tready,

  output logic        seg_valid,
  output logic        seg_csum_bad,
  output logic [31:0] seg_seq,
  output logic [31:0] seg_ack,
  output logic [7:0]  seg_flags,
  output logic [15:0] seg_window,
  output logic [15:0] seg_payload_len,
  output logic [15:0] seg_tcp_len
);

  assign s_axis_tready = 1'b1;

  logic [7:0]  mem [0:MAX_FRAME-1];
  logic [15:0] wr_ptr;
  logic        collecting;
  logic        parse_pulse;

  logic [15:0] frame_len_r;

  integer i;

  // Capture frame bytes
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr      <= '0;
      collecting  <= 1'b0;
      parse_pulse <= 1'b0;
      frame_len_r <= '0;
    end else begin
      parse_pulse <= 1'b0;
      if (s_axis_tvalid && s_axis_tready) begin
        if (!collecting) begin
          collecting <= 1'b1;
          wr_ptr     <= '0;
        end
        for (i = 0; i < 8; i++) begin
          if (s_axis_tkeep[i]) begin
            automatic logic [15:0] idx = (collecting ? wr_ptr : 16'd0) + i[15:0];
            // Count keeps properly relative to current wr_ptr at beat start
          end
        end
        // Write using running offset within beat
        begin
          automatic logic [15:0] base = collecting ? wr_ptr : 16'd0;
          automatic logic [15:0] k = 16'd0;
          for (i = 0; i < 8; i++) begin
            if (s_axis_tkeep[i] && (base + k) < MAX_FRAME) begin
              mem[base + k] <= s_axis_tdata[i*8 +: 8];
              k = k + 16'd1;
            end
          end
          wr_ptr <= base + k;
          if (s_axis_tlast) begin
            collecting  <= 1'b0;
            frame_len_r <= base + k;
            parse_pulse <= 1'b1;
          end
        end
      end
    end
  end

  // Combinational parse helpers on buffered frame (registered outputs)
  function automatic logic [15:0] be16(input logic [7:0] hi, input logic [7:0] lo);
    be16 = {hi, lo};
  endfunction

  function automatic logic [31:0] be32(
      input logic [7:0] b0, input logic [7:0] b1,
      input logic [7:0] b2, input logic [7:0] b3
  );
    be32 = {b0, b1, b2, b3};
  endfunction

  // Ones' complement sum over a byte range [start, start+len), optionally
  // skipping checksum field at skip_off (2 bytes) relative to start when skip_en.
  function automatic logic [31:0] sum_bytes(
      input int start_off,
      input int len,
      input int skip_off,
      input bit skip_en
  );
    logic [31:0] acc;
    int off;
    acc = '0;
    for (off = 0; off < len; off++) begin
      if (skip_en && (off == skip_off || off == skip_off + 1)) begin
        // contribute zero
      end else if ((start_off + off) < MAX_FRAME) begin
        acc = acc_add8(acc, mem[start_off + off], ~off[0]);
      end
    end
    sum_bytes = acc;
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      seg_valid       <= 1'b0;
      seg_csum_bad    <= 1'b0;
      seg_seq         <= '0;
      seg_ack         <= '0;
      seg_flags       <= '0;
      seg_window      <= '0;
      seg_payload_len <= '0;
      seg_tcp_len     <= '0;
    end else begin
      seg_valid    <= 1'b0;
      seg_csum_bad <= 1'b0;

      if (parse_pulse && frame_len_r >= 16'd54) begin
        automatic logic [47:0] dst_mac;
        automatic logic [15:0] ethertype;
        automatic logic [7:0]  ihl;
        automatic logic [15:0] ip_total;
        automatic logic [7:0]  proto;
        automatic logic [15:0] ip_csum_field;
        automatic logic [31:0] src_ip, dst_ip;
        automatic logic [15:0] ip_hdr_len;
        automatic int          ip_start;
        automatic int          tcp_start;
        automatic logic [15:0] tcp_len;
        automatic logic [7:0]  data_off;
        automatic logic [15:0] tcp_hdr_len;
        automatic logic [15:0] plen;
        automatic logic [15:0] sport, dport;
        automatic logic [31:0] seq, ack;
        automatic logic [7:0]  flags;
        automatic logic [15:0] window;
        automatic logic [15:0] tcp_csum_field;
        automatic logic [31:0] ip_acc, tcp_acc;
        automatic logic [15:0] ip_calc, tcp_calc;
        automatic logic        tuple_ok;
        automatic logic        csum_ok;

        dst_mac    = {mem[0], mem[1], mem[2], mem[3], mem[4], mem[5]};
        ethertype  = be16(mem[12], mem[13]);
        ihl        = mem[14][3:0];
        ip_total   = be16(mem[16], mem[17]);
        proto      = mem[23];
        ip_csum_field = be16(mem[24], mem[25]);
        src_ip     = be32(mem[26], mem[27], mem[28], mem[29]);
        dst_ip     = be32(mem[30], mem[31], mem[32], mem[33]);
        ip_hdr_len = {10'd0, ihl, 2'b00};
        ip_start   = 14;
        tcp_start  = 14 + ip_hdr_len;
        tcp_len    = ip_total - ip_hdr_len;

        sport = be16(mem[tcp_start+0], mem[tcp_start+1]);
        dport = be16(mem[tcp_start+2], mem[tcp_start+3]);
        seq   = be32(mem[tcp_start+4], mem[tcp_start+5], mem[tcp_start+6], mem[tcp_start+7]);
        ack   = be32(mem[tcp_start+8], mem[tcp_start+9], mem[tcp_start+10], mem[tcp_start+11]);
        data_off = mem[tcp_start+12][7:4];
        flags    = mem[tcp_start+13];
        window   = be16(mem[tcp_start+14], mem[tcp_start+15]);
        tcp_csum_field = be16(mem[tcp_start+16], mem[tcp_start+17]);
        tcp_hdr_len = {10'd0, data_off, 2'b00};
        plen = (tcp_len >= tcp_hdr_len) ? (tcp_len - tcp_hdr_len) : 16'd0;

        ip_acc  = sum_bytes(ip_start, ip_hdr_len, 10, 1'b1);
        ip_calc = finalize_csum(ip_acc);

        tcp_acc = sum_bytes(tcp_start, tcp_len, 16, 1'b1);
        tcp_acc = acc_add16(tcp_acc, src_ip[31:16]);
        tcp_acc = acc_add16(tcp_acc, src_ip[15:0]);
        tcp_acc = acc_add16(tcp_acc, dst_ip[31:16]);
        tcp_acc = acc_add16(tcp_acc, dst_ip[15:0]);
        tcp_acc = acc_add16(tcp_acc, {8'd0, IP_PROTO_TCP});
        tcp_acc = acc_add16(tcp_acc, tcp_len);
        tcp_calc = finalize_csum(tcp_acc);

        tuple_ok = (dst_mac == local_mac)
                && (ethertype == ETHERTYPE_IPV4)
                && (proto == IP_PROTO_TCP)
                && (ihl >= 4'd5)
                && (data_off >= 4'd5)
                && (dst_ip == local_ip)
                && (src_ip == remote_ip)
                && (dport == local_port)
                && (sport == remote_port)
                && (ip_total >= (ip_hdr_len + 16'd20))
                && (frame_len_r >= (16'd14 + ip_total));

        csum_ok = (ip_calc == ip_csum_field) && (tcp_calc == tcp_csum_field);

        if (tuple_ok) begin
          seg_valid       <= 1'b1;
          seg_csum_bad    <= ~csum_ok;
          seg_seq         <= seq;
          seg_ack         <= ack;
          seg_flags       <= flags;
          seg_window      <= window;
          seg_payload_len <= plen;
          seg_tcp_len     <= tcp_len;
        end
      end
    end
  end

endmodule
