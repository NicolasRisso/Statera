// Special functions and distributions (standard textbook algorithms, implemented from scratch).
package numerics

import "core:math"

// ln Γ(x) for x > 0 (Lanczos approximation, g = 7, n = 9; ~15 significant digits).
log_gamma :: proc(x: f64) -> f64 {
	if x < 0.5 {
		// Reflection: Γ(x)Γ(1−x) = π / sin(πx)
		return math.ln(math.PI / abs(math.sin(math.PI * x))) - log_gamma(1 - x)
	}
	@(static, rodata) coef := [9]f64 {
		0.99999999999980993, 676.5203681218851, -1259.1392167224028,
		771.32342877765313, -176.61502916214059, 12.507343278686905,
		-0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7,
	}
	z := x - 1
	a := coef[0]
	t := z + 7.5
	for i in 1 ..< 9 { a += coef[i] / (z + f64(i)) }
	return 0.5 * math.ln(2 * math.PI) + (z + 0.5) * math.ln(t) - t + math.ln(a)
}

// ln(n!) for n ≥ 0.
log_factorial :: proc(n: int) -> f64 {
	return log_gamma(f64(n) + 1)
}

// Regularized upper incomplete gamma Q(a, x) = Γ(a, x) / Γ(a).
gamma_q :: proc(a, x: f64) -> f64 {
	if x <= 0 { return 1 }
	if x < a + 1 { return 1 - gamma_p_series(a, x) }
	return gamma_q_fraction(a, x)
}

@(private)
EPS :: 1e-16

@(private)
gamma_p_series :: proc(a, x: f64) -> f64 {
	sum := 1 / a
	term := sum
	for n in 1 ..< 10_000 {
		term *= x / (a + f64(n))
		sum += term
		if abs(term) < abs(sum) * EPS { break }
	}
	return sum * math.exp(-x + a * math.ln(x) - log_gamma(a))
}

// Continued fraction (modified Lentz).
@(private)
gamma_q_fraction :: proc(a, x: f64) -> f64 {
	TINY :: 1e-300
	b := x + 1 - a
	c := 1 / TINY
	d := 1 / b
	h := d
	for i in 1 ..< 10_000 {
		an := -f64(i) * (f64(i) - a)
		b += 2
		d = an * d + b
		if abs(d) < TINY { d = TINY }
		c = b + an / c
		if abs(c) < TINY { c = TINY }
		d = 1 / d
		delta := d * c
		h *= delta
		if abs(delta - 1) < EPS { break }
	}
	return math.exp(-x + a * math.ln(x) - log_gamma(a)) * h
}

// Upper-tail probability of the chi-square distribution: P(X² ≥ x).
chisq_sf :: proc(x, df: f64) -> f64 {
	if x <= 0 { return 1 }
	return gamma_q(df / 2, x / 2)
}

// Hypergeometric probability of a 2×2 table with first cell `a` and fixed margins
// (row1 = r1, col1 = c1, total = n).
hypergeometric :: proc(a, r1, c1, n: int) -> f64 {
	b, c := r1 - a, c1 - a
	d := n - r1 - c1 + a
	if a < 0 || b < 0 || c < 0 || d < 0 { return 0 }
	r2, c2 := n - r1, n - c1
	return math.exp(log_factorial(r1) + log_factorial(r2) + log_factorial(c1) + log_factorial(c2) -
		log_factorial(n) - log_factorial(a) - log_factorial(b) - log_factorial(c) - log_factorial(d))
}

// Fisher's exact test for [[a, b], [c, d]]: two-sided (tables no more likely than observed)
// and one-sided (the tail in the observed direction).
fisher_exact :: proc(a, b, c, d: int) -> (two_sided, one_sided: f64) {
	r1, c1, n := a + b, a + c, a + b + c + d
	lo := max(0, r1 + c1 - n)
	hi := min(r1, c1)
	p_obs := hypergeometric(a, r1, c1, n)
	expected := f64(r1) * f64(c1) / f64(n)
	lower, upper := 0.0, 0.0
	for k in lo ..= hi {
		p := hypergeometric(k, r1, c1, n)
		if p <= p_obs * (1 + 1e-7) { two_sided += p }
		if k <= a { lower += p }
		if k >= a { upper += p }
	}
	one_sided = lower if f64(a) < expected else upper
	return min(two_sided, 1), min(one_sided, 1)
}
