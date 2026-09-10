SIM ?= icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(abspath $(CURDIR)/../../rtl/udp_mcast_tx/udp_mcast_tx.sv)
TOPLEVEL = udp_mcast_tx
MODULE = test_udp_mcast_tx
WAVES ?= 0
COMPILE_ARGS += -g2012
export PYTHONPATH := $(abspath $(CURDIR)/..):$(PYTHONPATH)
export COCOTB_REDUCED_LOG_FMT := 1

include $(shell cocotb-config --makefiles)/Makefile.sim
