package numerics

import "core:testing"

@(private = "file")
close :: proc(t: ^testing.T, got, want, rel: f64, what: string) {
	testing.expectf(t, abs(got - want) <= rel * abs(want), "%s: got %.17g, want %.17g", what, got, want)
}

@(test)
test_t_distribution :: proc(t: ^testing.T) {
	// Reference values from SPSS output (tests/golden/ttest_basic) and standard tables.
	close(t, t_sig2(1.9634147778727, 15), 0.068413021208744, 1e-11, "one-sample sig")
	close(t, t_sig2(0.80006140584339, 13.776978138589), 0.43725402737002, 1e-11, "welch sig")
	// t.975(6) recovered from SPSS's ONEWAY CI (upper − mean) / SE in tests/golden/oneway_basic.
	close(t, t_quantile(0.975, 6), (77.962255890011 - 70.607142857143) / 3.0058757651717, 1e-11, "t.975(6)")
	close(t, t_quantile(0.975, 10), 2.228138851986274, 1e-13, "t.975(10)")
	close(t, t_quantile(0.975, 1), 12.706204736174698, 1e-12, "t.975(1)")
}

@(test)
test_f_distribution :: proc(t: ^testing.T) {
	close(t, f_sf(1.2499350529213, 2, 13), 0.31878612358325, 1e-11, "anova sig")
	close(t, f_sf(1.424356225703, 2, 6.2935963738134), 0.30883367143415, 1e-11, "welch sig")
}
