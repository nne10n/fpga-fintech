# E01 — 字段/索引摘录（绑 URL+章节）

## S1 Columbia §3.1.3 + Table 2

**URL：** http://www.cs.columbia.edu/~sedwards/classes/2026/4840-spring/designs/Market-Data-Parser.pdf

```
index = (symbol_id << 11) | price_offset[10:0]
price_offset = floor((price - base[symbol_id]) / 100)
```

Table 2: agg_qty 32b | order_count 16b | valid 1b | reserved 15b → **64b/槽**

Top-of-Book（bid）三规则 — §3.1.3 Top-of-Book Tracking：
1. px > BEST_BID → 替换 best
2. px == BEST_BID 且 valid=1 → 刷新 qty
3. px == BEST_BID 且 valid→0 → 从 best_off **向下扫** valid

越界：窗外 → STATUS sticky + ERR COUNT++，drop；stretch = sparse hash 或 rebase。

## S2 FPL17 §III + Algorithm 2

**URL：** https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf

Eq.1: `Ap = Ald + (p - pld) / pt`

Fig.4: mask[i]=(qty>0); reduction on (mask & addr)

Algorithm 2 L20 (HWCancel): qty→0 时 `cache.at(price) = cache[5].next`

## S3 fpga-feed-handler（已读文件路径）

**URL：** https://github.com/alchevrier/fpga-feed-handler

| 文件 | 摘录 |
|------|------|
| `docs/adr/ADR-005-mathematical-index-deterministic-addressing.md` | `idx = ((price-base_price)*inv_tick)>>16`; side 为地址 MSB |
| `docs/adr/ADR-004-order-book-bram-aos.md` | `struct Level { price, qty }` 单址读写 |
| `docs/adr/ADR-012-hot-path-register-store-buffer.md` | 8 槽/侧 Register；miss 驱逐→BRAM write-only |
| `docs/adr/ADR-016-early-exit-event-filter.md` | filt_base≤p<filt_max 防 overflow |

## S14 证伪边界

**URL：** https://github.com/mmzarif/fpga-order-book  
**路径：** `README.md` Features

> Supports … **Sorted bid/ask arrays** (descending/ascending) … Tracks best bid/ask

→ 非 S1 式 per-price 聚合槽；作 **⊘ 反例** 写入 E02/report §9。
