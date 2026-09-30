# 出处清单（留证硬规则版）

**调研目录：** `fpga-tcp-sticky-frag-retransmit-20260916-1854/`  
**仓：** [Research_everything](https://cursor.com/codebase/melon5253/Research_everything)  
**修订：** 批量收紧 — 每条含 **可点击 URL + 章节/文件路径**；对比表单元格只引用下表 ID

**证据摘录目录：** [evidence/](./evidence/)

---

## 主出处（≥10）

| ID | URL / 路径 | 章节 / 文件定位 | 抓取 | 等级 | 支撑点 |
|----|------------|-----------------|------|------|--------|
| S1 | https://www.rfc-editor.org/rfc/rfc9293.html | §2.2 字节流；§3.2 IP ID；§3.7 MSS/PMTUD；§3.10 段处理/dup/SHLD-31 | ✅ | **事实** | L4 语义、dup、乱序 |
| S2 | https://www.rfc-editor.org/rfc/rfc2018.html | §3–4 SACK option | ✅ | **事实** | 缺口上报 |
| S3 | https://www.rfc-editor.org/rfc/rfc5681.html | §3–4 RTO、dup-ACK 快重传 | ✅ | **事实** | TX 重传背景 |
| S4 | https://www.rfc-editor.org/rfc/rfc791.html | §Fragmentation / Identification / Offset | ✅ | **事实** | IP 分片 **≠** TCP seq |
| S5 | https://trea.com/information/.../571f29aa-74dc-434c-91c0-55f568fe3e53 | Fig.5 **method 500** step 502–520；RX/TX buffer 406/408 | ✅ | **事实** | OOO 窗 drop、外存 SAR |
| S6 | https://davidsidler.ch/files/fccm2015-tcpip.pdf | **§IV.3** OOO Packet Processing；§IV.3 fast retransmit | ✅ PDF | **事实** | FPGA SAR、dup drop、TX 快重传 |
| S7 | https://davidsidler.ch/files/fpl16-lowlatencytcpip.pdf | **§II.A** 64KB/conn；**§III.D** 应用重组；**§III.E** TX buffer=重传 | ✅ PDF | **事实** | RX→BRAM、TX 角色 |
| S8 | https://doi.org/10.3390/s23104690 | **§Introduction** BRAM/DDR、VC709 会话估算 | ✅ PMC | **事实**·单平台 | 承载分工 |
| S9 | https://pmc.ncbi.nlm.nih.gov/articles/PMC9865474/ | 摘要：FPGA reorder、外存指针 | ⚠️ | **事实**（摘要） | DRAM OOO 对照 |
| S10 | https://doi.org/10.1109/nas.2010.53 | 摘要：骨干 OOO、FPGA reasm | ⚠️ | **事实**（摘要） | 乱序存在性 |
| S11 | https://doi.org/10.1109/iscit.2011.6089757 | 摘要：多连接 FPGA reorder | ⚠️ | **事实**（摘要） | 多连接 SAR |
| S12 | https://doi.org/10.1109/jssc.2003.818294 | 摘要：10Gb TOE | ⚠️ | **事实**（摘要） | full TOE 架构 |
| S13 | https://docs.kernel.org/networking/ip-sysctl.html | TCP/ip sysctl 索引 | ✅ | **事实** | Host 对照入口 |
| S14 | Stevens, *TCP/IP Illustrated Vol.1* | Ch.17 TCP；字节流/黏包概念 | 📚 | **事实** | 教科书分层 |
| S15 | https://github.com/torvalds/linux/blob/master/net/ipv4/tcp_input.c | **`tcp_data_queue` L5605–5734**；**`tcp_ofo_queue` L5304–5349**；**`tcp_prune_ofo_queue` L5937+** | ✅ raw | **事实** | Host RX dup/OOO/prune 对照 |

---

## 仓内证据路径（report 可引用）

| 路径 | 内容 |
|------|------|
| [evidence/01-rfc9293-tcp-stream-vs-segment.md](./evidence/01-rfc9293-tcp-stream-vs-segment.md) | S1 摘录 A–D |
| [evidence/02-ip-fragmentation-vs-tcp-layer.md](./evidence/02-ip-fragmentation-vs-tcp-layer.md) | S4+S7 IP/TCP/L7 边界 |
| [evidence/03-fpga-toe-ooo-sar-hardware.md](./evidence/03-fpga-toe-ooo-sar-hardware.md) | S5/S6/S7/S8 硬件摘录 |
| [evidence/04-fetch-notes-crosscheck.md](./evidence/04-fetch-notes-crosscheck.md) | 多源交叉矩阵 |
| [evidence/05-falsification-boundary.md](./evidence/05-falsification-boundary.md) | **证伪/边界 ≥1**（IP ID、裸 payload、OOO 窗、Host prune） |

---

## 抓取限制

1. IEEE S10–S12、S9 全文不可得处 **不** 写 cycle/深度数字。
2. S8 板级延迟（600 ns 等）**不** 进入 report 选型结论。
3. 无出处数字已从 report 删除或标 **待核实**。

---

## 开源仓阅读记录（S15）

| 文件 | 接口/函数 | 用途 |
|------|-----------|------|
| `net/ipv4/tcp_input.c` | `tcp_data_queue()` | 有序/ dup / 转 OOO |
| 同上 | `tcp_data_queue_ofo()` | OOO 入 RB 树 |
| 同上 | `tcp_ofo_queue()` | 填洞 drain |
| 同上 | `tcp_prune_ofo_queue()` | recv 压力 prune — **边界证伪** |

分支：查阅时 `master`（2026-09-16 抓取）；行号随内核版本漂移，以 GitHub permalink 为准。
