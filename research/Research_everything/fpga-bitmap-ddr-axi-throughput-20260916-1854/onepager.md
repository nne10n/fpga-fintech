# 一页纸速览：Bitmap × DDR × AXI 吞吐（1854 收紧版）

**Asia/Shanghai 2026-09-16 18:54** · 仓 [Research_everything](https://cursor.com/codebase/melon5253/Research_everything) · 目录 `fpga-bitmap-ddr-axi-throughput-20260916-1854/`

---

## 默认方案（结论 = 默认 + 翻车）

| ρ 档 | 路径 α | 路径 β | merge / 空洞 | 屏障 | 出处 |
|------|--------|--------|--------------|------|------|
| **≤0.15** | 片上 BRAM bitmap + 64-slot summary + `find_next_bit` 游标 | SOA payload + **单 index AR** + RO 深度 | **不 merge**；空洞≥1 拆 | payload→fence→set valid；快照 epoch | α:S5,S6,S15；β:S1；屏障:**推断** |
| **0.15–0.4** | 同左（summary 块可 256） | SOA + 可选短 run merge | L_min=2 **推断**；空洞≥2 拆 | 同左 | **推断**（无单篇直接出处） |
| **≥0.4** | 片上 word scan | SOA + run-merge INCR | L_min=4 **推断**；4KB 切段 | 同左；全表可双缓冲 | merge 切段:S1–S4,S3 |

**禁止默认：** α 在 DDR 上逐 word 裸扫 next-valid（**证伪** S4 + A1 反例；正例 S5,S9 均为片上 mask）。

---

## 机制四问（每方案必答）

| # | 问题 | 答案 | 出处 |
|---|------|------|------|
| Q1 | 映射 | 同 index `i`；`payload(i)=P_base+i×stride`；bitmap 片上或 `B_base+⌊i/8⌋` 异区 | SOA:S9 Eq.1；AXI 地址:S1 |
| Q2 | INCR merge | SOA 且 run 内全 valid、stride 固定 → 一条 INCR AR | S1,S13 |
| Q3 | 空洞阈值 | 低 ρ 空洞≥1 拆；高 ρ run≥L_min 且连续 valid 才 merge | **推断** |
| Q4 | 屏障 | alloc：β 写完成→fence→α set；free：α clear→fence→β 可选清零 | **推断** |

---

## 翻车条件

| 信号 | 后果 | 出处/标注 |
|------|------|-----------|
| α DDR 裸扫 bitmap | 每 next-valid 一次 DDR 读 | **证伪** S4；反例 A1 |
| merge 跨 4KB | AXI 违规 / VIP Fatal | S1,S2,S14 |
| 依赖 SmartConnect 自动拆 burst | 非合规 Master；升级可失效 | **证伪/边界** S4 |
| RO=1 | β 流水线空泡 | S1 outstanding **推断** |
| stride 非 beat 对齐 | narrow read 行为 | **待核实** S1 |
| 低 ρ 强行 merge | 合并逻辑空转 | **推断** |
| 无 fence alloc | 半初始化 payload 可见 | **推断** |
| 池化/bank 交错 payload | 连续 i 地址不连续 → 无法 INCR | **推断** |

---

## Out（一句）

未核实 ns/GB/s、完整 RTL top/core、策略报单、会话/ITCH、离散 DDR 加速长综述 → 见 [0838](../fpga-hw-orderbook-price-level-20260916-0838/report.md) 或 **Out**，本报告不展开。

---

## 链接

- [report.md](./report.md) · [sources.md](./sources.md) · [evidence/](./evidence/)
