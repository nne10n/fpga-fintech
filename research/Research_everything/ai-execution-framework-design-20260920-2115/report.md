# AI 执行框架设计

**Asia/Shanghai 2026-09-20 21:15**（v2 并入提示词大师收紧） · 证据见 [`sources.md`](sources.md)、[`evidence/`](evidence/)

---

## 0. 开篇消歧：「AI 执行框架」指什么

### 候选定义（先列后锁）

| 候选 | 含义 | 本报告是否采用 |
|------|------|----------------|
| **A. Agent / 工具调用运行时与编排** | 计划 → 选工具 → 执行 → 观察 → 停止；含状态、门禁、留证 | **默认锁定** |
| B. 深度学习 **训练** 框架 | PyTorch、TensorFlow、JAX 等 | **Out** |
| C. **Chat UI / 会话壳** | 仅消息渲染，不含工具副作用与停止契约 | **Out**（可作前端，非本题） |
| D. **ML 推理 serving** | Triton、TorchServe 等 | **Out** |
| E. **CI Runner 本身** | GitHub Actions、Jenkins | 仅作 **IDE/CI 集成** 维对照 (S17,S18) |

**锁定结论（事实+范围）：** 除非上下文另有所指，本题 **AI 执行框架 = A**：让 coding/研究/工具型代理 **可靠完成带副作用任务** 的 runtime + orchestration，不是训练栈，也不是纯聊天界面。

---

## 1. 结论摘要 + 一页纸速览

### 结论摘要（≤10 行）

1. **默认定义：** Agent 运行时与编排（§0-A）；PyTorch/TF、纯 Chat UI **不在题面**。
2. **默认组合（推断，可落地）：** **显式状态机/图编排**（短任务可用有界 ReAct/`Runner` 等价于 1-node 图）+ **工具白名单 + schema 校验**（function calling / MCP）+ **关键步骤人审**（deploy/push/外发消息/`interrupt`）+ **运行留证**（trace + tool 原始 I/O + 可选检查点/CI oracle）。出处：S3–S6,S8–S10,S5,E5。
3. **端到端：** 目标 → 步骤 = Planner（可选）+ 循环内 model 选 tool；副作用隔离 = Host 沙箱 + server 校验 + 幂等/Activity；停止 = max_turns **且** 成功谓词；「做完」= **oracle**（测试/CI/文件/人审），非模型自述 (S1,S10,E4,E5)。
4. **开放联网乱点：** 收窄出站 allowlist、只读浏览工具、禁止任意 `shell`；高危 URL/MCP 须人审；否则 **换方案** 为离线镜像 research 或预抓取 corpus（推断，S6,S17）。
5. **无 oracle：** 禁止自动标「已验证」；交付须 **人审 ACK** 或显式声明「不可自动验收」；可引用姊妹调研 `ai-automated-test-verify-code-20260917-0940/`（**待核实** 是否已落盘，见 E5）。
6. **记忆/长任务：** thread checkpointer 或 Temporal Workflow；LLM/工具 I/O 非 Workflow 内直接调用 (S4,S14,E3)。
7. **多代理：** 仅在有 **确定性路由 + termination** 时；否则默认 **单代理 + Handoff 可选** (S11,S12,S9)。
8. **对照框架** 已按 **冻结九维** 落表（§6–§7），非 star 数营销。
9. **Cursor/Cloud Agent** 属 **IDE/CI 执行面**：Build/install + 分支 checkout，**不替代** Gate/Oracle (S17,S18)。
10. 详表与换方案条件见 §8–§9。

**一页纸：** [`onepager.md`](onepager.md)。

---

## 2. 范围 In / Out

### In

- 执行/编排框架的 **设计选项** 与 **可落地方案**：控制流、工具与权限、状态持久化、并行与子代理、人机门禁、失败恢复、可观测留证、与 IDE/CI 集成。
- 开源/公开文档对照：LangGraph、OpenAI Agents SDK、AutoGen、CrewAI、Temporal+LLM、Cursor Cloud Agent（机制层）。

### Out

- 训练/微调大模型、提示词「文采」教程、完整商业产品 PRD、未核实 benchmark 刷分。
- FPGA RTL 等：本仓另有专题，与 Agent 编排 **正交**（一句交叉引用即可）。

---

## 3. 假设（先写再比）

以下为本报告 **对比与推荐的前提**；若你的任务不满足，须先改假设再选框架。

| 假设轴 | 本报告默认 | 若不成立 → 对比权重变化 | 标注 |
|--------|------------|-------------------------|------|
| **单人助手 vs 多代理团队** | **偏单人助手**；多代理作可选扩展 | 强角色分工 → 加重 AutoGen/CrewAI/Handoff 维；须加 termination | 推断 |
| **是否改用户系统 / 发消息** | 默认 **可写仓、可开 PR**；**外发邮件/Slack/生产 DB 写** 视为高危，默认 **人审** | 只读调研 → 可放松 push 门禁，仍须工具 allowlist | 推断；门禁事实 S5,S10 |
| **是否落仓跑 CI** | **推荐** coding 任务以 git push + CI 为 oracle（与 Cloud Agent 流程一致） | 无 CI → 依赖本地测试命令 oracle（姊妹目录 E5） | 推断；环境事实 S17,S18 |
| **延迟与成本** | 默认 **成本敏感**：有 `max_turns`、Plan-Execute 降 planner 频率 | 低延迟优先 → 少 replan、少多代理轮询 | 推断；步数上限事实 S10,S3 |

**技术前提（事实）：** 模型支持 tool/function calling (S8)；文档快照 2026-09-20。

---

## 4. 冻结对比维（全文统一）

后文 **§6 机制表、§7 产品矩阵、§8 推荐** 均只用下列九维 + **出处**：

1. **控制流**（DAG / 状态机 / ReAct 循环）
2. **工具接口与权限边界**
3. **记忆 / 状态持久化**
4. **并行与子代理**
5. **人机门禁**
6. **失败重试与补偿**
7. **可观测与留证**
8. **和 IDE/CI 集成**
9. **出处**（S#）

---

## 5. 端到端机制（四问必答）

### 5.1 一次任务如何从目标变成步骤

| 阶段 | 机制 | 典型实现 | 出处 |
|------|------|----------|------|
| 目标入态 | 用户 prompt + 结构化 `goal`/`acceptance` 写入 state | graph state / RunConfig | 推断；S3 |
| 计划 | 可选：Plan-and-Execute Planner 一次出多步 (S15)；或 ReAct 每步隐式 plan | PS 两阶段提示 (S16) | S15,S16,S1 |
| 选工具 | 模型 `tool_calls` 或 MCP `tools/call` | strict schema 降参错 | S8,S6 |
| 执行 | Host 调 adapter；**非**模型直接 syscall | Runner 循环 (S10) | S10,S8 |
| 观察 | tool output **原文** 追加 messages | call_id 对齐 (S8) | S8 |
| 循环 | 直至停止条件（§5.3） | ReAct / super-step | S1,S3 |

### 5.2 工具副作用如何隔离

| 层级 | 措施 | 标注 | 出处 |
|------|------|------|------|
| 协议 | MCP server 校验输入、ACL、限流、sanitize 输出 | 事实 | S6 |
| Host | 工具 **白名单**；路径/workspace 边界；Sandbox agents | 推断+事实 | S9,S17 |
| 网络 | Cloud Agent 网络策略；生产应 **出站 allowlist** | 部分事实 | S17 |
| 恢复 | LangGraph 恢复 **重跑 node** → 副作用须 **幂等** 或进 Activity | 事实 | S3,E1 |
| Temporal | 非确定性 I/O 仅 Activity；Workflow 确定性 replay | 事实 | S14,E3 |

### 5.3 何时停

| 停止类型 | 条件 | 出处 |
|----------|------|------|
| **硬上限** | `max_turns` / `recursion_limit` / wall-clock | S10,S3 |
| **护栏 tripwire** | Input/Output/Tool guardrail 异常 | S10 |
| **编排终止** | AutoGen `termination_condition`；Crew 任务链结束 | S11,S12 |
| **成功终止** | §5.4 oracle **真** + 模型无 pending tool | 推断,E5 |
| **人审暂停** | `interrupt` 非终止，resume 后继续 | S5 |

### 5.4 如何证明「做完了」而非模型自说自话

**原则（事实+推断）：** ReAct 依赖 **外部观测** 抗幻觉 (S1,E4)；执行框架必须把 **完成** 定义为 **oracle 谓词**，不是 assistant 最后一句话。

| Oracle | 执行框架挂载 | 交叉引用 |
|--------|--------------|----------|
| 命令 exit code + 日志 | Gate：仅当 tool 返回 code=0 且日志匹配模式 | 姊妹 **`ai-automated-test-verify-code-20260917-0940/`**（E5，目录 **待核实**） |
| 产物存在/哈希 | State.`artifacts` + 确定性 `read_file`/`hash` 工具 | E5 |
| CI 绿 | push 后外部 CI；Agent 侧 **订阅或轮询** workflow | 推断；环境 S18 |
| 人审 | `interrupt` / PR review / 双控 | S5 |
| **无 oracle** | 禁止「已验证」；仅「已交付草稿」+ 人审 ACK | 推断,E5 |

**留证（事实）：** OpenAI Agents **tracing** 可记录 generations/tools/guardrails (S9)；LangGraph checkpointer 存 super-step 快照 (S4)。**推断：** 审计应保留 **tool 原始 output**，不只摘要。

---

## 6. 控制流选项（DAG / 状态机 / ReAct）

（与 v1 §4.1 一致，压缩表述。）

- **ReAct 循环：** 交错 thought/action；单代理 while (S1,S10)。
- **Plan-Execute：** Planner → Executor → Replanner (S15)；提示学来源 Plan-and-Solve (S16)。
- **LangGraph：** StateGraph、super-step、条件边 = **显式 DAG/状态机** (S3)。
- **Temporal：** Workflow 编排 + Activity 执行 = 企业级状态机 (S13,S14)。
- **OpenAI Runner：** 内置 turn 循环；可视为 **隐式状态机**（turn 计数）(S9,S10)。

---

## 7. 开源 / 产品对照矩阵（映射九维，非 star）

> 单元格：**事实** 来自对应文档 (S#)；**推断** 已标。

### 7.1 LangGraph

| 维 | 落点 | 出处 |
|----|------|------|
| 控制流 | StateGraph、super-step、混合确定性节点与 LLM 节点 | S2,S3 |
| 工具与权限 | 不内置 OS 沙箱；工具在 node 内自接 MCP/FC | 推断；S2 |
| 记忆/持久化 | Checkpointer（thread）+ Store（跨 thread） | S4,S20 |
| 并行与子代理 | 同 super-step 并行；子图 checkpoint 命名空间需注意 | S3,S20 |
| 人机门禁 | `interrupt` + `Command(resume=)` | S5 |
| 失败/补偿 | 检查点恢复；node 重跑非事务 | S3,E1 |
| 可观测留证 | LangSmith 追踪（可选） | S2 |
| IDE/CI | 无专用；自托管 runtime | 推断 |
| | | S2–S5,S20 |

### 7.2 OpenAI Agents SDK

| 维 | 落点 | 出处 |
|----|------|------|
| 控制流 | Runner turn 循环；Handoffs | S9,S10 |
| 工具与权限 | Function tools + MCP；tool guardrails | S9,S10 |
| 记忆 | Sessions | S9 |
| 并行与子代理 | Handoffs / agents-as-tools；Sandbox 子代理 | S9 |
| 人机门禁 | Guardrails；HITL 机制 | S9,S10 |
| 失败/补偿 | MaxTurnsExceeded；Activity 无 | S10 |
| 可观测 | Built-in tracing | S9 |
| IDE/CI | 无；可自接 git/CI 工具 | 推断 |
| | | S9,S10 |

### 7.3 Microsoft AutoGen (AgentChat Teams)

| 维 | 落点 | 出处 |
|----|------|------|
| 控制流 | RoundRobin / SelectorGroupChat / Swarm | S11 |
| 工具与权限 | Agent 级 tools；无统一 MCP 规范 | 推断 |
| 记忆 | 共享群聊上下文；BufferedContext 等 | S11 |
| 并行与子代理 | 多 participant；Selector **LLM 路由** | S11 |
| 人机门禁 | ExternalTermination | S11 |
| 失败/补偿 | termination + max_turns | S11 |
| 可观测 | emit_team_events | S11 |
| IDE/CI | 无 | 推断 |
| | | S11 |

### 7.4 CrewAI

| 维 | 落点 | 出处 |
|----|------|------|
| 控制流 | Process.sequential / hierarchical | S12 |
| 工具与权限 | Agent/task 级 tools | S12 |
| 记忆 | Task `context` 链 | S12 |
| 并行与子代理 | hierarchical manager 委派 | S12 |
| 人机门禁 | Task guardrails | S12 |
| 失败/补偿 | **待核实** 版本差异 | 待核实 |
| 可观测 | verbose 等 | **待核实** |
| IDE/CI | 无 | 推断 |
| | | S12 |

### 7.5 Temporal + LLM

| 维 | 落点 | 出处 |
|----|------|------|
| 控制流 | Workflow 确定性；agent 循环可在 Workflow | S13,S14 |
| 工具与权限 | `activity_as_tool`；I/O 在 Activity | S13,S14 |
| 记忆/持久化 | Event History | S14 |
| 并行与子代理 | 多 Activity 并行 | S13 |
| 人机门禁 | Signal/Update/Approval 模式 | S13,S14 |
| 失败/补偿 | Activity 重试；Workflow replay | S13,S14 |
| 可观测 | Temporal UI history | S13 |
| IDE/CI | 可编排 CI Activity | 推断 |
| | | S13,S14 |

### 7.6 Cursor Cloud Agent（执行面，非编排内核）

| 维 | 落点 | 出处 |
|----|------|------|
| 控制流 | 产品内 Agent 循环；**不在** environment.json 定义图 | 推断；S17 |
| 工具与权限 | MCP/工具由 Host 配置；网络/ secrets | S17 |
| 记忆/持久化 | Build 快照 + 分支 checkout 磁盘态 | S18 |
| 并行与子代理 | 产品能力（subagent）**待核实** 细节 | 待核实 |
| 人机门禁 | 用户审批工具/PR 等产品层 | 推断 |
| 失败/补偿 | Build 重建、install 重跑 | S18 |
| 可观测 | Dashboard/run 事件 | 推断 |
| IDE/CI | **核心维**：`.cursor/environment.json`、Build、push/PR | S17,S18 |
| | | S17,S18 |

---

## 8. 综合对比表（模式级，九维）

| 维 | ReAct/Runner | Plan-Execute | LangGraph | AutoGen Teams | CrewAI | Temporal+LLM |
|----|--------------|--------------|-----------|---------------|--------|--------------|
| 控制流 | 循环 (S1,S10) | Planner/Executor (S15) | DAG/状态机 (S3) | GroupChat (S11) | Sequential/Hierarchical (S12) | Workflow (S14) |
| 工具与权限 | FC/MCP 自接 (S8,S6) | 同左 | 同左 | Agent tools | Task/agent tools (S12) | activity_as_tool (S13) |
| 记忆/持久化 | Session/内存 (S9) | plan 文本 | Checkpointer+Store (S4,S20) | 群聊历史 (S11) | task context (S12) | Event History (S14) |
| 并行与子代理 | 单代理为主 | Executor 可多个 | 图并行 (S3) | 多 agent (S11) | manager 委派 (S12) | 多 Activity |
| 人机门禁 | 应用/SDK guardrails (S10) | Replanner | interrupt (S5) | ExternalTermination (S11) | task guardrails (S12) | Signal (S14) |
| 失败/补偿 | 重试自实现 | Replanner | 检查点+幂等 (E1) | termination (S11) | 待核实 | Activity 重试 (S13) |
| 可观测留证 | trace (S9) | 同左 | LangSmith (S2) | team events (S11) | 待核实 | Temporal UI (S13) |
| IDE/CI | 自接 | 自接 | 自接 | 自接 | 自接 | 可编排 CI |
| 出处 | S1,S8–S10 | S15,S16 | S2–S5,S20 | S11 | S12 | S13,S14 |

---

## 9. 默认推荐与换方案

### 9.1 默认组合（再述）

**显式状态机/图编排**（短任务 = 有界 ReAct，等价最小图）+ **工具白名单 + schema** + **关键步骤人审** + **运行留证** + **oracle 完成谓词**（§5.4，E5）。

组件映射：LangGraph 或 Runner **Loop**；MCP/FC **Tool**；`max_turns`+guardrails+interrupt **Gate**；checkpointer/trace **Obs**。

### 9.2 场景：开放联网乱点

| 风险 | 默认对策 | 何时整包换方案 |
|------|----------|----------------|
| 任意 URL/下载/SSRF | 出站 allowlist、只读 fetch、无浏览器自动点击 | 必须全自动爬网 → **预抓取 + 离线 corpus** 或专用 research 子图，禁用通用 browser |
| MCP 模型自动 tools/call | Client 人审 + 高危 deny (E2) | 无法人审 → **只读工具集** |
| 成本爆炸 | max_turns、缓存 fetch | 仍爆 → Plan-Execute 限 planner 次数 (S15) |

标注：**推断** + S6,S17。

### 9.3 场景：无 oracle

| 策略 | 说明 |
|------|------|
| **禁止** | 自动「测试通过/已验证」文案 |
| **允许** | 草稿 + 清单式「待人类确认项」 |
| **门禁** | 仅 `interrupt` 后人可点「接受交付」 |
| **若必须自动** | 先 **补 oracle**（加测试、快照对比）— 见 E5 与姊妹目录 |

### 9.4 其他换方案（简表）

| 信号 | 换方案 |
|------|--------|
| 长时/等人/崩溃 | LangGraph checkpointer 或 Temporal (S4,S14) |
| 多角色闲聊不终止 | 单代理或 sequential + 硬 termination (S11) |
| 仅要 VM+git | Cursor Cloud Agent + 仍须应用 Gate (S17) |

---

## 10. 工作示例

### 10.1 单代理工具循环 + oracle

与 v1 §7.1 相同契约；**成功** 增加：`pytest` tool exit 0（E5 姊妹主题）且 `report.md` 存在。

### 10.2 人审 + 检查点

与 v1 §7.2 相同；push 前 `interrupt`；push 用 Activity/`@task` 保幂等 (E1,S14)。

---

## 11. 风险、证伪、待核实

| ID | 要点 | 文件 |
|----|------|------|
| E1 | LangGraph resume 重跑 node | evidence/E1-… |
| E2 | MCP 模型可控，人审在 client | evidence/E2-… |
| E3 | Temporal Workflow 禁直接 LLM | evidence/E3-… |
| E4 | 无 grounding 空转 | evidence/E4-… |
| E5 | Oracle 与姊妹目录交叉引用 | evidence/E5-… |

**待核实：** `ai-automated-test-verify-code-20260917-0940/` 是否已入仓；CrewAI 重试/telemetry；各 Host MCP 确认 UI。

---

## 12. 出处列表

见 [`sources.md`](sources.md)（S1–S20，≥10 URL）。

---

*v2：已并入开篇消歧、冻结九维、机制四问、假设轴、In/Out、默认组合与开放联网/无 oracle 换方案。*
