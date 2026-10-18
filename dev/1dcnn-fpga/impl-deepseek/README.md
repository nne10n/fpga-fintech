# 1D-CNN FPGA V1 — Implementer B (`impl-deepseek`) — **RTL delivery**

Synthesizable SystemVerilog DUT (FPGA skill / sv_coding_rules). **No Vitis HLS as delivery subject.**

## Clock / reset map

| This RTL | Phase1 doc |
| --- | --- |
| `sys_clk` / `sys_rst_n` (async active-low) | `clk_pl` / `rst_n` |
| `clk_adc` / `rst_adc_n` | ADC domain |
| Top ports keep `clk_pl`/`rst_n`; assign `sys_clk=clk_pl` inside `system_1dcnn_pl` |

## Layout

```
impl-deepseek/
├── include/regs.h          # frozen map (REG_ID=0x1DC00101)
├── rtl/                    # synthesizable DUT (SV)
│   ├── system_1dcnn_pl.sv  # top
│   ├── cnn_engine.sv       # FSM + sequential PE (real datapath)
│   ├── weight_mem.sv       # 1-cycle sync BRAM + hotswap stub
│   ├── axi_ctrl.sv, score_path.sv, window_buffer.sv, preprocess_fir.sv, adc_frontend.sv
│   └── cnn_params.svh
├── tb/                     # iverilog / verilator harnesses
├── vectors/                # ≥32 cases + weight_map.json
├── ref/                    # Python golden
├── _behavioral/            # SIM-HOST twin only (not DUT)
├── _legacy_hls/            # old HLS (reference only)
├── reports/                # bitexact / resource / sim_summary
└── ps/                     # driver + vote_alarm skeleton
```

## Frozen V1

- Overlap: hop=len (≤2 win/s @ 25.6 kSPS / 2048)
- INT16 act/wgt, INT32 acc; quant **MAC→scale/shift→sat i16→ReLU**
- Conv1 **pad_left=6** (pad_total=12)
- PACK_CH=0; scores `REG_SCORE0..9`; single weight bank + hotswap **reserve** (`feat_hotswap=0`)
- FSM names: `cs_state`/`ns_state`, `cs_mstep`/`ns_mstep`

## Build / sim

See `reports/sim_summary.md`. Tools used: **Icarus 12.0**, **Verilator 5.032**, g++/Python3 (numpy).

## Results (short)

| Check | Result |
| --- | --- |
| Verilator cnn_engine vs golden | **31/36** PASS (5 sat-boundary FC class mismatches) |
| SIM-HOST twin | **36/36** PASS |
| Icarus weight_mem+score_path | PASS |
| NFR-01 latency @ seq PE | **not met** (ESTIMATE ~23 ms@150 MHz) — need PE unroll |

## Non-goals

- HLS as DUT; 50% overlap real-time; dual-bank hotswap function; Vivado bitstream on this box
