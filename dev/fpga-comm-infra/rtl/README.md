# rtl

可综合 SystemVerilog。家规：`sys_clk` / `sys_rst_n`；三段式 FSM；`i_` / `o_` / `w_` / `r_`；CSR `cfg_*`。

| 模块 | 路径 | 说明 |
| --- | --- | --- |
| `udp_mcast_tx` | `udp_mcast_tx/udp_mcast_tx.sv` | S2 组播 TX；角色 A；DA=RFC1112；无 ARP |
| `tcp_pay_strip` | `tcp_pay_strip/tcp_pay_strip.sv` | S1 独立剥头核；角色 A；非法丢+计数 |

同钟核内 scratch 不是 CDC。`tx_afifo` 见 `ip-catalog/`，本步不例化。
