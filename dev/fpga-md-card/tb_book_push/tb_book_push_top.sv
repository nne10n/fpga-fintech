// -----------------------------------------------------------------------------
// tb_book_push_top.sv — P2 harness for book_push_refill_top (make sim-book-push)
//
// CURRENT DUT:  u_dut = book_push_refill_tb_glue → u_dut.u_top = book_push_refill_top (REAL)
//   Hierarchy: u_dut.u_top.u_push (engine), u_refill, u_snap
//   Top exposes DDR CDC (o_ddr_req_*/i_ddr_rsp_*) + DMA AXIS (o_dma_valid/ready/msg),
//   NOT raw User AXI. Glue adapts flat cocotb ports ↔ top + AXI shell (m_axi AR/R).
//   A1–A5 LIVE NOW on glue AXI shell → axi_ddr_model (BIND_TO_AXI_SHELL semantics).
// Engine unit tests: tb_push/ (make sim-push) — leave alone; P2 target is top via glue.
// Obsolete: book_push_engine_stub.sv not in BOOK_PUSH_RTL (leftover; not DUT).
//
// Port map (flat cocotb ports → real top ports via glue):
//   clk/rst_n/clear          → sys_clk / sys_rst_n (+ TB clear)
//   rt_valid + flat rt_*     → i_rt_valid / i_rt_symbol / i_rt_row
//   csr_refill_kick/symbol/side → i_refill_req_valid / i_refill_req
//   csr_enable/skip/period   → i_snap_enable / i_snap_skip_empty / i_period_cycles
//   glue m_axi AR/R + b16_*  → o_ddr_req_* / i_ddr_rsp_*  (AXI shell for A1–A5)
//   push_valid/ready + push_* → o_dma_valid / i_dma_ready / o_dma_msg  (no o_dma_tlast on top)
//   csr_base_best16, outstanding_*, hot_path_stall → shell/L1 observe (not top ports)
// Flat cocotb port names are FROZEN (tests/helpers depend on them).
//
// Assert placement:
//   ON TOP (via glue observe): T-A7 flags one-hot, T-A8 no AW, PRI/SEQ/SKIP via CP3–CP5,
//                              T-A9 ASYNC=0; T-A6 LIVE hierarchical BIND on u_dut.u_top:
//                              i_rt_valid must not be gated by DDR rsp/req ready
//   AXI SHELL LIVE NOW (BIND_TO_AXI_SHELL): A1–A5 on u_dut m_axi_* → axi_ddr_model
// ASSERT_AXI locked from docs/p0-top10-axi-contract.md §3 (FROZEN 2026-09-04)
// Cover map: tb_book_push/COVERPOINTS.md
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module tb_book_push_top
  import book_pkg::*;
#(
  parameter int N_SYM = 32,   // sim; prod book_pkg::N_SYM=4096
  parameter int RTT   = 4,
  parameter int ASYNC = 0     // sim: sys_clk == ddr_clk
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        clear,

  input  logic        csr_enable,
  input  logic [31:0] csr_period_cycles,
  input  logic        csr_snap_skip_empty,
  input  logic [63:0] csr_base_best16,
  input  logic [15:0] csr_refill_symbol,
  input  logic [1:0]  csr_refill_side,
  input  logic        csr_refill_kick,

  input  logic [15:0] rt_symbol_id,
  input  logic [1:0]  rt_side,
  input  logic [3:0]  rt_level,
  input  logic [63:0] rt_px,
  input  logic [31:0] rt_qty,
  input  logic        rt_lvl_vld,
  input  logic [31:0] rt_seq,
  input  logic [63:0] rt_ts_ns,
  input  logic        rt_l1_may_have_more,
  input  logic        rt_dig_hole,
  input  logic        rt_valid,
  output logic        rt_ready,

  input  logic        b16_wr_en,
  input  logic [15:0] b16_symbol_id,
  input  logic [1:0]  b16_side,
  input  logic [3:0]  b16_slot,
  input  logic [63:0] b16_px,
  input  logic [31:0] b16_qty,
  input  logic        b16_vld,

  output logic        push_valid,
  input  logic        push_ready,
  output logic [15:0] push_symbol_id,
  output logic [63:0] push_ts_ns,
  output logic [31:0] push_seq,
  output logic [7:0]  push_flags,
  output logic [9:0]  push_bid_vld,
  output logic [9:0]  push_ask_vld,
  output logic [639:0] push_bid_px,
  output logic [319:0] push_bid_qty,
  output logic [639:0] push_ask_px,
  output logic [319:0] push_ask_qty,

  output logic [31:0] push_rt_cnt,
  output logic [31:0] push_timer_cnt,
  output logic [31:0] push_refill_cnt,
  output logic [31:0] refill_discard_cnt,
  output logic [31:0] refill_issue_cnt,
  output logic [31:0] drop_cnt,
  output logic [15:0] snap_next_id,
  output logic [3:0]  outstanding_refill,
  output logic [3:0]  outstanding_total,
  output logic        hot_path_stall,
  output logic [1:0]  last_grant,
  input  logic        l1_rmw_pri_hold,

  output logic [31:0] ddr_rd_cnt,
  output logic [31:0] ddr_wr_cnt,
  output logic        a_fail
);

  // Elab lock: §3 widths
  initial begin
    if (AXI_DATA_W != 512) $error("LOCK: AXI_DATA_W!=512");
    if (AXI_ADDR_W != 33)  $error("LOCK: AXI_ADDR_W!=33");
    if (AXI_MAX_OUTSTAND != 4) $error("LOCK: MAX_OUTSTAND!=4");
    if (AXI_ID_W != 4) $error("LOCK: ID_W!=4");
    if (TOP10_MSG_W != 2080) $error("LOCK: TOP10_MSG_W!=2080");
    if (TOP10_MSG_BYTES != 260) $error("LOCK: TOP10_MSG_BYTES!=260");
    if (BEST16_STRIDE_B != 512) $error("LOCK: STRIDE_SYM!=512");
  end

  logic [TOP10_MSG_W-1:0] push_msg_flat;

  logic [AXI_ID_W-1:0]   arid, rid, awid, bid;
  logic [AXI_ADDR_W-1:0] araddr, awaddr;
  logic [7:0]            arlen, awlen;
  logic [2:0]            arsize, awsize;
  logic [1:0]            arburst, awburst, rresp, bresp;
  logic                  arvalid, arready, rvalid, rready, rlast;
  logic                  awvalid, awready, wvalid, wready, wlast, bvalid, bready;
  logic [AXI_DATA_W-1:0] rdata, wdata;
  logic [AXI_DATA_W/8-1:0] wstrb;
  logic                  stub_awvalid, stub_wvalid, stub_bready;

  // CURRENT: u_dut = book_push_refill_tb_glue; u_dut.u_top = book_push_refill_top (REAL).
  // Engine = u_dut.u_top.u_push; refill = u_refill; snap = u_snap.
  // Glue: flat cocotb ports ↔ top + AXI shell (m_axi AR/R) for A1–A5.
  // Engine-only props → u_dut.u_top.u_push (tb_push/). Do not use bare book_push_engine as P2 DUT.
  book_push_refill_tb_glue #(.N_SYM(N_SYM)) u_dut (
    .clk(clk), .rst_n(rst_n), .clear(clear),
    .csr_enable(csr_enable),
    .csr_period_cycles(csr_period_cycles),
    .csr_snap_skip_empty(csr_snap_skip_empty),
    .csr_base_best16(csr_base_best16[AXI_ADDR_W-1:0]),
    .csr_refill_symbol(csr_refill_symbol),
    .csr_refill_side(csr_refill_side),
    .csr_refill_kick(csr_refill_kick),
    .rt_symbol_id(rt_symbol_id), .rt_side(rt_side), .rt_level(rt_level),
    .rt_px(rt_px), .rt_qty(rt_qty), .rt_lvl_vld(rt_lvl_vld),
    .rt_seq(rt_seq), .rt_ts_ns(rt_ts_ns),
    .rt_l1_may_have_more(rt_l1_may_have_more), .rt_dig_hole(rt_dig_hole),
    .rt_valid(rt_valid), .rt_ready(rt_ready),
    .b16_wr_en(b16_wr_en), .b16_symbol_id(b16_symbol_id), .b16_side(b16_side),
    .b16_slot(b16_slot), .b16_px(b16_px), .b16_qty(b16_qty), .b16_vld(b16_vld),
    .push_valid(push_valid), .push_ready(push_ready),
    .push_symbol_id(push_symbol_id), .push_ts_ns(push_ts_ns), .push_seq(push_seq),
    .push_flags(push_flags), .push_bid_vld(push_bid_vld), .push_ask_vld(push_ask_vld),
    .push_bid_px(push_bid_px), .push_bid_qty(push_bid_qty),
    .push_ask_px(push_ask_px), .push_ask_qty(push_ask_qty),
    .push_msg_flat(push_msg_flat),
    .push_rt_cnt(push_rt_cnt), .push_timer_cnt(push_timer_cnt),
    .push_refill_cnt(push_refill_cnt),
    .refill_discard_cnt(refill_discard_cnt), .refill_issue_cnt(refill_issue_cnt),
    .drop_cnt(drop_cnt), .snap_next_id(snap_next_id),
    .outstanding_total(outstanding_total), .outstanding_refill(outstanding_refill),
    .hot_path_stall(hot_path_stall), .last_grant(last_grant),
    .l1_rmw_pri_hold(l1_rmw_pri_hold),
    .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen),
    .m_axi_arsize(arsize), .m_axi_arburst(arburst),
    .m_axi_arvalid(arvalid), .m_axi_arready(arready),
    .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp),
    .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
    .m_axi_awvalid(stub_awvalid), .m_axi_wvalid(stub_wvalid),
    .m_axi_bready(stub_bready)
  );

  // Push path does NOT use User DDR AXI writes
  assign awid = '0;
  assign awaddr = '0;
  assign awlen = '0;
  assign awsize = 3'(AXI_SIZE_64B);
  assign awburst = 2'b01;
  assign awvalid = stub_awvalid;
  assign wvalid = stub_wvalid;
  assign wlast = 1'b0;
  assign wdata = '0;
  assign wstrb = '0;
  assign bready = stub_bready;

  axi_ddr_model #(
    .ADDR_W(AXI_ADDR_W), .DATA_W(AXI_DATA_W), .ID_W(AXI_ID_W), .RTT(RTT)
  ) u_ddr (
    .clk(clk), .rst_n(rst_n),
    .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen),
    .s_axi_awsize(awsize), .s_axi_awburst(awburst),
    .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wlast(wlast),
    .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bid(bid), .s_axi_bresp(bresp), .s_axi_bvalid(bvalid),
    .s_axi_bready(bready),
    .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen),
    .s_axi_arsize(arsize), .s_axi_arburst(arburst),
    .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rid(rid), .s_axi_rdata(rdata), .s_axi_rresp(rresp),
    .s_axi_rlast(rlast), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
    .rd_cnt(ddr_rd_cnt), .wr_cnt(ddr_wr_cnt)
  );

  // ===========================================================================
  // ASSERT_AXI — locked §3 + CDC iron laws (immediate)
  // On top (via glue): T-A7, T-A8, T-A9 (+ CP priority/seq/skip via tests)
  // T-A6: LIVE hierarchical BIND on u_dut.u_top — i_rt_valid never gated by
  //   DDR rsp/req ready (glue rt_ready=1 / hot_path_stall=0 are pulse semantics only)
  // A1–A5: LIVE NOW on glue AXI shell (u_dut m_axi_* → axi_ddr_model);
  //   still BIND_TO_AXI_SHELL semantics (top has no User AXI AW/AR ports)
  // ===========================================================================
  logic af;
  assign a_fail = af;

  // ---------------------------------------------------------------------------
  // T-A6 BIND on u_dut.u_top (hierarchical — no new RTL probe ports)
  // Property: when i_rt_valid rises while DDR is busy/blocked, RT is still
  // consumed within 1–2 cycles (o_tx_rt / o_drop_rt move, or RT presented on DMA).
  // Approximates "not combinationally AND-gated with ddr ready": RT can be high
  // and accepted while rsp stalled or req not ready.
  // ---------------------------------------------------------------------------
  wire        ta6_i_rt      = u_dut.u_top.i_rt_valid;
  wire        ta6_rsp_blk   = u_dut.u_top.o_ddr_rsp_ready && !u_dut.u_top.i_ddr_rsp_valid;
  wire        ta6_req_blk   = u_dut.u_top.o_ddr_req_valid && !u_dut.u_top.i_ddr_req_ready;
  wire        ta6_ddr_blk   = ta6_rsp_blk || ta6_req_blk;
  wire [31:0] ta6_tx_rt     = u_dut.u_top.u_push.o_tx_rt;
  wire [31:0] ta6_drop_rt   = u_dut.u_top.u_push.o_drop_rt;
  wire        ta6_rt_on_dma = push_valid && push_flags[0]; // F_TOP10_RT

  logic        ta6_armed;
  logic [1:0]  ta6_age;
  logic [31:0] ta6_tx0, ta6_drop0;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      af        <= 1'b0;
      ta6_armed <= 1'b0;
      ta6_age   <= 2'd0;
      ta6_tx0   <= '0;
      ta6_drop0 <= '0;
    end else begin
      // A1 arsize == $clog2(64)  [BIND_TO_AXI_SHELL — live on glue m_axi]
      if (arvalid && arready && (arsize != 3'(AXI_SIZE_64B))) begin
        af <= 1'b1;
        $error("ASSERT_AXI A1: arsize=%0d want %0d", arsize, AXI_SIZE_64B);
      end
      // A2 64B-aligned AR  [BIND_TO_AXI_SHELL — live on glue m_axi]
      if (arvalid && arready && (araddr[5:0] != 6'b0)) begin
        af <= 1'b1;
        $error("ASSERT_AXI A2: araddr 0x%0h not 64B aligned", araddr);
      end
      // A3 BASE_BEST16 + symbol*STRIDE_SYM; residual 0 or 256 (side)  [BIND_TO_AXI_SHELL — live]
      if (arvalid && arready) begin
        logic [63:0] off;
        off = 64'(araddr) - 64'(csr_base_best16[AXI_ADDR_W-1:0]);
        if (off[8:0] != 9'd0 && off[8:0] != 9'(BEST16_SIDE_B)) begin
          af <= 1'b1;
          $error("ASSERT_AXI A3: best16 residual=%0d (want 0 or 256)", off[8:0]);
        end
      end
      // A4 outstanding ≤ MAX_OUTSTAND  [BIND_TO_AXI_SHELL — live on glue]
      if (outstanding_total > 4'(AXI_MAX_OUTSTAND)) begin
        af <= 1'b1;
        $error("ASSERT_AXI A4: outstanding_total=%0d", outstanding_total);
      end
      // A5 refill QoS ≤ REFILL_MAX_OUTSTAND  [BIND_TO_AXI_SHELL — live on glue]
      if (outstanding_refill > 4'(REFILL_MAX_OUTSTAND)) begin
        af <= 1'b1;
        $error("ASSERT_AXI A5: outstanding_refill=%0d", outstanding_refill);
      end
      // A6 / T-A6: BIND on u_dut.u_top — i_rt_valid not gated by DDR rsp/req ready
      // (replaces vacuous !rt_ready || hot_path_stall sole check)
      if (ta6_i_rt && ta6_ddr_blk && !ta6_armed) begin
        ta6_armed <= 1'b1;
        ta6_age   <= 2'd0;
        ta6_tx0   <= ta6_tx_rt;
        ta6_drop0 <= ta6_drop_rt;
      end else if (ta6_armed) begin
        automatic logic ta6_prog;
        ta6_prog = (ta6_tx_rt != ta6_tx0) || (ta6_drop_rt != ta6_drop0) || ta6_rt_on_dma;
        if (ta6_prog) begin
          ta6_armed <= 1'b0;
        end else if (ta6_age >= 2'd2) begin
          af <= 1'b1;
          ta6_armed <= 1'b0;
          $error("ASSERT_AXI T-A6: i_rt_valid while DDR blocked but RT not consumed in 2 cycles (rsp_blk=%0b req_blk=%0b)",
                 ta6_rsp_blk, ta6_req_blk);
        end else begin
          ta6_age <= ta6_age + 2'd1;
        end
      end
      // A7 flags one-hot source on accepted push  [ON TOP / o_dma_msg via glue]
      if (push_valid && push_ready && ($countones(push_flags & 8'h07) != 1)) begin
        af <= 1'b1;
        $error("ASSERT_AXI A7: flags=0x%0h not one-hot", push_flags);
      end
      // A8 push must not drive User AXI AW (DMA ≠ DDR AXI)  [ON TOP]
      if (awvalid) begin
        af <= 1'b1;
        $error("ASSERT_AXI A8: unexpected AW from push path");
      end
      // A9 ASYNC=0 documented; dual-clock TB later
      if (ASYNC != 0) begin
        // placeholder
      end
    end
  end

  // BIND hierarchy (CURRENT):
  //   u_dut = book_push_refill_tb_glue; u_dut.u_top = book_push_refill_top (REAL)
  //   Engine-only → u_dut.u_top.u_push; refill → u_refill; snap → u_snap
  // BIND_TO_AXI_SHELL (A1–A5 LIVE on glue m_axi_*): outstanding, araddr align, arsize
  // BIND_TO_RTL (u_dut.u_top): flags one-hot; no AW; T-A6 LIVE — i_rt_valid never
  //   gated by ddr rsp/req ready (hierarchical; see ta6_* above)
  // BIND_TO_RTL (u_dut.u_top.u_push, engine-only / tb_push):
  //   (q_rt_pending && push_fire) |-> grant==RT; cmd_fifo_full |-> drop_cnt++
  // BIND_TO_AXI_SHELL: L1 bank RMW > refill AR; never feed m_axi_*ready to udp_strip

  logic unused_w;
  assign unused_w = ^{awready, wready, bvalid, bid, bresp, push_msg_flat[0], ASYNC[0]};

endmodule
