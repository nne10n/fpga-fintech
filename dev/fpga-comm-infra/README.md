# FPGA 通信基建（第一步）

仓库 slug：**fpga-comm-infra**

| 文件 | Commit | 说明 |
| --- | --- | --- |
| [`design/comm-infra-step1-design.md`](design/comm-infra-step1-design.md) | `efa5e23` | **G1 FROZEN 总稿**（权威；**不是** `docs/comm-infra-step1-design.md`） |
| [`docs/boundary/通信基建-边界单.md`](docs/boundary/通信基建-边界单.md) | `3fb73e3` | G0 边界单（本仓有效） |
| [`docs/通信基建-G1决策摘要.md`](docs/通信基建-G1决策摘要.md) | `f95fac2` | 决策摘要（细节以总稿+边界单为准） |
| [`docs/design/`](docs/design/) | — | D1–D4 分章索引，不另 freeze 语义 |

## 本步交付

1. **S2** `udp_mcast_tx`：UDP 组播 TX（优先）
2. **S1** `tcp_pay_strip`：L2–L4 → TCP payload（独立核）

单钟 `sys_clk` / `sys_rst_n`。异钟 MAC 才允许例化 catalog 中的 `tx_afifo`（本步不例化）。

## 仿真

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r tb/requirements.txt

# S2  (D3: H1/H2/H3/size/A/map  + payload_len=1)
make -C tb/udp_mcast_tx

# S1  (D3: H4/A)
make -C tb/tcp_pay_strip

# 两者
make -C tb all
```

通过标准见 `docs/path-inventory.md` 与各 test 函数名。

本地实测（Icarus 12.0 + cocotb 1.9.2）：

| 套件 | 命令 | 结果 |
| --- | --- | --- |
| S2 | `make -C tb/udp_mcast_tx` | **TESTS=7 PASS=7 FAIL=0** |
| S1 | `make -C tb/tcp_pay_strip` | **TESTS=5 PASS=5 FAIL=0** |

## 明确不做

完整 TCP 栈、策略/订单簿、N>1、IGMP、同卡 RX、组地址 ARP、写死组地址/端口。
