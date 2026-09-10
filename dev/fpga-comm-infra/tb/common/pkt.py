"""Packet builders for G1 S1/S2 cocotb tests. AXIS lane 0 = first on-wire byte."""

from __future__ import annotations


def rfc1112_da(dip: int) -> bytes:
    return bytes(
        [
            0x01,
            0x00,
            0x5E,
            (dip >> 16) & 0x7F,
            (dip >> 8) & 0xFF,
            dip & 0xFF,
        ]
    )


def ipv4_checksum(hdr: bytes) -> int:
    s = 0
    for i in range(0, len(hdr), 2):
        s += (hdr[i] << 8) | hdr[i + 1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def mac_bytes(mac: int) -> bytes:
    return mac.to_bytes(6, "big")


def ip_bytes(ip: int) -> bytes:
    return ip.to_bytes(4, "big")


def build_udp_mcast_frame(
    src_mac: int,
    src_ip: int,
    dst_ip: int,
    src_port: int,
    dst_port: int,
    ttl: int,
    payload: bytes,
) -> bytes:
    da = rfc1112_da(dst_ip)
    sa = mac_bytes(src_mac)
    eth = da + sa + bytes([0x08, 0x00])
    tot = 20 + 8 + len(payload)
    ip = bytearray(20)
    ip[0] = 0x45
    ip[2] = (tot >> 8) & 0xFF
    ip[3] = tot & 0xFF
    ip[8] = ttl & 0xFF
    ip[9] = 17
    ip[12:16] = ip_bytes(src_ip)
    ip[16:20] = ip_bytes(dst_ip)
    csum = ipv4_checksum(bytes(ip))
    ip[10] = (csum >> 8) & 0xFF
    ip[11] = csum & 0xFF
    udp = bytearray(8)
    udp[0:2] = src_port.to_bytes(2, "big")
    udp[2:4] = dst_port.to_bytes(2, "big")
    ulen = 8 + len(payload)
    udp[4:6] = ulen.to_bytes(2, "big")
    return bytes(eth) + bytes(ip) + bytes(udp) + payload


def build_l2l4_tcp(
    payload: bytes,
    *,
    src_mac: bytes = bytes.fromhex("aabbccddeeff"),
    dst_mac: bytes = bytes.fromhex("112233445566"),
    src_ip: int = 0x0A000001,
    dst_ip: int = 0x0A000002,
    src_port: int = 40000,
    dst_port: int = 80,
    ip_opts: bytes = b"",
    tcp_opts: bytes = b"",
    vlan_tci: int | None = None,
    proto: int = 6,
    ip_flags_frag: int = 0x4000,
    pad_to: int | None = None,
) -> bytes:
    if len(ip_opts) % 4:
        raise ValueError("IP options must be 4-byte aligned")
    if len(tcp_opts) % 4:
        raise ValueError("TCP options must be 4-byte aligned")
    ihl = 5 + len(ip_opts) // 4
    doff = 5 + len(tcp_opts) // 4
    ip_payload_len = doff * 4 + len(payload)
    ip_tot = ihl * 4 + ip_payload_len
    if vlan_tci is None:
        eth = dst_mac + src_mac + bytes([0x08, 0x00])
    else:
        eth = (
            dst_mac
            + src_mac
            + bytes([0x81, 0x00])
            + vlan_tci.to_bytes(2, "big")
            + bytes([0x08, 0x00])
        )
    ip = bytearray(ihl * 4)
    ip[0] = 0x40 | (ihl & 0xF)
    ip[2] = (ip_tot >> 8) & 0xFF
    ip[3] = ip_tot & 0xFF
    ip[6] = (ip_flags_frag >> 8) & 0xFF
    ip[7] = ip_flags_frag & 0xFF
    ip[8] = 64
    ip[9] = proto
    ip[12:16] = ip_bytes(src_ip)
    ip[16:20] = ip_bytes(dst_ip)
    if ip_opts:
        ip[20 : 20 + len(ip_opts)] = ip_opts
    csum = ipv4_checksum(bytes(ip))
    ip[10] = (csum >> 8) & 0xFF
    ip[11] = csum & 0xFF
    tcp = bytearray(doff * 4)
    tcp[0:2] = src_port.to_bytes(2, "big")
    tcp[2:4] = dst_port.to_bytes(2, "big")
    tcp[12] = (doff & 0xF) << 4
    tcp[13] = 0x10  # ACK
    if tcp_opts:
        tcp[20 : 20 + len(tcp_opts)] = tcp_opts
    frame = bytes(eth) + bytes(ip) + bytes(tcp) + payload
    if pad_to is not None and len(frame) < pad_to:
        frame = frame + bytes(pad_to - len(frame))
    return frame


def beats_from_bytes(buf: bytes) -> list[tuple[int, int, int]]:
    """Return list of (tdata, tkeep, tlast)."""
    out: list[tuple[int, int, int]] = []
    n = len(buf)
    if n == 0:
        return out
    off = 0
    while off < n:
        chunk = buf[off : off + 8]
        tdata = 0
        tkeep = 0
        for i, b in enumerate(chunk):
            tdata |= b << (8 * i)
            tkeep |= 1 << i
        off += len(chunk)
        tlast = 1 if off >= n else 0
        out.append((tdata, tkeep, tlast))
    return out


def bytes_from_beats(beats: list[tuple[int, int, int]]) -> bytes:
    data = bytearray()
    for tdata, tkeep, _tlast in beats:
        for i in range(8):
            if (tkeep >> i) & 1:
                data.append((tdata >> (8 * i)) & 0xFF)
    return bytes(data)
