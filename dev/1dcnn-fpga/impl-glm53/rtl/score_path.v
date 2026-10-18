// score_path — capture 10 AXIS beats INT16; TLAST on last; REG_SCORE snapshot
`timescale 1ns/1ps
module score_path (
  input  wire        clk,
  input  wire        rst_n,
  input  wire [15:0] s_axis_tdata,
  input  wire        s_axis_tvalid,
  output wire        s_axis_tready,
  input  wire        s_axis_tlast,
  output reg  [15:0] score_r [0:9],
  output reg         done_sticky,
  output reg         irq_pulse
);
  assign s_axis_tready = 1'b1;
  reg [3:0] idx;
  integer i;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      idx <= 0; done_sticky <= 0; irq_pulse <= 0;
      for (i=0;i<10;i=i+1) score_r[i] <= 16'd0;
    end else begin
      irq_pulse <= 1'b0;
      if (s_axis_tvalid) begin
        score_r[idx] <= s_axis_tdata;
        if (s_axis_tlast || idx == 4'd9) begin
          done_sticky <= 1'b1;
          irq_pulse   <= 1'b1;
          idx <= 4'd0;
        end else idx <= idx + 4'd1;
      end
    end
  end
endmodule
