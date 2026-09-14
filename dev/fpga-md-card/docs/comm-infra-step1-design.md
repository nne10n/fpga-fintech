# 通信基建-第一步 · 设计总稿

日期：2026-09-09  
状态：**G1 FROZEN**（组长宣布）— S2 优先交付；S1 约束同步冻结，实现顺序后置  
G0：成文边界单 v2 `docs/boundary/通信基建-边界单.md` @ **melon5253/fpga-comm-infra**（commit `3fb73e3dddd1795e59093954cf371197a8413eba`）  
产物仓：https://cursor.com/codebase/melon5253/fpga-comm-infra
仓内副本：`design/comm-infra-step1-design.md` @ commit `efa5e23a31820669d070c02aab11b47a13c226e1`  
章程：`team-design-charter.md`  
关联：`udp-mcast-tx-design.md` / `udp-mcast-tx-stream-contract.md`（S2 基线）

---

## 0. Scope（禁扩）

| ID | 内容 | 硬约束 |
|---|---|---|
| S1 | TCP 网络帧 → **payload 提取** | 入/出均为 **64b AXIS** |
| S2 | FPGA 产物 → **UDP 组播输出** | 每包 **&lt;512B**；UDP 组播 |

**不做：** 完整 TCP 协议栈重做、策略/订单簿/报单、其它网络功能。

**优先级：** 先 **S2**，再 **S1**。  
**S1 入侧（H4）：** L2–L4 网络帧 → 仅 TCP payload；若入已是 TCP segment → 变更单。  
**验收：** S1=点子王选项 A；S2=TX-only + 禁组地址 ARP + 单包 &lt;512B。

---

## 1. D4 假设（已裁定）

| ID | 内容 |
|---|---|
| A1 | S1：入 L2–L4 帧，出 TCP payload；无建连/重传 |
| A2 | S1/S2 **分核**；应用可在中间；本步不绑死应用 |
| A3 | S2 演进 `mcast_eng` / 组播契约；`payload_len`∈**[1,511]** |
| A4 | `sys_clk` / `sys_rst_n`；异钟 MAC 才 afifo |
| A5 | 产物仓 `melon5253/fpga-comm-infra` |
| H1 | 组地址/UDP 端口 **CSR/meta 参数化，禁写死**；机房实参后补 |
| H2 | TTL 默认 **1**；`ttl==0`/CSR0 → 当 1 |
| H3 | **无同卡 RX / 无 IGMP** |

---

## 2. D1 架构

```text
AXIS-64 (L2–L4 TCP 帧)
        │
        ▼
 ┌──────────────┐
 │ tcp_pay_strip│  S1（后置实现）
 └──────┬───────┘
        │ TCP payload AXIS-64
        ▼
   （应用 / 其它，边界外）
        │ 产物 payload &lt;512B
        ▼
 ┌──────────────┐
 │ udp_mcast_tx │  S2（优先）— 演进 mcast_eng
 └──────┬───────┘
        ▼
     MAC TX AXIS-64
```

铁律：分核；TCP 状态不进组播核；S1/S2 均角色 A（不回灌上游）。

---

## 3. D2 接口契约（收口）

### 3.1 S2 UDP 组播 TX（优先）

沿用已冻三分法，增量：

| 层 | 内容 |
|---|---|
| CSR | `cfg_src_mac/src_ip`、缺省 dip/ports、`ttl_default=1`、`map_en`（默认1）、`mtu_pay`≤511 |
| SOP meta | `dst/src_ip`、ports、`ttl`、`payload_len`∈[1,511]、`is_mcast`；禁 MAC/VLAN |
| 派生 | DA=RFC1112(dip)（线侧永远派生）；IP/UDP len、IPv4 csum；UDP csum=0 |

处理序：锁 meta → 门禁 → 填头 → 出站。meta&gt;CSR；禁 ARP；角色 A。

### 3.2 S1 TCP payload strip

| 口 | 说明 |
|---|---|
| 入 | AXIS-64 整帧（Eth/IP/TCP+payload），`tkeep/tlast` |
| 出 | AXIS-64 **仅 TCP payload** |
| 行为 | 切穿剥 L2–L4；角色 A；非 TCP/非法 → 丢+计数 |
| 禁 | 用 `udp_strip` / `tcp_pay_stub` 冒充本核 |

---

## 4. D3 验证方案（意图，不写 TB）

| ID | 查什么 |
|---|---|
| S2-H1 | 组地址/端口未写死；改 CSR/meta 后线上跟新 |
| S2-H2 | 默认 TTL=1；0→1 |
| S2-H3 | 无 RX/IGMP 状态 |
| S2-size | `payload_len`&gt;511 不发/丢+计；&lt;512 正常 |
| S2-A | ready 恒可收；MAC pause 不回灌 |
| S2-map | DA=RFC1112；禁 ARP |
| S1-H4 | 入 L2–L4 出纯 payload；非法丢+计 |
| S1-A | 入侧角色 A 不回灌 |

下游：**先落 S2 用例**，S1 并行不互堵。引用正式仓路径。

---

## 5. 复用 / 缺页

| 项 | 决议 |
|---|---|
| S2 组帧/csum/RFC1112 | 演进 `mcast_eng` 内联 |
| S1 | 独立 `tcp_pay_strip`；禁 stub 冒充 |
| catalog | 开写前立骨架于产物仓；异钟登记 `tx_afifo` |
| 文档 | 只引 `melon5253/fpga-comm-infra` |

---

## 6. 可实现性家规（开写前）

1. `sys_clk`/`sys_rst_n`、三段式、`i_/o_/w_/r_`；CSR `cfg_*`  
2. H1 写死组地址/端口 = 硬伤  
3. H2/H3 如上  
4. S2 `payload_len`∈[1,511]；角色 A  
5. S1 独立核；FIFO/RAM 登 catalog 后再例化  

---

## 7. 下游移交

**FROZEN 包：** 本文 + 边界单 + udp-mcast 契约（S2）。  
**实现序：** S2 → S1。  
**编码验证组：** G2 复审；禁静默改语义。

变更：机房组地址实参、入侧已是 TCP segment、同卡 RX/IGMP → 走变更单。
