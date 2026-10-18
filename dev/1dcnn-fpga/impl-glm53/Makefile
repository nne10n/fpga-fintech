# impl-glm53 — SV cnn_engine bit-exact (Verilator primary) + legacy HLS host compare
ROOT := $(abspath .)
CXX  ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -I$(ROOT)/tb -I$(ROOT)/include -I$(ROOT)/_legacy_hls

VERILATOR ?= verilator
VTOP      := cnn_engine
VDIR      := $(ROOT)/sim/obj_dir
VSIM      := $(VDIR)/V$(VTOP)
VFLAGS    := --cc --exe -sv --build -j $$(nproc) --top-module $(VTOP) \
             -Mdir $(VDIR) -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-LATCH \
             -CFLAGS "-O2 -std=c++17"

.PHONY: all vectors weights gen_golden bitexact_hls sv_bitexact bitexact vote_test reports clean

all: weights vectors gen_golden sv_bitexact reports

weights:
	python3 scripts/gen_weights.py

vectors:
	python3 scripts/gen_vectors.py

tb/gen_golden: tb/gen_golden.cpp tb/golden_cnn.cpp tb/golden_cnn.hpp
	$(CXX) $(CXXFLAGS) -o $@ tb/gen_golden.cpp tb/golden_cnn.cpp

gen_golden: tb/gen_golden weights vectors
	./tb/gen_golden $(ROOT)

tb/run_bitexact: tb/run_bitexact.cpp _legacy_hls/cnn_engine.cpp _legacy_hls/cnn_engine.hpp
	$(CXX) $(CXXFLAGS) -o $@ tb/run_bitexact.cpp _legacy_hls/cnn_engine.cpp

bitexact_hls: tb/run_bitexact gen_golden
	mkdir -p reports
	./tb/run_bitexact $(ROOT)

$(VSIM): rtl/cnn_pkg.sv rtl/cnn_engine.sv tb/sv_bitexact_main.cpp
	mkdir -p $(ROOT)/sim
	$(VERILATOR) $(VFLAGS) rtl/cnn_pkg.sv rtl/cnn_engine.sv tb/sv_bitexact_main.cpp

sv_bitexact: $(VSIM) gen_golden
	mkdir -p reports
	$(VSIM) $(ROOT)

bitexact: sv_bitexact

vote_test: ps/vote_alarm.c include/regs.h
	$(CXX) -x c -O2 -DVOTE_ALARM_MAIN -I$(ROOT) -o ps/vote_alarm_test ps/vote_alarm.c
	./ps/vote_alarm_test

reports: bitexact
	@echo "reports under reports/"

clean:
	rm -f tb/run_bitexact tb/gen_golden ps/vote_alarm_test
	rm -rf $(ROOT)/sim/obj_dir
