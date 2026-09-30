# E3 — 证伪/边界：Workflow 内直接调 LLM 破坏确定性

**Asia/Shanghai 2026-09-20 21:15**

## 摘录（事实）

来源：Temporal AI Agent Reference Architecture（S14）

> The single most important rule in a Temporal AI stack is that **all non-deterministic I/O belongs in Activities, not Workflows**. This includes **every LLM call, every tool invocation**, every external API request, and every database read.
>
> Workflow code is replayed from history during failure recovery. If you call an LLM directly inside a Workflow, the replay will attempt to call the LLM again — producing a different result, breaking determinism, and corrupting the Workflow's state.

来源：Temporal blog（S13 同主题，S3 博客链接在 S13 索引中）

> The Workflow replays your agent's progress using the **recorded LLM decisions** from the Event History.

## 边界结论

| 模式 | 适用 | 翻车信号 |
|------|------|----------|
| 进程内 ReAct 循环 | 短任务、可丢中间态 | Worker 崩溃后重复 LLM 调用、成本飙升 |
| Temporal + Activity 包 LLM | 长对话、人审等待、强 SLA | 误把工具写进 Workflow → replay 不一致 |

**证伪结论：** Temporal 适合 **编排 durability**，不等于「把现有脚本丢进 Workflow」；Agent 循环逻辑可仍在 Workflow，但 **LLM/工具 I/O 必须 Activity 化**（S13 OpenAI Agents 集成文档亦强调 model calls as Activities）。

标注：**事实**。
