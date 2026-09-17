# E02 — 六维交叉对照（留证硬规则：每格绑 S?+路径）

**标注：** 事实 / 推断 / 待核实  
**规则：** 无路径的格不写入；数字必须来自该路径原文。

| ID | 物理承载 | 地址索引 | 字段集 | 稀疏假设 | 更新/穿best | 出处路径 | 标注 |
|----|----------|----------|--------|----------|-------------|----------|------|
| A | M10K 8192×64b 共享 | `(sym<<11)\|⌊(px-base)/100⌋` | agg_qty32,cnt16,v1 | 2048 penny=$20.48 窗 | RMW；tracker 下/上扫 | S1 §3.1.3; Table 2 | **事实** |
| B | BRAM 每 tick 槽 | `Ap=Ald+(p-pld)/pt` | total_qty; mask | [pld,plu] 枚举 | ±qty；reduction/cache | S2 §III Eq.1; §IV | **事实** |
| B′ | 同 B + next 链 | 同 B | qty; next_off | 同 B | clipped reduction | S2 §IV-B Fig.5 | **事实** |
| C | Reg 8槽/侧+BRAM WO | 排名 k | px,qty | 热⊂K | comparator；驱逐 | S3 `ADR-012` | **事实**（规划） |
| D | URAM+bitmask | abs off | qty; valid bit | NSE | RMW；hybrid | S4 Poster ABSTRACT | **事实** |
| E | DRAM 行 | px→row | qty; CACHE | 超片上 | 片外RMW | S6 摘要 | **事实**（摘要） |
| F | dummy 价链 | 水平链指针 | px + 聚合 | 高稀疏 | INSERT 遍历 | S9 §3 Fig.6 | **事实** |
| G | 圆环 m | `(px-off) mod m` | qty,v | inside only | rebalance | S7 §Bid processors | **事实** |
| H | BRAM 256×82b | [0..127]/[128..255] | px,sh,cnt,side,v | ≤256 | 2cyc RMW；FSM扫 | S8 README | **事实** |
| I | BRAM 1K×4B | quantize 5¢ | is_buy,qty30 | 1K step | 2stg；越界drop | S10 博文 | **事实** |
| **⊘S14** | sorted order array | 序插入 rank | order ID,P,Q | — | **非档位聚合** | S14 README Features | **事实**（边界） |

## 源间冲突归并

| 冲突 | 源 | 归并 | 标注 |
|------|-----|------|------|
| 档位存不存 px | S1 隐含 / S3 AOS 显式 | 稠密 tick→隐含；否则显式 | **推断** |
| 有无 order_cnt | S1/S8 有 / S2 无 | qty==0 可判空；cnt 为增强 | **事实**+**推断** |
| BBO 维护 | S1 tracker / S8 FSM | 深 W 用 tracker；浅 K 可 FSM | **推断** |

## 翻车映射（推断，无量化阈值）

| 条件 | 行 ID | 依据路径 |
|------|-------|----------|
| 稀疏高空档 | F,C,G | S7 sparse 文 |
| 窗越界 | A→rebase/F | S1 stretch |
| 超片上 | E | S6 摘要 |
| Top-K miss 多 | C→↑K/D | S3 ADR-012 |
| alias | 禁 G | S7 alias 句 |
