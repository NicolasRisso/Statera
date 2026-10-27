package app

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:sync"

import "../engine"
import "../io/sav"
import "../output"

App :: struct {
	theme:          Theme, // resolved from prefs.theme_mode
	prefs:          Prefs,
	fonts:          Fonts,
	dpi:            f32,
	running:        bool,

	session:        engine.Session, // active dataset + output document
	show_labels:    bool,
	selected_var:   int,

	syntax_buf:     [64 * 1024]u8,
	output_focus:   int, // item to scroll to, -1 for none
	layouts:        [dynamic]Cached_Layout, // per output item, rebuilt only when it changes
	item_heights:   [dynamic]f32,           // last drawn height per output item (for clipping)
	layout_arena:   virtual.Arena,

	palette_open:   bool,
	palette_query:  [128]u8,
	palette_cursor: int,
	reset_layout:   bool,
	show_demo:      bool,

	open_lock:      sync.Mutex,
	pending_open:   string,      // set by a file dialog thread
	pending_action: File_Action,
	data_path:      string,      // where Ctrl+S saves; empty until opened or saved
}

DEFAULT_SYNTAX :: `* Statera syntax editor. Ctrl+Enter runs everything against the active dataset.
COMPUTE income_k = income / 1000.
COMPUTE high_score = score >= 80.
CROSSTABS /TABLES=group BY high_score /CELLS=COUNT ROW EXPECTED /STATISTICS=CHISQ PHI.
MEANS TABLES=score income_k BY group /STATISTICS=ANOVA.
T-TEST GROUPS=group(1 2) /VARIABLES=score age.
ONEWAY score BY group /STATISTICS=DESCRIPTIVES HOMOGENEITY WELCH.
SORT CASES BY group.
SPLIT FILE LAYERED BY group.
DESCRIPTIVES age score income_k /STATISTICS=MEAN STDDEV MIN MAX SKEWNESS.
SPLIT FILE OFF.
TEMPORARY.
SELECT IF (age < 30).
FREQUENCIES VARIABLES=satisfaction /STATISTICS=MEDIAN MODE.
`

app_init :: proc(app: ^App) {
	app.show_labels = true
	app.output_focus = -1
	app.running = true
	copy(app.syntax_buf[:], DEFAULT_SYNTAX)
	load_demo_dataset(app)
}

data :: proc(app: ^App) -> ^sav.File {
	return &app.session.data
}

Cached_Layout :: struct {
	cells:  rawptr, // identity of the table's cell storage
	count:  int,
	layout: output.Layout,
}

// Pivot layouts are expensive to rebuild every frame; output items only ever get appended
// (or all cleared), so cache by index and validate against the table's cell storage.
cached_layout :: proc(app: ^App, index: int, t: ^output.Table) -> ^output.Layout {
	if len(app.layouts) > len(app.session.items) {
		virtual.arena_destroy(&app.layout_arena)
		app.layout_arena = {}
		app.layouts = {}
	}
	alloc := virtual.arena_allocator(&app.layout_arena)
	if app.layouts == nil { app.layouts = make([dynamic]Cached_Layout, alloc) }
	for len(app.layouts) <= index { append(&app.layouts, Cached_Layout{}) }
	c := &app.layouts[index]
	if c.cells != raw_data(t.cells) || c.count != len(t.cells) {
		c^ = {cells = raw_data(t.cells), count = len(t.cells), layout = output.layout(t, alloc)}
	}
	return &c.layout
}

log_text :: proc(app: ^App, kind: output.Text_Kind, text: string) {
	context.allocator = engine.out_allocator(&app.session)
	engine.report(&app.session, kind, "", text)
	app.output_focus = len(app.session.items) - 1
}

// Runs syntax through the engine; the output pane scrolls to the first new item.
run_syntax :: proc(app: ^App, src: string) -> (errors: int) {
	first := len(app.session.items)
	errors = engine.run(&app.session, src)
	if len(app.session.items) > first { app.output_focus = first }
	return
}

run_editor :: proc(app: ^App) {
	run_syntax(app, string(cstring(&app.syntax_buf[0])))
}

// Opening a file goes through GET FILE, like a dialog in SPSS: the action is syntax.
open_dataset :: proc(app: ^App, path: string) {
	quoted, _ := strings.replace_all(path, "'", "''", context.temp_allocator)
	syntax := fmt.tprintf("GET FILE='%s'.", quoted)
	log_text(app, .Note, syntax)
	if run_syntax(app, syntax) == 0 {
		set_data_path(app, path)
		add_dataset_summary(app, path)
	}
}

add_dataset_summary :: proc(app: ^App, source: string) {
	context.allocator = engine.out_allocator(&app.session)
	f := data(app)
	t := output.Table{title = fmt.aprintf("Dataset: %s", app.session.data_name)}
	rows := [?][2]string {
		{"Source", source},
		{"Cases", fmt.tprintf("%d", f.n_cases)},
		{"Variables", fmt.tprintf("%d", len(f.variables))},
		{"Compression", fmt.tprintf("%v", f.compression)},
		{"Encoding", f.encoding if f.encoding != "" else "-"},
		{"Weight", f.variables[f.weight].name if f.weight >= 0 else "none"},
	}
	for r in rows {
		output.add_text(&t, {r[0]}, {"Value"}, r[1])
	}
	append(&app.session.items, t)
	app.output_focus = len(app.session.items) - 1
}

File_Action :: enum u8 {
	Open,
	Save_Data,
	Export_Output,
}

// Called from file-dialog threads; the main loop picks the request up with take_pending.
request_file :: proc(app: ^App, action: File_Action, path: string) {
	sync.mutex_lock(&app.open_lock)
	defer sync.mutex_unlock(&app.open_lock)
	app.pending_action = action
	app.pending_open = strings.clone(path, context.allocator)
}

take_pending :: proc(app: ^App) -> (action: File_Action, path: string, ok: bool) {
	sync.mutex_lock(&app.open_lock)
	defer sync.mutex_unlock(&app.open_lock)
	action, path, app.pending_open = app.pending_action, app.pending_open, ""
	return action, path, path != ""
}

save_dataset :: proc(app: ^App, path: string) {
	quoted, _ := strings.replace_all(path, "'", "''", context.temp_allocator)
	syntax := fmt.tprintf("SAVE OUTFILE='%s'.", quoted)
	log_text(app, .Note, syntax)
	if run_syntax(app, syntax) == 0 {
		set_data_path(app, path)
		log_text(app, .Note, fmt.tprintf("Saved %s", path))
	}
}

// Writes the output document; the format follows the file extension (HTML by default).
export_output :: proc(app: ^App, path: string) {
	items := app.session.items[:]
	lower := strings.to_lower(path, context.temp_allocator)
	data: []byte
	switch {
	case strings.has_suffix(lower, ".csv"):  data = transmute([]byte)output.to_csv(items, context.temp_allocator)
	case strings.has_suffix(lower, ".xlsx"): data = output.to_xlsx(items, context.temp_allocator)
	case:                                    data = transmute([]byte)output.to_html(items, "Statera output", context.temp_allocator)
	}
	if os.write_entire_file(path, data) != nil {
		log_text(app, .Error, fmt.tprintf("Could not write %s", path))
		return
	}
	log_text(app, .Note, fmt.tprintf("Output exported to %s", path))
}

set_data_path :: proc(app: ^App, path: string) {
	delete(app.data_path)
	app.data_path = strings.clone(path)
}

// A synthetic survey large enough to exercise the virtualized grid.
load_demo_dataset :: proc(app: ^App) {
	N :: 250_000
	arena := engine.new_arena()
	context.allocator = virtual.arena_allocator(arena)
	f := sav.File {
		n_cases     = N,
		weight      = -1,
		sysmis      = sav.SYSMIS,
		encoding    = "UTF-8",
		compression = .Bytecode,
		// Reserved up front: the ^Variable pointers below must survive later appends.
		variables   = make([dynamic]sav.Variable, 0, 16),
	}

	F :: proc(w, d: u8) -> sav.Format { return {type = 5, width = w, decimals = d} }
	add :: proc(f: ^sav.File, name, label: string, measure: sav.Measure, format: sav.Format) -> ^sav.Variable {
		append(&f.variables, sav.Variable{name = name, label = label, measure = measure, print = format, write = format, n_segments = 1})
		v := &f.variables[len(f.variables) - 1]
		v.numbers = make([dynamic]f64, 0, N)
		return v
	}
	label :: proc(v: ^sav.Variable, pairs: ..struct {
			value: f64,
			label: string,
		}) {
		for p in pairs { append(&v.value_labels, sav.Value_Label{value = p.value, label = p.label}) }
	}

	id := add(&f, "id", "Respondent ID", .Nominal, F(8, 0))
	group := add(&f, "group", "Experimental group", .Nominal, F(1, 0))
	label(group, {1, "Control"}, {2, "Treatment A"}, {3, "Treatment B"})
	region := add(&f, "region", "Region", .Nominal, F(1, 0))
	label(region, {1, "North"}, {2, "Northeast"}, {3, "Center-West"}, {4, "Southeast"}, {5, "South"})
	age := add(&f, "age", "Age in years", .Scale, F(3, 0))
	satisfaction := add(&f, "satisfaction", "Overall satisfaction", .Ordinal, F(1, 0))
	label(satisfaction, {1, "Very dissatisfied"}, {2, "Dissatisfied"}, {3, "Neutral"}, {4, "Satisfied"}, {5, "Very satisfied"}, {9, "No answer"})
	satisfaction.missing = {kind = .Discrete, count = 1, values = {9, 0, 0}}
	score := add(&f, "score", "Test score", .Scale, F(6, 2))
	income := add(&f, "income", "Monthly income (BRL)", .Scale, F(10, 2))

	r := rand.create(42)
	gen := rand.default_random_generator(&r)
	for i in 0 ..< N {
		g := f64(1 + rand.int_max(3, gen))
		append(&id.numbers, f64(i + 1))
		append(&group.numbers, g)
		append(&region.numbers, f64(1 + rand.int_max(5, gen)))
		append(&age.numbers, f64(18 + rand.int_max(63, gen)))
		append(&satisfaction.numbers, 9 if rand.float64(gen) < 0.03 else f64(1 + rand.int_max(5, gen)))
		s := 70 + 4 * (g - 1) + 12 * rand.norm_float64(gen)
		append(&score.numbers, sav.SYSMIS if rand.float64(gen) < 0.02 else math.round(s * 100) / 100)
		append(&income.numbers, math.round(math.exp(8.2 + 0.6 * rand.norm_float64(gen)) * 100) / 100)
	}
	engine.set_dataset(&app.session, f, arena, "survey (demo)")
	add_dataset_summary(app, "generated in memory")
}
