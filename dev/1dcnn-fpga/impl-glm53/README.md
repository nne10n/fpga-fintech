# impl-glm53 — 1D-CNN FPGA V1 (实施者 A / zcoder glm5.3)

Independent implementation under HANDOFF isolation.  
**Do not read or write `impl-deepseek/`.**

Delivery language (HANDOFF 2026-10-17): **synthesizable SystemVerilog** is the primary DUT (FSM + PE datapath). Behavioral task model archived under `_behavioral/`. HLS C++ under `_legacy_hls/`.

## What is here

| Path | Role |
| --- | --- |
| `include/regs.h` | Frozen AXI-Lite map (Phase1 arch §5.3) |
| `rtl/cnn_pkg.sv` | Types, weight offsets, sat/ReLU helpers |
| `rtl/cnn_engine.sv` | **Primary DUT** — synthesizable FSM (`cs_state`/`ns_state`) + `PE_M=16` × `PE_K_UNROLL=8` |
| `rtl/*.v` | Frontend/glue stubs; top `system_1dcnn_pl` |
| `_behavioral/cnn_engine.sv` | Former task-based whole-net model (reference only) |
| `_legacy_hls/` | Former Vitis HLS `cnn_engine` (optional host compare) |
| `tb/golden_cnn.*` | Independent C++ golden → `vectors/*.golden.bin` |
| `tb/sv_bitexact_main.cpp` | Verilator harness (SV DUT ↔ golden, 0-bit) |
| `vectors/` | ≥32 windows + `weights.bin` + `.golden.bin` |
| `reports/bitexact_result.md` | Latest SV sim result |
| `reports/synth_friendly.md` | Synthesizability notes + cycle math |

## Tool versions on this box (2026-10-17 Asia/Shanghai)

| Tool | Status |
| --- | --- |
| Verilator | 5.032 — **used for SV bit-exact** |
| Icarus Verilog | 12.0 — installed |
| g++ | 14.x — golden + harness |
| Vitis HLS / Vivado | Not installed |

## Quick start (SV bit-exact)

```bash
cd /workspace/1dcnn-fpga/impl-glm53
make all          # weights + vectors + golden + Verilator sv_bitexact
# or:
make sv_bitexact
```

Expected: **32 / 32 PASS**, DUT = `rtl/cnn_engine.sv`, golden = `vectors/*.golden.bin`, **~17420 cycles/window**.

Optional legacy host compare: `make bitexact_hls`.

## Weight / quant

- Layout: `scripts/weight_map.json` (microarch §5.2), 11504 INT16 words.
- Order: **MAC → scale/shift → saturate INT16 → ReLU** (FC: no ReLU).
- Conv1 pad_left=pad_right=6.

## Register notes

- `REG_ID` mnemonic `0x1DCN0101` → **`0x1DC00101`**.
- `STATUS[5] feat_hotswap = 0`; scores via `REG_SCORE0..9`.
- Boundary ports `clk`/`rst_n`; internal `sys_clk`/`sys_rst_n` (async active-low).

## SV DUT notes

- AXIS act in (TLAST on last of 2048); AXIS scores out (10 beats, TLAST on last).
- Three-process FSM; no whole-net `task` in DUT.
- `err_code=0x10` if start without `weight_ok`.
- Latency: **17420 cyc ≈ 174 μs @100 MHz** (NFR-01 ≤500 μs met under declared PE product; DSP folding may be needed on XC7Z020).
