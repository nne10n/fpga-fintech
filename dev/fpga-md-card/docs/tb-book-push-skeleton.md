# TB skeleton: book-push-refill-v2 (P2)

**P2 DUT = `book_push_refill_top`** via `book_push_refill_tb_glue` (not bare `book_push_engine`).  
Engine unit tests: `tb_push/` / `make sim-push`.

```bash
make sim-book-push
```

| Path | Role |
|---|---|
| `rtl/book_push_refill_top.sv` | **Real** DUT — DDR CDC + DMA (no User AXI) |
| `tb_book_push/book_push_refill_tb_glue.sv` | Flat cocotb ↔ top + AXI shell (A1–A5) |
| `tb_book_push/tb_book_push_top.sv` | Harness + `axi_ddr_model` + sticky asserts |
| `tb_book_push/push_helpers.py` / `test_p2_*.py` | Five P2 classes |
| `tb_book_push/COVERPOINTS.md` | Hierarchy, port map, ASSERT split |
| `tb_book_push/book_push_engine_stub.sv` | **DEPRECATED** — not in `BOOK_PUSH_RTL` |

Hierarchy: `tb_book_push_top.u_dut`(glue)`.u_top`(real top)`.u_push|u_refill|u_snap`.

A1–A5 on glue AXI shell; T-A7/A8/PRI/SEQ/SKIP live; **T-A6 Live (hierarchical)** on `u_dut.u_top` — see COVERPOINTS.

Sim `N_SYM=32` (prod `N_SYM=4096`). Do not change `event_t`.
