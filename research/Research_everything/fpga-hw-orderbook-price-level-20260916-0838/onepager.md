# 一页纸速览：FPGA 档位聚合层

**Asia/Shanghai 2026-09-16 08:38** · 仅 level aggregate · 上游已给 `(px, qty, side)`

## 结论（≤10 行）

1. **默认：** 分侧 **BRAM/URAM 稠密槽** + **`off=⌊(px−base)/T⌋`**（或涨跌停 `Ap=Ald+(p−pld)/pt`）+ **`{agg_qty, order_cnt, valid}`**；px 可隐含。
2. **BBO/Top-N：** 寄存器 snapshot + **增量 tracker**（或 valid-bitmask）；热路径不扫全表。
3. **改量：** 单址 RMW：`agg_qty±=Δ`，`order_cnt±=1`，`valid=(order_cnt>0)`；**不需**档内 `head`。
4. **删空 / 穿 best：** 清 valid → 从 `best_off` **有界线性扫** 或 bitmask **hybrid 搜** / tree reduction（Publish 重时）。
5. **翻车换方案：** 空档占比高 → 哈希/价链/Top-K+冷存；窗越界无 rebase → rebase 或稀疏结构；`tick×range` 超片上 → DRAM 映射+片上 CACHE。
6. **per-order 才要：** ref 映射表、`head`、档内链；档位层 **`order_cnt` 判空即可**。
7. **Out：** 策略报单、会话栈、写死 ns、RTL top/core。

## 六维机制表（压缩）

| 承载 | 索引 | 字段 | 稀疏假设 | 更新代价 | 出处 |
|------|------|------|----------|----------|------|
| BRAM 稠密槽 | 滑动窗/绝对 tick | agg_qty,cnt,valid | 近密 | RMW+有界扫 | [Columbia](http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf) |
| BRAM 全 band | 涨跌停枚举 | total_qty+mask | 有界枚举 | RMW+reduction/cache | [FPL17](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf) |
| 寄存器 Top-K | 排名 k | px,qty | 热档⊂K | comparator+驱逐 | [fpga-feed-handler](https://github.com/alchevrier/fpga-feed-handler) |
| URAM+bitmask | 绝对 off | qty+valid bit | 中稀疏 | 清 bit+hybrid 搜 | [IIT TTO](https://rndshowcase.iiit.ac.in/tto2024/TTO_website_data/PDF/25.pdf) |
| DRAM 行 | px→行址 | qty | 深簿 | 片外慢+片上 CACHE | [ASAP24](https://doi.org/10.1109/asap61560.2024.00025) |
| 价哈希/价链 | h(px)/有序链 | px,agg_qty,cnt | 高稀疏 | 插删链+Top缓存 | [punt-engine](https://punt-engine.com/notes/the-architecture-of-a-pipelined-order-book) |

## 冻结参数（缺则标待核实）

| 参数 | 工作假定 |
|------|----------|
| tick `T` | 固定；可 penny 粗化 |
| 窗/界 | `W` 槽滑动窗，或 `[limit_lo, limit_hi]` |
| 单向最大档 | `N_max ≤ W` |
| 买卖表 | **默认分侧各一** |

详见 [report.md](./report.md)。
