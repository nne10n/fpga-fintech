#!/usr/bin/env python3
"""P2: 实时优先抢占定时."""
from __future__ import annotations

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge

from push_helpers import (
    F_TOP10_RT,
    F_TOP10_TIMER,
    SIDE_BID,
    assert_no_a_fail,
    csr_write,
    inject_rt,
    kick_refill,
    msg_from_dut_push,
    reset,
    start_clock,
)


@cocotb.test()
async def test_p2_rt_preempt(dut):
    start_clock(dut)
    await reset(dut)

    # Populate a few symbols; hold DMA during fill
    dut.push_ready.value = 0
    for sid in range(8):
        await inject_rt(
            dut, symbol_id=sid, side=SIDE_BID, level=0, px=10 + sid, qty=1, seq=1, ts_ns=1
        )
    dut.push_ready.value = 1
    for _ in range(80):
        await RisingEdge(dut.clk)

    await csr_write(dut, enable=1, period_cycles=3, snap_skip_empty=0)

    saw_timer = False
    for _ in range(300):
        await FallingEdge(dut.clk)
        if int(dut.push_valid.value) and int(dut.push_flags.value) == F_TOP10_TIMER:
            saw_timer = True
            await RisingEdge(dut.clk)
            break
        await RisingEdge(dut.clk)
    assert saw_timer, "timer snap never started"

    # Park DMA, inject fresh symbol so RT must enter push_q_rt
    dut.push_ready.value = 0
    for _ in range(2):
        await RisingEdge(dut.clk)
    await inject_rt(
        dut, symbol_id=15, side=SIDE_BID, level=0, px=999, qty=9, seq=50, ts_ns=50
    )
    await RisingEdge(dut.clk)  # allow NBA enqueue
    assert int(dut.push_valid.value) == 1
    assert int(dut.push_flags.value) == F_TOP10_RT, (
        f"expected RT pending, flags={int(dut.push_flags.value)}"
    )

    dut.push_ready.value = 1
    order = []
    for _ in range(40):
        await FallingEdge(dut.clk)
        if int(dut.push_valid.value) and int(dut.push_ready.value):
            m = msg_from_dut_push(dut)
            order.append((m.flags, m.symbol_id, m.bid_px[0]))
            if m.flags == F_TOP10_RT:
                assert m.symbol_id == 15
                assert m.bid_px[0] == 999
                await RisingEdge(dut.clk)
                break
        await RisingEdge(dut.clk)

    assert order and order[0][0] == F_TOP10_RT, f"RT must win; order={order}"
    assert_no_a_fail(dut)

    # ------------------------------------------------------------------
    # T-A6: RT must progress while DDR req is blocked (l1_rmw_pri_hold).
    # Natural stall: glue holds i_ddr_req_ready low → o_ddr_req_valid stuck.
    # ------------------------------------------------------------------
    dut.push_ready.value = 0
    dut.l1_rmw_pri_hold.value = 1
    await kick_refill(dut, sid=7, side=SIDE_BID)
    for _ in range(6):
        await RisingEdge(dut.clk)

    rt_before = int(dut.push_rt_cnt.value)
    drop_before = int(dut.drop_cnt.value)
    await inject_rt(
        dut, symbol_id=21, side=SIDE_BID, level=0, px=321, qty=3, seq=210, ts_ns=210
    )

    progressed = False
    for _ in range(5):
        await RisingEdge(dut.clk)
        if int(dut.push_valid.value) and (int(dut.push_flags.value) & F_TOP10_RT):
            progressed = True
            break
        if int(dut.push_rt_cnt.value) > rt_before or int(dut.drop_cnt.value) > drop_before:
            progressed = True
            break
    assert progressed, (
        "T-A6: RT must progress while DDR req stalled "
        f"(rt={int(dut.push_rt_cnt.value)} drop={int(dut.drop_cnt.value)} "
        f"flags={int(dut.push_flags.value) if int(dut.push_valid.value) else -1})"
    )

    dut.l1_rmw_pri_hold.value = 0
    dut.push_ready.value = 1
    for _ in range(10):
        await RisingEdge(dut.clk)
    assert_no_a_fail(dut)
