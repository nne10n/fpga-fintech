# Research Directory Convention

## Topic folders

Each research deliverable is a **dated topic folder** at the repository root:

```text
<topic-slug>-YYYYMMDD-HHmm/
├── README.md      # Topic metadata (title, date, tags, one-line summary)
├── report.md      # Research report (default: full; one-pager when explicitly requested)
├── sources.md     # Required: clickable URLs + what each source supports
├── evidence/      # Optional but preferred: excerpts, fetch notes, comparison scraps (no secrets)
└── figures/       # (optional) diagrams, tables exports, screenshots
```

> **Note:** Topic folders created before this convention may lack `evidence/` or full `sources.md` structure; do not rewrite their `report.md` bodies retroactively unless explicitly asked.

### Naming

| Part | Rule |
|------|------|
| `topic-slug` | Lowercase kebab-case slug (e.g. `fpga-latency`, `exchange-matching`) |
| `YYYYMMDD` | Calendar date in **Asia/Shanghai** |
| `HHmm` | 24-hour clock time in **Asia/Shanghai** (no separator) |

**Example:** `fpga-order-book-20250916-1430/`

### Creating a new topic

1. Copy the stub template from [`_template/`](../_template/) to a new folder with the naming pattern above.
2. Fill in `README.md` metadata and write `report.md` per the deliverable mode (see below).
3. **Required:** create `sources.md` with clickable URLs and what each source supports.
4. **Recommended:** add `evidence/` with short excerpts, fetch notes, or comparison scraps (no secrets).
5. Add optional `figures/` when the report needs diagrams or exports.
6. Commit the folder; do not modify `_template/`.

---

## Research intensity

Every new report must meet a **high research bar**:

| Rule | Requirement |
|------|-------------|
| Multi-source cross-check | Key claims supported by **≥2 independent sources** when possible; note conflicts |
| Checkable mechanisms | Mechanism claims must be **verifiable** (RFC section, paper figure, manual table, patent claim) — not hand-wavy |
| No empty slogans | Avoid filler like "industry best practice" without naming the practice and citing it |
| Claim labeling | Mark every non-obvious statement as **事实** (fact), **推断** (inference), or **待核实** (to verify) |

Use source IDs (`S1`, `S2`, …) in `sources.md` and reference them inline in `report.md`.

---

## Evidence retention

Evidence must **stay in the deliverable folder** so readers can audit claims without re-fetching.

### `sources.md` (required)

- Clickable URLs (full `https://…`, not bare domain names)
- Per-source: fetch status, claim label (事实/推断/待核实), and **what it supports**
- Optional ID column (`S1`, `S2`, …) for cross-reference from `report.md`

See [`_template/sources.md`](../_template/sources.md).

### `report.md` (required)

- Tie claims to source IDs or inline links
- Include an **evidence grade** summary near the top (which sources are primary vs secondary, what remains 待核实)
- Use 事实 / 推断 / 待核实 labels in mechanism sections and comparison tables

See [`_template/report.md`](../_template/report.md).

### `evidence/` (optional but preferred)

Short-lived research artifacts that support the report:

- Fetch notes (HTTP status, section headings found, paywall blocks)
- Quoted excerpts (≤ paragraph; respect copyright — cite, don't paste whole papers)
- Comparison scraps (draft tables, side-by-side notes before they land in `report.md`)

**Do not** store secrets (API keys, credentials, private URLs). See [`_template/evidence/README.md`](../_template/evidence/README.md).

---

## Deliverable modes

### Default — full detailed report

Unless the task explicitly says「一页纸」/ one-pager, write a **full** `report.md`. Length is not capped; prioritize completeness over brevity.

Expected coverage:

- Background and scope (In / Out)
- Stated assumptions and open parameters
- Mechanism sections (one subsection per major approach or design axis)
- Comparison tables (trade-offs, when to use which)
- Conventions, pitfalls, and migration triggers
- Open options / follow-ups
- References (inline source IDs and/or `sources.md`)

### One-pager mode

When the task **explicitly** requests「一页纸」/ one-pager, use the same folder layout but force `report.md` to **one printed page** (~500–700 words) with a compressed structure (question, findings, implications, references).

**Still required:** `sources.md` and claim labeling. `evidence/` remains recommended.

---

## File templates

### `README.md` (topic metadata)

```markdown
# <Topic Title>

- **Slug:** `<topic-slug>`
- **Date (Asia/Shanghai):** YYYY-MM-DD HH:mm
- **Tags:** fpga, fintech, …
- **Summary:** One sentence describing the research question and conclusion.

## Links

- (optional) related repos, papers, or prior reports
```

### `report.md` (default — full report)

Use the section outline in [`_template/report.md`](../_template/report.md). May include multiple mechanism subsections, tables, and assumptions; length is open.

### `report.md` (one-pager mode)

Keep to **one printed page** (~500–700 words). Suggested sections:

```markdown
# <Topic Title>

## Question

What are we investigating?

## Findings

Key facts, data points, or architecture notes.

## Implications

What this means for FPGA / fintech work.

## References

- …
```

---

## Template path

Copy from:

```text
_template/
├── README.md
├── report.md
├── sources.md
└── evidence/
    └── README.md
```

Do not add sample research content to `_template/`; it remains empty stubs for future agents and contributors.
