# 出处清单与抓取备注

**调研目录：** `fpga-hw-orderbook-price-level-20260916-0838`  
**抓取时间：** Asia/Shanghai 2026-09-16（第二轮落盘）

---

## 主出处（report.md §12 扩展）

| ID | URL | 抓取状态 | 事实/推断/待核实 | 备注 |
|----|-----|----------|------------------|------|
| S1 | http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf | ✅ PDF 全文可读 | **事实** | penny offset、8192 共享阵列、tracker 三规则、rebase stretch |
| S2 | https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf | ✅ PDF 全文 | **事实** | Eq.1、mask&addr reduction、Top-5 bitonic cache、clipped tree、Table II latency |
| S3 | https://github.com/alchevrier/fpga-feed-handler | ✅ README + ADR | **事实** | idx=(p-base)/tick、AOS、DATAFLOW 冷路径、filter_event、ADR-005/006/012 |
| S4 | https://rndshowcase.iiit.ac.in/tto2024/TTO_website_data/PDF/25.pdf | ✅ Poster PDF | **事实** | URAM 62.5%、valid bitmask、topCache、HBM 存 order 历史 |
| S5 | https://doi.org/10.1109/fpl60245.2023.00051 | ⚠️ 摘要页 | **事实**（摘要级） | 与 S4 同组；hybrid 细节需全文 **待核实** |
| S6 | https://doi.org/10.1109/asap61560.2024.00025 | ⚠️ 摘要页 | **事实**（摘要级） | DRAM 映射、两级 CACHE；具体 addr 公式 **待核实** |
| S7 | https://punt-engine.com/notes/the-architecture-of-a-pipelined-order-book | ✅ 全文 | **事实** | mod m 环形窗、alias 例、k-best rebalance |
| S8 | https://github.com/adilsondias-engineer/08-fpga-order-book | ✅ README | **事实** | 256×82b、128+128 地址映射、2-cycle RMW、SCAN FSM |
| S9 | https://www.mdpi.com/2079-9292/12/3/520 | ✅ 全文（agent fetch） | **事实** | dummy price node 水平链；vertical 单链为 per-order |
| S10 | https://hugobrh.dev/posts/Trademaxxer_Price_ladder/ | ✅ 摘要+正文片段 | **事实** | 1K entry、5¢ step、2R1W BRAM、越界 write_enable |
| S11 | https://doi.org/10.14711/thesis-991013159956803412 | ⚠️ 摘要+片段 | **事实** | HFOBU 槽数随收盘价×tick 缩放表 |
| S12 | https://doi.org/10.1145/3020078.3021775 | ⚠️ 摘要 | **事实**（边界） | FPGA cache + CPU tree；档位层仅借鉴 Top 投影思想 |

---

## 次要 / 对比引用

| URL | 用途 | 标注 |
|-----|------|------|
| https://doi.org/10.23919/fpl.2017.8056862 | S2 正式 DOI | **事实** |
| https://github.com/mmzarif/fpga-order-book | 反例：sorted order array 非档位聚合 | **事实**（非推荐架构） |
| http://algo-logic.com/orderbook | 商业 Full OB 延迟宣称 | **待核实**（无内部结构） |
| NovaSparks press release（FPL17 引用） | 竞品延迟区间 | **待核实** |

---

## 本轮相对 0834 新增出处

- **S10** BRH price ladder（0834 未列）
- **S11** 港大论文容量缩放（0834 未列）
- **S12** Hybrid list（0834 未列）
- **S5** FPL 2023 正式 DOI（0834 仅 IIT poster）

---

## 抓取限制说明

1. **MDPI / IEEE** 部分为 HTML 摘要；机制细节以可访问 PDF/HTML 为准，未访问处标 **待核实**。
2. **商业 FPGA OB IP**（NovaSparks、Algo-Logic）无公开档位字段布局 — 不写入机制表具体行。
3. **延迟 ns 数字**：仅转述论文/博客 **已发表** 值（如 FPL17 132–288ns、ASAP 26–209ns），**不作为** 本报告选型硬指标（任务 Out）。
4. 本地 agent-tools 缓存为抓取中间文件，**不提交 git**。

---

## Bib 风格快捷引用

```bibtex
@inproceedings{he2017hfobu,
  title={Exploring the Potential of Reconfigurable Platforms for Order Book Update},
  author={He, Conghui and others},
  booktitle={FPL},
  year={2017},
  doi={10.23919/fpl.2017.8056862}
}

@inproceedings{kashera2023hybrid,
  title={Building Low-Latency Order Books with Hybrid Binary-Linear Search Data Structures on FPGAs},
  booktitle={FPL},
  year={2023},
  doi={10.1109/fpl60245.2023.00051}
}
```
