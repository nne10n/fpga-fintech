// -----------------------------------------------------------------------------
// dec_sse_fast.sv — Synthetic FAST template decoder (M9)
//
// v1.0 hard-coded wire layout (NOT exchange FAST template PDF):
//   [0]     PMap / msg_type  (1 byte)
//   [1..6]  security code ASCII (6 bytes)
//   [7..10] seq u32 big-endian
//   [11..18] px u64 big-endian  (design §3.5 said u32; use u64 to match
//            event_t.px / Binary TB — see README)
//   [19..22] qty u32 big-endian
// MIN_LEN = 23. Network/big-endian; AXIS first byte = tdata[7:0].
//
// exch=EXCH_SSE, ch=CH_SNAP (fixed), msg_type=PMap byte,
// ts_ns=tuser.sop_ts, symbol_id=0, flags=0, side=0, order_id=0.
// Store-and-forward; emit on tlast+1. m_code sideband same as dec_bin_generic.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module dec_sse_fast
  import md_pkg::*;
#(
  parameter int BUF_BYTES = 64
) (
  input  logic         sys_clk,
  /* verilator lint_off SYNCASYNCNET */
  input  logic         sys_rst_n,
  /* verilator lint_on SYNCASYNCNET */
  input  logic [63:0]  i_s_tdata,
  input  logic [7:0]   i_s_tkeep,
  input  logic         i_s_tvalid,
  input  logic         i_s_tlast,
  output logic         o_s_tready,
  input  pay_tuser_t   i_s_tuser,
  output logic [511:0] o_m_event_tdata,
  output logic         o_m_event_tvalid,
  output logic         o_m_event_tlast,
  input  logic         i_m_event_tready,
  output logic [47:0]  o_m_code,
  output logic [31:0]  o_msg_ok,
  output logic [31:0]  o_msg_bad,
  (* keep = "true" *) output logic [1:0] o_dbg_cs_state,
  (* keep = "true" *) output logic       o_dbg_err_sticky
);

  assign o_s_tready = 1'b1;

  localparam int unsigned BUF_MAX  = BUF_BYTES;
  localparam int unsigned MIN_LEN  = 23;
  localparam int unsigned OFF_PMAP = 0;
  localparam int unsigned OFF_CODE = 1;
  localparam int unsigned OFF_SEQ  = 7;
  localparam int unsigned OFF_PX   = 11;
  localparam int unsigned OFF_QTY  = 19;

  typedef enum logic [1:0] {
    ST_IDLE = 2'd0,
    ST_BUF  = 2'd1,
    ST_DROP = 2'd2
  } state_e;

  // ---- FSM ----
  state_e cs_state;
  state_e ns_state;

  // ---- store-and-forward buffer ----
  logic [7:0] r_mem [0:BUF_MAX-1];
  logic [8:0] r_len;
  logic       r_ovf;
  pay_tuser_t r_tuser;
  logic [7:0] w_mem [0:BUF_MAX-1];
  logic [8:0] w_len;
  logic       w_ovf;
  pay_tuser_t w_tuser;

  // ---- emit / counters ----
  logic [31:0] r_ok;
  logic [31:0] r_bad;
  event_t      r_ev;
  logic [47:0] r_code;
  logic        r_emit;
  logic        r_err_sticky;

  assign o_msg_ok         = r_ok;
  assign o_msg_bad        = r_bad;
  assign o_m_event_tdata  = r_ev;
  assign o_m_event_tvalid = r_emit;
  assign o_m_event_tlast  = 1'b1;
  assign o_m_code         = r_code;
  assign o_dbg_cs_state   = cs_state;
  assign o_dbg_err_sticky = r_err_sticky;

  function automatic logic [31:0] sat_inc(input logic [31:0] c);
    return (c == 32'hFFFF_FFFF) ? c : (c + 32'd1);
  endfunction

  function automatic logic [31:0] be_u32(
      input logic [7:0] m [0:BUF_MAX-1],
      input int unsigned off
  );
    return {m[off], m[off+1], m[off+2], m[off+3]};
  endfunction

  function automatic logic [63:0] be_u64(
      input logic [7:0] m [0:BUF_MAX-1],
      input int unsigned off
  );
    return {m[off], m[off+1], m[off+2], m[off+3],
            m[off+4], m[off+5], m[off+6], m[off+7]};
  endfunction

  function automatic logic [47:0] extract_code(
      input logic [7:0] m [0:BUF_MAX-1]
  );
    // char0 → [7:0] (matches sym_cam / Binary decoders)
    return {m[OFF_CODE+5], m[OFF_CODE+4], m[OFF_CODE+3],
            m[OFF_CODE+2], m[OFF_CODE+1], m[OFF_CODE]};
  endfunction

  function automatic event_t build_event(
      input logic [7:0] m [0:BUF_MAX-1],
      input pay_tuser_t tu
  );
    event_t ev;
    ev           = '0;
    ev.pad       = '0;
    ev.raw_ptr   = '0;
    ev.queue_pos = '0;
    ev.level     = '0;
    ev.order_id  = 64'h0;
    ev.side      = 2'b00;
    ev.qty       = be_u32(m, OFF_QTY);
    ev.px        = be_u64(m, OFF_PX);
    ev.flags     = 8'h0;
    ev.msg_type  = m[OFF_PMAP];
    ev.ch        = CH_SNAP[3:0];
    ev.exch      = EXCH_SSE[1:0];
    ev.symbol_id = 16'h0;
    ev.seq       = be_u32(m, OFF_SEQ);
    ev.ts_ns     = tu.sop_ts;
    return ev;
  endfunction

  // Register current FSM state.
  // SPEC: module-design-v1.md §3.5
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      cs_state <= ST_IDLE;
    else
      cs_state <= ns_state;
  end

  // Fill store-and-forward buffer and detect overflow this beat.
  // SPEC: module-design-v1.md §3.5
  always_comb begin
    automatic int bi;
    automatic logic [8:0] n;
    automatic logic ov;
    for (bi = 0; bi < BUF_MAX; bi++)
      w_mem[bi] = r_mem[bi];
    n       = r_len;
    ov      = r_ovf;
    w_tuser = r_tuser;
    if (i_s_tvalid && (cs_state == ST_IDLE)) begin
      w_tuser = i_s_tuser;
      n  = 9'd0;
      ov = 1'b0;
      for (bi = 0; bi < 8; bi++) begin
        if (i_s_tkeep[bi]) begin
          if (n < BUF_MAX[8:0]) begin
            w_mem[n] = i_s_tdata[8*bi +: 8];
            n = n + 9'd1;
          end else
            ov = 1'b1;
        end
      end
    end else if (i_s_tvalid && (cs_state == ST_BUF)) begin
      for (bi = 0; bi < 8; bi++) begin
        if (i_s_tkeep[bi]) begin
          if (n < BUF_MAX[8:0]) begin
            w_mem[n] = i_s_tdata[8*bi +: 8];
            n = n + 9'd1;
          end else
            ov = 1'b1;
        end
      end
    end
    w_len = n;
    w_ovf = ov;
  end

  // Select next FSM state from tlast / overflow (store-and-forward).
  // SPEC: module-design-v1.md §3.5
  always_comb begin
    ns_state = cs_state;
    case (cs_state)
      ST_IDLE: begin
        if (i_s_tvalid && i_s_tlast)
          ns_state = ST_IDLE;
        else if (i_s_tvalid && w_ovf)
          ns_state = ST_DROP;
        else if (i_s_tvalid)
          ns_state = ST_BUF;
      end
      ST_BUF: begin
        if (i_s_tvalid && i_s_tlast)
          ns_state = ST_IDLE;
        else if (i_s_tvalid && w_ovf)
          ns_state = ST_DROP;
      end
      ST_DROP: begin
        if (i_s_tvalid && i_s_tlast)
          ns_state = ST_IDLE;
      end
      default: ns_state = ST_IDLE;
    endcase
  end

  // Capture payload bytes, running length, overflow, and SOP tuser.
  // SPEC: module-design-v1.md §3.5
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    automatic int bi;
    if (!sys_rst_n) begin
      r_len   <= '0;
      r_ovf   <= 1'b0;
      r_tuser <= '0;
      for (bi = 0; bi < BUF_MAX; bi++)
        r_mem[bi] <= 8'h0;
    end else if (i_s_tvalid && (cs_state == ST_IDLE || cs_state == ST_BUF)) begin
      r_len   <= w_len;
      r_ovf   <= w_ovf;
      r_tuser <= w_tuser;
      for (bi = 0; bi < BUF_MAX; bi++)
        r_mem[bi] <= w_mem[bi];
    end else if (i_s_tvalid && i_s_tlast && (cs_state == ST_DROP)) begin
      r_len <= '0;
      r_ovf <= 1'b0;
    end
  end

  // Emit event on tlast+1; handshake increments ok, else bad; short/ovf inc bad.
  // SPEC: module-design-v1.md §3.5
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
      r_ok   <= '0;
      r_bad  <= '0;
      r_ev   <= '0;
      r_code <= '0;
      r_emit <= 1'b0;
    end else begin
      if (r_emit) begin
        if (i_m_event_tready)
          r_ok <= sat_inc(r_ok);
        else
          r_bad <= sat_inc(r_bad);
      end
      r_emit <= 1'b0;
      if (i_s_tvalid && i_s_tlast && (cs_state == ST_DROP))
        r_bad <= sat_inc(r_bad);
      else if (i_s_tvalid && i_s_tlast && (cs_state == ST_IDLE || cs_state == ST_BUF)
               && (w_ovf || (w_len < MIN_LEN[8:0])))
        r_bad <= sat_inc(r_bad);
      else if (i_s_tvalid && i_s_tlast && (cs_state == ST_IDLE || cs_state == ST_BUF)
               && !w_ovf && (w_len >= MIN_LEN[8:0])) begin
        r_ev   <= build_event(w_mem, w_tuser);
        r_code <= extract_code(w_mem);
        r_emit <= 1'b1;
      end
    end
  end

  // Sticky illegal-state flag.
  // SPEC: module-design-v1.md §3.5
  always_ff @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
      r_err_sticky <= 1'b0;
    else if ((cs_state != ST_IDLE) && (cs_state != ST_BUF) && (cs_state != ST_DROP))
      r_err_sticky <= 1'b1;
  end

endmodule

`default_nettype wire
