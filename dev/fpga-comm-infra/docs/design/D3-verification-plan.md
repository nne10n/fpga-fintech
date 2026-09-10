# D3 验证计划

**状态：** G1 FROZEN。权威正文：`design/comm-infra-step1-design.md` §4。  
实现用例：`tb/`。先落 S2，S1 并行不互堵。

| ID | 查什么 | 用例 |
| --- | --- | --- |
| S2-H1 | 组地址/端口未写死；改 CSR/meta 后线上跟新 | `test_s2_h1_csr_then_meta` |
| S2-H2 | 默认 TTL=1；0→1 | `test_s2_h2_ttl_default_and_zero` |
| S2-H3 | 无 RX/IGMP 状态 | `test_s2_h3_no_rx_igmp` |
| S2-size | `payload_len`>511 不发/丢+计；&lt;512 正常 | `test_s2_size_511_ok_512_drop` |
| S2-A | ready 恒可收；MAC pause 不回灌 | `test_s2_role_a_ready_and_mac_pause` |
| S2-map | DA=RFC1112；禁 ARP | `test_s2_map_rfc1112_no_arp` |
| S1-H4 | 入 L2–L4 出纯 payload；非法丢+计 | `test_s1_h4_*` |
| S1-A | 入侧角色 A 不回灌 | `test_s1_role_a_ready` |

**不覆盖：** 完整 TCP 栈 / 握手 / 重传 / 乱序、IGMP、同卡 RX、N>1、业务策略。

命令见仓库根 `README.md`。
