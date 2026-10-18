// weight_mem — single bank INT16 BRAM; hot-swap stub (feat_hotswap=0)
`timescale 1ns/1ps
module weight_mem #(
  parameter DEPTH = 11504
)(
  input  wire        clk,
  input  wire        rst_n,
  // load (AXI-Lite word path model)
  input  wire        wr_en,
  input  wire [15:0] wr_data,
  input  wire        soft_rst,
  input  wire        bank_sel,     // V1: must be 0
  output reg         weight_ok,
  output reg  [7:0]  err_code,
  // read to engine: 1-cycle sync BRAM
  input  wire [15:0] rd_addr,
  input  wire        rd_en,
  output reg  [15:0] rd_data
);
  reg [15:0] mem [0:DEPTH-1];
  reg [15:0] wr_ptr;
  integer i;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr    <= 16'd0;
      weight_ok <= 1'b0;
      err_code  <= 8'h00;
      rd_data   <= 16'd0;
    end else begin
      if (soft_rst) begin
        wr_ptr    <= 16'd0;
        weight_ok <= 1'b0;
      end
      if (bank_sel) err_code <= 8'h20; // hot-swap unimplemented
      if (wr_en) begin
        mem[wr_ptr] <= wr_data;
        wr_ptr <= wr_ptr + 16'd1;
        if (wr_ptr + 16'd1 >= DEPTH[15:0]) weight_ok <= 1'b1;
      end
      if (rd_en) rd_data <= mem[rd_addr];
    end
  end
endmodule
