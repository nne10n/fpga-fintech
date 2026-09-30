# 证据 01：RFC 9293 — TCP 字节流 vs Segment 边界

**抓取时间：** 2026-09-16 18:54 (Asia/Shanghai)  
**来源：** https://www.rfc-editor.org/rfc/rfc9293.html  
**标注：** **事实**

---

## 摘录 A：TCP 对上层是可靠有序字节流

> TCP provides a **reliable, in-order, byte-stream service** to applications.  
> The application byte-stream is conveyed over the network via **TCP segments**, with each TCP segment sent as an Internet Protocol (IP) datagram.  
> TCP reliability consists of detecting packet losses (via sequence numbers) and errors (via per-segment checksums), as well as correction via **retransmission**.

**支撑点：** 应用层看到的是**字节流**，不是消息记录；segment 是传输单元，**≠ 应用消息边界**。黏包/半包属于应用分帧层，不是 TCP 层概念。

---

## 摘录 B：Segment 处理 — 去重、trim、乱序保留

> Segments are processed in sequence. **Initial tests on arrival are used to discard old duplicates**, but further processing is done in SEG.SEQ order. If a segment's contents straddle the boundary between old and new, **only the new parts are processed**.  
> … One could tailor actual segments to fit this assumption by **trimming off any portions that lie outside the window** … and only processing further if the segment then begins at RCV.NXT. **Segments with higher beginning sequence numbers SHOULD be held for later processing** (SHLD-31).

**支撑点：** L4 RX 必须实现 dup 丢弃、重叠 trim、乱序 SAR 保留——对应 FPGA partial TOE 的 RX 引擎，**与 TX 重传队列无关**。

---

## 摘录 C：TCB 含 retransmission queue（TX 侧）

> Among the variables stored in the TCB are … pointers to the **retransmit queue** and to the current segment.

**支撑点：** RFC 明确区分 RX 重组状态（RCV.NXT）与 TX 重传队列（retransmit queue）；FPGA 可只实现前者（partial TOE RX）。

---

## 摘录 D：MSS 受 IP reassembly limit 约束（IP/TCP 边界）

> Maximum Segment Size Option … This value is **limited by the IP reassembly limit**.

**支撑点：** IP 层重组能力与 TCP MSS 选型相关，但 **IP 分片重组发生在 L3**，与 TCP seq 重组、应用分帧是不同机制。

---

## 摘录 E：IPv4 Identification 不可用于 TCP dup 检测（证伪用）

> The same IP Identification field may be reused anyways since it is only meaningful when a datagram is **fragmented** … TCP implementations should not rely on … this IPv4 header field … It is **not a reasonable way** … to **identify duplicate received segments**.

**出处定位：** RFC 9293 **§3.2**（Header Format 段内）  
**仓内交叉：** [05-falsification-boundary.md](./05-falsification-boundary.md) 边界①
