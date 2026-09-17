# FPGA 硬件订单簿：价格档位管理机制

- **Slug:** `fpga-hw-orderbook-price-level-20260916-1854`
- **Date (Asia/Shanghai):** 2026-09-16 18:54（收紧修订同目录）
- **仓:** Research_everything
- **Tags:** FPGA, order-book, price-level, level-aggregate, evidence-graded

## 留证硬规则（5 题共用）

1. 对比表单元格 / 机制断言 / 数字 → 须指 `sources.md` 的 **URL + 章节/文件路径**；否则 **待核实** 或删。
2. 文首 **结论≤10 行** + [`onepager.md`](onepager.md) 速览。
3. 证据分级：**事实 / 推断 / 待核实**；开源仓写明已读文件（见 `sources.md` §开源仓已读）。
4. **Out：** 未核实 ns、RTL top、策略报单。
5. 结论 = **默认方案 + 翻车条件**；收紧轮次 **加厚证据、不改口径**。

## 交付物

| 文件 | 说明 |
|------|------|
| [report.md](./report.md) | 完整正文 |
| [onepager.md](./onepager.md) | 一页纸速览 |
| [sources.md](./sources.md) | S1–S14（≥10 URL），含 **S14 证伪/边界** |
| [evidence/](./evidence/) | E01 摘录 / E02 六维对照 / E03 抓取日志 |

## 默认结论（推断，口径未改）

分侧 **BRAM/URAM 稠密槽** + 线性 tick 索引 + `{agg_qty, order_cnt, valid}` + 寄存器 tracker（S1）；翻车见 `onepager.md` §翻车。

## Links

- 上一轮：[../fpga-hw-orderbook-price-level-20260916-0838/report.md](../fpga-hw-orderbook-price-level-20260916-0838/report.md)
