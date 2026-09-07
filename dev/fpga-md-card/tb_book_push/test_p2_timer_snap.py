#!/usr/bin/env python3
"""P2: timer snap emits F_TOP10_TIMER for populated symbols."""
from __future__ import annotations

import cocotb
from cocotb.triggers import RisingEdge

from push_helpers import (
    F_TOP10_RT,
    F_TOP10_TIMER,
    N_SYM_TB,
    SIDE_BID,
    assert_no_a_fail,
    collect_pushes,
    csr_write,
    inject_rt,
    msg_from_dut_push,
    reset,
    start_clock,
)


@cocotb.test()
async def test_p2_timer_snap(dut):
    start_clock(dut)
    await reset(dut)

    live = (0, 5, 10)
    dut.push_ready.value = 1
    for sid, seq in zip(live, (1, 2, 3)):
        dut.push_ready.value = 0
        await inject_rt(
            dut, symbol_id=sid, side=SIDE_BID, level=0, px=100 + sid, qty=1, seq=seq, ts_ns=seq
        )
        dut.push_ready.value = 1
        m = (await collect_pushes(dut, 1, only_flags=F_TOP10_RT, timeout_cycles=50))[0]
        assert m.symbol_id == sid, f"RT sid={m.symbol_id} expected {sid}"
        assert (m.bid_vld & 0x1) != 0

    await csr_write(dut, enable=1, period_cycles=5, snap_skip_empty=1)

    timer_msgs = []
    for _ in range(1000):
        if int(dut.push_valid.value) and int(dut.push_ready.value):
            m = msg_from_dut_push(dut)
            if m.flags == F_TOP10_TIMER:
                timer_msgs.append(m)
        await RisingEdge(dut.clk)
        if set(live).issubset({x.symbol_id for x in timer_msgs}):
            break

    sids = {m.symbol_id for m in timer_msgs}
    assert set(live).issubset(sids), f"timer sids={sids} expected at least {live}"
    assert all(m.flags == F_TOP10_TIMER for m in timer_msgs)
    assert int(dut.push_timer_cnt.value) >= len(live)
    assert int(dut.push_timer_cnt.value) < N_SYM_TB
    assert N_SYM_TB == 32
    assert_no_a_fail(dut)
