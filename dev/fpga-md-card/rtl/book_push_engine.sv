// -----------------------------------------------------------------------------
// book_push_engine.sv — three-level push + empty DMA sink (P1.0 / P1.1 start)
// Queues: push_q_rt (same symbol overwrite) > push_q_refill > push_q_snap.
// DMA AXIS single-beat TOP10_MSG_W (sim); production may slice to 512b later.
// Iron rule: i_rt_valid is pulse — never backpressure caller; DMA ready only
// stalls emit. Refill/snap use valid/ready (not on hot decode path).
// RT pop matches emit symbol (not first-vld). DEPTH_REFILL/SNAP default 64.
// SPEC: docs/p1-parallel-partition.md §6; docs/book-push-refill-v2.md
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module book_push_engine
  import book_pkg::*;
#(
  // SPEC p1-parallel-partition.md §6: refill/snap depth ≥64 (prod default).
  // Sim may override smaller via -GDEPTH_REFILL / -GDEPTH_SNAP (see Makefile).
  parameter int DEPTH_RT     = 256,
  parameter int DEPTH_REFILL = 64,
  parameter int DEPTH_SNAP   = 64
) (
  input  logic              sys_clk,
  /* verilator lint_off SYNCASYNCNET */
  input  logic              sys_rst_n,
  /* verilator lint_on SYNCASYNCNET */
  input  logic              i_rt_valid,
  input  logic [15:0]       i_rt_symbol,
  input  l0_top10_row_t     i_rt_row,
  input  logic              i_refill_valid,
  output logic              o_refill_ready,
  input  logic [15:0]       i_refill_symbol,
  input  l0_top10_row_t     i_refill_row,
  input  logic              i_snap_valid,
  output logic              o_snap_ready,
  input  logic [15:0]       i_snap_symbol,
  input  l0_top10_row_t     i_snap_row,
  output logic [TOP10_MSG_W-1:0] o_m_tdata,
  output logic              o_m_tvalid,
  output logic              o_m_tlast,
  input  logic              i_m_tready,
  output logic [31:0]       o_tx_rt,
  output logic [31:0]       o_tx_refill,
  output logic [31:0]       o_tx_snap,
  output logic [31:0]       o_drop_rt,
  output logic [31:0]       o_drop_refill,
  output logic [31:0]       o_drop_snap,
  (* keep = "true" *) output logic [1:0] o_dbg_cs_state,
  (* keep = "true" *) output logic       o_dbg_err_sticky
);

  localparam int RT_AW     = (DEPTH_RT     <= 1) ? 1 : $clog2(DEPTH_RT);
  localparam int REFILL_AW = (DEPTH_REFILL <= 1) ? 1 : $clog2(DEPTH_REFILL);
  localparam int SNAP_AW   = (DEPTH_SNAP   <= 1) ? 1 : $clog2(DEPTH_SNAP);

  typedef enum logic [1:0] {
    ST_IDLE = 2'b00,
    ST_EMIT = 2'b01
  } state_e;

  typedef enum logic [1:0] {
    SRC_RT     = 2'd0,
    SRC_REFILL = 2'd1,
    SRC_SNAP   = 2'd2,
    SRC_NONE   = 2'd3
  } src_e;

  typedef struct packed {
    logic          vld;
    logic [15:0]   symbol;
    l0_top10_row_t row;
  } rt_slot_t;

  typedef struct packed {
    logic [15:0]   symbol;
    l0_top10_row_t row;
  } fifo_slot_t;

  state_e cs_state;
  state_e ns_state;

  rt_slot_t             r_rt_q [0:DEPTH_RT-1];
  logic [RT_AW:0]       r_rt_count;
  fifo_slot_t           r_refill_q [0:DEPTH_REFILL-1];
  logic [REFILL_AW-1:0] r_refill_wr;
  logic [REFILL_AW-1:0] r_refill_rd;
  logic [REFILL_AW:0]   r_refill_count;
  fifo_slot_t           r_snap_q [0:DEPTH_SNAP-1];
  logic [SNAP_AW-1:0]   r_snap_wr;
  logic [SNAP_AW-1:0]   r_snap_rd;
  logic [SNAP_AW:0]     r_snap_count;

  logic [TOP10_MSG_W-1:0] r_m_tdata;
  src_e                   r_emit_src;
  logic                   r_err_sticky;
  logic [31:0]            r_tx_rt;
  logic [31:0]            r_tx_refill;
  logic [31:0]            r_tx_snap;
  logic [31:0]            r_drop_rt;
  logic [31:0]            r_drop_refill;
  logic [31:0]            r_drop_snap;

  logic w_rt_pending;
  logic w_refill_pending;
  logic w_snap_pending;
  src_e w_grant_src;
  logic w_fire;
  logic w_refill_push;
  logic w_snap_push;
  logic w_refill_pop;
  logic w_snap_pop;
  logic w_load_emit;

  function automatic logic [31:0] sat_inc(input logic [31:0] c);
    return (c == 32'hFFFF_FFFF) ? c : (c + 32'd1);
  endfunction

  logic               w_rt_preempt;
  // Pending for *next* grant: subtract the entry consumed by this-cycle fire
  // so w_load_emit after pop-on-fire does not reload the same RT/refill/snap.
  assign w_fire           = (cs_state == ST_EMIT) && i_m_tready;
  assign w_rt_pending     = (r_rt_count != '0)
                            && !(w_fire && (r_emit_src == SRC_RT));
  assign w_refill_pending = (r_refill_count != '0)
                            && !(w_fire && (r_emit_src == SRC_REFILL));
  assign w_snap_pending   = (r_snap_count != '0)
                            && !(w_fire && (r_emit_src == SRC_SNAP));

  always_comb begin
    if (w_rt_pending)
      w_grant_src = SRC_RT;
    else if (w_refill_pending)
      w_grant_src = SRC_REFILL;
    else if (w_snap_pending)
      w_grant_src = SRC_SNAP;
    else
      w_grant_src = SRC_NONE;
  end
  // Pop on fire (not load) so a stalled TIMER/REFILL beat can be preempted by RT
  // without losing the lower-priority queue entry — SPEC priority rt>refill>timer.
  assign w_rt_preempt = (cs_state == ST_EMIT) && !i_m_tready
                        && w_rt_pending && (r_emit_src != SRC_RT);
  assign w_load_emit  = (cs_state == ST_IDLE && w_grant_src != SRC_NONE)
                        || (w_fire && w_grant_src != SRC_NONE)
                        || w_rt_preempt;
  assign w_refill_pop = w_fire && (r_emit_src == SRC_REFILL);
  assign w_snap_pop   = w_fire && (r_emit_src == SRC_SNAP);

  assign o_refill_ready = 1'b1;
  assign o_snap_ready   = 1'b1;
  assign w_refill_push  = i_refill_valid && o_refill_ready;
  assign w_snap_push    = i_snap_valid && o_snap_ready;

  assign o_m_tdata        = r_m_tdata;
  assign o_m_tvalid       = (cs_state == ST_EMIT);
  assign o_m_tlast        = 1'b1;
  assign o_tx_rt          = r_tx_rt;
  assign o_tx_refill      = r_tx_refill;
  assign o_tx_snap        = r_tx_snap;
  assign o_drop_rt        = r_drop_rt;
  assign o_drop_refill    = r_drop_refill;
  assign o_drop_snap      = r_drop_snap;
  assign o_dbg_cs_state   = cs_state;
  assign o_dbg_err_sticky = r_err_sticky;

  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      cs_state <= ST_IDLE;
    else
      cs_state <= ns_state;
  end

  always_comb begin
    ns_state = cs_state;
    case (cs_state)
      ST_IDLE: begin
        if (w_grant_src != SRC_NONE)
          ns_state = ST_EMIT;
      end
      ST_EMIT: begin
        if (i_m_tready) begin
          if (w_grant_src != SRC_NONE)
            ns_state = ST_EMIT;
          else
            ns_state = ST_IDLE;
        end
      end
      default: ns_state = ST_IDLE;
    endcase
  end

  // RT queue: apply pulse insert/overwrite first, then pop for emit load.
  // SPEC: §6.1 same-symbol overwrite; §6.3 accept while DMA stalled
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    automatic int i, hit, free_i, pop_i;
    automatic logic found_hit, found_free, found_pop, do_pop_rt;
    automatic logic [RT_AW:0] cnt;
    automatic logic slot_vld [0:DEPTH_RT-1];
    automatic logic [15:0] slot_sym [0:DEPTH_RT-1];
    automatic l0_top10_row_t slot_row [0:DEPTH_RT-1];
    if (!sys_rst_n) begin
      r_rt_count <= '0;
      r_drop_rt  <= 32'd0;
      for (i = 0; i < DEPTH_RT; i++)
        r_rt_q[i] <= '0;
    end else begin
      for (i = 0; i < DEPTH_RT; i++) begin
        slot_vld[i] = r_rt_q[i].vld;
        slot_sym[i] = r_rt_q[i].symbol;
        slot_row[i] = r_rt_q[i].row;
      end
      cnt = r_rt_count;
      found_hit = 1'b0;
      found_free = 1'b0;
      found_pop = 1'b0;
      hit = 0; free_i = 0; pop_i = 0;
      if (i_rt_valid) begin
        for (i = 0; i < DEPTH_RT; i++) begin
          if (!found_hit && slot_vld[i] && (slot_sym[i] == i_rt_symbol)) begin
            hit = i;
            found_hit = 1'b1;
          end
          if (!found_free && !slot_vld[i]) begin
            free_i = i;
            found_free = 1'b1;
          end
        end
        if (found_hit) begin
          slot_sym[hit] = i_rt_symbol;
          slot_row[hit] = i_rt_row;
          slot_vld[hit] = 1'b1;
          r_rt_q[hit].symbol <= i_rt_symbol;
          r_rt_q[hit].row    <= i_rt_row;
          r_rt_q[hit].vld    <= 1'b1;
        end else if (found_free) begin
          slot_sym[free_i] = i_rt_symbol;
          slot_row[free_i] = i_rt_row;
          slot_vld[free_i] = 1'b1;
          r_rt_q[free_i].symbol <= i_rt_symbol;
          r_rt_q[free_i].row    <= i_rt_row;
          r_rt_q[free_i].vld    <= 1'b1;
          cnt = cnt + (RT_AW+1)'(1);
        end else
          r_drop_rt <= sat_inc(r_drop_rt);
      end
      // Nit B: pop the slot matching the beat on the wire, not "first vld".
      // Mid-stall may retarget r_m_tdata to a different RT symbol than load order.
      do_pop_rt = w_fire && (r_emit_src == SRC_RT);
      if (do_pop_rt) begin
        automatic logic [15:0] emit_sym;
        emit_sym = r_m_tdata[15:0]; // top10_msg_t.symbol_id at LSB
        for (i = 0; i < DEPTH_RT; i++) begin
          if (!found_pop && slot_vld[i] && (slot_sym[i] == emit_sym)) begin
            pop_i = i;
            found_pop = 1'b1;
          end
        end
        if (found_pop) begin
          r_rt_q[pop_i].vld <= 1'b0;
          cnt = cnt - (RT_AW+1)'(1);
        end
        // If no symbol match: leave queue as-is (avoid first-vld wrong pop)
      end
      r_rt_count <= cnt;
    end
  end

  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    automatic logic [REFILL_AW:0] cnt;
    automatic logic [REFILL_AW-1:0] wr, rd;
    if (!sys_rst_n) begin
      r_refill_wr <= '0;
      r_refill_rd <= '0;
      r_refill_count <= '0;
      r_drop_refill <= 32'd0;
    end else begin
      cnt = r_refill_count; wr = r_refill_wr; rd = r_refill_rd;
      if (w_refill_pop && (cnt != '0)) begin
        rd = rd + REFILL_AW'(1);
        cnt = cnt - (REFILL_AW+1)'(1);
      end
      if (w_refill_push) begin
        if (cnt == (REFILL_AW+1)'(DEPTH_REFILL)) begin
          rd = rd + REFILL_AW'(1);
          cnt = cnt - (REFILL_AW+1)'(1);
          r_drop_refill <= sat_inc(r_drop_refill);
        end
        r_refill_q[wr] <= '{symbol: i_refill_symbol, row: i_refill_row};
        wr = wr + REFILL_AW'(1);
        cnt = cnt + (REFILL_AW+1)'(1);
      end
      r_refill_wr <= wr; r_refill_rd <= rd; r_refill_count <= cnt;
    end
  end

  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    automatic logic [SNAP_AW:0] cnt;
    automatic logic [SNAP_AW-1:0] wr, rd;
    if (!sys_rst_n) begin
      r_snap_wr <= '0;
      r_snap_rd <= '0;
      r_snap_count <= '0;
      r_drop_snap <= 32'd0;
    end else begin
      cnt = r_snap_count; wr = r_snap_wr; rd = r_snap_rd;
      if (w_snap_pop && (cnt != '0)) begin
        rd = rd + SNAP_AW'(1);
        cnt = cnt - (SNAP_AW+1)'(1);
      end
      if (w_snap_push) begin
        if (cnt == (SNAP_AW+1)'(DEPTH_SNAP)) begin
          rd = rd + SNAP_AW'(1);
          cnt = cnt - (SNAP_AW+1)'(1);
          r_drop_snap <= sat_inc(r_drop_snap);
        end
        r_snap_q[wr] <= '{symbol: i_snap_symbol, row: i_snap_row};
        wr = wr + SNAP_AW'(1);
        cnt = cnt + (SNAP_AW+1)'(1);
      end
      r_snap_wr <= wr; r_snap_rd <= rd; r_snap_count <= cnt;
    end
  end

  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    automatic int i, hit;
    automatic logic found;
    automatic logic [15:0] sym;
    automatic l0_top10_row_t row;
    automatic logic [7:0] fl;
    if (!sys_rst_n) begin
      r_m_tdata <= '0;
      r_emit_src <= SRC_NONE;
      r_tx_rt <= 32'd0;
      r_tx_refill <= 32'd0;
      r_tx_snap <= 32'd0;
      r_err_sticky <= 1'b0;
    end else begin
      if (w_fire) begin
        unique case (r_emit_src)
          SRC_RT:     r_tx_rt <= sat_inc(r_tx_rt);
          SRC_REFILL: r_tx_refill <= sat_inc(r_tx_refill);
          SRC_SNAP:   r_tx_snap <= sat_inc(r_tx_snap);
          default:    r_err_sticky <= 1'b1;
        endcase
      end
      if (w_load_emit) begin
        found = 1'b0; hit = 0; sym = '0; row = '0; fl = '0;
        unique case (w_grant_src)
          SRC_RT: begin
            for (i = 0; i < DEPTH_RT; i++) begin
              if (!found && r_rt_q[i].vld) begin
                hit = i; found = 1'b1;
              end
            end
            if (found) begin
              sym = r_rt_q[hit].symbol;
              // Same-cycle overwrite wins over stale queue row
              if (i_rt_valid && (i_rt_symbol == r_rt_q[hit].symbol))
                row = i_rt_row;
              else
                row = r_rt_q[hit].row;
            end
            fl = F_TOP10_RT;
          end
          SRC_REFILL: begin
            sym = r_refill_q[r_refill_rd].symbol;
            row = r_refill_q[r_refill_rd].row;
            fl = F_TOP10_REFILL;
          end
          SRC_SNAP: begin
            sym = r_snap_q[r_snap_rd].symbol;
            row = r_snap_q[r_snap_rd].row;
            fl = F_TOP10_TIMER;
          end
          default: fl = '0;
        endcase
        r_m_tdata <= pack_top10_msg(sym, row, fl);
        r_emit_src <= w_grant_src;
      end
      // Mid-stall RT takes the wire (rt > *). May change symbol vs prior load;
      // RT pop matches r_m_tdata.symbol_id (Nit B). AFTER w_load_emit for NBA win.
      if ((cs_state == ST_EMIT) && !i_m_tready && i_rt_valid) begin
        r_m_tdata  <= pack_top10_msg(i_rt_symbol, i_rt_row, F_TOP10_RT);
        r_emit_src <= SRC_RT;
      end
    end
  end

endmodule

`default_nettype wire
