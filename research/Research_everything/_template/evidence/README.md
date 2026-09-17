# evidence/ — 调研证据留存

本目录存放**支撑 `report.md` 与 `sources.md` 的原始痕迹**，便于审计，无需读者重新抓取。

## 放什么

| 类型 | 示例 | 说明 |
|------|------|------|
| 抓取备注 | `fetch-rfc9293.md` | HTTP 状态、可读章节、付费墙、镜像 URL |
| 短摘录 | `excerpt-toe-reorder.txt` | ≤ 一段引文 + 来源 URL；勿整篇粘贴 |
| 对比草稿 | `table-draft.md` | 入 `report.md` 前的维度对比草稿 |
| 截图/导出 | `fig-*.png` | 可选；大图放 `figures/` 亦可 |

## 不放什么

- API 密钥、凭证、内网 URL、客户数据
- 整篇论文/PDF 副本（用 DOI/URL 链接即可）
- 与报告无关的临时文件

## 命名建议

`<source-id>-<short-desc>.<ext>` — 例如 `S4-patent-ooo-handler.txt`
