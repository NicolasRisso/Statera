// MEANS. Spec: docs/specs/procs/means.md
package procs

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

import "../io/sav"
import "../output"
import "../transform"

Means_Cell :: enum u8 { Mean, Count, Stddev, Min, Max, Sum, Variance, Semean, Range }

MEANS_DEFAULT_CELLS :: []Means_Cell{.Mean, .Count, .Stddev}

Means_Table :: struct {
	deps: []int,
	by:   []int, // nesting order: BY v1 BY v2 ...
}

@(private)
MEANS_CELL_NAMES := [Means_Cell]string {
	.Mean     = "Mean",
	.Count    = "N",
	.Stddev   = "Std. Deviation",
	.Min      = "Minimum",
	.Max      = "Maximum",
	.Sum      = "Sum",
	.Variance = "Variance",
	.Semean   = "Std. Error of Mean",
	.Range    = "Range",
}

// One level of a category path: a value, or the level's Total.
@(private)
Level :: struct {
	value: f64,
	total: bool,
}

means :: proc(ctx: ^Context, tables: []Means_Table, cells: []Means_Cell, anova: bool, items: ^[dynamic]output.Item) {
	cells := cells if len(cells) > 0 else MEANS_DEFAULT_CELLS
	file := ctx.file
	for &g in ctx.groups {
		for spec in tables {
			by_label := make([dynamic]string, context.temp_allocator)
			for b in spec.by { append(&by_label, var_title(&file.variables[b])) }
			by_text := strings.join(by_label[:], " * ", context.temp_allocator)

			// Case Processing Summary: two spaces before the first '*' (as SPSS prints it).
			cps := output.Table{command = "Means", subtype = "Case Processing Summary", title = "Case Processing Summary"}
			for d in spec.deps {
				dv := &file.variables[d]
				included, all := 0.0, 0.0
				for row, i in g.rows {
					all += g.weights[i]
					if valid_row(file, dv, spec.by, row) { included += g.weights[i] }
				}
				label := []string{fmt.tprintf("%s  * %s", var_title(dv), by_text)}
				for part in ([?]struct {
						name: string,
						n:    f64,
					}{{"Included", included}, {"Excluded", all - included}, {"Total", all}}) {
					output.add_number(&cps, label, {part.name, "N"}, part.n, output.NO_DECIMALS)
					output.add_number(&cps, label, {part.name, "Percent"}, 100 * part.n / all if all > 0 else 0, 1, percent = true)
				}
			}
			append(items, cps)
			append(items, means_report(ctx, &g, spec, cells))

			if anova { means_anova(ctx, &g, spec, by_label[0], items) }
		}
	}
}

@(private)
valid_row :: proc(file: ^sav.File, dv: ^sav.Variable, by: []int, row: int) -> bool {
	if transform.is_missing(dv, dv.numbers[row], file.sysmis) { return false }
	for b in by {
		bv := &file.variables[b]
		if transform.is_missing(bv, bv.numbers[row], file.sysmis) { return false }
	}
	return true
}

@(private)
means_report :: proc(ctx: ^Context, g: ^Group, spec: Means_Table, cells: []Means_Cell) -> output.Table {
	file := ctx.file
	t := output.Table{command = "Means", subtype = "Report", title = "Report"}

	// Cases valid on every BY variable and at least one dependent define the categories.
	base := make([dynamic]int, context.temp_allocator)
	for row, i in g.rows {
		any_dep := false
		for d in spec.deps { any_dep ||= valid_row(file, &file.variables[d], spec.by, row) }
		if any_dep { append(&base, i) }
	}

	paths := make([dynamic][]Level, context.temp_allocator)
	prefix := make([]Level, len(spec.by), context.temp_allocator)
	enumerate_levels(file, g, spec.by, base[:], 0, prefix, &paths)

	single := len(spec.deps) == 1
	for p in paths {
		labels := make([]string, len(p), context.temp_allocator)
		for l, k in p {
			labels[k] = "Total" if l.total else value_text(&file.variables[spec.by[k]], l.value)
		}
		for cell in cells {
			for d in spec.deps {
				dv := &file.variables[d]
				xs := make([dynamic]f64, context.temp_allocator)
				ws := make([dynamic]f64, context.temp_allocator)
				for i in base {
					row := g.rows[i]
					if !valid_row(file, dv, spec.by, row) || !matches(file, spec.by, p, row) { continue }
					append(&xs, dv.numbers[row])
					append(&ws, g.weights[i])
				}
				s := summarize(xs[:], ws[:])
				dd := int(dv.print.decimals)
				value, decimals := 0.0, 0
				switch cell {
				case .Mean:     value, decimals = s.mean, dd + 2
				case .Count:    value, decimals = s.n, output.NO_DECIMALS
				case .Stddev:   value, decimals = math.sqrt(s.variance), dd + 3
				case .Min:      value, decimals = s.min, dd
				case .Max:      value, decimals = s.max, dd
				case .Sum:      value, decimals = s.sum, dd
				case .Variance: value, decimals = s.variance, 3
				case .Semean:   value, decimals = s.se_mean, dd + 3
				case .Range:    value, decimals = s.max - s.min, dd
				}
				if single {
					add_stat(&t, labels, {MEANS_CELL_NAMES[cell]}, value, decimals, path(nil, var_title(dv)))
				} else {
					add_stat(&t, path(labels, MEANS_CELL_NAMES[cell]), {var_title(dv)}, value, decimals)
				}
			}
		}
	}
	return t
}

// Category paths in SPSS order: at each level, the values present (ascending) then Total.
@(private)
enumerate_levels :: proc(file: ^sav.File, g: ^Group, by: []int, base: []int, level: int, prefix: []Level, out: ^[dynamic][]Level) {
	if level == len(by) {
		append(out, slice.clone(prefix, context.temp_allocator))
		return
	}
	bv := &file.variables[by[level]]
	values := make([dynamic]f64, context.temp_allocator)
	for i in base {
		row := g.rows[i]
		if !matches(file, by[:level], prefix[:level], row) { continue }
		append(&values, bv.numbers[row])
	}
	for v in distinct_sorted(values[:]) {
		prefix[level] = {value = v}
		enumerate_levels(file, g, by, base, level + 1, prefix, out)
	}
	prefix[level] = {total = true}
	enumerate_levels(file, g, by, base, level + 1, prefix, out)
}

@(private)
matches :: proc(file: ^sav.File, by: []int, p: []Level, row: int) -> bool {
	for l, k in p {
		if l.total { continue }
		if file.variables[by[k]].numbers[row] != l.value { return false }
	}
	return true
}

@(private)
means_anova :: proc(ctx: ^Context, g: ^Group, spec: Means_Table, factor_label: string, items: ^[dynamic]output.Item) {
	file := ctx.file
	t := output.Table{command = "Means", subtype = "ANOVA", title = "ANOVA Table"}
	assoc := output.Table{command = "Means", subtype = "Measures of Association", title = "Measures of Association"}
	for d in spec.deps {
		dv := &file.variables[d]
		groups := factor_samples(ctx, g, dv, &file.variables[spec.by[0]], spec.by)
		a := one_way_anova(groups)
		label := fmt.tprintf("%s * %s", var_title(dv), factor_label)
		between := []string{label, "Between Groups", "(Combined)"}
		output.add_number(&t, between, {"Sum of Squares"}, a.ss_between, 3)
		output.add_number(&t, between, {"df"}, a.df_between, output.NO_DECIMALS)
		output.add_number(&t, between, {"Mean Square"}, a.ms_between, 3)
		output.add_number(&t, between, {"F"}, a.f, 3)
		output.add_number(&t, between, {"Sig."}, a.sig, 3)
		output.add_number(&t, {label, "Within Groups"}, {"Sum of Squares"}, a.ss_within, 3)
		output.add_number(&t, {label, "Within Groups"}, {"df"}, a.df_within, output.NO_DECIMALS)
		output.add_number(&t, {label, "Within Groups"}, {"Mean Square"}, a.ms_within, 3)
		output.add_number(&t, {label, "Total"}, {"Sum of Squares"}, a.ss_total, 3)
		output.add_number(&t, {label, "Total"}, {"df"}, a.df_total, output.NO_DECIMALS)

		eta2 := a.ss_between / a.ss_total
		output.add_number(&assoc, {label}, {"Eta"}, math.sqrt(eta2), 3)
		output.add_number(&assoc, {label}, {"Eta Squared"}, eta2, 3)
	}
	append(items, t)
	append(items, assoc)
}

// Splits the valid values of `dv` by the levels of `factor` (ascending). Cases must also be
// valid on every variable in `also_valid`.
factor_samples :: proc(ctx: ^Context, g: ^Group, dv, factor: ^sav.Variable, also_valid: []int = nil) -> []Sample {
	file := ctx.file
	levels := make([dynamic]f64, context.temp_allocator)
	for row in g.rows {
		if valid_row(file, dv, also_valid, row) && !transform.is_missing(factor, factor.numbers[row], file.sysmis) {
			append(&levels, factor.numbers[row])
		}
	}
	values := distinct_sorted(levels[:])
	out := make([]Sample, len(values), context.temp_allocator)
	for v, k in values {
		xs := make([dynamic]f64, context.temp_allocator)
		ws := make([dynamic]f64, context.temp_allocator)
		for row, i in g.rows {
			if factor.numbers[row] != v || !valid_row(file, dv, also_valid, row) { continue }
			append(&xs, dv.numbers[row])
			append(&ws, g.weights[i])
		}
		out[k] = {xs[:], ws[:]}
	}
	return out
}

// Level values matching factor_samples' order.
factor_levels :: proc(ctx: ^Context, g: ^Group, dv, factor: ^sav.Variable) -> []f64 {
	file := ctx.file
	levels := make([dynamic]f64, context.temp_allocator)
	for row in g.rows {
		if valid_row(file, dv, nil, row) && !transform.is_missing(factor, factor.numbers[row], file.sysmis) {
			append(&levels, factor.numbers[row])
		}
	}
	return distinct_sorted(levels[:])
}
