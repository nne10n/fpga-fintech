# AI 执行框架设计调研

- **Slug:** `ai-execution-framework-design-20260920-2115`
- **Date (Asia/Shanghai):** 2026-09-20 21:15
- **Tags:** agent-runtime, orchestration, MCP, checkpoint, guardrails, observability
- **Summary:** v2 已并入开篇消歧（= Agent 运行时与编排，非 PyTorch/Chat UI）、冻结九维对比、机制四问、假设轴与「开放联网/无 oracle」换方案；默认组合为 **图/状态机 + 工具白名单 + 关键人审 + 留证 + oracle 完成**。

## 范围

- **In:** 执行循环（ReAct / Plan-Execute / Graph）、状态持久化与检查点、工具协议（OpenAI function calling、MCP）、记忆分层、人机门禁、失败重试/补偿、开源框架对照（LangGraph、OpenAI Agents SDK、AutoGen、CrewAI、Temporal+LLM）、IDE/CI 执行面对照（Cursor Cloud Agent，仅机制层）
- **Out:** 从零训练模型、完整 IDE 产品 PRD、未核实 benchmark 分数、FPGA RTL 专题（本仓另有 FPGA 系列调研，此处不展开）

## 一句话结论

**默认骨架：** 单代理、有 `max_turns`/递归上限的 **plan→act→observe** 循环，工具经 schema 校验与（可选）人审/护栏执行，每步 **结构化状态 + 工具原始输出** 写入检查点或追踪后端；**长任务/人审/崩溃恢复** 再引入图编排（LangGraph）或 durable workflow（Temporal），多代理仅在有明确路由与终止契约时使用。

## 交付物清单

- [x] `report.md` — 完整报告
- [x] `onepager.md` — 一页纸速览
- [x] `sources.md` — 可点击 URL + 标注（事实/推断/待核实）
- [x] `evidence/` — 摘录与证伪/边界笔记

## Links

- 仓库：[Research_everything](https://cursor.com/codebase/melon5253/Research_everything)
- 本目录：`ai-execution-framework-design-20260920-2115/`
