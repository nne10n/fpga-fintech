# 不同 Agent 工具在 RTL 设计/编码任务上的能力与适用性调研（截至 2026-09）

> 证据分级：【论文自测】= 作者自评/预印本；【公开榜单】= 第三方可复现评测；【厂商宣传】= PR/官网；【二手】= 媒体/博客。
> 核查手段：因本环境 web_fetch 被沙箱阻断（域名解析到非公网 IP），改用 curl 直取 arXiv/厂商原文。

## ① 通用编码 Agent / IDE 在 HDL 场景

| 工具 | 形态 | RTL 相关公开证据 | 能否闭环调 EDA | 证据等级 | 来源 |
|---|---|---|---|---|---|
| Claude Code | CLI agent | HWE-Bench 中被用作官方 scaffold（DeepSeek V4 系用 1M 上下文跑）；CVDP agentic 单一 harness（VerilogCoder 类）中 Claude Opus 4.6 非 agentic 50.66%、带工具 43.48% | 可（shell 内调 iverilog/verilator/yosys/vvp，无内建语义） | 【公开榜单】 | [hwe-bench](https://github.com/pku-liang/hwe-bench)、[arXiv 2603.19347](https://arxiv.org/html/2603.19347) |
| OpenAI Codex (CLI/云) | CLI/云 agent | HWE-Bench 官方 scaffold 之一；CVDP agentic 中 GPT Codex-5.3 非 agentic 49.67%、带工具 45.65%（**优于 Claude 的带工具表现**） | 同上（纯 shell） | 【公开榜单】 | 同上 |
| GitHub Copilot (Agent Mode/coding agent) | IDE + 云 agent | 未见任何 HDL 专项公开评测；学术论文与榜单均未纳入 | 弱（无 RTL 工具链集成） | 未核实 | — |
| Cursor | IDE | CVDP 论文将其列为 agentic 助手动机（Anysphere 2025），但**无 RTL 实测数据** | 弱 | 【二手】 | [CVDP arXiv 2506.14074](https://arxiv.org/abs/2506.14074) |
| Windsurf / Cline / Roo Code / Kilo Code | IDE/插件 | 无 RTL 公开评测；仅在工具兼容性列表中出现 | 未核实 | 未核实 | — |
| Aider / OpenHands | 开源 CLI/多智能体 | 被 2603.19347 作为 agentic 范式背景引用（OpenHands 多智能体、Terminus 终端原生），**无 HDL 定量结果** | 理论上可 | 【二手】 | [arXiv 2603.19347](https://arxiv.org/html/2603.19347) |
| Devin | 云 agent | 无 HDL 公开评测 | 未核实 | 未核实 | — |
| Gemini CLI / Qwen Code | CLI | Gemini-3.1 Pro Preview 在 CVDP 非 agentic 达 **58.61%（当前最高）**，属模型而非该 CLI 的 harness 结果 | 未核实（CLI 层） | 【论文自测】 | [arXiv 2603.19347](https://arxiv.org/html/2603.19347) |
| 2026 新兴 | — | **HORIZON**（NVIDIA Research，GPT-5.3 为 backbone）：把 HDL 设计建模为 Git 仓库级演化，独立 worktree + 可执行验收门（编译/仿真/覆盖率/断言），在 ChipBench、RTLLM-2.0、Verilog-Eval 及 CVDP 多个类目达 **100% 完成率**；91% token 为缓存输入 | **是（最完整闭环）** | 【论文自测】+【二手】 | [semiengineering](https://semiengineering.com/a-self-evolving-agent-framework-that-treats-hardware-design-as-repository-level-code-evolution-nvidia-research/)、[TechGig 2026-07](https://techgig.com/news/software-devops/nvidia-horizon-ai-agent-automates-rtl-hardware-design-with-100-benchmark-pass-rate/132207436) |

**关键结论（有公开 RTL 数据的只有 Claude Code、Codex、Gemini 系模型，且多为"模型分数"而非"工具分数"）**

## ② EDA 专用 Agent 与开源框架

| 名称 | 定位 | 量化效果 | 依赖私有 EDA | MCP/API | 等级/来源 |
|---|---|---|---|---|---|
| ChipAgents (2025) | RTL 生成/验证/调试/时序收敛 | 宣称 VerilogEval **97%** SOTA；$21M A 轮（2025-10），另加 $60M 扩展 A 轮；与 AWS 合作 | 自研平台 | API | 【厂商宣传】 [Bessemer](https://www.bvp.com/news/meet-the-founder-and-ceo-of-chipagents-william-wang)、[Semiconductor Digest](https://www.semiconductor-digest.com/chipagents-and-aws-partner-to-advance-ai-powered-semiconductor-engineering/) |
| Cadence ChipStack / AgentStack | RTL 生成、验证规划、形式分析、仿真、调试、收敛；Level-5 自主 | 宣称 RTL 验证循环 **40×+ 加速**，五周验证闭环→<1 天（NVIDIA 场景）；2025-11 收购 ChipStack，2026-02 首产品，2026-04 扩至 ViraStack/InnoStack | **是**（Xcelium/Jasper） | MCP + 兼容 Codex/Claude Code；NVIDIA OpenShell 沙箱 | 【厂商宣传】 [CIMdata 2026-06](https://www.cimdata.com/en/industry-summary-articles/item/30157-cadence-unveils-industry-s-first-fully-autonomous-virtual-engineer-for-chip-design-powered-by-nvidia) |
| Synopsys AgentEngineer | 全自主 debug/RCA 闭环 + 实现与 QoR 收敛 | debug 周期 **降 25–40%**（早期评估）；与 AMD/Microsoft Discovery 合作 | **是**（Fusion Compiler 等） | 是（Microsoft Discovery/Azure） | 【厂商宣传】 [Synopsys 2026-07-27](https://news.synopsys.com/2026-07-27-Synopsys-Advances-Agentic-AI-Chip-Design-with-AMD-and-Microsoft) |
| Siemens EDA | 自验证长时程 agent（物理引擎每步校验）；库表征 | 表征流程 **10× 加速**、配置小时→分钟、流程周→天；token 成本降 5–10× | **是**（Catapult/Questa/Calibre/Solido 等） | MCP 动态工具发现 + Agent Skills | 【厂商宣传】 [DQ India 2026-08](https://www.dqindia.com/semiconductors/siemens-introduces-self-verifying-eda-ai-agents-at-dac-2026-12256994) |
| NVIDIA ChipNeMo | 芯片领域 LLM（前代） | 已被 Nemotron 3.5/4 路线接续；无 2026 新 RTL 榜单 | 否 | — | 【二手】 |
| HORIZON (NVIDIA Research) | 通用 RTL 设计 agent 框架 | 见上表 | 否（iverilog/verilator/yosys/覆盖率开源栈） | 评测器可插拔 | 【论文自测】 |
| ChipCraftBrain (arXiv 2604.19856) | 多智能体 + 符号推理 RTL 生成 | VerilogEval-Human **97.x%**（与 ChipAgents 持平）；CVDP 302 子集高通过率；6 个专用 agent + PPO 编排，$0.06/problem 参照 MAGE 20×Sonnet | 否 | — | 【论文自测】 |
| ACE-RTL (arXiv 2602.10218) | RTL 专用 LLM + frontier reasoner 的"上下文演化" | 1.7M RTL 样本训练；并行 scaling 降低首成功迭代数 | 否 | — | 【论文自测】 |
| VerilogCoder / AutoChip / VeriAssist / RTLFixer | 开源 RTL agent 框架 | AutoChip 建立"文本反馈闭环"基线；VerilogCoder 用 AST 波形追踪做语义修复（双环：语法快环 + 语义慢环） | 否 | — | 【论文自测】 [Agentic EDA 综述 arXiv 2512.23189](https://arxiv.org/html/2512.23189) |
| **HAgent** (masc-ucsc) | 开源 AI 硬件 agent 框架 | Docker 化 EDA pipeline，YAML API，**支持 MCP server 模式** | 否 | MCP | 【开源】 [GitHub](https://github.com/masc-ucsc/hagent) |
| **mcp4eda** | MCP server 套件（Yosys/Verilator/Verible/GTKWave 等 8 个） | 无量化数据 | 否（开源工具链） | MCP | 【开源】 [GitHub](https://github.com/ssql2014/mcp4eda) |
| **fpgaZeroMCP** | MCP：lint→仿真→综合→P&R→烧录 + IP 核注册表 | UVM PASS/FAIL 判定解析、后台构建、命令白名单 | 否 | MCP | 【开源】 [GitHub](https://github.com/bard0-design/fpgaZeroMCP) |
| **rtl-skills** | Claude Code skills/agents 全流程（varch→vsynth→vtestgen→vdebug） | 无量化数据 | 否（含 Vivado） | Claude Code skill | 【开源】 [GitHub](https://github.com/phamcuong21478/rtl-skills) |
| **HWE-Bench** (PKU) | **榜单**：417 个真实硬件 bug 修复任务，6 个开源项目（ibex/cva6/caliptra/rocket-chip/XiangShan/OpenTitan），容器内真实仿真 fail-to-pass | 7 模型 × 4 agent 框架，最佳 **70.7%**；小核 >90%，复杂 SoC <65% | 否 | 否 | 【公开榜单】 [GitHub](https://github.com/pku-liang/hwe-bench) |
| Silogy / Aitomatic / Astrus / Xcelerium / ChipStack AI（独立） / Ricursive | 芯片 AI 初创 | Ricursive 2026-01 融资 **$300M / $4B 估值**；其余未核实 | 未核实 | 未核实 | 【二手】 [SiliconANGLE](https://siliconangle.com/2026/01/26/ricursive-intelligence-nabs-300m-speed-chip-design-ai/) |
| SemiKong | 开源半导体领域 LLM（Aitomatic 等） | 宣称上市时间缩短 **30%** | 否 | — | 【厂商宣传】 [Tom's Hardware](https://www.tomshardware.com/tech-industry/artificial-intelligence/semikong-is-the-worlds-first-open-source-semiconductor-focused-llm-it-claims-to-bring-new-chips-to-market-30-percent-faster) |

**公开榜单现状**：CVDP（783 题/13 类，含 agentic 格式，非 agentic 上限 34%→前沿 50–58%）、HWE-Bench（仓库级 bug 修复）、ChipVerilog（OpenCores 衍生，64 目标、~20,400 行；Claude Opus 4.5 语料 pass@1 83.13% 语法 / **23.55% 功能**，GPT-5.4 最优；跨模块目标功能率 ~0%）。VerilogEval/RTLLM 仍是主流自测口径。

## ③ 可落地的选型判断

1. **不要指望"通用 agent 开箱即用"**：CVDP 与 2603.19347 一致证明，朴素地把前沿模型套上工具外壳会**降低**成绩（Opus 4.6：50.66%→43.48%），有结构化的五步 harness 才能追平/超过非 agentic 基线。
2. **决定成败的是"验收门"而非模型规模**：HORIZON 的 Git worktree + 可执行验收谓词（编译/仿真/覆盖率/断言）是把通过率推到 100% 的核心机制；工具清单的边际收益很小。
3. **最有效的单点能力是"跑仿真"**：2603.19347 明确 `vvp` 仿真调用是与正确结果相关性最强的工具使用模式；Yosys/Verilator 扩展工具收益边际。
4. **仓库级 > 模块级是真实分水岭**：HWE-Bench 复杂 SoC 掉到 <65%，ChipVerilog 跨模块功能 pass@1 近 0。选型时必须用**自己仓库级别**的任务试，而不是 VerilogEval 分数。
5. **闭源 EDA 厂商 agent 只在自家工具链闭环**：Cadence/Synopsys/Siemens 的 40×、25–40%、10× 均绑定自有 signoff 引擎；若团队用开源栈（iverilog/Verilator/Yosys/OpenROAD），应走 **HAgent / mcp4eda / fpgaZeroMCP** 这类 MCP 路线。
6. **插件化路线成本最低**：`rtl-skills` 类 Claude Code skill 已覆盖"架构→RTL→lint→仿真→回归→Vivado 综合→文档"全流程，是把通用 agent 变成 RTL agent 的最短路径。
7. **HWE-Bench 是当前最接近工程现实的公开榜单**（真实 PR + 容器化 fail-to-pass + scaffold 可切换），应作为工具对比的首选基准；CVDP agentic 子集次之。
8. **成本要按"迭代次数"而非 token 单价估**：CVDP 上下文远大于 VerilogEval，多轮迭代成本叠加；HORIZON 91% 缓存命中是可参考的降本模式。

## ④ 证据薄弱 / 存疑处

- **ChipAgents 的 "97% VerilogEval"**：仅见厂商新闻稿与二手转载，**未找到公开论文或第三方复现**；ChipCraftBrain 将其作为对照并注明"在承认的方差范围内"，不等于独立验证。
- **通用 agent 的 RTL 分数被"模型分数"混淆**：Claude Code / Codex 在 CVDP 中的成绩来自研究者自建 harness，**不能等同于这两个产品本身的能力**；尚无 Copilot、Cursor、Windsurf、Cline、Roo Code、Kilo Code、Aider、Devin 的任何 HDL 公开实测。
- **NVIDIA ChipNeMo 的 2026 后续**：ChipNeMo 原论文定位为领域适配 LLM，未见 2026 年新版本或新榜单；HORIZON 属 Research 框架，非 ChipNeMo 续作，勿混为一谈。
- **HORIZON 的 "100% 完成率"**：论文自测 + 二手报道，其 benchmark 子集划分由作者自定义（CVDP 仅取 302/783），需谨慎外推。
- **Astrus / Xcelerium / Silogy / Aitomatic（2026 动态）**：未能核实到具体产品页与量化数据，标注"未核实"。
- **厂商加速数据（40× / 25–40% / 10×）** 全部为早期评估或客户场景宣传，无同行评审，不可作为采购依据。
- 本环境 web_fetch 被阻断，dev.to/Reddit 等社区口碑类证据未系统采集；纯用户口碑结论在本报告中一律标为"未核实"。
