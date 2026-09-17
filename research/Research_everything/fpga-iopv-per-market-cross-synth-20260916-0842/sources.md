# 出处清单

**Asia/Shanghai 2026-09-16 08:42** · 修订：口径收紧版 · 标注：**[事实]** 可核对公开文档；**[推断]** 由事实推导的工程结论；**[待核实]** 缺用户/实测参数

| # | 来源 | 用途 | 标注 |
|---|------|------|------|
| 1 | [Exegy US20090182683 — Low Latency Basket Calculation](https://www.freepatentsonline.com/y2009/0182683.html) | FPGA 流水线 basket lookup + Δ NAV；symbol 两表索引；多 basket 扇出；bid/ask/last NAV | **[事实]** 专利 Claims 1–21, 39–45, 61–68, 96 |
| 2 | [DolphinDB — Calculating ETF IOPV](https://docs.dolphindb.com/en/Tutorials/streaming_IOPV.html) | 事件驱动 IOPV；ffill；增量 `Last Total + deltas`；perRow 触发 | **[事实]** 教程描述 |
| 3 | [中证网 — ETF IOPV 公式与说明](https://www.cs.com.cn/xwzx/hg/202502/t20250207_6472791.html) | 沪深 IOPV 公式；15s 更新；现金替代三类 | **[事实]** 转引交易所口径 |
| 4 | [SZSE — 基金公司数据接口规范（IOPV 清单）](http://docs.static.szse.cn/www/marketServices/technicalservice/notice/W020190408723859697048.pdf) | IOPV 清单字段；qty 可与 PCF 不同；必须现金替代不进成分段；跨境由第三方算 | **[事实]** PDF §4.2.4 |
| 5 | [SSE — IOPV 上传接口开发文档](https://www.sse.com.cn/services/tradingtech/development/c/10789096/files/8faa414a4f94458e96bc96dcf5e109dd.pdf) | 指数机构上传 IOPV；price N13(5)；100 条/请求 | **[事实]** |
| 6 | [建信基金 SSE 公告 — IOPV 公式修订](https://www.sse.com.cn/disclosure/fund/announcement/c/new/2026-02-09/588910_20260209_S3LC.pdf) | 官方 IOPV 公式与 4 位小数 | **[事实]** |
| 7 | [国泰基金 — IOPV 汇率换算公告](https://pdf.dfcfw.com/pdf/H2_AN202508281736028245_1.pdf) | 港股通 ETF 估值汇率；公式含汇率×成交价 | **[事实]** |
| 8 | [JPX — Indicative NAV / PCF](https://www.jpx.co.jp/english/equities/products/etfs/inav/index.html) | iNAV 15s；PCF 定义；投资者可自行计算 | **[事实]** |
| 9 | [Deutsche Börse — Guide to iNAV Calculation v2.4](https://www.dax-indices.com/document/Resources/Guides/iNAV_2_4_e.pdf) | iNAV 公式含 cash、FX、adjustment；15–60s 频率 | **[事实]** |
| 10 | [Fidelity — ETF iNAV](https://www.fidelity.com/learning-center/investment-products/etf/etfs-inav) | calculation basket；last price；跨时区 stale | **[事实]** |
| 11 | [SEC Form 497 — IOPV 局限性披露](https://www.sec.gov/Archives/edgar/data/1100663/000119312515383347/d38988d497.htm) | IOPV≠实时 NAV；外国成分价可能不更新 | **[事实]** |
| 12 | [Solactive — iNAV/IOPV Calculation](https://www.solactive.com/inav-calculation/) | PCF + 实时价 + cash + FX + corporate actions | **[事实]** |
| 13 | [ICE — ETF IOPV Calculation Services T&C](https://www.ice.com/publicdocs/IDI_-_Terms_and_Conditions_for_ETF_IOPV_Calculation_Services.pdf) | Fund Basket 来自 NSCC/客户文件 | **[事实]** |
| 14 | [Franklin Templeton — International ETF Fair Value (2026)](https://www.franklintempleton.com/articles/2026/etf/when-markets-are-closed-what-is-your-international-etf-really-worth) | 闭市时段 FV vs observable price 分歧 | **[事实]** 方法论 |
| 15 | [Xilinx Vitis Quantitative Finance Library](https://xilinx.github.io/Vitis_Libraries/quantitative_finance/2020.2/index.html) | FPGA 金融定价内核分层（L2/L3） | **[推断]** 定点/流水参考 |
| 16 | [arXiv 2212.13977 — FPGA HFT / streaming](https://arxiv.org/html/2212.13977v1) | FPGA 低延迟数据处理在 HFT 的应用背景 | **[事实]** 领域背景 |

## 抓取备注

- Exegy 专利（#1）为 basket/NAV 增量硬件化 **最直接** 公开来源；未声称具体 ns 延迟。
- 沪深公式（#3–#7）与 SZSE 清单（#4）对 **现金替代字段拆分** 的硬件表项设计 **具约束力**（若产品要对齐交易所 IOPV）。
- DolphinDB（#2）与 Exegy（#1）**独立同构** 支持「增量 Δ 而非全量 Σ」作为默认热路径 — 本报告 **默认推荐** 属 **[推断]**，但有两源交叉。
- 本报告 **cycle 数、BRAM 容量、M/B 上限** 均为 **[推断]**，无本仓库 RTL 实测。
- 用户未指定目标 ETF：**市场集合、B、是否 QDII** 标 **[待核实]**。
