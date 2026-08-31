# Siemens EDA vs Synopsys EDA 仿真工具对比笔记

**调研日期：** 2026-08-31（Asia/Shanghai）  
**读者：** 坤 仇 / 调研专员  
**范围：** FPGA/ASIC 数字功能仿真为重心。模拟/混合信号与仿真加速（emulation）只在改变仿真工具图景时提及。  
**方法约束：** 只写有出处的具体主张；厂商营销数字一律标注；不编造基准、市占、价格、产品名或引文。独立工程师报告标为 anecdotal。  
**未核实、因此不采用：** qishuai-cn.com 上 2026-04/07/08 多篇互相矛盾的 “BIS 把 sub-7nm EDA 列入 EAR” 文章，无 Federal Register 原文，不写入比较结论。

---

## 0. 怎么读这份笔记

- **[厂商]** = 产品页、新闻稿、datasheet、厂商博客/白皮书。数字默认是营销，不是独立基准。
- **[官方第三方]** = AMD/Altera 用户手册、BIS/厂商对出口管制的声明、IEEE 标准页。比厂商自评更可操作。
- **[客户经厂商转述]** = 新闻稿里的客户引言，或厂商博客复述 DVCon。有姓名/公司，但仍经厂商渠道。
- **[anecdotal]** = StackOverflow、Altera Community、OSVVM forum、GitHub、AMD 论坛。用来标弱点方向，不当成基准。
- **[行业媒体]** = SemiWiki、Semiconductor Engineering、Reuters、CRS。SemiWiki/SemiEngineering 常有厂商赞助或访谈，不当成独立 bake-off。

三家都自称 “highest / best-in-class / fastest”。**没有任何 2023–2026 公开、可复现、跨厂商的独立 bake-off 数字被本调研找到。** 选型应自己用 DUT/UVM 环境跑 bake-off。

---

## 1. 产品名地图（2025–2026 实际在卖/在文档里的名字）

### 1.1 Siemens EDA（原 Mentor Graphics）

| 名字 | 角色 | 2025–2026 状态 | 出处 |
|---|---|---|---|
| **ModelSim** | 传统 HDL 仿真器 | 仍出现在 AMD Vivado 2025.1 支持表（Siemens EDA ModelSim 2024.3 DE）。Intel/Altera FPGA 捆绑版已被 Questa FPGA Edition 替换。Student Edition 页面写 “temporarily unavailable”（美国联邦法规导致免费下载暂停）。 | AMD UG900 2025.1；Intel ADV 2122 2021-05-14；Altera docs 2025-12-15；Siemens ModelSim SE 不可用页 |
| **Questa / QuestaSim / Questa Core / Questa Prime** | 企业级功能仿真家族 | Altera Quartus 26.1 明确：*“QuestaSim is the generic name for Questa Core and Questa Prime simulators.”* FPGA OEM 版基于 **Questa Core**，不含 Questa Prime 特性。 | Altera UG 2026-08-10；Altera Questa FPGA Edition 产品页 |
| **Questa Base** | ModelSim 用户升级档 | 分销商（Sintecs 等）仍作为 “next-generation for ModelSim users、含 Visualizer” 销售。非 Siemens 美国主站 2026 主推品牌。 | Sintecs Questa Base 页（厂商渠道转述） |
| **Questa One** | 2025 新伞品牌 “smart verification” | Siemens 2025-05-13 宣布，**2025-06 起供应**。FAQ：整合 12+ 新产品与 17+ AI 能力。DAC 2026 SemiWiki 访谈仍用此名，并提 Agentic Toolkit。 | Siemens PR 2025-05-13；siemens.com/questa-one；SemiWiki DAC 2026 |
| **Questa One Sim** | 功能仿真引擎（Questa 仿真的演进） | 产品页自称面向 SoC/ASIC/**FPGA**。功能：ParallelSim 自动分区、SmartCompile、X-debug、内建 PSS、VHDL constraint solver、CDC metastability injection。子产品：Sim CX（覆盖加速）、Sim DX（DFT）、Sim Xact（GLS 假 X）、Sim PA（UPF 功耗感知）。 | siemens.com Questa One Sim；Sim PA 产品页 |
| **Visualizer Debug Environment** | 仿真/仿真加速/原型 统一 debug | 现挂在 Questa One 下。SV/UVM、VHDL、SystemC/C++、transaction、UPF、覆盖可视化、live + post-sim。 | Visualizer 产品页 |
| **Verification IQ** | 基于浏览器的验证管理 + AI 分析 | Testplan Author / Regression Navigator / Coverage Analyzer / Compliance Advisor / Verification Insight。Regression Navigator **与 Questa Verification Run Manager (VRM) 紧耦合**。 | VIQ 产品页；VIQ fact sheet |
| **Verification Run Manager (VRM)** | 回归执行引擎 | 2024.2 用户手册仍在（Microchip 镜像，Siemens 版权，2024-06）。不是 Cadence 的 vManager。 | VRM UG 2024.2 |
| **Veloce CS** | 硬件辅助验证（对比项，非本文主体） | Strato CS 仿真加速（CrystalX 芯片）、Primo CS 企业原型、proFPGA CS 软件原型。2024 夏季 GA。VIP/测试可在 Questa One Sim 与 Veloce 间复用（厂商宣称）。 | Siemens Veloce CS 页；Veloce CS 发布稿 |
| **Analog FastSPICE (AFS) + Symphony / Symphony Pro** | AMS | Symphony 用 AFS 做模拟核，数字核可选 Questa / VCS / Incisive / Xcelium（SemiWiki 2024-01-17）。**Symphony Pro 只与 Questa + Visualizer MS 捆绑**（UVM/UPF/RNM/覆盖）。 | Siemens Symphony 页；SemiWiki 2024-01-17 |
| **Catapult HLS + Questa HL-SYC** | HLS 验证 | Catapult 做 C++/SystemC HLS；Questa HL-SystemC 把 formal/覆盖前移到综合前。 | Siemens Catapult / HL-SYC 页 |
| **Questa One Avery VIP** | VIP | 2025-05-13 PR：同一 CTS/TB 可在 Questa One Sim 与 Veloce CS 复用。 | Siemens PR 2025-05-13 |
| **Tessent** | DFT（改变仿真图景） | QDX/Questa One DFT 仿真加速与 Tessent SSN 绑定。Microsoft 引言称 “weeks to days”。 | Siemens PR 2025-05-13 |

**关于 “Questa One” 是否替换 QuestaSim：** 厂商说法是 *evolution of the functional simulator* / 伞品牌，不是公开宣布 “QuestaSim 停售”。Altera/AMD 2025–2026 文档仍写 Questa Advanced Simulator / QuestaSim 2024.3–2025.3。实务上：旧合同/FPGA OEM 仍是 QuestaSim 家族；新推 AI/并行/覆盖加速卖 Questa One Sim。

### 1.2 Synopsys

| 名字 | 角色 | 2025–2026 状态 | 出处 |
|---|---|---|---|
| **VCS** | 主功能仿真器 | 产品页自称 “Industry’s Highest Performance Simulation Solution” 且 “primary verification solution used by a majority of the world’s top semiconductor companies”——**厂商自评，无独立市占数字**。NTB、FGP、ICO、DPO、DTL、Xpropagation、Native Low Power、DPI/DKI、ZeBu 加速。 | synopsys.com/verification/simulation/vcs.html |
| **VCS MX / 现称 VCS 3-step flow** | 混合语言（VHDL+Verilog/SV） | Altera Quartus **从 25.1 起**：原 “VCS MX” = **VCS (3-step) flow（完全支持）**；原 “VCS” = **VCS (2-step) flow（仍支持但 deprecated）**。Agilex 3/5 只支持 3-step。命令：`vlogan`/`vhdlan` → `vcs` → `simv`。 | Altera VCS Support 2026-04-22；Altera supported simulators 2026-08-10 |
| **Native Testbench (NTB)** | VCS 内建 SV testbench | 产品页/datasheet 仍作为关键能力列出。 | VCS 产品页；VCS datasheet PDF |
| **Verdi** | Debug + 部分验证管理 | 厂商称 “de-facto debug standard”。FSDB、波形/协议/断言/UVM transaction、UPF、AMS、HW/SW sync、ZeBu/HAPS。含 **Verdi VMS**（规划/回归/覆盖）及与 **VC Execution Manager** 的集成（datasheet）。Euclide IDE。 | Verdi 产品页；verdi-ds.pdf（©2024） |
| **DVE** | 旧 VCS GUI | 2023–2026 官方主站不再主推。AMD 论坛 2024 仍有人用 VCS-MX + DVE/`-kdb` 编 Vivado VHDL 库——说明部分 FPGA 流程还在用。**未找到官方 “DVE EOL” 日期，不要写成已停售。** | AMD Adaptive Support 帖（anecdotal） |
| **VC Formal** | Formal，紧挨仿真 | 与 VCS Unified Compile、与 Verdi Unified Debug。FCA app 可在 VCS shell 内做不可达分析，覆盖库可与仿真合并。 | VC Formal 产品页；Synopsys 博客 “Formal enhance simulation coverage” |
| **VC SpyGlass / VC LP** | 静态/低功耗静态 | Unified Compile with VCS。 | VCS 产品页；Verification family 页 |
| **Verdi VMS / VC Execution Manager** | 回归/覆盖管理 | VMS：规划、编译、回归、覆盖标注。Datasheet 写 VMS 也集成 VC Execution Manager。 | verdi-ds.pdf |
| **VC VIP** | VIP | 与 VCS solver/覆盖、Verdi Protocol Analyzer 原生集成（厂商）。 | VCS 产品页 |
| **ZeBu / ZeBu-200 / ZeBu Server 5** | 仿真加速（对比项） | VCS “congruent mode” 声称仿真与硬件匹配。ZeBu-200 用 AMD VP1902。 | VCS 产品页；DE247 ZeBu-200 报道 |
| **HAPS** | FPGA 原型 | 与 Verdi 联调。 | Verdi 产品页；FPGA portfolio 页 |
| **PrimeSim HSPICE / XA / Pro + VCS PrimeSim AMS** | AMS | **FineSim / CustomSim 已并入 PrimeSim 家族**（当前公开名）。VCS 与 PrimeSim 内核级合仿；Verdi AMS debug。 | PrimeSim Pro/XA datasheet |
| **Synplify** | FPGA 综合 | 支持 SV、VHDL-2008/**2019**；AMD/Intel/Lattice/Microchip 等。**可在 GUI/batch 自动生成 VCS 的 RTL/综合后/P&R 仿真脚本（Linux）**。 | synopsys.com/verification/fpga-simulation.html；Synplify 产品页 |
| **SARA University Software Program** | 学术授权 | 学校申请，bundle 含 “nearly all” EDA 工具（含仿真）。无公开单价。 | synopsys.com/academic-research/university.html |

### 1.3 Cadence（第三极，一段）

**Xcelium Logic Simulator** 是公开文档里与 Questa/VCS 并列的第三家企业仿真器。官方能力：SystemVerilog、VHDL、SystemC、**e**、UVM、混合信号、IEEE UPF、X-propagation；Apps：SimAI（ML 回归）、Mixed-Signal（Spectre 合仿）、Multi-Core、Distributed Simulation（多 die）、Safety（ISO 26262）、PowerPlayback（Palladium 波形回放做门级功耗）、X-Pessimism Removal。Debug/管理走 **Verisium Debug / Verisium Manager**（Cadence 的 **vManager** 是 Cadence 自己的验证管理产品，不要和 Siemens VRM 搞混）。仿真加速：Palladium；原型：Protium。AMD Vivado 与 Altera Quartus 均支持 Xcelium，且 **仅 Linux**。  
出处：https://www.cadence.com/en_US/home/tools/system-design-and-verification/simulation-and-testbench-verification/xcelium-simulator.html （抓取 2026-08-31）；AMD UG900 2025.1；Altera supported simulators 2026-08-10。

---

## 2. 语言 / 标准支持

### 2.1 三家都能做的（有官方页，无独立完整度评分）

| 能力 | Siemens Questa One Sim / Questa | Synopsys VCS | Cadence Xcelium |
|---|---|---|---|
| SystemVerilog / UVM | 是（厂商） | 是；NTB；Accellera UVM，datasheet 还列 VMM/OVM 及互操作 kit | 是；另有 **e** |
| VHDL | 是；One Sim 宣传 VHDL constraint solver | 是（3-step / 原 MX） | 是 |
| 混合语言 | 是（FPGA Edition 也写 Verilog/SV/VHDL/SystemC） | 3-step：vlogan+vhdlan | 是 |
| SVA / 断言 | Visualizer 有 assertion analysis | Verdi assertion analysis | 是（XPR 等） |
| 覆盖 | 代码+功能；VIQ Coverage Analyzer；Sim CX | 规划/覆盖/closure；testbench class line coverage | SimAI / Verisium |
| SystemC | Visualizer 列 SystemC/C/C++；FPGA Edition 列 SystemC | IEEE 1666；DKI/DPI；Verdi CBug | 是 |
| DPI-C | Visualizer/历史 Questa DPI | 产品页 Direct Interfaces (DKI, DPI) | 未在本调研中展开 |
| UPF | **Questa One Sim PA：UPF 4.0 及 3.1/3.0/2.1/2.0**（厂商） | Native Low Power；Verdi Power-Aware 用 UPF | IEEE UPF（产品页） |
| X-prop | 专利 X-debug；Sim Xact 去 GLS 假 X | Xpropagation | XPR App |
| PSS | One Sim **built-in PSS**（厂商） | Verdi testbench debug 列 portable stimulus | 未核对本调研 |

### 2.2 VHDL-2019：不对称，且 Questa 侧有独立抱怨

- **Synplify（综合，不是仿真器）** 明确写支持 VHDL-2008/**2019**。[厂商] https://www.synopsys.com/implementation-and-signoff/fpga-based-design/synplify.html  
- **Questa VHDL-2019：** Siemens 社区 2024–2025 工程师帖：支持清单在安装树 `$QUESTA_HOME/docs/technotes/vhdl2019.note`。2024.2 加了一批构造（含 ENV Date & Time API）；**Interfaces 当时仍在研发**；2024.3 未宣称新 2019 特性。完整 LRM 支持**未被官方称为完成**。  
  https://community.sw.siemens.com/s/question/0D5Vb0000083hlgKAA/does-questa-support-vhdl-2019  
- **[anecdotal] OSVVM 论坛：** 维护者称 Questa 2024.2 宣称 2019 后，OSVVM 打开 `-2019`；**2025 发行版开始把 RandomPkg2019 判为 unsupported**。建议整工程统一 VHDL 版本。  
  https://osvvm.org/forums/topic/weird-questasim-base-error  
- **VCS VHDL-2019：** 本调研未找到与 Questa technote 同级别的公开特性清单。不要写成 “VCS 完整支持 2019”。

### 2.3 混合语言实务差异（有文档，不是性能）

- **VCS：** FPGA 新器件（Agilex 3/5）**只认 3-step**；2-step deprecated。Vivado `compile_simlib` 对 VHDL 必须全库 `-kdb` 才能进 Verdi/DVE，2023.1+ 用户踩过坑。[官方第三方 + anecdotal] Altera 2026-04-22；AMD forum。  
- **Questa：** 单引擎混编是传统强项（Mentor 血统）。FPGA OEM 版也标 mixed-language。Visualizer 有专门 “Introduction to Visualizer for VHDL users” 网络研讨会——说明 Siemens 仍把 VHDL 用户当一等公民。[厂商]

---

## 3. 编译/运行性能与可扩展性

**结论先行：** 两边都有并行仿真；**没有公开独立 bake-off**。能写的是各自机制 + 厂商数字（标注）+ 工程师限制条件。

### 3.1 Synopsys VCS — Fine-Grained Parallelism 等

**机制（厂商）：** 编译时开 FGP，**运行时**再选核数，不必为每种机器重编。同一引擎跑串行和并行。支持 Xprop、Native Low Power、SDF、并行 FSDB dump。另有 partition compile、precompiled IP、save/restore、constraint solver 优化、DTL、DPO、ICO。  
https://www.synopsys.com/verification/simulation/vcs.html  

**厂商数字（全部不可当独立基准）：**

| 声明 | 来源 | 日期 |
|---|---|---|
| FGP：RTL 最高约 2×、门级 5× | VCS datasheet PDF | 未标注独立年份；现仍挂产品站 |
| SemiEngineering 赞助博文：长测试 RTL 3–5×、GLS 最高 10×；scan 甚至 10–30× | https://semiengineering.com/simulation-go-parallel-or-go-home/ 作者 Taruna Reddy（Synopsys PMM） | **2020-02-27**（早于本窗口，仅作机制说明） |
| 同文限制：TB 占主导、大量 PLI/DPI、交互式、短测试 → FGP 收益有限 | 同上 | 2020 |
| DPO：SNUG 用户案例回归 TAT 再降（文内 1.13×/1.58×/25%） | Synopsys 博客 “Enhancing Chip Design Simulation with AI” | 文内引 SNUG Singapore **2022** |
| ICO：Qualcomm DVCon US 2023 — 覆盖左移 1.5 周；某项目 grid 降 10–15%；晚项目多发现 30% TB 问题 | Synopsys 博客转述 Qualcomm | DVCon US **2023**；博客仍在线 |

**[anecdotal]** UC Berkeley Chipyard GitHub issue #1081：开 `-fgp` 时 DPI/参数解析会打架；维护者称 *“chipyard design may not benefit due to low EPC (event per cycle)”*。说明 FGP 对低事件密度设计不是免费午餐。  
https://github.com/ucb-bar/chipyard/issues/1081

### 3.2 Siemens Questa One Sim — ParallelSim / SmartCompile / 覆盖与 DFT 加速

**机制（厂商）：** ParallelSim + smart auto-partitioning；SmartCompile 针对 3DIC/AI 加速器缩短 TAT；multi-test profiler；Sim CX 先进约束求解；Sim DX + Tessent 加速 DFT pattern；Sim Xact 用 formal 去 GLS 假 X / 零延时竞争。  
https://www.siemens.com/en-gb/products/ic/questa-one/simulation/questa-one-sim/

**厂商数字（2025-05-13 新闻稿，全部 [厂商]）：**

- Coverage Acceleration：**比传统 TB solver 快 50× 达到覆盖目标**  
- DFT Simulation Acceleration：**8×** 更快门级 DFT 串行 pattern（靠 Parallel Simulation；绑 Tessent SSN）  
- Fault Simulation Acceleration：**48×**  
- Stimulus Free Verification：复杂开源 SoC 参考设计 **>24h → <1 min**  
- Microsoft（Selim Bilgin）：QDX “weeks to days”；Azure Cobalt 100 上 **再高最多 20%**  
- Arm（Karima Dridi）：AArch64 上性能/成本/回归时间改善（无数字）  
- MediaTek：Property Assist 省 “weeks”；Regression Navigator 把最可能 fail 的测试先跑，省 “days”  

https://news.siemens.com/en-us/siemens-questa-one/  **2025-05-13**

**Altera FPGA Edition vs 旧 ModelSim FPGA Edition（Siemens 测，3 个设计）：Verilog 最高 2.5× / VHDL 1.25×。Starter = 完整 FPGA Edition 平均 40% 性能。完整版容量最多 5000 instance（不含预编译库）。**  
https://www.altera.com/products/development-tools/quartus-prime/questa  
[厂商测量 + 容量硬限制，对 FPGA 用户是真实约束]

### 3.3 X-prop / 随机稳定性

- 三家都有 X-prop 产品化（Questa X-debug/Xact；VCS Xpropagation；Xcelium XPR）。**无公开横向精度对比。**  
- 随机稳定性：本调研 **未找到** 2023–2026 说明 “VCS vs Questa seed 可移植” 的官方保证。UVM 跨仿真器 **不应假设** 同一 seed 产生同一刺激。不要编造稳定性结论。

### 3.4 编译时间抱怨 [anecdotal]

- Altera Community 2025：Questa 2023.4–2025.1 在 Windows 上 **cd / 读 modelsim.ini 可卡数十秒**，2021 版明显快。编译本身不慢，GUI/启动慢。  
  https://community.altera.com/discussions/quartus-prime/intel-questasim-is-very-slow-for-changing-directory--compiling/313408  
- StackOverflow 2023-11-29：Questa 默认优化导致波形里看不到信号，需 `vsim -voptargs=+acc` 或 GUI full visibility——**可见性与速度的经典权衡**。  
  https://stackoverflow.com/questions/77573414/

---

## 4. Debug：Verdi vs Visualizer

两边都覆盖：波形、源码、连通性、UVM class、transaction、断言、UPF、协议、仿真加速联调。差异在 **生态锁定与习惯**，不是功能有无。

| | Siemens Visualizer | Synopsys Verdi |
|---|---|---|
| 波形库 | 自有（与 Questa/Veloce 绑定） | **FSDB**（厂商称最普及；第三方仿真器也可写 FSDB） |
| UVM | class 进波形、UVM hierarchy、UVM schematic、config_db、live breakpoint | SVTB/UVM/PSS、transaction recording、Protocol Analyzer |
| VHDL | 有专门 VHDL 用户 webinar | 混合语言靠 VCS 3-step + KDB |
| 功耗 | UPF overlay | Power-Aware：可视化 power intent、追功耗错误 |
| AMS | Visualizer MS（Symphony Pro） | Verdi AMS |
| 仿真加速 | 与 Veloce 同一 cockpit | 与 ZeBu/HAPS 直连 |
| AI | Questa One / VIQ（回归预测、覆盖分析） | AI failure analysis、regression debug automation |
| 第三方仿真 | 主推本家引擎 | 明确 “debug third-party tool results via FSDB” |

出处：Visualizer https://www.siemens.com/en-us/products/ic/questa-one/debug-analysis/visualizer-debug/ ；Verdi https://www.synopsys.com/verification/debug/verdi.html ；verdi-ds.pdf ©2024。

**实务含义（非基准）：** ASIC 验证团队大量存量 FSDB/Verdi 技能 → 换 Visualizer 成本高。FPGA 设计师从 ModelSim GUI 上来 → Visualizer/Questa classic GUI 迁移路径更短（Questa Base 宣传保留 Classic GUI）。Verdi 的 FSDB 第三方开放性是真实生态优势（厂商自称 + 业界习惯，无市占数字）。

---

## 5. 覆盖收敛与回归管理

**不要把 Cadence vManager 算进 Siemens。** Siemens 侧是 **VRM + Verification IQ**。

### Siemens

- **VRM**（2024.2 UG）：回归执行、结果目录、与脚本集成。ISO 26262 相关章节在手册目录里。  
  https://ww1.microchip.com/downloads/aemDocuments/documents/FPGA/swdocs/questasim/vrm_user_2024_2.pdf （2024-06）  
- **Verification IQ**（现 Questa One VIQ）：浏览器、零安装、公私有/混合云。Regression Navigator 预测先跑易失败测试；Coverage Analyzer 做协同覆盖收敛。Fact sheet 写与 VRM 紧耦合。  
  https://www.siemens.com/en-us/products/ic/questa-one/verification-iq/  
- **Sim CX：** 覆盖加速约束求解（厂商 50×，见 §3.2）。

### Synopsys

- VCS 内建规划/覆盖/closure + **ICO**（强化学习，Qualcomm DVCon 2023 案例，见 §3.1）。  
- **Verdi VMS：** 规划、编译、回归、覆盖标注、关系数据库。预配置 VCS 流程。  
- **VC Execution Manager：** Verdi datasheet 写 VMS 与之集成。  
- **VC Formal FCA：** 不可达覆盖排除，覆盖库与 VCS 合并（厂商博客）。

两边 2025–2026 都在卖 “AI 决定下一条测试 / 先跑会挂的测试”。**无独立比较。**

---

## 6. FPGA 向流程（本用户重心）

### 6.1 AMD Vivado — 两边都是一等第三方，但 OS 不对称

**Vivado 2025.1 UG900 Supported Simulators**（搜索结果摘录，页面为 JS 应用，抓取工具未渲染；以 AMD 文档标题/表格为准）：

| 仿真器 | 版本 | IDE 集成 |
|---|---|---|
| AMD Vivado Simulator | 2025.1 | 是 |
| Siemens EDA Questa Advanced Simulator | 2024.3_3 (SE) | 是 |
| Siemens EDA ModelSim | 2024.3 (DE) | 是 |
| Synopsys VCS | W-2024.09-SP1 | 是 |
| Cadence Xcelium | 24.09.001 | 是 |
| Aldec Rivera-PRO / Active-HDL | 2024.10 / 15.0 | 是 |

https://docs.amd.com/r/2025.1-English/ug900-vivado-logic-simulation/Supported-Simulators  

**Vivado 2025.2 UG900 平台表：**

| | RHEL 64 Linux | Windows 64 |
|---|---|---|
| ModelSim DE | Yes | Yes |
| Questa Advanced | Yes | Yes |
| Xcelium | Yes | **NA** |
| VCS | Yes | **NA** |
| Active-HDL | NA | Yes |
| Riviera-PRO | Yes | Yes |

https://docs.amd.com/r/en-US/ug900-vivado-logic-simulation/Simulating-with-Third-Party-Simulators  

**[anecdotal + AMD AE]** Vivado 2025.2 官方 Questa = 2025.2；用户装 Questa 2026.1 会 WARN 不兼容。从 2026.1 起 `modelsim.ini` **改名为 `questa.ini`**。  
https://adaptivesupport.amd.com/s/question/0D5Pd00001VQinwKAD/

**Intel/Altera 捆绑 Questa 不能当 Vivado 仿真器用**（器件/库锁定）。  
https://adaptivesupport.amd.com/s/question/0D54U00008Udq1SSAR/

### 6.2 Altera/Intel Quartus — Questa 是亲儿子，VCS 能用但 Linux-only

**Quartus Prime Pro 26.1 支持表（文档日期 2026-08-10）：**

| Vendor | Simulator | Version | Platform |
|---|---|---|---|
| Altera | Questa-Altera FPGA Edition | 2025.3 | Win+Linux 64 |
| Siemens EDA | QuestaSIM (Core/Prime) | 2025.3 | Win+Linux 64 |
| Synopsys | VCS | X-2025.06-SP1-1 | **Linux only** |
| Cadence | Xcelium | 25.09.011 | Linux only |

注：Quartus 25.1+ VCS MX → 3-step；2-step deprecated。Agilex 3/5 **无 2-step**。  
https://docs.altera.com/r/docs/683870/26.1/quartus-prime-pro-edition-user-guide-third-party-simulation/supported-simulators  
https://docs.altera.com/r/docs/683870/26.1/quartus-prime-pro-edition-user-guide-third-party-simulation/synopsys-vcs-support （2026-04-22）

**Questa-Altera FPGA Edition 要点（Altera 产品页）：**

- Quartus 购买附带；也可单买。许可证 **购后 12 个月到期，每年要在 SSLC 重生**。  
- Starter：**免费一年期**，须 SSLC 领取，每年续。  
- 完整版：**最多 5000 instance**（不含预编译库）。超限：Altera 2025-12-15 差异表写 Questa FPGA Edition 会 **error**（旧 ModelSim 只是 warning）；强行 suppress 后仿真 **慢 30×**（文档原句）。  
- **只支持 Quartus 仿真库**；要 Xilinx/其他库必须升 Core/Prime。  
- 比 Questa Core/Prime **更慢**（Altera FAQ 原文）。  
- Win+Linux 64。NativeLink 从 Quartus 拉起。  

https://www.altera.com/products/development-tools/quartus-prime/questa  
https://docs.altera.com/r/docs/691278/21.3/questa-intel-fpga-edition-quick-start-intel-quartus-prime-pro-edition/known-differences-between-the-questa-intel-fpga-edition-and-modelsim-intel-fpga-edition （2025-12-15）

Intel 2021-05-14 ADV 2122：ModelSim-Intel FPGA Edition **被 Questa-Intel FPGA Edition 替换**。

### 6.3 HLS / 综合邻接

- **Siemens Catapult HLS：** C++/SystemC → ASIC 或 FPGA（厂商称技术无关）。验证用 Catapult Coverage / Formal / SLEC + **Questa HL-SYC**。与 Vivado HLS 互转有 Siemens 白皮书（偏旧，2021 博客）。**仿真器锁定在 Questa 家族，不是 VCS。**  
  https://www.siemens.com/en-us/products/ic/catapult-high-level-synthesis/  
- **Synopsys Synplify：** 多厂商 FPGA 综合；**直接生成 VCS 仿真脚本**（RTL / post-syn / post-P&R，Linux）。Synplify 宣称 VHDL-2019。  
  https://www.synopsys.com/verification/fpga-simulation.html  
- AMD Vitis HLS / Intel HLS Compiler：走各自 `compile_simlib` + 上表第三方仿真器，不是仿真器本身的差异。

### 6.4 FPGA 用户怎么读

1. **Windows 笔记本 + Vivado/Quartus GUI：** Questa/ModelSim 能跑；**VCS/Xcelium 官方不支持 Windows。**  
2. **Altera 器件、预算紧：** FPGA Edition / Starter 是默认路径；注意 5000 instance 与年检许可。大设计要买 Core/Prime。  
3. **AMD 器件 + 企业 UVM 回归：** Vivado 原生仿真器对 UVM 大规模回归通常不够（本调研未引用独立基准，这是行业常识级经验——**不写成测量结论**）。Questa 与 VCS 都被 Vivado 官方支持；选谁取决于 OS、是否已有 Verdi、是否混 VHDL。  
4. **Intel FPGA Edition 不能拿去仿 Xilinx。**

---

## 7. 生态锁定

| 维度 | Siemens | Synopsys |
|---|---|---|
| VIP | Avery（2025 并入 Questa One 叙事）；Altera 表：Questa/VCS/Xcelium 均可跑 Siemens EDA VIP | VC VIP + Verdi Protocol Analyzer（厂商 “native”） |
| 仿真加速 | Questa ↔ Veloce CS 同一 VIP/CTS（厂商） | VCS congruent ↔ ZeBu；Verdi 统一 debug |
| Formal | Questa Formal / OneSpin 血统（产品页 Questa One formal）；与仿真同伞 | VC Formal Unified Compile |
| 低功耗 | UPF 4.0 Sim PA + Visualizer | Native Low Power + VC LP + Verdi PA |
| AMS | Symphony 可接 **多家数字仿真器**；Symphony Pro **只 Questa** | VCS PrimeSim AMS 内核级；HSPICE 黄金模型（厂商） |
| HLS | Catapult ↔ Questa | Synplify ↔ VCS/Verdi |
| FPGA 厂商库 | Altera 亲儿子；Vivado 官方支持 | Vivado/Quartus 官方支持但 Linux-only |
| CI/云 | VIQ 浏览器云；Arm 引言提 on-prem + cloud | VCS 产品页未在本调研中展开云 SKU；DPO/ICO 面向网格回归 |
| 波形交换 | 偏本家 | FSDB 事实标准（厂商自称） |

**锁定含义：** 选仿真器几乎等于选 debug+VIP+（将来）emulation 合同。AMS 若必须用 Spectre，Cadence 合仿更顺；必须用 HSPICE 签核，VCS+PrimeSim 更顺；必须用 AFS，Symphony±Questa。数字纯 FPGA 团队很少被 AMS 决定。

---

## 8. 许可 / 成本 / 学术（无公开价，不编）

**未找到 2023–2026 官方公开价目。** 2001 年 VCS TSL $20,250 等历史新闻过时，不采用。

能 sourced 的结构：

- **Altera Questa FPGA Edition：** Quartus 购买附带或单买；**12 个月许可，每年 SSLC 重生**。Starter 免费但要年领。完整版 5000 instance 帽。  
- **Siemens 高校：** Higher Education Software Program；管理员邮件 `eda_academic.sisw@siemens.com` 拿 ModelSim/Questa 课堂套件。  
  https://www.siemens.com/en-us/company/academic-future-workforce/educators/eda-higher-education-software/  
- **ModelSim Student Edition：** 页面写因 **美国联邦法规** 暂停在线免费发放。  
  https://www.siemens.com/en-us/products/ic/questa-one/modelsim-student-edition-unavailable/  
- **Missouri S&T 2024-04-17：** 校园 ModelSim 12.0 授权拿不到，改 QuestaSim。说明 **ModelSim 老许可正在枯竭**。  
  https://econnection.mst.edu/2024/04/switch-from-modelsim-12-0-to-questasim/  
- **Synopsys SARA：** 学校会员制，SolvNetPlus + 近全套 EDA（含仿真课程实验）。个人学生一般不能直接买 VCS。  
  https://www.synopsys.com/academic-research/university.html  

行业合同是浮动 license + 年维，价格走销售。**不要在汇报里写美元数字。**

---

## 9. 弱点与社区抱怨（标明 anecdotal / 政策）

### 9.1 Siemens / Questa

| 点 | 性质 | 出处 |
|---|---|---|
| VHDL-2019 不完整且 2024→2025 行为回退 | anecdotal + 厂商社区 | OSVVM；Siemens community |
| Windows GUI/cd 变慢（2023.4–2025.1） | anecdotal | Altera Community |
| 默认 vopt 藏信号 | anecdotal | StackOverflow 2023-11 |
| FPGA Edition 5000 instance；超限可慢 30× | **官方第三方文档** | Altera 2025-12-15 |
| FPGA Edition 不能仿非 Altera 库 | 官方 | Altera FAQ |
| ModelSim SE 免费下载暂停 | 官方 | Siemens 页面 |
| Vivado 版本锁 + 2026.1 ini 改名 | anecdotal + AMD AE | AMD forum |
| 性能数字几乎全是 2025-05 PR | 厂商营销 | Siemens PR |

### 9.2 Synopsys / VCS

| 点 | 性质 | 出处 |
|---|---|---|
| **无 Windows 仿真**（Vivado/Quartus/MathWorks 均标 Linux only） | **官方第三方** | AMD UG900；Altera 2026-08-10；MathWorks DPI 文档 |
| 混语言必须 3-step；Agilex 3/5 无 2-step | 官方第三方 | Altera 2026-04-22 |
| Vivado VHDL 库 `-kdb` 易踩坑 | anecdotal | AMD forum |
| FGP 对低 EPC / TB 主导 / DPI 重设计收益有限 | 厂商自己也写 + GitHub | SemiEng 2020；Chipyard #1081 |
| “highest performance / majority of top companies” 无独立审计 | 厂商营销 | VCS 产品页 |
| DVE 技能在新项目贬值，但旧脚本仍在 | anecdotal | AMD forum 2024 |

### 9.3 中国出口管制（2024–2026，有一手声明）

**不要写成 “中国买不到 Questa/VCS”。** 2025 年发生过一次短暂切断再恢复。

1. **2025-05：** BIS 以 “is informed” 信函要求对 ECCN **3D991 / 3E991** 对华（及中国军事最终用户）出口许可。Cadence、Synopsys 公开披露；Siemens 后来确认收到 5 月 23 日信。  
   法律综述：https://www.hsfkramer.com/notes/sanctions/2025-posts/us-and-china-agree-to-framework-addressing-export-control-issues  
2. **2025-07-02：** Synopsys 声明：BIS 通知 **5 月 29 日对华限制已立即撤销**，正在恢复中国区访问。  
   https://news.synopsys.com/2025-07-02-Synopsys-Issues-Statement-in-Connection-to-the-Lifting-of-Recent-U-S-Export-Restrictions-Related-to-China  
3. **2025-07-03：** Siemens Tony Hemmelgarn 声明：5 月 23 日信中的限制 **不再有效**；**恢复 ECCN 3D991/3E991 的软件与技术访问**（仍须遵守其余出口法规），恢复对华销售与支持。  
   https://news.siemens.com/en-us/siemens-eda-china-update/  
4. Reuters 2025-07-03：三家均在恢复中国客户访问。  
   https://www.reuters.com/world/china/siemens-says-us-has-lifted-chip-software-curbs-china-bloomberg-news-reports-2025-07-03/  
5. CRS 报告 R48642：2025-07 BIS 在中方恢复稀土磁材许可后撤销 EDA 许可要求。  
   https://www.congress.gov/crs_external_products/R/PDF/R48642/R48642.3.pdf  

**对用户含义：** 许可法律上仍受 EAR 约束；2025 年 5–7 月证明 **工具可被行政信函快速关掉**。先进节点/军用最终用户另有既有规则。仿真器选型不能假设 “德国西门子就不受美国 EAR”——Siemens EDA 软件同样被 3D991/3E991 套住。

---

## 10. 仿真加速对比（只为理解仿真器绑定）

| | Siemens Veloce CS | Synopsys ZeBu |
|---|---|---|
| 仿真器搭档 | Questa One Sim；同一 Avery CTS | VCS congruent mode |
| Debug | Visualizer | Verdi |
| 近期硬件 | Strato CS：CrystalX；原型用 AMD VP1902 | ZeBu-200 / Server 5：AMD VP1902 |
| 厂商容量声称 | 40MG–40+BG | Server 5 “beyond 60BG”；ZeBu-200 至 15.4BG 等 | 

全部 [厂商]。大 SoC 团队选 emulation 合同会反向锁定仿真器。纯 FPGA 团队通常碰不到。

---

## 11. 怎么选（给 FPGA vs ASIC 团队）

### FPGA 团队（含金融/低延迟、Windows 实验室、Vivado/Quartus 日常）

1. **默认 Questa 路径更顺：** Windows+Linux、Quartus 捆绑、Vivado IDE 集成、VHDL 一等、从 ModelSim 脚本可迁移。  
2. **先分清 SKU：** Starter / Altera FPGA Edition（5000 inst）/ Questa Core / Prime / One Sim。OEM 版不能仿 AMD 库。  
3. **只有在这些成立时才上 VCS：** 已有 Linux farm、已有 Verdi 技能/FSDB 资产、UVM 回归规模大到值得迁、或公司 ASIC 流程已经是 VCS。  
4. **不要为 FPGA 桌面流买 VCS**——官方无 Windows。  
5. HLS：Catapult 用户留 Questa；Synplify 用户 VCS 脚本是现成的。多数 Vivado HLS 用户与两者都只是 `compile_simlib` 关系。

### ASIC / 大规模 SoC UVM 团队

1. **VCS+Verdi 是存量最大的组合**（厂商自称 “majority of top companies”——**不当成市占**，但 VIP/FSDB/招聘技能确实围绕它转）。FGP/ICO/DPO 和 Qualcomm 级案例都在这栈上。  
2. **Questa One 值得 bake-off 的场景：** VHDL 混编多、Tessent DFT 门级 pattern 是痛点、已有 Veloce、要 UPF 4.0 一体化、想试 Coverage Acceleration / Regression Navigator。2025-06 之后新合同会看到 Questa One 包装。  
3. **Cadence Xcelium** 若团队已有 Jasper/Palladium/Spectre，第三极不是“落后选项”。  
4. **务必自跑 DUT：** 约束求解、FGP vs ParallelSim、覆盖收敛，设计相关极强。

### 混合 FPGA+ASIC / 本用户画像

金融 FPGA 研究：优先 **Questa（Core 或 Vivado 支持的 Advanced）+ Visualizer**，Windows 友好，Quartus/Vivado 都能挂。若与 ASIC 验证组共用 UVM VIP 且对方是 VCS，再评估 Linux 回归机上的 VCS 作为第二仿真器——**不要假设 UVM 随机在两器之间 seed 兼容。**

---

## 12. 来源清单（标题 + 日期 + 类型）

1. Siemens, “Siemens leverages AI… Questa One smart verification solution”, **2025-05-13**, 厂商新闻稿. https://news.siemens.com/en-us/siemens-questa-one/  
2. Siemens, Questa One 产品页, 抓取 **2026-08-31**, 厂商. https://www.siemens.com/en-us/products/ic/questa-one/  
3. Siemens, Questa One Sim 产品页, 抓取 **2026-08-31**, 厂商. https://www.siemens.com/en-gb/products/ic/questa-one/simulation/questa-one-sim/  
4. Siemens, Questa Visualizer Debug Environment, 抓取 **2026-08-31**, 厂商. https://www.siemens.com/en-us/products/ic/questa-one/debug-analysis/visualizer-debug/  
5. Siemens, Questa One Verification IQ, 抓取 **2026-08-31**, 厂商. https://www.siemens.com/en-us/products/ic/questa-one/verification-iq/  
6. Siemens, Questa One Sim PA / UPF 4.0, 抓取 **2026-08-31**, 厂商. https://www.siemens.com/en-us/products/ic/questa-one/simulation/power-aware/  
7. Siemens, Tony Hemmelgarn 对华 EDA 声明, **2025-07-03**, 厂商/监管. https://news.siemens.com/en-us/siemens-eda-china-update/  
8. Siemens, ModelSim Student Edition Unavailable, 抓取 **2026-08-31**, 厂商. https://www.siemens.com/en-us/products/ic/questa-one/modelsim-student-edition-unavailable/  
9. Siemens, Veloce CS, 抓取 **2026-08-31**, 厂商. https://www.siemens.com/en-us/products/ic/hav/veloce-cs/  
10. Siemens, Symphony mixed-signal, 抓取 **2026-08-31**, 厂商. https://www.siemens.com/en-us/products/ic/symphony/  
11. Siemens, Catapult HLS, 抓取 **2026-08-31**, 厂商. https://www.siemens.com/en-us/products/ic/catapult-high-level-synthesis/  
12. Daniel Payne, “Questa One Updated at DAC 2026”, SemiWiki, DAC **2026**, 行业访谈（亲 Siemens）. https://semiwiki.com/eda/372370-questa-one-updated-at-dac-2026/  
13. Synopsys, VCS 产品页, 抓取 **2026-08-31**, 厂商. https://www.synopsys.com/verification/simulation/vcs.html  
14. Synopsys, VCS datasheet PDF, 厂商（“majority of top 20” 等）. https://www.synopsys.com/content/dam/synopsys/gated-assets/verification/vcs-ds.pdf  
15. Synopsys, Verdi 产品页, 抓取 **2026-08-31**, 厂商. https://www.synopsys.com/verification/debug/verdi.html  
16. Synopsys, Verdi datasheet, ©**2024**, 厂商. https://www.synopsys.com/content/dam/synopsys/verification/datasheets/verdi-ds.pdf  
17. Synopsys, VC Formal 产品页, 抓取 **2026-08-31**, 厂商. https://www.synopsys.com/verification/static-and-formal-verification/vc-formal.html  
18. Synopsys, “How Qualcomm Accelerated Coverage Closure…”, 博客转述 DVCon US **2023**, 客户经厂商. https://www.synopsys.com/blogs/chip-design/ai-chip-design-verification-qualcomm.html  
19. Taruna Reddy, “Simulation: Go Parallel Or Go Home”, SemiEngineering, **2020-02-27**, 厂商赞助博文（FGP 机制）. https://semiengineering.com/simulation-go-parallel-or-go-home/  
20. Synopsys, FPGA simulation/synthesis portfolio, 抓取 **2026-08-31**, 厂商. https://www.synopsys.com/verification/fpga-simulation.html  
21. Synopsys, Synplify 产品页, 抓取 **2026-08-31**, 厂商. https://www.synopsys.com/implementation-and-signoff/fpga-based-design/synplify.html  
22. Synopsys, University Software Program (SARA), 抓取 **2026-08-31**, 厂商. https://www.synopsys.com/academic-research/university.html  
23. Synopsys, 对华出口限制解除声明, **2025-07-02**, 厂商/监管. https://news.synopsys.com/2025-07-02-Synopsys-Issues-Statement-in-Connection-to-the-Lifting-of-Recent-U-S-Export-Restrictions-Related-to-China  
24. Synopsys, PrimeSim Pro datasheet（VCS PrimeSim AMS；FineSim/CustomSim 后继名）, 厂商. https://www.synopsys.com/implementation-and-signoff/resources/datasheets/primesim-pro-ds.html  
25. Cadence, Xcelium Logic Simulation, 抓取 **2026-08-31**, 厂商. https://www.cadence.com/en_US/home/tools/system-design-and-verification/simulation-and-testbench-verification/xcelium-simulator.html  
26. AMD, UG900 2025.1 Supported Simulators, **2025.1**, 官方第三方. https://docs.amd.com/r/2025.1-English/ug900-vivado-logic-simulation/Supported-Simulators  
27. AMD, UG900 2025.2 Simulating with Third-Party Simulators（Win vs Linux 表）, **2025.2**, 官方第三方. https://docs.amd.com/r/en-US/ug900-vivado-logic-simulation/Simulating-with-Third-Party-Simulators  
28. Altera, Quartus Prime Pro UG Third-Party Simulation — Supported Simulators, **2026-08-10**, 官方第三方. https://docs.altera.com/r/docs/683870/26.1/quartus-prime-pro-edition-user-guide-third-party-simulation/supported-simulators  
29. Altera, Synopsys VCS Support（3-step vs 2-step）, **2026-04-22**, 官方第三方. https://docs.altera.com/r/docs/683870/26.1/quartus-prime-pro-edition-user-guide-third-party-simulation/synopsys-vcs-support  
30. Altera, Questa-Altera FPGA Edition 产品页, 抓取 **2026-08-31**, 官方第三方/OEM. https://www.altera.com/products/development-tools/quartus-prime/questa  
31. Altera, Questa vs ModelSim FPGA Edition 已知差异, **2025-12-15**, 官方第三方. https://docs.altera.com/r/docs/691278/21.3/questa-intel-fpga-edition-quick-start-intel-quartus-prime-pro-edition/known-differences-between-the-questa-intel-fpga-edition-and-modelsim-intel-fpga-edition  
32. Intel, ADV 2122 Replacement of ModelSim-Intel FPGA Edition, **2021-05-14**, 官方（背景）. https://www.intel.com/content/www/us/en/content-details/677755/customer-advisory-adv-2122-replacement-of-modelsim-intel-fpga-edition-software.html  
33. Reuters, US lifts curbs for chip design software…, **2025-07-03**, 独立新闻. https://www.reuters.com/world/china/siemens-says-us-has-lifted-chip-software-curbs-china-bloomberg-news-reports-2025-07-03/  
34. CRS, “U.S. Export Controls and China: Advanced Semiconductors” R48642, 2025 修订本, 美国国会. https://www.congress.gov/crs_external_products/R/PDF/R48642/R48642.3.pdf  
35. Daniel Payne, “Mastering Mixed-Signal Verification with Siemens Symphony”, SemiWiki, **2024-01-17**, 行业（Symphony 可接 Questa/VCS/Xcelium）. https://semiwiki.com/eda/341021-mastering-mixed-signal-verification-with-siemens-symphony-platform/  
36. Siemens Community, “Does Questa support VHDL 2019?”, 2024–2025 帖, 厂商论坛. https://community.sw.siemens.com/s/question/0D5Vb0000083hlgKAA/does-questa-support-vhdl-2019  
37. OSVVM forum, “Weird QuestaSim Base Error”, **2025**, anecdotal. https://osvvm.org/forums/topic/weird-questasim-base-error  
38. Altera Community, Questa directory/compile slowness, **2025**, anecdotal. https://community.altera.com/discussions/quartus-prime/intel-questasim-is-very-slow-for-changing-directory--compiling/313408  
39. StackOverflow, Questa vish-4014 / vopt visibility, **2023-11-29**, anecdotal. https://stackoverflow.com/questions/77573414/  
40. AMD Adaptive Support, Questa 2026.1 vs Vivado 2025.2 / questa.ini, anecdotal+AE. https://adaptivesupport.amd.com/s/question/0D5Pd00001VQinwKAD/  
41. AMD Adaptive Support, Questa-Intel FPGA Edition vs Vivado, anecdotal. https://adaptivesupport.amd.com/s/question/0D54U00008Udq1SSAR/  
42. Chipyard #1081, VCS FGP, anecdotal. https://github.com/ucb-bar/chipyard/issues/1081  
43. Missouri S&T, Switch from ModelSim 12.0 to QuestaSim, **2024-04-17**, 高校 IT. https://econnection.mst.edu/2024/04/switch-from-modelsim-12-0-to-questasim/  
44. Questa VRM User Guide v2024.2, Siemens, **2024-06**（Microchip 镜像）. https://ww1.microchip.com/downloads/aemDocuments/documents/FPGA/swdocs/questasim/vrm_user_2024_2.pdf  
45. MathWorks, Generate Cross-Platform DPI（VCS Linux only；Questa Win+Linux）, 文档, 官方第三方. https://www.mathworks.com/help/hdlverifier/ug/generate-cross-platform-dpic-components.html  

---

## 13. 明确没有写进结论的东西

- 任何 “Questa 比 VCS 快 x 倍” 的独立数字  
- 全球/中国市占百分比  
- 许可证美元/人民币价格  
- DVE 官方停售日  
- FineSim/CustomSim 作为当前产品名（现公开名为 PrimeSim 家族）  
- Cadence vManager 属于 Siemens（它属于 Cadence）  
- 2026-08 BIS sub-7nm EDA 新规（仅出现在不可靠转载站、日期互相矛盾）  
- UVM seed 跨仿真器稳定  

调研完成。父代理可据此写今晚的对比稿；数字凡未标 [官方第三方] 或 [anecdotal] 的，一律当 [厂商]。
