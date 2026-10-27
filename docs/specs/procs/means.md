# MEANS
Status: draft (verified by tests/golden/means_basic)
Sources: Command Syntax Reference (public); black-box runs.

## Syntax (subset implemented)
`MEANS [TABLES=] deps BY v1 [BY v2 …] [/TABLES=…] [/CELLS = MEAN COUNT STDDEV MIN MAX SUM VARIANCE SEMEAN RANGE …] [/STATISTICS=ANOVA]`
- The default cells are MEAN COUNT STDDEV. Cells appear in the order listed.

## Output per TABLES list
1. **Case Processing Summary.** One row per dependent, labelled `<dep label>  * <v1 label> * <v2 label>`. **There are two spaces before the first `*`.** Columns: `Included`, `Excluded` and `Total`, each with `N` and `Percent` (`%` format). A case is included for a dependent when the dependent and every BY variable are valid.
2. **Report.**
   - **One dependent:** the dependent is the layer and the statistics are columns. Rows are the category path.
   - **Several dependents:** rows are the category path plus the statistic, and the columns are the dependents. Cells go in row order: group, then statistic, then dependent.
   - **Category paths:** at each BY level, take the ascending values present in the current subset, then `Total` (all cases at that level). Nesting multiplies: for `BY sex BY grp` the order is Male/Control … Male/Total, Female/…, then Total/Control … Total/Total.
   - **Decimals** (d = the dependent's): Mean d+2, Std. Deviation d+3, Minimum/Maximum/Sum/Range d, Variance 3, Std. Error of Mean d+3, N none.
3. **With /STATISTICS=ANOVA** (first BY variable only):
   - **ANOVA Table:** rows `<dep> * <v1>` / `Between Groups` / `(Combined)`, then `Within Groups`, then `Total`. Columns: Sum of Squares, df, Mean Square, F and Sig. Within Groups has no F or Sig., and Total has only SS and df. Note the label here has a **single** space before `*`.
   - **Measures of Association:** Eta = √(SS_between/SS_total) and Eta Squared, both with 3 decimals.

## Open questions
- Category labels for values with no value label; empty cells in nested tables; /MISSING; and the other cell statistics (MEDIAN, GMEDIAN, KURT…).
