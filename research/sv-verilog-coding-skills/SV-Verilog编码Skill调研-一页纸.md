# SV/Verilog 编码 Skill 调研（一页纸）

## 1. 结论摘要
- **本地三件套已够写/审 DUT 家规主路径**：`sv-coding-rules`（硬家规）> `fpga-rtl-style`（风格层）> `sv-ip-catalog`（例化契约）；冲突以 `sv-coding-rules` 为准。
- **缺口不在「再写一套命名」**，而在：公开基线对照包、lint 分诊工作流、可选「项目覆盖层」模板。
- **优先补（选型）**：① lint-triage 类（修/waiver/假绿）② CodingStyle 合同可挂载包（lowRISC / rtl-skills 二选一作对照）③ 可选项目覆盖 SKILL（i_/o_ vs _i/_o、复位极性）。
- **不必补**：架构划分、XDC/时序、完整 UVM（已有/应另开页）。
- **公开「短原则」skill（mindrally）仅作灵感，不可替代家规**——偏好同步复位且偏泛，与本地异步低有效家规冲突。

## 2. 背景
Agent Skills 以目录 + `SKILL.md`（YAML frontmatter：`name`/`description` + 正文规程）形态被 Cursor/Claude 等加载；FPGA 侧公开物多为「风格指南」或「工具链方法论」，真正可执行的 **编码合同型** skill 仍稀缺。本页只回答：本地编码 skill 是否够用、缺什么、从哪抄。

## 3. 范围边界
- **In**：可综合 RTL 写/审——端口、`always_ff`/`always_comb`、FSM、命名、复位、valid/ready、lint、IP 例化约束、可读性/家规模板。
- **Out**：架构/模块划分专题；XDC/时序收敛；完整 UVM；板级 bring-up；纯 TB 语法教学。  
  （对照：`fpga-architecture-partition` 属 Out，仅作边界说明。）

## 4. Skill 分类表

| 名称 | 用途一句话 | 典型触发词 | 出处 | 证据 |
|------|------------|------------|------|------|
| sv_coding_rules | 家规硬约束：sys_clk/sys_rst_n 异步低、三段式 FSM（cs_state/ns_state）、i_/o_/w_/r_、换行与禁 SSA 中间网 | 三段式、cs_state、sys_rst_n、命名、重构 | `/home/box/agent-data/workflows/sv-coding-rules/SKILL.md` | 事实（已 Read） |
| FPGA RTL Style | 代码层风格：端口/握手/CDC 写码约束；与上冲突则 defer | always_ff、valid/ready、lint、写 RTL | `/home/box/agent-data/workflows/fpga-rtl-style/SKILL.md` | 事实（已 Read） |
| sv_ip_catalog | IP/叶子例化：先 SEARCH 目录再粘贴全端口；禁 `.*`、禁猜极性 | IP核、FIFO、例化、ip-catalog | `/home/box/agent-data/workflows/sv-ip-catalog/SKILL.md` | 事实（已 Read） |
| lowRISC Verilog Style | 业界基线：SV-2017、`always_ff`/`always_comb`、`logic`、命名 `_i/_o`、异步低复位、两段 FSM（`_q`/`_d`） | coding style、Comportable、OpenTitan | https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md | 事实（已抓 raw） |
| rtl-skills CodingStyle | Agent 可挂编码合同：Verilog-2005 DUT、同步复位、`_ff`/`_ns`、valid/ready、CDC、Verible/Verilator | CodingStyle、vfill、//@ | https://raw.githubusercontent.com/phamcuong21478/rtl-skills/main/skills/shared/CodingStyle.md | 事实（已抓 raw） |
| mindrally `fpga` / `systemverilog` | 短系统提示：模块化、偏同步复位、AXI/CDC 原则级 | FPGA、SystemVerilog、Vivado | https://github.com/mindrally/skills/blob/main/fpga/SKILL.md ；…/systemverilog/SKILL.md | 事实（已抓 raw） |
| oh-my-fpga `lint-triage` | 编码相关：latch/FSM/coding-style lint → FIX/WAIVE/ASK，禁假绿 | lint my rtl、unintended latches | https://github.com/LNC0831/oh-my-fpga/blob/main/skills/lint-triage/SKILL.md | 事实（已抓 raw） |
| oh-my-fpga `cdc-audit` | 仅一句：编码硬约束（1bit 2FF；总线禁逐 bit sync）；深审计属旁路 | CDC、2FF、灰码 FIFO | https://github.com/LNC0831/oh-my-fpga/blob/main/skills/cdc-audit/SKILL.md | 事实（已抓 raw；本页不展开） |
| babyworm rtl-agent-team `systemverilog` | 项目覆盖层范例：在 lowRISC 上改 `i_`/`o_`、禁 CamelCase、强制 `always_ff`/`always_comb` | project conventions、rtl-coder | https://github.com/babyworm/rtl-agent-team/blob/main/skills/systemverilog/SKILL.md | 事实（已抓 raw） |
| Agent Skills 规范 | skill 形态：`SKILL.md` + name/description；Cursor 另有 paths 等 | agentskills、Cursor skills | https://agentskills.io/specification ；https://cursor.com/docs/skills | 事实（已抓规范页） |
| 独立「纯编码」Marketplace 包 | Cursor Marketplace / awesome 列表中独立 FPGA coding skill | marketplace FPGA skill | — | 待核实（2026-09 盘点写「未找到」；本轮未复扫全库） |

## 5. 编码向常见惯例与注意点
1. **时序/组合分离**：`always_ff` 用 `<=`，`always_comb` 用 `=`；禁止同块混用、禁止锁存（`case` 必有 `default`）。
2. **复位与时钟写死**：本地默认 `sys_clk` + `sys_rst_n` 异步低；公开源常见 `clk_i`/`rst_ni`（lowRISC）或同步 `rst_n`（rtl-skills/mindrally）——**选型前先锁极性**。
3. **FSM**：本地强制三段式 + `cs_state`/`ns_state`；lowRISC 为两段 `_q`/`_d`；rtl-skills 为 `*_state_ff`/`*_state_ns`——**勿混名**。
4. **握手**：`fire = valid && ready`；`valid` 在 `ready==0` 时勿无故拉低；单周期脉冲置位优先于清除。
5. **命名**：方向前缀（本地 `i_`/`o_`）与角色（`s_`/`m_`）可并存；时钟复位常豁免前缀。
6. **例化**：仅命名连接；本地 + lowRISC + rtl-skills 均禁位置/`.*`；IP 先打开 pasteable 全端口再写。
7. **Lint**：建议 Verilator `-Wall` / Verible；waiver 必须行内理由（本地铁律与 lint-triage 一致）。
8. **CDC 写码底线**：1 bit → 2FF；多 bit → 灰码 FIFO / req-ack；总线逐 bit 2FF 视为 bug。

## 6. 坑与反模式
1. **把 mindrally 当家规** → 同步复位偏好与本地异步低有效冲突，且无打回表。
2. **混用 FSM 命名体系**（`state_ff` vs `cs_state` vs `state_q`）→ 审查假通过、重构翻车。
3. **假绿 lint**：批量 waive / 降 severity（lint-triage 明确禁止）。
4. **凭记忆写 IP 端口**（极性、`tready`、宽）→ `sv_ip_catalog` 要求 halt。
5. **软件式 SSA 中间网**（`w_tmp`、单扇出拆项）→ 本地明确打回。
6. **约束代替硬件**（`set_false_path` 掩盖未同步交叉）→ 编码层与 cdc-audit 共同禁区。

## 7. 开放选项（优先补 2–4 类）
1. **lint-triage 薄封装**（适用：已有 Vivado/SynthPilot 或 Verilator CI，要「修 vs 有理由 waiver」剧本）——可直接 fork oh-my-fpga `lint-triage` 去 MCP 绑定。
2. **对照基线 skill 包**（适用：新人 onboarding / PR 对照）——挂 lowRISC 全文链接 + 一页「与家规差异表」，勿整份拷进上下文。
3. **项目覆盖层 SKILL**（适用：多仓库复位/前缀不一致）——学 babyworm：声明「基线=lowRISC/本地，下列为 overrides」。
4. **（可选）CodingStyle 合同子集**（适用：仍锁 Verilog-2005 DUT）——摘 rtl-skills §0/§14–16，勿全盘同步复位。

## 8. 出处列表
1. `/home/box/agent-data/workflows/sv-coding-rules/SKILL.md`
2. `/home/box/agent-data/workflows/fpga-rtl-style/SKILL.md`
3. `/home/box/agent-data/workflows/sv-ip-catalog/SKILL.md`
4. https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md
5. https://raw.githubusercontent.com/phamcuong21478/rtl-skills/main/skills/shared/CodingStyle.md
6. https://github.com/mindrally/skills/blob/main/fpga/SKILL.md
7. https://github.com/LNC0831/oh-my-fpga/blob/main/skills/lint-triage/SKILL.md
8. https://github.com/babyworm/rtl-agent-team/blob/main/skills/systemverilog/SKILL.md
9. https://agentskills.io/specification
10. https://cursor.com/docs/skills
11. （边界对照，非 In）`/home/box/agent-data/workflows/fpga-architecture-partition/SKILL.md`
12. （旧盘点参考，星标未复核）`/workspace/fpga-skill-inventory.md`

---
调研日期：2026-09-14｜方法：本地 Read + WebFetch 核实公开 raw；未写未核实星标。
