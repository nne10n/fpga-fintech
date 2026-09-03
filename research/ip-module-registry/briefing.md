# 可粘贴 IP/可复用模块登记册（给 FPGA 领域 skill 专家）

调研日：2026-09-02。目标：仓库内 catalog，供 AI 写 RTL 时**从目录实例化，禁止凭记忆发明端口**。本文只引用已打开的活 URL。

给专家今晚可直接写：`SKILL.md` + 目录模板 + 一条填满的 `axis_register` 记录。不要把 IEEE 1685 XML 当主存储。

---

## 0. 先给结论（今晚怎么落）

**默认方案：`catalog/index.yaml`（或 `.json`）+ `catalog/modules/<name>.md`，每条 md 含可粘贴 SV 例化 stanza。**

- `SKILL.md` 只放 SEARCH/REGISTER/UPDATE 规程与字段契约，不塞全库端口表。
- Agent Skills 规范：启动只加载 YAML frontmatter；正文触发后加载；`references/` 按需。见 https://github.com/agentskills/agentskills/blob/main/docs/specification.mdx
- 同类 FPGA skill 包（oh-my-fpga、FPGA-Agent）**没有** IP-registry skill；最接近的是 wrapper 生成 skill，不是 in-repo 目录。

---

## 1. 做法调查（对 LLM agent：上下文 / grep / 端口幻觉）

| 做法 | 代表 | 对 LLM 优点 | 对 LLM 缺点 |
|---|---|---|---|
| 一模块一 md | OpenTitan `hw/ip/<blk>/README.md` + 生成的 `doc/interfaces.md` | grep 友好；可塞 SV 模板、禁止误用、CDC | 无总索引时要扫目录；README 易与 RTL 漂移 |
| 一大表 | OpenTitan `hw/ip/README.md` 一句话表 | 索引极短，适合 SKILL 里“先读这个” | 无端口/时序，不能当实例化源 |
| YAML/JSON 索引 + md 体 | Agent Skills 三层；Topwrap 也用 YAML 描述核 | 索引进上下文、正文按需；CI 易校验 | 需纪律：索引与 md 双写 |
| IP-XACT IEEE 1685 | Accellera schema、Kactus2、Vivado `component.xml` | 端口/参数/busInterface/portMap 机器可读 | 对 LLM 太重；无粘贴 SV；时序是 qualifier/约束不是握手波形 |
| FuseSoC `.core` CAPI2 | `name` VLNV、filesets、parameters、targets | 依赖与文件集清晰；参数有 description | **无端口表、无握手/时钟域** |
| XCI / `component.xml` | UG1118 打包输出 | 厂商工具权威 | **禁止手改**；XCI 不是 SV 例化；Vivado 多用 1685-2009 |
| `_hw.tcl` / Qsys | Intel Platform Designer | 接口+associatedClock 明确 | Tcl 非 SV；不适合当粘贴模板 |

### A. Cursor/Claude SKILL.md：有没有 IP catalog skill？

**oh-my-fpga：没有 IP-registry / IP-catalog skill。**  
仓库 https://github.com/LNC0831/oh-my-fpga ，README https://raw.githubusercontent.com/LNC0831/oh-my-fpga/main/README.md 。v1 共 13 个 skill，目录 https://github.com/LNC0831/oh-my-fpga/tree/main/skills 实际列出：`timing-closure`, `cdc-audit`, `constraints-authoring`, `full-flow-demo`, `sim-bringup`, `coverage-closure`, `lint-triage`, `qor-report`, `utilization-reduction`, `power-optimization`, `zynq-bringup`, `ila-hw-debug`, `bitstream-program`。方法论层，不维护可例化模块目录。

**FPGA-Agent / FPGA-Agent-skills：没有 IP-registry skill。**  
https://github.com/Shinei-Nouzen-Arch/FPGA-Agent-skills 指向 https://github.com/Shinei-Nouzen-Arch/FPGA-Agent 。README https://raw.githubusercontent.com/Shinei-Nouzen-Arch/FPGA-Agent/main/README.md 列 8 个 skill：`vitis-hls-synthesis`, `vivado-synth`, `vivado-constraints`, `vivado-impl`, `vivado-analysis`, `vivado-debug`, `vivado-sim`, `vivado-tcl`。结构是 `SKILL.md` + `REFERENCE.md` + `examples/`。例：https://raw.githubusercontent.com/Shinei-Nouzen-Arch/FPGA-Agent/main/vivado-synth/SKILL.md 是综合策略，不是 IP 表。

**最接近的现成 skill（仍不是 catalog）：**  
https://raw.githubusercontent.com/babyworm/rtl-agent-team/main/skills/rtl-ip-instantiate/SKILL.md  
- 从 `docs/ip/{ip_name}.xml`（IP-XACT）或 datasheet **读端口再写 wrapper**，禁止凭记忆。  
- 输出 `rtl/ip_wrappers/{ip_name}_wrapper.sv`；未连端口必须 `// TIED:`。  
- 有 `scripts/gen_instantiation.py` 从 vendor 模块头确定性生成骨架。  
- **没有** in-repo 模块登记册；是一次性包装流程。可抄其“先读描述符、禁止自动截宽、halt on missing descriptor”。

Agent Skills 字段约束：`name`/`description` 必填；description ≤1024。https://github.com/agentskills/agentskills/blob/main/docs/specification.mdx

### B. IP-XACT（IEEE 1685）+ Kactus2：真实字段

官方入口：https://www.accellera.org/downloads/standards/ip-xact  
Schema：http://www.accellera.org/XMLSchema/IPXACT/1685-2022/ （含 `component.xsd`, `port.xsd`, `busInterface.xsd`, `abstractionDefinition.xsd`, `busDefinition.xsd`）  
User Guide PDF：https://www.accellera.org/images/downloads/standards/ip-xact/IPXACT-2022_user_guide.pdf  
Leon2 示例 zip（Accellera 提供）：同一 downloads 页。  
Kactus2：https://github.com/kactus2/kactus2dev （1685-2014 与 1685-2022）；例库 https://github.com/kactus2/ipxactexamplelib  
可读字段解说（含 XML 片段）：https://antmicro.github.io/topwrap/developers_guide/ipxact-design.html  
Vivado 侧小 `component.xml`：https://raw.githubusercontent.com/Digilent/vivado-library/master/ip/rgb2dvi/component.xml （spirit 2009 风格 VLNV `digilentinc.com:ip:rgb2dvi:1.4`）

**component 里 LLM 真正用得上的：**

- **VLNV**：`vendor` / `library` / `name` / `version`
- **model/ports**：物理口 `name`；`wire/direction`（in/out/inout/phantom）；`vectors/left/right`（可引用参数表达式）
- **parameters** 与 **moduleParameters** 两层（IP-XACT 参数 ≠ 一定等于 HDL parameter）
- **fileSets**：源文件 + `fileType`
- **busInterfaces/busInterface**：`busType` VLNV、`abstractionRef`、`portMaps`（logicalPort ↔ physicalPort）、角色 `initiator`/`target`（2022；旧称 master/slave）
- **catalog**：列出其它 IP-XACT 文件的 VLNV+路径

**abstractionDefinition 与“时序”：** User Guide 写明 wire 上 `qualifier`：`isClock` / `isReset` / `isAddress` / `isData`；每侧 `onInitiator`/`onTarget`：`presence`（required/optional/illegal）、`width`、`direction`、`defaultValue`。Topwrap 文明确：时钟/复位靠 qualifier，**不是** valid/ready 波形。周期级 timingConstraint / clockDriver 在 **component port driver**（IEEE 草案/旧 SPIRIT 文档也这么分），不是“握手 vs 脉冲”语义。

**不要发明 XML 标签。** 写 skill 时引用 schema/User Guide，不要手搓一套伪 IP-XACT。

### C. FuseSoC `.core` YAML（已抓真实文件）

文档：https://fusesoc.readthedocs.io/en/stable/user/build_system/core_files.html  
真实文件：https://raw.githubusercontent.com/olofk/fusesoc/master/tests/userguide/blinky/blinky.core  

关键键（CAPI2）：

```
CAPI=2:
name: fusesoc:examples:blinky:1.0.0    # VLNV vendor:library:name:version
description: ...
filesets: { rtl: { files: [...], file_type: systemVerilogSource } }
targets: { default: { filesets, toplevel, parameters } }
parameters:
  clk_freq_hz:
    datatype: int
    description: Frequency of the board clock, in Hz
    paramtype: vlogparam
```

概述：https://fusesoc.readthedocs.io/en/stable/user/overview.html — 一个 core 是可复用 IP（文档举例就是 FIFO）。  
FuseSoC 源码注释仍写 `# FIXME: Add IP-XACT support`：https://github.com/olofk/fusesoc/blob/main/fusesoc/capi2/core.py  
Kactus2 展示仓：https://github.com/olofk/de0_nano_ipxact  

**缺陷：`.core` 不描述端口、不描述握手、不描述 CDC。** 只能当 fileset/依赖/参数层，不能当例化源。

### D. AMD XCI / component.xml / VLNV；Intel Qsys `_hw.tcl`

**AMD**

- UG1118 Creating and Packaging Custom IP（2026.1，2026-07-23）：https://docs.amd.com/r/en-US/ug1118-vivado-creating-packaging-custom-ip/Outputs-from-IP-Packager  
  输出：`component.xml`（IP-XACT）、`xgui/*.tcl`、按用途分目录。**“IP packager output files are not intended for manual editing.”**
- Identification / VLNV：https://docs.amd.com/r/en-US/ug1118-vivado-creating-packaging-custom-ip/Identification  
  Vendor, Library, Name, Version 唯一标识 catalog；另有 display name、description、categories。
- UG896 Designing with IP — packager 基于 IEEE 1685：https://docs.amd.com/r/en-US/ug896-vivado-ip/IP-Packager （及 PDF https://www.xilinx.com/support/documents/sw_manuals/xilinx2022_2/ug896-vivado-ip.pdf）
- UG1119 tutorial；UG994 bus interface：https://docs.amd.com/r/en-US/ug994-vivado-ip-subsystems/Using-Bus-Interfaces  
- XCI：工程里某次 IP **定制实例**（参数值），不是可复用 RTL 模板。例化走 `create_ip -vlnv ...`，不是粘贴 SV。

**Intel / Altera**

- **不要用 683623 当 Qsys 文档。** 现网 683623 = AN 745 DisplayPort 板级指南：https://docs.altera.com/r/docs/683623/current/an-745-design-guidelines-for-displayport-ip-interface/design-guidelines-for-displayport-ip-interface  
- 当前 Platform Designer（原 Qsys）组件：**683609** Quartus Prime Pro UG：https://docs.altera.com/r/docs/683609/26.1/quartus-prime-pro-edition-user-guide/creating-platform-designer-components  
  Component Editor 写 `_hw.tcl`：https://docs.altera.com/r/docs/683609/25.1.1/quartus-prime-pro-edition-user-guide/creating-ip-components-in-the-component-editor  
  `_hw.tcl` 声明 SV 接口：https://docs.altera.com/r/docs/683609/26.1/quartus-prime-pro-edition-user-guide/declaring-systemverilog-interfaces-in-_hw.tcl  
- Standard 版 Tcl 参考 **683364**：https://docs.altera.com/r/docs/683364/18.1/intel-quartus-prime-standard-edition-user-guide-platform-designer/component-interface-tcl-reference  
- `_hw.tcl` 真实模式：`add_interface clk clock end` + `associatedClock` + `add_interface_port`；Avalon-ST 有 `readyLatency`（这是厂商对握手时序的字段，仍不是 SV 模板）。

### E. Corundum / alexforencich README 接口表；OpenTitan 模板

**verilog-axis**（含 FIFO / register slice）：https://raw.githubusercontent.com/alexforencich/verilog-axis/master/README.md  
模块头（权威端口）：https://raw.githubusercontent.com/alexforencich/verilog-axis/master/rtl/axis_register.v  

README「Common signals」实表：

| 信号 | 含义 |
|---|---|
| tdata | Data（宽 DATA_WIDTH） |
| tkeep | Data word valid（KEEP_WIDTH） |
| tvalid | Data valid |
| tready | Sink ready |
| tlast | End-of-frame |
| tid / tdest / tuser | 侧带 |

Handshake：`tvalid && tready` 完成一次 transfer。ASCII 波形在同一 README「AXI Stream Interface Example」。  
`axis_register`：`REG_TYPE` 0 bypass / 1 simple（插入 bubble）/ 2 skid（无 bubble）。时钟 `clk`，复位 `rst` **高有效**。

**verilog-axi**：https://raw.githubusercontent.com/alexforencich/verilog-axi/master/README.md — Common signals 是 AXI 通道清单 + ASCII 读写波形，**没有**逐模块 Markdown 端口表；端口在 `rtl/*.v` 头。

**Corundum** 才是“文档里真有端口表”的样板：https://docs.corundum.io/en/latest/modules/mqnic_app_block.html  
- 每接口：Signal / Dir / Width / Description  
- 明确时钟域：`clk` 核心；`*_axis_direct_*` 同步 MAC TX/RX clk；`*_axis_sync_*` 与 `*_axis_if_*` 同步 core clk  
- Handshake：AXI-Stream valid/ready；DMA desc 也是 valid/ready；部分 RX 可关 tready 改为丢包（`AXIS_RX_USE_READY`）

**OpenTitan**

- 块文档模板：https://opentitan.org/book/doc/contributing/doc/example_ip_block.html  
  `README.md` 概述 → `doc/theory_of_operation.md` → `doc/programmers_guide.md` → **生成的** `doc/interfaces.md` / `doc/registers.md`（CMDGEN + `regtool.py --interfaces`）
- Comportability：https://opentitan.org/book/doc/contributing/hw/comportability/index.html  
- 目录一句话表：https://raw.githubusercontent.com/lowRISC/opentitan/master/hw/ip/README.md  
- 真实接口表：https://raw.githubusercontent.com/lowRISC/opentitan/master/hw/ip/uart/doc/interfaces.md  
  Primary Clock `clk_i`；总线 `tl`；pin `rx`/`tx`；inter-module 表含 Type `uni`/`req_rsp`、Act `req`/`rcv`/`rsp`

启示：人读概述 + **机器生成接口表**， combats README 过期。Agent 目录应对齐 RTL 头或解析器，而不是纯手写。

### F. 仓内 `ips/` / `rtl/README` 目录

- OpenTitan `hw/ip/`：索引表 + 每块 README。https://github.com/lowRISC/opentitan/tree/master/hw/ip  
- ZipCPU wb*：https://github.com/ZipCPU/wb2axip/blob/master/README.md 是**散文模块目录**（每核一段 + 源路径），端口在 `rtl/*.v` 注释端口列表，例如 https://github.com/ZipCPU/zipcpu/blob/master/rtl/ex/wbpriarbiter.v  
- liteeth：https://raw.githubusercontent.com/enjoy-digital/liteeth/master/README.md **没有**端口表；自陈 “add more documentation”。接口在 Python（`interface in ["crossbar","wishbone","hybrid"]`）。**不能当 SV 例化源。**  
- litepcie：同类 LiteX 生成核，README 同样不是粘贴级端口表。

---

## 2. 推荐目录（默认拍板）

放在 skill 旁或仓库 `hw/` 下，二选一，**不要两个真相**：

```
skills/ip-module-registry/
  SKILL.md                 # 规程 + 字段契约；禁止发明端口
  references/fields.md     # 可选：字段释义（按需加载）
  scripts/
    check_catalog.py       # CI：stanza 端口 vs RTL 模块头
catalog/
  index.yaml               # 短记录：id, one_liner, path, tags, status
  modules/
    axis_register.md       # 完整记录 + 可粘贴 SV
    sync_fifo.md
```

若仓库已有 `rtl/`，则 `catalog/modules/*.md` 里 `source:` 指向真实 SV，**不要复制第二份 RTL**。

**为何不是单一大表：** 一张表塞不下 5 项必填 + 波形 + 禁误用；上下文会爆。  
**为何不是纯 IP-XACT：** agent 要 `u_foo ( .clk(clk), ...)`；XML 不能直接粘。  
**为何不是只靠 FuseSoC：** 没有端口。可另存 `foo.core` 给构建，登记册仍用 md。  
**为何 index.yaml + md：** 对齐 Agent Skills 分层；SEARCH 只 grep/读 index；命中后再 Read 一条 md。oh-my-fpga/FPGA-Agent 已证明“短 SKILL + 按需 REFERENCE/examples”。

`index.yaml` 建议键（保持短）：

```yaml
modules:
  - id: axis_register
    one_liner: "AXI-Stream 寄存器切片（bypass/simple/skid）"
    file: catalog/modules/axis_register.md
    source: third_party/verilog-axis/rtl/axis_register.v
    tags: [axis, pipeline, timing]
    vendor: in-house   # 或 vendor
    verify: cocotb
```

---

## 3. 字段清单 + 填满样例

### 3.1 五条用户必填

1. **可粘贴 SystemVerilog 例化模板**（完整端口，禁止 `.*` 作登记源）
2. **一行功能**
3. **参数 + 接口定义**（参数名/类型/默认；接口名与端口清单）
4. **参数含义**
5. **接口时序**：pulse vs handshake；所属时钟域

### 3.2 建议加抄的额外字段

| 字段 | 为何 |
|---|---|
| `id` / `module_name` | grep 主键，等于 SV module 名 |
| `vlnv` 可选 | 与 FuseSoC/IP-XACT 对齐，不强制 XML |
| `source_path` | 权威 RTL；CI 对这个文件 |
| `clocks[]` | 名字、边沿、域标签 |
| `resets[]` | 名字、**极性**、同步/异步、关联时钟 |
| `cdc_notes` | 无 CDC 也要写 “none — 单时钟” |
| `latency_cycles` | 含 bubble 与否（对照 REG_TYPE） |
| `resource_est` | LUT/FF/BRAM 量级或 “slice-only” |
| `origin` | in-house / vendor / third-party |
| `verify_status` | none / lint / sim / formal / silicon |
| `forbidden` | 禁止误用（乱接复位极性、当 CDC FIFO 用等） |
| `protocol` | axis / axi4 / wb / pulse / csr |
| `ready_latency` | 若 Avalon-ST；AXI-Stream 通常 0 |
| `tieoffs` | 可选端口默认绑什么 |
| `related` | 异步 FIFO、width adapter |
| `last_synced_rev` | git blob 或日期，CI 可写 |

### 3.3 填满样例：`axis_register`（端口来自已抓 RTL，不是记忆）

权威：https://raw.githubusercontent.com/alexforencich/verilog-axis/master/rtl/axis_register.v  
行为：https://raw.githubusercontent.com/alexforencich/verilog-axis/master/README.md （`axis_register` 节 + Common signals + 波形）

```markdown
# axis_register

## one_liner
AXI4-Stream 数据通路寄存器：可选 bypass / 简单缓冲（有气泡）/ skid（满吞吐无气泡），用于拉长布线。

## origin / source
- origin: third-party
- source_path: <repo-relative>/axis_register.v
- upstream: https://github.com/alexforencich/verilog-axis/blob/master/rtl/axis_register.v
- verify_status: cocotb in upstream (repo CI badge on README)
- vlnv: (none in-repo; optional local: local:axis:axis_register:0.0.0)

## clocks / resets
| name | dir | polarity | domain | notes |
|------|-----|----------|--------|-------|
| clk  | in  | rising   | axis   | 唯一时钟 |
| rst  | in  | **active-high** | axis | 同步到 clk；不是 rst_n |

cdc_notes: none — s_axis 与 m_axis 同一 `clk`。跨时钟用 `axis_async_fifo`，禁止把本模块当 CDC。

## parameters
| name | default | meaning |
|------|---------|---------|
| DATA_WIDTH | 8 | tdata 位宽 |
| KEEP_ENABLE | (DATA_WIDTH>8) | 是否传播 tkeep；关则内部视为全 1 |
| KEEP_WIDTH | ((DATA_WIDTH+7)/8) | tkeep 宽 |
| LAST_ENABLE | 1 | 是否传播 tlast |
| ID_ENABLE | 0 | 是否传播 tid |
| ID_WIDTH | 8 | tid 宽 |
| DEST_ENABLE | 0 | 是否传播 tdest |
| DEST_WIDTH | 8 | tdest 宽 |
| USER_ENABLE | 1 | 是否传播 tuser |
| USER_WIDTH | 1 | tuser 宽 |
| REG_TYPE | 2 | 0=bypass 组合直通；1=simple 缓冲（下游反压时插入 bubble）；2=skid 满吞吐 |

## interfaces
protocol: axi4-stream handshake（一次 beat = tvalid && tready）。非 pulse。
ready_latency: 0（标准 AXI-Stream）。

### s_axis (slave, domain=axis/clk)
s_axis_tdata[DATA_WIDTH-1:0] in; s_axis_tkeep[KEEP_WIDTH-1:0] in;
s_axis_tvalid in; s_axis_tready out; s_axis_tlast in;
s_axis_tid[ID_WIDTH-1:0] in; s_axis_tdest[DEST_WIDTH-1:0] in; s_axis_tuser[USER_WIDTH-1:0] in

### m_axis (master, domain=axis/clk)
对应输出；m_axis_tready in。

## latency_cycles
- REG_TYPE=0: 0 cycle（组合）
- REG_TYPE=1: 1 cycle，反压时 sink 侧会丢拍（bubble）
- REG_TYPE=2: 1 cycle 数据延迟，无 bubble（skid）

## resource_est
slice FF 为主；skid 约两拍数据寄存器。无 BRAM。

## forbidden
- 禁止当作 CDC（无双时钟）。
- 禁止把 `rst` 当低有效；本模块是高有效。
- 禁止对 KEEP/ID/DEST 使能位与宽度参数不一致。
- 登记例化禁止使用 `.*`；关闭的侧带仍要按模板列出或显式注释 TIED。
- REG_TYPE=1 时不要假设“永远满吞吐”。

## pasteable_sv
```systemverilog
axis_register #(
  .DATA_WIDTH  (DATA_WIDTH),
  .KEEP_ENABLE (KEEP_ENABLE),
  .KEEP_WIDTH  (KEEP_WIDTH),
  .LAST_ENABLE (1),
  .ID_ENABLE   (0),
  .ID_WIDTH    (8),
  .DEST_ENABLE (0),
  .DEST_WIDTH  (8),
  .USER_ENABLE (1),
  .USER_WIDTH  (1),
  .REG_TYPE    (2)
) u_axis_register (
  .clk           (clk),
  .rst           (rst),
  .s_axis_tdata  (s_axis_tdata),
  .s_axis_tkeep  (s_axis_tkeep),
  .s_axis_tvalid (s_axis_tvalid),
  .s_axis_tready (s_axis_tready),
  .s_axis_tlast  (s_axis_tlast),
  .s_axis_tid    (s_axis_tid),
  .s_axis_tdest  (s_axis_tdest),
  .s_axis_tuser  (s_axis_tuser),
  .m_axis_tdata  (m_axis_tdata),
  .m_axis_tkeep  (m_axis_tkeep),
  .m_axis_tvalid (m_axis_tvalid),
  .m_axis_tready (m_axis_tready),
  .m_axis_tlast  (m_axis_tlast),
  .m_axis_tid    (m_axis_tid),
  .m_axis_tdest  (m_axis_tdest),
  .m_axis_tuser  (m_axis_tuser)
);
```
```

同步 FIFO 可另做一条，字段相同；时序仍写 handshake + 满/空标志是 level 还是 pulse（以 RTL 为准）。Corundum 风格端口表可直接当 md 表格模板：https://docs.corundum.io/en/latest/modules/mqnic_app_block.html

---

## 4. Agent 规程（写入 SKILL.md 的编号步骤）

**硬规则（抄 babyworm + oh-my-fpga 验证优先）：**  
未打开 `catalog/modules/<id>.md` 的 pasteable_sv **不得**写出该模块端口。记忆中的 `tready` 极性、`rst_n` 一律视为不可信。描述符缺失 → halt。端口宽不一致 → halt，禁止自动截断。https://raw.githubusercontent.com/babyworm/rtl-agent-team/main/skills/rtl-ip-instantiate/SKILL.md

### SEARCH（选用模块、不发明端口）

1. 读本 skill 的 `description` 触发词：instantiate、reuse、FIFO、AXIS slice、catalog。
2. 只打开 `catalog/index.yaml`（或 json）。用 one_liner/tags 筛选，**不要**把全部 modules/*.md 读进上下文。
3. 选出 ≤3 个候选后，`Read` 对应 `catalog/modules/<id>.md`。
4. 需要确认漂移时，再 `Read` `source_path` 的模块头（parameter 列表 + ANSI 端口），**以 RTL 为准**。
5. 从 md 复制 `pasteable_sv`，只改实例名与连接网名；不增删端口。
6. 若 index 无匹配：允许写新 RTL，但必须走 REGISTER，禁止“先写后补端口”。
7. 厂商 IP（Vivado XCI / PD `_hw.tcl`）：catalog 只记 wrapper 的 SV 边界；内部 XCI 不当粘贴源。UG1118 禁止手改 component.xml。

### REGISTER（新增 RTL 的门闩）

1. RTL 合入前必须同时加：`catalog/modules/<module_name>.md` 与 index 一行。
2. 五条必填 + clocks/resets 极性 + cdc_notes + forbidden + source_path 缺一不可。
3. `pasteable_sv` 必须列出**全部**顶层端口（含当前默认关掉的侧带）。
4. `module_name` == SV `module` 标识符 == 文件名 stem（可规定例外但要写在记录里）。
5. origin=vendor 时写清：工具生成物路径、VLNV、以及**只例化 wrapper**。
6. 跑 `scripts/check_catalog.py`：解析 RTL 端口集 == stanza 端口集。
7. verify_status 至少 `lint` 才允许 tag `ready`；否则 `draft`，agent 默认不选用 draft。
8. 可选：同目录加 FuseSoC `.core` 只解决 fileset，不替代 md。

### UPDATE（端口变了）

1. 改 RTL 端口/参数/复位极性 = 必须同 commit 改 md + index。
2. CI：stanza 与 RTL 头集合差非空 → **fail**（对齐 oh-my-fpga“工具名必须存在于真实目录”的确定性检查：https://raw.githubusercontent.com/LNC0831/oh-my-fpga/main/README.md ）。
3. 改 handshake 语义（如 simple vs skid）必须改 `latency_cycles` 与 forbidden。
4. 删除模块：index 删行；md 移 `catalog/retired/` 而非静默消失，避免 agent 引用幽灵 id。
5. 禁止只改 README 散文不改 pasteable_sv。liteeth README 已证明散文会停更：https://raw.githubusercontent.com/enjoy-digital/liteeth/master/README.md

---

## 5. 各源缺陷（写进 SKILL「不要用什么当真理」）

| 源 | 缺陷 |
|---|---|
| IP-XACT | 重；参数双层；abstraction 的“时序”是 isClock/isReset/presence，**没有** valid/ready 波形；Vivado 停在 1685-2009 `spirit:`，2022 是 `ipxact:`（Topwrap 文） |
| Kactus2 | 能生成 HDL **头**，不管行为（Kactus2 README “Neither Kactus2 nor IP-XACT handles module implementations”）https://raw.githubusercontent.com/kactus2/kactus2dev/master/README.md |
| XCI / component.xml | 非粘贴 SV；packager 输出不手改；XCI 是实例定制 |
| `_hw.tcl` | Tcl API；associatedClock/readyLatency 有用但 agent 不能粘进 SV |
| FuseSoC `.core` | 无端口、无波形、无 CDC |
| 大 README（axis/axi、ZipCPU、liteeth） | axis 有公共信号+波形但无逐模块表；axi/zip 靠源码头；liteeth 几乎无端口文档 → **过期与不全** |
| OpenTitan README | 接口表靠生成才抗漂移；手写 theory 仍可能旧 |
| Corundum 模块页 | 端口表优秀但太长，不适合整本塞进 SKILL；适合当 md 表格范例 |
| oh-my-fpga / FPGA-Agent | 无登记册；不能当 IP 源 |
| babyworm rtl-ip-instantiate | 包装第三方，不维护可检索 in-house 目录 |

---

## 6. SKILL.md 骨架（专家可粘贴后填仓库相对路径）

Frontmatter 遵循 https://github.com/agentskills/agentskills/blob/main/docs/specification.mdx

```markdown
---
name: ip-module-registry
description: Instantiate reusable RTL from the in-repo catalog (pasteable SV, never invent ports). Use when writing/connecting FIFO, AXI-Stream register slice, CDC, or any catalog IP; when adding a new reusable module; when module ports change.
---

# IP module registry

## Absolute rules
- Do not invent or recall ports. Copy pasteable_sv from catalog/modules/<id>.md.
- If the module is not in catalog/index.yaml, REGISTER it before instantiating, or halt.
- RTL header wins if catalog and RTL differ; then UPDATE the catalog in the same change.

## Layout
catalog/index.yaml
catalog/modules/<id>.md

## Required record fields
(paste section 3.1–3.2)

## SEARCH / REGISTER / UPDATE
(paste section 4)

## Do not use as instantiation source
IP-XACT XML, XCI, component.xml, FuseSoC .core, vendor _hw.tcl, stale README prose.
```

三层可学 FPGA-Agent：决策在 SKILL，字段细则在 `references/fields.md`，例子即 `catalog/modules/`。https://raw.githubusercontent.com/Shinei-Nouzen-Arch/FPGA-Agent/main/README.md

CI 最小实现提示：用 slang/verible 或正则抽 `module ... ( ... );` 端口名，与 pasteable 里 `.port (` 集合做对称差。oh-my-fpga 用零 LLM 检查工具名——这里用零 LLM 检查端口名。

---

## 7. URL 清单（均为本次打开过的活链接）

- Agent Skills spec: https://github.com/agentskills/agentskills/blob/main/docs/specification.mdx
- oh-my-fpga README: https://raw.githubusercontent.com/LNC0831/oh-my-fpga/main/README.md
- oh-my-fpga skills dir: https://github.com/LNC0831/oh-my-fpga/tree/main/skills
- FPGA-Agent README: https://raw.githubusercontent.com/Shinei-Nouzen-Arch/FPGA-Agent/main/README.md
- FPGA-Agent vivado-synth SKILL: https://raw.githubusercontent.com/Shinei-Nouzen-Arch/FPGA-Agent/main/vivado-synth/SKILL.md
- rtl-ip-instantiate SKILL: https://raw.githubusercontent.com/babyworm/rtl-agent-team/main/skills/rtl-ip-instantiate/SKILL.md
- Accellera IP-XACT: https://www.accellera.org/downloads/standards/ip-xact
- Schema 1685-2022: http://www.accellera.org/XMLSchema/IPXACT/1685-2022/
- User Guide: https://www.accellera.org/images/downloads/standards/ip-xact/IPXACT-2022_user_guide.pdf
- port.xsd: https://www.accellera.org/XMLSchema/IPXACT/1685-2022/port.xsd
- Topwrap IP-XACT: https://antmicro.github.io/topwrap/developers_guide/ipxact-design.html
- Kactus2: https://github.com/kactus2/kactus2dev
- ipxactexamplelib: https://github.com/kactus2/ipxactexamplelib
- Digilent component.xml: https://raw.githubusercontent.com/Digilent/vivado-library/master/ip/rgb2dvi/component.xml
- FuseSoC core files: https://fusesoc.readthedocs.io/en/stable/user/build_system/core_files.html
- blinky.core: https://raw.githubusercontent.com/olofk/fusesoc/master/tests/userguide/blinky/blinky.core
- UG1118 outputs: https://docs.amd.com/r/en-US/ug1118-vivado-creating-packaging-custom-ip/Outputs-from-IP-Packager
- UG1118 identification: https://docs.amd.com/r/en-US/ug1118-vivado-creating-packaging-custom-ip/Identification
- UG896 packager: https://docs.amd.com/r/en-US/ug896-vivado-ip/IP-Packager
- UG994 bus interfaces: https://docs.amd.com/r/en-US/ug994-vivado-ip-subsystems/Using-Bus-Interfaces
- Intel 683609 PD components: https://docs.altera.com/r/docs/683609/26.1/quartus-prime-pro-edition-user-guide/creating-platform-designer-components
- Intel _hw.tcl SV: https://docs.altera.com/r/docs/683609/26.1/quartus-prime-pro-edition-user-guide/declaring-systemverilog-interfaces-in-_hw.tcl
- Intel 683364 Tcl ref: https://docs.altera.com/r/docs/683364/18.1/intel-quartus-prime-standard-edition-user-guide-platform-designer/component-interface-tcl-reference
- 683623 实为 DisplayPort AN745: https://docs.altera.com/r/docs/683623/current/an-745-design-guidelines-for-displayport-ip-interface/design-guidelines-for-displayport-ip-interface
- verilog-axis README: https://raw.githubusercontent.com/alexforencich/verilog-axis/master/README.md
- axis_register.v: https://raw.githubusercontent.com/alexforencich/verilog-axis/master/rtl/axis_register.v
- verilog-axi README: https://raw.githubusercontent.com/alexforencich/verilog-axi/master/README.md
- Corundum mqnic_app_block: https://docs.corundum.io/en/latest/modules/mqnic_app_block.html
- OpenTitan example IP doc: https://opentitan.org/book/doc/contributing/doc/example_ip_block.html
- Comportability: https://opentitan.org/book/doc/contributing/hw/comportability/index.html
- hw/ip README: https://raw.githubusercontent.com/lowRISC/opentitan/master/hw/ip/README.md
- uart interfaces.md: https://raw.githubusercontent.com/lowRISC/opentitan/master/hw/ip/uart/doc/interfaces.md
- liteeth README: https://raw.githubusercontent.com/enjoy-digital/liteeth/master/README.md
- ZipCPU wb2axip README: https://raw.githubusercontent.com/ZipCPU/wb2axip/master/README.md
