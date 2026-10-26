package sav

import "core:slice"

// Deep-copies the case data (and per-variable arrays) of `f` with `allocator`.
// Strings such as names and labels are shared, so `f` must outlive the clone.
clone :: proc(f: ^File, allocator := context.allocator) -> File {
	context.allocator = allocator
	out := f^
	out.variables = make([dynamic]Variable, 0, len(f.variables) + 16)
	for v in f.variables {
		nv := v
		nv.numbers = slice.clone_to_dynamic(v.numbers[:])
		nv.strings = slice.clone_to_dynamic(v.strings[:])
		nv.value_labels = slice.clone_to_dynamic(v.value_labels[:])
		append(&out.variables, nv)
	}
	return out
}
