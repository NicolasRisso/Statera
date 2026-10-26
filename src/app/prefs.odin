package app

import "core:os"
import "core:strings"

import sdl "vendor:sdl3"

// Per-user settings, stored in the OS app-data folder (writable even when installed system-wide).
Prefs :: struct {
	dir:        string,
	layout_ini: cstring,
	theme_mode: Theme_Mode,
}

prefs_load :: proc() -> Prefs {
	p := Prefs{theme_mode = .System}
	if base := sdl.GetPrefPath("RissoProductions", "OpenSPSS"); base != nil {
		p.dir = strings.clone(string(cstring(base)))
		sdl.free(rawptr(base))
	}
	p.layout_ini = strings.clone_to_cstring(strings.concatenate({p.dir, "layout.ini"}, context.temp_allocator))

	data, err := os.read_entire_file(prefs_path(p), context.temp_allocator)
	if err != nil { return p }
	for line in strings.split_lines(string(data), context.temp_allocator) {
		key, _, value := strings.partition(strings.trim_space(line), "=")
		if key == "theme" {
			switch value {
			case "dark":  p.theme_mode = .Dark
			case "light": p.theme_mode = .Light
			case:         p.theme_mode = .System
			}
		}
	}
	return p
}

prefs_save :: proc(p: Prefs) {
	names := [Theme_Mode]string{.System = "system", .Dark = "dark", .Light = "light"}
	text := strings.concatenate({"theme=", names[p.theme_mode], "\n"}, context.temp_allocator)
	_ = os.write_entire_file(prefs_path(p), transmute([]byte)text)
}

@(private = "file")
prefs_path :: proc(p: Prefs) -> string {
	return strings.concatenate({p.dir, "prefs.ini"}, context.temp_allocator)
}
