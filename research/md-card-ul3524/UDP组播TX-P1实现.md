# UDP 组播 TX — P1 实现方案（可编码）

日期：2026-09-07  
状态：**实现基线**（依据 FROZEN `udp-mcast-tx-design.md` v1.0 + `udp-mcast-tx-stream-contract.md`）  
范围：先演进现网 `mcast_eng`，**不全量拆** `udp_mcast_tx`；薄适配可后置。

---

## 0. 目标（出门标准）

1. TTL 可配：`cfg_ttl_default` 上电默认 **1**；帧内 TTL 用该值（本阶段无逐包 meta）
2. Eth DA：`cfg_map_en=1`（默认）时由 `cfg_dst_ip` **RFC1112 映射**；`cfg_dst_mac` 只读镜像（写忽略）
3. `cfg_map_en=0`：用 CSR `dst_mac`，但若 `dst_mac != map(dst_ip)` → **不发** + sticky
4. 地址检查：`dst_ip∉224/4` 或 `src_ip∈224/4` → 不发 + sticky；`tready` 仍恒 1
5. IPv4 hdr csum 随 TTL/地址重算
6. `make sim-mcast` 绿；新增用例覆盖 map / TTL=1 / 非法地址 / mismatch
7. X1100：若 `post_tready = mcast && dma`，改为内部丢、不堵上游（架构 §7 提醒）

**不做（本 P1）：** IGMP、VLAN、通用 `s_udp_*` 多 beat 口、N>1 客户、loopback cut（可留 TODO）。

---

## 1. 模块改动清单

| 文件 | 动作 |
|---|---|
| `rtl/mcast_eng.sv` | 主改：TTL CSR、map、校验、csum |
| `rtl/md_rx_top.sv` | 引出 `cfg_ttl_default` / `cfg_map_en`；必要时修 tready 扇出 |
| `rtl/x1100/md_rx_top_x1100.sv` | 同上 + 检查 post_tready 铁律 |
| `tb/test_mcast_eng.py` | 新用例 + 改默认期望 TTL/DA |
| `docs/udp-mcast-tx-p1-impl.md` | 本文 |

可选后续：`mcast_event_to_udp_adapter` + 独立 `udp_mcast_tx`（契约口）— **P1.1**，不挡本出门。

---

## 2. `mcast_eng` 端口增量

```systemverilog
input  logic [7:0]  i_cfg_ttl_default,  // 默认绑 8'd1
input  logic        i_cfg_map_en,       // 默认 1
output logic        o_err_addr_sticky,
output logic        o_err_mac_mismatch
```

现有 `i_cfg_dst_mac` 保留：`map_en=1` 时忽略写入值，组帧用 `w_mapped_mac`；可用 `assign` 调试口读回 map（top 可选）。

### 2.1 组合逻辑

```text
w_mapped_mac = {24'h01005E, 1'b0, i_cfg_dst_ip[22:0]}
w_da_is_mcast = (i_cfg_dst_ip[31:28] == 4'hE)
w_sa_ok       = (i_cfg_src_ip[31:28] != 4'hE)
w_mac_ok      = i_cfg_map_en ? 1'b1
              : (i_cfg_dst_mac == w_mapped_mac)
w_addr_ok     = w_da_is_mcast && w_sa_ok
w_hdr_ok      = w_addr_ok && w_mac_ok
w_ttl         = (i_cfg_ttl_default == 8'd0) ? 8'd1 : i_cfg_ttl_default
  // 注：契约 meta.ttl==0 用 CSR；本阶段无 meta，CSR=0 也当 1，避免 TTL=0 非法
```

`w_accept` 原条件 **AND** `w_hdr_ok`。  
非法时：原 drop 计数路径旁增加 sticky（一旦置 1，rst 清）。

### 2.2 组帧

- `fb[0..5]` ← `i_cfg_map_en ? w_mapped_mac : i_cfg_dst_mac`
- `fb[22]` ← `w_ttl`（替换 `8'h40`）
- `ipv4_hdr_csum` 增加 ttl 形参（现写死在 sum 的 `0x4011` → `{ttl,8'h11}`）

### 2.3 反压

保持 `o_s_event_tready = 1'b1`。

---

## 3. Top 接线

- `md_rx_top` / x1100：新增端口或内部常量  
  - 仿真默认：`cfg_mcast_ttl=8'd1`，`cfg_mcast_map_en=1'b1`  
- **X1100 tready：** 搜索 `mcast_ev_ready && dma_ev_ready` 一类 AND；若会回灌 CAM/解码，改为各消费者内部 ready=1、满则丢（与 design §7 一致）

---

## 4. 仿真用例（`sim-mcast`）

| 用例 | 期望 |
|---|---|
| `test_map_da` | dst_ip=239.1.1.1 → DA=`01:00:5e:01:01:01`（注意 bit23 清 0） |
| `test_ttl_default_1` | IP TTL 字节 == 1；csum 匹配 |
| `test_bad_sa_group` | src_ip 为组地址 → 不发，sticky |
| `test_bad_da_unicast` | dst_ip 单播 → 不发 |
| `test_map_en0_mismatch` | map_en=0 且 mac≠map → 不发 |
| `test_map_en0_match` | map_en=0 且 mac==map → 正常发 |
| 现有对拍 | 更新 TB 期望 TTL 从 0x40→1；DA 与 map 一致 |

RFC1112 例：`239.1.1.1` = `0xEF010101`，低 23 bit → MAC `01:00:5e:01:01:01`。

---

## 5. 编码序

1. 改 `ipv4_hdr_csum` + TTL/map 组合 + accept 门控  
2. sticky 输出  
3. top 端口默认  
4. TB 用例  
5. `make sim-mcast`；再 `make sim-top` / 相关 x1100 冒烟  
6. 回路径与 diff 摘要给组长 / 并行抽审（反压）

---

## 6. 风险

| 风险 | 处理 |
|---|---|
| TB 写死 TTL=64 / 手写 MAC | 一并改期望 |
| map 与历史 CSR MAC 不一致 | 默认 map_en=1；文档告知迁移 |
| csum 漏改 ttl | 用例 `test_ttl_default_1` 咬死 |

---

*组长签发 · 编码：顶级码农 · 验证：补用例*
