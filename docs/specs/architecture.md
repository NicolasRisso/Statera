# Reference architecture (IBM SPSS Statistics 25)
Status: analyst summary, 2026-10-26
Sources: static inspection of the licensed install with rea/Ghidra (PE export/import tables, string inventories, config files, live process and socket observation, a few callee/caller queries). Everything here is in our own words. There is no decompiled code, and no private symbol names beyond file names and public command keywords.

This explains how the reference is *organized* so Statera's design can match its behavior boundaries. It is **not** a blueprint to copy.

## Process model
- The front end (`stats.exe`) hosts a JVM in-process and runs the Swing UI. It launches the engine (`spssengine.exe`) as a child process.
- They talk over **one loopback TCP connection**, using a generic client/server message framework. The same framework serves the remote "Statistics Server", so locally the UI is simply a client of a private engine.
- The engine starts its own JVM for a few Java-implemented services (chart rendering, `.xlsx` I/O, some tree/neural procedures).
- Programmability: the Python/R `spss` module talks to a backend C API (dictionary access, case access, a pivot-table builder). A separate front-end scripting API drives the Viewer.

**Statera takeaway:** our engine is a library with the same clean split (UI as one client among the CLI/MCP/API). No IPC is needed for local use, though a socket mode remains possible for "server" use later.

## Command dispatch
1. The command processor recognizes the command keyword against a compiled-in vocabulary. Keywords are stored truncated (8 characters), which is consistent with abbreviation-by-prefix.
2. Each command maps to an internal procedure entry, and several commands can share one (e.g. MATCH FILES / ADD FILES / UPDATE).
3. Entries map to a 3-letter module code. The module `SPSSW<code>.DLL` is **loaded on demand** when the command runs.
4. Transformations and utility commands (COMPUTE, RECODE, IF, DO IF, LOOP, SELECT IF, FILTER, WEIGHT, SPLIT FILE, TEMPORARY, DATA LIST, SET, EXECUTE…) live in the core, not in procedure modules.
5. Some newer commands (GENLINMIXED, NPTESTS, KNN, ADP, LINEAR, extension commands) are declared by XML command specs and hosted by a component framework.
6. The `syntax_xml/` grammars appear to be used only by the syntax editor (colouring and completion), not by the engine.

### Procedure modules → commands (non-obvious rows)
| Module | Command(s) |
|---|---|
| spsswcde | **DESCRIPTIVES** |
| spsswdsc | **DISCRIMINANT** (not DESCRIPTIVES) |
| spsswbrk | MEANS |
| spsswfre | FREQUENCIES |
| spsswcrs | CROSSTABS |
| spsswpea | CORRELATIONS |
| spsswspr | NONPAR CORR |
| spsswtte | T-TEST |
| spsswone | ONEWAY |
| spsswreg | REGRESSION |
| spssweda | EXAMINE (also shared by GLM/ONEWAY) |
| spsswkme | QUICK CLUSTER |
| spsswldn | ANACOR, CATPCA, CATREG, CORRESPONDENCE, HOMALS, MULTIPLE CORRESPONDENCE, OVERALS, PRINCALS |
| spsswfil | GET, SAVE, XSAVE, MATCH FILES, ADD FILES, UPDATE, IMPORT, EXPORT, GET DATA, GET SAS, (SAVE/GET) TRANSLATE, RENAME VARIABLES, STAR JOIN |
| spsswtst | DATE, PREDICT, CREATE, RMV, TSET, TSHOW, USE, VERIFY |

The full 127-module table is kept in the analyst notes. It's reproducible with `rea inspect-native-exports` on a licensed install and isn't needed for implementation.

## Procedure ↔ engine contract (observed service categories)
Procedures get these services from the core:
- dictionary access (names, types, formats, labels, missing specs)
- a **case-pass iterator** that has already applied TEMPORARY, FILTER and SELECT IF and reports split-group boundaries
- the weight variable (**procedures apply weights themselves**)
- missing-value predicates
- tallying tables for distinct values
- memory and interrupt checks
- distributions and linear algebra
- a **pivot-table builder**
- numbered errors and warnings

**Statera takeaway:** give procedures a `Procedure_Context` with exactly these capabilities. Today `src/procs` reads `sav.File` directly. Introduce the context before adding WEIGHT, FILTER, SELECT IF, TEMPORARY or SPLIT FILE.

## Output pipeline
- Procedures emit pivot tables (dimensions → groups → categories → cells with semantic formats, footnotes) as **one stream**. Both the Viewer and the engine-side output tree consume it. OMS serializes that tree to OXML, `.spv`, `.sav`, HTML and text.
- Row/column labels and footnotes come from localized string tables keyed by ID.

**Statera takeaway:** one table model (`src/output`) projected to every format, which is what we have. OXML is a faithful projection, so golden comparison through OMS is sound. Keep labels in a localizable table when we add i18n.

## Numerics
- **No third-party BLAS/LAPACK/MKL.** The core has in-house LINPACK/BLAS-1-style routines, EISPACK-style eigen routines, sweep operators and a Brent root finder. NLR/CNLR/PROBIT use the NPSOL optimizer. Exact tests use an embedded StatXact-style engine.
- Crossproduct and correlation accumulation (REGRESSION, CORRELATIONS, FACTOR, DISCRIMINANT…) is **multithreaded**, so last-bit results may depend on thread count.
- **SYSMIS = −DBL_MAX** (`0xFFEFFFFFFFFFFFFF`). HIGHEST = DBL_MAX. LOWEST = the next double above −DBL_MAX (`0xFFEFFFFFFFFFFFFE`). This is confirmed in memory constants and in the `.sav` files SPSS writes.
- "Fuzzy" rounding helpers are used by CROSSTABS and REGRESSION, so weighted counts are likely rounded with a tolerance.

## Data I/O
- The engine has its **own** `.sav`/`.zsav` reader and writer, including encryption. The public `spssio64` I/O module (135 `spss*` functions) is used only by the ODBC driver and a Java wrapper.
- Other formats: Excel (`.xls` native, `.xlsx` via the JVM), ODS, text (multithreaded), ODBC, SAS/Stata (third-party transfer engine), Cognos/TM1, Dimensions.

## Open questions (resolve by black-box golden tests first)
1. Exact keyword abbreviation and ambiguity rules: test truncations of every command we support.
2. Weighted counts: the fuzzy-rounding tolerance in FREQUENCIES/CROSSTABS with fractional weights.
3. Whether results depend on thread count: compare `SET THREADS=1` vs `n` for REGRESSION/CORRELATIONS at full precision.
4. Weight-filter rules (zero, negative or missing weights) and the order of TEMPORARY / FILTER / SELECT IF / WEIGHT application.
