package output

import "core:strings"

// A table arranged as a grid: unique row/column paths in first-seen order.
// Shared by the UI renderer and the exporters.
Layout :: struct {
	title:     string,
	layer:     []string, // label of the (single) layer category, if any
	captions:  []string,
	rows:      [][]string,
	cols:      [][]string,
	row_depth: int,
	col_depth: int,
	cells:     []^Cell, // rows × cols, nil where empty
	texts:     []string, // display text per grid slot, footnote marks appended
	notes:     []string, // footnote texts; mark = 'a' + index
	row_marks: map[string]string, // label → marks for footnotes on row labels
	col_marks: map[string]string,
}

// Builds the layout with `allocator`; everything inside lives as long as it.
layout :: proc(t: ^Table, allocator := context.allocator) -> Layout {
	context.allocator = allocator
	l := Layout{title = t.title, captions = t.captions, row_depth = 1, col_depth = 1}
	row_index := make(map[string]int, allocator = context.temp_allocator)
	col_index := make(map[string]int, allocator = context.temp_allocator)
	rows := make([dynamic][]string)
	cols := make([dynamic][]string)
	key :: proc(p: []string) -> string { return strings.join(p, "\x1f", context.temp_allocator) }
	for c in t.cells {
		if key(c.row) not_in row_index {
			row_index[key(c.row)] = len(rows)
			append(&rows, c.row)
			l.row_depth = max(l.row_depth, len(c.row))
		}
		if key(c.col) not_in col_index {
			col_index[key(c.col)] = len(cols)
			append(&cols, c.col)
			l.col_depth = max(l.col_depth, len(c.col))
		}
	}
	if len(t.cells) > 0 { l.layer = t.cells[0].layer }
	l.rows, l.cols = rows[:], cols[:]
	l.cells = make([]^Cell, len(rows) * len(cols))
	l.texts = make([]string, len(rows) * len(cols))

	notes := make([dynamic]string)
	mark :: proc(notes: ^[dynamic]string, note: string) -> rune {
		for existing, k in notes {
			if existing == note { return 'a' + rune(k) }
		}
		append(notes, note)
		return 'a' + rune(len(notes) - 1)
	}
	for &c in t.cells {
		slot := row_index[key(c.row)] * len(cols) + col_index[key(c.col)]
		l.cells[slot] = &c
		b := strings.builder_make()
		strings.write_string(&b, c.text)
		for n in c.footnotes { strings.write_rune(&b, mark(&notes, n)) }
		l.texts[slot] = strings.to_string(b)
	}
	l.row_marks = make(map[string]string)
	l.col_marks = make(map[string]string)
	for n in t.label_notes {
		m := mark(&notes, n.text)
		is_col := false
		for c in cols {
			for part in c { is_col ||= part == n.label }
		}
		target := &l.col_marks if is_col else &l.row_marks
		// A missing key reads as "", so marks accumulate per label.
		target[n.label] = strings.concatenate({target[n.label], string_of_rune(m)})
	}
	l.notes = notes[:]
	return l
}

@(private)
string_of_rune :: proc(r: rune) -> string {
	b := strings.builder_make()
	strings.write_rune(&b, r)
	return strings.to_string(b)
}

// True when the header label at `level` repeats the previous path's (drawn as one merged band).
same_band :: proc(prev, cur: []string, level: int) -> bool {
	if prev == nil || len(prev) <= level || len(cur) <= level { return false }
	for i in 0 ..= level {
		if prev[i] != cur[i] { return false }
	}
	return true
}
