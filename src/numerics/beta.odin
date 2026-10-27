package numerics

import "core:math"

// Regularized incomplete beta I_x(a, b) (continued fraction, modified Lentz).
beta_inc :: proc(x, a, b: f64) -> f64 {
	if x <= 0 { return 0 }
	if x >= 1 { return 1 }
	front := math.exp(log_gamma(a + b) - log_gamma(a) - log_gamma(b) + a * math.ln(x) + b * math.ln(1 - x))
	// The fraction converges fastest for x < (a+1)/(a+b+2); use the symmetry otherwise.
	if x < (a + 1) / (a + b + 2) {
		return front * beta_fraction(x, a, b) / a
	}
	return 1 - front * beta_fraction(1 - x, b, a) / b
}

@(private)
beta_fraction :: proc(x, a, b: f64) -> f64 {
	TINY :: 1e-300
	qab, qap, qam := a + b, a + 1, a - 1
	c := 1.0
	d := 1 - qab * x / qap
	if abs(d) < TINY { d = TINY }
	d = 1 / d
	h := d
	for m in 1 ..< 10_000 {
		fm := f64(m)
		m2 := 2 * fm
		aa := fm * (b - fm) * x / ((qam + m2) * (a + m2))
		d = 1 + aa * d
		if abs(d) < TINY { d = TINY }
		c = 1 + aa / c
		if abs(c) < TINY { c = TINY }
		d = 1 / d
		h *= d * c
		aa = -(a + fm) * (qab + fm) * x / ((a + m2) * (qap + m2))
		d = 1 + aa * d
		if abs(d) < TINY { d = TINY }
		c = 1 + aa / c
		if abs(c) < TINY { c = TINY }
		d = 1 / d
		delta := d * c
		h *= delta
		if abs(delta - 1) < EPS { break }
	}
	return h
}

// Two-sided p-value of Student's t: P(|T| ≥ |t|).
t_sig2 :: proc(t, df: f64) -> f64 {
	return beta_inc(df / (df + t * t), df / 2, 0.5)
}

// Lower-tail probability P(T ≤ t).
t_cdf :: proc(t, df: f64) -> f64 {
	tail := 0.5 * t_sig2(t, df)
	return 1 - tail if t > 0 else tail
}

// Quantile of Student's t: the t with P(T ≤ t) = p.
t_quantile :: proc(p, df: f64) -> f64 {
	if p == 0.5 { return 0 }
	if p < 0.5 { return -t_quantile(1 - p, df) }
	// Bracket, bisect, then polish with Newton steps on the density.
	lo, hi := 0.0, 1.0
	for t_cdf(hi, df) < p { hi *= 2 }
	for _ in 0 ..< 200 {
		mid := 0.5 * (lo + hi)
		if t_cdf(mid, df) < p { lo = mid } else { hi = mid }
		if hi - lo <= 1e-15 * hi { break }
	}
	t := 0.5 * (lo + hi)
	for _ in 0 ..< 3 {
		f := t_cdf(t, df) - p
		t -= f / t_pdf(t, df)
	}
	return t
}

t_pdf :: proc(t, df: f64) -> f64 {
	return math.exp(log_gamma((df + 1) / 2) - log_gamma(df / 2) - 0.5 * math.ln(df * math.PI) -
		(df + 1) / 2 * math.ln(1 + t * t / df))
}

// Upper-tail probability of the F distribution: P(F ≥ f).
f_sf :: proc(f, df1, df2: f64) -> f64 {
	if f <= 0 { return 1 }
	return beta_inc(df2 / (df2 + df1 * f), df2 / 2, df1 / 2)
}
