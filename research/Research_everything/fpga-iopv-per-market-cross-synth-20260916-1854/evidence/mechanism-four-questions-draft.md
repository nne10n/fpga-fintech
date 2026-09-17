# 机制四问 — 对比草稿（入 report §5 前）

Asia/Shanghai 2026-09-16 18:54 · 收紧修订 · 每格绑出处 · 无出处标待核实

**证伪源：** S11（IOPV≠NAV）· S3（非所有 ETF 发 IOPV）· S9（跨时区方法切换可跳变）

---

## 四问 × 三源独立验证

| 机制问题 | Exegy S1 | DolphinDB S2 | 沪深 S3 + DB iNAV S4 + Fidelity S5 | B0 默认答 |
|----------|----------|--------------|-------------------------------------|-----------|
| **新 tick→partial** | Δ contribution + prev NAV | deltas(Price×Pos) + cumsum | last 价 × qty 增量 | `partial[leg]+=qty×Δpx`；valid=0/auction/halt **freeze** |
| **未齐是否输出** | （未明示 withhold） | ffill 仍算 IOPV | 15s 仍发布；stale last 仍计 | **输出** + quality/coverage |
| **权重热更双缓冲** | client 改表 Claim 21–22 | （教程静态 portfolio） | PCF **日更** S4 | shadow swap + 重播种（推断）；pause **待核实** |
| **FX 跳变整幅重算** | （NAV 层，未拆 FX） | （单币种教程） | fx 显式因子 fxt S9 | **否**；synth only（推断） |

---

## partial ↔ 合成 切分验证

```
✅ partial[L] = Σ(qty×px) + cash_substitute_local[L]   // 可加，本 leg 货币
✅ synth = Σ(partial[L]×FX[L→report]) + global_cash    // 只汇合，禁止 qty×px lookup
❌ 合成阶段回头扫成分表 — 违反可加性，FX 跳变变 O(M)
```

---

## 与旧稿 0842 差异（本版加深）

| 项 | 0842 | 1854 加深 |
|----|------|-----------|
| 证据 | sources 无 fetch 状态 | evidence/ 5 文件 + sources 抓取状态 |
| 跨时区 | 引用 Fidelity | + DB iNAV §2.2.3–4 proxy 时段切换 |
| SEC 披露 | 列表引用 | S11 摘录 IOPV≠NAV、15s、FX cash component |
| Solactive | 列表引用 | S12 pricing waterfall → stale 降级链 |
| 四问 | 表格式 | 三源交叉草稿 + 显式禁止合成回头算 |
