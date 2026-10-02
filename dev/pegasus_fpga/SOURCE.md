# Pegasus 拓扑 — RTL / TB / golden model

来源：OneDrive `workbench/001_Research/pegasus_fpga/`（与设计稿同批，约 2026-10-01）。

| 路径 | 说明 |
| --- | --- |
| `rtl/pegasus_topo.v` | 可综合邻居生成器 / 耦合判定（P16 packed 地址） |
| `ref/pegasus_ref.py` | golden model（对齐 dwave-networkx offsets_index=0） |
| `tb/tb_pegasus.v` | iverilog testbench |
| `tb/gen_vectors.py` | 向量生成 |
| `tb/vectors_cp.txt` / `vectors_nb.txt` | 全量验证向量 |

设计文档见 [`../../research/pegasus_fpga/`](../../research/pegasus_fpga/)。

未纳入：`tb_pegasus.vvp`、`__pycache__/`。

镜像日期：2026-10-02（weekday product sync）。
