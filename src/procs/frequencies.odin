// FREQUENCIES. Spec: docs/specs/procs/frequencies.md
package procs

import "core:math"

import "../io/sav"
import "../output"
import "../transform"

Freq_Stat :: enum u8 {
	Mean, Semean, Median, Mode, Stddev, Variance, Skewness, Seskew, Kurtosis, Sekurt, Range, Min, Max, Sum,
}

Freq_Stats :: bit_set[Freq_Stat]

FREQ_DEFAULT :: Freq_Stats{.Mean, .Stddev, .Min, .Max}
FREQ_ALL :: Freq_Stats{.Mean, .Semean, .Median, .Mode, .Stddev, .Variance, .Skewness, .Seskew, .Kurtosis, .Sekurt, .Range, .Min, .Max, .Sum}

MULTIPLE_MODES :: "Multiple modes exist. The smallest value is shown"

Freq_Options :: struct {
	stats:    Freq_Stats,
	no_table: bool,
}

frequencies :: proc(file: ^sav.File, vars: []int, opts: Freq_Options, items: ^[dynamic]output.Item) {
	append(items, statistics_table(file, vars, opts.stats))
	if opts.no_table { return }
	append(items, output.Text{kind = .Heading, command = "Frequencies", text = "Frequency Table"})
	for vi in vars {
		append(items, frequency_table(file, &file.variables[vi]))
	}
}

@(private)
var_title :: proc(v: ^sav.Variable) -> string {
	return v.label if v.label != "" else v.name
}

@(private)
statistics_table :: proc(file: ^sav.File, vars: []int, stats: Freq_Stats) -> output.Table {
	t := output.Table{command = "Frequencies", subtype = "Statistics", title = "Statistics"}
	// Rows are emitted statistic-major so the cell order matches SPSS's table.
	for vi in vars {
		v := &file.variables[vi]
		valid := f64(len(valid_values(file, v)))
		output.add_number(&t, {"N", "Valid"}, {var_title(v)}, valid, output.NO_DECIMALS)
	}
	for vi in vars {
		v := &file.variables[vi]
		valid := f64(len(valid_values(file, v)))
		output.add_number(&t, {"N", "Missing"}, {var_title(v)}, f64(file.n_cases) - valid, output.NO_DECIMALS)
	}

	order := [?]struct {
		stat: Freq_Stat,
		name: string,
	}{
		{.Mean, "Mean"}, {.Semean, "Std. Error of Mean"}, {.Median, "Median"}, {.Mode, "Mode"},
		{.Stddev, "Std. Deviation"}, {.Variance, "Variance"}, {.Skewness, "Skewness"},
		{.Seskew, "Std. Error of Skewness"}, {.Kurtosis, "Kurtosis"}, {.Sekurt, "Std. Error of Kurtosis"},
		{.Range, "Range"}, {.Min, "Minimum"}, {.Max, "Maximum"}, {.Sum, "Sum"},
	}
	for o in order {
		if o.stat not_in stats { continue }
		for vi in vars {
			v := &file.variables[vi]
			xs := valid_values(file, v)
			s := summarize(xs)
			d := int(v.print.decimals)
			row, col := []string{o.name}, []string{var_title(v)}
			switch o.stat {
			case .Mean:     add_stat(&t, row, col, s.mean, d + 2)
			case .Semean:   add_stat(&t, row, col, s.se_mean, d + 3)
			case .Median:   add_stat(&t, row, col, percentile(sorted_copy(xs), 0.5), d + 2)
			case .Stddev:   add_stat(&t, row, col, math.sqrt(s.variance), d + 3)
			case .Variance: add_stat(&t, row, col, s.variance, 3)
			case .Skewness: add_stat(&t, row, col, s.skewness, 3)
			case .Seskew:   add_stat(&t, row, col, s.se_skew, 3)
			case .Kurtosis: add_stat(&t, row, col, s.kurtosis, 3)
			case .Sekurt:   add_stat(&t, row, col, s.se_kurt, 3)
			case .Range:    add_stat(&t, row, col, s.max - s.min, d)
			case .Min:      add_stat(&t, row, col, s.min, d)
			case .Max:      add_stat(&t, row, col, s.max, d)
			case .Sum:      add_stat(&t, row, col, s.sum, d)
			case .Mode:
				mode, multiple := find_mode(xs)
				if math.is_nan(mode) {
					output.add_text(&t, row, col, "")
				} else if multiple {
					output.add_number(&t, row, col, mode, d, {MULTIPLE_MODES})
				} else {
					output.add_number(&t, row, col, mode, d)
				}
			}
		}
	}
	return t
}

@(private)
find_mode :: proc(xs: []f64) -> (mode: f64, multiple: bool) {
	if len(xs) == 0 { return math.nan_f64(), false }
	sorted := sorted_copy(xs)
	best, best_count, ties := sorted[0], 0, false
	for i := 0; i < len(sorted); {
		j := i
		for j < len(sorted) && sorted[j] == sorted[i] { j += 1 }
		count := j - i
		if count > best_count {
			best, best_count, ties = sorted[i], count, false
		} else if count == best_count {
			ties = true
		}
		i = j
	}
	return best, ties
}

@(private)
Value_Count :: struct {
	value: f64,
	count: int,
}

@(private)
count_values :: proc(values: []f64) -> []Value_Count {
	sorted := sorted_copy(values)
	out := make([dynamic]Value_Count, context.temp_allocator)
	for x in sorted {
		if len(out) > 0 && out[len(out) - 1].value == x {
			out[len(out) - 1].count += 1
		} else {
			append(&out, Value_Count{x, 1})
		}
	}
	return out[:]
}

@(private)
value_text :: proc(v: ^sav.Variable, x: f64) -> string {
	for l in v.value_labels {
		if l.value == x { return l.label }
	}
	return output.format_number(x, int(v.print.decimals), context.temp_allocator)
}

@(private)
frequency_table :: proc(file: ^sav.File, v: ^sav.Variable) -> output.Table {
	t := output.Table{command = "Frequencies", subtype = "Frequencies", title = var_title(v)}
	total := f64(file.n_cases)

	valid := make([dynamic]f64, context.temp_allocator)
	user_missing := make([dynamic]f64, context.temp_allocator)
	sysmis := 0
	for x in v.numbers {
		switch {
		case x == file.sysmis:                         sysmis += 1
		case transform.is_missing(v, x, file.sysmis): append(&user_missing, x)
		case:                                          append(&valid, x)
		}
	}
	n_valid := f64(len(valid))

	cumulative := 0.0
	for vc in count_values(valid[:]) {
		row := []string{"Valid", value_text(v, vc.value)}
		pct := 100 * f64(vc.count) / total
		valid_pct := 100 * f64(vc.count) / n_valid
		cumulative += valid_pct
		output.add_number(&t, row, {"Frequency"}, f64(vc.count), output.NO_DECIMALS)
		output.add_number(&t, row, {"Percent"}, pct, 1)
		output.add_number(&t, row, {"Valid Percent"}, valid_pct, 1)
		output.add_number(&t, row, {"Cumulative Percent"}, cumulative, 1)
	}
	if len(valid) > 0 {
		output.add_number(&t, {"Valid", "Total"}, {"Frequency"}, n_valid, output.NO_DECIMALS)
		output.add_number(&t, {"Valid", "Total"}, {"Percent"}, 100 * n_valid / total, 1)
		output.add_number(&t, {"Valid", "Total"}, {"Valid Percent"}, 100, 1)
	}

	n_missing := f64(len(user_missing) + sysmis)
	if n_missing == 0 { return t }
	missing_rows := 0
	for vc in count_values(user_missing[:]) {
		row := []string{"Missing", value_text(v, vc.value)}
		output.add_number(&t, row, {"Frequency"}, f64(vc.count), output.NO_DECIMALS)
		output.add_number(&t, row, {"Percent"}, 100 * f64(vc.count) / total, 1)
		missing_rows += 1
	}
	if sysmis > 0 {
		output.add_number(&t, {"Missing", "System"}, {"Frequency"}, f64(sysmis), output.NO_DECIMALS)
		output.add_number(&t, {"Missing", "System"}, {"Percent"}, 100 * f64(sysmis) / total, 1)
		missing_rows += 1
	}
	if missing_rows > 1 {
		output.add_number(&t, {"Missing", "Total"}, {"Frequency"}, n_missing, output.NO_DECIMALS)
		output.add_number(&t, {"Missing", "Total"}, {"Percent"}, 100 * n_missing / total, 1)
	}
	output.add_number(&t, {"Total"}, {"Frequency"}, total, output.NO_DECIMALS)
	output.add_number(&t, {"Total"}, {"Percent"}, 100, 1)
	return t
}
