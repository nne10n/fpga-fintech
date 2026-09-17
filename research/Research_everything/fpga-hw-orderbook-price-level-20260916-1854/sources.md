# 出处清单（留证硬规则版）

**目录：** `fpga-hw-orderbook-price-level-20260916-1854/`  
**仓：** Research_everything  
**修订：** 2026-09-16 — 批量统一收紧（5 题共用规则）

正文编号 **S1–S14**。对比表/机制断言/数字须能指回下表 **「可读路径」** 列；否则正文标 **待核实** 或删除。

---

## 主出处（14 条可点击 URL，≥10）

| ID | URL | 可读路径（章节/文件） | 档位层支撑点 | 标注 |
|----|-----|----------------------|--------------|------|
| **S1** | [Columbia 4840 ITCH OB PDF](http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf) | §3.1.3；Table 1–2；Register Map Table 3 | penny offset、8192 合表、字段位宽、tracker 三规则、越界 ERR、rebase stretch | **事实** |
| **S2** | [FPL17 HFOBU PDF](https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf) | §III Eq.1；§III-B Fig.4；§IV；Algorithm 2 | fixed tick、mask&addr、Top-5 cache、next 链、clipped tree | **事实** |
| **S3** | [fpga-feed-handler](https://github.com/alchevrier/fpga-feed-handler) | `README.md`；`docs/adr/ADR-004-order-book-bram-aos.md`；`docs/adr/ADR-005-mathematical-index-deterministic-addressing.md`；`docs/adr/ADR-012-hot-path-register-store-buffer.md`；`docs/adr/ADR-016-early-exit-event-filter.md` | idx 公式、AOS、side 地址位、Register Top-K 规划、filt 越界 | **事实** |
| **S4** | [IIT TTO 2024 Poster](https://rndshowcase.iiit.ac.in/tto2024/TTO_website_data/PDF/25.pdf) | ABSTRACT；CONTRIBUTIONS；Logic Utilization 表 | URAM 62.5%、bitmask、topCache、hybrid 搜 | **事实** |
| **S5** | [FPL 2023 Hybrid DOI](https://doi.org/10.1109/fpl60245.2023.00051) | 摘要页 | 与 S4 同组；分界闭式 | **待核实**（摘要） |
| **S6** | [ASAP 2024 FPGA LOB DOI](https://doi.org/10.1109/asap61560.2024.00025) | 摘要 contributions 段 | DRAM px→row、两级 CACHE | **事实**（摘要） |
| **S7** | [Pipebomb 架构笔记](https://punt-engine.com/notes/the-architecture-of-a-pipelined-order-book) | §Bid and ask processors；§Caching | mod m、alias 句、k-best rebalance | **事实** |
| **S8** | [08-fpga-order-book](https://github.com/adilsondias-engineer/08-fpga-order-book) | `README.md` §Price Level Table / §BBO Tracker / §BRAM Inference | 256×82b、128+128 映射、2-cycle RMW、FSM 扫 | **事实** |
| **S9** | [MDPI Electronics 2023](https://www.mdpi.com/2079-9292/12/3/520) | §3 架构 Fig.6；§5.2 INSERT | dummy price node 水平链；vertical=per-order | **事实** |
| **S10** | [BRH Price Ladder](https://hugobrh.dev/posts/Trademaxxer_Price_ladder/) | §Design Tradeoffs；§Datapath | 1K entry、5¢ step、`mem[price]={is_buy,qty}`、越界 drop | **事实** |
| **S11** | [HKU HFOBU Thesis](https://doi.org/10.14711/thesis-991013159956803412) | — | 槽数随收盘价×tick | **待核实**（未全文） |
| **S12** | [FPL17 DOI](https://doi.org/10.23919/fpl.2017.8056862) | 元数据 | S2 正式引用 | **事实** |
| **S13** | [Wray ASAP 2010](https://doi.org/10.1109/asap.2010.5540966) | — | FPGA 交易 OB 先驱 | **待核实** |
| **S14** | [mmzarif/fpga-order-book](https://github.com/mmzarif/fpga-order-book) | `README.md` Features；`rtl/order_book.sv` | **证伪/边界：** sorted bid/ask **order array**，非 per-price 聚合槽 | **事实** |

---

## 证伪/边界源（至少 1 条，必填）

**S14** 明确采用 *「Sorted bid/ask arrays」* 存 **逐单 ID/价/量**（`README.md` Features），与 S1/S2 **档位聚合槽** 索引模型不同。本题 **In** 仅档位层；S14 说明「sorted order array ≠ 档位聚合默认方案」——选型档位表时勿照搬 S14 结构。

---

## 开源仓已读文件清单

| 仓 | 本次实际阅读路径 | 未读（不写入机制表） |
|----|------------------|----------------------|
| S3 fpga-feed-handler | `README.md`；`docs/adr/ADR-004*.md`；`ADR-005*.md`；`ADR-012*.md`；`ADR-016*.md` | `src/*.cpp` RTL 未逐行核 |
| S8 08-fpga-order-book | `README.md`（含 `price_level_table.vhd` / `bbo_tracker.vhd` 描述） | `.vhd` 源文件未在本轮 fetch |
| S14 mmzarif | `README.md`；结构树含 `rtl/order_book.sv` | `order_book.sv` 未 fetch 全文 |

---

## 留证规则（本轮写入）

1. **对比表单元格**：须含 `S? + §/文件`；写不出 → **待核实** 或删行。  
2. **数字**：仅转述上表可读路径中的数；无路径则删（例：删除无出处的「空槽 >70%」）。  
3. **ns 延迟**：论文/Poster 虽有发表值，本题 **Out**，不进选型表。  
4. **推断**：默认方案/翻车映射可标 **推断**，但不得与 **事实** 源矛盾。

---

## Bib

见上一轮 `sources.md` Bib 块（S1/S2/S5/S6 DOI 未变）。
