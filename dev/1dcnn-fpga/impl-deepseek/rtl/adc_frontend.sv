`default_nettype none
`timescale 1ns/1ps
//==============================================================================
// adc_frontend — AD7606-class SPI capture + AXIS (PACK_CH=0)
// Domains: clk_adc/rst_adc_n (PHY), sys_clk/sys_rst_n (AXIS via simple sync FIFO)
//==============================================================================
module adc_frontend #(
    parameter int FIFO_DEPTH = 256,
    parameter int PACK_CH    = 0
) (
    input  wire        clk_adc,
    input  wire        rst_adc_n,
    input  wire        sys_clk,
    input  wire        sys_rst_n,
    output logic       adc_cs_n,
    output logic       adc_sclk,
    output logic       adc_mosi,
    input  wire        adc_miso,
    input  wire        adc_busy,
    output logic       adc_convst,
    input  wire [1:0]  i_fs_sel,
    input  wire [1:0]  i_ch_sel,
    input  wire        i_capt_en,
    output logic signed [15:0] m_axis_tdata,
    output logic               m_axis_tvalid,
    input  wire                m_axis_tready,
    output logic               m_axis_tlast,
    output logic [23:0]        m_axis_tuser,
    output logic               o_fifo_wr_err,
    output logic               o_ovfl_sticky
);
    typedef enum logic [2:0] {
        ST_IDLE=3'd0, ST_WAIT_BUSY=3'd1, ST_READ_CH=3'd2,
        ST_WRITE_FIFO=3'd3, ST_ERROR=3'd4
    } state_t;
    state_t cs_adc, ns_adc;

    logic [15:0] ch0_ff, ch1_ff, shift_ff;
    logic [4:0]  bit_ff;
    logic [15:0] div_ff, div_cnt_ff;
    logic        tick;
    logic [15:0] fifo_mem [0:FIFO_DEPTH-1];
    logic [$clog2(FIFO_DEPTH):0] wr_ptr_gray, rd_ptr_gray;
    // simplified same-clock path for V1 sim: also accept clk_adc==sys_clk
    logic [$clog2(FIFO_DEPTH)-1:0] wr_ff, rd_ff;
    logic [$clog2(FIFO_DEPTH):0]   lvl_ff;
    logic        wr_pulse;
    logic [15:0] wr_data;

    always_ff @(posedge clk_adc or negedge rst_adc_n) begin
        if (!rst_adc_n) cs_adc <= ST_IDLE;
        else cs_adc <= ns_adc;
    end

    always_comb begin
        ns_adc = cs_adc;
        case (cs_adc)
            ST_IDLE: if (i_capt_en && tick) ns_adc = ST_WAIT_BUSY;
            ST_WAIT_BUSY: if (!adc_busy) ns_adc = ST_READ_CH;
            ST_READ_CH: if (bit_ff == 5'd31) ns_adc = ST_WRITE_FIFO;
            ST_WRITE_FIFO: ns_adc = ST_IDLE;
            ST_ERROR: ns_adc = ST_ERROR;
            default: ns_adc = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk_adc or negedge rst_adc_n) begin
        if (!rst_adc_n) begin
            adc_cs_n <= 1'b1; adc_sclk <= 1'b0; adc_mosi <= 1'b0; adc_convst <= 1'b0;
            bit_ff <= 5'd0; shift_ff <= 16'd0; ch0_ff <= 16'd0; ch1_ff <= 16'd0;
            div_cnt_ff <= 16'd0; tick <= 1'b0; wr_pulse <= 1'b0; wr_data <= 16'd0;
            o_fifo_wr_err <= 1'b0; o_ovfl_sticky <= 1'b0;
            div_ff <= 16'd16;
        end else begin
            wr_pulse <= 1'b0;
            tick <= 1'b0;
            unique case (i_fs_sel)
                2'd0: div_ff <= 16'd32;
                2'd1: div_ff <= 16'd16;
                2'd2: div_ff <= 16'd8;
                default: div_ff <= 16'd4;
            endcase
            if (div_cnt_ff >= div_ff) begin
                div_cnt_ff <= 16'd0;
                tick <= 1'b1;
            end else div_cnt_ff <= div_cnt_ff + 16'd1;

            case (cs_adc)
                ST_IDLE: begin
                    adc_cs_n <= 1'b1;
                    if (i_capt_en && tick) adc_convst <= 1'b1;
                    else adc_convst <= 1'b0;
                end
                ST_WAIT_BUSY: begin
                    adc_convst <= 1'b0;
                    bit_ff <= 5'd0;
                end
                ST_READ_CH: begin
                    adc_cs_n <= 1'b0;
                    adc_sclk <= ~adc_sclk;
                    if (adc_sclk) begin
                        shift_ff <= {shift_ff[14:0], adc_miso};
                        bit_ff <= bit_ff + 5'd1;
                        if (bit_ff == 5'd15) ch0_ff <= {shift_ff[14:0], adc_miso};
                        if (bit_ff == 5'd31) ch1_ff <= {shift_ff[14:0], adc_miso};
                    end
                end
                ST_WRITE_FIFO: begin
                    adc_cs_n <= 1'b1;
                    wr_pulse <= 1'b1;
                    wr_data <= (i_ch_sel == 2'd1) ? ch1_ff : ch0_ff;
                    if (lvl_ff >= FIFO_DEPTH[$clog2(FIFO_DEPTH):0]) begin
                        o_ovfl_sticky <= 1'b1;
                        o_fifo_wr_err <= 1'b1;
                    end
                end
                default: ;
            endcase
        end
    end

    // sync FIFO (assume clk_adc related / same for V1 glue; production: XPM AFIFO)
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wr_ff <= '0; rd_ff <= '0; lvl_ff <= '0;
            m_axis_tdata <= 16'sd0; m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0; m_axis_tuser <= 24'd0;
        end else begin
            if (wr_pulse && lvl_ff != FIFO_DEPTH[$clog2(FIFO_DEPTH):0]) begin
                fifo_mem[wr_ff] <= wr_data;
                wr_ff <= wr_ff + 1'b1;
                lvl_ff <= lvl_ff + 1'b1;
            end
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
                if (lvl_ff != 0) lvl_ff <= lvl_ff - 1'b1;
                rd_ff <= rd_ff + 1'b1;
            end else if (!m_axis_tvalid && lvl_ff != 0) begin
                m_axis_tdata <= fifo_mem[rd_ff];
                m_axis_tvalid <= 1'b1;
                m_axis_tlast <= 1'b0;
                m_axis_tuser <= {16'd0, 6'd0, i_ch_sel, 4'd0}; // ch_id in [7:0] area
                m_axis_tuser <= {16'd0, i_ch_sel};
            end
        end
    end
endmodule
`default_nettype wire
