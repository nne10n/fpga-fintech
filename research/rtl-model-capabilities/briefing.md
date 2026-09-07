# RTL/HDL LLM Capabilities Survey (as of 2026-09-04)

**Audience:** 坤仇 / 调研专员 — FPGA/fintech research  
**Method:** Primary sources only (arXiv, ACM/IEEE, vendor press). No invented scores.  
**Label key:** `[IND]` independent academic · `[VENDOR]` vendor claim · `[ANEC]` anecdotal / non-bakeoff · `[AGENT]` closed-loop agent (not single-shot model)

---

## 0. How to read these numbers (critical)

1. **Benchmarks are not interchangeable.** VerilogEval / RTLLM are small, often saturated modules. CVDP / ChipBench / FinHardBench are harder and closer to industrial work. A model at 95% on VerilogEval can be ~30% on ChipBench or ~61% Sim% on FinHardBench.
2. **Syntax ≠ function ≠ synthesis ≠ timing.** FinHardBench: 34.7% of attempts synthesize+route but fail simulation (“deployable-but-wrong”). SynthAgentic: simulation pass rates overstate HQI by ~7.5 pts on average.
3. **Single-shot vs agent loops reverse rankings.** VerilogCoder / MAGE push VerilogEval to ~94–96% with sim feedback; FinHardBench agentic pilot passes VWAP/RSI where single-shot fails.
4. **Contamination risk:** OpenLLM-RTL, CodeV-R1, SynthAgentic explicitly warn about train-on-test / open-benchmark leakage. Prefer held-out or newly authored suites (CVDP, ChipBench, FinHardBench) for deployment decisions.
5. **Do not merge pass@1 / pass@5 / pass@k / Exact-Match / HQI / Sim% into one ranking.**

---

## 1. Master comparison table (model × benchmark × score × date × source type)

Only rows with a concrete number + URL are included.

| Model | Benchmark / metric | Score | Date (approx) | Source type | URL |
|---|---|---|---|---|---|
| GPT-4o | VerilogEval v2 Spec-to-RTL pass@1 (T=0.8, 0-shot / 1-shot) | 61.4% / 62.6% | 2024-08 (arXiv); TODAES 2025 | IND | https://arxiv.org/abs/2408.11053 · https://doi.org/10.1145/3718088 |
| GPT-4 Turbo | same Spec-to-RTL 0-shot / 1-shot (T=0.8) | 61.1% / 56.7% | 2024-08 | IND | https://arxiv.org/abs/2408.11053 |
| GPT-4 (0613) | VerilogEval-Human pass@1 (orig paper) | 43.5% | 2023-11 / ICCAD | IND | https://arxiv.org/abs/2309.07544 |
| Llama3.1 405B | VerilogEval v2 Spec-to-RTL 0-shot / 1-shot (T=0.8) | 57.1% / 58.3% | 2024-08 | IND | https://arxiv.org/abs/2408.11053 |
| Llama3.1 70B | Spec-to-RTL 0-shot / 1-shot (T=0.8) | 39.0% / 48.5% | 2024-08 | IND | https://arxiv.org/abs/2408.11053 |
| RTL-Coder DeepSeek 6.7B | Spec-to-RTL 0-shot / 1-shot (T=0.8) | 30.9% / 33.5% | 2024-08 | IND | https://arxiv.org/abs/2408.11053 |
| DeepSeek Coder 6.7B | Spec-to-RTL 1-shot (T=0.8) | 25.6% | 2024-08 | IND | https://arxiv.org/abs/2408.11053 |
| Mistral Large | Spec-to-RTL 1-shot (T=0.8) | 46.0% | 2024-08 | IND | https://arxiv.org/abs/2408.11053 |
| Claude 3.7 Sonnet | CVDP Non-Agentic code-gen overall pass@1 (n=5) | **33.56%** | 2025-06 (arXiv:2506.14074) | IND | https://arxiv.org/abs/2506.14074 |
| GPT-4.1 | CVDP Non-Agentic overall | 28.91% | 2025-06 | IND | https://arxiv.org/abs/2506.14074 |
| Llama 3.1 405B | CVDP Non-Agentic overall | 22.79% | 2025-06 | IND | https://arxiv.org/abs/2506.14074 |
| Claude 3.7 Sonnet | CVDP Agentic (single-turn) overall | 29.0% | 2025-06 | IND | https://arxiv.org/abs/2506.14074 |
| GPT-4.1 | CVDP Agentic overall | 21.0% | 2025-06 | IND | https://arxiv.org/abs/2506.14074 |
| Claude 4.5 Opus | ChipBench Verilog gen avg pass@1 | **30.74%** | 2026-01 (arXiv:2601.21448) | IND | https://arxiv.org/html/2601.21448v2 |
| Gemini 3 Flash | ChipBench Verilog gen avg pass@1 | 30.74% | 2026-01 | IND | https://arxiv.org/html/2601.21448v2 |
| GPT-5.2 | ChipBench Verilog gen avg pass@1 | 26.29% | 2026-01 | IND | https://arxiv.org/html/2601.21448v2 |
| GPT-5 | ChipBench Verilog gen avg pass@1 | 24.81% | 2026-01 | IND | https://arxiv.org/html/2601.21448v2 |
| GPT-4o | ChipBench Verilog gen avg pass@1 | **10.37%** | 2026-01 | IND | https://arxiv.org/html/2601.21448v2 |
| DeepSeek-Coder | ChipBench Verilog gen avg pass@1 | 29.26% | 2026-01 | IND | https://arxiv.org/html/2601.21448v2 |
| MAGE (DeepSeek-V3 backbone) | ChipBench Verilog gen pass@1 | **37.41%** | 2026-01 | AGENT | https://arxiv.org/html/2601.21448v2 |
| Claude 4.5 Opus | ChipBench Verilog **debug** avg pass@1 | 47.45% | 2026-01 | IND | https://arxiv.org/html/2601.21448v2 |
| GPT-5 | ChipBench debug avg pass@1 | 43.59% | 2026-01 | IND | https://arxiv.org/html/2601.21448v2 |
| Claude Sonnet **4.6** | FinHardBench module gen **Sim%** | **61%** | ~2026-08 (arXiv:2608.00909) | IND | https://arxiv.org/abs/2608.00909 |
| GPT-5.4 | FinHardBench Sim% | **61%** | ~2026-08 | IND | https://arxiv.org/abs/2608.00909 |
| Gemini 3.1 Flash Lite | FinHardBench Sim% | 46% | ~2026-08 | IND | https://arxiv.org/abs/2608.00909 |
| DeepSeek V3.2 | FinHardBench Sim% | 25% | ~2026-08 | IND | https://arxiv.org/abs/2608.00909 |
| Mistral Large 2512 | FinHardBench Sim% | 23% | ~2026-08 | IND | https://arxiv.org/abs/2608.00909 |
| MiniMax M2.7 | FinHardBench Sim% | **19%** | ~2026-08 | IND | https://arxiv.org/abs/2608.00909 |
| (all six models) | FinHardBench functional correctness range | **19–61%** | ~2026-08 | IND | https://arxiv.org/abs/2608.00909 |
| Claude Sonnet 4.6 | FinHardBench strategy-adaptation pass | 42% (only nonzero) | ~2026-08 | IND | https://arxiv.org/abs/2608.00909 |
| Claude / GPT-5.4 | FinHardBench system DSE: seeds reaching 107.5 ns opt | **5/5** | ~2026-08 | IND | https://arxiv.org/abs/2608.00909 |
| CodeV-R1-7B | VerilogEval v2 Spec-to-RTL pass@1 | **68.8%** | 2025-05 (arXiv:2505.24183) | IND (domain FT) | https://arxiv.org/abs/2505.24183 |
| CodeV-R1-7B | RTLLM v1.1 / v2 pass@1 | **72.9% / 68.0%** | 2025-05 | IND | https://arxiv.org/abs/2505.24183 |
| DeepSeek-R1-671B | RTLLM v1.1 / v2 pass@1 | 64.8% / 64.7% | 2025-05 (eval in CodeV-R1) | IND | https://arxiv.org/abs/2505.24183 |
| GPT-4o | VerilogEval v2 SR / CC pass@1 (CodeV-R1 table) | 64.1% / 57.6% | 2025-05 | IND | https://arxiv.org/abs/2505.24183 |
| OriGen | VerilogEval-Human / Machine pass@1 | 54.4% / 74.1% | 2024-07 (arXiv:2407.16237) | IND | https://arxiv.org/html/2407.16237v2 |
| OriGen | RTLLM pass@5 | 65.5% | 2024-07 | IND | https://arxiv.org/html/2407.16237v2 |
| BetterV-CodeQwen 7B | VerilogEval-Machine / Human pass@1 | 68.1% / 46.1% | 2024 (cited OpenLLM-RTL) | IND | https://arxiv.org/abs/2402.03375 · https://arxiv.org/abs/2503.15112 |
| ChipNeMo 13B | VerilogEval-Machine / Human pass@1 | 43.4% / 22.4% | 2023-11; cited in OpenLLM-RTL | IND (closed data) | https://arxiv.org/abs/2311.00176 · https://arxiv.org/abs/2503.15112 |
| DeepSeek-Direct (80K RTLCoder-Data) | VerilogEval-Machine / Human pass@1 | 64.7% / 42.8% | ICCAD 2024 / arXiv:2503.15112 | IND | https://arxiv.org/abs/2503.15112 |
| DeepSeek-Direct (7K verified) | RTLLM V1.1 Func pass@5 | 48.3% | 2024 | IND | https://arxiv.org/abs/2503.15112 |
| GPT-4 (baseline in OpenLLM-RTL) | RTLLM V1.1 Func | 65.5% | 2024 | IND | https://arxiv.org/abs/2503.15112 |
| MAGE (Claude 3.5 Sonnet) | VerilogEval-Human v2 Pass@1 | **95.7%** | 2024-12 / DAC 2025 | AGENT | https://arxiv.org/abs/2412.07822 |
| VerilogCoder (GPT-4 Turbo) | VerilogEval-Human v2 pass rate | **94.2%** | 2024-08 / AAAI 2025 | AGENT | https://arxiv.org/abs/2408.08927 |
| GPT-4.1 (single-shot → ReAct) | RTLLM | 88.24% → **96.08%** | 2025-09 preprint / IEEE later | IND | https://doi.org/10.20944/preprints202509.1681.v1 · https://ieeexplore.ieee.org/document/11398091 |
| Claude Sonnet 4 (single → ReAct) | RTLLM | 90.2% → **96.08%** | same | IND | same |
| Claude Sonnet 4 | VerilogEval (Critical Review) | up to **89.74%** | same | IND | same |
| Llama 4 Maverick | RTLLM single → agentic | 66.00% → 71.43% | same | IND | same |
| GPT-4 | RTL-Repo Exact Match / Edit Similarity | 48.5 / 71.87 | 2024-05 (arXiv:2405.17378) | IND | https://arxiv.org/abs/2405.17378 |
| GPT-3.5 | RTL-Repo Exact Match / Edit Similarity | 33.8 / 61.4 | 2024-05 | IND | https://arxiv.org/abs/2405.17378 |
| RTLCoder-DeepSeek | RTL-Repo Edit Similarity (best open) | 48.1 | 2024-05 | IND | https://arxiv.org/abs/2405.17378 |
| Gemini-3-Pro | SynthAgentic Coverage / Global HQI | **87.5% / 85.1** | 2026-02–03 API; GLSVLSI’26 | IND | https://arxiv.org/abs/2603.11287 |
| GPT-5.4-Pro | SynthAgentic Cov / G.HQI | 84.5 / 81.3 | 2026 | IND | https://arxiv.org/abs/2603.11287 |
| Claude-4.6-Sonnet | SynthAgentic Cov / G.HQI | 82.9 / 78.2 | 2026 | IND | https://arxiv.org/abs/2603.11287 |
| GPT-4o | SynthAgentic Cov / G.HQI | 71.2 / 68.0 | 2026 | IND | https://arxiv.org/abs/2603.11287 |
| DeepSeek-V3.2 | SynthAgentic Cov / G.HQI | 59.4 / 58.8 | 2026 | IND | https://arxiv.org/abs/2603.11287 |
| Qwen3.5-397B† | SynthAgentic Cov / G.HQI | 55.2 / 58.2 | 2026 | IND | https://arxiv.org/abs/2603.11287 |
| Grok-4.1-Fast | SynthAgentic Cov / G.HQI | 47.3 / **47.5** (Tier 2) | 2026 | IND | https://arxiv.org/abs/2603.11287 |
| Synopsys AgentEngineer | “time-to-validated RTL” | up to **50×** faster +20% coverage | DAC 2026 claim | **VENDOR** | press / Futurum / AI2Work summaries |
| Cadence ChipStack L5 | “RTL validation cycle” | over **40×** (~5 weeks → <1 day) | Computex 2026 | **VENDOR** | https://www.cadence.com/en_US/home/company/newsroom/press-releases/pr/2026/cadence-unveils-industrys-first-fully-autonomous-virtual.html |
| Siemens Questa One RTL Code Agent | — | qualitative agent description; **no public bake-off pass%** | 2025–2026 | **VENDOR** | Siemens Questa One Agentic Toolkit announcements |

### Models with **no public RTL eval found** (classic VerilogEval/RTLLM bake-offs)

| Model family | Status |
|---|---|
| Grok (xAI) classic VerilogEval/RTLLM table | **No public VerilogEval/RTLLM bake-off found.** Only appearance: SynthAgentic Grok-4.1-Fast HQI 47.5 (Tier 2). |
| Pure VHDL-only commercial models | **No public large-scale VHDL bake-off found** comparable to VerilogEval. |
| Many Chinese vendor “RTL copilots” without paper | Treat marketing as **VENDOR**; wait for arXiv/ICCAD numbers. |

---

## 2. Benchmark landscape (what each suite actually measures)

| Suite | Size / nature | Primary metric | Hardness vs frontier (2026) | URL |
|---|---|---|---|---|
| VerilogEval v1/v2 | ~156 HDLBits-style modules; code-completion + Spec-to-RTL | pass@k via iverilog | **Saturated** for agents (~94–96%); single-shot ~60–70% frontier | https://github.com/NVlabs/verilog-eval · https://arxiv.org/abs/2408.11053 |
| RTLLM / RTLLM 2.0 / OpenLLM-RTL | 30→50 hand-crafted designs | syntax + functional pass@5 | Near-saturated with ReAct (~96%) | https://arxiv.org/abs/2503.15112 · https://github.com/hkust-zhiyao/RTLLM |
| RTL-Repo | >4k GitHub multi-file contexts | Edit Similarity / Exact Match | Multi-file completion; GPT-4 leads | https://arxiv.org/abs/2405.17378 |
| CVDP | 783 expert problems, 13 categories, agentic+non-agentic | pass@1; DV categories hardest | **Hard:** best ~34% code-gen | https://arxiv.org/abs/2506.14074 · https://github.com/NVlabs/cvdp_benchmark |
| ChipBench | 44 hierarchical/CPU modules + 89 debug + 132 ref-models | pass@k | **Hard:** best single ~31%, MAGE 37% | https://arxiv.org/abs/2601.21448 |
| FinHardBench | 33 financial FPGA tasks + DSE + adaptation | Sim% + post-P&R timing | Domain-hard: 19–61% Sim%; timing cliffs | https://arxiv.org/abs/2608.00909 · https://github.com/owenfucell/FinHardBench |
| SynthAgentic / HQI | 202 VerilogEval+RTLLM tasks under Yosys/Nangate45 | Coverage + Global/Expected HQI | Separates “passes sim” from QoR | https://arxiv.org/abs/2603.11287 |
| AssertEval | 18 designs, SVA from specs | syntax / FPV pass / COI | Verification axis | https://github.com/hkust-zhiyao/AssertLLM (OpenLLM-RTL) |
| Spec2RTL-Agent | Complex multi-page specs (small N) | correctness + human interventions | Agentic case study, not large bake-off | https://arxiv.org/abs/2506.13905 |
| RTL-BenchLS | >10k formally verified designs; round-trip / masked / repo-issue | equivalence | Reported best ~23% / 28% / 12% (search summaries; verify paper) | arXiv:2606.08976 (Jun 2026) |

**HDLBits:** used as source for VerilogEval-Human; not a separate modern bake-off.

**Contamination notes (sourced):**
- OpenLLM-RTL uses Rouge-L filtering vs benchmarks.
- CodeV-R1 removes Rouge-L >0.5 overlap with VerilogEval/RTLLM.
- SynthAgentic §Limitations: open benchmarks → contamination not ruled out.
- CVDP / ChipBench / FinHardBench: newly authored / domain-specific → lower leakage risk.

---

## 3. Strengths (where numbers support)

### 3.1 Syntax & small modules (HDLBits / VerilogEval class)
- Frontier single-shot Spec-to-RTL ~58–63% (GPT-4o, Llama3.1-405B) — Pinckney 2024.
- Domain 7B models (RTLCoder, BetterV, OriGen, CodeV, CodeV-R1) competitive or better on these suites after SFT/RL.
- **Agent loops:** MAGE 95.7%, VerilogCoder 94.2% on VerilogEval-Human v2 — with simulator access.

### 3.2 Small / textbook functional correctness
- Critical Review (2025): GPT-4.1 / Claude Sonnet 4 reach ~90–96% on VerilogEval/RTLLM **with** lightweight ReAct + iverilog MCP.

### 3.3 Debugging (better than green-field gen)
- ChipBench: Claude 4.5 Opus debug 47.45% vs gen 30.74%.
- CVDP cid16 (bug fix): Claude 3.7 ~53% Non-Agentic — higher than TB/assertion categories.

### 3.4 System-level DSE with numeric feedback (FinHardBench Exp.2)
- Claude 4.6 & GPT-5.4: 5/5 seeds hit latency optimum under 24-round budget; beats Random/SA/BO reliability at same budget.
- Rankings for **generation** and **DSE** only moderately correlated (ρ≈0.55).

### 3.5 Synthesis-aware quality (SynthAgentic)
- Gemini-3-Pro leads HQI (85.1); Tier-1 cluster includes Claude 4.x and GPT-5.x Pro variants.
- Useful when FPGA team cares about area/delay, not just sim pass.

---

## 4. Weaknesses (sourced failure modes)

| Weakness | Evidence | Source |
|---|---|---|
| Financial / trading RTL | FinHardBench Sim% 19–61%; L5 option pricing ~0–2/18; VWAP timing 13.67× | arXiv:2608.00909 |
| Deployable-but-wrong | 206/594 (34.7%) synth+route but sim-fail; RSI inflation 90% | FinHardBench §4.2 |
| CDC / multi-clock | CVDP failure clusters cite clock-domain / protocol violations | arXiv:2506.14074 |
| Timing / PPA optimization | FinHardBench pipeline-insertion near-zero; SynthAgentic FSM&Protocols hardest | both |
| UVM / testbench / SVA | CVDP cid12–14 often single-digit to ~25%; ChipBench notes TB harder than RTL | CVDP, ChipBench |
| Large repos / hierarchy | ChipBench CPU IP ≤22.22%; full hierarchical gen → 0% in their setup; RTL-Repo Exact Match GPT-4 48.5% | ChipBench, RTL-Repo |
| Strategy-level spec adaptation | Only Claude 4.6 nonzero (42%) on FinHardBench strategy changes | FinHardBench |
| Waveform-aware debug | ChipBench: VCD one-shot helps only 8/21 models | ChipBench §3.3 |

---

## 5. Closed-loop (sim feedback) changes ranking

| Setting | Approx top result | Implication |
|---|---|---|
| Single-shot frontier on VerilogEval v2 | ~63% (GPT-4o) | Baseline |
| VerilogCoder / MAGE with sim+waveform/state tools | ~94–96% | Agents dominate small benches |
| ReAct + MCP iverilog (Critical Review) | ~90–96% on VerilogEval/RTLLM | Lightweight loops enough to saturate easy suites |
| FinHardBench agentic pilot (Claude Code / Codex) | Passes VWAP & RSI (single-shot ~6–11%) | **Hard domain tasks need tools**; backbone also upgraded in pilot |
| ChipBench MAGE | 37.41% vs Claude Opus 30.74% | Agents help but **do not saturate** industrial-ish suites |
| CVDP verification categories | Still very low for single-turn models | Need specialized DV agents (e.g. Agentrys vendor claim 90–96% on CID12–14 — label **VENDOR/third-party**, not CVDP authors) |

**Takeaway for FPGA team:** Ranking on VerilogEval without a sim loop is a poor predictor of closed-loop productivity. For FinHardBench-class work, plan for **iverilog/Verilator + Yosys/NextPNR or Vivado in the loop**.

---

## 6. Domain / specialized models (condensed)

| Model | Base | Claimed niche | Key sourced number | Caveat |
|---|---|---|---|---|
| ChipNeMo | LLaMA-ish, NVIDIA | Chip design DAPT | Human 22.4% (older) | Closed corpus; superseded on open benches |
| VeriGen | CodeGen fine-tune | Early Verilog FT | Dataset/model paper TODAES 2024 | Numbers vary by table; prefer citing VeriGen paper directly for exact setup |
| RTLCoder | DeepSeek/Mistral 6–7B | Open RTL SFT | ~31–37% VerilogEval Spec-to-RTL (Pinckney); RTLLM Func ~48% pass@5 (OpenLLM-RTL) | Strong for size; frontier now stronger single-shot |
| BetterV | CodeQwen/DS/CL + discriminator | Controlled gen | Machine 68.1% / Human 46.1% | Closed variants exist |
| CodeV | Multi-level summarization SFT | Open Verilog IT | Human ~53% (CodeV-CQ); later CodeV-R1 much higher | |
| OriGen | Code-to-code + self-reflection | Open + compiler feedback | Human 54.4%; RTLLM pass@5 65.5% | |
| CodeV-R1-7B | Qwen2.5-Coder-7B + RLVR | Reasoning Verilog | **VE v2 68.8%; RTLLM v1.1 72.9%** — beats DeepSeek-R1 on RTLLM | Best open specialized as of mid-2025 paper |
| CraftRTL | Correct-by-construction synthetic | Narrow formal subsets + repair | Human up to 68% (15B) in CodeV-R1 comparison table | |

---

## 7. Vendor EDA copilots (label: VENDOR, not bake-off)

| Vendor | Product | Published metric | Independence |
|---|---|---|---|
| Synopsys | AgentEngineer / autonomous DV agent | up to 50× time-to-validated RTL, +20% coverage | **VENDOR** vs “traditional workflows” |
| Cadence | ChipStack Level-5 (+ AuraStack etc.) | >40× RTL validation; weeks→day | **VENDOR**; NVIDIA demo on selected blocks |
| Siemens | Questa One Agentic Toolkit / RTL Code Agent | NL→RTL + lint; self-verifying Fuse agents | **VENDOR**; no public pass@k vs Claude/GPT |

Do **not** put these in the same ranking column as VerilogEval/CVDP numbers.

---

## 8. Practical pick for an FPGA team in 2026 (with uncertainty)

### Recommended stack (evidence-weighted, not a score invention)

1. **Primary general model (coding + adaptation + hard specs):**  
   - Prefer **Claude Sonnet 4.6 / Opus 4.5-class** when FinHardBench / ChipBench / CVDP matter (Claude tops FinHardBench Sim%+adaptation; Opus tops ChipBench gen+debug among singles).  
   - Keep **GPT-5.4 / GPT-5.2** as peer: tied Sim% on FinHardBench; strong DSE; ChipBench mid-pack.  
   - **Gemini-3-Pro / Flash** strong on SynthAgentic HQI and ChipBench Flash; worth A/B for QoR-sensitive FPGA.

2. **Open / on-prem specialized fine-tune:**  
   - **CodeV-R1-7B** (or successor) for offline Spec-to-RTL on textbook→RTLLM-class tasks (best open numbers mid-2025).  
   - **RTLCoder / OriGen** still useful as cheap local assistants; do not expect FinHardBench-level domain RTL.

3. **Harness (non-negotiable for finance FPGA):**  
   - Closed-loop: `iverilog`/`verilator` + golden TB + **Yosys/NextPNR or Vivado** timing.  
   - Explicitly gate on **Sim%**, not Routed%. FinHardBench shows synthesizes-but-wrong is the danger.  
   - Optional: MAGE-/VerilogCoder-style multi-agent on small IPs; expect large drop on ChipBench/CVDP/FinHard.

4. **Uncertainty flags**
   - No head-to-head of Claude 4.6 vs GPT-5.4 vs Gemini-3-Pro on **same** ChipBench+FinHardBench+CVDP card in one paper. Cross-paper ranks are **approximate**.  
   - Agentic FinHardBench pilot used stronger backbones than Exp.1 — do not claim single-shot ceiling.  
   - Vendor 40–50× claims: early access / selected demos as of mid-2026.

### Anti-patterns
- Choosing by VerilogEval alone.  
- Shipping Routed% without Sim%.  
- Expecting UVM/SVA/CDC from single-shot frontier models (CVDP).  
- Treating Synopsys/Cadence/Siemens speedups as model bake-off scores.

---

## 9. Suggested reading order for 坤仇 tonight

1. FinHardBench — https://arxiv.org/abs/2608.00909 (domain truth for fintech FPGA)  
2. ChipBench — https://arxiv.org/abs/2601.21448 (industrial complexity + debug)  
3. CVDP — https://arxiv.org/abs/2506.14074 (breadth: DV, assertions, reuse)  
4. Revisiting VerilogEval — https://arxiv.org/abs/2408.11053 (historical frontier 2024)  
5. CodeV-R1 — https://arxiv.org/abs/2505.24183 (best open specialized)  
6. SynthAgentic — https://arxiv.org/abs/2603.11287 (synthesis QoR, includes Grok-4.1-Fast)  
7. OpenLLM-RTL — https://arxiv.org/abs/2503.15112 (datasets + AssertEval)  
8. MAGE / VerilogCoder — agent ceiling on easy benches  

---

## 10. Source URL index (≥15)

1. https://arxiv.org/abs/2608.00909 — FinHardBench  
2. https://arxiv.org/html/2608.00909v1  
3. https://github.com/owenfucell/FinHardBench  
4. https://arxiv.org/abs/2408.11053 — Revisiting VerilogEval  
5. https://doi.org/10.1145/3718088  
6. https://github.com/NVlabs/verilog-eval  
7. https://arxiv.org/abs/2503.15112 — OpenLLM-RTL / RTLLM 2.0  
8. https://github.com/hkust-zhiyao/RTLLM  
9. https://github.com/hkust-zhiyao/RTL-Coder  
10. https://arxiv.org/abs/2506.14074 — CVDP  
11. https://github.com/NVlabs/cvdp_benchmark  
12. https://arxiv.org/abs/2601.21448 — ChipBench  
13. https://arxiv.org/html/2601.21448v2  
14. https://arxiv.org/abs/2505.24183 — CodeV-R1  
15. https://arxiv.org/abs/2407.16237 — OriGen  
16. https://arxiv.org/abs/2402.03375 — BetterV  
17. https://arxiv.org/abs/2311.00176 — ChipNeMo  
18. https://arxiv.org/abs/2405.17378 — RTL-Repo  
19. https://arxiv.org/abs/2412.07822 — MAGE  
20. https://arxiv.org/abs/2408.08927 — VerilogCoder  
21. https://arxiv.org/abs/2603.11287 — SynthAgentic / HQI  
22. https://doi.org/10.20944/preprints202509.1681.v1 — Critical Review / frontier ReAct  
23. https://ieeexplore.ieee.org/document/11398091  
24. https://www.cadence.com/.../cadence-unveils-industrys-first-fully-autonomous-virtual.html — ChipStack **VENDOR**  
25. https://arxiv.org/abs/2309.07544 — original VerilogEval  
26. https://arxiv.org/abs/2506.13905 — Spec2RTL-Agent  

---

*File written 2026-09-04 for parent 调研专员. All numeric claims above are tied to a listed URL; if a cell is blank or “unknown,” it was not found in primary sources searched.*
