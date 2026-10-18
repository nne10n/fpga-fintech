# Resource estimate — impl-glm53 (V1)

> **Update 2026-10-17 (Asia/Shanghai) — synthesizable SV rework:** DUT is now FSM+PE (`PE_M=16`, `PE_K_UNROLL=8`). Verilator measured **17420 cycles/window** → **174.2 μs @100 MHz** (NFR-01 PASS under this PE product). See `reports/synth_friendly.md`. Prior PE_M-only 1275 μs analytical row remains as a conservative alternate if K-unroll is folded for DSP budget.


| Field | Value |
| --- | --- |
| Device | XC7Z020-1CLG400 class |
| Source of numbers | **Estimate** (analytical). Vitis HLS / Vivado **not installed** — no csynth measured figures. |
| Date | 2026-10-17 (Asia/Shanghai) |
| HLS PE params (declared in `hls/cnn_types.hpp`) | **`PE_M=16`**, **`PE_K_UNROLL=8`** |

## NFR-06 budget vs this implementation

| Resource | Budget (NFR-06) | This impl (estimate) | Status |
| --- | --- | --- | --- |
| BRAM | ≤70% (≤440 KB / 630 KB) | **≈ 80.5 KB** used (see breakdown) | PASS (est.) |
| LUT | ≤40% (≈21.3k / 53.2k) | ~8–15k (HLS CNN + stubs) | PASS (est.) |
| DSP | ≤30% (≤66 / 220) | bounded by PE product (see below), ≤66 target | see latency |
| Window latency | ≤500 μs (NFR-01) | **see PE-aligned estimate below** | **at risk / needs csynth** |

## BRAM breakdown (microarch §9)

| Module | Design budget | This impl (est.) | Notes |
| --- | --- | --- | --- |
| weight_mem | ≤80 KB | 11 504 × 2 B = **22.5 KB** | bank0 only; feat_hotswap=0 |
| cnn 特征+行缓存 | ≤292 KB | **≈ 40 KB** | baseline feature maps + K≤16 line |
| window + adc FIFO | ≤64 KB | **≈ 17 KB** | 2×4096×INT16 + FIFO 256×32b |
| other | ≤4 KB | **≈ 1 KB** | coef / regs |
| **合计** | **≤440 KB (70%)** | **≈ 80.5 KB (~12.8%)** | PASS (est.) |

## Latency reasoning — aligned to declared PE (not a fictitious 64-MAC)

Declared in code (`hls/cnn_types.hpp`, microarch defaults):

| Symbol | Value | Role |
| --- | --- | --- |
| `PE_M` | **16** | time-dimension parallelism (pragma / design intent) |
| `PE_K_UNROLL` | **8** | kernel-dimension unroll factor |

**Effective MAC/cycle assumption used here:** treat steady-state as up to  
`PE_M × min(PE_K_UNROLL, K_layer)` **only when both dimensions are fully utilized**.  
Conservative V1 estimate for whole-network average uses **`PE_M = 16` MAC/cycle** (time PE only), because:

- layers have mixed `K` (16/8/3) and channel nesting; K-unroll does not yield a constant 16×8=128 MAC/cycle across the net;
- host functional `cyc_cnt` is **not** HLS schedule latency;
- claiming 64 MAC/cycle is **not** justified by the declared PE product unless a separate PE_COUT=4 (or similar) is coded — **it is not**.

Baseline MAC/window ≈ **2.04×10⁶** (Phase0 §6.1).

| Assumption | Cycles | @100 MHz | @150 MHz | vs NFR-01 ≤500 μs |
| --- | --- | --- | --- | --- |
| **Primary: PE_M=16 MAC/cycle** | ≈ 2.04e6 / 16 = **127 500** | **1275 μs** | **850 μs** | **FAIL estimate** (above 500 μs) |
| Optimistic: PE_M×PE_K peak on Conv1 only (16×8=128) if fully scheduled | best-case layer peak only — **not** used for whole-window claim | — | — | — |
| Floor NFR-01 ≤1 ms | 1275 μs @100 MHz | — | — | above floor at 100 MHz; **850 μs @150 MHz still >500 μs target** |

**Conclusion (honest):** with **only the declared `PE_M=16` / `PE_K_UNROLL=8`**, analytical whole-window latency **does not meet** the ≤500 μs target under a PE_M-only average. Closing the gap requires csynth-proven schedule and/or higher effective parallelism (e.g. channel PE within DSP≤66) — **not claimed in this tree**. NFR-02 (≥2 win/s) remains acquisition-bound (~80 ms/window) so throughput is still OK even if single-window compute is ~1 ms.

## Throughput (NFR-02)

- V1: ≥2 win/s, 2048, HOP=LEN.
- Acquisition @25.6 kHz: 2048/25600 ≈ **80 ms/window** → compute estimate ≪ acquisition → **PASS** for throughput.

## Flags

- All figures **estimate** until Vivado / Vitis HLS reports attached.
- Prior draft that claimed **64-MAC/cycle → 319 μs** is **withdrawn** (that PE width was not declared in HLS sources).
