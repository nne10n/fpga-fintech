# S2 — DolphinDB 流式 IOPV 教程摘录：ffill + 增量 cumsum

**开源仓/文档：** https://github.com/dolphindb/DolphinDB （教程非独立 repo 文件）  
**文档路径：** `docs.dolphindb.com/en/Tutorials/streaming_IOPV.html`  
**关键 API：** `createCrossSectionalEngine`, `createReactiveStateEngine`, `ffill`, `deltas`, `cumsum`, `replayDS`, `replay`  
抓取：2026-09-16 18:54 · ✅ 全文可读

---

## IOPV 公式（教程简化版）

> multiply the **last available price** of each security … by the number of shares … summed, cash components added, liabilities subtracted … divide by creation unit shares.

## 历史批算：ffill + rowSum

```text
iopvHist = select rowSum(ffill(constituentValue)) as IOPV
           from timeSeriesValue pivot by tradetime, SecurityID
```

- **ffill**：前向填充 null — 对应硬件 **last valid / stale ffill**。
- **pivot + rowSum**：全量截面求和 — 对应「非增量」直路（Section 4）。

## 实时最优路径（Section 5）

1. **过滤无价变 tick**：`filter=<deltas(Price) != 0>` — 约 75% tick 可跳过。
2. **加权价增量**：`deltas(Price*Position)` — 对应 `qty×(px_new−px_old)`。
3. **增量累加**：`cumsum(deltaValue)` — 对应 `Last Total + deltas`。

> Use `Last Total Market Value + deltas` to calculate the latest total market value, which takes **less time** than summing up all constituents' weighted prices.

## perRow 触发

> `triggeringPattern='perRow'` — triggers calculation upon the arrival of a new trade record.

---

## 对本报告的支撑点

- **[事实]** 软件侧独立验证：增量 Δ 优于全量 Σ（与 Exegy S1 交叉）。
- **[事实]** ffill 为 IOPV 缺价处理的标准软件实践。
- **[推断]** DolphinDB 为单进程/单域；跨市场 leg 需本报告 **partial→synth 分层** 扩展（非教程原生概念）。
