# REGRESSION (linear, METHOD=ENTER)
Status: draft (verified by tests/golden/reg_basic)
Sources: Command Syntax Reference (public); ordinary least squares via the normal equations; black-box runs.

## Syntax (subset implemented)
`REGRESSION [/DESCRIPTIVES [MEAN STDDEV CORR SIG N]] [/STATISTICS COEFF OUTS R ANOVA CI(p)] /DEPENDENT dep [dep…] /METHOD=ENTER predictors`
- Defaults: /STATISTICS = COEFF OUTS R ANOVA. A bare /DESCRIPTIVES means MEAN STDDEV CORR SIG N.
- Cases are deleted **listwise** over the dependent and all predictors. Each dependent gets its own model.

## Output per dependent, in order
1. With /DESCRIPTIVES, a **Descriptive Statistics** table: rows are the dependent then the predictors; columns are Mean (d+2), Std. Deviation (d+3) and N.
2. Also with /DESCRIPTIVES, a **Correlations** table. Rows are `<statistic> / <variable>` (the statistic is outermost): `Pearson Correlation` (3 decimals, **diagonal `1.000`**), `Sig. (1-tailed)` (3 decimals, diagonal is a null cell with text `.`) and `N`. Columns are the variables.
3. **Variables Entered/Removed:** row `1`. `Variables Entered` is the predictor labels in **reverse** order, joined by `, `, with the cell note "All requested variables entered." `Variables Removed` is a null cell with text `.`. `Method` is `Enter`. The table caption is `Dependent Variable: <dep>`.
4. **Model Summary:** row `1`, with R, R Square and Adjusted R Square (3 decimals) and Std. Error of the Estimate (dependent's d+3). The R cell carries the note `Predictors: (Constant), <reverse-order labels>`.
5. **ANOVA:** rows `1 / Regression`, `1 / Residual` and `1 / Total`, with the same columns as ONEWAY's ANOVA. The Sig. cell carries the Predictors note, and the table caption is `Dependent Variable: <dep>`.
6. **Coefficients:** rows `1 / (Constant)` then the predictors in entry order. Columns:
   - `Unstandardized Coefficients / B` and `/ Std. Error` (3 decimals).
   - `Standardized Coefficients / Beta` (3 decimals; not for the constant).
   - t and Sig. (3 decimals).
   - With CI(p): `<p, one decimal>% Confidence Interval for B / Lower Bound` and `Upper Bound` (3 decimals).

   The table caption is `Dependent Variable: <dep>`.

## Formulas (centred sums of squares and cross-products S; N cases; p predictors)
- b = S_xx⁻¹ S_xy; the constant b₀ = ȳ − Σ b_j x̄_j.
- SS_reg = bᵀS_xy, SS_tot = S_yy, SS_res = SS_tot − SS_reg. df = p and N−p−1.
- MSE = SS_res/(N−p−1). SE(b_j) = √(MSE·(S_xx⁻¹)_jj) and SE(b₀) = √(MSE·(1/N + x̄ᵀS_xx⁻¹x̄)).
- Beta_j = b_j·sd(x_j)/sd(y). R² = SS_reg/SS_tot, and adjusted R² = 1 − (1−R²)(N−1)/(N−p−1).

## Open questions
- Stepwise methods, the Excluded Variables table (OUTS only shows with non-ENTER methods), multiple METHOD blocks, residual statistics, collinearity diagnostics, and the tolerance check that drops near-collinear predictors.
