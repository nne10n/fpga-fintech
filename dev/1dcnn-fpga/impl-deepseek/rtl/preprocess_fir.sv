`default_nettype none
`timescale 1ns/1ps
//==============================================================================
// preprocess_fir — DC block + 32-tap symmetric FIR, bypass mux first
//==============================================================================
module preprocess_fir #(
    parameter int FIR_TAPS = 32,
    parameter int COEF_W   = 16,
    parameter bit BYPASS_REG = 1
) (
    input  wire                sys_clk,
    input  wire                sys_rst_n,
    input  wire                i_bypass,
    input  wire signed [15:0]  s_axis_tdata,
    input  wire                s_axis_tvalid,
    output logic               s_axis_tready,
    input  wire                s_axis_tlast,
    input  wire [23:0]         s_axis_tuser,
    output logic signed [15:0] m_axis_tdata,
    output logic               m_axis_tvalid,
    input  wire                m_axis_tready,
    output logic               m_axis_tlast,
    output logic [23:0]        m_axis_tuser
);
    // Fixed lowpass-ish coefficients (Q15-ish small ints); V1 placeholder
    localparam logic signed [15:0] COEF [0:31] = '{
        16'sd1,16'sd2,16'sd3,16'sd4,16'sd5,16'sd6,16'sd7,16'sd8,
        16'sd8,16'sd7,16'sd6,16'sd5,16'sd4,16'sd3,16'sd2,16'sd1,
        16'sd1,16'sd2,16'sd3,16'sd4,16'sd5,16'sd6,16'sd7,16'sd8,
        16'sd8,16'sd7,16'sd6,16'sd5,16'sd4,16'sd3,16'sd2,16'sd1
    };

    logic signed [15:0] delay_ff [0:FIR_TAPS-1];
    logic signed [31:0] acc;
    logic signed [15:0] fir_y;
    integer ti;

    wire s_fire = s_axis_tvalid && s_axis_tready;
    assign s_axis_tready = i_bypass ? m_axis_tready : m_axis_tready;

    always_comb begin
        acc = 32'sd0;
        for (ti = 0; ti < FIR_TAPS; ti++)
            acc = acc + 32'(delay_ff[ti]) * 32'(COEF[ti]);
        // >> 8 scale
        fir_y = acc[23:8];
    end

    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            m_axis_tdata <= 16'sd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast <= 1'b0;
            m_axis_tuser <= 24'd0;
            for (ti = 0; ti < FIR_TAPS; ti++) delay_ff[ti] <= 16'sd0;
        end else begin
            if (i_bypass) begin
                if (BYPASS_REG) begin
                    if (m_axis_tready || !m_axis_tvalid) begin
                        m_axis_tvalid <= s_axis_tvalid;
                        m_axis_tdata <= s_axis_tdata;
                        m_axis_tlast <= s_axis_tlast;
                        m_axis_tuser <= s_axis_tuser;
                    end
                end else begin
                    m_axis_tvalid <= s_axis_tvalid;
                    m_axis_tdata <= s_axis_tdata;
                    m_axis_tlast <= s_axis_tlast;
                    m_axis_tuser <= s_axis_tuser;
                end
            end else if (s_fire) begin
                for (ti = FIR_TAPS-1; ti > 0; ti--)
                    delay_ff[ti] <= delay_ff[ti-1];
                delay_ff[0] <= s_axis_tdata;
                m_axis_tdata <= fir_y;
                m_axis_tvalid <= 1'b1;
                m_axis_tlast <= s_axis_tlast;
                m_axis_tuser <= s_axis_tuser;
            end else if (m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end
        end
    end
endmodule
`default_nettype wire
