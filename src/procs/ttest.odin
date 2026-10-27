// T-TEST. Spec: docs/specs/procs/t-test.md
package procs

import "core:fmt"
import "core:math"

import "../io/sav"
import "../numerics"
import "../output"
import "../transform"

CI_95 :: "95% Confidence Interval of the Difference"

ttest_one_sample :: proc(ctx: ^Context, vars: []int, test_value: f64, items: ^[dynamic]output.Item) {
	file := ctx.file
	// SPSS left-justifies the test value in a 40-character field.
	header := fmt.tprintf("Test Value = %-40s", number_text(test_value))
	for &g in ctx.groups {
		stats := output.Table{command = "T-Test", subtype = "One Sample Statistics", title = "One-Sample Statistics"}
		test := output.Table{command = "T-Test", subtype = "One Sample Test", title = "One-Sample Test"}
		for vi in vars {
			v := &file.variables[vi]
			s := summarize(valid_values(ctx, &g, v))
			d := int(v.print.decimals)
			row := []string{var_title(v)}
			add_group_stats(&stats, row, s, d)

			df := s.n - 1
			diff := s.mean - test_value
			t := diff / s.se_mean
			q := numerics.t_quantile(0.975, df)
			output.add_number(&test, row, {header, "t"}, t, 3)
			output.add_number(&test, row, {header, "df"}, df, df_decimals(df))
			output.add_number(&test, row, {header, "Sig. (2-tailed)"}, numerics.t_sig2(t, df), 3)
			output.add_number(&test, row, {header, "Mean Difference"}, diff, d + 3)
			output.add_number(&test, row, {header, CI_95, "Lower"}, diff - q * s.se_mean, d + 2)
			output.add_number(&test, row, {header, CI_95, "Upper"}, diff + q * s.se_mean, d + 2)
		}
		append(items, stats)
		append(items, test)
	}
}

// N, Mean, Std. Deviation, Std. Error Mean.
@(private)
add_group_stats :: proc(t: ^output.Table, row: []string, s: Summary, d: int) {
	output.add_number(t, row, {"N"}, s.n, output.NO_DECIMALS)
	add_stat(t, row, {"Mean"}, s.mean, d + 2)
	add_stat(t, row, {"Std. Deviation"}, math.sqrt(s.variance), d + 3)
	add_stat(t, row, {"Std. Error Mean"}, s.se_mean, d + 3)
}

// Integers print without decimals; other values with the shortest round-trip form.
@(private)
number_text :: proc(x: f64) -> string {
	if x == math.trunc(x) && abs(x) < 1e15 { return fmt.tprintf("%d", i64(x)) }
	return fmt.tprintf("%v", x)
}

ttest_groups :: proc(ctx: ^Context, factor: int, a, b: f64, vars: []int, items: ^[dynamic]output.Item) {
	file := ctx.file
	fv := &file.variables[factor]
	for &g in ctx.groups {
		stats := output.Table{command = "T-Test", subtype = "Group Statistics", title = "Group Statistics"}
		test := output.Table{command = "T-Test", subtype = "Independent Samples Test", title = "Independent Samples Test"}
		for vi in vars {
			v := &file.variables[vi]
			d := int(v.print.decimals)
			samples := [2]Sample{level_sample(ctx, &g, v, fv, a), level_sample(ctx, &g, v, fv, b)}
			s1 := summarize(samples[0].xs, samples[0].ws)
			s2 := summarize(samples[1].xs, samples[1].ws)
			add_group_stats(&stats, {var_title(v), value_text(fv, a)}, s1, d)
			add_group_stats(&stats, {var_title(v), value_text(fv, b)}, s2, d)

			lev := one_way_anova(levene_deviations(samples[:], .Mean))
			diff := s1.mean - s2.mean
			LEV :: "Levene's Test for Equality of Variances"
			TT :: "t-test for Equality of Means"

			// Equal variances assumed (pooled).
			equal := []string{var_title(v), "Equal variances assumed"}
			output.add_number(&test, equal, {LEV, "F"}, lev.f, 3)
			output.add_number(&test, equal, {LEV, "Sig."}, lev.sig, 3)
			df := s1.n + s2.n - 2
			pooled := ((s1.n - 1) * s1.variance + (s2.n - 1) * s2.variance) / df
			add_t_columns(&test, equal, TT, diff, math.sqrt(pooled * (1 / s1.n + 1 / s2.n)), df, d)

			// Equal variances not assumed (Welch–Satterthwaite).
			u1, u2 := s1.variance / s1.n, s2.variance / s2.n
			welch_df := (u1 + u2) * (u1 + u2) / (u1 * u1 / (s1.n - 1) + u2 * u2 / (s2.n - 1))
			add_t_columns(&test, {var_title(v), "Equal variances not assumed"}, TT, diff, math.sqrt(u1 + u2), welch_df, d)
		}
		append(items, stats)
		append(items, test)
	}
}

@(private)
add_t_columns :: proc(t: ^output.Table, row: []string, header: string, diff, se, df: f64, d: int) {
	tv := diff / se
	q := numerics.t_quantile(0.975, df)
	output.add_number(t, row, {header, "t"}, tv, 3)
	output.add_number(t, row, {header, "df"}, df, df_decimals(df))
	output.add_number(t, row, {header, "Sig. (2-tailed)"}, numerics.t_sig2(tv, df), 3)
	output.add_number(t, row, {header, "Mean Difference"}, diff, d + 3)
	output.add_number(t, row, {header, "Std. Error Difference"}, se, d + 3)
	output.add_number(t, row, {header, CI_95, "Lower"}, diff - q * se, d + 3)
	output.add_number(t, row, {header, CI_95, "Upper"}, diff + q * se, d + 3)
}

// Valid values of `v` for cases whose factor equals `level`.
@(private)
level_sample :: proc(ctx: ^Context, g: ^Group, v, factor: ^sav.Variable, level: f64) -> Sample {
	xs := make([dynamic]f64, context.temp_allocator)
	ws := make([dynamic]f64, context.temp_allocator)
	for row, i in g.rows {
		if factor.numbers[row] != level { continue }
		x := v.numbers[row]
		if transform.is_missing(v, x, ctx.file.sysmis) { continue }
		append(&xs, x)
		append(&ws, g.weights[i])
	}
	return {xs[:], ws[:]}
}

ttest_paired :: proc(ctx: ^Context, pairs: [][2]int, items: ^[dynamic]output.Item) {
	file := ctx.file
	for &g in ctx.groups {
		stats := output.Table{command = "T-Test", subtype = "Paired Samples Statistics", title = "Paired Samples Statistics"}
		corr := output.Table{command = "T-Test", subtype = "Paired Samples Correlations", title = "Paired Samples Correlations"}
		test := output.Table{command = "T-Test", subtype = "Paired Samples Test", title = "Paired Samples Test"}
		for p, k in pairs {
			va, vb := &file.variables[p[0]], &file.variables[p[1]]
			pair := fmt.tprintf("Pair %d", k + 1)
			as := make([dynamic]f64, context.temp_allocator)
			bs := make([dynamic]f64, context.temp_allocator)
			ds := make([dynamic]f64, context.temp_allocator)
			ws := make([dynamic]f64, context.temp_allocator)
			for row, i in g.rows {
				x, y := va.numbers[row], vb.numbers[row]
				if transform.is_missing(va, x, file.sysmis) || transform.is_missing(vb, y, file.sysmis) { continue }
				append(&as, x)
				append(&bs, y)
				append(&ds, x - y)
				append(&ws, g.weights[i])
			}
			sa, sb := summarize(as[:], ws[:]), summarize(bs[:], ws[:])
			for e in ([?]struct {
					v: ^sav.Variable,
					s: Summary,
				}{{va, sa}, {vb, sb}}) {
				row := []string{pair, var_title(e.v)}
				d := int(e.v.print.decimals)
				add_stat(&stats, row, {"Mean"}, e.s.mean, d + 2)
				output.add_number(&stats, row, {"N"}, e.s.n, output.NO_DECIMALS)
				add_stat(&stats, row, {"Std. Deviation"}, math.sqrt(e.s.variance), d + 3)
				add_stat(&stats, row, {"Std. Error Mean"}, e.s.se_mean, d + 3)
			}

			r := correlation(as[:], bs[:], ws[:], sa.mean, sb.mean)
			n := sa.n
			corr_row := []string{pair, fmt.tprintf("%s & %s", var_title(va), var_title(vb))}
			output.add_number(&corr, corr_row, {"N"}, n, output.NO_DECIMALS)
			output.add_number(&corr, corr_row, {"Correlation"}, r, 3)
			output.add_number(&corr, corr_row, {"Sig."}, numerics.t_sig2(r * math.sqrt((n - 2) / (1 - r * r)), n - 2), 3)

			sd := summarize(ds[:], ws[:])
			dmax := int(max(va.print.decimals, vb.print.decimals))
			df := sd.n - 1
			q := numerics.t_quantile(0.975, df)
			row := []string{pair, fmt.tprintf("%s - %s", var_title(va), var_title(vb))}
			PD :: "Paired Differences"
			output.add_number(&test, row, {PD, "Mean"}, sd.mean, dmax + 3)
			output.add_number(&test, row, {PD, "Std. Deviation"}, math.sqrt(sd.variance), dmax + 3)
			output.add_number(&test, row, {PD, "Std. Error Mean"}, sd.se_mean, dmax + 3)
			output.add_number(&test, row, {PD, CI_95, "Lower"}, sd.mean - q * sd.se_mean, dmax + 3)
			output.add_number(&test, row, {PD, CI_95, "Upper"}, sd.mean + q * sd.se_mean, dmax + 3)
			tv := sd.mean / sd.se_mean
			output.add_number(&test, row, {"t"}, tv, 3)
			output.add_number(&test, row, {"df"}, df, df_decimals(df))
			output.add_number(&test, row, {"Sig. (2-tailed)"}, numerics.t_sig2(tv, df), 3)
		}
		append(items, stats)
		append(items, corr)
		append(items, test)
	}
}

// Weighted Pearson correlation of paired values.
correlation :: proc(xs, ys, ws: []f64, mx, my: f64) -> f64 {
	sxx, syy, sxy: f64
	for x, i in xs {
		dx, dy := x - mx, ys[i] - my
		sxx += ws[i] * dx * dx
		syy += ws[i] * dy * dy
		sxy += ws[i] * dx * dy
	}
	return sxy / math.sqrt(sxx * syy)
}
