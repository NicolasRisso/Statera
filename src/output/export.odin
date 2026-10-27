// Exporters for the output document: HTML, CSV, XLSX, and TSV (clipboard).
package output

import "core:fmt"
import "core:hash"
import "core:strings"

// The table as a text grid: header rows first, row-label columns first.
// Repeated outer labels are blanked so groups read like merged cells.
grid :: proc(l: ^Layout, allocator := context.allocator) -> [][]string {
	context.allocator = allocator
	width := l.row_depth + len(l.cols)
	out := make([dynamic][]string)
	for level in 0 ..< l.col_depth {
		line := make([]string, width)
		for c, ci in l.cols {
			if level >= len(c) { continue }
			if ci > 0 && same_band(l.cols[ci - 1], c, level) { continue }
			line[l.row_depth + ci] = strings.concatenate({c[level], l.col_marks[c[level]]})
		}
		append(&out, line)
	}
	for r, ri in l.rows {
		line := make([]string, width)
		for level in 0 ..< min(len(r), l.row_depth) {
			if ri > 0 && same_band(l.rows[ri - 1], r, level) { continue }
			line[level] = strings.concatenate({r[level], l.row_marks[r[level]]})
		}
		for _, ci in l.cols { line[l.row_depth + ci] = l.texts[ri * len(l.cols) + ci] }
		append(&out, line)
	}
	return out[:]
}

to_tsv :: proc(t: ^Table, allocator := context.allocator) -> string {
	l := layout(t, context.temp_allocator)
	b := strings.builder_make(allocator)
	for line in grid(&l, context.temp_allocator) {
		for cell, i in line {
			if i > 0 { strings.write_byte(&b, '\t') }
			strings.write_string(&b, cell)
		}
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

@(private)
csv_field :: proc(b: ^strings.Builder, s: string) {
	if strings.contains_any(s, ",\"\n") {
		strings.write_byte(b, '"')
		for r in s {
			if r == '"' { strings.write_byte(b, '"') }
			strings.write_rune(b, r)
		}
		strings.write_byte(b, '"')
	} else {
		strings.write_string(b, s)
	}
}

to_csv :: proc(items: []Item, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	line :: proc(b: ^strings.Builder, fields: []string) {
		for f, i in fields {
			if i > 0 { strings.write_byte(b, ',') }
			csv_field(b, f)
		}
		strings.write_byte(b, '\n')
	}
	for item in items {
		switch v in item {
		case Text:
			if v.kind == .Note { continue }
			line(&b, {v.text})
			strings.write_byte(&b, '\n')
		case Table:
			table := v
			l := layout(&table, context.temp_allocator)
			line(&b, {l.title})
			for c in l.captions { line(&b, {c}) }
			if len(l.layer) > 0 { line(&b, {strings.join(l.layer, " / ", context.temp_allocator)}) }
			for row in grid(&l, context.temp_allocator) { line(&b, row) }
			for n, k in l.notes { line(&b, {fmt.tprintf("%c. %s", 'a' + rune(k), n)}) }
			strings.write_byte(&b, '\n')
		}
	}
	return strings.to_string(b)
}

@(private)
html_escape :: proc(b: ^strings.Builder, s: string) {
	for r in s {
		switch r {
		case '<': strings.write_string(b, "&lt;")
		case '>': strings.write_string(b, "&gt;")
		case '&': strings.write_string(b, "&amp;")
		case '"': strings.write_string(b, "&quot;")
		case:     strings.write_rune(b, r)
		}
	}
}

HTML_STYLE :: `body{font-family:Inter,Segoe UI,system-ui,sans-serif;color:#1d2130;margin:32px;max-width:1100px}
h1{font-size:20px;color:#4f5bd5}h2{font-size:15px;margin:28px 0 6px}
table{border-collapse:collapse;font-size:13px;margin:4px 0}
td{padding:4px 10px;border-bottom:1px solid #e0e3eb;white-space:pre}
tr.head td{background:#f0f2f7;color:#6b7185;font-weight:600}
td.num{text-align:right;font-variant-numeric:tabular-nums}td.lab{font-weight:500}
.cap,.note{color:#6b7185;font-size:12px;margin:2px 0}
.warn{border-left:3px solid #b86e12;padding:6px 10px;background:#fbf5ec}
.err{border-left:3px solid #d63b4e;padding:6px 10px;background:#fcf0f2}`

to_html :: proc(items: []Item, title: string, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "<!doctype html>\n<html><head><meta charset=\"utf-8\"><title>")
	html_escape(&b, title)
	fmt.sbprintf(&b, "</title><style>%s</style></head><body><h1>", HTML_STYLE)
	html_escape(&b, title)
	strings.write_string(&b, "</h1>\n")
	for item in items {
		switch v in item {
		case Text:
			class := "note"
			switch v.kind {
			case .Heading: strings.write_string(&b, "<h2>"); html_escape(&b, v.text); strings.write_string(&b, "</h2>\n"); continue
			case .Warning: class = "warn"
			case .Error:   class = "err"
			case .Note:
			}
			fmt.sbprintf(&b, "<p class=\"%s\">", class)
			html_escape(&b, v.text)
			strings.write_string(&b, "</p>\n")
		case Table:
			table := v
			l := layout(&table, context.temp_allocator)
			strings.write_string(&b, "<h2>")
			html_escape(&b, l.title)
			strings.write_string(&b, "</h2>\n")
			for c in l.captions { strings.write_string(&b, "<p class=\"cap\">"); html_escape(&b, c); strings.write_string(&b, "</p>\n") }
			if len(l.layer) > 0 {
				strings.write_string(&b, "<p class=\"cap\">")
				html_escape(&b, strings.join(l.layer, " / ", context.temp_allocator))
				strings.write_string(&b, "</p>\n")
			}
			strings.write_string(&b, "<table>\n")
			for line, li in grid(&l, context.temp_allocator) {
				head := li < l.col_depth
				strings.write_string(&b, "<tr class=\"head\">" if head else "<tr>")
				for cell, ci in line {
					class := "lab" if ci < l.row_depth else "num"
					fmt.sbprintf(&b, "<td class=\"%s\">", class)
					html_escape(&b, cell)
					strings.write_string(&b, "</td>")
				}
				strings.write_string(&b, "</tr>\n")
			}
			strings.write_string(&b, "</table>\n")
			for n, k in l.notes {
				fmt.sbprintf(&b, "<p class=\"note\">%c. ", 'a' + rune(k))
				html_escape(&b, n)
				strings.write_string(&b, "</p>\n")
			}
		}
	}
	strings.write_string(&b, "</body></html>\n")
	return strings.to_string(b)
}

// Minimal Office Open XML workbook: one sheet with every table stacked vertically.
// Numeric cells are written as numbers rounded to their displayed precision.
to_xlsx :: proc(items: []Item, allocator := context.allocator) -> []byte {
	sheet := strings.builder_make(context.temp_allocator)
	strings.write_string(&sheet, `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` + "\n")
	strings.write_string(&sheet, `<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>`)
	row := 0
	put_row :: proc(sheet: ^strings.Builder, row: ^int, cells: []string, numbers: []^Cell = nil) {
		row^ += 1
		fmt.sbprintf(sheet, `<row r="%d">`, row^)
		for text, i in cells {
			if text == "" { continue }
			ref := fmt.tprintf("%s%d", column_name(i), row^)
			if numbers != nil && numbers[i] != nil && numbers[i].has_value && len(numbers[i].footnotes) == 0 {
				c := numbers[i]
				fmt.sbprintf(sheet, `<c r="%s"><v>%.17g</v></c>`, ref, round_half_away(c.number, max(c.decimals, 0)))
				continue
			}
			fmt.sbprintf(sheet, `<c r="%s" t="inlineStr"><is><t xml:space="preserve">`, ref)
			html_escape(sheet, text)
			strings.write_string(sheet, `</t></is></c>`)
		}
		strings.write_string(sheet, `</row>`)
	}
	for item in items {
		switch v in item {
		case Text:
			if v.kind != .Note { put_row(&sheet, &row, {v.text}) }
		case Table:
			table := v
			l := layout(&table, context.temp_allocator)
			put_row(&sheet, &row, {l.title})
			for c in l.captions { put_row(&sheet, &row, {c}) }
			lines := grid(&l, context.temp_allocator)
			for line, li in lines {
				if li < l.col_depth {
					put_row(&sheet, &row, line)
					continue
				}
				nums := make([]^Cell, len(line), context.temp_allocator)
				r := li - l.col_depth
				for _, ci in l.cols { nums[l.row_depth + ci] = l.cells[r * len(l.cols) + ci] }
				put_row(&sheet, &row, line, nums)
			}
			for n, k in l.notes { put_row(&sheet, &row, {fmt.tprintf("%c. %s", 'a' + rune(k), n)}) }
			row += 1
		}
	}
	strings.write_string(&sheet, `</sheetData></worksheet>`)

	files := [?]Zip_Entry {
		{"[Content_Types].xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` + "\n" +
			`<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">` +
			`<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>` +
			`<Default Extension="xml" ContentType="application/xml"/>` +
			`<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>` +
			`<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>` +
			`</Types>`},
		{"_rels/.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` + "\n" +
			`<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
			`<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>` +
			`</Relationships>`},
		{"xl/workbook.xml", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` + "\n" +
			`<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">` +
			`<sheets><sheet name="Output" sheetId="1" r:id="rId1"/></sheets></workbook>`},
		{"xl/_rels/workbook.xml.rels", `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>` + "\n" +
			`<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">` +
			`<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>` +
			`</Relationships>`},
		{"xl/worksheets/sheet1.xml", strings.to_string(sheet)},
	}
	return zip_store(files[:], allocator)
}

@(private)
column_name :: proc(i: int) -> string {
	n := i + 1
	buf: [8]u8
	k := len(buf)
	for n > 0 {
		k -= 1
		buf[k] = u8('A' + (n - 1) % 26)
		n = (n - 1) / 26
	}
	return strings.clone(string(buf[k:]), context.temp_allocator)
}

Zip_Entry :: struct {
	name, data: string,
}

// Writes an uncompressed ("stored") zip archive.
zip_store :: proc(entries: []Zip_Entry, allocator := context.allocator) -> []byte {
	out := make([dynamic]byte, allocator)
	u16le :: proc(out: ^[dynamic]byte, v: int) { append(out, u8(v), u8(v >> 8)) }
	u32le :: proc(out: ^[dynamic]byte, v: u32) { append(out, u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24)) }
	offsets := make([]int, len(entries), context.temp_allocator)
	crcs := make([]u32, len(entries), context.temp_allocator)
	for e, i in entries {
		offsets[i] = len(out)
		crcs[i] = hash.crc32(transmute([]byte)e.data)
		u32le(&out, 0x04034b50)
		u16le(&out, 20) // version needed
		u16le(&out, 0)  // flags
		u16le(&out, 0)  // method: stored
		u16le(&out, 0)  // time
		u16le(&out, 0x21) // date: 1980-01-01
		u32le(&out, crcs[i])
		u32le(&out, u32(len(e.data)))
		u32le(&out, u32(len(e.data)))
		u16le(&out, len(e.name))
		u16le(&out, 0)
		append(&out, ..transmute([]byte)e.name)
		append(&out, ..transmute([]byte)e.data)
	}
	central := len(out)
	for e, i in entries {
		u32le(&out, 0x02014b50)
		u16le(&out, 20)
		u16le(&out, 20)
		u16le(&out, 0)
		u16le(&out, 0)
		u16le(&out, 0)
		u16le(&out, 0x21)
		u32le(&out, crcs[i])
		u32le(&out, u32(len(e.data)))
		u32le(&out, u32(len(e.data)))
		u16le(&out, len(e.name))
		u16le(&out, 0) // extra
		u16le(&out, 0) // comment
		u16le(&out, 0) // disk
		u16le(&out, 0) // internal attrs
		u32le(&out, 0) // external attrs
		u32le(&out, u32(offsets[i]))
		append(&out, ..transmute([]byte)e.name)
	}
	size := len(out) - central
	u32le(&out, 0x06054b50)
	u16le(&out, 0)
	u16le(&out, 0)
	u16le(&out, len(entries))
	u16le(&out, len(entries))
	u32le(&out, u32(size))
	u32le(&out, u32(central))
	u16le(&out, 0)
	return out[:]
}
