// -----------------------------------------------------------------------------
// tcp_order_top.sv — Minimal 1-connection TCP client + order-send application
//
// Wire side: AXI-Stream 64-bit Ethernet frames
//   - First wire byte in tdata[7:0] (Xilinx-style)
//   - Assumed line rate clock domain ~156.25 MHz (10GbE) or any convenient sim clk
//
// Host side: connect/close + order byte buffer + send pulse
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tcp_order_top
  import tcp_pkg::*;
#(
  parameter int          MAX_PAYLOAD = 256,
  parameter logic [31:0] ISS         = 32'h1000_0000,
  parameter logic [15:0] RCV_WND     = 16'd65535
) (
  input  logic        clk,
  input  logic        rst_n,

  // Static endpoint config (stable while connected)
  input  logic [47:0] cfg_local_mac,
  input  logic [47:0] cfg_remote_mac,
  input  logic [31:0] cfg_local_ip,
  input  logic [31:0] cfg_remote_ip,
  input  logic [15:0] cfg_local_port,
  input  logic [15:0] cfg_remote_port,

  // Session control
  input  logic        connect_req,
  input  logic        close_req,
  output logic [3:0]  tcp_state,
  output logic        established,
  output logic        outstanding,
  output logic [31:0] dbg_snd_una,
  output logic [31:0] dbg_snd_nxt,
  output logic [31:0] dbg_rcv_nxt,

  // Order (发单) API
  input  logic        order_we,
  input  logic [15:0] order_addr,
  input  logic [7:0]  order_wdata,
  input  logic        order_len_we,
  input  logic [15:0] order_len_wdata,
  input  logic        order_clear,
  output logic [15:0] order_len,
  input  logic        order_send,
  output logic        order_send_ready,
  output logic        order_send_done,

  // Debug: RX parser events
  output logic        dbg_seg_valid,
  output logic        dbg_seg_csum_bad,

  // AXIS to wire (TX)
  output logic [63:0] m_axis_tdata,
  output logic [7:0]  m_axis_tkeep,
  output logic        m_axis_tvalid,
  output logic        m_axis_tlast,
  input  logic        m_axis_tready,

  // AXIS from wire (RX)
  input  logic [63:0] s_axis_tdata,
  input  logic [7:0]  s_axis_tkeep,
  input  logic        s_axis_tvalid,
  input  logic        s_axis_tlast,
  output logic        s_axis_tready
);

  // ----- Order buffer -----
  logic [15:0] pl_addr;
  logic [7:0]  pl_data;

  order_buffer #(
    .MAX_PAYLOAD(MAX_PAYLOAD)
  ) u_order (
    .clk            (clk),
    .rst_n          (rst_n),
    .order_we       (order_we),
    .order_addr     (order_addr),
    .order_wdata    (order_wdata),
    .order_len_we   (order_len_we),
    .order_len_wdata(order_len_wdata),
    .order_len      (order_len),
    .order_clear    (order_clear),
    .pl_addr        (pl_addr),
    .pl_data        (pl_data)
  );

  // ----- RX -----
  logic        seg_valid;
  logic        seg_csum_bad;
  logic [31:0] seg_seq, seg_ack;
  logic [7:0]  seg_flags;
  logic [15:0] seg_window, seg_payload_len, seg_tcp_len;

  assign dbg_seg_valid    = seg_valid;
  assign dbg_seg_csum_bad = seg_csum_bad;

  eth_ipv4_tcp_rx #(
    .MAX_FRAME(14 + 20 + 20 + MAX_PAYLOAD + 64)
  ) u_rx (
    .clk            (clk),
    .rst_n          (rst_n),
    .local_mac      (cfg_local_mac),
    .local_ip       (cfg_local_ip),
    .local_port     (cfg_local_port),
    .remote_ip      (cfg_remote_ip),
    .remote_port    (cfg_remote_port),
    .s_axis_tdata   (s_axis_tdata),
    .s_axis_tkeep   (s_axis_tkeep),
    .s_axis_tvalid  (s_axis_tvalid),
    .s_axis_tlast   (s_axis_tlast),
    .s_axis_tready  (s_axis_tready),
    .seg_valid      (seg_valid),
    .seg_csum_bad   (seg_csum_bad),
    .seg_seq        (seg_seq),
    .seg_ack        (seg_ack),
    .seg_flags      (seg_flags),
    .seg_window     (seg_window),
    .seg_payload_len(seg_payload_len),
    .seg_tcp_len    (seg_tcp_len)
  );

  // ----- TCP SM -----
  logic        tx_req_valid;
  logic        tx_req_ready;
  pkt_kind_e   tx_req_kind;
  logic [31:0] tx_req_seq, tx_req_ack;
  logic [15:0] tx_req_window, tx_req_payload_len;
  logic        tx_done_pulse;
  tcp_state_e  state_e;

  assign tcp_state = state_e;

  tcp_client_sm #(
    .ISS    (ISS),
    .RCV_WND(RCV_WND)
  ) u_sm (
    .clk               (clk),
    .rst_n             (rst_n),
    .connect_req       (connect_req),
    .close_req         (close_req),
    .seg_valid         (seg_valid),
    .seg_csum_bad      (seg_csum_bad),
    .seg_seq           (seg_seq),
    .seg_ack           (seg_ack),
    .seg_flags         (seg_flags),
    .seg_window        (seg_window),
    .seg_payload_len   (seg_payload_len),
    .order_send_req    (order_send),
    .order_len         (order_len),
    .order_send_ready  (order_send_ready),
    .order_send_done   (order_send_done),
    .tx_req_valid      (tx_req_valid),
    .tx_req_ready      (tx_req_ready),
    .tx_req_kind       (tx_req_kind),
    .tx_req_seq        (tx_req_seq),
    .tx_req_ack        (tx_req_ack),
    .tx_req_window     (tx_req_window),
    .tx_req_payload_len(tx_req_payload_len),
    .tx_done_pulse     (tx_done_pulse),
    .state             (state_e),
    .established       (established),
    .snd_una           (dbg_snd_una),
    .snd_nxt           (dbg_snd_nxt),
    .rcv_nxt           (dbg_rcv_nxt),
    .outstanding       (outstanding)
  );

  // ----- TX -----
  // Latch kind at accept so SM seq advance uses the emitted kind
  // (handled inside SM via pending_kind held until overwritten)

  tcp_frame_tx #(
    .MAX_PAYLOAD(MAX_PAYLOAD)
  ) u_tx (
    .clk               (clk),
    .rst_n             (rst_n),
    .local_mac         (cfg_local_mac),
    .remote_mac        (cfg_remote_mac),
    .local_ip          (cfg_local_ip),
    .remote_ip         (cfg_remote_ip),
    .local_port        (cfg_local_port),
    .remote_port       (cfg_remote_port),
    .req_valid         (tx_req_valid),
    .req_ready         (tx_req_ready),
    .req_kind          (tx_req_kind),
    .req_seq           (tx_req_seq),
    .req_ack           (tx_req_ack),
    .req_window        (tx_req_window),
    .req_payload_len   (tx_req_payload_len),
    .pl_addr           (pl_addr),
    .pl_data           (pl_data),
    .m_axis_tdata      (m_axis_tdata),
    .m_axis_tkeep      (m_axis_tkeep),
    .m_axis_tvalid     (m_axis_tvalid),
    .m_axis_tlast      (m_axis_tlast),
    .m_axis_tready     (m_axis_tready),
    .tx_done_pulse     (tx_done_pulse)
  );

endmodule
