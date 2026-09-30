# 证据 05：证伪 / 边界用例（强制 ≥1）

**抓取时间：** 2026-09-16（批量收紧修订）  
**用途：** 否定常见误设，划定 FPGA 实现边界

---

## 边界 ①：IPv4 Identification **不能**用于 TCP dup 检测

**等级：** **事实**

**出处：** [RFC 9293 §3.2](https://www.rfc-editor.org/rfc/rfc9293.html#section-3.2)（仓内摘录 [01-rfc9293-tcp-stream-vs-segment.md](./01-rfc9293-tcp-stream-vs-segment.md) 可补 D 段）

> The same IP Identification field may be reused anyways since it is only meaningful when a datagram is **fragmented** … TCP implementations should not rely on … this IPv4 header field … It is **not a reasonable way** to indicate duplicate sent segments nor to **identify duplicate received segments**.

**证伪：** 在 FPGA RX 用 IP ID 判 TCP 重传/黏包 → **错误**；必须用 **TCP seq**（S1 §3.10）。

---

## 边界 ②：无 seq 的「裸 payload」路径不可用

**等级：** **推断**（由 S1 字节流语义 + S6 OOO 步骤推导）

**出处：** S1 [RFC 9293 §2.2](https://www.rfc-editor.org/rfc/rfc9293.html#section-2.2) 要求 seq 保序；S6 [FCCM'15 PDF §IV.3](https://davidsidler.ch/files/fccm2015-tcpip.pdf) OOO 逐步依赖 SEQ vs `received`。

**证伪：** 实验室「MAC 后直送分帧 FSM、不做 L4」在 dup/乱序/重传下 **无法** 对齐 RFC 语义 → 报告方案 **B = 不可用**。

---

## 边界 ③：OOO 窗外 segment 被 drop（非无限 SAR）

**等级：** **事实**

**出处：** S5 [TREA 专利 method 500 step 506–510](https://trea.com/information/data-flow-architecture-for-a-tcp-offload-engine/patentgrant/571f29aa-74dc-434c-91c0-55f568fe3e53)（仓内 [03-fpga-toe-ooo-sar-hardware.md](./03-fpga-toe-ooo-sar-hardware.md) 摘录 E）

> If the TCP segment **falls outside of the window** … the TCP segment is **dropped**.

**边界：** 乱序深度受 **OOO window 参数** 硬限制；超窗不是「慢慢缓冲」而是 **丢段** → 须 SACK/对端重传或换 DRAM/Host（翻车条件）。

---

## 边界 ④：Host 栈在 recv 窗满时 prune OOO（对照）

**等级：** **事实**（开源仓已读文件）

**出处：** Linux `net/ipv4/tcp_input.c`（[torvalds/linux@master](https://github.com/torvalds/linux/blob/master/net/ipv4/tcp_input.c)）

| 函数 | 行号（约） | 行为 |
|------|------------|------|
| `tcp_data_queue` | L5696–L5708 | `!after(end_seq, rcv_nxt)` → `SKB_DROP_REASON_TCP_OLD_DATA` |
| `tcp_data_queue` | L5630–L5633 | 有序 → `receive_queue`；否则 → `tcp_data_queue_ofo` |
| `tcp_prune_ofo_queue` | L5937+ | recv 内存压力时 **prune** OOO 队列 |

**边界：** 即使 Host 栈也 **不** 无限缓冲乱序；FPGA BRAM SAR 深度有限是 **同类约束**，非 FPGA 特有缺陷。

---

## 边界 ⑤：把 IP 分片当 TCP/应用半包

**等级：** **事实** + **推断**

**出处：** S4 [RFC 791 Fragmentation](https://www.rfc-editor.org/rfc/rfc791.html) 用 Identification/Offset；S7 [FPL'16 §III.D](https://davidsidler.ch/files/fpl16-lowlatencytcpip.pdf) 应用重组跨 segment 消息。

**证伪：** 在 `READ_BODY` 用 IP frag offset 拼 body → **层错误**；应先 L3 reasm（Rare）或上游 DF（S1 §3.7 PMTUD **事实**）。
