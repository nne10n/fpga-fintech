# FPGA tick-to-trade 口径 — Harness 试跑一页纸

- 生成时间: 2026-09-12 00:31:03 CST
- 工具: npx @deepseek-ai/dsh --profile headless
- 对接: FPGA业务团队组长 / Mac mini

---

已写入 `/Users/laoxue/workbench/tick-to-trade_vs_STAC-T0.md`，全文如下（一页纸）：

---

# tick-to-trade 与 STAC-T0 actionable / I-O latency 口径区别（业务对齐用）

## 1. 背景
- "tick-to-trade" 是行业泛称：泛指从行情事件到报单发出的端到端时间；不同厂商起止点常不一致。
- STAC-T0 是 STAC 基准理事会定义的**交易网络 I/O 基准**，只测平台收发链路的固有延迟【STAC】。
- STAC-T0 明确**不含交易逻辑、不含市场专用协议处理**：被测栈只做 UDP 入、TCP 出与一个简单比较【STAC】。
- 因此 **STAC-T0 的 actionable latency ≠ 完整策略 tick-to-trade**；把两者等同是常见误导。
- 本文只对齐口径，用于选型/对标沟通，不涉及实现架构。

## 2. 两个指标对照

| 指标 | 定义 | 含不含策略/协议 | 常见陷阱 |
|---|---|---|---|
| **tick-to-trade**（端到端泛称） | 从行情 tick 到达至对应报单发出；行业常用"入包最后一位 EOF → 出包最后一位 EOF"【论】 | 概念上含解码、策略/风控、编码、egress；但基准测量**通常不含任何策略或模型逻辑**【论】 | 未说明起止点（首/末 bit）、包长、协议、是否含策略；常与 wire-to-wire、tick-to-order、socket-to-socket 混用 |
| **STAC-T0.ACTIONABLE.LAT**（I-O 可控口径） | `tFO − tIND`：从"做决定所需的最后一位"（index 末位 tIND）到出包**第一位** tFO【STAC】 | **不含**交易逻辑、**不含**市场协议解析；SUT 仅读取 index 并按 `index mod 1024` 决定是否回 118 字节 TCP 帧【STAC】 | 把 ACTIONABLE 当完整策略延迟；与 FILO/LIFO/FIFO 混报；抓包设备时间戳所取的 bit 位置不同，tIND 等为理论推算值【STAC】 |
| **STAC-T0.FILO.LAT**（端到端口径） | `tLO − tFI`：首 bit 入 → 末 bit 出，与 STAC-T1 端到端口径一致【STAC】 | 同样不含策略/协议；但**含序列化延迟**（ACTIONABLE 不含）【STAC】 | 厂商只报 ACTIONABLE 的漂亮值，隐去更接近端到端的 FILO |
| **STAC-T1**（真正含协议处理的 tick-to-trade） | 回放真实行情 + 真实交易所协议下单，含行情解码与报单生成、"基本是除策略算法以外的全部"【STAC】 | 含市场协议与产品逻辑（ACK/成交），**仍不含交易算法** | 误以为 T1 也含策略；或拿 T0 的 I-O 数字去对标 T1 |

> 一句话：**T0 = 平台 I/O 下限；T0.FILO ≈ 端到端链路；T1 = 除策略外全流程；完整 tick-to-trade = 还要加上策略与风控。**

## 3. 业务怎么用（选型/对标时怎么读厂商数字）
1. **先锁三要素再比数**：起止点（首 bit/末 bit）、包长与协议、是否含策略与风控。三者不同则数字不可比。
2. **区分 ACTIONABLE 与 FILO**：ACTIONABLE（tFO−tIND）通常更小、更"好看"，是平台可控部分；要和端到端数字比较时必须换 FILO。
3. **T0 数字只当平台能力参考**：STAC-T0 不含策略，**不能**用它承诺业务端到端 SLA；策略/风控/编解码需另立预算【论】。
4. **对标要同条件**：同一 STAC-T0 版本、同一 message structure(A/B)、同一速率档（低/中/高）、同一 metric，并要求 min/mean/分位与丢包情况【STAC】。
5. **商务/验收拆两张账**：网络 I/O 延迟（可对标 STAC-T0）与策略+风控处理时间（需自测）分开列，避免口径错配。

## 4. 出处
- **STAC-T0 Overview**，2020-11-05，https://stacresearch.com/system/files/central/STAC-T0%20backgrounder.pdf 【STAC】
- **STAC Report: New LDA/Xilinx solution under STAC-T0 (tick-to-trade network I/O)**，2020，https://docs.stacresearch.com/news/XLX200514 【STAC】——文中厂商选择highlight：68 字节帧 actionable 最小 24.2 ns、均值 27.9–29.2 ns【厂】
- **Databento Microstructure Guide — "Latency, tick-to-trade"**（访问 2026），https://databento.com/microstructure/tick-to-trade 【二手】
- **A-Team Insight — "Exegy and AMD Achieve Record-Breaking Tick-to-Trade Latency in STAC-T0 Benchmark"**，2024，https://a-teaminsight.com/blog/exegy-and-amd-achieve-record-breaking-tick-to-trade-latency-in-stac-t0-benchmark/ 【二手】
- **Magmio — "Tick-to-Trade Latency in High-Frequency Trading"**，2026，https://www.magmio.com/news/225-tick-to-trade 【二手】

---

口径要点：STAC-T0 是**网络 I/O 黑盒基准**（UDP 入/TCP 出、无策略无协议），其 `ACTIONABLE = tFO − tIND` 是以"决策所需最后一位"为起点的平台可控延迟；`FILO = tLO − tFI` 才接近端到端；含协议不含策略的是 STAC-T1；完整 tick-to-trade 还要叠加策略与风控。
