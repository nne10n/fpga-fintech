#!/usr/bin/env python3
"""P2: snap_skip_empty=1 空槽跳过."""
from __future__ import annotations

import cocotb
from cocotb.triggers import RisingEdge, ReadOnly

from push_helpers import (
    F_TOP10_TIMER,
    N_SYM_TB,
    SIDE_BID,
    assert_no_a_fail,
    csr_write,
    drain_pushes,
    inject_rt,
    msg_from_dut_push,
    reset,
    start_clock,
)


@cocotb.test()
async def test_p2_skip_empty(dut):
    start_clock(dut)
    await reset(dut)

    dut.push_ready.value = 0
    for sid in (4, 9):
        await inject_rt(
            dut, symbol_id=sid, side=SIDE_BID, level=0, px=40 + sid, qty=3, seq=sid, ts_ns=sid
        )
    await drain_pushes(dut, 30)

    await csr_write(dut, enable=1, period_cycles=4, snap_skip_empty=1)
    dut.push_ready.value = 1

    timer_sids = []
    # Exactly one sweep worth of cycles (N_SYM) + margin for period startup
    for _ in range(N_SYM_TB + 20):
        await ReadOnly()
        if int(dut.push_valid.value) and int(dut.push_ready.value):
            m = msg_from_dut_push(dut)
            if m.flags == F_TOP10_TIMER:
                timer_sids.append(m.symbol_id)
        await RisingEdge(dut.clk)

    assert 4 in timer_sids and 9 in timer_sids, f"timer_sids={timer_sids}"
    assert set(timer_sids).issubset({4, 9}), f"unexpected empty push: {timer_sids}"
    # With skip_empty, far fewer than N_SYM pushes
    assert int(dut.push_timer_cnt.value) < N_SYM_TB // 2
    assert_no_a_fail(dut)
