# AI 方案设计图跨工具统一 → Codex 风格

**完整详尽调研报告（修订）** · Asia/Shanghai 2026-09-16 08:53

---

## 结论摘要（≤10 行）

1. **OpenAI 未公开 Codex Diagram Design System**；「Codex 风格」= **可核对输出特征清单（§2 冻结 ≥10 条）**，每条标注事实/推断/待核实及出处，禁止冒充官方规范。
2. **对齐目标**：跨 Codex、Cursor、Claude、Gemini、Grok 的 **框线架构图 / 数据流 / 时序图**；交付口径为 **「生成后一键重渲一致」**（canonical `.mmd` → 固定渲染管道），而非「各工具聊天窗像素即时一致」。
3. **四条路径不可混写**：① Skill/系统提示 ② 统一 IR ③ 统一渲染器主题 ④ 后处理（SVG/CSS/布局）；**提示词能管结构与语法，管不住宿主渲染器像素与线宽字体默认值**。
4. **默认落地组合**：**② Mermaid IR + ③ 单一 `mmdc` 主题导出为主**，**① Skill 为辅**（约束 diagram type、subgraph、禁 classDef），**④ 后处理为 CI 门**（lint、strip 装饰、SVG diff）；**不**以「只加提示词」为主路径。
5. **位图降级**：工具仅出 PNG/SVG 截图且无源码 → **归档位图 + Vision/人工反写 `.mmd` → 重渲**；位图 **never canonical**；无法反写则标注 `derivative-only` 且不参与 CI diff。
6. **In**：统一到 Codex 可观察视觉/结构习惯的实现方案；**Out**：训练/微调模型、完整绘图产品、FPGA 等无关专题、未核实品牌法律结论。
7. **翻车**：专有画布锁死、Mermaid 子集渲染器、Claude ASCII 替代架构图、强依赖 classDef 导致跨平台漂移。
8. 对比维见 §5 冻结表；出处 ≥10 见 [sources.md](./sources.md)（16 条）。

---

## 一页纸速览

> 独立文件：[onepager.md](./onepager.md)

| 决策问题 | 一句话 |
|----------|--------|
| Codex 风格？ | 冻结清单 §2：**Mermaid + 默认主题几何风（非手绘）**；视觉像素来自 **Mermaid 宿主主题**，非 OpenAI 专有配色 |
| 四条路径？ | ① 提示管 **结构**；② IR 管 **diff**；③ 渲染主题管 **像素**；④ 后处理管 **漂移/布局** |
| 默认组合？ | **IR + 单一渲染管道** 为主，Skill 为辅；**生成后重渲** 一致 |
| 仅位图？ | 归档 → 反写 Mermaid → 重渲；否则 `derivative-only` |

---

## 0. 范围（In / Out）

| In | Out |
|----|-----|
| 将多 AI 工具产出的 **方案/架构/数据流/时序** 设计图，对齐 **Codex 可观察习惯** 的 **实现路径、Skill 模板、渲染管线** | **训练/微调** 模型以「学会画 Codex 图」 |
| 风格规范 **可核对要素**（结构 + 由 Mermaid 默认主题承载的视觉项） | 做 **完整绘图产品**（Figma/Excalidraw SaaS 全栈） |
| 四条路径对比、CI 校验、位图降级 | 本仓库 **FPGA 等无关专题** 机制展开 |
| 与 **Markdown + Mermaid** 仓库文档协同 | 未核实的 **OpenAI 品牌/VI 法律** 结论 |
| 可复制的 prompt/skill 与 `mmdc` 管道示例 | 像素级企业 VI 手册 |

---

## 1. 假设与口径（先写）

| 参数 | 冻结假定 | 状态 |
|------|----------|------|
| **要对齐的 AI 工具** | OpenAI Codex / ChatGPT、Cursor Agent、Claude Code/Desktop、Google Gemini、xAI Grok Build | 假设（团队可裁剪） |
| **主要图类型** | `flowchart`（架构/数据流）、`sequenceDiagram`（交互时序）、`stateDiagram-v2`（状态机）；不含 ER/UI  mockup | 假设 |
| **一致性口径** | **生成后一键重渲一致**：各工具只产出/编辑 **Mermaid IR**；**视觉一致由 CI 同一 `mmdc` 主题 + SVG 导出保证** | 推断（工程可执行） |
| **非目标口径** | 「每次在 ChatGPT/Cursor 聊天窗里即时像素一致」—— **不保证**（宿主 Mermaid 版本/主题各异） | 事实 |
| **Codex 参照样本** | openai/codex issue 中的 Mermaid  reproduction；OpenAI 博客 **静态** 架构插图（语义分层，非 Mermaid 源）；ChatGPT iOS Codex 任务 **inline Mermaid** 能力说明 | 部分待核实 |
| **交付物** | Canonical：`docs/diagrams/*.mmd`；发布：`docs/figures/*.svg`（CI 生成） | 推断 |
| **语言** | 节点标签中/英均可；**同一 repo 内统一** | 团队约定 |

---

## 2. 「Codex 风格」冻结特征清单（≥10 条）

> **说明**：OpenAI **未发布** diagram 颜色/字体/线宽规范。下列 **视觉像素项** 在 Codex 典型输出为 **无 `classDef` 的 Mermaid**，最终像素 **由宿主 Mermaid 默认主题决定**（出处：Mermaid theming docs + issue 样例无 inline style）。表中 **「Codex 样本」** 指 openai/codex 或 OpenAI 公开材料中 **可复现** 的出图/说明。

| # | 特征维度 | 冻结描述 | 如何核对 | 标注 | 出处 |
|---|----------|----------|----------|------|------|
| F1 | **介质** | 架构说明以 **` ```mermaid ` 围栏源码** 交付；非仅 PNG/Excalidraw | issue 复现块含 `flowchart TD/LR` 源码 | **事实** | [openai/codex#35628](https://github.com/openai/codex/issues/35628), [#32356](https://github.com/openai/codex/issues/32356) |
| F2 | **是否手绘感** | **否**——几何/矢量框线图；Codex 生态讨论围绕 **Mermaid**，非 Excalidraw Sketch | 官方 issue 需求对象均为 `mermaid` fence | **事实** | #35628, #36660 |
| F3 | **布局方向** | 流程/架构常用 **`flowchart TD`**；链路型可用 **`LR`**（issue 样例二者均有） | 对照样例源码首行 | **事实** | #35628 (`TD`), #32356 (`LR`) |
| F4 | **箭头** | 主路径 **`-->`** 实线箭头；可选 **`-.->`** 表可选/异步（Mermaid 语法层） | 样例边符号 + Mermaid flowchart 文档 | **事实**（语法） | #35628 样例；[Mermaid flowchart](https://mermaid.js.org/syntax/flowchart.html) |
| F5 | **节点形状** | 过程 **`[]` 矩形**；分支 **`{}` 菱形**（#35628 明确 `B{Decision}`） | 样例节点括号类型 | **事实** | #35628 |
| F6 | **分组/标题层级** | 逻辑层用 **`subgraph id [Label]`**；**图标题在 Markdown 正文 `##`**，非 Mermaid 内嵌大 banner | 博客/App Server 分层语义 + Mermaid subgraph 文档；issue 未强制 subgraph | **推断**（结构） | [App Server 博客](https://openai.com/index/unlocking-the-codex-harness/)；[Mermaid subgraph](https://mermaid.js.org/syntax/flowchart.html) |
| F7 | **颜色** | 典型 Codex **Mermaid 样例不含 `classDef`/`style`** → 颜色 = **Mermaid `default`/`neutral` 主题变量**（如 `primaryColor` 等） | 样例源码无 inline 色；渲染后取样 | **事实**（无 custom）+ **推断**（具体色值属 Mermaid 非 OpenAI） | #35628, #32356；[Mermaid theming](https://github.com/mermaid-js/mermaid/blob/develop/docs/config/theming.md) |
| F8 | **字体** | 未检出 OpenAI 指定字体；**Mermaid 主题 `fontFamily` 默认栈**（常见 sans-serif） | `mmdc` 导出 SVG 的 `font-family` | **待核实**（Codex Web 宿主版本） | Mermaid theming docs |
| F9 | **线宽** | 样例无 `linkStyle`/`stroke-width` → **Mermaid/dagre 默认边宽**（通常 1px 级） | 导出 SVG `stroke-width` | **待核实**（随 Mermaid 版本） | Mermaid flowchart + theme docs |
| F10 | **圆角** | 默认矩形 **小圆角/直角由 Mermaid 主题 `nodeBorderRadius` 决定**；样例未用 `()` 圆角节点形状 | SVG `rx`/`ry` 或 shape 语法 | **待核实** | Mermaid theming docs |
| F11 | **间距** | **dagre 自动布局**；样例未手工坐标 | 同一 IR 多渲染器布局可能略异 | **事实**（布局引擎） | [Mermaid renderer=dagre](https://mermaid.js.org/syntax/flowchart.html) |
| F12 | **装饰** | 典型样例 **无 emoji/icon/`classDef` 配色**（与 Gemini 等对比） | 源码扫描 | **推断**（多样本） | #35628, #32356；对比 §6 |
| F13 | **边标签** | 常见 **`-->|文字|`** 表协议/动作/分支语义 | 样例与社区最佳实践 | **推断** | #35628 (`|yes|`, `|no|`)；Agent loop 博客语义 |
| F14 | **渲染面** | Web/部分移动端 **inline 渲染**；CLI/Android 部分面 **仅源码**（需 fallback PNG/SVG） | 产品/issue 行为 | **事实** | #35628, #32356, [#36660](https://github.com/openai/codex/issues/36660) |

### 2.1 清单使用规则

- **CI 可自动验**：F1、F3–F5、F7（无 classDef）、F12（可 lint）
- **需重渲后验**：F7–F10 像素项——**必须以 §4 路径③ 固定 `mmdc` 主题** 为准，不以 ChatGPT 聊天窗为准
- **禁止**：将 Mermaid 默认色值写成「OpenAI 官方品牌色」

---

## 3. 提示词能管什么、管不住什么

| 层级 | ① Skill/提示 **能管** | ① Skill/提示 **管不住** |
|------|----------------------|-------------------------|
| **结构** | diagram type、TD/LR、subgraph 命名、节点 ID 规则、边标签文案、禁 ASCII 替代 | 模型偶发违例、工具截断 |
| **语法** | 禁 `classDef`、引号规则、节点上限 | 模型仍可能输出非法 Mermaid |
| **语义** | 分层与协议名、图例说明 | 业务正确性 |
| **视觉像素** | 仅能通过 **禁止 inline style** 间接影响 | **颜色/字体/线宽/圆角/间距** 最终由 **路径③ 渲染器主题 + dagre** 决定 |
| **跨工具聊天窗** | 无法统一 | 各宿主 Mermaid 版本/主题 |
| **位图** | 可禁止「仅 PNG」 | 无法从提示词还原丢失的 IR |

**结论**：提示词是 **结构层约束**；**像素级 Codex-like 一致** 必须依赖 **② IR + ③ 统一渲染 + ④ 后处理**。

---

## 4. 四条实现路径（拆分对比，禁止混写）

### 4.1 路径① — 系统提示 / Skill 风格规约

**机制**：在 `AGENTS.md`、`.cursor/skills/`、Claude `SKILL.md`、Gemini Custom Instructions 写入 **Diagram Contract**（见 [examples/skill-diagram-codex-style.md](./examples/skill-diagram-codex-style.md)）。

**管什么**：F1、F3–F6、F12、F13 的结构与语法；禁止位图-only。

**管不住什么**：F7–F11 像素；聊天窗即时渲染；模型服从度 100%。

**成本**：低；**无 CI 像素保证**。

### 4.2 路径② — 统一中间表示（IR）

**机制**：Canonical **`docs/diagrams/*.mmd`**（默认 **Mermaid**；可选 Graphviz `.dot`、JSON 图模型如 ELK/D2——本报告 **默认 Mermaid**）。

| IR | 优点 | 缺点 |
|----|------|------|
| **Mermaid** | LLM 友好；Codex issue 样例一致；GH 可渲染 | 布局表达力有限 |
| Graphviz | 布局可控 | LLM 错误率高 |
| JSON 图模型 | 易 lint、可换布局引擎 | 需转换层；LLM 不友好 |

**管什么**：可 diff、可版本审；与工具解耦。

**管不住什么**：不自带像素；需路径③。

### 4.3 路径③ — 统一渲染器主题（同一导出管道）★视觉主路径

**机制**：CI/本地 **固定一条导出命令**，锁定主题与版本，例如：

```bash
# 示例：锁定 Mermaid 版本 + neutral 主题 + 透明底
npx -p @mermaid-js/mermaid-cli@11 mmdc \
  -i docs/diagrams/foo.mmd \
  -o docs/figures/foo.svg \
  -b transparent \
  -c docs/mermaid-config.json
```

`docs/mermaid-config.json` 可设 `theme: neutral` 或 `base` + 团队 `themeVariables`（**团队扩展，非 OpenAI 官方**）。

**管什么**：F7–F11 **在发布 SVG 上一致**；跨 Codex/Cursor/Claude/Gemini/Grok **发布物像素一致**。

**管不住什么**：各工具 **聊天窗内** 预览；bounded 子集渲染器（Grok `mermaid-to-svg`、Codex CLI 提案）可能与 `mmdc` 有差异——需 **supported-syntax 白名单**。

### 4.4 路径④ — 后处理（SVG/CSS 主题、布局重排）

**机制**：

- **Lint/Normalize**：`graph`→`flowchart`、strip `classDef`/`style`、ID/引号修复、节点数告警
- **布局重排**：Mermaid `elk` renderer、或 IR→Graphviz→SVG（复杂图）
- **SVG 后处理**：`svgo`、统一 CSS、`stroke-width`/`font-family` 注入（当需超越 Mermaid 主题时）

**管什么**：漂移修复、CI 红门、可选 **SVG diff** 回归。

**管不住什么**：无法从无 IR 的位图恢复结构（需降级 §7）。

---

## 5. 四条路径冻结对比表

| 维度 | ① Skill/提示 | ② 统一 IR | ③ 统一渲染主题 | ④ 后处理 |
|------|-------------|-----------|----------------|----------|
| **风格可控粒度** | 结构/语法 | 结构（语义图） | **像素（发布物）** | 像素微调+布局 |
| **跨工具一致性** | 低～中 | **高（源码）** | **高（SVG）** | 依赖上游 IR |
| **对模型服从度依赖** | **高** | 中 | 低 | 低 |
| **工程落地成本** | **最低** | 低 | 中（CI+锁版本） | 中～高 |
| **可 CI 校验** | 部分 lint 规则 | **IR diff** | **SVG diff / mmdc  exit code** | **lint + SVG diff** |
| **锁死图类型** | 否（靠提示） | 否（IR 可扩展） | 否（Mermaid 多 type） | 否 |
| **出处** | §3；examples | #35628；Mermaid docs | mermaid-cli；theming docs | VMark v11 lint 实践；Revision blog |

### 5.1 组合推荐（非混写口号）

| 组合 | 适用 | 推荐度 |
|------|------|--------|
| 仅① | 个人草稿 | ★★ |
| ①+② | 有 diff 无像素保证 | ★★★ |
| **②+③+①+④** | **团队默认** | ★★★★★ |
| ②+③+④（无①） | 人工写 IR | ★★★★ |
| 仅④ | 无效（无 IR） | ★ |

---

## 6. 跨工具默认输出对照（相对冻结清单）

| 工具 | 相对 F1–F14 的典型偏差 | 对齐手段 |
|------|------------------------|----------|
| Codex / ChatGPT | 基线；Web 渲染像素随宿主 | IR + ③ 重渲 |
| Cursor | 偶发 `graph` 旧语法 | ④ normalize |
| Claude CLI | **ASCII 框图**（违 F1/F2） | ① 禁 ASCII；强制 Mermaid |
| Gemini | **`classDef` 配色**（违 F12） | ① 禁止 + ④ strip |
| Grok Build | Mermaid 子集、sequence Unicode 化 | ② 白名单 + ③ `mmdc` 发布 |

---

## 7. 默认落地组合与位图降级

### 7.1 默认组合（主路径声明）

```text
用户/Agent（任意工具）+ ① Skill（结构）
    → ② docs/diagrams/*.mmd（canonical IR）
    → ④ lint/normalize（pre-commit / CI）
    → ③ mmdc + 锁定 mermaid-config.json → docs/figures/*.svg
    → report.md 引用 SVG + 折叠 Mermaid 源
```

- **主**：**② IR + ③ 单一渲染主题**
- **辅**：**① Skill**（降低 IR 脏度）
- **门**：**④ 后处理/lint**（可选 SVG diff）

**一致性口径**：**生成后一键重渲**——作者接受「聊天窗里看起来不同」，**合并前 SVG 必须来自同一条 `mmdc` 管道**。

### 7.2 工具只能出位图时的降级路径

| 步骤 | 动作 | 产物状态 |
|------|------|----------|
| D1 | 位图存入 `docs/figures/_derivative/<name>.png` | **非 canonical** |
| D2 | Metadata 标记 `source: bitmap-only`, `ir: missing` | 可追踪 |
| D3 | **反写 IR**：人工 / Vision 模型 → 草稿 `.mmd` | 待审 IR |
| D4 | 作者校对后 **`docs/diagrams/<name>.mmd` 入库** | **升为 canonical** |
| D5 | 跑 ③④ 重渲 SVG；**CI 仅对 `.mmd` 做 diff/SVG diff** | 一致发布物 |
| D6 | **无法反写**：保留 D1 位图 + 图注「无 IR，不可 diff」 | **不参与** 风格 CI |

**禁止**：把聊天截图直接当 canonical 替换 `.mmd`。

### 7.3 CI 片段（示意）

```bash
node scripts/lint-mermaid.js docs/diagrams/   # ④
npx -p @mermaid-js/mermaid-cli@11 mmdc -c docs/mermaid-config.json \
  -i docs/diagrams/foo.mmd -o docs/figures/foo.svg   # ③
# 可选：npx pixelmatch ...  # ④ SVG raster diff
```

---

## 8. 工作示例

### 8.1 约束前 vs 约束后（结构层）

方案：Client → App Server → ThreadManager → Core → Model/Tools。

| 要点 | 约束前（Gemini/Claude 漂移） | 约束后（对齐 F1–F6,F12） |
|------|------------------------------|---------------------------|
| 语法 | `graph`、ID 含空格 | `flowchart TD`、camelCase ID |
| 分组 | 无 subgraph | `subgraph client/harness/core` |
| 装饰 | `classDef` 紫色 | 无 classDef |
| 边 | 无标签 | `\|JSON-RPC\|`、`\|tool call\|` |

源码：[examples/before-after.mmd](./examples/before-after.mmd)

### 8.2 冻结清单自检（示例）

对 [examples/agent-loop-codex-style.mmd](./examples/agent-loop-codex-style.mmd)：

| 检查项 | 结果 |
|--------|------|
| F1 mermaid 围栏 / .mmd | ✅ |
| F3 flowchart TD | ✅ |
| F5 `[]` / `{}` | ✅ |
| F6 subgraph | ✅ |
| F12 无 classDef | ✅ |
| F7–F10 像素 | ⬜ 需 `mmdc` 导出后对照团队 `mermaid-config.json` |

详表：[examples/lint-checklist-example.md](./examples/lint-checklist-example.md)

---

## 9. 风险与待核实

| 待核实项 | 影响 |
|----------|------|
| ChatGPT/Codex Web **当前 Mermaid  major 版本** | 聊天预览 vs `mmdc` 语法差 |
| Codex Web **默认 theme 名**（default/neutral/dark） | F7–F10 对照基准 |
| OpenAI 内部是否存在未公开 Diagram Style Guide | 若未来公开需修订 §2 |
| Vision 反写位图 → Mermaid 的准确率 | 降级 D3 成本 |

**翻车条件**：专有画布、bounded 渲染器 + 高阶语法、仅 ASCII、多视图无模型库、位图当 canonical。

---

## 10. 决策问题正式答复

### Q1. Codex 风格可核对特征？

见 **§2 冻结清单 F1–F14**。有 OpenAI 直接出处的主要为 **F1–F5、F14**；**F7–F10 像素项** 来自 **Mermaid 默认主题 + 无 inline style 的 Codex issue 样例**；**F8–F10 在 Codex Web 的确切值待核实**。

### Q2. 跨工具统一主路径？

**② IR + ③ 统一渲染主题** 为主；**① Skill** 为辅；**④ 后处理** 为 CI 门。**不是**「加提示词」单路径。

### Q3. 默认组合与位图降级？

见 **§7**。**生成后一键重渲**；位图走 **D1–D6 降级**，canonical 始终 `.mmd`。

---

## 11. 出处

见 [sources.md](./sources.md)（16 条）。

---

## 附录 A：Mermaid 子集白名单（bounded 渲染器友好）

与初版相同：`flowchart TD|LR`、`subgraph id [Title]`、基础边与 sequence；禁 `icon`/experimental chart。

---

## 附录 B：与 fpga 报告协同

fpga 主题 report 内 **ASCII 机制简图** 保留；**对外架构** 走本报告 **②+③** 管道；职责分离，不混 canonical。
