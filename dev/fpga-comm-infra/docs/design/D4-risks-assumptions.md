# D4 风险与假设

**状态：** G1 FROZEN。权威正文：`design/comm-infra-step1-design.md` §1。  
边界假设表：`docs/boundary/通信基建-边界单.md` §6 @ `3fb73e3`。

| ID | 内容 |
| --- | --- |
| A1 | S1：入 L2–L4 帧，出 TCP payload；无建连/重传 |
| A2 | S1/S2 **分核**；应用可在中间；本步不绑死应用 |
| A3 | S2 组播契约；`payload_len`∈**[1,511]** |
| A4 | `sys_clk` / `sys_rst_n`；异钟 MAC 才 afifo（同钟禁止假 CDC） |
| A5 | 产物仓 `melon5253/fpga-comm-infra` |
| H1 | 组地址/UDP 端口 CSR/meta 参数化，**禁写死** |
| H2 | TTL 默认 **1**；`ttl==0`/CSR0 → 当 1 |
| H3 | **无同卡 RX / 无 IGMP** |
| H4 | 入侧 = L2–L4 网络帧；若实际为 TCP segment → 变更单 |

**风险（不扩 scope）：** 角色 A 在 MAC pause 时丢包而非回压；同钟 scratch 不得换成 `tx_afifo`；写死组地址/端口为硬伤。
