# sim_summary — Implementer B RTL redo

| Item | Value |
| --- | --- |
| Date | 2026-10-17 Asia/Shanghai |
| iverilog | 12.0 — `tb/tb_wmem_score` PASS |
| verilator | 5.032 — `tb/tb_cnn_engine_wrap` + `cnn_engine`/`weight_mem` |
| Verilator bitexact | **31/36 PASS** (see bitexact_result.md) |
| SIM-HOST twin | **36/36 PASS** (`_behavioral/rtl_twin_host`) |
| Waves | not dumped (log evidence only) |

### How to reproduce
```bash
cd /workspace/1dcnn-fpga/impl-deepseek
# Icarus smoke
iverilog -g2012 -o tb/sim_wmem_score rtl/weight_mem.sv rtl/score_path.sv tb/tb_wmem_score.sv && vvp tb/sim_wmem_score
# Verilator cnn_engine (N cases)
verilator -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-BLKANDNBLK \
  --cc --exe -O3 --build -j 4 -Irtl --top-module tb_cnn_engine_wrap \
  rtl/weight_mem.sv rtl/cnn_engine.sv tb/tb_cnn_engine_wrap.sv tb/tb_cnn_engine.cpp \
  --Mdir obj_dir -o sim_cnn
./obj_dir/sim_cnn . 36
# Host twin
g++ -O2 -std=c++17 -o _behavioral/rtl_twin_host _behavioral/rtl_twin_host.cpp
./_behavioral/rtl_twin_host .
```

### Non-goals this sim
- Full `system_1dcnn_pl` with ADC PHY live data
- Vivado xsim / post-synth timing
