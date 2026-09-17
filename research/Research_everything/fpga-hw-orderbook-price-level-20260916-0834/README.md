# FPGA 硬件订单簿：价格档位管理机制

- **Slug:** `fpga-hw-orderbook-price-level-20260916-0834`
- **Date (Asia/Shanghai):** 2026-09-16 08:34
- **Tags:** FPGA, order-book, price-level, level-aggregate, BRAM, low-latency
- **Summary:** 本题仅 **档位聚合层**（非档内订单链）。更稳妥默认：**BRAM/URAM + 固定 tick 绝对/滑动窗索引 + `{agg_qty, order_cnt, valid}`**；价稀疏、窗口越界或 tick×价域超片上容量时改 **价哈希/valid-bitmap/水平价链/寄存器 Top-K 投影**。
- **Note:** 本目录 `report.md` 为任务指定的一页纸交付；仓库默认现为完整详细报告（见根 [README.md](../README.md)）。

## 范围

- **In：** 档位聚合的物理承载、地址索引、字段集、稀疏度假设、新档/删空档/改量代价；Top-N 与全深度关系（机制层）；上游已解析 `px, qty, side`
- **Out：** 档内 per-order 队列与撮合/撤单状态机（仅说明档位层是否需要 `order_cnt`）；策略与报单；会话/ITCH 逐字段解码；未核实 ns；完整 RTL 模块划分与 top-core 规格

## Links

- [report.md](./report.md)
