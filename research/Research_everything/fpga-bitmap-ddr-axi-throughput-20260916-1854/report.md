# Bitmap 维护 DDR 有效条目 × AXI 接口吞吐优化

**1854 收紧重跑** · Asia/Shanghai 2026-09-16 18:54 · 仓 [Research_everything](https://cursor.com/codebase/melon5253/Research_everything)

**留证：** [evidence/](./evidence/) · **出处：** [sources.md](./sources.md)（S1–S16） · **前序：** [0848](../fpga-bitmap-ddr-axi-throughput-20260916-0848/report.md)

---

## 留证硬规则（本轮强制）

| 规则 | 执行 |
|------|------|
| 对比表单元格 | 非空单元格须带 `S?` / **推断** / **待核实**；无出处则删或标待核实 |
| 机制断言 | 同则；交叉关键机制 ≥2 源（见 sources 矩阵） |
| 数字 | N、ρ、RO、L_min、stride、相对 AR 次数须标 **假设/推断** 或给公式源（如 S3 4KB 式） |
| 禁编造 | 未核实 **GB/s、ns** 不写进结论；第三方 timing **不引用** |
| 开源仓 | 写清 **文件/函数**（S6：`lib/find_bit.c` / `_find_next_bit`） |
| 证伪/边界 | ≥1 条：**S4**（不可依赖互联拆违规 burst）→ [evidence/s4-falsify-interconnect-split.md](./evidence/s4-falsify-interconnect-split.md) |

**证据分级：** **事实** = 规范/可访问原文；**推断** = 工程默认；**待核实** = IP/缺参；**证伪/边界** = 否定性/不可依赖断言。

---

## 结论摘要（≤10 行）

1. **α/β 分离（推断）：** α = bitmap 扫描/置清；β = 按有效 index 读/写 DDR payload；禁止混为单一 DDR 带宽问题。
2. **α 默认（事实+推断）：** 片上 BRAM/URAM（S5,S9,S15）；**禁止** DDR 逐 word 裸扫 next-valid（**证伪** S4；正例 S5,S9 均为片上 mask）。
3. **β 默认（事实）：** SOA `P_base+i×stride`（S9 Eq.1 同构）；INCR merge 当 run 连续、stride 对齐、不跨 4KB（S1,S3）。
4. **低 ρ≤0.15 默认（推断）：** summary + 单 index AR；空洞≥1 不 merge；RO 深度填流水线（S1 outstanding 概念）。
5. **高 ρ≥0.4 默认（推断）：** run-merge + Master 侧 4KB 切段（S2–S4,S3）；L_min=4 **假设**。
6. **屏障（推断）：** alloc = payload 写完成→fence→set valid；快照 epoch 或双缓冲。
7. **翻车：** α DDR 裸扫、跨 4KB merge、RO=1、stride∤beat（待核实）、无 fence、池化 layout（§7.3）。
8. **Out：** 未核实 ns、RTL top/core、策略报单、会话/ITCH、离散 DDR 长综述 — **不展开**（§1.1）。
9. **指标：** 仅相对 AR 次数/空读比例；无 GB/s（S12 未引效率表 **待核实**）。
10. **一页纸：** [onepager.md](./onepager.md)

---

## 一页纸速览

> 独立文件：[onepager.md](./onepager.md)（默认方案 + 四问 + 翻车 + Out 一句）

---

## 1. 问题定义与范围

### 1.1 In / Out

| In | Out（本报告不展开） |
|----|---------------------|
| bitmap 维护 DDR 槽 valid 的 **访存组织与 AXI 吞吐** | 订单簿撮合、ITCH/会话、**策略报单** → [0838](../fpga-hw-orderbook-price-level-20260916-0838/report.md) |
| 路径 α/β、八维对比、屏障、翻车 | **完整 RTL top/core** |
| AXI4 burst/4KB/outstanding（S1） | 未核实 **GB/s、ns** |
| 索引级槽表映射 | DDR 物理层 JEDEC 抄录 |
| | **离散 DDR 加速泛化长综述** — 非本报告；深档 DRAM 仅 **Out 交叉** 0838 §2.5 |

### 1.2 两条路径

```
  路径 α (bitmap)  片上 BRAM/URAM │ set/clear │ next-valid / 全表
        │ 有效 index 或 run
        ▼
  路径 β (payload)  DDR SOA │ 单 AR │ run-merge INCR │ SG(RO)
```

| 路径 | 承载默认 | AXI | 出处 |
|------|----------|-----|------|
| **α** | 片上 BRAM/URAM | 否（audit/WT 副本除外） | S5,S9,S15,S16 |
| **β** | DDR SOA payload | 是 | S1 |

**吞吐口径（推断）：** 分别计 α 产出 index/run 与 β AR 次数、有效 beat 占比；合并指标 **相对**，无绝对带宽。

### 1.3 valid vs payload

| 概念 | 宽度 | 出处 |
|------|------|------|
| valid bit | 1 bit/槽 | S5,S9 mask 分表 **事实** |
| payload | W_rec **假设** 128 bit | — |
| bitmap 打包 | ⌈N/8⌋ B；N=4096 **假设** | S7 同量级 |

β 若盲扫全 N 槽，ρ=10% **假设** 时空读比例高 — **推断**（无单源公式，机制自明）。

---

## 2. 假设与口径

| 参数 | 假定 | 标注 | 出处 |
|------|------|------|------|
| N | 4096 | **假设** | S7 |
| ρ 低/高 | ≤0.15 / ≥0.4 | **假设** | — |
| W_axi | 256 bit | **假设** | S1 允许 ARSIZE |
| RO / WO | 8 / 4 | **假设** | S11 **待核实** 上限 |
| L_min 低/高 | ∞ / 4 | **推断** | — |
| L_min 中 | 2 | **推断** | — |
| stride | align(16,32) B | **假设** | S1 beat 对齐 **待核实** narrow |

---

## 3. 地址映射与机制四问

### 3.1 映射

```
payload(i) = P_base + i × stride          // SOA，S9 Eq.1 同构
bitmap 片上: bit[i] @ BRAM word[i/W_word] // S6,W_word=64 假设
bitmap DDR 副本: B_base + ⌊i/8⌋            // 可选 WT，异区 推断
```

| 布局 | β merge | 出处 |
|------|---------|------|
| SOA | **可** INCR | S1,S9 |
| 池化/bank 交错 | **否** | **推断** |
| AOS 内嵌 valid | 否决作 α 替代 | **推断** |

### 3.2 机制四问

| # | 答案 | 出处 |
|---|------|------|
| Q1 映射 | 同 i；payload/bitmap 异区 | S9,S1 |
| Q2 INCR | run 全 valid + 连续地址 → 一条 AR | S1,S13 |
| Q3 空洞 | 低 ρ ≥1 拆；高 ρ run≥L_min **推断** | **推断** |
| Q4 屏障 | alloc: β→fence→α；free: α→fence→β | **推断** |

---

## 4. 八维框架

① bitmap 承载 | ② payload 布局 | ③ 扫描 | ④ AXI 聚合 | ⑤ 4KB/对齐 | ⑥ bank | ⑦ 读写比 | ⑧ 出处 — 见 §6 表。

---

## 5. 方案与机制

### 5.1 路径 α 承载

**A0 片上（默认）**

| 项 | 内容 | 出处 |
|----|------|------|
| 承载 | BRAM + 可选 64b summary/64 槽 | S5,S15 |
| 扫描 | `_find_next_bit` 同构 word 游标 | S6 `lib/find_bit.c` |
| Q2 | α 无 AXI；audit 可 512B INCR 读 bitmap | **推断**；INCR **事实** S1 |
| Q3 | word=0 skip；summary 跳块 | S6 |

**A1 DDR bitmap（反例，非默认）**

| 项 | 内容 | 出处 |
|----|------|------|
| 行为 | 增量 next-valid 每步 DDR 读 word | **推断** |
| 判定 | **禁止为默认**；与 S5,S9 片上 mask **对照证伪** | S5,S9 vs A1 |

### 5.2 路径 α 扫描（开源接口 S6）

| 接口 | 路径 | 说明 |
|------|------|------|
| 文件 | `torvalds/linux` → `lib/find_bit.c` | S6 |
| 函数 | `_find_next_bit(addr, nbits, start)` | S6 |
| 宏 | `FIND_NEXT_BIT` — mask 低位、跳零 word | S6；evidence/linux |

RTL 映射：**推断** — BRAM 口读 word + ctz，非 Linux 延迟。

### 5.3 路径 β

**B0 run-merge（高 ρ）**

| 项 | 出处 |
|----|------|
| INCR、ARLEN≤255 | S1 |
| 4KB 切段 `addr[11:ADDRLSB]+(len+1)<4096` | S3 |
| Master 自切段，**不**依赖互联 | **证伪** S4 |

**B1 单 AR（低 ρ）** — 不 merge：**推断**

**B2 池化** — 连续 i 不连续 addr：**推断**

### 5.4 一致性

| 操作 | 序 | 出处 |
|------|-----|------|
| alloc | β AW → BRESP → fence → α set | **推断** |
| free | α clear → fence → β 可选清零 | **推断** |
| 快照 | epoch 或双缓冲 | **推断** |

S5：bitmask 在 **URAM 片上** 更新 topCache；HBM 存历史订单 — **事实**（evidence/iit）；**不得** 推为 DDR bitmap 裸扫依据。

### 5.5 4KB / 对齐

| 规则 | 出处 |
|------|------|
| burst 不跨 4KB | S1,S2,S14 |
| VIP Fatal 违规 burst | S2 |
| SmartConnect 偶发接受 ≠ 合规 | **证伪/边界** S4 |

---

## 6. 综合对比表（八维 + 四问，单元格留证）

| 方案 | ① bitmap | ② payload | ③ 扫描 | ④ AXI | ⑤ 4K/对齐 | ⑥ bank | ⑦ 读写 | Q1 | Q2 merge | Q3 空洞 | Q4 屏障 |
|------|----------|-----------|--------|-------|-----------|--------|--------|-----|----------|---------|---------|
| **低ρ默认** | A0+summary S5,S15 | B1 SOA S9 | S6 ffs | 单 AR S1 | stride **假设**；4K S1 | 异区 **推断** | 随机读 **推断** | §3.1 S9 | 否 S1 | ≥1 **推断** | epoch **推断** |
| **中ρ** | A0 S15 | B0/B1 S9 | S6 | L_min=2 **推断** | S3,S1 | 异区 **推断** | 混合 **推断** | §3.1 | 可选 **推断** | ≥2 **推断** | epoch **推断** |
| **高ρ默认** | A0 S5,S15 | B0 S9 | S6 | run INCR S1,S13 | 切段 S2–S4,S3 | 异区 **推断** | 扫少 **推断** | §3.1 | 是 S1 | L_min **推断** | fence **推断** |
| A1 反例 | DDR S1 | B0 S9 | burst **推断** | β merge S1 | S1 | 争用 **待核实** S12 | audit **推断** | 异区 **推断** | β 同 | 同 | WT **推断** |
| B2 反例 | A0 S15 | 交错 **推断** | S6 | SG S1 | 差 **推断** | 差 **待核实** | — | 非线性 **推断** | 否 S1 | — | fence **推断** |
| 内嵌 valid | 无 | AOS **推断** | 无 α | 逐行 S1 | 行对齐 **推断** | — | — | 同行 **推断** | 否 | — | 简单 **推断** |

---

## 7. 默认方案 + 翻车条件（结论主体）

### 7.1 低 ρ ≤0.15（**推断**）

| 块 | 内容 | 出处 |
|----|------|------|
| α | BRAM + 64-slot summary + S6 游标 | S5,S6,S15 |
| β | SOA + 单 index AR | S1,S9 |
| merge | 否 | **推断** |
| 屏障 | payload→fence→valid | **推断** |

### 7.2 高 ρ ≥0.4（**推断**）

| 块 | 内容 | 出处 |
|----|------|------|
| α | BRAM word scan | S6,S15 |
| β | run-merge + S3 4KB  clip | S1–S4,S3 |
| L_min | 4 **假设** | — |

### 7.3 翻车条件

| 条件 | 现象 | 处置 | 出处 |
|------|------|------|------|
| α DDR 裸扫 | 每步 DDR 读 bitmap | α 回片上 | **证伪** S4；S5,S9 |
| 跨 4KB merge | 违规/Fatal | Master 切段 | S2,S4 |
| 信互联自动拆 | 升级失效 | Master 合规 | **证伪** S4 |
| RO=1 | β 空泡 | 增 RO | S1 **推断** |
| stride∤beat | narrow **待核实** | pad | S1 **待核实** |
| 低ρ强 merge | 空转 | L_min=∞ | **推断** |
| 无 fence | 半写 payload | β→α 序 | **推断** |
| 池化 layout | 无 INCR | 改 SOA | **推断** |

---

## 8. 工作示例（相对，数字均 **假设**）

**8.1 低 ρ：** N=4096 **假设**，ρ=0.05 **假设**，stride=32B **假设**。α：0 AXI（S6）；β：1 AR/有效 index（S1）。无效槽 0 AR vs 盲读 1 AR — **推断**。

**8.2 高 ρ：** ρ=0.6 **假设**，均 run=6 **假设**。α：0 AXI；β：相对 AR ≈ ρN/run vs ρN — **推断**（算式 illustrative，非实测）。

---

## 9. Out 边界（一句交叉，非综述）

| Out 项 | 指向 |
|--------|------|
| 档位 valid-bitmask 业务 | [0838](../fpga-hw-orderbook-price-level-20260916-0838/report.md) S7 |
| 深档 DRAM 行映射 | 0838 §2.5 **Out** |
| RTL top / 策略报单 / ns | **不写** |

槽表 `i` 与档位 `off=⌊(px-base)/T⌋` **不同索引语义** — S7,S8 **事实** vs 本 In **假设** N 槽。

---

## 10. 待核实

| 项 | 标注 |
|----|------|
| MIG bank/row | **待核实** S12 |
| PG058 RO 上限 | **待核实** S11 |
| 16B on 32B beat narrow | **待核实** S1 |
| L_min 最优 | **推断** |

---

## 11. 出处

[sources.md](./sources.md) S1–S16；[evidence/](./evidence/) 含 **S4 证伪**、S6 摘录、4KB、IIT、FPL17、收紧规则说明。

---

*1854 收紧 · ≤10 行摘要 + onepager · 单元格留证 · S4 证伪 · Out 不展开 RTL/综述/ns*
