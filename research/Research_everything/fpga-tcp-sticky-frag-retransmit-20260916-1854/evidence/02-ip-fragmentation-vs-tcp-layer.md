# 证据 02：IP 分片 ≠ TCP 碎包 ≠ 应用半包

**抓取时间：** 2026-09-16 18:54  
**来源：** RFC 791 (IP)、RFC 9293 (TCP)、Sidler FPL'16  
**标注：** **事实**（RFC）；**推断**（FPGA 边界建议）

---

## 摘录 A：RFC 791 — IP 分片在 datagram 层

> **Fragmentation** of an internet datagram is necessary when it … exceeds the maximum transmission unit (MTU) …  
> An internet datagram can be marked **"don't fragment."** Any internet datagram so marked is **not to be internet fragmented** under any circumstances.  
> The internet **fragmentation and reassembly** procedure needs to be able … The receiver of the fragments uses the **identification field** … The **fragment offset field** tells the receiver the position of a fragment in the original datagram.

**键字段：** IP Identification、Fragment Offset、More-Fragments flag —— 与 TCP **Sequence Number 完全无关**。

---

## 摘录 B：RFC 9293 — 避免 IP 分片（PMTUD/DF）

> Avoiding sending a TCP segment that would result in an IP datagram larger than the smallest MTU … **Making matters worse, some firewalls or middleboxes may drop fragmented packets** …  
> PMTUD … relies both on **avoiding source fragmentation** and setting the **IPv4 DF (don't fragment) flag** …

**支撑点：** 现代 TCP 栈应通过 PMTUD/PLPMTUD **避免** IP 分片；FPGA 行情路径默认 **DF + 上游重组或不进 FPGA**。

---

## 摘录 C：Sidler FPL'16 — TCP 排序 vs 应用重组

> The TCP/IP stack **enforces the ordering of the segments**, but **reassembly of the segments has to be done by the application itself**. The additional buffer space in the application to accumulate these larger data chunks incurs a minimal resource overhead …

**支撑点（事实·论文）：** 即使 full TOE 输出**有序 segment 流**，跨 MTU 的**应用消息**仍须应用层 buffer —— 即 **应用半包/黏包 FSM**，不是 L4 SAR 的职责。

---

## 三层对照表（本调研冻结）

| 现象 | 协议层 | 索引键 | FPGA 模块 |
|------|--------|--------|-----------|
| IP datagram 被切成多片 | **L3 IP** | `(id, frag_offset, src, dst)` | IP reasm（通常 **Out**） |
| 一条消息跨多个 TCP segment | **L4 TCP** | `(conn_id, seq)` | SAR / reorder |
| 一条 segment 含多条应用消息 | **L7 应用** | `(conn_id)` + 读偏移 | 分帧 FSM |
| 对端重传导致 dup segment | **L4 RX** | `RCV.NXT` | dup trim（**非**黏包） |

**推断（FPGA 默认）：** 行情 RX 路径设 **IPv4 DF=1** 或 MAC 前过滤 IP 分片；若必须收分片，在 **L3 独立模块** 重组后再进 TCP parser —— **禁止** 与应用 `READ_BODY` 混用同一 buffer 逻辑。
