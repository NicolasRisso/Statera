# CROSSTABS
Status: draft (verified by tests/golden/xtab_basic, xtab_stats)
Sources: Command Syntax Reference (public); standard contingency-table statistics (Agresti; Fisher's exact test via the hypergeometric distribution); black-box runs.

## Syntax (subset implemented)
`CROSSTABS [/TABLES=] rowvars BY colvars [/TABLES=...] [/CELLS = {COUNT ROW COLUMN TOTAL EXPECTED | ALL | NONE}...] [/STATISTICS = {CHISQ PHI CC}...]`
- Every row variable is crossed with every column variable, in order. /CELLS defaults to COUNT. Layers (a second BY) aren't implemented yet.

## Cases
- A case enters a table if both variables are valid (not user- or system-missing), it passes FILTER, and it has a positive weight.
- **Weighted cell counts are rounded per cell** to integers, half away from zero (/COUNT ROUND CELL is the default). Marginals, N and every statistic use the rounded cells (golden: 23 summed weights → N = 25).

## Output
1. **Case Processing Summary** (one per CROSSTABS command, one row per table, labelled `Row label * Col label`). Columns: `Valid / N`, `Valid / Percent`, `Missing / N`, `Missing / Percent`, `Total / N`, `Total / Percent`. Percent cells display with 1 decimal and a `%` suffix (`100.0%`, `.0%`). With weights, **Valid N is the rounded table N, but the percentages and Missing/Total N use the unrounded weights**. So the golden case shows Valid 25 (100.0%) next to Total 23.
2. Per table, **`<Row label> * <Col label> Crosstabulation`**:
   - Columns: `<col label> / <value>` for each column value that occurs (ascending), then `Total`.
   - With only COUNT: rows are `<row label> / <value>`, then `Total`. The statistic `Count` is a layer.
   - With several cell statistics, rows are `<row label> / <value> / <statistic>` and `Total / <statistic>`. The statistic order is Count, Expected Count, `% within <row label>`, `% within <col label>`, `% of Total`.
   - Count: 0 decimals. Expected Count: 1 decimal. Percentages: 1 decimal with `%`.
3. With CHISQ, **Chi-Square Tests** follows each crosstab. Rows:
   - **Pearson Chi-Square:** Value, df and Asymptotic Significance (2-sided). The Value cell carries the footnote "`k` cells (`p`%) have expected count less than 5. The minimum expected count is `m`." Here `p` has 1 decimal and `m` has 2.
   - **Continuity Correction** (2×2 only): Value, df and Sig. The row label carries the footnote "Computed only for a 2x2 table".
   - **Likelihood Ratio:** Value, df and Sig.
   - **Fisher's Exact Test** (2×2 only): `Exact Sig. (2-sided)` and `Exact Sig. (1-sided)` columns.
   - **Linear-by-Linear Association:** Value, df = 1 and Sig.
   - **N of Valid Cases:** Value only.
4. With PHI or CC, **Symmetric Measures** follows. Rows are `Nominal by Nominal / Phi`, `Cramer's V` (both from PHI) and `Contingency Coefficient` (CC), then `N of Valid Cases`. Columns are Value and Approximate Significance (the Pearson p-value).

## Formulas (O = observed, E = row total × column total / N; r and c = the rows and columns that occur)
- Pearson X² = Σ(O−E)²/E, with df = (r−1)(c−1) and p = upper tail of χ²(df).
- Likelihood ratio G² = 2 Σ O·ln(O/E) over O > 0, with the same df.
- Continuity correction (2×2): N·max(0, |ad−bc| − N/2)² / (r₁r₂c₁c₂), df = 1.
- Linear-by-linear: (N−1)·R², where R is the Pearson correlation of the row and column **values**, weighted by the cell counts. df = 1.
- Fisher's exact test (2×2): hypergeometric probabilities with fixed margins. The 2-sided p sums every table with probability ≤ the observed one, within a small relative tolerance. The 1-sided p is the tail in the observed direction.
- Phi = √(X²/N). For 2×2 it's signed as (ad − bc). Cramer's V = √(X² / (N·(min(r,c)−1))). Contingency coefficient = √(X²/(X²+N)).

## Open questions
- Layers (`BY a BY b`), /MISSING=INCLUDE, /FORMAT, other /COUNT modes, and the other /STATISTICS (CORR, LAMBDA, GAMMA, …).
- The footnote wording when no cell has expected count < 5.
