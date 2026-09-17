# FPGA 硬件订单簿：价格档位（Price Level）管理机制

**目录：** `fpga-hw-orderbook-price-level-20260916-1854/` · **仓：** Research_everything  
**修订：** 批量统一收紧（留证硬规则 + 证据分级 + 口径不变加厚）

---

## 结论摘要（≤10 行）

1. **In：** 档位聚合层承载、索引、字段、空档/穿越 best。**Out：** 档内 per-order 链、**策略报单**、会话/ITCH 栈、**未核实 ns**、**RTL top/core**。
2. **默认承载+索引（推断，口径同第三轮）：** 分侧 **BRAM/URAM 稠密槽** + `off=⌊(px−base)/T⌋`（S1 §3.1.3）或 `Ap=Ald+(p−pld)/pt`（S2 Eq.1）+ **`{agg_qty, order_cnt, valid}`**（S1 Table 2）。
3. **BBO：** 寄存器 snapshot + **增量 tracker**（S1 §3.1.3）；Publish 路径可用 **mask+reduction / Top-5 cache**（S2 §IV）或 **bitmask hybrid**（S4 Poster）。
4. **更新：** 单址 RMW；S8 `README.md` 载 **2-cycle Read-First**；删空 **清 valid/mask**（S1 Table 2；S2 mask 表）。
5. **翻车（推断）：** 稀疏高空档、窗越界无 rebase（S1 stretch）、tick×range 超片上（S6 摘要动机）、Top-K 过小（S3 ADR-012）、mod m alias（S7）→ F/C/D/E/G 或 rebase。
6. **per-order Out：** ref 表、`head`、档内 FIFO；档位层 **`order_cnt` 判空**（S1；S2 仅 total_qty 亦成立）。
7. **证伪边界：** S14 sorted **order array** 非档位聚合槽——勿与 S1/S2 默认混用（S14 `README.md` Features）。
8. 机制表/数字均绑 `sources.md` 可读路径；无路径则 **待核实** 或删。详表见 [`evidence/E02`](evidence/E02-six-dimension-crosswalk.md)。

---

## 一页纸速览

独立文件：[`onepager.md`](onepager.md)（六维压缩 + 默认/翻车 + 反例 S14）。

| 决策 | 一句话 | 主据 |
|------|--------|------|
| 默认承载+索引 | 分侧 BRAM + 线性 tick + `{agg_qty,order_cnt,valid}` | S1 §3.1.3；S3 ADR-004/005 |
| 翻车 | 稀疏、越界、超 RAM、Top-K 不足、alias | 见 §7.2 |
| 留证 | `sources.md` S1–S14；`evidence/E01–E03` | — |

---

## 1. 假设（先写）

| 参数 | 假定 | 标注 | 出处 |
|------|------|------|------|
| Tick `T` | 固定；可 penny 粗化 | **待核实**（按品种） | S1 `price_offset=⌊(px-base)/100⌋` **事实** |
| `base` / `limit_lo` | median latch / 0.9OP | **待核实** | S1 §3.1.3 **事实** / S2 §III **事实** |
| `W` | 2048 penny/sym（S1）；256/sym（S8） | **事实**（各源内） | S1；S8 README |
| 买卖表 | 默认分侧；备选合表 | **推断** / **事实** | S1 合表 **事实**；分侧为工程默认 **推断** |

### 1.1 In / Out

| In | Out |
|----|-----|
| 档位承载、索引、字段 | 档内 per-order、Replace 状态机 |
| 新档/改量/删空/穿 best | **策略报单** |
| Top-N vs 全深度（机制） | 会话/ITCH 解码 |
| 上游已解析 `px,qty,side` | **未核实 ns** |
| | **RTL top/core 接口** |

---

## 2. 字段决策（每支有出处）

| 决策 | 条件 | 字段 | 出处 | 标注 |
|------|------|------|------|------|
| px 隐含 | 稠密 tick 映射 | 不存 px | S1 Table 2；S2 §III | **事实** |
| px 显式 | AOS/浅簿/价链 | `{price,qty}` 或 dummy px | S3 ADR-004 `struct Level`；S8 README；S9 §3 Fig.6 | **事实** |
| 无 order_cnt | 仅 qty 判空 | `{total_qty}` + mask | S2 §III；S10 `mem[price]` | **事实** |
| 有 order_cnt | 判空/审计 | cnt16 | S1 Table 2；S8 README 82b 域 | **事实** |
| next 链 | Publish-heavy band | `next_valid_off` | S2 §IV-B Fig.5 | **事实** |
| AOS vs SOA | FPGA 单址 RMW | AOS 一址读 | S3 ADR-004 §Context | **事实** |

---

## 3. 机制分类（六维，逐格绑据）

> 全表副本：[`evidence/E02-six-dimension-crosswalk.md`](evidence/E02-six-dimension-crosswalk.md)

### 3.1 类 A — BRAM/M10K 滑动 penny 窗

| 维 | 内容 | 出处 |
|----|------|------|
| 承载 | 8192×64b，4 sym 共享 M10K | S1 §3.1.3 Resources；Table 2 |
| 索引 | `(sym_id<<11)\|off`；`off=⌊(px-base[sym])/100⌋` | S1 §3.1.3 |
| 字段 | agg_qty 32b, order_count 16b, valid 1b | S1 Table 2 |
| 稀疏 | 设计假定 liquid 名 day range < $20.48 窗 | S1 §3.1.3 Penny Granularity |
| 更新 | Add/Cancel/Delete → agg_qty±, cnt±, valid | S1 §3.1.3 Aggregate Updates |
| 穿 best | tracker：优价替换 / 同价刷新 / 空则向下扫 | S1 §3.1.3 Top-of-Book Tracking |

**越界（事实）：** 窗外 → STATUS sticky + ERR COUNT++，消息 drop；rebase/price hash = stretch（S1 §3.1.3 末段）。

### 3.2 类 B — 涨跌停全 band + mask/cache

| 维 | 内容 | 出处 |
|----|------|------|
| 承载 | 每 tick 一槽 | S2 §III Fig.3 |
| 索引 | `Ap = Ald + (p-pld)/pt` | S2 Eq.1 |
| 字段 | total_qty；mask=(qty>0) | S2 §III-B Fig.4 |
| 稀疏 | [limit_down, limit_up] 可枚举 | S2 §III-A |
| 更新 | `orderbook[Ap] ±= qty` | S2 Algorithm 2 L9/L16 |
| 穿 best | tree on `(mask&addr)`；Top-5 cache O(1) Publish | S2 §III-B；§IV-A |

**B′ 扩展：** per-Ap `next` 链 + clipped reduction（S2 §IV-B Fig.5）。

### 3.3 类 C — Register Top-K + BRAM write-only（S3）

| 维 | 内容 | 出处 |
|----|------|------|
| 承载 | 8 槽/侧 flip-flop `{price,qty}`（规划） | S3 ADR-012 §Decision |
| 索引 | 排名 k，非 px→addr | S3 ADR-012 |
| 更新 | comparator 命中 RMW；miss 驱逐 worst→BRAM WO | S3 ADR-012 |
| 穿 best | cache 移位填洞 | S3 ADR-012；S7 §Caching（Pipebomb 同类） |

**状态：** ADR-012 **deferred**；ADR-013 DATAFLOW fork **Done**（S3 `README.md` Roadmap）— 机制为 **事实**（文档），硅上实现 **待核实**。

### 3.4 类 D — URAM + bitmask + hybrid（S4）

| 维 | 内容 | 出处 |
|----|------|------|
| 承载 | orderBook in URAM；URAM 62.50% | S4 Logic Utilization 表 |
| 索引 | 绝对 off + bitmask | S4 ABSTRACT |
| 穿 best | topCache 清空 → hybrid binary-linear | S4 ABSTRACT |
| 闭式分界 | — | **待核实**（S5 全文未取） |

### 3.5 类 E — DRAM 行 + 两级 CACHE（S6 摘要）

| 维 | 内容 | 出处 |
|----|------|------|
| 承载 | px 映射 DRAM 行 | S6 摘要 contribution 1 |
| 穿 best | 两级 CACHE 管 BBO/快照 | S6 摘要 contribution 2 |
| row=f(px) 闭式 | — | **待核实** |

### 3.6 类 F — 水平 dummy 价链（S9）

| 维 | 内容 | 出处 |
|----|------|------|
| 价档位 | dummy order node 水平链 | S9 §3 Fig.6 文字 |
| per-order | vertical 时间链 | S9 §3（**Out**） |
| 穿 best | 链头 / 遍历 dummy | S9 §5.2 INSERT |

### 3.7 类 G — 圆环 mod m（S7）

| 维 | 内容 | 出处 |
|----|------|------|
| 索引 | `(px-offset) mod m` | S7 §Bid and ask processors |
| alias | 「$100,010.25 与 $100,000.01 同 idx」 | S7 同节原文 |
| 穿 best | k-best cache **rebalance** | S7 §Caching |

### 3.8 类 H / I — 工程浅簿

| 类 | 要点 | 出处 |
|----|------|------|
| H | 256×82b；addr [0..127]bid/[128..255]ask；BBO FSM 扫 | S8 README §Price Level Table, §BBO Tracker |
| I | 1K entry；5¢ step；越界 `write_enable=0` | S10 §Design Tradeoffs, §Basic Testbench |

---

## 4. 穿越 best 四路径（机制断言→出处）

| 路径 | 机制 | 出处 | 标注 |
|------|------|------|------|
| ① tracker | bid：优价替换；同价 valid→0 则 off−1..0 扫 valid | S1 §3.1.3 Top-of-Book Tracking | **事实** |
| ② reduction+cache | max(mask&addr) tree；Cancel 后 cache←第6档 | S2 §III-B；Algorithm 2 L20 | **事实** |
| ③ hybrid bitmask | topCache 清空 → binary-linear on bitmask | S4 ABSTRACT | **事实** |
| ④ FSM 全扫 | level 变更触发扫 256 档 | S8 README §BBO Tracker | **事实** |

**选型（推断）：** Publish 相对稀（S2 Table I 2–10/s）且 band 固定 → ②；更新为主且 W=2048 → ①；浅簿 K=256 → ④。

---

## 5. 综合六维对比表（每格绑 S?+路径）

| # | 物理承载 | 地址索引 | 字段集 | 稀疏假设 | 更新/穿best | 出处路径 |
|---|----------|----------|--------|----------|-------------|----------|
| A | M10K 8192×64b | `(sym<<11)\|⌊(px-base)/100⌋` | qty32,cnt16,v1 | liquid 日波 < $20.48 窗 | RMW；tracker 扫 | S1 §3.1.3; Table 2 |
| B | BRAM 全 tick band | Ald+(p-pld)/pt | qty; mask | 涨跌停可枚举 | ±qty；reduction/cache | S2 §III–IV |
| C | Reg 8×2 + BRAM WO | 排名 k | px,qty | 热档⊂K | comparator；驱逐 | S3 ADR-012 |
| D | URAM+bitmask | abs off | qty; bit | NSE 中稀疏 | RMW；hybrid | S4 Poster |
| E | DRAM 行 | px→row | qty; CACHE | 超片上 | 片外RMW | S6 摘要 |
| F | dummy 价链 BRAM | 链表 off | px + 聚合 | 高稀疏 | INSERT 遍历 dummy | S9 §3; §5.2 |
| G | 圆环 m | (px-off) mod m | qty,v | 仅 inside | O(1)；rebalance | S7 §Bid processors |
| H | BRAM 256×82b | 128+128 侧 | px,sh,cnt,side,v | ≤256 档 | 2cyc RMW；FSM 扫 | S8 README |
| I | BRAM 1K×4B | quantize(px,5¢) | is_buy,qty30 | 1K×5¢ 窗 | 2stg RMW；越界 drop | S10 博文 |
| **⊘** | sorted order array | 序插入 | order ID,P,Q | — | **非档位聚合** | **S14 README Features** |

---

## 6. 默认推荐与翻车（结论=默认+翻车）

### 6.1 默认（推断 — 口径未改）

| 层 | 选择 | 主据 |
|----|------|------|
| 承载 | 分侧 BRAM/URAM 稠密槽 | S1；S3 ADR-004 |
| 索引 | 线性 tick | S1 §3.1.3；S3 ADR-005 |
| 字段 | `{agg_qty, order_cnt, valid}` | S1 Table 2 |
| BBO | 寄存器 + tracker | S1 §3.1.3 |
| 越界 | drop + 计数 | S1；S3 ADR-005 Pre-conditions |

### 6.2 翻车 → 换档（推断）

| 条件 | 依据 | 换方案 |
|------|------|--------|
| band 内有效 tick 比例低 | S7 称 sparse 圆环「full of zeroes」 | F / C / G |
| px 超 `base±$10.24` 且无 rebase | S1 stretch 文 | rebase 或 S1 价 hash |
| tick×range 超片上 | S6 摘要动机 | E 或 S1 penny 粗化 |
| 8 槽 Register 常 miss | S3 ADR-012 | ↑K 或 D |
| mod m alias 不可接受 | S7 alias 原文 | 禁用 G → A/F |
| Publish 热于更新 | S2 Table I Publish 2–10/s | B cache 路径 |

*删除无出处量化阈值（如「空槽 >70%」）。*

---

## 7. 工作示例（数字均来自出处）

### 示例 ① S1 penny 窗

- `W=2048` penny/sym（S1 §3.1.3「2048 penny entries per symbol」）
- `base` latch 后：px=150.00 → off=0；px=150.52 → off=52
- px 使 off=2049 → 越界 drop（S1「outside the ± $10.24 window」— 2048×$0.01=$20.48）

### 示例 ② S2 band

- pld=99.00, plu=110.00, pt=0.01 → 1101 tick（S2 §III 文「1101」量级 — 由 (110−99)/0.01+1 **推断** 核对）
- Cancel 后 qty=0 → mask=0；找 best → Fig.4 reduction

### 示例 ③ S7 alias（原文，不自行算 mod）

> 「if we index $100,010.25, we will get the same quantity as we did for $100,000.01」（S7 §Bid and ask processors）

---

## 8. 容量（仅转述出处数字）

| 实例 | 计算 | 出处 |
|------|------|------|
| S8 | 8 sym × 256 × 82 b | S8 README §Price Level Table |
| S1 | 8192 × 64 b 共享 | S1 Table 2 + §3.1.3 |
| S4 | URAM util 62.50% | S4 Poster 表 |
| A 股全 tick | — | S11 **待核实** |

---

## 9. 证伪/边界（S14）

S14 `README.md` Features：**「Sorted bid/ask arrays」** + 逐单 ID/价/量 + delete compaction — **无** `(side,px)` 聚合槽。说明：

- 档位聚合（S1/S2）≠ sorted order array（S14）
- 本题 **Out** 档内链；S14 整架构 **不** 作为档位层默认

---

## 10. 风险与待核实

| 项 | 说明 |
|----|------|
| S1 rebase RTL | stretch，**待核实** |
| S5/S4 hybrid 分界 | **待核实** |
| S6 DRAM f(px) | **待核实** |
| S8/S14 RTL 源 | 本轮仅 README，**待核实** 与文档一致 |
| 反模式 | 稀疏满幅 tick（S7 动机）；删空不清 valid（S1 tracker 前提） |

---

## 11. 出处

[`sources.md`](sources.md) — S1–S14（≥10 URL）。留证：[`evidence/`](evidence/)。

---

*收紧修订：对比表逐格绑路径；删无出处密度；增 S14 证伪专节；开源补 ADR/README 路径；口径与第三轮默认方案一致。*
