// window_buffer — ping-pong, V1 HOP=LEN (no overlap)
`timescale 1ns/1ps
module window_buffer #(
  parameter DEPTH  = 4096,
  parameter N_BANK = 2
)(
  input  wire        clk,
  input  wire        rst_n,
  input  wire [31:0] win_len,
  input  wire [31:0] win_hop,
  input  wire [15:0] s_axis_tdata,
  input  wire        s_axis_tvalid,
  output wire        s_axis_tready,
  output reg  [15:0] m_axis_tdata,
  output reg         m_axis_tvalid,
  input  wire        m_axis_tready,
  output reg         m_axis_tlast,
  output reg  [23:0] m_axis_tuser,
  output reg  [7:0]  err_code
);
  // Behavioral skeleton: param check for illegal hop
  assign s_axis_tready = 1'b1;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axis_tdata  <= 16'd0;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast  <= 1'b0;
      m_axis_tuser  <= 24'd0;
      err_code      <= 8'h00;
    end else begin
      if (win_hop == 0 || win_hop > win_len) err_code <= 8'h01;
    end
  end
endmodule
