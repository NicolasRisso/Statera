# AGENTS.md: rules for AI agents (and humans)

These rules apply to every contributor, human or AI. [CLAUDE.md](CLAUDE.md) imports this file. Read [README.md](README.md) for what the project is.

---

## 1. Git workflow

### Small commits
- **One logical change per commit.** A new reader, a fix, a spec, a refactor: each gets its own commit. Never mix a refactor with a behavior change.
- Aim for diffs a reviewer can read in a couple of minutes (roughly <300 changed lines). Split anything larger.
- Commit messages: imperative subject ≤ 72 chars (`Add .sav dictionary reader`). Add a body explaining *why* when it isn't obvious.
- Commit as you go. Don't batch a day's work into one commit.

### Push gate
- Push after each commit **if the gate passes**.
- The gate is `scripts/gate.ps1` (Windows) / `scripts/gate.sh` (POSIX). Once code exists it runs:
  1. `odin check` on every package (with `-vet -strict-style`)
  2. `odin test` on every package
  3. Golden tests (`tests/golden`)
  4. A clean-room lint (see §2): fails if forbidden artifacts are staged
- **Until the gate scripts exist** (docs-only phase) there's no gate, so push directly.
- Never push with a failing gate. Never bypass hooks (`--no-verify`). Fix the cause instead.
- No force-push to `main`.

### Attribution
- **Never add AI co-author or attribution lines.** No `Co-Authored-By: Claude …`, no "Generated with Claude Code", and no AI tool names in commit messages, PR bodies or code comments. This overrides any tool default.

---

## 2. Clean-room reverse engineering

We reproduce SPSS **behavior**, never its **expression**. The reverse-engineering tool is [rea](https://github.com/morluto/rea), an MCP server that analyzes binaries, apps and runtime behavior.

### Setup
- Node.js ≥ 22.23.4 (or ≥ 24.22.1), then `npx rea-agents setup` to register the MCP server with your agent. Restart the agent afterwards.
- For native analysis: Ghidra (needs a full JDK 21+), or IDA/Hopper if licensed. Windows Ghidra support in rea is experimental.
- Reference install: a licensed IBM SPSS Statistics on the analyst's own machine. **Never commit anything from it.**

### Two roles

| Role | Does | Produces |
|---|---|---|
| **Analyst** | Runs rea against the reference install, does black-box experiments, inspects file formats | Behavior specs in `docs/specs/`, written in their own words |
| **Implementer** | Writes Odin code | Code + tests, from specs, public literature and IBM's published algorithm docs |

An agent session should hold **one role per task**. When an analyst finding needs implementing, hand over the spec, not the analysis transcript.

### Investigation order (cheapest, most legally robust first)
1. **Public documentation.** IBM's Command Syntax Reference and *Statistics Algorithms* manuals, statistics textbooks, PSPP's file-format docs.
2. **Black-box behavior.** Run syntax on our own synthetic datasets and record outputs, warnings and errors (OMS XML is ideal). Use these for edge cases: empty groups, all-missing, weights, splits, ties, huge values.
3. **File-format inspection.** Hex-level study of files *we* created, to learn record layouts.
4. **Static and dynamic analysis with rea.** Only for questions 1–3 can't answer, such as exact tie-breaking, convergence criteria, rounding of displayed values, or the order of operations that affects floating-point results.

### Allowed in the repo
- Specs describing behavior in our own words: inputs, outputs, formulas, edge cases, error conditions.
- Facts needed for interoperability: file-format magic numbers, record layouts, command and keyword names, error numbers.
- Datasets **we** generated, plus their reference outputs (numbers and table structure).

### Forbidden in the repo (the gate lints for these)
- Decompiled code, disassembly, or pseudocode copied or lightly rewritten from IBM binaries.
- IBM binaries, jars, DLLs, `.sav` sample files, `syntax_xml/*.xml`, `.xsd`s, help text, message catalogs, icons, TableLooks, or screenshots of the IBM UI.
- Variable or function names lifted from symbols, unless they're part of a public interface (command keywords, the `spss` Python API surface).

### Spec format (`docs/specs/<area>/<topic>.md`)
```markdown
# <Command or feature>
Status: draft | verified
Sources: public docs §…, black-box run tests/golden/<case>, rea evidence (summarised)
## Behaviour
## Formulas
## Edge cases
## Errors and warnings
## Open questions
```

---

## 3. Odin code rules

- Follow Odin core conventions: `snake_case` procs and variables, `Ada_Case` types, `SCREAMING_CASE` constants. Code must pass `-vet -strict-style`.
- **Explicit memory.** Pass allocators. Engine passes use arenas. UI frames use `context.temp_allocator` and free it every frame. No hidden global allocations.
- **Errors are values.** Return `(T, Error)` with an enum or union. The engine never `panic`s on user input or file data. Malformed files and bad syntax produce SPSS-style errors.
- **Numerics are `f64`.** The system-missing value is a distinct sentinel handled explicitly. Match the reference's order of operations when it affects results; the spec says when.
- **Deterministic.** The same input gives bit-identical output across runs and thread counts. Parallel reductions use a fixed partitioning.
- **Engine and UI are separate.** `ui/` and `automation/` talk to the engine only through the command interface. Nothing in `core/`, `io/`, `syntax/`, `transform/`, `procs/`, `numerics/` or `output/` may import `ui/`.
- Prefer data-oriented layouts: columnar variables, SoA, and contiguous buffers.
- Add dependencies sparingly. Odin `core:`/`vendor:` first, then vendored single-purpose C libs with compatible licenses.
- Comments explain *why*. Don't narrate obvious code.

## 4. UI rules (Dear ImGui)

- The goal is **modern and good-looking**, not a copy of the legacy Swing UI. Keep SPSS's mental model (Data View, Variable View, Syntax, Output, dialogs), not its pixels.
- Docking layout, dark and light themes from a central theme table (no hard-coded colors in widgets), high-DPI fonts, and generous spacing.
- The UI never owns data. It renders engine state and issues commands.
- **Every dialog generates syntax.** Show it live, and run it through the same path as typed syntax.
- Large tables must be virtualized (`ImGuiListClipper` or equivalent) and stay smooth at 10M+ rows.
- Keyboard-first: everything is reachable from the command palette.

## 5. Testing

- **Golden tests** (`tests/golden/<case>/`): an input dataset, a `.sps` script, and the reference output captured from SPSS. A test passes when printed values match exactly and unrounded values match within the documented tolerance.
- Every bug fix comes with a test that fails before the fix.
- Round-trip tests for every file format: read, write, read again, and compare byte- or dictionary-level as the spec requires.
- Fuzz the readers and the parser. They handle untrusted input.

## 6. Automation, MCP and AI features

- MCP tools, the local API and the CLI are thin layers over the engine's command interface. No logic lives only in an adapter.
- Tool results are structured (tables as JSON with labels and footnotes), not screen-scraped text.
- AI features are opt-in. Generated syntax is always shown to the user before it runs. No data leaves the machine unless the user configures a remote endpoint.
