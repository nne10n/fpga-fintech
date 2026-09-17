# Bitmap 维护 DDR 有效条目 × AXI 接口吞吐优化

**完整详尽调研报告（修订）** · Asia/Shanghai 2026-09-16 08:48

---

## 结论摘要（≤10 行）

1. **先拆两条路径再谈吞吐（推断）：** **路径 α** = bitmap 扫描/置清（找 next valid、批量 flip）；**路径 β** = 按有效下标对 DDR **payload** 读/写。二者 **可不同承载**——禁止默认「bitmap 与 payload 都在 DDR 上裸扫/裸读」。
2. **路径 α 默认：** N≤64K → **片上 BRAM/URAM**（4096 bit=512 B）；全表刷才 **DDR burst 读 bitmap 区**；增量游标用 **片上 word 步进 + 可选分层 summary**。
3. **路径 β 默认：** payload **SOA 连续数组**于 DDR；仅对 bitmap 置位 index 发 AXI；**合 burst** 仅当连续有效 run 长度 ≥ `L_min` 且地址 **INCR 连续、不跨 4KB**。
4. **稀疏度高（ρ≤0.15，推断）：** **片上 bitmap + 64 槽 summary + 单 index payload AR**；放弃跨空洞 merge（空洞 ≥1 即拆请求）；扫描用 **增量游标** 非每次全表。
5. **稀疏度低（ρ≥0.4，推断）：** **片上 bitmap + SOA payload + run 检测 merge**（`L_min=4` 槽 **假设**）；全表快照可 **分段 INCR burst** 读 payload；bitmap 扫描非瓶颈。
6. **地址映射（事实+推断）：** `payload_addr(i)=P_base+i×stride`；`bitmap` 片上或 `B_base+⌊i/8⌋`；**无交错** 时 stride=`⌈W_rec/8⌉` 对齐 beat。
7. **一致性（推断）：** 分配 **payload 写完成 → 内存屏障 → set valid**；释放 **clear valid → 屏障 → 可选清 payload**；快照需 **epoch 或双缓冲 bitmap**，否则扫描与写并发翻车。
8. **AXI 默认（推断）：** RO=8、WO=4、分 ID；ARSIZE=max；**4KB 边界** 强制切段；outstanding=1 或 stride 未对齐 → **路径 β 翻车**。
9. **In/Out：** 本报告 **In**=用 bitmap 维护「DDR 哪些槽有效」时的 **访存组织与吞吐**；**Out**=订单簿/会话完整语义、完整 RTL top/core、离散 DDR 加速泛化综述（见 §8 交叉引用，不重复展开）。
10. 证据分 **事实/推断/待核实**；**禁未核实 ns/GB/s**；对比表按 **§4 冻结八维** 填表，机制行强制回答映射/burst/空洞/屏障四问。

---

## 一页纸速览

> 独立文件：[onepager.md](./onepager.md)

| 决策问题 | 一句话 |
|----------|--------|
| 两条路径？ | **α bitmap 扫描/置清** 与 **β payload 读/写** 分开选型；α 优先片上，β 才走 DDR AXI |
| 高 ρ / 低 ρ 默认？ | 高 ρ：**片上 bitmap + run-merge payload burst**；低 ρ：**片上 bitmap + summary + 单 AR，不 merge** |
| 连续有效能 INCR burst？ | **能**，当 run 连续、stride 对齐、不跨 4KB 且 run≥`L_min`；**空洞≥1 默认放弃合并**（低 ρ） |
| 置位与 payload 写？ | **先 payload 后 valid**；快照扫描用 **epoch/双缓冲**；禁止 write-back 脏镜像与外读 DDR 并发 |
| 何时翻车？ | 双路径都 DDR 裸扫、AOS/池化交错、RO=1、stride∤beat、跨 4KB 未切、无屏障 |

---

## 1. 问题定义与范围

### 1.1 In / Out（钉死）

| In | Out |
|----|-----|
| 用 **bitmap** 维护「DDR 中哪些槽有效」时的 **访存组织** 与 **吞吐手段** | **完整业务语义**（订单簿撮合规则、会话/ITCH 栈、报单策略） |
| 路径 α：扫描/枚举/置位/清除 valid | **完整 RTL top/core** 模块划分与接口成文 |
| 路径 β：按有效 index 读/写 payload | **DDR4/LPDDR 物理层** 调参手册抄录 |
| AXI4/AXI4-Lite burst、对齐、outstanding、4KB 边界 | 未核实绝对 **GB/s、ns** |
| bitmap↔payload **地址映射**、一致性/屏障 | **「离散 DDR 加速」泛化综述**（另篇；可交叉引用 [订单簿档位报告](../fpga-hw-orderbook-price-level-20260916-0838/report.md)，本报告不重复展开） |
| bank/行冲突 **调度直觉** | CPU 侧缺页/页表算法长文（**一句对照**：Linux `find_next_bit` 仅作 word-scan 对照） |
| 固定槽表（4096 槽）**索引级**映射 | |

### 1.2 两条路径分解（核心方法论）

**禁止** 将「bitmap 扫描」与「payload 访问」混为单一「DDR 带宽」问题；必须先分路径再对比。

```
                    ┌──────────────────────────────────────┐
  路径 α (bitmap)   │ 找 next valid │ 全表/增量扫描 │ set/clear │
                    │ 承载：片上优先 │ DDR 仅冷/audit │
                    └─────────────────┬────────────────────┘
                                      │ 输出：有效 index 集合 / 游标
                                      ▼
                    ┌──────────────────────────────────────┐
  路径 β (payload)  │ 按 index AR/AW │ merge burst │ SG 队列 │
                    │ 承载：DDR SOA  │ 仅 touched 槽 │
                    └──────────────────────────────────────┘
```

| 路径 | 问什么 | 典型承载 | AXI 是否必须 |
|------|--------|----------|--------------|
| **α bitmap** | 哪些槽有效？下一有效在哪？ | **BRAM/URAM**（默认） | 仅 flush/audit/超大 N |
| **β payload** | 有效槽里内容是什么？ | **DDR SOA** | **是**（数据主路径） |

**吞吐对比口径：** 分别统计 **α 命令/周期** 与 **β AR+AW 次数、有效 beat 比例**；合并指标 = α 产出 index 速率 × β 每 index 字节。

### 1.3 有效位 vs 记录体

| 概念 | 含义 | 典型宽度 |
|------|------|----------|
| **valid bit** | 槽 `i` 是否有有效记录 | 1 bit/槽 |
| **payload** | 槽内字段 | `W_rec` bit，**假设** 64～512 |
| **bitmap** | valid 密集打包 | `⌈N/8⌉` B |

**核心矛盾：** 若路径 β 对 **全部 N 槽** 读 payload 再判 valid，ρ=10% 时 **~90% AR 空读**；路径 α 的意义是 **β 只触达置位 index**。

---

## 2. 假设与口径（先写；缺参标待核实）

### 2.1 冻结参数表

| 参数 | 符号 | 工作假定 | 状态 |
|------|------|----------|------|
| 条目（槽）个数 | `N` | 4096 | **假设** |
| 单条 payload 宽度 | `W_rec` | 128 bit（16 B） | **假设** |
| 有效稀疏度 / 占用率 | `ρ` | 高 ρ：0.4～0.8；低 ρ：0.02～0.15 | **假设** |
| AXI 数据位宽 | `W_axi` | 256 bit（32 B/beat） | **假设** |
| READ outstanding | `RO` | 8 | **假设** |
| WRITE outstanding | `WO` | 4 | **假设** |
| DDR 控制器类型 | — | Xilinx/AMD MIG（AXI4 Full slave） | **待核实** |
| 扫描模式 | — | **增量游标**（next-valid）为主；**一次性全表** 为快照子模式 | **假设** |
| bitmap 与 payload 时钟 | — | 同域；CDC **待核实** | **待核实** |
| 原子 alloc/free | — | 单写者 FSM | **假设** |
| merge 最小 run | `L_min` | 低 ρ：∞（不 merge）；高 ρ：4 槽 | **假设** |
| 扫描 word 宽 | `W_word` | 64 bit | **假设** |

### 2.2 稀疏度分档（本报告结论口径）

| 档位 | ρ 范围 | 有效槽数（N=4096） | 路径 α 热点 | 路径 β 热点 |
|------|--------|-------------------|-------------|-------------|
| **高稀疏** | ≤0.15 | ≤614 | 跳空 word、summary | **单 index AR** 为主 |
| **中稀疏** | 0.15～0.4 | 614～1638 | word scan + 游标 | 短 run merge 可选 |
| **低稀疏** | ≥0.4 | ≥1638 | 全 word 几乎非零 | **run-merge burst**、分段全表 |

### 2.3 证据标注

- **事实：** AXI4 规范、AMD PG、可核对公开文档。
- **推断：** 默认组合、相对倍数、`L_min` 工程取值。
- **待核实：** MIG bank 映射、IP outstanding 上限、narrow read 行为。

---

## 3. 地址映射与路径协同（机制四问之基础）

### 3.1 bitmap 与 payload 地址如何映射

**默认 SOA 线性映射（推断）：**

```
index i ∈ [0, N)

片上 bitmap:  bit[i] → BRAM addr ⌊i/32⌋ word, 位 i mod 32（或 64-bit word）

DDR payload:  addr_payload(i) = P_base + i × stride
              stride = align_up(W_rec/8, AXI_bytes)   // 典型 16→32 对齐

DDR bitmap 副本（可选）:
              addr_bitmap_byte(i) = B_base + ⌊i/8⌋
              与 payload **分区** 不同基址，避免同 row 争用 **推断**
```

| 布局变体 | payload 地址 | 路径 β burst | 备注 |
|----------|--------------|--------------|------|
| **SOA 数组** | `P_base + i×stride` | **最佳** | 默认 |
| **field-SOA** | `P_f + i×stride_f` 每字段 | 每字段独立 merge | 多 AR |
| **池化/按 bank 交错** | `P_base + (i mod B)×gap + ⌊i/B⌋×slot` | **差** | 连续 i 不连续地址 **推断** |
| **AOS** | `P_base + i×row_bytes` | 仅单槽 | 扫描场景 **否决** |

**4096 槽示例（假设 stride=16 B，P_base=0x1000）：** slot 10 → `0x10A0`；bitmap bit[10] → 片上 word[0] bit 10。

### 3.2 机制四问（每个方案必答）

| # | 问题 | 默认答案模板 |
|---|------|--------------|
| Q1 | bitmap 与 payload 如何映射？ | 见 §3.1；index **同 i**，物理地址 **异区** |
| Q2 | 连续有效位能否 INCR burst？ | **SOA 且 stride 固定**：run `[i,i+L)` 全 valid → 一条 AR len=L×stride/beat−1 **事实**（AXI INCR） |
| Q3 | 空洞多大放弃 merge？ | **低 ρ：空洞≥1 即拆**；**高 ρ：空洞≤3 且 run≥L_min=4 可 merge** **推断** |
| Q4 | 置位/清与 payload 写屏障？ | **alloc：payload 写完成→fence→set valid**；**free：clear valid→fence→清 payload**；快照 **epoch 或双缓冲** |

---

## 4. 冻结八维对比框架

以下 **每一行方案** 在 §5 综合表中填满八维 + 机制四问。

| 维度 | 问什么 |
|------|--------|
| **① bitmap 承载** | 片上 / DDR / 分层（summary+L2） |
| **② payload 布局** | SOA 数组 / 池化 / bank 交错 |
| **③ 扫描算法** | 逐字 popcount、分层 bitmap、游程（run） |
| **④ 有效→AXI 聚合** | 合 burst / scatter-gather 队列 / 分 outstanding |
| **⑤ 对齐与 4K 边界** | beat 对齐、burst 切段 |
| **⑥ bank/行冲突规避** | 分区、错相位、RO 深度 |
| **⑦ 读写比与更新频率** | 读多扫少 vs 写多 flip 频 |
| **⑧ 出处** | 事实/推断/待核实 |

---

## 5. 方案分类与机制深挖

### 5.1 路径 α：bitmap 承载

#### A0 片上 authoritative（默认）

| 项 | 内容 |
|----|------|
| ① 承载 | BRAM/URAM 全量 + 可选 **64-bit summary**（每 64 槽 1 bit） |
| ③ 扫描 | **增量游标**：`find_next_bit(cur)` word-at-a-time **事实**（Linux 同构） |
| Q1 映射 | 片上 only；DDR 可选 `B_base` 副本 |
| Q2 burst | α **无 AXI**；audit 时 DDR bitmap 可 **单次 512B INCR** |
| Q3 空洞 | summary **跳过 64 空槽块**；word=0 不进入 popcount 细扫 |
| Q4 屏障 | set/clear **1 cycle**；与 β 顺序见 §5.4 |
| ⑦ 更新频 | 每 alloc/free 1 flip；write-through 至 DDR 可 **合并 byte 写** |
| ⑧ | IIT TTO **事实**；UG473 **事实** |

#### A1 DDR bitmap（无片上）

| 项 | 内容 |
|----|------|
| ① 承载 | DDR `B_base..` 512B（N=4096） |
| ③ 扫描 | 全表：**1× burst 读 bitmap** → 片内 popcount；增量：**cache 1 word**，miss burst |
| Q2 burst | **512B 单次 INCR**（256b 宽 ≈16 beat）**推断** |
| Q4 屏障 | RMW byte 写 bit；与 payload **独立 AW** → 需 **fence** 保序 |
| ⑥ | bitmap 读与 payload 读 **同控器** → 错开相位 **待核实** |
| 翻车 | 高频 next-valid **每步多 DDR 读** |
| ⑧ | AXI4 **事实** |

#### A2 分层 bitmap（summary + 片上 L1 + DDR L2）

| 项 | 内容 |
|----|------|
| ① | summary 寄存器 + BRAM L1 + DDR L2 冷备份 |
| ③ | 先 summary **leading-zero**，再 L1 word，再 payload |
| 适用 | **N>64K** 或 **低 ρ 全表** |
| Q3 | summary 层 **64/256 槽** 一块；块内空洞走 word scan |
| ⑧ | Linux hierarchical bitops **事实**（概念对照） |

---

### 5.2 路径 α：扫描算法

| 算法 | 做法 | 增量游标 | 全表 | Q3 空洞 |
|------|------|----------|------|---------|
| **逐字 popcount + ffs** | 64b word，ctz 迭代 | **默认** | 扫 W=N/64 word | word=0 skip |
| **分层 bitmap** | summary→L1 | 块级 skip | 块并行 | 空块 skip |
| **游程编码（RTL 侧）** | 维护 **run table**（改 bitmap 时更新） | O(1) next | 重建成本高 | 无 merge 空洞问题 | **推断**；更新频高则亏 |

**禁止：** 路径 α 对 DDR **逐 bit** 或 **逐槽** 发 AXI。

---

### 5.3 路径 β：payload 布局与 AXI 聚合

#### B0 SOA + 合 burst（高 ρ 默认）

| 项 | 内容 |
|----|------|
| ② 布局 | `payload[i]` 连续 stride |
| ④ 聚合 | run 检测器：连续 valid index **合并一条 INCR AR** |
| ⑤ 对齐 | `P_base`、`stride` **32B 对齐** **假设**；跨 4KB **切 burst** **事实** |
| Q2 | run 长度 L，地址 `P_base+i×stride` 连续 → **一条 AR** |
| Q3 | **L_min=4**（高 ρ）；**L<4 或空洞≥1**（低 ρ）→ 单槽 AR |
| ④ outstanding | **ID_bitmap 预取** 与 **ID_payload** 分离 **推断** |
| ⑧ | AXI INCR **事实**；WP469 **事实** |

#### B1 SOA + 单 index AR（低 ρ 默认）

| 项 | 内容 |
|----|------|
| ④ 聚合 | **不合 burst**；每有效槽 1 AR（RO 流水线填谷） |
| Q3 | **任意空洞即不 merge** |
| ⑦ | 读多写少；β 命令率 ≈ **ρ×N**（全表）或 **1**（随机） |

#### B2 池化 / bank 交错（反例）

| 项 | 内容 |
|----|------|
| ② | `addr = bank[i mod B] + chunk` |
| Q2 | 连续 i **地址不连续** → **无法 INCR merge** |
| ④ | 仅 SG：** gather 队列** 多 AR（outstanding 打满） |
| 翻车 | 连续有效 **仍 N 次 AR** |

#### B3 Scatter-Gather（SG）队列

| 项 | 内容 |
|----|------|
| ④ | α 输出 index FIFO → β **最多 RO 个并行 AR** |
| 适用 | 低 ρ、valid **离散**；用 **深度 RO** 换 merge |
| ⑤ | 每 AR 仍受 **对齐/4KB** 约束 |

---

### 5.4 置位/清除与 payload 一致性

| 操作 | 顺序（推断） | 屏障 |
|------|--------------|------|
| **alloc(i)** | β: AW payload → **BRESP** → α: set valid | **写后 fence**；读者见 valid 时 payload 必完整 |
| **free(i)** | α: clear valid → **fence** → β: 可选 AW 清零 | 防读者见 valid 已删但 payload 旧数据 |
| **快照扫描** | 读 epoch；扫 α；若 epoch 变 **重扫** | 或 **双缓冲 bitmap** swap |
| **write-back 片上** | 脏 L1 + 外读 DDR bitmap | **flush 或禁止并发** |

**双缓冲（推断）：** 写方改 **B**，扫描读 **A**；swap 原子 → 无 fence 停顿；代价 **2× bitmap RAM**。

---

### 5.5 对齐、4KB、bank 直觉

| 规则 | 来源 | 实践 |
|------|------|------|
| burst 不跨 4KB | AXI4 **事实** | run-merge 在页边界 **切段** |
| ARSIZE = log2(beat_bytes) | AXI4 **事实** | 非对齐窄读 **待核实** SLVERR |
| stride×L 跨页 | — | 计算 **min(L, L_to_4K)** |
| bank 冲突 | MIG **待核实** | `P_base` 与 `B_base` **异区**；β 高 RO 时 α **错相位** |

---

## 6. 综合对比表（八维 + 机制四问）

| 方案 | ①bitmap | ②payload | ③扫描 | ④AXI聚合 | ⑤对齐/4K | ⑥bank | ⑦读写比 | Q1映射 | Q2 merge | Q3空洞 | Q4屏障 | ⑧ |
|------|---------|----------|-------|----------|----------|-------|---------|--------|----------|--------|--------|---|
| **默认 高ρ** | A0片上 | B0 SOA | popcount+游标 | run INCR | 32B/切段 | 异区 | 扫少读多 | §3.1 | **是** L≥4 | ≤3 可跳 | alloc/free fence | 推断 |
| **默认 低ρ** | A0+summary | B1 SOA | summary+ffs | 单 AR | 32B | 异区 | 随机读 | §3.1 | **否** | ≥1 拆 | epoch | 推断 |
| A1 DDR α | DDR | B0 | burst bitmap | β merge | 64B B_base | 争用 | audit | 异区 | β 同左 | 同左 | WT byte | 事实 |
| A2 分层 | summary+BRAM | B0/B1 | 分层 | SG/merge | 同左 | 同左 | 大 N | 分级 | 视 ρ | 块跳 | swap | 推断 |
| B2 池化 | A0 | 交错 | α 同 | **SG only** | 差 | **差** | — | 非线性 i | **否** | — | fence | 推断 |
| 内嵌 valid | 无 | AOS | 无 α | 逐行 | 行对齐 | — | — | 同行 | 否 | — | 简单 | 反例 |

**怎么找 next valid（α）：** 默认 **片上 64b word + mask + ctz**；低 ρ **+ summary**；全表 DDR audit **1 burst**。

**怎么减少空读（β）：** **仅读 set bit index**；高 ρ **run-merge**；低 ρ **RO 并行单 AR** 而非 merge。

**缺口/冲突：** 池化布局、同 row bitmap+payload 并行、write-back 脏读。

---

## 7. 默认推荐与翻车条件

### 7.1 稀疏度高（ρ≤0.15）— 更稳妥组合 **推断**

```
路径 α: BRAM bitmap + 64-slot summary + 增量游标（find_next_bit）
路径 β: SOA stride=align(16,32) + 单 index AR + RO=8 填流水线
聚合:   不 merge（L_min=∞）；空洞≥1 即独立 AR
一致性: alloc→payload→fence→valid；快照 epoch
DDR:    仅 payload 区；bitmap 可选 WT 副本
```

| 约束 | 值 |
|------|-----|
| outstanding | RO≥4，否则 β 流水线空泡 |
| 对齐 | stride **必须** 整除 beat 或接受 pad |

### 7.2 稀疏度低（ρ≥0.4）— 更稳妥组合 **推断**

```
路径 α: BRAM bitmap（summary 可选弱化）+ 增量/全表 word scan
路径 β: SOA + run 检测 merge burst（L_min=4）
聚合:   INCR；4KB 边界切段；RO=8，ID 分离
一致性: 同高 ρ；全表快照可双缓冲
```

| 约束 | 值 |
|------|-----|
| merge | run≥4 且 run 内 **全 valid**、地址连续 |
| 全表 β AR | ≈ **N/4** 量级（理想 merge）vs **ρN** 无 merge **相对** |

### 7.3 翻车条件（outstanding / 对齐 / 路径混用）

| 条件 | 路径 | 现象 | 处置 |
|------|------|------|------|
| **α、β 均 DDR 裸扫** | α+β | 每 next-valid **DDR 读 bitmap** + payload | α **拉回片上** |
| RO=1 | β | merge 无效，AR 串行 | RO≥4 |
| stride 非 beat 对齐 | β | narrow/slave 异常 **待核实** | pad stride |
| merge 跨 4KB 未切 | β | AXI 违规 **事实** | 软件切段 |
| 低 ρ 强行 merge | β | 合并逻辑 **空转** | L_min=∞ |
| 高 ρ 不 merge | β | AR **ρN 次** | 开 run 检测 |
| 无 fence alloc | α+β | 读半初始化 payload | payload→valid |
| write-back + DDR 读 bitmap | α | 脏数据 | flush / WT |
| 池化/bank 交错 | β | 连续 i 不连续 addr | 改 SOA |
| 增量游标与全表混用无 epoch | α | 漏/重 | epoch 或双缓冲 |

---

## 8. 工作示例

### 8.1 示例 A：低稀疏 + 增量游标（路径 α 片上 → β 单 AR）

**假设：** N=4096，ρ=0.05，**增量** next-valid；片上 A0+summary。

1. **α：** `cur=100` → summary[1..] 有 bit → word[2] **BRAM 1 cycle** → ffs→`i=137`；**0 AXI**。
2. **β：** `AR addr=0x1000+137×32`（stride 32B **假设**），len=0；**1 AR**。
3. 若 `i` 无效（TOCTOU）：epoch 变 → 重扫 **推断**。
4. **相对：** 无 bitmap 时对随机 slot **每查 1 AR**；无效 slot **0 AR**。

### 8.2 示例 B：高稀疏 + 全表快照（run-merge）

**假设：** N=4096，ρ=0.6，**一次性全表**；连续 valid run 平均 6 槽 **假设**。

1. **α：** BRAM 全 word scan，**0 AXI**；输出 index run：`[100,106), [200,205), ...`
2. **β：** run `[100,106)` → `AR base=0x1000+100×32, len=6×32/32−1=5` **一条 INCR**（不跨 4KB **假设**）。
3. **AR 次数：** ~0.6×4096/6 ≈ **410** merge AR **推断** vs 无 merge **2458**。
4. **空洞：** run 间 **空洞≥1**，**不跨 run merge**。

---

## 9. 与前序仓库交叉引用（Out 边界）

| 文档 | 关系 |
|------|------|
| [fpga-hw-orderbook-price-level-20260916-0838](../fpga-hw-orderbook-price-level-20260916-0838/report.md) | **档位 valid-bitmask、4096 槽** — 本报告补 **路径 α/β 分离 + AXI/DDR 吞吐**；**不重复** 档位业务语义 |
| 离散 DDR 加速泛化 | **另篇 Out**；此处仅 **索引级 SOA** 一句 |

---

## 10. 风险与待核实

| 项 | 类型 |
|----|------|
| MIG bank/row 映射、port 调度 | **待核实** |
| RO/WO IP 上限 | **待核实** |
| 16B payload on 32B beat narrow read | **待核实** |
| AXI atomic CAS | **待核实** |
| `L_min=4` 最优值 | **推断** |
| 绝对带宽/延迟 | **禁止未核实** |

---

## 11. 出处

| # | 来源 | 用途 | 标注 |
|---|------|------|------|
| 1 | [AMBA AXI4 (IHI 0022)](https://developer.arm.com/documentation/ihi0022/latest/) | INCR、4KB、outstanding、WSTRB | **事实** |
| 2 | [AMD PG058 AXI Reference](https://docs.amd.com/r/en-US/pg058-axi-ref) | 互联 outstanding | **事实** |
| 3 | [UG473 BRAM](https://docs.amd.com/r/en-US/ug473_7Series_CLB) | 片上 bitmap 容量 | **事实** |
| 4 | [UG573 URAM](https://docs.amd.com/r/en-US/ug573-ultrascale-clb) | 大 N | **事实** |
| 5 | [IIT TTO 2024 valid-bitmask](https://rndshowcase.iiit.ac.in/tto2024/TTO_website_data/PDF/25.pdf) | hybrid next-valid | **事实** |
| 6 | [Linux find_bit.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/lib/find_bit.c) | word scan 对照 | **事实** |
| 7 | [fpga-hw-orderbook-price-level-20260916-0838](../fpga-hw-orderbook-price-level-20260916-0838/report.md) | 4096 槽 valid | **事实** |
| 8 | [Columbia Market Data Parser](http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf) | 稠密 valid | **事实** |
| 9 | [FPL17 mask table](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf) | mask/qty 分离 | **事实** |
| 10 | [MDPI FPGA order book](https://www.mdpi.com/2079-9292/12/3/520) | 片上结构 | **事实** |
| 11 | [WP469 AXI burst](https://docs.amd.com/) | INCR 效率 | **事实** |
| 12 | [AMD MIG PG](https://docs.amd.com/) | DDR 控制器 | **待核实** |

详见 [sources.md](./sources.md)。

---

*修订结束 · 双路径 α/β · 八维对比 · 机制四问 · 高/低 ρ 默认组合 · 禁未核实 ns/GB/s*
