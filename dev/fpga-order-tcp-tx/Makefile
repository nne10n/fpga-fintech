# Minimal FPGA TCP order-send core — simulation entrypoint
# Usage:
#   make sim          # run full cocotb suite (CI-friendly)
#   make sim WAVES=1  # also dump dump.fst

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

VERILOG_SOURCES := \
  $(ROOT)/rtl/tcp_pkg.sv \
  $(ROOT)/rtl/order_buffer.sv \
  $(ROOT)/rtl/eth_ipv4_tcp_rx.sv \
  $(ROOT)/rtl/tcp_frame_tx.sv \
  $(ROOT)/rtl/tcp_client_sm.sv \
  $(ROOT)/rtl/tcp_order_top.sv

TOPLEVEL            := tcp_order_top
MODULE              := test_tcp_order
COCOTB_TOPLEVEL     := $(TOPLEVEL)
COCOTB_TEST_MODULES := $(MODULE)

export PYTHONPATH := $(ROOT)/tb:$(PYTHONPATH)
export COCOTB_REDUCED_LOG_FMT := 1

# Verilator flags (keep EXTRA_ARGS free of nested quotes)
EXTRA_ARGS += -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL
EXTRA_ARGS += -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-CASEINCOMPLETE
EXTRA_ARGS += --timing

ifeq ($(WAVES),1)
  VERILATOR_TRACE := 1
  EXTRA_ARGS += --trace-fst --trace-structs
endif

.PHONY: venv
venv:
	@test -x $(PYTHON) || python3 -m venv $(VENV)
	@$(PYTHON) -m pip -q install -r $(ROOT)/requirements.txt

.PHONY: sim
sim: venv
	$(MAKE) -f $(shell $(VENV)/bin/cocotb-config --makefiles)/Makefile.sim \
		SIM=$(SIM) \
		TOPLEVEL_LANG=$(TOPLEVEL_LANG) \
		VERILOG_SOURCES="$(VERILOG_SOURCES)" \
		TOPLEVEL=$(TOPLEVEL) \
		MODULE=$(MODULE) \
		COCOTB_TOPLEVEL=$(COCOTB_TOPLEVEL) \
		COCOTB_TEST_MODULES=$(COCOTB_TEST_MODULES) \
		EXTRA_ARGS="$(EXTRA_ARGS)" \
		VERILATOR_TRACE=$(VERILATOR_TRACE) \
		VERILATOR_BIN_DIR=$(VERILATOR_BIN_DIR) \
		PYTHON_BIN=$(PYTHON)

.PHONY: clean
clean:
	rm -rf sim_build results.xml dump.fst dump.vcd __pycache__ tb/__pycache__

.PHONY: help
help:
	@echo "make sim          - run cocotb+Verilator regression"
	@echo "make sim WAVES=1  - run with FST waveform dump"
	@echo "make clean        - remove build artefacts"
