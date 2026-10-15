# LLM/Agent 用于真实 RTL 设计的工程实践素材（调研截止 2026-09-14）

来源分级：【论文】【官方文档】【媒体】【社区】。GitHub 页面在本环境被解析为内网 IP 而无法直接抓取，**star 数与活跃度标注为"未核实"**，仅保留可验证链接。

## ① 工具链表

| 工具 | 用途 | headless/CLI | agent 可解析性 | 链接 |
|---|---|---|---|---|
| Verilator（5.x）【官方文档】 | 高速仿真、lint、覆盖 | 是；`--lint-only`、`--binary`、`--coverage` | 好：stderr 诊断带 file:line，退出码可判定；`--Wno-fatal` 可分级 | [verilating](https://verilator.org/guide/latest/verilating.html)、[verilator_coverage](https://verilator.org/guide/latest/exe_verilator_coverage.html) |
| Icarus Verilog + vvp【官方文档】 | 兼容性仿真、教学/小规模回归 | 是 | 中：文本日志，需自行 grep；退出码可用 | [calyx 集成 commit](https://github.com/calyxir/calyx/commit/b287a07d6eba663da888a4f180e669fe1b24c0a1)（示例，非官方主页） |
| cocotb【官方文档】 | Python 测试台，替代 SV TB | 是；Makefile based，CI 友好 | 好：可输出 JUnit XML，天然结构化 | [simulator support](https://docs.cocotb.org/en/stable/simulator_support.html)、[build/test runner](https://docs.cocotb.org/en/development/building.html) |
| Verible（verilog_lint / syntax）【官方文档】 | 解析、lint、格式化 | 是 | 好：结构化诊断，支持规则开关/autofix | [lint 源码](https://foss-fpga-tools.googlesource.com/third_party/verible/+/51eb6bdba4337541e31d0af35b11aebf883ecd6a/verilog/tools/lint/verilog_lint.cc)、[syntax 工具](https://foss-fpga-tools.googlesource.com/third_party/verible/+/refs/tags/v0.0-1585-ga42d7af6/verilog/tools/syntax) |
| Yosys【官方文档】 | 综合、`equiv` 等价性、脚本化 | 是（Tcl/脚本） | 中好：日志 + 非零退出码 | 见市场目录 [yosys](https://explore.market.dev/ecosystems/cpp/projects/yosys) |
| SymbiYosys (sby)【官方文档】 | 形式验证（BMC/证明）、SVA | 是 | 好：`.sby` 配置 + 结构化 VCD/日志，pass/fail 明确 | [社区整理文档](https://raw.githubusercontent.com/lmcapacho/open-hardware-software/refs/heads/main/docs/tools/symbiyosys.md) |
| OpenLane 2【官方文档】 | RTL→GDSII 全流程自动化 | 是：CLI + Python `Flow` API | 好：JSON 配置/指标、日志分层 | [CLI](https://github.com/The-OpenROAD-Project/OpenLane/blob/master/docs/source/reference/cli.md)、[flows API](https://openlane2.readthedocs.io/en/stable/reference/api/flows/)、[quickstart](https://github.com/chipfoundry/openlane2/blob/main/docs/source/getting_started/quickstart.md) |
| OpenSTA【官方文档】 | 静态时序分析、报告 | 是 | 中：`.rpt` 文本需解析 | [reporting/output](https://deepwiki.com/parallaxsw/OpenSTA/4-reporting-and-output)、[path reporting](https://deepwiki.com/parallaxsw/OpenSTA/4.1-path-reporting) |
| VerilogEval（NVlabs）【论文/官方】 | spec→RTL 基准 + 评估脚本 | 是 | 好：pass@k 报告 | [README](https://raw.githubusercontent.com/NVlabs/verilog-eval/release/1.0.0/README.md)、[Revisiting VerilogEval, ACM TODAES 2025](https://dl.acm.org/doi/10.1145/3718088) |
| TuRTLe（HPAI-BSC）【论文/官方】 | RTL 生成统一评测（MLCAD 2025 / TODAES 2026） | 是 | 好 | [repo](https://github.com/HPAI-BSC/TuRTLe)、[MLCAD](https://dl.acm.org/doi/abs/10.1109/MLCAD65511.2025.11189228) |
| RTLLM | RTL 生成基准 | 是 | 中 | [数据集镜像](https://huggingface.co/datasets/ggcristian/RTLLM-v1.1) |
| SVA/断言数据集 | 断言生成与研究 | — | — | [achieve-lab/assertion_data_for_LLM](https://github.com/achieve-lab/assertion_data_for_LLM)、[ACM TODAES SVA 数据集论文](https://dl.acm.org/doi/full/10.1145/3764934) |

**商业替代边界**：Xcelium/VCS/DC 等均有 headless CLI，但许可（license server、seat 抢占）与合规使 agent 无法在 CI/沙箱随意调用；公开可复现工作流基本都收敛到 Verilator/Icarus + Yosys/sby + OpenLane 三件套。

## ② MCP 与集成机制清单

| 项目 | 说明 | 分级/链接 |
|---|---|---|
| MCP4EDA | 面向开源 EDA 工具的 MCP server，覆盖 RTL→GDSII 与后端感知综合优化 | 【论文】[arXiv 2507.19570](https://arxiv.org/abs/2507.19570)、[repo](https://github.com/NellyW8/MCP4EDA) |
| mcp-eda-hub | MCP-EDA 服务器目录（聚合索引，非工具本体） | 【社区】[repo](https://github.com/ssql2014/mcp-eda-hub) |
| fpgaZeroMCP | FPGA 工具链 MCP：lint/仿真/综合/布局布线 + IP 核注册表 | 【社区】[repo](https://github.com/bard0-design/fpgaZeroMCP) |
| VLSI-MCP | VLSI 流程 MCP 封装 | 【社区】[repo](https://github.com/rahulbalhotra/VLSI-MCP) |
| Chip-Design-Agent / MCP-EDA Server | 面向 Archestra 的 MCP EDA server | 【社区】[repo](https://github.com/BARATHM111/Chip-Design-Agent---MCP-EDA-Server-for-Archestra) |
| rtl-skills | Claude Code skills/agents：架构→RTL→lint→自测试台→回归→调试→Vivado 综合，由一页 spec 驱动 | 【社区】[repo](https://github.com/phamcuong21478/rtl-skills) |
| rtl_agent | 文本/PDF/音视频 → Spec IR → 双 Oracle agent → 已验证 SystemVerilog（GLSVLSI 2026） | 【论文/社区】[repo](https://github.com/srijavuppala/rtl_agent)、[论文](https://dl.acm.org/doi/full/10.1145/3787109.3816376) |
| MAGE | 多 agent 引擎做自动 RTL 生成 | 【论文】[IEEE](https://ieeexplore.ieee.org/document/11133191) |
| HWE-Bench | 真实硬件 bug 修复基准；模型需 agent scaffolding 在容器内调用 EDA 工具 | 【论文】[arXiv 2604.14709](https://arxiv.org/abs/2604.14709) |
| PEFA-AI | 渐进式错误反馈的 agentic RTL 生成（开源 LLM） | 【论文】[arXiv 2511.03934](https://arxiv.org/abs/2511.03934) |

**shell 工具调用模式**：上述多数项目本质是"agent 调 CLI + 解析日志"，MCP 只是把 CLI 包装成带 schema 的 tool。CI 侧可参考 [snax-dev CI workflow](https://github.com/KULeuven-MICAS/snax-dev/blob/6989793ab627741afbe25811922763ee86ea9988/.github/workflows/ci.yml)、[fpganinja/taxi CI 基础设施](https://deepwiki.com/fpganinja/taxi/15-testing-and-ci-infrastructure)。

## ③ 可落地流程模板（spec → RTL → 验证）

1. **spec→接口表**：人写/校验端口表（名称、方向、位宽、时钟域、复位极性）为 YAML/CSV，作为唯一契约；agent 不得改契约。
2. **模块级生成**：每个接口表条目对应一个模块任务，输出单文件 RTL + 文件头（生成模型、prompt 哈希、时间）。
3. **lint 门禁**：`verible-verilog-lint rtl/*.sv --rules_config=lint.rules`；`verilator --lint-only -Wall --Wno-fatal top.sv`。任一失败即回环。
4. **自测试台/回归**：cocotb 或 Verilator C++ TB，CI 中 `make` 输出 JUnit XML；失败日志原样回灌给 agent。
5. **形式/等价兜底**：关键子模块 `sby -f prop.sby`（BMC + 断言）；重构前后 `yosys -p "equiv_make gold gate equiv; equiv_simple; equiv_status -assert"`。
6. **集成**：顶层互联单独生成，跑整芯片仿真 + 覆盖（`verilator_coverage`，关注 line/toggle）。
7. **物理/时序确认**：OpenLane 2 非交互跑 `openlane --pdk ... config.json`，读 metrics JSON 与 OpenSTA `.rpt` 作为收尾判据。
8. **人类审查关卡**：接口表、复位/时钟策略、状态机安全性、位宽截断、X 传播五类强制人工过目；agent 只出 diff + 证据（lint/仿真/形式三层结果）。

## ④ 风险与合规要点

- **保密与私有化部署**：主流做法是本体内网部署开源权重模型；三星电子 DS 部门引入企业版 ChatGPT（【媒体】[报道](https://china.kyungjeilbo.com/view/20260723092870416)、[Aju Press](https://www.ajupress.com/discovery/reporter/candice-kim?page=9)），说明大厂倾向"受控企业租户 + 不外传设计数据"。
- **生成码的知识产权与来源**：OpenTitan 已发布**生成式 AI 政策**与贡献指南/CLA 体系（【官方】[AI policy](https://opentitan.org/aipolicy/)、[contributing](https://opentitan.org/book/doc/contributing/#license-agreements)、[CLA](https://opentitan.org/cla/index.html)）——提交 LLM 生成 RTL 前必须确认政策与披露要求。社区层面出现针对 AI 生成代码的许可提案（【社区】[AI-MIT License 提交](http://lists.opensource.org/pipermail/license-discuss_lists.opensource.org/2026-March/022539.html)）与代码来源审查讨论（【社区】[qemu-devel 讨论](https://lists.gnu.org/archive/html/qemu-devel/2026-05/msg07062.html)）。
- **安全**：LLM 生成 RTL 的可信度已有专门研究（【论文】[Trusting the Machine: How Secure is LLM-Generated RTL Code?](https://xplorestaging.ieee.org/document/11189213)）。
- **可追溯性**：建议记录 prompt 版本、模型版本、种子、工具版本与全部日志摘要；对形式验证引入未公开 SVA 时注意审计一致性。
- **工具许可**：商业仿真/综合 license 与 CI 并发冲突，agent 方案应显式声明仅使用开源工具链，商业工具只做最终签核（未核实的替代路径不做承诺）。
- **AGENTS.md 实践**：RTL 仓库已有先例，如 openhwgroup/core-et 的 [AGENTS.md](https://github.com/openhwgroup/core-et/blob/main/AGENTS.md)；通用工程侧可参考 [Sentry 分层 AGENTS.md 解读](https://blog.gitcode.com/966226ae1b49b0f084483b339bfd57f4.html)（【媒体/社区】）。

**未核实项**：各仓库 star 数/提交活跃度；商业 EDA 厂商 agent 产品的具体开放程度；上述 MCP 项目的生产可用性。
