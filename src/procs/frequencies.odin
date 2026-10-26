// FREQUENCIES. Spec: docs/specs/procs/frequencies.md
package procs

import "core:math"
import "core:slice"
import "core:strings"

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

frequencies :: proc(ctx: ^Context, vars: []int, opts: Freq_Options, items: ^[dynamic]output.Item) {
	if ctx.mode == .Separate {
		for &g in ctx.groups {
			append(items, output.Text{kind = .Heading, command = "Frequencies", text = strings.clone(g.caption)})
			frequencies_groups(ctx, slice.from_ptr(&g, 1), false, vars, opts, items)
		}
		return
	}
	frequencies_groups(ctx, ctx.groups, true, vars, opts, items)
}

@(private)
frequencies_groups :: proc(ctx: ^Context, groups: []Group, layered: bool, vars: []int, opts: Freq_Options, items: ^[dynamic]output.Item) {
	caption := [1]string{groups[0].caption}
	captions := caption[:] if !layered && groups[0].caption != "" else nil

	stats := statistics_table(ctx, groups, layered, vars, opts.stats)
	stats.captions = clone_strings(captions)
	append(items, stats)
	if opts.no_table { return }
	if len(vars) > 1 {
		append(items, output.Text{kind = .Heading, command = "Frequencies", text = "Frequency Table"})
	}
	for vi in vars {
		v := &ctx.file.variables[vi]
		t := output.Table{command = "Frequencies", subtype = "Frequencies", title = strings.clone(var_title(v))}
		t.captions = clone_strings(captions)
		for &g in groups {
			frequency_rows(&t, ctx, &g, g.labels if layered else nil, v)
		}
		append(items, t)
	}
}

@(private)
clone_strings :: proc(s: []string) -> []string {
	if len(s) == 0 { return nil }
	out := make([]string, len(s))
	for x, i in s { out[i] = strings.clone(x) }
	return out
}

@(private)
statistics_table :: proc(ctx: ^Context, groups: []Group, layered: bool, vars: []int, stats: Freq_Stats) -> output.Table {
	t := output.Table{command = "Frequencies", subtype = "Statistics", title = "Statistics"}
	order := [?]struct {
		stat: Freq_Stat,
		name: string,
	}{
		{.Mean, "Mean"}, {.Semean, "Std. Error of Mean"}, {.Median, "Median"}, {.Mode, "Mode"},
		{.Stddev, "Std. Deviation"}, {.Variance, "Variance"}, {.Skewness, "Skewness"},
		{.Seskew, "Std. Error of Skewness"}, {.Kurtosis, "Kurtosis"}, {.Sekurt, "Std. Error of Kurtosis"},
		{.Range, "Range"}, {.Min, "Minimum"}, {.Max, "Maximum"}, {.Sum, "Sum"},
	}
	file := ctx.file
	for &g in groups {
		prefix := g.labels if layered else nil
		total := total_weight(&g)
		// Rows are emitted statistic-major so the cell order matches SPSS's table.
		for vi in vars {
			v := &file.variables[vi]
			_, ws := valid_values(ctx, &g, v)
			output.add_number(&t, path(prefix, "N", "Valid"), {var_title(v)}, sum(ws), output.NO_DECIMALS)
		}
		for vi in vars {
			v := &file.variables[vi]
			_, ws := valid_values(ctx, &g, v)
			output.add_number(&t, path(prefix, "N", "Missing"), {var_title(v)}, total - sum(ws), output.NO_DECIMALS)
		}
		for o in order {
			if o.stat not_in stats { continue }
			for vi in vars {
				v := &file.variables[vi]
				xs, ws := valid_values(ctx, &g, v)
				s := summarize(xs, ws)
				d := int(v.print.decimals)
				row, col := path(prefix, o.name), path(nil, var_title(v))
				switch o.stat {
				case .Mean:     add_stat(&t, row, col, s.mean, d + 2)
				case .Semean:   add_stat(&t, row, col, s.se_mean, d + 3)
				case .Median:   add_stat(&t, row, col, percentile(xs, ws, 0.5), d + 2)
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
					mode, multiple := find_mode(xs, ws)
					if math.is_nan(mode) { continue }
					output.add_number(&t, row, col, mode, d, {MULTIPLE_MODES} if multiple else nil)
				}
			}
		}
	}
	return t
}

@(private)
sum :: proc(xs: []f64) -> f64 {
	s := 0.0
	for x in xs { s += x }
	return s
}

@(private)
find_mode :: proc(xs, ws: []f64) -> (mode: f64, multiple: bool) {
	counts := count_values(xs, ws)
	if len(counts) == 0 { return math.nan_f64(), false }
	best := counts[0]
	for c in counts[1:] {
		if c.w > best.w {
			best, multiple = c, false
		} else if c.w == best.w {
			multiple = true
		}
	}
	return best.x, multiple
}

@(private)
frequency_rows :: proc(t: ^output.Table, ctx: ^Context, g: ^Group, prefix: []string, v: ^sav.Variable) {
	file := ctx.file
	total := total_weight(g)

	valid_x := make([dynamic]f64, context.temp_allocator)
	valid_w := make([dynamic]f64, context.temp_allocator)
	miss_x := make([dynamic]f64, context.temp_allocator)
	miss_w := make([dynamic]f64, context.temp_allocator)
	sysmis := 0.0
	for row, i in g.rows {
		x, w := v.numbers[row], g.weights[i]
		switch {
		case x == file.sysmis:
			sysmis += w
		case transform.is_missing(v, x, file.sysmis):
			append(&miss_x, x)
			append(&miss_w, w)
		case:
			append(&valid_x, x)
			append(&valid_w, w)
		}
	}
	n_valid := sum(valid_w[:])

	cumulative := 0.0
	for vc in count_values(valid_x[:], valid_w[:]) {
		row := path(prefix, "Valid", value_text(v, vc.x))
		valid_pct := 100 * vc.w / n_valid
		cumulative += valid_pct
		output.add_number(t, row, {"Frequency"}, vc.w, output.NO_DECIMALS)
		output.add_number(t, row, {"Percent"}, 100 * vc.w / total, 1)
		output.add_number(t, row, {"Valid Percent"}, valid_pct, 1)
		output.add_number(t, row, {"Cumulative Percent"}, cumulative, 1)
	}
	if n_valid > 0 {
		row := path(prefix, "Valid", "Total")
		output.add_number(t, row, {"Frequency"}, n_valid, output.NO_DECIMALS)
		output.add_number(t, row, {"Percent"}, 100 * n_valid / total, 1)
		output.add_number(t, row, {"Valid Percent"}, 100, 1)
	}

	n_missing := total - n_valid
	if len(miss_x) == 0 && sysmis == 0 { return }
	missing_rows := 0
	for vc in count_values(miss_x[:], miss_w[:]) {
		row := path(prefix, "Missing", value_text(v, vc.x))
		output.add_number(t, row, {"Frequency"}, vc.w, output.NO_DECIMALS)
		output.add_number(t, row, {"Percent"}, 100 * vc.w / total, 1)
		missing_rows += 1
	}
	if sysmis > 0 {
		row := path(prefix, "Missing", "System")
		output.add_number(t, row, {"Frequency"}, sysmis, output.NO_DECIMALS)
		output.add_number(t, row, {"Percent"}, 100 * sysmis / total, 1)
		missing_rows += 1
	}
	if missing_rows > 1 {
		row := path(prefix, "Missing", "Total")
		output.add_number(t, row, {"Frequency"}, n_missing, output.NO_DECIMALS)
		output.add_number(t, row, {"Percent"}, 100 * n_missing / total, 1)
	}
	output.add_number(t, path(prefix, "Total"), {"Frequency"}, total, output.NO_DECIMALS)
	output.add_number(t, path(prefix, "Total"), {"Percent"}, 100, 1)
}
