// The case stream a procedure sees. Spec: docs/specs/engine/procedure-context.md
package procs

import "core:slice"
import "core:strings"

import "../io/sav"
import "../output"
import "../transform"

Split_Mode :: enum u8 {
	Off,
	Layered,
	Separate,
}

// One split group: case rows that passed FILTER and have a usable weight.
Group :: struct {
	rows:    []int,
	weights: []f64,    // parallel to rows; 1 when unweighted
	labels:  []string, // split values, outermost first; empty without SPLIT FILE
	caption: string,   // e.g. "Sex = Male" (SEPARATE mode)
}

Context :: struct {
	file:   ^sav.File,
	groups: []Group,
	mode:   Split_Mode,
}

// Valid (non-missing) values of `v` in group `g`, with their weights.
valid_values :: proc(ctx: ^Context, g: ^Group, v: ^sav.Variable) -> (xs, ws: []f64) {
	x := make([dynamic]f64, 0, len(g.rows), context.temp_allocator)
	w := make([dynamic]f64, 0, len(g.rows), context.temp_allocator)
	for row, i in g.rows {
		value := v.numbers[row]
		if transform.is_missing(v, value, ctx.file.sysmis) { continue }
		append(&x, value)
		append(&w, g.weights[i])
	}
	return x[:], w[:]
}

total_weight :: proc(g: ^Group) -> f64 {
	sum := 0.0
	for w in g.weights { sum += w }
	return sum
}

// Value label if one exists, otherwise the value in the variable's print format.
value_text :: proc(v: ^sav.Variable, x: f64) -> string {
	for l in v.value_labels {
		if l.value == x { return l.label }
	}
	return output.format_number(x, int(v.print.decimals), context.temp_allocator)
}

var_title :: proc(v: ^sav.Variable) -> string {
	return v.label if v.label != "" else v.name
}

// Builds a label path from a prefix plus trailing parts, in temp memory.
path :: proc(prefix: []string, parts: ..string) -> []string {
	out := make([]string, len(prefix) + len(parts), context.temp_allocator)
	copy(out, prefix)
	copy(out[len(prefix):], parts)
	return out
}

Weighted :: struct {
	x, w: f64,
}

// Value/weight pairs sorted by value, in temp memory.
sorted_pairs :: proc(xs, ws: []f64) -> []Weighted {
	ps := make([]Weighted, len(xs), context.temp_allocator)
	for &p, i in ps { p = {xs[i], ws[i]} }
	slice.sort_by(ps, proc(a, b: Weighted) -> bool { return a.x < b.x })
	return ps
}

// Distinct values with summed weights, ascending.
count_values :: proc(xs, ws: []f64) -> []Weighted {
	out := make([dynamic]Weighted, context.temp_allocator)
	for p in sorted_pairs(xs, ws) {
		if len(out) > 0 && out[len(out) - 1].x == p.x {
			out[len(out) - 1].w += p.w
		} else {
			append(&out, p)
		}
	}
	return out[:]
}

// Split-group caption, e.g. "Sex = Male" (several split variables joined with ", ").
caption :: proc(parts: []string) -> string {
	return strings.join(parts, ", ", context.temp_allocator)
}
