# 抓取留证：FPL17 — mask table 与 qty 分表

**抓取时间：** 2026-09-16  
**URL：** https://www.doc.ic.ac.uk/~wl/papers/17/fpl17ch.pdf  
**HTTP：** 200（PDF 文本提取）  
**标注：** **事实**

---

## 原文摘录（Figure 4 说明）

> A **mask table** is used to identify the price with nonzero quantities. Performing the logical AND operation to each element in the mask table and the address table generates the **mask & addr** table, which is the input of the parallel reduction algorithm.

> The tree reduction algorithm parallelizes in space. The pipeline depth of reducing an array of n elements is **log(n)**.

---

## 地址映射（Equation 1，事实）

```
Ap = Ald + (p - pld) / pt
```

- `pld`：limit down price；`pt`：price tick；`Ald`：limit down 对应地址。
- **推断：** 与本报告 SOA `payload_addr(i)=P_base+i×stride` **同构**（固定 tick 线性 index）。

---

## 路径 α/β 分离启示

| FPL17 元素 | 路径 | DDR? |
|------------|------|------|
| mask table（valid/nonzero） | **α** | 片上 BRAM **事实** |
| total qty 表 | payload | 片上 **事实** |
| tree reduction on (mask&addr) | **α 输出** → BBO | 无 AXI |

**Out 边界：** FPL17 论文给出 **132–288 ns** 等绝对延迟（Table/Abstract）——本报告 **不引用** 为 AXI/DDR 吞吐证据（业务与载体不同）。

---

## 与 bitmap×DDR 主题关系

- FPL17 **未使用 DDR bitmap**；valid 在片上 mask → 支持「**α 默认片上**」铁律。
- 若 qty 表扩展到 DDR（类 0838 类 E），mask 仍应 **片上或 summary**，β 仅读 **置位 index** 的 payload 行。
