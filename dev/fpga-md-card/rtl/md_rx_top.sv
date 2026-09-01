// -----------------------------------------------------------------------------
// md_rx_top.sv — M0 stub: clock/reset + single udp_strip instance (M1)
// Full ingress/arb/decode wiring comes in later milestones.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module md_rx_top
  import md_pkg::*;
(
  input  logic        clk,
  input  logic        rst_n,

  input  logic [47:0] cfg_dst_mac,
  input  logic [31:0] cfg_dst_ip,
  input  logic [15:0] cfg_udp_dport,

  input  logic [63:0] s_axis_tdata,
  input  logic [7:0]  s_axis_tkeep,
  input  logic        s_axis_tvalid,
  input  logic        s_axis_tlast,
  output logic        s_axis_tready,
  input  eth_tuser_t  s_axis_tuser,

  output logic [63:0] m_axis_tdata,
  output logic [7:0]  m_axis_tkeep,
  output logic        m_axis_tvalid,
  output logic        m_axis_tlast,
  input  logic        m_axis_tready,
  output pay_tuser_t  m_axis_tuser,

  output logic [31:0] drop_not_udp,
  output logic [31:0] drop_opt,
  output logic [31:0] drop_filter,
  output logic [31:0] frames_ok
);

  udp_strip u_udp_strip (
    .clk           (clk),
    .rst_n         (rst_n),
    .cfg_dst_mac   (cfg_dst_mac),
    .cfg_dst_ip    (cfg_dst_ip),
    .cfg_udp_dport (cfg_udp_dport),
    .s_axis_tdata  (s_axis_tdata),
    .s_axis_tkeep  (s_axis_tkeep),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tlast  (s_axis_tlast),
    .s_axis_tready (s_axis_tready),
    .s_axis_tuser  (s_axis_tuser),
    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tkeep  (m_axis_tkeep),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tlast  (m_axis_tlast),
    .m_axis_tready (m_axis_tready),
    .m_axis_tuser  (m_axis_tuser),
    .drop_not_udp  (drop_not_udp),
    .drop_opt      (drop_opt),
    .drop_filter   (drop_filter),
    .frames_ok     (frames_ok)
  );

endmodule
