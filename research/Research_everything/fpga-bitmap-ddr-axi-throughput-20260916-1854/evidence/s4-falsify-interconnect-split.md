# 证伪/边界留证：不可依赖互联替 Master 跨 4KB 拆分

**用途：** 支撑「run-merge 须在 Master 切段」及「禁止假设 SmartConnect 修复违规 burst」  
**标注：** **证伪/边界**（S4）

---

## 来源

- **URL：** https://adaptivesupport.amd.com/s/question/0D54U00008wQR3rSAG/about-axi-burst-length-and-burst-size
- **抓取：** 2026-09-16，200

## 原文摘录

> If your IP generates any request that crosses a 4K boundary it is not AXI compliant. That would be a bug in your IP. **The master shouldn't make the request.**

> The expectation is that the master will respect that requirement. Some implementation of the smart connect may happen to accept such a large transfer but **it could stop working at any update** and it would not be a bug.

## 对本主题的边界结论

| 断言 | 判定 |
|------|------|
| run-merge 可写 `ARLEN` 跨 4KB 交给互联拆 | **证伪** — Master 必须自切段（配合 S3 公式） |
| 违规 burst「碰巧能跑」= 可写进默认方案 | **证伪** — 仅算侥幸，非设计依据 |
| β payload merge 与 α bitmap 无关 | **事实** — 切段责任在 β AXI Master |

## 交叉核对

- S2 VIP Fatal、S14 断言名 — 同向 **事实**
- ZipCPU S3 — Master 侧 `next_axlen` 限幅 **事实**
