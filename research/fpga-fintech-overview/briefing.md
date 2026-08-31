I have enough primary sources. Drafting the Chinese briefing with sourced claims and a short uncertainty list.

---

# FPGA 在金融科技中的应用（简报，截至 2026-08-28）

口径：只写能对上公开一手来源的事实。STAC-T0 的 13.9 ns **不是**完整策略 tick-to-trade，而是网络 I/O 的 actionable latency。GitHub 上宣称“带神经网络的 sub-50 ns 交易系统”当作爱好者项目，不当作生产证据。

---

## 1. 为什么金融里会出现 FPGA（短）

生产里 FPGA 解决的是三件事：**确定时延、线速并行、可改写**。

- **确定性**：关键路径不经过 OS 调度、缓存 miss、软件时间戳。STAC 专门做 STAC-T0，就是因为软件时间戳在几十纳秒量级误差太大，必须用线侧硬件打戳。
- **并行流水**：PHY → 协议解析 → 订单簿/模式匹配 → 风控 → TCP 发单，可全部落在同一块 fabric，CPU 不在关键路径。
- **vs CPU**：CPU 仍跑策略、会话管理、审计；但 feed handler / 发单 / 风控若在软件里，抖动和核占用会在行情峰值时崩。Exegy Nexus 的卖点就是把归一化做到 FPGA，客户端只占 **1 个 CPU 核**。
- **vs GPU**：GPU 强在吞吐和训练、批量推理。HFT 要的是 batch=1、抖动接近零。公开 STAC-ML 金融推理纪录目前是 FPGA 栈（Myrtle VOLLO、Xelera Silva），不是 GPU。
- **vs ASIC**：协议、策略、监管（15c3-5 / MiFID II）会变。FPGA 可重配；Achronix 等推 eFPGA-in-ASIC，但那是更少、更贵的下一步，不是主流卡。
- **功耗/机柜**：colo 电和 U 位贵。Nexus 声称相对软件 feed 堆叠可减 **>40%** 机柜占用；这是厂商 ROI 案例，不是独立审计。

收发器本身：AMD 称 Alveo UL3524/UL3422 的 GTF 收发器 **<3 ns**（近端 loopback、不含协议/PL）。这是硅片 I/O，不是交易延迟。

---

## 2. 真正在卖、在跑的生产用例

### A. 超低延迟交易 / 网络 I/O（纳秒级，但要看测的是什么）

**STAC-T0（2024-04）**：Exegy nxFramework + nxTCP-UDP-10g-ULL + AMD Alveo UL3524，Dell R7525 / EPYC 7313。  
- 507 字节帧：**最低 actionable latency 13.9 ns**  
- 68 字节帧：14.1 ns  
- 相对前纪录（同为 AMD 加速器，24.2 ns）最低值低约 50%，最高值低 40–49%。  
Exegy 的 Olivier Cousin 对 A-Team 说清楚了：时钟从 UDP 帧里**触发字段（如价格）进入 FPGA** 起，到 TCP 订单离开 FPGA 止；测的是 **10GbE 处理**，新卡把 MAC/PCS **硬化进 ASIC**。抖动声称压到 **200 ps**。  
**这不是带完整订单簿+策略的端到端交易。**

**nxAccess（Enyx/Exegy 执行引擎，生产产品）**：CME 上 switch SOP-to-SOP：  
- 硬件 tick-to-trade + pattern matcher：**389 ns**  
- 硬件、无 pattern matcher：**624 ns**  
- 软件路径：**1.5 µs**  
形态是 preload 订单模板 → 硬件 trigger/update → send。混合架构：延迟关键在 FPGA，复杂逻辑在软件。规格含硬件 TCP、最多 8000 符号、16k+ 订单缓冲、kill switch。

### B. 行情解析 / feed handler / 订单簿

- **Exegy nxFeed**：FPGA NIC 上做 A/B 仲裁、解码、归一化、建簿，C++ API。常作为走向 nxAccess 全 FPGA 的第一步。
- **Exegy Nexus**（2025-06-25 发布，计划 2025 Q4 初量产）：FPGA 设备 + SmartNIC；软件侧约 **~2 µs** 拿到行情，策略反应 **<3 µs**；与 tick-to-trade 平台对接时，多市场聚合数据响应 **<350 ns**。2026-06 获 TradingTech “Best Trading Technology Stack”。
- **Celoxica QDS**：线仲裁、品种过滤、归一化、全深簿、自动恢复；宣传覆盖全球 80+ 场所。

### C. 下单 / DMA / 会话

- **Celoxica GXA**：ULL 网关、归一化 API、FIX/Native、会话、TCP Direct。
- **Exegy FPGA FIX 引擎**：声称把数百 FIX 会话卸到 FPGA，主机约 **2 核** vs 软件约 **40 核**；ASCII FIX 4.4 ↔ 二进制；最多 **128 sessions**。用于券商/交易所网关、FIX↔native 风控，不完全是 HFT 纳秒路径。

### D. 交易前风控（15c3-5 / MiFID II）——生产里很实

监管要求订单在到交易所前做检查，软件会加微秒～毫秒。FPGA 把检查做成 bump-in-the-wire：

- **Celoxica MAG**：in-line 风控 + DMA；FIX 单位数微秒级线到线，Native **数百纳秒**；宣称符合 15c3-5 与 MiFID II；60+ 场所。2026 TradingTech Insight Europe：**Best Pre-Trade Risk Controls Provider**。
- **Algo-Logic PTRC**：15c3-5，10GbE 上完整检查 **远低于 1 µs**。
- **Magmio Risk Check Gateway**：全 FPGA，厂商称低至 **200 ns**；in-line 或旁路；跑在 Cisco Nexus SmartNIC 与 AMD Alveo UL3524 上。
- **nxFramework** 参考设计：用户侧与交易所侧两套 TCP，风控网关 **sub-1 µs RTT**。

### E. 网络卸载（TCP/UDP/SmartNIC/L1）

- **Exegy nxFramework IP**（厂商表）：10G MAC/PCS 29 ns RTT (SOP-to-SOF @322 MHz，含 27.345 ns PMA)；**10G 全 TCP 53 ns RTT**；**10G 全 UDP 43 ns RTT**；PCIe DMA 790 ns RTT。
- **LMS ÜberNIC**（BittWare + Intel/Altera Agilex 7）：整栈进 FPGA，PCIe 5.0 + **CXL**。STAC-N1（2024-05，SUT LMS240510a）：STAC 称这是**首次公开测全 FPGA UDP 栈，也是首次测 CXL 栈**。66 字节公开数字：mean **1.9 µs**，p99 **2.0–2.3 µs**（这是主机网络栈 ping-pong，不是 T0 的 13.9 ns）。
- **Cisco Nexus SmartNIC**（原 Exablaze）：FPGA NIC，K3P-Q 文档写软件 trigger-to-response 低至 **596 ns**。
- **Arista 7130**：L1 交换 **5–6 ns**，jitter <100 ps；MetaMux 聚合约 **39 ns**。STAC-T0 打戳用的就是 Arista 7130 MetaWatch。这是交易机房标配，不是加速卡。

### F. 交易路径上的 ML——有产品、有 STAC，但多数是微秒不是纳秒

**已产品化、有审计/生产口径：**

1. **Xelera Silva**（AMD Alveo 生态，UL3422 页面点名）：XGBoost / LightGBM / CatBoost + LSTM 等。三种模式同一 API：  
   - CPU-only：小 GBT p99 可 **<1 µs**  
   - Accelerator（Alveo V80 等）：STAC-ML **El Popo**（2026-05-27，配置 XLRA260312）**首个独立审计提交**：GBT_A p99 **1.60 µs** (NMI=1) / **1.88 µs** (NMI=15)  
   - Inline Silicon：厂商 2026-05 套件，LightGBM on UL3524 p99 **~250 ns**（厂商 kit，不是 STAC-T0）
2. **Myrtle.ai VOLLO**：CEO 称“**数十万小时生产交易**”。2026-04-29 STAC Summit London：STAC-ML Markets Inference，p99 低至 **2 µs**，号称对三个模型都低于此前所有已审计系统。硬件：Silicom Artena + **AMD Versal Premium VP1802**。更早（Agilex 7）有 5.1 µs / 24 µs LSTM 纪录。
3. **AMD FINN**：开源量化 NN → FPGA IP，官方给 UL3524 参考设计。这是工具链，不是交易产品。

**研究/非生产（不要写进“已上线”）：** LightTrader（HPCA 2023，FPGA+自研 AI ASIC）；ASAP 2024 订单簿 FPGA；FinHardBench（2026-08 arXiv）测 LLM 写金融 RTL。GitHub 上 Alveo UL3524 “sub-50 ns + NN”是未审计 RTL 项目。

### G. 密码学

公开生产材料里，HFT 关键路径几乎不谈 TLS/HSM。看得到的是：**硬件 TCP/UDP 栈、FIX 会话、Reed-Solomon/CRC（nxFramework）**。Xelera Net 的 IPsec 更像数据中心 SmartNIC，不是交易所 colo 的 tick-to-trade。**不要把“FPGA 做交易加密”写成主流。**

---

## 3. 厂商与平台（卖什么）

| 角色 | 卖什么 | 要点 |
|---|---|---|
| **AMD** | Alveo **UL3524**（2023-09，已出货）；**UL3422**（瘦卡，同 VU2P 硅片，外推同一 STAC 纪录）；Alveo U50/U55C/**V80**；Versal Premium | GTF <3 ns；FINN；合作方 Exegy、Xelera、Hypertec、Alpha Data |
| **Altera**（原 Intel PSG；2025-04 Silver Lake 购 51%，估值 $8.75B） | Agilex 7 等；金融页推 LMS ÜberNIC、Myrtle VOLLO、压缩卸载 | 金融卡生态弱于 AMD ULL 专用卡，但 CXL NIC 和部分 ML 在 Agilex 上 |
| **Achronix** | Speedster 7t / VectorPath 815（应用表含 HFT）；Speedcore **eFPGA IP** | 2022 与 Silicon Creations 称 ASIC 内 UDP-to-TCP **<10 ns**——**厂商声明，无 STAC** |
| **Exegy** | 收购 Enyx（2022）、Vela、**NovaSparks（2026-01-14）**；Nexus / nxFeed / nxAccess / nxFramework / Axiom | 目前最完整的“FPGA 行情+交易+框架”商业栈 |
| **Celoxica** | MAG / GXA / QDS | 买卖双方、风控+DMA+行情；单数微秒级确定性，不是 13.9 ns 那一档 |
| **Xelera** | Silva 推理；Net SmartNIC | 把 GBT 推理产品化，降低 FPGA 人才门槛 |
| **Myrtle.ai** | VOLLO | 序列/LSTM 类金融推理，跨 AMD/Altera |
| **LMS + BittWare** | ÜberNIC | 全硬件网络栈 + CXL，面向 FSI |
| **Cisco** | Nexus SmartNIC（Exablaze） | 低延迟 NIC + FDK，Magmio 等跑在上面 |
| **Arista** | 7130 FPGA 交换机 | L1/汇聚/打戳，几乎每家 ULL 机房都有 |
| **Algo-Logic / Magmio** | 风控网关 | 经纪商 15c3-5 硬件化 |

NovaSparks：巴黎 FPGA 行情归一化/分发；2026-01 被 Exegy 买下。此前两家有过专利诉讼。Enyx 品牌已并入 Exegy（nx* 产品线）。

---

## 4. 前沿 / 研究（2024–2026）

- **专用 ULL 硅片**：UL3524 GTF + 硬化 MAC/PCS → STAC-T0 13.9 ns（2024）。UL3422 把同样硅片塞进瘦卡，方便 colo 密度。
- **CXL SmartNIC**：LMS ÜberNIC + STAC-N1（2024-05）。主机侧仍是微秒；价值是峰值行情下栈不塌、口密度、可在卡上做过滤/仲裁。CXL 3.0 的 cache-coherent 负载/存储进交易热路径，公开生产案例仍少。
- **ML 推理产品化**：STAC-ML 从 LSTM（Myrtle 2023–2026）扩到 **El Popo GBT**（Xelera 2026-05）。行业共识：表格行情上 GBT 仍是系统化交易主力；大模型/Transformer **没有**进入纳秒 T2T 的公开生产证据。
- **LightTrader**（HPCA 2023）：FPGA + 7nm CGRA AI 加速器，相对 GPU/FPGA 基线报 13.92× / 7.28× AI 处理加速——研究系统。
- **Liu et al., IEEE ASAP 2024**：FPGA 实时订单簿与快照（FinHardBench 引用订单簿 26–209 ns）。
- **VLSI-TSA 2026**：Alveo U50 双向风控，单笔约 518–530 ns，连续 1 万笔吞吐相对前作约 2.1–2.2×。
- **O’Mahony et al., Electronics 2024**：FPGA 期权定价综述，相对 CPU 加速 270–5400×——定价/风险，不是 HFT 发单。
- **FinHardBench**（arXiv:2608.00909，约 2026-08）：33 个金融 FPGA 任务，测 LLM 写 Verilog。功能正确率 **19–61%**；大量“能综合能布线但算错”（RSI 路由成功里 90% 算错）。结论：协议改、策略改仍靠人；LLM 还不能当生产 RTL 主力。

---

## 5. 仍然难、尚未铺开的

1. **把完整策略放进 FPGA**：生产主流是行情+TCP+风控+触发模板；复杂 alpha 仍在 CPU。RTL 人才、验证、交易所协议变更（FinHardBench 说一轮要数天到数周）。
2. **纳秒级 ML**：STAC-T0 13.9 ns 无 ML。公开 inline GBT ~250 ns（厂商 kit）；LSTM/NN 多在 1–3 µs。大模型、在线训练、热更新权重且保持零抖动——未规模化。
3. **深簿 vs 延迟**：nxAccess 8000 符号；全市场、全深度、多资产 24/5，FPGA 片上内存不够，常要软硬分流。
4. **25G/100G/400G 与 24×5**：多数公开 ULL 数字仍是 10G。交易所扩时段、EuroCTP 等新源（Exegy 2026-08 称接入 Axiom）会逼 feed 架构，不自动等于更低 T2T。
5. **CXL**：有卡、有 STAC-N1，未见与 STAC-T0 同级的交易热路径数字。
6. **eFPGA/ASIC**：Achronix <10 ns 仍是 2022 宣传；ASIC 锁定 vs 协议常变，只有最头部自营会做。
7. **密码学加速进交易路径**：公开材料几乎空白。
8. **LLM 生成交易 FPGA**：FinHardBench 显示“能出 bitstream 但逻辑错”比综合失败更危险。

---

## 6. 未来 12 个月可盯（有来源才写）

- **Exegy Nexus 量产落地 + NovaSparks 客户并入**（发布时写 2025 Q4 初交货；2026 已在拿奖）。看多资产、fast-cancel/sweep 是否按 roadmap 出来。
- **STAC-ML El Popo 是否有第二家提交**（目前公开第一家是 Xelera/AMD/HPE，2026-05）。
- **AMD 下一代 ULL 卡**：Risk.net 对 AMD 的采访（Hamid Salehi）明确说客户在问 UL3422 之后是什么，并称未来几年会有更多 ULLT 产品。具体型号未公布。
- **Altera 独立后是否补金融专用卡**，以及 ÜberNIC/CXL 有没有更多 STAC。
- **Inline 推理是否进入真实 T2T**（Silva Inline、FINN 进 datapath）——现在主要是产品页和 kit，缺与 T0 同级的第三方 T2T+ML 报告。
- **24/5、欧股 CTP、中东交易所扩展**（Exegy Axiom 2026-06 扩中东）——驱动的是 feed 密度和运维，不一定是更低纳秒。
- **LLM 辅助 FPGA**：值得盯工具，不值得当成 12 个月内能替掉自研团队。

---

## 不确定 / 不要当事实用

- 具体哪家自营（Optiver、HRT 等）用哪张卡：AMD 只说“领先交易公司已部署”，无客户名单。
- QuantVPS 一类博客写的 “2026 标准 100–500 ns T2T”：二手概括，未采用。
- GitHub / LinkedIn 个人项目的 sub-50 ns + transformer：未综合到交易所、未 STAC。
- Nexus 某美股经纪商年省 $1.4–2M、32→17 台服务器：厂商 ROI。
- Magmio 200 ns、Celoxica “数百 ns Native”、Silva inline 250 ns：厂商数字，部分无 STAC。
- Achronix eFPGA <10 ns：2022 合作稿。
- FPGA 做交易加密/后量子：无足够公开生产证据。

---

## 主要来源（15 条，含日期）

1. STAC: *New STAC-T0 results with an Exegy/AMD FPGA solution* — 2024-04 — https://docs.stacresearch.com/news/AMD240422  
2. AMD IR: *AMD Unveils Purpose-Built FPGA-Based Accelerator…*（UL3524）— 2023-09-27 — https://ir.amd.com/news-events/press-releases/detail/1158/amd-unveils-purpose-built-fpga-based-accelerator-for-ultra-low-latency-electronic-trading  
3. AMD: *Alveo UL3422 Accelerator Card*（含 STAC 外推脚注）— 产品页，脚注定价 2024-09 — https://www.amd.com/en/products/accelerators/alveo/ul3422.html  
4. A-Team Insight: *Exegy and AMD Achieve Record-Breaking Tick-to-Trade Latency*（Cousin 解释 T0 测什么）— 2024 — https://a-teaminsight.com/blog/exegy-and-amd-achieve-record-breaking-tick-to-trade-latency-in-stac-t0-benchmark/  
5. Exegy: *Nexus launch* — 2025-06-25 — https://www.exegy.com/nexus-launch/  
6. Exegy: *Acquires NovaSparks* — 2026-01-14 — https://www.exegy.com/exegy-acquires-novasparks/  
7. Exegy: *nxAccess*（389/624 ns CME）— https://www.exegy.com/products/nxaccess/  
8. Exegy: *nxFramework*（TCP 53 ns / UDP 43 ns RTT）— https://www.exegy.com/products/nxframework/  
9. Celoxica: *Products*（MAG/GXA/QDS，15c3-5 / MiFID II）— https://celoxica.com/products/  
10. Xelera: *Sets the First STAC-ML El Popo World Record* — 2026-05-27 — https://www.xelera.io/post/xelera-sets-the-first-stac-ml-el-popo-world-record  
11. Myrtle.ai: *Halves Latency in Financial ML Inference… VOLLO* — 2026-04-29 — https://myrtle.ai/resources/news/myrtle-ai-halves-latency-in-financial-machine-learning-inference-benchmark-record-with-vollo/  
12. STAC: *LMS ÜberNIC CXL under STAC-N1* — 2024-05 — https://www.stacresearch.com/news/LMS240510a  
13. Intel: *Silver Lake investment in Altera* — 2025-04-14 — https://newsroom.intel.com/corporate/intel-partner-deal-news-april2025  
14. Arista: *7130LS Series Data Sheet*（L1 5 ns, MetaMux ~39 ns）— https://www.arista.com/assets/data/pdf/Datasheets/7130LS-Series-Data-Sheet.pdf  
15. Fu et al.: *FinHardBench* — arXiv:2608.00909 — 2026-08 — https://arxiv.org/html/2608.00909  

补充（风控/FIX，按需用）：  
- Magmio 风控网关：https://www.magmio.com/fpga-trade-risk-check  
- Algo-Logic PTRC：https://www.algo-logic.com/pre-trade-risk-check  
- Exegy FPGA FIX：https://www.exegy.com/fpga-fix-community/  
- AMD Alveo UL3524：https://www.amd.com/en/products/accelerators/alveo/ul3524.html  
- Yoo et al., LightTrader, HPCA 2023  

**给用户的一句话**：FPGA 在金融里已经是行情、TCP、风控、L1 交换的生产默认件；纳秒竞赛的公开天花板是 **STAC-T0 13.9 ns 的网络反应**；机器学习刚进入 **微秒级、可采购的推理产品**（GBT/LSTM），还没进入那条 13.9 ns 的热路径。
