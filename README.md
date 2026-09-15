# FPGA 金融科技

`nne10n` 的 FPGA 金融科技工作仓库：调研稿在 `research/`，开发和验证代码在 `dev/`。

私有仓库。资料截止 2026-09。

## 调研

| 主题 | 路径 | 说明 |
| --- | --- | --- |
| FPGA 在金融科技的应用与前沿 | [`research/fpga-fintech-overview/`](research/fpga-fintech-overview/) | 行情、TCP、风控、L1；含汇报 HTML |
| FPGA 硬件行情订单簿 | [`research/hardware-orderbook/`](research/hardware-orderbook/) | 建簿产品与设计思路 |
| AI Agent 在 FPGA 开发与验证 | [`research/ai-agent-fpga-verification/`](research/ai-agent-fpga-verification/) | 可复制闭环，不是端到端自治签核 |
| Siemens vs Synopsys 仿真工具 | [`research/eda-sim-siemens-synopsys/`](research/eda-sim-siemens-synopsys/) | 数字功能仿真对比笔记 |
| 券商 FPGA 行情卡（UL3524 / X1100） | [`research/md-card-ul3524/`](research/md-card-ul3524/) | 规格、模块设计、订单簿/L0/L1 DDR、X1100 适配与 Yusur NDPP 计划 |
| FPGA / 数字 IC 可复制 Skill 盘点 | [`research/fpga-skill-inventory/`](research/fpga-skill-inventory/) | Cursor/Agent Skills 可借鉴来源与缺口 |
| SV/Verilog 编码 Skill 调研 | [`research/sv-verilog-coding-skills/`](research/sv-verilog-coding-skills/) | 本地三件套够用性、公开基线对照与缺口一页纸 |
| 可粘贴 IP/可复用模块登记册调研 | [`research/ip-module-registry/`](research/ip-module-registry/) | catalog 方案：index + modules md，供 RTL 例化 |
| 通信基建第一步（G1） | [`research/comm-infra-g1/`](research/comm-infra-g1/) | 边界单、G1/G2 决策摘要、FROZEN 总稿；RTL 见 dev |

每个主题里 `调研汇报.md` / `调研汇报-初稿.md` / `规格-v1.md` 是中文稿，`briefing.md` 是对应英文底稿（有则）。

## 开发

| 工程 | 路径 | 说明 |
| --- | --- | --- |
| 行情卡 RTL/仿真 | [`dev/fpga-md-card/`](dev/fpga-md-card/) | UDP strip、深/沪 Binary+FAST、仲裁、event merge、订单簿 L0/L1、X1100 适配、组播/DMA |
| TCP 报单发送核 | [`dev/fpga-order-tcp-tx/`](dev/fpga-order-tcp-tx/) | AXI-Stream 64b TCP client + order buffer |
| 通信基建（TCP strip + UDP 组播 TX） | [`dev/fpga-comm-infra/`](dev/fpga-comm-infra/) | S1 `tcp_pay_strip`、S2 `udp_mcast_tx`、独立 TB（G1 FROZEN / G2 有条件放行） |
