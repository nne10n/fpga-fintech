# FPGA / 存储子系统：Bitmap 维护 DDR 有效条目 × AXI 吞吐优化

- **Slug:** `fpga-bitmap-ddr-axi-throughput-20260916-0848`
- **Date (Asia/Shanghai):** 2026-09-16 08:48
- **Tags:** FPGA, DDR, AXI4, bitmap, valid-bit, dual-path, burst, outstanding, popcount, slot-table
- **Summary:** 先拆 **路径 α（bitmap 扫描/置清）** 与 **路径 β（payload 读/写）** 再谈吞吐；**禁止** 默认双路径均在 DDR 裸扫。**低 ρ（≤0.15）**：片上 bitmap + summary + 单 index AR、不 merge；**高 ρ（≥0.4）**：片上 bitmap + SOA run-merge burst（L_min=4）。机制行强制回答 **地址映射 / INCR 条件 / 空洞阈值 / 屏障**。

## 范围

- **In：** 用 bitmap 维护「DDR 中哪些槽有效」时的 **访存组织与吞吐手段**（路径 α/β、八维对比、AXI 聚合、一致性）
- **Out：** 完整业务语义（订单簿/会话）、完整 RTL top/core、离散 DDR 加速泛化综述（交叉引用 [fpga-hw-orderbook-price-level-20260916-0838](../fpga-hw-orderbook-price-level-20260916-0838/report.md)，不重复展开）；未核实 GB/s/ns；DDR 物理层抄录

## 决策问题

1. **两条路径如何分工？** → [report.md §1.2](./report.md)
2. **高/低稀疏度默认组合？** → [report.md §7](./report.md)
3. **merge / 屏障 / 翻车？** → [report.md §3.2、§5.4、§7.3](./report.md)

## Links

- [report.md](./report.md) — 详尽正文（修订：双路径 + 八维 + 机制四问）
- [onepager.md](./onepager.md) — 一页纸速览
- [sources.md](./sources.md) — 出处 ≥12
