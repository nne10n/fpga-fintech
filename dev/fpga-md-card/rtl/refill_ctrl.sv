// -----------------------------------------------------------------------------
// refill_ctrl.sv — best16 refill bypass on sys_clk (seq gate + L0 Port-B write)
// SPEC: docs/book-push-refill-v2.md §4; docs/p1-parallel-partition.md §7
// SPEC: async FIFO to ddr_clk is OUTSIDE this module — expose handshake only
// Never stall hot path: req merge/drop; FIFO full → o_drop_cnt
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module refill_ctrl
  import book_pkg::*;
#(
  parameter int FIFO_DEPTH = 64
) (
  input  logic                sys_clk,
  input  logic                sys_rst_n,

  // Soft req from hot path / CSR (always accepted if merge possible)
  input  logic                i_req_valid,
  input  refill_req_t         i_req,

  // CDC/DDR side — async FIFO IP external (握手)
  output logic                o_ddr_req_valid,
  input  logic                i_ddr_req_ready,
  output refill_req_t         o_ddr_req,

  input  logic                i_ddr_rsp_valid,
  output logic                o_ddr_rsp_ready,
  input  refill_rsp_t         i_ddr_rsp,

  // L0 Port-B style read for seq gate / RMW (握手)
  output logic                o_l0_rd_valid,
  output logic [N_SYM_AW-1:0] o_l0_rd_symbol,
  input  logic                i_l0_rd_ready,
  input  top10_view_t         i_l0_rd_view,
  input  logic                i_l0_rd_view_valid,

  // L0 Port-B write (握手; nack → retry)
  output logic                o_l0_wr_valid,
  output logic [N_SYM_AW-1:0] o_l0_wr_symbol,
  output top10_view_t         o_l0_wr_view,
  input  logic                i_l0_wr_ready,
  input  logic                i_l0_wr_nack,

  // Push refill path (握手)
  output logic                o_push_valid,
  input  logic                i_push_ready,
  output logic [N_SYM_AW-1:0] o_push_symbol,
  output top10_view_t         o_push_view,

  (* keep = "true" *) output logic [3:0]  o_dbg_cs_state,
  (* keep = "true" *) output logic [15:0] o_dbg_fifo_depth,
  (* keep = "true" *) output logic [31:0] o_dbg_drop_cnt,
  (* keep = "true" *) output logic [31:0] o_dbg_stale_cnt,
  (* keep = "true" *) output logic        o_dbg_err_sticky
);

  localparam int AW = $clog2(FIFO_DEPTH);

  typedef enum logic [3:0] {
    ST_IDLE     = 4'd0,
    ST_ISSUE    = 4'd1,
    ST_WAIT_RSP = 4'd2,
    ST_RD_L0    = 4'd3,
    ST_CHK_SEQ  = 4'd4,
    ST_WR_L0    = 4'd5,
    ST_PUSH     = 4'd6
  } state_e;

  state_e cs_state;
  state_e ns_state;

  // Soft FIFO (same clock) — merge same symbol+side keep newest seq_start
  refill_req_t      q_mem [0:FIFO_DEPTH-1];
  logic             q_vld [0:FIFO_DEPTH-1];
  logic [AW:0]      r_q_wr;
  logic [AW:0]      r_q_rd;
  logic [AW:0]      r_q_count;
  logic [31:0]      r_drop_cnt;
  logic [31:0]      r_stale_cnt;
  logic             r_err_sticky;

  logic             w_q_found;
  logic [AW-1:0]    w_q_found_idx;
  logic             w_q_full;
  logic             w_q_empty;
  logic             w_q_pop;

  refill_req_t      r_active_req;
  refill_rsp_t      r_active_rsp;
  top10_view_t      r_l0_view;
  top10_view_t      r_wr_view;

  logic             r_ddr_req_valid;
  logic             r_l0_rd_valid;
  logic             r_l0_rd_issued;
  logic             r_l0_wr_valid;
  logic             r_push_valid;

  assign w_q_full  = (r_q_count == (AW+1)'(FIFO_DEPTH));
  assign w_q_empty = (r_q_count == '0);
  assign w_q_pop   = (cs_state == ST_IDLE) && !w_q_empty && (ns_state == ST_ISSUE);

  always_comb begin
    w_q_found     = 1'b0;
    w_q_found_idx = '0;
    for (int i = 0; i < FIFO_DEPTH; i++) begin
      if (q_vld[i] &&
          (q_mem[i].symbol_id == i_req.symbol_id) &&
          (q_mem[i].side == i_req.side)) begin
        w_q_found     = 1'b1;
        w_q_found_idx = AW'(i);
      end
    end
  end

  // -----------------------------------------------------------------------
  // 第一段
  // -----------------------------------------------------------------------
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      cs_state <= ST_IDLE;
    else
      cs_state <= ns_state;
  end

  // -----------------------------------------------------------------------
  // 第二段
  // -----------------------------------------------------------------------
  always_comb begin
    ns_state = cs_state;
    unique case (cs_state)
      ST_IDLE: begin
        if (!w_q_empty)
          ns_state = ST_ISSUE;
      end
      ST_ISSUE: begin
        if (r_ddr_req_valid && i_ddr_req_ready)
          ns_state = ST_WAIT_RSP;
      end
      ST_WAIT_RSP: begin
        if (i_ddr_rsp_valid)
          ns_state = ST_RD_L0;
      end
      ST_RD_L0: begin
        if (i_l0_rd_view_valid && r_l0_rd_issued)
          ns_state = ST_CHK_SEQ;
      end
      ST_CHK_SEQ: begin
        // SPEC: book-push-refill-v2.md §4.3 — L0.seq > seq_start → discard or reissue
        if (r_l0_view.seq > r_active_rsp.seq_start)
          ns_state = ST_ISSUE; // reissue with updated seq_start (stage-3)
        else
          ns_state = ST_WR_L0;
      end
      ST_WR_L0: begin
        if (i_l0_wr_nack)
          ns_state = ST_WR_L0; // retry
        else if (r_l0_wr_valid && i_l0_wr_ready)
          ns_state = ST_PUSH;
      end
      ST_PUSH: begin
        if (r_push_valid && i_push_ready)
          ns_state = ST_IDLE;
        else if (r_push_valid && !i_push_ready)
          ns_state = ST_IDLE; // drop push; L0 already written
      end
      default: ns_state = ST_IDLE;
    endcase
  end

  assign o_ddr_rsp_ready = (cs_state == ST_WAIT_RSP);

  // -----------------------------------------------------------------------
  // 第三段 — soft FIFO enqueue (never stall)
  // -----------------------------------------------------------------------
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_q_wr    <= '0;
      r_q_rd    <= '0;
      r_q_count <= '0;
      r_drop_cnt <= 32'd0;
      for (int i = 0; i < FIFO_DEPTH; i++) begin
        q_vld[i] <= 1'b0;
        q_mem[i] <= '0;
      end
    end else begin
      automatic logic [AW:0] c;
      automatic logic [AW:0] rd;
      automatic logic [AW:0] wr;
      c  = r_q_count;
      rd = r_q_rd;
      wr = r_q_wr;
      if (w_q_pop) begin
        q_vld[rd[AW-1:0]] <= 1'b0;
        rd = rd + (AW+1)'(1);
        c  = c - (AW+1)'(1);
      end
      if (i_req_valid) begin
        if (w_q_found && !(w_q_pop && (w_q_found_idx == r_q_rd[AW-1:0]))) begin
          q_mem[w_q_found_idx] <= i_req; // keep newest seq_start
          q_vld[w_q_found_idx] <= 1'b1;
        end else if (c != (AW+1)'(FIFO_DEPTH)) begin
          q_mem[wr[AW-1:0]] <= i_req;
          q_vld[wr[AW-1:0]] <= 1'b1;
          wr = wr + (AW+1)'(1);
          c  = c + (AW+1)'(1);
        end else begin
          if (r_drop_cnt != 32'hFFFF_FFFF)
            r_drop_cnt <= r_drop_cnt + 32'd1;
        end
      end
      r_q_rd    <= rd;
      r_q_wr    <= wr;
      r_q_count <= c;
    end
  end

  // 第三段 — active req/rsp + views
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_active_req <= '0;
      r_active_rsp <= '0;
      r_l0_view    <= '0;
      r_wr_view    <= '0;
    end else begin
      if (w_q_pop)
        r_active_req <= q_mem[r_q_rd[AW-1:0]];
      if (cs_state == ST_CHK_SEQ && (r_l0_view.seq > r_active_rsp.seq_start)) begin
        r_active_req.seq_start <= r_l0_view.seq;
        r_active_rsp.seq_start <= r_l0_view.seq;
      end
      if (cs_state == ST_WAIT_RSP && i_ddr_rsp_valid)
        r_active_rsp <= i_ddr_rsp;
      if (cs_state == ST_RD_L0 && i_l0_rd_view_valid && r_l0_rd_issued) begin
        r_l0_view <= i_l0_rd_view;
        r_wr_view <= top10_apply_refill_side(
            i_l0_rd_view,
            r_active_rsp.side,
            r_active_rsp.lvl_vld,
            r_active_rsp.lvl_px,
            r_active_rsp.lvl_qty);
      end
    end
  end

  // 第三段 — DDR req valid
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      r_ddr_req_valid <= 1'b0;
    else if (cs_state == ST_ISSUE) begin
      if (r_ddr_req_valid && i_ddr_req_ready)
        r_ddr_req_valid <= 1'b0;
      else
        r_ddr_req_valid <= 1'b1;
    end else
      r_ddr_req_valid <= 1'b0;
  end

  // 第三段 — L0 read issue
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_l0_rd_valid  <= 1'b0;
      r_l0_rd_issued <= 1'b0;
    end else if (cs_state != ST_RD_L0) begin
      r_l0_rd_valid  <= 1'b0;
      r_l0_rd_issued <= 1'b0;
    end else begin
      if (r_l0_rd_valid && i_l0_rd_ready) begin
        r_l0_rd_valid  <= 1'b0;
        r_l0_rd_issued <= 1'b1;
      end else if (!r_l0_rd_issued)
        r_l0_rd_valid <= 1'b1;
    end
  end

  // 第三段 — L0 write + push
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_l0_wr_valid <= 1'b0;
      r_push_valid  <= 1'b0;
    end else begin
      if (cs_state == ST_WR_L0) begin
        if (i_l0_wr_nack)
          r_l0_wr_valid <= 1'b1; // retry
        else if (r_l0_wr_valid && i_l0_wr_ready)
          r_l0_wr_valid <= 1'b0;
        else
          r_l0_wr_valid <= 1'b1;
      end else
        r_l0_wr_valid <= 1'b0;

      if (cs_state == ST_WR_L0 && r_l0_wr_valid && i_l0_wr_ready && !i_l0_wr_nack)
        r_push_valid <= 1'b1;
      else if (cs_state == ST_PUSH && (i_push_ready || !i_push_ready))
        r_push_valid <= 1'b0;
      else if (cs_state == ST_IDLE)
        r_push_valid <= 1'b0;
    end
  end

  // 第三段 — stale / sticky
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_stale_cnt  <= 32'd0;
      r_err_sticky <= 1'b0;
    end else begin
      if (cs_state == ST_CHK_SEQ && (r_l0_view.seq > r_active_rsp.seq_start)) begin
        if (r_stale_cnt != 32'hFFFF_FFFF)
          r_stale_cnt <= r_stale_cnt + 32'd1;
        r_err_sticky <= 1'b1;
      end
      if (|r_drop_cnt)
        r_err_sticky <= 1'b1;
    end
  end

  assign o_ddr_req_valid = r_ddr_req_valid;
  assign o_ddr_req       = r_active_req;

  assign o_l0_rd_valid  = r_l0_rd_valid;
  assign o_l0_rd_symbol = r_active_rsp.symbol_id[N_SYM_AW-1:0];

  assign o_l0_wr_valid  = r_l0_wr_valid;
  assign o_l0_wr_symbol = r_active_rsp.symbol_id[N_SYM_AW-1:0];
  assign o_l0_wr_view   = r_wr_view;

  assign o_push_valid  = r_push_valid && (cs_state == ST_PUSH);
  assign o_push_symbol = r_active_rsp.symbol_id[N_SYM_AW-1:0];
  assign o_push_view   = r_wr_view;

  assign o_dbg_cs_state   = cs_state;
  assign o_dbg_fifo_depth = 16'(r_q_count);
  assign o_dbg_drop_cnt   = r_drop_cnt;
  assign o_dbg_stale_cnt  = r_stale_cnt;
  assign o_dbg_err_sticky = r_err_sticky;

endmodule

`default_nettype wire
