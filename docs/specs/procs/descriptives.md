# DESCRIPTIVES
Status: draft (verified by tests/golden/desc_basic)
Sources: Command Syntax Reference (public); standard moment formulas; black-box runs.

## Syntax (subset implemented)
`DESCRIPTIVES [VARIABLES=] varlist [/STATISTICS = {DEFAULT | ALL | MEAN SEMEAN STDDEV VARIANCE RANGE MIN MAX SUM SKEWNESS KURTOSIS}...]`
- The default is MEAN STDDEV MIN MAX. ALL means every statistic.
- varlist supports names, `TO` (a dictionary-order range) and `ALL`.

## Behaviour
- Each variable is summarized over its valid values. User-missing and system-missing values are excluded per variable.
- Output is one pivot table, subtype `Descriptive Statistics`, titled "Descriptive Statistics".
  - Rows: one per variable, labelled with the variable label (or the name if there's no label), then `Valid N (listwise)`.
  - `Valid N (listwise)` counts cases where every listed variable is valid. It appears only in the N column.
  - Columns, in this fixed order and only for the requested statistics: N, Range, Minimum, Maximum, Sum, Mean, Std. Deviation, Variance, Skewness, Kurtosis.
  - If any of SEMEAN, SKEWNESS or KURTOSIS is requested, every column gets a second level: `Statistic`, plus a `Std. Error` sibling under Mean (SEMEAN), Skewness and Kurtosis.
- Decimals follow [number-display](../output/number-display.md).

## Formulas (n = valid count; unweighted)
- mean = Σx / n
- variance s² = Σ(x − mean)² / (n − 1); std. deviation = s; SE mean = s / √n
- skewness = n / ((n−1)(n−2)) · Σ((x − mean)/s)³, with SE = √(6n(n−1) / ((n−2)(n+1)(n+3)))
- kurtosis = n(n+1) / ((n−1)(n−2)(n−3)) · Σ((x − mean)/s)⁴ − 3(n−1)² / ((n−2)(n−3)), with SE = √(4(n²−1)·SE_skew² / ((n−3)(n+5)))
- range = max − min

## Edge cases
- Statistics that are undefined for small n (variance at n < 2, skewness at n < 3, kurtosis at n < 4) display as blank cells. *(Not yet golden-verified.)*

## Open questions
- Weighted cases (WEIGHT BY), Z-score saving (/SAVE), /SORT and /MISSING=LISTWISE.
