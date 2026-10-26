// Output model: pivot tables as flat cells addressed by row/column label paths, plus text items.
// The same shape feeds the UI, the golden comparer (OMS XML is flattened the same way) and the API.
package output

import "core:fmt"
import "core:math"
import "core:strings"

NO_DECIMALS :: -1

Cell :: struct {
	row:       []string, // category labels from outermost to innermost
	col:       []string,
	layer:     []string,
	text:      string,
	number:    f64,
	has_value: bool,
	decimals:  int, // NO_DECIMALS for integers/counts
	footnotes: []string,
}

Table :: struct {
	command: string, // OMS command name, e.g. "Descriptives"
	subtype: string, // OMS subType, e.g. "Descriptive Statistics"
	title:    string,
	captions:    []string, // table-level notes, e.g. the split group under SPLIT FILE SEPARATE
	label_notes: [dynamic]Label_Note,
	cells:       [dynamic]Cell,
}

// A footnote attached to a row/column label rather than a cell.
Label_Note :: struct {
	label: string,
	text:  string,
}

Text_Kind :: enum u8 {
	Heading,
	Note,
	Warning,
	Error,
}

Text :: struct {
	kind:    Text_Kind,
	command: string,
	text:    string,
}

Item :: union {
	Table,
	Text,
}

// All strings handed to these procs are cloned with context.allocator.
add_number :: proc(t: ^Table, row, col: []string, x: f64, decimals: int, footnotes: []string = nil, layer: []string = nil, percent := false) {
	text := format_number(x, decimals)
	if percent { text = strings.concatenate({text, "%"}) }
	append(&t.cells, Cell {
		row       = clone_path(row),
		col       = clone_path(col),
		layer     = clone_path(layer),
		text      = text,
		number    = x,
		has_value = true,
		decimals  = decimals,
		footnotes = clone_path(footnotes),
	})
}

add_label_note :: proc(t: ^Table, label, text: string) {
	append(&t.label_notes, Label_Note{strings.clone(label), strings.clone(text)})
}

add_text :: proc(t: ^Table, row, col: []string, text: string) {
	append(&t.cells, Cell{row = clone_path(row), col = clone_path(col), text = strings.clone(text), decimals = NO_DECIMALS})
}

@(private)
clone_path :: proc(p: []string) -> []string {
	if len(p) == 0 { return nil }
	out := make([]string, len(p))
	for s, i in p { out[i] = strings.clone(s) }
	return out
}

// SPSS display rules: round half away from zero, drop the leading zero of |x| < 1.
// Spec: docs/specs/output/number-display.md
format_number :: proc(x: f64, decimals: int, allocator := context.allocator) -> string {
	if math.is_nan(x) || math.is_inf(x) { return strings.clone(".", allocator) }
	d := max(decimals, 0)
	r := round_half_away(x, d)
	s := fmt.aprintf("%.*f", d, r, allocator = context.temp_allocator)
	if strings.has_prefix(s, "0.") {
		s = s[1:]
	} else if strings.has_prefix(s, "-0.") {
		s = strings.concatenate({"-", s[2:]}, context.temp_allocator)
	}
	if s == "-0" || (strings.has_prefix(s, "-.") && strings.trim_right(s[2:], "0") == "") {
		s = s[1:] // no negative zero
	}
	return strings.clone(s, allocator)
}

round_half_away :: proc(x: f64, decimals: int) -> f64 {
	scale := math.pow(10, f64(decimals))
	// The tiny relative nudge keeps values like 2.675 (stored as 2.67499...) rounding the way they print.
	y := abs(x) * scale
	y = math.floor(y + 0.5 + y * 1e-13)
	return math.copy_sign(y / scale, x)
}
