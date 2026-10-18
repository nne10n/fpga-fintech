`default_nettype none
`timescale 1ns/1ps
`include "cnn_params.svh"
// TB wrap: weight_mem + cnn_engine (synthesizable DUT only)
module tb_cnn_engine_wrap (
    input  wire sys_clk,
    input  wire sys_rst_n,
    input  wire load_en,
    input  wire wr_en,
    input  wire signed [15:0] wr_data,
    output wire weight_ok,
    input  wire eng_en,
    input  wire signed [15:0] s_tdata,
    input  wire s_tvalid,
    output wire s_tready,
    input  wire s_tlast,
    output wire signed [15:0] m_tdata,
    output wire m_tvalid,
    input  wire m_tready,
    output wire m_tlast,
    output wire [31:0] cyc_cnt,
    output wire busy,
    // debug peeks
    output wire signed [15:0] dbg_feat0_0,
    output wire signed [15:0] dbg_feat0_1,
    output wire signed [15:0] dbg_feat1_0,
    output wire signed [15:0] dbg_score0,
    output wire [3:0] dbg_cs,
    output wire [4:0] dbg_ms
);
    logic w_rd_en;
    logic [13:0] w_rd_addr;
    logic signed [15:0] w_rd_data;
    logic err_hs, err_w;

    weight_mem u_w (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .i_load_en(load_en), .i_wr_en(wr_en), .i_wr_data(wr_data),
        .i_soft_rst(1'b0), .i_bank_sel(1'b0),
        .i_rd_en(w_rd_en), .i_rd_addr(w_rd_addr), .o_rd_data(w_rd_data),
        .o_weight_ok(weight_ok), .o_err_hotswap(err_hs)
    );
    cnn_engine u_c (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .i_eng_en(eng_en), .i_weight_ok(weight_ok),
        .o_busy(busy), .o_cyc_cnt(cyc_cnt), .o_err_weight(err_w),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .s_axis_tlast(s_tlast),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tlast(m_tlast),
        .o_w_rd_en(w_rd_en), .o_w_rd_addr(w_rd_addr), .i_w_rd_data(w_rd_data)
    );
    assign dbg_feat0_0 = u_c.feat0[0];
    assign dbg_feat0_1 = u_c.feat0[1];
    assign dbg_feat1_0 = u_c.feat1[0];
    assign dbg_score0  = u_c.score_ff[0];
    assign dbg_cs = u_c.cs_state;
    assign dbg_ms = u_c.cs_mstep;
endmodule
