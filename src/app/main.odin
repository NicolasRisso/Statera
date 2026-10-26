// OpenSPSS desktop application: SDL3 window, OpenGL 3 renderer, Dear ImGui docking UI.
package app

import "base:runtime"
import "core:os"
import "core:strings"

import im "../../vendor/imgui"
import "../../vendor/imgui/imgui_impl_opengl3"
import "../../vendor/imgui/imgui_impl_sdl3"
import gl "vendor:OpenGL"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

GL_MAJOR :: 3
GL_MINOR :: 3

main :: proc() {
	if !sdl.Init({.VIDEO}) {
		os.exit(1)
	}
	defer sdl.Quit()

	sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(transmute(u32)sdl.GL_CONTEXT_PROFILE_CORE))
	sdl.GL_SetAttribute(.CONTEXT_FLAGS, i32(transmute(u32)sdl.GL_CONTEXT_FORWARD_COMPATIBLE_FLAG))
	sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, GL_MAJOR)
	sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, GL_MINOR)
	sdl.GL_SetAttribute(.DOUBLEBUFFER, 1)

	window := sdl.CreateWindow("OpenSPSS", 1440, 900, {.OPENGL, .RESIZABLE, .HIGH_PIXEL_DENSITY, .HIDDEN})
	if window == nil {
		os.exit(1)
	}
	defer sdl.DestroyWindow(window)
	sdl.SetWindowMinimumSize(window, 800, 500)

	gl_ctx := sdl.GL_CreateContext(window)
	defer sdl.GL_DestroyContext(gl_ctx)
	sdl.GL_MakeCurrent(window, gl_ctx)
	sdl.GL_SetSwapInterval(1)
	gl.load_up_to(GL_MAJOR, GL_MINOR, proc(p: rawptr, name: cstring) {
		(^rawptr)(p)^ = rawptr(sdl.GL_GetProcAddress(name))
	})

	im.CHECKVERSION()
	im.CreateContext()
	defer im.DestroyContext()
	io := im.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard, .DockingEnable, .ViewportsEnable}
	app := new(App)
	defer free(app)
	app_init(app)
	app.prefs = prefs_load()
	io.IniFilename = app.prefs.layout_ini
	set_theme_mode(app, app.prefs.theme_mode, save = false)

	app.dpi = sdl.GetWindowDisplayScale(window)
	if app.dpi <= 0 { app.dpi = 1 }
	style := im.GetStyle()
	im.Style_ScaleAllSizes(style, app.dpi)
	style.FontScaleDpi = app.dpi
	app.fonts = load_fonts()

	imgui_impl_sdl3.InitForOpenGL(window, gl_ctx)
	defer imgui_impl_sdl3.Shutdown()
	imgui_impl_opengl3.Init("#version 150")
	defer imgui_impl_opengl3.Shutdown()

	// Usage: openspss [file.sav] [--light | --dark] [--screenshot out.png]
	screenshot_path := ""
	for i := 1; i < len(os.args); i += 1 {
		switch arg := os.args[i]; arg {
		case "--light":
			set_theme_mode(app, .Light, save = false)
		case "--dark":
			set_theme_mode(app, .Dark, save = false)
		case "--screenshot":
			if i + 1 < len(os.args) { screenshot_path = os.args[i + 1]; i += 1 }
		case:
			open_dataset(app, arg)
		}
	}

	sdl.ShowWindow(window)
	main_id := sdl.GetWindowID(window)
	frame := 0
	for app.running {
		frame += 1
		e: sdl.Event
		for sdl.PollEvent(&e) {
			imgui_impl_sdl3.ProcessEvent(&e)
			#partial switch e.type {
			case .QUIT:
				app.running = false
			case .WINDOW_CLOSE_REQUESTED:
				if e.window.windowID == main_id { app.running = false }
			case .SYSTEM_THEME_CHANGED:
				if app.prefs.theme_mode == .System { set_theme_mode(app, .System, save = false) }
			case .DROP_FILE:
				open_dataset(app, string(e.drop.data))
			}
		}
		if path, ok := take_pending_open(app); ok {
			open_dataset(app, path)
			delete(path)
		}

		imgui_impl_opengl3.NewFrame()
		imgui_impl_sdl3.NewFrame()
		im.NewFrame()
		handle_shortcuts(app)
		draw_ui(app)
		im.Render()

		gl.Viewport(0, 0, i32(io.DisplaySize.x * io.DisplayFramebufferScale.x), i32(io.DisplaySize.y * io.DisplayFramebufferScale.y))
		bg := palette.bg
		gl.ClearColor(bg.x, bg.y, bg.z, 1)
		gl.Clear(gl.COLOR_BUFFER_BIT)
		imgui_impl_opengl3.RenderDrawData(im.GetDrawData())
		if screenshot_path != "" && frame == 20 {
			save_screenshot(screenshot_path, io.DisplaySize * io.DisplayFramebufferScale)
			app.running = false
		}

		if .ViewportsEnable in io.ConfigFlags {
			backup_window, backup_ctx := sdl.GL_GetCurrentWindow(), sdl.GL_GetCurrentContext()
			im.UpdatePlatformWindows()
			im.RenderPlatformWindowsDefault()
			sdl.GL_MakeCurrent(backup_window, backup_ctx)
		}
		sdl.GL_SwapWindow(window)
		free_all(context.temp_allocator)
	}
}

// Reads back the main framebuffer and writes it as a PNG (developer aid for visual checks).
@(private = "file")
save_screenshot :: proc(path: string, size: im.Vec2) {
	w, h := i32(size.x), i32(size.y)
	pixels := make([]u8, int(w * h * 4), context.temp_allocator)
	gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
	gl.ReadPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))
	stbi.flip_vertically_on_write(true)
	stbi.write_png(strings.clone_to_cstring(path, context.temp_allocator), w, h, 4, raw_data(pixels), w * 4)
}

set_theme_mode :: proc(app: ^App, mode: Theme_Mode, save := true) {
	app.prefs.theme_mode = mode
	app.theme = resolve_theme(mode)
	apply_theme(app.theme)
	if save { prefs_save(app.prefs) }
}

toggle_theme :: proc(app: ^App) {
	set_theme_mode(app, .Light if app.theme == .Dark else .Dark)
}

@(private = "file")
handle_shortcuts :: proc(app: ^App) {
	CTRL :: i32(im.Key.ImGuiMod_Ctrl)
	chord :: proc(key: im.Key) -> im.KeyChord { return CTRL | i32(key) }
	if im.Shortcut(chord(.K), {.RouteGlobal}) { app.palette_open = true }
	if im.Shortcut(chord(.O), {.RouteGlobal}) { show_open_dialog(app) }
	if im.Shortcut(chord(.L), {.RouteGlobal}) { app.show_labels = !app.show_labels }
	if im.Shortcut(chord(.Q), {.RouteGlobal}) { app.running = false }
	if im.Shortcut(chord(.Enter), {.RouteGlobal}) { check_syntax(app) }
	if im.Shortcut(CTRL | i32(im.Key.ImGuiMod_Shift) | i32(im.Key.T), {.RouteGlobal}) { toggle_theme(app) }
}

show_open_dialog :: proc(app: ^App) {
	@(static) filters := [?]sdl.DialogFileFilter{
		{name = "SPSS data files", pattern = "sav;zsav"},
		{name = "All files", pattern = "*"},
	}
	callback :: proc "c" (userdata: rawptr, files: [^]cstring, filter: i32) {
		context = runtime.default_context()
		if files == nil || files[0] == nil { return }
		request_open((^App)(userdata), string(files[0]))
	}
	sdl.ShowOpenFileDialog(callback, app, sdl.GL_GetCurrentWindow(), &filters[0], len(filters), nil, false)
}
