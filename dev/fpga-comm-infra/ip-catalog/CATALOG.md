# IP 登记表

权威约束：`design/comm-infra-step1-design.md`（G1 FROZEN）A4 / §5 / §6.5。

| 名称 | 类型 | 时钟 | 本步例化 | 备注 |
| --- | --- | --- | --- | --- |
| `tx_afifo` | async FIFO（真正 CDC） | wr/rd 异钟 | **否** | 仅当 MAC TX 相对 `sys_clk` 异钟时才允许例化；见 `tx_afifo/` |
| （同钟 scratch） | 核内推断阵列 | `sys_clk` | 允许 | `udp_mcast_tx` / `tcp_pay_strip` 单钟包缓冲，**不是** CDC，不得替换成 `tx_afifo` |

未登记的外部 FIFO/RAM 不得例化。
