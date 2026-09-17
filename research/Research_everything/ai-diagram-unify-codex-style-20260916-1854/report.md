# AI 方案设计图跨工具统一 → Codex 风格

**收紧修订** · Asia/Shanghai 2026-09-16 · 仓 [Research_everything](https://cursor.com/codebase/melon5253/Research_everything) · 目录 `ai-diagram-unify-codex-style-20260916-1854/`

---

## 结论摘要（≤10 行）

1. **证伪 S19**：OpenAI **未公开** Codex Diagram Design System；可操作锚点 = **§2 F1–F12**（issue 样例 + Mermaid 文档），**禁止**编造官方配色/字体。
2. **默认方案**：**② `docs/diagrams/*.mmd` + ③ 锁定 `mmdc`（S9：`-i/-o/-c`）** 为主，**① Skill** 为辅，**④ lint** 为 CI 门；口径 **生成后一键重渲**（S1,S2）。
3. **四路径拆分**：① Skill ② IR ③ 渲染主题 ④ 后处理 — **禁止**混写为「加提示词即统一像素」（S7,S15）。
4. **提示词**管结构/语法（F1–F6,F10,F12）；**管不住** F7–F9 像素与各宿主 Mermaid 版本（S1,S7,S10）。
5. **位图降级**：仅 PNG → `_derivative/` → 反写 `.mmd` → ③ 重渲；位图 never canonical（S2）。
6. **Out**：训练微调、绘图 SaaS、**未核实 ns / RTL top / 策略报单**、伪造 Codex VI（见 §0）。
7. **翻车条件**：专有画布 S20、bounded 子集 S1/S14、Claude ASCII S10、classDef 主路径、位图当 canonical、指望聊天窗一致 S1/S21。
8. 证据：[`sources.md`](./sources.md) S1–S21（含 **证伪 S19、边界 S20/S21**）；[`evidence/`](./evidence/)；[`onepager.md`](./onepager.md)。

---

## 一页纸速览

> 独立文件：[onepager.md](./onepager.md)

| 决策 | 答案 | 出处 |
|------|------|------|
| 官方 Codex 绘图 Spec？ | **不存在可引用公开版** | **S19** |
| 主路径？ | IR + 锁定 `mmdc` | S9,S7 |
| 提示词边界？ | 结构 yes / 像素 no | S7,S1 |
| 位图？ | 降级 D1–D6 | S2 |

---

## 0. 范围

### In

| 项 | 出处 |
|----|------|
| 多工具架构/数据流/时序图对齐 Codex **可观察** Mermaid 习惯 | S1,S2 |
| 四路径、Skill、`mmdc` CI、位图降级 | S9,S16 |
| Markdown + Mermaid 仓库协同 | S11 |

### Out

| 项 | 说明 |
|----|------|
| 训练/微调 | 用户指定 Out |
| 完整绘图 SaaS | 用户指定 Out |
| FPGA / 本仓无关 RTL 机制 | 用户指定 Out |
| **未核实 ns** | 无时序 primary，不入论断 |
| **RTL top** | 非本专题 |
| **策略报单** | 非本专题 |
| OpenAI 品牌法律 | 无 primary |
| **编造 Codex 官方 diagram 规范** | **S19 证伪** |

---

## 1. 假设与口径

| 参数 | 假定 | 标注 | 出处 |
|------|------|------|------|
| 对齐工具 | Codex/ChatGPT、Cursor、Claude、Gemini、Grok | 假设 | 团队裁剪 |
| 图类型 | `flowchart`、`sequenceDiagram`、`stateDiagram-v2` | 假设 | S1 首版 scope 仅 flowchart |
| 一致性 | 生成后 **同一 `mmdc` 管道** 出 SVG | 推断 | S9 |
| 非目标 | 聊天窗即时像素一致 | **事实** | S1 仅源码；S10 ASCII |
| Canonical 路径 | `docs/diagrams/*.mmd` → `docs/figures/*.svg` | 推断 | S9 CLI 契约 |

---

## 2. Codex 风格冻结特征（F1–F12）

> **不是**官方 Spec（**S19**）。视觉像素 = Mermaid `themeVariables`（**S7**），非 OpenAI VI。

| ID | 特征 | 如何核对 | 标注 | 出处 |
|----|------|----------|------|------|
| F1 | Mermaid 围栏 / `.mmd` 交付 | 查 `flowchart`/`sequenceDiagram` 源码 | 事实 | S1,S2 |
| F2 | 几何框线（非 Excalidraw） | issue 对象均为 `mermaid` fence | 事实 | S1,S2 |
| F3 | `flowchart TD` 或 `LR` | 样例首行 | 事实 | S1 `TD`; S2 `LR` |
| F4 | `-->`；可选 `-.->`；`\|label\|` | 样例边 + S6 语法页 | 事实 | S1,S6 |
| F5 | 过程 `[]`；决策 `{}` | S1 样例 `B{Decision}` | 事实 | S1 |
| F6 | `subgraph id [Label]`；标题在 Markdown | S6 subgraph；S5 四层组件名 | 推断 | S5,S6 |
| F7 | 样例无 `classDef`/`style` | grep 源码；SVG `fill` | 事实+推断 | S1,S2,S7 |
| F8 | 字体 = Mermaid `fontFamily` | SVG `font-family` vs S7 默认栈 | **待核实**（Codex Web） | S7 |
| F9 | 线宽/圆角 = 主题+dagre 默认 | SVG `stroke-width`/`rx` | **待核实** | S7,S6 |
| F10 | 边标签表协议/分支 | S1 `\|yes\|/\|no\|` | 推断 | S1,S4 |
| F11 | 渲染面：Web inline；CLI/Android 常仅源码 | issue 行为描述 | 事实 | S1,S2,S3 |
| F12 | 无 emoji/icon/classDef 配色 | lint `noClassDef` | 推断 | S1,S2 |

像素核对步骤：[`evidence/pixel-verification-checklist.md`](./evidence/pixel-verification-checklist.md)（**S7,S9**）。

---

## 3. 提示词能管 / 管不住

| 层级 | ① 能管 | ① 管不住 | 出处 |
|------|--------|----------|------|
| 结构 | type、TD/LR、subgraph、ID、边标签 | 模型违例、截断 | S15,S10 |
| 语法 | 禁 classDef、白名单 type | 非法 Mermaid | S16 |
| 语义 | 分层名、协议名 | 业务正确性 | — |
| 像素 | 仅间接（禁 inline style） | F7–F9 | **S7** |
| 聊天窗 | — | 宿主版本/是否渲染 | **S1,S21** |
| 位图 | 禁 PNG-only 交付 | 无法恢复 IR | S2 |

矩阵详表：[`evidence/prompt-vs-pipeline-matrix.md`](./evidence/prompt-vs-pipeline-matrix.md)（单元格均绑 S#）。

---

## 4. 四条路径

### 4.1 ① Skill / 系统提示

| 项 | 内容 | 出处 |
|----|------|------|
| 触点 | `AGENTS.md`、`.cursor/skills/`、`SKILL.md` | S15 |
| 管 | F1–F6,F10,F12 | S15 |
| 不管 | F7–F9；聊天预览 | S7,S1 |
| 示例 | [`examples/skill-diagram-codex-style.md`](./examples/skill-diagram-codex-style.md) | — |

### 4.2 ② 统一 IR

| IR | 依据 | 标注 | 出处 |
|----|------|------|------|
| Mermaid `.mmd` | Codex issue 样例一致 | 推断默认 | S1,S2,S6 |
| Graphviz | 布局强 | 备选 | — |
| JSON 图 | lint 易 | 需转换 | — |

### 4.3 ③ 统一渲染（视觉主路径）

**接口（S9）：** `@mermaid-js/mermaid-cli` → 可执行文件 **`mmdc`**

```bash
npx -p @mermaid-js/mermaid-cli@11 mmdc \
  -i docs/diagrams/foo.mmd \
  -o docs/figures/foo.svg \
  -b transparent \
  -c docs/mermaid-config.json
```

| 项 | 内容 | 出处 |
|----|------|------|
| 主题变量 | `theme`/`themeVariables`/`flowchart.defaultRenderer` | **S7** `mermaid.initialize` 同名字段 |
| 配置样例 | [`evidence/mermaid-config.example.json`](./evidence/mermaid-config.example.json) | 团队选 `neutral`，**非 OpenAI** |
| 管 | 发布 SVG 上 F7–F9 一致 | S7,S9 |
| 不管 | 聊天窗；bounded 子集 | S1,S14 |

**Mermaid 引擎（S8）：** `github.com/mermaid-js/mermaid` → `packages/mermaid/`；初始化 API `mermaid.initialize({ theme, themeVariables, flowchart })`。

**Bounded 渲染（S14）：** `warpdotdev/mermaid-to-svg` Rust crate — **子集** Mermaid→SVG，高阶语法可能失败。

### 4.4 ④ 后处理

| 动作 | 依据 | 出处 |
|------|------|------|
| strip `classDef`/`style` | F7,F12 | S1,S16 |
| `graph`→`flowchart` | 旧语法 | S16 |
| SVG diff | CI 回归 | S9 导出链 |
| 脚本 | [`evidence/pipeline-ci-snippet.sh`](./evidence/pipeline-ci-snippet.sh) | — |

---

## 5. 四路径对比表

| 维度 | ① Skill | ② IR | ③ 渲染 | ④ 后处理 |
|------|---------|------|--------|----------|
| 可控粒度 | 结构/语法 | 结构 | **发布像素** | 微调+布局 |
| 跨工具一致 | 低–中 | 高（源码） | 高（SVG） | 依赖② |
| 模型依赖 | 高 | 中 | 低 | 低 |
| 落地成本 | 最低 | 低 | 中 | 中–高 |
| CI | 部分 lint | IR diff | `mmdc` exit | lint+SVG diff |
| 出处 | S15 | S1,S6 | S7,S9 | S16 |

### 5.1 组合

| 组合 | 推荐 | 出处 |
|------|------|------|
| 仅① | ★★ | 推断 |
| ①+② | ★★★ | 推断 |
| **②+③+①+④** | **★★★★★ 默认** | S9,S7,S15,S16 |
| 仅④ | ★ 无效 | 推断（无 IR） |

---

## 6. 跨工具偏差（有 primary 才入表）

| 工具/面 | 偏差 | 对齐 | 标注 | 出处 |
|---------|------|------|------|------|
| Codex ChatGPT Web | 像素随宿主 Mermaid | ②+③ | 待核实 major | S1,S2 |
| Codex CLI TUI | **不渲染，仅源码** | ②+③ | 事实 | **S1** |
| Codex Android remote | Mermaid 不可见 | ②+③+PNG fallback | 事实 | **S2** |
| Cursor | 可出 Mermaid；无像素规范 | ②+③+④ | 推断 | S12 |
| Claude Code CLI | **ASCII 框图** | ①禁+②+③ | 事实 | **S10** |
| Claude VS Code ext | mermaid 块不渲染 | ②+③ 发布 SVG | 边界 | **S10,S21** |
| GitHub Markdown | 原生渲染 fenced mermaid | ②+③ 与 GH 可能异 | 事实 | S11 |

无 primary 的 Gemini/Grok 子集行 **已删除**（留 §9 待核实）。

详表：[`evidence/cross-tool-deviation-matrix.md`](./evidence/cross-tool-deviation-matrix.md)

---

## 7. 默认方案 + 位图降级

### 7.1 主路径

```text
Agent（任意工具）+ ① Skill
  → ② docs/diagrams/*.mmd
  → ④ lint
  → ③ mmdc -c docs/mermaid-config.json
  → docs/figures/*.svg
```

| 角色 | 路径 | 出处 |
|------|------|------|
| 主 | ②+③ | S9,S7 |
| 辅 | ① | S15 |
| 门 | ④ | S16 |

### 7.2 位图 D1–D6

| 步 | 动作 | 状态 | 出处 |
|----|------|------|------|
| D1 | `_derivative/*.png` | 非 canonical | S2 |
| D2 | metadata `ir: missing` | 追踪 | 推断 |
| D3 | Vision/人工 → 草稿 `.mmd` | 待审 | 待核实 |
| D4 | 入库 `docs/diagrams/` | canonical | S9 |
| D5 | ③④ 重渲 | 发布 SVG | S9 |
| D6 | 无法反写 | 不参与 CI diff | 推断 |

S2 原文建议：**「Mermaid source for editing/version control, SVG or PNG for reliable mobile viewing」** — **事实**（issue 建议，非产品已实现声明）。

---

## 8. 工作示例

| 文件 | 对齐 | 出处 |
|------|------|------|
| [`examples/app-server-harness.mmd`](./examples/app-server-harness.mmd) | F6,F10 | S5 四层组件 |
| [`examples/agent-loop-codex-style.mmd`](./examples/agent-loop-codex-style.mmd) | F3–F5,F10 | S1 样例结构 |
| [`examples/before-after.mmd`](./examples/before-after.mmd) AFTER | F1–F7,F12 | S1,S5 |
| BEFORE（注释） | classDef 漂移 | **合成** | **S18** |

---

## 9. 待核实与证伪/边界

### 9.1 待核实

| 项 | 核对法 | 出处 |
|----|--------|------|
| Codex Web Mermaid major | DevTools `mermaid.version` | — |
| Codex Web 默认 theme | 导出 SVG vs S7 | S7 |
| Grok Mermaid 子集 | 重抓 changelog | 已删 §6 行 |
| Vision 反写准确率 | 抽样 | — |

### 9.2 证伪（S19）

检索 OpenAI 博客（S4,S5）与 openai/codex issue（S1–S3）：**零** diagram 颜色/字体/线宽公开规范链接 → **不存在可引用 Codex Diagram Design System**。团队 `mermaid-config.json` 为 **自订**，不得标「官方」。

摘录：[`evidence/falsification-boundary-notes.md`](./evidence/falsification-boundary-notes.md)

### 9.3 边界（主方案失效条件）

| 边界 | 含义 | 出处 |
|------|------|------|
| **S20** | `/design` 持久架构画布 → IR 非唯一真相 | openai/codex#35100 |
| **S21** | Claude VS Code Mermaid **NOT_PLANNED** → 不能指望聊天窗预览 | #20529 via S10 |
| **S1** | CLI 提案 **禁 shell out `mmdc`** → 终端预览与 CI SVG **长期分叉** | #35628 |
| **S14** | bounded Rust 子集 ≠ 完整 Mermaid | warpdotdev/mermaid-to-svg |

### 9.4 翻车条件（汇总）

专有画布（S20）、bounded+高阶语法（S1,S14）、ASCII 架构图（S10）、classDef 当主风格（S1 样例反面）、位图 canonical（S2）、聊天窗像素当交付（S1,S21）。

---

## 10. 决策答复

| Q | A | 出处 |
|---|---|------|
| Codex 风格？ | §2 F1–F12；**无官方 Spec** | S19,S1–S7 |
| 主路径？ | ② IR + ③ `mmdc`；① 辅；④ 门 | S9,S15,S16 |
| 位图？ | D1–D6；`.mmd` canonical | S2,S9 |

---

## 11. 出处

[`sources.md`](./sources.md) · [`evidence/`](./evidence/)

---

## 附录 A：bounded 白名单

与 S1 首版 scope：**flowchart TD|LR**、`subgraph`、基础 sequence/state；禁 `icon`/experimental/`classDef` — **S1,S6,S16**。

## 附录 B：与 fpga 报告

fpga 报告 ASCII 机制图可保留；**对外架构** 走 ②+③；不混 canonical — 本仓分工，无 primary。
