# book-push-refill-v2 P2 coverpoints + assertions

**P2 DUT = `book_push_refill_top`** (via TB glue) — NOT bare `book_push_engine`.  
Engine unit tests: `tb_push/` (`make sim-push`) — separate.

## Hierarchy (current, locked)

```text
tb_book_push_top
  u_dut  = book_push_refill_tb_glue     # flat cocotb ↔ top + AXI shell
    u_top = book_push_refill_top        # REAL RTL
      u_l0_mem / u_snap / u_refill / u_push
  u_ddr  = axi_ddr_model                # shell AR/R peer
```

Harness: `tb_book_push/tb_book_push_top.sv`  
Glue: `tb_book_push/book_push_refill_tb_glue.sv`  
Top: `rtl/book_push_refill_top.sv`  
Contract: `docs/book-push-refill-v2.md`, `docs/p0-top10-axi-contract.md` §3 (**FROZEN**)  
Run: `make sim-book-push` (sim `N_SYM=32`; prod `book_pkg::N_SYM=4096`)

Top boundary: **DDR CDC** (`o_ddr_req_*` / `i_ddr_rsp_*`) + **DMA** (`o_dma_valid` / `i_dma_ready` / `o_dma_msg`) — **no** User AXI on top.

Obsolete: `book_push_engine_stub.sv` is **not** in `BOOK_PUSH_RTL` (DEPRECATED leftover).

## Port map — top ↔ glue / flat TB

| `book_push_refill_top` port | Role | Glue / flat observe |
|---|---|---|
| `sys_clk` / `sys_rst_n` | Clock / reset | `clk` / `rst_n` (+ `clear`) |
| `i_rt_valid`, `i_rt_symbol`, `i_rt_row` | Hot-path RT push (pulse; no BP) | `rt_valid` + flat `rt_*` → glue packs `l0_top10_row_t` |
| `i_refill_req_valid`, `i_refill_req` | Soft refill / gap trigger | `csr_refill_kick` + symbol/side, or auto from dig-hole |
| `i_snap_enable`, `i_snap_skip_empty`, `i_period_cycles` | Snap CSR | `csr_enable` / `csr_snap_skip_empty` / `csr_period_cycles` |
| `o_ddr_req_*` / `i_ddr_rsp_*` | DDR CDC | Glue AXI shell (`m_axi_ar*` / R) + `b16_*` poke payload |
| `o_dma_valid`, `i_dma_ready`, `o_dma_msg` | DMA sink | `push_valid/ready` + flat `push_*` / `push_flags` |
| `i_hot_upd_*` / `o_hot_upd_*` | Port-A L0 | Driven by glue on RT update |
| `o_dbg_*` | Debug | Counters via hierarchical peek (`u_top.u_push` / `u_refill` / `u_snap`) |

Flat cocotb port names stay frozen (helpers/tests).

## Five P2 coverage classes

| ID | Coverpoint (top behavior) | Observe | Test |
|---|---|---|---|
| CP1 | Gap refill → best16 → DMA `F_TOP10_REFILL` | ddr req/rsp → `o_dma_msg.flags` | `test_p2_gap_refill` |
| CP2 | Timer snap (`i_period_cycles`; prod 4096@10ms) | snap CSR → `F_TOP10_TIMER` | `test_p2_timer_snap` |
| CP3 | Priority **rt > refill > timer** | concurrent RT vs refill/snap → DMA order | `test_p2_rt_preempt` |
| CP4 | Seq gate: stale discard (+ reissue) | `u_top.u_refill` stale / `refill_discard_cnt` | `test_p2_refill_seq` |
| CP5 | `i_snap_skip_empty=1` skips empty | no DMA for empty sym | `test_p2_skip_empty` |

## ASSERT split

### On top path (DMA / hot-path) — harness sticky `a_fail`

| ID | Check | Status |
|---|---|---|
| T-A7 | `o_dma_msg.flags` one-hot among `{rt,timer,refill}` | **Live** on `push_flags` |
| T-PRI | RT preempts refill/snap | **Live** via CP3 / `last_grant` |
| T-SEQ | refill stale discard | **Live** via CP4 |
| T-SKIP | skip_empty | **Live** via CP5 |
| T-A8 | No User AXI AW on DMA path | **Live** (`awvalid` must stay 0) |
| T-A9 | Sim `ASYNC=0` | Documented |
| T-A6 | Hot-path never waits DDR rsp / req ready | **Live (hierarchical on u_top)**: when `u_dut.u_top.i_rt_valid` rises while DDR busy/blocked (`o_ddr_rsp_ready && !i_ddr_rsp_valid` OR `o_ddr_req_valid && !i_ddr_req_ready`), RT must progress within 1–2 cycles (`u_push.o_tx_rt` / `o_drop_rt` or RT on DMA). Glue `rt_ready=1` / `hot_path_stall=0` are pulse/legal-by-construction only — not the sole check. **Limits**: no formal `bind` module; approximate (not a full combo-gate cone check); arms only on concurrent DDR-blocked RT |

### Glue AXI shell (`BIND_TO_AXI_SHELL`) — live now on `u_dut` `m_axi_*`

| ID | Check |
|---|---|
| A1 | `arsize == 6` ($clog2(64)) |
| A2 | AR 64B aligned |
| A3 | `BASE_BEST16 + symbol*512`; residual 0 or 256 |
| A4 | `outstanding_total ≤ 4` |
| A5 | `outstanding_refill ≤ 2` (QoS) |
| ELAB | DATA_W=512, ADDR_W=33, ID_W=4, msg 2080b/260B, STRIDE=512 |

### BIND_TO_RTL hierarchy

- P2 top props → `u_dut.u_top`
- Engine-only → `u_dut.u_top.u_push` (covered by `tb_push/`, not this suite)
- Refill seq → `u_dut.u_top.u_refill`
- Snap skip → `u_dut.u_top.u_snap`
- A1–A5 → glue shell (or future board AXI shell)

## Status / remaining gaps

- **DONE**: real `book_push_refill_top` via glue; CP1–CP5; A1–A5/A7/A8 live; `make sim-book-push` target.
- **DONE**: T-A6 **Live (hierarchical on u_top)** — harness BIND in `tb_book_push_top.sv`; cocotb exercises RT under `l1_rmw_pri_hold` / mid-RTT rsp wait.
- **OPEN**: optional delete DEPRECATED `book_push_engine_stub.sv` when nobody references it.
- **LIMIT (T-A6)**: property arms only when RT coincides with DDR blocked; does not prove absence of all gating cones; Verilator hierarchical ports used (no extra RTL probes).
