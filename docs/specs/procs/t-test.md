# T-TEST
Status: draft (verified by tests/golden/ttest_basic)
Sources: Command Syntax Reference (public); standard t-test, Welch-Satterthwaite and Levene formulas; black-box runs.

Missing values are excluded analysis by analysis (each variable, or each pair, on its own). d = the variable's print decimals.

## One sample: `T-TEST /TESTVAL=x /VARIABLES=list`
- **One-Sample Statistics:** rows are the variables. Columns: N, Mean (d+2), Std. Deviation (d+3), Std. Error Mean (d+3).
- **One-Sample Test:** every column sits under one header, `Test Value = ` plus the test value **left-justified in a 40-character field** (`70` gives `"Test Value = 70"` followed by 38 spaces). Columns: t (3), df (integer), Sig. (2-tailed) (3), Mean Difference (d+3), and `95% Confidence Interval of the Difference / Lower` and `Upper` (**d+2**).

## Independent samples: `T-TEST GROUPS=g(a b) /VARIABLES=list`
- **Group Statistics:** rows `<var> / <group label>` for a then b. Columns: N, Mean (d+2), Std. Deviation (d+3), Std. Error Mean (d+3).
- **Independent Samples Test:**
  - Row `<var> / Equal variances assumed`: `Levene's Test for Equality of Variances / F` and `/ Sig.` (3 each). Then under `t-test for Equality of Means`: t (3), df (integer), Sig. (2-tailed) (3), Mean Difference (d+3), Std. Error Difference (d+3), and `95% Confidence Interval of the Difference / Lower` and `Upper` (**d+3**).
  - Row `<var> / Equal variances not assumed`: the same t-test columns, without Levene. df is Welch–Satterthwaite with 3 decimals.
- **Levene's F:** the one-way ANOVA F on |x − group mean|.

## Paired samples: `T-TEST PAIRS=a1 a2 WITH b1 b2 (PAIRED)`
Without `WITH … (PAIRED)`, every pair within the list is tested. Pairs are numbered `Pair 1`, `Pair 2`, …, and a case needs both values. D = max(d_a, d_b).
- **Paired Samples Statistics:** rows `Pair k / <a label>` and `Pair k / <b label>`. Columns: Mean (own d+2), N, Std. Deviation (own d+3), Std. Error Mean (own d+3).
- **Paired Samples Correlations:** row `Pair k / <a> & <b>`. Columns: N, Correlation (3), Sig. (3, the two-sided t test of r with n−2 df).
- **Paired Samples Test:** row `Pair k / <a> - <b>`. Columns: under `Paired Differences`, Mean, Std. Deviation, Std. Error Mean and `95% Confidence Interval of the Difference / Lower` and `Upper` (all D+3); then t (3), df (integer) and Sig. (2-tailed) (3).

## Open questions
- Test-value text for non-integer values; the GROUPS cut-point form `g(c)`; /CRITERIA=CI(x); /MISSING=LISTWISE.
