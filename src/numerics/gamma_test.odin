package numerics

import "core:math"
import "core:testing"

@(private = "file")
near :: proc(t: ^testing.T, got, want, rel: f64, what: string) {
	testing.expectf(t, abs(got - want) <= rel * abs(want), "%s: got %.17g, want %.17g", what, got, want)
}

@(test)
test_log_gamma :: proc(t: ^testing.T) {
	testing.expectf(t, abs(log_gamma(1)) < 1e-14, "lgamma(1) = %v, want ~0", log_gamma(1))
	near(t, log_gamma(5), math.ln(f64(24)), 1e-14, "lgamma(5)")
	near(t, log_gamma(0.5), 0.5 * math.ln(math.PI), 1e-14, "lgamma(0.5)")
	near(t, log_gamma(100), 359.13420536957539878, 1e-14, "lgamma(100)")
}

@(test)
test_chisq_sf :: proc(t: ^testing.T) {
	near(t, chisq_sf(3.841458820694124, 1), 0.05, 1e-12, "chisq 95% df=1")
	near(t, chisq_sf(18.307038053275146, 10), 0.05, 1e-12, "chisq 95% df=10")
	near(t, chisq_sf(1, 2), math.exp(-0.5), 1e-14, "chisq df=2 closed form")
}

@(test)
test_fisher_exact :: proc(t: ^testing.T) {
	// Lady tasting tea: [[3,1],[1,3]] → two-sided 0.4857142857, one-sided 0.2428571429.
	two, one := fisher_exact(3, 1, 1, 3)
	near(t, two, 0.48571428571428571, 1e-12, "fisher two-sided")
	near(t, one, 0.24285714285714286, 1e-12, "fisher one-sided")
}
