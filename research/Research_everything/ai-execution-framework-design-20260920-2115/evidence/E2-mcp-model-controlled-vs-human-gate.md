# E2 — 边界：MCP「模型可控工具」与人审门禁

**Asia/Shanghai 2026-09-20 21:15**

## 摘录（事实）

来源：MCP Tools 规范（S6）

> Tools in MCP are designed to be **model-controlled**, meaning that the language model can discover and invoke tools automatically based on its contextual understanding and the user's prompts.
>
> However, implementations are free to expose tools through any interface pattern that suits their needs—the protocol itself does not mandate any specific user interaction model.

Security（S6）：

> Servers MUST: Validate all tool inputs; Implement proper access controls; Rate limit tool invocations; Sanitize tool outputs.
>
> Clients SHOULD: … present tool inputs to the user before execution …

来源：Server concepts（S19）

> Tools … | … | **Model**  
> Prompts … user-controlled, requiring explicit invocation

## 边界结论

- **事实：** 协议默认允许模型自动 `tools/call`；人审不是协议强制，是 **Client 实现策略**（S6 SHOULD）。
- **推断：** 生产「coding agent」应在 runtime **above MCP** 增加：高危工具 allowlist、参数预览、dry-run、或 OpenAI Agents **tool guardrails**（S9/S10）。
- **待核实：** 各 IDE/MCP Host 是否默认展示确认 UI（因产品而异，本报告不枚举）。

**证伪结论：** 「上了 MCP 就安全」不成立——安全在 **server 校验 + client 门禁 + 网络隔离** 三层（S6, S7）。
