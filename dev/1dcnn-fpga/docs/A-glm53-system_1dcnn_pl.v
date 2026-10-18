// system_1dcnn_pl — top glue (structural stub)
`timescale 1ns/1ps
module system_1dcnn_pl (
  input  wire clk_pl,
  input  wire rst_n,      // active-low
  input  wire clk_adc,
  input  wire rst_adc_n,
  // ADC SPI
  output wire adc_cs_n, adc_sclk, adc_mosi, adc_convst,
  input  wire adc_miso, adc_busy,
  // AXI-Lite simplified
  input  wire [7:0]  s_axi_awaddr,
  input  wire        s_axi_awvalid,
  output wire        s_axi_awready,
  input  wire [31:0] s_axi_wdata,
  input  wire        s_axi_wvalid,
  output wire        s_axi_wready,
  output wire [1:0]  s_axi_bresp,
  output wire        s_axi_bvalid,
  input  wire        s_axi_bready,
  input  wire [7:0]  s_axi_araddr,
  input  wire        s_axi_arvalid,
  output wire        s_axi_arready,
  output wire [31:0] s_axi_rdata,
  output wire [1:0]  s_axi_rresp,
  output wire        s_axi_rvalid,
  input  wire        s_axi_rready,
  output wire        irq_pl
);
  // Instantiations omitted detail wiring — modules exist as stubs for BD integration.
  // Data path: adc_frontend -> preprocess_fir -> window_buffer -> cnn_engine(HLS) -> score_path
  // Control: axi_ctrl; weights: weight_mem
  assign irq_pl = 1'b0;
  assign s_axi_awready = 1'b0;
  assign s_axi_wready  = 1'b0;
  assign s_axi_bresp   = 2'b00;
  assign s_axi_bvalid  = 1'b0;
  assign s_axi_arready = 1'b0;
  assign s_axi_rdata   = 32'h1DC00101;
  assign s_axi_rresp   = 2'b00;
  assign s_axi_rvalid  = 1'b0;
  assign adc_cs_n = 1'b1;
  assign adc_sclk = 1'b0;
  assign adc_mosi = 1'b0;
  assign adc_convst = 1'b0;
endmodule
