# 一页纸速览：Bitmap × DDR × AXI 吞吐优化（修订）

**Asia/Shanghai 2026-09-16 08:48**

---

## 方法论：先拆两条路径

| 路径 | 职责 | 默认承载 | 禁止 |
|------|------|----------|------|
| **α bitmap** | 找 next valid、置位/清除、批量 flip | **片上 BRAM/URAM** | DDR 逐 bit/逐槽裸扫 |
| **β payload** | 按有效 index 读/写记录体 | **DDR SOA** | 对空槽试探读 |

**吞吐分开算：** α 产出 index 速率；β AR 次数 × 有效 beat 比例。

---

## 三问三答

| # | 问题 | 答案 |
|---|------|------|
| 1 | bitmap 片上还是 DDR？ | **α 默认片上**；DDR 仅 payload + 可选 bitmap WT 副本；audit/超大 N 才 DDR burst 读 bitmap |
| 2 | 如何避免逐槽 AXI？ | **α 片上 word+summary**；**β 仅 touched index**；高 ρ **run-merge INCR** |
| 3 | 高/低 ρ 默认？ | 低 ρ：**summary+单 AR，不 merge**；高 ρ：**run-merge L_min=4**；快照 **epoch/双缓冲** |

---

## 冻结八维（对比表列）

① bitmap 承载 | ② payload 布局 | ③ 扫描算法 | ④ 有效→AXI 聚合 | ⑤ 对齐/4K | ⑥ bank 规避 | ⑦ 读写比/更新频 | ⑧ 出处

**机制四问（每行必答）：** Q1 地址映射 | Q2 连续 valid 能否 INCR | Q3 空洞多大放弃 merge | Q4 置位/清与 payload 屏障

---

## 默认组合

### 高稀疏 ρ≤0.15

| 维 | 选择 |
|----|------|
| α | BRAM + 64-slot summary + **增量游标** |
| β | SOA stride=align(16,32) + **单 index AR** + RO=8 |
| merge | **否**（空洞≥1 即拆） |
| 屏障 | payload→fence→set valid；快照 **epoch** |

### 低稀疏 ρ≥0.4

| 维 | 选择 |
|----|------|
| α | BRAM word scan（summary 可选） |
| β | SOA + **run-merge**（L_min=4）+ 4KB 切段 |
| merge | **是**（run 内全 valid、地址连续） |
| 屏障 | 同左；全表可用 **双缓冲 bitmap** |

---

## 翻车条件（outstanding / 对齐）

| 信号 | 后果 |
|------|------|
| α+β 都 DDR 裸扫 | next-valid 多一次 DDR 读 |
| RO=1 | β 流水线空泡 |
| stride 非 beat 对齐 | narrow read **待核实** |
| merge 跨 4KB 未切 | AXI 违规 |
| 低 ρ 强行 merge | 合并器空转 |
| 无 fence | 半初始化 payload 可见 |
| 池化/bank 交错 payload | 连续 i 无法 INCR |

---

## 冻结假设

| 参数 | 假定 | 状态 |
|------|------|------|
| N | 4096 | 假设 |
| W_rec | 128 bit | 假设 |
| W_axi | 256 bit | 假设 |
| RO/WO | 8/4 | 假设 |
| DDR 控 | MIG AXI4 | 待核实 |
| 扫描 | **增量游标** 为主 | 假设 |
| ρ | 高 0.4～0.8 / 低 0.02～0.15 | 假设 |

---

## In / Out

- **In：** bitmap 维护 DDR 槽有效位时的 **访存组织与吞吐**
- **Out：** 订单簿/会话语义、RTL top/core、DDR 加速泛化综述（交叉引用 [0838](../fpga-hw-orderbook-price-level-20260916-0838/report.md)）

---

## 链接

- [report.md](./report.md) — 完整修订正文
- [sources.md](./sources.md) — 出处 ≥12
