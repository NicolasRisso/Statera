// One-way ANOVA building blocks shared by MEANS, T-TEST and ONEWAY.
// Specs: docs/specs/procs/oneway.md, t-test.md
package procs

import "core:math"

import "../numerics"

// Valid values of one dependent within one factor level.
Sample :: struct {
	xs, ws: []f64,
}

Anova :: struct {
	ss_between, ss_within, ss_total: f64,
	df_between, df_within, df_total: f64,
	ms_between, ms_within:           f64,
	f, sig:                          f64,
}

one_way_anova :: proc(groups: []Sample) -> Anova {
	a: Anova
	grand, total_w := 0.0, 0.0
	k := 0
	for g in groups {
		if len(g.xs) == 0 { continue }
		k += 1
		for x, i in g.xs {
			grand += g.ws[i] * x
			total_w += g.ws[i]
		}
	}
	grand /= total_w
	for g in groups {
		if len(g.xs) == 0 { continue }
		s := summarize(g.xs, g.ws)
		a.ss_between += s.n * (s.mean - grand) * (s.mean - grand)
		for x, i in g.xs { a.ss_within += g.ws[i] * (x - s.mean) * (x - s.mean) }
	}
	a.ss_total = a.ss_between + a.ss_within
	a.df_between = f64(k - 1)
	a.df_within = total_w - f64(k)
	a.df_total = total_w - 1
	a.ms_between = a.ss_between / a.df_between
	a.ms_within = a.ss_within / a.df_within
	a.f = a.ms_between / a.ms_within
	a.sig = numerics.f_sf(a.f, a.df_between, a.df_within)
	return a
}

Levene_Center :: enum u8 { Mean, Median, Trimmed_Mean }

// Absolute deviations from each group's centre, the input to Levene's test.
levene_deviations :: proc(groups: []Sample, center: Levene_Center) -> []Sample {
	out := make([]Sample, len(groups), context.temp_allocator)
	for g, gi in groups {
		c: f64
		switch center {
		case .Mean:         c = summarize(g.xs, g.ws).mean
		case .Median:       c = percentile(g.xs, g.ws, 0.5)
		case .Trimmed_Mean: c = trimmed_mean(g.xs, g.ws, 0.05)
		}
		z := make([]f64, len(g.xs), context.temp_allocator)
		for x, i in g.xs { z[i] = abs(x - c) }
		out[gi] = {z, g.ws}
	}
	return out
}

// Satterthwaite df for the within-group sum of squares of `groups` (Levene, adjusted df).
satterthwaite_within_df :: proc(groups: []Sample) -> f64 {
	num, den := 0.0, 0.0
	for g in groups {
		if len(g.xs) < 2 { continue }
		s := summarize(g.xs, g.ws)
		u := 0.0
		for x, i in g.xs { u += g.ws[i] * (x - s.mean) * (x - s.mean) }
		num += u
		den += u * u / (s.n - 1)
	}
	return num * num / den
}

// Mean after trimming `alpha` of the total weight from each end, with fractional end weights.
trimmed_mean :: proc(xs, ws: []f64, alpha: f64) -> f64 {
	ps := sorted_pairs(xs, ws)
	total := 0.0
	for p in ps { total += p.w }
	tc := alpha * total
	sum, cum := 0.0, 0.0
	for p in ps {
		lo, hi := cum, cum + p.w
		cum = hi
		// Portion of this value's weight inside [tc, total − tc].
		keep := min(hi, total - tc) - max(lo, tc)
		if keep > 0 { sum += keep * p.x }
	}
	return sum / (total - 2 * tc)
}

Welch :: struct {
	f, df1, df2, sig: f64,
}

welch_anova :: proc(groups: []Sample) -> Welch {
	k := 0
	W, mw := 0.0, 0.0
	ws := make([]f64, len(groups), context.temp_allocator)
	sums := make([]Summary, len(groups), context.temp_allocator)
	for g, i in groups {
		if len(g.xs) == 0 { continue }
		k += 1
		sums[i] = summarize(g.xs, g.ws)
		ws[i] = sums[i].n / sums[i].variance
		W += ws[i]
		mw += ws[i] * sums[i].mean
	}
	mw /= W
	between, lambda := 0.0, 0.0
	for g, i in groups {
		if len(g.xs) == 0 { continue }
		between += ws[i] * (sums[i].mean - mw) * (sums[i].mean - mw)
		r := 1 - ws[i] / W
		lambda += r * r / (sums[i].n - 1)
	}
	kf := f64(k)
	w: Welch
	w.f = (between / (kf - 1)) / (1 + 2 * (kf - 2) * lambda / (kf * kf - 1))
	w.df1 = kf - 1
	w.df2 = (kf * kf - 1) / (3 * lambda)
	w.sig = numerics.f_sf(w.f, w.df1, w.df2)
	return w
}

// df for display: integers show no decimals, fractional df show 3.
df_decimals :: proc(df: f64) -> int {
	return -1 if df == math.floor(df) else 3
}
