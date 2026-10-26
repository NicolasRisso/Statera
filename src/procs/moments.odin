// Shared summary statistics for DESCRIPTIVES / FREQUENCIES. Formulas: docs/specs/procs/descriptives.md
package procs

import "core:math"
import "core:slice"

import "../io/sav"
import "../transform"

Summary :: struct {
	n:        f64,
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

// Valid (non-missing) values of a numeric variable, in case order.
valid_values :: proc(file: ^sav.File, v: ^sav.Variable, allocator := context.temp_allocator) -> []f64 {
	out := make([dynamic]f64, 0, len(v.numbers), allocator)
	for x in v.numbers {
		if !transform.is_missing(v, x, file.sysmis) { append(&out, x) }
	}
	return out[:]
}

summarize :: proc(xs: []f64) -> Summary {
	s := Summary{variance = math.nan_f64(), skewness = math.nan_f64(), kurtosis = math.nan_f64(),
		se_mean = math.nan_f64(), se_skew = math.nan_f64(), se_kurt = math.nan_f64()}
	n := f64(len(xs))
	s.n = n
	if len(xs) == 0 {
		s.min, s.max, s.mean = math.nan_f64(), math.nan_f64(), math.nan_f64()
		return s
	}
	s.min, s.max = xs[0], xs[0]
	for x in xs {
		s.sum += x
		s.min = min(s.min, x)
		s.max = max(s.max, x)
	}
	s.mean = s.sum / n

	m2, m3, m4: f64
	for x in xs {
		d := x - s.mean
		m2 += d * d
		m3 += d * d * d
		m4 += d * d * d * d
	}
	if n >= 2 {
		s.variance = m2 / (n - 1)
		s.se_mean = math.sqrt(s.variance / n)
	}
	sd := math.sqrt(s.variance)
	if n >= 3 && sd > 0 {
		s.skewness = n / ((n - 1) * (n - 2)) * m3 / (sd * sd * sd)
		s.se_skew = math.sqrt(6 * n * (n - 1) / ((n - 2) * (n + 1) * (n + 3)))
	}
	if n >= 4 && sd > 0 {
		s.kurtosis = n * (n + 1) / ((n - 1) * (n - 2) * (n - 3)) * m4 / (sd * sd * sd * sd) - 3 * (n - 1) * (n - 1) / ((n - 2) * (n - 3))
		s.se_kurt = math.sqrt(4 * (n * n - 1) * s.se_skew * s.se_skew / ((n - 3) * (n + 5)))
	}
	return s
}

// HAVERAGE percentile of sorted values. Spec: docs/specs/procs/frequencies.md
percentile :: proc(sorted: []f64, p: f64) -> f64 {
	n := len(sorted)
	if n == 0 { return math.nan_f64() }
	t := f64(n + 1) * p
	k := int(math.floor(t))
	f := t - f64(k)
	if k < 1 { return sorted[0] }
	if k >= n { return sorted[n - 1] }
	return sorted[k - 1] + f * (sorted[k] - sorted[k - 1])
}

sorted_copy :: proc(xs: []f64) -> []f64 {
	out := slice.clone(xs, context.temp_allocator)
	slice.sort(out)
	return out
}
