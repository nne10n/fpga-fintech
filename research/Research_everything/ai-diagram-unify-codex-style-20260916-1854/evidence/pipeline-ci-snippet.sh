#!/usr/bin/env bash
# 路径 ②→④→③ 示意 CI 片段（非生产脚本）
# 标注：推断 · 团队可按 monorepo 调整路径

set -euo pipefail

ROOT="${1:-.}"
DIAGRAMS="${ROOT}/docs/diagrams"
FIGURES="${ROOT}/docs/figures"
CONFIG="${ROOT}/docs/mermaid-config.json"
MERMAID_CLI_VERSION="${MERMAID_CLI_VERSION:-11}"

echo "== ④ Lint Mermaid IR =="
# 伪实现：grep 禁 classDef、graph→flowchart 告警
for f in "${DIAGRAMS}"/*.mmd; do
  [[ -f "$f" ]] || continue
  if grep -qE 'classDef|^[[:space:]]*style ' "$f"; then
    echo "FAIL: inline style/classDef in $f (F7,F12)" >&2
    exit 1
  fi
  if grep -qE '^graph ' "$f"; then
    echo "WARN: legacy 'graph' in $f — normalize to flowchart" >&2
  fi
done

echo "== ③ mmdc 锁定主题导出 =="
mkdir -p "${FIGURES}"
for f in "${DIAGRAMS}"/*.mmd; do
  [[ -f "$f" ]] || continue
  base="$(basename "$f" .mmd)"
  npx -p "@mermaid-js/mermaid-cli@${MERMAID_CLI_VERSION}" mmdc \
    -i "$f" \
    -o "${FIGURES}/${base}.svg" \
    -b transparent \
    -c "${CONFIG}"
done

echo "== ④ 可选 SVG golden diff =="
# npx pixelmatch rendered.png golden.png

echo "OK: canonical IR → locked theme SVG"
