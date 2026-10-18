# Synthesizability checklist — impl-glm53 `cnn_engine`

Date: 2026-10-17 (Asia/Shanghai)

## Verdict

**DUT `rtl/cnn_engine.sv` is written as synthesizable-intent SystemVerilog** (explicit FSM + registered datapath + PE MAC tree). Behavioral whole-net `task` model moved to `_behavioral/cnn_engine.sv` (reference only, not built by `make sv_bitexact`).

## Checklist

| Rule (HANDOFF / sv_coding_rules) | Status |
| --- | --- |
| No `task` / nested-for whole-net compute in DUT | **PASS** — no `task` in `rtl/cnn_engine.sv` |
| Explicit FSM `cs_state` / `ns_state` (three-process) | **PASS** — Proc1 `always_ff` only `cs_state`; Proc2 `always_comb` only `ns_state`; Proc3 datapath |
| `sys_clk` / `sys_rst_n` async active-low | **PASS** — aliases from boundary `clk`/`rst_n` (TB compatibility) |
| `always_ff` / `always_comb` only for compute path | **PASS** |
| PE params declared | **`PE_M=16`**, **`PE_K_UNROLL=8`** |
| Quant order MAC→scale/shift→sat→ReLU | **PASS** (FC: no ReLU) |
| Cycle count reflects schedule (≫ 2059) | **PASS** — measured **17420** cyc/window |

## PE / schedule

- Conv tiles: for each `(ot, oc_group)` → `ST_BIAS` (1) + `ST_MAC` (`cin × ceil(K/PE_K_UNROLL)`) + `ST_QUANT` (1).
- Each MAC cycle: `PE_M` output channels × up to `PE_K_UNROLL` kernel taps (combinational product tree → registered accumulate).
- Pool / GAP / FC: explicit states, PE_M-wide where applicable; FC uses 1 IC/cycle × 10 OC (masked to `N_CLASS`).

### Analytical MAC cycles (compute only, excl. recv/emit)

| Stage | Tiles | MAC/tile | BIAS+QUANT | Est. cycles |
| --- | --- | --- | --- | --- |
| Conv1 | 512×1 | 1×2=2 | +2 | ≈2048 |
| Conv2 | 127×2 | 16×1=16 | +2 | ≈4572 |
| Pool | 63×2 | — | 1/tile | ≈126 |
| Conv3 | 61×4 | 32×1=32 | +2 | ≈8296 |
| GAP | 4 groups | 61 ACC + 1 Q | | ≈248 |
| FC | 1 | 64 MAC + bias/q | | ≈66 |
| **Sum compute** | | | | **≈15356** |
| + AXIS recv 2048 + LCFG/emit | | | | **≈17420** (matches sim) |

## Latency vs NFR-01 (@100 MHz)

| Metric | Value |
| --- | --- |
| Measured `cyc_cnt` / window | **17420** |
| Wall @100 MHz | **174.2 μs** |
| NFR-01 ≤500 μs | **PASS (estimate / sim cycles)** |
| @150 MHz | **≈116 μs** |

Notes: DSP count for a true `PE_M×PE_K_UNROLL=128` multiply array may exceed NFR-06 DSP≤66 on XC7Z020 — folding / time-multiplex of the PE tree may be required at place-and-route; **cycle count above assumes the declared PE product is instantiated**. Vivado csynth/impl not available on this box.

## Remaining non-synth constructs in DUT

**None intended.** Helpers `sat_i16` / `relu_i16` are package functions (combinational, synthesizable). Unpacked arrays (`act_mem`, `wgt_mem`, `buf_*`) are for BRAM inference; multi-port concurrent reads in the PE tree are simulation-friendly and may need banking for real FPGA QoR.

## Build

```bash
make sv_bitexact   # Verilator DUT = rtl/cnn_engine.sv
```
