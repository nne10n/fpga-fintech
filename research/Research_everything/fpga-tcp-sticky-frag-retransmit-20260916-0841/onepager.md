# 一页纸速览：FPGA TCP 黏包 / 半包 / 重传

**Asia/Shanghai 2026-09-16 08:41（收紧版）** · [report.md](./report.md)

---

## 一句话

**三层禁混称：** L4 按 seq 流重组 → 应用层切黏包/拼半包 → 重传分 **RX 容忍** 与 **TX 引擎**。低延迟交易默认：**FPGA = RX 重组 + 分帧；TX 重传不上 FPGA**。

---

## 三层（必须分开）

| 层 | 做什么 | 键 | 不做什么 |
|----|--------|-----|----------|
| **A · L4 流重组** | 缺段 SAR、乱序、dup/旧段丢 | `(conn_id, seq)` | 消息边界 |
| **B · 应用分帧** | 黏包切、半包拼 | `(conn_id)` + 读偏移 | seq/重传 |
| **C-RX** | dup trim、ACK/SACK **促对端重发** | `RCV.NXT` | 本地 RTO |
| **C-TX** | RTO、重传队列 | `SND.UNA/NXT` | 分帧 |

**TCP 不保证消息边界（事实）。IP 分片 ≠ TCP/应用半包（Out）。**

---

## 冻结假设

| 项 | 默认 |
|----|------|
| MTU/MSS | 1500 / 1460（假设） |
| 方向 | 行情 **单向 RX** |
| MAX_MSG | 64 KiB（**待核实**） |
| TX 重传 | **默认不上 FPGA** |
| 校验 | MAC+IP 已卸载（假设） |
| ns 延迟 | **不写** |

---

## 冻结对比维（选型表头）

承载 | 重组窗/outstanding | 分帧 FSM | 乱序深度 | 重传(RX/TX) | cut-through? | TOE/栈耦合 | 出处

---

## 交易默认

```
MAC csum → [L4 RX: SAR/dedup, HW ACK+SACK] → [App: len-prefix FSM] → 解码
TX/本地重传 → Host 或 NIC（默认）
```

| 翻车 | 换型 |
|------|------|
| OOO > 8–16 seg（**待核实**） | DRAM SAR 或 Host L4 |
| MAX_MSG > URAM | DRAM buf 或流式解析 |
| 必须线速 TX 重传 | full TOE / SmartNIC |

---

## 五问（每方案必答）

黏包怎么切 · 半包怎么拼 · L4 缺段怎么办 · 超时/上报 · 内存键 `(conn_id,seq)`

---

## 两例

① **半包：** L4 拼两 segment → FSM `READ_BODY` 凑满 emit。  
② **dup：** L4 `SEQ+LEN≤RCV.NXT` 丢弃 → 应用无感（**非**黏包问题）。

---

## 出处

RFC 9293/793 · 2018 SACK · TOE OOO 专利 · TOExxG · FPGA reorder — [sources.md](./sources.md)（≥12）
