# FPGA 处理 TCP 黏包、碎包与重传/乱序重组

**完整详尽调研报告（批量收紧修订 · 留证硬规则）**

- **目录：** `fpga-tcp-sticky-frag-retransmit-20260916-1854/`
- **仓：** [Research_everything](https://cursor.com/codebase/melon5253/Research_everything)
- **时间：** Asia/Shanghai 2026-09-16 18:54（收紧修订同目录）
- **留证规则：** 对比表单元格 / 机制断言 / 数字 **必须** 指到 [sources.md](./sources.md) ID + URL 章节，或 [evidence/](./evidence/) 仓内路径；写不出 → **待核实** 或删除
- **Out：** 未核实 ns、RTL top、策略报单；**不把 IP 分片当成 TCP 碎包**

---

## 1. 结论摘要（≤10 行）

1. **默认方案（推断）：** 低延迟 **行情单向 RX** → FPGA **partial TOE RX**（SAR/dedup + HW ACK/SACK）+ **应用 len-prefix 分帧**；**TX 重传不上 FPGA**（依据：S7 FPL'16 §III.E「TX Buffers solely required for retransmission」+ 本报告 §3 单向假设 **待核实** 业务）。
2. **三层禁混称（事实）：** L4 按 **TCP seq** 流重组（S1 RFC9293 §2.2、§3.10）；L7 在有序字节流上切黏包/拼半包（S1 §2.2；S7 §III.D）；重传分 **RX 容忍**（S1 §3.10 dup/trim；S2 SACK）与 **TX 引擎**（S3 RTO；S6 §IV.3 fast retransmit）— **两条路径**（S6/S7 **事实**）。
3. **IP 分片边界（事实）：** IP 用 Identification/Offset/MF（S4 RFC791 §Fragmentation）；**≠** TCP seq（S1 §3.2 明示 IP ID **不可** 用于 dup 检测 — 见 [evidence/05-falsification-boundary.md](./evidence/05-falsification-boundary.md) 边界①）。
4. **承载默认（推断）：** 少连接 + 浅乱序 → **BRAM SAR**（S6 §IV.3 RX SAR；S7 §III.D RX→BRAM）；OOO 超 **OOO window** → **drop**（S5 method 500 **事实**）→ 换 DRAM OOO（S5 外存 RX buffer；S8 Sensors'23 §Introduction BRAM/DDR 分工 **事实**·平台叙述）。
5. **翻车换型：** ① OOO 超 FPGA/OOE window（S5 step 506–510）；② `MAX_MSG` + OOO 占满片上 RAM（S7 每连接 64 KiB RX buffer **事实**·该论文配置；总量 **待核实** 按器件）；③ 必须 FPGA 线速 **TX 重传**（S6 fast retransmit **事实**）→ full TOE 或 Host/NIC；④ IP 分片无 L3 reasm 进 TCP → **禁止**（S4/S1 §3.7）。
6. **证伪（事实）：** 裸 payload 无 seq（方案 B）/ 用 IP ID 判 dup / 把 IP 分片当半包 — 均 **不成立**（[evidence/05](./evidence/05-falsification-boundary.md)）。
7. **cut-through（待核实）：** 仅 **推断** 在 `SEQ==RCV.NXT` 且无 SAR 反压时可减少缓冲；**无** 公开 RTL 标准，**不写 ns**。
8. **无单一行业标准** FPGA 分帧 FSM；选型用 §5 冻结对比表 + §3 假设。

---

## 2. 一页纸速览

### 2.1 默认 + 翻车（结论 = 方案 + 条件）

| | 内容 | 出处 |
|---|------|------|
| **默认** | partial TOE **RX** + BRAM SAR + len-prefix 分帧；TX/本地重传 → Host/NIC | S6 §IV.3；S7 §III.D–E；§3 假设 **推断** |
| **翻车→D′** | OOO 超 window 被 drop（S5）；或 BRAM 不够（S8 VC709 会话数叙述 **事实**·单平台） | S5 method 500；S8 §Introduction |
| **翻车→E** | 必须 FPGA **TX 重传** + 线速 | S6 §IV.3 fast retransmit；S7 §III.E TX buffer |
| **翻车→A** | 多连接深 OOO / 协议在 Host | S15 `tcp_input.c` OOO 对照；S13 |

### 2.2 三层 + IP 边界（每格有出处）

| 层 | 职责 | 键索引 | 出处 |
|----|------|--------|------|
| L3 IP 重组 | datagram 分片拼回 | `(id, offset, src, dst)` | S4 RFC791 Fragmentation；**默认 Out** |
| L4 流重组 | seq 有序、SAR、dup trim | `(conn_id, seq)` | S1 §2.2、§3.10；S6 §IV.3 |
| L7 应用分帧 | 黏包切、半包拼 | `(conn_id)` + 读偏移 | S1 §2.2；S7 §III.D |
| C-RX | dup/ACK/SACK 促对端重发 | `RCV.NXT` | S1 §3.10；S2；S15 L5696–5708 |
| C-TX | RTO、重传队列、快重传 | `SND.UNA/NXT` | S3；S5 TX buffer；S6 §IV.3 |

### 2.3 数据路径（默认）

```
[MAC/IP csum] → [L4 RX: SAR/dedup, ACK+SACK] → [L7 len-prefix FSM] → 解码
TX 数据/本地重传 → Host 或 NIC（默认不上 FPGA）  ← S7 §III.E **推断**默认
```

### 2.4 决策三答

| # | 问题 | 结论 | 出处 |
|---|------|------|------|
| 1 | 重组 vs 分帧？ | L4=seq 字节流；L7=消息界 | S1 §2.2 |
| 2 | 黏包/半包/L4 缺段/IP 分片？ | L7 / L4 SAR / **L3 Out** | S4；S7 §III.D；[evidence/02](./evidence/02-ip-fragmentation-vs-tcp-layer.md) |
| 3 | TX 重传上 FPGA？ | **行情默认不上** | S7 §III.E；§8 |

---

## 3. 输入假设（冻结）

| 参数 | 值 | 等级 | 出处/说明 |
|------|-----|------|-----------|
| MTU / MSS | 1500 / 1460 B | **假设** | 以太网常见值；S1 §3.7 MSS **事实** |
| MAX_MSG | 64 KiB | **待核实** | 按 ITCH/FIX/SBE 协议核对 |
| 业务方向 | 行情 **单向 RX** | **假设** | TX 默认不上 FPGA 之前提 |
| 连接数 | 1–4 | **假设** | — |
| IP 分片进 TCP 模块 | **否** | **Out** | S1 §3.7 PMTUD/DF **事实** |
| 乱序深度上界 | 未测 | **待核实** | 决定 BRAM vs DRAM |
| 绝对延迟 ns | — | **Out** | — |

---

## 4. 范围

**In：** L4/L7 拼拆等缺段、ACK/SACK、应用超时上报。**Out：** 用户态栈重写、策略报单、RTL top、IP 分片≡TCP 半包、未核实 ns、TLS 全文。

---

## 5. 冻结对比维 — 方案总表

表头：**承载 | 重组窗 | 分帧 FSM | 乱序深度 | 重传(RX/TX) | cut-through | TOE耦合 | 出处**

| ID | 方案 | 承载 | 重组窗 | 分帧 FSM | 乱序深度 | 重传 | cut-through | TOE耦合 | 出处 |
|----|------|------|--------|----------|----------|------|-------------|---------|------|
| A | Host 栈 + FPGA 旁路 | Host `sk_rcvbuf` | 内核 OOO 树 | Host 用户态 | 受 `rcvbuf` 约束；可 prune | RX+TX Host | 批处理 | 内核/DPDK | S15 L5605–5734；S13 |
| B | 裸 payload（无 seq） | 无 | 0 | 误用 | **不可用** | 无 | 假 | 无 | S1 §2.2；[evidence/05](./evidence/05-falsification-boundary.md) ② |
| D | **partial TOE RX（默认）** | BRAM SAR + RX buf | 参数化 OOO 窗 | len-prefix | 受 OOO window | RX；HW ACK/SACK | **待核实** | 自研/ partial IP | S1 §3.10；S6 §IV.3 |
| D′ | partial + DRAM OOO | 外存 RX（S5） | 同 D，payload DDR | 同 D | 中–深 **待核实** | RX only | 缓冲 | + DDR ctrl | S5 RX buffer 406；S8 §3.1 |
| E | full TOE | BRAM+DDR | S7：**64 KiB/conn** | FPGA/Host | 深 | RX+TX | 缓冲 | TOE IP | S7 §II.A；S6 §IV.3 |
| F | FPGA RX + Host TX | 混合 | FPGA 浅 SAR | FPGA | 浅 **待核实** | RX FPGA / TX Host | 混合 | 协同 | S7 RX 路径；S3 TX **推断** |
| H | L3 IP reasm + D | +L3 | IP+TCP | 同 D | IP+TCP | 同 D | IP 分片时 **否** | Rare | S4；S1 §3.7 |

**说明：** 表中 **未写数字** 处 = 源文献仅给机制、不给本场景定量 → **待核实**；S8「VC709 ~26 sessions @2MB」仅作 **单平台参考**（S8 §Introduction），**不** 泛化为行业指标。

---

## 6. 三层机制（分章 · 每断言有出处）

### 6.1 层 0：IP 分片 ≠ TCP 碎包 ≠ L7 半包

| 断言 | 等级 | 出处 |
|------|------|------|
| IP 分片字段为 Identification/Offset/MF | **事实** | S4 RFC791 Fragmentation |
| TCP dup 检测靠 seq，**非** IP ID | **事实** | S1 §3.2；[evidence/05](./evidence/05-falsification-boundary.md) ① |
| PMTUD/DF 避免 IP 分片 | **事实** | S1 §3.7 |
| TOE 保序 segment；跨 MTU **应用消息** 由 application 重组 | **事实** | S7 §III.D |

仓内摘录：[evidence/02-ip-fragmentation-vs-tcp-layer.md](./evidence/02-ip-fragmentation-vs-tcp-layer.md)

---

### 6.2 层 A：L4 流重组

| 断言 | 等级 | 出处 |
|------|------|------|
| TCP = reliable in-order **byte-stream** | **事实** | S1 §2.2 |
| dup：`SEG.SEQ+LEN ≤ RCV.NXT` 丢弃；trim 重叠 | **事实** | S1 §3.10；S15 L5696–5731 |
| 乱序：`SEQ > RCV.NXT` 应保留（SHLD-31） | **事实** | S1 §3.10 |
| 硬件：OOO 入 RX Buffer + RX SAR；dup 在 `read by app..received` 间 drop | **事实** | S6 §IV.3 |
| OOO 超窗 drop | **事实** | S5 method 500 step 506–510 |

伪码对齐 S1 §3.10 + S6 §IV.3 — 见 [evidence/01](./evidence/01-rfc9293-tcp-stream-vs-segment.md)、[evidence/03](./evidence/03-fpga-toe-ooo-sar-hardware.md)。

**内存索引（有出处的数字）：**

| 项 | 值 | 出处 |
|----|-----|------|
| 全 TOE 每连接 RX/TX buf | **64 KiB** | S7 §II.A |
| OOO 块指针 | **13 bit ×2** / block | S6 §IV.3 |
| VC709 例：52 Mb BRAM、2 Mb/会话 → **~26 会话** | **事实**·单论文 | S8 §Introduction |

其余 BRAM 容量 **待核实**（按目标 FPGA 数据手册）。

---

### 6.3 层 B：应用消息分帧

| 断言 | 等级 | 出处 |
|------|------|------|
| TCP **不**提供应用记录边界 | **事实** | S1 §2.2；S14 Stevens Vol.1（书籍） |
| 半包：消息跨多 TCP segment → L7 `READ_BODY` 等待 | **事实** | S7 §III.D |
| 黏包：单次 L4 释放含多条消息 → L7 循环 `READ_HDR` | **推断** | 由 S1 字节流 + 分帧 FSM 定义 |
| `MAX_MSG` 非法 → ERROR | **推断** | 工程惯例；阈值 **待核实** |

---

### 6.4 层 C：RX 容忍 vs TX 引擎

| 机制 | 等级 | 出处 |
|------|------|------|
| RX dup trim + ACK/SACK | **事实** | S1 §3.10；S2；S6 §IV.3 |
| TX RTO / 拥塞控制 | **事实** | S3 RFC5681 |
| TX buffer **主要为重传**保留 | **事实** | S7 §III.E |
| Fast retransmit（dup ACK） | **事实** | S6 §IV.3；S3 |
| 行情默认省略 FPGA TX 引擎 | **推断** | S7 §III.E + §3 单向假设 |

---

## 7. 方案 D 五问（默认方案机制行）

| 五问 | 答案 | 出处 |
|------|------|------|
| 黏包怎么切 | 有序流上 emit 后 **READ_HDR** 循环 | **推断**；S1 §2.2 |
| 半包怎么拼 | **READ_BODY** → `app_buf[conn_id]` | S7 §III.D |
| L4 缺段 | SAR `(conn_id,seq)` + drain；SACK hole | S2；S6 §IV.3 |
| 缺口/超时 | L4：SACK；L7：`APP_PARTIAL_TIMEOUT` | S2；**待核实** 超时值 |
| 内存键 | L4 `(conn_id,seq)`；L7 `(conn_id)` | S6 §IV.3 |

---

## 8. 低延迟：TX 重传与翻车

### 8.1 默认取舍

| 决策 | 选择 | 等级 | 出处 |
|------|------|------|------|
| FPGA L4 RX | **是** | **推断** | S6/S7 |
| FPGA L7 分帧 | **是** | **推断** | S7 §III.D |
| **FPGA TX 重传** | **否** | **推断** | S7 §III.E；§3 |
| ACK/SACK | HW 发 | **推断** | S2；partial TOE 常见能力 **待核实** 具体 IP |

### 8.2 翻车条件（仅列有出处或明确待核实）

| 条件 | 换型 | 出处 |
|------|------|------|
| OOO **超 window** 被 drop | D′ 或 A | S5 step 506–510 |
| 片上 RAM 不够（会话×buf） | D′ / DRAM | S8 §Introduction；S7 §II.A 64KiB×N |
| 必须 FPGA **TX 重传** | E 或 NIC | S6 fast retransmit |
| partial 无 SACK 且 hole 持久 | 加 SACK 或 Host | S2 **事实** 机制；组合 **待核实** |
| IP 分片无 L3 | 上游 DF 或 H | S1 §3.7；S4 |

### 8.3 预算（仅符号，系数待核实）

```
OOO_bytes  ≈ ooo_depth × MSS × conn_count     — MSS: S1 §3.7；depth: 待核实
app_bytes  ≈ conn_count × (MAX_MSG + hdr)     — MAX_MSG: 待核实
SAR_meta   ≈ conn_count × ooo_depth × 26 bit  — 26b: S6 §IV.3 **事实**
```

---

## 9. 工作示例（演示层边界，数字为 **假设** MSS=1460）

### 9.1 半包（L4 拼流 + L7 半包）

| 步骤 | L4 | L7 | 出处 |
|------|-----|-----|------|
| Seg1 1460B | 释放有序字节 | READ_HDR→len；READ_BODY 部分 | S1 §2.2；S7 §III.D |
| Seg2 3544B | SEQ 连续 | emit | S6 §IV.3 drain |

### 9.2 dup（RX 容忍，L7 无感）

| 步骤 | L4 | 出处 |
|------|-----|------|
| 重传旧 seq | DROP `TCP_OLD_DATA` | S15 L5696–5708；S1 §3.10 |

### 9.3 证伪：IP 分片当 TCP 半包

见 [evidence/05-falsification-boundary.md](./evidence/05-falsification-boundary.md) ⑤。

---

## 10. 待核实清单

| 项 | 原因 |
|----|------|
| 目标链路 OOO segment 数 | 无现网 trace |
| 行情 MAX_MSG / 是否 SBE 定长 | 协议未绑定 |
| 是否必须 FPGA 报单 TX | 业务 Out 边界 |
| cut-through RTL 条件 | 无公开标准 |
| 商用 partial TOE 是否 HW SACK | S5 类 IP **待核实** |

---

## 11. 出处与证据

- 出处索引：[sources.md](./sources.md)（S1–S15，≥10）
- 原文摘录：[evidence/](./evidence/)（含 [05 证伪/边界](./evidence/05-falsification-boundary.md)）

---

*三层（L4 / L7 / RX·TX）分模块验证；对比表无出处的数字已删除或标待核实。*
