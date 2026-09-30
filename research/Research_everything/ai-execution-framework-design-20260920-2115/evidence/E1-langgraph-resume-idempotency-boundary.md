# E1 — 证伪/边界：LangGraph 恢复 ≠ 幂等副作用

**Asia/Shanghai 2026-09-20 21:15**

## 摘录（事实）

来源：LangGraph Graph API（S3）

> When you compile with a checkpointer, LangGraph saves checkpoints at super-step boundaries, not mid-function inside a node. If execution stops and later resumes (for example after an interrupt or a retry), **the affected node runs again from the start of its function**. Code and side effects before the pause run again.

来源：LangGraph Interrupts 参考（S5）

> The graph resumes from the start of the node, **re-executing all logic**.

## 边界结论

| 错误假设 | 实际行为 | 设计含义 |
|----------|----------|----------|
| `interrupt()` 后人审通过后续跑「中断点之后一行」 | 整个 **node 函数从头执行** | 中断前的 DB 写入、HTTP、非幂等工具可能 **重复** |
| 检查点 = 事务性 exactly-once 工具 | 检查点在 **super-step** 边界，非 node 内细粒度 | 副作用须放 **task/Activity** 或幂等键 |

**证伪结论：** 不能把 LangGraph 检查点当成「自动补偿事务」；长任务须 **显式幂等** 或 **Temporal Activity** 模式（S14）。

标注：**事实**（摘录）+ **推断**（工程建议）。
