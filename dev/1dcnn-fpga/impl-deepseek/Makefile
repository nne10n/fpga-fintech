.PHONY: sim-host sim-wmem sim-cnn reports
ROOT := $(abspath .)

sim-host:
	g++ -O2 -std=c++17 -o _behavioral/rtl_twin_host _behavioral/rtl_twin_host.cpp
	./_behavioral/rtl_twin_host $(ROOT)

sim-wmem:
	iverilog -g2012 -o tb/sim_wmem_score rtl/weight_mem.sv rtl/score_path.sv tb/tb_wmem_score.sv
	vvp tb/sim_wmem_score

sim-cnn:
	verilator -Wno-fatal -Wno-WIDTH -Wno-UNOPTFLAT -Wno-CASEINCOMPLETE -Wno-BLKANDNBLK \
	  --cc --exe -O3 --build -j 4 -Irtl --top-module tb_cnn_engine_wrap \
	  rtl/weight_mem.sv rtl/cnn_engine.sv tb/tb_cnn_engine_wrap.sv tb/tb_cnn_engine.cpp \
	  --Mdir obj_dir -o sim_cnn
	./obj_dir/sim_cnn $(ROOT) 36

reports: sim-host sim-wmem
	@echo "see reports/"
