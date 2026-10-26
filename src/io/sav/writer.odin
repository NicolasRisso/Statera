// Writer for SPSS system files (.sav). Format: docs/specs/io/sav-format.md
package sav

import "core:bytes"
import "core:fmt"
import "core:math"
import "core:strings"
import "core:time"

PRODUCT :: "@(#) SPSS DATA FILE Statera"

@(private = "file")
MONTHS := [12]string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

// Serializes `file` as a .sav. Only .None and .Bytecode compression are supported for now.
write :: proc(file: ^File, compression := Compression.Bytecode, allocator := context.allocator) -> (data: []byte, err: Error) {
	if compression == .Zlib {
		return nil, Read_Error{kind = .Unsupported}
	}
	w: bytes.Buffer
	bytes.buffer_init_allocator(&w, 0, 4096, allocator)

	assign_segments(file)
	n_segments := 0
	for v in file.variables { n_segments += v.n_segments }

	date, clock := file.creation_date, file.creation_time
	if date == "" || clock == "" {
		date, clock = now_strings()
	}

	put_bytes(&w, "$FL2")
	put_padded(&w, PRODUCT, 60)
	put_i32(&w, 2)
	put_i32(&w, i32(n_segments))
	put_i32(&w, i32(compression))
	put_i32(&w, i32(file.variables[file.weight].segment + 1) if file.weight >= 0 else 0)
	put_i32(&w, i32(file.n_cases))
	put_f64(&w, 100)
	put_padded(&w, date, 9)
	put_padded(&w, clock, 8)
	put_padded(&w, file.file_label, 64)
	put_padded(&w, "", 3)

	for v in file.variables { put_variable(&w, v) }
	for v in file.variables {
		if len(v.value_labels) > 0 { put_value_labels(&w, v) }
	}
	if len(file.documents) > 0 {
		put_i32(&w, 6)
		put_i32(&w, i32(len(file.documents)))
		for line in file.documents { put_padded(&w, line, 80) }
	}
	put_extensions(&w, file, compression)
	put_i32(&w, 999)
	put_i32(&w, 0)

	if compression == .None {
		put_cases_raw(&w, file)
	} else {
		put_cases_bytecode(&w, file)
	}
	return bytes.buffer_to_bytes(&w), nil
}

@(private = "file")
assign_segments :: proc(file: ^File) {
	segment := 0
	for &v, i in file.variables {
		v.segment = segment
		v.n_segments = 1 if v.width == 0 else (v.width + 7) / 8
		segment += v.n_segments
		if v.short_name == "" {
			v.short_name = fmt.aprintf("V%d", i + 1, allocator = context.temp_allocator)
		}
	}
}

@(private = "file")
put_variable :: proc(w: ^bytes.Buffer, v: Variable) {
	n_missing: i32
	switch v.missing.kind {
	case .None:               n_missing = 0
	case .Discrete:           n_missing = i32(v.missing.count)
	case .Range:              n_missing = -2
	case .Range_And_Discrete: n_missing = -3
	}
	put_i32(w, 2)
	put_i32(w, i32(v.width))
	put_i32(w, 1 if v.label != "" else 0)
	put_i32(w, n_missing)
	put_i32(w, pack_format(v.print))
	put_i32(w, pack_format(v.write))
	put_padded(w, strings.to_upper(v.short_name, context.temp_allocator), 8)
	if v.label != "" {
		n := i32(len(v.label))
		put_i32(w, n)
		put_padded(w, v.label, int(align4(n)))
	}
	for i in 0 ..< int(abs(n_missing)) {
		if v.width == 0 {
			put_f64(w, v.missing.values[i])
		} else {
			raw := v.missing.raw[i]
			bytes.buffer_write(w, raw[:])
		}
	}
	for _ in 1 ..< v.n_segments {
		put_i32(w, 2)
		put_i32(w, -1)
		for _ in 0 ..< 4 { put_i32(w, 0) }
		put_padded(w, "", 8)
	}
}

@(private = "file")
put_value_labels :: proc(w: ^bytes.Buffer, v: Variable) {
	put_i32(w, 3)
	put_i32(w, i32(len(v.value_labels)))
	for l in v.value_labels {
		if v.width == 0 {
			put_f64(w, l.value)
		} else {
			raw := l.raw
			bytes.buffer_write(w, raw[:])
		}
		label := l.label[:min(len(l.label), 120)]
		bytes.buffer_write_byte(w, u8(len(label)))
		put_padded(w, label, (len(label) + 8) / 8 * 8 - 1)
	}
	put_i32(w, 4)
	put_i32(w, 1)
	put_i32(w, i32(v.segment + 1))
}

@(private = "file")
put_extensions :: proc(w: ^bytes.Buffer, file: ^File, compression: Compression) {
	// 3: machine integer info (version 0.1.0, IEEE floats, little-endian, UTF-8).
	ints := [8]i32{0, 1, 0, -1, 1, i32(compression), 2, 65001}
	put_extension_header(w, 3, 4, 8)
	for x in ints { put_i32(w, x) }

	// 4: machine float info.
	put_extension_header(w, 4, 8, 3)
	put_f64(w, SYSMIS)
	put_f64(w, math.F64_MAX)
	put_f64(w, math.nextafter(-math.F64_MAX, 0))

	// 11: measure, display width, alignment.
	put_extension_header(w, 11, 4, i32(3 * len(file.variables)))
	for v in file.variables {
		put_i32(w, i32(v.measure))
		put_i32(w, 8 if v.width == 0 else i32(min(v.width, 255)))
		put_i32(w, 1 if v.width == 0 else 0) // numbers right-aligned, strings left
	}

	// 13: long variable names.
	names := strings.builder_make(context.temp_allocator)
	for v, i in file.variables {
		if i > 0 { strings.write_byte(&names, '\t') }
		fmt.sbprintf(&names, "%s=%s", strings.to_upper(v.short_name, context.temp_allocator), v.name)
	}
	put_extension_header(w, 13, 1, i32(strings.builder_len(names)))
	put_bytes(w, strings.to_string(names))

	// 20: character encoding.
	put_extension_header(w, 20, 1, 5)
	put_bytes(w, "UTF-8")
}

@(private = "file")
put_cases_raw :: proc(w: ^bytes.Buffer, file: ^File) {
	for c in 0 ..< file.n_cases {
		for v in file.variables {
			if v.width == 0 {
				put_f64(w, v.numbers[c])
			} else {
				put_padded(w, v.strings[c], v.n_segments * 8)
			}
		}
	}
}

@(private = "file")
Bytecode_Writer :: struct {
	out:      ^bytes.Buffer,
	ops:      [8]u8,
	n_ops:    int,
	raw:      [8][8]u8,
	n_raw:    int,
}

@(private = "file")
put_cases_bytecode :: proc(w: ^bytes.Buffer, file: ^File) {
	bw := Bytecode_Writer{out = w}
	for c in 0 ..< file.n_cases {
		for v in file.variables {
			if v.width == 0 {
				x := v.numbers[c]
				switch {
				case x == SYSMIS:
					emit(&bw, 255, nil)
				case x == math.floor(x) && x >= -99 && x <= 151:
					emit(&bw, u8(x + 100), nil)
				case:
					raw: [8]u8
					put_f64_into(raw[:], x)
					emit(&bw, 253, raw[:])
				}
				continue
			}
			padded := make([]u8, v.n_segments * 8, context.temp_allocator)
			for &b in padded { b = ' ' }
			copy(padded, v.strings[c])
			for s in 0 ..< v.n_segments {
				chunk := padded[s * 8:][:8]
				if string(chunk) == "        " {
					emit(&bw, 254, nil)
				} else {
					emit(&bw, 253, chunk)
				}
			}
		}
	}
	if bw.n_ops > 0 { flush(&bw) }
}

@(private = "file")
emit :: proc(bw: ^Bytecode_Writer, op: u8, raw: []u8) {
	bw.ops[bw.n_ops] = op
	bw.n_ops += 1
	if raw != nil {
		copy(bw.raw[bw.n_raw][:], raw)
		bw.n_raw += 1
	}
	if bw.n_ops == 8 { flush(bw) }
}

@(private = "file")
flush :: proc(bw: ^Bytecode_Writer) {
	for i in bw.n_ops ..< 8 { bw.ops[i] = 0 }
	bytes.buffer_write(bw.out, bw.ops[:])
	for i in 0 ..< bw.n_raw { bytes.buffer_write(bw.out, bw.raw[i][:]) }
	bw.n_ops, bw.n_raw = 0, 0
}

@(private = "file")
now_strings :: proc() -> (date, clock: string) {
	now := time.now()
	y, mon, d := time.date(now)
	h, m, s := time.clock(now)
	date = fmt.aprintf("%02d %s %02d", d, MONTHS[int(mon) - 1], y % 100, allocator = context.temp_allocator)
	clock = fmt.aprintf("%02d:%02d:%02d", h, m, s, allocator = context.temp_allocator)
	return
}

@(private = "file")
pack_format :: proc(f: Format) -> i32 {
	return i32(u32(f.type) << 16 | u32(f.width) << 8 | u32(f.decimals))
}

@(private = "file")
put_extension_header :: proc(w: ^bytes.Buffer, subtype, size, count: i32) {
	put_i32(w, 7)
	put_i32(w, subtype)
	put_i32(w, size)
	put_i32(w, count)
}

@(private = "file")
put_i32 :: proc(w: ^bytes.Buffer, x: i32) {
	b := transmute([4]u8)i32le(x)
	bytes.buffer_write(w, b[:])
}

@(private = "file")
put_f64 :: proc(w: ^bytes.Buffer, x: f64) {
	b: [8]u8
	put_f64_into(b[:], x)
	bytes.buffer_write(w, b[:])
}

@(private = "file")
put_f64_into :: proc(dst: []u8, x: f64) {
	b := transmute([8]u8)f64le(x)
	copy(dst, b[:])
}

@(private = "file")
put_bytes :: proc(w: ^bytes.Buffer, s: string) {
	bytes.buffer_write_string(w, s)
}

// Writes s truncated or space-padded to exactly n bytes.
@(private = "file")
put_padded :: proc(w: ^bytes.Buffer, s: string, n: int) {
	k := min(len(s), n)
	bytes.buffer_write_string(w, s[:k])
	for _ in k ..< n { bytes.buffer_write_byte(w, ' ') }
}
