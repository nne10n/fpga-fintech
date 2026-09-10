# 路径清单（G1 FROZEN 实现）

- 方案总稿：**`design/comm-infra-step1-design.md`** @ `efa5e23`（**不是** `docs/comm-infra-step1-design.md`）
- 边界单：`docs/boundary/通信基建-边界单.md` @ **`3fb73e3`**（本仓有效）
- 决策摘要：`docs/通信基建-G1决策摘要.md`
- 不引用 fpga-md-card 文本为真源

| 路径 | 角色 |
| --- | --- |
| `design/comm-infra-step1-design.md` | G1 FROZEN 总稿（权威） |
| `docs/boundary/通信基建-边界单.md` | G0 边界单 @ `3fb73e3` |
| `docs/通信基建-G1决策摘要.md` | G1 决策摘要 |
| `docs/design/D1-architecture.md` | D1 索引 → 总稿 §2 |
| `docs/design/D2-interface-contract.md` | D2 索引 → 总稿 §3 |
| `docs/design/D3-verification-plan.md` | D3 索引 → 总稿 §4 + `tb/` |
| `docs/design/D4-risks-assumptions.md` | D4 索引 → 总稿 §1 |
| `ip-catalog/README.md` | catalog 规则：同钟禁假 CDC |
| `ip-catalog/CATALOG.md` | 登记表；`tx_afifo` 本步不例化 |
| `ip-catalog/tx_afifo/README.md` | 异钟 FIFO 占位 |
| `rtl/udp_mcast_tx/udp_mcast_tx.sv` | S2 组播 TX 核 |
| `rtl/tcp_pay_strip/tcp_pay_strip.sv` | S1 TCP payload strip 核（独立，非 stub） |
| `tb/common/pkt.py` | 组帧/AXIS 节拍 |
| `tb/udp_mcast_tx/test_udp_mcast_tx.py` | S2 D3：H1/H2/H3/size/A/map + len=1 → **7 PASS** |
| `tb/tcp_pay_strip/test_tcp_pay_strip.py` | S1 D3：H4/A → **5 PASS** |
| `tb/Makefile` | `make s2` / `make s1` / `make all`（无 `sim-top` / `x1100`） |

未例化：`tx_afifo`（单钟 `sys_clk`，A4）。无 IGMP / RX / 完整 TCP 栈。

## G2 已知非阻塞（不挡合并）

- 本步无集成 `sim-top` / `x1100` 目标；待 top 存在后的集成里程碑再加。
- 空 TCP payload、`payload_len=0` TB 缺口已知；下轮补用例，不扩 scope。
