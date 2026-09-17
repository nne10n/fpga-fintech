# 出处清单

**调研目录：** `fpga-iopv-per-market-cross-synth-20260916-1854`  
**仓：** Research_everything  
**抓取：** Asia/Shanghai 2026-09-16 18:54（收紧修订：2026-09-16）

**标注：** **事实** / **推断** / **待核实** · 抓取：✅ 可读 · ⚠️ 摘要 · ❌ 不可达

---

## 主出处（≥10）

| ID | URL | 抓取 | 标注 | 支撑点 | 证据 |
|----|-----|------|------|--------|------|
| S1 | [Exegy US20090182683](https://www.freepatentsonline.com/y2009/0182683.html) | ✅ | 事实 | Claim 6–7 Δ NAV；Claim 11 bid/ask/last；Claim 20 双表；Claim 21–22 改表；Claim 24–28 gate；Claim 34 FPGA | [S1](evidence/S1-exegy-patent-delta-nav.txt) |
| S2 | [DolphinDB streaming IOPV](https://docs.dolphindb.com/en/Tutorials/streaming_IOPV.html) | ✅ | 事实 | `ffill`；`deltas(Price*Position)`+`cumsum`；`perRow`；~75% 无价变 | [S2](evidence/S2-dolphindb-incremental-iopv.md) |
| S3 | [中证网 IOPV 说明](https://www.cs.com.cn/xwzx/hg/202502/t20250207_6472791.html) | ✅ | 事实 | 沪深公式；last；15s；三类替代；**并非每只 ETF 都发 IOPV** | [S3](evidence/S3-cs-cn-sse-iopv-formula.md) |
| S4 | [SZSE IOPV 清单规范 PDF](http://docs.static.szse.cn/www/marketServices/technicalservice/notice/W020190408723859697048.pdf) | ⚠️ | 事实 | IOPV 清单字段；qty 可与 PCF 不同 | — |
| S7 | [国泰基金 IOPV 汇率公告 PDF](https://pdf.dfcfw.com/pdf/H2_AN202508281736028245_1.pdf) | ⚠️ | 事实 | 港股通估值汇率×成交价 | — |
| S8 | [JPX iNAV/PCF](https://www.jpx.co.jp/english/equities/products/etfs/inav/index.html) | ✅ | 事实 | iNAV **15s**；PCF 定义 | — |
| S9 | [Deutsche Börse iNAV Guide v2.5 PDF](https://www.dax-indices.com/document/Resources/Guides/iNAV_2_4_e.pdf) | ✅ | 事实 | `iNAV=(Cash+Σ p·fx·q·c)/N`；4dp；跨时区 proxy；方法切换可跳变 | [S4-db](evidence/S4-deutsche-boerse-inav-formula.md) |
| S10 | [Fidelity ETF iNAV](https://www.fidelity.com/learning-center/investment-products/etf/etfs-inav) | ✅ | 事实 | last price；15s；跨时区 **stale** last | [S5](evidence/S5-fidelity-stale-cross-timezone.md) |
| S11 | [SEC Form 497 IOPV 披露](https://www.sec.gov/Archives/edgar/data/1100663/000119312515383347/d38988d497.htm) | ✅ | **事实（证伪/边界）** | IOPV≠NAV；清单≠持仓；15s；cash/FX 组件 | [S11](evidence/S11-sec-iopv-boundary-falsify.md) |
| S12 | [Solactive iNAV](https://www.solactive.com/inav-calculation/) | ✅ | 事实 | PCF+实时价+cash+FX；pricing waterfall | — |
| S15 | [Xilinx Vitis Quant Finance](https://xilinx.github.io/Vitis_Libraries/quantitative_finance/2020.2/index.html) | ✅ | 推断 | 定点算子库；**无 IOPV 模块** | — |

## 次要出处

| ID | URL | 抓取 | 标注 | 用途 |
|----|-----|------|------|------|
| S5 | [SSE IOPV 上传 PDF](https://www.sse.com.cn/services/tradingtech/development/c/10789096/files/8faa414a4f94458e96bc96dcf5e109dd.pdf) | ⚠️ | 事实 | price N13(5) |
| S6 | [建信基金 IOPV 公式 PDF](https://www.sse.com.cn/disclosure/fund/announcement/c/new/2026-02-09/588910_20260209_S3LC.pdf) | ⚠️ | 事实 | 4dp 公式 |
| S13 | [ICE IOPV T&C PDF](https://www.ice.com/publicdocs/IDI_-_Terms_and_Conditions_for_ETF_IOPV_Calculation_Services.pdf) | ⚠️ | 事实 | Fund Basket 来源 |
| S14 | [Franklin Templeton FV 2026](https://www.franklintempleton.com/articles/2026/etf/when-markets-are-closed-what-is-your-international-etf-really-worth) | ⚠️ | 事实 | 闭市 FV vs observable |
| S16 | [arXiv 2212.13977 FPGA streaming](https://arxiv.org/html/2212.13977v1) | ✅ | 事实 | 领域背景；**无 ns 数字** |

---

## 证伪 / 边界源（必填 ≥1）

| ID | 可证伪论断 | 边界内容 | 报告处理 |
|----|-----------|----------|----------|
| **S11** | 「FPGA IOPV = 基金实时 NAV」 | IOPV **should not be viewed as** real-time NAV | 输出标 reference；不对齐日终 NAV |
| **S11** | 「清单即持仓」 | portfolio **may include** non-Deposit securities | quality 字段；不 silent 假精度 |
| **S3** | 「所有 ETF 必须硬件算 IOPV」 | **并非每只** ETF 提供实时 IOPV | 产品确认后再部署 |
| **S9** | 「跨时区 iNAV 连续可微」 | 方法切换时 **may jump slightly** | `FX_METHOD_SWITCH` |

---

## 交叉核对

| 论断 | 主源 | 交叉 | 结论 |
|------|------|------|------|
| Δ 路径 | S1 Claim 6–7 | S2 §5.3 | 事实+推断 → B0 |
| last 默认 | S3 | S10 | 事实 |
| 未齐仍输出 | S10 | S2 ffill | 事实 |
| FX@ synth | S9 fxt | S7 | 事实 |
| 15s 对外 | S3,S11 | S8 | 事实 |
| partial/合成切分 | S9 结构 | S3 现金项归属 | 推断 |

---

## 待核实（无出处已删/不入表）

| 项 | 原因 |
|----|------|
| leg≤4、CDC 分界、pause 拍数 | 无公开来源 |
| M/B 上限、64b 确切 scale | 无 RTL 实测 |
| FX 刷新 Hz | 产品相关 |

**禁止：** 未核实 **ns**（S1/S16 均无绝对延迟声称）。
