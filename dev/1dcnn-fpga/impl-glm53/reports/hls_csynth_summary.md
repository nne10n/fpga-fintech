# HLS csynth summary — impl-glm53

| Field | Value |
| --- | --- |
| Tool on this box | **Vitis HLS / Vivado: NOT installed** |
| Host compiler used | g++ (Debian 14.2.0) |
| Top function | `cnn_engine` (`hls/cnn_engine.cpp`) |
| Part (intended) | xc7z020clg400-1 |
| Clock (intended) | 10 ns (100 MHz) in `hls/run_hls_csim.tcl` |
| PE params | **Declared** `PE_M=16`, `PE_K_UNROLL=8` in `cnn_types.hpp` (host ignores pragmas; latency est. uses these) |

## What was verified here

| Check | Result |
| --- | --- |
| Software compile of HLS sources | PASS (`make hls_csim_host`) |
| Functional csim vs golden (v00_allzero) | PASS — 0-bit match |
| Full 32-vector bit-exact (tb golden) | PASS — see `bitexact_result.md` |
| `csynth_design` II / latency / resources | **N/A** — run on a machine with Vitis HLS: `cd hls && vitis_hls -f run_hls_csim.tcl` then enable `csynth_design` |

## Expected (when csynth available)

Fill from csynth report:

| Metric | Target | Measured |
| --- | --- | --- |
| Latency (cycles) | ≤ 50 000 @100 MHz (500 μs) | _TBD_ |
| II (pipeline) | design-dependent | _TBD_ |
| BRAM | within NFR-06 | _TBD_ |
| DSP | ≤66 | _TBD_ |
| LUT / FF | within NFR-06 | _TBD_ |

## Note

Pragma warnings on host g++ (`ignoring #pragma HLS ...`) are expected outside Vitis HLS.
