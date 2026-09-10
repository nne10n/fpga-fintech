# D2 接口契约

**状态：** G1 FROZEN。权威正文：`design/comm-infra-step1-design.md` §3。  
边界：`docs/boundary/通信基建-边界单.md` @ `3fb73e3`。

64-bit AXI-Stream：`tdata[7:0]` 为线上首字节；`tkeep[i]` 对应该字节；`tlast` 包界。角色 A：入侧 `tready ≡ 1`。

## S2 `udp_mcast_tx`（优先）

| 层 | 内容 |
| --- | --- |
| CSR | `cfg_src_mac` / `cfg_src_ip`、缺省 dip/ports、`ttl_default=1`、`map_en`（默认 1）、`mtu_pay`≤511 |
| SOP meta | `dst/src_ip`、ports、`ttl`、`payload_len`∈[1,511]、`is_mcast`；禁 MAC/VLAN |
| 派生 | DA=RFC1112(dip)（线侧永远派生）；IP/UDP len、IPv4 csum；UDP csum=0 |

处理序：锁 meta → 门禁 → 填头 → 出站。**meta > CSR**。禁 ARP。组地址/端口禁止写死。

TTL：默认 1；`ttl==0`（含 CSR 写 0）→ 1。`payload_len`>511 不发，丢+计。

## S1 `tcp_pay_strip`

| 口 | 说明 |
| --- | --- |
| 入 | AXIS-64 整帧（Eth/IP/TCP+payload），`tkeep`/`tlast` |
| 出 | AXIS-64 **仅 TCP payload**（无 L2–L4 头；含 TCP options 变长） |
| 行为 | 切穿剥头；角色 A；非 TCP/非法 → 丢+计数 |
| 禁 | 用 `udp_strip` / `tcp_pay_stub` 冒充本核 |
