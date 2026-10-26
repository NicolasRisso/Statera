# FREQUENCIES
Status: draft (verified by tests/golden/freq_basic, freq_stats)
Sources: Command Syntax Reference (public); black-box runs.

## Syntax (subset implemented)
`FREQUENCIES [VARIABLES=] varlist [/FORMAT=NOTABLE] [/STATISTICS = {DEFAULT | ALL | MEAN SEMEAN MEDIAN MODE STDDEV VARIANCE SKEWNESS SESKEW KURTOSIS SEKURT RANGE MINIMUM MAXIMUM SUM}...]`
DEFAULT means MEAN STDDEV MINIMUM MAXIMUM.

## Behaviour
1. **Statistics table** (subtype `Statistics`, title "Statistics"), always emitted.
   - Columns: one per variable (label or name).
   - Rows: `N / Valid` and `N / Missing` first, then the requested statistics in this fixed order: Mean, Std. Error of Mean, Median, Mode, Std. Deviation, Variance, Skewness, Std. Error of Skewness, Kurtosis, Std. Error of Kurtosis, Range, Minimum, Maximum, Sum.
   - When several values tie for the most frequent, Mode shows the smallest, with the footnote "Multiple modes exist. The smallest value is shown".
2. A heading **Frequency Table**, then one table per variable (subtype `Frequencies`, title = variable label or name), unless /FORMAT=NOTABLE.
   - Columns: Frequency, Percent, Valid Percent, Cumulative Percent.
   - `Valid` group: one row per distinct valid value, ascending. The row label is the value label if one exists, otherwise the value in the variable's print format. Then `Valid / Total`, which has no Cumulative Percent.
   - `Missing` group (only if any missing cases): one row per distinct user-missing value (label or formatted value), then `System` for system-missing, then `Missing / Total`, which appears only when there's more than one missing row. Missing rows have only Frequency and Percent.
   - The grand `Total` row (Frequency, Percent) appears only when there are missing cases.
   - Percent = count / all cases; Valid Percent = count / valid cases; Cumulative Percent sums Valid Percent.

## Formulas
- Mean, SE, std. deviation, variance, skewness, kurtosis and their SEs as in [DESCRIPTIVES](descriptives.md).
- **Median / percentiles (HAVERAGE):** with sorted valid values x₁…xₙ and p = 0.5, take position t = (n+1)p, k = ⌊t⌋ and f = t − k. Result = x_k + f(x_{k+1} − x_k), clamped to x₁ when k < 1 and to xₙ when k ≥ n.

## Open questions
- Exact rule for when `Missing / Total` appears (verified only with 2 missing rows, and with a single user-missing row where it was absent).
- Weighted counts, /PERCENTILES, /NTILES, /GROUPED, /BARCHART, /HISTOGRAM, /ORDER.
