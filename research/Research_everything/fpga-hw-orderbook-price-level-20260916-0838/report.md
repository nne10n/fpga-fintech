# FPGA 硬件订单簿：价格档位（Price Level）管理机制

**第二轮完整详尽报告（修订）** · Asia/Shanghai 2026-09-16 08:38

---

## 结论摘要（≤10 行）

1. 本题 **In：档位聚合层**（level aggregate）；**Out：** 档内 per-order 链、策略报单、会话/ITCH 栈、写死未核实 ns、RTL top/core 划分。
2. **默认组合（推断）：** 分侧 **BRAM/URAM 稠密槽** + 固定 tick **线性索引** `off=⌊(px−base)/T⌋`（或涨跌停 `Ap=Ald+(p−pld)/pt`）+ 字段 **`{agg_qty, order_cnt, valid}`**（px 隐含；不必存 `head`）。
3. **BBO/Top-N：** 热路径用 **寄存器 snapshot + 增量 tracker**；Publish 重时可配 valid-bitmask / tree reduction / hybrid 搜，避免每条消息扫全表。
4. **更新：** 新档/改量/删空均为 **单址 RMW**（典型 2-cycle 读-改-写流水线）；删空清 `valid` 并触发 **穿越 best 修复**。
5. **翻车换方案：** 空档占比高 → 价哈希/水平价链/Register Top-K+BRAM 冷存；窗越界无 rebase → rebase 或稀疏结构；`tick×价域` 超片上 → DRAM 行映射 + 片上两级 CACHE 或 tick 粗化。
6. **per-order 才需：** ref→(px,qty) 映射、`head`、档内 FIFO；档位层 **`order_cnt` 判空** 即可（FPL17 聚合简化）。
7. 下文按 **假设 → 机制分类 → 深挖 → 对比 → 推荐 → 容量示例 → 风险 → 出处** 展开；证据分 **事实 / 推断 / 待核实**。

---

## 一页纸速览

> 独立文件：[onepager.md](./onepager.md)（六维压缩表 + 冻结参数 + 决策要点）。

| 决策问题 | 一句话 |
|----------|--------|
| 默认承载+索引？ | 分侧 BRAM/URAM + 线性 tick 映射 + `{agg_qty,order_cnt,valid}` + 寄存器 BBO |
| 何时翻车？ | 高空档率、窗越界、tick×range 超 RAM、Top-K 过小、环形 mod alias |
| 推荐字段？ | 档位层三件套；显式 px 仅哈希/Top-K/DRAM；`head` 仅 per-order |

---

## 1. 假设与口径

### 1.1 范围 In / Out

| In | Out |
|----|-----|
| 档位承载、索引、字段、数据结构 | 档内 per-order 队列、撮合、Replace **状态机** |
| 新档 / 改量 / 删空档、穿越 best | 策略、报单 |
| 稀疏度、容量、Top-N vs 全深度（机制） | 会话栈、ITCH 逐字段解码 |
| 上游已解析 `px, qty, side` | 写死未核实绝对延迟 ns |
| `order_cnt` 作档位空否判据 | 完整 RTL 模块划分、top-core 接口 |

**术语：** **Level** = 同一 `(side, px)` 的聚合量；**Order** = 带 ref 的单笔（ref 表 Out，档位层只收 `(px, Δqty, Δcnt)`）。

### 1.2 冻结参数表

| 参数 | 符号 | 工作假定 | 状态 |
|------|------|----------|------|
| Tick size | `T` | 固定；可粗化（penny 桶） | **待核实**（按品种） |
| 价格下界 | `limit_lo` / `base` | 滑动窗 base 会话 latch；或 `limit_lo=0.9×OP` | **待核实** |
| 价格上界 | `limit_hi` / `base+W·T` | 与下界对称 | **待核实** |
| 窗口宽度 | `W` | 256–2048 槽/侧 | **待核实** |
| 单向最大有效档 | `N_eff` | `N_eff ≤ W`（稠密表） | **待核实** |
| 买卖表 | — | **默认分侧各一**；备选 `(sym≪⌈log₂W⌉)\|off` 合表 | **假设** |

### 1.3 证据标注

- **事实：** 公开 PDF/README/ADR 可核对描述。
- **推断：** 由多源机制归纳的选型建议。
- **待核实：** 缺参、论文摘要未展开、商业 IP 未公开部分。

---

## 2. 机制分类（六维）

以下按 **物理承载 | 地址索引 | 字段集 | 稀疏假设 | 更新路径 | 出处** 分类；每类至少一条可核对出处。

### 2.1 类 A：BRAM 稠密槽 + 滑动窗/绝对 tick 线性索引

- **承载：** 分侧或合表 BRAM；每槽一档。
- **索引：** `off=⌊(px−base)/T⌋`；Columbia penny：`off=⌊(px−base[sym])/100⌋`。
- **字段：** `{agg_qty, order_cnt, valid}`，px 隐含。
- **稀疏：** 有效档 **近 inside 连续或近密**；空槽可扫。
- **更新：** 1× RMW；删空 + 有界线性扫 valid。
- **出处：** [Columbia PDF](http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf) **事实**

### 2.2 类 B：BRAM 涨跌停全 band + 绝对 tick 枚举

- **承载：** 覆盖 `[limit_down, limit_up]` 每一 tick 的槽阵列。
- **索引：** `Ap=Ald+(p−pld)/pt`（FPL17 Eq.1）。
- **字段：** `{total_qty}` + 独立 **mask** 表。
- **稀疏：** 价域 **有界可枚举**（如 ±10% OP）；槽可空。
- **更新：** ±qty O(1)；best 用 parallel tree reduction 或 Top-5 bitonic cache。
- **出处：** [FPL17](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf) **事实**

### 2.3 类 C：寄存器 Top-K + BRAM write-only 冷存

- **承载：** K 槽 flip-flop `{px,qty}`；深档 BRAM 仅 write-only。
- **索引：** **排名 k∈[0,K−1]**，非 px→addr。
- **字段：** K 槽显式 px；冷存可 `{px,qty}` AOS。
- **稀疏：** **热档 ⊂ K** 且 inside 密集。
- **更新：** comparator 命中 RMW；miss 驱逐最远档入 BRAM。
- **出处：** [fpga-feed-handler](https://github.com/alchevrier/fpga-feed-handler) **事实**

### 2.4 类 D：URAM 槽表 + valid-bitmask

- **承载：** URAM 全深度 orderBook；独立 valid 位阵。
- **索引：** 绝对 `off` + `bitmask[off]`。
- **字段：** `{qty}` + valid bit。
- **稀疏：** **中等稀疏**，band 内多空档。
- **更新：** 删空清 bit；穿 best 用 **hybrid binary-linear** 在位阵上搜下一 valid off。
- **出处：** [IIT TTO 2024](https://rndshowcase.iiit.ac.in/tto2024/TTO_website_data/PDF/25.pdf) **事实**

### 2.5 类 E：DRAM/HBM 深档行 + 片上 Top CACHE

- **承载：** 片外按 px 映射行；片上两级 CACHE 管 BBO/快照。
- **索引：** `row = f(px)` 单调（摘要级 **待核实** 闭式）。
- **字段：** 行内 `{qty}`；CACHE 显式 top levels。
- **稀疏：** 深簿、`tick×range` **超片上**。
- **更新：** 片外 RMW 相对慢；热路径触 CACHE 不触 DRAM 读（**推断**）。
- **出处：** [ASAP 2024](https://doi.org/10.1109/asap61560.2024.00025) **事实**（摘要）

### 2.6 类 F：价哈希 / 水平价链（稀疏）

- **承载：** 哈希桶链或 px 排序 dummy node 水平链。
- **索引：** `h(px) mod M` 或链表 off。
- **字段：** **显式 `{px, agg_qty, order_cnt, valid}`**。
- **稀疏：** **高度稀疏**、tick 细或 gap 大。
- **更新：** 插链/ unlink；best 需 Top 缓存或链头。
- **出处：** [punt-engine](https://punt-engine.com/notes/the-architecture-of-a-pipelined-order-book) **事实**；[MDPI 2023](https://www.mdpi.com/2079-9292/12/3/520) **事实**（价节点层）

### 2.7 类 G：环形相对窗 mod m（近 touch 专用）

- **承载：** 长度 m 环形 buffer。
- **索引：** `idx=(px−offset) mod m`。
- **字段：** `{agg_qty, valid}`。
- **稀疏：** 仅 **极近 inside**；**alias 可接受**。
- **更新：** O(1) 改量；跨 m 边界 **cache rebalance**。
- **出处：** punt-engine **事实**

### 2.8 类 H：分侧合表浅簿（工程参考）

- **承载：** 256×82b BRAM/ sym。
- **索引：** `[0..127]` bid 降序，`[128..255]` ask 升序。
- **字段：** 显式 `{px, shares, order_count, side, valid}`。
- **更新：** 2-cycle RMW；BBO 周期 FSM 全扫描。
- **出处：** [08-fpga-order-book](https://github.com/adilsondias-engineer/08-fpga-order-book) **事实**

---

## 3. 各机制深挖

### 3.1 类 A：BRAM 稠密槽 + 滑动窗

**索引公式**

```
off = ⌊(px − base[sym]) / T⌋
addr = (sym_id ≪ ⌈log₂ W⌉) | off
px_implied = base[sym] + off × T
```

- **越界：** `px > base+W·T` 或 `px < base` → drop + ERR COUNT（Columbia **事实**）；fpga-feed-handler `filt_max`/`filt_base` 硬过滤（**事实**）。
- **rebase：** Columbia 标 stretch；**无 rebase 时窗 drift 必写错槽**（**待核实** 具体 RTL）。

**空档与穿越 best**

- 增量 **tracker FSM**（Columbia **事实**）：
  - bid：更新 px **>** best → 替换 best；
  - 更新 px == best 且 valid→0 → **从 best_off 向下扫** valid 直至命中；
  - ask 对称 **向上扫**。
- 扫描 **有界 W**；liquid 名 near inside 连续，实践中几步终止（Columbia **事实**）。

**更新路径**

| 事件 | 操作 |
|------|------|
| 新档 | cnt:0→1；qty=Δ；valid=1；RMW |
| 改量 | qty±=Δ；cnt 不变或 ±1；RMW |
| 删空 | qty=0；cnt=0；valid=0；触发 tracker 扫 |

**流水线：** Read-First 2-stage RMW（08-fpga **事实**）。dual-port 可 scan 与 update 并行（Columbia **事实**）。

---

### 3.2 类 B：涨跌停全 band + mask / reduction

**索引：** `Ap = Ald + (p − pld) / pt`（FPL17 **事实**）。

**空档：** 无效 tick 槽 qty=0；**mask[i]=(qty[i]>0)**。

**穿越 best / Top-N**

- **Parallel tree reduction** on `(mask & addr)` → max valid addr；深度 **O(log n) 级流水线**（FPL17 **事实**，相对复杂度，不写死 ns）。
- **Top-5 bitonic cache：** Trade/Publish O(1) 读 cache；Cancel 清空 cache 档时从 fixed tick 表 **补第 6 档**（**事实**）。
- **可选 next 链：** 每档 `next_valid_off`，clipped reduction 维护（§IV-B **事实**）。

**更新路径：** Add/Cancel 仅 `orderbook[Ap] ±= qty` + 同步 cache/链（HFOBU Algorithm 2 **事实**）。

---

### 3.3 类 C：Register Top-K + BRAM 冷存

**索引：** 非 px 映射；K 槽按 **价序排名** 存 `{px,qty}`。

**空档与穿越 best**

- 档 qty→0：cache **移位**填洞；若 best 槽空 → 从 side processor 遍历或 rebalance（Pipebomb **事实**）。
- fpga-feed-handler：**snapshot 读寄存器**，BRAM RMW 在 DATAFLOW **冷路径** FIFO 解耦（**事实**）。

**更新路径**

- 命中：comparator 树 O(1) 更新 qty。
- miss：驱逐 worst 档 **write-only** 入 BRAM（ADR-012 **事实**，deferred 设计）。

---

### 3.4 类 D：URAM + valid-bitmask + hybrid 搜

**机制：** 槽表在 URAM；`valid_bit[off]` 独立（类比 08-fpga valid_bits **事实**）。

**穿越 best：** topCache 中 px 被清空 → 在 bitmask 上 **hybrid binary-linear search** 找下一 valid off → 刷新 topCache（IIT TTO **事实**）；binary/linear 分界 **启发式，闭式待核实**。

**更新路径：** 改量 RMW URAM 槽；删空清 bit；**不** 遍历全 URAM（**推断**）。

---

### 3.5 类 E：DRAM 行映射

**机制（摘要）：** px 直接映射 DRAM 地址，**一次访问即定位价序**（ASAP 2024 **事实**）；片上 **两级 CACHE** 管 best/snapshot。

**空档：** DRAM 行仍占位；空档不释放行（**推断**）。

**热路径：** 避免随机 DRAM 读；更新可异步 write-combine（**推断**）。具体 addr 公式 **待核实**（仅摘要）。

---

### 3.6 类 F：价哈希 / 水平价链

**哈希索引（推断模板）：**

```
slot = h(px) mod M
while slot occupied and slot.px ≠ px: slot = probe(slot)
```

- **空档：** 删空 unlink 结点或清 valid；**无固定 off 空洞**问题。
- **穿越 best：** 哈希无序 → **必须** Register Top-K 或 **有序价链链头=best**（MDPI 水平链 **事实**）。

**水平价链：** dummy price node 按 buy 降序 / sell 升序；新档有序插入；best=链头（MDPI **事实**）。档内 vertical 单链 **Out**。

---

### 3.7 类 G：环形 mod m

**索引：** `idx = (px − offset) mod m`（Pipebomb **事实**）。

**空洞：** 无传统「空槽扫描」；**alias** 即语义空洞（两价同 idx）。

**穿越 best：** best 跨 m 倍数 → **整 cache 重建**（Pipebomb **事实**）。

---

## 4. 综合对比表（六维）

| # | 物理承载 | 地址索引 | 字段集 | 稀疏假设 | 更新路径代价 | 出处 |
|---|----------|----------|--------|------------|--------------|------|
| A | BRAM 稠密槽 | `⌊(px−base)/T⌋` | agg_qty,cnt,valid | 近密 | RMW + 有界扫 | Columbia |
| B | BRAM 全 band | `Ald+(p−pld)/pt` | qty + mask | 有界枚举 | RMW + reduction/cache | FPL17 |
| C | 寄存器 Top-K | 排名 k | px,qty | 热档⊂K | comparator + 驱逐写 BRAM | fpga-feed-handler |
| D | URAM + bitmask | 绝对 off | qty + valid bit | 中稀疏 | RMW + hybrid 搜 | IIT TTO |
| E | DRAM 行 | px→row | qty | 深簿超片上 | 片外 RMW + 片上 CACHE | ASAP24 |
| F | 哈希/价链 | h(px)/链指针 | px,agg_qty,cnt | 高稀疏 | 插删 + Top/链头 | punt-engine / MDPI |
| G | 环形 buffer | mod m | agg_qty,valid | 近 touch | O(1) 改量 + rebalance | punt-engine |
| H | BRAM 256 合表 | 128+128 侧 | px,shares,cnt,side,valid | 浅簿 | 2-cycle RMW + FSM 扫 | 08-fpga-order-book |
| I | BRH ladder | 量化 addr | is_buy,qty | 1K×step | 2-stage RMW；越界 drop | [BRH blog](https://hugobrh.dev/posts/Trademaxxer_Price_ladder/) |

> 表中延迟均为 **相对**（RMW / O(log n) / 有界扫）；**无出处 ns 一律不列**。

---

## 5. 默认推荐与翻车条件

### 5.1 默认推荐（推断）

| 层 | 选择 |
|----|------|
| 承载 | 分侧 **BRAM/URAM** 稠密槽 |
| 索引 | **固定 tick 线性**（滑动窗或涨跌停 band） |
| 字段 | **`{agg_qty, order_cnt, valid}`** |
| BBO | **寄存器 + 增量 tracker** |
| 布局 | **买卖分表**；多 sym 再 `(sym≪log W)\|off` |

### 5.2 翻车条件 → 换档

| 条件 | 换方案 |
|------|--------|
| `N_eff ≪ W` 且 RAM 满 | F / C / G（视 alias 容忍度） |
| 日波幅 > `W·T`，无 rebase | rebase 机制或 B / E / F |
| `tick×range` 超 BRAM/URAM | E（DRAM 映射）或 tick 粗化（Columbia penny **事实**） |
| 仅 Top-K 且热档 >K | 增大 K、D、或 A+bitmask |
| mod m alias 不可接受 | 禁用 G，回 A 或 F |

### 5.3 字段：档位 vs per-order

| 档位层推荐 | 仅 per-order |
|------------|--------------|
| agg_qty, order_cnt, valid | ref→(px,qty) 映射表 |
| px（哈希/Top-K/DRAM 时） | head, 档内链 |
| side（合表时） | last_update_ts（审计） |
| next_valid_off（可选，FPL17） | 撮合状态 |

---

## 6. 工作示例

### 示例 ① 滑动窗（相对市价锚点）如何映射地址

**场景（Columbia 口径，事实）：** 单 sym，penny 粗化 `T'=0.01 USD`，`W=2048`，`base` 自首 256 条 median latch = **$150.00**（ITCH 定点 `base_raw=1500000`，四位小数）。

| px (USD) | 计算 | off | 备注 |
|----------|------|-----|------|
| 150.00 | ⌊(150.00−150.00)/0.01⌋ | 0 | 窗内最低价槽 |
| 150.52 | ⌊0.52/0.01⌋ | 52 | 普通档 |
| 160.47 | ⌊10.47/0.01⌋ | 1047 | 窗内 |
| 170.49 | ⌊20.49/0.01⌋ | 2049 | **>2047 → 越界 drop**，ERR++ |

**合表 addr：** `addr = (sym_id ≪ 11) | off`（Columbia **事实**）。

**穿越 best（bid）：** 假定 `best_off=52`（$150.52）上最后一单撤空 → `valid[52]=0` → tracker 从 off=51,50,… **向下** 找下一 `valid=1`（如 off=50 → $150.50）→ 更新 BEST_BID 寄存器。**扫描上界 W**（Columbia **事实**）。

**与「相对 best 排名窗」区别：** Register Top-K（类 C）用 **排名 k** 而非 off；本示例是 **相对 base 的绝对 tick 窗**，base 可会话 rebase 以 **跟随市价带**（rebase RTL **待核实**）。

---

### 示例 ② 稀疏绝对价表：空洞与遍历

**场景（FPL17 band，事实）：** 涨跌停 band tick=0.01，pld=99.00，plu=110.00 → **1101 槽/侧**。有效档稀疏；槽 Ap 按 Eq.1 枚举，**空 tick qty=0**。

**空洞表示**

```
mask[Ap] = (orderbook[Ap] > 0)   // FPL17 Fig.4 事实
valid 与 qty 同步；无单独 order_cnt 时以 qty==0 为空（FPL17 仅 total_qty）
```

**删空：** Cancel 后 `orderbook[Ap]=0` → `mask[Ap]=0`；若 Ap 为当前 best → 需找下一 valid。

**遍历 / 找 next valid（bid 侧求最高 valid 价）**

1. **Tree reduction（FPL17 事实）：** 构造 `candidate[Ap] = mask[Ap] ? Ap : 0`；parallel `max` 树 → `best_Ap`；再读 `orderbook[best_Ap]`。Top-5：mask 掉已选 Ap，重复 5 次（**事实**）。
2. **线性扫（08-fpga 类，事实）：** 从当前 Ap 向 inside **逐步递减** Ap，2-cycle/步 BRAM 读，直至 `mask=1`。**上界 band 宽度**。
3. **Hybrid（IIT 类，事实）：** valid-bitmask 上先 **binary** 逼近区间，再 **linear** 扫邻近 bit；分界启发式 **待核实**。

**对比稠密窗（类 A）：** 同样有空洞，但 **W 较小**（2048 vs 1101×2）；Columbia 用 **tracker 增量扫**，FPL17 用 **reduction+cache** 摊销 Publish 成本——选型取决于 **快照频率 vs 更新频率**（**推断**）。

---

## 7. 容量估算示例（符号公式）

### 7.1 片上档位 RAM

```
Bits_chip ≈ S × (W_bid + W_ask) × W_entry

W_entry = w_qty + w_cnt + w_valid + [w_px]
```

**例 1（08-fpga，事实）：** S=8，W=256，W_entry≈82 → **8×256×82 ≈ 168 Kb**（README 称 ~2.5 KB/sym 量级）。

**例 2（Columbia，事实）：** 8192×64 b 共享 4 sym → **512 Kb** 量级。

**例 3（FPL17 band，事实）：** 单 sym 1101 tick × 2 侧 × w_qty；若 w_qty=32 → **~70 Kb/sym**（**推断** 位宽）。

### 7.2 何时超 BRAM（港大论文，事实）

```
N_tick ≈ (limit_up − limit_down) / T
      ≈ (2 × 0.1 × P_close) / T        // A 股 ±10% OP 口径
```

P_close=1771, T=0.01 → **N_tick ≈ 35,420** 槽/侧 → 单 sym 需 **URAM 或 DRAM**（S11 **事实** 数量级）。

### 7.3 Top-K 寄存器 vs 全表

```
Bits_top = 2 × K × (w_px + w_qty)     // 类 C
```

K=8, w_px=32, w_qty=32 → **512 b** 量级（**推断**），远小于全表——适用 **仅策略读 Top 档**（fpga-feed-handler **事实** 动机）。

---

## 8. 风险与待核实

| 项 | 说明 |
|----|------|
| rebase RTL | Columbia stretch；窗 drift 处理 **待核实** |
| hybrid 分界 | IIT/FPL2023 启发式 **待核实** 闭式 |
| qty==0 vs order_cnt | 无 cnt 时 partial-cancel 边界 **待核实** |
| DRAM addr 映射 | ASAP24 仅摘要 **待核实** |
| 商业 IP 内部布局 | NovaSparks、Algo-Logic **未公开** |
| 绝对 ns / BRAM 占比 | 论文有发表值但 **本报告 Out**；选型不写死 |
| mod m alias | Pipebomb **事实** 风险；策略需显式接受 |
| 多 sym 端口争用 | dual-port 规划 **推断** |

**反模式（节选）：** 稀疏簿满幅 tick 阵列；无 rebase 滑动窗；删空不清 valid；片外表无 Top 投影；档位层混档内 FIFO（MDPI vertical **Out**）。

---

## 9. 出处（≥10，可点击）

| # | 来源 | 标注 |
|---|------|------|
| 1 | [Columbia ITCH FPGA PDF](http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf) | **事实** |
| 2 | [FPL17 HFOBU PDF](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf) | **事实** |
| 3 | [fpga-feed-handler](https://github.com/alchevrier/fpga-feed-handler) | **事实** |
| 4 | [IIT TTO 2024 PDF](https://rndshowcase.iiit.ac.in/tto2024/TTO_website_data/PDF/25.pdf) | **事实** |
| 5 | [FPL 2023 Hybrid DOI](https://doi.org/10.1109/fpl60245.2023.00051) | **事实**（摘要） |
| 6 | [ASAP 2024 FPGA LOB](https://doi.org/10.1109/asap61560.2024.00025) | **事实**（摘要） |
| 7 | [punt-engine Pipebomb](https://punt-engine.com/notes/the-architecture-of-a-pipelined-order-book) | **事实** |
| 8 | [08-fpga-order-book](https://github.com/adilsondias-engineer/08-fpga-order-book) | **事实** |
| 9 | [MDPI Electronics 2023](https://www.mdpi.com/2079-9292/12/3/520) | **事实** |
| 10 | [BRH Price Ladder](https://hugobrh.dev/posts/Trademaxxer_Price_ladder/) | **事实** |
| 11 | [HKU HFOBU Thesis DOI](https://doi.org/10.14711/thesis-991013159956803412) | **事实** |
| 12 | [FPL17 DOI](https://doi.org/10.23919/fpl.2017.8056862) | **事实** |

抓取备注见 [sources.md](./sources.md)。

---

*修订说明：并入提示词大师 6 条约束——文首结论+速览、节序重排、两则工作示例、无出处数字删除/标待核实。*
