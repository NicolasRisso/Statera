// ONEWAY. Spec: docs/specs/procs/oneway.md
package procs

import "core:math"

import "../numerics"
import "../output"

Oneway_Options :: struct {
	descriptives: bool,
	homogeneity:  bool,
	welch:        bool,
}

ASYMPTOTIC_F :: "Asymptotically F distributed."

oneway :: proc(ctx: ^Context, deps: []int, factor: int, opts: Oneway_Options, items: ^[dynamic]output.Item) {
	file := ctx.file
	fv := &file.variables[factor]
	single := len(deps) == 1
	// With one dependent it is the layer; with several, the outermost row label.
	place :: proc(single: bool, title: string, rest: ..string) -> (row, layer: []string) {
		if single { return path(nil, ..rest), path(nil, title) }
		return path([]string{title}, ..rest), nil
	}

	for &g in ctx.groups {
		desc := output.Table{command = "Oneway", subtype = "Descriptives", title = "Descriptives"}
		homo := output.Table{command = "Oneway", subtype = "Test of Homogeneity of Variance", title = "Test of Homogeneity of Variances"}
		anova := output.Table{command = "Oneway", subtype = "ANOVA", title = "ANOVA"}
		robust := output.Table{command = "Oneway", subtype = "Robust Tests of Equality of Means", title = "Robust Tests of Equality of Means"}

		for d in deps {
			dv := &file.variables[d]
			title := var_title(dv)
			dd := int(dv.print.decimals)
			samples := factor_samples(ctx, &g, dv, fv)
			levels := factor_levels(ctx, &g, dv, fv)

			if opts.descriptives {
				all_x := make([dynamic]f64, context.temp_allocator)
				all_w := make([dynamic]f64, context.temp_allocator)
				for s, k in samples {
					row, layer := place(single, title, value_text(fv, levels[k]))
					add_descriptives_row(&desc, row, layer, s.xs, s.ws, dd)
					append(&all_x, ..s.xs)
					append(&all_w, ..s.ws)
				}
				row, layer := place(single, title, "Total")
				add_descriptives_row(&desc, row, layer, all_x[:], all_w[:], dd)
			}

			if opts.homogeneity {
				variants := [?]struct {
					name:   string,
					center: Levene_Center,
					adjust: bool,
				}{
					{"Based on Mean", .Mean, false},
					{"Based on Median", .Median, false},
					{"Based on Median and with adjusted df", .Median, true},
					{"Based on trimmed mean", .Trimmed_Mean, false},
				}
				for v in variants {
					z := levene_deviations(samples, v.center)
					a := one_way_anova(z)
					df2 := a.df_within
					if v.adjust { df2 = satterthwaite_within_df(z) }
					row, layer := place(single, title, v.name)
					output.add_number(&homo, row, {"Levene Statistic"}, a.f, 3, layer = layer)
					output.add_number(&homo, row, {"df1"}, a.df_between, output.NO_DECIMALS, layer = layer)
					output.add_number(&homo, row, {"df2"}, df2, df_decimals(df2), layer = layer)
					output.add_number(&homo, row, {"Sig."}, numerics.f_sf(a.f, a.df_between, df2), 3, layer = layer)
				}
			}

			a := one_way_anova(samples)
			between, layer := place(single, title, "Between Groups")
			output.add_number(&anova, between, {"Sum of Squares"}, a.ss_between, 3, layer = layer)
			output.add_number(&anova, between, {"df"}, a.df_between, output.NO_DECIMALS, layer = layer)
			output.add_number(&anova, between, {"Mean Square"}, a.ms_between, 3, layer = layer)
			output.add_number(&anova, between, {"F"}, a.f, 3, layer = layer)
			output.add_number(&anova, between, {"Sig."}, a.sig, 3, layer = layer)
			within, _ := place(single, title, "Within Groups")
			output.add_number(&anova, within, {"Sum of Squares"}, a.ss_within, 3, layer = layer)
			output.add_number(&anova, within, {"df"}, a.df_within, output.NO_DECIMALS, layer = layer)
			output.add_number(&anova, within, {"Mean Square"}, a.ms_within, 3, layer = layer)
			total, _ := place(single, title, "Total")
			output.add_number(&anova, total, {"Sum of Squares"}, a.ss_total, 3, layer = layer)
			output.add_number(&anova, total, {"df"}, a.df_total, output.NO_DECIMALS, layer = layer)

			if opts.welch {
				w := welch_anova(samples)
				row, wl := place(single, title, "Welch")
				output.add_label_note(&robust, "Statistic", ASYMPTOTIC_F)
				output.add_number(&robust, row, {"Statistic"}, w.f, 3, layer = wl)
				output.add_number(&robust, row, {"df1"}, w.df1, output.NO_DECIMALS, layer = wl)
				output.add_number(&robust, row, {"df2"}, w.df2, df_decimals(w.df2), layer = wl)
				output.add_number(&robust, row, {"Sig."}, w.sig, 3, layer = wl)
			}
		}
		if opts.descriptives { append(items, desc) }
		if opts.homogeneity { append(items, homo) }
		append(items, anova)
		if opts.welch { append(items, robust) }
	}
}

@(private)
add_descriptives_row :: proc(t: ^output.Table, row, layer: []string, xs, ws: []f64, d: int) {
	s := summarize(xs, ws)
	output.add_number(t, row, {"N"}, s.n, output.NO_DECIMALS, layer = layer)
	add_stat(t, row, {"Mean"}, s.mean, d + 2, layer)
	add_stat(t, row, {"Std. Deviation"}, math.sqrt(s.variance), d + 3, layer)
	add_stat(t, row, {"Std. Error"}, s.se_mean, d + 3, layer)
	CI :: "95% Confidence Interval for Mean"
	if s.n > 1 {
		q := numerics.t_quantile(0.975, s.n - 1)
		add_stat(t, row, {CI, "Lower Bound"}, s.mean - q * s.se_mean, d + 2, layer)
		add_stat(t, row, {CI, "Upper Bound"}, s.mean + q * s.se_mean, d + 2, layer)
	}
	add_stat(t, row, {"Minimum"}, s.min, d, layer)
	add_stat(t, row, {"Maximum"}, s.max, d, layer)
}
