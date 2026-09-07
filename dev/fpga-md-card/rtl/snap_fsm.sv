// -----------------------------------------------------------------------------
// snap_fsm.sv — periodic full-market Top-10 snapshot walker (sys_clk)
// SPEC: docs/book-push-refill-v2.md §3; docs/p1-parallel-partition.md §3/§6
// Walk symbol 0..4095; Port-B style read; skip empty; push or drop-and-advance
// Default period: 10ms @322.265625MHz ≈ 3_222_656 cycles (CSR i_period_cycles)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module snap_fsm
  import book_pkg::*;
#(
  parameter int N_SYM_P = N_SYM
) (
  input  logic                sys_clk,
  input  logic                sys_rst_n,

  input  logic                i_snap_enable,
  input  logic                i_snap_skip_empty,
  input  logic [31:0]         i_period_cycles,

  // Port-B style read (握手)
  output logic                o_rd_valid,
  output logic [N_SYM_AW-1:0] o_rd_symbol,
  input  logic                i_rd_ready,
  input  top10_view_t         i_rd_view,
  input  logic                i_rd_view_valid,

  // To push_q_snap (握手; 满则丢当前 id 前进 — SPEC p1 §6.1)
  output logic                o_push_valid,
  input  logic                i_push_ready,
  output logic [N_SYM_AW-1:0] o_push_symbol,
  output top10_view_t         o_push_view,

  (* keep = "true" *) output logic [2:0]          o_dbg_cs_state,
  (* keep = "true" *) output logic [31:0]         o_dbg_drop_cnt,
  (* keep = "true" *) output logic [N_SYM_AW-1:0] o_dbg_symbol,
  (* keep = "true" *) output logic                o_dbg_err_sticky
);

  typedef enum logic [2:0] {
    ST_IDLE        = 3'd0,
    ST_WAIT_PERIOD = 3'd1,
    ST_READ        = 3'd2,
    ST_PUSH        = 3'd3
  } state_e;

  state_e              cs_state;
  state_e              ns_state;

  logic [31:0]         r_period_cnt;
  logic [N_SYM_AW-1:0] r_symbol;
  top10_view_t         r_view;
  logic                r_rd_issued;
  logic                r_push_valid;
  logic [31:0]         r_drop_cnt;
  logic                r_err_sticky;

  logic                w_rd_fire;
  logic                w_is_last;
  logic                w_view_empty;

  assign w_rd_fire    = o_rd_valid && i_rd_ready;
  assign w_is_last    = (r_symbol == N_SYM_AW'(N_SYM_P - 1));
  assign w_view_empty = top10_view_empty(i_rd_view);

  // -----------------------------------------------------------------------
  // 第一段 — 当前态
  // -----------------------------------------------------------------------
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      cs_state <= ST_IDLE;
    else
      cs_state <= ns_state;
  end

  // -----------------------------------------------------------------------
  // 第二段 — 次态 only
  // -----------------------------------------------------------------------
  always_comb begin
    ns_state = cs_state;
    unique case (cs_state)
      ST_IDLE: begin
        if (i_snap_enable)
          ns_state = ST_WAIT_PERIOD;
      end
      ST_WAIT_PERIOD: begin
        if (!i_snap_enable)
          ns_state = ST_IDLE;
        else if (r_period_cnt >= i_period_cycles)
          ns_state = ST_READ;
      end
      ST_READ: begin
        if (!i_snap_enable)
          ns_state = ST_IDLE;
        else if (i_rd_view_valid && r_rd_issued) begin
          if (i_snap_skip_empty && w_view_empty) begin
            if (w_is_last)
              ns_state = ST_WAIT_PERIOD;
            else
              ns_state = ST_READ;
          end else
            ns_state = ST_PUSH;
        end
      end
      ST_PUSH: begin
        // one-cycle attempt: ready → push; !ready → drop (SPEC)
        if (!i_snap_enable)
          ns_state = ST_IDLE;
        else if (w_is_last)
          ns_state = ST_WAIT_PERIOD;
        else
          ns_state = ST_READ;
      end
      default: ns_state = ST_IDLE;
    endcase
  end

  // -----------------------------------------------------------------------
  // 第三段 — period counter
  // -----------------------------------------------------------------------
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      r_period_cnt <= 32'd0;
    else if (cs_state != ST_WAIT_PERIOD)
      r_period_cnt <= 32'd0;
    else if (r_period_cnt >= i_period_cycles)
      r_period_cnt <= 32'd0;
    else
      r_period_cnt <= r_period_cnt + 32'd1;
  end

  // 第三段 — symbol cursor
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      r_symbol <= '0;
    else if (cs_state == ST_WAIT_PERIOD && ns_state == ST_READ)
      r_symbol <= '0;
    else if (cs_state == ST_READ && i_rd_view_valid && r_rd_issued &&
             i_snap_skip_empty && w_view_empty && !w_is_last)
      r_symbol <= r_symbol + N_SYM_AW'(1);
    else if (cs_state == ST_PUSH && ns_state == ST_READ)
      r_symbol <= r_symbol + N_SYM_AW'(1);
  end

  // 第三段 — read issue + view capture
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_rd_issued  <= 1'b0;
      r_view       <= '0;
      r_push_valid <= 1'b0;
    end else begin
      if (cs_state != ST_READ)
        r_rd_issued <= 1'b0;
      else if (w_rd_fire)
        r_rd_issued <= 1'b1;
      else if (i_rd_view_valid && r_rd_issued &&
               i_snap_skip_empty && w_view_empty && !w_is_last)
        r_rd_issued <= 1'b0; // re-issue for next symbol

      if (cs_state == ST_READ && i_rd_view_valid && r_rd_issued) begin
        r_view <= i_rd_view;
        if (!(i_snap_skip_empty && w_view_empty))
          r_push_valid <= 1'b1;
      end

      if (cs_state == ST_PUSH)
        r_push_valid <= 1'b0;
      else if (cs_state == ST_IDLE || cs_state == ST_WAIT_PERIOD)
        r_push_valid <= 1'b0;
    end
  end

  // 第三段 — drop counter when PUSH sees !ready
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_drop_cnt   <= 32'd0;
      r_err_sticky <= 1'b0;
    end else if (cs_state == ST_PUSH && r_push_valid && !i_push_ready) begin
      if (r_drop_cnt != 32'hFFFF_FFFF)
        r_drop_cnt <= r_drop_cnt + 32'd1;
      r_err_sticky <= 1'b1;
    end
  end

  assign o_rd_valid    = (cs_state == ST_READ) && !r_rd_issued;
  assign o_rd_symbol   = r_symbol;
  assign o_push_valid  = (cs_state == ST_PUSH) && r_push_valid;
  assign o_push_symbol = r_symbol;
  assign o_push_view   = r_view;

  assign o_dbg_cs_state   = cs_state;
  assign o_dbg_drop_cnt   = r_drop_cnt;
  assign o_dbg_symbol     = r_symbol;
  assign o_dbg_err_sticky = r_err_sticky;

endmodule

`default_nettype wire
