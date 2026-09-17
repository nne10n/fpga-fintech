# 抓取留证：Linux `find_next_bit` — word-at-a-time 扫描

**抓取时间：** 2026-09-16  
**URL：** https://raw.githubusercontent.com/torvalds/linux/master/lib/find_bit.c  
**HTTP：** 200  
**标注：** **事实**（软件对照）；FPGA 实现为 **推断**

---

## 核心宏 `FIND_NEXT_BIT`（节选）

```c
#define FIND_NEXT_BIT(FETCH, MUNGE, size, start) \
({ \
 unsigned long mask, idx, tmp, sz = (size), __start = (start); \
 if (unlikely(__start >= sz)) \
  goto out; \
 mask = MUNGE(BITMAP_FIRST_WORD_MASK(__start)); \
 idx = __start / BITS_PER_LONG; \
 for (tmp = (FETCH) & mask; !tmp; tmp = (FETCH)) { \
  if ((idx + 1) * BITS_PER_LONG >= sz) \
   goto out; \
  idx++; \
 } \
 sz = min(idx * BITS_PER_LONG + __ffs(MUNGE(tmp)), sz); \
out: \
 sz; \
})
```

---

## 机制要点（→ 路径 α RTL 对照）

| Linux 行为 | FPGA 路径 α 映射 |
|------------|------------------|
| `BITMAP_FIRST_WORD_MASK(start)` 屏蔽已扫位 | 游标 `cur` 对应 word 内 bit mask |
| word=0 则 `idx++` 跳整 word | **零 word 跳过**；低 ρ 可加 64/256 summary |
| `__ffs` 找最低置位 | LUT/CLB **ctz** 或 priority encoder |
| 64-bit `BITS_PER_LONG` | 本报告默认 `W_word=64` **假设** |

---

## 禁止误读

- 内核实现假设 **CPU 本地 RAM 延迟**；**不得** 据此推断 BRAM 扫描 ns 或 DDR bitmap 读延迟。
- Linux 无 AXI burst；**不得** 将 find_next_bit 直接映射为「DDR INCR 扫描 bitmap」——本报告 **禁止** 该默认。

---

## 交叉核对

- 与 IIT hybrid search（S5）**互补**：软件 word-hop vs 硬件 binary-linear 块跳。
- 与 0848 report §5.2 **一致**；1854 强化「片上默认、DDR 仅 audit burst」铁律。
