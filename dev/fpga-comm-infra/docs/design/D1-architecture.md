# D1 架构

**状态：** G1 FROZEN。权威正文：`design/comm-infra-step1-design.md` §2（勿另写一份语义）。  
边界：`docs/boundary/通信基建-边界单.md` @ `3fb73e3`。

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
        │ 产物 payload <512B
        ▼
 ┌──────────────┐
 │ udp_mcast_tx │  S2（优先）
 └──────┬───────┘
        ▼
     MAC TX AXIS-64
```

- **分核：** S1 / S2 独立；TCP 状态不进组播核；本步不绑死中间应用。
- **时钟：** `sys_clk` / `sys_rst_n`；异钟 MAC 才例化 catalog `tx_afifo`。
- **背压：** 两核均为角色 A（不回灌上游）。
- **实现序：** 先 S2 `udp_mcast_tx`，再 S1 `tcp_pay_strip`。
