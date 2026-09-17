# 出处索引

Asia/Shanghai 2026-09-16 · 共 **21** 条（S1–S21）

**留证硬规则：** 报告对比表单元格、机制断言、数字须能指回本表 ID；指不出则 **待核实** 或删除。

---

## 主出处表

| ID | 标注 | 标题 | URL | 开源触点（文件/接口/命令） | 支撑点 |
|----|------|------|-----|---------------------------|--------|
| S1 | 事实 | openai/codex#35628 CLI TUI Mermaid | https://github.com/openai/codex/issues/35628 | issue 正文 fenced 样例；标签 `CLI`,`TUI` | F1–F5,F11；CLI **当前仅源码**；提案禁 `mmdc`/Node |
| S2 | 事实 | openai/codex#32356 Android Mermaid | https://github.com/openai/codex/issues/32356 | issue 复现块 `flowchart LR` | F1,F3,F11；**Mermaid 源 + SVG/PNG 查看** 建议 |
| S3 | 事实 | openai/codex#36660 Visualization fences | https://github.com/openai/codex/issues/36660 | 关联 #35628 | F11 bounded 渲染面 |
| S4 | 事实 | Unrolling the Codex agent loop | https://openai.com/index/unrolling-the-codex-agent-loop/ | 博客正文 turn/item 语义 | F10 边标签语义（推断对齐） |
| S5 | 事实 | Unlocking the Codex harness: App Server | https://openai.com/index/unlocking-the-codex-harness/ | 组件枚举：stdio reader / message processor / thread manager / core threads | F6 分层；**静态插图非 Mermaid 源** |
| S6 | 事实 | Mermaid flowchart syntax | https://mermaid.js.org/syntax/flowchart.html | 语法：`flowchart`、`subgraph`、`-->`、`[]`/`{}` | F4,F5,F6,F9 layout=dagre |
| S7 | 事实 | Mermaid Theme Configuration | https://mermaid.js.org/config/theming.html | `themeVariables.fontFamily` 默认 `trebuchet ms, verdana, arial`；`fontSize` `16px`；`primaryColor` `#fff4dd` | F7–F9 像素锚点（**Mermaid 非 OpenAI**） |
| S8 | 事实 | mermaid-js/mermaid | https://github.com/mermaid-js/mermaid | `packages/mermaid/src/`；`mermaid.initialize({ theme, themeVariables })` | IR 渲染引擎 |
| S9 | 事实 | mermaid-js/mermaid-cli | https://github.com/mermaid-js/mermaid-cli | CLI **`mmdc`**；参数 **`-i`** 输入 **`-o`** 输出 **`-c`** 配置 **`-b`** 背景 | §4.3,§7 CI 管道 |
| S10 | 事实 | anthropics/claude-code#14375 | https://github.com/anthropics/claude-code/issues/14375 | OP Problem Statement；评论引 #20529 | Claude CLI **ASCII 框图**；VS Code **不渲染** mermaid |
| S11 | 事实 | GitHub Creating diagrams | https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams | fenced ` ```mermaid ` | GH 预览 ≠ 锁定 `mmdc` 发布物 |
| S12 | 推断 | Cursor Understanding codebase | https://cursor.com/learn/understanding-your-codebase | 文档页 Mermaid 示例 | Cursor 可出 Mermaid；无像素规范 |
| S14 | 事实 | warpdotdev/mermaid-to-svg | https://github.com/warpdotdev/mermaid-to-svg | Rust crate；**纯子集** Mermaid→SVG | bounded 渲染器边界 |
| S15 | 推断 | mermaid-architect syntax guide | https://github.com/1999azzar/mermaid-architect/blob/HEAD/references/syntax-guide.md | `references/syntax-guide.md` | Skill 结构约束参考 |
| S16 | 推断 | VMark Mermaid v11 pitfalls | https://vmark.app/guide/mermaid.html | 页面 lint 项列举 | §4.4 AI 输出脏语法 |
| S18 | 推断 | 本仓 0853 版 | https://cursor.com/codebase/melon5253/Research_everything/tree/main/ai-diagram-unify-codex-style-20260916-0853 | `examples/before-after.mmd` BEFORE 段 | **合成** classDef 漂移样例；非 primary |
| **S19** | **证伪** | OpenAI/Codex 无公开 Diagram Design System | https://openai.com/index/unlocking-the-codex-harness/ （及 S1–S5 检索） | 博客+issue **零** diagram VI/hex/字体规范链接 | **否定**：不存在可引用官方 Codex 绘图规范 |
| **S20** | **边界** | openai/codex#35100 `/design` 持久画布 | https://github.com/openai/codex/issues/35100 | issue 提案「persistent architecture canvas」 | **边界**：若采用专有画布，`.mmd` canonical 路径失效 |
| **S21** | **边界** | claude-code#20529 VS Code Mermaid | https://github.com/anthropics/claude-code/issues/20529 | 状态 **NOT_PLANNED**（S10 评论 tactician200 2026-05-22 引述） | **边界**：Claude VS Code **无** inline Mermaid 路线 |

## 待核实 / 未入表论断

| 论断 | 状态 | 原因 |
|------|------|------|
| Grok Build Mermaid 子集范围 | **待核实** | x.ai/build/changelog 抓取超时；已从 §6 删未证单元格 |
| ChatGPT iOS inline Mermaid | **待核实** | 无 primary；不引用第三方 |
| Gemini 默认 `classDef` | **待核实** | 仅 S18 合成样例；§6 不列无 primary 行 |
| Codex Web 当前 Mermaid major | **待核实** | §9 保留核对步骤 |

## 交叉核对

| 论断 | 主源 | 辅源 | 结论 |
|------|------|------|------|
| Codex issue 样例为 Mermaid 无 classDef | S1 正文样例 | S2 正文样例 | **事实** |
| 像素色值非 OpenAI VI | S7 `primaryColor` | S1 无 inline style | **推断** |
| CLI TUI 不渲染仅源码 | S1 当前行为段 | — | **事实** |
| 不存在官方 Codex 绘图 Spec | **S19** 检索 | S5 静态 PNG 无 `.mmd` | **证伪** |
| 聊天窗≠发布物 | S1 | S21 NOT_PLANNED | **事实+边界** |

## Out（本专题不覆盖）

训练/微调；完整绘图 SaaS；FPGA 机制；**未核实 ns**；**RTL top**；**策略报单**；OpenAI 品牌法律；**编造 Codex 官方配色/字体规范**。

## 标注说明

- **事实**：官方文档、issue 可核对原文、Mermaid 文档数值
- **推断**：工程组合推荐；非 OpenAI 声明
- **证伪**：检索/原文证明某规范**不存在**
- **边界**：产品路线关闭或替代路径使主方案失效
