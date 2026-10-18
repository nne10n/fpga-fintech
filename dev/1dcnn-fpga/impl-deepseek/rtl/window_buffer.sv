`default_nettype none
`timescale 1ns/1ps
//==============================================================================
// window_buffer — dual-bank window cutter, V1 hop=len (no overlap)
//==============================================================================
module window_buffer #(
    parameter int DEPTH = 4096
) (
    input  wire                sys_clk,
    input  wire                sys_rst_n,
    input  wire [31:0]         i_win_len,
    input  wire [31:0]         i_win_hop,
    input  wire                i_capt_en,
    output logic               o_param_err,
    output logic               o_ovfl_err,
    input  wire signed [15:0]  s_axis_tdata,
    input  wire                s_axis_tvalid,
    output logic               s_axis_tready,
    output logic signed [15:0] m_axis_tdata,
    output logic               m_axis_tvalid,
    input  wire                m_axis_tready,
    output logic               m_axis_tlast,
    output logic [15:0]        m_axis_tuser
);
    typedef enum logic [2:0] {
        ST_FILL0 = 3'd0,
        ST_DRAIN0_FILL1 = 3'd1,
        ST_DRAIN1_FILL0 = 3'd2,
        ST_ERROR = 3'd3
    } state_t;

    state_t cs_state, ns_state;
    logic signed [15:0] bank0 [0:DEPTH-1];
    logic signed [15:0] bank1 [0:DEPTH-1];
    logic [12:0] wr0_ff, wr1_ff, rd_ff;
    logic [15:0] win_seq_ff;
    logic [31:0] len_ff, hop_ff;

    wire s_fire = s_axis_tvalid && s_axis_tready;
    wire m_fire = m_axis_tvalid && m_axis_tready;
    wire len_ok = (i_win_len == 32'd1024) || (i_win_len == 32'd2048) || (i_win_len == 32'd4096);
    wire hop_ok = (i_win_hop >= 32'd1) && (i_win_hop <= i_win_len);

    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) cs_state <= ST_FILL0;
        else cs_state <= ns_state;
    end

    always_comb begin
        ns_state = cs_state;
        case (cs_state)
            ST_FILL0: if (wr0_ff == len_ff[12:0] - 13'd1 && s_fire) ns_state = ST_DRAIN0_FILL1;
            ST_DRAIN0_FILL1: begin
                if (o_ovfl_err) ns_state = ST_ERROR;
                else if (rd_ff == len_ff[12:0] - 13'd1 && m_fire && wr1_ff == len_ff[12:0])
                    ns_state = ST_DRAIN1_FILL0;
            end
            ST_DRAIN1_FILL0: begin
                if (o_ovfl_err) ns_state = ST_ERROR;
                else if (rd_ff == len_ff[12:0] - 13'd1 && m_fire && wr0_ff == len_ff[12:0])
                    ns_state = ST_DRAIN0_FILL1;
            end
            ST_ERROR: ns_state = ST_ERROR;
            default: ns_state = ST_FILL0;
        endcase
    end

    assign s_axis_tready = i_capt_en && !o_param_err && (cs_state != ST_ERROR) && (
        (cs_state == ST_FILL0) ||
        (cs_state == ST_DRAIN0_FILL1 && wr1_ff < len_ff[12:0]) ||
        (cs_state == ST_DRAIN1_FILL0 && wr0_ff < len_ff[12:0])
    );

    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wr0_ff <= 13'd0; wr1_ff <= 13'd0; rd_ff <= 13'd0;
            win_seq_ff <= 16'd0;
            len_ff <= 32'd2048; hop_ff <= 32'd2048;
            o_param_err <= 1'b0; o_ovfl_err <= 1'b0;
            m_axis_tdata <= 16'sd0; m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0; m_axis_tuser <= 16'd0;
        end else begin
            if (!len_ok || !hop_ok) o_param_err <= 1'b1;
            else begin
                o_param_err <= 1'b0;
                len_ff <= i_win_len;
                hop_ff <= i_win_hop;
            end

            // writes
            if (s_fire) begin
                if (cs_state == ST_FILL0 || cs_state == ST_DRAIN1_FILL0) begin
                    bank0[wr0_ff] <= s_axis_tdata;
                    wr0_ff <= wr0_ff + 13'd1;
                end else if (cs_state == ST_DRAIN0_FILL1) begin
                    bank1[wr1_ff] <= s_axis_tdata;
                    wr1_ff <= wr1_ff + 13'd1;
                end
            end

            // drain
            if (cs_state == ST_DRAIN0_FILL1) begin
                m_axis_tvalid <= 1'b1;
                m_axis_tdata <= bank0[rd_ff];
                m_axis_tlast <= (rd_ff == len_ff[12:0] - 13'd1);
                m_axis_tuser <= win_seq_ff;
                if (m_fire) begin
                    if (rd_ff == len_ff[12:0] - 13'd1) begin
                        rd_ff <= 13'd0;
                        wr0_ff <= 13'd0;
                        win_seq_ff <= win_seq_ff + 16'd1;
                        m_axis_tvalid <= 1'b0;
                    end else rd_ff <= rd_ff + 13'd1;
                end
                // ovfl: both full and not drained
                if (wr1_ff == len_ff[12:0] && rd_ff < len_ff[12:0] && !m_axis_tready && s_axis_tvalid)
                    o_ovfl_err <= 1'b1;
            end else if (cs_state == ST_DRAIN1_FILL0) begin
                m_axis_tvalid <= 1'b1;
                m_axis_tdata <= bank1[rd_ff];
                m_axis_tlast <= (rd_ff == len_ff[12:0] - 13'd1);
                m_axis_tuser <= win_seq_ff;
                if (m_fire) begin
                    if (rd_ff == len_ff[12:0] - 13'd1) begin
                        rd_ff <= 13'd0;
                        wr1_ff <= 13'd0;
                        win_seq_ff <= win_seq_ff + 16'd1;
                        m_axis_tvalid <= 1'b0;
                    end else rd_ff <= rd_ff + 13'd1;
                end
            end else begin
                m_axis_tvalid <= 1'b0;
                m_axis_tlast <= 1'b0;
            end
        end
    end
endmodule
`default_nettype wire
