# 出处清单与抓取备注

**Asia/Shanghai 2026-09-16 18:54（收紧二轮）** · `fpga-bitmap-ddr-axi-throughput-20260916-1854/` · 仓 [Research_everything](https://cursor.com/codebase/melon5253/Research_everything)

标注：**事实** / **推断** / **待核实** / **证伪/边界**

---

| ID | 来源 | 引用点 | 标注 | 抓取 |
|----|------|--------|------|------|
| S1 | [AMBA AXI4 (IHI 0022E)](https://developer.arm.com/documentation/ihi0022/latest/) | INCR、ARLEN/ARSIZE、outstanding、§A3.4.1 4KB | **事实** | JS 壳；S2–S4 交叉 |
| S2 | [AMD AR#1062002 AXI VIP](https://adaptivesupport.amd.com/s/article/1062002) | `AXI4_ERRM_*_BOUNDARY` Fatal | **事实** | 200；evidence/axi4 |
| S3 | [ZipCPU AXI Master 2020-06-16](https://zipcpu.com/blog/2020/06/16/axiaddr-limits.html) | 4KB 限幅公式、Master 切段 | **事实** | 200 |
| S4 | [AMD Community — 4KB burst](https://adaptivesupport.amd.com/s/question/0D54U00008wQR3rSAG/about-axi-burst-length-and-burst-size) | Master 须合规；**SmartConnect 不保证拆** | **证伪/边界** | 200；[evidence/s4-falsify-interconnect-split.md](./evidence/s4-falsify-interconnect-split.md) |
| S5 | [IIT TTO 2024 PDF](https://rndshowcase.iiit.ac.in/tto2024/TTO_website_data/PDF/25.pdf) | URAM bitmask；HBM 历史；**非 DDR bitmap 扫** | **事实** | 200；evidence/iit |
| S6 | [Linux `lib/find_bit.c`](https://raw.githubusercontent.com/torvalds/linux/master/lib/find_bit.c) | 文件 `lib/find_bit.c`；`_find_next_bit`；`FIND_NEXT_BIT` | **事实** | 200；evidence/linux |
| S7 | [0838/report.md](../fpga-hw-orderbook-price-level-20260916-0838/report.md) | 类 D valid-bitmask；Out 边界 | **事实** | 仓内 |
| S8 | [Columbia Market Data Parser PDF](http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf) | BRAM valid 稠密槽 | **事实** | 0838 已引 |
| S9 | [FPL17 PDF](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf) | mask/qty 分表；Ap 线性式 | **事实** | 200；evidence/fpl17 |
| S10 | [MDPI 12(3)520](https://www.mdpi.com/2079-9292/12/3/520) | 片上价节点 | **事实** | 未重抓 |
| S11 | [PG058 AXI Ref](https://docs.amd.com/r/en-US/pg058-axi-ref) | outstanding/FIFO | **待核实** | 壳 |
| S12 | [PG150 MIG](https://docs.amd.com/r/en-US/pg150-ultrascale-memory-ip) | AXI slave/bank | **待核实** | 壳 |
| S13 | [WP469 AXI Burst](https://docs.amd.com/r/en-US/wp469-axi-burst-types) | INCR 效率 | **事实** | 壳 |
| S14 | [Altera AXI4 Assertions](https://docs.altera.com/r/docs/838773/25.1/altera-axi4-bus-functional-model-user-guides/altera-axi4-memory-mapped-assertions) | ARADDR_BOUNDARY | **事实** | 检索 |
| S15 | [UG473 BRAM](https://docs.amd.com/r/en-US/ug473_7Series_CLB) | 36Kb 双口 | **事实** | — |
| S16 | [UG573 URAM](https://docs.amd.com/r/en-US/ug573-ultrascale-clb) | 288Kb | **事实** | — |

**计数：** 16 条（≥10）。**证伪/边界：** S4（必选 1 条）。

---

## 开源接口（S6）

| 字段 | 值 |
|------|-----|
| 仓库 | `torvalds/linux` |
| 文件 | `lib/find_bit.c` |
| 符号 | `_find_next_bit(const unsigned long *addr, unsigned long nbits, unsigned long start)` |
| 宏 | `FIND_NEXT_BIT(FETCH, MUNGE, size, start)` |

---

## 交叉核对

| 机制 | 主源 | 辅源 |
|------|------|------|
| 4KB 不跨 | S1 | S2,S3,S14 |
| 禁止信互联拆 burst | **S4 证伪** | S2 |
| 片上 mask | S5,S9 | S7 |
| α word 扫描 | S6 | S5 |
| INCR merge | S1 | S13 |

---

## 未编造

无未核实 GB/s/ns。IIT 350 ns **不引用**于本主题结论（evidence/iit 隔离）。

## 收紧规则留证

[evidence/evidence-rules-batch-tightening.md](./evidence/evidence-rules-batch-tightening.md)
