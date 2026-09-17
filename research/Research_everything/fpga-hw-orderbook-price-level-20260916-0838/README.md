# FPGA 硬件订单簿：价格档位管理机制（第二轮详尽调研）

- **Slug:** `fpga-hw-orderbook-price-level-20260916-0838`
- **Date (Asia/Shanghai):** 2026-09-16 08:38
- **Tags:** FPGA, order-book, price-level, level-aggregate, BRAM, URAM, low-latency, HFT
- **Summary:** 档位聚合层更稳妥的默认组合是 **分侧 BRAM/URAM 稠密槽表 + 固定 tick 绝对/滑动窗线性索引 + `{agg_qty, order_cnt, valid}`**；热路径 BBO/Top-N 用 **寄存器投影或增量 tracker**，空档穿越 best 用 **有界线性扫 / valid-bitmask + hybrid 搜 / clipped reduction**；价域稀疏、窗越界或 `tick×range` 超片上容量时改 **价哈希、水平价链、Register Top-K+BRAM 冷存、DRAM 深档+片上两级 CACHE**。
- **Round:** 第二轮完整详尽报告（相对 `…-0834` 一页纸版显著加厚；含文首结论+速览、`onepager.md`、两则工作示例）

## 范围

- **In：** 档位聚合（level aggregate）的物理承载、地址索引、字段集、数据结构、更新路径（新档/删空档/改量）、空档与穿越 best 处理、稀疏度/容量假设、Top-N 与全深度关系（机制层）；上游已解析 `px, qty, side`
- **Out：** 档内 per-order 队列与撮合/撤单状态机（仅说明档位层是否需要 `order_cnt`/`head`）；策略与报单；会话/ITCH 逐字段解码；未核实绝对延迟 ns；完整 RTL 模块划分与 top-core 规格

## 与 `fpga-hw-orderbook-price-level-20260916-0834` 的差异

| 维度 | 0834（一页纸） | 0838（本轮） |
|------|----------------|--------------|
| 篇幅 | 单页摘要 + 一张机制表 | 12 章完整报告 + 多表 + 更新路径伪代码 |
| 物理承载 | 一行概括 | BRAM/URAM/DRAM/HBM/寄存器窗：端口、RMW 流水线、容量估算公式 |
| 索引 | 公式一句 | 六种索引方式：公式、碰撞/越界、rebase、环形窗 mod 语义 |
| 字段 | 字段名列表 | 位宽选项、AOS vs SOA、隐含 px vs 显式 px 决策树 |
| 更新路径 | 未分步 | 新档/改量/删空档逐步状态机 + hazard 说明 |
| 穿越 best | 一句「扫描」 | 增量 tracker / 线性扫 / tree reduction / hybrid 对比与适用条件 |
| 假设 | 表格占位 | **冻结参数表** + 各方案翻车定量条件 |
| 出处 | 8 条链接 | ≥12 条，附事实/推断/待核实标注与抓取备注（见 `sources.md`） |

## Links

- [onepager.md](./onepager.md) — 一页纸速览（独立文件）
- [report.md](./report.md) — 完整详尽正文（文首含 ≤10 行结论 + 速览块）
- [sources.md](./sources.md) — 出处清单与抓取备注
- 上一轮一页纸：[../fpga-hw-orderbook-price-level-20260916-0834/report.md](../fpga-hw-orderbook-price-level-20260916-0834/report.md)
