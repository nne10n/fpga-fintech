# FPGA / 存储子系统：Bitmap × DDR × AXI 吞吐（1854 收紧版）

- **Slug:** `fpga-bitmap-ddr-axi-throughput-20260916-1854`
- **Date (Asia/Shanghai):** 2026-09-16 18:54
- **仓:** [Research_everything](https://cursor.com/codebase/melon5253/Research_everything)
- **Tags:** FPGA, DDR, AXI4, bitmap, dual-path, evidence, tightening
- **Summary:** α 片上 bitmap / β DDR SOA 分离；低ρ 单 AR、高ρ run-merge+4KB 切段；**S4 证伪**不可依赖互联拆 burst；单元格留证；Out 不写 ns/RTL top/策略/离散 DDR 综述。

## 交付物

| 文件 | 说明 |
|------|------|
| [report.md](./report.md) | 正文：≤10 行摘要 + 留证规则 + 八维表（单元格带 S?） |
| [onepager.md](./onepager.md) | 一页纸：默认方案 + 翻车 |
| [sources.md](./sources.md) | S1–S16（≥10）；S4 **证伪/边界** |
| [evidence/](./evidence/) | 抓取/证伪/收紧规则（≥3） |

## 决策

1. α/β 分工 → report §1.2  
2. 默认方案 + 翻车 → report §7、[onepager.md](./onepager.md)  
3. 机制四问 → report §3.2  
4. Out 边界 → report §9（**非** DDR 综述）

## 前序

[0848](../fpga-bitmap-ddr-axi-throughput-20260916-0848/) · [0838 档位](../fpga-hw-orderbook-price-level-20260916-0838/report.md)
