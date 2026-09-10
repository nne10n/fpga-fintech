from __future__ import annotations

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, with_timeout

from common.pkt import beats_from_bytes, build_l2l4_tcp


async def _reset(dut) -> None:
    dut.sys_rst_n.value = 0
    dut.i_s_axis_tvalid.value = 0
    dut.i_s_axis_tlast.value = 0
    dut.i_s_axis_tdata.value = 0
    dut.i_s_axis_tkeep.value = 0
    dut.i_m_axis_tready.value = 1
    await ClockCycles(dut.sys_clk, 5)
    dut.sys_rst_n.value = 1
    await ClockCycles(dut.sys_clk, 2)


async def send_frame(dut, frame: bytes) -> None:
    for tdata, tkeep, tlast in beats_from_bytes(frame):
        dut.i_s_axis_tdata.value = tdata
        dut.i_s_axis_tkeep.value = tkeep
        dut.i_s_axis_tvalid.value = 1
        dut.i_s_axis_tlast.value = tlast
        await RisingEdge(dut.sys_clk)
        assert int(dut.o_s_axis_tready.value) == 1, "Role A ready must stay 1"
    dut.i_s_axis_tvalid.value = 0
    dut.i_s_axis_tlast.value = 0
    dut.i_s_axis_tkeep.value = 0


async def recv_payload(dut, timeout_us: int = 50) -> bytes:
    data = bytearray()

    async def _recv() -> bytes:
        nonlocal data
        while True:
            await RisingEdge(dut.sys_clk)
            if int(dut.o_m_axis_tvalid.value) and int(dut.i_m_axis_tready.value):
                tdata = int(dut.o_m_axis_tdata.value)
                tkeep = int(dut.o_m_axis_tkeep.value)
                tlast = int(dut.o_m_axis_tlast.value)
                for i in range(8):
                    if (tkeep >> i) & 1:
                        data.append((tdata >> (8 * i)) & 0xFF)
                if tlast:
                    return bytes(data)

    return await with_timeout(_recv(), timeout_us, "us")


async def expect_no_tx(dut, cycles: int = 80) -> None:
    for _ in range(cycles):
        await RisingEdge(dut.sys_clk)
        assert int(dut.o_m_axis_tvalid.value) == 0


def _start(dut) -> None:
    cocotb.start_soon(Clock(dut.sys_clk, 10, units="ns").start())


@cocotb.test()
async def test_s1_h4_basic_strip(dut):
    """S1-H4: L2–L4 in, TCP payload out (no headers)."""
    _start(dut)
    await _reset(dut)
    payload = b"hello-tcp-payload-xyz"
    frame = build_l2l4_tcp(payload)
    await send_frame(dut, frame)
    out = await recv_payload(dut)
    assert out == payload
    await RisingEdge(dut.sys_clk)
    assert int(dut.o_ok_cnt.value) >= 1


@cocotb.test()
async def test_s1_h4_tcp_and_ip_options(dut):
    """S1-H4: variable IHL / TCP data-offset; payload start follows options."""
    _start(dut)
    await _reset(dut)
    payload = b"opt-payload-123456"
    ip_opts = bytes([0x01, 0x01, 0x01, 0x00])  # NOPs + EOL
    tcp_opts = bytes([0x02, 0x04, 0x05, 0xB4])  # MSS
    frame = build_l2l4_tcp(payload, ip_opts=ip_opts, tcp_opts=tcp_opts)
    await send_frame(dut, frame)
    out = await recv_payload(dut)
    assert out == payload


@cocotb.test()
async def test_s1_h4_eth_padding_uses_ip_len(dut):
    """S1-H4: Ethernet padding after a short IP datagram is not payload."""
    _start(dut)
    await _reset(dut)
    payload = b"short"
    frame = build_l2l4_tcp(payload, pad_to=64)
    await send_frame(dut, frame)
    out = await recv_payload(dut)
    assert out == payload


@cocotb.test()
async def test_s1_h4_vlan_and_illegal_udp(dut):
    """S1-H4: optional single VLAN still strips; UDP / truncated frames drop+count."""
    _start(dut)
    await _reset(dut)
    payload = b"vlan-tcp-payload"
    frame = build_l2l4_tcp(payload, vlan_tci=0x0007)
    await send_frame(dut, frame)
    out = await recv_payload(dut)
    assert out == payload

    drops0 = int(dut.o_drop_cnt.value)
    udp = build_l2l4_tcp(b"not-tcp", proto=17)
    await send_frame(dut, udp)
    await expect_no_tx(dut)
    assert int(dut.o_drop_cnt.value) > drops0
    assert int(dut.o_fail_sticky.value) == 1

    drops1 = int(dut.o_drop_cnt.value)
    trunc = build_l2l4_tcp(b"abcdefgh")[:20]
    await send_frame(dut, trunc)
    await expect_no_tx(dut)
    assert int(dut.o_drop_cnt.value) > drops1


@cocotb.test()
async def test_s1_role_a_ready(dut):
    """S1-A: ingress ready ≡ 1; downstream pause does not backpressure producer."""
    _start(dut)
    await _reset(dut)
    dut.i_m_axis_tready.value = 0
    p1 = b"first-payload-aaaa"
    await send_frame(dut, build_l2l4_tcp(p1))
    drops0 = int(dut.o_drop_cnt.value)
    p2 = b"second-payload-bbbb"
    await send_frame(dut, build_l2l4_tcp(p2))
    assert int(dut.o_s_axis_tready.value) == 1
    assert int(dut.o_drop_cnt.value) > drops0
    dut.i_m_axis_tready.value = 1
    out = await recv_payload(dut)
    assert out == p1
