// -----------------------------------------------------------------------------
// book_engine.sv — L0 hot Top-10 + L1 fork (stub or DDR engine)
//
// USE_L1_DDR=0 (default): l1_cmd_stub — keeps legacy sim-book / x1100 green
// USE_L1_DDR=1: l1_ddr_engine + internal axi_ddr_model (no board FDK)
// USE_BOOK_PUSH=0 (default): export RT/refill hooks only; no push top
// USE_BOOK_PUSH=1: instantiate book_push_refill_top (DDR CDC stub; DMA sink)
// When L1 not ready: drop cmd (engine drop_cnt++); NEVER backpressure decode
// P1.4: L0 delta → o_rt_* pulse; dig-hole → soft o_refill_req_* (no decode BP)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

module book_engine
  import md_pkg::*;
  import book_pkg::*;
#(
  parameter int N_H             = N_HOT,
  parameter bit USE_L1_DDR      = 1'b0,
  parameter int L1_BANK_FIFO    = 64,
  parameter int L1_RTT          = 8,
  // P1.4 gated push/refill (default off → sim-book / x1100 unchanged)
  parameter bit USE_BOOK_PUSH   = 1'b0,
  parameter int PUSH_N_SYM      = 64,   // light N for smoke; full N_SYM later
  parameter int PUSH_DEPTH_RF   = 64,
  parameter int PUSH_DEPTH_SNAP = 64
) (
  input  logic         clk,
  input  logic         rst_n,

  input  logic [511:0] s_event_tdata,
  input  logic         s_event_tvalid,
  input  logic         s_event_tlast,
  output logic         s_event_tready,
  input  logic [47:0]  s_code,

  output logic [511:0] m_bypass_tdata,
  output logic         m_bypass_tvalid,
  output logic         m_bypass_tlast,
  input  logic         m_bypass_tready,

  output book_delta_t  m_delta,
  output logic         m_delta_valid,
  input  logic         m_delta_ready,

  input  logic              hot_we,
  input  logic [HOT_AW-1:0] hot_addr,
  input  logic [47:0]       hot_code,
  input  logic              hot_entry_valid,
  input  logic              book_clear,

  output logic [31:0]  l1_push_cnt,
  output logic [31:0]  hot_hit_cnt,
  output logic [31:0]  hot_miss_cnt,
  output logic [31:0]  delta_cnt,

  input  logic [HOT_AW:0] dbg_hot_id,
  input  logic [1:0]      dbg_side,
  output level_t          dbg_lvl0,
  output level_t          dbg_lvl1,
  output level_t          dbg_lvl2,
  output level_t          dbg_lvl3,
  output level_t          dbg_lvl4,
  output level_t          dbg_lvl5,
  output level_t          dbg_lvl6,
  output level_t          dbg_lvl7,
  output level_t          dbg_lvl8,
  output level_t          dbg_lvl9,

  // P1.4 hooks (always driven). Interim symbol_id = hot_id-1 until code→id map.
  output logic                o_rt_valid,
  output logic [N_SYM_AW-1:0] o_rt_symbol,
  output l0_top10_row_t       o_rt_row,
  output logic                o_refill_req_valid,
  output refill_req_t         o_refill_req,

  // Optional DMA observe when USE_BOOK_PUSH=1 (else tied 0)
  // Caller must NOT feed i_push_dma_ready into decode/udp_strip.
  output logic            o_push_dma_valid,
  output top10_msg_t      o_push_dma_msg,
  input  logic            i_push_dma_ready,
  output logic [31:0]     o_push_tx_rt
);

  assign s_event_tready = 1'b1;

  logic unused_tlast;
  assign unused_tlast = s_event_tlast;

  logic            cam_hit;
  logic [HOT_AW:0] cam_hid;

  hot_cam #(.N(N_H)) u_hot (
    .clk(clk), .rst_n(rst_n),
    .hot_we(hot_we), .hot_addr(hot_addr),
    .hot_code(hot_code), .hot_entry_valid(hot_entry_valid),
    .clear(book_clear),
    .s_code(s_code), .hit(cam_hit), .hot_id(cam_hid)
  );

  logic [511:0] byp_data_q;
  logic         byp_valid_q;
  assign m_bypass_tdata  = byp_data_q;
  assign m_bypass_tvalid = byp_valid_q;
  assign m_bypass_tlast  = 1'b1;

  wire byp_fire = byp_valid_q && m_bypass_tready;

  l1_cmd_t l1_cmd;
  logic    l1_valid;
  logic    l1_ready;
  logic [31:0] l1_drop;
  logic [31:0] l1_done, l1_err, l1_hwm;
  l1_cmd_t l1_last;
  logic    l1_last_v;

  generate
    if (USE_L1_DDR) begin : g_l1_ddr
      logic [3:0]  awid, arid, bid, rid;
      logic [32:0] awaddr, araddr;
      logic [7:0]  awlen, arlen;
      logic [2:0]  awsize, arsize;
      logic [1:0]  awburst, arburst, bresp, rresp;
      logic        awvalid, awready, wvalid, wready, bvalid, bready;
      logic        arvalid, arready, rvalid, rready, wlast, rlast;
      logic [511:0] wdata, rdata;
      logic [63:0]  wstrb;
      logic         repair_v;
      book_delta_t  repair_d;
      logic [31:0]  ddr_rd_unused, ddr_wr_unused;

      l1_ddr_engine #(
        .N_BANK(4),
        .BANK_FIFO_D(L1_BANK_FIFO),
        .MAX_OUTSTAND(4),
        .ASYNC(0)
      ) u_l1 (
        .clk(clk), .rst_n(rst_n), .clear(book_clear),
        .s_cmd(l1_cmd), .s_valid(l1_valid), .s_ready(l1_ready),
        .push_cnt(l1_push_cnt), .drop_cnt(l1_drop),
        .done_cnt(l1_done), .err_cnt(l1_err), .high_watermark(l1_hwm),
        .repair_valid(repair_v), .repair_delta(repair_d),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen),
        .m_axi_awsize(awsize), .m_axi_awburst(awburst),
        .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid),
        .m_axi_bready(bready),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen),
        .m_axi_arsize(arsize), .m_axi_arburst(arburst),
        .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp),
        .m_axi_rlast(rlast), .m_axi_rvalid(rvalid), .m_axi_rready(rready)
      );

      axi_ddr_model #(.ADDR_W(33), .DATA_W(512), .ID_W(4), .RTT(L1_RTT)) u_ddr (
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
        .rd_cnt(ddr_rd_unused), .wr_cnt(ddr_wr_unused)
      );

      assign l1_last   = '0;
      assign l1_last_v = 1'b0;
      logic unused_rep;
      assign unused_rep = ^{repair_v, repair_d};
    end else begin : g_l1_stub
      l1_cmd_stub u_l1 (
        .clk(clk), .rst_n(rst_n), .clear(book_clear),
        .s_cmd(l1_cmd), .s_valid(l1_valid), .s_ready(l1_ready),
        .push_cnt(l1_push_cnt), .drop_cnt(l1_drop),
        .last_cmd(l1_last), .last_valid(l1_last_v)
      );
      assign l1_done = '0;
      assign l1_err  = '0;
      assign l1_hwm  = '0;
    end
  endgenerate

  logic            oc_valid;
  book_op_e        oc_op;
  logic [63:0]     oc_oid;
  logic [HOT_AW:0] oc_hid;
  logic [1:0]      oc_side;
  logic [63:0]     oc_px;
  logic [31:0]     oc_qty;
  logic [31:0]     oc_seq;
  logic [63:0]     oc_ts;
  logic            oc_ready;

  book_delta_t     oc_delta;
  logic            oc_delta_v;

  logic            oc_rt_v;
  logic [HOT_AW:0] oc_rt_hid;
  l0_top10_row_t   oc_rt_row;
  logic            oc_dig_v;
  logic [1:0]      oc_dig_side;
  logic [3:0]      oc_dig_depth;

  order_cache u_oc (
    .clk(clk), .rst_n(rst_n), .clear(book_clear),
    .cmd_valid(oc_valid), .cmd_op(oc_op), .cmd_order_id(oc_oid),
    .cmd_hot_id(oc_hid), .cmd_side(oc_side), .cmd_px(oc_px),
    .cmd_qty(oc_qty), .cmd_seq(oc_seq), .cmd_ts(oc_ts),
    .cmd_ready(oc_ready),
    .m_delta(oc_delta), .m_delta_valid(oc_delta_v),
    .m_delta_ready(m_delta_ready || !m_delta_valid),
    .dbg_hot_id(dbg_hot_id), .dbg_side(dbg_side),
    .dbg_lvl0(dbg_lvl0), .dbg_lvl1(dbg_lvl1), .dbg_lvl2(dbg_lvl2),
    .dbg_lvl3(dbg_lvl3), .dbg_lvl4(dbg_lvl4), .dbg_lvl5(dbg_lvl5),
    .dbg_lvl6(dbg_lvl6), .dbg_lvl7(dbg_lvl7), .dbg_lvl8(dbg_lvl8),
    .dbg_lvl9(dbg_lvl9),
    .m_rt_valid(oc_rt_v), .m_rt_hot_id(oc_rt_hid), .m_rt_row(oc_rt_row),
    .m_dig_hole(oc_dig_v), .m_dig_side(oc_dig_side), .m_dig_depth(oc_dig_depth)
  );

  // Map hot_id (1..N_H) → symbol index 0..N_H-1 for push/refill hooks
  wire [N_SYM_AW-1:0] w_rt_sym =
      (oc_rt_hid >= (HOT_AW+1)'(1)) ? N_SYM_AW'(oc_rt_hid - 1'b1) : '0;

  assign o_rt_valid  = oc_rt_v;
  assign o_rt_symbol = w_rt_sym;
  assign o_rt_row    = oc_rt_row;

  // Soft refill on dig-hole (l1_may_have_more assumed 1 until L1 best16 ready)
  refill_req_t w_refill_req;
  always_comb begin
    w_refill_req = '0;
    w_refill_req.symbol_id = 16'(w_rt_sym);
    w_refill_req.side      = oc_dig_side;
    w_refill_req.seq_start = oc_rt_row.seq;
  end
  assign o_refill_req_valid = oc_dig_v;
  assign o_refill_req       = w_refill_req;

  book_delta_t delta_q;
  logic        delta_v_q;
  logic [31:0] delta_c_q, hit_c_q, miss_c_q;

  assign m_delta       = delta_q;
  assign m_delta_valid = delta_v_q;
  assign hot_hit_cnt   = hit_c_q;
  assign hot_miss_cnt  = miss_c_q;
  assign delta_cnt     = delta_c_q;

  function automatic logic [31:0] sat_inc(input logic [31:0] c);
    return (c == 32'hFFFF_FFFF) ? c : (c + 32'd1);
  endfunction

  event_t   ein;
  book_op_e op_dec;
  logic     is_ot;

  always_comb begin
    ein    = event_t'(s_event_tdata);
    op_dec = decode_book_op(ein);
    is_ot  = (op_dec == OP_ADD || op_dec == OP_CXL || op_dec == OP_TRADE);

    l1_cmd   = '0;
    l1_valid = 1'b0;
    oc_valid = 1'b0;
    oc_op    = OP_NOP;
    oc_oid   = '0;
    oc_hid   = '0;
    oc_side  = '0;
    oc_px    = '0;
    oc_qty   = '0;
    oc_seq   = '0;
    oc_ts    = '0;

    if (s_event_tvalid && is_ot) begin
      // Always present L1 cmd; if !l1_ready engine drops (never stall here)
      l1_cmd.op       = op_dec;
      l1_cmd.order_id = ein.order_id;
      l1_cmd.hot_id   = cam_hit ? cam_hid : '0;
      l1_cmd.code     = s_code;
      l1_cmd.side     = ein.side;
      l1_cmd.px       = ein.px;
      l1_cmd.qty      = ein.qty;
      l1_cmd.seq      = ein.seq;
      l1_cmd.ts_ns    = ein.ts_ns;
      l1_valid        = 1'b1;

      if (cam_hit) begin
        oc_valid = 1'b1;
        oc_op    = op_dec;
        oc_oid   = ein.order_id;
        oc_hid   = cam_hid;
        oc_side  = ein.side;
        oc_px    = ein.px;
        oc_qty   = ein.qty;
        oc_seq   = ein.seq;
        oc_ts    = ein.ts_ns;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      byp_data_q  <= '0;
      byp_valid_q <= 1'b0;
      delta_q     <= '0;
      delta_v_q   <= 1'b0;
      delta_c_q   <= '0;
      hit_c_q     <= '0;
      miss_c_q    <= '0;
    end else begin
      if (byp_fire)
        byp_valid_q <= 1'b0;
      if (s_event_tvalid) begin
        byp_data_q  <= s_event_tdata;
        byp_valid_q <= 1'b1;
        if (is_ot) begin
          if (cam_hit)
            hit_c_q <= sat_inc(hit_c_q);
          else
            miss_c_q <= sat_inc(miss_c_q);
        end
      end

      if (m_delta_ready && delta_v_q)
        delta_v_q <= 1'b0;
      if (oc_delta_v) begin
        delta_q   <= oc_delta;
        delta_v_q <= 1'b1;
        delta_c_q <= sat_inc(delta_c_q);
      end

      if (book_clear) begin
        hit_c_q     <= '0;
        miss_c_q    <= '0;
        delta_c_q   <= '0;
        delta_v_q   <= 1'b0;
        byp_valid_q <= 1'b0;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // P1.4: gated book_push_refill_top
  // - Hot Port-A write mirrors RT row into l0_top10_mem (same view as push)
  // - DDR CDC stubbed (ready=1, no rsp) until best16 AXI shell
  // - DMA sink always ready internally (iron rule); i_push_dma_ready observe-only
  // ---------------------------------------------------------------------------
  generate
    if (USE_BOOK_PUSH) begin : g_book_push
      logic          w_dma_v;
      top10_msg_t    w_dma_msg;
      logic          w_ddr_req_v, w_ddr_rsp_r;
      refill_req_t   w_ddr_req;
      logic          w_err_nc;
      logic [31:0]   w_conf_nc;
      logic [2:0]    w_snap_cs_nc, w_grant_nc;
      logic [3:0]    w_rf_cs_nc;
      l0_top10_row_t w_hot_rd_nc;
      logic          w_hot_rv_nc;
      logic [31:0]   r_tx_rt;

      book_push_refill_top #(
        .N_SYM_P     (PUSH_N_SYM),
        .DEPTH_REFILL(PUSH_DEPTH_RF),
        .DEPTH_SNAP  (PUSH_DEPTH_SNAP)
      ) u_push_top (
        .sys_clk            (clk),
        .sys_rst_n          (rst_n),
        // Mirror RT row into L0 mem Port-A (same cycle as push_q_rt)
        .i_hot_upd_req      (oc_rt_v),
        .i_hot_upd_we       (1'b1),
        .i_hot_upd_symbol   (w_rt_sym),
        .i_hot_upd_wdata    (oc_rt_row),
        .o_hot_upd_rdata    (w_hot_rd_nc),
        .o_hot_upd_rvalid   (w_hot_rv_nc),
        .i_rt_valid         (oc_rt_v),
        .i_rt_symbol        (w_rt_sym),
        .i_rt_row           (oc_rt_row),
        .i_refill_req_valid (oc_dig_v),
        .i_refill_req       (w_refill_req),
        .i_snap_enable      (1'b0),
        .i_snap_skip_empty  (1'b1),
        .i_period_cycles    (32'd3_222_656),
        // DDR CDC stub: accept reqs, never return rsp
        .o_ddr_req_valid    (w_ddr_req_v),
        .i_ddr_req_ready    (1'b1),
        .o_ddr_req          (w_ddr_req),
        .i_ddr_rsp_valid    (1'b0),
        .o_ddr_rsp_ready    (w_ddr_rsp_r),
        .i_ddr_rsp          ('0),
        // DMA: always ready — NEVER gate decode; expose for observe
        .o_dma_valid        (w_dma_v),
        .i_dma_ready        (1'b1),
        .o_dma_msg          (w_dma_msg),
        .o_dbg_err_sticky   (w_err_nc),
        .o_dbg_mem_conflict_cnt(w_conf_nc),
        .o_dbg_snap_cs      (w_snap_cs_nc),
        .o_dbg_refill_cs    (w_rf_cs_nc),
        .o_dbg_push_grant   (w_grant_nc)
      );

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || book_clear)
          r_tx_rt <= '0;
        else if (w_dma_v)
          r_tx_rt <= sat_inc(r_tx_rt);
      end

      assign o_push_dma_valid = w_dma_v;
      assign o_push_dma_msg   = w_dma_msg;
      assign o_push_tx_rt     = r_tx_rt;

      logic unused_push;
      assign unused_push = ^{w_ddr_req_v, w_ddr_req, w_ddr_rsp_r, w_hot_rv_nc,
                             w_hot_rd_nc, w_err_nc, w_conf_nc, w_snap_cs_nc,
                             w_rf_cs_nc, w_grant_nc, i_push_dma_ready};
    end else begin : g_no_book_push
      assign o_push_dma_valid = 1'b0;
      assign o_push_dma_msg   = '0;
      assign o_push_tx_rt     = 32'd0;
      logic unused_ready;
      assign unused_ready = i_push_dma_ready;
    end
  endgenerate

  logic unused_tie;
  assign unused_tie = ^{l1_ready, oc_ready, l1_drop, l1_last_v, l1_last,
                        l1_done, l1_err, l1_hwm, oc_dig_depth};

endmodule
