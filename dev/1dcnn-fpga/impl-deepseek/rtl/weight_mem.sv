`default_nettype none
`timescale 1ns/1ps
//==============================================================================
// weight_mem — single bank INT16 weights, 1-cycle sync BRAM read
// Hotswap: bank_sel reserved; V1 only bank0; bank_sel=1 → err sticky
//==============================================================================
module weight_mem #(
    parameter int DEPTH  = 11504,
    parameter int ADDR_W = 14
) (
    input  wire                sys_clk,
    input  wire                sys_rst_n,
    // load port (word write, auto-increment)
    input  wire                i_load_en,
    input  wire                i_wr_en,
    input  wire signed [15:0]  i_wr_data,
    input  wire                i_soft_rst,
    input  wire                i_bank_sel,
    // read port to cnn_engine (1-cycle sync)
    input  wire                i_rd_en,
    input  wire [ADDR_W-1:0]   i_rd_addr,
    output logic signed [15:0] o_rd_data,
    // status
    output logic               o_weight_ok,
    output logic               o_err_hotswap
);
    logic signed [15:0] mem [0:DEPTH-1];
    logic [ADDR_W-1:0] wr_ptr_ff;
    logic              loading_ff;

    // write / load FSM-ish
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            wr_ptr_ff   <= '0;
            loading_ff  <= 1'b0;
            o_weight_ok <= 1'b0;
            o_err_hotswap <= 1'b0;
        end else if (i_soft_rst) begin
            wr_ptr_ff   <= '0;
            loading_ff  <= 1'b0;
            o_weight_ok <= 1'b0;
        end else begin
            if (i_bank_sel) o_err_hotswap <= 1'b1;
            if (i_load_en && !loading_ff) begin
                loading_ff  <= 1'b1;
                wr_ptr_ff   <= '0;
                o_weight_ok <= 1'b0;
            end
            if (i_wr_en) begin
                mem[wr_ptr_ff] <= i_wr_data;
                if (wr_ptr_ff == ADDR_W'(DEPTH-1)) begin
                    o_weight_ok <= 1'b1;
                    loading_ff  <= 1'b0;
                    wr_ptr_ff   <= '0;
                end else begin
                    wr_ptr_ff <= wr_ptr_ff + 1'b1;
                end
            end
        end
    end

    // 1-cycle sync read
    always_ff @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) o_rd_data <= '0;
        else if (i_rd_en) o_rd_data <= mem[i_rd_addr];
    end
endmodule
`default_nettype wire
