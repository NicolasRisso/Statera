package sav

import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
round_trip :: proc(t: ^testing.T, compression: Compression) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	alloc := virtual.arena_allocator(&arena)

	path := strings.concatenate({FIXTURES, "compressed.sav"}, context.temp_allocator)
	original, err := read_file(path, alloc)
	if !testing.expect_value(t, err, nil) { return }

	data, werr := write(&original, compression, alloc)
	if !testing.expect_value(t, werr, nil) { return }

	if out_dir, ok := os.lookup_env("OPENSPSS_WRITE_SAMPLES", context.temp_allocator); ok {
		name := "rt_bytecode.sav" if compression == .Bytecode else "rt_uncompressed.sav"
		_ = os.write_entire_file(strings.concatenate({out_dir, "/", name}, context.temp_allocator), data)
	}

	again, rerr := read(data, alloc)
	if !testing.expect_value(t, rerr, nil) { return }
	testing.expect_value(t, again.compression, compression)
	testing.expect_value(t, again.n_cases, original.n_cases)
	if !testing.expect_value(t, len(again.variables), len(original.variables)) { return }

	for v, i in original.variables {
		a := again.variables[i]
		testing.expect_value(t, a.name, v.name)
		testing.expect_value(t, a.label, v.label)
		testing.expect_value(t, a.print, v.print)
		testing.expect_value(t, a.measure, v.measure)
		testing.expect_value(t, a.missing.kind, v.missing.kind)
		testing.expect_value(t, len(a.value_labels), len(v.value_labels))
		for x, c in v.numbers { testing.expect_value(t, a.numbers[c], x) }
	}
}

@(test)
test_round_trip_bytecode :: proc(t: ^testing.T) {
	round_trip(t, .Bytecode)
}

@(test)
test_round_trip_uncompressed :: proc(t: ^testing.T) {
	round_trip(t, .None)
}

@(test)
test_round_trip_strings :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	alloc := virtual.arena_allocator(&arena)
	context.allocator = alloc

	f := File{n_cases = 3, weight = -1, sysmis = SYSMIS}
	v := Variable{name = "city_name", short_name = "CITY", width = 12, print = {type = 1, width = 12}}
	v.write = v.print
	append(&v.strings, "Sao Paulo   ", "            ", "Rio de Janei")
	append(&f.variables, v)

	data, err := write(&f, .Bytecode, alloc)
	if !testing.expect_value(t, err, nil) { return }
	back, rerr := read(data, alloc)
	if !testing.expect_value(t, rerr, nil) { return }
	testing.expect_value(t, back.variables[0].name, "city_name")
	testing.expect_value(t, back.variables[0].strings[0], "Sao Paulo   ")
	testing.expect_value(t, back.variables[0].strings[1], "            ")
	testing.expect_value(t, back.variables[0].strings[2], "Rio de Janei")
}
