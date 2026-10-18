// axi_ctrl — AXI4-Lite regfile matching include/regs.h / arch §5.3
`timescale 1ns/1ps
module axi_ctrl (
  input  wire        clk,
  input  wire        rst_n,
  // simplified lite ports (full AXI-Lite wrapper in BD)
  input  wire [7:0]  awaddr,
  input  wire        awvalid,
  output reg         awready,
  input  wire [31:0] wdata,
  input  wire        wvalid,
  output reg         wready,
  output reg  [1:0]  bresp,
  output reg         bvalid,
  input  wire        bready,
  input  wire [7:0]  araddr,
  input  wire        arvalid,
  output reg         arready,
  output reg  [31:0] rdata,
  output reg  [1:0]  rresp,
  output reg         rvalid,
  input  wire        rready,
  // sidebands
  input  wire        busy,
  input  wire        done_sticky,
  input  wire        err_sticky,
  input  wire        fifo_ovfl,
  input  wire        weight_ok,
  input  wire [31:0] cyc_cnt,
  input  wire [31:0] win_cnt,
  input  wire [7:0]  err_code,
  input  wire [15:0] score0, score1, score2, score3, score4,
  input  wire [15:0] score5, score6, score7, score8, score9,
  output reg         eng_en, capt_en, soft_rst, fir_bypass, irq_en,
  output reg  [31:0] win_len, win_hop,
  output reg         irq
);
  localparam ID_VAL = 32'h1DC0_0101; // doc 0x1DCN0101 → N=0
  // STATUS[5]=feat_hotswap=0 always
  wire [31:0] status = {26'd0, 1'b0, weight_ok, fifo_ovfl, err_sticky, done_sticky, busy};

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      awready<=0; wready<=0; bvalid<=0; bresp<=0;
      arready<=0; rvalid<=0; rresp<=0; rdata<=0;
      eng_en<=0; capt_en<=0; soft_rst<=0; fir_bypass<=0; irq_en<=0;
      win_len<=32'd2048; win_hop<=32'd2048; irq<=0;
    end else begin
      // minimal read of ID / STATUS / SCOREn
      if (arvalid && !rvalid) begin
        arready <= 1'b1;
        rvalid  <= 1'b1;
        case (araddr)
          8'h00: rdata <= ID_VAL;
          8'h08: rdata <= status;
          8'h80: rdata <= {16'd0, score0};
          8'h84: rdata <= {16'd0, score1};
          8'h88: rdata <= {16'd0, score2};
          8'h8C: rdata <= {16'd0, score3};
          8'h90: rdata <= {16'd0, score4};
          8'h94: rdata <= {16'd0, score5};
          8'h98: rdata <= {16'd0, score6};
          8'h9C: rdata <= {16'd0, score7};
          8'hA0: rdata <= {16'd0, score8};
          8'hA4: rdata <= {16'd0, score9};
          default: rdata <= 32'd0;
        endcase
      end else begin
        arready <= 1'b0;
        if (rvalid && rready) rvalid <= 1'b0;
      end
      irq <= irq_en & done_sticky;
    end
  end
endmodule
