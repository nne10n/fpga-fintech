# 像素特征核对（F7–F9）

绑定 **S7,S9** · 数字必须来自 S7 或导出实测

## 命令（S9 接口）

```bash
npx -p @mermaid-js/mermaid-cli@11 mmdc \
  -i examples/agent-loop-codex-style.mmd \
  -o evidence/out/agent-loop.svg \
  -b transparent \
  -c evidence/mermaid-config.example.json
```

| ID | 检查 | 方法 | 期望 | 标注 | 出处 |
|----|------|------|------|------|------|
| F7 | 无 classDef | `grep classDef examples/*.mmd` | 无匹配 | 事实 | S1,S2 |
| F7 | 节点 fill | SVG `fill=` | 非 S18 合成 `#f3e8ff` | 推断 | S7,S18 |
| F8 | font-family | SVG grep | 含 config 或 S7 默认栈 | 待核实 | **S7** `trebuchet ms…` |
| F9 | stroke-width | SVG grep | 1px 级 | 待核实 | S7 |
| F9 | rx/ry | SVG grep | 主题默认 | 待核实 | S7 |

## S7 默认数字（非 Codex 官方）

| 变量 | 值 | 出处 |
|------|-----|------|
| fontSize | 16px | **S7** |
| primaryColor | #fff4dd | **S7** |
| fontFamily | trebuchet ms, verdana, arial | **S7** |

**禁止：** 上表数值写入「Codex 官方规范」（**S19 证伪**）。
