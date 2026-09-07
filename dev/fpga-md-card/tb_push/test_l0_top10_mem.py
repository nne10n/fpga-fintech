#!/usr/bin/env python3
"""P1.0: l0_top10_mem — Port-A write/read, Port-B snap read, same-bank A wins."""
from __future__ import annotations

import cocotb
from cocotb.triggers import RisingEdge, ReadOnly

from p1_push_helpers import pack_l0_row, reset_sys, start_clock


def _idle_ports(dut):
    dut.i_a_req.value = 0
    dut.i_a_we.value = 0
    dut.i_a_symbol.value = 0
    dut.i_a_wdata.value = 0
    dut.i_b_req.value = 0
    dut.i_b_we.value = 0
    dut.i_b_is_refill.value = 0
    dut.i_b_symbol.value = 0
    dut.i_b_wdata.value = 0


@cocotb.test()
async def test_l0_porta_write_read(dut):
    start_clock(dut)
    _idle_ports(dut)
    await reset_sys(dut)

    row = pack_l0_row(
        nonempty=1,
        seq=0x11,
        ts_ns=0xABC,
        bid_vld=0b1,
        ask_vld=0,
        bid_px=0x1000,
        bid_qty=10,
    )
    # symbol 5 → bank 1, local addr 1
    dut.i_a_symbol.value = 5
    dut.i_a_wdata.value = row
    dut.i_a_we.value = 1
    dut.i_a_req.value = 1
    await RisingEdge(dut.sys_clk)
    assert int(dut.o_a_ready.value) == 1
    dut.i_a_req.value = 0
    dut.i_a_we.value = 0
    await RisingEdge(dut.sys_clk)

    # read back Port-A
    dut.i_a_symbol.value = 5
    dut.i_a_we.value = 0
    dut.i_a_req.value = 1
    await RisingEdge(dut.sys_clk)
    dut.i_a_req.value = 0
    await RisingEdge(dut.sys_clk)
    assert int(dut.o_a_valid.value) == 1
    assert int(dut.o_a_rdata.value) == row


@cocotb.test()
async def test_l0_portb_snap_read(dut):
    start_clock(dut)
    _idle_ports(dut)
    await reset_sys(dut)

    row = pack_l0_row(nonempty=1, seq=7, ts_ns=99, bid_vld=0b11, bid_px=42, bid_qty=3)
    # write via A
    dut.i_a_symbol.value = 8  # bank 0
    dut.i_a_wdata.value = row
    dut.i_a_we.value = 1
    dut.i_a_req.value = 1
    await RisingEdge(dut.sys_clk)
    dut.i_a_req.value = 0
    dut.i_a_we.value = 0
    await RisingEdge(dut.sys_clk)

    # Port-B snap read
    dut.i_b_symbol.value = 8
    dut.i_b_we.value = 0
    dut.i_b_is_refill.value = 0
    dut.i_b_req.value = 1
    await RisingEdge(dut.sys_clk)
    assert int(dut.o_b_ready.value) == 1
    dut.i_b_req.value = 0
    await RisingEdge(dut.sys_clk)
    assert int(dut.o_b_valid.value) == 1
    assert int(dut.o_b_rdata.value) == row


@cocotb.test()
async def test_l0_same_bank_a_wins(dut):
    start_clock(dut)
    _idle_ports(dut)
    await reset_sys(dut)

    row_a = pack_l0_row(nonempty=1, seq=1, bid_vld=1, bid_px=1, bid_qty=1)
    row_b = pack_l0_row(nonempty=1, seq=2, bid_vld=1, bid_px=2, bid_qty=2)

    # Preload symbol 4 (bank 0) via A
    dut.i_a_symbol.value = 4
    dut.i_a_wdata.value = row_a
    dut.i_a_we.value = 1
    dut.i_a_req.value = 1
    await RisingEdge(dut.sys_clk)
    dut.i_a_req.value = 0
    await RisingEdge(dut.sys_clk)

    # Same cycle: A writes symbol 4, B tries read symbol 0 (also bank 0)
    dut.i_a_symbol.value = 4
    dut.i_a_wdata.value = row_a
    dut.i_a_we.value = 1
    dut.i_a_req.value = 1
    dut.i_b_symbol.value = 0  # bank 0, empty
    dut.i_b_we.value = 0
    dut.i_b_req.value = 1
    await RisingEdge(dut.sys_clk)
    await ReadOnly()
    assert int(dut.o_a_ready.value) == 1
    assert int(dut.o_b_ready.value) == 0  # A wins, B must retry
    # leave ReadOnly; next edge deassert
    await RisingEdge(dut.sys_clk)
    dut.i_a_req.value = 0
    dut.i_a_we.value = 0
    dut.i_b_req.value = 0
    await RisingEdge(dut.sys_clk)

    # B retry succeeds
    dut.i_b_symbol.value = 4
    dut.i_b_we.value = 0
    dut.i_b_req.value = 1
    await RisingEdge(dut.sys_clk)
    assert int(dut.o_b_ready.value) == 1
    dut.i_b_req.value = 0
    await RisingEdge(dut.sys_clk)
    assert int(dut.o_b_valid.value) == 1
    assert int(dut.o_b_rdata.value) == row_a

    # silence unused
    _ = row_b
