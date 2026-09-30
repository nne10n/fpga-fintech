# FPGA 处理 TCP 黏包、碎包与重传/乱序重组

- **Slug:** `fpga-tcp-sticky-frag-retransmit-20260916-1854`
- **Date (Asia/Shanghai):** 2026-09-16 18:54（批量收紧修订）
- **仓:** [Research_everything](https://cursor.com/codebase/melon5253/Research_everything)
- **Tags:** FPGA, TCP, TOE, 黏包, 半包, 重传, 乱序, IP 分片, 留证
- **Summary:** **三层禁混称**（L4 流重组 / L7 分帧 / RX·TX 重传）；**IP 分片 ≠ TCP 碎包**。低延迟默认：**partial TOE RX + 应用分帧；TX 重传不上 FPGA**（S7 §III.E + 单向假设 **推断**）。对比表/机制/数字 **必须** 指到 [sources.md](./sources.md) 或 [evidence/](./evidence/)。

## 留证硬规则（本目录）

1. 对比表单元格、机制断言、数字 → **URL+章节** 或 **仓内 evidence 路径**；否则 **待核实** 或删除
2. 文首：**结论 ≤10 行** + **一页纸速览** → [report.md](./report.md) §1–§2
3. 分级：**事实 / 推断 / 待核实**；开源仓写清文件/接口（S15）
4. **Out：** 未核实 ns、RTL top、策略报单；不把 IP 分片当 TCP 碎包
5. 结论 = **默认方案 D** + **翻车条件**；[evidence/05](./evidence/05-falsification-boundary.md) 证伪/边界

## 交付物

| 文件 | 说明 |
|------|------|
| [report.md](./report.md) | 完整报告（§1 结论 + §2 速览 + 机制 + 有出处对比表） |
| [sources.md](./sources.md) | **15** 条出处（≥10）+ 章节/路径 |
| [evidence/](./evidence/) | **5** 份摘录（含证伪/边界） |

## Links

- [report.md](./report.md) · [sources.md](./sources.md) · [evidence/](./evidence/)
- [前版 0841](../fpga-tcp-sticky-frag-retransmit-20260916-0841/)
