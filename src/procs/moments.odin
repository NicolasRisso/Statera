// Shared summary statistics for DESCRIPTIVES / FREQUENCIES.
// Formulas: docs/specs/procs/descriptives.md (weighted: n is replaced by W, see engine/procedure-context.md)
package procs

import "core:math"

Summary :: struct {
	n:        f64, // sum of weights
	sum:      f64,
	min, max: f64,
	mean:     f64,
	variance: f64, // NaN when undefined
	skewness: f64,
	kurtosis: f64,
	se_mean:  f64,
	se_skew:  f64,
	se_kurt:  f64,
}

summarize :: proc(xs, ws: []f64) -> Summary {
	nan := math.nan_f64()
	s := Summary{variance = nan, skewness = nan, kurtosis = nan, se_mean = nan, se_skew = nan, se_kurt = nan}
	if len(xs) == 0 {
		s.min, s.max, s.mean = nan, nan, nan
		return s
	}
	s.min, s.max = xs[0], xs[0]
	for x, i in xs {
		s.n += ws[i]
		s.sum += ws[i] * x
		s.min = min(s.min, x)
		s.max = max(s.max, x)
	}
	n := s.n
	s.mean = s.sum / n

	m2, m3, m4: f64
	for x, i in xs {
		d := x - s.mean
		w := ws[i]
		m2 += w * d * d
		m3 += w * d * d * d
		m4 += w * d * d * d * d
	}
	if n > 1 {
		s.variance = m2 / (n - 1)
		s.se_mean = math.sqrt(s.variance / n)
	}
	sd := math.sqrt(s.variance)
	if n > 2 && sd > 0 {
		s.skewness = n / ((n - 1) * (n - 2)) * m3 / (sd * sd * sd)
		s.se_skew = math.sqrt(6 * n * (n - 1) / ((n - 2) * (n + 1) * (n + 3)))
	}
	if n > 3 && sd > 0 {
		s.kurtosis = n * (n + 1) / ((n - 1) * (n - 2) * (n - 3)) * m4 / (sd * sd * sd * sd) - 3 * (n - 1) * (n - 1) / ((n - 2) * (n - 3))
		s.se_kurt = math.sqrt(4 * (n * n - 1) * s.se_skew * s.se_skew / ((n - 3) * (n + 5)))
	}
	return s
}

// HAVERAGE percentile over values expanded by cumulative weight.
// Spec: docs/specs/procs/frequencies.md, engine/procedure-context.md
percentile :: proc(xs, ws: []f64, p: f64) -> f64 {
	if len(xs) == 0 { return math.nan_f64() }
	ps := sorted_pairs(xs, ws)
	total := 0.0
	for q in ps { total += q.w }
	t := (total + 1) * p
	k := math.floor(t)
	f := t - k
	if k < 1 { return ps[0].x }
	if k >= total { return ps[len(ps) - 1].x }
	a := value_at(ps, k)
	b := value_at(ps, k + 1)
	return a + f * (b - a)
}

// The value at 1-based position `pos` when each value is repeated by its weight.
@(private)
value_at :: proc(ps: []Weighted, pos: f64) -> f64 {
	cum := 0.0
	for q in ps {
		cum += q.w
		if cum >= pos { return q.x }
	}
	return ps[len(ps) - 1].x
}
