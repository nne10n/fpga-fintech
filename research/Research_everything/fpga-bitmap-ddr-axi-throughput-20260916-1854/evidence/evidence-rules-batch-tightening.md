# 批量统一收紧 — 本题适用规则（1854 二轮）

**日期：** 2026-09-16  
**目录：** `fpga-bitmap-ddr-axi-throughput-20260916-1854/`

## 留证硬规则（已并入 report 文首）

1. 对比表 **每个非空单元格** 须带 `S?` / **推断** / **待核实**；写不出出处则删或标待核实。
2. 机制断言同则；**数字**（N、ρ、L_min、RO、stride、AR 次数）须标 **假设/推断** 或给公式出处。
3. **禁止** 未核实 GB/s、ns；IIT 350 ns 等 **不得** 进入本主题结论（见 evidence/iit 隔离说明）。

## 本轮相对首版 1854 的删改

| 删/改 | 原因 |
|-------|------|
| 删除 report §10 RTL top 框图 | Out — 不写 RTL top |
| 删除 report §11 DDR 加速综述表 | Out — 不另起离散 DDR 综述；仅 §1 Out 一句 |
| 结论摘要 12 行 → **≤10 行** | 规则 2 |
| epoch 决策树删除「1 µs」 | 无出处数字 |
| §6 对比表全列补 `S?` | 留证硬规则 |
| 新增 **S4 证伪** evidence | 规则 6：≥1 证伪/边界 |

## 开源仓接口（S6）

| 项 | 值 |
|----|-----|
| 仓库 | `torvalds/linux` |
| 文件 | `lib/find_bit.c` |
| 接口 | `_find_next_bit()`；宏 `FIND_NEXT_BIT` |
| URL | https://raw.githubusercontent.com/torvalds/linux/master/lib/find_bit.c |
