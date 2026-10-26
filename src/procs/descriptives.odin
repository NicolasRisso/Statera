// DESCRIPTIVES. Spec: docs/specs/procs/descriptives.md
package procs

import "core:math"
import "core:slice"

import "../io/sav"
import "../output"
import "../transform"

Desc_Stat :: enum u8 {
	Mean, Semean, Stddev, Variance, Range, Min, Max, Sum, Skewness, Kurtosis,
}

Desc_Stats :: bit_set[Desc_Stat]

DESC_DEFAULT :: Desc_Stats{.Mean, .Stddev, .Min, .Max}
DESC_ALL :: Desc_Stats{.Mean, .Semean, .Stddev, .Variance, .Range, .Min, .Max, .Sum, .Skewness, .Kurtosis}

descriptives :: proc(file: ^sav.File, vars: []int, stats: Desc_Stats) -> output.Table {
	t := output.Table{command = "Descriptives", subtype = "Descriptive Statistics", title = "Descriptive Statistics"}
	two_level := stats & {.Semean, .Skewness, .Kurtosis} != {}

	col :: proc(two_level: bool, name: string, sub := "Statistic") -> []string {
		// Clone: a slice literal would point into this proc's stack frame.
		if !two_level { return slice.clone([]string{name}, context.temp_allocator) }
		return slice.clone([]string{name, sub}, context.temp_allocator)
	}

	for vi in vars {
		v := &file.variables[vi]
		row := []string{v.label if v.label != "" else v.name}
		s := summarize(valid_values(file, v))
		d := int(v.print.decimals)

		output.add_number(&t, row, col(two_level, "N"), s.n, output.NO_DECIMALS)
		if .Range in stats { add_stat(&t, row, col(two_level, "Range"), s.max - s.min, d) }
		if .Min in stats { add_stat(&t, row, col(two_level, "Minimum"), s.min, d) }
		if .Max in stats { add_stat(&t, row, col(two_level, "Maximum"), s.max, d) }
		if .Sum in stats { add_stat(&t, row, col(two_level, "Sum"), s.sum, d) }
		if .Mean in stats { add_stat(&t, row, col(two_level, "Mean"), s.mean, d + 2) }
		if .Semean in stats { add_stat(&t, row, col(two_level, "Mean", "Std. Error"), s.se_mean, d + 3) }
		if .Stddev in stats { add_stat(&t, row, col(two_level, "Std. Deviation"), math.sqrt(s.variance), d + 3) }
		if .Variance in stats { add_stat(&t, row, col(two_level, "Variance"), s.variance, 3) }
		if .Skewness in stats {
			add_stat(&t, row, col(two_level, "Skewness"), s.skewness, 3)
			add_stat(&t, row, col(two_level, "Skewness", "Std. Error"), s.se_skew, 3)
		}
		if .Kurtosis in stats {
			add_stat(&t, row, col(two_level, "Kurtosis"), s.kurtosis, 3)
			add_stat(&t, row, col(two_level, "Kurtosis", "Std. Error"), s.se_kurt, 3)
		}
	}

	listwise := 0
	cases: for c in 0 ..< file.n_cases {
		for vi in vars {
			v := &file.variables[vi]
			if transform.is_missing(v, v.numbers[c], file.sysmis) { continue cases }
		}
		listwise += 1
	}
	output.add_number(&t, {"Valid N (listwise)"}, col(two_level, "N"), f64(listwise), output.NO_DECIMALS)
	return t
}

// Undefined statistics (NaN) produce no cell at all, as in SPSS (golden: compute_basic, div0).
@(private)
add_stat :: proc(t: ^output.Table, row, col: []string, x: f64, decimals: int) {
	if math.is_nan(x) { return }
	output.add_number(t, row, col, x, decimals)
}
