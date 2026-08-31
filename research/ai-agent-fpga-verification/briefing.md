# AI Agents in FPGA Development and Verification — Research Notes

**Research date:** 2026-08-31 (Monday; user TZ Asia/Shanghai)  
**Scope:** Mature, copyable workflows for AI agents in FPGA development and verification, 2023–2026 primary sources.  
**Audience:** 坤 仇 (FPGA/fintech researcher) via 调研专员.  
**Caution already known:** FinHardBench (arXiv:2608.00909, ~2026-08) — LLM writing financial Verilog, functional correctness 19–61%, “synthesizes but computes wrong” is the danger. This note treats that as a failure-mode warning, not the whole story.

**Label key:** `[V]` production/vendor · `[A]` academic · `[O]` open-source/hobby · `[N]` anecdotal  
**Rule:** every concrete named product, paper, metric, or repo below has a URL + date. Vendor speedup numbers are **vendor claims**, not independently verified. GitHub star counts are snapshots from fetches on 2026-08-31.

**Name-check (do not invent):**
- **Cadence Verisium SimAI** exists (Cadence product page, fetched 2026-08-31). It is **not** a Siemens product.
- **Siemens Questa One Sim** exists as a simulator in the Questa One family; **“Questa One SimAI” was not found** in Siemens press or product pages.
- **Synopsys AgentEngineer™** exists (Synopsys agentic-AI page, fetched 2026-08-31). **“Synopsys AgentAR” was not found** as an EDA product; `agentAR` is an unrelated UIST 2025 AR-authoring paper.

---

## 0. Maturity map (one screen)

| FPGA loop stage | Maturity 2026 | Copyable artifact | Label |
|---|---|---|---|
| Spec → RTL (small modules, HDLBits/VerilogEval class) | **Relatively mature as a loop pattern**: write → compile → sim → patch | AutoChip, VerilogCoder, AIvril | [A][O] |
| Spec → RTL (production trading IP / large financial datapath) | **Not mature** | FinHardBench caution | [A] |
| TB / UVM / cocotb environment generation | **Emerging-copyable** in Python (cocotb/pyUVM); SV/UVM still research | AgentDV, GoGoTB, UVM², HAVEN | [A] |
| Sim debug (log parse → patch) | **Mature pattern**, not a product | AutoChip, HDLAgent, AIvril AutoReview/AutoDV | [A][O] |
| Coverage-driven gen | **Emerging**; works on small/CSR-exposed DUTs | LLM4DV, AgentDV, GoGoTB | [A] |
| Formal / SVA | **Assistive mature** (human-audited SVA + FPV); autonomous closure not | AssertLLM, AutoSVA2, Synopsys Formal Advisor, Cadence ChipStack formal skill | [A][V] |
| Synth / P&R / timing closure | **Assistive, FPGA-specific, early-access** | AMD Vivado AI Assistant + timing-closure skill; oh-my-fpga `timing-closure` | [V][O] |
| HLS (C/C++ → FPGA) | **Research-to-prototype**; board-level loops exist | ChatHLS, FPGAgent, HLS-Eval, Spec2RTL-Agent | [A] |
| Board bring-up / ILA | **Hobby/vendor assistive**; not autonomous | oh-my-fpga `ila-hw-debug`, `zynq-bringup`; AMD course labs | [O][V][N] |
| Vendor agentic DV (Questa/VCS/Xcelium) | **Early access / evaluation 2026**, ASIC-centric | Siemens Agentic Toolkit (2026-02-27), Synopsys AgentEngineer (DAC 2026-07-26), Cadence ChipStack (2026-02) | [V] |
| Cursor/Claude skills + MCP driving Vivado/Quartus | **Copyable hobby/SMB tooling**; star counts still small | SynthPilot + oh-my-fpga; fpga-mcp; Gateflow; fpgaZeroMCP | [O] |

**What “mature” means here:** a team can clone a documented loop (prompt + tool + parse + gate) without inventing the methodology. It does **not** mean production trading IP can be autonomously signed off.

---

## 1. Where agents sit in the FPGA loop

### 1.1 Spec → RTL

**Pattern that is copyable:** LLM emits Verilog from a natural-language spec; a compiler/simulator (Icarus, Verilator) returns errors; the same conversation is re-prompted with the log until tests pass or `n` is exhausted.

- **AutoChip** (arXiv:2311.04887, 2023-11; DAC 2024 framing on HTML version): first feedback-driven fully automated HDL generation. Design prompt + iverilog compile/sim; “succinct” (last-iteration only) feedback beat full-conversation context. Reported: most-recent-context feedback generated Verilog that passed 24.2% more test cases than zero-shot; GPT-3.5+GPT-4 ensemble Pass@5 up to 89.19% on 120 HDLBits problems. Open-source: https://github.com/shailja-thakur/AutoChip (61★, 2026-08-31). [A][O]
- **Follow-on:** “Automatically Improving LLM-based Verilog Generation using EDA Tool Feedback” (arXiv:2411.11856, 2024-11, v3 HTML). Same AutoChip framework, VerilogEval. Best case: +5.8% successful designs vs best zero-shot, with 34.2% cost decrease (GPT-4o). Mixing smaller models then one GPT-4o call: same success, 41.9% lower cost. [A]
- **VerilogCoder** (AAAI 2025, published 2025-04-11; https://doi.org/10.1609/aaai.v39i1.32007): multi-agent Autogen system with Task-and-Circuit Relation Graph planner + AST-based waveform tracer. VerilogEval-Human v2: **94.2%** syntactically and functionally correct with GPT-4 Turbo; +33.9 pp vs SOTA on that benchmark (authors’ claim). Waveform-level debug is the differentiator vs AutoChip’s text-log loop. [A]
- **AIvril / RapidGPT stack** (arXiv:2409.11411, 2024-09): two loops — AutoReview (syntax) and AutoDV (functional). VerilogEval-Human: 88.46% average success on verification goals (authors). Part of PrimisAI RapidGPT (VS Code HDL pair-designer). [A][V]
- **ChipNeMo** (NVIDIA, arXiv:2311.00176, 2023-11-01): **not** a Verilog generator first. Domain-adapted LLaMA2 (DAPT + RAG) for (1) engineering chatbot, (2) EDA script generation, (3) bug summarization. ChipNeMo-70B beat GPT-4 on chatbot and EDA scripts in NVIDIA’s human eval. Production-internal; weights not public. [A][V]
- **RTLCoder** (arXiv:2312.08617 v4; LAD 2024 Best Paper Nomination; TCAD early access): 7B open model, 27k synthetic instruction-code pairs. GitHub https://github.com/hkust-zhiyao/RTL-Coder (310★, created 2023-11-20). Beats GPT-3.5 on VerilogEval/RTLLM (authors). **Model, not an agent loop.** [A][O]
- **VeriGen** (DATE 2023 / TODAES 2024): fine-tuned CodeGen on GitHub+textbooks. Foundational, not agentic. [A]
- **HDLAgent** (arXiv:2501.00642, 2025-01; GitHub masc-ucsc/hdlagent, 22★, **ARCHIVED**, created 2024-02-01): spec→HDL with self-reflection + EDA grounding; languages Verilog/Chisel/PyRTL/DSLX. [A][O]
- **Spec2RTL-Agent** (arXiv:2506.13905, 2025-06-16): does **not** emit Verilog first. Spec PDF → plan → pseudocode → Python → synthesizable C++ → **Cadence Stratus HLS**. 3 NIST FIPS specs (AES/DSS/HMAC); 3/3 correct; ~4.33 human interventions vs ~20 human baseline (authors). FPGA-relevant because HLS is a common FPGA path. [A]

**FPGA-specific vs ASIC-generic:** almost all RTL papers are FPGA-agnostic HDL. FPGA-specific generation work is concentrated in **HLS** (ChatHLS, FPGAgent, HLS-Eval) and **tool driving** (Vivado MCP / SynthPilot). Direct “NL → FPGA bitstream IP” for production is not a published mature flow.

### 1.2 TB / UVM / cocotb

A 2026 consensus in agent papers: **LLMs write better Python testbenches than SystemVerilog UVM**. GoGoTB (arXiv:2607.26181, ICCAD 2026) states this explicitly and therefore uses **cocotb + Verilator**. AgentDV (arXiv:2608.27148, 2026-08) uses **Verilator + cocotb + pyUVM**.

Copyable academic stacks:
- **UVLLM** (arXiv:2411.16238, 2024-11-25; DAC 2025): UVM + LLM repair. Syntax FR 86.99%, functional FR 71.92% on their error benchmark; 10.42× faster than MEIC (authors). Uses Verilator lint pre-process, then UVM scoreboard vs LLM-generated C/C++ reference model. [A]
- **UVM²** (arXiv:2504.19959 v4; ICCAD 2025 DOI 10.1109/iccad66269.2025.11240679): first systematic LLM-driven **UVM testbench generation + coverage-feedback stimulus**. Average code/function coverage 87.44%/89.58%; setup time >15× reduction (authors). Critiques UVLLM: TB still partly manual; stimulus was unconstrained-random. [A]
- **UVMarvel** (arXiv:2605.04704, 2026-05): subsystem-level UVM across APB/AHB/AXI. 95.65% code coverage (authors). Open-source libraries: https://github.com/SEU-ACAL/reproduce-UVMarvel-DAC-26. [A]
- **HAVEN** (arXiv:2604.27643, 2026-04): **do not let the LLM write HDL for the TB**. LLM plans architecture; Jinja2 protocol templates emit UVM components; a Protocol-Aware Sequence DSL + rule-based generator emit sequences. 19 IPs, 100% compile, 90.6% code / 87.9% functional coverage (authors). Direct lesson: constrain the LLM to the planning layer. [A]
- **GoGoTB** (arXiv:2607.26181, ICCAD 2026 Nov 8–12): 8-stage agent, 3-layer execution control (tool-call guard / stage quality gates / L1–L4 repair escalation), spec-grounded coverage. 8 designs, 7 LLMs, **100% environment generation success**; avg 98.4% line / 97.2% branch / 97.0% toggle / **83.2% functional**. UVM² baseline 0% SRG on same 8 designs (authors’ reproduction). Stack: Verilator 5.024 + cocotb 2.0.1. [A]
- **AgentDV** (arXiv:2608.27148, 2026-08): ISQED 2026 AutoVerifier task. CSR-grounded RAL (not LLM-inferred addresses). Runnability filter before admitting tests. OpenTitan UART/AES/HMAC/timer. Claude Sonnet 4.6: 80.9% pass rate overall, 100% on 4 DUTs; line/branch 74.5%/88.4% (challenge) vs 71.6%/79.2% (public OT). **Single-shot Claude without AgentDV: 0% valid coverage-producing environment.** AES datapath stays ~37% line coverage — CSR tests cannot start the engine. [A]

### 1.3 Sim debug

Copyable pattern (not a named product):
1. Compile; feed **structured** compiler diagnostics (Verilator JSON, not raw walls of text).
2. If sim fails: feed **mismatch tuples** (time, inputs, DUT out, golden out), not the whole VCD.
3. Keep the **testbench frozen** while patching RTL (AIvril AutoDV; AutoChip).
4. Rollback if pass-rate drops (UVLLM scoreboard rollback).
5. Waveform/AST tracing when log text is insufficient (VerilogCoder).

ChipNeMo’s production analogue: bug summarization over long comment+log histories with hierarchical chunking. [V][A]

### 1.4 Coverage

- **LLM4DV** (arXiv:2310.04535; FCCM 2025 DOI 10.1109/FCCM62733.2025.00048): LLM as **coverage-directed stimulus agent**, not TB writer. 8 DUTs (incl. Ibex, SDRAM ctrl, MIPS), 3883 bins. Best configs 89.74–100% coverage on simpler DUTs; Ibex CPU hard. Claude 3.5 Sonnet strongest. Open-source framework. FPGA-relevant (FCCM). [A]
- **AgentDV Iterate stage:** uncovered RTL regions annotated → one gap-directed test per iteration; stop after 5 iters or 2 consecutive zero-gain. [A]
- **GoGoTB S8:** every residual bin classified into 7 root-cause categories (Stimulus Gap, Sequence Gap, Cross Hole, State Unreached, Timing Dependent, Transition Gap, Seed Insufficient) with a targeted remedy; stall detector. [A]
- **Cadence Verisium SimAI** (product page, fetched 2026-08-31; Cadence 2022 platform launch): ML from Xcelium regressions to generate new regressions (compression / failure-amp / coverage-amp / closure / AutoFocus). **Not LLM-agentic**; classical ML on sim data. ASIC/SoC. [V]
- **Siemens Questa One Verification IQ** (product page): predictive/generative/prescriptive analytics for regression and coverage. Data-driven, not a coding agent. [V]

### 1.5 Formal / SVA

- **AssertLLM** (arXiv:2402.00386 / 2411.14436; ASPDAC 2025): spec document (text + waveforms) → structured template → SVA. 89% of generated assertions syntactically and functionally accurate on a 23-I/O design (v4 HTML). FPV evaluation. [A]
- **AssertLLM2** (arXiv:2605.27472, 2026-05): 83 designs, golden RTL + mutated buggy RTL; JasperGold syntax/FPV/coverage/mutation. GitHub hkust-zhiyao/AssertLLM2. [A]
- **ChatSVA** (arXiv:2604.02811, 2026-04): multi-agent SVA gen. 24 RTL designs: 98.66% syntax / 96.12% functional pass, 82.50% function coverage (authors vs AssertLLM baseline). [A]
- **Orenes-Vera et al.** “Using LLMs to Facilitate Formal Verification of RTL” (arXiv:2309.09437, 2023-09-18): GPT-4 + JasperGold iterative rule-crafting. 23 iterations / ~8 hours to teach GPT-4 correct SVA on a FIFO. AutoSVA2: GPT-4 safety properties + AutoSVA liveness. Found a CVA6 PTW bug missed by AutoSVA. Key finding: **GPT-4 can write correct SVA even for buggy RTL** (does not merely mirror the DUT). [A]
- **AssertCoder** (arXiv:2507.10338, 2025-07): multimodal spec → SVA; mutation eval with SymbiYosys + Mantra. [A]
- **Synopsys Formal Advisor** (Synopsys.ai Copilot blog, fetched 2026-08-31): generates formal testbenches from NL/docs; accessed from VC Formal, Verdi, or VS Code. Vendor: “4–5× productivity” (customer claim). [V]
- **Cadence ChipStack** formal skill (product page, fetched 2026-08-31): “Generates a formal verification plan and corresponding SVA and automatically proves them with Jasper.” [V]

FPGA angle: open-source FPV (SymbiYosys / Yosys) is the copyable path; Jasper/VC Formal are vendor. Formal does **not** replace simulation for FPGA datapaths (AES, trading matching engines).

### 1.6 Synth / P&R / timing closure

This is the **FPGA-native** agent surface, and it is 2026-new.

- **AMD Vivado AI Assistant** (course VIVADO-AI-ASST, spec updated 2026-06-30; tools Vivado 2025.2 + VS Code + GitHub Copilot): MCP knowledge grounding; labs for project/BD/IP, lint/log analysis, multi-run comparison, **iterative timing closure**, AXI/sim debug, ILA/VIO. [V]
- **AMD Vitis Unified IDE AI Chat** (UG1702 2026.1; UG1400 2026.1 dated 2026-07-31): Theia agents Architect / Coder / Command / Orchestrator / Universal / User_Guide. AMD MCP `vivado-doc-server` at `https://vivado.amd.com/mcp/doc-search`. **Guidance only; AMD does not host or validate third-party models.** Skills configurable in `settings.json`. [V]
- **FPGA Horizons US East 2026 workshop** (fpgadeveloper.com, 2026-05-19, Jeff Johnson / Opsero): AMD did two things — (1) MCP server for **documentation**, (2) **agent skills** with procedural best practices (timing-closure skill demoed). Early-access lounge “in a few weeks”; **no paywall, including ML Standard (free) license**. Model-agnostic (Claude Code, Codex, local). Author: raw LLMs already know Tcl/Python but are **overconfident on stale tool versions**; MCP grounds to current docs. [N][V]
- **oh-my-fpga** (https://github.com/LNC0831/oh-my-fpga, 17★, MIT): 13 named skills including `timing-closure`, `cdc-audit`, `full-flow-demo`, `sim-bringup`, `coverage-closure`, `ila-hw-debug`, `zynq-bringup`. Principles: verification-first, never fake-pass, smallest safe change (constraints before RTL), stop and hand back to human. Requires SynthPilot MCP. Cursor gets the same 13 as MCP prompts (SynthPilot 1.3.0+). [O]
- **SynthPilot** (https://www.synthpilot.dev/, Chinese-first; zip installer EOL 2026-03): MCP for Vivado / Anlogic TD / Quartus. Free 43 Vivado tools; Pro 475; MAX 510. Vendor claim: 900+ engineers registered (AMD, 清华, 复旦, 上交, 中科院, 复旦微, 禾赛, 北醒 named on site). **Proprietary MCP + MIT skills.** Local EDA execution. [O][V-ish]
- **fpga-mcp** (https://github.com/wmm246/fpga-mcp, 0★ snapshot): MIT multi-vendor rewrite claiming 689 tools (343 Vivado / 167 Quartus / 157 Anlogic). Positions itself against SynthPilot’s edition gating. **New / unproven by stars.** [O]
- **fpgaZeroMCP** (https://github.com/lcapossio/fpgaZeroMCP, 5★, created 2026-03-19): OSS CAD Suite (Yosys/nextpnr/Verilator/iverilog). Lint, sim, synth, P&R, program. [O]
- **coreyhahn/vivado_mcp** (48★, created 2026-01-18): persistent Vivado Tcl session via pexpect (avoids ~30s startup per command). [O]
- **weft-mcp, quartus-Lmcp-server, abbbe/fpga-mcp-servers**: Quartus-specific community MCP (async compile because 20–45 min builds). [O]
- **silica-eda** (PyPI v0.1.9): MCP wrapping OSS + commercial (VCS/Questa/Xcelium/Vivado/Quartus/Jasper) if on PATH. [O]
- **MCP4EDA** (https://github.com/NellyW8/MCP4EDA, 96★, created 2025-05-24; arXiv:2507.19570): Yosys/Icarus/OpenLane RTL-to-GDSII. ASIC-leaning. [A][O]

**Maturity verdict:** driving synth/impl **as a copilot that reads reports** is copyable today (MCP + skill). **Trusting the agent to close timing and ship a bitstream** is not. oh-my-fpga itself forbids claiming “timing closed” without fresh post-impl evidence.

### 1.7 HLS

- **HLS-Eval** (ICLAD 2025 DOI 10.1109/iclad65226.2025.00021; GitHub stefanpie/hls-eval): 94 designs; metrics parseability / compilability / runnability / synthesizability vs Vitis HLS. [A]
- **ChatHLS** (arXiv:2507.00642; ACL 2026 long 962; GitHub GEAR-SEU/ChatHLS-ACL-26): multi-agent HLS-C repair + QoR-aware directive tuning. 82.7% repair pass over 612 cases; 1.9–14.8× kernel speedup (authors). Validated on Xilinx ZCU106. Limitations stated by authors: no DATAFLOW/AXI IP packaging; one FPGA family. [A]
- **FPGAgent** (arXiv:2608.23630, 2026-08): NL spec → HLS kernel → C++ validator → host code → **board-level execution**. HLS-Eval 78 tasks, 5 models. +16.9% synthesizable, +26.7% executable, +30.6% functional vs baselines (authors). Explicitly: sim+synth pass ≠ FPGA-runnable (timing/P&R). [A]
- **Spec2RTL-Agent**: see 1.1; HLS as the RTL back-end. [A]

HLS agents are **more FPGA-native** than VerilogEval-class RTL agents, because the toolchain (Vitis HLS CSIM/CSYN/COSIM) is FPGA.

### 1.8 Board bring-up

oh-my-fpga `zynq-bringup`, `ila-hw-debug`, `bitstream-program`. AMD course labs on VCK190 / KV260. Tang Nano 9K Cursor blog (DEV.to, anecdotal): generate RTL+TB, paste logs, never trust pinout/timing. [O][V][N]

Not mature as autonomy. Useful as a **scripted copilot** for ILA insertion and programming.

---

## 2. Closed-loop practices that actually work

These are the transferable engineering practices, independent of any one paper’s pass rate.

### 2.1 Write → simulate → parse log → patch

**Minimum viable loop (copy this):**

```
prompt(spec, frozen_TB_or_golden)
  → LLM emits RTL
  → verilator --lint-only / iverilog   # syntax gate
  → sim (verilator+cocotb | questa | vcs | iverilog)
  → parse: compile errors OR (time, in, dut, golden) mismatches
  → if fail: re-prompt with LAST iteration only (AutoChip “succinct”)
  → cap n (AutoChip n=10; UVLLM n=5; AgentDV Kmax=5, patience=2)
  → never mutate the TB while scoring the DUT (AIvril)
```

**Why succinct context wins:** AutoChip found full conversation history *hurt* repair (model confusion + token cost). GoGoTB Layer-1 “structuring” converts raw logs to classified diagnostics so the LLM never sees megabytes of Verilator noise.

**Simulator choice for agents:**
- **Verilator**: structured, parseable, free, FPGA-friendly. Chosen by GoGoTB, AgentDV, UVLLM lint, LLM4DV. [A]
- **cocotb / pytest / pyUVM**: Python, where LLMs are strong. GoGoTB’s explicit rationale. [A]
- **Questa / VCS / Xcelium**: needed for full SV/UVM, mixed-lang, encrypted IP, vendor VIP. Agent papers that generate UVM (UVM², UVMarvel, HAVEN) assume these. Vendor agentic toolkits (Questa One, Synopsys AgentEngineer, ChipStack) wrap them. [V][A]
- **Icarus**: AutoChip’s original choice; fine for HDLBits, weak for SV/UVM.

### 2.2 Coverage-driven generation

Do not stop at “tests passed.” AgentDV’s single-shot baseline produced **0%** coverage-producing environments. GoGoTB’s UART ablation: environment compiled and simulated, **functional coverage 0%** until protocol-framing knowledge was injected; then 75.3%.

Copyable coverage loop:
1. Derive bins from **spec behaviors**, not signal ranges (GoGoTB L3–L4 vs UVM² L2).
2. Measure with Verilator coverage or vendor UCDB.
3. Feed **uncovered regions / named bins** back; generate one directed test.
4. Stall-stop (2 rounds no gain).
5. Report residual bins with root cause — do not silently drop.

LLM4DV is the FPGA-conference (FCCM 2025) version of this for **stimulus only**.

### 2.3 Constrained-random + LLM

Industry CRT remains the bulk generator. LLM should:
- write/repair **constraints and coverage models**
- generate **directed tests for residual bins** (GoGoTB S8; AgentDV Iterate)
- **not** replace the constrained-random engine

Cadence Verisium SimAI is the vendor ML analogue (regression compression / coverage amp) — classical ML, years in market (platform 2022; SimAI still on product page 2026). [V]

HAVEN’s DSL: high-coverage sequences first **without** the LLM; LLM only fills gaps. [A]

### 2.4 Human-in-the-loop review gates

Every vendor 2026 agentic pitch includes this. Siemens (2026-02-27): “configurable human oversight at critical decision points.” Cadence ChipStack L5 (Computex 2026): humans inspect/guide; Codex/Claude Code compatible. AMD UG1400: review, confirm intent, verify file diffs, rebuild.

oh-my-fpga hard gates: no “timing closed” without post-impl evidence; no silent RTL edits; no fake waivers.

**Practical FPGA gates for a trading-IP team:**
| Gate | Block bitstream if |
|---|---|
| Lint | un-waived error |
| Sim vs frozen golden | any mismatch |
| Coverage | functional bins below plan |
| Formal (where bounded) | CEX on safety SVA |
| Synth | timing not met **or** resources over |
| Equivalence / COSIM (HLS) | C/RTL mismatch |
| Board smoke | ILA/self-test fail |

### 2.5 Golden-model vs RTL

FinHardBench’s failure mode is exactly “compiled ≠ correct.” Mitigations found in the literature:

- **Independent golden**: C/C++/Python model written from spec, **not** from the generated RTL. UVLLM uses LLM-generated C/C++ reference — **this is itself a risk** (correlated hallucination). Prefer a human-owned golden for financial IP.
- **RAL/CSR as oracle**: AgentDV derives expected register values from the CSR map via pyUVM RAL `check_t.CHECK`. The LLM never invents addresses/reset values.
- **Keep TB frozen** (AIvril): otherwise the agent “fixes” the checker.
- **Mutation testing**: Firefly (MLCAD 2025 DOI 10.1109/mlcad65511.2025.11189125; GitHub mavericnu/firefly): LLM-injected semantically aware faults; 95%/90% line+toggle still missed 28%/67% of mutants on two cores. Coverage ≠ bug detection. [A]
- **Formal as second oracle**: AssertLLM2 / Orenes-Vera — SVA from spec, prove on RTL, hunt mutants.

### 2.6 Don’t ship a bitstream that only compiled

FPGAgent (2026-08) exists because HLS that passes CSIM+CSYN still fails on board. oh-my-fpga `full-flow-demo` inserts a checkpoint at lint / sim / synth / impl / bitstream. AMD IDR/RQA/RQS (Vivado 2026.1 product page) are **classical** timing helpers — use them; do not replace STA with an LLM opinion.

---

## 3. Skills / prompts / MCP / vendor assistants (2024–2026 confirmed)

### 3.1 Named Cursor/Claude skills for FPGA

| Name | Where | What | Stars / status | Label |
|---|---|---|---|---|
| **oh-my-fpga** 13 skills | GitHub LNC0831/oh-my-fpga; Claude Code plugin; Cursor via SynthPilot MCP prompts | timing-closure, cdc-audit, constraints-authoring, full-flow-demo, sim-bringup, coverage-closure, lint-triage, qor-report, utilization-reduction, power-optimization, zynq-bringup, ila-hw-debug, bitstream-program | 17★ | [O] |
| **Gateflow-Plugin** | GitHub codejunkie99/Gateflow-Plugin | SV codegen, VHDL, P&R, flash, formal, IP library; Cursor via `.cursorrules`; v2.5.3 dated 2026-05-21 | 109★ | [O] |
| **AMD agent skills** | FPGA Horizons 2026 workshop; Vitis `settings.json` skills; VIVADO-AI-ASST course | procedural timing-closure etc.; MCP-grounded | early access / 2026.1 docs | [V] |
| **Siemens curated prompt libraries** | Questa One Agentic Toolkit (2026-02-27) | domain-expert prompts behind MCP agents | early access | [V] |
| **Cadence ChipStack “agentic skills”** | cadence.com ChipStack page | RTL gen, TB (SVA/UVM/checkers/coverage), debug, formal plan+prove | early access → production claims | [V] |

Cursor itself (learncursor.dev, mid-2026): skills live in `.cursor/skills/` as `SKILL.md`; also reads `.claude/skills/`. No official FPGA skill registry. **Team practice:** check `SKILL.md` into the FPGA repo (lint rules, sim command, coverage gate, never-waive CDC).

### 3.2 MCP servers that drive FPGA tools

| Server | Drives | Notes | Label |
|---|---|---|---|
| **AMD `vivado-doc-server`** | AMD documentation search | `https://vivado.amd.com/mcp/doc-search`; in Vitis 2026.1 settings.json | [V] |
| **AMD Vivado AI Assistant MCP** | Vivado via VS Code extension | Course 2026-06-30; Horizons May 2026 | [V] |
| **Siemens Questa One MCPs** | Questa One Sim, SFV, Verification IQ | Vendor-written MCPs; Copilot/Claude/Cursor/Cline/Fuse | [V] |
| **SynthPilot** | Vivado, Quartus, Anlogic | Commercial tiers; Chinese site synthpilot.cn; local Tcl servers ports 9999/9998/9997 | [O] |
| **fpga-mcp** | Vivado, Quartus, Anlogic | MIT, 689 tools, 0★ | [O] |
| **fpgaZeroMCP** | Yosys/nextpnr/Verilator | 5★, 2026-03 | [O] |
| **vivado_mcp** | Vivado persistent Tcl | 48★, 2026-01 | [O] |
| **weft-mcp / quartus-Lmcp-server / fpga-mcp-servers** | Quartus | async compile essential (20–45 min) | [O] |
| **silica-eda** | OSS + VCS/Questa/Xcelium/Vivado/Quartus/Jasper if on PATH | PyPI | [O] |
| **MCP4EDA** | Yosys/Icarus/OpenLane | 96★, paper 2025-07 | [A][O] |

**Intel/Altera:** no first-party Quartus AI assistant found in this survey. Community Quartus MCP only.

### 3.3 Vendor AI (confirmed 2024–2026)

**AMD / Xilinx — FPGA-first**
- Vitis Unified IDE AI Chat + User_Guide agent + `vivado-doc-server` (UG1400 2026-07-31, UG1702 2026.1). [V]
- Vivado AI Assistant Extension + Copilot (course 2026-06-30). [V]
- Agentic workshop FPGA Horizons US East, week of 2026-05-12 (article 2026-05-19). [N]
- Product page Vivado 2026.1: RQA/RQS/IDR still the **non-LLM** timing closure path. [V]

**Siemens EDA**
- **Questa One** announced 2025-05-13, available June 2025. AI-powered “smart verification” (creation/analysis/debug/regression/engines). Microsoft Azure Cobalt customer quote on QDX DFT sim. [V]
- **Questa One Agentic Toolkit** 2026-02-27, early access. Agents: RTL Code, Lint, CDC, Verification Planning, Debug. MCPs to Questa One Verification IQ / SFV / Sim. Works with GitHub Copilot, Claude Code, Cursor, Cline, Fuse. NVIDIA Llama Nemotron / NIM. MediaTek: “hours not days.” Tsavorite: agentic FPV + Lint Agent auto-fix. [V]
- **Not found:** “Questa One SimAI.” **SimAI is Cadence Verisium.**

**Synopsys**
- **Synopsys.ai Copilot** commercially available (blog fetched 2026-08-31): Knowledge Assistant, Workflow Assistant (PrimeTime, Fusion Compiler), Code Advisor (RTL + Euclide lint), Formal Advisor (VC Formal/Verdi/VS Code), Lint Advisor (VC SpyGlass). Fujitsu: 10–30% RTL productivity (assertions, wrappers, parameterized modules). Vendor: 2–5× overall. [V]
- **AgentEngineer™**: L1–L5 autonomy framework. Synopsys Converge 2026: first L4 orchestrated multi-agent (NL/formal spec → RTL → lint → unit TB → iterative verify). News 2026-03-11: “2× productivity, up to 5× in select cases” (vendor). DAC 2026-07-26 with NVIDIA: long-running DV orchestrator, “up to 50× faster time-to-validated RTL +20% coverage” (vendor, footnote 1); availability **H2 2026**. AMD+Microsoft Discovery evaluation 2026-07-27: debug-closure 25–40% cycle-time cut (vendor early eval); spec-to-RTL workflow previously announced. [V]
- **Not found:** “Synopsys AgentAR” as an EDA product.

**Cadence**
- **JedAI** platform + **Verisium** (press 2022; product page live 2026): Manager, Debug, SimAI, FormalAI, AutoTriage, WaveMiner. Protium FPGA prototyping is in the verification full-flow, but Verisium is SoC verification analytics, not an FPGA compiler agent. [V]
- **ChipStack acquisition Nov 2025**; **ChipStack AI Super Agent launched ~2026-02-10** (BusinessWire). Front-end: RTL, TB, regression, debug. Formal plan+SVA+Jasper prove. Vendor: up to 10× coding productivity. Early access then. COMPUTEX 2026: L5 autonomy; NVIDIA using ChipStack with Xcelium+Jasper, “40× faster RTL validation, 5-week loop → <1 day” (Cadence PR). L5 expected early-access H2 2026. Secondary report (otontechnology.com): Altera “>10× on flagship FPGA projects,” Tenstorrent “up to 4× formal time” — **treat as secondary/vendor-adjacent, not audited**. [V][N]
- **InnoStack** (implementation), **ViraStack** (analog), **AgentStack** orchestrator — CadenceLIVE 2026 April (PR). [V]

**PrimisAI**
- RapidGPT VS Code extension (marketplace, warning: may be inaccurate). Magnus backend. AIvril paper 2024-09 as verification-in-the-loop in that stack. FPGA+ASIC pair-designer. [V]

---

## 4. Academic / industry frameworks (FPGA-relevant called out)

| Framework | Year | Loop? | FPGA-specific? | Artifact | Label |
|---|---|---|---|---|---|
| Chip-Chat | 2023 MLCAD | conversational human+GPT-4 | tapeout (ASIC) | 8-bit accumulator CPU | [A] |
| VeriGen | 2023 DATE | no (SFT model) | no | CodeGen-16B | [A] |
| VerilogEval | 2023 ICCAD | eval harness | no | 156 problems | [A] |
| RTLLM | 2023–24 ASP-DAC | eval | no | 30 designs | [A] |
| AutoChip | 2023–25 | yes, iverilog | no | GitHub 61★ | [A][O] |
| ChipNeMo | 2023–24 | RAG chatbot + scripts | NVIDIA internal (could be GPU/ASIC) | not public | [V][A] |
| ChatEDA | 2023 MLCAD / TCAD 2024 | agent orchestrates EDA APIs RTL→GDSII | ASIC | AutoMage | [A] |
| RTLCoder | 2023–25 LAD/TCAD | no (SFT) | no | GitHub 310★ | [A][O] |
| AIvril | 2024-09 | AutoReview+AutoDV | no | RapidGPT stack | [A][V] |
| UVLLM | 2024-11 / DAC 2025 | UVM+repair | no | code anon. | [A] |
| VerilogCoder | AAAI 2025-04 | multi-agent + waveform AST | no | Autogen | [A] |
| LLM4DV | FCCM 2025 | coverage-directed stimulus | **yes (FCCM)** | open framework | [A] |
| HLS-Eval | ICLAD 2025 | eval | **yes (Vitis HLS)** | GitHub | [A] |
| UVM² | ICCAD 2025 | UVM gen + coverage | no | — | [A] |
| Spec2RTL-Agent | 2025-06 | spec→C++→HLS | HLS (FPGA-capable) | 3 NIST specs | [A] |
| ChatHLS | ACL 2026 | repair+directive | **yes (ZCU106)** | GitHub + HF models | [A] |
| HDLAgent | 2025-01 | reflection+EDA | multi-HDL | archived 22★ | [A][O] |
| Firefly | MLCAD 2025 | mutation testing | no | GitHub | [A] |
| HAVEN | 2026-04 | template UVM | no | — | [A] |
| UVMarvel | 2026-05 | subsystem UVM | no | GitHub SEU-ACAL | [A] |
| GoGoTB | ICCAD 2026 | full env + spec coverage | no (cocotb/Verilator portable) | to be OSS | [A] |
| AgentDV | 2026-08 | CSR DV loop | no (OpenTitan) | to be OSS | [A] |
| FPGAgent | 2026-08 | HLS to **board** | **yes** | HLS-Eval | [A] |
| FinHardBench | 2026-08 | eval (finance Verilog) | FPGA-relevant domain | arXiv:2608.00909 | [A] |

**DVCon / DAC / FCCM / FPGA:** this survey confirmed FCCM 2025 (LLM4DV), DAC 2025 (UVLLM), ICCAD 2025 (UVM²), ICLAD 2025 (HLS-Eval), MLCAD 2025 (Firefly), ACL 2026 (ChatHLS), ICCAD 2026 (GoGoTB). FPGA Symposium-specific LLM-agent papers were **not** found as a dense cluster; FPGA work lives in HLS (ChatHLS, FPGAgent, HLS-Eval) and FCCM (LLM4DV).

---

## 5. Verification-specific notes

**UVM test gen:** copy HAVEN’s split (LLM plans, templates emit). UVM²/UVMarvel show coverage-feedback stimulus. For FPGA teams without UVM licenses, **cocotb+pyUVM+Verilator** (AgentDV/GoGoTB) is the 2026 open path.

**Assertion mining:** AssertLLM/ChatSVA/AssertCoder from spec; Orenes-Vera from RTL+rules; Synopsys Formal Advisor / ChipStack Jasper skill as vendor. Always run FPV; never trust generated SVA unaudited (Orenes-Vera: 23 iterations to teach timing operators).

**Waveform/debug agents:** VerilogCoder AST waveform tracer; Cadence Verisium Debug/WaveMiner (ML, 2022+); Siemens Debug Agent (waveforms+assertions+coverage+logs, 2026-02); Synopsys debug-closure agent (DAC 2026, Microsoft Discovery). FPGA ILA: oh-my-fpga `ila-hw-debug` + AMD course.

**Mutation testing:** Firefly (LLM mutants) and AssertLLM2 (AST mutants + Jasper). Use as a **gate on the TB**, not as a generator of production RTL.

**Formal + LLM:** mature as **SVA drafting + FPV**; not mature as “prove the trading engine.” Bounded FPV on protocols/CSR/CDC-ish properties is the FPGA sweet spot.

**Stay digital:** this note does not cover AMS.

---

## 6. What is NOT mature

1. **Full autonomous RTL-to-bitstream for production trading IP.** FinHardBench: functional correctness 19–61%; synthesizable-wrong is the dangerous quadrant. VerilogEval/HDLBits pass rates do not transfer to financial datapaths.
2. **Trusting LLM timing closure.** AMD/oh-my-fpga treat timing as an **iterative, evidence-gated** assistant. Vivado IDR/RQA/RQS remain the engines. No paper or vendor doc in this survey claims an LLM replaced STA sign-off.
3. **FinHardBench failure modes to keep on the wall:**
   - compiles / synthesizes / even meets timing, **computes the wrong PnL/match/risk**
   - TB written by the same model that wrote the RTL (correlated bugs)
   - coverage on control, not on numeric corner cases (IEEE-754, saturation, rounding)
   - AgentDV AES result: CSR-level agents leave datapaths dark (~37% line)
4. **Vendor 50× / 10× / 40× numbers** — DAC/COMPUTEX 2026 marketing, early access, footnotes. Treat as **directionally interesting, not a planning assumption**.
5. **SV/UVM generated in one shot** — GoGoTB: UVM² 0% environment success on their 8-design rerun; Python TB is the working path.
6. **Quartus first-party agent** — not found. Community MCP only.
7. **“Questa One SimAI” / “Synopsys AgentAR”** — names not confirmed; do not use them in the formal report.

---

## 7. Recommended 2026 workflow for an FPGA team

Stack assumed: **Vivado and/or Quartus**, **Questa *or* VCS**, **SystemVerilog + cocotb**, financial/trading IP. Human owns golden and sign-off.

### 7.1 Tooling to install (copyable)

| Layer | Pick | Why |
|---|---|---|
| IDE agent | Cursor or Claude Code + Copilot | Siemens/AMD/Cadence all list these |
| FPGA MCP | **AMD official MCP** (if Vivado 2025.2+/2026.1) **and/or SynthPilot** (Vivado+Quartus, Chinese vendor, local) | Official docs grounding + actual Tcl execution |
| Skills | Check **oh-my-fpga** 13 skills into `.cursor/skills/` / `.claude/skills/`; write a team `golden-sim` skill | Methodology layer |
| Fast sim | **Verilator 5.x + cocotb 2.x + pytest** | Agent-parseable; GoGoTB/AgentDV stack |
| Sign-off sim | **Questa One** (if Siemens shop) or **VCS** (if Synopsys) | UVM/VIP/coverage merge |
| Formal (bounded) | **SymbiYosys** locally; **VC Formal** or **Questa Formal/SFV** or **Jasper** if licensed | LLM-drafted SVA only |
| Lint/CDC | Verilator + vendor CDC (Questa CDC Agent / SpyGlass / Vivado `report_cdc`) | oh-my-fpga `cdc-audit` |
| HLS (if C++ kernels) | Vitis HLS + ChatHLS-style CSIM/CSYN/COSIM loop | FPGA-native |
| Mutation (optional) | Firefly or simple AST mutants | Qualify the TB |

If Questa vs VCS: **do not switch simulators for AI**. Pick the vendor whose **agentic toolkit you can actually get early access to** (Questa One Agentic Toolkit since 2026-02; Synopsys AgentEngineer H2 2026). Cocotb talks to both plus Verilator.

### 7.2 Loop to adopt (CI)

```
spec.md + golden.py (human-owned, reviewed)
        │
        ▼
[agent] draft RTL + draft cocotb tests   ← never both from one unreviewed prompt
        │
        ▼
CI: verilator lint → pytest-cocotb vs frozen golden → coverage XML
        │ fail: agent patch RTL only (succinct log); n≤5; rollback if coverage↓
        ▼
human review gate (diff + coverage delta)
        │
        ▼
Questa/VCS nightly: UVM or cocotb + constrained-random + coverage merge
        │ residual bins → agent directed tests (LLM4DV / GoGoTB S8 style)
        ▼
SVA draft (AssertLLM-style from spec) → human audit → FPV on protocols/CSR
        │
        ▼
Vivado/Quartus: synth/impl via MCP; agent reads WNS/TNS/CDC; proposes XDC/strategy
        │ human accepts; never auto-waive
        ▼
bitstream only if: golden sim pass AND functional coverage plan AND WNS≥0 AND CDC clean
        │
        ▼
board: ILA skill / self-test vs golden traces  ← FPGAgent lesson
```

### 7.3 Failure modes to instrument

| Symptom | Likely cause | Mitigation |
|---|---|---|
| Synth green, sim red | FinHardBench class | frozen golden; mutation |
| Sim green, coverage hollow | UART-style silent TB (GoGoTB CS1) | spec-grounded bins; protocol knowledge pack |
| High coverage, bugs escape | Firefly 28–67% unkilled mutants | mutation gate; formal on control |
| AES/HMAC datapath dark | CSR-only agent (AgentDV) | protocol-level sequences; independent C model |
| Timing “fixed” in chat | hallucinated Tcl / stale Vivado | MCP live `report_timing`; post-impl evidence |
| Agent edits the checker | correlated TB | freeze TB; RAL from CSR map |
| Quartus job hung the IDE | 20–45 min sync build | async MCP (`quartus_build_async`) |
| HLS CSIM pass, board fail | FPGAgent thesis | COSIM + on-board exec before claiming done |

### 7.4 Team “skills” to write this week (even without SynthPilot)

Create `.cursor/skills/` (or `.claude/skills/`):
1. `verilator-loop` — exact lint/sim commands, succinct error template, n=5, never touch `tb/`.
2. `golden-gate` — pytest vs `golden.py`; fail CI on mismatch.
3. `coverage-gap` — parse Verilator coverage; prompt for one directed test.
4. `xdc-first` — timing: constraints/strategy before RTL (oh-my-fpga principle 3).
5. `cdc-never-waive` — require named synchronizer or `set_clock_groups` justification.
6. `no-bitstream-on-compile` — explicit checklist.

AMD official skills (when EA lands) and oh-my-fpga can **replace** 4–6; keep 1–3 as repo-local.

---

## 8. Uncertainties and source quality

- Vendor DAC/COMPUTEX 2026 numbers (50×, 40×, 10×) are **press-release**, often footnoted, often early-access. Independent FPGA trading-IP replication: **none found**.
- Academic pass rates are on HDLBits / VerilogEval / 8–19 open IPs / HLS-Eval. **Not** matching engines.
- MCP FPGA servers: useful, but star counts 0–109 as of 2026-08-31. SynthPilot’s “900+ engineers” is a marketing claim on their site.
- AMD MCP: Horizons (May 2026) said EA “in a few weeks”; Vitis 2026.1 docs (July 2026) show `vivado-doc-server`. How much of Vivado **execution** (vs doc search) is GA vs EA is not fully clear from public docs (AMD splash pages blocked some fetches).
- GoGoTB/AgentDV/FPGAgent are **2026-07/08 preprints**; ICCAD 2026 not yet held as of this note (conference Nov 8–12 2026). Treat as high-quality but not camera-ready.
- Intel first-party AI assistant: **not found**.
- Chinese sources: SynthPilot.cn / 简体 README of oh-my-fpga are the main Chinese-language **tooling** hits. Academic Chinese teams appear as SEU (UVLLM/UVM²/UVMarvel/ChatHLS), HKUST (RTLCoder/AssertLLM), Tsinghua/PKU/Tencent (GoGoTB). No additional mature 中文 vendor FPGA-agent flow beyond SynthPilot + AMD docs 中文 UG1702.

---

## 9. Sources (URL, title, date)

1. https://arxiv.org/abs/2311.04887 — AutoChip: Automating HDL Generation Using LLM Feedback. arXiv 2023-11-08 (HTML v2 fetched 2026-08-31). [A]
2. https://github.com/shailja-thakur/AutoChip — AutoChip repo. Fetched 2026-08-31; 61★. [O]
3. https://arxiv.org/abs/2411.11856 — Automatically Improving LLM-based Verilog Generation using EDA Tool Feedback. 2024-11. [A]
4. https://arxiv.org/abs/2311.00176 — ChipNeMo: Domain-Adapted LLMs for Chip Design. 2023-11-01. [A][V]
5. https://arxiv.org/abs/2309.07544 — VerilogEval (ICCAD 2023). [A]
6. https://arxiv.org/abs/2305.13243 — Chip-Chat (MLCAD 2023). [A]
7. https://arxiv.org/abs/2312.08617 — RTLCoder. 2023-12-14; LAD 2024 / TCAD. [A]
8. https://github.com/hkust-zhiyao/RTL-Coder — RTLCoder. Fetched 2026-08-31; 310★; created 2023-11-20. [O]
9. https://www.cse.cuhk.edu.hk/~byu/papers/J115-TCAD2024-ChatEDA.pdf — ChatEDA, IEEE TCAD Vol. 43 No. 10, Oct 2024. [A]
10. https://arxiv.org/abs/2411.16238 — UVLLM. 2024-11-25; DAC 2025. [A]
11. https://arxiv.org/abs/2504.19959 — UVM². 2025-04; ICCAD 2025. [A]
12. https://arxiv.org/html/2605.04704v1 — UVMarvel. arXiv 2605.04704, 2026-05. [A]
13. https://arxiv.org/abs/2607.26181 — GoGoTB. ICCAD 2026 (Nov 8–12 2026). [A]
14. https://arxiv.org/abs/2608.27148 — AgentDV. 2026-08. [A]
15. https://arxiv.org/abs/2409.11411 — AIvril. 2024-09. [A]
16. https://arxiv.org/abs/2506.13905 — Spec2RTL-Agent. 2025-06-16. [A]
17. https://doi.org/10.1609/aaai.v39i1.32007 — VerilogCoder, AAAI 2025, published 2025-04-11. [A]
18. https://arxiv.org/abs/2310.04535 — LLM4DV. FCCM 2025. [A]
19. https://arxiv.org/abs/2402.00386 — AssertLLM. 2024-02 (v4 HTML). [A]
20. https://arxiv.org/abs/2309.09437 — Using LLMs to Facilitate Formal Verification of RTL (Orenes-Vera). 2023-09-18. [A]
21. https://doi.org/10.1109/mlcad65511.2025.11189125 — Firefly mutation testing, MLCAD 2025. [A]
22. https://github.com/mavericnu/firefly — Firefly. Fetched via search 2026-08-31. [O]
23. https://arxiv.org/html/2507.00642v4 — ChatHLS. 2025-07; ACL 2026. [A]
24. https://github.com/GEAR-SEU/ChatHLS-ACL-26 — ChatHLS code. [O]
25. https://doi.org/10.1109/iclad65226.2025.00021 — HLS-Eval, ICLAD 2025. [A]
26. https://arxiv.org/html/2608.23630 — FPGAgent. 2026-08. [A]
27. https://arxiv.org/html/2501.00642v1 — HDLAgent. 2025-01. [A]
28. https://github.com/masc-ucsc/hdlagent — HDLAgent. 22★, ARCHIVED, created 2024-02-01. [O]
29. https://arxiv.org/html/2604.27643 — HAVEN. 2026-04. [A]
30. https://arxiv.org/html/2605.27472 — AssertLLM2. 2026-05. [A]
31. https://www.arxiv.org/pdf/2604.02811 — ChatSVA. 2026-04. [A]
32. https://news.siemens.com/en-us/questa-one-agentic-ai-toolkit/ — Siemens Questa One Agentic Toolkit. **2026-02-27**. [V]
33. https://press.siemens.com/global/en/pressrelease/siemens-leverages-ai-close-industrys-ic-verification-productivity-gap-new-questa-one — Questa One announcement. **2025-05-13**. [V]
34. https://www.siemens.com/en-us/products/ic/questa-one/ — Questa One product. Fetched 2026-08-31. [V]
35. https://www.siemens.com/en-us/products/ic/questa-one/verification-iq/ — Questa One Verification IQ. Fetched 2026-08-31. [V]
36. https://www.synopsys.com/ai/agentic-ai.html — AgentEngineer. Fetched 2026-08-31. [V]
37. https://www.synopsys.com/blogs/chip-design/synopsys-ai-copilots-chip-design.html — Synopsys.ai Copilots 2–5×. Fetched 2026-08-31 (mentions Converge 2026). [V]
38. https://news.synopsys.com/2026-03-11-Synopsys-Outlines-Vision-for-Engineering-the-Future — L4 AgentEngineer. **2026-03-11**. [V]
39. https://news.synopsys.com/2026-07-26-Synopsys-Showcases-Comprehensive-Autonomous-Engineering-Workflows-from-Silicon-to-Systems,-Developed-with-NVIDIA-Technology — DAC autonomous DV agent. **2026-07-26**. [V]
40. https://investor.synopsys.com/news/news-details/2026/Synopsys-Advances-Agentic-AI-Chip-Design-with-AMD-and-Microsoft/default.aspx — AMD+Microsoft. **2026-07-27**. [V]
41. https://www.cadence.com/en_US/home/tools/system-design-and-verification/ai-driven-verification.html — Verisium + SimAI. Fetched 2026-08-31 (platform launched 2022). [V]
42. https://www.cadence.com/en_US/home/company/newsroom/press-releases/pr/2022/cadence-revolutionizes-verification-productivity-with-the.html — Verisium launch. 2022. [V]
43. https://www.cadence.com/en_US/home/tools/system-design-and-verification/chipstack-ai-superagent.html — ChipStack AI Super Agent. Fetched 2026-08-31. [V]
44. https://www.businesswire.com/news/home/20260210926552/en/Cadence-Unleashes-ChipStack-AI-Super-Agent-Pioneering-a-New-Frontier-in-Chip-Design-and-Verification — ChipStack launch. **2026-02-10**. [V]
45. https://www.cadence.com/en_US/home/company/newsroom/press-releases/pr/2026/cadence-unveils-industrys-first-fully-autonomous-virtual.html — ChipStack L5, Computex 2026. [V]
46. https://docs.amd.com/r/en-US/ug1400-vitis-embedded/AI-Assistance-in-the-Vitis-Unified-IDE — UG1400 2026.1, **2026-07-31**. [V]
47. https://docs.amd.com/r/en-US/ug1702-vitis-accelerated-reference/Using-AI-Features-of-the-Vitis-Unified-IDE — UG1702 2026.1 AI agents + MCP. [V]
48. https://docs.amd.com/r/zh-CN/ug1702-vitis-accelerated-reference/使用-Vitis-Unified-IDE-的-AI-功能 — UG1702 中文. [V]
49. https://docs.amd.com/api/khub/documents/6Tv~vBGaVgTYr4TMKo4rhQ/content — VIVADO-AI-ASST course. Updated **2026-06-30**. [V]
50. https://www.fpgadeveloper.com/takeaways-fpga-horizons-us-east-2026/ — FPGA Horizons US East 2026 AMD workshop. **2026-05-19**. [N]
51. https://www.synthpilot.dev/ — SynthPilot. Fetched 2026-08-31; zip EOL 2026-03. [O]
52. https://github.com/LNC0831/oh-my-fpga — oh-my-fpga skills. Fetched 2026-08-31; 17★. [O]
53. https://raw.githubusercontent.com/LNC0831/oh-my-fpga/main/README.md — skill table (13). Fetched 2026-08-31. [O]
54. https://github.com/wmm246/fpga-mcp — fpga-mcp. 0★. [O]
55. https://github.com/lcapossio/fpgaZeroMCP — fpgaZeroMCP. 5★, created 2026-03-19. [O]
56. https://github.com/coreyhahn/vivado_mcp — vivado_mcp. 48★, created 2026-01-18. [O]
57. https://github.com/codejunkie99/Gateflow-Plugin — Gateflow. 109★; changelog 2026-05-21. [O]
58. https://github.com/NellyW8/MCP4EDA — MCP4EDA. 96★; arXiv:2507.19570. [A][O]
59. https://pypi.org/project/silica-eda/ — silica-eda v0.1.9. [O]
60. https://marketplace.visualstudio.com/items?itemName=PrimisAI.rapidgpt — RapidGPT. Fetched 2026-08-31. [V]
61. https://arxiv.org/html/2608.00909 — FinHardBench (known caution; ~2026-08). [A]
62. https://dl.acm.org/doi/10.1145/3746059.3747676 — agentAR (UIST 2025) — **unrelated AR paper**, listed only to reject the Synopsys “AgentAR” name. 2025. [A]
63. https://www.tessolve.com/wp-content/uploads/2024/06/4-Andy-Penrose-Verification-Futures-UK-June-24-AI-and-GenAI-for-Verification-Productivity.pdf — Cadence Verisium SimAI/FormalAI slides. June 2024. [V]
64. https://dev.to/sreevanthkg/ai-assisted-fpga-development-cursor-ide-for-tang-nano-9k-projects-did — Cursor + Tang Nano 9K. Anecdotal hobby. [N]

---

*End of notes. Do not treat vendor speedup claims or VerilogEval pass rates as production-trading-IP expectations.*
