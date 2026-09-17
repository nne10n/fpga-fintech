# 抓取留证：AXI4 burst 不得跨 4KB 边界

**抓取时间：** 2026-09-16（Asia/Shanghai）  
**用途：** 支撑 report §3.2 Q2/Q3、§5.5、§7.2 run-merge 切段规则  
**标注：** **事实**

---

## S1 — ARM AMBA AXI4（IHI 0022）

- **URL：** https://developer.arm.com/documentation/ihi0022/latest/
- **抓取状态：** 页面需登录/JS 渲染；规范条文以二次来源交叉核对。
- **支撑点：** Section A3.4.1 — *"A burst must not cross a 4KB address boundary."*

---

## S2 — AMD AXI VIP 仿真 Fatal（社区文章 1062002）

- **URL：** https://adaptivesupport.amd.com/s/article/1062002
- **摘录：**
  ```
  Fatal: AXI4_ERRM_AWADDR_BOUNDARY: A burst must not cross a 4kbyte boundary. Spec: section A3.4.1.
  ```
- **含义：** VIP 对违规 burst 直接 Fatal；run-merge 必须在 4KB 处切段。

---

## S3 — ZipCPU bursting AXI Master（2020-06-16）

- **URL：** https://zipcpu.com/blog/2020/06/16/axiaddr-limits.html
- **摘录：**
  > It's illegal in AXI to cross 4kB boundaries.  
  > `AxADDR[11:ADDRLSB] + (AxLEN +1) < 4kB`
- **RTL 含义：** run-merge 检测器输出 `L_eff = min(L_run, L_to_4K_boundary)`。

---

## S4 — AMD 社区问答（SmartConnect 不替 Master 合规）

- **URL：** https://adaptivesupport.amd.com/s/question/0D54U00008wQR3rSAG/about-axi-burst-length-and-burst-size
- **摘录（Member necare81）：**
  > If your IP generates any request that crosses a 4K boundary it is not AXI compliant. That would be a bug in your IP. The master shouldn't make the request.
- **推断：** 不可依赖互联自动拆分；bitmap→payload merge 逻辑须在 Master 侧切段。

---

## 对本主题的映射

| 场景 | 规则 |
|------|------|
| SOA `stride=32B`，run 从 `i=100` 起 L=6 | 若 `0x1000+100×32+6×32` 跨页 → 拆为两条 AR |
| 256b 宽 beat=32B | 单 burst 最多 `4096/32=128` beat（理想对齐） |
| 低 ρ 单 index AR | 通常 len=0，4KB 约束自动满足 |

**未给出：** 任何 ns/GB/s 绝对值。
