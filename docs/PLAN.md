# Statera: master plan

This is the living plan for rewriting SPSS Statistics as a behavior-compatible, open-source Odin application. Rules for working on it are in [AGENTS.md](../AGENTS.md). Engine architecture findings from reverse engineering are in [specs/architecture.md](specs/architecture.md).

## Decisions (2026-10-26)

| Topic | Decision |
|---|---|
| Reference | IBM SPSS Statistics 25 (local licensed install). Newer versions later, as they matter. |
| RE posture | Strict clean room: analysts write specs, implementers code from specs. See AGENTS.md §2. |
| RE tooling | [rea](https://github.com/morluto/rea) + Ghidra 12.1.4 + JDK 21 + Node 24, portable in `D:\RissoProductions\tools` (outside the repo) |
| Language | Odin (dev-2026-09+) |
| UI | Dear ImGui docking branch via odin-imgui (dear_bindings), SDL3, OpenGL 3 |
| License | Apache-2.0 |
| Platforms | Windows x64, Linux x64, macOS (arm64 + x64). CI gates every push on all three. |
| Distribution | GitHub Releases with installers: Windows setup `.exe`, macOS `.dmg`, Linux AppImage + `.deb` |

## How we know we're right: golden tests

`scripts/golden/make_reference.py` runs a test case's `case.sps` through **headless SPSS** (the `spss` Python module bundled with SPSS drives the backend without the UI) and captures:
- every output table as OMS XML (full-precision `number` plus the displayed `text`)
- any files the syntax saves (`.sav`, `.zsav`, …)

Statera runs the same `case.sps`. The golden runner compares table structure, displayed text (must be exact) and numbers (within the per-procedure tolerance). Every procedure gets cases for normal data, edge cases (empty, all-missing, ties, weights, splits, huge/tiny values) and error paths.

## Architecture

```
src/
  io/         sav (done: reader), zsav, por, csv/text, xlsx      → readers/writers
  data/       Dataset: columnar variables, dictionary, case filter/weight/split state
  syntax/     lexer → parser driven by a command grammar table → command AST
  transform/  expression compiler + VM for COMPUTE/IF/RECODE/LOOP…, function library
  engine/     command dispatcher, data passes, TEMPORARY/procedure semantics, settings (SET)
  procs/      one package per command family (freq, desc, crosstabs, ttest, glm, regression…)
  numerics/   distributions, special functions, linear algebra, optimizers
  output/     pivot-table model, formats (F/COMMA/DOLLAR/DATE…), TableLooks, exporters
  automation/ CLI batch runner, MCP server, local HTTP API
  app/        ImGui application (Data View, Variable View, Syntax, Output, dialogs)
```

The engine is a library. `app/`, `automation/` and the CLI are its clients, and all of them submit **syntax** (or the equivalent command AST). This mirrors how SPSS itself works: every dialog emits syntax.

## Phases

### Phase 0: foundations ✅ mostly done
- [x] README, AGENTS.md, CLAUDE.md, license, gitignore
- [x] Golden harness driving headless SPSS
- [x] Push gate (`scripts/gate.*`) and 3-OS CI
- [x] rea + Ghidra toolchain verified
- [x] Architecture spec from RE ([specs/architecture.md](specs/architecture.md))
- [ ] Register rea as an MCP server for agent sessions

### Phase 1: data I/O
- [x] `.sav` reader: header, variables, labels, missing values, documents, measure, long names, encoding; none/bytecode/zlib compression
- [ ] very long strings (subtype 14), long-string labels/missing (21/22), MR sets (7/19), attributes (17/18)
- [x] `.sav` writer (uncompressed + bytecode), and SPSS 25 opens our files
- [ ] `.zsav` writer; byte-identical output to SPSS where it matters
- [ ] `.por` reader/writer, CSV/text (`GET DATA`/`DATA LIST`), xlsx
- [ ] Fuzzing for all readers

### Phase 2: syntax and transformations
- [x] Lexer: interactive-mode tokenization (`.` terminators, quoted strings, comments, operators)
- [ ] Lexer: batch mode / continuation lines
- [ ] Grammar-table-driven parser, written by us from the public Command Syntax Reference
- [ ] Error/warning messages with SPSS-compatible numbering
- [x] Expressions: arithmetic/logical/relational with SPSS missing semantics; numeric, statistical and missing-value functions (golden: compute_basic)
- [ ] Expressions: string, date/time and distribution functions
- [x] `GET`, `SAVE`, `COMPUTE`, `EXECUTE`
- [x] Procedure context: `WEIGHT`, `FILTER`, `SELECT IF`, `TEMPORARY`, `SORT CASES`, `SPLIT FILE` (layered/separate), golden-verified (specs/engine/procedure-context.md)
- [ ] Data commands: `DATA LIST`, `BEGIN DATA`, `RECODE`, `IF`, `DO IF`, `LOOP`, `VECTOR`, `COUNT`, `AGGREGATE`, `MATCH FILES`, `ADD FILES`, labels, missing values, formats

### Phase 3: output
- [x] Pivot-table model as flat cells with row/column paths and footnotes (matches OMS structure)
- [x] Layers, captions, label footnotes, percent cells
- [ ] Multi-category layers in the UI, corner text
- [x] Number display rules for DESCRIPTIVES/FREQUENCIES statistics (specs/output/number-display.md)
- [ ] Date/time formats, E notation, wide formats
- [ ] Exporters: OMS-compatible XML (lets us compare against golden tests directly), HTML, CSV, XLSX, PDF; `.spv` later

### Phase 4: first procedures (most-used first)
Done (golden-verified, weighted and split): `FREQUENCIES` (counts + all statistics), `DESCRIPTIVES` (all statistics), `CROSSTABS` (cells COUNT/EXPECTED/ROW/COLUMN/TOTAL; CHISQ incl. Fisher and continuity correction; PHI, Cramer's V, CC).
CROSSTABS still to do: layers (`BY a BY b`), CORR/LAMBDA/GAMMA/etc., /MISSING, /FORMAT.
Next: `MEANS`, `T-TEST`, `ONEWAY`, `CORRELATIONS`, `NONPAR CORR`, `REGRESSION`, `EXAMINE`, `NPAR TESTS`, `RELIABILITY`, `FACTOR`

### Phase 5: UI MVP
- [x] App shell: SDL3 + OpenGL3 + ImGui docking, DPI-aware fonts (Inter, JetBrains Mono)
- [x] Themes: light, dark, follow-system (live), saved per user
- [x] Data View: virtualized grid (250k demo cases), value-label toggle, user-missing/SYSMIS styling
- [ ] Data View: cell editing and type-aware editors
- [x] Variable View: dictionary display
- [ ] Variable View: editing
- [ ] Syntax editor: highlighting, grammar-aware autocomplete, error squiggles, run selection
- [ ] Output viewer: outline + pivot tables, pivoting by drag, export
- [x] Command palette (`Ctrl+K`)
- [ ] Dialogs for the Phase 4 procedures, with live syntax preview

### Phase 6: automation and AI
- [ ] `statera run file.sps` batch CLI
- [ ] MCP server (`statera mcp`, stdio + streamable HTTP): `open_dataset`, `describe_dataset`, `get_cases`, `run_syntax`, `validate_syntax`, `explain_command`, `get_output`, `export_output`
- [ ] Local JSON API (`statera serve`) + thin Python client
- [ ] Optional in-app assistant: plain language → syntax (shown before running), "explain this table"

### Phase 7: first release
- [ ] Release workflow on tag `v*`: builds on all three OSes, then attaches installers to a GitHub Release
  - Windows: Inno Setup installer (`Statera-<ver>-setup.exe`), file associations for `.sav`/`.sps`
  - macOS: `.app` bundle in a `.dmg` (universal or per-arch); signing/notarization once we have a cert
  - Linux: AppImage + `.deb`, desktop entry and MIME types
- [ ] Release notes page listing every build and checksums (SHA-256)

### Phase 8: breadth
GLM/UNIANOVA, MANOVA, MIXED, LOGISTIC REGRESSION, NOMREG, PLUM, GENLIN, COXREG, KM, SURVIVAL, CLUSTER, QUICK CLUSTER, TWOSTEP, DISCRIMINANT, CTABLES, AGGREGATE extras, time series, Bayesian, charts (GGRAPH/GPL), and the rest of the 307 commands, prioritized by user demand.

## Command inventory (SPSS 25: 307 commands)

Command names are a public interface (Command Syntax Reference). Coverage is tracked in `docs/coverage.md` (to come). The reference install implements procedures in about 127 per-family native modules. The mapping is in the architecture spec.
