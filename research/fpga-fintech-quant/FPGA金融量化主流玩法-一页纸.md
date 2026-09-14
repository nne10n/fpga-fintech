# FPGA × 金融量化：玩法 / 指标 / 路径（一页纸）

数字口径标记：**【STAC】**=STAC 审计基准；**【厂】**=厂商宣传或厂商自测；**【论】**=论文实验室；**【交易所】**=交易所一手文档；**【二手】**=媒体/行业科普，降级使用。

---

## 一、背景（FPGA 在量化里解决什么）

- FPGA 被用在**逻辑固定、必须极短且确定时延内完成**的环节：行情解析与归一化、A/B 线仲裁、建簿、固定规则触发、硬件报单、内联风控、硬件打时间戳。
- 核心卖点是**确定性（低抖动）**，不是通用算力；本质是把热路径从主机软件栈里挪出来。
- 与 CPU/GPU 的一句话分工：CPU 跑策略研究、参数生成与灵活业务逻辑；GPU 跑吞吐型批量计算；FPGA 跑单笔路径上的固定逻辑与时延关键段。*（该分工为常见工程共识，未找到单一权威出处 → 未核实）*
- 公开可比的边界：`STAC-T0` 只测**网络 I/O**，明确"不含交易逻辑、不含市场专用协议处理"【STAC】；软件栈（内核旁路 + 商用 NIC）最低 tick-to-trade 约 **2 µs**，硬件方案则可进入亚微秒到个位数纳秒【二手】。

---

## 二、主流玩法分类表

| 玩法 | 典型职责 | 常见部署位置 | 是否已有公开产品 |
|---|---|---|---|
| 行情接入 / A–B 仲裁 | 组播 A/B 双线去重、按序仲裁、线路异常切换 | 同城机房服务器 / NIC / 交换机 FPGA | 有：Celoxica QDS、Exegy nxFramework；论文级硬件仲裁【论】 |
| 建簿 / 热视图 | 由增量行情维护可查询簿与热门档位视图（**只点名玩法，不展开结构**） | 同城服务器加速卡或交换机 FPGA | 有：Arista 对外授权建簿类 IP Core；论文级 FPGA 建簿【论】 |
| 策略触发 / 简单特征 | 门限比较、固定规则触发、低延迟特征预计算 | 加速卡热路径 / 交换机 FPGA | 部分：Exegy 有 sub-100 ns RTT 的 tick-to-trade 参考设计【厂】；公开基准不含策略逻辑【STAC】 |
| 报单 / TCP 卸载 | 硬件维护 TCP/UDP 会话并直接发单，绕开主机栈 | 加速卡 / 交换机 FPGA | 有：Exegy nxTCP-UDP-10g-ULL、LDA Lightspeed TCP、Solarflare Delegated Sends【厂】【二手】 |
| 交易前风控 | 报单前限额/白名单/自成交检查，内联拦截 | 网关口，与发单同路径或旁路 | 有：Celoxica MAG / AIR、Exegy 风控网关参考设计【厂】 |
| 精确时钟 / L1 交换 | 硬件时间戳、PTP、L1 端口转发、分光复用 | 机房网络层（交换机 / tap 设备） | 有：Arista 7130（MetaWatch / MetaMux）、LDA NeoTap X / Lynx【厂】 |
| 行情分发 / 复用 | 一路行情低延迟复制到多个策略实例 | 交换机 FPGA | 有：Arista MetaMux、LDA layer-1 方案【厂】 |

---

## 三、核心指标表

| 指标 | 定义 | 常见口径 / 陷阱 | 出处 |
|---|---|---|---|
| tick-to-trade | 收到行情事件 → 发出报单的端到端时间 | 口径分歧：EOF→EOF 还是 SOF→EOF；**常在不含策略逻辑的平台上测**，把平台 I/O 当含策略端到端是错的 | 【二手】Databento |
| Actionable / I-O latency | STAC-T0 关键指标：从"决策所需最后一个 bit"到"模拟报单第一个 bit" | 明确不含交易逻辑与市场协议；**13.9 ns 属此口径，不是完整策略 tick-to-trade** | 【STAC】STAC-T0 backgrounder；AMD/Exegy 结果 13.9 ns（507B 帧）、14.1 ns（68B 帧） |
| 建簿 / 归一化延迟 | 增量消息 → 簿可用 / 归一化输出 | 强依赖符号数、深度、消息率；论文之间不可直接横比 | 【论】FPL 2017：10 Gb/s 下 132–288 ns，1.2–1.5 M msg/s |
| 抖动（jitter） | 同一负载下时延分布宽度（max、p99.9） | **均值无意义**；低速率下的 max 才决定能否成交 | 【STAC】STAC-T0 同时报 min/max；AMD 报 max 较前记录低 40–49%【厂】【STAC】 |
| 吞吐 / pps、msg/s | 单位时间可处理报文数 / 消息数 | 1 秒均值会低估：1 ms 微突发常达 1 s 均值的约 **10 倍** | 【厂】Exegy MarketDataPeaks |
| 确定性 | 相同输入下时延可重复、无排队抖动 | L1 交换不缓冲不排队，故"几乎不可测抖动"；软件栈抖动显著更大 | 【厂】Arista 7130 产品概述 |
| 部署形态与资源占用（仅列有公开口径者） | 单卡功耗/槽位；基准测试的服务器与 CPU 型号 | 只在厂商自己的性能报告与 STAC 配置说明里有，跨版本/跨时钟频率不可比 | 【厂】Alveo UL3422：FHHL 单槽 120 W；【STAC】STAC-T0 配置为 Dell R7525 + EPYC 7313 |

其他可引用但需标口径的数字：Exegy nxFramework 性能报告给出 10G MAC/PCS 29 ns RTT（含 27.345 ns 收发器）、10G TCP 53 ns RTT、UDP 43 ns RTT、PCIe DMA 790 ns RTT【厂】；AMD 称 Alveo UL3524 收发器时延 **< 3 ns**，UL3422/UL3524 表格标 2.34 ns 且明确为**近端环回**口径【厂】；Arista 7130 L1 端口到端口 4 ns（16/48 口）、6 ns（96 口）、MetaMux 低至 39 ns、MetaWatch 亚纳秒时间戳【厂】；LDA NeoTap X 时间戳精度 100 ps、端口到端口 2 ns【厂】【二手】；Solarflare + LDA 的 Delegated TCP send 宣称 120 ns【二手】。

---

## 四、技术路径（每项只写切分选项）

- **行情接入 / A–B 仲裁**：①纯软件内核旁路（Onload / TCPDirect / ef_vi / DPDK）做去重仲裁，硬件只负责分光；②FPGA 在线速路径完成解析与仲裁，主机只收归一化结果（Celoxica 的"卡内 feed handler + C++ API"即此形态）；③把仲裁下沉到交换机 FPGA，多台主机共享同一份已仲裁行情。partial offload 常止步于解析/仲裁，决策留在主机；全硬件则连触发一起搬进卡内。
- **建簿 / 热视图**：①主机软件建簿，FPGA 只做解析；②FPGA 建簿后只把需要的部分（如最热档位）推给主机；③交换机 FPGA 内置簿视图，供多策略共享。取舍点是簿深度、符号数、是否需要复杂查询，而非单纯延迟。
- **策略触发 / 特征**：①主机算法 + FPGA 仅做低延迟触发与预计算；②固定规则全硬件实现；③混合：FPGA 触发后直接在硬件发单，主机异步跟进。注意公开基准 STAC-T0 不含策略逻辑，"含策略"的端到端数字通常只有厂商自测【厂】。
- **报单 / TCP 卸载**：①主机栈 + **Delegated Sends**（网卡维护 TCP 连接，主机把发送动作委托给网卡，Onload 特性）；②FPGA 内完整 TCP/IP 栈（Exegy nxTCP-UDP、LDA Lightspeed TCP）；③硬件发单 + 主机负责会话管理、重传与对账。全硬件栈换来的时延，代价是连接数与异常处理的灵活性。
- **交易前风控**：①主机网关内联检查（软件，µs 级）；②风控与发单同处 FPGA 路径（Celoxica MAG / AIR、Exegy 风控网关参考设计）；③独立旁路监听 + 硬件熔断。关键选项是"必须拦在报单前"还是"只做监控"。
- **精确时钟 / L1 交换**：①交易服务器侧用 PTP 与网卡硬件时间戳（Nasdaq Nordic PTP：PTPv2，纳秒级时间戳，UTC 偏差 ±10 µs）【交易所】；②网络层 L1 交换 + 分光复用 + 带内时间戳（Arista MetaWatch、LDA NeoTap X）；③独立 tap/聚合设备做离线测量。这一层基本属于基建，与策略卡解耦。

---

## 五、注意与坑

1. **指标混用**：厂商纳秒数字常是 MAC/PCS 环回或网络 I/O（AMD 的 2.34 ns 明确是近端环回），不能与端到端 tick-to-trade 相加或横比；13.9 ns 是 STAC-T0 actionable，**不含策略**。
2. **研究当生产**：论文的 132–288 ns 建簿、42 ns 仲裁都是特定器件与负载下的实验室口径，不能外推到实盘符号数与行情率。
3. **组播 RX vs TCP 补包**：UDP A/B 仲裁路径极快，但丢包恢复走的是完全不同的慢路径（CME TCP Message Recovery 限 **2000 包以内、24 小时内**）【交易所】；把仲裁延迟当成"含恢复的行情延迟"是错的。
4. **风控与 HFT 不是一个延迟档**：热路径以 ns～百 ns 计，合规风控可接受 µs 级；硬把两者压进同一条热路径，通常换来更难维护的硬件逻辑。
5. **确定性 ≠ 平均低**：低速率下 min 与 max 的差距才是成交的决定因素。

---

## 六、开放选项表（不引入新硬约束）

| 主题 | A / B / C | 对业务优先级的含义 |
|---|---|---|
| 先通信基建还是先建簿 | A 先 L1/分光/时钟；B 先 FPGA 行情 + A–B 仲裁；C 先 FPGA 建簿 / 触发 | A 收益普惠所有策略且最难被单点替代；B 直接改善全部延迟敏感策略的入场时延；C 只在多符号、深度簿场景产生增量收益 |
| 延迟目标档位 | A 软件 + 内核旁路（µs 级）；B 混合：FPGA 热路径 + 主机策略；C 全硬件 | A 人力与工程成本最低、适用策略面最宽；B 是当前多数公开产品形态；C 只对极少数规则化策略成立 |
| 风控位置 | A 主机内联；B FPGA 与发单同路径；C 独立旁路 + 熔断 | A 迭代快、时延预算宽；B 满足"报单前必须过风控"且几乎不加时延；C 只能监控不能拦截 |
| 时钟与测量 | A 只做 PTP 合规；B 加硬件时间戳 + tap 做延迟度量；C 建立延迟指标体系并纳入上线门槛 | A 合规成本最低；B 才可能产出可信的 tick-to-trade 数字；C 才能避免"指标混用"导致的决策错误 |

---

## 七、出处

**STAC（审计 / 基准口径）**
1. STAC-T0 Overview（背景说明），2020-11-05 — https://stacresearch.com/system/files/central/STAC-T0%20backgrounder.pdf
2. STAC Report: New STAC-T0 results with an Exegy/AMD FPGA solution, 2024-06-25 — https://docs.stacresearch.com/news/AMD240422
3. STAC Summit 演讲 *Ultra Low Latency Trading with the latest Alveo Accelerators, CPU's and Solarflare NIC's*, 2024-10-29 — https://docs.stacresearch.com/system/files/resource/files/STAC-Summit-29-October-2024-AMD2.pdf

**厂商（宣传 / 自测口径）**
4. AMD, *AMD Sets STAC Benchmark World Record for Fastest Electronic Trade Execution*, 2024-06-27 — https://www.amd.com/en/blogs/2024/amd-sets-stac-benchmark-world-record-for-fastest-e.html
5. AMD, *Alveo UL3524* 产品页（无日期）— https://www.amd.com/en/products/accelerators/alveo/ul3524.html
6. Exegy, *nxFramework* 产品页（含性能报告，无日期）— https://www.exegy.com/products/nxframework/
7. Celoxica, *Client use cases*（无日期）— https://celoxica.com/client-use-cases/
8. Arista, *The Arista 7130 Series* 产品概述 PDF，2019-08 — https://www.arista.com/assets/data/pdf/7130-product-overveiw.pdf
9. Exegy, *MarketDataPeaks*（无日期）— https://www.exegy.com/marketdatapeaks/
10. LDA Technologies 官网（Lynx / NeoTap X，无日期）— https://ldatech.com/

**交易所一手**
11. CME Group Client Systems Wiki, *MDP 3.0 – Dissemination*（更新 2024-12-26）— https://cmegroupclientsite.atlassian.net/wiki/spaces/EPICSANDBOX/pages/457222936/MDP+3.0+-+Dissemination
12. Nasdaq, *Nordic PTP Services* 事实说明书（无日期）— https://www.nasdaq.com/docs/nasdaq-nordic-ptp-services-fs.pdf

**论文（实验室口径）**
13. Denholm, Inoue, Takenaka, Becker, Luk, *Network-Level FPGA Acceleration of Low Latency Market Data Feed Arbitration*, IEICE Trans. Inf. Syst. E98.D(2), 2015 — https://www.jstage.jst.go.jp/article/transinf/E98.D/2/E98.D_2014RCP0011/_article/-char/en
14. He, Fu, Luk, Li, Yang, *Exploring the potential of reconfigurable platforms for order book update*, FPL 2017 — https://spiral.imperial.ac.uk/handle/10044/1/56418
15. O Mahony, Hanzon, Popovici, *The Role of FPGAs in Modern Option Pricing Techniques: A Survey*, Electronics 13(16):3186, 2024 — https://doi.org/10.3390/electronics13163186

**行业媒体 / 科普（二手，降级使用）**
16. Databento Microstructure Guide, *What is tick-to-trade latency?* — https://databento.com/microstructure/tick-to-trade
17. Databento Microstructure Guide, *What is kernel bypass?* — https://databento.com/microstructure/kernel-bypass
18. Traders Magazine, *Solarflare and LDA Technologies Slash "tick-to-trade" Latency to 120 Nanoseconds*, 2017-05-04 — https://www.tradersmagazine.com/departments/brokerage/solarflare-and-lda-technologies-slash-tick-to-trade-latency-to-120-nanoseconds/
19. Mondo Visione, *Best Time Stamping/Latency Measurement System Winner: LDA Technologies' NeoTap X*, 2026-02-27 — https://mondovisione.com/media-and-resources/news/best-time-stampinglatency-measurement-system-winner-lda-technologies-neotap-x-2026227/
