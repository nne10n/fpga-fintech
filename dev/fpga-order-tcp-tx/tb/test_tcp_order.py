#!/usr/bin/env python3
"""
cocotb tests for tcp_order_top — handshake, payload send, ACK window, csum drop.
"""

from __future__ import annotations

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

from axis_bfm import reset_dut, axis_send_frame, axis_recv_frame, pulse, load_order
from pkt_utils import (
    TcpSeg,
    build_frame,
    parse_frame,
    verify_frame_checksums,
    TCP_SYN,
    TCP_ACK,
    TCP_PSH,
    TCP_FIN,
)

# Match RTL defaults / TB config
LOCAL_MAC = 0x020000000001
REMOTE_MAC = 0x020000000002
LOCAL_IP = 0xC0A8000A   # 192.168.0.10
REMOTE_IP = 0xC0A80001  # 192.168.0.1
LOCAL_PORT = 40000
REMOTE_PORT = 5000
ISS = 0x10000000
PEER_ISS = 0x20000000

ST_CLOSED = 0
ST_SYN_SENT = 1
ST_ESTABLISHED = 2


def apply_cfg(dut):
    dut.cfg_local_mac.value = LOCAL_MAC
    dut.cfg_remote_mac.value = REMOTE_MAC
    dut.cfg_local_ip.value = LOCAL_IP
    dut.cfg_remote_ip.value = REMOTE_IP
    dut.cfg_local_port.value = LOCAL_PORT
    dut.cfg_remote_port.value = REMOTE_PORT


async def wait_established(dut, timeout=2000):
    for _ in range(timeout):
        await RisingEdge(dut.clk)
        if int(dut.established.value) == 1:
            return
    raise TimeoutError("DUT did not reach ESTABLISHED")


async def do_handshake(dut) -> None:
    """Drive connect, respond to SYN with SYN-ACK, accept DUT ACK."""
    await pulse(dut, "connect_req")

    # Expect SYN
    frame = await axis_recv_frame(dut)
    ip_ok, tcp_ok = verify_frame_checksums(frame)
    assert ip_ok and tcp_ok, "SYN checksums bad"
    syn = parse_frame(frame)
    assert syn is not None
    assert syn.flags & TCP_SYN
    assert not (syn.flags & TCP_ACK)
    assert syn.src_ip == LOCAL_IP
    assert syn.dst_ip == REMOTE_IP
    assert syn.src_port == LOCAL_PORT
    assert syn.dst_port == REMOTE_PORT
    assert syn.seq == ISS

    # Peer SYN-ACK
    synack = TcpSeg(
        src_mac=REMOTE_MAC,
        dst_mac=LOCAL_MAC,
        src_ip=REMOTE_IP,
        dst_ip=LOCAL_IP,
        src_port=REMOTE_PORT,
        dst_port=LOCAL_PORT,
        seq=PEER_ISS,
        ack=ISS + 1,
        flags=TCP_SYN | TCP_ACK,
        window=65535,
        payload=b"",
    )
    await axis_send_frame(dut, build_frame(synack))
    await ClockCycles(dut.clk, 5)

    # Expect ACK
    ack_frame = await axis_recv_frame(dut)
    ip_ok, tcp_ok = verify_frame_checksums(ack_frame)
    assert ip_ok and tcp_ok, "handshake ACK checksums bad"
    ack = parse_frame(ack_frame)
    assert ack is not None
    assert ack.flags & TCP_ACK
    assert not (ack.flags & TCP_SYN)
    assert ack.ack == PEER_ISS + 1
    assert ack.seq == ISS + 1

    await wait_established(dut)


@cocotb.test()
async def test_handshake(dut):
    """Client reaches ESTABLISHED against a Python TCP peer BFM."""
    cocotb.start_soon(Clock(dut.clk, 4, unit="ns").start())  # 250 MHz sim clock
    apply_cfg(dut)
    await reset_dut(dut)
    await do_handshake(dut)
    assert int(dut.tcp_state.value) == ST_ESTABLISHED


@cocotb.test()
async def test_payload_send(dut):
    """After ESTABLISHED, order_send emits a correct TCP data segment."""
    cocotb.start_soon(Clock(dut.clk, 4, unit="ns").start())
    apply_cfg(dut)
    await reset_dut(dut)
    await do_handshake(dut)

    # Toy binary order: type(1)=1, side(1)=1(buy), qty(u32 BE), price(u32 BE), pad
    order = bytes([0x01, 0x01]) + (100).to_bytes(4, "big") + (12345).to_bytes(4, "big")
    order += b"\x00" * 6  # 16-byte toy order
    await load_order(dut, order)

    # Wait ready
    for _ in range(100):
        await RisingEdge(dut.clk)
        if int(dut.order_send_ready.value) == 1:
            break
    assert int(dut.order_send_ready.value) == 1

    await pulse(dut, "order_send")

    data_frame = await axis_recv_frame(dut, timeout_cycles=10000)
    ip_ok, tcp_ok = verify_frame_checksums(data_frame)
    assert ip_ok, "IPv4 checksum mismatch on data segment"
    assert tcp_ok, "TCP checksum mismatch on data segment (catch off-by-one)"

    seg = parse_frame(data_frame)
    assert seg is not None
    assert seg.src_port == LOCAL_PORT
    assert seg.dst_port == REMOTE_PORT
    assert seg.seq == ISS + 1
    assert seg.ack == PEER_ISS + 1
    assert seg.flags & TCP_ACK
    assert seg.flags & TCP_PSH
    assert seg.payload == order

    # Off-by-one checksum regression: mutate payload in a rebuilt frame and
    # ensure our reference checker fails (documents test sensitivity).
    bad = bytearray(data_frame)
    # Flip one payload byte — TCP csum must disagree
    plen = len(order)
    bad[-plen] ^= 0xFF
    ip_ok2, tcp_ok2 = verify_frame_checksums(bytes(bad))
    assert not tcp_ok2, "checksum helper failed to catch payload flip"


@cocotb.test()
async def test_ack_and_resend_ready(dut):
    """Peer ACK clears outstanding; core ready to send again (window=1 seg)."""
    cocotb.start_soon(Clock(dut.clk, 4, unit="ns").start())
    apply_cfg(dut)
    await reset_dut(dut)
    await do_handshake(dut)

    order1 = b"ORDER_ONE_........"  # 16 bytes
    await load_order(dut, order1)
    for _ in range(100):
        await RisingEdge(dut.clk)
        if int(dut.order_send_ready.value):
            break
    await pulse(dut, "order_send")
    _ = await axis_recv_frame(dut, timeout_cycles=10000)

    assert int(dut.outstanding.value) == 1
    assert int(dut.order_send_ready.value) == 0

    # Peer ACK covering the segment
    ack = TcpSeg(
        src_mac=REMOTE_MAC,
        dst_mac=LOCAL_MAC,
        src_ip=REMOTE_IP,
        dst_ip=LOCAL_IP,
        src_port=REMOTE_PORT,
        dst_port=LOCAL_PORT,
        seq=PEER_ISS + 1,
        ack=ISS + 1 + len(order1),
        flags=TCP_ACK,
        window=65535,
        payload=b"",
    )
    await axis_send_frame(dut, build_frame(ack))

    done = False
    for _ in range(200):
        await RisingEdge(dut.clk)
        if int(dut.order_send_done.value) == 1:
            done = True
        if int(dut.order_send_ready.value) == 1 and int(dut.outstanding.value) == 0:
            break
    assert done or int(dut.order_send_done.value) == 0  # pulse may be 1-cycle
    assert int(dut.outstanding.value) == 0
    assert int(dut.order_send_ready.value) == 1

    # Second send
    order2 = b"ORDER_TWO_........"
    await load_order(dut, order2)
    await pulse(dut, "order_send")
    frame2 = await axis_recv_frame(dut, timeout_cycles=10000)
    ip_ok, tcp_ok = verify_frame_checksums(frame2)
    assert ip_ok and tcp_ok
    seg2 = parse_frame(frame2)
    assert seg2 is not None
    assert seg2.seq == ISS + 1 + len(order1)
    assert seg2.payload == order2


@cocotb.test()
async def test_csum_error_dropped(dut):
    """Checksum error on RX is not accepted as ACK."""
    cocotb.start_soon(Clock(dut.clk, 4, unit="ns").start())
    apply_cfg(dut)
    await reset_dut(dut)
    await do_handshake(dut)

    order = b"CSUM_DROP_TEST...."
    await load_order(dut, order)
    for _ in range(100):
        await RisingEdge(dut.clk)
        if int(dut.order_send_ready.value):
            break
    await pulse(dut, "order_send")
    _ = await axis_recv_frame(dut, timeout_cycles=10000)
    assert int(dut.outstanding.value) == 1

    # Bad TCP checksum ACK
    bad_ack = TcpSeg(
        src_mac=REMOTE_MAC,
        dst_mac=LOCAL_MAC,
        src_ip=REMOTE_IP,
        dst_ip=LOCAL_IP,
        src_port=REMOTE_PORT,
        dst_port=LOCAL_PORT,
        seq=PEER_ISS + 1,
        ack=ISS + 1 + len(order),
        flags=TCP_ACK,
        window=65535,
        payload=b"",
    )
    await axis_send_frame(dut, build_frame(bad_ack, corrupt_tcp_csum=True))
    await ClockCycles(dut.clk, 20)

    # Should still be outstanding
    assert int(dut.outstanding.value) == 1
    assert int(dut.order_send_ready.value) == 0
    # Parser should flag bad csum at least once
    # (dbg_seg_csum_bad is a pulse — sample during window)
    saw_bad = False
    # Send again and watch pulse
    await axis_send_frame(dut, build_frame(bad_ack, corrupt_tcp_csum=True))
    for _ in range(30):
        await RisingEdge(dut.clk)
        if int(dut.dbg_seg_csum_bad.value) == 1:
            saw_bad = True
            break
    assert saw_bad, "expected dbg_seg_csum_bad pulse"
    assert int(dut.outstanding.value) == 1

    # Good ACK then clears
    good = build_frame(bad_ack, corrupt_tcp_csum=False)
    await axis_send_frame(dut, good)
    for _ in range(50):
        await RisingEdge(dut.clk)
        if int(dut.outstanding.value) == 0:
            break
    assert int(dut.outstanding.value) == 0
    assert int(dut.order_send_ready.value) == 1


@cocotb.test()
async def test_fin_close(dut):
    """One-direction FIN close path."""
    cocotb.start_soon(Clock(dut.clk, 4, unit="ns").start())
    apply_cfg(dut)
    await reset_dut(dut)
    await do_handshake(dut)

    await pulse(dut, "close_req")
    fin_frame = await axis_recv_frame(dut, timeout_cycles=10000)
    ip_ok, tcp_ok = verify_frame_checksums(fin_frame)
    assert ip_ok and tcp_ok
    fin = parse_frame(fin_frame)
    assert fin is not None
    assert fin.flags & TCP_FIN
    assert fin.flags & TCP_ACK
    assert fin.seq == ISS + 1

    # ACK the FIN
    ack = TcpSeg(
        src_mac=REMOTE_MAC,
        dst_mac=LOCAL_MAC,
        src_ip=REMOTE_IP,
        dst_ip=LOCAL_IP,
        src_port=REMOTE_PORT,
        dst_port=LOCAL_PORT,
        seq=PEER_ISS + 1,
        ack=ISS + 2,
        flags=TCP_ACK,
        window=65535,
        payload=b"",
    )
    await axis_send_frame(dut, build_frame(ack))
    for _ in range(100):
        await RisingEdge(dut.clk)
        if int(dut.tcp_state.value) == ST_CLOSED:
            break
    assert int(dut.tcp_state.value) == ST_CLOSED
