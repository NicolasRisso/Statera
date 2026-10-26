// DESCRIPTIVES. Spec: docs/specs/procs/descriptives.md
package procs

import "core:math"
import "core:slice"
import "core:strings"

import "../output"
import "../transform"

Desc_Stat :: enum u8 {
	Mean, Semean, Stddev, Variance, Range, Min, Max, Sum, Skewness, Kurtosis,
}

Desc_Stats :: bit_set[Desc_Stat]

DESC_DEFAULT :: Desc_Stats{.Mean, .Stddev, .Min, .Max}
DESC_ALL :: Desc_Stats{.Mean, .Semean, .Stddev, .Variance, .Range, .Min, .Max, .Sum, .Skewness, .Kurtosis}

descriptives :: proc(ctx: ^Context, vars: []int, stats: Desc_Stats, items: ^[dynamic]output.Item) {
	new_table :: proc() -> output.Table {
		return {command = "Descriptives", subtype = "Descriptive Statistics", title = "Descriptive Statistics"}
	}
	if ctx.mode == .Separate {
		for &g in ctx.groups {
			append(items, output.Text{kind = .Heading, command = "Descriptives", text = strings.clone(g.caption)})
			t := new_table()
			t.captions = slice.clone([]string{strings.clone(g.caption)})
			descriptives_group(&t, ctx, &g, nil, vars, stats)
			append(items, t)
		}
		return
	}
	t := new_table()
	for &g in ctx.groups {
		descriptives_group(&t, ctx, &g, g.labels, vars, stats)
	}
	append(items, t)
}

@(private)
descriptives_group :: proc(t: ^output.Table, ctx: ^Context, g: ^Group, prefix: []string, vars: []int, stats: Desc_Stats) {
	two_level := stats & {.Semean, .Skewness, .Kurtosis} != {}
	col :: proc(two_level: bool, name: string, sub := "Statistic") -> []string {
		return path(nil, name, sub) if two_level else path(nil, name)
	}

	file := ctx.file
	for vi in vars {
		v := &file.variables[vi]
		row := path(prefix, var_title(v))
		s := summarize(valid_values(ctx, g, v))
		d := int(v.print.decimals)

		output.add_number(t, row, col(two_level, "N"), s.n, output.NO_DECIMALS)
		if .Range in stats { add_stat(t, row, col(two_level, "Range"), s.max - s.min, d) }
		if .Min in stats { add_stat(t, row, col(two_level, "Minimum"), s.min, d) }
		if .Max in stats { add_stat(t, row, col(two_level, "Maximum"), s.max, d) }
		if .Sum in stats { add_stat(t, row, col(two_level, "Sum"), s.sum, d) }
		if .Mean in stats { add_stat(t, row, col(two_level, "Mean"), s.mean, d + 2) }
		if .Semean in stats { add_stat(t, row, col(two_level, "Mean", "Std. Error"), s.se_mean, d + 3) }
		if .Stddev in stats { add_stat(t, row, col(two_level, "Std. Deviation"), math.sqrt(s.variance), d + 3) }
		if .Variance in stats { add_stat(t, row, col(two_level, "Variance"), s.variance, 3) }
		if .Skewness in stats {
			add_stat(t, row, col(two_level, "Skewness"), s.skewness, 3)
			add_stat(t, row, col(two_level, "Skewness", "Std. Error"), s.se_skew, 3)
		}
		if .Kurtosis in stats {
			add_stat(t, row, col(two_level, "Kurtosis"), s.kurtosis, 3)
			add_stat(t, row, col(two_level, "Kurtosis", "Std. Error"), s.se_kurt, 3)
		}
	}

	listwise := 0.0
	cases: for row, i in g.rows {
		for vi in vars {
			v := &file.variables[vi]
			if transform.is_missing(v, v.numbers[row], file.sysmis) { continue cases }
		}
		listwise += g.weights[i]
	}
	output.add_number(t, path(prefix, "Valid N (listwise)"), col(two_level, "N"), listwise, output.NO_DECIMALS)
}

// Undefined statistics (NaN) produce no cell at all, as in SPSS (golden: compute_basic, div0).
@(private)
add_stat :: proc(t: ^output.Table, row, col: []string, x: f64, decimals: int) {
	if math.is_nan(x) { return }
	output.add_number(t, row, col, x, decimals)
}
