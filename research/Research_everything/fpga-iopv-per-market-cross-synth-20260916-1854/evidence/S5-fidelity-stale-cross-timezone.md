# S5 — Fidelity iNAV 跨时区 stale 与 Fair Value 摘录

来源：https://www.fidelity.com/learning-center/investment-products/etf/etfs-inav
抓取：2026-09-16 18:54 · ✅ 全文可读

---

## iNAV 计算（事实）

> multiply the **last available price** of each security in the calculation basket by the number of shares … summed, cash added, liabilities subtracted … divide by creation unit shares.

## 披露频率

> calculated by the listing exchange … disseminated to the public **every 15 seconds**.

## 跨时区 stale（Limitation #1）

> when an ETF trades in a **different time zone** than its underlying securities … the "last price" … will be based on the **previous day's close** (until the market opens again). As a result, the "last price" … is essentially **"stale"**.

→ 与本报告：**未齐仍输出 IOPV** + `stale_leg_mask` + `quality=DEGRADED`。

## Fair Value 扩展（非交易所默认 IOPV）

> Liquidity providers will use a **proxy** … e.g. FTSE 100 **futures** while LSE closed.

→ 对应换方案：**Host px_override / proxy 表项**；硬件 **不内置 FV 模型**。

## 15s 延迟（Limitation #2）

> disseminated "only" every 15 seconds. In particularly volatile markets, this lag may misrepresent the actual value.

→ 片内可逐笔维护 nav；对外 gate 15s 或 |ΔIOPV| 阈值（S1 专利 trigger 对齐）。

---

## 对本报告机制四问 #2 的交叉核对

| 问题 | Fidelity 事实 | 本报告默认 |
|------|---------------|------------|
| 全市场未齐是否输出？ | **仍发布 iNAV**（用 stale last） | **输出** + degraded |
| 是否 withhold？ | 文档未要求 withhold | 除非产品显式 gate |
