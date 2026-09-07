# FPGA market-data card — simulation entrypoint (M1–M9)
# Usage:
#   make sim          # run full cocotb suite (CI-friendly)
#   make sim WAVES=1  # also dump FST (per-target sim_build)
#   make sim-udp / make sim-dec / make sim-dec-sse / make sim-dec-fast / make sim-arb / make sim-cam / make sim-mcast / make sim-dma / make sim-top

ROOT        := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
VENV        := $(ROOT)/.venv
PYTHON      := $(VENV)/bin/python

# Prefer locally built Verilator (>=5.036 required by cocotb 2.x)
LOCAL_VDIR := $(ROOT)/.local
ifeq ($(wildcard $(LOCAL_VDIR)/bin/verilator),)
  VERILATOR_BIN_DIR ?=
  export PATH := $(VENV)/bin:$(PATH)
else
  VERILATOR_BIN_DIR := $(LOCAL_VDIR)/bin
  export PATH := $(LOCAL_VDIR)/bin:$(VENV)/bin:$(PATH)
  export VERILATOR_ROOT := $(LOCAL_VDIR)/share/verilator
endif

SIM             ?= verilator
TOPLEVEL_LANG   ?= verilog
WAVES           ?= 0

export PYTHONPATH := $(ROOT)/tb_push:$(ROOT)/tb:$(ROOT)/tb_x1100:$(ROOT)/tb_l1:$(ROOT)/tb_book_push:$(PYTHONPATH)
export COCOTB_REDUCED_LOG_FMT := 1

EXTRA_ARGS += -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL
EXTRA_ARGS += -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-CASEINCOMPLETE -Wno-BLKSEQ -Wno-MULTIDRIVEN -Wno-VARHIDDEN
EXTRA_ARGS += --timing

ifeq ($(WAVES),1)
  VERILATOR_TRACE := 1
  EXTRA_ARGS += --trace-fst --trace-structs
endif

.PHONY: venv
venv:
	@test -x $(PYTHON) || python3 -m venv $(VENV)
	@$(PYTHON) -m pip -q install -r $(ROOT)/requirements.txt

.PHONY: sim sim-udp sim-dec sim-dec-sse sim-dec-fast sim-arb sim-cam sim-mcast sim-dma sim-top sim-x1100 sim-book sim-book-push-hook sim-x1100-book sim-l1 sim-l0-mem sim-push sim-book-push
sim: sim-udp sim-dec sim-dec-sse sim-dec-fast sim-arb sim-cam sim-mcast sim-dma sim-top

sim-udp: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/udp_strip.sv" \
		TOPLEVEL=udp_strip \
		MODULE=test_udp_strip \
		COCOTB_TOPLEVEL=udp_strip \
		COCOTB_TEST_MODULES=test_udp_strip \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/udp_strip

sim-dec: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/dec_bin_generic.sv $(ROOT)/rtl/dec_szse_bin.sv" \
		TOPLEVEL=dec_szse_bin \
		MODULE=test_dec_szse_bin \
		COCOTB_TOPLEVEL=dec_szse_bin \
		COCOTB_TEST_MODULES=test_dec_szse_bin \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/dec_szse_bin

sim-dec-sse: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/dec_bin_generic.sv $(ROOT)/rtl/dec_sse_bin.sv" \
		TOPLEVEL=dec_sse_bin \
		MODULE=test_dec_sse_bin \
		COCOTB_TOPLEVEL=dec_sse_bin \
		COCOTB_TEST_MODULES=test_dec_sse_bin \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/dec_sse_bin

sim-dec-fast: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/dec_sse_fast.sv" \
		TOPLEVEL=dec_sse_fast \
		MODULE=test_dec_sse_fast \
		COCOTB_TOPLEVEL=dec_sse_fast \
		COCOTB_TEST_MODULES=test_dec_sse_fast \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/dec_sse_fast

sim-arb: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/arb_nway.sv" \
		TOPLEVEL=arb_nway \
		MODULE=test_arb_nway \
		COCOTB_TOPLEVEL=arb_nway \
		COCOTB_TEST_MODULES=test_arb_nway \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/arb_nway

sim-cam: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/sym_cam.sv" \
		TOPLEVEL=sym_cam \
		MODULE=test_sym_cam \
		COCOTB_TOPLEVEL=sym_cam \
		COCOTB_TEST_MODULES=test_sym_cam \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/sym_cam

sim-mcast: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/mcast_eng.sv" \
		TOPLEVEL=mcast_eng \
		MODULE=test_mcast_eng \
		COCOTB_TOPLEVEL=mcast_eng \
		COCOTB_TEST_MODULES=test_mcast_eng \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/mcast_eng

sim-dma: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/dma_pack.sv" \
		TOPLEVEL=dma_pack \
		MODULE=test_dma_pack \
		COCOTB_TOPLEVEL=dma_pack \
		COCOTB_TEST_MODULES=test_dma_pack \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/dma_pack

sim-top: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/udp_strip.sv $(ROOT)/rtl/dec_bin_generic.sv $(ROOT)/rtl/dec_sse_bin.sv $(ROOT)/rtl/dec_sse_fast.sv $(ROOT)/rtl/dec_szse_bin.sv $(ROOT)/rtl/arb_nway.sv $(ROOT)/rtl/event_merge.sv $(ROOT)/rtl/sym_cam.sv $(ROOT)/rtl/mcast_eng.sv $(ROOT)/rtl/dma_pack.sv $(ROOT)/rtl/telem.sv $(ROOT)/rtl/tcp_pay_stub.sv $(ROOT)/rtl/swallow.sv $(ROOT)/rtl/md_rx_top.sv" \
		TOPLEVEL=md_rx_top \
		MODULE=test_md_rx_top \
		COCOTB_TOPLEVEL=md_rx_top \
		COCOTB_TEST_MODULES=test_md_rx_top \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/md_rx_top


# Book RTL shared by x1100 (ENABLE_BOOK) and unit TB
# Default excludes push top (USE_BOOK_PUSH=0) so sim-book stays light.
BOOK_RTL := $(ROOT)/rtl/book_pkg.sv $(ROOT)/rtl/hot_cam.sv $(ROOT)/rtl/order_cache.sv \
	$(ROOT)/rtl/l1_cmd_stub.sv $(ROOT)/rtl/l1_ddr_engine.sv $(ROOT)/rtl/sim/axi_ddr_model.sv \
	$(ROOT)/rtl/book_engine.sv
# Extra sources when elaborating USE_BOOK_PUSH=1
BOOK_PUSH_EXTRA := $(ROOT)/rtl/l0_top10_mem.sv $(ROOT)/rtl/book_push_engine.sv \
	$(ROOT)/rtl/snap_fsm.sv $(ROOT)/rtl/refill_ctrl.sv $(ROOT)/rtl/book_push_refill_top.sv

.PHONY: sim-x1100 sim-book
sim-x1100: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/x1100/ndpp_pkg.sv $(ROOT)/rtl/udp_strip.sv $(ROOT)/rtl/dec_bin_generic.sv $(ROOT)/rtl/dec_szse_bin.sv $(ROOT)/rtl/arb_nway.sv $(ROOT)/rtl/sym_cam.sv $(BOOK_RTL) $(ROOT)/rtl/mcast_eng.sv $(ROOT)/rtl/dma_pack.sv $(ROOT)/rtl/telem.sv $(ROOT)/rtl/x1100/md_rx_top_x1100.sv" \
		TOPLEVEL=md_rx_top_x1100 \
		MODULE=test_md_rx_top_x1100 \
		COCOTB_TOPLEVEL=md_rx_top_x1100 \
		COCOTB_TEST_MODULES=test_md_rx_top_x1100 \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/md_rx_top_x1100

# L0 book_engine unit tests (ENABLE_BOOK path exercised at unit level)
sim-book: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(BOOK_RTL)" \
		TOPLEVEL=book_engine \
		MODULE=test_book_engine \
		COCOTB_TOPLEVEL=book_engine \
		COCOTB_TEST_MODULES=test_book_engine \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/book_engine

# Optional: book_engine with USE_BOOK_PUSH=1 (light PUSH_N_SYM=64)
.PHONY: sim-book-push-hook
sim-book-push-hook: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(BOOK_RTL) $(BOOK_PUSH_EXTRA)" \
		TOPLEVEL=book_engine \
		MODULE=test_book_engine \
		COCOTB_TOPLEVEL=book_engine \
		COCOTB_TEST_MODULES=test_book_engine \
		EXTRA_ARGS="$(EXTRA_ARGS) -GUSE_BOOK_PUSH=1 -GPUSH_N_SYM=64" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/book_engine_push

# x1100 with ENABLE_BOOK=1 + book-focused TB
sim-x1100-book: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/x1100/ndpp_pkg.sv $(ROOT)/rtl/udp_strip.sv $(ROOT)/rtl/dec_bin_generic.sv $(ROOT)/rtl/dec_szse_bin.sv $(ROOT)/rtl/arb_nway.sv $(ROOT)/rtl/sym_cam.sv $(BOOK_RTL) $(ROOT)/rtl/mcast_eng.sv $(ROOT)/rtl/dma_pack.sv $(ROOT)/rtl/telem.sv $(ROOT)/rtl/x1100/md_rx_top_x1100.sv" \
		TOPLEVEL=md_rx_top_x1100 \
		MODULE=test_md_rx_top_x1100_book \
		COCOTB_TOPLEVEL=md_rx_top_x1100 \
		COCOTB_TEST_MODULES=test_md_rx_top_x1100_book \
		EXTRA_ARGS="$(EXTRA_ARGS) -GENABLE_BOOK=1" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/md_rx_top_x1100_book


# L1 DDR engine + axi_ddr_model (tb_l1)
L1_RTL := $(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/book_pkg.sv $(ROOT)/rtl/l1_ddr_engine.sv $(ROOT)/rtl/sim/axi_ddr_model.sv $(ROOT)/tb_l1/tb_l1_top.sv

.PHONY: sim-l1
sim-l1: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(L1_RTL)" \
		TOPLEVEL=tb_l1_top \
		MODULE=test_l1_add_cxl_trade,test_l1_bank_parallel,test_l1_drop_when_full \
		COCOTB_TOPLEVEL=tb_l1_top \
		COCOTB_TEST_MODULES=test_l1_add_cxl_trade,test_l1_bank_parallel,test_l1_drop_when_full \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/l1_ddr



# P1.0 L0 Top-10 4-bank mem (N_SYM_P=32 for light sim)
L0_MEM_RTL := $(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/book_pkg.sv $(ROOT)/rtl/l0_top10_mem.sv

.PHONY: sim-l0-mem
sim-l0-mem: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(L0_MEM_RTL)" \
		TOPLEVEL=l0_top10_mem \
		MODULE=test_l0_top10_mem \
		COCOTB_TOPLEVEL=l0_top10_mem \
		COCOTB_TEST_MODULES=test_l0_top10_mem \
		EXTRA_ARGS="$(EXTRA_ARGS) -GN_SYM_P=32" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/l0_top10_mem

# P1.0 book_push_engine — RTL defaults DEPTH_REFILL/SNAP=64; sim overrides shallow
PUSH_RTL := $(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/book_pkg.sv $(ROOT)/rtl/book_push_engine.sv

.PHONY: sim-push
sim-push: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(PUSH_RTL)" \
		TOPLEVEL=book_push_engine \
		MODULE=test_book_push_engine \
		COCOTB_TOPLEVEL=book_push_engine \
		COCOTB_TEST_MODULES=test_book_push_engine \
		EXTRA_ARGS="$(EXTRA_ARGS) -GDEPTH_RT=16 -GDEPTH_REFILL=8 -GDEPTH_SNAP=8" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/book_push_engine

# book-push-refill-v2 P2: real book_push_refill_top via TB glue
BOOK_PUSH_RTL := $(ROOT)/rtl/md_pkg.sv $(ROOT)/rtl/book_pkg.sv \
	$(ROOT)/rtl/l0_top10_mem.sv \
	$(ROOT)/rtl/book_push_engine.sv \
	$(ROOT)/rtl/snap_fsm.sv \
	$(ROOT)/rtl/refill_ctrl.sv \
	$(ROOT)/rtl/book_push_refill_top.sv \
	$(ROOT)/rtl/sim/axi_ddr_model.sv \
	$(ROOT)/tb_book_push/book_push_refill_tb_glue.sv \
	$(ROOT)/tb_book_push/tb_book_push_top.sv

.PHONY: sim-book-push
sim-book-push: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(BOOK_PUSH_RTL)" \
		TOPLEVEL=tb_book_push_top \
		MODULE=test_p2_gap_refill,test_p2_timer_snap,test_p2_rt_preempt,test_p2_refill_seq,test_p2_skip_empty \
		COCOTB_TOPLEVEL=tb_book_push_top \
		COCOTB_TEST_MODULES=test_p2_gap_refill,test_p2_timer_snap,test_p2_rt_preempt,test_p2_refill_seq,test_p2_skip_empty \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON) \
		SIM_BUILD=$(ROOT)/sim_build/book_push

.PHONY: clean
clean:
	rm -rf sim_build results.xml dump.fst dump.vcd __pycache__ tb/__pycache__ tb_x1100/__pycache__ tb_l1/__pycache__ tb_push/__pycache__ tb_book_push/__pycache__

.PHONY: help
help:
	@echo "make sim          - run all unit + top integration tests"
	@echo "make sim-udp      - udp_strip only"
	@echo "make sim-dec      - dec_szse_bin only"
	@echo "make sim-dec-sse  - dec_sse_bin only"
	@echo "make sim-dec-fast - dec_sse_fast only"
	@echo "make sim-arb      - arb_nway only"
	@echo "make sim-cam      - sym_cam only"
	@echo "make sim-mcast    - mcast_eng only"
	@echo "make sim-dma      - dma_pack only"
	@echo "make sim-top      - md_rx_top integration"
	@echo "make sim-x1100    - md_rx_top_x1100 32b SZSE A/B (ENABLE_BOOK=0)"
	@echo "make sim-book     - book_engine L0 unit tests"
	@echo "make sim-book-push-hook - book_engine USE_BOOK_PUSH=1 smoke"
	@echo "make sim-x1100-book - x1100 with ENABLE_BOOK=1"
	@echo "make sim-l1        - L1 DDR engine (axi model) tests"
	@echo "make sim-l0-mem   - P1.0 l0_top10_mem 4-bank unit tests"
	@echo "make sim-push     - P1.0 book_push_engine unit tests"
	@echo "make sim-book-push - book_push P2 (book_push_refill_top via glue)"
	@echo "make sim WAVES=1  - run with FST waveform dump"
	@echo "make clean        - remove build artefacts"
