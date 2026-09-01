#!/usr/bin/env python3
"""Packet helpers: Ethernet/IPv4/TCP build & parse, checksum utilities."""

from __future__ import annotations

import struct
from dataclasses import dataclass
from typing import Optional


def fold_csum(acc: int) -> int:
    acc &= 0xFFFFFFFF
    while acc >> 16:
        acc = (acc & 0xFFFF) + (acc >> 16)
    return acc & 0xFFFF


def ip_checksum(header: bytes) -> int:
    """Compute IPv4 header checksum (header with checksum field zeroed)."""
    assert len(header) >= 20
    h = bytearray(header)
    h[10] = 0
    h[11] = 0
    acc = 0
    for i in range(0, len(h), 2):
        if i + 1 < len(h):
            acc += (h[i] << 8) | h[i + 1]
        else:
            acc += h[i] << 8
    return (~fold_csum(acc)) & 0xFFFF


def tcp_checksum(src_ip: bytes, dst_ip: bytes, tcp_seg: bytes) -> int:
    """TCP checksum over pseudo-header + segment (checksum field zeroed)."""
    seg = bytearray(tcp_seg)
    if len(seg) < 18:
        raise ValueError("TCP segment too short")
    seg[16] = 0
    seg[17] = 0
    tcp_len = len(seg)
    acc = 0
    # pseudo
    for i in range(0, 4, 2):
        acc += (src_ip[i] << 8) | src_ip[i + 1]
        acc += (dst_ip[i] << 8) | dst_ip[i + 1]
    acc += 6  # protocol
    acc += tcp_len
    for i in range(0, tcp_len, 2):
        if i + 1 < tcp_len:
            acc += (seg[i] << 8) | seg[i + 1]
        else:
            acc += seg[i] << 8
    return (~fold_csum(acc)) & 0xFFFF


def mac_to_bytes(mac: int) -> bytes:
    return mac.to_bytes(6, "big")


def ip_to_bytes(ip: int) -> bytes:
    return ip.to_bytes(4, "big")


@dataclass
class TcpSeg:
    src_mac: int
    dst_mac: int
    src_ip: int
    dst_ip: int
    src_port: int
    dst_port: int
    seq: int
    ack: int
    flags: int
    window: int
    payload: bytes
    ip_csum: int = 0
    tcp_csum: int = 0


TCP_FIN = 0x01
TCP_SYN = 0x02
TCP_RST = 0x04
TCP_PSH = 0x08
TCP_ACK = 0x10


def build_frame(seg: TcpSeg, corrupt_ip_csum: bool = False,
                corrupt_tcp_csum: bool = False) -> bytes:
    payload = seg.payload
    tcp_hdr = bytearray(20)
    struct.pack_into("!HH", tcp_hdr, 0, seg.src_port, seg.dst_port)
    struct.pack_into("!II", tcp_hdr, 4, seg.seq, seg.ack)
    tcp_hdr[12] = 0x50  # data off = 5
    tcp_hdr[13] = seg.flags & 0xFF
    struct.pack_into("!H", tcp_hdr, 14, seg.window)
    # checksum 0 for now
    struct.pack_into("!H", tcp_hdr, 18, 0)
    tcp_seg = bytes(tcp_hdr) + payload

    src_ip_b = ip_to_bytes(seg.src_ip)
    dst_ip_b = ip_to_bytes(seg.dst_ip)
    t_csum = tcp_checksum(src_ip_b, dst_ip_b, tcp_seg)
    if corrupt_tcp_csum:
        t_csum = (t_csum + 1) & 0xFFFF
    tcp_seg = bytearray(tcp_seg)
    struct.pack_into("!H", tcp_seg, 16, t_csum)

    ip_total = 20 + len(tcp_seg)
    ip_hdr = bytearray(20)
    ip_hdr[0] = 0x45
    ip_hdr[1] = 0x00
    struct.pack_into("!H", ip_hdr, 2, ip_total)
    struct.pack_into("!H", ip_hdr, 4, 0x0001)
    struct.pack_into("!H", ip_hdr, 6, 0x4000)
    ip_hdr[8] = 64
    ip_hdr[9] = 6
    ip_hdr[12:16] = src_ip_b
    ip_hdr[16:20] = dst_ip_b
    i_csum = ip_checksum(ip_hdr)
    if corrupt_ip_csum:
        i_csum = (i_csum + 1) & 0xFFFF
    struct.pack_into("!H", ip_hdr, 10, i_csum)

    eth = mac_to_bytes(seg.dst_mac) + mac_to_bytes(seg.src_mac) + b"\x08\x00"
    return bytes(eth + ip_hdr + tcp_seg)


def parse_frame(frame: bytes) -> Optional[TcpSeg]:
    if len(frame) < 54:
        return None
    dst_mac = int.from_bytes(frame[0:6], "big")
    src_mac = int.from_bytes(frame[6:12], "big")
    if frame[12:14] != b"\x08\x00":
        return None
    ihl = (frame[14] & 0x0F) * 4
    if ihl < 20:
        return None
    ip_total = struct.unpack("!H", frame[16:18])[0]
    proto = frame[23]
    if proto != 6:
        return None
    src_ip = int.from_bytes(frame[26:30], "big")
    dst_ip = int.from_bytes(frame[30:34], "big")
    ip_csum_field = struct.unpack("!H", frame[24:26])[0]
    # verify IP csum
    if ip_checksum(frame[14:14 + ihl]) != ip_csum_field:
        # still parse but mark? for tests we assert separately
        pass

    tcp_off = 14 + ihl
    tcp_len = ip_total - ihl
    if len(frame) < tcp_off + tcp_len:
        return None
    tcp = frame[tcp_off:tcp_off + tcp_len]
    src_port, dst_port = struct.unpack("!HH", tcp[0:4])
    seq, ack = struct.unpack("!II", tcp[4:12])
    data_off = (tcp[12] >> 4) * 4
    flags = tcp[13]
    window = struct.unpack("!H", tcp[14:16])[0]
    tcp_csum_field = struct.unpack("!H", tcp[16:18])[0]
    payload = tcp[data_off:]

    calc_tcp = tcp_checksum(frame[26:30], frame[30:34], tcp)
    if calc_tcp != tcp_csum_field:
        pass

    return TcpSeg(
        src_mac=src_mac,
        dst_mac=dst_mac,
        src_ip=src_ip,
        dst_ip=dst_ip,
        src_port=src_port,
        dst_port=dst_port,
        seq=seq,
        ack=ack,
        flags=flags,
        window=window,
        payload=payload,
        ip_csum=ip_csum_field,
        tcp_csum=tcp_csum_field,
    )


def verify_frame_checksums(frame: bytes) -> tuple[bool, bool]:
    """Return (ip_ok, tcp_ok)."""
    if len(frame) < 54 or frame[12:14] != b"\x08\x00":
        return False, False
    ihl = (frame[14] & 0x0F) * 4
    ip_total = struct.unpack("!H", frame[16:18])[0]
    ip_ok = ip_checksum(frame[14:14 + ihl]) == struct.unpack("!H", frame[24:26])[0]
    tcp_off = 14 + ihl
    tcp = frame[tcp_off:tcp_off + (ip_total - ihl)]
    tcp_ok = tcp_checksum(frame[26:30], frame[30:34], tcp) == struct.unpack("!H", tcp[16:18])[0]
    return ip_ok, tcp_ok
