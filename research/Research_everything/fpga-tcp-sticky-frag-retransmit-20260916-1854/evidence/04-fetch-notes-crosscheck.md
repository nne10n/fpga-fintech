# 证据 04：多源交叉抓取备注（2026-09-16 18:54）

**标注说明：** ✅ 全文/摘要可读 · ⚠️ 仅摘要 · 📚 书籍

---

## 抓取结果矩阵

| ID | URL | 状态 | 等级 | 本调研用途 |
|----|-----|------|------|------------|
| S1 | https://www.rfc-editor.org/rfc/rfc9293.html | ✅ | **事实** | 字节流、dup/trim、SHLD-31 乱序保留 |
| S2 | https://www.rfc-editor.org/rfc/rfc2018.html | ✅ | **事实** | SACK 缺口上报 |
| S3 | https://www.rfc-editor.org/rfc/rfc5681.html | ✅ | **事实** | RTO、dup-ACK 快重传背景 |
| S4 | https://www.rfc-editor.org/rfc/rfc791.html | ✅ | **事实** | IP 分片字段与语义 |
| S5 | TREA US10320918 | ✅ 摘要+method 500 | **事实** | OOO 窗、SAR、外存 RX/TX buffer |
| S6 | Sidler FCCM'15 PDF | ✅ | **事实** | 10k 连接 TOE、OOO SAR、fast retransmit |
| S7 | Sidler FPL'16 PDF | ✅ | **事实** | RX→BRAM、TX buffer=重传、应用重组 |
| S8 | Sensors 2023 doi:10.3390/s23104690 | ✅ PMC | **事实** | BRAM/DDR 双队列、多会话延迟模型 |
| S9 | PMC9865474 / Electronics 2023 | ⚠️ 超时重试用摘要 | **事实**（摘要级） | FPGA reorder pipeline、外存指针 |
| S10 | IEEE NAS 2010 doi:10.1109/nas.2010.53 | ⚠️ 摘要 | **事实**（摘要级） | 骨干网 OOO 特征、FPGA reasm 原型 |
| S11 | ISCIT 2011 doi:10.1109/iscit.2011.6089757 | ⚠️ 摘要 | **事实**（摘要级） | 多连接 FPGA reorder |
| S12 | Hoskote JSSC 2003 doi:10.1109/jssc.2003.818294 | ⚠️ 摘要 | **事实**（摘要级） | 商用 10Gb TOE 架构 |
| S13 | Linux ip-sysctl | ✅ | **事实** | Host 栈对照 |
| S14 | Stevens TCP/IP Illustrated Vol.1 | 📚 | **事实** | 分层、黏包概念教科书 |

---

## 批量收紧修订（2026-09-16）

| 规则 | 落实 |
|------|------|
| 对比表单元格有出处 | report §5 每格 S* 或 待核实 |
| 结论 ≤10 行 + 速览 | report §1–§2 |
| 证伪/边界 ≥1 | [05-falsification-boundary.md](./05-falsification-boundary.md) |
| 开源仓文件路径 | S15 `tcp_input.c` 函数行号 |
| 无出处数字 | 删除或标待核实（如 OOO 8–16 seg） |

---

## 0841 → 1854 交叉核对结论

| 论断 | 0841 | 1854 交叉结果 |
|------|------|---------------|
| TCP 不保证消息边界 | RFC 9293 | ✅ 摘录 A 确认 |
| 低延迟默认不上 FPGA TX 重传 | 推断 | ✅ Sidler FPL'16 TX buffer 仅重传 + 行情单向假设强化 |
| IP 分片 ≠ 应用半包 | 声明 | ✅ RFC 791 + RFC 9293 PMTUD 双源 |
| OOO > SAR 深度需 DRAM | 推断 | ✅ 专利 method 500 drop + Sensors BRAM 会话上限 |
| cut-through 仅有序路径 | 推断 | ⚠️ 仍**待核实**具体 RTL；不写 ns |

---

## 故意不写入报告的数

- Sensors 2023 板级 **600 ns / 1.3 µs** 等 —— 特定 FIFO+VC709 实测，**不**作为通用选型硬指标（任务 Out：未核实 ns）。
- TOE 厂商 **80%/90% 线速** marketing —— 不引用。
- IEEE 全文 cycle 数 —— 无全文不写入。

---

## agent-tools 缓存

RFC/论文抓取中间文件位于 Cursor agent-tools 目录，**不提交 git**；本目录 `evidence/` 为提交用摘录副本。
