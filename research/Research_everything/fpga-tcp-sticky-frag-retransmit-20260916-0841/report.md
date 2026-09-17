# FPGA 处理 TCP 黏包、碎包与重传/乱序重组

**完整详尽调研报告（第二轮 · 提示词收紧版）**

- **时区/时间：** Asia/Shanghai 2026-09-16 08:41（修订落盘同目录）
- **证据基调：** RFC 793/9293、RFC 2018、RFC 5681、TOE IP 手册、FPGA 乱序重组论文/专利；**无单一行业标准**——**事实 / 推断 / 待核实** 正文分开标注。
- **铁律：** 下列 **三层机制禁止混称**——L4 流重组、应用消息分帧、重传（RX 容忍 vs TX 引擎）各章独立。

---

## 1. 结论摘要（≤10 行）

1. **三层拆分（禁混称）：** **(A) L4 流重组** = 按 `seq` 缺段缓冲、乱序 SAR、重复/旧段丢弃；**(B) 应用消息分帧** = 在 **有序无重复字节流** 上切黏包/拼半包（长度前缀/分隔符/定长），TCP **不**提供消息边界（RFC 9293 **事实**）；**(C) 重传** = **RX 侧容忍**（dup/trim/ACK+SACK 促对端重发）与 **TX 侧重传引擎**（RTO/重传队列/SACK 引导本地重发）是 **两条路径**，可只实现其一。
2. **In 边界：** 只讨论 **帧/流在 FPGA 内如何拼、拆、等缺段、如何触发重发/上报缺口**；**Out：** 完整 Linux 用户态栈重写、策略报单、完整 RTL top/core、把 **IP 分片** 当成 **TCP/应用碎包**（IP 分片 **Out** 详设）。
3. **冻结假设（§3）：** MTU≈1500、MSS≈1460、**行情单向 RX**、`max_msg_len=64 KiB`（**待核实**按协议）、**不默认 FPGA TX 重传**、MAC+IP/TCP 校验 **已在 MAC/TOE 卸载**（**假设**）。
4. **低延迟交易默认（推断）：** **FPGA = L4 RX 流重组 + 应用分帧**；**TX 重传不上 FPGA**——ACK/SACK 由 partial TOE 硬件发，**数据 TX/重传** 留 Host 内核或独立 NIC，除非报单/会话 **必须** 同 die 闭环（**待核实**业务）。
5. **承载默认：** 单连接、乱序深度 ≤4 segment → **BRAM/URAM** SAR 表 + 小 OOO payload；`outstanding_seg × MSS` 或 `max_msg_len` 超片上预算 → **DRAM** 或 **卸回软核/Host**（**推断**）。
6. **黏包/半包：** 均在 **应用分帧 FSM**（`conn_id` 索引拼装 buf）；**L4 碎包**（segment 跨 beat）由 TOE 写入 `(conn_id, seq)` 槽，与黏包 **不同层**。
7. **缺口：** L4 hole → SAR 等段 + SACK 上报对端；应用半包 hole → 等 L4 有序字节，超时 `PARSER_TIMEOUT` 上报 **会话层**（非 IP 分片超时）。
8. **cut-through：** 仅当 `seg.SEQ==RCV.NXT` 且无 FSM 反压时可 **直通** 到分帧器；乱序/半包必走缓冲（**推断**）。
9. **翻车换 DRAM/软核：** OOO 深度 > SAR 表深度（典型 **>8–16 segment**，**待核实**链路）；`max_msg_len` > 片上 URAM（>256 KiB–1 MiB 量级 **待核实** 器件）；多连接 >16 且需 TX 重传 → full TOE 或 Host（**推断**）。
10. **禁写死未核实 ns**；延迟仅谈 **路径形态**（cut-through vs 缓冲），不标具体纳秒。

---

## 2. 一页纸速览

### 2.1 三层（必须分开）

| 层 | 职责 | 键索引 | 不负责 |
|----|------|--------|--------|
| **L4 流重组** | seq 有序、缺段 SAR、乱序、dup/旧段丢弃 | **`conn_id` + `seq_start`** | 消息边界 |
| **应用消息分帧** | 黏包切、半包拼 | **`conn_id` + 流内读偏移** | seq/重传 |
| **重传 · RX** | 容忍 dup、trim、发 ACK/SACK **促对端重发** | `conn_id` + `RCV.NXT` | 本地 RTO 队列 |
| **重传 · TX** | RTO、重传队列、dup-ACK 快重传 | `conn_id` + `SND.UNA/NXT` | 应用分帧 |

### 2.2 冻结对比维（全文统一）

| 承载 | 重组窗 / outstanding | 分帧 FSM | 乱序深度 | 重传角色 | 延迟路径 | TOE/栈耦合 | 出处 |
|------|---------------------|----------|----------|----------|----------|------------|------|
| 见 §5 总表 | 见 §5 | 见 §5 | 见 §5 | 见 §5 | 见 §5 | 见 §5 | S1–S12 |

### 2.3 低延迟交易默认

```
[MAC 校验卸载] → [L4 RX: seq/SAR/dedup, HW ACK+SACK] → [App: len-prefix FSM] → 行情解码
TX 数据/本地重传：Host 或商用 NIC（默认不上 FPGA）
```

| 条件 | 动作 |
|------|------|
| 单向行情、已握手、乱序浅 | **partial TOE RX + BRAM SAR** |
| 需同机低延迟报单 TX | 评估 **TX 重传上 FPGA** 或 **专用 NIC**（**待核实**） |
| OOO > SAR 深度 或 msg > URAM | **DRAM OOO** 或 **卸回软核** |
| 多连接 + TX 闭环 | **full TOE IP** 或 **Host 栈** |

### 2.4 决策三答（速查）

| # | 问题 | 结论 |
|---|------|------|
| 1 | 重组 vs 分帧分哪层？ | **L4** = 字节流 seq；**应用** = 消息界（TCP 不保证） |
| 2 | 黏包 vs 半包 vs L4 缺段？ | 黏包/半包 = **应用 FSM**；L4 缺段 = **SAR `(conn_id,seq)`** |
| 3 | TX 重传上不上 FPGA？ | **交易行情默认不上**；RX 重组+分帧在 FPGA；翻车见 §8 |

---

## 3. 输入假设（开写前冻结）

缺省按表执行；未冻结标 **待核实** 后再比对方案。

| 参数 | 符号/值 | 状态 | 对比影响 |
|------|---------|------|----------|
| **MTU** | 1500 B（以太网） | **假设** | 每 beat 最大 IP len |
| **MSS** | 1460 B | **假设** | SAR 槽大小、OOO 窗字节 |
| **最大应用消息长** | `MAX_MSG = 64 KiB` | **待核实**（按 ITCH/FIX/SBE） | 分帧 buf、URAM/DRAM |
| **业务方向** | **行情单向 RX** 为主 | **假设** | 默认省略 FPGA TX 重传 |
| **是否主动 TX 重传** | **否**（默认） | **待核实** | 决定是否要 TX 引擎 |
| **连接数** | 1–4 长连接 | **假设** | `conn_id` 表深 |
| **握手** | 已完成，FPGA 见 ESTABLISHED | **假设** | 不展开 SYN 机 |
| **MAC+IP 校验** | **已卸载**（MAC/IP/TCP csum verify） | **假设** | 坏包在 L2–L3 丢弃 |
| **IP 分片** | **不允许进 FPGA**（DF 或上游重组） | **Out 详设** | **≠** TCP 碎包/应用半包 |
| **乱序深度** | ≤4 segment（约 6 KiB） | **待核实** | BRAM vs DRAM |
| **绝对延迟 ns** | — | **Out** | 不写入选型 |

---

## 4. 范围（In / Out）

### 4.1 In — FPGA 内机制

| 主题 | 内容 |
|------|------|
| **拼** | L4 按 seq 合并 segment；应用层按 len 拼半包 body |
| **拆** | 应用层从有序流切多条消息（黏包） |
| **等缺段** | L4 SAR 等 `seq==RCV.NXT`；应用 FSM 等 body 字节 |
| **触发重发** | RX：dup ACK / SACK **上报缺口** 促 **对端** 重传；TX（若实现）：RTO/expired 发本地段 |
| **上报缺口** | SACK block、应用 `partial_msg_timeout` 事件到 Host |

### 4.2 Out

| 排除项 | 说明 |
|--------|------|
| 完整 Linux **用户态**栈重写 | 可用内核/DPDK，不重写教程 |
| 策略报单 / 交易逻辑 | — |
| 完整 RTL top/core 模块划分 | 仅机制级 |
| **IP 分片 ≡ TCP 碎包** | 明确 **禁止** 混称；IP frag **Out** |
| 未核实 ns 延迟 | — |
| 完整 TLS / RFC793 逐条抄录 | — |

---

## 5. 三层机制（分章 · 禁混称）

### 5.1 层 A：L4 流重组（TCP 字节流域）

**定义：** 把 **TCP segment 序列** 变为 **严格递增、无重复、无 gap 的字节流** 交给上层。

**事实（RFC 9293）：** TCP 对上层是 **无记录边界** 的字节流；**segment 边界 ≠ 消息边界**。

#### 5.1.1 状态（per `conn_id`）

| 寄存器 | 含义 |
|--------|------|
| `RCV.NXT` | 下一期望 seq |
| `RCV.WND` | 接收窗 |
| `SACK_BLOCKS[]` | 已收但未连续的 seq 区间（RFC 2018 **事实**） |

#### 5.1.2 缺段 / 乱序 / 重复

```
ON_SEGMENT(conn_id, SEQ, LEN, payload):
  if SEQ+LEN <= RCV.NXT:           → DROP (dup/旧段)           // RX 重传容忍
  elif SEQ < RCV.NXT < SEQ+LEN:    → trim, accept 新后缀
  elif SEQ == RCV.NXT:             → accept; RCV.NXT += LEN; drain SAR 连续块
  elif SEQ > RCV.NXT:              → if in OOO window: SAR[(conn_id,SEQ)]=payload
                                    else: DROP + SACK  // 或告警 **待核实**
  emit cumulative ACK (+ SACK if holes)
```

- **缺段（L4 hole）：** `SEQ > RCV.NXT`，payload 写入 **`mem[conn_id][seq_start]`**（或 ptr 入 DRAM），直至填洞。
- **乱序深度：** 未填洞的最大 `SEQ - RCV.NXT`（字节或 segment 数）；超窗 → 丢段或 **conn_err**（**待核实**策略）。
- **超时：** L4 **不** 为应用消息超时；可选 **persist timer** 仅用于 **是否发零窗探测**（partial TOE 常省略 **推断**）。**促对端重传** 靠 **SACK/重复 ACK**，非本地 RTO。

#### 5.1.3 内存索引与承载

| 承载 | 典型容量 | 索引键 | 适用 |
|------|----------|--------|------|
| **BRAM** | 4–32 KiB OOO | `(conn_id, seq_start) → slot` | 乱序 ≤4 seg **假设** |
| **URAM** | 32–256 KiB | 同上 | 更大窗 **推断** |
| **DRAM** | MB 级 | `(conn_id, seq) → DDR ptr` | OOO 深、多连接 **事实**（S7 论文） |

**与 AXIS：** 输出 **字节流**；`tlast` = segment 末 beat，**≠** 消息末。

---

### 5.2 层 B：应用消息分帧（会话/协议域）

**定义：** 在 **L4 已交付的有序字节流** 上，识别 **应用消息边界**。TCP **不保证** 一条 segment 一条消息（**事实**）。

#### 5.2.1 三种分帧方式（机制对比）

| 方式 | FSM 复杂度 | 黏包怎么切 | 半包怎么拼 | 索引键 |
|------|------------|------------|------------|--------|
| **长度前缀** | 低（2 态+partial） | emit 后 **立即 READ_HDR** 循环 | `body_remain>0` 挂起，累积进 `buf[conn_id]` | `conn_id` + 流内 offset |
| **分隔符** | 中（扫描+转义） | 见 delimiter 切分 | 同上 | `conn_id` |
| **定长** | 最低 | 每 N 字节 emit | 按 N 模余数挂起 | `conn_id` |

**统一 FSM（长度前缀示例）：**

```
READ_HDR: 凑 4B → len; if len>MAX_MSG → ERROR
READ_BODY: copy min(avail, remain); remain==0 → emit, goto READ_HDR  // 黏包
           else wait  // 半包（等 L4 继续供字节）
```

#### 5.2.2 与 L4 的边界

| 现象 | 归属层 |
|------|--------|
| 一条消息跨 2 个 **TCP segment** | L4 透明拼流 → **应用** `READ_BODY` 半包 |
| 一个 segment 内 3 条消息 | L4 一次释放 → **应用** 循环切黏包 |
| 重复 seq 段 | **仅 L4** 丢弃；应用 **不可** 见 |
| **IP 分片** | **Out**；若进 FPGA 需 IP reasm，**≠** 本层半包 |

#### 5.2.3 缺口 / 超时（应用层）

| 事件 | 行为 |
|------|------|
| L4 长期无字节（对端丢包） | FSM 停在 `READ_BODY`；**watchdog** 超时 → `APP_PARTIAL_TIMEOUT(conn_id)` 上报 Host |
| 非法 len | 丢弃连接或 skip **待核实** |
| FIN/RST | 清 `buf[conn_id]`，FSM → IDLE（RFC **事实**） |

**内存：** `app_buf[conn_id]` 大小 ≥ `MAX_MSG + hdr_size + (MSS-1)`（**推断**）。

---

### 5.3 层 C：重传 — RX 容忍 vs TX 引擎（分轨）

**禁止** 将「收到重复段」与「本地发重传段」混为同一状态机。

#### 5.3.1 RX 侧重传 **容忍**（接收路径）

| 机制 | 作用 | FPGA 典型 |
|------|------|-----------|
| 完全 dup | `SEQ+LEN ≤ RCV.NXT` → 丢弃 payload | partial TOE **事实**（S5） |
| 重叠 trim | 取 `RCV.NXT` 之后字节 | 同上 |
| **促对端重发** | **累计 ACK + SACK** 暴露 hole | HW ACK 生成 **推断** |
| dup ACK | 可选，加速对端 fast retransmit | 简化 TOE 可省略 **待核实** |

**不上报应用层**；分帧 FSM 无感知。

#### 5.3.2 TX 侧重传 **引擎**（发送路径）

| 机制 | 作用 | 典型实现位置 |
|------|------|--------------|
| RTO 定时器 | 超时重发 unacked 段 | full TOE / Host **事实**（RFC 5681） |
| 重传队列 | 保存已发未确认段 | TX SRAM/DDRAM |
| SACK 解析（RX 反馈） | 指导 **本地** 重传哪些 seq | full TOE |
| dup-ACK 计数 | fast retransmit | Host 栈或 full TOE |

**低延迟交易默认：** **FPGA 不实现 TX 引擎**；行情 **单向 RX** 足够；若需 **同机报单**，TX 重传放 **Host 或 SmartNIC**（**推断**，**待核实**是否接受 PCIe 往返）。

#### 5.3.3 RX vs TX 对照

| 维度 | RX 容忍 | TX 引擎 |
|------|---------|---------|
| 触发源 | 对端重传 / 网络 dup | 本地 ACK 缺失 / RTO |
| 关键状态 | `RCV.NXT`, SAR | `SND.UNA`, `SND.NXT`, 重传队列 |
| partial TOE | **In** | 通常 **Out** |
| full TOE | **In** | **In**（S5 **事实**） |

---

## 6. 方案分类与冻结对比总表

| ID | 方案 | 承载 | 重组窗/outstanding | 分帧 FSM | 乱序深度 | 重传角色 | 延迟路径 | TOE/栈耦合 | 出处 |
|----|------|------|-------------------|----------|----------|----------|----------|------------|------|
| A | Host 栈 + FPGA 旁路 | Host DRAM | 内核窗 | Host 用户态 | 内核级 | RX+TX 全 Host | 内核批处理 | DPDK/内核 | S11 |
| B | 裸 payload（无 seq） | 无 | 0 | FPGA 误用 | **不可用** | 无 | 假 cut-through | 无 | **推断** |
| D | **partial TOE RX** | BRAM/URAM SAR | 4–16 seg **假设** | FPGA len-prefix | ≤4 seg **假设** | **仅 RX** + HW ACK/SACK | 有序可 cut-through | 商用 partial IP / 自研 | S1,S4,S5 |
| D′ | partial + DRAM OOO | DRAM | 32+ seg | 同上 | 中–深 **待核实** | 仅 RX | 缓冲 | 同上 + DDR ctrl | S7 |
| E | **full TOE** | BRAM+DRAM | 参数化 16–64 KiB **事实** S5 | FPGA/Host | 深 | **RX+TX** | 缓冲为主 | TOExxG 等 | S5,S8 |
| F | FPGA L4 + Host TX | 混合 | FPGA 浅窗 | FPGA | 浅 | RX FPGA / TX Host | 混合 | 协同 | **推断** |
| G | 卸回软核（MicroBlaze/Nios） | DRAM | 软核 tcpip 栈 | 软核或 FPGA | 中 | 可选 TX | 非 cut-through | lwip/自有 | **待核实** |

---

## 7. 各方案机制行（五问必答）

### 7.1 方案 D：partial TOE RX + FPGA 应用分帧（**交易默认**）

| 五问 | 答案 |
|------|------|
| **黏包怎么切** | L4 有序流 → 分帧 FSM `emit` 后 **不消费尽** 底层，**循环 READ_HDR** |
| **半包怎么拼** | `READ_BODY` 写 `app_buf[conn_id]`，`body_remain` 减至 0 emit |
| **L4 碎包/缺段** | SAR：`store(conn_id, SEQ, payload)`；`SEQ==RCV.NXT` 时 **drain** 连续块到分帧器 |
| **缺口/超时** | L4：SACK **上报** hole，**促对端重传**；应用：`APP_PARTIAL_TIMEOUT` 若 L4 长期断流 |
| **内存键** | L4：` (conn_id, seq_start)`；应用：`(conn_id)` + 流内读指针 |

**cut-through（推断）：** 当 `SEQ==RCV.NXT` 且分帧器 `ready`，payload 可 **不落 DRAM** 直写 FSM；乱序必须经 SAR。

### 7.2 方案 D′：partial TOE + DRAM OOO

| 五问 | 答案 |
|------|------|
| 黏包/半包 | 同 D |
| L4 缺段 | DRAM ptr 表，SAR 项在 BRAM **事实**（S7） |
| 缺口/超时 | 同 D；窗满 → **conn_err** 或丢最远段 **待核实** |
| 内存键 | `(conn_id, seq) → DDR_line` |

**适用：** 实测乱序 **>8 segment** 或 co-lo 外跨 WAN（**待核实**）。

### 7.3 方案 E：full TOE

| 五问 | 答案 |
|------|------|
| 黏包/半包 | 同 D（TOE 输出有序流） |
| L4 | 硬件 reorder + dup trim **事实**（S5） |
| TX 重传 | **RTO + 重传队列** 在 FPGA **事实**（S5） |
| 内存键 | RX: `(conn_id,seq)`；TX: `(conn_id, snd_seq)` |

**适用：** 多连接、**必须** FPGA 内 TX 闭环；验证成本高 **推断**。

### 7.4 方案 F：FPGA RX + Host TX 重传

| 五问 | 答案 |
|------|------|
| 黏包/半包 | FPGA 分帧 |
| L4 RX | FPGA SAR |
| TX 重传 | **Host** RTO/SACK 解析 |
| 风险 | PCIe 调度、双路径 `conn_id` 一致 **待核实** |

**适用：** 行情 FPGA 解析 + 报单走内核 **推断**。

### 7.5 方案 A / B / G（简述）

| 方案 | 黏包/半包 | L4 | 缺口 | 键 |
|------|-----------|-----|------|-----|
| A Host | Host recv 循环 | 内核 | 内核 SACK | 内核 sk_buff |
| B 裸 payload | 仅 lab 有序流 | **无** | 无法正确处理 | 无 seq **不可用** |
| G 软核 | 软核 FSM | lwip 栈 | 栈 timeout | 软核堆 |

---

## 8. 低延迟交易：默认取舍与翻车换型

### 8.1 默认取舍（推断）

| 决策 | 默认 | 例外（待核实） |
|------|------|----------------|
| **FPGA 做 L4 RX 重组** | **是** | 极简单 lab 可 Host 旁路 |
| **FPGA 做应用分帧** | **是**（len-prefix/SBE） | 协议已在 Host |
| **FPGA 做 TX 重传** | **否** | 报单必须 bypass 内核且同一 FPGA |
| **承载** | **BRAM SAR**，OOO ≤4 MSS | 见下表 |
| **ACK/SACK** | **HW 发**（partial TOE） | 减轻 Host 中断 |

### 8.2 何时翻车 → DRAM 或软核

| 翻车条件 | 量化直觉 | 换型 |
|----------|----------|------|
| **乱序深度** > SAR 表项（如 >8–16 seg） | 跨域/拥塞路径 **待核实** | **D′ DRAM OOO** 或 **A Host L4** |
| **`MAX_MSG`** > 单连接 URAM（如 >256 KiB–1 MiB） | 巨型 snapshot 消息 **待核实** | **DRAM app_buf** 或 **流式解析**（不定长 buf） |
| **连接数** × OOO 窗 > 片上 RAM | >16 conn **假设** | DRAM 或 **G 软核** / SmartNIC |
| **必须 TX 重传** + 线速 | 报单/session 双向 **待核实** | **E full TOE** 或 **NIC offload**，非 partial |
| **partial 无 SACK** 且 hole 持久 | 对端不 fast recover | 加 SACK 或 **卸回 Host** |
| **IP 分片进 FPGA** | 未做 IP reasm | **上游禁止** 或 **Out** 另做 IP 层 |

### 8.3 cut-through 与延迟路径（不写 ns）

| 路径 | 条件 | 形态 |
|------|------|------|
| **Cut-through** | 有序、FSM ready、无反压 | MAC→parse→TOE pass→分帧 **推断** |
| **Store-forward** | 乱序、SAR 填洞、半包 | 至少 1 segment 或 1 msg 缓冲 |
| **Host 往返** | TX 重传走 PCIe | 延迟路径变长 **推断** |

---

## 9. 工作示例

### 9.1 示例 ①：长度前缀消息跨两个 TCP segment（半包 + L4 拼流）

**冻结：** MSS=1460，`len=5000`，`MAX_MSG=64KiB`，单 `conn_id=0`。

| 步骤 | L4（层 A） | 应用分帧（层 B） |
|------|------------|------------------|
| Seg1 SEQ=1000, 1460B | `RCV.NXT`: 1000→2460，释放 1460B 有序流 | READ_HDR→len=5000；READ_BODY +1456B，`remain=3544` **半包** |
| Seg2 SEQ=2460, 3544B | `SEQ==RCV.NXT`，释放 3544B | +3544B，`remain=0` → **emit**；若还有字节则 **切黏包** READ_HDR |

**层 C：** 无重传；纯碎包/半包，**RX 容忍** 未触发。

### 9.2 示例 ②：对端重传导致 dup（RX 容忍，应用无感）

| 步骤 | L4（层 A） | 应用（层 B） | 重传（层 C） |
|------|------------|--------------|--------------|
| 已收 [5000,6000) | `RCV.NXT=6000` | 正常解析 | — |
| 对端重传 SEQ=5000 LEN=1000 | `5000+1000≤6000` **DROP** | **无字节输入** | **RX 容忍**；可选 dup ACK **促对端** 停止 |
| 重叠重传 SEQ=5500 LEN=800 | trim，若全新无则 drop | 无感 | 同左 |

**要点：** dup 处理 **只在 L4**；**不是** 应用黏包/半包问题。

### 9.3 示例 ③：乱序 + L4 缺段（SACK 上报）

| 步骤 | L4 | 应用 |
|------|-----|------|
| 收 SEQ=1000 LEN=1000 | `RCV.NXT=2000` | 收到 1000B |
| 收 SEQ=3000 LEN=1000（跳 2000） | SAR[(0,3000)]=1000B；**SACK 2000–3000 hole** | FSM 可解析已交付部分；若半包则 **等** |
| 收 SEQ=2000 LEN=1000 | 填洞，`RCV.NXT`→4000，drain 3000 块 | 继续收字节 |

**层 C RX：** SACK **上报缺口** → 对端重传（非 FPGA TX RTO）。

---

## 10. 风险与待核实

| 项 | 说明 |
|----|------|
| 目标链路乱序 segment 数 | 决定 BRAM vs DRAM **待核实** |
| 行情协议 `MAX_MSG` / 是否 SBE 定长 | 决定 FSM 类型 **待核实** |
| 是否 **必须** FPGA 内报单 TX | 决定 TX 引擎 **待核实** |
| 现成 MAC/IP csum 核是否已集成 | 影响 parse 路径 **待核实** |
| 商用 TOE 授权与 AXI 接口 | S5/S9 **待核实** |
| co-lo vs 跨 WAN | 乱序深度差异 **待核实** |

---

## 11. 开放选项（非唯一架构）

1. **SBE 定长 + 组固定**：分帧 FSM 最简；版本升级需改表 **推断**。
2. **流式 JSON/文本 delimiter**：FSM 复杂，交易少用 **推断**。
3. **FPGA 只做到 L4，分帧在 Host**：PCIe 带宽够时可选 **推断**。
4. **RX cut-through + 侧路 SAR 备份**：极低延迟实验 **待核实**。
5. **应用层 seq（业务 dedup）**：**不能** 替代 TCP seq **推断**。

---

## 12. 出处列表（≥10）

| ID | 来源 | 类型 | 用于 |
|----|------|------|------|
| S1 | RFC 9293 / RFC 793 (TCP) | **事实** | 字节流、seq、dup |
| S2 | RFC 2018 (SACK) | **事实** | 缺口上报 |
| S3 | RFC 5681 | **事实** | TX RTO/fast retransmit 背景 |
| S4 | TOE OOO patent (TREA Fig.5) | **事实** | SAR、OOO 窗 |
| S5 | TOExxG-IP Brief (DG Way) | **事实** | reorder、dup trim、TX RX |
| S6 | IEEE ISCIT 2011 FPGA TCP reorder | **事实** | 多连接 reorder |
| S7 | PMC9865474 FPGA reorder | **事实** | DRAM ptr、SAR |
| S8 | Hoskote JSSC 2003 TOE | **事实** | 商用 TOE 架构 |
| S9 | AMD/Xilinx Ethernet docs | **待核实** | MAC csum 卸载 |
| S10 | Intel LLE guides | **待核实** | 集成边界 |
| S11 | Linux networking docs | **事实** | Host 对照 |
| S12 | Stevens TCP/IP Illustrated Vol.1 | **事实** | 分层概念 |

URL 与抓取备注见 [sources.md](./sources.md)。

---

*报告结束。三层（L4 流重组 / 应用分帧 / RX·TX 重传）须分模块设计与验证；IP 分片不得与 TCP/应用半包混称。*
