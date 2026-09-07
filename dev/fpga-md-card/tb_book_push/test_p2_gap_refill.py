#!/usr/bin/env python3
"""P2: 十档缺失 → best16 回补 → F_TOP10_REFILL."""
from __future__ import annotations

import cocotb
from cocotb.triggers import RisingEdge, FallingEdge

from push_helpers import (
    F_TOP10_REFILL,
    F_TOP10_RT,
    SIDE_BID,
    assert_no_a_fail,
    drain_pushes,
    inject_rt,
    msg_from_dut_push,
    poke_best16_side10,
    reset,
    start_clock,
)


@cocotb.test()
async def test_p2_gap_refill(dut):
    start_clock(dut)
    await reset(dut)

    sid = 3
    dut.push_ready.value = 1
    for lvl in range(10):
        await inject_rt(
            dut,
            symbol_id=sid,
            side=SIDE_BID,
            level=lvl,
            px=1000 - lvl,
            qty=10 + lvl,
            seq=10 + lvl,
            ts_ns=100 + lvl,
        )
    await drain_pushes(dut, 40)

    await poke_best16_side10(dut, symbol_id=sid, side=SIDE_BID, base_px=2000, base_qty=50)

    # Hold ready so dig RT queues; refill AXI can complete; then release
    dut.push_ready.value = 0
    await inject_rt(
        dut,
        symbol_id=sid,
        side=SIDE_BID,
        level=4,
        dig_hole=1,
        seq=100,
        ts_ns=200,
        l1_may_have_more=1,
    )
    # Mid-RTT: refill in WAIT_RSP (o_ddr_rsp_ready && !i_ddr_rsp_valid) — T-A6 window.
    mid_rt_done = False
    for i in range(20):
        await RisingEdge(dut.clk)
        if i == 2 and not mid_rt_done:
            # Fire another RT while DDR rsp stalled; must still be accepted onto DMA.
            await inject_rt(
                dut,
                symbol_id=sid,
                side=SIDE_BID,
                level=1,
                px=1111,
                qty=2,
                seq=101,
                ts_ns=201,
            )
            mid_rt_done = True
            await RisingEdge(dut.clk)  # NBA enqueue / mid-stall retarget
            assert int(dut.push_valid.value) == 1 and int(dut.push_flags.value) == F_TOP10_RT, (
                "T-A6: RT must present on DMA while DDR rsp stalled "
                f"(flags={int(dut.push_flags.value)} valid={int(dut.push_valid.value)})"
            )
    assert int(dut.refill_issue_cnt.value) >= 1
    assert int(dut.ddr_rd_cnt.value) >= 1
    assert mid_rt_done, "T-A6 mid-RTT RT inject did not run"

    dut.push_ready.value = 1
    saw_rt = False
    refill = None
    for _ in range(100):
        await FallingEdge(dut.clk)
        if int(dut.push_valid.value) and int(dut.push_ready.value):
            m = msg_from_dut_push(dut)
            if m.flags == F_TOP10_RT and m.symbol_id == sid:
                saw_rt = True
            if m.flags == F_TOP10_REFILL and m.symbol_id == sid:
                refill = m
        await RisingEdge(dut.clk)
        if saw_rt and refill is not None:
            break

    assert saw_rt, "expected RT dig push before/with refill"
    assert refill is not None, "expected REFILL push"
    assert refill.bid_vld == 0x3FF, f"bid_vld=0x{refill.bid_vld:x}"
    assert refill.bid_px[0] == 2000
    assert refill.bid_qty[0] == 50
    # allow one settle edge for counter NBA/blocking visibility
    await RisingEdge(dut.clk)
    assert int(dut.push_refill_cnt.value) >= 1 or int(dut.last_grant.value) == 1
    assert_no_a_fail(dut)
