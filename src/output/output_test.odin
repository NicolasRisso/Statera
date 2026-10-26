package output

import "core:testing"

@(test)
test_format_number :: proc(t: ^testing.T) {
	cases := [?]struct {
		x:        f64,
		decimals: int,
		want:     string,
	}{
		{0.39572593036212, 3, ".396"},
		{-0.65402693334864, 3, "-.654"},
		{6.25, 1, "6.3"},
		{18.75, 1, "18.8"},
		{75.265625, 4, "75.2656"},
		{20, NO_DECIMALS, "20"},
		{58, 2, "58.00"},
		{-0.0001, 2, ".00"},
		{2.675, 2, "2.68"},
		{1204.25, 2, "1204.25"},
	}
	for c in cases {
		got := format_number(c.x, c.decimals, context.temp_allocator)
		testing.expectf(t, got == c.want, "format_number(%v, %d) = %q, want %q", c.x, c.decimals, got, c.want)
	}
}
