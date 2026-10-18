`default_nettype none
`timescale 1ns/1ps
//==============================================================================
// system_1dcnn_pl — V1 PL top (Phase1 ports clk_pl/rst_n map to sys_*)
//==============================================================================
module system_1dcnn_pl (
    input  wire        clk_pl,
    input  wire        rst_n,
    input  wire        clk_adc,
    input  wire        rst_adc_n,
    output wire        adc_cs_n,
    output wire        adc_sclk,
    output wire        adc_mosi,
    input  wire        adc_miso,
    input  wire        adc_busy,
    output wire        adc_convst,
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
    wire sys_clk = clk_pl;
    wire sys_rst_n = rst_n;

    wire eng_en, capt_en, soft_rst, fir_bypass, irq_en;
    wire [31:0] win_len, win_hop, weight_words;
    wire [1:0] fs_sel, ch_sel;
    wire weight_load_en, bank_sel, weight_data_we;
    wire [15:0] weight_data;
    wire busy, done_pulse, err_pulse, fifo_ovfl, weight_ok;
    wire [7:0] err_code_in;
    wire [31:0] cyc_cnt_in;
    wire [31:0] score_snap [0:9];

    wire signed [15:0] adc_tdata;
    wire adc_tvalid, adc_tready, adc_tlast;
    wire [23:0] adc_tuser;
    wire fir_tready;
    wire signed [15:0] fir_tdata;
    wire fir_tvalid, fir_tlast;
    wire [23:0] fir_tuser;
    wire signed [15:0] win_tdata;
    wire win_tvalid, win_tready, win_tlast;
    wire [15:0] win_tuser;
    wire signed [15:0] score_tdata;
    wire score_tvalid, score_tready, score_tlast;
    wire w_rd_en;
    wire [13:0] w_rd_addr;
    wire signed [15:0] w_rd_data;
    wire err_weight, err_hotswap;
    wire ovfl_sticky, fifo_wr_err;
    wire param_err, win_ovfl;
    wire irq_pulse;

    assign err_pulse = err_weight | err_hotswap | param_err | win_ovfl | ovfl_sticky;
    assign err_code_in = ovfl_sticky ? 8'h30 :
                         err_hotswap ? 8'h20 :
                         err_weight  ? 8'h10 :
                         win_ovfl    ? 8'h02 :
                         param_err   ? 8'h01 : 8'h00;
    assign fifo_ovfl = ovfl_sticky;
    assign irq = irq_pulse;

    axi_ctrl u_axi (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready), .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready), .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .busy(busy), .done_pulse(done_pulse), .err_pulse(err_pulse),
        .fifo_ovfl(fifo_ovfl), .weight_ok(weight_ok),
        .err_code_in(err_code_in), .cyc_cnt_in(cyc_cnt_in), .score_snap(score_snap),
        .eng_en(eng_en), .capt_en(capt_en), .soft_rst(soft_rst), .fir_bypass(fir_bypass),
        .irq_en(irq_en), .win_len(win_len), .win_hop(win_hop), .fs_sel(fs_sel), .ch_sel(ch_sel),
        .weight_load_en(weight_load_en), .bank_sel(bank_sel), .weight_words(weight_words),
        .weight_data(weight_data), .weight_data_we(weight_data_we), .irq()
    );

    adc_frontend #(.PACK_CH(0)) u_adc (
        .clk_adc(clk_adc), .rst_adc_n(rst_adc_n),
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .adc_cs_n(adc_cs_n), .adc_sclk(adc_sclk), .adc_mosi(adc_mosi),
        .adc_miso(adc_miso), .adc_busy(adc_busy), .adc_convst(adc_convst),
        .i_fs_sel(fs_sel), .i_ch_sel(ch_sel), .i_capt_en(capt_en),
        .m_axis_tdata(adc_tdata), .m_axis_tvalid(adc_tvalid), .m_axis_tready(adc_tready),
        .m_axis_tlast(adc_tlast), .m_axis_tuser(adc_tuser),
        .o_fifo_wr_err(fifo_wr_err), .o_ovfl_sticky(ovfl_sticky)
    );

    preprocess_fir u_fir (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .i_bypass(fir_bypass),
        .s_axis_tdata(adc_tdata), .s_axis_tvalid(adc_tvalid), .s_axis_tready(adc_tready),
        .s_axis_tlast(adc_tlast), .s_axis_tuser(adc_tuser),
        .m_axis_tdata(fir_tdata), .m_axis_tvalid(fir_tvalid), .m_axis_tready(fir_tready),
        .m_axis_tlast(fir_tlast), .m_axis_tuser(fir_tuser)
    );

    window_buffer u_win (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .i_win_len(win_len), .i_win_hop(win_hop), .i_capt_en(capt_en),
        .o_param_err(param_err), .o_ovfl_err(win_ovfl),
        .s_axis_tdata(fir_tdata), .s_axis_tvalid(fir_tvalid), .s_axis_tready(fir_tready),
        .m_axis_tdata(win_tdata), .m_axis_tvalid(win_tvalid), .m_axis_tready(win_tready),
        .m_axis_tlast(win_tlast), .m_axis_tuser(win_tuser)
    );

    weight_mem u_wmem (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .i_load_en(weight_load_en), .i_wr_en(weight_data_we),
        .i_wr_data($signed(weight_data)), .i_soft_rst(soft_rst), .i_bank_sel(bank_sel),
        .i_rd_en(w_rd_en), .i_rd_addr(w_rd_addr), .o_rd_data(w_rd_data),
        .o_weight_ok(weight_ok), .o_err_hotswap(err_hotswap)
    );

    cnn_engine u_cnn (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .i_eng_en(eng_en), .i_weight_ok(weight_ok),
        .o_busy(busy), .o_cyc_cnt(cyc_cnt_in), .o_err_weight(err_weight),
        .s_axis_tdata(win_tdata), .s_axis_tvalid(win_tvalid), .s_axis_tready(win_tready),
        .s_axis_tlast(win_tlast),
        .m_axis_tdata(score_tdata), .m_axis_tvalid(score_tvalid), .m_axis_tready(score_tready),
        .m_axis_tlast(score_tlast),
        .o_w_rd_en(w_rd_en), .o_w_rd_addr(w_rd_addr), .i_w_rd_data(w_rd_data)
    );

    score_path u_score (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .s_axis_tdata(score_tdata), .s_axis_tvalid(score_tvalid),
        .s_axis_tready(score_tready), .s_axis_tlast(score_tlast),
        .i_irq_en(irq_en), .o_score_regs(score_snap),
        .o_done_pulse(done_pulse), .o_irq_pulse(irq_pulse)
    );
endmodule
`default_nettype wire
