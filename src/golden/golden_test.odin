// Golden tests: run tests/golden/<case>/case.sps through the engine and compare with SPSS's OMS output.
package golden

import "core:encoding/xml"
import "core:log"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:testing"

import "../engine"
import "../io/sav"
import "../output"

ROOT :: #directory + "/../.."

// Cases the engine supports so far. The rest need commands that aren't implemented yet.
@(test) test_freq_basic :: proc(t: ^testing.T) { run_case(t, "freq_basic") }
@(test) test_freq_stats :: proc(t: ^testing.T) { run_case(t, "freq_stats") }
@(test) test_desc_basic :: proc(t: ^testing.T) { run_case(t, "desc_basic") }
@(test) test_compute_basic :: proc(t: ^testing.T) { run_case(t, "compute_basic", compare_saved = "computed.sav") }
@(test) test_ctx_weight :: proc(t: ^testing.T) { run_case(t, "ctx_weight") }
@(test) test_ctx_filter :: proc(t: ^testing.T) { run_case(t, "ctx_filter") }
@(test) test_ctx_split :: proc(t: ^testing.T) { run_case(t, "ctx_split") }
@(test) test_xtab_basic :: proc(t: ^testing.T) { run_case(t, "xtab_basic") }
@(test) test_xtab_stats :: proc(t: ^testing.T) { run_case(t, "xtab_stats") }
@(test) test_means_basic :: proc(t: ^testing.T) { run_case(t, "means_basic") }
@(test) test_ttest_basic :: proc(t: ^testing.T) { run_case(t, "ttest_basic") }
@(test) test_oneway_basic :: proc(t: ^testing.T) { run_case(t, "oneway_basic") }
@(test) test_corr_basic :: proc(t: ^testing.T) { run_case(t, "corr_basic") }
@(test) test_reg_basic :: proc(t: ^testing.T) { run_case(t, "reg_basic") }

Flat_Cell :: struct {
	row, col, layer: string, // paths joined with " / "
	text:            string,
	number:          f64,
	has_value:       bool,
	footnotes:       string,
}

Flat_Table :: struct {
	subtype, title: string,
	captions:       string,
	label_notes:    [dynamic]string, // "label: note" for footnotes on row/column labels
	cells:          [dynamic]Flat_Cell,
}

run_case :: proc(t: ^testing.T, name: string, compare_saved := "") {
	root, _ := filepath.abs(ROOT, context.temp_allocator)
	root, _ = strings.replace_all(root, "\\", "/", context.temp_allocator)
	case_dir := strings.concatenate({root, "/tests/golden/", name}, context.temp_allocator)
	out_dir := strings.concatenate({root, "/build/golden/", name}, context.temp_allocator)
	_ = os.make_directory_all(out_dir)

	src, err := os.read_entire_file(strings.concatenate({case_dir, "/case.sps"}, context.temp_allocator), context.temp_allocator)
	if !testing.expect(t, err == nil, "cannot read case.sps") { return }
	syntax, _ := strings.replace_all(string(src), "@ROOT@", root, context.temp_allocator)
	syntax, _ = strings.replace_all(syntax, "@OUT@", out_dir, context.temp_allocator)

	s: engine.Session
	defer engine.destroy(&s)
	failures := engine.run(&s, syntax)
	for item in s.items {
		if text, ok := item.(output.Text); ok && (text.kind == .Error || text.kind == .Warning) {
			log.infof("[%v] %s", text.kind, text.text)
		}
	}
	testing.expect_value(t, failures, 0)

	ours := flatten_ours(s.items[:])
	theirs, ok := flatten_oms(strings.concatenate({case_dir, "/expected/oms.xml"}, context.temp_allocator))
	if !testing.expect(t, ok, "cannot parse expected/oms.xml") { return }
	compare_tables(t, ours[:], theirs[:])

	if compare_saved != "" {
		compare_datasets(t,
			strings.concatenate({out_dir, "/", compare_saved}, context.temp_allocator),
			strings.concatenate({case_dir, "/expected/", compare_saved}, context.temp_allocator))
	}
}

compare_tables :: proc(t: ^testing.T, ours, theirs: []Flat_Table) {
	testing.expectf(t, len(ours) == len(theirs), "table count: ours %d, SPSS %d", len(ours), len(theirs))
	for i in 0 ..< min(len(ours), len(theirs)) {
		a, b := ours[i], theirs[i]
		testing.expectf(t, a.subtype == b.subtype && a.title == b.title && a.captions == b.captions,
			"table %d: ours %q/%q [%s], SPSS %q/%q [%s]", i, a.subtype, a.title, a.captions, b.subtype, b.title, b.captions)
		an := strings.join(a.label_notes[:], "; ", context.temp_allocator)
		bn := strings.join(b.label_notes[:], "; ", context.temp_allocator)
		testing.expectf(t, an == bn, "table %d (%s) label notes: ours %q, SPSS %q", i, b.title, an, bn)
		mismatches := 0
		for j in 0 ..< max(len(a.cells), len(b.cells)) {
			if j >= len(a.cells) || j >= len(b.cells) {
				testing.expectf(t, false, "table %d (%s): cell count ours %d, SPSS %d", i, b.title, len(a.cells), len(b.cells))
				break
			}
			x, y := a.cells[j], b.cells[j]
			same := x.row == y.row && x.col == y.col && x.layer == y.layer && x.text == y.text && x.footnotes == y.footnotes &&
				x.has_value == y.has_value && (!y.has_value || close_enough(x.number, y.number))
			if !same {
				mismatches += 1
				if mismatches <= 5 {
					testing.expectf(t, false, "table %d (%s) cell %d:\n  ours: [%s | %s | %s] %q %v %q\n  SPSS: [%s | %s | %s] %q %v %q",
						i, b.title, j, x.layer, x.row, x.col, x.text, x.number, x.footnotes, y.layer, y.row, y.col, y.text, y.number, y.footnotes)
				}
			}
		}
		if mismatches > 5 {
			testing.expectf(t, false, "table %d (%s): %d mismatched cells in total", i, b.title, mismatches)
		}
	}
}

// core:encoding/xml collapses whitespace inside attribute values, so labels with SPSS's
// padding (e.g. "Test Value = 70" + 38 spaces, "Exam score  * Study group") are compared
// whitespace-normalized on both sides. Our output still emits the exact padding.
normalize_ws :: proc(s: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	space := false
	for r in strings.trim_space(s) {
		if r == ' ' {
			space = true
			continue
		}
		if space { strings.write_byte(&b, ' ') }
		space = false
		strings.write_rune(&b, r)
	}
	return strings.to_string(b)
}

join_path :: proc(p: []string) -> string {
	parts := make([]string, len(p), context.temp_allocator)
	for s, i in p { parts[i] = normalize_ws(s) }
	return strings.join(parts, " / ", context.temp_allocator)
}

close_enough :: proc(a, b: f64) -> bool {
	// OMS stores 14 significant digits.
	return abs(a - b) <= 1e-11 * max(abs(a), abs(b), 1e-300) || abs(a - b) < 1e-12
}

flatten_ours :: proc(items: []output.Item) -> [dynamic]Flat_Table {
	out := make([dynamic]Flat_Table, context.temp_allocator)
	for item in items {
		table, ok := item.(output.Table)
		if !ok { continue }
		ft := Flat_Table {
			subtype  = table.subtype,
			title    = table.title,
			captions = strings.join(table.captions, "; ", context.temp_allocator),
		}
		ft.cells = make([dynamic]Flat_Cell, context.temp_allocator)
		ft.label_notes = make([dynamic]string, context.temp_allocator)
		for n in table.label_notes {
			append(&ft.label_notes, strings.concatenate({n.label, ": ", n.text}, context.temp_allocator))
		}
		for c in table.cells {
			append(&ft.cells, Flat_Cell {
				row       = join_path(c.row),
				col       = join_path(c.col),
				layer     = join_path(c.layer),
				text      = c.text,
				number    = c.number,
				has_value = c.has_value,
				footnotes = strings.join(c.footnotes, "; ", context.temp_allocator),
			})
		}
		append(&out, ft)
	}
	return out
}

// Flattens OMS XML pivot tables into cells with layer/row/column paths. Hidden groups are skipped.
flatten_oms :: proc(path: string) -> (tables: [dynamic]Flat_Table, ok: bool) {
	doc, err := xml.load_from_file(path, {flags = {.Ignore_Unsupported, .Decode_SGML_Entities}}, allocator = context.temp_allocator)
	if err != nil { return }
	tables = make([dynamic]Flat_Table, context.temp_allocator)
	walk_oms(doc, 0, &tables, nil, {}, {})
	return tables, true
}

@(private)
attr :: proc(e: ^xml.Element, key: string) -> string {
	for a in e.attribs {
		if a.key == key { return a.val }
	}
	return ""
}

@(private)
Path :: struct {
	row, col, layer: [dynamic]string,
}

@(private)
walk_oms :: proc(doc: ^xml.Document, id: xml.Element_ID, tables: ^[dynamic]Flat_Table, table: ^Flat_Table, path: Path, axis: string) {
	e := &doc.elements[id]
	path, axis, table := path, axis, table
	switch e.ident {
	case "pivotTable":
		captions := make([dynamic]string, context.temp_allocator)
		for v in e.value {
			child, is_elem := v.(xml.Element_ID)
			if is_elem && doc.elements[child].ident == "footnote" { collect_notes(doc, child, &captions) }
		}
		append(tables, Flat_Table {
			subtype  = attr(e, "subType"),
			title    = attr(e, "text"),
			captions = strings.join(captions[:], "; ", context.temp_allocator),
			label_notes = make([dynamic]string, context.temp_allocator),
			cells    = make([dynamic]Flat_Cell, context.temp_allocator),
		})
		table = &tables[len(tables) - 1]
		path = {}
	case "dimension":
		axis = attr(e, "axis")
	case "category", "group":
		if attr(e, "hide") != "true" {
			label := attr(e, "text")
			row := make([dynamic]string, context.temp_allocator)
			col := make([dynamic]string, context.temp_allocator)
			layer := make([dynamic]string, context.temp_allocator)
			append(&row, ..path.row[:])
			append(&col, ..path.col[:])
			append(&layer, ..path.layer[:])
			switch axis {
			case "row":   append(&row, label)
			case "layer": append(&layer, label)
			case:         append(&col, label)
			}
			path = {row, col, layer}
			if table != nil {
				for v in e.value {
					child, is_elem := v.(xml.Element_ID)
					if !is_elem || doc.elements[child].ident != "footnote" { continue }
					notes := make([dynamic]string, context.temp_allocator)
					collect_notes(doc, child, &notes)
					for n in notes {
						append(&table.label_notes, strings.concatenate({label, ": ", n}, context.temp_allocator))
					}
				}
			}
		}
	case "cell":
		if table == nil { return }
		number := attr(e, "number")
		value, has_value := strconv.parse_f64(number)
		notes := make([dynamic]string, context.temp_allocator)
		collect_notes(doc, id, &notes)
		append(&table.cells, Flat_Cell {
			row       = join_path(path.row[:]),
			col       = join_path(path.col[:]),
			layer     = join_path(path.layer[:]),
			text      = attr(e, "text"),
			number    = value,
			has_value = has_value && number != "",
			footnotes = strings.join(notes[:], "; ", context.temp_allocator),
		})
		return
	}
	for v in e.value {
		if child, is_elem := v.(xml.Element_ID); is_elem {
			walk_oms(doc, child, tables, table, path, axis)
		}
	}
}

@(private)
collect_notes :: proc(doc: ^xml.Document, id: xml.Element_ID, notes: ^[dynamic]string) {
	for v in doc.elements[id].value {
		child, ok := v.(xml.Element_ID)
		if !ok { continue }
		if doc.elements[child].ident == "note" { append(notes, attr(&doc.elements[child], "text")) }
		collect_notes(doc, child, notes)
	}
}

// Compares two .sav files' dictionaries and values (SYSMIS must match exactly).
compare_datasets :: proc(t: ^testing.T, ours_path, theirs_path: string) {
	ours, e1 := sav.read_file(ours_path, context.temp_allocator)
	theirs, e2 := sav.read_file(theirs_path, context.temp_allocator)
	if !testing.expect(t, e1 == nil && e2 == nil, "cannot read saved datasets") { return }
	testing.expect_value(t, ours.n_cases, theirs.n_cases)
	if !testing.expect_value(t, len(ours.variables), len(theirs.variables)) { return }
	for tv, i in theirs.variables {
		ov := ours.variables[i]
		testing.expectf(t, strings.equal_fold(ov.name, tv.name), "variable %d: ours %s, SPSS %s", i, ov.name, tv.name)
		testing.expectf(t, ov.print == tv.print, "%s format: ours %v, SPSS %v", tv.name, ov.print, tv.print)
		bad := 0
		for c in 0 ..< theirs.n_cases {
			a, b := ov.numbers[c], tv.numbers[c]
			if (a == sav.SYSMIS) != (b == sav.SYSMIS) || (b != sav.SYSMIS && !close_enough(a, b)) {
				bad += 1
				if bad <= 3 {
					testing.expectf(t, false, "%s case %d: ours %v, SPSS %v", tv.name, c + 1, fmt_value(a), fmt_value(b))
				}
			}
		}
	}
}

@(private)
fmt_value :: proc(x: f64) -> string {
	if x == sav.SYSMIS { return "SYSMIS" }
	if math.is_nan(x) { return "NaN" }
	return fmt.tprintf("%.17g", x)
}
