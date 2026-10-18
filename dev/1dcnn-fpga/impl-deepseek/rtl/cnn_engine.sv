`default_nettype none
`timescale 1ns/1ps
`include "cnn_params.svh"
//==============================================================================
// cnn_engine — synthesizable sequential PE (FSM + MAC + BRAM features)
// Weight BRAM is 1-cycle sync: ISS -> WAIT -> CAP/MAC (NBA-safe)
//==============================================================================
module cnn_engine (
    input  wire                sys_clk,
    input  wire                sys_rst_n,
    input  wire                i_eng_en,
    input  wire                i_weight_ok,
    output logic               o_busy,
    output logic [31:0]        o_cyc_cnt,
    output logic               o_err_weight,
    input  wire signed [15:0]  s_axis_tdata,
    input  wire                s_axis_tvalid,
    output logic               s_axis_tready,
    input  wire                s_axis_tlast,
    output logic signed [15:0] m_axis_tdata,
    output logic               m_axis_tvalid,
    input  wire                m_axis_tready,
    output logic               m_axis_tlast,
    output logic               o_w_rd_en,
    output logic [13:0]        o_w_rd_addr,
    input  wire signed [15:0]  i_w_rd_data
);
    typedef enum logic [3:0] {
        ST_IDLE=0, ST_LOAD_WIN=1, ST_CONV1=2, ST_CONV2=3,
        ST_POOL=4, ST_CONV3=5, ST_GAP=6, ST_FC=7, ST_OUT_SCORE=8
    } state_t;

    // 5-bit microstep: ISS_* then WAIT_* then use data
    typedef enum logic [4:0] {
        MS_ISS_BIAS=0, MS_WAIT_B=1, MS_CAP_BIAS=2,
        MS_ISS_W=3,    MS_WAIT_W=4, MS_DO_MAC=5,
        MS_ISS_SM=6,   MS_WAIT_SM=7, MS_CAP_SM=8,
        MS_ISS_SS=9,   MS_WAIT_SS=10, MS_DO_QUANT=11,
        MS_POOL_ONE=12,
        MS_GAP_ADD=13,
        MS_GAP_ISM=14, MS_GAP_W1=15, MS_GAP_CRM=16,
        MS_GAP_ISS=17, MS_GAP_W2=18, MS_GAP_CSS=19, MS_GAP_Q=20
    } mstep_t;

    state_t cs_state, ns_state;
    mstep_t cs_mstep, ns_mstep;

    logic signed [15:0] feat0 [0:`FEAT_DEPTH-1];
    logic signed [15:0] feat1 [0:`FEAT_DEPTH-1];
    logic bank_rd_ff;

    logic [11:0] wr_idx_ff;
    logic [7:0]  oc_ff;
    logic [9:0]  ot_ff;
    logic [5:0]  ic_ff;
    logic [4:0]  k_ff;
    logic signed [31:0] acc_ff;
    logic signed [15:0] smult_ff, act_hold_ff;
    logic signed [15:0] score_ff [0:9];
    logic [3:0]  score_idx_ff;
    logic [31:0] cyc_ff;
    logic cyc_run_ff, busy_ff, err_weight_ff, layer_done_ff;
    logic signed [15:0] gap_rm_ff;
    logic [15:0] gap_rs_ff;

    logic [7:0]  p_cout;
    logic [5:0]  p_cin;
    logic [4:0]  p_k, p_stride, p_pad;
    logic [11:0] p_rin;
    logic [9:0]  p_rout;
    logic [13:0] p_wbase, p_bias, p_sm, p_ss;
    logic p_relu, p_is_fc;

    wire s_fire = s_axis_tvalid && s_axis_tready;
    wire m_fire = m_axis_tvalid && m_axis_tready;

    function automatic logic signed [15:0] rd_feat(input logic bank, input logic [13:0] idx);
        if (idx >= `FEAT_DEPTH) return 16'sd0;
        else if (!bank) return feat0[idx];
        else return feat1[idx];
    endfunction

    function automatic logic signed [15:0] sat_i16(input logic signed [63:0] x);
        if (x > 64'sd32767) return 16'sd32767;
        else if (x < -64'sd32768) return -16'sd32768;
        else return x[15:0];
    endfunction

    logic signed [15:0] w_act_pad;
    logic signed [31:0] w_t_idx;
    always_comb begin
        w_t_idx = 32'(ot_ff) * 32'(p_stride) + 32'(k_ff) - 32'(p_pad);
        if (w_t_idx < 0 || w_t_idx >= 32'(p_rin)) w_act_pad = 16'sd0;
        else w_act_pad = rd_feat(bank_rd_ff, 14'(32'(w_t_idx) * 32'(p_cin) + 32'(ic_ff)));
    end
    wire signed [15:0] w_act_fc = rd_feat(bank_rd_ff, 14'(ic_ff));
    wire last_tap = (k_ff == p_k - 5'd1) && (ic_ff == p_cin - 6'd1);
    wire last_out = (ot_ff == p_rout - 10'd1) && (oc_ff == p_cout - 8'd1);

    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) cs_state <= ST_IDLE;
        else cs_state <= ns_state;
    end
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) cs_mstep <= MS_ISS_BIAS;
        else cs_mstep <= ns_mstep;
    end

    always_comb begin
        ns_state = cs_state;
        case (cs_state)
            ST_IDLE: if (i_eng_en && i_weight_ok && s_axis_tvalid) ns_state = ST_LOAD_WIN;
            ST_LOAD_WIN: if (s_fire && s_axis_tlast) ns_state = ST_CONV1;
            ST_CONV1: if (layer_done_ff) ns_state = ST_CONV2;
            ST_CONV2: if (layer_done_ff) ns_state = ST_POOL;
            ST_POOL:  if (layer_done_ff) ns_state = ST_CONV3;
            ST_CONV3: if (layer_done_ff) ns_state = ST_GAP;
            ST_GAP:   if (layer_done_ff) ns_state = ST_FC;
            ST_FC:    if (layer_done_ff) ns_state = ST_OUT_SCORE;
            ST_OUT_SCORE: if (m_fire && m_axis_tlast) ns_state = ST_IDLE;
            default: ns_state = ST_IDLE;
        endcase
    end

    always_comb begin
        ns_mstep = cs_mstep;
        if (cs_state != ns_state &&
            (ns_state==ST_CONV1||ns_state==ST_CONV2||ns_state==ST_CONV3||
             ns_state==ST_FC||ns_state==ST_POOL||ns_state==ST_GAP)) begin
            if (ns_state==ST_POOL) ns_mstep = MS_POOL_ONE;
            else if (ns_state==ST_GAP) ns_mstep = MS_GAP_ADD;
            else ns_mstep = MS_ISS_BIAS;
        end else case (cs_state)
            ST_CONV1, ST_CONV2, ST_CONV3, ST_FC: case (cs_mstep)
                MS_ISS_BIAS: ns_mstep = MS_WAIT_B;
                MS_WAIT_B:   ns_mstep = MS_CAP_BIAS;
                MS_CAP_BIAS: ns_mstep = MS_ISS_W;
                MS_ISS_W:    ns_mstep = MS_WAIT_W;
                MS_WAIT_W:   ns_mstep = MS_DO_MAC;
                MS_DO_MAC:   ns_mstep = last_tap ? MS_ISS_SM : MS_ISS_W;
                MS_ISS_SM:   ns_mstep = MS_WAIT_SM;
                MS_WAIT_SM:  ns_mstep = MS_CAP_SM;
                MS_CAP_SM:   ns_mstep = MS_ISS_SS;
                MS_ISS_SS:   ns_mstep = MS_WAIT_SS;
                MS_WAIT_SS:  ns_mstep = MS_DO_QUANT;
                MS_DO_QUANT: ns_mstep = MS_ISS_BIAS;
                default: ns_mstep = MS_ISS_BIAS;
            endcase
            ST_POOL: ns_mstep = MS_POOL_ONE;
            ST_GAP: case (cs_mstep)
                MS_GAP_ADD: ns_mstep = (ot_ff == 10'(`GAP_T-1)) ? MS_GAP_ISM : MS_GAP_ADD;
                MS_GAP_ISM: ns_mstep = MS_GAP_W1;
                MS_GAP_W1:  ns_mstep = MS_GAP_CRM;
                MS_GAP_CRM: ns_mstep = MS_GAP_ISS;
                MS_GAP_ISS: ns_mstep = MS_GAP_W2;
                MS_GAP_W2:  ns_mstep = MS_GAP_CSS;
                MS_GAP_CSS: ns_mstep = MS_GAP_Q;
                MS_GAP_Q:   ns_mstep = MS_GAP_ADD;
                default: ns_mstep = MS_GAP_ADD;
            endcase
            default: ns_mstep = MS_ISS_BIAS;
        endcase
    end

    assign o_busy = busy_ff;
    assign o_cyc_cnt = cyc_ff;
    assign o_err_weight = err_weight_ff;
    assign s_axis_tready = (cs_state == ST_LOAD_WIN);

    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            busy_ff<=0; err_weight_ff<=0; cyc_ff<=0; cyc_run_ff<=0;
            wr_idx_ff<=0; bank_rd_ff<=0; layer_done_ff<=0;
            oc_ff<=0; ot_ff<=0; ic_ff<=0; k_ff<=0;
            acc_ff<=0; smult_ff<=0; act_hold_ff<=0;
            o_w_rd_en<=0; o_w_rd_addr<=0; score_idx_ff<=0;
            m_axis_tdata<=0; m_axis_tvalid<=0; m_axis_tlast<=0;
            p_cout<=0; p_cin<=0; p_k<=0; p_stride<=0; p_pad<=0;
            p_rin<=0; p_rout<=0; p_wbase<=0; p_bias<=0; p_sm<=0; p_ss<=0;
            p_relu<=0; p_is_fc<=0; gap_rm_ff<=0; gap_rs_ff<=0;
            for (int si=0; si<10; si++) score_ff[si]<=0;
        end else begin
            o_w_rd_en <= 1'b0;
            if (cs_state != ns_state) layer_done_ff <= 1'b0;

            if (cs_state==ST_IDLE && ns_state==ST_LOAD_WIN) begin
                busy_ff<=1; cyc_ff<=0; cyc_run_ff<=1; wr_idx_ff<=0; bank_rd_ff<=0;
                for (int zi=0; zi<10; zi++) score_ff[zi] <= 16'sd0;
            end
            if (cs_state==ST_OUT_SCORE && ns_state==ST_IDLE) begin
                busy_ff<=0; cyc_run_ff<=0;
            end
            if (cyc_run_ff) cyc_ff <= cyc_ff + 1'b1;
            if (cs_state==ST_IDLE && i_eng_en && !i_weight_ok && s_axis_tvalid)
                err_weight_ff <= 1'b1;

            if (cs_state==ST_LOAD_WIN && s_fire) begin
                feat0[wr_idx_ff] <= s_axis_tdata;
                wr_idx_ff <= wr_idx_ff + 1'b1;
            end

            if (ns_state==ST_CONV1 && cs_state!=ST_CONV1) begin
                p_cout<=`CONV1_COUT; p_cin<=`CONV1_CIN; p_k<=`CONV1_K;
                p_stride<=`CONV1_S; p_pad<=`CONV1_PAD_L;
                p_rin<=`CONV1_RIN; p_rout<=`CONV1_ROUT;
                p_wbase<=`OFF_CONV1_W; p_bias<=`OFF_CONV1_BIAS;
                p_sm<=`OFF_CONV1_SMULT; p_ss<=`OFF_CONV1_SSHIFT;
                p_relu<=1; p_is_fc<=0; oc_ff<=0; ot_ff<=0; ic_ff<=0; k_ff<=0;
            end else if (ns_state==ST_CONV2 && cs_state!=ST_CONV2) begin
                p_cout<=`CONV2_COUT; p_cin<=`CONV2_CIN; p_k<=`CONV2_K;
                p_stride<=`CONV2_S; p_pad<=0;
                p_rin<=`CONV2_RIN; p_rout<=`CONV2_ROUT;
                p_wbase<=`OFF_CONV2_W; p_bias<=`OFF_CONV2_BIAS;
                p_sm<=`OFF_CONV2_SMULT; p_ss<=`OFF_CONV2_SSHIFT;
                p_relu<=1; p_is_fc<=0; oc_ff<=0; ot_ff<=0; ic_ff<=0; k_ff<=0;
            end else if (ns_state==ST_CONV3 && cs_state!=ST_CONV3) begin
                p_cout<=`CONV3_COUT; p_cin<=`CONV3_CIN; p_k<=`CONV3_K;
                p_stride<=`CONV3_S; p_pad<=0;
                p_rin<=`CONV3_RIN; p_rout<=`CONV3_ROUT;
                p_wbase<=`OFF_CONV3_W; p_bias<=`OFF_CONV3_BIAS;
                p_sm<=`OFF_CONV3_SMULT; p_ss<=`OFF_CONV3_SSHIFT;
                p_relu<=1; p_is_fc<=0; oc_ff<=0; ot_ff<=0; ic_ff<=0; k_ff<=0;
            end else if (ns_state==ST_FC && cs_state!=ST_FC) begin
                p_cout<=`FC_COUT; p_cin<=`FC_CIN; p_k<=1;
                p_stride<=1; p_pad<=0; p_rin<=1; p_rout<=1;
                p_wbase<=`OFF_FC_W; p_bias<=`OFF_FC_BIAS;
                p_sm<=`OFF_FC_SMULT; p_ss<=`OFF_FC_SSHIFT;
                p_relu<=0; p_is_fc<=1; oc_ff<=0; ot_ff<=0; ic_ff<=0; k_ff<=0;
            end else if (ns_state==ST_POOL && cs_state!=ST_POOL) begin
                oc_ff<=0; ot_ff<=0;
            end else if (ns_state==ST_GAP && cs_state!=ST_GAP) begin
                oc_ff<=0; ot_ff<=0; acc_ff<=0;
            end

            if (cs_state==ST_CONV1||cs_state==ST_CONV2||cs_state==ST_CONV3||cs_state==ST_FC) begin
                case (cs_mstep)
                    MS_ISS_BIAS: begin
                        o_w_rd_en<=1; o_w_rd_addr<=p_bias+14'(oc_ff);
                    end
                    MS_WAIT_B: ; // BRAM latency
                    MS_CAP_BIAS: begin
                        acc_ff <= {{16{i_w_rd_data[15]}}, i_w_rd_data};
                        ic_ff<=0; k_ff<=0;
                    end
                    MS_ISS_W: begin
                        o_w_rd_en<=1;
                        if (p_is_fc)
                            o_w_rd_addr <= p_wbase + 14'(oc_ff)*14'(`FC_CIN) + 14'(ic_ff);
                        else
                            o_w_rd_addr <= p_wbase + 14'(oc_ff)*14'(p_cin)*14'(p_k)
                                         + 14'(ic_ff)*14'(p_k) + 14'(k_ff);
                        act_hold_ff <= p_is_fc ? w_act_fc : w_act_pad;
                    end
                    MS_WAIT_W: ;
                    MS_DO_MAC: begin
                        acc_ff <= acc_ff + ($signed(act_hold_ff) * $signed(i_w_rd_data));
                        if (k_ff == p_k-5'd1) begin
                            k_ff<=0; ic_ff<=ic_ff+1'b1;
                        end else k_ff<=k_ff+1'b1;
                    end
                    MS_ISS_SM: begin
                        o_w_rd_en<=1; o_w_rd_addr<=p_sm+14'(oc_ff);
                    end
                    MS_WAIT_SM: ;
                    MS_CAP_SM: smult_ff <= i_w_rd_data;
                    MS_ISS_SS: begin
                        o_w_rd_en<=1; o_w_rd_addr<=p_ss+14'(oc_ff);
                    end
                    MS_WAIT_SS: ;
                    MS_DO_QUANT: begin
                        automatic logic signed [63:0] prod, scaled;
                        automatic logic signed [15:0] vv;
                        automatic logic [5:0] sh;
                        prod = $signed({{32{acc_ff[31]}}, acc_ff})
                             * $signed({{48{smult_ff[15]}}, smult_ff});
                        sh = (i_w_rd_data[15:0] > 16'd63) ? 6'd63 : i_w_rd_data[5:0];
                        scaled = prod >>> sh;
                        vv = sat_i16(scaled);
                        if (p_relu && vv[15]) vv = 16'sd0;
                        if (p_is_fc) score_ff[oc_ff[3:0]] <= vv;
                        else if (!bank_rd_ff)
                            feat1[14'(ot_ff)*14'(p_cout)+14'(oc_ff)] <= vv;
                        else
                            feat0[14'(ot_ff)*14'(p_cout)+14'(oc_ff)] <= vv;
                        if (ot_ff == p_rout-10'd1) begin
                            ot_ff <= 0;
                            if (oc_ff == p_cout-8'd1) begin
                                layer_done_ff <= 1'b1;
                                bank_rd_ff <= ~bank_rd_ff;
                            end else oc_ff <= oc_ff + 1'b1;
                        end else ot_ff <= ot_ff + 1'b1;
                    end
                    default: ;
                endcase
            end

            if (cs_state==ST_POOL && cs_mstep==MS_POOL_ONE) begin
                automatic logic signed [15:0] a0, a1, mx;
                automatic logic [13:0] base;
                base = 14'(ot_ff)*14'(`POOL_S)*14'(`CONV2_COUT) + 14'(oc_ff);
                a0 = rd_feat(bank_rd_ff, base);
                a1 = rd_feat(bank_rd_ff, 14'(base + `CONV2_COUT));
                mx = (a0 > a1) ? a0 : a1;
                if (!bank_rd_ff) feat1[14'(ot_ff)*14'(`CONV2_COUT)+14'(oc_ff)] <= mx;
                else feat0[14'(ot_ff)*14'(`CONV2_COUT)+14'(oc_ff)] <= mx;
                if (oc_ff == 8'(`CONV2_COUT-1)) begin
                    oc_ff <= 0;
                    if (ot_ff == 10'(`POOL_ROUT-1)) begin
                        layer_done_ff <= 1'b1;
                        bank_rd_ff <= ~bank_rd_ff;
                    end else ot_ff <= ot_ff + 1'b1;
                end else oc_ff <= oc_ff + 1'b1;
            end

            if (cs_state==ST_GAP) begin
                case (cs_mstep)
                    MS_GAP_ADD: begin
                        if (ot_ff==0)
                            acc_ff <= $signed(rd_feat(bank_rd_ff, 14'(oc_ff)));
                        else
                            acc_ff <= acc_ff + $signed(rd_feat(bank_rd_ff,
                                      14'(ot_ff)*14'(`GAP_C)+14'(oc_ff)));
                        ot_ff <= ot_ff + 1'b1;
                    end
                    MS_GAP_ISM: begin
                        o_w_rd_en<=1; o_w_rd_addr<=`OFF_GAP_RMULT; ot_ff<=0;
                    end
                    MS_GAP_W1: ;
                    MS_GAP_CRM: gap_rm_ff <= i_w_rd_data;
                    MS_GAP_ISS: begin
                        o_w_rd_en<=1; o_w_rd_addr<=`OFF_GAP_RSHIFT;
                    end
                    MS_GAP_W2: ;
                    MS_GAP_CSS: gap_rs_ff <= i_w_rd_data[15:0];
                    MS_GAP_Q: begin
                        automatic logic signed [63:0] prod, scaled;
                        automatic logic signed [15:0] vv;
                        automatic logic [5:0] sh;
                        prod = $signed({{32{acc_ff[31]}}, acc_ff})
                             * $signed({{48{gap_rm_ff[15]}}, gap_rm_ff});
                        sh = (gap_rs_ff > 16'd63) ? 6'd63 : gap_rs_ff[5:0];
                        scaled = prod >>> sh;
                        vv = sat_i16(scaled);
                        if (!bank_rd_ff) feat1[14'(oc_ff)] <= vv;
                        else feat0[14'(oc_ff)] <= vv;
                        if (oc_ff == 8'(`GAP_C-1)) begin
                            layer_done_ff <= 1'b1;
                            bank_rd_ff <= ~bank_rd_ff;
                        end else oc_ff <= oc_ff + 1'b1;
                        acc_ff <= 0;
                    end
                    default: ;
                endcase
            end

            if (cs_state!=ST_OUT_SCORE && ns_state==ST_OUT_SCORE) begin
                score_idx_ff<=0; m_axis_tdata<=score_ff[0];
                m_axis_tvalid<=1; m_axis_tlast<=0;
            end else if (cs_state==ST_OUT_SCORE) begin
                if (m_fire) begin
                    if (score_idx_ff==9) begin
                        m_axis_tvalid<=0; m_axis_tlast<=0; score_idx_ff<=0;
                    end else begin
                        score_idx_ff <= score_idx_ff + 1'b1;
                        m_axis_tdata <= score_ff[score_idx_ff + 4'd1];
                        m_axis_tvalid <= 1'b1;
                        m_axis_tlast <= (score_idx_ff + 4'd1 == 4'd9);
                    end
                end
            end else begin
                m_axis_tvalid<=0; m_axis_tlast<=0;
            end
        end
    end
endmodule
`default_nettype wire
