//==============================================================================
// system_1dcnn_pl — top wrapper (V1)
// Declared top module name per HANDOFF / task requirement.
//==============================================================================
`timescale 1ns/1ps
module system_1dcnn_pl (
    input  wire        clk_pl,
    input  wire        rst_n,       // active-low
    input  wire        clk_adc,
    input  wire        rst_adc_n,
    // ADC SPI
    output wire        adc_cs_n,
    output wire        adc_sclk,
    output wire        adc_mosi,
    input  wire        adc_miso,
    input  wire        adc_busy,
    output wire        adc_convst,
    // AXI4-Lite
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
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
    output wire        irq
);
    wire eng_en, capt_en, soft_rst, fir_bypass, irq_en;
    wire [31:0] win_len, win_hop, weight_words;
    wire [1:0] fs_sel, ch_sel;
    wire weight_load_en, bank_sel, weight_data_we;
    wire [15:0] weight_data;
    wire busy = 1'b0;
    wire done_pulse, err_pulse = 1'b0, fifo_ovfl = 1'b0, weight_ok = 1'b0;
    wire [7:0] err_code_in = 8'd0;
    wire [31:0] cyc_cnt_in = 32'd0;
    wire [31:0] score_snap [0:9];
    wire fifo_wr_err, ovfl_sticky;
    wire [31:0] fifo_wdata;
    wire fifo_wen, fifo_full = 1'b0, fifo_almost_full = 1'b0;

    axi_ctrl u_axi (
        .clk_pl(clk_pl), .rst_n(rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .busy(busy), .done_pulse(done_pulse), .err_pulse(err_pulse),
        .fifo_ovfl(fifo_ovfl | ovfl_sticky), .weight_ok(weight_ok),
        .err_code_in(err_code_in), .cyc_cnt_in(cyc_cnt_in), .score_snap(score_snap),
        .eng_en(eng_en), .capt_en(capt_en), .soft_rst(soft_rst), .fir_bypass(fir_bypass),
        .irq_en(irq_en), .win_len(win_len), .win_hop(win_hop), .fs_sel(fs_sel), .ch_sel(ch_sel),
        .weight_load_en(weight_load_en), .bank_sel(bank_sel), .weight_words(weight_words),
        .weight_data(weight_data), .weight_data_we(weight_data_we), .irq(irq)
    );

    adc_frontend #(.PACK_CH(0)) u_adc (
        .clk_adc(clk_adc), .rst_adc_n(rst_adc_n), .clk_pl(clk_pl), .rst_n(rst_n),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk), .adc_mosi(adc_mosi),
        .adc_miso(adc_miso), .adc_busy(adc_busy), .adc_convst(adc_convst),
        .fs_sel(fs_sel), .ch_sel(ch_sel), .capt_en(capt_en),
        .fifo_wdata(fifo_wdata), .fifo_wen(fifo_wen),
        .fifo_full(fifo_full), .fifo_almost_full(fifo_almost_full),
        .m_axis_tdata(), .m_axis_tvalid(), .m_axis_tready(1'b1),
        .m_axis_tlast(), .m_axis_tuser(),
        .fifo_wr_err(fifo_wr_err), .ovfl_sticky(ovfl_sticky)
    );

    // Score path stub inputs (tied until HLS IP integrated)
    wire [15:0] score_tdata = 16'd0;
    wire score_tvalid = 1'b0;
    wire score_tlast = 1'b0;
    score_path u_score (
        .clk_pl(clk_pl), .rst_n(rst_n),
        .s_axis_tdata(score_tdata), .s_axis_tvalid(score_tvalid),
        .s_axis_tready(), .s_axis_tlast(score_tlast),
        .irq_en(irq_en), .score_regs(score_snap),
        .done_pulse(done_pulse), .irq_pulse()
    );
endmodule
