package app

import "core:fmt"
import "core:strings"

import im "../../vendor/imgui"
import "../engine"
import "../io/sav"
import "../output"

WIN_DATA :: "Data View"
WIN_VARS :: "Variable View"
WIN_SYNTAX :: "Syntax"
WIN_OUTPUT :: "Output"

cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

text_colored :: proc(col: im.Vec4, s: string) {
	im.PushStyleColorImVec4(.Text, col)
	im.TextUnformatted(cstr(s))
	im.PopStyleColor()
}

draw_ui :: proc(app: ^App) {
	draw_menu_bar(app)
	draw_status_bar(app)

	dock_id := im.GetID("main_dockspace")
	vp := im.GetMainViewport()
	if app.reset_layout || im.DockBuilderGetNode(dock_id) == nil {
		build_default_layout(dock_id, vp)
		app.reset_layout = false
	}
	im.DockSpaceOverViewport(dock_id, vp)

	draw_data_view(app)
	draw_variable_view(app)
	draw_syntax(app)
	draw_output(app)
	draw_command_palette(app)
	if app.show_demo { im.ShowDemoWindow(&app.show_demo) }
}

@(private = "file")
build_default_layout :: proc(dock_id: im.ID, vp: ^im.Viewport) {
	DOCKSPACE_NODE :: 1 << 10 // ImGuiDockNodeFlags_DockSpace (internal)
	im.DockBuilderRemoveNode(dock_id)
	im.DockBuilderAddNode(dock_id, transmute(im.DockNodeFlags)i32(DOCKSPACE_NODE))
	im.DockBuilderSetNodeSize(dock_id, vp.WorkSize)

	left, right, top, bottom: im.ID
	im.DockBuilderSplitNode(dock_id, .Right, 0.42, &right, &left)
	im.DockBuilderSplitNode(left, .Down, 0.34, &bottom, &top)
	im.DockBuilderDockWindow(WIN_DATA, top)
	im.DockBuilderDockWindow(WIN_VARS, top)
	im.DockBuilderDockWindow(WIN_SYNTAX, bottom)
	im.DockBuilderDockWindow(WIN_OUTPUT, right)
	im.DockBuilderFinish(dock_id)
}

@(private = "file")
draw_menu_bar :: proc(app: ^App) {
	if !im.BeginMainMenuBar() { return }
	defer im.EndMainMenuBar()

	text_colored(palette.accent, "Statera")
	im.Dummy({8, 0})
	if im.BeginMenu("File") {
		if im.MenuItem("Open data file…", "Ctrl+O") { show_open_dialog(app) }
		if im.MenuItem("Save data", "Ctrl+S") { save_or_ask(app) }
		if im.MenuItem("Save data as…", "Ctrl+Shift+S") { show_save_dialog(app) }
		im.Separator()
		if im.MenuItem("Export output…", "Ctrl+E") { show_export_dialog(app) }
		if im.MenuItem("Load demo dataset") { load_demo_dataset(app) }
		im.Separator()
		if im.MenuItem("Quit", "Ctrl+Q") { app.running = false }
		im.EndMenu()
	}
	if im.BeginMenu("View") {
		if im.MenuItem("Value labels", "Ctrl+L", app.show_labels) { app.show_labels = !app.show_labels }
		im.Separator()
		if im.MenuItem("Theme: follow system", nil, app.prefs.theme_mode == .System) { set_theme_mode(app, .System) }
		if im.MenuItem("Theme: light", nil, app.prefs.theme_mode == .Light) { set_theme_mode(app, .Light) }
		if im.MenuItem("Theme: dark", nil, app.prefs.theme_mode == .Dark) { set_theme_mode(app, .Dark) }
		if im.MenuItem("Toggle light/dark", "Ctrl+Shift+T") { toggle_theme(app) }
		im.Separator()
		if im.MenuItem("Reset layout") { app.reset_layout = true }
		if im.MenuItem("ImGui demo", nil, app.show_demo) { app.show_demo = !app.show_demo }
		im.EndMenu()
	}
	if im.BeginMenu("Run") {
		if im.MenuItem("Run all syntax", "Ctrl+Enter") { run_editor(app) }
		im.EndMenu()
	}
	if im.BeginMenu("Help") {
		if im.MenuItem("Command palette", "Ctrl+K") { app.palette_open = true }
		im.Separator()
		im.MenuItem(cstr(fmt.tprintf("Statera %s · Apache-2.0", VERSION)), nil, false, false)
		im.EndMenu()
	}

	hint := "Ctrl+K  command palette"
	segments := [Theme_Mode]cstring{.System = "System", .Light = "Light", .Dark = "Dark"}
	pad := im.GetStyle().FramePadding.x * 2
	seg_w: f32 = 0
	for s in segments { seg_w += im.CalcTextSize(s).x + pad }
	im.SameLine(im.GetWindowWidth() - seg_w - im.CalcTextSize(cstr(hint)).x - 40)
	text_colored(palette.dim, hint)
	im.SameLine(0, 16)
	draw_theme_switch(app, segments)
}

// Segmented control: the active mode is drawn in the accent color.
@(private = "file")
draw_theme_switch :: proc(app: ^App, labels: [Theme_Mode]cstring) {
	im.PushStyleVarImVec2(.ItemSpacing, {0, 0})
	defer im.PopStyleVar()
	for mode in Theme_Mode {
		active := app.prefs.theme_mode == mode
		im.PushStyleColorImVec4(.Button, palette.accent if active else palette.frame)
		im.PushStyleColorImVec4(.Text, palette.panel if active else palette.text)
		if im.SmallButton(labels[mode]) { set_theme_mode(app, mode) }
		im.PopStyleColor(2)
		im.SameLine()
	}
	im.NewLine()
}

@(private = "file")
draw_status_bar :: proc(app: ^App) {
	flags := im.WindowFlags{.NoScrollbar, .NoSavedSettings, .MenuBar}
	h := im.GetFrameHeight()
	if im.BeginViewportSideBar("##status", im.GetMainViewport(), .Down, h, flags) {
		if im.BeginMenuBar() {
			f := data(app)
			text_colored(palette.ok, "●")
			im.TextUnformatted(cstr(fmt.tprintf("%s   %d cases × %d variables", app.session.data_name, f.n_cases, len(f.variables))))
			right := fmt.tprintf("Weight: %s   Filter: off   Split: off   %.0f fps",
				f.variables[f.weight].name if f.weight >= 0 else "off", im.GetIO().Framerate)
			w := im.CalcTextSize(cstr(right)).x
			im.SameLine(im.GetWindowWidth() - w - 16)
			text_colored(palette.dim, right)
			im.EndMenuBar()
		}
	}
	im.End()
}

is_user_missing :: proc(v: ^sav.Variable, x: f64) -> bool {
	m := &v.missing
	switch m.kind {
	case .None:
		return false
	case .Discrete:
		for i in 0 ..< m.count {
			if x == m.values[i] { return true }
		}
	case .Range:
		return x >= m.values[0] && x <= m.values[1]
	case .Range_And_Discrete:
		return (x >= m.values[0] && x <= m.values[1]) || x == m.values[2]
	}
	return false
}

value_label :: proc(v: ^sav.Variable, x: f64) -> (string, bool) {
	for l in v.value_labels {
		if l.value == x { return l.label, true }
	}
	return "", false
}

format_number :: proc(v: ^sav.Variable, x: f64) -> string {
	return fmt.tprintf("%.*f", int(v.print.decimals), x)
}

@(private = "file")
draw_data_view :: proc(app: ^App) {
	defer im.End()
	if !im.Begin(WIN_DATA) { return }
	f := data(app)

	im.Checkbox("Value labels", &app.show_labels)
	im.SameLine()
	text_colored(palette.dim, fmt.tprintf("   %s · %d cases", app.session.data_name, f.n_cases))

	n_cols := min(len(f.variables), 511)
	if n_cols == 0 {
		text_colored(palette.dim, "No variables. Open a .sav file (Ctrl+O) or drop one on the window.")
		return
	}
	flags := im.TableFlags_ScrollX | im.TableFlags_ScrollY | im.TableFlags_RowBg | im.TableFlags_BordersInnerV |
		im.TableFlags_BordersOuter | im.TableFlags_Resizable | im.TableFlags_Reorderable | im.TableFlags_Hideable |
		im.TableFlags_SizingFixedFit
	if !im.BeginTable("##data", i32(n_cols + 1), flags) { return }
	defer im.EndTable()

	im.TableSetupScrollFreeze(1, 1)
	im.TableSetupColumn("#", {.WidthFixed, .NoHide, .NoReorder}, 64)
	for i in 0 ..< n_cols {
		v := &f.variables[i]
		w: f32 = 110 if len(v.value_labels) > 0 else 84
		im.TableSetupColumn(cstr(v.name), {.WidthFixed}, w)
	}
	im.TableHeadersRow()

	clipper: im.ListClipper
	im.ListClipper_Begin(&clipper, i32(f.n_cases))
	defer im.ListClipper_End(&clipper)
	for im.ListClipper_Step(&clipper) {
		for row in clipper.DisplayStart ..< clipper.DisplayEnd {
			im.TableNextRow()
			if im.TableSetColumnIndex(0) {
				text_colored(palette.dim, fmt.tprintf("%d", row + 1))
			}
			for i in 0 ..< n_cols {
				if !im.TableSetColumnIndex(i32(i + 1)) { continue }
				draw_cell(app, &f.variables[i], int(row))
			}
		}
	}
}

@(private = "file")
draw_cell :: proc(app: ^App, v: ^sav.Variable, row: int) {
	if v.width > 0 {
		if row < len(v.strings) { im.TextUnformatted(cstr(strings.trim_right_space(v.strings[row]))) }
		return
	}
	if row >= len(v.numbers) { return }
	x := v.numbers[row]
	if x == data(app).sysmis {
		text_colored(palette.sysmis, ".")
		return
	}
	s := format_number(v, x)
	if app.show_labels {
		if label, ok := value_label(v, x); ok { s = label }
	}
	if is_user_missing(v, x) {
		text_colored(palette.missing, s)
	} else {
		im.TextUnformatted(cstr(s))
	}
}

@(private = "file")
draw_variable_view :: proc(app: ^App) {
	defer im.End()
	if !im.Begin(WIN_VARS) { return }
	f := data(app)

	flags := im.TableFlags_ScrollY | im.TableFlags_RowBg | im.TableFlags_BordersInnerV | im.TableFlags_BordersOuter |
		im.TableFlags_Resizable
	headers := [?]cstring{"", "Name", "Type", "Width", "Decimals", "Label", "Values", "Missing", "Measure"}
	if !im.BeginTable("##vars", len(headers), flags) { return }
	defer im.EndTable()

	im.TableSetupScrollFreeze(0, 1)
	for h, i in headers {
		col_flags: im.TableColumnFlags = {.WidthStretch} if i == 5 || i == 6 else {.WidthFixed}
		im.TableSetupColumn(h, col_flags, 40 if i == 0 else 0)
	}
	im.TableHeadersRow()

	for &v, i in f.variables {
		im.TableNextRow()
		im.TableNextColumn()
		if im.Selectable(cstr(fmt.tprintf("%d", i + 1)), app.selected_var == i, {.SpanAllColumns}) {
			app.selected_var = i
		}
		im.TableNextColumn(); im.TextUnformatted(cstr(v.name))
		im.TableNextColumn(); im.TextUnformatted("String" if v.width > 0 else "Numeric")
		im.TableNextColumn(); im.TextUnformatted(cstr(fmt.tprintf("%d", v.width if v.width > 0 else int(v.print.width))))
		im.TableNextColumn(); im.TextUnformatted(cstr(fmt.tprintf("%d", v.print.decimals)))
		im.TableNextColumn(); im.TextUnformatted(cstr(v.label))
		im.TableNextColumn(); draw_labels_summary(&v)
		im.TableNextColumn(); draw_missing_summary(&v)
		im.TableNextColumn(); draw_measure(v.measure)
	}
}

@(private = "file")
draw_labels_summary :: proc(v: ^sav.Variable) {
	if len(v.value_labels) == 0 {
		text_colored(palette.dim, "None")
		return
	}
	b := strings.builder_make(context.temp_allocator)
	for l, i in v.value_labels {
		if i > 0 { strings.write_string(&b, ", ") }
		fmt.sbprintf(&b, "%v = %s", l.value, l.label)
		if i == 2 && len(v.value_labels) > 3 {
			fmt.sbprintf(&b, ", +%d more", len(v.value_labels) - 3)
			break
		}
	}
	im.TextUnformatted(cstr(strings.to_string(b)))
}

@(private = "file")
draw_missing_summary :: proc(v: ^sav.Variable) {
	m := &v.missing
	switch m.kind {
	case .None:
		text_colored(palette.dim, "None")
	case .Discrete:
		b := strings.builder_make(context.temp_allocator)
		for i in 0 ..< m.count {
			if i > 0 { strings.write_string(&b, ", ") }
			fmt.sbprintf(&b, "%v", m.values[i])
		}
		text_colored(palette.missing, strings.to_string(b))
	case .Range:
		text_colored(palette.missing, fmt.tprintf("%v thru %v", m.values[0], m.values[1]))
	case .Range_And_Discrete:
		text_colored(palette.missing, fmt.tprintf("%v thru %v, %v", m.values[0], m.values[1], m.values[2]))
	}
}

@(private = "file")
draw_measure :: proc(m: sav.Measure) {
	switch m {
	case .Scale:   text_colored(palette.accent, "◆ Scale")
	case .Ordinal: text_colored(palette.ok, "▲ Ordinal")
	case .Nominal: text_colored(palette.missing, "● Nominal")
	case .Unknown: text_colored(palette.dim, "Unknown")
	}
}

@(private = "file")
draw_syntax :: proc(app: ^App) {
	defer im.End()
	if !im.Begin(WIN_SYNTAX) { return }

	if im.Button("▶ Run  (Ctrl+Enter)") { run_editor(app) }
	im.SameLine()
	text_colored(palette.dim, "GET SAVE COMPUTE SELECT IF FILTER WEIGHT SORT CASES SPLIT FILE TEMPORARY · FREQUENCIES DESCRIPTIVES CROSSTABS MEANS T-TEST ONEWAY")

	im.PushFontFloat(app.fonts.mono, 0)
	im.PushStyleColorImVec4(.FrameBg, palette.bg)
	size := im.GetContentRegionAvail()
	im.InputTextMultiline("##syntax", cstring(&app.syntax_buf[0]), len(app.syntax_buf), size, {.AllowTabInput})
	im.PopStyleColor()
	im.PopFont()
}

@(private = "file")
draw_output :: proc(app: ^App) {
	defer im.End()
	if !im.Begin(WIN_OUTPUT) { return }

	items := app.session.items[:]
	if im.BeginChild("##outline", {200, 0}, {.ResizeX, .Borders}) {
		text_colored(palette.dim, "OUTLINE")
		for item, i in items {
			label: string
			switch v in item {
			case output.Table:
				label = fmt.tprintf("■ %s", v.title)
			case output.Text:
				if v.kind == .Note { continue }
				label = fmt.tprintf("%s %s", "×" if v.kind == .Error else "•", first_line(v.text, 40))
			}
			if im.Selectable(cstr(fmt.tprintf("%s##o%d", label, i))) { app.output_focus = i }
		}
	}
	im.EndChild()
	im.SameLine()

	if im.BeginChild("##items") {
		// Items scrolled out of view are replaced by a spacer of their last measured height.
		for len(app.item_heights) < len(items) { append(&app.item_heights, 0) }
		if len(app.item_heights) > len(items) { resize(&app.item_heights, len(items)) }
		for &item, i in items {
			if app.output_focus == i {
				im.SetScrollHereY(0)
				app.output_focus = -1
			}
			h := app.item_heights[i]
			if h > 0 && !im.IsRectVisibleBySize({1, h}) {
				im.Dummy({1, h})
				continue
			}
			start := im.GetCursorPosY()
			im.PushIDInt(i32(i))
			switch &v in item {
			case output.Table: draw_pivot_table(app, i, &v)
			case output.Text:  draw_output_text(&v)
			}
			im.PopID()
			app.item_heights[i] = im.GetCursorPosY() - start
		}
	}
	im.EndChild()
}

@(private = "file")
first_line :: proc(s: string, max_len: int) -> string {
	line := s
	if i := strings.index_byte(line, '\n'); i >= 0 { line = line[:i] }
	return line if len(line) <= max_len else fmt.tprintf("%s…", line[:max_len])
}

@(private = "file")
draw_output_text :: proc(t: ^output.Text) {
	switch t.kind {
	case .Heading:
		im.Dummy({0, 4})
		text_colored(palette.accent, t.text)
	case .Note:
		im.PushFontFloat(nil, 0)
		text_colored(palette.dim, t.text)
		im.PopFont()
	case .Warning, .Error:
		col := palette.error if t.kind == .Error else palette.missing
		im.PushStyleColorImVec4(.ChildBg, {col.x, col.y, col.z, 0.08})
		flags := im.ChildFlags{.AutoResizeY, .Borders}
		if im.BeginChild("##msg", {0, 0}, flags) {
			text_colored(col, "Error" if t.kind == .Error else "Warning")
			im.PushTextWrapPos(0)
			im.TextUnformatted(cstr(t.text))
			im.PopTextWrapPos()
		}
		im.EndChild()
		im.PopStyleColor()
	}
	im.Dummy({0, 6})
}

// Renders a table from its cached layout: repeated outer labels are suppressed so groups
// read like merged cells; numbers are right-aligned like SPSS.
@(private = "file")
draw_pivot_table :: proc(app: ^App, index: int, t: ^output.Table) {
	l := cached_layout(app, index, t)

	text_colored(palette.text, l.title)
	im.SameLine(0, 12)
	if im.SmallButton("Copy") {
		im.SetClipboardText(cstr(output.to_tsv(t, context.temp_allocator)))
	}
	if im.IsItemHovered() { im.SetTooltip("Copy as tab-separated text (pastes into spreadsheets)") }
	for c in l.captions { text_colored(palette.dim, c) }
	// Single-category layers (e.g. CROSSTABS "Count") are shown as a subtitle.
	if len(l.layer) > 0 { text_colored(palette.dim, strings.join(l.layer, " / ", context.temp_allocator)) }

	n_cols := l.row_depth + len(l.cols)
	// ScrollX keeps columns at their natural width (scrolling when the pane is narrow); it
	// needs an explicit height, so size the table to its rows.
	flags := im.TableFlags_BordersOuter | im.TableFlags_BordersInnerH | im.TableFlags_SizingFixedFit |
		im.TableFlags_RowBg | im.TableFlags_ScrollX
	row_h := im.GetTextLineHeight() + 2 * im.GetStyle().CellPadding.y
	height := f32(l.col_depth + len(l.rows)) * row_h + im.GetStyle().ScrollbarSize + 4
	if n_cols <= 512 && im.BeginTable("##pivot", i32(n_cols), flags, {0, height}) {
		defer im.EndTable()
		for level in 0 ..< l.col_depth {
			// A plain row (not .Headers) so header text counts toward column auto-fit.
			im.TableNextRow()
			im.TableSetBgColor(.RowBg0, im.GetColorU32ImVec4(palette.header))
			for _ in 0 ..< l.row_depth { im.TableNextColumn() }
			for c, ci in l.cols {
				im.TableNextColumn()
				if level >= len(c) || (ci > 0 && output.same_band(l.cols[ci - 1], c, level)) { continue }
				text_colored(palette.dim, fmt.tprintf("%s%s", c[level], l.col_marks[c[level]]))
			}
		}
		clipper: im.ListClipper
		im.ListClipper_Begin(&clipper, i32(len(l.rows)))
		defer im.ListClipper_End(&clipper)
		for im.ListClipper_Step(&clipper) {
			for ri in int(clipper.DisplayStart) ..< int(clipper.DisplayEnd) {
				r := l.rows[ri]
				im.TableNextRow()
				for level in 0 ..< l.row_depth {
					im.TableNextColumn()
					if level >= len(r) || (ri > 0 && output.same_band(l.rows[ri - 1], r, level)) { continue }
					im.TextUnformatted(cstr(fmt.tprintf("%s%s", r[level], l.row_marks[r[level]])))
				}
				for _, ci in l.cols {
					im.TableNextColumn()
					slot := ri * len(l.cols) + ci
					cell := l.cells[slot]
					if cell == nil { continue }
					text := cstr(l.texts[slot])
					w := im.CalcTextSize(text).x
					avail := im.GetContentRegionAvail().x
					if cell.has_value && avail > w { im.SetCursorPosX(im.GetCursorPosX() + avail - w) }
					im.TextUnformatted(text)
				}
			}
		}
	}
	for note, k in l.notes {
		text_colored(palette.dim, fmt.tprintf("%c. %s", 'a' + rune(k), note))
	}
	im.Dummy({0, 12})
}
Palette_Command :: struct {
	name:     string,
	shortcut: string,
	run:      proc(app: ^App),
}

PALETTE_COMMANDS := [?]Palette_Command {
	{"Open data file…", "Ctrl+O", proc(app: ^App) { show_open_dialog(app) }},
	{"Save data", "Ctrl+S", proc(app: ^App) { save_or_ask(app) }},
	{"Save data as…", "Ctrl+Shift+S", proc(app: ^App) { show_save_dialog(app) }},
	{"Export output (HTML / XLSX / CSV)…", "Ctrl+E", proc(app: ^App) { show_export_dialog(app) }},
	{"Load demo dataset", "", proc(app: ^App) { load_demo_dataset(app) }},
	{"Run all syntax", "Ctrl+Enter", proc(app: ^App) { run_editor(app) }},
	{"Toggle value labels", "Ctrl+L", proc(app: ^App) { app.show_labels = !app.show_labels }},
	{"Toggle light/dark theme", "Ctrl+Shift+T", proc(app: ^App) { toggle_theme(app) }},
	{"Theme: follow system", "", proc(app: ^App) { set_theme_mode(app, .System) }},
	{"Theme: light", "", proc(app: ^App) { set_theme_mode(app, .Light) }},
	{"Theme: dark", "", proc(app: ^App) { set_theme_mode(app, .Dark) }},
	{"Reset layout", "", proc(app: ^App) { app.reset_layout = true }},
	{"Clear output", "", proc(app: ^App) { engine.clear_output(&app.session) }},
	{"Show ImGui demo", "", proc(app: ^App) { app.show_demo = true }},
	{"Quit", "Ctrl+Q", proc(app: ^App) { app.running = false }},
}

@(private = "file")
draw_command_palette :: proc(app: ^App) {
	if app.palette_open {
		im.OpenPopup("##palette")
		app.palette_open = false
		app.palette_query = {}
		app.palette_cursor = 0
	}
	vp := im.GetMainViewport()
	im.SetNextWindowPos({vp.WorkPos.x + vp.WorkSize.x * 0.5, vp.WorkPos.y + 80}, .Always, {0.5, 0})
	im.SetNextWindowSize({560, 0})
	if !im.BeginPopupModal("##palette", nil, {.NoTitleBar, .NoResize, .NoMove, .NoSavedSettings}) { return }
	defer im.EndPopup()

	if im.IsWindowAppearing() { im.SetKeyboardFocusHere() }
	im.SetNextItemWidth(-1)
	im.InputTextWithHint("##q", "Type a command…", cstring(&app.palette_query[0]), len(app.palette_query))
	query := string(cstring(&app.palette_query[0]))

	matches: [len(PALETTE_COMMANDS)]int
	n := 0
	for c, i in PALETTE_COMMANDS {
		if query == "" || strings.contains(strings.to_lower(c.name, context.temp_allocator), strings.to_lower(query, context.temp_allocator)) {
			matches[n] = i
			n += 1
		}
	}
	if im.IsKeyPressed(.DownArrow) { app.palette_cursor = min(app.palette_cursor + 1, n - 1) }
	if im.IsKeyPressed(.UpArrow) { app.palette_cursor = max(app.palette_cursor - 1, 0) }
	app.palette_cursor = clamp(app.palette_cursor, 0, max(n - 1, 0))

	run := -1
	for k in 0 ..< n {
		c := PALETTE_COMMANDS[matches[k]]
		if im.Selectable(cstr(c.name), k == app.palette_cursor) { run = matches[k] }
		if c.shortcut != "" {
			w := im.CalcTextSize(cstr(c.shortcut)).x
			im.SameLine(im.GetWindowWidth() - w - 20)
			text_colored(palette.dim, c.shortcut)
		}
	}
	if n > 0 && (im.IsKeyPressed(.Enter) || im.IsKeyPressed(.KeypadEnter)) { run = matches[app.palette_cursor] }
	if run >= 0 || im.IsKeyPressed(.Escape) {
		im.CloseCurrentPopup()
		if run >= 0 { PALETTE_COMMANDS[run].run(app) }
	}
}
