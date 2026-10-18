`default_nettype none
`timescale 1ns/1ps
//==============================================================================
// score_path — capture 10-beat AXIS scores into REG_SCORE0..9
//==============================================================================
module score_path #(
    parameter int N_CLASS = 10
) (
    input  wire                sys_clk,
    input  wire                sys_rst_n,
    input  wire signed [15:0]  s_axis_tdata,
    input  wire                s_axis_tvalid,
    output logic               s_axis_tready,
    input  wire                s_axis_tlast,
    input  wire                i_irq_en,
    output logic [31:0]        o_score_regs [0:9],
    output logic               o_done_pulse,
    output logic               o_irq_pulse
);
    typedef enum logic [1:0] { ST_WAIT=2'd0, ST_CAP=2'd1, ST_IRQ=2'd2 } state_t;
    state_t cs_state, ns_state;
    logic [3:0] idx_ff;
    logic [1:0] irq_cnt_ff;

    assign s_axis_tready = 1'b1;
    wire s_fire = s_axis_tvalid && s_axis_tready;

    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) cs_state <= ST_WAIT;
        else cs_state <= ns_state;
    end

    always_comb begin
        ns_state = cs_state;
        case (cs_state)
            ST_WAIT: begin
                if (s_fire) begin
                    if (s_axis_tlast) begin
                        if (i_irq_en) ns_state = ST_IRQ;
                        else ns_state = ST_WAIT;
                    end else ns_state = ST_CAP;
                end
            end
            ST_CAP: begin
                if (s_fire && (s_axis_tlast || idx_ff == 4'd9)) begin
                    if (i_irq_en) ns_state = ST_IRQ;
                    else ns_state = ST_WAIT;
                end
            end
            ST_IRQ: begin
                if (irq_cnt_ff == 2'd0) ns_state = ST_WAIT;
            end
            default: ns_state = ST_WAIT;
        endcase
    end

    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            idx_ff <= 4'd0;
            o_done_pulse <= 1'b0;
            o_irq_pulse <= 1'b0;
            irq_cnt_ff <= 2'd0;
            for (int i = 0; i < 10; i++) o_score_regs[i] <= 32'd0;
        end else begin
            o_done_pulse <= 1'b0;
            case (cs_state)
                ST_WAIT: begin
                    o_irq_pulse <= 1'b0;
                    if (s_fire) begin
                        o_score_regs[0] <= {{16{s_axis_tdata[15]}}, s_axis_tdata};
                        idx_ff <= 4'd1;
                        if (s_axis_tlast) begin
                            o_done_pulse <= 1'b1;
                            irq_cnt_ff <= 2'd2;
                        end
                    end
                end
                ST_CAP: begin
                    if (s_fire) begin
                        o_score_regs[idx_ff] <= {{16{s_axis_tdata[15]}}, s_axis_tdata};
                        if (s_axis_tlast || idx_ff == 4'd9) begin
                            o_done_pulse <= 1'b1;
                            irq_cnt_ff <= 2'd2;
                            idx_ff <= 4'd0;
                        end else idx_ff <= idx_ff + 4'd1;
                    end
                end
                ST_IRQ: begin
                    o_irq_pulse <= 1'b1;
                    if (irq_cnt_ff == 2'd0) o_irq_pulse <= 1'b0;
                    else irq_cnt_ff <= irq_cnt_ff - 2'd1;
                end
                default: ;
            endcase
        end
    end
endmodule
`default_nettype wire
