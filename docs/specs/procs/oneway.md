# ONEWAY
Status: draft (verified by tests/golden/oneway_basic)
Sources: Command Syntax Reference (public); one-way ANOVA, Levene / Brown–Forsythe and Welch (1951) formulas; black-box runs.

## Syntax (subset implemented)
`ONEWAY deps BY factor [/STATISTICS = DESCRIPTIVES HOMOGENEITY WELCH]`. Missing values are excluded per dependent.

## Layout
With **one** dependent, it goes in the layer of each table. With several, each table's rows start with `<dep label>`. Tables come in this order: Descriptives, Test of Homogeneity of Variances, ANOVA, Robust Tests of Equality of Means.

## Tables (d = the dependent's print decimals)
- **Descriptives:** rows are `<group label>` per factor value present, then `Total`. Columns: N, Mean (d+2), Std. Deviation (d+3), Std. Error (d+3), `95% Confidence Interval for Mean / Lower Bound` and `Upper Bound` (d+2; mean ± t₀.₉₇₅(n−1)·SE), Minimum and Maximum (d).
- **Test of Homogeneity of Variances:** the Levene statistic is the one-way ANOVA F computed on the absolute deviations z = |x − c_g|. Rows:
  - `Based on Mean`: c = the group mean.
  - `Based on Median`: c = the group median.
  - `Based on Median and with adjusted df`: the same statistic, with df2 adjusted (formula to be confirmed, see open questions).
  - `Based on trimmed mean`: c = the group's 5% trimmed mean.

  Columns: Levene Statistic (3), df1 (integer), df2 (integer, or 3 decimals when adjusted) and Sig. (3).
- **ANOVA:** rows `Between Groups` (SS, df, Mean Square, F, Sig.), `Within Groups` (SS, df, MS) and `Total` (SS, df). All values use 3 decimals, and df is an integer.
- **Robust Tests of Equality of Means (WELCH):** row `Welch`, with columns Statistic, df1, df2 (3) and Sig. The `Statistic` column label carries the footnote "Asymptotically F distributed." (once per dependent).
  - With w_i = n_i/s_i², W = Σw_i, m′ = Σw_i·m_i/W and Λ = Σ(1 − w_i/W)²/(n_i − 1):
  - F* = [Σw_i(m_i − m′)²/(k−1)] / [1 + 2(k−2)Λ/(k²−1)], df1 = k−1, df2 = (k²−1)/(3Λ).

## Open questions
- The adjusted-df formula. Working hypothesis: Satterthwaite, df2 = (Σu_i)² / Σ(u_i²/(n_i−1)), with u_i = Σ_j(z_ij − z̄_i)².
- The trimmed-mean definition. Working hypothesis: the EXAMINE-style 5% trimmed mean with fractional end weights.
- Post hoc tests, contrasts, /MISSING=LISTWISE, Brown–Forsythe.
