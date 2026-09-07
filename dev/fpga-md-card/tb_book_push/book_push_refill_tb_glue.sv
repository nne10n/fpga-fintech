`timescale 1ns / 1ps
// TB-only glue: flat P2 ports ↔ book_push_refill_top (+ AXI shell for A1–A5)
// Note: AXI shell (m_axi AR/R) for A1–A5.
// T-A6 lives in harness hierarchical BIND on u_dut.u_top (tb_book_push_top.sv):
//   i_rt_valid must not be gated by DDR rsp/req ready.
// rt_ready=1 is pulse semantics (top has no RT backpressure); hot_path_stall=0 by
// construction for legal RTL — harness A6 no longer uses these as the sole check.
`default_nettype none

module book_push_refill_tb_glue
  import book_pkg::*;
#(
  parameter int N_SYM_TB = 32,
  parameter int N_SYM = N_SYM_TB,
  parameter int REFILL_MAX_OS = REFILL_MAX_OUTSTAND,
  parameter int AXI_ADDR_W_P = AXI_ADDR_W,
  parameter int AXI_DATA_W_P = AXI_DATA_W,
  parameter int AXI_ID_W_P = AXI_ID_W
) (
  input  logic clk, rst_n, clear,
  input  logic csr_enable,
  input  logic [31:0] csr_period_cycles,
  input  logic csr_snap_skip_empty,
  input  logic [AXI_ADDR_W_P-1:0] csr_base_best16,
  input  logic [15:0] csr_refill_symbol,
  input  logic [1:0]  csr_refill_side,
  input  logic csr_refill_kick,
  input  logic [15:0] rt_symbol_id,
  input  logic [1:0]  rt_side,
  input  logic [3:0]  rt_level,
  input  logic [63:0] rt_px,
  input  logic [31:0] rt_qty,
  input  logic rt_lvl_vld,
  input  logic [31:0] rt_seq,
  input  logic [63:0] rt_ts_ns,
  input  logic rt_l1_may_have_more,
  input  logic rt_dig_hole,
  input  logic rt_valid,
  output logic rt_ready,
  input  logic b16_wr_en,
  input  logic [15:0] b16_symbol_id,
  input  logic [1:0]  b16_side,
  input  logic [3:0]  b16_slot,
  input  logic [63:0] b16_px,
  input  logic [31:0] b16_qty,
  input  logic b16_vld,
  output logic push_valid,
  input  logic push_ready,
  output logic [15:0] push_symbol_id,
  output logic [63:0] push_ts_ns,
  output logic [31:0] push_seq,
  output logic [7:0]  push_flags,
  output logic [9:0]  push_bid_vld, push_ask_vld,
  output logic [639:0] push_bid_px, push_ask_px,
  output logic [319:0] push_bid_qty, push_ask_qty,
  output logic [TOP10_MSG_W-1:0] push_msg_flat,
  output logic [31:0] push_rt_cnt, push_timer_cnt, push_refill_cnt,
  output logic [31:0] refill_discard_cnt, refill_issue_cnt, drop_cnt,
  output logic [15:0] snap_next_id,
  output logic [3:0]  outstanding_total, outstanding_refill,
  output logic hot_path_stall,
  output logic [1:0] last_grant,
  input  logic l1_rmw_pri_hold,
  output logic [AXI_ID_W_P-1:0] m_axi_arid,
  output logic [AXI_ADDR_W_P-1:0] m_axi_araddr,
  output logic [7:0] m_axi_arlen,
  output logic [2:0] m_axi_arsize,
  output logic [1:0] m_axi_arburst,
  output logic m_axi_arvalid,
  input  logic m_axi_arready,
  input  logic [AXI_ID_W_P-1:0] m_axi_rid,
  input  logic [AXI_DATA_W_P-1:0] m_axi_rdata,
  input  logic [1:0] m_axi_rresp,
  input  logic m_axi_rlast, m_axi_rvalid,
  output logic m_axi_rready, m_axi_awvalid, m_axi_wvalid, m_axi_bready
);

  logic [31:0] l0_seq [0:N_SYM-1];
  logic [63:0] l0_ts  [0:N_SYM-1];
  logic bid_v [0:N_SYM-1][0:9]; logic [63:0] bid_p [0:N_SYM-1][0:9]; logic [31:0] bid_q [0:N_SYM-1][0:9];
  logic ask_v [0:N_SYM-1][0:9]; logic [63:0] ask_p [0:N_SYM-1][0:9]; logic [31:0] ask_q [0:N_SYM-1][0:9];
  logic b16_v [0:N_SYM-1][0:1][0:15]; logic [63:0] b16_p [0:N_SYM-1][0:1][0:15]; logic [31:0] b16_q [0:N_SYM-1][0:1][0:15];

  function automatic logic [AXI_ADDR_W_P-1:0] side_addr(input logic [15:0] sid, input logic [1:0] side);
    logic [63:0] a;
    a = best16_addr(64'(csr_base_best16), sid[N_SYM_AW-1:0], (side==SIDE_ASK), 4'd0);
    a[5:0]=6'b0; return AXI_ADDR_W_P'(a);
  endfunction

  // Combinational post-update row for current rt_valid beat
  function automatic l0_top10_row_t row_after_rt();
    l0_top10_row_t row;
    logic [9:0] bv, av;
    logic [639:0] bpx, apx; logic [319:0] bqy, aqy;
    int sid;
    sid = int'(rt_symbol_id);
    bv='0; av='0; bpx='0; apx='0; bqy='0; aqy='0; row='0;
    if (sid < N_SYM) begin
      for (int i=0;i<10;i++) begin
        automatic logic bb, aa;
        automatic logic [63:0] bp, ap; automatic logic [31:0] bq, aq;
        bb = bid_v[sid][i]; bp = bid_p[sid][i]; bq = bid_q[sid][i];
        aa = ask_v[sid][i]; ap = ask_p[sid][i]; aq = ask_q[sid][i];
        if (rt_dig_hole) begin
          if (rt_side==SIDE_BID && i>=int'(rt_level)) bb=0;
          if (rt_side==SIDE_ASK && i>=int'(rt_level)) aa=0;
        end else if (i==int'(rt_level) && rt_level<4'd10) begin
          if (rt_side==SIDE_BID) begin bb=rt_lvl_vld; bp=rt_px; bq=rt_qty; end
          else begin aa=rt_lvl_vld; ap=rt_px; aq=rt_qty; end
        end
        bv[i]=bb; av[i]=aa;
        bpx[i*64+:64]=bp; apx[i*64+:64]=ap;
        bqy[i*32+:32]=bq; aqy[i*32+:32]=aq;
      end
      row.seq=rt_seq; row.ts_ns=rt_ts_ns;
      row.bid_vld=bv; row.ask_vld=av;
      row.bid_px=bpx; row.ask_px=apx;
      row.bid_qty=bqy; row.ask_qty=aqy;
      row.nonempty=(bv!='0)||(av!='0);
    end
    return row;
  endfunction

  function automatic int depth_after_rt();
    int d, sid;
    sid = int'(rt_symbol_id); d=0;
    if (rt_dig_hole) return int'(rt_level);
    if (rt_side==SIDE_BID) begin
      for (int i=0;i<10;i++) begin
        if (i==int'(rt_level)) begin if (rt_lvl_vld) d++; end
        else if (sid<N_SYM && bid_v[sid][i]) d++;
      end
    end else begin
      for (int i=0;i<10;i++) begin
        if (i==int'(rt_level)) begin if (rt_lvl_vld) d++; end
        else if (sid<N_SYM && ask_v[sid][i]) d++;
      end
    end
    return d;
  endfunction

  l0_top10_row_t w_row_now;
  logic          w_need_refill;
  assign w_row_now = row_after_rt();
  assign w_need_refill = rt_valid && (depth_after_rt() < 10) && rt_l1_may_have_more;

  logic                w_hot_req, w_hot_we, w_rt_v, w_rf_v;
  logic [N_SYM_AW-1:0] w_hot_sym, w_rt_sym;
  l0_top10_row_t       w_hot_wdata, w_rt_row;
  refill_req_t         w_rf_req;
  l0_top10_row_t       w_hot_rdata_nc;
  logic                w_hot_rvalid_nc;

  // Same-cycle pulses into top (matches stub timing for preempt tests)
  always_comb begin
    w_hot_req=0; w_hot_we=0; w_rt_v=0; w_rf_v=0;
    w_hot_sym='0; w_rt_sym='0; w_hot_wdata='0; w_rt_row='0; w_rf_req='0;
    if (rt_valid && int'(rt_symbol_id)<N_SYM) begin
      w_hot_req=1; w_hot_we=1;
      w_hot_sym=N_SYM_AW'(rt_symbol_id);
      w_hot_wdata=w_row_now;
      w_rt_v=1; w_rt_sym=N_SYM_AW'(rt_symbol_id); w_rt_row=w_row_now;
      if (w_need_refill) begin
        w_rf_v=1;
        w_rf_req.symbol_id=rt_symbol_id;
        w_rf_req.side=rt_side;
        w_rf_req.seq_start=rt_seq;
      end
    end else if (csr_refill_kick && int'(csr_refill_symbol)<N_SYM) begin
      w_rf_v=1;
      w_rf_req.symbol_id=csr_refill_symbol;
      w_rf_req.side=csr_refill_side;
      w_rf_req.seq_start=l0_seq[csr_refill_symbol];
    end
  end

  logic w_ddr_req_v, w_ddr_req_r, w_ddr_rsp_v, w_ddr_rsp_r;
  refill_req_t w_ddr_req; refill_rsp_t w_ddr_rsp;
  logic w_dma_v; top10_msg_t w_dma_msg;
  logic w_err_nc; logic [31:0] w_conflict_nc;
  logic [2:0] w_snap_cs_nc; logic [3:0] w_rf_cs_nc; logic [2:0] w_push_g_nc;

  book_push_refill_top #(.N_SYM_P(N_SYM), .DEPTH_REFILL(8), .DEPTH_SNAP(8)) u_top (
    .sys_clk(clk), .sys_rst_n(rst_n),
    .i_hot_upd_req(w_hot_req), .i_hot_upd_we(w_hot_we),
    .i_hot_upd_symbol(w_hot_sym), .i_hot_upd_wdata(w_hot_wdata),
    .o_hot_upd_rdata(w_hot_rdata_nc), .o_hot_upd_rvalid(w_hot_rvalid_nc),
    .i_rt_valid(w_rt_v), .i_rt_symbol(w_rt_sym), .i_rt_row(w_rt_row),
    .i_refill_req_valid(w_rf_v), .i_refill_req(w_rf_req),
    .i_snap_enable(csr_enable), .i_snap_skip_empty(csr_snap_skip_empty),
    .i_period_cycles(csr_period_cycles),
    .o_ddr_req_valid(w_ddr_req_v), .i_ddr_req_ready(w_ddr_req_r), .o_ddr_req(w_ddr_req),
    .i_ddr_rsp_valid(w_ddr_rsp_v), .o_ddr_rsp_ready(w_ddr_rsp_r), .i_ddr_rsp(w_ddr_rsp),
    .o_dma_valid(w_dma_v), .i_dma_ready(push_ready), .o_dma_msg(w_dma_msg),
    .o_dbg_err_sticky(w_err_nc), .o_dbg_mem_conflict_cnt(w_conflict_nc),
    .o_dbg_snap_cs(w_snap_cs_nc), .o_dbg_refill_cs(w_rf_cs_nc), .o_dbg_push_grant(w_push_g_nc)
  );

  assign push_valid=w_dma_v;
  assign push_symbol_id=w_dma_msg.symbol_id;
  assign push_ts_ns=w_dma_msg.ts_ns;
  assign push_seq=w_dma_msg.seq;
  assign push_flags=w_dma_msg.flags;
  assign push_bid_vld=w_dma_msg.bid_vld;
  assign push_ask_vld=w_dma_msg.ask_vld;
  assign push_bid_px=w_dma_msg.bid_px;
  assign push_bid_qty=w_dma_msg.bid_qty;
  assign push_ask_px=w_dma_msg.ask_px;
  assign push_ask_qty=w_dma_msg.ask_qty;
  assign push_msg_flat=TOP10_MSG_W'(w_dma_msg);
  // Pulse semantics: top RT has no ready; T-A6 is hierarchical on u_top (not these ties).
  assign rt_ready=1'b1;
  // Remains 0 by construction for legal RTL (no illegal RT↔DDR gating in glue path).
  assign hot_path_stall=1'b0;
  assign m_axi_awvalid=1'b0; assign m_axi_wvalid=1'b0;
  assign m_axi_bready=1'b1; assign m_axi_rready=1'b1;

  assign push_rt_cnt=u_top.u_push.o_tx_rt;
  assign push_refill_cnt=u_top.u_push.o_tx_refill;
  assign push_timer_cnt=u_top.u_push.o_tx_snap;
  assign drop_cnt=u_top.u_push.o_drop_rt+u_top.u_push.o_drop_refill+u_top.u_push.o_drop_snap;
  assign refill_discard_cnt=u_top.u_refill.o_dbg_stale_cnt;
  assign snap_next_id=16'(u_top.u_snap.o_dbg_symbol);

  logic [31:0] c_iss; logic [1:0] grant_r;
  assign refill_issue_cnt=c_iss; assign last_grant=grant_r;

  typedef struct packed {
    logic valid; logic [15:0] sid; logic [1:0] side; logic [31:0] seq_start;
    logic [AXI_ADDR_W_P-1:0] addr; logic ar_sent;
  } rf_os_t;
  rf_os_t rf_os [0:REFILL_MAX_OS-1];

  function automatic int count_os();
    int n; n=0; for (int i=0;i<REFILL_MAX_OS;i++) if (rf_os[i].valid) n++; return n;
  endfunction
  assign outstanding_refill=4'(count_os());
  assign outstanding_total=outstanding_refill;

  int ar_sel; logic ar_sel_v;
  always_comb begin
    ar_sel_v=0; ar_sel=0;
    for (int i=0;i<REFILL_MAX_OS;i++)
      if (rf_os[i].valid && !rf_os[i].ar_sent && !ar_sel_v) begin ar_sel_v=1; ar_sel=i; end
  end
  assign m_axi_arvalid=ar_sel_v && !l1_rmw_pri_hold;
  assign m_axi_arid=ar_sel_v ? AXI_ID_W_P'(ar_sel) : '0;
  assign m_axi_araddr=ar_sel_v ? rf_os[ar_sel].addr : '0;
  assign m_axi_arlen=8'd0;
  assign m_axi_arsize=3'(AXI_SIZE_64B);
  assign m_axi_arburst=2'b01;

  logic w_take_ddr_req; int free_slot;
  always_comb begin
    free_slot=-1;
    for (int i=0;i<REFILL_MAX_OS;i++) if (!rf_os[i].valid && free_slot<0) free_slot=i;
    w_take_ddr_req=w_ddr_req_v && (free_slot>=0) && !l1_rmw_pri_hold;
  end
  assign w_ddr_req_r=w_take_ddr_req;

  logic rsp_hold_v; refill_rsp_t rsp_hold; int rsp_hold_id;
  assign w_ddr_rsp_v=rsp_hold_v; assign w_ddr_rsp=rsp_hold;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      c_iss<='0; grant_r<='0; rsp_hold_v<=0; rsp_hold<='0; rsp_hold_id<=0;
      for (int i=0;i<REFILL_MAX_OS;i++) rf_os[i]<='0;
      for (int s=0;s<N_SYM;s++) begin
        l0_seq[s]<='0; l0_ts[s]<='0;
        for (int i=0;i<10;i++) begin
          bid_v[s][i]<=0; bid_p[s][i]<=0; bid_q[s][i]<=0;
          ask_v[s][i]<=0; ask_p[s][i]<=0; ask_q[s][i]<=0;
        end
        for (int a=0;a<2;a++) for (int k=0;k<16;k++) begin
          b16_v[s][a][k]<=0; b16_p[s][a][k]<=0; b16_q[s][a][k]<=0;
        end
      end
    end else if (clear) begin
      for (int i=0;i<REFILL_MAX_OS;i++) rf_os[i]<='0;
      rsp_hold_v<=0;
      for (int s=0;s<N_SYM;s++) begin
        l0_seq[s]<='0; l0_ts[s]<='0;
        for (int i=0;i<10;i++) begin bid_v[s][i]<=0; ask_v[s][i]<=0; end
      end
    end else begin
      if (b16_wr_en && int'(b16_symbol_id)<N_SYM && int'(b16_slot)<16) begin
        automatic int is_ask=(b16_side==SIDE_ASK)?1:0;
        b16_v[b16_symbol_id][is_ask][b16_slot]<=b16_vld;
        b16_p[b16_symbol_id][is_ask][b16_slot]<=b16_px;
        b16_q[b16_symbol_id][is_ask][b16_slot]<=b16_qty;
      end

      if (rt_valid && int'(rt_symbol_id)<N_SYM) begin
        automatic int sid=int'(rt_symbol_id);
        l0_seq[sid]<=rt_seq; l0_ts[sid]<=rt_ts_ns;
        if (rt_dig_hole) begin
          if (rt_side==SIDE_BID) begin
            for (int i=0;i<10;i++) if (i>=int'(rt_level)) bid_v[sid][i]<=0;
          end else begin
            for (int i=0;i<10;i++) if (i>=int'(rt_level)) ask_v[sid][i]<=0;
          end
        end else if (rt_level<4'd10) begin
          if (rt_side==SIDE_BID) begin
            bid_v[sid][rt_level]<=rt_lvl_vld; bid_p[sid][rt_level]<=rt_px; bid_q[sid][rt_level]<=rt_qty;
          end else begin
            ask_v[sid][rt_level]<=rt_lvl_vld; ask_p[sid][rt_level]<=rt_px; ask_q[sid][rt_level]<=rt_qty;
          end
        end
      end

      if (w_take_ddr_req) begin
        rf_os[free_slot].valid<=1;
        rf_os[free_slot].sid<=w_ddr_req.symbol_id;
        rf_os[free_slot].side<=w_ddr_req.side;
        rf_os[free_slot].seq_start<=w_ddr_req.seq_start;
        rf_os[free_slot].addr<=side_addr(w_ddr_req.symbol_id, w_ddr_req.side);
        rf_os[free_slot].ar_sent<=0;
        c_iss<=c_iss+32'd1;
      end
      if (m_axi_arvalid && m_axi_arready) rf_os[ar_sel].ar_sent<=1;

      if (m_axi_rvalid && m_axi_rready && !rsp_hold_v) begin
        automatic int id=int'(m_axi_rid);
        if (id<REFILL_MAX_OS && rf_os[id].valid && rf_os[id].ar_sent) begin
          automatic int sid=int'(rf_os[id].sid);
          automatic int is_ask=(rf_os[id].side==SIDE_ASK)?1:0;
          automatic refill_rsp_t rsp; rsp='0;
          rsp.symbol_id=rf_os[id].sid; rsp.side=rf_os[id].side;
          rsp.seq_start=rf_os[id].seq_start;
          for (int i=0;i<10;i++) begin
            rsp.lvl_vld[i]=b16_v[sid][is_ask][i];
            rsp.lvl_px[i*64+:64]=b16_p[sid][is_ask][i];
            rsp.lvl_qty[i*32+:32]=b16_q[sid][is_ask][i];
          end
          rsp_hold_v<=1; rsp_hold<=rsp; rsp_hold_id<=id;
        end
      end
      if (rsp_hold_v && w_ddr_rsp_r) begin
        rsp_hold_v<=0;
        if (rsp_hold_id<REFILL_MAX_OS) rf_os[rsp_hold_id].valid<=0;
      end

      if (w_dma_v && push_ready) begin
        unique case (1'b1)
          w_dma_msg.flags[0]: grant_r<=2'd0;
          w_dma_msg.flags[2]: grant_r<=2'd1;
          w_dma_msg.flags[1]: grant_r<=2'd2;
          default: ;
        endcase
      end
    end
  end

  logic unused_bits;
  assign unused_bits=|{m_axi_rdata[0], m_axi_rresp, m_axi_rlast, w_hot_rdata_nc.nonempty,
                       w_hot_rvalid_nc, w_err_nc, w_conflict_nc[0], w_snap_cs_nc[0],
                       w_rf_cs_nc[0], w_push_g_nc[0]};
endmodule
`default_nettype wire
