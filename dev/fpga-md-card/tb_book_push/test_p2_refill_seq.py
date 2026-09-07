#!/usr/bin/env python3
"""P2: seq gate — L0.seq > seq_start discards stale refill (no old overwrite)."""
from __future__ import annotations

import cocotb
from cocotb.triggers import RisingEdge

from push_helpers import (
    F_TOP10_REFILL,
    SIDE_BID,
    assert_no_a_fail,
    drain_pushes,
    inject_rt,
    kick_refill,
    msg_from_dut_push,
    poke_best16_side10,
    reset,
    start_clock,
)


@cocotb.test()
async def test_p2_refill_seq(dut):
    start_clock(dut)
    await reset(dut)

    sid = 2
    dut.push_ready.value = 0
    await inject_rt(
        dut, symbol_id=sid, side=SIDE_BID, level=0, px=100, qty=1, seq=10, ts_ns=10
    )
    dut.push_ready.value = 1
    await drain_pushes(dut, 20)

    await poke_best16_side10(dut, symbol_id=sid, side=SIDE_BID, base_px=5000, base_qty=7)

    await kick_refill(dut, sid, SIDE_BID)
    await RisingEdge(dut.clk)
    dut.push_ready.value = 0
    await inject_rt(
        dut, symbol_id=sid, side=SIDE_BID, level=0, px=111, qty=2, seq=20, ts_ns=20
    )
    dut.push_ready.value = 1

    disc0 = int(dut.refill_discard_cnt.value)
    saw_discard = False
    saw_refill_push = False
    for _ in range(200):
        if int(dut.refill_discard_cnt.value) > disc0:
            saw_discard = True
        if int(dut.push_valid.value) and int(dut.push_ready.value):
            m = msg_from_dut_push(dut)
            if m.flags == F_TOP10_REFILL:
                saw_refill_push = True
                assert m.bid_px[0] == 5000
                assert m.seq == 20
        await RisingEdge(dut.clk)
    assert saw_discard, "expected seq-gate discard when L0.seq > seq_start"
    assert saw_refill_push, "expected eventual refill push after reissue"
    assert int(dut.refill_issue_cnt.value) >= 2
    assert_no_a_fail(dut)
