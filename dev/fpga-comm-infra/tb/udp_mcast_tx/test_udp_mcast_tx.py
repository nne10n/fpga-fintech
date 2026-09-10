from __future__ import annotations

from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, with_timeout

from common.pkt import beats_from_bytes, build_udp_mcast_frame, rfc1112_da

RTL_S2 = Path(__file__).resolve().parents[2] / "rtl" / "udp_mcast_tx" / "udp_mcast_tx.sv"


async def _reset(dut) -> None:
    dut.sys_rst_n.value = 0
    dut.i_s_axis_tvalid.value = 0
    dut.i_s_axis_tlast.value = 0
    dut.i_s_axis_tdata.value = 0
    dut.i_s_axis_tkeep.value = 0
    dut.i_meta_valid.value = 0
    dut.i_m_axis_tready.value = 1
    await ClockCycles(dut.sys_clk, 5)
    dut.sys_rst_n.value = 1
    await ClockCycles(dut.sys_clk, 2)


def _drive_cfg(
    dut,
    *,
    src_mac=0x020000000001,
    src_ip=0x0A00000A,
    dst_ip=0xE1000001,
    src_port=0x1000,
    dst_port=0x2000,
    ttl=1,
    map_en=1,
    mtu=511,
) -> None:
    dut.cfg_src_mac.value = src_mac
    dut.cfg_src_ip.value = src_ip
    dut.cfg_dst_ip.value = dst_ip
    dut.cfg_src_port.value = src_port
    dut.cfg_dst_port.value = dst_port
    dut.cfg_ttl_default.value = ttl
    dut.cfg_map_en.value = map_en
    dut.cfg_mtu_pay.value = mtu


def _drive_meta(
    dut,
    *,
    valid=0,
    dst_ip=0,
    src_ip=0,
    dst_port=0,
    src_port=0,
    ttl=0,
    payload_len=0,
    is_mcast=0,
) -> None:
    dut.i_meta_valid.value = valid
    dut.i_meta_dst_ip.value = dst_ip
    dut.i_meta_src_ip.value = src_ip
    dut.i_meta_dst_port.value = dst_port
    dut.i_meta_src_port.value = src_port
    dut.i_meta_ttl.value = ttl
    dut.i_meta_payload_len.value = payload_len
    dut.i_meta_is_mcast.value = is_mcast


async def send_payload(dut, payload: bytes, meta: dict | None) -> None:
    beats = beats_from_bytes(payload)
    for i, (tdata, tkeep, tlast) in enumerate(beats):
        if i == 0 and meta is not None:
            _drive_meta(dut, valid=1, **meta)
        elif i == 0:
            _drive_meta(dut, valid=0)
        dut.i_s_axis_tdata.value = tdata
        dut.i_s_axis_tkeep.value = tkeep
        dut.i_s_axis_tvalid.value = 1
        dut.i_s_axis_tlast.value = tlast
        await RisingEdge(dut.sys_clk)
        assert int(dut.o_s_axis_tready.value) == 1, "Role A ready must stay 1"
        _drive_meta(dut, valid=0)
    dut.i_s_axis_tvalid.value = 0
    dut.i_s_axis_tlast.value = 0
    dut.i_s_axis_tkeep.value = 0


async def recv_frame(dut, timeout_cycles: int = 4000) -> bytes:
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

    return await with_timeout(_recv(), 5, "ms")


async def expect_no_tx(dut, cycles: int = 80) -> None:
    for _ in range(cycles):
        await RisingEdge(dut.sys_clk)
        assert int(dut.o_m_axis_tvalid.value) == 0, "unexpected TX beat"


def _start(dut) -> None:
    cocotb.start_soon(Clock(dut.sys_clk, 10, units="ns").start())


@cocotb.test()
async def test_s2_h1_csr_then_meta(dut):
    """S2-H1: group/ports not hardcoded; CSR then meta both appear on the wire."""
    _start(dut)
    await _reset(dut)
    rtl = RTL_S2.read_text(encoding="utf-8")
    assert "239." not in rtl
    assert "E1000A0A" not in rtl.upper()
    assert "16'h1234" not in rtl

    _drive_cfg(
        dut,
        src_mac=0x020000000011,
        src_ip=0x0A000001,
        dst_ip=0xE1010203,
        src_port=0x1111,
        dst_port=0x2222,
        ttl=1,
    )
    payload_a = bytes(range(16))
    await send_payload(dut, payload_a, meta=None)
    frame_a = await recv_frame(dut)
    exp_a = build_udp_mcast_frame(
        0x020000000011, 0x0A000001, 0xE1010203, 0x1111, 0x2222, 1, payload_a
    )
    assert frame_a == exp_a, f"CSR path mismatch {frame_a.hex()} vs {exp_a.hex()}"

    payload_b = bytes(range(24, 24 + 20))
    await send_payload(
        dut,
        payload_b,
        meta=dict(
            dst_ip=0xEF00000A,
            src_ip=0xC0A80002,
            dst_port=0xBEEF,
            src_port=0xCAFE,
            ttl=1,
            payload_len=len(payload_b),
            is_mcast=1,
        ),
    )
    frame_b = await recv_frame(dut)
    exp_b = build_udp_mcast_frame(
        0x020000000011, 0xC0A80002, 0xEF00000A, 0xCAFE, 0xBEEF, 1, payload_b
    )
    assert frame_b == exp_b
    assert frame_a[30:34] != frame_b[30:34]
    assert frame_a[36:38] != frame_b[36:38]


@cocotb.test()
async def test_s2_h2_ttl_default_and_zero(dut):
    """S2-H2: default TTL=1; ttl==0 and CSR write 0 both become 1."""
    _start(dut)
    await _reset(dut)
    _drive_cfg(dut, ttl=1)
    p = b"ttl-default"
    await send_payload(
        dut,
        p,
        meta=dict(
            dst_ip=0xE1000001,
            src_ip=0x0A000001,
            dst_port=1,
            src_port=2,
            ttl=1,
            payload_len=len(p),
            is_mcast=1,
        ),
    )
    f1 = await recv_frame(dut)
    assert f1[22] == 1

    _drive_cfg(dut, ttl=0)
    p2 = b"ttl-csr0"
    await send_payload(dut, p2, meta=None)
    f2 = await recv_frame(dut)
    assert f2[22] == 1

    _drive_cfg(dut, ttl=5)
    p3 = b"ttl-meta0"
    await send_payload(
        dut,
        p3,
        meta=dict(
            dst_ip=0xE1000001,
            src_ip=0x0A000001,
            dst_port=1,
            src_port=2,
            ttl=0,
            payload_len=len(p3),
            is_mcast=1,
        ),
    )
    f3 = await recv_frame(dut)
    assert f3[22] == 1

    p4 = b"ttl-meta2"
    await send_payload(
        dut,
        p4,
        meta=dict(
            dst_ip=0xE1000001,
            src_ip=0x0A000001,
            dst_port=1,
            src_port=2,
            ttl=2,
            payload_len=len(p4),
            is_mcast=1,
        ),
    )
    f4 = await recv_frame(dut)
    assert f4[22] == 2


@cocotb.test()
async def test_s2_h3_no_rx_igmp(dut):
    """S2-H3: TX-only — no RX / IGMP ports or state."""
    _start(dut)
    await _reset(dut)
    names = set(str(p._name) if hasattr(p, "_name") else str(p) for p in dut)
    joined = " ".join(names).lower()
    assert "igmp" not in joined
    assert not any("rx" == n.lower() or n.lower().endswith("_rx") for n in names)
    rtl = RTL_S2.read_text(encoding="utf-8").lower()
    assert "igmp" not in rtl
    assert "i_arp" not in rtl and "o_arp" not in rtl
    assert "arp_cache" not in rtl
    assert "s_axis_rx" not in rtl


@cocotb.test()
async def test_s2_size_511_ok_512_drop(dut):
    """S2-size: payload_len 511 sends; >511 / 0 do not send and count drop."""
    _start(dut)
    await _reset(dut)
    _drive_cfg(dut)
    p511 = bytes([x & 0xFF for x in range(511)])
    drops0 = int(dut.o_drop_cnt.value)
    await send_payload(
        dut,
        p511,
        meta=dict(
            dst_ip=0xE1000001,
            src_ip=0x0A000001,
            dst_port=9,
            src_port=8,
            ttl=1,
            payload_len=511,
            is_mcast=1,
        ),
    )
    f = await recv_frame(dut)
    assert f[38:40] == (8 + 511).to_bytes(2, "big")
    assert f[42:] == p511

    p16 = bytes(range(16))
    await send_payload(
        dut,
        p16,
        meta=dict(
            dst_ip=0xE1000001,
            src_ip=0x0A000001,
            dst_port=9,
            src_port=8,
            ttl=1,
            payload_len=512,
            is_mcast=1,
        ),
    )
    await expect_no_tx(dut)
    assert int(dut.o_drop_cnt.value) > drops0
    assert int(dut.o_fail_sticky.value) == 1
    assert int(dut.o_nosend_cnt.value) >= 1


@cocotb.test()
async def test_s2_role_a_ready_and_mac_pause(dut):
    """S2-A: ready ≡ 1; MAC pause does not backpressure producer; overflow drops."""
    _start(dut)
    await _reset(dut)
    _drive_cfg(dut)
    dut.i_m_axis_tready.value = 0
    p1 = b"0123456789abcdef"
    await send_payload(
        dut,
        p1,
        meta=dict(
            dst_ip=0xE1000001,
            src_ip=0x0A000001,
            dst_port=1,
            src_port=2,
            ttl=1,
            payload_len=len(p1),
            is_mcast=1,
        ),
    )
    # Second packet while first is emitting into a paused MAC
    p2 = b"second-packet-xx"
    drops0 = int(dut.o_drop_cnt.value)
    await send_payload(
        dut,
        p2,
        meta=dict(
            dst_ip=0xE1000001,
            src_ip=0x0A000001,
            dst_port=1,
            src_port=2,
            ttl=1,
            payload_len=len(p2),
            is_mcast=1,
        ),
    )
    assert int(dut.o_s_axis_tready.value) == 1
    assert int(dut.o_drop_cnt.value) > drops0
    dut.i_m_axis_tready.value = 1
    f = await recv_frame(dut)
    assert f[42:] == p1


@cocotb.test()
async def test_s2_map_rfc1112_no_arp(dut):
    """S2-map: DA=RFC1112(dip); map_en=0 still derived; user MAC never on-wire DA."""
    _start(dut)
    await _reset(dut)
    src_mac = 0xAABBCCDDEEFF
    dip = 0xEF010203
    _drive_cfg(dut, src_mac=src_mac, dst_ip=dip, map_en=0)
    p = b"map-en-zero"
    await send_payload(dut, p, meta=None)
    f = await recv_frame(dut)
    assert f[0:6] == rfc1112_da(dip)
    assert f[0:6] != src_mac.to_bytes(6, "big")
    assert f[6:12] == src_mac.to_bytes(6, "big")
    assert int(dut.o_map_en_live.value) == 0

    dip2 = 0xE0000001
    await send_payload(
        dut,
        p,
        meta=dict(
            dst_ip=dip2,
            src_ip=0x0A000001,
            dst_port=1,
            src_port=2,
            ttl=1,
            payload_len=len(p),
            is_mcast=1,
        ),
    )
    f2 = await recv_frame(dut)
    assert f2[0:6] == rfc1112_da(dip2)
    assert f2[40:42] == b"\x00\x00"


@cocotb.test()
async def test_s2_payload_len_1(dut):
    """Edge: payload_len=1 is in [1,511] and is sent."""
    _start(dut)
    await _reset(dut)
    _drive_cfg(dut)
    p = b"Z"
    await send_payload(
        dut,
        p,
        meta=dict(
            dst_ip=0xE1000001,
            src_ip=0x0A000001,
            dst_port=7,
            src_port=8,
            ttl=1,
            payload_len=1,
            is_mcast=1,
        ),
    )
    f = await recv_frame(dut)
    await RisingEdge(dut.sys_clk)
    assert f[42:] == p
    assert int(dut.o_tx_ok_cnt.value) >= 1
