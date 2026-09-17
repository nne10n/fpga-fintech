# FPGA IOPV 分市场计算与跨市场合成调研

- **Slug:** `fpga-iopv-per-market-cross-synth-20260916-1854`
- **仓:** [Research_everything](https://cursor.com/codebase/melon5253/Research_everything)
- **Date:** Asia/Shanghai 2026-09-16 18:54（收紧修订同目录）
- **Tags:** FPGA, IOPV, partial, cross-market, FX, evidence

## 交付物

| 文件 | 说明 |
|------|------|
| [report.md](./report.md) | 详尽正文：文首结论≤10行 + 一页纸速览；对比表/机制/数字绑出处 |
| [onepager.md](./onepager.md) | 独立一页纸 |
| [sources.md](./sources.md) | ≥11 主出处；**S11 证伪/边界** |
| [evidence/](./evidence/) | 7 份摘录（含 S11 边界、四问草稿） |

## 结论（一行）

**B0：** per-leg 可加 partial 累加器 → 同钟 synth（只汇合 partial×FX + global）；翻车见 report §7.2；**S11 证伪** IOPV≠NAV。

## Out

未核实 ns · RTL top · 策略报单 · 行情解析重做 · 申赎状态机深挖

## 前序

[`fpga-iopv-per-market-cross-synth-20260916-0842`](../fpga-iopv-per-market-cross-synth-20260916-0842/)
