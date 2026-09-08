# 用户侧 → UDP TX 流接口契约（组播）

日期：2026-09-07  
状态：**草案冻结（AXI/协议负责人）** — 供小组组长收进组播 TX 总稿  
仓库：`/workspace/fpga-md-card`  
对照：现有 `rtl/mcast_eng.sv`（event→整帧）、`docs/module-design-v1.md` §2/§3.8、`/workspace/fpga-udp-unicast-to-multicast.md` §7.2

---

## 0. 范围与铁律

本契约定义 **User Logic 上游 → `udp_mcast_tx`（或等价 UDP 组包核）** 的流口，**不**含 MAC/PCS、IGMP、LightningMAC 绑定细节。

| ID | 铁律 |
|---|---|
| **T1** | 目的地址为 IPv4 组地址（`224.0.0.0/4`）时：**禁止 ARP / 禁止走单播 ARP 未命中丢包路径**。 |
| **T2** | Eth DA **仅**由 IP 映射：`01:00:5e:00:00:00 \| (dst_ip & 0x7FFFFF)`（RFC 1112）。用户侧**不**送 dst_mac。 |
| **T3** | IP SA = 本机单播（`src_ip`）；**禁止**用组地址当 SA。 |
| **T4** | 线侧字节序与仓一致：AXIS 首字节在 `tdata[7:0]`（同 `md_pkg` / `fpga-order-tcp-tx`）。 |

下游（UDP TX 内部）负责：Eth/IPv4/UDP 头、IP header checksum、UDP csum（v1 允许 0）、TTL、组包出站 eth AXIS。

---

## 1. 口形总览

```
  book_push / mcast adapter / 其它 User Logic
              │
              │  s_udp_*  （本契约）
              ▼
         udp_mcast_tx
              │
              │  m_eth_*  AXIS-64/32 整帧（接 MAC TX / TB）
              ▼
           LightningMAC / stub
```

与现网 `mcast_eng` 的关系：

| | 现 `mcast_eng` | 本契约 `s_udp_*` |
|---|---|---|
| 上游载荷 | 固定 `event_t` 512b 单 beat | **任意 UDP payload** 多 beat AXIS |
| 头字段 | CSR 模板（含 **dst_mac**） | **逐包 meta**；dst_mac 由核内映射 |
| 用途 | 行情 event 专用 | 通用组播 UDP TX（含 `top10_msg` 等） |

迁移：可加薄适配把 `event_t`/`top10_msg` 打成 `s_udp_*`；长期新路径优先本口，避免再把 dst_mac 暴露给用户侧。

---

## 2. 流信号（AXIS + meta）

默认仿真/UL 风格 **DATA_W=64**；X1100 可参数化 **32**（与 `ndpp_pkg` 一致）。下列以 64b 写口名。

### 2.1 Payload AXIS

| 信号 | 方向（相对 TX 核） | 宽 | 说明 |
|---|---|---|---|
| `s_udp_tdata` | in | DATA_W | UDP **载荷**（不含 Eth/IP/UDP 头） |
| `s_udp_tkeep` | in | DATA_W/8 | 有效字节；末拍可稀疏，中间拍须全 1 |
| `s_udp_tvalid` | in | 1 | |
| `s_udp_tready` | out | 1 | 见 §4 反压 |
| `s_udp_tlast` | in | 1 | 本 UDP 报文最后一拍 |

约定：

- `fire = tvalid && tready`
- 一帧 = 连续拍直到 `tlast`；`payload_len` 必须等于该帧有效字节数（见 meta）
- 空载荷（len=0）**禁止**；非法则 TX 丢弃并 `drop_bad++`，不反压解码热路径（若上游是热路径角色，见 §4）

### 2.2 Meta（与 SOP 同拍有效）

推荐 **独立口**（与 AXIS 并行），在 **首拍 fire**（SOP）采样并锁存至 `tlast`；非首拍 meta 忽略。

```systemverilog
typedef struct packed {
  logic [31:0] dst_ip;      // 组地址 224/4；非组地址见 §5 单播差异
  logic [31:0] src_ip;      // 本机单播 SA
  logic [15:0] dst_port;
  logic [15:0] src_port;
  logic [7:0]  ttl;         // 0 表示用 CSR 默认（建议默认 1，RFC 1112）
  logic [15:0] payload_len; // UDP 数据长度；UDP Length = payload_len+8
  logic [7:0]  flags;       // [0]=is_mcast 必须 1；其余保留
  logic [7:0]  pad;
} udp_tx_meta_t;            // 建议打包进 md_pkg / 独立 pkg
```

| 信号 | 方向 | 说明 |
|---|---|---|
| `s_udp_meta` | in | `udp_tx_meta_t`，SOP 有效 |
| `s_udp_meta_valid` | in | 与首拍 `tvalid` 同拍为 1；可绑成 `tvalid && !in_packet` |

校验（TX 核组合/首拍）：

1. `flags[0]==1` 且 `dst_ip[31:28]==4'hE` → 组播路径（本契约主路径）
2. `payload_len` ∈ `[1, MTU_PAY]`（CSR；默认 ≤1472）
3. 实际 `tkeep` 累计字节 == `payload_len`，否则 `drop_bad++`

**禁止** meta 携带：`dst_mac`、`src_mac`（src_mac 仅 CSR）、VLAN（v1 不做）。

### 2.3 下游 eth AXIS（参考，非本契约主体）

与现 `mcast_eng` 出站一致：`m_eth_tdata/tkeep/tvalid/tlast/tready`，整帧含 Eth+IP+UDP+payload；无 FCS（MAC 补）或按 FDK。

---

## 3. 组播封装（TX 核义务）

SOP 锁存 meta 后：

| 字段 | 来源 |
|---|---|
| Eth DA | **映射** `dst_ip`（T2）；**不**查表 ARP |
| Eth SA | CSR `cfg_src_mac` |
| Eth type | `0x0800` |
| IP TTL | `meta.ttl!=0 ? meta.ttl : cfg_ttl_default` |
| IP DA/SA | `meta.dst_ip` / `meta.src_ip` |
| UDP sport/dport/len | meta；csum v1=0 |
| IP total length | 20+8+payload_len |

实现检查清单：组播路径 **绕过** 任何「ARP miss → drop」；单播 TX 可共用封装器但必须 `if (is_mcast) map else arp` 分叉（见 §5）。

---

## 4. 反压与角色

| 上游角色 | `s_udp_tready` | 满/忙时行为 |
|---|---|---|
| **A. 热路径**（event_bus / book 旁路，对标现 `mcast_eng`） | **恒 1** 或浅 FIFO 满仍呈 ready=1 | **丢包 + 计数**（`drop_busy`/`drop_rate`）；**禁止**回灌到解码/`udp_strip` |
| **B. 可停路径**（主机下发、慢速配置、非线速） | 真实反压 | 允许 `tready=0`；上游必须能停 |

默认行情组播出站 = **角色 A**。  
`book_push_engine` → 组播：优先 A（与「推送不回灌热路径」一致）；若 push 已有独立队列，队列满丢最新/覆盖写策略由 push 契约定，**本口仍不得把 MAC 反压传到 L0 写口**。

MAC/`m_eth_tready` 暂停：仅堵在 TX 核内 store-and-forward 或出站 FIFO；角色 A 继续对上游 ready=1 并在入队失败时丢。

---

## 5. 与现「单播 TX」口差异

对照仓内惯例：单播控制面常见路径是 **ARP 解析 DA + 本机 SA**（见 gap 分析 §3/§7.2）；`fpga-order-tcp-tx` 为 TCP 整帧 AXIS，不经本 UDP meta 口。

| 项 | 单播 UDP TX（典型） | 本组播 UDP TX（本契约） |
|---|---|---|
| `dst_ip` | 单播主机 | **组地址 224/4** |
| Eth DA | ARP/邻接表 | **IP→MAC 映射，禁 ARP** |
| meta.`flags[0]` | 0 | **1** |
| TTL 默认 | 常 64 | **建议 1**（未指定时） |
| 失败模式 | ARP miss 可丢/重试 | **无 ARP 重试**；映射失败不存在（组合逻辑） |
| 反压 | 常可停 | 行情默认 **不回灌**（角色 A） |
| 用户是否送 MAC | 有时送 dst_mac | **禁止**；核内计算 |

双模核：同一 `s_udp_*` 可兼单播——`flags[0]=0` 走 ARP 口（另契约）；组播总稿只冻 `flags[0]=1` 路径。

---

## 6. 与现 `mcast_eng` 字段对照（迁移）

| 现 CSR / 行为 | 本契约 |
|---|---|
| `i_cfg_dst_mac` | **删除用户可见**；改映射 |
| `i_cfg_dst_ip` 等 | 改为逐包 `s_udp_meta`（CSR 可作缺省） |
| `i_s_event_*` 512b | 改为 payload AXIS；adapter 把 event/top10 摊成 beats |
| `o_s_event_tready=1` | 角色 A 保持 |
| Token bucket | 仍可放在 TX 核或上游；满丢计数保留 |

---

## 7. 时钟与参数

| 项 | 冻结建议 |
|---|---|
| 时钟 | 与热路径同域 `sys_clk` 322.265625 MHz（仿真任意）；跨 MAC 域则 eth 侧异步 FIFO，**meta/payload 同域** |
| `DATA_W` | 64 默认；32 参数化（X1100） |
| `MTU_PAY` | CSR，默认 1472 |
| `cfg_ttl_default` | CSR，默认 1 |
| `cfg_src_mac` | CSR |

---

## 8. 验收（协议侧）

- [ ] 组地址报文：抓 eth DA == RFC1112 映射；波形中 **无** ARP 请求因该 DA 产生
- [ ] `src_ip` 为单播；DA 为组地址
- [ ] 角色 A：拉低 `m_eth_tready` 时上游热路径仍不堵；仅见 `drop_*` 增
- [ ] `payload_len` 与 `tkeep` 累计不一致 → `drop_bad`，无坏帧出站
- [ ] 文档路径已交组长收进总稿

---

## 9. 一句话

**用户侧只送 UDP 载荷 AXIS + 组播 meta（dip/sip/ports/ttl/len）；TX 核映射 Eth DA、禁 ARP、默认不回灌热路径——与单播「ARP+可停」口明确分叉。**
