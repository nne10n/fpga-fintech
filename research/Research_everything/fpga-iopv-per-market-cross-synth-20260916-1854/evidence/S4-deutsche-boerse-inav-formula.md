# S4 — Deutsche Börse / STOXX iNAV Guide v2.5 摘录

来源：https://www.dax-indices.com/document/Resources/Guides/iNAV_2_4_e.pdf（站内显示 Version 2.5, March 2022）
抓取：2026-09-16 18:54 · ✅ PDF 可读

---

## Portfolio-based iNAV 公式

```
iNAV_t = ( Cash + Σ ( p_it × fx_t × q_it × c_it ) ) / N_t
```

| 符号 | 含义 |
|------|------|
| p_it | 成分 i 本地货币价格 |
| fx_t | **iNAV 货币转换因子** |
| q_it | 成分数量 |
| c_it | **adjustment factor**（公司行动等） |
| Cash | 基金现金头寸 |

## 跨时区特殊方法（§2.2.3–2.2.4）

- 闭市时段可用 **指数/期货/代理 instrument** 替代 observable price。
- 方法切换时刻 iNAV **可能小幅跳变**（valuation method 差异 + FX）。
- 多 proxy **可按时段串联**。

## 精度与 FX

- iNAV **四舍五入 4 位小数**发布。
- 多币种：Euro 主算后 × Refinitiv **realtime f/x mid-rate**（bid+ask 平均）；或 WM fixing。

## 计算频率

> typical calculation intervals range from **every 15 seconds to every 60 seconds**.

---

## 对本报告的支撑点

- **[事实]** FX 与 price 在公式中 **显式分离** — 支持本报告「FX 只在 synth 乘、partial 保持本 leg 货币」。
- **[事实]** adjustment factor **Host 日更入表**，不在 tick 路径重算 — 对齐 §6.1 双缓冲。
- **[事实]** 跨时区 stale + proxy 为 **官方计算商实践** — 硬件默认 ffill+stale；FV/proxy 需 **Host px_override**（Franklin S14 交叉）。
- **[推断]** 方法切换跳变 → synth 输出应带 **`quality`/`fx_version`** 标记。
