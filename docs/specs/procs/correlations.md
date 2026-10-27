# CORRELATIONS
Status: draft (verified by tests/golden/corr_basic)
Sources: Command Syntax Reference (public); Pearson correlation with the t test of r; black-box runs.

## Syntax (subset implemented)
`CORRELATIONS [/VARIABLES=] list [WITH list] [/PRINT = {TWOTAIL | ONETAIL} {SIG | NOSIG}] [/STATISTICS = DESCRIPTIVES XPROD | ALL] [/MISSING = {PAIRWISE | LISTWISE}]`
- **Naming trap:** `SIG` (the default) prints significance **without** flags. `NOSIG` adds the `*`/`**` flags.
- Without `WITH`, the matrix is the list × itself. With `WITH`, rows are the left list and columns the right list.

## Cases
- **PAIRWISE** (default): each coefficient uses the cases valid on both variables, and the table has an `N` row.
- **LISTWISE:** only cases valid on every variable. The `N` row is dropped, and the table gets the caption `Listwise N=<n>`.

## Output
- With /STATISTICS=DESCRIPTIVES, a **Descriptive Statistics** table comes first. Rows are the variables; columns are Mean (d+2), Std. Deviation (d+3) and N.
- **Correlations:** cells go in the order row variable → statistic → column variable. The statistic rows, in order:
  - `Pearson Correlation` (3 decimals). The diagonal shows `1` with no decimals.
  - `Sig. (2-tailed)` or `Sig. (1-tailed)` (3 decimals). There's no diagonal cell.
  - With XPROD: `Sum of Squares and Cross-products` and `Covariance` (3 decimals, diagonal included).
  - `N` (pairwise only).
- **Flags (NOSIG):** off-diagonal r cells get the footnote "Correlation is significant at the 0.01 level (2-tailed)." when p < .01, or "… 0.05 level …" when p < .05. Their markers are `**` and `*`, and the one-tailed variant says `(1-tailed)`.
- Sig: t = r√((n−2)/(1−r²)) with n−2 df. The one-tailed p is half the two-tailed p.

## Open questions
- The row order of N vs the cross-product rows in pairwise mode with XPROD (assumed: N last).
