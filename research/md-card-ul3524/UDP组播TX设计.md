# UDP 组播 TX 方案（可评审）

日期：2026-09-07  
状态：**FROZEN v1.0（组长签字）** — 2026-09-07；架构 §7 + AXI §4 已合入  
仓库：`/workspace/fpga-md-card`  
依据：调研 `fpga-udp-unicast-to-multicast.md` §3.4 / §7.2；现网 `rtl/mcast_eng.sv`、`docs/module-design-v1.md` §3.8、`spec-v1.md` §2.6

---

## 0. 结论先行

本卡 **不是**「单播 UDP + ARP」再改组播，而是已有 **硬核组播 TX** `mcast_eng`：CSR 模板头直接打 Eth/IPv4/UDP，**从不走 ARP**。

本方案目标：把现有 TX 收成 **RFC 1112 合规、可配置、可验证** 的组播发路径，并写清与 MAC/IP、DMA、单播控制面的边界。

| 项 | 决议 |
|---|---|
| 主路径 | **演进 `mcast_eng`**（共路径增强），不新建第二套 UDP 栈 |
| ARP | **永不**对组地址 ARP；保持模板头 / RFC1112 映射 |
| IGMP | **TX-only Level 1：out-of-scope**（交换机 snooping/PIM/静态 OIF 为机房依赖） |
| 单播控制/恢复 | 保留现有/未来单播路径；与组播 TX **口分离** |
| 本轮交付 | 方案 + 接口契约；不全量 RTL（仅列必改点 / 可选接口草稿） |

---

## 1. 规格与假设

| 项 | 取值 | 备注 |
|---|---|---|
| 线速 | **假设 10G**（X1100 / 现 md 热路径同量级） | 未单独确认 1G；改 1G 只影响 MAC 壳 |
| 时钟 | `sys_clk` = **322.265625 MHz** 单域（与现 `mcast_eng` 一致） | TX→MAC 若异钟，仅在 top 加 afifo |
| 复位 | `sys_rst_n` 异步断言、同步释放 | |
| 载荷 | 现网：`event_t` 64B 固定；可扩「通用 UDP payload AXIS」见 §4 | |
| 组地址 | CSR `dst_ip ∈ 224.0.0.0/4` | 机房具体组未给 → 方案按可配 |
| 接口单播 SA | CSR `src_ip` / `src_mac` | **禁止** SA=组地址 |
| TTL | CSR `ttl`，**上电默认 1**（RFC 1112 §6.1） | 现 RTL 写死 `0x40`，属 gap |
| VLAN | v1 **不做**；机房若要 802.1Q 单独立项 | |
| 同卡 RX 同组 | 假设 **可能**；须定义 loopback（§6） | |
| 客户端数 | 规格目标 N=16；仿真 N=1 | 每客户独立引擎 |

---

## 2. 与现网差异（相对「典型单播 UDP TX」+ 相对现 `mcast_eng`）

### 2.1 相对典型单播 UDP（调研 checklist）

| # | 要求 | 现 `mcast_eng` | 本方案动作 |
|---|---|---|---|
| 1 | IP DA=组，SA=接口单播 | CSR 可配，**无硬件约束** | 加 CSR 合法性检查 / 粘滞错；可选硬丢非法帧 |
| 2 | Eth DA=RFC1112（`01-00-5E`+低 23b） | CSR `dst_mac` **手填**，易与 IP 漂移 | **HW 由 `dst_ip` 映射 DA**（推荐）；或校验 CSR MAC≡映射 |
| 3 | 绕过 ARP 失败丢包 | **已绕过**（无 ARP） | 保持；文档钉死 |
| 4 | TTL 显式 | **写死 0x40** | 改 CSR，默认 1 |
| 5 | 发送方可不加入组 | 满足 Level 1 | IGMP OOS |
| 6 | 本机也收同组 | 未定义 | §6 loopback |

### 2.2 相对现模块可保留

- PCS/MAC CRC、64b AXIS 出站节奏、store-and-forward 一帧  
- UDP 长度/端口 CSR、payload=`event_t`、UDP csum=0、IPv4 hdr csum 组合算  
- symbol 过滤位图 + ch_mask + token bucket；**event 侧 tready≡1**（永不反压热路径）  
- `dma_pack` 软核旁路、遥测计数  

---

## 3. 模块划分

```text
md_rx_top / md_tx 壳
  event_bus (broadcast)
       │
       ├─► mcast_eng × N          ← 本方案焦点（数据面）
       │     ├─ filt / rate       （控制面影子）
       │     ├─ hdr_build         （RFC1112 map + TTL + csum）
       │     └─ axis64 TX beats
       │              │
       │              ▼
       │         (opt) tx_afifo   若 mac_tx_clk ≠ sys_clk
       │              │
       │              ▼
       │         MAC/PCS TX
       │
       └─► dma_pack               （主机，非线侧组播）

控制面：CSR（AXI-Lite 或现绑线）— src/dst IP、TTL、ports、filt、rate
单播 ARP/TCP 恢复：独立模块，**禁止**与 mcast_eng 共享「ARP 查表失败→丢」逻辑
```

| 模块 | 职责 | 钟 |
|---|---|---|
| `mcast_eng` | 过滤、限速、组帧、AXIS-64 出 | `sys_clk` |
| `mcast_hdr_map`（可内联） | `dst_ip`→Eth DA；TTL；SA/DA 合法性 | 同左 |
| `tx_mac_bridge`（可选） | sys↔mac_tx CDC | 双钟时才有 |
| MAC IP | L1/L2 发送 | `mac_tx_clk` |
| CSR 块 | 影子寄存器 | `sys_clk` |

**层次：** `_top` 只接线/复位/可选 CDC；业务 FSM 留在 `mcast_eng`。

---

## 4. 接口契约（用户侧 → UDP TX）— **正式（AXI 已回填）**

完整细则：[`udp-mcast-tx-stream-contract.md`](./udp-mcast-tx-stream-contract.md)。  
本节是总稿自洽口表：**TTL / RFC1112 map 模式 / 反压铁律 / CSR** 以本节为准；与 stream 契约冲突时以本节 + stream 契约最新修订共同 bump。

### 4.0 铁律（冻结）

| ID | 内容 |
|---|---|
| **T1** | 组地址（`224.0.0.0/4`）**禁止 ARP**，禁止落入单播「ARP miss→丢」路径 |
| **T2** | Eth DA **仅** RFC1112 映射；用户侧**不**送 `dst_mac`（正式路径） |
| **T3** | IP SA = 本机单播；**禁止** SA∈`224/4` |
| **T4** | MAC/`m_eth_tready` 暂停**不得**回灌 `event_bus` / 解码 / L0 写口 |
| **T5** | 线侧首字节 `tdata[7:0]`（同 `md_pkg`） |

RFC1112 映射：

```text
dst_mac = {24'h01005E, 1'b0, dst_ip[22:0]}
```

### 4.1 目标流口 `s_udp_*`（新路径）

| 信号 | 宽 | 说明 |
|---|---|---|
| `s_udp_tdata` | DATA_W（默认 64；X1100 可 32） | UDP **载荷 only** |
| `s_udp_tkeep` | DATA_W/8 | 末拍可稀疏；中间拍全 1 |
| `s_udp_tvalid` / `s_udp_tready` / `s_udp_tlast` | 1 | `fire=valid&&ready` |
| `s_udp_meta` | `udp_tx_meta_t` | **SOP 同拍**锁存至 `tlast` |
| `s_udp_meta_valid` | 1 | 与首拍 `tvalid` 同拍为 1 |

`udp_tx_meta_t` 字段：

| 字段 | 宽 | 冻结语义 |
|---|---|---|
| `dst_ip` | 32 | 组地址；断言 ∈`224/4` |
| `src_ip` | 32 | 本机单播；断言 ∉`224/4` |
| `dst_port` / `src_port` | 16/16 | |
| `ttl` | 8 | **0 = 用 CSR `cfg_ttl_default`**；非 0 用本字段 |
| `payload_len` | 16 | 必须等于本帧 `tkeep` 累计字节；∈`[1, cfg_mtu_pay]` |
| `flags[0]` | 1 | **`is_mcast=1`**（本路径强制） |
| `flags[7:1]` / `pad` | — | 保留 0 |

**禁止** meta/ AXIS 携带：`dst_mac`、`src_mac`、VLAN。

### 4.2 TTL（冻结）

| 项 | 值 |
|---|---|
| CSR `cfg_ttl_default` | **上电默认 `8'd1`**（RFC 1112 §6.1） |
| 现网 gap | `mcast_eng` 写死 `0x40` → P1 必改 |
| 装包选用 | `meta.ttl != 0 ? meta.ttl : cfg_ttl_default` |
| IP hdr csum | 随 TTL/地址**每帧重算** |

### 4.3 RFC1112 map 模式（冻结）

| `cfg_map_en` | 行为 |
|---|---|
| **1（正式 / 默认）** | Eth DA = HW map(`dst_ip`)；CSR `dst_mac` **只读镜像**（写忽略或写后读回 map 值） |
| **0（迁移期 only）** | 兼容旧 CSR `dst_mac`；若 `dst_mac != map(dst_ip)` → **不发** + `err_mac_mismatch` sticky；正式产品关闭此模式 |

非法：`dst_ip∉224/4` 或 `src_ip∈224/4` → 不发 + `err_addr_sticky`（角色 A 仍 ready=1）。

### 4.4 反压铁律（冻结）

| 角色 | 适用 | `s_udp_tready` / 现 `o_s_event_tready` | 忙/FIFO 满 / MAC pause |
|---|---|---|---|
| **A 热路径（默认行情）** | `event_bus`→薄适配→TX；book 旁路 | **恒可收（语义 ready=1）** | **丢 + `drop_busy`/`drop_rate`**；MAC pause 只停出站拍 |
| **B 可停** | 主机慢速/非线速 | 真实反压 | 允许 `tready=0` |

本卡组播出站 = **角色 A**。薄适配接现 `mcast_eng` 事件口时保持 `o_s_event_tready=1`。

### 4.5 CSR 表（相对现 `mcast_eng`）

| CSR | 现有 | 正式 |
|---|---|---|
| `cfg_src_mac` | 有 | 保持；Eth SA |
| `cfg_src_ip` | 有 | 保持；断言 ∉`224/4` |
| `cfg_dst_ip` | 有 | 保持作缺省组地址；逐包 meta 优先 |
| `cfg_dst_mac` | 可写 | **`cfg_map_en=1` 时只读镜像** |
| `cfg_udp_sport/dport` | 有 | 缺省；meta 优先 |
| **`cfg_ttl_default`** | **无** | **新增，默认 1** |
| **`cfg_map_en`** | **无** | **新增，默认 1** |
| **`cfg_mtu_pay`** | 无 | 默认 1472 |
| filt / period / refill | 有 | 保持 |
| 遥测 | tx_ok / drop_* | 增 `err_addr_sticky` / `err_mac_mismatch` / `drop_bad` |

### 4.6 与现 `mcast_eng`：薄适配

```text
event_bus ──► mcast_event_to_udp_adapter ──s_udp_*──► udp_mcast_tx / 演进后 mcast_eng
                 │
                 └─ 把 event_t（或 top10_msg）摊成 payload beats；
                    meta 从 CSR 缺省 + flags.is_mcast=1 填充
```

| 现网 | 正式 |
|---|---|
| 用户可见 `dst_mac` | 删除；核内 map |
| `event_t` 512b 单拍直进 | 适配 → `s_udp_*` |
| ready≡1 | 角色 A 保持 |
| TTL=`0x40` | `cfg_ttl_default=1` + meta |

v1 行情主线：**演进 `mcast_eng` 内联 map/TTL/检查**，外挂薄适配即可；不强制先拆独立 `udp_mcast_tx_core`。

### 4.7 线侧出站（保留）

`m_eth_tdata/tkeep/tvalid/tlast` + `m_eth_tready`：AXIS-64 整帧（Eth+IP+UDP+payload），无 FCS；字节0=`tdata[7:0]`。

### 4.8 相对单播 TX（摘要）

| | 单播（典型） | 本组播 |
|---|---|---|
| Eth DA | ARP | RFC1112 map，禁 ARP |
| TTL 默认 | 常 64 | **1** |
| 反压 | 常可停 | **角色 A 不回灌** |

---

## 5. 关键路径时序（`sys_clk`）

| 段 | 拍（估） |
|---|---|
| accept 组合（filt+rate+!busy） | 0（同拍决策） |
| 组帧写入 `r_frame[]` | 1（accept 拍） |
| AXIS 发出 | 14 beat（106B，末拍 2B） |
| **热路径事件 → 首拍上线** | **1 + MAC/PCS**（相对现网不劣化） |
| MAC `tready` 低 | 只拉长 ST_TX；event 继续可被丢（drop_rate） |

相对「理想单播 ARP 命中」：组播路径 **更短**（无 ARP RTT）。相对现 `mcast_eng`：TTL/映射为组合增量，目标 **不增加 accept→首拍** 拍数。

---

## 6. 与 MAC / IP / 环回

| 衔接 | 要求 |
|---|---|
| MAC TX | 收 AXIS-64；FCS 由 MAC；DA 已是组播 MAC |
| IP | 无路由查表；TTL 用 CSR；不分片（DF 可维持现 0） |
| 校验和 | IPv4 hdr 随 TTL/地址重算；UDP csum 可继续 0 |
| **Loopback** | 若同卡 RX 订了同组：默认 **依赖交换机/MAC 是否环回**；FPGA 侧推荐 CSR `tx_loopback_cut=1` 时 RX 过滤「SA=本机 src_mac」避免自激（可选，标 O） |
| 网络依赖 | IGMP snooping / PIM / 静态 OIF：**文档依赖，不实现** |

---

## 7. 与行情 / 报单 / DMA 咬合（架构正式版）

作者：FPGA 架构师 · 日期：2026-09-07  
前提（仓内事实）：**无** ARP 单播 UDP TX 栈；线侧 UDP 出站基线即 `mcast_eng`。报单参考仓 `fpga-order-tcp-tx-src` 为 **TCP**，与本卡组播 UDP **口分离**。

### 7.1 结论（共路径怎么切）

| 出站 | 载荷 | 物理路径 | 与 `mcast_eng` |
|---|---|---|---|
| **行情事件组播** | `event_t`（64B） | `event_bus` → `mcast_eng` → MAC/PCS TX | **本方案本体**（演进，非新栈） |
| **主机 DMA（软核/LightningDMA）** | `event_t` 或 `top10_msg` | `dma_pack` / `book_push_engine` → DMA | **并联旁路**，不进 MAC 组播口 |
| **十档推送（book_push）** | `top10_msg_t` | L0/`book_push_engine` → DMA | **默认不进** `mcast_eng` |
| **报单** | TCP 段 | 专用报单核 / 柜台口 | **禁止**接入 `mcast_eng` |

```text
                    event_bus (broadcast, tready 铁律见下)
                         │
          ┌──────────────┼──────────────────┐
          ▼              ▼                  ▼
     mcast_eng×N    dma_pack            (opt) 旁路计数
     (线侧组播)     (主机 event)
          │              │
          ▼              ▼
       MAC TX         PCIe/DMA

  book_push_engine ──► DMA（top10_msg）
       ▲
       │  不默认叉进 mcast_eng
  L0 / refill / timer

  报单 TCP TX ────────► 另一 MAC/口（或 TDGW 前单播）
```

**共路径定义（钉死）：**

1. **共享的只有** `sys_clk` 上的 `event_bus` 扇出（行情解码后）。`mcast_eng` 与 `dma_pack` 已是并联消费者。  
2. **不共享** ARP/邻接表、报单 TCP 状态机、book_push 的 DMA 描述符环。  
3. **不新建**第二套 UDP/IP 组帧栈；TTL/RFC1112 等在现 `mcast_eng` 内演进（见 §2、§4）。  
4. 若产品要「十档也打到线侧组播」：在 `book_push` 后再挂 **可选** `mcast_eng` 实例或通用 payload 口（§4.4），**默认关闭**；打开前单独算带宽与过滤，不与 event 组播抢同一 token 桶 unless 显式 CSR 绑定。

### 7.2 反压与丢包边界（与 book_push 一致的铁律）

| 节点 | 对上游 | 拥塞时 |
|---|---|---|
| `mcast_eng` ← `event_bus` | **`tready ≡ 1`** | 滤/限速/忙 → drop + 计数，**不**堵解码 |
| `dma_pack` ← `event_bus` | 浅 FIFO；满则丢 | 同上，不回灌 strip |
| `book_push_engine` ← L0 rt | rt 为脉冲，不反压 | DMA `tready` 只停 emit；refill/snap 自有 ready |
| MAC ← `mcast_eng` | 可拉低 `tready` | 只拉长 `ST_TX`；accept 窗口忙则后续 event 可被 drop_rate |

X1100 顶层若用 `post_tready = mcast_ready && dma_ready`：**违反**「永不反压」时必须改回「各消费者 ready 恒 1 / 内部丢」（与 `module-design-v1`、book_push 铁律对齐）。架构要求：**event 扇出点对各 `mcast_eng`/`dma_pack` 视为 always-ready 接口**。

### 7.3 延迟预算（相对现网 / 相对「假想单播 ARP」）

钟：`sys_clk` = 322.265625 MHz ≈ **3.103 ns/拍**（与 md 热路径同域）。

| 段 | 拍（设计） | ns @322M | 备注 |
|---|---|---|---|
| event 到达 → accept（filt+rate+!busy） | 0～1 | 0～3.1 | 现实现同拍决策；TTL/RFC1112 map **组合进组帧**，目标不增拍 |
| 组帧写入 `r_frame[]` | 1 | 3.1 | store-and-forward 一帧 |
| AXIS-64 首拍上线 | 含在上一拍后立即 | — | 106B / 14 beat 发完 ≈ 43.4 ns 纯线拍 |
| **event → 线侧首拍**（User Logic） | **≈1** | **≈3.1** | 再加 MAC/PCS（厂商壳；NDPP 公开 Lightning MAC ~30ns 量级作量纲，**非本卡承诺**） |
| 整帧发完 | 1+14 | ≈46.5 | 末拍 2B；遇 `tready` 低则拉长 |

**相对现 `mcast_eng`：** P1（TTL CSR + RFC1112）目标 **不增加** accept→首拍拍数；IP hdr csum 随 TTL 重算仍在组帧拍完成。

**相对「单播 UDP + ARP 命中」：** 组播路径 **更短**（0 ARP RTT）。仓内无该单播栈，对比仅作产品叙事，不作回归基线。

**相对 `book_push`→DMA：** 不同出口。book_push 延迟由 L0 更新 + 队列优先级（rt>refill>timer）+ DMA 决定，**不计入**线侧组播预算；二者并行，互不阻塞（除共享 PCIe/DDR 控制器时的系统预算，见 `p0-top10-axi-contract`：定时 top10 走 DMA 不走 DDR AXI）。

**报单路径：** TCP RTT/会话与组播 TX **无公共关键路径**；禁止为组播改动报单口时序。

### 7.4 与 book_push / 十档产品的产品边界

| 问题 | 决议 |
|---|---|
| 十档更新是否自动上组播？ | **否（默认）**。主机吃 DMA `top10_msg`；线侧仍以 `event_t` 组播（或客户定制过滤）为主 |
| 定时 4096 全推是否打线侧？ | **否**。~100MB/s 级走 DMA（已冻）；线侧 10G 组播应用 token bucket 限客户，不承载全市场定时刷 |
| 缺档 refill 结果上组播？ | **否**。refill 只修 L0，再经 book_push→DMA；若要线侧一致，等下一笔触发 rt 的 event 组播或显式策略 CSR |
| 同源双写（同一 top10 既 DMA 又 mcast） | 可选产品开关；打开前：独立 `mcast` 实例 + 独立限速 + 带宽评审 |

### 7.5 报单 / 控制面

- 报单：TCP（或会员网关单播），**另一口或另一 bitstream 角色**；不共享 `mcast_eng` 头模板。  
- 组播控制面：CSR（src/dst IP、TTL、ports、filt、rate、`cfg_map_en`）。  
- **禁止**把「ARP 失败→丢」状态机接到组播路径（仓内本无 ARP；防未来误合入单播核）。

### 7.6 架构验收（§7）

- [ ] 框图与顶层例化一致：`event_bus` 并联 `mcast_eng` + `dma_pack`；book_push 仅 DMA  
- [ ] 各 `mcast_eng`/`dma_pack` 对 event **恒 ready**（或等价内部丢）  
- [ ] P1 改 TTL/map 后 `event→首拍` 拍数不劣化  
- [ ] 文档/代码审：组播路径无 ARP 调用；报单核未例化进 md 组播口  


## 8. 风险

| ID | 风险 | 缓解 |
|---|---|---|
| R1 | CSR MAC/IP 不一致 | HW map 或严格校验 |
| R2 | TTL=64 误出机房 | 默认 1 + CSR；遥测打印 |
| R3 | 同卡 RX 自收风暴 | loopback cut / SA 过滤 |
| R4 | N=16 时 MAC 口仲裁 | 独立口或加权 arb；规格已要求并行引擎 |
| R5 | 误接 ARP 单播栈 | 代码审：mcast 路径禁 ARP 调用 |
| R6 | 机房要 VLAN | 本方案 OOS，另开 |

---

## 9. 验证要点

| 用例 | 检查 |
|---|---|
| RFC1112 map | 若干组地址 → DA 字节级对拍 |
| SA/DA 合法性 | SA∈224/4 或 DA∉224/4 → 粘滞错/不发 |
| TTL | CSR=1/64 时 IP 字节与 csum 正确 |
| 无 ARP | 断 ARP 表仍能发（本设计天然满足；防回归） |
| 反压 | MAC pause 时 event 不停；只增 drop_rate/busy |
| 过滤/限速 | 与现 TB 行为一致 |
| 可选 loopback | 开 cut 后 RX 不见本机 SA 组播 |

建议：在现 `mcast` TB 上加 `test_mcast_rfc1112_*`；不全量新 UVM。

---

## 10. 里程碑

| 阶段 | 内容 | 出门条件 |
|---|---|---|
| **P0** | 本文 FROZEN（架构+AXI 合入） | 组长签字 |
| **P1** | `mcast_eng`：TTL CSR + RFC1112 map/校验 + SA/DA 检查 | `make sim` 含新用例绿 |
| **P2** | （可选）loopback cut；N>1 arb 文档 | 按产品 |
| **P3** | 上板：机房组地址/TTL/是否静态 OIF 核对 | 抓包 DA/IP/TTL |

---

## 11. 待合入

- [x] 架构师：与 book_push/DMA/报单咬合 + 延迟数字（§7 正式版，2026-09-07）  
- [x] AXI：正式 AXIS/CSR 口表（§4 正文已回填 TTL/map/反压；细则见 `udp-mcast-tx-stream-contract.md`）  
- [ ] 用户确认（不挡实现）：线速、机房组地址、是否同卡 RX / loopback cut  

---

*组长：FPGA小组组长 · 协作：FPGA 架构师、FPGA AXI接口协议负责人 · 调研：调研专员*
