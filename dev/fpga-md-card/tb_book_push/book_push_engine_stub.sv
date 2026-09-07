`timescale 1ns / 1ps
// DEPRECATED — obsolete leftover. NOT in Makefile BOOK_PUSH_RTL.
// P2 DUT is book_push_refill_tb_glue → book_push_refill_top (real). Do not use as DUT.
// Kept on disk only; safe to delete if unused. NOT for synth.
// book_push_engine_stub — historical P2 behavioral stub. Priority rt > refill > timer.
module book_push_engine_stub
  import book_pkg::*;
#(
  parameter int N_SYM_TB = 32,
  parameter int N_SYM = N_SYM_TB,
  parameter int Q_RT_DEPTH = 16,
  parameter int Q_REFILL_DEPTH = 16,
  parameter int Q_SNAP_DEPTH = 16,
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
  logic [15:0] q_rt_sid [0:Q_RT_DEPTH-1], q_rf_sid [0:Q_REFILL_DEPTH-1], q_sn_sid [0:Q_SNAP_DEPTH-1];
  int q_rt_n, q_rf_n, q_sn_n;
  typedef struct packed {
    logic valid; logic [15:0] sid; logic [1:0] side; logic [31:0] seq_start;
    logic [AXI_ADDR_W_P-1:0] addr; logic ar_sent;
  } rf_os_t;
  rf_os_t rf_os [0:REFILL_MAX_OS-1];
  logic [31:0] timer_cnt, c_rt, c_tm, c_rf, c_disc, c_iss, c_drop;
  logic [15:0] snap_id; logic snap_active; logic [1:0] grant_r;

  assign push_rt_cnt=c_rt; assign push_timer_cnt=c_tm; assign push_refill_cnt=c_rf;
  assign refill_discard_cnt=c_disc; assign refill_issue_cnt=c_iss; assign drop_cnt=c_drop;
  assign snap_next_id=snap_id; assign last_grant=grant_r;
  assign hot_path_stall=1'b0; assign rt_ready=1'b1;
  assign m_axi_awvalid=1'b0; assign m_axi_wvalid=1'b0; assign m_axi_bready=1'b1; assign m_axi_rready=1'b1;

  function automatic int count_os();
    int n; n=0; for (int i=0;i<REFILL_MAX_OS;i++) if (rf_os[i].valid) n++; return n;
  endfunction
  assign outstanding_refill=4'(count_os()); assign outstanding_total=outstanding_refill;

  function automatic int depth_bid(input int sid);
    int d; d=0; for (int i=0;i<10;i++) if (bid_v[sid][i]) d++; return d;
  endfunction
  function automatic int depth_ask(input int sid);
    int d; d=0; for (int i=0;i<10;i++) if (ask_v[sid][i]) d++; return d;
  endfunction
  function automatic logic is_empty(input int sid);
    return (depth_bid(sid)==0) && (depth_ask(sid)==0);
  endfunction
  function automatic logic [AXI_ADDR_W_P-1:0] side_addr(input logic [15:0] sid, input logic [1:0] side);
    logic [63:0] a;
    a = best16_addr(64'(csr_base_best16), sid[N_SYM_AW-1:0], (side==SIDE_ASK), 4'd0);
    a[5:0]=6'b0; return AXI_ADDR_W_P'(a);
  endfunction

  task automatic q_rt_push(input logic [15:0] sid);
    for (int i=0;i<q_rt_n;i++) if (q_rt_sid[i]==sid) return;
    if (q_rt_n < Q_RT_DEPTH) begin q_rt_sid[q_rt_n]=sid; q_rt_n++; end
    else begin for (int i=0;i<Q_RT_DEPTH-1;i++) q_rt_sid[i]=q_rt_sid[i+1]; q_rt_sid[Q_RT_DEPTH-1]=sid; c_drop++; end
  endtask
  task automatic q_rf_push(input logic [15:0] sid);
    for (int i=0;i<q_rf_n;i++) if (q_rf_sid[i]==sid) return;
    if (q_rf_n < Q_REFILL_DEPTH) begin q_rf_sid[q_rf_n]=sid; q_rf_n++; end else c_drop++;
  endtask
  task automatic q_sn_push(input logic [15:0] sid);
    if (q_sn_n < Q_SNAP_DEPTH) begin q_sn_sid[q_sn_n]=sid; q_sn_n++; end
  endtask
  task automatic q_rt_pop();
    for (int i=0;i<q_rt_n-1;i++) q_rt_sid[i]=q_rt_sid[i+1]; if (q_rt_n>0) q_rt_n--;
  endtask
  task automatic q_rf_pop();
    for (int i=0;i<q_rf_n-1;i++) q_rf_sid[i]=q_rf_sid[i+1]; if (q_rf_n>0) q_rf_n--;
  endtask
  task automatic q_sn_pop();
    for (int i=0;i<q_sn_n-1;i++) q_sn_sid[i]=q_sn_sid[i+1]; if (q_sn_n>0) q_sn_n--;
  endtask
  task automatic try_issue_refill(input logic [15:0] sid, input logic [1:0] side, input logic [31:0] seq_start);
    int slot;
    if (l1_rmw_pri_hold) return;
    if (count_os() >= REFILL_MAX_OS) return;
    for (int i=0;i<REFILL_MAX_OS;i++)
      if (rf_os[i].valid && rf_os[i].sid==sid && rf_os[i].side==side) begin rf_os[i].seq_start=seq_start; return; end
    slot=-1;
    for (int i=0;i<REFILL_MAX_OS;i++) if (!rf_os[i].valid) begin slot=i; break; end
    if (slot<0) return;
    rf_os[slot].valid=1'b1; rf_os[slot].sid=sid; rf_os[slot].side=side;
    rf_os[slot].seq_start=seq_start; rf_os[slot].addr=side_addr(sid,side); rf_os[slot].ar_sent=1'b0;
    c_iss++;
  endtask

  int ar_sel; logic ar_sel_v;
  always_comb begin
    ar_sel_v=1'b0; ar_sel=0;
    for (int i=0;i<REFILL_MAX_OS;i++)
      if (rf_os[i].valid && !rf_os[i].ar_sent && !ar_sel_v) begin ar_sel_v=1'b1; ar_sel=i; end
  end
  assign m_axi_arvalid = ar_sel_v && !l1_rmw_pri_hold;
  assign m_axi_arid = ar_sel_v ? AXI_ID_W_P'(ar_sel) : '0;
  assign m_axi_araddr = ar_sel_v ? rf_os[ar_sel].addr : '0;
  assign m_axi_arlen = 8'd0;
  assign m_axi_arsize = 3'(AXI_SIZE_64B);
  assign m_axi_arburst = 2'b01;

  logic g_valid; logic [1:0] g_src; logic [15:0] g_sid;
  always_comb begin
    g_valid=1'b0; g_src=2'd0; g_sid='0;
    if (q_rt_n>0) begin g_valid=1'b1; g_src=2'd0; g_sid=q_rt_sid[0]; end
    else if (q_rf_n>0) begin g_valid=1'b1; g_src=2'd1; g_sid=q_rf_sid[0]; end
    else if (q_sn_n>0) begin g_valid=1'b1; g_src=2'd2; g_sid=q_sn_sid[0]; end
  end
  logic fire; assign fire = g_valid && push_ready;

  top10_msg_t msg_c;
  always_comb begin
    push_valid=g_valid; push_symbol_id=g_sid;
    push_ts_ns='0; push_seq='0; push_bid_vld='0; push_ask_vld='0;
    push_bid_px='0; push_bid_qty='0; push_ask_px='0; push_ask_qty='0; push_flags='0; msg_c='0;
    if (g_valid && int'(g_sid)<N_SYM) begin
      push_ts_ns=l0_ts[g_sid]; push_seq=l0_seq[g_sid];
      for (int i=0;i<10;i++) begin
        push_bid_vld[i]=bid_v[g_sid][i]; push_ask_vld[i]=ask_v[g_sid][i];
        push_bid_px[i*64 +: 64]=bid_p[g_sid][i]; push_ask_px[i*64 +: 64]=ask_p[g_sid][i];
        push_bid_qty[i*32 +: 32]=bid_q[g_sid][i]; push_ask_qty[i*32 +: 32]=ask_q[g_sid][i];
      end
      unique case (g_src)
        2'd0: push_flags=F_TOP10_RT;
        2'd1: push_flags=F_TOP10_REFILL;
        2'd2: push_flags=F_TOP10_TIMER;
        default: push_flags='0;
      endcase
      msg_c.symbol_id=g_sid; msg_c.ts_ns=push_ts_ns; msg_c.seq=push_seq; msg_c.flags=push_flags;
      msg_c.bid_vld=push_bid_vld; msg_c.ask_vld=push_ask_vld;
      msg_c.bid_px=push_bid_px; msg_c.bid_qty=push_bid_qty;
      msg_c.ask_px=push_ask_px; msg_c.ask_qty=push_ask_qty;
    end
    push_msg_flat=msg_c;
  end
  logic unused_bits; assign unused_bits = |{m_axi_rdata[0], m_axi_rresp, m_axi_rlast};

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      q_rt_n=0; q_rf_n=0; q_sn_n=0;
      timer_cnt='0; snap_id='0; snap_active=1'b0;
      c_rt='0; c_tm='0; c_rf='0; c_disc='0; c_iss='0; c_drop='0; grant_r='0;
      for (int i=0;i<REFILL_MAX_OS;i++) rf_os[i]='0;
      for (int s=0;s<N_SYM;s++) begin
        l0_seq[s]='0; l0_ts[s]='0;
        for (int i=0;i<10;i++) begin
          bid_v[s][i]=0; bid_p[s][i]=0; bid_q[s][i]=0;
          ask_v[s][i]=0; ask_p[s][i]=0; ask_q[s][i]=0;
        end
        for (int a=0;a<2;a++) for (int k=0;k<16;k++) begin
          b16_v[s][a][k]=0; b16_p[s][a][k]=0; b16_q[s][a][k]=0;
        end
      end
      for (int i=0;i<Q_RT_DEPTH;i++) q_rt_sid[i]=0;
      for (int i=0;i<Q_REFILL_DEPTH;i++) q_rf_sid[i]=0;
      for (int i=0;i<Q_SNAP_DEPTH;i++) q_sn_sid[i]=0;
    end else if (clear) begin
      q_rt_n=0; q_rf_n=0; q_sn_n=0; timer_cnt='0; snap_id='0; snap_active=1'b0;
      for (int i=0;i<REFILL_MAX_OS;i++) rf_os[i]='0;
      for (int s=0;s<N_SYM;s++) begin
        l0_seq[s]='0; l0_ts[s]='0;
        for (int i=0;i<10;i++) begin bid_v[s][i]=0; ask_v[s][i]=0; end
      end
    end else begin
      if (b16_wr_en && int'(b16_symbol_id)<N_SYM && int'(b16_slot)<16) begin
        automatic int is_ask = (b16_side==SIDE_ASK) ? 1 : 0;
        b16_v[b16_symbol_id][is_ask][b16_slot]=b16_vld;
        b16_p[b16_symbol_id][is_ask][b16_slot]=b16_px;
        b16_q[b16_symbol_id][is_ask][b16_slot]=b16_qty;
      end

      if (rt_valid && rt_ready && int'(rt_symbol_id)<N_SYM) begin
        automatic int sid = int'(rt_symbol_id);
        automatic int d;
        l0_seq[sid]=rt_seq; l0_ts[sid]=rt_ts_ns;
        if (rt_dig_hole) begin
          if (rt_side==SIDE_BID) begin
            for (int i=0;i<10;i++) if (i>=int'(rt_level)) bid_v[sid][i]=1'b0;
          end else begin
            for (int i=0;i<10;i++) if (i>=int'(rt_level)) ask_v[sid][i]=1'b0;
          end
        end else if (rt_level < 4'd10) begin
          if (rt_side==SIDE_BID) begin
            bid_v[sid][rt_level]=rt_lvl_vld; bid_p[sid][rt_level]=rt_px; bid_q[sid][rt_level]=rt_qty;
          end else begin
            ask_v[sid][rt_level]=rt_lvl_vld; ask_p[sid][rt_level]=rt_px; ask_q[sid][rt_level]=rt_qty;
          end
        end
        q_rt_push(16'(sid));
        if (rt_dig_hole) d = int'(rt_level);
        else begin
          d=0;
          if (rt_side==SIDE_BID) begin
            for (int i=0;i<10;i++) begin
              if (i==int'(rt_level)) begin if (rt_lvl_vld) d++; end
              else if (bid_v[sid][i]) d++;
            end
          end else begin
            for (int i=0;i<10;i++) begin
              if (i==int'(rt_level)) begin if (rt_lvl_vld) d++; end
              else if (ask_v[sid][i]) d++;
            end
          end
        end
        if (d<10 && rt_l1_may_have_more) try_issue_refill(16'(sid), rt_side, rt_seq);
      end

      if (csr_refill_kick && int'(csr_refill_symbol)<N_SYM)
        try_issue_refill(csr_refill_symbol, csr_refill_side, l0_seq[csr_refill_symbol]);

      if (m_axi_arvalid && m_axi_arready) rf_os[ar_sel].ar_sent = 1'b1;

      if (m_axi_rvalid && m_axi_rready) begin
        automatic int id = int'(m_axi_rid);
        if (id < REFILL_MAX_OS && rf_os[id].valid && rf_os[id].ar_sent) begin
          automatic int sid = int'(rf_os[id].sid);
          automatic int is_ask = (rf_os[id].side==SIDE_ASK) ? 1 : 0;
          if (l0_seq[sid] > rf_os[id].seq_start) begin
            c_disc++;
            rf_os[id].seq_start = l0_seq[sid];
            rf_os[id].ar_sent = 1'b0;
            rf_os[id].addr = side_addr(16'(sid), rf_os[id].side);
            c_iss++;
          end else begin
            for (int i=0;i<10;i++) begin
              if (is_ask) begin
                ask_v[sid][i]=b16_v[sid][is_ask][i]; ask_p[sid][i]=b16_p[sid][is_ask][i]; ask_q[sid][i]=b16_q[sid][is_ask][i];
              end else begin
                bid_v[sid][i]=b16_v[sid][is_ask][i]; bid_p[sid][i]=b16_p[sid][is_ask][i]; bid_q[sid][i]=b16_q[sid][is_ask][i];
              end
            end
            q_rf_push(16'(sid));
            rf_os[id].valid = 1'b0;
          end
        end
      end

      if (csr_enable) begin
        if (!snap_active) begin
          if (csr_period_cycles==0 || timer_cnt+1 >= csr_period_cycles) begin
            timer_cnt='0; snap_active=1'b1;
          end else timer_cnt = timer_cnt+1;
        end else if (q_sn_n < Q_SNAP_DEPTH) begin
          automatic int sid = int'(snap_id);
          if (!(csr_snap_skip_empty && is_empty(sid))) q_sn_push(16'(sid));
          if (sid+1 >= N_SYM) begin snap_id='0; snap_active=1'b0; end
          else snap_id = snap_id + 16'd1;
        end
      end else begin
        timer_cnt='0; snap_active=1'b0;
      end

      if (fire) begin
        grant_r = g_src;
        unique case (g_src)
          2'd0: begin q_rt_pop(); c_rt++; end
          2'd1: begin q_rf_pop(); c_rf++; end
          2'd2: begin q_sn_pop(); c_tm++; end
          default: ;
        endcase
      end
    end
  end
endmodule
