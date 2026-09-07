// -----------------------------------------------------------------------------
// book_push_refill_top.sv — sys_clk integration of L0 mem + snap + refill + push
// SPEC: docs/p1-parallel-partition.md §3/§4; book-push-refill-v2.md
// No AXI / LightningDMA IP here — expose DDR CDC handshakes + DMA AXIS ports.
// Port-B arb: refill_wr > refill_rd > snap_rd (SPEC p1 §5.2)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module book_push_refill_top
  import book_pkg::*;
#(
  parameter int N_SYM_P      = N_SYM,
  parameter int DEPTH_REFILL = 64,
  parameter int DEPTH_SNAP   = 64
) (
  input  logic                sys_clk,
  /* verilator lint_off SYNCASYNCNET */
  input  logic                sys_rst_n,
  /* verilator lint_on SYNCASYNCNET */

  // Hot-path Port-A stub (later: l0_upd_pipe) — pass-through
  input  logic                i_hot_upd_req,
  input  logic                i_hot_upd_we,
  input  logic [N_SYM_AW-1:0] i_hot_upd_symbol,
  input  l0_top10_row_t       i_hot_upd_wdata,
  output l0_top10_row_t       o_hot_upd_rdata,
  output logic                o_hot_upd_rvalid,

  // RT push from L0 update (脉冲; 无反压)
  input  logic                i_rt_valid,
  input  logic [N_SYM_AW-1:0] i_rt_symbol,
  input  l0_top10_row_t       i_rt_row,

  // Soft refill request
  input  logic                i_refill_req_valid,
  input  refill_req_t         i_refill_req,

  // Snap CSR — period default comment: 3_222_656 (~10ms @322M)
  input  logic                i_snap_enable,
  input  logic                i_snap_skip_empty,
  input  logic [31:0]         i_period_cycles,

  // DDR CDC handshakes (async FIFO outside)
  output logic                o_ddr_req_valid,
  input  logic                i_ddr_req_ready,
  output refill_req_t         o_ddr_req,
  input  logic                i_ddr_rsp_valid,
  output logic                o_ddr_rsp_ready,
  input  refill_rsp_t         i_ddr_rsp,

  // DMA master (LightningDMA sink external) — keep msg port; map from engine AXIS
  output logic                o_dma_valid,
  input  logic                i_dma_ready,
  output top10_msg_t          o_dma_msg,

  (* keep = "true" *) output logic        o_dbg_err_sticky,
  (* keep = "true" *) output logic [31:0] o_dbg_mem_conflict_cnt,
  (* keep = "true" *) output logic [2:0]  o_dbg_snap_cs,
  (* keep = "true" *) output logic [3:0]  o_dbg_refill_cs,
  (* keep = "true" *) output logic [2:0]  o_dbg_push_grant
);

  // ---------------------------------------------------------------------------
  // Port-B mem side (l0_top10_row_t) + arb
  // ---------------------------------------------------------------------------
  logic                w_b_en;
  logic                w_b_we;
  logic                w_b_ready;
  logic                w_b_is_refill;
  logic [N_SYM_AW-1:0] w_b_symbol;
  l0_top10_row_t       w_b_wdata;
  l0_top10_row_t       w_b_rdata;
  logic                w_b_rvalid;
  logic [31:0]         w_mem_conflict_cnt;
  logic [1:0]          w_mem_cs_nc;
  logic                w_a_ready_nc;
  logic                w_mem_err;

  logic                w_snap_rd_valid;
  logic [N_SYM_AW-1:0] w_snap_rd_symbol;
  logic                w_snap_rd_ready;
  top10_view_t         w_snap_rd_view;
  logic                w_snap_rd_view_valid;
  logic                w_snap_push_valid;
  logic                w_snap_push_ready;
  logic [N_SYM_AW-1:0] w_snap_push_symbol;
  top10_view_t         w_snap_push_view;
  logic [2:0]          w_snap_cs;
  logic [31:0]         w_snap_drop;
  logic [N_SYM_AW-1:0] w_snap_dbg_sym;
  logic                w_snap_err;

  logic                w_rf_l0_rd_valid;
  logic [N_SYM_AW-1:0] w_rf_l0_rd_symbol;
  logic                w_rf_l0_rd_ready;
  top10_view_t         w_rf_l0_rd_view;
  logic                w_rf_l0_rd_view_valid;
  logic                w_rf_l0_wr_valid;
  logic [N_SYM_AW-1:0] w_rf_l0_wr_symbol;
  top10_view_t         w_rf_l0_wr_view;
  logic                w_rf_l0_wr_ready;
  logic                w_rf_l0_wr_nack;
  logic                w_rf_push_valid;
  logic                w_rf_push_ready;
  logic [N_SYM_AW-1:0] w_rf_push_symbol;
  top10_view_t         w_rf_push_view;
  logic [3:0]          w_rf_cs;
  logic [15:0]         w_rf_depth;
  logic [31:0]         w_rf_drop;
  logic [31:0]         w_rf_stale;
  logic                w_rf_err;

  logic [TOP10_MSG_W-1:0] w_dma_tdata;
  logic                   w_dma_tlast;
  logic [31:0]            w_push_tx_rt;
  logic [31:0]            w_push_tx_refill;
  logic [31:0]            w_push_tx_snap;
  logic [31:0]            w_push_drop_rt;
  logic [31:0]            w_push_drop_refill;
  logic [31:0]            w_push_drop_snap;
  logic [1:0]             w_push_cs;
  logic                   w_push_err;
  l0_top10_row_t          w_rf_push_row;
  l0_top10_row_t          w_snap_push_row;

  typedef enum logic [1:0] {
    B_IDLE  = 2'd0,
    B_RF_WR = 2'd1,
    B_RF_RD = 2'd2,
    B_SNAP  = 2'd3
  } b_gnt_e;

  b_gnt_e     w_b_gnt;
  logic [1:0] r_b_rd_gnt;

  assign w_b_gnt =
      w_rf_l0_wr_valid ? B_RF_WR :
      w_rf_l0_rd_valid ? B_RF_RD :
      w_snap_rd_valid  ? B_SNAP  :
                         B_IDLE;

  assign w_b_is_refill = (w_b_gnt == B_RF_WR) || (w_b_gnt == B_RF_RD);

  always_comb begin
    w_b_en     = 1'b0;
    w_b_we     = 1'b0;
    w_b_symbol = '0;
    w_b_wdata  = '0;
    unique case (w_b_gnt)
      B_RF_WR: begin
        w_b_en     = 1'b1;
        w_b_we     = 1'b1;
        w_b_symbol = w_rf_l0_wr_symbol;
        w_b_wdata  = view_to_l0_row(w_rf_l0_wr_view);
      end
      B_RF_RD: begin
        w_b_en     = 1'b1;
        w_b_symbol = w_rf_l0_rd_symbol;
      end
      B_SNAP: begin
        w_b_en     = 1'b1;
        w_b_symbol = w_snap_rd_symbol;
      end
      default: ;
    endcase
  end

  // o_b_ready==0 ≡ old o_b_nack
  assign w_rf_l0_wr_ready = (w_b_gnt == B_RF_WR) && w_b_ready;
  assign w_rf_l0_wr_nack  = (w_b_gnt == B_RF_WR) && !w_b_ready;
  assign w_rf_l0_rd_ready = (w_b_gnt == B_RF_RD) && w_b_ready;
  assign w_snap_rd_ready  = (w_b_gnt == B_SNAP)  && w_b_ready;

  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      r_b_rd_gnt <= B_IDLE;
    else if (w_b_en && !w_b_we && w_b_ready)
      r_b_rd_gnt <= w_b_gnt;
  end

  // Boundary convert: mem/push use l0_top10_row_t; snap/refill_ctrl keep top10_view_t
  assign w_rf_l0_rd_view       = l0_row_to_view(w_b_rdata);
  assign w_rf_l0_rd_view_valid = w_b_rvalid && (r_b_rd_gnt == B_RF_RD);
  assign w_snap_rd_view        = l0_row_to_view(w_b_rdata);
  assign w_snap_rd_view_valid  = w_b_rvalid && (r_b_rd_gnt == B_SNAP);
  assign w_rf_push_row         = view_to_l0_row(w_rf_push_view);
  assign w_snap_push_row       = view_to_l0_row(w_snap_push_view);

  // l0_top10_mem — 4-bank dual-port (req/ready + l0_top10_row_t)
  l0_top10_mem #(.N_SYM_P(N_SYM_P)) u_l0_mem (
    .sys_clk            (sys_clk),             // 时钟
    .sys_rst_n          (sys_rst_n),           // 复位(异步低)
    .i_a_req            (i_hot_upd_req),       // 握手
    .i_a_we             (i_hot_upd_we),
    .i_a_symbol         (16'(i_hot_upd_symbol)),
    .i_a_wdata          (i_hot_upd_wdata),
    .o_a_rdata          (o_hot_upd_rdata),
    .o_a_valid          (o_hot_upd_rvalid),    // 握手
    .o_a_ready          (w_a_ready_nc),        // 握手 (unused)
    .i_b_req            (w_b_en),              // 握手
    .i_b_we             (w_b_we),
    .i_b_is_refill      (w_b_is_refill),
    .i_b_symbol         (16'(w_b_symbol)),
    .i_b_wdata          (w_b_wdata),
    .o_b_rdata          (w_b_rdata),
    .o_b_valid          (w_b_rvalid),          // 握手
    .o_b_ready          (w_b_ready),           // 握手 (≡ !nack)
    .o_dbg_conflict_cnt (w_mem_conflict_cnt),
    .o_dbg_cs_state     (w_mem_cs_nc),
    .o_dbg_err_sticky   (w_mem_err)
  );

  // snap_fsm — still top10_view_t at its ports
  snap_fsm #(.N_SYM_P(N_SYM_P)) u_snap (
    .sys_clk            (sys_clk),             // 时钟
    .sys_rst_n          (sys_rst_n),           // 复位(异步低)
    .i_snap_enable      (i_snap_enable),
    .i_snap_skip_empty  (i_snap_skip_empty),
    .i_period_cycles    (i_period_cycles),
    .o_rd_valid         (w_snap_rd_valid),     // 握手
    .o_rd_symbol        (w_snap_rd_symbol),
    .i_rd_ready         (w_snap_rd_ready),     // 握手
    .i_rd_view          (w_snap_rd_view),
    .i_rd_view_valid    (w_snap_rd_view_valid),
    .o_push_valid       (w_snap_push_valid),   // 握手
    .i_push_ready       (w_snap_push_ready),   // 握手
    .o_push_symbol      (w_snap_push_symbol),
    .o_push_view        (w_snap_push_view),
    .o_dbg_cs_state     (w_snap_cs),
    .o_dbg_drop_cnt     (w_snap_drop),
    .o_dbg_symbol       (w_snap_dbg_sym),
    .o_dbg_err_sticky   (w_snap_err)
  );

  // refill_ctrl — SPEC: afifo to ddr_clk is outside; still top10_view_t
  refill_ctrl u_refill (
    .sys_clk            (sys_clk),             // 时钟
    .sys_rst_n          (sys_rst_n),           // 复位(异步低)
    .i_req_valid        (i_refill_req_valid),  // 握手
    .i_req              (i_refill_req),
    .o_ddr_req_valid    (o_ddr_req_valid),     // 握手
    .i_ddr_req_ready    (i_ddr_req_ready),     // 握手
    .o_ddr_req          (o_ddr_req),
    .i_ddr_rsp_valid    (i_ddr_rsp_valid),     // 握手
    .o_ddr_rsp_ready    (o_ddr_rsp_ready),     // 握手
    .i_ddr_rsp          (i_ddr_rsp),
    .o_l0_rd_valid      (w_rf_l0_rd_valid),    // 握手
    .o_l0_rd_symbol     (w_rf_l0_rd_symbol),
    .i_l0_rd_ready      (w_rf_l0_rd_ready),    // 握手
    .i_l0_rd_view       (w_rf_l0_rd_view),
    .i_l0_rd_view_valid (w_rf_l0_rd_view_valid),
    .o_l0_wr_valid      (w_rf_l0_wr_valid),    // 握手
    .o_l0_wr_symbol     (w_rf_l0_wr_symbol),
    .o_l0_wr_view       (w_rf_l0_wr_view),
    .i_l0_wr_ready      (w_rf_l0_wr_ready),    // 握手
    .i_l0_wr_nack       (w_rf_l0_wr_nack),     // 脉冲(同拍 nack)
    .o_push_valid       (w_rf_push_valid),     // 握手
    .i_push_ready       (w_rf_push_ready),     // 握手
    .o_push_symbol      (w_rf_push_symbol),
    .o_push_view        (w_rf_push_view),
    .o_dbg_cs_state     (w_rf_cs),
    .o_dbg_fifo_depth   (w_rf_depth),
    .o_dbg_drop_cnt     (w_rf_drop),
    .o_dbg_stale_cnt    (w_rf_stale),
    .o_dbg_err_sticky   (w_rf_err)
  );

  // book_push_engine — l0_top10_row_t + AXIS DMA
  book_push_engine #(.DEPTH_REFILL(DEPTH_REFILL), .DEPTH_SNAP(DEPTH_SNAP)) u_push (
    .sys_clk         (sys_clk),                // 时钟
    .sys_rst_n       (sys_rst_n),              // 复位(异步低)
    .i_rt_valid      (i_rt_valid),             // 脉冲(sys_clk, 单拍)
    .i_rt_symbol     (16'(i_rt_symbol)),
    .i_rt_row        (i_rt_row),
    .i_refill_valid  (w_rf_push_valid),        // 握手
    .o_refill_ready  (w_rf_push_ready),        // 握手
    .i_refill_symbol (16'(w_rf_push_symbol)),
    .i_refill_row    (w_rf_push_row),
    .i_snap_valid    (w_snap_push_valid),      // 握手
    .o_snap_ready    (w_snap_push_ready),      // 握手
    .i_snap_symbol   (16'(w_snap_push_symbol)),
    .i_snap_row      (w_snap_push_row),
    .o_m_tdata       (w_dma_tdata),            // 握手
    .o_m_tvalid      (o_dma_valid),            // 握手
    .o_m_tlast       (w_dma_tlast),
    .i_m_tready      (i_dma_ready),            // 握手
    .o_tx_rt         (w_push_tx_rt),
    .o_tx_refill     (w_push_tx_refill),
    .o_tx_snap       (w_push_tx_snap),
    .o_drop_rt       (w_push_drop_rt),
    .o_drop_refill   (w_push_drop_refill),
    .o_drop_snap     (w_push_drop_snap),
    .o_dbg_cs_state  (w_push_cs),
    .o_dbg_err_sticky(w_push_err)
  );

  assign o_dma_msg = top10_msg_t'(w_dma_tdata);

  assign o_dbg_err_sticky       = w_mem_err | w_snap_err | w_rf_err | w_push_err;
  assign o_dbg_mem_conflict_cnt = w_mem_conflict_cnt;
  assign o_dbg_snap_cs          = w_snap_cs;
  assign o_dbg_refill_cs        = w_rf_cs;
  // Engine exposes cs_state[1:0]; keep legacy 3b top pin (zero-extend)
  assign o_dbg_push_grant       = {1'b0, w_push_cs};

  logic unused_dbg;
  assign unused_dbg = |w_snap_drop | |w_snap_dbg_sym | |w_rf_depth | |w_rf_drop |
                      |w_rf_stale | |w_push_tx_rt | |w_push_tx_refill |
                      |w_push_tx_snap | |w_push_drop_rt | |w_push_drop_refill |
                      |w_push_drop_snap | |w_mem_cs_nc | w_dma_tlast | w_a_ready_nc;

endmodule

`default_nettype wire
