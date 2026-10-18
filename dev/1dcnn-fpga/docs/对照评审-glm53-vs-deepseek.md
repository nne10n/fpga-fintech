# 对照评审：impl-glm53 vs impl-deepseek

| 项目 | 内容 |
| --- | --- |
| 文档编号 | QDR-1DCNN-FPGA-REVIEW-M1 |
| 版本 | V1.0 |
| 日期 | 2026-10-17（Asia/Shanghai） |
| 评审对象 | A：`/workspace/1dcnn-fpga/impl-glm53/`；B：`/workspace/1dcnn-fpga/impl-deepseek/` |
| 基线 | `docs/HANDOFF-实施约束.md`、`Phase0-FPGA需求规格书-定稿.md`、`Phase1-系统架构说明书.md`、`Phase1-模块微架构设计.md` |
| 范围 | M1 交付物质量对照（**非** csynth/上板实测） |

**已核实事实（评审引用，不另造数字）：**

| 项 | A (glm5.3) | B (deepseek) |
| --- | --- | --- |
| Bit-exact 报告 | 32/32 PASS | 36/36 PASS（csim） |
| BRAM 估计 | ≈80 KB | ≈101 KB |
| 延迟估计 | ≈319 μs @100 MHz | ≈760 μs @100 MHz；~450–507 μs @150 MHz |
| Vitis csynth | 本机均无，标 N/A / ESTIMATE | 同左 |
| REG_ID | `0x1DCN0101` → `0x1DC00101` | 同左 |

评分刻度：**1** = 严重缺口 / 误导；**2** = 弱；**3** = 达标但有明显瑕疵；**4** = 良好；**5** = 接近可进下一阶段。

---

## 1. 文档契约符合度

| | A | B |
| --- | --- | --- |
| **得分** | **4** | **4** |
| 证据 | `include/regs.h`；`README.md`（REG_ID / FEATURE / PACK_CH）；`scripts/weight_map.json` | `include/regs.h`；`README.md`；`vectors/weight_map.json` |

**共同点（合规）：**

- 寄存器偏移与位域对齐 Phase1 架构 §5.3：`REG_SCORE0..9` @ `0x080–0x0A4`，`STATUS[5]=feat_hotswap`，`WEIGHT_CTRL[1]=bank_sel` 预留。
- 量化顺序声明为 MAC → scale/shift → sat INT16 → ReLU；复位 `rst_n` 低有效；V1 无重叠、`PACK_CH=0`、单套权重。
- 文档歧义 `0x1DCN0101` 均编码为 `0x1DC00101` 并书面记录，未私改其它冻结项。

**差异与扣分点：**

| 点 | A | B |
| --- | --- | --- |
| Conv1 pad 表述 | `pad_left=pad_right=6`（合计 12）写入 `scripts/weight_map.json` | `pad_total=12`（`vectors/weight_map.json`）；README 写 `pad=12` |
| 几何等价性 | 对 Rout=512（K=16,S=4,Rin=2048）两边合计 pad=12，**形状一致** | 同左 |
| ERR 命名 | `ERR_SAT_STICKY=0x11` | `ERR_COMPUTE_SAT=0x11`（码值同微架构 §8，符号名不同） |
| 扩展寄存器 | RSVD 占位为主 | 另命名 `REG_NET_PROFILE` / `REG_ENGINE_MASK`（扩展钩子，未破坏冻结偏移） |

**小结：** 两边契约符合度相当；pad 表述不同但几何等价。未发现「私改接口」一票否决项。

---

## 2. 模块完备度（adc / fir / window / cnn / weight / axi / score / ps）

| | A | B |
| --- | --- | --- |
| **得分** | **3** | **4** |
| 证据 | `rtl/*.v`（7 文件，共 ~322 行）；`hls/cnn_engine.*`；`ps/driver/cnn_regs_drv.h` + `vote_alarm.c` | `rtl/*.{v,sv}`（4 文件，~479 行）；`hls/{cnn_engine,preprocess_fir,window_buffer,weight_mem}.*`；`ps/driver/1dcnn_uio.c` + `vote_alarm.c` |

| 模块 | A | B |
| --- | --- | --- |
| `adc_frontend` | RTL 有（薄 stub） | RTL 较完整（~123 行） |
| `preprocess_fir` | RTL stub（~44 行） | **HLS** `preprocess_fir.cpp`（有抽头/bypass 逻辑） |
| `window_buffer` | RTL stub（~34 行） | **HLS** `window_buffer.cpp`（ping-pong / 参数校验） |
| `cnn_engine` | HLS 核心 + 独立 `golden_cnn` | HLS 核心（`cnn_engine_infer`） |
| `weight_mem` | RTL stub | HLS 头 `weight_mem.h`（布局常量） |
| `axi_ctrl` | RTL stub（~75 行） | SystemVerilog 较完整（~192 行） |
| `score_path` | RTL stub（~33 行） | SV stub/半成品（~72 行） |
| `system_1dcnn_pl` | **结构性胶合 stub**：AXI/ADC 大量 `assign` 常值，未真正例化数据通路 | 有连线骨架；score/HLS IP 仍待集成 |
| PS | 头文件驱动 + `vote_alarm` 且 `make vote_test` 可跑 | UIO/mmap **C 驱动** + `vote_alarm`（无独立 make 目标） |

**小结：** A 七模块「文件齐全」但顶层与多数 RTL 停留在占位；B 前端/控制更深，FIR/window 走 HLS，更接近可综合骨架。两边均未完成可综合全链路连线 → 均未满 5。

---

## 3. Bit-exact 可信度

| | A | B |
| --- | --- | --- |
| **得分** | **2** | **5** |
| 证据 | `tb/run_bitexact.cpp` L115–126；`reports/bitexact_result.md`（32/32）；`hls/cnn_engine_tb.cpp` | `tb/csim_main.cpp`；`ref/fixed_point_cnn.py`；`reports/bitexact_result.md`（36/36） |

**A — 报告通过率高，方法偏弱：**

- `make bitexact` 对同一窗口调用两次 `cnn1d::infer_baseline`，比较 `scores` vs `scores2`（**自洽**），并写出 `.golden.bin`。
- 源码注释写明：「same code as golden … 0-bit vs itself (self-consistency)」。
- `hls/cnn_engine_tb.cpp` 仅打印 `v00_allzero` 分数，**未**对 32 组做 DUT↔golden 0-bit 比对。
- 因此「32/32 PASS」证明的是软件金标可重复，**不能**直接等同于「HLS 源与独立金标 bit-exact」。

**B — 方法符合 HANDOFF §5.2 意图：**

- Host csim 跑 `cnn_engine_infer`（DUT），与 Python `ref/fixed_point_cnn.py` 生成的分数 CSV 做 0-bit 比较。
- 36 组（≥32），含全零/饱和/随机等；权重/向量种子（42 / 20261017）可复现。
- 同一代码路径既是交付 HLS 源，又是被测对象 → **可信度明显高于 A**。

**小结：** 数字上 A 32/32、B 36/36 都绿；评审上 **B 显著更可信**。A 若要追平，需把 `cnn_engine` 对全部向量与 golden 文件做 0-bit 比对并写入报告。

---

## 4. 资源 / 延迟估计严谨度

| | A | B |
| --- | --- | --- |
| **得分** | **3** | **4** |
| 证据 | `reports/resource_estimate.md`；`reports/hls_csynth_summary.md` | 同路径 B 侧 |

**BRAM（均 PASS 估计）：**

- A ≈80 KB（~13% of device / 远低于 440 KB 预算）；breakdown：权重 22.5 + 特征~40 + window/FIFO~17 + 其它。
- B ≈101 KB（~23% of 440 KB 预算）；breakdown 更细（特征 ping-pong、line buf 分项），偏保守。

**延迟：**

| | A | B |
| --- | --- | --- |
| 方法 | 用总 MAC≈2.04M ÷ **64 MAC/cycle** → ≈31.9k cycles → **≈319 μs @100 MHz** | 先按层 II 保守估 ~214k cycles；再按 PE_M=16 修订 → **≈76k cycles → 760 μs @100 MHz / ~507 μs @150 MHz** |
| 与声明 PE 一致性 | README/csynth 写 `PE_M=16`、`PE_K_UNROLL=8`，延迟却按 **64** 有效 MAC/cycle，**偏乐观** | 与 PE_M=16 叙事一致；明确标出 @100 MHz 对 NFR-01 **偏紧/可能 FAIL** |
| NFR-01（≤500 μs） | 估计 PASS（依赖未证实的 64-MAC 有效吞吐） | @100 MHz 估计不达标；@150 MHz +调参声称可达 ≤450–507 μs |

**小结：** B 的估计更诚实、分层可追溯；A 的 BRAM 更省、延迟数字更漂亮，但并行度假设与 PE 参数不完全自洽。两边均为 **预综合估计**，进 M2 必须以 csynth 实测替换。

---

## 5. 代码可读与可复现（make）

| | A | B |
| --- | --- | --- |
| **得分** | **4** | **4** |
| 证据 | `Makefile`；`README.md`；`scripts/gen_*.py` | `Makefile`；`scripts/run_csim.sh`；`ref/` + `scripts/` |

| 项 | A | B |
| --- | --- | --- |
| 一键入口 | `make all` → weights + vectors + bitexact + reports | `make all` / `make csim` / `./scripts/run_csim.sh` |
| 额外目标 | `hls_csim_host`、`vote_test` | weights/vectors 依赖链清晰 |
| README | 工具版本、冻结项、歧义列表完整 | 工具、树、网络表、Vitis 步骤完整 |
| 向量可读性 | `.bin` + `manifest.json`，用例命名语义清晰（allzero/sat/realistic…） | CSV cases + manifest，多 4 组（36） |
| 金标独立源 | C++ `tb/golden_cnn.*`（与 bitexact 强绑定） | Python `ref/fixed_point_cnn.py`（跨语言对照） |

**小结：** 两边均可在无 Vitis 环境下复现软件级检查；可读性与工程卫生相当。A 多了 `vote_test` 一键；B 多了跨语言金标与更多向量。

---

## 6. 隔离合规

| | A | B |
| --- | --- | --- |
| **得分** | **5** | **5** |
| 证据 | README 明示勿触碰 `impl-deepseek/`；交叉引用检索仅见自身路径声明 | README 明示勿触碰 `impl-glm53/`；同左 |

- 工作区物理分离：`impl-glm53/` vs `impl-deepseek/`。
- 检索未发现读取对方源码/向量/报告的痕迹（仅禁止声明中的路径名）。
- REG_ID、权重字数（11504）等相同结论可归因于**同一只读文档集**，符合对照实验设计。

**小结：** 隔离合规，双方产物均可进入对照评分。

---

## 7. 风险与缺口

| | A | B |
| --- | --- | --- |
| **得分** | **3** | **3** |
| （分越高 = 风险披露与缺口管理越好；两边风险形态不同） | | |

### 共同缺口（阻断真实 M2/上板）

1. **无 Vitis HLS csynth / Vivado impl** → II、真实 latency、DSP/BRAM/LUT 均为估计。
2. **顶层未完成 HLS IP ↔ RTL 数据通路闭环**（A 更明显：AXI 端口常值绑死）。
3. **ADC PHY / 管脚 / 时序** 仍为 stub 级；板卡到货后需重绑。
4. **权重为合成数据**，非训练导出；上线前必须按同一 `weight_map` 替换真权重并重跑 bit-exact。

### A 特有风险

- Bit-exact **方法不足以支撑**「HLS 与金标对齐」结论；进 csynth 前易带着未暴露的定点偏差。
- 延迟按 64-MAC/cycle 估算，与声明 PE 不完全一致 → NFR-01 可能在实测时回退。
- RTL 广度优先、深度不足；集成工作量仍大。

### B 特有风险

- @100 MHz 分析延迟 **≈760 μs**，相对 NFR-01（≤500 μs） openly 偏紧；依赖 150 MHz 或提高并行度。
- BRAM 估计高于 A（≈101 vs ≈80 KB），仍远低于预算，但特征缓冲假设需 csynth 验证。
- FIR/window 在 HLS、部分 glue 在 SV，跨语言集成接口需在 BD 阶段对齐。
- `make` 未覆盖 `vote_alarm` 单测；PS 驱动需目标机验证。

### 文档遗留（双方已记录，主理人待裁定）

- `REG_ID` 助记符 `0x1DCN0101` 非法 hex → 现行双方均为 `0x1DC00101`；建议 Phase0/1 **书面修订**统一编码，避免后续工具链脚本歧义。

---

## 8. 分项对照总表

| 维度 | A (glm5.3) | B (deepseek) | 权重感受 |
| --- | --- | --- | --- |
| 文档契约符合度 | 4 | 4 | 高 |
| 模块完备度 | 3 | 4 | 高 |
| Bit-exact 可信度 | 2 | 5 | 高 |
| 资源/延迟估计严谨度 | 3 | 4 | 高/中 |
| 代码可读与可复现 | 4 | 4 | 中 |
| 隔离合规 | 5 | 5 | 一票否决项：均通过 |
| 风险与缺口管理 | 3 | 3 | 中 |
| **加权印象分（粗算）** | **~3.3** | **~4.1** | — |

---

## 9. 总评与推荐

**总评：** 在相同文档约束与隔离条件下，**B（impl-deepseek）整体更接近可进入 M2/csynth**：独立 Python 金标 + DUT 0-bit csim（36/36）可信，模块与延迟分析更扎实；A（impl-glm53）交付面更「文件齐」、延迟/BRAM 数字更乐观，但 bit-exact 实为自洽测试，RTL 顶层仍是占位胶合，进综合前需先补真正的 DUT↔golden 对齐。

**推荐主路径（进 M2/csynth）：以 B 为优先综合候选**；A 作为对照保留，但须先修复 bit-exact 方法后再谈并行度优势是否成立。

### 建议下一步（2–3 条）

1. **主理人书面修订 REG_ID**：把 `0x1DCN0101` 正式定为 `0x1DC00101`（或其它合法编码），通知双方同步（已实施值一致，仅需文档落槌）。
2. **优先对 B 跑 Vitis HLS csynth**（`hls/run_hls.tcl`，100 MHz 与 150 MHz 各一档）：用实测 latency/II/DSP/BRAM 替换估计；若 100 MHz 不达 NFR-01，按 B 报告路径扫 `PE_M` / 时钟。
3. **要求 A 在进 csynth 前补强验收**：`cnn_engine` 对全部 ≥32 向量与 `.golden.bin`（或独立金标）做 0-bit 比对写入 `bitexact_result.md`；并修正延迟估计与 `PE_M`/`PE_K_UNROLL` 假设一致。可选：两边用**同一训练导出权重 blob**重跑，消除合成权重差异后再比分数数值（当前分数不可跨实现直接比）。

---

## 10. 修订历史

| 版本 | 日期 | 说明 |
| --- | --- | --- |
| V1.0 | 2026-10-17 | 首版对照评审（M1 / 预 csynth） |
