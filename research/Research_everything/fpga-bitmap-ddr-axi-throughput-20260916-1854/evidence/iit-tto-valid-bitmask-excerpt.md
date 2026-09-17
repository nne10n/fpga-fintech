# 抓取留证：IIT TTO 2024 — URAM orderBook + valid-bitmask

**抓取时间：** 2026-09-16  
**URL：** https://rndshowcase.iiit.ac.in/tto2024/TTO_website_data/PDF/25.pdf  
**HTTP：** 200（PDF 文本可提取）  
**标注：** **事实**（片上 bitmap 语义）；AXI/DDR 细节 **未展开 → 推断边界**

---

## 原文摘录（摘要页）

> Unlike traditional methods, we use a **bitmask array to maintain valid price information**; which is used by our **hybrid binary-linear search** to efficiently update the topCache, in case a price gets cleared out in the topCache

> The primary orderBook is stored in the **URAM**, and a distinct data structure topCache to store market depth information.

> In our approach, we employ the **HBM to store this data** [past order information].

---

## 与本调研路径 α/β 的对照

| IIT 设计元素 | 路径 | 本报告映射 |
|--------------|------|------------|
| bitmask array（valid price） | **α** | 片上 authoritative bitmap；**非 DDR 裸扫** |
| hybrid binary-linear search | **α** | 类似 summary + word scan；低 ρ 可类比 |
| URAM orderBook（qty） | 片上 payload | 非本主题「DDR payload」主路径 |
| HBM 历史订单 | 片外深存 | **β 类 DRAM/HBM**；热路径应避免随机读 **推断** |

---

## 论文披露 timing（事实，但非本报告带宽口径）

| 子系统 | 频率 | Cycles | Latency |
|--------|------|--------|---------|
| OrderBook Subsystem | 300 MHz | 105 | 350 ns |

**声明：** 上表为 **IIT 论文自报**，与本报告「bitmap×DDR AXI 吞吐」**不可直接换算**；本目录 **禁止** 将其当作 MIG/AXI merge 的 GB/s 证据。

---

## 交叉核对

- 与 [0838 类 D](../fpga-hw-orderbook-price-level-20260916-0838/report.md) valid-bitmask **一致**。
- 与 FPL17 mask table（S9）**概念同构**：valid 与 qty **分表**。
