# 证据 03：FPGA TOE 乱序 SAR 与 TX 重传硬件实现

**抓取时间：** 2026-09-16 18:54  
**来源：** Sidler FCCM'15、Sidler FPL'16、TREA 专利 US10320918、Sensors 2023  
**标注：** **事实**（论文/专利原文）

---

## 摘录 A：Sidler FCCM'15 — OOO 处理与 dup 丢弃

> **Out-of-Order (OOO) Packet Processing:** … The RX Engine expects the SEQ number of each packet it receives to be the same as **received**. If this is not the case, the packet is considered to be out-of-order and the following steps are executed:  
> 1) If the SEQ number is **between read by app and received**, then the packet is **dropped** as it has already been received.  
> 2) Otherwise, the OOO segment is accepted. The payload is written directly into the **RX Buffer** and the two pointers to the block are written to the **RX SAR table**.  
> 3) If OOO segments overlap or are adjacent … the pointers are updated accordingly.

**支撑点：** 硬件 OOO = `(conn_id, seq)` SAR 表 + RX Buffer；dup 在 L4 丢弃，应用无感。

---

## 摘录 B：Sidler FCCM'15 — Fast Retransmit（TX 引擎）

> … we also support **Fast retransmit** as proposed in RFC2581 which triggers a retransmit on **duplicate acknowledgments** …

**支撑点：** **full TOE** 在 FPGA 内实现 TX 快重传；与 partial RX-only 形成对照。

---

## 摘录 C：Sidler FPL'16 — RX 移入 BRAM、TX 缓冲仅为重传

> Since for the optimized stack Nagle's algorithm was removed, there is **no requirement to buffer on the TX path** … The **TX Buffers are solely required for retransmission** of data in case of a failure.  
> … **more BRAMs are required, since the RX buffer was moved from DDR into BRAM**. This also cuts the fix allocated memory in the DDR in half.

**支撑点：** 低延迟优化 = **RX 片上** + **TX DDR 仅服务重传**；若业务**不需要 FPGA 发数据**，TX buffer/RTO 整块可省略。

---

## 摘录 D：TREA 专利 method 500 — OOO 窗与 drop

> At step 504, the TCP receive engine checks the sequence number … If the sequence number is **in the past** … the method proceeds to step 510 … **the TCP segment is dropped**.  
> … At step 506 … checks the TCP segment against the **current OOO window**. If the TCP segment **falls outside of the window**, … **dropped**. If … **within the OOO window** … stored … **merged** if overlapping.

**支撑点：** 商用 TOE IP 的 OOO 窗满 → drop；对应本报告「乱序深度翻车」条件。

---

## 摘录 E：Sensors 2023 — BRAM vs DDR3 与多会话

> … in the case of a **small number of TCP sessions**, an on-chip **BRAM** storage structure is generally used … in the case of a **large number of TCP sessions**, an external **DDR3** storage structure is used …  
> … limited on-chip resources can only support a maximum of **26 sessions** (assuming 2 Mb per session on VC709).

**支撑点（事实·论文，特定平台假设）：** 承载选型 = f(会话数 × 每连接 buffer)；**推断** 行情 1–4 连接可 BRAM SAR。

---

## 摘录 F：Sidler FPL'16 资源表 — TX 重传占 DDR 带宽

| 版本 | Mem alloc | Mem bw |
|------|-----------|--------|
| TCP/IP org. | 1300 MB | **40 Gbps** |
| TCP/IP opt. | 650 MB | **10 Gbps** |

**推断：** full TOE（RX+TX 重传）在 FPGA 上与应用争用 DDR；低延迟 **行情 RX-only** 默认不上 TX 引擎，部分出于 **资源/带宽** 而非仅「不需要发单」。
