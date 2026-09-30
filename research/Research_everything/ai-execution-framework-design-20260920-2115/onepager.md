# 一页纸速览：AI 执行框架设计（v2）

**Asia/Shanghai 2026-09-20 21:15** · 详述 [`report.md`](report.md)

## 消歧（默认锁定）

**AI 执行框架 = Agent/工具运行时与编排**（计划→选工具→执行→观察→停止）。**不是** PyTorch/TF 训练框架，**不是**纯 Chat UI。详见 report §0。

## 默认组合

**显式状态机/图**（短任务可有界 ReAct）+ **工具白名单 + schema** + **关键步骤人审** + **运行留证** + **oracle 完成**（测试/CI/文件/人审）。§9.1

## 机制四问（30 秒）

| 问 | 答 |
|----|-----|
| 目标→步骤 | 可选 Planner + model 选 tool 循环 (S15,S10) |
| 副作用隔离 | MCP 校验 + Host 沙箱 + 幂等/Activity (S6,E1,S14) |
| 何时停 | max_turns + 护栏 + **oracle 真** (S10,E5) |
| 证明做完 | tool 原始输出 + exit code/CI/人审；**禁**模型空口「已验证」 (S1,E4,E5) |

姊妹 oracle 调研（**待核实落盘**）：`ai-automated-test-verify-code-20260917-0940/` → [`evidence/E5-oracle-completion-crossref.md`](evidence/E5-oracle-completion-crossref.md)

## 假设（默认）

单人助手；可写仓/PR；外发消息=高危；**推荐 CI oracle**；成本敏感→限步数。§3

## 冻结九维

控制流 | 工具与权限 | 记忆/持久化 | 并行与子代理 | 人机门禁 | 失败/补偿 | 可观测留证 | IDE/CI | 出处 — §4，产品矩阵 §7

## 换方案

| 条件 | 动作 |
|------|------|
| **开放联网乱点** | allowlist + 只读 fetch + 人审；不行→离线 corpus §9.2 |
| **无 oracle** | 人审 ACK 或声明不可自动验收；禁伪 verified §9.3 |
| 长时/崩溃 | LangGraph / Temporal §9.4 |

## 证伪必读

E1 恢复重跑 node · E2 MCP 模型可控 · E3 Temporal LLM 在 Activity · E4 grounding
