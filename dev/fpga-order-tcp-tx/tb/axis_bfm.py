#!/usr/bin/env python3
"""AXIS-64 byte-stream helpers for cocotb (first wire byte in tdata[7:0])."""

from __future__ import annotations

from cocotb.triggers import RisingEdge


async def reset_dut(dut, cycles: int = 5):
    dut.rst_n.value = 0
    dut.connect_req.value = 0
    dut.close_req.value = 0
    dut.order_we.value = 0
    dut.order_addr.value = 0
    dut.order_wdata.value = 0
    dut.order_len_we.value = 0
    dut.order_len_wdata.value = 0
    dut.order_clear.value = 0
    dut.order_send.value = 0
    dut.s_axis_tdata.value = 0
    dut.s_axis_tkeep.value = 0
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tlast.value = 0
    dut.m_axis_tready.value = 1
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def axis_send_frame(dut, frame: bytes):
    """Drive one Ethernet frame into s_axis_*."""
    i = 0
    n = len(frame)
    while i < n:
        chunk = frame[i : i + 8]
        data = 0
        keep = 0
        for b_i, b in enumerate(chunk):
            data |= (b & 0xFF) << (8 * b_i)
            keep |= 1 << b_i
        dut.s_axis_tdata.value = data
        dut.s_axis_tkeep.value = keep
        dut.s_axis_tvalid.value = 1
        dut.s_axis_tlast.value = 1 if (i + len(chunk) >= n) else 0
        # Hold until a rising edge where tready accepts the beat
        while True:
            await RisingEdge(dut.clk)
            if int(dut.s_axis_tready.value) == 1:
                break
        i += len(chunk)
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tlast.value = 0
    dut.s_axis_tkeep.value = 0


async def axis_recv_frame(dut, timeout_cycles: int = 5000) -> bytes:
    """Collect one frame from m_axis_*."""
    buf = bytearray()
    cycles = 0
    while cycles < timeout_cycles:
        await RisingEdge(dut.clk)
        cycles += 1
        if int(dut.m_axis_tvalid.value) == 1 and int(dut.m_axis_tready.value) == 1:
            data = int(dut.m_axis_tdata.value)
            keep = int(dut.m_axis_tkeep.value)
            last = int(dut.m_axis_tlast.value)
            for b_i in range(8):
                if keep & (1 << b_i):
                    buf.append((data >> (8 * b_i)) & 0xFF)
            if last:
                return bytes(buf)
    raise TimeoutError(f"AXIS RX timeout, got {len(buf)} bytes")


async def pulse(dut, signal_name: str):
    getattr(dut, signal_name).value = 1
    await RisingEdge(dut.clk)
    getattr(dut, signal_name).value = 0


async def load_order(dut, payload: bytes):
    dut.order_clear.value = 1
    await RisingEdge(dut.clk)
    dut.order_clear.value = 0
    for addr, byte in enumerate(payload):
        dut.order_we.value = 1
        dut.order_addr.value = addr
        dut.order_wdata.value = byte
        await RisingEdge(dut.clk)
    dut.order_we.value = 0
    dut.order_len_we.value = 1
    dut.order_len_wdata.value = len(payload)
    await RisingEdge(dut.clk)
    dut.order_len_we.value = 0
