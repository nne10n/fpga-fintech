# S11 — SEC Form 497：IOPV 边界与可证伪点

来源：https://www.sec.gov/Archives/edgar/data/1100663/000119312515383347/d38988d497.htm
抓取：2026-09-16 · ✅ 全文可读

---

## 证伪/边界摘录（原文意）

1. **IOPV ≠ 实时 NAV**
   > the Fund's IOPV … **should not be viewed as a real-time update of the Fund's NAV**, which is calculated only once a day.

2. **清单 ≠ 持仓**
   > the current portfolio … **may include securities that are not a part of the current Deposit Securities**.

3. **披露频率上限**
   > disseminates information **every 15 seconds** … an updated IOPV.

4. **cash/FX 组件**
   > The cash component … estimated accrued interest, dividends … If applicable, each IOPV also reflects **changes in currency exchange rates**.

5. **外国成分价可能陈旧**（同文件其他段落与 S10 交叉）
   > foreign … prices may not be updated during … trading hours.

---

## 对本报告的可证伪约束

| 若硬件声称 | S11 反驳 | 报告处理 |
|------------|----------|----------|
| IOPV = 基金实时 NAV | **不成立** | 输出标 `reference_iopv`，不对齐日终 NAV |
| 合成可省略 cash/FX 项 | cash/FX 为 IOPV 组成部分 | `global_estimated_cash` + synth×FX 必填 |
| 片内逐笔必须对外逐笔发 | 官方披露 **15s** | 计算与 dissemination **解耦**（S1 Claim 24–28） |
| stale 外国 leg 可 silent 当 live | 价可能不更新 | **必须** `quality`/`stale_leg_mask` |

**标注：** 以上边界为 **[事实]**；硬件字段名为 **[推断]**。
