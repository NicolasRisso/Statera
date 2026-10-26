// CROSSTABS. Spec: docs/specs/procs/crosstabs.md
package procs

import "core:fmt"
import "core:math"
import "core:slice"

import "../io/sav"
import "../numerics"
import "../output"
import "../transform"

Xtab_Cell :: enum u8 { Count, Expected, Row, Column, Total }
Xtab_Cells :: bit_set[Xtab_Cell]

Xtab_Stat :: enum u8 { Chisq, Phi, Cc }
Xtab_Stats :: bit_set[Xtab_Stat]

Xtab_Pair :: struct {
	row, col: int, // variable indices
}

Xtab_Options :: struct {
	cells: Xtab_Cells,
	stats: Xtab_Stats,
}

COMPUTED_2X2 :: "Computed only for a 2x2 table"

@(private)
Xtab :: struct {
	rows, cols: []f64,   // distinct values that occur, ascending
	n:          [][]f64, // rounded counts [row][col]
	row_tot:    []f64,
	col_tot:    []f64,
	total:      f64,     // N: sum of rounded cells
	valid_w:    f64,     // unrounded weight of valid cases
	missing:    f64,     // unrounded weight of cases missing on either variable
}

crosstabs :: proc(ctx: ^Context, pairs: []Xtab_Pair, opts: Xtab_Options, items: ^[dynamic]output.Item) {
	file := ctx.file
	for &g in ctx.groups {
		prefix := g.labels if ctx.mode == .Layered else nil
		tabs := make([]Xtab, len(pairs), context.temp_allocator)
		for p, i in pairs { tabs[i] = tabulate(ctx, &g, &file.variables[p.row], &file.variables[p.col]) }

		cps := output.Table{command = "Crosstabs", subtype = "Case Processing Summary", title = "Case Processing Summary"}
		for p, i in pairs {
			x := &tabs[i]
			row := path(prefix, fmt.tprintf("%s * %s", var_title(&file.variables[p.row]), var_title(&file.variables[p.col])))
			// Valid N is the rounded table N; percentages and the total use unrounded weights
			// (golden: xtab_stats, weighted: Valid 25 / 100.0%, Total 23).
			all := x.valid_w + x.missing
			for part in ([?]struct {
					name:     string,
					n, share: f64,
				}{{"Valid", x.total, x.valid_w}, {"Missing", x.missing, x.missing}, {"Total", all, all}}) {
				output.add_number(&cps, row, {part.name, "N"}, part.n, output.NO_DECIMALS)
				output.add_number(&cps, row, {part.name, "Percent"}, 100 * part.share / all if all > 0 else 0, 1, percent = true)
			}
		}
		append(items, cps)

		for p, i in pairs {
			rv, cv := &file.variables[p.row], &file.variables[p.col]
			append(items, crosstab_table(&tabs[i], rv, cv, opts.cells, prefix))
			if .Chisq in opts.stats { append(items, chi_square_table(&tabs[i], prefix)) }
			if opts.stats & {.Phi, .Cc} != {} { append(items, symmetric_table(&tabs[i], opts.stats, prefix)) }
		}
	}
}

@(private)
tabulate :: proc(ctx: ^Context, g: ^Group, rv, cv: ^sav.Variable) -> Xtab {
	sysmis := ctx.file.sysmis
	xs := make([dynamic]f64, context.temp_allocator)
	ys := make([dynamic]f64, context.temp_allocator)
	ws := make([dynamic]f64, context.temp_allocator)
	t: Xtab
	for row, i in g.rows {
		x, y := rv.numbers[row], cv.numbers[row]
		if transform.is_missing(rv, x, sysmis) || transform.is_missing(cv, y, sysmis) {
			t.missing += g.weights[i]
			continue
		}
		append(&xs, x)
		append(&ys, y)
		append(&ws, g.weights[i])
		t.valid_w += g.weights[i]
	}
	t.rows = distinct_sorted(xs[:])
	t.cols = distinct_sorted(ys[:])
	t.n = make([][]f64, len(t.rows), context.temp_allocator)
	for &r in t.n { r = make([]f64, len(t.cols), context.temp_allocator) }
	for x, i in xs {
		r, _ := slice.binary_search(t.rows, x)
		c, _ := slice.binary_search(t.cols, ys[i])
		t.n[r][c] += ws[i]
	}
	// /COUNT ROUND CELL: weighted cell counts are rounded before anything else.
	t.row_tot = make([]f64, len(t.rows), context.temp_allocator)
	t.col_tot = make([]f64, len(t.cols), context.temp_allocator)
	for &r, i in t.n {
		for &v, j in r {
			v = output.round_half_away(v, 0)
			t.row_tot[i] += v
			t.col_tot[j] += v
			t.total += v
		}
	}
	return t
}

@(private)
distinct_sorted :: proc(xs: []f64) -> []f64 {
	s := slice.clone(xs, context.temp_allocator)
	slice.sort(s)
	out := make([dynamic]f64, context.temp_allocator)
	for x in s {
		if len(out) == 0 || out[len(out) - 1] != x { append(&out, x) }
	}
	return out[:]
}

@(private)
crosstab_table :: proc(x: ^Xtab, rv, cv: ^sav.Variable, cells: Xtab_Cells, prefix: []string) -> output.Table {
	rt, ct := var_title(rv), var_title(cv)
	t := output.Table{command = "Crosstabs", subtype = "Crosstabulation", title = fmt.aprintf("%s * %s Crosstabulation", rt, ct)}
	cells := cells if cells != {} else {.Count}
	single := card(cells) == 1
	names := [Xtab_Cell]string {
		.Count    = "Count",
		.Expected = "Expected Count",
		.Row      = fmt.tprintf("%% within %s", rt),
		.Column   = fmt.tprintf("%% within %s", ct),
		.Total    = "% of Total",
	}
	N := x.total

	emit :: proc(t: ^output.Table, kind: Xtab_Cell, row, col, layer: []string, n, r, c, total: f64) {
		switch kind {
		case .Count:    output.add_number(t, row, col, n, output.NO_DECIMALS, layer = layer)
		case .Expected: output.add_number(t, row, col, r * c / total, 1, layer = layer)
		case .Row:      output.add_number(t, row, col, 100 * n / r if r > 0 else 0, 1, layer = layer, percent = true)
		case .Column:   output.add_number(t, row, col, 100 * n / c if c > 0 else 0, 1, layer = layer, percent = true)
		case .Total:    output.add_number(t, row, col, 100 * n / total if total > 0 else 0, 1, layer = layer, percent = true)
		}
	}

	block :: proc(t: ^output.Table, x: ^Xtab, cv: ^sav.Variable, cells: Xtab_Cells, single: bool, names: [Xtab_Cell]string,
		row_label: []string, counts: []f64, row_total: f64) {
		ct := var_title(cv)
		for kind in Xtab_Cell {
			if kind not_in cells { continue }
			row := row_label if single else path(row_label, names[kind])
			layer := path(nil, names[kind]) if single else nil
			for value, j in x.cols {
				emit(t, kind, row, path(nil, ct, value_text(cv, value)), layer, counts[j], row_total, x.col_tot[j], x.total)
			}
			emit(t, kind, row, path(nil, "Total"), layer, row_total, row_total, x.total, x.total)
		}
	}

	for value, i in x.rows {
		block(&t, x, cv, cells, single, names, path(prefix, rt, value_text(rv, value)), x.n[i], x.row_tot[i])
	}
	block(&t, x, cv, cells, single, names, path(prefix, "Total"), x.col_tot, N)
	return t
}

@(private)
Chi_Square :: struct {
	pearson, lr, linear: f64,
	df:                  f64,
	r, c:                int,
	min_expected:        f64,
	small_cells:         int,
}

@(private)
chi_square :: proc(x: ^Xtab) -> Chi_Square {
	s := Chi_Square{r = len(x.rows), c = len(x.cols), min_expected = math.F64_MAX}
	N := x.total
	for i in 0 ..< s.r {
		for j in 0 ..< s.c {
			e := x.row_tot[i] * x.col_tot[j] / N
			o := x.n[i][j]
			s.pearson += (o - e) * (o - e) / e
			if o > 0 { s.lr += 2 * o * math.ln(o / e) }
			s.min_expected = min(s.min_expected, e)
			if e < 5 { s.small_cells += 1 }
		}
	}
	s.df = f64((s.r - 1) * (s.c - 1))

	// Linear-by-linear: (N−1)·R², R = count-weighted Pearson correlation of the category values.
	mx, my: f64
	for i in 0 ..< s.r { mx += x.rows[i] * x.row_tot[i] }
	for j in 0 ..< s.c { my += x.cols[j] * x.col_tot[j] }
	mx /= N
	my /= N
	sxx, syy, sxy: f64
	for i in 0 ..< s.r {
		for j in 0 ..< s.c {
			dx, dy := x.rows[i] - mx, x.cols[j] - my
			sxx += x.n[i][j] * dx * dx
			syy += x.n[i][j] * dy * dy
			sxy += x.n[i][j] * dx * dy
		}
	}
	if sxx > 0 && syy > 0 {
		R := sxy / math.sqrt(sxx * syy)
		s.linear = (N - 1) * R * R
	}
	return s
}

@(private)
chi_square_table :: proc(x: ^Xtab, prefix: []string) -> output.Table {
	t := output.Table{command = "Crosstabs", subtype = "Chi Square Tests", title = "Chi-Square Tests"}
	s := chi_square(x)
	N := x.total
	VALUE, DF, SIG :: "Value", "df", "Asymptotic Significance (2-sided)"
	pct := 100 * f64(s.small_cells) / f64(s.r * s.c)
	note := fmt.tprintf("%d cells (%s%%) have expected count less than 5. The minimum expected count is %s.",
		s.small_cells, output.format_number(pct, 1, context.temp_allocator),
		output.format_number(s.min_expected, 2, context.temp_allocator))

	row :: proc(t: ^output.Table, prefix: []string, name: string, value, df: f64, notes: []string = nil) {
		output.add_number(t, path(prefix, name), {VALUE}, value, 3, notes)
		output.add_number(t, path(prefix, name), {DF}, df, output.NO_DECIMALS)
		output.add_number(t, path(prefix, name), {SIG}, numerics.chisq_sf(value, df), 3)
	}

	is_2x2 := s.r == 2 && s.c == 2
	row(&t, prefix, "Pearson Chi-Square", s.pearson, s.df, {note})
	if is_2x2 {
		a, b, c, d := x.n[0][0], x.n[0][1], x.n[1][0], x.n[1][1]
		diff := max(abs(a * d - b * c) - N / 2, 0)
		yates := N * diff * diff / (x.row_tot[0] * x.row_tot[1] * x.col_tot[0] * x.col_tot[1])
		row(&t, prefix, "Continuity Correction", yates, 1)
		output.add_label_note(&t, "Continuity Correction", COMPUTED_2X2)
	}
	row(&t, prefix, "Likelihood Ratio", s.lr, s.df)
	if is_2x2 {
		two, one := numerics.fisher_exact(int(x.n[0][0]), int(x.n[0][1]), int(x.n[1][0]), int(x.n[1][1]))
		output.add_number(&t, path(prefix, "Fisher's Exact Test"), {"Exact Sig. (2-sided)"}, two, 3)
		output.add_number(&t, path(prefix, "Fisher's Exact Test"), {"Exact Sig. (1-sided)"}, one, 3)
	}
	row(&t, prefix, "Linear-by-Linear Association", s.linear, 1)
	output.add_number(&t, path(prefix, "N of Valid Cases"), {VALUE}, N, output.NO_DECIMALS)
	return t
}

@(private)
symmetric_table :: proc(x: ^Xtab, stats: Xtab_Stats, prefix: []string) -> output.Table {
	t := output.Table{command = "Crosstabs", subtype = "Symmetric Measures", title = "Symmetric Measures"}
	s := chi_square(x)
	N := x.total
	p := numerics.chisq_sf(s.pearson, s.df)
	measure :: proc(t: ^output.Table, prefix: []string, name: string, value, p: f64) {
		output.add_number(t, path(prefix, "Nominal by Nominal", name), {"Value"}, value, 3)
		output.add_number(t, path(prefix, "Nominal by Nominal", name), {"Approximate Significance"}, p, 3)
	}
	if .Phi in stats {
		phi := math.sqrt(s.pearson / N)
		if s.r == 2 && s.c == 2 {
			a, b, c, d := x.n[0][0], x.n[0][1], x.n[1][0], x.n[1][1]
			if a * d - b * c < 0 { phi = -phi }
		}
		measure(&t, prefix, "Phi", phi, p)
		measure(&t, prefix, "Cramer's V", math.sqrt(s.pearson / (N * f64(min(s.r, s.c) - 1))), p)
	}
	if .Cc in stats {
		measure(&t, prefix, "Contingency Coefficient", math.sqrt(s.pearson / (s.pearson + N)), p)
	}
	output.add_number(&t, path(prefix, "N of Valid Cases"), {"Value"}, N, output.NO_DECIMALS)
	return t
}
