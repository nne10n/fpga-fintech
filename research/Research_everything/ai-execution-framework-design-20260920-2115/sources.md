# 出处索引（S1–S20）

标注：**事实** = 直接来自下列公开文档/论文；**推断** = 本报告基于多源归纳的设计建议；**待核实** = 需在你方环境实测或文档版本可能变化。

| ID | URL | 类型 | 本报告主要用途 |
|----|-----|------|----------------|
| S1 | https://arxiv.org/abs/2210.03629 | 论文 | ReAct：推理与行动交错、外部观测抗幻觉 |
| S2 | https://docs.langchain.com/oss/python/langgraph/overview | 文档 | LangGraph 定位：编排 runtime、持久化、HITL |
| S3 | https://docs.langchain.com/oss/python/langgraph/graph-api | 文档 | StateGraph、super-step、checkpointer 边界 |
| S4 | https://docs.langchain.com/oss/python/langgraph/checkpointers | 文档 | 检查点、thread_id、故障恢复 |
| S5 | https://docs.langchain.com/oss/python/langgraph/interrupts | 文档 | `interrupt()` + `Command(resume=)` 人审 |
| S6 | https://modelcontextprotocol.io/specification/2024-11-05/server/tools | 规范 | MCP tools/list、tools/call、安全要求 |
| S7 | https://www.anthropic.com/news/model-context-protocol | 新闻/说明 | MCP 架构（server/client）与开放标准 |
| S8 | https://developers.openai.com/api/docs/guides/function-calling | 文档 | 函数/工具调用、call_id、strict schema |
| S9 | https://openai.github.io/openai-agents-python/ | 文档 | Agents SDK 原语：Agent、Handoff、Guardrails、Tracing |
| S10 | https://openai.github.io/openai-agents-python/ref/run/ | 文档 | Runner 循环、max_turns、护栏 tripwire |
| S11 | https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/tutorial/teams.html | 文档 | AutoGen 多代理团队、termination_condition |
| S12 | https://docs.crewai.com/edge/en/concepts/processes | 文档 | CrewAI sequential / hierarchical 进程 |
| S13 | https://docs.temporal.io/ai | 文档 | Temporal Durable AI、Activity vs Workflow |
| S14 | https://go.temporal.io/platform-hub/ai-engineering/ai-reference-architecture | 文档 | LLM/工具必须进 Activity；Workflow 确定性 |
| S15 | https://www.langchain.com/blog/planning-agents | 博文 | Plan-and-Execute 三组件（planner/executor/replanner） |
| S16 | https://aclanthology.org/2023.acl-long.147.pdf | 论文 | Plan-and-Solve 两阶段提示（计划→执行） |
| S17 | https://cursor.com/docs/cloud-agent/setup | 文档 | Cloud Agent 环境：Build/install、environment.json |
| S18 | https://cursor.com/docs/cloud-agent/builds | 文档 | Build 快照、分支 checkout、staleness |
| S19 | https://modelcontextprotocol.io/docs/2024-11-05/learn/server-concepts | 文档 | Tools vs Resources vs Prompts 控制主体 |
| S20 | https://docs.langchain.com/oss/python/langgraph/persistence | 文档 | Checkpointer（线程内）vs Store（跨线程） |

## 关键主张 → 出处绑定（节选）

| 主张 | 标注 | 出处 |
|------|------|------|
| ReAct 通过交错行动从外部源取数，缓解纯 CoT 幻觉 | 事实 | S1 |
| LangGraph 在 super-step 边界存检查点，恢复时节点函数从头重跑 | 事实 | S3, S4 |
| MCP 工具由模型发现/调用，但实现可要求用户确认 | 事实 | S6, S19 |
| OpenAI Runner 一轮 = 一次模型调用（含工具）；超限抛 MaxTurnsExceeded | 事实 | S10 |
| Temporal：非确定性 I/O（含 LLM、工具）应在 Activity，Workflow 需确定性 | 事实 | S13, S14 |
| Plan-and-Execute 将规划与逐步工具执行分离，可 replan | 事实 | S15；提示学来源 S16 |
| Cursor Cloud Agent：Build 阶段 install，运行阶段 checkout 分支 | 事实 | S17, S18 |
| 「默认生产组合 = 仅 LangGraph 图、无需工具原始日志」 | 推断 | 综合 S2–S10；**待核实** 具体 SLA |
| CrewAI hierarchical 在生产中行为因 manager 配置差异大 | 待核实 | S12 + 社区经验，见 report §11 |
| 完成 oracle 与自动化测试验证 | 推断 | 交叉引用 `ai-automated-test-verify-code-20260917-0940/` + E5（目录落盘 **待核实**） |

## 事实 / 推断 / 待核实 规则

- 对比表与机制句在 `report.md` 中用 `(S#)` 或「见 sources S#」绑定。
- 写不出出处的机制句已删除或标 **待核实**。
- 开源框架能力以 **2026-09 抓取之官方文档** 为准，升级后需重核。
