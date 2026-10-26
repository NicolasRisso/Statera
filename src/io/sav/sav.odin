// Reader for SPSS system files (.sav, .zsav). Format: docs/specs/io/sav-format.md
package sav

import "core:bytes"
import "core:compress/zlib"
import "core:encoding/endian"
import "core:math"
import "core:os"
import "core:strings"

SYSMIS :: -math.F64_MAX

Compression :: enum u8 {
	None     = 0,
	Bytecode = 1,
	Zlib     = 2,
}

Measure :: enum u8 {
	Unknown = 0,
	Nominal = 1,
	Ordinal = 2,
	Scale   = 3,
}

Format :: struct {
	type:     u8,
	width:    u8,
	decimals: u8,
}

Missing_Kind :: enum u8 {
	None,
	Discrete,           // up to 3 values
	Range,              // values[0]..values[1]
	Range_And_Discrete, // values[0]..values[1], plus values[2]
}

Missing :: struct {
	kind:   Missing_Kind,
	count:  int,
	values: [3]f64,     // numeric variables
	raw:    [3][8]u8,   // string variables
}

Value_Label :: struct {
	value: f64,     // numeric variables
	raw:   [8]u8,   // string variables
	label: string,
}

Variable :: struct {
	name:         string,
	short_name:   string,
	width:        int, // 0 = numeric, else string width in bytes
	label:        string,
	print:        Format,
	write:        Format,
	missing:      Missing,
	measure:      Measure,
	value_labels: [dynamic]Value_Label,
	segment:      int, // index of the first 8-byte segment in a case
	n_segments:   int,
	numbers:      [dynamic]f64,    // case values when numeric
	strings:      [dynamic]string, // case values when string, width bytes each
}

File :: struct {
	product:       string,
	creation_date: string,
	creation_time: string,
	file_label:    string,
	encoding:      string,
	compression:   Compression,
	bias:          f64,
	sysmis:        f64,
	weight:        int, // variable index, -1 if unweighted
	n_cases:       int,
	variables:     [dynamic]Variable,
	documents:     [dynamic]string,
}

Error_Kind :: enum u8 {
	None,
	Io,
	Not_A_System_File,
	Truncated,
	Bad_Record,
	Bad_Compression,
	Unsupported,
}

Read_Error :: struct {
	kind:   Error_Kind,
	offset: int, // byte offset where the problem was detected
}

Error :: union {
	Read_Error,
}

@(private)
Reader :: struct {
	data:  []byte,
	pos:   int,
	order: endian.Byte_Order,
}

// All memory is taken from `allocator`; use an arena and free it as a whole.
read_file :: proc(path: string, allocator := context.allocator) -> (file: File, err: Error) {
	data, os_err := os.read_entire_file(path, context.temp_allocator)
	if os_err != nil {
		return {}, Read_Error{kind = .Io}
	}
	return read(data, allocator)
}

read :: proc(data: []byte, allocator := context.allocator) -> (file: File, err: Error) {
	context.allocator = allocator
	r := Reader{data = data, order = .Little}

	magic := take(&r, 4) or_return
	zsav := string(magic) == "$FL3"
	if !zsav && string(magic) != "$FL2" {
		return {}, Read_Error{kind = .Not_A_System_File, offset = 0}
	}
	product := take(&r, 60) or_return

	layout, _ := endian.get_i32(data[64:68], .Little)
	if layout != 2 && layout != 3 {
		r.order = .Big
		layout, _ = endian.get_i32(data[64:68], .Big)
		if layout != 2 && layout != 3 {
			return {}, Read_Error{kind = .Not_A_System_File, offset = 64}
		}
	}
	r.pos = 68

	_ = read_i32(&r) or_return // nominal case size; recomputed from the dictionary
	compression := read_i32(&r) or_return
	weight_segment := read_i32(&r) or_return
	n_cases := read_i32(&r) or_return
	file.bias = read_f64(&r) or_return
	file.creation_date = trimmed(take(&r, 9) or_return)
	file.creation_time = trimmed(take(&r, 8) or_return)
	file.file_label = trimmed(take(&r, 64) or_return)
	_ = take(&r, 3) or_return

	file.product = trimmed(product)
	file.n_cases = int(n_cases)
	file.sysmis = SYSMIS
	file.weight = -1
	switch {
	case compression == 0 && !zsav: file.compression = .None
	case compression == 1 && !zsav: file.compression = .Bytecode
	case compression == 2 && zsav:  file.compression = .Zlib
	case:                           return {}, Read_Error{kind = .Bad_Compression, offset = 72}
	}

	read_dictionary(&r, &file) or_return

	if weight_segment > 0 {
		file.weight = variable_at_segment(&file, int(weight_segment) - 1)
	}

	cases := r.data[r.pos:]
	if file.compression == .Zlib {
		cases = inflate_zsav(&r) or_return
	}
	read_cases(&file, cases, r.order, r.pos) or_return
	return file, {}
}

@(private)
read_dictionary :: proc(r: ^Reader, file: ^File) -> Error {
	segment := 0
	for {
		at := r.pos
		rec_type := read_i32(r) or_return
		switch rec_type {
		case 2:
			read_variable(r, file, &segment) or_return
		case 3:
			read_value_labels(r, file) or_return
		case 6:
			n_lines := read_i32(r) or_return
			for _ in 0 ..< n_lines {
				append(&file.documents, trimmed(take(r, 80) or_return))
			}
		case 7:
			read_extension(r, file) or_return
		case 999:
			_ = read_i32(r) or_return // filler
			return {}
		case:
			return Read_Error{kind = .Bad_Record, offset = at}
		}
	}
}

@(private)
read_variable :: proc(r: ^Reader, file: ^File, segment: ^int) -> Error {
	at := r.pos
	width := read_i32(r) or_return
	has_label := read_i32(r) or_return
	n_missing := read_i32(r) or_return
	print := read_i32(r) or_return
	write := read_i32(r) or_return
	short_name := trimmed(take(r, 8) or_return)

	defer segment^ += 1
	if width == -1 {
		if len(file.variables) == 0 {
			return Read_Error{kind = .Bad_Record, offset = at}
		}
		file.variables[len(file.variables) - 1].n_segments += 1
		return {}
	}
	if width < 0 || width > 255 {
		return Read_Error{kind = .Bad_Record, offset = at}
	}

	v := Variable {
		short_name = short_name,
		name       = short_name,
		width      = int(width),
		print      = unpack_format(print),
		write      = unpack_format(write),
		segment    = segment^,
		n_segments = 1,
	}
	if has_label == 1 {
		n := read_i32(r) or_return
		v.label = trimmed(take(r, int(n)) or_return)
		_ = take(r, int(align4(n) - n)) or_return
	}

	switch n_missing {
	case 0:
	case 1 ..= 3: v.missing.kind = .Discrete
	case -2:      v.missing.kind = .Range
	case -3:      v.missing.kind = .Range_And_Discrete
	case:         return Read_Error{kind = .Bad_Record, offset = at}
	}
	v.missing.count = int(abs(n_missing))
	for i in 0 ..< v.missing.count {
		raw := take(r, 8) or_return
		copy(v.missing.raw[i][:], raw)
		v.missing.values[i], _ = endian.get_f64(raw, r.order)
	}
	append(&file.variables, v)
	return {}
}

@(private)
read_value_labels :: proc(r: ^Reader, file: ^File) -> Error {
	count := read_i32(r) or_return
	labels := make([]Value_Label, count, context.temp_allocator)
	for &l in labels {
		raw := take(r, 8) or_return
		copy(l.raw[:], raw)
		l.value, _ = endian.get_f64(raw, r.order)
		n := int((take(r, 1) or_return)[0])
		l.label = trimmed(take(r, n) or_return)
		_ = take(r, (n + 8) / 8 * 8 - (n + 1)) or_return
	}

	at := r.pos
	if (read_i32(r) or_return) != 4 {
		return Read_Error{kind = .Bad_Record, offset = at}
	}
	n_vars := read_i32(r) or_return
	for _ in 0 ..< n_vars {
		seg := read_i32(r) or_return
		idx := variable_at_segment(file, int(seg) - 1)
		if idx < 0 {
			return Read_Error{kind = .Bad_Record, offset = at}
		}
		append(&file.variables[idx].value_labels, ..labels)
	}
	return {}
}

@(private)
read_extension :: proc(r: ^Reader, file: ^File) -> Error {
	at := r.pos
	subtype := read_i32(r) or_return
	size := read_i32(r) or_return
	count := read_i32(r) or_return
	body := take(r, int(size) * int(count)) or_return

	switch subtype {
	case 4: // machine float info
		if size == 8 && count >= 1 {
			file.sysmis, _ = endian.get_f64(body[0:8], r.order)
		}
	case 11: // measure, display width, alignment per variable
		per := 3 if int(count) == 3 * len(file.variables) else 2
		for &v, i in file.variables {
			if (i + 1) * per * 4 > len(body) { break }
			m, _ := endian.get_i32(body[i * per * 4:], r.order)
			if m >= 0 && m <= 3 { v.measure = Measure(m) }
		}
	case 13: // long variable names
		for pair in strings.split(string(body), "\t", context.temp_allocator) {
			eq := strings.index_byte(pair, '=')
			if eq < 0 { continue }
			for &v in file.variables {
				if v.short_name == pair[:eq] {
					v.name = strings.clone(pair[eq + 1:])
				}
			}
		}
	case 14:
		return Read_Error{kind = .Unsupported, offset = at} // very long strings: not yet
	case 20:
		file.encoding = trimmed(body)
	}
	return {}
}

@(private)
inflate_zsav :: proc(r: ^Reader) -> (out: []byte, err: Error) {
	at := r.pos
	_ = read_i64(r) or_return // zheader offset (this position)
	trailer_ofs := read_i64(r) or_return
	_ = read_i64(r) or_return // trailer length

	t := Reader{data = r.data, pos = int(trailer_ofs), order = r.order}
	_ = read_i64(&t) or_return // bias
	_ = read_i64(&t) or_return // zero
	_ = read_i32(&t) or_return // block size
	n_blocks := read_i32(&t) or_return

	buf: bytes.Buffer
	bytes.buffer_init_allocator(&buf, 0, 0)
	for _ in 0 ..< n_blocks {
		_ = read_i64(&t) or_return // uncompressed offset
		comp_ofs := read_i64(&t) or_return
		raw_size := read_i32(&t) or_return
		comp_size := read_i32(&t) or_return
		lo, hi := int(comp_ofs), int(comp_ofs) + int(comp_size)
		if lo < 0 || hi > len(r.data) {
			return nil, Read_Error{kind = .Truncated, offset = at}
		}
		block: bytes.Buffer
		if zlib.inflate(r.data[lo:hi], &block, expected_output_size = int(raw_size)) != nil {
			return nil, Read_Error{kind = .Bad_Compression, offset = lo}
		}
		bytes.buffer_write(&buf, bytes.buffer_to_bytes(&block))
		bytes.buffer_destroy(&block)
	}
	return bytes.buffer_to_bytes(&buf), {}
}

@(private)
Segment_Kind :: enum u8 { Raw, Number, Spaces, Sysmis, End }

@(private)
Case_Stream :: struct {
	data:       []byte,
	pos:        int,
	compressed: bool,
	bias:       f64,
	ops:        [8]u8,
	op_index:   int,
}

@(private)
next_segment :: proc(s: ^Case_Stream) -> (kind: Segment_Kind, raw: []byte, number: f64) {
	if !s.compressed {
		if s.pos + 8 > len(s.data) { return .End, nil, 0 }
		defer s.pos += 8
		return .Raw, s.data[s.pos:][:8], 0
	}
	for {
		if s.op_index == 0 || s.op_index == 8 {
			if s.pos + 8 > len(s.data) { return .End, nil, 0 }
			copy(s.ops[:], s.data[s.pos:][:8])
			s.pos += 8
			s.op_index = 0
		}
		op := s.ops[s.op_index]
		s.op_index += 1
		switch op {
		case 0:
			continue
		case 252:
			return .End, nil, 0
		case 253:
			if s.pos + 8 > len(s.data) { return .End, nil, 0 }
			defer s.pos += 8
			return .Raw, s.data[s.pos:][:8], 0
		case 254:
			return .Spaces, nil, 0
		case 255:
			return .Sysmis, nil, 0
		case:
			return .Number, nil, f64(op) - s.bias
		}
	}
}

@(private)
read_cases :: proc(file: ^File, data: []byte, order: endian.Byte_Order, base: int) -> Error {
	s := Case_Stream{data = data, compressed = file.compression != .None, bias = file.bias}
	str := make([]byte, 256, context.temp_allocator)
	n := 0
	cases: for file.n_cases < 0 || n < file.n_cases {
		for &v, vi in file.variables {
			for seg in 0 ..< v.n_segments {
				kind, raw, number := next_segment(&s)
				if kind == .End {
					if vi == 0 && seg == 0 { break cases }
					return Read_Error{kind = .Truncated, offset = base + s.pos}
				}
				if v.width == 0 {
					value: f64
					switch kind {
					case .Raw:    value, _ = endian.get_f64(raw, order)
					case .Number: value = number
					case .Sysmis: value = file.sysmis
					case .Spaces, .End: return Read_Error{kind = .Bad_Compression, offset = base + s.pos}
					}
					append(&v.numbers, value)
					continue
				}
				chunk := str[seg * 8:][:8]
				switch kind {
				case .Raw:    copy(chunk, raw)
				case .Spaces: for &b in chunk { b = ' ' }
				case .Number, .Sysmis, .End: return Read_Error{kind = .Bad_Compression, offset = base + s.pos}
				}
			}
			if v.width > 0 {
				append(&v.strings, strings.clone(string(str[:v.width])))
			}
		}
		n += 1
	}
	file.n_cases = n
	return {}
}

@(private)
variable_at_segment :: proc(file: ^File, segment: int) -> int {
	for v, i in file.variables {
		if v.segment == segment { return i }
	}
	return -1
}

@(private)
unpack_format :: proc(packed: i32) -> Format {
	u := u32(packed)
	return {type = u8(u >> 16), width = u8(u >> 8), decimals = u8(u)}
}

@(private)
align4 :: proc(n: i32) -> i32 {
	return (n + 3) &~ 3
}

@(private)
trimmed :: proc(b: []byte) -> string {
	return strings.clone(strings.trim_right(string(b), " \x00"))
}

@(private)
take :: proc(r: ^Reader, n: int) -> (b: []byte, err: Error) {
	if n < 0 || r.pos + n > len(r.data) {
		return nil, Read_Error{kind = .Truncated, offset = r.pos}
	}
	defer r.pos += n
	return r.data[r.pos:][:n], {}
}

@(private)
read_i32 :: proc(r: ^Reader) -> (v: i32, err: Error) {
	b := take(r, 4) or_return
	v, _ = endian.get_i32(b, r.order)
	return
}

@(private)
read_i64 :: proc(r: ^Reader) -> (v: i64, err: Error) {
	b := take(r, 8) or_return
	v, _ = endian.get_i64(b, r.order)
	return
}

@(private)
read_f64 :: proc(r: ^Reader) -> (v: f64, err: Error) {
	b := take(r, 8) or_return
	v, _ = endian.get_f64(b, r.order)
	return
}
