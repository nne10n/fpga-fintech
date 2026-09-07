// -----------------------------------------------------------------------------
// book_pkg.sv — L0 hot Top-10 book types (SZSE / X1100)
// Does NOT alter md_pkg::event_t layout.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps

package book_pkg;
  import md_pkg::*;

  localparam int N_HOT      = 64;
  localparam int N_ORDER    = 4096;
  localparam int ORDER_AW   = 12;   // log2(N_ORDER)
  localparam int N_PROBE    = 4;
  localparam int TOP_N      = 10;
  localparam int HOT_AW     = 6;    // log2(N_HOT)

  // Side encoding (matches SZSE synth / module-design): 1=bid, 2=ask
  localparam logic [1:0] SIDE_BID = 2'd1;
  localparam logic [1:0] SIDE_ASK = 2'd2;

  // Op decode from event (L0 v1 convention for synth + book_engine):
  //   CH_ORDER + msg_type==2 → ADD
  //   CH_ORDER + msg_type==4 → CXL
  //   CH_TRADE               → TRADE
  typedef enum logic [2:0] {
    OP_ADD   = 3'd0,
    OP_CXL   = 3'd1,
    OP_TRADE = 3'd2,
    OP_NOP   = 3'd7
  } book_op_e;

  localparam logic [7:0] MSG_ADD = 8'd2;
  localparam logic [7:0] MSG_CXL = 8'd4;

  typedef struct packed {
    logic        valid;
    logic [63:0] order_id;
    logic [HOT_AW:0] hot_id; // 1..N_HOT (0 = none)
    logic [1:0]  side;
    logic [63:0] px;
    logic [31:0] qty;
  } order_slot_t;

  typedef struct packed {
    logic        valid;
    logic [63:0] px;
    logic [31:0] qty;
  } level_t;

  typedef struct packed {
    book_op_e          op;
    logic [63:0]       order_id;
    logic [HOT_AW:0]   hot_id;     // 0 if non-hot
    logic [47:0]       code;
    logic [1:0]        side;
    logic [63:0]       px;
    logic [31:0]       qty;
    logic [31:0]       seq;
    logic [63:0]       ts_ns;
  } l1_cmd_t;

  // One level change notification (L0 delta)
  typedef struct packed {
    logic              valid;       // payload valid
    logic [HOT_AW:0]   hot_id;
    logic [1:0]        side;
    logic [3:0]        level;       // 0..9
    logic              level_valid; // 0 → slot cleared / empty
    logic [63:0]       px;
    logic [31:0]       qty;
    logic [31:0]       seq;
    logic [63:0]       ts_ns;
    book_op_e          op;
  } book_delta_t;

  function automatic book_op_e decode_book_op(input event_t e);
    if (e.ch == CH_TRADE)
      return OP_TRADE;
    if (e.ch == CH_ORDER) begin
      if (e.msg_type == MSG_CXL)
        return OP_CXL;
      // default ORDER (msg_type==2 or other) → ADD
      return OP_ADD;
    end
    return OP_NOP;
  endfunction

  function automatic logic [ORDER_AW-1:0] hash_oid(input logic [63:0] oid);
    return oid[11:0] ^ oid[23:12] ^ oid[35:24] ^ oid[47:36];
  endfunction

  // Bid: higher px is better; Ask: lower px is better
  function automatic logic px_better(
      input logic [1:0]  side,
      input logic [63:0] a,
      input logic [63:0] b
  );
    if (side == SIDE_BID)
      return a > b;
    else
      return a < b;
  endfunction

  function automatic logic px_worse(
      input logic [1:0]  side,
      input logic [63:0] a,
      input logic [63:0] b
  );
    return px_better(side, b, a);
  endfunction

  // ---------------------------------------------------------------------------
  // P0 frozen (2026-09-04): 4096×Top-10 push + DDR best16 refill
  // See docs/p0-top10-axi-contract.md / book-push-refill-v2.md
  // N_HOT remains for L0 order_cache/hot_cam until P1 migrates view RAM to N_SYM.
  // ---------------------------------------------------------------------------
  localparam int N_SYM            = 4096;
  localparam int N_SYM_AW         = 12;    // log2(N_SYM)
  localparam int BEST16_N         = 16;
  localparam int BEST16_SLOT_B    = 16;    // bytes per slot
  localparam int BEST16_STRIDE_B  = 512;   // 2 sides × 16 slots × 16B
  localparam int BEST16_SIDE_B    = 256;   // 16 × 16B (one side)

  // Default byte bases (CSR may override); LEVEL size must match l1_ddr_engine
  localparam logic [63:0] BASE_ORDER_DEFAULT  = 64'h0;
  // Placeholders — RTL params N_ORDER_L1/N_LEVEL_L1 own the real stride
  localparam logic [63:0] BASE_BEST16_DEFAULT = 64'h0; // set at elab: LEVEL_BASE + N_LEVEL*64

  localparam logic [7:0] F_TOP10_RT     = 8'h01;
  localparam logic [7:0] F_TOP10_TIMER  = 8'h02;
  localparam logic [7:0] F_TOP10_REFILL = 8'h04;

  // AXI4-MM User Logic master (p0-top10-axi-contract.md §3 — FROZEN)
  localparam int AXI_DATA_W         = 512;
  localparam int AXI_ADDR_W         = 33;
  localparam int AXI_ID_W           = 4;
  localparam int AXI_MAX_OUTSTAND   = 4;
  localparam int AXI_BEAT_B         = 64;   // bytes / beat @ DATA_W=512
  localparam int AXI_SIZE_64B       = 6;    // $clog2(64); awsize/arsize
  localparam int REFILL_MAX_OUTSTAND = 2;   // QoS: refill ≤1–2 of MAX_OUTSTAND

  // Flat packed msg: level0 (best) in LSBs of each *_px/*_qty vector.
  // Width 2080b = 260B; DMA desc uses TOP10_MSG_BYTES (pad buffer to 256B align
  // externally if ring requires — payload itself is 260B).
  typedef struct packed {
    logic [19:0]      pad;
    logic [319:0]     ask_qty;   // 10×32
    logic [639:0]     ask_px;    // 10×64
    logic [9:0]       ask_vld;
    logic [319:0]     bid_qty;
    logic [639:0]     bid_px;
    logic [9:0]       bid_vld;
    logic [7:0]       flags;
    logic [31:0]      seq;
    logic [63:0]      ts_ns;
    logic [15:0]      symbol_id;
  } top10_msg_t;

  localparam int TOP10_MSG_W      = $bits(top10_msg_t); // 2080
  localparam int TOP10_MSG_BYTES  = TOP10_MSG_W / 8;    // 260

  function automatic logic [63:0] top10_get_px(
      input logic [639:0] px_vec,
      input int unsigned  lvl
  );
    top10_get_px = px_vec[lvl*64 +: 64];
  endfunction

  function automatic logic [31:0] top10_get_qty(
      input logic [319:0] qty_vec,
      input int unsigned  lvl
  );
    top10_get_qty = qty_vec[lvl*32 +: 32];
  endfunction

  // ---------------------------------------------------------------------------
  // P1 parallel L0 banks + refill types (docs/p1-parallel-partition.md)
  // ---------------------------------------------------------------------------
  localparam int N_L0_BANK    = 4;
  localparam int N_L0_BANK_AW = 2;                      // log2(N_L0_BANK)
  localparam int N_L0_DEPTH   = N_SYM / N_L0_BANK;      // 1024
  localparam int N_L0_AW      = 10;                     // log2(N_L0_DEPTH)

  // L0 row storage (no flags/symbol — those ride the push path)
  // SPEC: book-push-refill-v2.md §2.1; p1-parallel-partition.md §5
  typedef struct packed {
    logic [31:0]  seq;
    logic [63:0]  ts_ns;
    logic [9:0]   bid_vld;
    logic [9:0]   ask_vld;
    logic [639:0] bid_px;
    logic [319:0] bid_qty;
    logic [639:0] ask_px;
    logic [319:0] ask_qty;
  } top10_view_t;

  localparam int TOP10_VIEW_W = $bits(top10_view_t);

  function automatic logic [N_L0_BANK_AW-1:0] l0_bank_id(
      input logic [N_SYM_AW-1:0] symbol_id
  );
    return symbol_id[N_L0_BANK_AW-1:0];
  endfunction

  function automatic logic [N_L0_AW-1:0] l0_bank_addr(
      input logic [N_SYM_AW-1:0] symbol_id
  );
    return symbol_id[N_SYM_AW-1:N_L0_BANK_AW];
  endfunction

  function automatic logic top10_view_empty(input top10_view_t v);
    return (v.bid_vld == 10'b0) && (v.ask_vld == 10'b0);
  endfunction

  function automatic top10_msg_t top10_pack_msg(
      input top10_view_t   v,
      input logic [15:0]   symbol_id,
      input logic [7:0]    flags
  );
    top10_msg_t m;
    m = '0;
    m.symbol_id = symbol_id;
    m.ts_ns     = v.ts_ns;
    m.seq       = v.seq;
    m.flags     = flags;
    m.bid_vld   = v.bid_vld;
    m.bid_px    = v.bid_px;
    m.bid_qty   = v.bid_qty;
    m.ask_vld   = v.ask_vld;
    m.ask_px    = v.ask_px;
    m.ask_qty   = v.ask_qty;
    return m;
  endfunction

  // SPEC: p1-parallel-partition.md §7 / book-push-refill-v2.md §4
  typedef struct packed {
    logic [15:0] symbol_id;
    logic [1:0]  side;       // SIDE_BID / SIDE_ASK
    logic [31:0] seq_start;
  } refill_req_t;

  // Side-specific best10 payload from DDR best16[0..9]
  typedef struct packed {
    logic [15:0]  symbol_id;
    logic [1:0]   side;
    logic [31:0]  seq_start;
    logic [9:0]   lvl_vld;
    logic [639:0] lvl_px;
    logic [319:0] lvl_qty;
  } refill_rsp_t;

  function automatic top10_view_t top10_apply_refill_side(
      input top10_view_t  v,
      input logic [1:0]   side,
      input logic [9:0]   lvl_vld,
      input logic [639:0] lvl_px,
      input logic [319:0] lvl_qty
  );
    top10_view_t o;
    o = v;
    if (side == SIDE_BID) begin
      o.bid_vld = lvl_vld;
      o.bid_px  = lvl_px;
      o.bid_qty = lvl_qty;
    end else begin
      o.ask_vld = lvl_vld;
      o.ask_px  = lvl_px;
      o.ask_qty = lvl_qty;
    end
    return o;
  endfunction

  function automatic logic [63:0] best16_addr(
      input logic [63:0] base_best16,
      input logic [N_SYM_AW-1:0] symbol_id,
      input logic                is_ask,  // 0=bid 1=ask
      input logic [3:0]          slot     // 0..15
  );
    best16_addr = base_best16
                + ({{(64-N_SYM_AW){1'b0}}, symbol_id} * BEST16_STRIDE_B)
                + (is_ask ? BEST16_SIDE_B : 64'd0)
                + ({{60{1'b0}}, slot} * BEST16_SLOT_B);
  endfunction



  // ---------------------------------------------------------------------------
  // P1.0 deliverable aliases / row type (additive; keep top10_view_t)
  // SPEC: docs/p1-push-refill-handoff.md P1.0
  // ---------------------------------------------------------------------------
  localparam int L0_N_BANK  = N_L0_BANK;           // 4
  localparam int L0_BANK_AW = N_SYM_AW - 2;         // 10 — symbols per bank = 1024

  typedef struct packed {
    logic         nonempty;   // any bid/ask vld
    logic [31:0]  seq;
    logic [63:0]  ts_ns;
    logic [9:0]   bid_vld;
    logic [9:0]   ask_vld;
    logic [639:0] bid_px;     // lvl0 best in LSBs
    logic [319:0] bid_qty;
    logic [639:0] ask_px;
    logic [319:0] ask_qty;
  } l0_top10_row_t;

  localparam int L0_TOP10_ROW_W = $bits(l0_top10_row_t);

  function automatic top10_msg_t pack_top10_msg(
      input logic [15:0]   symbol_id,
      input l0_top10_row_t row,
      input logic [7:0]    flags
  );
    top10_msg_t m;
    m.pad       = '0;
    m.ask_qty   = row.ask_qty;
    m.ask_px    = row.ask_px;
    m.ask_vld   = row.ask_vld;
    m.bid_qty   = row.bid_qty;
    m.bid_px    = row.bid_px;
    m.bid_vld   = row.bid_vld;
    m.flags     = flags;
    m.seq       = row.seq;
    m.ts_ns     = row.ts_ns;
    m.symbol_id = symbol_id;
    return m;
  endfunction

  function automatic l0_top10_row_t view_to_l0_row(input top10_view_t v);
    l0_top10_row_t r;
    r.nonempty = !top10_view_empty(v);
    r.seq      = v.seq;
    r.ts_ns    = v.ts_ns;
    r.bid_vld  = v.bid_vld;
    r.ask_vld  = v.ask_vld;
    r.bid_px   = v.bid_px;
    r.bid_qty  = v.bid_qty;
    r.ask_px   = v.ask_px;
    r.ask_qty  = v.ask_qty;
    return r;
  endfunction

  function automatic top10_view_t l0_row_to_view(input l0_top10_row_t r);
    top10_view_t v;
    v.seq     = r.seq;
    v.ts_ns   = r.ts_ns;
    v.bid_vld = r.bid_vld;
    v.ask_vld = r.ask_vld;
    v.bid_px  = r.bid_px;
    v.bid_qty = r.bid_qty;
    v.ask_px  = r.ask_px;
    v.ask_qty = r.ask_qty;
    return v;
  endfunction


endpackage
