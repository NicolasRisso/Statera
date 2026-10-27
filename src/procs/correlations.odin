// CORRELATIONS. Spec: docs/specs/procs/correlations.md
package procs

import "core:fmt"
import "core:math"

import "../io/sav"
import "../numerics"
import "../output"
import "../transform"

Corr_Options :: struct {
	one_tailed:   bool,
	flag:         bool, // /PRINT=NOSIG
	descriptives: bool,
	xprod:        bool,
	listwise:     bool,
}

// Sums for one variable pair over the cases valid on both (plus any listwise constraint).
@(private)
Pair_Sums :: struct {
	n, mx, my, sxx, syy, sxy: f64,
}

@(private)
pair_sums :: proc(file: ^sav.File, g: ^Group, a, b: ^sav.Variable, rows_ok: []bool) -> Pair_Sums {
	p: Pair_Sums
	for row, i in g.rows {
		if !rows_ok[i] { continue }
		x, y := a.numbers[row], b.numbers[row]
		if transform.is_missing(a, x, file.sysmis) || transform.is_missing(b, y, file.sysmis) { continue }
		w := g.weights[i]
		p.n += w
		p.mx += w * x
		p.my += w * y
	}
	if p.n == 0 { return p }
	p.mx /= p.n
	p.my /= p.n
	for row, i in g.rows {
		if !rows_ok[i] { continue }
		x, y := a.numbers[row], b.numbers[row]
		if transform.is_missing(a, x, file.sysmis) || transform.is_missing(b, y, file.sysmis) { continue }
		w := g.weights[i]
		p.sxx += w * (x - p.mx) * (x - p.mx)
		p.syy += w * (y - p.my) * (y - p.my)
		p.sxy += w * (x - p.mx) * (y - p.my)
	}
	return p
}

// Two-sided p-value of a Pearson r with n cases.
r_sig2 :: proc(r, n: f64) -> f64 {
	if abs(r) >= 1 { return 0 }
	return numerics.t_sig2(r * math.sqrt((n - 2) / (1 - r * r)), n - 2)
}

// Rows of `g` usable under listwise deletion over `vars` (all true when pairwise).
@(private)
listwise_rows :: proc(file: ^sav.File, g: ^Group, vars: []int, listwise: bool) -> []bool {
	ok := make([]bool, len(g.rows), context.temp_allocator)
	for row, i in g.rows {
		ok[i] = true
		if !listwise { continue }
		for v in vars {
			vv := &file.variables[v]
			if transform.is_missing(vv, vv.numbers[row], file.sysmis) {
				ok[i] = false
				break
			}
		}
	}
	return ok
}

correlations :: proc(ctx: ^Context, rows_vars, cols_vars: []int, opts: Corr_Options, items: ^[dynamic]output.Item) {
	file := ctx.file
	all := make([dynamic]int, context.temp_allocator)
	append(&all, ..rows_vars)
	for c in cols_vars {
		dup := false
		for r in rows_vars { dup ||= r == c }
		if !dup { append(&all, c) }
	}
	square := len(cols_vars) == 0
	cols := rows_vars if square else cols_vars

	for &g in ctx.groups {
		ok := listwise_rows(file, &g, all[:], opts.listwise)
		if opts.descriptives {
			desc := output.Table{command = "Correlations", subtype = "Descriptive Statistics", title = "Descriptive Statistics"}
			for v in all {
				vv := &file.variables[v]
				xs := make([dynamic]f64, context.temp_allocator)
				ws := make([dynamic]f64, context.temp_allocator)
				for row, i in g.rows {
					if !ok[i] || transform.is_missing(vv, vv.numbers[row], file.sysmis) { continue }
					append(&xs, vv.numbers[row])
					append(&ws, g.weights[i])
				}
				s := summarize(xs[:], ws[:])
				d := int(vv.print.decimals)
				row := []string{var_title(vv)}
				add_stat(&desc, row, {"Mean"}, s.mean, d + 2)
				add_stat(&desc, row, {"Std. Deviation"}, math.sqrt(s.variance), d + 3)
				output.add_number(&desc, row, {"N"}, s.n, output.NO_DECIMALS)
			}
			append(items, desc)
		}

		t := output.Table{command = "Correlations", subtype = "Correlations", title = "Correlations"}
		tail := "1-tailed" if opts.one_tailed else "2-tailed"
		sig_name := fmt.tprintf("Sig. (%s)", tail)
		listwise_n := 0.0
		for rv in rows_vars {
			a := &file.variables[rv]
			sums := make([]Pair_Sums, len(cols), context.temp_allocator)
			for cv, j in cols { sums[j] = pair_sums(file, &g, a, &file.variables[cv], ok) }
			row_label := var_title(a)
			for cv, j in cols {
				p := sums[j]
				col := []string{var_title(&file.variables[cv])}
				row := []string{row_label, "Pearson Correlation"}
				if square && cv == rv {
					output.add_number(&t, row, col, 1, output.NO_DECIMALS)
					continue
				}
				r := p.sxy / math.sqrt(p.sxx * p.syy)
				sig := r_sig2(r, p.n)
				if opts.one_tailed { sig /= 2 }
				note: [1]string
				flagged := opts.flag && sig < 0.05
				if flagged {
					level := "0.01" if sig < 0.01 else "0.05"
					note[0] = fmt.tprintf("Correlation is significant at the %s level (%s).", level, tail)
				}
				output.add_number(&t, row, col, r, 3, note[:] if flagged else nil)
			}
			for cv, j in cols {
				if square && cv == rv { continue }
				p := sums[j]
				r := p.sxy / math.sqrt(p.sxx * p.syy)
				sig := r_sig2(r, p.n)
				if opts.one_tailed { sig /= 2 }
				output.add_number(&t, {row_label, sig_name}, {var_title(&file.variables[cv])}, sig, 3)
			}
			if opts.xprod {
				for cv, j in cols {
					output.add_number(&t, {row_label, "Sum of Squares and Cross-products"}, {var_title(&file.variables[cv])}, sums[j].sxy, 3)
				}
				for cv, j in cols {
					output.add_number(&t, {row_label, "Covariance"}, {var_title(&file.variables[cv])}, sums[j].sxy / (sums[j].n - 1), 3)
				}
			}
			if !opts.listwise {
				for cv, j in cols {
					output.add_number(&t, {row_label, "N"}, {var_title(&file.variables[cv])}, sums[j].n, output.NO_DECIMALS)
				}
			}
			if len(cols) > 0 { listwise_n = sums[0].n }
		}
		if opts.listwise {
			t.captions = clone_strings({fmt.tprintf("Listwise N=%s", output.format_number(listwise_n, output.NO_DECIMALS, context.temp_allocator))})
		}
		append(items, t)
	}
}
