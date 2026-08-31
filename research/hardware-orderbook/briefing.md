# FPGA 硬件行情订单簿：产品与核心设计思路

调研日期：2026-08-31（Asia/Shanghai）  
范围：FPGA / FPGA NIC **上真正建簿或维护簿**（LOB / book building），不含 tick-to-trade、风控、ML。  
证据规则：不编造数字、产品名、论文标题或架构细节；每条具体主张附 URL。主张按 **厂商宣传 / 专利 / 论文 / STAC 审计** 标注。

---

## 0. 先把边界钉死：什么不是订单簿

**STAC-T0 13.9 ns 不是订单簿。** STAC-T0 把被测系统当黑盒，重放合成 UDP，包内有一个不可预测的 uint64 “index”代替价格/方向/数量；SUT 不做交易逻辑、也不做市场协议解析；核心指标 ACTIONABLE.LAT = tFO − tIND（index 最后一比特到出站 TCP 第一比特）。规格说明写明：“without the SUT performing any trading logic or market-specific protocol handling”。2024-04 的 Exegy/AMD 结果是 **Exegy nxFramework + nxTCP-UDP-10g-ULL IP 跑在 AMD Alveo UL3524 上的网络 I/O**，最小 actionable 13.9 ns（507 字节帧）。这是 MAC/PCS/TCP 路径，不是 parse → book → BBO。

**L1 交换机不是订单簿。** Exegy Nexus 把嵌入式 L1 crosspoint 用作 fan-out；LDA 卖 fair multicast / MAC-PCS。它们解决分发抖动，不维护价格档。

**硬件 TCP 栈不是订单簿。** nxAccess 的 Full Hardware TCP Stacks、LDA Lightspeed TCP 是报单路径。

**交易所 FPGA 行情通道多数也不是客户侧建簿。** Nasdaq TotalView-ITCH FPGA 版与软件版 **payload 相同**，差别是未整形/未限速的确定性分发；ISE/GEMX/MRX Depth FPGA（2025 滚动上线）同理。客户仍要自己（或 ticker plant）从增量消息重建簿。Nasdaq Eqlipse matching engine 公开数字是 door-to-door 14 μs / sub-40 μs，未声称客户侧 FPGA 建簿。

**AMD Alveo UL3524 本身不是订单簿产品。** 2023-09-27 发布的是 fintech 加速卡（自定义 Virtex UltraScale+、hardened transceiver、<3 ns FPGA transceiver latency）；合作方是 Alpha Data / Exegy nxFramework / Hypertec 机箱，不是现成 book IP。

---

## 1. 商业产品表

延迟一律标日期与口径。未写 STAC 的都是 **厂商自测**。

| 产品 | 簿是什么 | 市场/场所 | 延迟（日期 / 口径 / 性质） | 硬件 | 如何交给软件 | 证据性质 |
|---|---|---|---|---|---|---|
| **Exegy nxFeed**（原 Enyx） | FPGA NIC 上 **arbitrate / decode / normalize / build order books**；**book-based 与 order-based** 归一化；可按 symbol / message type / **book depth** 过滤 | 产品页指向 Global Market Coverage；2021 Enyx brochure 写 60+ exchanges | **2025-03 产品页/事实表：avg <1.2 μs，max <8 μs**，\*SOP-to-SOP measured on the switch\*。**2021 Enyx brochure 更激进：avg <1.0 μs，max <4 μs**（同口径，旧版） | “plug-n-play FPGA-based NIC”；2021 brochure：**Xilinx VUS+**。符号容量：2025 页 **16–250k / 卡**；2021 brochure **by-order 128k / by-price 256k / FPGA** | **PCIe 本地 C++ API**；或 **最多 8 路 UDP multicast**；TCP consumer resync | 厂商。非 STAC |
| **Exegy nxAccess** | **Embedded FPGA feedhandler with order book building**；另有 **pattern matcher** 跳过归一化/建簿，从 MAC/PCS 抽字段。Book-based 和/或 order-based；book depth filtering | 延迟数字针对 **CME** | **T2T（不是纯建簿）**：Hardware T2T w/ pattern matcher **389 ns**；w/o PM **624 ns**；Software T2T **1.5 μs**（SOP-to-SOP on switch, CME）。规格：最多 **8000 symbols** | FPGA 执行引擎 + feed handler；2 MB in-FPGA **order storage**（这是预置报单缓冲，不是行情簿） | 归一化数据同时给 **hardware & software trading logic**；PM 只给硬件 | 厂商。T2T ≠ 建簿时延 |
| **Exegy Nexus**（Q4 2025 上市，美股先发） | 托管 FPGA 一体机里做 **feed handling、preprocessing、book building、arbitration**；2026-04 事实表画了 **“Live order management & book building”** 和 Smart NIC 上 **“Order book aggregation & data distribution to memory”** | 事实表：Nasdaq, NYSE, Cboe, MEMX, MIAX, IEX | **<2.0 μs（UBBO-triggered trade），<270 ns（raw signal-triggered）** — 这是触发/交易口径，不是“更新一档的 ns”。另有 1 个 active polling thread、22–40% 机柜节省等 **厂商建模数字** | 1U/2U；最多 **8 张 PCIe FPGA 卡**；**AMD X3（行情）或 Bittware XUV-V8（执行/路由）**；嵌入 L1（8 QSFP in / 16 QSFP-DD out）；AMD Turin 单路 CPU。与 **LDA Technologies** 联合做机箱（2025-10-07） | **Shared-memory / direct-to-memory via Nexus NIC**；无轮询发布；API：config / resync / snapshots | 厂商。2026-04 事实表 |
| **Exegy Ticker Plant (XTP)** | **BBO 与 full-depth book views**；**User-defined BBO (UBBO)** 与 **Virtual Order Book**（跨市场组合） | **300+ feeds**，股/商品/衍生品/外汇 | “low microsecond latency remains consistent under load”（无更细 ns） | 2U 带 **patented FPGA**；入：4×10/40GbE；出：InfiniBand 或 RoCE 10/25/40/50/100Gb 或 TCP | **XCAPI (C/Java)** over **RDMA 或 TCP/IP** | 厂商产品单 2023-08。架构细节在专利（见下） |
| **NovaSparks NovaTick**（2026-01-14 被 Exegy 收购；官网多页现 404） | **纯 FPGA 建簿**；发布 **L1 (TOB) / L2 (Top N) / L3 (Full Depth) / full lot BBO**；2021-07 增加 **FPGA 多市场 consolidator**（读已归一化簿，出归一化簿或 BBO） | 产品材料：**75 feeds**（2021 稿写 70）；美股 CBOE/NYSE/Nasdaq + SIP 可在一台 appliance 上建簿并出 NBBO | **2016-11 STAC Summit 厂商幻灯（明确 \*not STAC benchmark\*）**，Nasdaq TotalView ITCH **全市场**：**10G multicast wire-to-wire 800 ns**（旧架构 1100）；**NovaLink wire-to-trading-FPGA-core 750 ns**；**PCIe DMA wire-to-server-memory 1250 ns**。分布：新架构 mean 773 ns / p99.9 1060 ns（10× replay, EOP-to-SOP 含 PHY/MAC）。2021-07：**TOB 更新到用户应用 <1 μs**（consolidator） | “largest FPGAs + array of memory chips”；最多 **4 颗大容量 FPGA** 矩阵；**Intel CPU 只做非延迟路径（exchange recovery 等）**。PCIe 卡或 appliance | Ethernet multicast、**PCIe DMA**、**NovaLink（FPGA-to-FPGA）**、无线/RF；snapshot for late joiners | 厂商。2016 数字偏旧；收购后官网不稳 |
| **Celoxica QDS** | **Full depth order book(s)**；line arbitrage、instrument filtering、normalisation、fully automated recovery、**multi-channel DMA** | 产品页：**80+ venues**，股/期货期权/固收 | 当前产品页 **无 ns 数字**。2017 Colt 合作稿写欧洲数据“consistent single-digit microsecond”（旧、且是归一化服务） | FPGA feed handler（页上未点名具体卡型） | **C++ API**；**multi-channel DMA** | 厂商功能清单。延迟证据弱 |
| **Algo-Logic Full Order-Book** | 单 FPGA：**维护 L3 订单级 + 默认 10 档 L2 + TOB + last trade**。L2 深度用户可配。小规模用片上存储；大规模用片外 DDR3 | 2013 材料：LSE 等；当前站另有 **exchange-side** “Full Order Book with aggregated in-memory matching engine” + KVS | **2013-11 STAC Summit 幻灯，标注 Not STAC Benchmarks**：**L3 <450 ns**；**L3+L2 <1 μs**；EMSE-2 **150 MSPS @ 10Gbps**。He 等 2017 文引用 Algo-Logic 官网当时数字 **<230 ns**（与 2013 幻灯不完全一致，以幻灯为准并记下歧义） | 2013：Altera V / Virtex-7；PLDA XP5、Terasic DE5Net、Nallatech P385、Bittware S5PH-Q、Solarflare AOE。IBM POWER8/CAPI 演示：Altera Stratix V A7 on Nallatech CORSA | AXI-4 Stream / Avalon（FPGA 内）；UDP；CAPI **把 128B L2 snapshot 写入 coherent shared memory**。当前 T2T 页是 CME 触发，不是独立建簿产品 | 厂商，材料偏 2013–2016。当前主推 T2T/交易所 matching |
| **华锐 FPGA 极速行情 D1** | 沪深 L2 **硬解**；数据类型：快照、逐笔委托、逐笔成交、**委托队列**。特色写 **“软硬融合……支持实时订单簿构建和 ETF IOPV 计算”** | 沪深股票/债券/基金/指数 | **实验室自测**：深市 FPGA 解码 **130 ns**、沪市 **210 ns**；公司级平台另写深市 **端到端 <10 μs**。这是 **解码/端到端分发**，不是单独的“建簿 ns” | 与 **AMD 高速行情平台融合部署**，“插卡即用”；组播发布 | 软硬同一套 **AMA API**；组播 | 厂商实验室。**“订单簿构建”是否在 FPGA 内完成，页上写的是软硬融合，不能当成纯 FPGA 全深簿** |
| **恒生 FPGA 极速行情 / 专利** | **公开产品**主打 FPGA **解码+组播**（深证 Binary 等），不是单独卖“FPGA 订单簿”。**专利**明确：FPGA 解码 → 重组 → **同步写入目标内存和目标缓存 → 在缓存内构建订单簿** | 沪深 + 五家期货交易所（产品介绍） | 2021 左右公开稿：FPGA 服务端解码全链路 **1.3 μs**（解码，非建簿）。期货 Nano+ 是切片频率 250 ms / 上期 4PS，与 LOB 无关 | 未在检索到的产品页点名具体 FPGA 卡 | 组播 / 与 LDP 软件栈 | **专利（2026-02-17 授权）确认公司有 FPGA 建簿方法**；**不能把 1.3 μs 说成建簿时延** |
| **盛立 EFH** | FPGA **处理交易所原始行情及发布**。DolphinDB 插件数据类型含 snapshot / order / execution / **tree（建树）** / ibrTree | 上交所、深交所 L2 | 公开文档 **无 FPGA 建簿 ns** | 招标材料称“沪深 FPGA 极速行情硬核版/软核版”（2026） | 组播；DolphinDB 插件订阅 | **“tree/建树”是 A 股行情类型（交易所或厂商发布的树/快照），不足以证明 FPGA 内维护全订单簿。** 建簿主张：未确认 |
| **LightTrader**（Rebellions+KAIST，HPCA 2023） | FPGA 交易管线里 **维护本地 LOB**（论文写 HFT 通常只留 **global LOB 的少数最低档** 以减存储）；offload engine 把 **10 档 bid/ask 的 price+qty** 做成 BF16 张量给 AI 芯片 | CME E-mini 回测 | 论文数字是 **DNN 推理 119–296 μs**，不是建簿 | Xilinx **Kintex UltraScale+ XCKU15P** + 2GB DDR4 + 4× AI ASIC；四 QSFP | 片上 L2$ / DRAM；PCIe 监控 | **论文**。簿是特征输入，不是产品级 ticker plant |

**明确不做（或未证实做）FPGA 订单簿的名字：**

- **LDA Technologies**：Nexus 机箱/L1/MAC-PCS/TCP；无独立 book 产品页。
- **Accolade ANIC**：抓包/分流 NIC；2022 Achronix 收购其网络 IP。不是建簿。
- **Cisco Nexus 3550 / Exablaze FDK**：给用户自己写 FPGA 逻辑的框架；无出厂 order book。GitHub Venturi 用 Exanic x10 在 FPGA 上做 **top-of-book** 属研究框架。
- **宽拓**：本轮检索 **没有** 可确认的 FPGA 订单簿产品页。
- **华云 HQM**：615 ns 是 **委托消息穿透（解析+推送）**，信创 FPGA 卡，不是建簿。

---

## 2. 核心设计思路（有出处，不是泛 CS）

公开 RTL/论文把流水线写得很清楚；厂商把同样的块藏在 API 后面。骨架一致：

**解析 → 品种映射 → 用 order-id 找回订单 → 更新价格档 → 更新 BBO/Top-N → 发增量或快照。**

Exegy 专利 US12211101B2（2025-01-28 授权，家族可追溯到 2008）把这条流水线写成 FPGA FAM 链：

`Message Parse → Symbol Map (hash) → ONPA（Order Normalization + Price Aggregation）→ [Interest/Entitlement Filter] → [Sorted View Update] → Message Format`

### 2.1 进簿之前：馈源处理

- **A/B 仲裁**：nxFeed / nxAccess 规格都写 **By-Message A/B feed arbitration**（逐消息，不是整包选路）。Celoxica QDS 写 line arbitrage。
- **序号缺口 / 恢复**：NovaTick **把 exchange recovery / retransmission 放在 Intel CPU**，FPGA 只管热路径；因此可以盘中晚加入并拿到“fully updated book”。nxFeed：**Exchange resynchronization** + **TCP-based consumer resynchronization**。Celoxica：fully automated recovery。Nexus API：resynchronisation / snapshots。
- **快照 vs 增量**：Nasdaq ITCH 是纯增量 + Glimpse 快照恢复（NovaTick 2014 发布稿同时提 ITCH 5.0 与 Glimpse 5.0）。A 股 L2 同时有 3 秒 10 档快照和逐笔；开源 AXOrderBook README 区分两种重建：**模拟撮合** vs **等待成交**（后者数据结构简单、集合竞价不能建、没有队列）。
- **品种过滤**：nxFeed/nxAccess 都有 Symbols / message type / **book depth** filtering。Nasdaq ITCH 的 Stock Locate 固定位置就是为了硬件过滤（交易所规范）。
- **价格归一**：Exegy ONPA 的 Price Normalizer 把变长价格打成 **64-bit，单位 billionths 或 256ths**（2 的幂用移位，10 的幂用 shift-add 流水）。nxAccess 写明 **Price & instrument normalization can be removed** 以再降延迟——这就是“完整性 vs 速度”的产品开关。

### 2.2 FPGA 上的簿结构

软件教科书是 **哈希(品种) → AVL/红黑树(价格) → 链表(同价订单)**。He 等 FPL 2017 把它标成 **不硬件友好**：Cancel/Publish 复杂度 O(log n + m)，FPGA 资源与抖动都差。后面所有严肃设计都在拆这棵树。

**A. 订单级查找：哈希 / 直接寻址，不是树**

- Exegy ONPA：每个活跃限价单一条 **limit order record**（内部 order id、价格、数量、属性…）；**order reference → 记录** 用 **H3 哈希 + chaining**；后续 modify/delete 只带 ref、不带 symbol 时，ONPA 做 **many-to-one** 回填 symbol/price/size（规范化）。哈希碰撞用链表；order engine 与 price engine **交错访问同一或分体 SDRAM** 掩盖延迟。
- Columbia CSEE 4840 Spring 2026（学生设计，非生产）：**16,384 槽开放寻址**，线性探测；槽 128 bit（valid + 64-bit ref + price + qty + side + symbol）；哈希 `h = ref[13:0] ⊕ [27:14] ⊕ [41:28]`；目标负载 ≤0.5；删除用 **backward-shift 而非 tombstone**（避免 MAX_PROBE 单调变坏）。映射 **M10K BRAM**。
- hugobrh.dev（2026-04 博文）：KC705、不用 DRAM，把 64-bit Nasdaq ref **压到 17-bit BRAM 地址**，演示级允许碰撞。

**B. 价格档：哈希聚合 vs tick 对齐数组**

- **价格聚合哈希（稀疏、全球市场）**：Exegy 为每个 (symbol, exchange, price) 维护 **regional price point record**（volume、order count、attribute 向量），另有 **composite** 跨市场聚合。Add 增加 volume/count，Delete 减少，档空则删记录；在增量事件上打 **price AMD（add/modify/delete 档位）** 给下游排序引擎减功。这对应 ITCH 这类 **价格几乎无界、tick 不固定** 的市场。
- **Fixed-tick 数组（A 股/中金所 ±10%）**：He 等 2017：**价格必须落在 [0.9 OP, 1.1 OP]**，tick 固定，于是 `addr = addr_limitdown + (p − p_ld)/tick`，**加/撤变成对数组元素做加减**。每个价位只存 **总数量**，不存每笔订单链表——因为交易所行情发布只要 (price, Σqty)。Liu 等 ASAP 2024 把同一思想推到片外：**价格档直接映射 DRAM 地址，一次 DRAM 访问完成“排序”**（排序被编址消掉）。
- **开源/教学的折中**：Columbia 2026 用 **每股 2048 个 penny 槽（窗口 $20.48）**，base 取前 256 笔中位数；窗外丢硬件、软件参考仍处理。这是 sparse tree 与 full tick 数组之间的 **有界窗口**。

**C. 排序与 Top-N：缓存，而不是每笔扫全簿**

- He：**Top-5 cache + bitonic sort（只排 5 个）+ clipped reduction tree** 维护“下一档”指针。没有 cache 时 Publish 深度是 **5 log n**（定流水线的最长路径）；有 cache 后 Publish O(1)，Add/Cancel/Trade 变成 log n − 1，**各路径深度被摊平**——这是 FPGA 延迟确定性的关键，不是渐近复杂度竞赛。FPGA2（Maxeler MAX4, Stratix-V 5SGSD8, 200 MHz, 48 GB DDR3）**Add 288 / Cancel 276 / Trade 260 / Publish 132 ns**（2017，CFFEX 日包）。
- Liu ASAP 2024：**两级 CACHE 管 BBO/快照**，延迟 **26–209 ns**，吞吐 **>3.26 Mmsg/s**（相对其软件对照 3.5–37.6× / 4.3–22.3×）。区间本身说明：命中 cache 的 BBO 更新和 miss 后走 DRAM 的档位更新不是同一个 ns。
- Exegy SVU（专利）：独立维护 bid/ask；两种实现都写了——**(1) 数组锚定在分配区底部、插入即 memmove，因绝大多数成交打在簿顶所以仍快；(2) B+ 树**，叶层链表便于 **refresh/snapshot**，header 里直接指针指向 leftmost = TOB。Price book 甚至用 **一棵 spliced 树合成 regional / composite / attribute-filtered / price-merged 视图**。输出事件带 **标量位置（第 3 档）或指向前一档的指针**，客户端 API 可以 O(1) 改镜像结构。
- Algo-Logic 2013：专有 **EMSE-2 搜索核 150 MSPS** 做 L3；L2 默认 10 档。IBM CAPI 演示则 **FPGA 建簿、只把 128B L2 snapshot 写进 CPU cache line**——典型的 **FPGA 深簿 + 主机只看顶**。
- LightTrader：**本地只留最低几档**；DNN 固定吃 10 档。这是产品化的 “Top-N in FPGA”。

**未在一手材料里看到、因此不要写进架构结论的：** 生产级 CAM 建簿、生产级 HBM 全市场 L3（AXOrderBook 的 HBM 是开源 HLS 实验；SEO 转载里的“150–200 ns / 30 万笔”与 GitHub README **对不上，忽略**）。

### 2.3 流水线与双路径

nxAccess 把设计张力做成两个产品开关：

1. **Normalized path**：仲裁 → 解码 → 归一 → **建簿** → 同时喂硬件策略和软件策略（完整市场视图）。
2. **Pattern matcher path**：MAC/PCS 上协议感知抽字段，**可关掉价格/品种归一**，只喂硬件（更短，但是“不是一本簿”）。

这与 STAC-T0 的哲学一致：最短路径根本不碰簿。

NovaSparks 2021 consolidator 是 **第二层 FPGA**：下面 70 个 feed handler 已经建好归一化单市场簿，上面再并成 NBBO/深度合成簿。Exegy XTP 的 UBBO / Virtual Order Book 是同一问题的托管一体机版本。

### 2.4 存储器：什么放 BRAM，什么溢到主机

| 层级 | 谁这么做 | 装得下什么 |
|---|---|---|
| **BRAM/URAM 热数据** | Columbia 2026：哈希表 ~230 个 M10K + 价格数组 ~64 M10K；GitHub 8-book demo：每品种 1024 单×130b + 256 档×82b | 少品种、有界深度、TOB |
| **片外 SRAM/DRAM 全深** | He：48 GB DDR3；Liu：价格→DRAM；Algo-Logic 2013：百万级挂单/上千品种用 DDR3；Exegy ONPA：SDRAM + 片上 cache 最近记录；NovaSparks：“array of memory chips” | 全市场 L3 / 全 tick 数组 |
| **HBM** | AXOrderBook 针对 Alveo U50 的 HLS（开源，非生产） | A 股千档实验 |
| **主机内存** | Exegy 专利 Fig.24：ticker plant 只出 **stream view**，**客户端 API 自己排序成 summary**；CAPI 演示只推 L2 snapshot；Nexus Smart NIC **直接 DMA 进应用内存** | 监管完整簿、多消费者、晚加入 snapshot |

**容量数字（厂商，勿与学术 ns 混用）：** nxFeed 16–250k 品种/卡（by-price 更密，因为不存每笔订单）；nxAccess 建簿路径 8k 品种（要在同一 FPGA 上再放执行引擎）。NovaSparks 2016-10 稿：当时 order-based 市场 **8,191 instruments**，并说新引擎是为继续扩容。

### 2.5 输出形态

- **BBO / L1**：所有厂商；He 的 Publish 就是 Top-5。
- **聚合 N 档 L2**：Algo-Logic 默认 10；LightTrader 10；Exegy price summary 可 **user-specified number of price points from top**。
- **L3 逐单**：NovaTick L3；Exegy order stream / order summary（价格+时间排序的逐单列表）；Algo-Logic L3。
- **合成/多市场**：NovaSparks FPGA aggregator；Exegy UBBO、spliced/aggregate price views、implied/FLASH 等 **attribute 过滤 + 同价合并**。
- **派生信号**：专利写 SVU 顶档变化可 **合成 quote 事件** 驱动 Level-1 last-value cache 和篮子 NAV——这是“簿的下游”，不是另一本簿。公开产品页 **没有** 把 imbalance/microprice 写成 FPGA 模块；不要脑补。

---

## 3. 2023–2026 学术 / 开源（非生产）

**Liu, Chen, Ma, Yang, Wan. “Real-Time Order Book Building and Snapshot Generating for High Frequency Trading on FPGA.” IEEE ASAP 2024, Hong Kong, 2024-07-24–26, pp. 71–76.**  
doi: [10.1109/asap61560.2024.00025](https://doi.org/10.1109/asap61560.2024.00025)  
贡献：价格→DRAM 编址消排序；两级 cache 做 BBO/快照。延迟 **26–209 ns**，吞吐 **>3.26M msg/s**。机构署名 China Institute of Finance and Capital Markets。这是 2023–2026 窗口里最直接的“FPGA 建簿”论文；IEEE 页有摘要，全文需订阅。

**Yoo, Kim, et al. “LightTrader…” HPCA 2023.**  
FPGA 上有 LOB 更新与 10 档 offload，但论文主线是 AI ASIC + 调度。硬件：XCKU15P。不要把它报成 ticker plant 产品。

**He, Fu, Luk, Li, Yang. “Exploring the Potential of Reconfigurable Platforms for Order Book Update.” FPL 2017.**  
虽早于 2023，但是 Liu 2024 与 HKUST 2024 论文都还在引用的 **HFOBU / fixed-tick / top-5 cache** 源头。对比表里 NovaSparks 被写成 880–1500 ns（当时新闻稿），He 的 FPGA2 132–288 ns —— **市场不同（中金所 vs 全球 ITCH）、测法不同，不能当排名**。

**Columbia CSEE 4840：** 2024 HFT Book Builder 被 2026 组批评为数据走了 ARM/TCP；2026 Market-Data-Parser 设计文档把 **哈希订单表 + penny 价格数组 + 增量 BBO tracker** 写到寄存器级。教学，非生产。

**GitHub（非生产，只采用其自述架构）：**

- [fpga2u/AXOrderBook](https://github.com/fpga2u/AXOrderBook)：A 股逐笔重建、千档、Python 模型 + Vitis HLS / Alveo U50。README **没有** 给出 150 ns 这类数字。
- [adilsondias-engineer/08-fpga-order-book](https://github.com/adilsondias-engineer/08-fpga-order-book)：8 本并行 BRAM 簿、256 档、BBO FSM；自述 ~12–17 周期/消息。
- hugobrh.dev 2026-04：BRAM 订单追踪 + 价格阶梯，cocotb vs golden model。

HKUST 2024 学位论文（doi [10.14711/thesis-991013159956803412](https://doi.org/10.14711/thesis-991013159956803412)）指出：HFOBU 吃内存（与涨跌停宽度成正比），BRAM 不够放多品种时把簿放到 **PS 侧内存**，并比较多种 top-5 读延迟——印证“全深 vs 延迟 vs 资源”三角。

---

## 4. 设计张力（有产品/论文对应）

**全深 vs 延迟。** 同一条 FPGA 流水线被最长路径卡住：He 证明若不做 Top-N cache，Publish 的 5 log n 会拖死 Add。Liu 的 26–209 ns 带宽就是 cache 命中 vs DRAM。厂商用产品开关表达同一件事：NovaTick 可选 L1/L2/L3；nxFeed 可滤 **book depth**；nxAccess 可完全绕过簿走 pattern matcher（389 vs 624 ns T2T，厂商，CME，含执行）。监管/合规要 L3 完整重建；HFT 做市往往只要 BBO + 几档 + 确定性。

**多市场合成。** 单市场建簿已经是哈希+DRAM；再并 NBBO 是 **第二级 FPGA**（NovaSparks 2021）或 XTP Virtual Order Book。合成引入“哪一路迟到就算缺口”的恢复问题，比单源 A/B 更脏。

**24×5 / 晚盘 / 盘中加入。** Exegy 2026 博客把 24/5 当成容量与恢复压力；NovaTick 明确 **late joiner snapshot + CPU 上的 exchange recovery**。FPGA 热路径不做 TCP 重传是有意的。

**25G/100G 馈源。** XTP 输出已列 10–100G RoCE/TCP；Nasdaq ITCH FPGA 要求 Carteret **10G 或 40G**（未整形流量）。Nexus 用 QSFP/QSFP-DD + L1。建簿逻辑的时钟域和 DRAM 口比 10G MAC 更容易先饱和——厂商很少把“100G 线速全 L3”写进可引用规格。

**缺口恢复 vs 热路径确定性。** 共同模式：**FPGA 丢包即标脏，CPU/会话层拉 snapshot/retransmit，再灌回 FPGA 簿。** nxFeed 把 consumer resync 做成 TCP API；Celoxica “fully automated recovery”。没有一家在公开材料里声称 FPGA 内跑完整重传协议来补 L3。

**监管完整 vs HFT TOB。** XTP 同时订 BBO 和 full-depth；Nexus 号称同一套分给做市和合规/时序捕获。这是 **一份 FPGA 簿、多种视图**，不是两套物理簿。代价是 ONPA 必须同时打 order 流和 price 流（Exegy 专利）。

---

## 5. 不确定与证据等级

1. **NovaSparks 官网在 2026-01 收购后大量 404**（本轮 WebFetch 对 `/novatick/`、`/ticker-plant/`、aggregator 新闻均 404）。数字回退到 2016 STAC Summit PDF、2016/2021 新闻稿镜像。收购后 NovaTick 是否并入 Nexus 未在 Exegy 稿里写明（Exegy 只说继续维护现有产品）。
2. **nxFeed 2021 vs 2025 延迟规格不一致**（1.0/4.0 vs 1.2/8.0 μs）。引用时必须带版本日期；可能是覆盖市场变多或测法变严，**不要取最小数字当 2026 现状**。
3. **没有任何公开 STAC 数字是“FPGA 建簿”**。STAC-T0 明确排除市场协议。厂商 ns 全是自测；学术 ns 是实验室工作负载（CFFEX 日包、或作者自备逐笔）。
4. **华锐“实时订单簿构建”** 写在“软硬融合” bullet 下，与 130/210 ns **解码** 数字并列但未说明簿在 FPGA 还是 CPU。稳健表述：确认 FPGA 硬解 L2；**FPGA 全深建簿未单独证实**。
5. **恒生**：产品是 FPGA 解码；**专利**才是建簿（缓存内构建）。专利摘要没有深度、没有 BRAM/DRAM、没有 ns。
6. **盛立 tree/建树**：A 股行情数据类型，**≠** 已证实的 FPGA LOB 引擎。
7. **Algo-Logic** 当前网站重心是 CME T2T 与交易所 matching KVS；2013 的 <450 ns L3 是否仍出货，无 2023–2026 产品页复述。
8. **Celoxica** 功能清单有 full depth book，**无架构白皮书、无延迟、无卡型**。
9. **Liu 2024 全文** 本轮未拿到 PDF（仅 IEEE 摘要 + 引用）。26–209 ns 与 DRAM 映射、两级 cache 来自摘要，细节（几档 cache、几只股票、哪块板）待全文。
10. 中文 SEO 转载给 AXOrderBook 编造的吞吐/延迟 **弃用**；只信 GitHub README。

---

## 6. 给调研专员的一句话结论

真正把 **订单簿建在 FPGA 里** 的商业线，2026 年能指着产品页说的，主要是 **Exegy 家族（nxFeed / nxAccess / XTP / 新 Nexus + 刚并入的 NovaTick）** 和 **Celoxica QDS（功能级，证据薄）**；Algo-Logic 有过完整 L3 IP 但公开材料停在上一代。中国厂商公开页几乎都是 **FPGA 解码/组播**，建簿要么写在“软硬融合”，要么写在 **2026 年恒生专利**，不要和 nxFeed 的 FPGA 全功能 ticker plant 画等号。

架构上没有魔法：ITCH/逐笔世界用 **order-id 哈希 + 价格聚合哈希 + 顶档排序结构（数组或 B+）**；涨跌停+固定 tick 的 A 股/期货用 **价格直接当地址的数组 + Top-N cache**。延迟来自 **把 Publish 从扫树变成读 cache**，以及 **恢复/全深/多市场放到 CPU 或第二级 FPGA**。STAC-T0 13.9 ns 是这条流水线左边的网卡，不是簿。

---

## 7. 来源（标题 + 日期 + URL）

1. Exegy, “nxFeed”, 产品页（访问 2026-08-31；规格与 2025-03 事实表一致）  
   https://www.exegy.com/products/nxfeed/
2. Exegy, “nxFeed” 产品事实表，2025-03  
   https://info.exegy.com/hubfs/Products/2025-03-OS-Exegy-FactSheets%20nxFeed.pdf
3. Enyx, “nxFeed” brochure v1.3, 约 2021-02（Xilinx VUS+；avg <1.0 μs / max <4 μs；128k/256k symbols）  
   https://www.enyx.com/wp-content/uploads/2021/02/nxFeed_Brochure_V1.3-WEB.pdf
4. Exegy, “nxAccess”, 产品页（访问 2026-08-31；CME SOP-to-SOP 389/624 ns / 1.5 μs；embedded book vs pattern matcher）  
   https://www.exegy.com/products/nxaccess/
5. Exegy, “Meet Exegy Nexus”, 产品页（访问 2026-08-31）  
   https://www.exegy.com/products/exegy-nexus/
6. Exegy, “Exegy Nexus Market Data Platform” 事实表, 2026-04  
   https://info.exegy.com/hubfs/2026-04-OS-Exegy-Exegy%20Nexus%20Market%20Data%20Platform.pdf
7. Exegy, “Unified Trading Infrastructure”, Nexus Q4 2025 美股、AMD X3 / Bittware XUV-V8  
   https://www.exegy.com/unified-trading-infrastructure/
8. Exegy, “Exegy and LDA Technologies Partner to Deliver Exegy Nexus”, 2025-10-07  
   https://www.exegy.com/exegy-partners-with-lda-technologies-to-deliver-nexus/
9. Exegy, “Exegy Acquires NovaSparks Inc.”, 2026-01-14  
   https://www.exegy.com/exegy-acquires-novasparks/
10. Exegy, “The Exegy Ticker Plant (XTP)” 产品单, 2023-08-24（BBO + full-depth；UBBO；RDMA/TCP；300+ feeds）  
    https://info.exegy.com/hubfs/XTP%20Product%20Sheet_08242023-1.pdf
11. Taylor et al., US12211101B2 “Method and apparatus for high-speed processing of financial market depth data”, 授权 2025-01-28（ONPA/SVU/B+ 树/哈希）  
    https://patents.google.com/patent/US12211101B2/en
12. NovaSparks, STAC Summit 幻灯 “Pure FPGA Market Data Solutions”, 2016-11-07（\*not STAC\*；ITCH 800/750/1250 ns）  
    https://docs.stacresearch.com/system/files/resource/files/STAC-Summit-7-November-2016-NovaSparks.pdf
13. NovaSparks, “NovaSparks Slashes Feed Handler Latency by 25%”, 2016-10-18（书引擎重写；当时 8191 品种）  
    https://novasparks.com/novasparks-slashes-feed-handler-latency-by-25/  
    （2026-08-31 WebFetch 404，搜索索引仍指向此 URL）
14. NovaSparks, “NovaSparks Unveils the First FPGA Market Data Aggregator”, 2021-07-20（FPGA 合成簿/BBO <1 μs）  
    https://novasparks.com/novasparks-unveil-the-first-fpga-market-data-aggregator/  
    （同样 404；搜索摘要可用，引用时标注官网现状）
15. Celoxica, “Products — Market Data (QDS)”, 访问 2026-08-31（full depth order book(s)；DMA）  
    https://celoxica.com/products/
16. Algo-Logic, STAC Summit “Hardware Acceleration Today Full Order-Book FPGA”, 2013-11-04（L3 <450 ns；L2 默认 10 档；Not STAC）  
    https://docs.stacresearch.com/system/files/resource/files/STAC%20Summit%20-%204%20November%202013%20-%20Algo-Logic.pdf
17. Mondo Visione, “Algo-Logic Systems Launches Full Order-Book Running On Single-FPGA Platform”, 约 2013（片上 vs DDR3 两种规模）  
    https://mondovisione.com/media-and-resources/news/algo-logic-systems-launches-full-order-book-running-on-single-fpga-platform-fu-2013829/
18. OpenPOWER, “Enabling financial service firms… order books… IBM POWER8 / CAPI”, Algo-Logic CORSA 演示  
    https://openpowerfoundation.org/blog/enabling-financial-service-firms-to-compute-heterogeneously-with-gateware-defined-networking-gdn-to-build-order-books-and-trade-with-the-lowest-latency/
19. Algo-Logic, “Building Blocks for Exchanges”（当前站：KVS 维护 open orders + aggregated order book + matching）  
    https://www.algo-logic.com/building-blocks-for-exchanges
20. 华锐技术, “华锐FPGA极速行情系统 / AMD”, 访问 2026-08-31  
    https://www.archforce.cn/products/AMD
21. 证券之星, “恒生电子获得发明专利授权：基于FPGA的订单簿数据构建方法及系统”, 2026-02-18（授权日 2026-02-17，CN202511374997.1）  
    http://stock.stockstar.com/RB2026021800000411.shtml
22. DolphinDB, “EFH 插件” 文档（盛立 FPGA 行情；tree/建树 为数据类型）  
    https://docs.dolphindb.cn/zh/plugins/efh.html
23. Liu et al., IEEE ASAP 2024, doi:10.1109/asap61560.2024.00025  
    https://doi.org/10.1109/asap61560.2024.00025
24. He, Fu, Luk, Li, Yang, FPL 2017 PDF（HFOBU；132–288 ns；fixed-tick）  
    https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf
25. Yoo et al., LightTrader HPCA 2023 PDF（10 档 LOB → BF16；XCKU15P）  
    https://rebellions.ai/wp-content/uploads/2023/11/RebellionsIONHPCA23_LightTrader.pdf
26. STAC, “STAC-T0 Overview”, 2020-11-05（无交易逻辑、无市场协议）  
    https://docs.stacresearch.com/system/files/central/STAC-T0%20backgrounder.pdf
27. STAC, “New STAC-T0 results with an Exegy/AMD FPGA solution” (AMD240422), 2024-04（13.9 ns actionable；UL3524 + nxTCP-UDP）  
    https://docs.stacresearch.com/news/AMD240422
28. AMD, “AMD Unveils … Alveo UL3524”, 2023-09-27  
    https://www.amd.com/en/newsroom/press-releases/2023-9-27-amd-unveils-purpose-built-fpga-based-accelerator-.html
29. Nasdaq Trader, TotalView-ITCH 5.0 spec（软件与 FPGA 版 payload 相同；FPGA 未整形；需 10/40G）  
    https://www.nasdaqtrader.com/content/technicalsupport/specifications/dataproducts/NQTVITCHSpecification.pdf
30. Nasdaq Trader, Data News #2025-4, 2025-05-06 起更新至 2025-09-03（ISE/GEMX/MRX Depth FPGA 分发，非客户建簿）  
    https://www.nasdaqtrader.com/TraderNews.aspx?id=dn2025-4
31. SEC, Nasdaq BX FPGA delivery for BX TotalView, 34-97541, 2023（FPGA 是 outbound 确定性分发）  
    https://www.sec.gov/files/rules/sro/bx/2023/34-97541.pdf
32. fpga2u/AXOrderBook, GitHub README（A 股逐笔重建 + HLS / U50）  
    https://github.com/fpga2u/AXOrderBook
33. Kathuria et al., “Low-Latency FPGA Market Data Parser and Hardware Order Book”, Columbia CSEE 4840, Spring 2026  
    http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf
34. AMD, “AMD Sets STAC Benchmark World Record…”, 2024-06 左右博文（13.9 ns 上下文）  
    https://www.amd.com/en/blogs/2024/amd-sets-stac-benchmark-world-record-for-fastest-e.html
35. A-Team Insight, Cousin 访谈：T0 测的是 UDP 进 TCP 出，clock 从字段进入 FPGA 起算, 2024  
    https://a-teaminsight.com/blog/exegy-and-amd-achieve-record-breaking-tick-to-trade-latency-in-stac-t0-benchmark/

