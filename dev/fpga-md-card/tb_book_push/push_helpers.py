"""Shared helpers for book_push / refill P2 cocotb tests.

top10_msg_t (book_pkg) is 2080-bit SV packed, MSB-first declaration:
  pad[19:0], ask_qty, ask_px, ask_vld, bid_qty, bid_px, bid_vld,
  flags, seq, ts_ns, symbol_id[15:0]  ← LSB
DMA little-endian: symbol_id at lowest bits/bytes.

Sampling note: push_* are combinational from queue head; DUT pops on
posedge when valid&&ready. Sample the presented beat BEFORE awaiting
RisingEdge so we capture the beat that will complete on that edge.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

SIDE_BID = 1
SIDE_ASK = 2

F_TOP10_RT = 0x01
F_TOP10_TIMER = 0x02
F_TOP10_REFILL = 0x04
F_RT = F_TOP10_RT
F_TIMER = F_TOP10_TIMER
F_REFILL = F_TOP10_REFILL

N_SYM_TB = 32
N_SYM_SIM = N_SYM_TB
TOP10_MSG_BITS = 2080
TOP10_MSG_BYTES = 260


@dataclass
class Top10Msg:
    symbol_id: int = 0
    ts_ns: int = 0
    seq: int = 0
    flags: int = 0
    bid_vld: int = 0
    ask_vld: int = 0
    bid_px: list[int] = field(default_factory=lambda: [0] * 10)
    bid_qty: list[int] = field(default_factory=lambda: [0] * 10)
    ask_px: list[int] = field(default_factory=lambda: [0] * 10)
    ask_qty: list[int] = field(default_factory=lambda: [0] * 10)
    pad: int = 0


PushMsg = Top10Msg


def start_clock(dut, period_ns: float = 10.0):
    cocotb.start_soon(Clock(dut.clk, period_ns, unit="ns").start())


async def reset(dut, n: int = 5):
    dut.rst_n.value = 0
    dut.clear.value = 0
    dut.csr_enable.value = 0
    dut.csr_period_cycles.value = 20
    dut.csr_snap_skip_empty.value = 1
    dut.csr_base_best16.value = 0
    dut.csr_refill_symbol.value = 0
    dut.csr_refill_side.value = SIDE_BID
    dut.csr_refill_kick.value = 0
    dut.rt_valid.value = 0
    dut.rt_symbol_id.value = 0
    dut.rt_side.value = SIDE_BID
    dut.rt_level.value = 0
    dut.rt_px.value = 0
    dut.rt_qty.value = 0
    dut.rt_lvl_vld.value = 0
    dut.rt_seq.value = 0
    dut.rt_ts_ns.value = 0
    dut.rt_l1_may_have_more.value = 0
    dut.rt_dig_hole.value = 0
    dut.b16_wr_en.value = 0
    dut.b16_symbol_id.value = 0
    dut.b16_side.value = SIDE_BID
    dut.b16_slot.value = 0
    dut.b16_px.value = 0
    dut.b16_qty.value = 0
    dut.b16_vld.value = 0
    dut.push_ready.value = 1
    if hasattr(dut, "l1_rmw_pri_hold"):
        dut.l1_rmw_pri_hold.value = 0
    for _ in range(n):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    for _ in range(3):
        await RisingEdge(dut.clk)


async def csr_write(
    dut,
    *,
    enable: int | None = None,
    period_cycles: int | None = None,
    snap_skip_empty: int | None = None,
    base_best16: int | None = None,
):
    if enable is not None:
        dut.csr_enable.value = enable
    if period_cycles is not None:
        dut.csr_period_cycles.value = period_cycles
    if snap_skip_empty is not None:
        dut.csr_snap_skip_empty.value = snap_skip_empty
    if base_best16 is not None:
        dut.csr_base_best16.value = base_best16
    await RisingEdge(dut.clk)


async def inject_rt(
    dut,
    *,
    symbol_id: int,
    side: int = SIDE_BID,
    level: int = 0,
    px: int = 0,
    qty: int = 0,
    seq: int = 1,
    ts_ns: int = 1,
    lvl_vld: int = 1,
    l1_may_have_more: int = 0,
    dig_hole: int = 0,
):
    dut.rt_symbol_id.value = symbol_id
    dut.rt_side.value = side
    dut.rt_level.value = level
    dut.rt_px.value = px
    dut.rt_qty.value = qty
    dut.rt_lvl_vld.value = lvl_vld
    dut.rt_seq.value = seq
    dut.rt_ts_ns.value = ts_ns
    dut.rt_l1_may_have_more.value = l1_may_have_more
    dut.rt_dig_hole.value = dig_hole
    dut.rt_valid.value = 1
    await RisingEdge(dut.clk)
    assert int(dut.rt_ready.value) == 1
    dut.rt_valid.value = 0
    dut.rt_dig_hole.value = 0
    dut.rt_l1_may_have_more.value = 0


async def poke_best16(
    dut,
    *,
    sid: int | None = None,
    symbol_id: int | None = None,
    side: int,
    slot: int,
    px: int,
    qty: int,
    vld: int = 1,
):
    s = symbol_id if symbol_id is not None else sid
    assert s is not None
    dut.b16_symbol_id.value = s
    dut.b16_side.value = side
    dut.b16_slot.value = slot
    dut.b16_px.value = px
    dut.b16_qty.value = qty
    dut.b16_vld.value = vld
    dut.b16_wr_en.value = 1
    await RisingEdge(dut.clk)
    dut.b16_wr_en.value = 0


async def poke_best16_side10(
    dut, *, symbol_id: int, side: int, base_px: int = 5000, base_qty: int = 100
):
    for i in range(10):
        px = base_px + (i if side == SIDE_ASK else -i)
        await poke_best16(
            dut, symbol_id=symbol_id, side=side, slot=i, px=px, qty=base_qty + i, vld=1
        )


async def kick_refill(dut, sid: int, side: int = SIDE_BID):
    dut.csr_refill_symbol.value = sid
    dut.csr_refill_side.value = side
    dut.csr_refill_kick.value = 1
    await RisingEdge(dut.clk)
    dut.csr_refill_kick.value = 0


def _unpack_px(vec) -> list[int]:
    v = int(vec)
    return [(v >> (i * 64)) & ((1 << 64) - 1) for i in range(10)]


def _unpack_qty(vec) -> list[int]:
    v = int(vec)
    return [(v >> (i * 32)) & ((1 << 32) - 1) for i in range(10)]


def msg_from_dut_push(dut) -> Top10Msg:
    return Top10Msg(
        symbol_id=int(dut.push_symbol_id.value),
        ts_ns=int(dut.push_ts_ns.value),
        seq=int(dut.push_seq.value),
        flags=int(dut.push_flags.value),
        bid_vld=int(dut.push_bid_vld.value),
        ask_vld=int(dut.push_ask_vld.value),
        bid_px=_unpack_px(dut.push_bid_px.value),
        bid_qty=_unpack_qty(dut.push_bid_qty.value),
        ask_px=_unpack_px(dut.push_ask_px.value),
        ask_qty=_unpack_qty(dut.push_ask_qty.value),
    )


async def drain_pushes(dut, cycles: int = 200) -> list[Top10Msg]:
    """Drain by sampling presented beat then clocking the handshake."""
    out: list[Top10Msg] = []
    dut.push_ready.value = 1
    for _ in range(cycles):
        if int(dut.push_valid.value) and int(dut.push_ready.value):
            out.append(msg_from_dut_push(dut))
        await RisingEdge(dut.clk)
    return out


async def collect_pushes(
    dut,
    n: int,
    timeout_cycles: int = 5000,
    only_flags: int | None = None,
    flag_mask: int | None = None,
) -> list[Top10Msg]:
    out: list[Top10Msg] = []
    dut.push_ready.value = 1
    for _ in range(timeout_cycles):
        if int(dut.push_valid.value) and int(dut.push_ready.value):
            m = msg_from_dut_push(dut)
            ok = True
            if only_flags is not None:
                ok = m.flags == only_flags
            if flag_mask is not None:
                ok = bool(m.flags & flag_mask)
            if ok:
                out.append(m)
                await RisingEdge(dut.clk)  # complete this beat
                if len(out) >= n:
                    return out
                continue
        await RisingEdge(dut.clk)
    raise AssertionError(
        f"timeout collecting {n} pushes (got {len(out)}); "
        f"rt={int(dut.push_rt_cnt.value)} tm={int(dut.push_timer_cnt.value)} "
        f"rf={int(dut.push_refill_cnt.value)} disc={int(dut.refill_discard_cnt.value)} "
        f"iss={int(dut.refill_issue_cnt.value)} ddr_rd={int(dut.ddr_rd_cnt.value)}"
    )


def assert_no_a_fail(dut):
    for name in ("a_fail", "assert_fail"):
        if hasattr(dut, name):
            assert int(getattr(dut, name).value) == 0, f"{name} sticky assert set"
            return


def assert_no_axi_fail(dut):
    assert_no_a_fail(dut)


def pack_top10_msg(m: Top10Msg) -> int:
    bid_px = bid_qty = ask_px = ask_qty = 0
    for i in range(10):
        bid_px |= (m.bid_px[i] & ((1 << 64) - 1)) << (i * 64)
        bid_qty |= (m.bid_qty[i] & ((1 << 32) - 1)) << (i * 32)
        ask_px |= (m.ask_px[i] & ((1 << 64) - 1)) << (i * 64)
        ask_qty |= (m.ask_qty[i] & ((1 << 32) - 1)) << (i * 32)
    v = 0
    v |= m.symbol_id & ((1 << 16) - 1)
    v |= (m.ts_ns & ((1 << 64) - 1)) << 16
    v |= (m.seq & ((1 << 32) - 1)) << 80
    v |= (m.flags & 0xFF) << 112
    v |= (m.bid_vld & 0x3FF) << 120
    v |= (bid_px & ((1 << 640) - 1)) << 130
    v |= (bid_qty & ((1 << 320) - 1)) << 770
    v |= (m.ask_vld & 0x3FF) << 1090
    v |= (ask_px & ((1 << 640) - 1)) << 1100
    v |= (ask_qty & ((1 << 320) - 1)) << 1740
    v |= (m.pad & ((1 << 20) - 1)) << 2060
    return v


def unpack_top10_msg(v: int) -> Top10Msg:
    m = Top10Msg()
    m.symbol_id = (v >> 0) & ((1 << 16) - 1)
    m.ts_ns = (v >> 16) & ((1 << 64) - 1)
    m.seq = (v >> 80) & ((1 << 32) - 1)
    m.flags = (v >> 112) & 0xFF
    m.bid_vld = (v >> 120) & 0x3FF
    bid_px = (v >> 130) & ((1 << 640) - 1)
    bid_qty = (v >> 770) & ((1 << 320) - 1)
    m.ask_vld = (v >> 1090) & 0x3FF
    ask_px = (v >> 1100) & ((1 << 640) - 1)
    ask_qty = (v >> 1740) & ((1 << 320) - 1)
    m.pad = (v >> 2060) & ((1 << 20) - 1)
    m.bid_px = [(bid_px >> (i * 64)) & ((1 << 64) - 1) for i in range(10)]
    m.bid_qty = [(bid_qty >> (i * 32)) & ((1 << 32) - 1) for i in range(10)]
    m.ask_px = [(ask_px >> (i * 64)) & ((1 << 64) - 1) for i in range(10)]
    m.ask_qty = [(ask_qty >> (i * 32)) & ((1 << 32) - 1) for i in range(10)]
    return m


def pack_top10_bytes(m: Top10Msg) -> bytes:
    return pack_top10_msg(m).to_bytes(TOP10_MSG_BYTES, "little")


def unpack_top10_bytes(b: bytes) -> Top10Msg:
    if len(b) < TOP10_MSG_BYTES:
        b = b + bytes(TOP10_MSG_BYTES - len(b))
    return unpack_top10_msg(int.from_bytes(b[:TOP10_MSG_BYTES], "little"))
