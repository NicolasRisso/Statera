package sav

import "core:mem/virtual"
import "core:strings"
import "core:testing"

FIXTURES :: #directory + "/../../../tests/golden/sav_basic/expected/"

@(private = "file")
check_sav_basic :: proc(t: ^testing.T, name: string, compression: Compression) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)

	file, err := read_file(strings.concatenate({FIXTURES, name}, context.temp_allocator), virtual.arena_allocator(&arena))
	if !testing.expect_value(t, err, nil) { return }

	testing.expect_value(t, file.compression, compression)
	testing.expect_value(t, file.encoding, "UTF-8")
	testing.expect_value(t, file.n_cases, 6)
	testing.expect_value(t, file.weight, -1)
	if !testing.expect_value(t, len(file.variables), 3) { return }

	id, grp, score := file.variables[0], file.variables[1], file.variables[2]
	testing.expect_value(t, id.name, "id")
	testing.expect_value(t, grp.name, "grp")
	testing.expect_value(t, score.name, "score")
	testing.expect_value(t, score.short_name, "SCORE")
	testing.expect_value(t, score.label, "Test score")
	testing.expect_value(t, score.print.type, 5) // F
	testing.expect_value(t, score.print.decimals, 2)
	testing.expect_value(t, id.measure, Measure.Nominal)
	testing.expect_value(t, score.measure, Measure.Scale)

	testing.expect_value(t, score.missing.kind, Missing_Kind.Discrete)
	testing.expect_value(t, score.missing.count, 1)
	testing.expect_value(t, score.missing.values[0], 99)

	if testing.expect_value(t, len(grp.value_labels), 2) {
		testing.expect_value(t, grp.value_labels[0].value, 1)
		testing.expect_value(t, grp.value_labels[0].label, "Control")
		testing.expect_value(t, grp.value_labels[1].value, 2)
		testing.expect_value(t, grp.value_labels[1].label, "Treatment")
	}

	want_id := [6]f64{1, 2, 3, 4, 5, 6}
	want_grp := [6]f64{1, 1, 2, 2, 2, 1}
	want_score := [6]f64{10.5, 12.25, 9, SYSMIS, 15.75, 99}
	for i in 0 ..< 6 {
		testing.expect_value(t, id.numbers[i], want_id[i])
		testing.expect_value(t, grp.numbers[i], want_grp[i])
		testing.expect_value(t, score.numbers[i], want_score[i])
	}
}

@(test)
test_uncompressed :: proc(t: ^testing.T) {
	check_sav_basic(t, "uncompressed.sav", .None)
}

@(test)
test_bytecode_compressed :: proc(t: ^testing.T) {
	check_sav_basic(t, "compressed.sav", .Bytecode)
}

@(test)
test_zlib_compressed :: proc(t: ^testing.T) {
	check_sav_basic(t, "zcompressed.zsav", .Zlib)
}

@(test)
test_rejects_non_sav :: proc(t: ^testing.T) {
	_, err := read(transmute([]byte)string("not a system file at all"), context.temp_allocator)
	e, ok := err.(Read_Error)
	testing.expect(t, ok)
	testing.expect_value(t, e.kind, Error_Kind.Not_A_System_File)

	_, err = read(transmute([]byte)string("$FL2 truncated header"), context.temp_allocator)
	e, _ = err.(Read_Error)
	testing.expect_value(t, e.kind, Error_Kind.Truncated)
}
