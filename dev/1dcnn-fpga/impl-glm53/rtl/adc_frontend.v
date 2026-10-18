// adc_frontend — AD7606 SPI stub + async FIFO model (V1)
// CDC: clk_adc -> clk_pl via async FIFO; PACK_CH=0 default
`timescale 1ns/1ps
module adc_frontend #(
  parameter ADC_IF_TYPE = 0,
  parameter FIFO_DEPTH  = 256,
  parameter N_CH        = 2,
  parameter PACK_CH     = 0
)(
  input  wire        clk_adc,
  input  wire        rst_adc_n,
  input  wire        clk_pl,
  input  wire        rst_n,
  // SPI phy stub
  output reg         adc_cs_n,
  output reg         adc_sclk,
  output reg         adc_mosi,
  input  wire        adc_miso,
  input  wire        adc_busy,
  output reg         adc_convst,
  // AXIS master (clk_pl)
  output reg  [15:0] m_axis_tdata,
  output reg         m_axis_tvalid,
  input  wire        m_axis_tready,
  output reg         m_axis_tlast,   // always 0: no window TLAST
  output reg  [23:0] m_axis_tuser,
  output reg         fifo_wr_err
);
  // Behavioral stub: idle AXIS after reset
  always @(posedge clk_pl or negedge rst_n) begin
    if (!rst_n) begin
      m_axis_tdata  <= 16'd0;
      m_axis_tvalid <= 1'b0;
      m_axis_tlast  <= 1'b0;
      m_axis_tuser  <= 24'd0;
      fifo_wr_err   <= 1'b0;
    end
  end
  always @(posedge clk_adc or negedge rst_adc_n) begin
    if (!rst_adc_n) begin
      adc_cs_n   <= 1'b1;
      adc_sclk   <= 1'b0;
      adc_mosi   <= 1'b0;
      adc_convst <= 1'b0;
    end
  end
endmodule
