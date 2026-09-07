#!/usr/bin/env python3
"""P1.0: book_push_engine — RT overwrite, priority vs snap, DMA stall still accepts RT."""
from __future__ import annotations

import cocotb
from cocotb.triggers import RisingEdge, with_timeout, First, Timer

from p1_push_helpers import (
    F_TOP10_RT,
    F_TOP10_TIMER,
    pack_l0_row,
    reset_sys,
    start_clock,
    unpack_top10_msg,
)


def _idle(dut):
    dut.i_rt_valid.value = 0
    dut.i_rt_symbol.value = 0
    dut.i_rt_row.value = 0
    dut.i_refill_valid.value = 0
    dut.i_refill_symbol.value = 0
    dut.i_refill_row.value = 0
    dut.i_snap_valid.value = 0
    dut.i_snap_symbol.value = 0
    dut.i_snap_row.value = 0
    dut.i_m_tready.value = 1


async def _recv_msg(dut, timeout_cycles: int = 50) -> dict:
    for _ in range(timeout_cycles):
        await RisingEdge(dut.sys_clk)
        if int(dut.o_m_tvalid.value) == 1 and int(dut.i_m_tready.value) == 1:
            assert int(dut.o_m_tlast.value) == 1
            return unpack_top10_msg(int(dut.o_m_tdata.value))
    raise TimeoutError("DMA msg timeout")


@cocotb.test()
async def test_push_rt_overwrite_then_snap(dut):
    start_clock(dut)
    _idle(dut)
    await reset_sys(dut)

    row1 = pack_l0_row(nonempty=1, seq=1, ts_ns=10, bid_vld=1, bid_px=100, bid_qty=1)
    row2 = pack_l0_row(nonempty=1, seq=2, ts_ns=20, bid_vld=1, bid_px=200, bid_qty=2)
    row_s = pack_l0_row(nonempty=1, seq=9, ts_ns=90, bid_vld=1, bid_px=900, bid_qty=9)

    # Stall DMA so both RT land in queue; second overwrites same symbol
    dut.i_m_tready.value = 0
    dut.i_rt_symbol.value = 5
    dut.i_rt_row.value = row1
    dut.i_rt_valid.value = 1
    await RisingEdge(dut.sys_clk)
    dut.i_rt_row.value = row2
    dut.i_rt_valid.value = 1
    await RisingEdge(dut.sys_clk)
    dut.i_rt_valid.value = 0

    # Snap for different symbol (lower prio) while still stalled
    dut.i_snap_symbol.value = 7
    dut.i_snap_row.value = row_s
    dut.i_snap_valid.value = 1
    await RisingEdge(dut.sys_clk)
    dut.i_snap_valid.value = 0
    await RisingEdge(dut.sys_clk)

    dut.i_m_tready.value = 1
    msg0 = await _recv_msg(dut)
    assert msg0["symbol_id"] == 5
    assert msg0["flags"] == F_TOP10_RT
    assert msg0["seq"] == 2
    assert msg0["bid_px"] & ((1 << 64) - 1) == 200

    msg1 = await _recv_msg(dut)
    assert msg1["symbol_id"] == 7
    assert msg1["flags"] == F_TOP10_TIMER
    assert msg1["seq"] == 9

    await RisingEdge(dut.sys_clk)
    assert int(dut.o_tx_rt.value) == 1
    assert int(dut.o_tx_snap.value) == 1
    assert int(dut.o_drop_rt.value) == 0


@cocotb.test()
async def test_push_dma_stall_rt_still_accepted(dut):
    start_clock(dut)
    _idle(dut)
    await reset_sys(dut)

    row1 = pack_l0_row(nonempty=1, seq=1, ts_ns=1, bid_vld=1, bid_px=11, bid_qty=1)
    row2 = pack_l0_row(nonempty=1, seq=2, ts_ns=2, bid_vld=1, bid_px=22, bid_qty=2)

    dut.i_m_tready.value = 0

    dut.i_rt_symbol.value = 3
    dut.i_rt_row.value = row1
    dut.i_rt_valid.value = 1
    await RisingEdge(dut.sys_clk)
    dut.i_rt_valid.value = 0

    # Wait until emit asserts valid while stalled
    saw_valid = False
    for _ in range(20):
        await RisingEdge(dut.sys_clk)
        if int(dut.o_m_tvalid.value) == 1:
            saw_valid = True
            break
    assert saw_valid, "expected o_m_tvalid while DMA not ready"

    # Second RT same symbol while stalled — must still accept (overwrite)
    dut.i_rt_symbol.value = 3
    dut.i_rt_row.value = row2
    dut.i_rt_valid.value = 1
    await RisingEdge(dut.sys_clk)
    dut.i_rt_valid.value = 0
    await RisingEdge(dut.sys_clk)

    # Release DMA — should see latest seq=2 (overwrite in queue or after first beat)
    dut.i_m_tready.value = 1
    msgs = []
    for _ in range(30):
        await RisingEdge(dut.sys_clk)
        if int(dut.o_m_tvalid.value) == 1 and int(dut.i_m_tready.value) == 1:
            msgs.append(unpack_top10_msg(int(dut.o_m_tdata.value)))
            if len(msgs) >= 1 and int(dut.o_tx_rt.value) >= 1:
                # may get 1 or 2 beats depending on whether first load already took row1
                pass
        if int(dut.o_tx_rt.value) >= 1 and int(dut.o_m_tvalid.value) == 0:
            break

    assert len(msgs) >= 1
    # Final emitted content for symbol 3 should reflect overwrite (seq 2) if only one,
    # or last msg seq==2 if two.
    last = msgs[-1]
    assert last["symbol_id"] == 3
    assert last["flags"] == F_TOP10_RT
    assert last["seq"] == 2 or (len(msgs) == 2 and msgs[0]["seq"] == 1 and msgs[1]["seq"] == 2)
    # Prefer overwrite-before-emit: if first beat already held row1, second follows.
    if len(msgs) == 1:
        assert last["seq"] == 2
    assert int(dut.o_drop_rt.value) == 0
