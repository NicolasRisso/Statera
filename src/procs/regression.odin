// Linear REGRESSION with METHOD=ENTER. Spec: docs/specs/procs/regression.md
package procs

import "core:fmt"
import "core:math"
import "core:strings"

import "../numerics"
import "../output"

Reg_Options :: struct {
	descriptives: bool,     // MEAN STDDEV N table
	corr:         bool,     // Correlations table (CORR SIG N)
	ci:           bool,
	ci_level:     f64,      // percent, e.g. 95
}

regression :: proc(ctx: ^Context, dep: int, predictors: []int, opts: Reg_Options, items: ^[dynamic]output.Item) -> (ok: bool, message: string) {
	file := ctx.file
	vars := make([]int, len(predictors) + 1, context.temp_allocator)
	vars[0] = dep
	copy(vars[1:], predictors)
	dv := &file.variables[dep]
	p := len(predictors)
	k := p + 1

	for &g in ctx.groups {
		rows_ok := listwise_rows(file, &g, vars, true)

		// Means and centred cross-products over listwise-complete cases (index 0 = dependent).
		n := 0.0
		mean := make([]f64, k, context.temp_allocator)
		for row, i in g.rows {
			if !rows_ok[i] { continue }
			n += g.weights[i]
			for v, j in vars { mean[j] += g.weights[i] * file.variables[v].numbers[row] }
		}
		if n <= f64(k) { return false, "too few valid cases for the model" }
		for &m in mean { m /= n }
		S := make([]f64, k * k, context.temp_allocator)
		for row, i in g.rows {
			if !rows_ok[i] { continue }
			w := g.weights[i]
			for a, ia in vars {
				da := file.variables[a].numbers[row] - mean[ia]
				for b, ib in vars {
					S[ia * k + ib] += w * da * (file.variables[b].numbers[row] - mean[ib])
				}
			}
		}
		sd :: proc(S: []f64, k, j: int, n: f64) -> f64 { return math.sqrt(S[j * k + j] / (n - 1)) }

		if opts.descriptives {
			t := output.Table{command = "Regression", subtype = "Descriptive Statistics", title = "Descriptive Statistics"}
			for v, j in vars {
				vv := &file.variables[v]
				d := int(vv.print.decimals)
				row := []string{var_title(vv)}
				output.add_number(&t, row, {"Mean"}, mean[j], d + 2)
				output.add_number(&t, row, {"Std. Deviation"}, sd(S, k, j, n), d + 3)
				output.add_number(&t, row, {"N"}, n, output.NO_DECIMALS)
			}
			append(items, t)
		}
		if opts.corr {
			t := output.Table{command = "Regression", subtype = "Correlations", title = "Correlations"}
			for a, ia in vars {
				for b, ib in vars {
					r := S[ia * k + ib] / math.sqrt(S[ia * k + ia] * S[ib * k + ib])
					output.add_number(&t, {"Pearson Correlation", var_title(&file.variables[a])}, {var_title(&file.variables[b])}, r, 3)
				}
			}
			for a, ia in vars {
				for b, ib in vars {
					row := []string{"Sig. (1-tailed)", var_title(&file.variables[a])}
					col := []string{var_title(&file.variables[b])}
					if ia == ib {
						output.add_text(&t, row, col, ".")
						continue
					}
					r := S[ia * k + ib] / math.sqrt(S[ia * k + ia] * S[ib * k + ib])
					output.add_number(&t, row, col, r_sig2(r, n) / 2, 3)
				}
			}
			for a in vars {
				for b in vars {
					output.add_number(&t, {"N", var_title(&file.variables[a])}, {var_title(&file.variables[b])}, n, output.NO_DECIMALS)
				}
			}
			append(items, t)
		}

		// Solve b = Sxx⁻¹ Sxy over the predictor block (indices 1..p).
		Sxx := make([]f64, p * p, context.temp_allocator)
		for i in 0 ..< p {
			for j in 0 ..< p { Sxx[i * p + j] = S[(i + 1) * k + (j + 1)] }
		}
		if !numerics.invert(Sxx, p) { return false, "the predictors are linearly dependent" }
		b := make([]f64, p, context.temp_allocator)
		for i in 0 ..< p {
			for j in 0 ..< p { b[i] += Sxx[i * p + j] * S[(j + 1) * k] }
		}
		ss_reg := 0.0
		for i in 0 ..< p { ss_reg += b[i] * S[(i + 1) * k] }
		ss_tot := S[0]
		ss_res := ss_tot - ss_reg
		df_reg, df_res := f64(p), n - f64(p) - 1
		mse := ss_res / df_res
		r2 := ss_reg / ss_tot

		labels := make([]string, p, context.temp_allocator)
		for v, i in predictors { labels[p - 1 - i] = var_title(&file.variables[v]) }
		entered := strings.join(labels, ", ", context.temp_allocator)
		predictors_note := fmt.tprintf("Predictors: (Constant), %s", entered)
		dep_caption := fmt.tprintf("Dependent Variable: %s", var_title(dv))

		ve := output.Table{command = "Regression", subtype = "Variables Entered Removed", title = "Variables Entered/Removed"}
		ve.captions = clone_strings({dep_caption})
		append(&ve.cells, output.Cell {
			row       = clone_strings({"1"}),
			col       = clone_strings({"Variables Entered"}),
			text      = strings.clone(entered),
			decimals  = output.NO_DECIMALS,
			footnotes = clone_strings({"All requested variables entered."}),
		})
		output.add_text(&ve, {"1"}, {"Variables Removed"}, ".")
		output.add_text(&ve, {"1"}, {"Method"}, "Enter")
		append(items, ve)

		ms := output.Table{command = "Regression", subtype = "Model Summary", title = "Model Summary"}
		output.add_number(&ms, {"1"}, {"R"}, math.sqrt(r2), 3, {predictors_note})
		output.add_number(&ms, {"1"}, {"R Square"}, r2, 3)
		output.add_number(&ms, {"1"}, {"Adjusted R Square"}, 1 - (1 - r2) * (n - 1) / df_res, 3)
		output.add_number(&ms, {"1"}, {"Std. Error of the Estimate"}, math.sqrt(mse), int(dv.print.decimals) + 3)
		append(items, ms)

		an := output.Table{command = "Regression", subtype = "ANOVA", title = "ANOVA"}
		an.captions = clone_strings({dep_caption})
		f := (ss_reg / df_reg) / mse
		output.add_number(&an, {"1", "Regression"}, {"Sum of Squares"}, ss_reg, 3)
		output.add_number(&an, {"1", "Regression"}, {"df"}, df_reg, output.NO_DECIMALS)
		output.add_number(&an, {"1", "Regression"}, {"Mean Square"}, ss_reg / df_reg, 3)
		output.add_number(&an, {"1", "Regression"}, {"F"}, f, 3)
		output.add_number(&an, {"1", "Regression"}, {"Sig."}, numerics.f_sf(f, df_reg, df_res), 3, {predictors_note})
		output.add_number(&an, {"1", "Residual"}, {"Sum of Squares"}, ss_res, 3)
		output.add_number(&an, {"1", "Residual"}, {"df"}, df_res, output.NO_DECIMALS)
		output.add_number(&an, {"1", "Residual"}, {"Mean Square"}, mse, 3)
		output.add_number(&an, {"1", "Total"}, {"Sum of Squares"}, ss_tot, 3)
		output.add_number(&an, {"1", "Total"}, {"df"}, n - 1, output.NO_DECIMALS)
		append(items, an)

		co := output.Table{command = "Regression", subtype = "Coefficients", title = "Coefficients"}
		co.captions = clone_strings({dep_caption})
		q := numerics.t_quantile(0.5 + opts.ci_level / 200, df_res)
		ci_header := fmt.tprintf("%.1f%% Confidence Interval for B", opts.ci_level)
		UB :: "Unstandardized Coefficients"
		coef_row :: proc(t: ^output.Table, name: string, b, se, beta: f64, has_beta: bool, df, q: f64, ci: bool, ci_header: string) {
			row := []string{"1", name}
			output.add_number(t, row, {UB, "B"}, b, 3)
			output.add_number(t, row, {UB, "Std. Error"}, se, 3)
			if has_beta { output.add_number(t, row, {"Standardized Coefficients", "Beta"}, beta, 3) }
			tv := b / se
			output.add_number(t, row, {"t"}, tv, 3)
			output.add_number(t, row, {"Sig."}, numerics.t_sig2(tv, df), 3)
			if ci {
				output.add_number(t, row, {ci_header, "Lower Bound"}, b - q * se, 3)
				output.add_number(t, row, {ci_header, "Upper Bound"}, b + q * se, 3)
			}
		}
		b0 := mean[0]
		quad := 0.0
		for i in 0 ..< p {
			b0 -= b[i] * mean[i + 1]
			for j in 0 ..< p { quad += mean[i + 1] * Sxx[i * p + j] * mean[j + 1] }
		}
		coef_row(&co, "(Constant)", b0, math.sqrt(mse * (1 / n + quad)), 0, false, df_res, q, opts.ci, ci_header)
		for v, i in predictors {
			beta := b[i] * sd(S, k, i + 1, n) / sd(S, k, 0, n)
			coef_row(&co, var_title(&file.variables[v]), b[i], math.sqrt(mse * Sxx[i * p + i]), beta, true, df_res, q, opts.ci, ci_header)
		}
		append(items, co)
	}
	return true, ""
}
