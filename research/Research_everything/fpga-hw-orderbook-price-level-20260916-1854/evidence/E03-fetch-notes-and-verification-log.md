# E03 — 抓取核对日志（收紧版）

**目录：** `fpga-hw-orderbook-price-level-20260916-1854/`

## 开源仓阅读路径（必填项）

| ID | 仓 | 已读路径 | 标注 |
|----|-----|----------|------|
| S3 | alchevrier/fpga-feed-handler | `README.md`；`docs/adr/ADR-004-order-book-bram-aos.md`；`ADR-005-mathematical-index-deterministic-addressing.md`；`ADR-012-hot-path-register-store-buffer.md`；`ADR-016-early-exit-event-filter.md` | **事实** |
| S8 | adilsondias-engineer/08-fpga-order-book | `README.md`（含 `price_level_table.vhd` / `bbo_tracker.vhd` 模块说明） | **事实** |
| S14 | mmzarif/fpga-order-book | `README.md` Features；目录树 `rtl/order_book.sv`（未 fetch 全文） | **事实**（边界） |

## PDF/HTML 抓取

| ID | 状态 | 章节用于留证 |
|----|------|--------------|
| S1 | ✅ 全文 | §3.1.3, Table 2 |
| S2 | ✅ 全文 | §III–IV, Algorithm 2 |
| S4 | ✅ Poster | ABSTRACT, Util 表 |
| S7 | ✅ HTML | §Bid processors, §Caching |
| S9 | ✅ HTML | §3 Fig.6, §5.2 |
| S10 | ✅ 博文 | Tradeoffs, Datapath |
| S5,S6,S11,S13 | ⚠️ 摘要/超时 | 仅摘要级断言，闭式 **待核实** |

## 本轮收紧删除项

| 删除内容 | 原因 |
|----------|------|
| 「空槽 >70%」 | 无出处量化阈值 |
| 示例③ 自算 mod 1024 | 改为 S7 原文 alias 句 |
| report 内 ns 数字作选型 | 本题 Out |
| Top-K 1024b 无 ADR 路径的精确位宽推断 | 改为仅引 S3「8 槽/侧」 |

## 证伪源（≥1）

**S14** — sorted order array 架构，证伪「所有 FPGA OB 都用档位聚合槽」之全称；边界见 `report.md` §9。
