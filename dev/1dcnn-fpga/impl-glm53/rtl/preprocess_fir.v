// preprocess_fir — DC block + FIR; fir_bypass mux first (microarch §2)
`timescale 1ns/1ps
module preprocess_fir #(
  parameter FIR_TAPS   = 32,
  parameter COEF_W     = 16,
  parameter BYPASS_REG = 1
)(
  input  wire        clk,
  input  wire        rst_n,
  input  wire        bypass,
  input  wire [15:0] s_axis_tdata,
  input  wire        s_axis_tvalid,
  output wire        s_axis_tready,
  input  wire        s_axis_tlast,
  input  wire [23:0] s_axis_tuser,
  output reg  [15:0] m_axis_tdata,
  output reg         m_axis_tvalid,
  input  wire        m_axis_tready,
  output reg         m_axis_tlast,
  output reg  [23:0] m_axis_tuser
);
  assign s_axis_tready = bypass ? m_axis_tready : m_axis_tready; // V1: 1:1
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axis_tdata  <= 16'd0;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast  <= 1'b0;
      m_axis_tuser  <= 24'd0;
    end else if (bypass) begin
      if (BYPASS_REG) begin
        m_axis_tdata  <= s_axis_tdata;
        m_axis_tvalid <= s_axis_tvalid;
        m_axis_tlast  <= s_axis_tlast;
        m_axis_tuser  <= s_axis_tuser;
      end
    end else begin
      // simple pass-through placeholder (fixed-coef FIR to be filled)
      m_axis_tdata  <= s_axis_tdata;
      m_axis_tvalid <= s_axis_tvalid;
      m_axis_tlast  <= s_axis_tlast;
      m_axis_tuser  <= s_axis_tuser;
    end
  end
endmodule
