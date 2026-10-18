# resource_estimate — ESTIMATE (no Vivado synth on this box)

| Resource | Budget (NFR-06) | This impl (ESTIMATE) | Notes |
| --- | --- | --- | --- |
| BRAM | ≤70% (≤440 KB) | ~**80–120 KB** (~18–27%) | weights 23 KB + feat ping-pong ~64 KB + window/FIR/FIFO |
| DSP | ≤30% (≤66) | **1** (seq PE) | scale-out via PE_N for NFR-01 |
| LUT/FF | ≤40% LUT | moderate | FSM + addr + quant; ESTIMATE |
| Window latency | ≤500 μs | **FAIL as seq PE** | 3,421,532 cyc → 34.2 ms@100 MHz / **22.8 ms@150 MHz** |

### Latency math
- Measured (Verilator) cycles/window: **3,421,532** (1 MAC PE + 1-cycle BRAM WAIT on each weight fetch).
- @100 MHz: 34.2 ms; @150 MHz: 22.8 ms — **does not meet NFR-01** with PE_N=1.
- To approach ≤500 μs @150 MHz need ≤75k cycles ≈ **PE_N ≥ ~45** effective MAC/cycle (or layer fusion) — parameter hook left for later; V1 delivery prioritizes bit-exact sequential PE.

### Label
All rows **ESTIMATE** (no `vivado`/`csynth` on box).
