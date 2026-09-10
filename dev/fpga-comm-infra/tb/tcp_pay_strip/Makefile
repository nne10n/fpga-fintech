SIM ?= icarus
TOPLEVEL_LANG = verilog
VERILOG_SOURCES = $(abspath $(CURDIR)/../../rtl/tcp_pay_strip/tcp_pay_strip.sv)
TOPLEVEL = tcp_pay_strip
MODULE = test_tcp_pay_strip
WAVES ?= 0
COMPILE_ARGS += -g2012
export PYTHONPATH := $(abspath $(CURDIR)/..):$(PYTHONPATH)
export COCOTB_REDUCED_LOG_FMT := 1

include $(shell cocotb-config --makefiles)/Makefile.sim
