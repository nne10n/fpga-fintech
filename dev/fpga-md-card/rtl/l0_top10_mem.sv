// -----------------------------------------------------------------------------
// l0_top10_mem.sv — 4-bank dual-port Top-10 RAM (P1.0)
// Production: map each bank array to URAM IP (behavioral stand-in here).
// bank=symbol_id[1:0]; local addr=symbol>>2. Port-A always accepted.
// Same-bank A/B: A wins, o_b_ready=0. Read latency 1 cycle.
// SPEC: docs/p1-parallel-partition.md §5; docs/p1-push-refill-handoff.md P1.0
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module l0_top10_mem
  import book_pkg::*;
#(
  parameter int N_SYM_P = 4096
) (
  input  logic            sys_clk,
  /* verilator lint_off SYNCASYNCNET */
  input  logic            sys_rst_n,
  /* verilator lint_on SYNCASYNCNET */
  input  logic            i_a_req,
  input  logic            i_a_we,
  input  logic [15:0]     i_a_symbol,
  input  l0_top10_row_t   i_a_wdata,
  output l0_top10_row_t   o_a_rdata,
  output logic            o_a_valid,
  output logic            o_a_ready,
  input  logic            i_b_req,
  input  logic            i_b_we,
  input  logic            i_b_is_refill,
  input  logic [15:0]     i_b_symbol,
  input  l0_top10_row_t   i_b_wdata,
  output l0_top10_row_t   o_b_rdata,
  output logic            o_b_valid,
  output logic            o_b_ready,
  (* keep = "true" *) output logic [31:0] o_dbg_conflict_cnt,
  (* keep = "true" *) output logic [1:0]  o_dbg_cs_state,
  (* keep = "true" *) output logic        o_dbg_err_sticky
);

  localparam int BANK_DEPTH = N_SYM_P / L0_N_BANK;
  localparam int BANK_AW    = (BANK_DEPTH <= 1) ? 1 : $clog2(BANK_DEPTH);

  l0_top10_row_t mem [0:L0_N_BANK-1][0:BANK_DEPTH-1];

  logic [1:0]         w_a_bank;
  logic [1:0]         w_b_bank;
  logic [BANK_AW-1:0] w_a_addr;
  logic [BANK_AW-1:0] w_b_addr;
  logic               w_same_bank;
  logic               w_a_fire;
  logic               w_b_fire;

  logic               r_a_valid;
  logic               r_b_valid;
  l0_top10_row_t      r_a_rdata;
  l0_top10_row_t      r_b_rdata;
  logic               r_err_sticky;
  logic [31:0]        r_conflict_cnt;

  assign w_a_bank    = i_a_symbol[1:0];
  assign w_b_bank    = i_b_symbol[1:0];
  assign w_a_addr    = i_a_symbol[2 +: BANK_AW];
  assign w_b_addr    = i_b_symbol[2 +: BANK_AW];
  assign w_same_bank = i_a_req && i_b_req && (w_a_bank == w_b_bank);
  assign o_a_ready   = 1'b1;
  assign o_b_ready   = !w_same_bank;
  assign w_a_fire    = i_a_req && o_a_ready;
  assign w_b_fire    = i_b_req && o_b_ready;

  assign o_a_rdata        = r_a_rdata;
  assign o_a_valid        = r_a_valid;
  assign o_b_rdata        = r_b_rdata;
  assign o_b_valid        = r_b_valid;
  assign o_dbg_conflict_cnt = r_conflict_cnt;
  assign o_dbg_cs_state     = 2'b00;
  assign o_dbg_err_sticky   = r_err_sticky;

  initial begin
    automatic int b, a;
    for (b = 0; b < L0_N_BANK; b++)
      for (a = 0; a < BANK_DEPTH; a++)
        mem[b][a] = '0;
  end

  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_a_valid    <= 1'b0;
      r_b_valid    <= 1'b0;
      r_a_rdata    <= '0;
      r_b_rdata    <= '0;
      r_err_sticky <= 1'b0;
      // Behavioral clear (sim / BRAM init stand-in). Prod URAM: use INIT.
      for (int bi = 0; bi < L0_N_BANK; bi++)
        for (int ai = 0; ai < BANK_DEPTH; ai++)
          mem[bi][ai] <= '0;
    end else begin
      r_a_valid <= 1'b0;
      r_b_valid <= 1'b0;
      if (w_a_fire) begin
        if (i_a_we)
          mem[w_a_bank][w_a_addr] <= i_a_wdata;
        else begin
          r_a_rdata <= mem[w_a_bank][w_a_addr];
          r_a_valid <= 1'b1;
        end
      end
      if (w_b_fire) begin
        if (i_b_we)
          mem[w_b_bank][w_b_addr] <= i_b_wdata;
        else begin
          r_b_rdata <= mem[w_b_bank][w_b_addr];
          r_b_valid <= 1'b1;
        end
      end
    end
  end

  // Same-bank A/B conflict cycles (saturating) — SPEC: p1-parallel-partition.md P-L0-DBG
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      r_conflict_cnt <= 32'd0;
    else if (w_same_bank) begin
      if (r_conflict_cnt != 32'hFFFF_FFFF)
        r_conflict_cnt <= r_conflict_cnt + 32'd1;
    end
  end

endmodule

`default_nettype wire
