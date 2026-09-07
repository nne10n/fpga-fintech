"""Helpers for l0_top10_row_t / top10_msg_t packing (matches book_pkg.sv)."""
from __future__ import annotations

from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

# bit widths from book_pkg
L0_ROW_W = 2037
TOP10_MSG_W = 2080

F_TOP10_RT = 0x01
F_TOP10_TIMER = 0x02
F_TOP10_REFILL = 0x04


def pack_l0_row(
    *,
    nonempty: int = 1,
    seq: int = 0,
    ts_ns: int = 0,
    bid_vld: int = 0,
    ask_vld: int = 0,
    bid_px: int = 0,
    bid_qty: int = 0,
    ask_px: int = 0,
    ask_qty: int = 0,
) -> int:
    """MSB-first packed l0_top10_row_t."""
    v = 0
    v = (v << 1) | (nonempty & 1)
    v = (v << 32) | (seq & ((1 << 32) - 1))
    v = (v << 64) | (ts_ns & ((1 << 64) - 1))
    v = (v << 10) | (bid_vld & ((1 << 10) - 1))
    v = (v << 10) | (ask_vld & ((1 << 10) - 1))
    v = (v << 640) | (bid_px & ((1 << 640) - 1))
    v = (v << 320) | (bid_qty & ((1 << 320) - 1))
    v = (v << 640) | (ask_px & ((1 << 640) - 1))
    v = (v << 320) | (ask_qty & ((1 << 320) - 1))
    assert v.bit_length() <= L0_ROW_W
    return v


def unpack_top10_msg(v: int) -> dict:
    """Unpack top10_msg_t (MSB-first as in book_pkg)."""
    x = int(v)
    ask_qty = x & ((1 << 320) - 1); x >>= 320
    # wait — packed struct first field is MSB. So shift from MSB.
    # Rebuild by slicing from top:
    # [pad|ask_qty|ask_px|ask_vld|bid_qty|bid_px|bid_vld|flags|seq|ts_ns|symbol_id]
    x = int(v)
    symbol_id = x & 0xFFFF
    x >>= 16
    ts_ns = x & ((1 << 64) - 1)
    x >>= 64
    seq = x & ((1 << 32) - 1)
    x >>= 32
    flags = x & 0xFF
    x >>= 8
    bid_vld = x & ((1 << 10) - 1)
    x >>= 10
    bid_px = x & ((1 << 640) - 1)
    x >>= 640
    bid_qty = x & ((1 << 320) - 1)
    x >>= 320
    ask_vld = x & ((1 << 10) - 1)
    x >>= 10
    ask_px = x & ((1 << 640) - 1)
    x >>= 640
    ask_qty = x & ((1 << 320) - 1)
    x >>= 320
    pad = x & ((1 << 20) - 1)
    return {
        "pad": pad,
        "ask_qty": ask_qty,
        "ask_px": ask_px,
        "ask_vld": ask_vld,
        "bid_qty": bid_qty,
        "bid_px": bid_px,
        "bid_vld": bid_vld,
        "flags": flags,
        "seq": seq,
        "ts_ns": ts_ns,
        "symbol_id": symbol_id,
    }


def start_clock(dut, period_ns: float = 10.0):
    import cocotb
    cocotb.start_soon(Clock(dut.sys_clk, period_ns, unit="ns").start())


async def reset_sys(dut, cycles: int = 5):
    dut.sys_rst_n.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.sys_clk)
    dut.sys_rst_n.value = 1
    await RisingEdge(dut.sys_clk)
