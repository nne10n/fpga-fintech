# FPGA 硬件订单簿：价格档位管理机制（一页纸）

## 1. 结论摘要（≤5 行）

**决策问题：** 档位层（level aggregate）怎么存、怎么找？

- **更稳妥默认：** **BRAM/URAM 承载 + 固定 tick 绝对价或滑动窗线性索引** + 字段 **`{agg_qty, order_cnt, valid}`**（`px` 可由槽址隐含；**不必**存档内 `head` 指针）。买卖 **各一侧独立表** 或 `(side, offset)` 合表均可（见假设）。
- **索引直觉：** `offset = ⌊(px − base) / tick⌋` 或 `⌊(px − limit_lo) / tick⌋`；单槽 RMW：`agg_qty ±= Δqty`，`order_cnt ±= 1`，`valid = (order_cnt > 0)`。
- **边界：** 本题 **只做档位聚合**；档内 FIFO/逐单链 **Out**——若上游按 ref 改量，档位层仅需 **`order_cnt` 判空**，不展开撮合状态机。
- **翻车换方案：** ① 有效档稀疏、空槽占比高；② 日波幅 **超出** 滑动窗 `W` 且 rebase 未实现；③ `tick × 价域宽度` 超 BRAM/URAM；④ 仅维护 Top-K 但热档常越界 K——改 **寄存器 Top 窗 / valid-bitmap+混合搜 / 价哈希 / 水平价链（仅价节点字段）**。
- **证据基调：** 下表机制来自公开 FPGA LOB 论文/专利/开源说明；无统一行业标准（**推断**）。

## 2. 背景（2–3 句）

硬件 LOB 常把软件 AVL+档内链表 **降为 per-price 聚合槽**，因档位更新是单址 RMW、利于 II=1。公开实现假定 **上游已给出 `(px, qty, side)`**（ITCH/会话解码 Out）。全深度与 snapshot 常 **片上档位表 + 寄存器 Top 投影** 分层，避免热路径扫空档。

## 3. 范围边界（In / Out）

| In | Out |
|---|---|
| 档位聚合：承载、索引、字段、稀疏度、改量/新档/删空档 | 档内 per-order 链、撮合、撤单/Replace **状态机** |
| Top-N 投影 vs 全深度槽表（机制） | 策略、报单 |
| 上游已解析 `px, qty, side` 前提下更新档位 | 会话栈、ITCH/二进制协议逐字段解码 |
| `order_cnt` 作为档位层「是否为空」字段 | 完整 RTL 模块划分、top-core 接口表 |
| 空档穿越 best 的扫描/缓存机制 | 未核实绝对延迟 ns |

**输入假设（缺参则按下表；标待核实）：**

| 参数 | 本文假定 | 状态 |
|---|---|---|
| tick size | 固定 `T`（可粗化，如 penny 桶） | 待核实（按品种） |
| 价域 | 滑动窗宽 `W` 槽，或涨跌停 `[limit_lo, limit_hi]` | 待核实 |
| 单向最大档数 | `N_max`（256–2048 量级） | 待核实 |
| 买卖表 | **默认分侧各一张**；亦见合表+side 字段选项 | 假设 |

## 4. 机制分类表

| 物理承载 | 地址索引 | 字段集 | 稀疏度假设 | 更新路径代价 | 可复现出处 |
|---|---|---|---|---|---|
| **BRAM 稠密槽表**（分侧或 `(sid≪W)\|off`） | **绝对价/滑动窗：** `off=⌊(px−base)/T⌋`；base 首批 latch（**待核实** rebase） | `{agg_qty, order_cnt, valid}`；px 隐含 | **满档密集**：有效档连续或近连续，空槽可扫 | **新档：** cnt=0→置 valid、qty=Δ；**改量：** RMW qty；**删空：** cnt→0 清 valid；**穿 best：** 从当前 best off **向下/上扫 valid**（有上界 W） | [Columbia ITCH 设计 PDF](http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf) **事实** |
| **BRAM 涨跌停全 band** | **绝对价：** `off=(px−limit_lo)/T` 枚举全 tick | `{total_qty}` per tick（FPL17） | 价域 **有界可枚举**，档可空 | 同上单槽 ±qty；Publish Top-5 不扫全表→配 **bitonic Top 缓存**；best 空→缓存重填 | [FPL 2017 HFOBU](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf) **事实** |
| **寄存器 Top-K 窗 + BRAM 冷存** | **相对 best 排名**（K 槽显式 `{px,qty}`，非全 px 映射） | `{px, qty}` AOS；BRAM 存深档 | **热档 ⊂ K** 且密集 | **改量：** K 内 comparator 命中则 RMW；**miss：** 驱逐最远档 **write-only** 入 BRAM；**穿 best：** 寄存器树更新，不读 BRAM | [fpga-feed-handler](https://github.com/alchevrier/fpga-feed-handler) **事实** |
| **URAM 槽表 + valid-bitmask** | **绝对 off** + ** bitmask[off]** 标记有效 | `{qty}` + 独立 valid 位阵 | **中等稀疏**：band 内多空档 | **删空：** 清 bit；**穿 best：** **hybrid binary-linear** 在 bit 阵上找下一有效 off→刷新 topCache | [IIT TTO 2024 PDF](https://rndshowcase.iiit.ac.in/tto2024/TTO_website_data/PDF/25.pdf) **事实** |
| **DRAM/HBM 深档表** | **绝对价→行址** 映射全 tick 范围 | `{qty}` per 址；Top 投影在片上 | 深簿、价域可枚举 | 片外 RMW 慢→**两级 CACHE** 管 best；空档仍占位；**推断：** 不宜热路径随机读 | [ASAP 2024 FPGA LOB](https://doi.org/10.1109/asap61560.2024.00025) **事实**（摘要） |
| **价哈希表（稀疏档）** | **`h(px) mod M`**，冲突链比对 px | `{px, agg_qty, order_cnt, valid}` 显式 px | **高度稀疏**：tick 细或 gap 大 | **新档：** 插链；**删空：** cnt=0 删结点；**穿 best：** 需 **有序结构或 Top 缓存**（**待核实** 全表最小价） | Columbia §3.1.3 stretch；[punt-engine 稀疏树选项](https://punt-engine.com/notes/the-architecture-of-a-pipelined-order-book) **事实/待核实** |
| **水平价链（仅价节点）** | **按 px 排序链表**，档内单链 Out | 价节点 `{px, agg_qty}` dummy；**无 head** 若纯聚合 | 稀疏且需 px 序 | **新档：** 有序插入；**删空：**  unlink 价节点；best = 链头 | [MDPI Electronics 2023](https://www.mdpi.com/2079-9292/12/3/520) **事实**（价节点层；垂直单链不展开） |

## 5. 常见惯例与注意点（5–8 条）

1. **档位层 vs 档内链：** 聚合槽只维护 **`agg_qty, order_cnt, valid`**；逐单 ref 映射 **Out**，但改量事件落到档位层时 **`order_cnt` 判空** 即可，**无需 `head`**（FPL17 聚合简化；Columbia 双结构仅作边界说明）。
2. **默认分侧表：** bid/ask 各 `N_max` 槽或 `[0..N−1]` bid 降序、`[N..2N−1]` ask 升序，避免 side 混扫（开源 256 档实现）。
3. **px 隐含 vs 显式：** 稠密 tick 映射可省略 px；哈希/寄存器窗需显式 px（上表）。
4. **删空档必清 valid**，并触发 best 修复：扫描、bit 搜或 Top 缓存（Columbia tracker；IIT bitmask）。
5. **滑动窗越界** 应计数/丢弃，勿 silent wrap（Columbia ERR COUNT）。
6. **AOS 单址** 优于 SOA（单索引 RMW 一次读，fpga-feed-handler **事实**）。
7. **热路径避免 BRAM 读-modify-写 hazard**：深档 write-only 入 BRAM，Top 在寄存器（fpga-feed-handler）。
8. **粗化 tick**（如 penny 桶）减槽数；sub-tick 精度 **Out** 于档位层（Columbia penny 桶）。

## 6. 坑与反模式（4–6 条）

1. **稀疏簿用满幅绝对 tick 阵列** → BRAM 空档浪费、best 扫描变长（punt-engine 动机）。
2. **无 rebase 滑动窗** → px drift 写错槽（Columbia 越界处理）。
3. **档位层混做档内 FIFO** → 指针 chase 破坏 II=1（MDPI 垂直链 **Out**）。
4. **片外深表无 Top 投影** → snapshot 随机读（ASAP 2024 两级 CACHE 反例）。
5. **删空未清 valid** → best 指向 ghost 档（惯例 4）。
6. **仅 Top-K 寄存器但热档分布 >K 且稀疏** → 频繁驱逐，深档失真（fpga-feed-handler 适用条件）。

## 7. 开放选项（2–4 个可选型方向，各一句话适用条件）

1. **BRAM + 滑动窗绝对 off（默认）：** `W×T` 覆盖日波幅、有效档近密、可 rebase/越界告警。
2. **Register Top-K + BRAM：** 快照/信号只读 K 档、消息率极高、可接受深档 write-only 延迟可见。
3. **DRAM 全 band + 片上 Top 缓存：** 涨跌停内 tick 可枚举、要全深度审计、热路径不触片外读。
4. **价哈希 / 水平价链 / valid-bitmap：** 空档占比高或 tick×range 超片上容量时切换。

## 8. 出处列表（≥6，可点击 URL）

1. [Columbia ITCH FPGA — penny 窗口、档位字段、best 扫描](http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf)
2. [He et al., FPL 2017 — 涨跌停 fixed tick 聚合 + Top-5 cache](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf)
3. [fpga-feed-handler — Register Top-K、绝对价 comparator、BRAM write-only](https://github.com/alchevrier/fpga-feed-handler)
4. [IIT TTO 2024 — URAM 槽表、valid-bitmask、hybrid search](https://rndshowcase.iiit.ac.in/tto2024/TTO_website_data/PDF/25.pdf)
5. [ASAP 2024 — DRAM 价址映射、片上两级 CACHE](https://doi.org/10.1109/asap61560.2024.00025)
6. [punt-engine — 稠密环形窗 vs 稀疏树/Top 缓存](https://punt-engine.com/notes/the-architecture-of-a-pipelined-order-book)
7. [08-fpga-order-book — 分侧 BRAM、`{px,shares,order_count,side,valid}`](https://github.com/adilsondias-engineer/08-fpga-order-book)
8. [MDPI 2023 — 水平价节点聚合（档内链不展开）](https://www.mdpi.com/2079-9292/12/3/520)
