# Prompt 片段（路径①）

## 系统级（AGENTS.md）

```markdown
## Diagrams（路径①，需配合 mmdc）
- Canonical: docs/diagrams/*.mmd
- 结构: flowchart TD + subgraph; 禁 classDef/ASCII-only
- 像素: 合并前运行 mmdc -c docs/mermaid-config.json
- 提示词不保证聊天窗颜色；以 CI SVG 为准
```

## User（结构约束）

```text
按 diagram-codex-style 输出 Mermaid：
flowchart TD、subgraph 分层、[]/{}、边带标签、无 classDef。
写入 docs/diagrams/foo.mmd。不要 PNG。
```

## User（位图降级）

```text
你给了 PNG 但没有 Mermaid。请根据该图反写等价 Mermaid IR（flowchart TD），
标注不确定处；输出 .mmd 供 mmdc 重渲。原 PNG 仅作 derivative 参考。
```

## 四条路径对照（勿混写）

| 错误说法 | 正确说法 |
|----------|----------|
| 「加提示词就能统一 Codex 颜色」 | 提示词统一 **结构**；颜色靠 **mmdc 主题** |
| 「在 ChatGPT 里看起来一样就行」 | **生成后一键重渲** SVG 为准 |
| 「后处理可以替代 IR」 | 无 `.mmd` 则 ④ 无法 diff |
