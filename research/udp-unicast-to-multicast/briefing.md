# FPGA UDP Unicast → Multicast: Gap Analysis Guide

**Date:** 2026-09-07 (Monday)  
**Audience:** FPGA / fintech engineers with working unicast UDP  
**Scope:** What must be **added or changed** for UDP multicast RX and/or TX  
**Rule:** Every concrete claim has a URL. No invented register names, IP options, or latency numbers.

---

## 0. Executive summary (for gap analysis)

Given a design that already sends/receives **unicast UDP**, multicast is not “just another destination IP.” The gaps fall into four layers:

| Layer | Typical unicast assumption | Multicast change |
|-------|---------------------------|------------------|
| L2 MAC | Filter only station unicast (+ maybe broadcast) | Accept group MAC(s) derived from group IP; unicast filter alone drops mcast |
| L3 membership | N/A | Host (or FPGA) must **join** via IGMP/MLD so switches/routers forward the stream |
| L3/UDP datapath | Dest IP == local unicast | Accept `224.0.0.0/4` (and SSM `232/8` if used); TX maps group→mcast MAC, **no ARP of group** |
| Network | Point-to-point path | IGMP snooping / PIM-SM on colo fabric; A/B dual groups for market data |

**What can usually stay:** Ethernet PCS/MAC datapath framing, UDP length/port parsing, UDP/IP checksum algorithms (same math), PHY, most DMA.

**What almost always must change for RX:** MAC address filter (or promiscuous + custom filter), IP dest acceptance of class-D, membership signaling (IGMP), switch-side snooping/PIM.

**What almost always must change for TX:** Dest MAC = multicast MAC (not ARP lookup of group), TTL policy, do not place group in IP SA.

---

## 1. L2 / MAC

### 1.1 IPv4 multicast MAC derivation

RFC 1112 §6.4: map an IP host group to Ethernet by placing the **low-order 23 bits** of the IP address into the low-order 23 bits of `01-00-5E-00-00-00`. Because 28 significant bits exist in the group address but only 23 map to MAC, **multiple groups share one MAC** (32:1 ambiguity).

- Spec: https://www.rfc-editor.org/rfc/rfc1112.txt  
- Same mapping restated in many engineering notes; prefer RFC as authority.

Example (illustrative of the RFC rule):  
`239.1.2.3` → `01:00:5e:01:02:03` (low 23 bits of the IP).

### 1.2 IPv6 multicast MAC (if relevant)

RFC 2464 §7: IPv6 multicast DST maps to Ethernet MAC whose first two octets are `33:33` and whose last four octets are the last four octets of DST.

- Spec: https://datatracker.ietf.org/doc/html/rfc2464  
- IPv6 membership uses **MLD/MLDv2**, not IGMP: https://www.rfc-editor.org/rfc/rfc2710 ; https://www.rfc-editor.org/rfc/rfc3810  

Most exchange market-data feeds documented in this research are **IPv4 UDP multicast**; treat IPv6 as optional unless your venue requires it.

### 1.3 What a unicast MAC filter misses

RFC 1112 §7.4: Ethernet module must be able to receive packets addressed to the Ethernet multicast addresses corresponding to the host’s IP host groups; hardware filtering is desirable so the host receives only destined frames. If the hardware filter capacity is exceeded, implementations may need to open the filter to accept more (or all) multicast packets and filter higher up.

- Spec: https://www.rfc-editor.org/rfc/rfc1112.txt  

**Implication for FPGA unicast designs:** if the MAC only matches the station unicast DA (and maybe broadcast `ff:ff:ff:ff:ff:ff`), frames with DA `01:00:5e:…` are dropped **before** your UDP stack sees them. Enabling multicast RX requires one of:

1. Perfect / programmable match entries for each needed mcast MAC  
2. Hash-based multicast accept table  
3. Promiscuous (or “accept all multicast”) mode + L3/UDP filtering in fabric or software  

### 1.4 Vendor / open MAC filter options (documented)

#### AMD AXI Ethernet Subsystem (PG138) — extended multicast table

When extended multicast filtering is selected (`C_MCAST_EXTEND = 1`), a Multicast Address Table is present. On RX of a multicast frame, hardware verifies the initial 24 bits are `01:00:5E`, then uses the **upper 15 bits of the unique 23-bit** Ethernet MAC multicast address to index memory. If the entry is 1, the frame is accepted and passed to software for full 23-bit comparison; if 0 (or prefix mismatch), it is dropped.

Important PG138 note: when using extended multicast filtering, the TEMAC must be set to **promiscuous mode** so frames are available for filtering; unicast match is then provided by additional registers (UAWL/UAWU).

- Multicast Address Table: https://docs.amd.com/r/en-US/pg138-axi-ethernet/Multicast-Address-Table-Offset-0x0002_0000-0x0003_FFFF  
- Implementation details (promiscuous + extended mcast): https://docs.amd.com/r/en-US/pg138-axi-ethernet/Implementation-Details  

#### AMD Tri-Mode Ethernet MAC (PG051) — frame filter

Optional frame filter: when enabled, frames that do not match known addresses / configurable filters are not passed. Configurable filters (value + mask over first 64 bytes) can do Destination Address filtering, multicast group matching, VLAN field matching. Promiscuous mode (Frame Filter Control) passes all frames regardless of DA.

- Frame Filter: https://docs.amd.com/r/en-US/pg051-tri-mode-eth-mac/Frame-Filter  
- Using the Frame Filter (DA / multicast / VLAN / promiscuous): https://docs.amd.com/r/en-US/pg051-tri-mode-eth-mac/Using-the-Frame-Filter  
- Frame Filter Configuration: https://docs.amd.com/r/en-US/pg051-tri-mode-eth-mac/Frame-Filter-Configuration  

#### Intel / Altera Triple-Speed Ethernet — multicast hash table

Optional 64-entry multicast hash table for hardware multicast address resolution. Host builds the table; a 6-bit code is generated by XORing address bits; write-1 validates that hash bucket. `MHASH_SEL` chooses XOR over all 48 bits or lower 24 bits. No hash match → frame discarded. Filling all entries with 1 accepts all multicast. Docs warn: fill the table and set RX enable appropriately before use.

- Multicast Address Resolution: https://docs.altera.com/r/docs/683402/25.3/triple-speed-ethernet-ip-user-guide/multicast-address-resolution  
- Also: https://www.intel.com/content/www/us/en/docs/programmable/813669/24-1-4-0-0/multicast-address-resolution.html  
- Feature summary (up to 5 unicast + 64 multicast / hash): https://cdrdv2-public.intel.com/705247/ug-ethernet-16.0-683402-705247.pdf  

#### AMD 10G/25G High Speed Ethernet (PG210 / XXV)

Product guide documents RX/TX multicast **statistics** counters (`stat_rx_multicast`, `stat_tx_multicast`) and control signals related to multicast destination address processing for **pause/control** frames. Baremetal wiki notes that directing RX to MCDMA channels by MAC is done with **user logic**, not a documented built-in perfect multicast membership table in the same sense as PG138’s extended mcast table.

- PG210 PDF (v4.1): https://www.xilinx.com/support/documents/ip_documentation/xxv_ethernet/v4_1/pg210-25g-ethernet.pdf  
- Baremetal XXV + MCDMA MAC-filter note: https://xilinx-wiki.atlassian.net/wiki/spaces/A/pages/18842542/Baremetal+XXV+Ethernet+driver  

**Gap-analysis takeaway:** for 10G/25G/100G CMAC-style IPs, plan on **custom AXI-Stream filter** (mcast MAC and/or IP group + UDP port) unless you deliberately use promiscuous + host filtering.

#### Corundum / OpenNIC

- Corundum: open FPGA NIC with Linux driver integration, MAC+PHY, queues, checksum offload, PTP; **application block** for custom datapath logic. No Corundum core README claim of a built-in IGMP engine or dedicated multicast join table was found in project docs reviewed.  
  - https://github.com/corundum/corundum/blob/master/README.md  
  - https://docs.corundum.io/en/latest/  
  - Paper (architecture): https://leed.sysnet.ucsd.edu/papers/CorundumPaper.pdf  

- OpenNIC: shell with user-logic insertion points; Silicom adaptation documents a **configurable MAC TX/RX filter**; for multicast/broadcast their description forwards to all endpoints. Base OpenNIC is a platform for custom acceleration, not a full host IGMP stack in RTL.  
  - https://github.com/Xilinx/open-nic  
  - Silicom OpenNIC MAC filter note (PDF): https://www.silicom.dk/wp-content/uploads/2023/11/SB_ONIC_SRIOV_DPDK.pdf  
  - iWave note mentioning unicast and multicast MAC filtering on iW-Fibre: https://iwave-global.com/articles/opennic-fpga-smartnic-shell-on-iw-fibre-platforms/  

#### alexforencich verilog-ethernet

Provides `eth_mac_*`, `ip` / `ip_complete`, `udp` / `udp_complete`, ARP. README lists UDP/IP/ARP modules; **no dedicated IGMP or multicast-join module** in the module list. TX path uses ARP for unicast MAC resolution via `arp_request_*` in `ip` — unsuitable for group destinations (see §3).

- Repo: https://github.com/alexforencich/verilog-ethernet  
- Wiki readme: https://alexforencich.com/wiki/en/verilog/ethernet/readme  

### 1.5 VLAN-tagged multicast in colo

VLAN tagging is **venue-specific**, not universal:

- NYSE / ICE LCN (Mahwah): customer LCN interfaces **not** configured for 802.1Q; customer VLAN tags may be ignored or discarded. Multicast on LCN described via **PIM-SM**.  
  - https://www.nyse.com/publicdocs/IGN_Colocation_Mahwah_Technical_Specs.pdf  

- MOEX colo: LACP trunk with **802.1Q** tagging for production/game server segment.  
  - http://ftp.moex.com/pub/connectivityguides/en/mcg1001-en-colocation-connectivityguide.pdf  

- Eurex N7 access guide: do **not** use 802.1Q on 10 Gbit access circuits.  
  - https://www.eurex.com/resource/blob/1399386/eb71ba678d7daa15ff073e4e074de318/data/N7_Network_Access_Guide_v.2.0.40.pdf  

**FPGA implication:** if the colo path delivers 802.1Q-tagged frames, your MAC/parser must strip or match VLAN (TPID `0x8100`) **before** ethertype/IP; PG051 documents VLAN field matching via frame filter masks. If the path is untagged (common on some LCNs), do not invent a VLAN requirement.

---

## 2. L3 / IGMP / MLD

### 2.1 Why joining matters

RFC 1112 levels of conformance:

- **Level 1:** send multicast only (no receive / no join)  
- **Level 2:** full receive — requires Join/Leave host-group ops and **IGMP**  

Receiving requires maintaining membership per interface; join notifies the local network module to update the multicast reception filter; IGMP keeps neighboring multicast routers informed.

- https://www.rfc-editor.org/rfc/rfc1112.txt  

IGMPv2 adds Leave and faster leave latency: https://www.rfc-editor.org/rfc/rfc2236.html  
IGMPv3 adds source filtering (INCLUDE/EXCLUDE) needed for SSM-style interest: https://www.rfc-editor.org/rfc/rfc3376  

### 2.2 Does the FPGA need an IGMP engine?

**Two valid architectures:**

| Architecture | Who sends IGMP Reports / Leave? | Who filters data plane? | When used |
|--------------|----------------------------------|-------------------------|-----------|
| **CPU-assisted** | Host OS / soft core / lwIP (`igmp_joingroup`) on same L2 domain / bonded NIC path that the switch associates with the port | FPGA MAC/IP filter accepts group MAC/IP | Common when FPGA is RX datapath and a CPU owns the control plane |
| **Full hardware IGMP** | FPGA RTL / soft UDP+IGMP IP | Same FPGA | Bare-metal / no CPU, or commercial TOE with IGMP |

Evidence / examples:

- CAST UDPIP-1G datasheet lists **IGMP v3 (Multicast)**, UDP unicast and multicast, per-channel multicast enable and receive group: https://www.cast-inc.com/sites/default/files/pdfs/2025-07/cast_udpip-1g-amd.pdf  
- Design Gateway UDP1G-IP (Altera listing) claims multicast/broadcast support in a full hardware UDP stack: https://www.altera.com/asap/offering/a1jui0000049u9omae/1g-udp-offloading-engine-udp1g-ip  
- Zynq + lwIP pattern: enable `LWIP_IGMP`, call `igmp_joingroup`, and open MAC filter / promiscuous — Chinese engineering note: https://www.kuazhi.com/post/714536054.html  

**Critical rule:** if the FPGA only programs a MAC/IP filter **without** any IGMP (or without static join / push on the upstream switch), then on networks with **IGMP snooping**, the switch may **not forward** the group to your port (see §5). Filtering alone ≠ membership.

### 2.3 Querier, reports, leave — what breaks without IGMP

- Routers send Membership Queries; hosts send Reports (v1/v2/v3) and Leaves (v2+).  
- IGMPv1/v2 hosts **suppress** their own Report if they hear another host’s Report for the same group — snooping switches must still see a Report from the interested port or they will not forward data to that port (RFC 4541).  
  - https://www.rfc-editor.org/rfc/rfc4541.html  

If you only open the MAC filter:

- On a **flooding** L2 segment without snooping: you may still receive (noisy, non-scalable).  
- On a **snooping** switch with prune of unregistered groups: you receive **nothing** for that group.  
- Vendor behavior for “unregistered” multicast varies (flood vs drop); RFC 4541 makes flooding of unregistered packets configurable/recommended carefully.

### 2.4 PIM — when FPGA need not implement it

PIM-SM is a **router** protocol: the Designated Router sees IGMP/MLD from hosts and sends PIM Join/Prune toward the RP / source tree.

- https://www.rfc-editor.org/rfc/rfc4601.html  
- Host interest is typically IGMP/MLD only (same doc overview).

**FPGA as end host / NIC:** implement **IGMP/MLD host side** (or rely on CPU / static OIF on provider switch). Do **not** need PIM unless you are building a multicast router on the FPGA.

Colo example: ICE LCN documents PIM-SM as the primary multicast distribution method inside the data center — customers may need PIM-SM-capable **network gear**, not PIM inside the FPGA NIC:  
https://www.nyse.com/publicdocs/IGN_Colocation_Mahwah_Technical_Specs.pdf  

JSE guidance can use **static OIF** push of market-data groups (no client PIM/IGMP joins accepted for those groups in that model):  
https://www.jse.co.za/sites/default/files/media/documents/jse-colocation-network-configuration-guidance-note/JSE%20Colocation%20Network%20Configuration%20Guidance%20Note%20v0.7.1.pdf  

---

## 3. UDP/IP datapath changes vs unicast

### 3.1 Destination IP check (RX)

Class D / host group range: `224.0.0.0`–`239.255.255.255` (`224.0.0.0/4`) per RFC 1112 §4:  
https://www.rfc-editor.org/rfc/rfc1112.txt  

SSM destination block `232.0.0.0/8` per RFC 4607 / IANA guidelines:  
- https://www.rfc-editor.org/rfc/rfc4607.html  
- https://datatracker.ietf.org/doc/rfc5771/  

**Change vs unicast:** replace or extend “dest IP == my unicast IP” with:

- accept packets whose dest IP is in the **joined group set**, and/or  
- accept `224.0.0.0/4` then demux by exact group + UDP port, and  
- for SSM, optionally filter on **(S,G)** (needs IGMPv3 INCLUDE and IP SA check).

Because of 32:1 MAC aliasing (RFC 1112 / RFC 4541), **L3 exact group match is mandatory** if you care about not processing alien groups that share the MAC.

### 3.2 Checksum

UDP checksum algorithm is unchanged for multicast: same pseudo-header (includes destination address — here the **group** address), UDP header, data (RFC 768):  
https://www.rfc-editor.org/rfc/rfc768.html  

IPv4 header checksum likewise covers the header with dest = group address; no special multicast checksum mode in the RFCs cited.

**Stay:** existing checksum engines.  
**Change:** ensure TX builds checksums with dest = group IP; RX verifies using received dest (group).

### 3.3 ARP

RFC 1112 §6.2–6.4: when destination is a host group, send **locally** to that group (map to Ethernet multicast MAC). ARP is the unicast IP-to-MAC mapping mechanism; group destinations use the deterministic MAC map instead.

- Do **not** ARP for the multicast group address as if it were a unicast host.  
- Host group address must never be used as IP **source** (§6.2).  
- For TX beyond the local link, TTL > 1 and multicast routers forward; default TTL for multicast if unspecified should be **1** (§6.1).

**Source still needs ARP/gateway for TX replies / unicast control** (e.g., TCP retransmit requests, management): that path remains unicast ARP as today.

### 3.4 TX multicast packet construction

Must-change checklist for TX:

1. IP DA = group address (`224/4`)  
2. IP SA = interface unicast address (never the group)  
3. Ethernet DA = mapped multicast MAC (`01:00:5e` + 23 bits)  
4. Ethernet SA = local MAC  
5. TTL: often 1 for link-local scope; set explicitly if leaving the LAN  
6. Skip ARP lookup for DA; do not fall through “ARP fail → drop” paths designed for unicast  

RFC 1112 also notes: a host need **not** be a member of a group to **send** to it (Level 1).

### 3.5 Multiple sockets / groups / fan-out

RFC 1112: a host may belong to more than one group; multiple upper-layer protocols may join the same group; join/leave are reference-counted.  
For market data: typically many channels = many (group, port) pairs; FPGA needs a **membership table** sized for N groups and a demux to multiple RX streams / DMA queues.

Commercial soft stacks document multi-channel UDP with per-channel multicast enable (CAST):  
https://www.cast-inc.com/sites/default/files/pdfs/2025-07/cast_udpip-1g-amd.pdf  

---

## 4. FPGA-specific stack pieces

### 4.1 Soft UDP stacks (alexforencich)

Modules that appear in a unicast UDP design and remain relevant:

- `eth_mac_*` — L2  
- `ip` / `ip_eth_rx|tx` / `ip_complete` — IPv4 + ARP hook  
- `udp` / `udp_ip_rx|tx` / `udp_complete` — UDP  

**Gaps for multicast (inferred from public module list + ARP-centric TX):**

- No IGMP module in published tree → add CPU IGMP or custom RTL  
- TX ARP path must be bypassed for group DA  
- RX local-IP equality check (if present in your integration) must accept groups  
- Optional: `udp_demux` / custom CAM for multi-group multi-port  

Sources: https://github.com/alexforencich/verilog-ethernet ; https://alexforencich.com/wiki/en/verilog/ethernet/readme  

### 4.2 Tick-to-trade / HFT style RX filter

HFT FPGA filters often parse Eth/IP/UDP at line rate and match dest port (and optionally group IP). Example open educational filter (port match focused):  
https://github.com/AditiKulkarni454/hft-udp-filter  

Such designs still depend on **network membership + MAC delivery**; the filter alone does not replace IGMP on snooping fabrics.

### 4.3 CPU-assisted vs full hardware IGMP (decision guide)

| Constraint | Prefer |
|------------|--------|
| Host Linux + Corundum/OpenNIC as NIC | Kernel IGMP + driver programs MAC filter / steers queues; FPGA app block filters hot path |
| Zynq PS + PL Ethernet | lwIP IGMP on PS; PL MAC promiscuous or mcast table |
| No CPU, hard real-time join/leave | Hardware IGMP (CAST/Intilop-class) or static switch OIF |
| RX-only market data, provider pushes groups | May skip host IGMP if colo **static-forwards** groups to your port (confirm with venue doc) |

---

## 5. Switch / network side (critical)

### 5.1 IGMP snooping: flood vs prune

Without snooping, bridges flood multicast like unknown DA (bandwidth waste). Snooping switches constrain forwarding using IGMP membership (RFC 4541).

Key RFC 4541 data rules:

- Non-IGMP packets outside `224.0.0.X` forwarded per membership tables **and** to router ports  
- `224.0.0.X` non-IGMP flooded to all ports  
- Unregistered multicast: must go to router ports; may flood all ports; vendors that drop must offer a flood option  
- Prefer **IP-based** forwarding tables over MAC-only because of 32:1 aliasing  

https://www.rfc-editor.org/rfc/rfc4541.html  

**Operational:** ensure IGMP snooping is on **and** your port’s membership is visible (Report or static). Misconfigured snooping is a top reason “FPGA filter is correct but no packets arrive.”

### 5.2 PIM-SM for L3

Across subnets / colo fabrics, PIM-SM builds trees from IGMP interest at the DR. Hosts/FPGAs do not run PIM; routers do.  
https://www.rfc-editor.org/rfc/rfc4601.html  

### 5.3 Exchange colo practices (A/B feeds)

Dual redundant UDP multicast lines (A/B), same sequenced data, client arbitrates:

- CME MDP 3.0: UDP Feed A and B; recommend processing both; TCP Recovery / Market Recovery for gaps:  
  https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/457325847/MDP+3.0+-+Recovery+Services+for+UDP  

- LME LMEsource: UDP multicast channels, redundant lines A and B; TCP retransmission / refresh for recovery:  
  https://www.lme.com/-/media/Files/Trading/Systems/LMEsource/LMEsource-v4-Developer-Guide-v11.pdf  

- JSE: Market Data via UDP multicast, Feed-A and Feed-B; arbitration recommended:  
  https://www.jse.co.za/sites/default/files/jse_document_manager/RW/Internal/ITaC/Trading%20and%20Market%20Data%20Documentation/Volume%20B%20Trading%20and%20Information%20Network%20Configuration%20Guide%20v3.01.pdf  

**FPGA note:** A and B are usually **two multicast groups** (and/or ports/paths). Size filters and IGMP joins for both. RX-only multicast + separate **unicast TCP** recovery path is the common pattern (CME/LME docs above).

---

## 6. Finance note: multicast vs TCP recovery

Exchanges favor UDP multicast for fan-out latency; reliability is layered:

1. Dual A/B multicast  
2. Sequence numbers → gap detect  
3. TCP retransmission or snapshot/refresh recovery  

Sources: CME recovery page and LME developer guide linked in §5.3; industry discussion of multicast gaps:  
https://www.keysight.com/blogs/en/tech/nwvs/2020/06/10/why-you-cant-trust-your-market-data-feed-multicast-gaps  

**FPGA practice (sourced pattern):** hardware path often optimizes **RX multicast decode**; recovery/retransmit may stay on CPU/TCP unicast. Do not assume the FPGA must implement TCP recovery unless that is your product requirement.

---

## 7. Checklists

### 7.1 Unicast already OK → enable multicast **RX**

Ordered; **M** = must-change / must-add for typical snooping colo; **O** = optional / venue-dependent.

1. **[M]** Confirm colo delivery model: IGMP dynamic join vs static OIF push vs flood (venue guide).  
2. **[M]** Derive mcast MAC(s) from group IP(s) (RFC 1112).  
3. **[M]** Change MAC RX filter: add perfect/hash entries, or promiscuous + fabric filter (PG051 / PG138 / Intel TSE / custom CMAC filter).  
4. **[M]** Extend IP DA accept: joined groups / `224/4` (and SSM `232/8` + source filter if needed).  
5. **[M]** Exact L3 group match (and UDP port) because of MAC aliasing.  
6. **[M]** Membership: host IGMP join **or** hardware IGMP **or** provider static forward — pick one that matches the fabric.  
7. **[M]** If IGMPv3/SSM required by venue, support INCLUDE (S,G).  
8. **[O]** VLAN strip/match if colo trunks 802.1Q (MOEX yes; some LCN/Eurex no).  
9. **[O]** Multi-group table + demux to queues (A/B feeds, multiple channels).  
10. **[M]** Verify with switch: snooping shows your port in group; capture DA=`01:00:5e:…` and IP DA=group.  
11. **[O]** MLD only if IPv6 market data.  
12. **[—]** PIM: not on FPGA host path.

### 7.2 Unicast already OK → enable multicast **TX**

1. **[M]** IP DA = group; IP SA = interface unicast (RFC 1112).  
2. **[M]** Eth DA = mapped mcast MAC; do not ARP the group.  
3. **[M]** Bypass unicast-only “ARP miss drop” on TX.  
4. **[M]** Set TTL deliberately (default 1 if unspecified per RFC 1112).  
5. **[O]** IGMP membership not required to send (Level 1), but may still want join if you also RX.  
6. **[O]** Loopback control if FPGA is also a member of the TX group.  
7. **[—]** Checksum engines: keep; feed group address into pseudo-header.  
8. **[O]** Rate / fan-out / multiple groups: scheduler and header templates.

### 7.3 What can stay (usually)

- PCS/PMA, MAC CRC, basic frame delimiters  
- UDP port parse, payload DMA, existing unicast TX/RX for recovery/control  
- Checksum **algorithms**  
- PTP/timestamp blocks (orthogonal)  
- Application decode after correct packets arrive  

---

## 8. Quick “gap matrix” against an existing unicast UDP FPGA

| Block in your design | Symptom if unchanged | Fix direction |
|----------------------|----------------------|---------------|
| MAC DA == my MAC only | Zero RX mcast frames at MAC | Mcast table / promiscuous / custom filter |
| IP DA == my IP only | Frames pass MAC, drop in IP | Accept group set / 224/4 |
| No IGMP / no static join | Empty RX on snooping switch | CPU or HW IGMP, or venue static OIF |
| TX uses ARP for all DA | ARP fail / wrong DA | Map group→01:00:5e… |
| Single RX queue | A/B or multi-channel contention | Multi-group demux / RSS / queues |
| Unicast TCP only recovery | OK as secondary path | Keep; do not confuse with mcast RX |

---

## 9. Reference index (URLs)

| Topic | URL |
|-------|-----|
| IPv4 host multicast + Ethernet map + IGMP v1 | https://www.rfc-editor.org/rfc/rfc1112.txt |
| IGMPv2 | https://www.rfc-editor.org/rfc/rfc2236.html |
| IGMPv3 | https://www.rfc-editor.org/rfc/rfc3376 |
| SSM 232/8 | https://www.rfc-editor.org/rfc/rfc4607.html |
| IPv4 mcast allocation incl. 232/8 | https://datatracker.ietf.org/doc/rfc5771/ |
| IPv6 Ethernet mcast MAC | https://datatracker.ietf.org/doc/html/rfc2464 |
| IGMP/MLD snooping | https://www.rfc-editor.org/rfc/rfc4541.html |
| PIM-SM | https://www.rfc-editor.org/rfc/rfc4601.html |
| UDP checksum | https://www.rfc-editor.org/rfc/rfc768.html |
| AMD AXI Ethernet mcast table | https://docs.amd.com/r/en-US/pg138-axi-ethernet/Multicast-Address-Table-Offset-0x0002_0000-0x0003_FFFF |
| AMD TEMAC frame filter | https://docs.amd.com/r/en-US/pg051-tri-mode-eth-mac/Using-the-Frame-Filter |
| Intel TSE mcast hash | https://docs.altera.com/r/docs/683402/25.3/triple-speed-ethernet-ip-user-guide/multicast-address-resolution |
| XXV Ethernet PG210 | https://www.xilinx.com/support/documents/ip_documentation/xxv_ethernet/v4_1/pg210-25g-ethernet.pdf |
| Corundum | https://github.com/corundum/corundum |
| OpenNIC | https://github.com/Xilinx/open-nic |
| verilog-ethernet | https://github.com/alexforencich/verilog-ethernet |
| CAST UDP+IGMPv3 | https://www.cast-inc.com/sites/default/files/pdfs/2025-07/cast_udpip-1g-amd.pdf |
| CME A/B + TCP recovery | https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/457325847/MDP+3.0+-+Recovery+Services+for+UDP |
| LME A/B + retransmit | https://www.lme.com/-/media/Files/Trading/Systems/LMEsource/LMEsource-v4-Developer-Guide-v11.pdf |
| ICE LCN PIM-SM / VLAN | https://www.nyse.com/publicdocs/IGN_Colocation_Mahwah_Technical_Specs.pdf |

---

*Document generated for gap analysis of existing FPGA unicast UDP designs. Claims limited to cited sources; where open NIC docs omit multicast features, absence is stated as “not found in reviewed docs,” not as a proof of impossibility.*
