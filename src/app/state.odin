package app

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem/virtual"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:time"

import "../io/sav"
import "../syntax"

Output_Kind :: enum u8 {
	Info,
	Table,
	Error,
}

Output_Item :: struct {
	kind:     Output_Kind,
	title:    string,
	subtitle: string,
	text:     string,
	columns:  []string,
	rows:     [][]string,
}

App :: struct {
	theme:          Theme, // resolved from prefs.theme_mode
	prefs:          Prefs,
	fonts:          Fonts,
	dpi:            f32,
	running:        bool,

	data_arena:     virtual.Arena,
	data:           sav.File,
	data_name:      string,
	show_labels:    bool,
	selected_var:   int,

	syntax_buf:     [64 * 1024]u8,

	out_arena:      virtual.Arena,
	output:         [dynamic]Output_Item,
	output_focus:   int, // item to scroll to, -1 for none

	palette_open:   bool,
	palette_query:  [128]u8,
	palette_cursor: int,
	reset_layout:   bool,
	show_demo:      bool,

	open_lock:      sync.Mutex,
	pending_open:   string, // set by the file dialog thread
}

DEFAULT_SYNTAX :: `* OpenSPSS syntax editor. Ctrl+Enter checks the syntax.
* The engine that runs commands is under construction (see docs/PLAN.md).
GET FILE='survey.sav'.
COMPUTE income_k = income / 1000.
FREQUENCIES VARIABLES=group region
  /STATISTICS=MODE.
DESCRIPTIVES age score income_k /STATISTICS=MEAN STDDEV MIN MAX.
CROSSTABS /TABLES=group BY region /STATISTICS=CHISQ.
`

app_init :: proc(app: ^App) {
	app.show_labels = true
	app.output_focus = -1
	app.running = true
	copy(app.syntax_buf[:], DEFAULT_SYNTAX)
	load_demo_dataset(app)
}

out_alloc :: proc(app: ^App) -> runtime.Allocator {
	return virtual.arena_allocator(&app.out_arena)
}

log_info :: proc(app: ^App, title, text: string) {
	context.allocator = out_alloc(app)
	append(&app.output, Output_Item{kind = .Info, title = strings.clone(title), subtitle = timestamp(), text = strings.clone(text)})
	app.output_focus = len(app.output) - 1
}

log_error :: proc(app: ^App, title, text: string) {
	context.allocator = out_alloc(app)
	append(&app.output, Output_Item{kind = .Error, title = strings.clone(title), subtitle = timestamp(), text = strings.clone(text)})
	app.output_focus = len(app.output) - 1
}

// Copies the strings into a slice owned by context.allocator (slice literals live on the stack).
strs :: proc(items: ..string) -> []string {
	return slice.clone(items)
}

@(private = "file")
timestamp :: proc() -> string {
	h, m, s := time.clock(time.now())
	return fmt.aprintf("%02d:%02d:%02d", h, m, s)
}

reset_dataset :: proc(app: ^App) {
	virtual.arena_destroy(&app.data_arena)
	app.data_arena = {}
	app.data = {}
	app.selected_var = 0
}

open_dataset :: proc(app: ^App, path: string) {
	arena: virtual.Arena
	file, err := sav.read_file(path, virtual.arena_allocator(&arena))
	if err != nil {
		virtual.arena_destroy(&arena)
		e := err.(sav.Read_Error)
		log_error(app, "Could not open data file", fmt.tprintf("%s\n%v at byte %d", path, e.kind, e.offset))
		return
	}
	reset_dataset(app)
	app.data_arena = arena
	app.data = file
	app.data_name = strings.clone(filepath.base(path), virtual.arena_allocator(&app.data_arena))
	add_dataset_summary(app, path)
}

add_dataset_summary :: proc(app: ^App, source: string) {
	context.allocator = out_alloc(app)
	f := &app.data
	rows := make([][]string, 6)
	rows[0] = strs("Source", strings.clone(source))
	rows[1] = strs("Cases", fmt.aprintf("%d", f.n_cases))
	rows[2] = strs("Variables", fmt.aprintf("%d", len(f.variables)))
	rows[3] = strs("Compression", fmt.aprintf("%v", f.compression))
	rows[4] = strs("Encoding", strings.clone(f.encoding if f.encoding != "" else "-"))
	rows[5] = strs("Weight", strings.clone(f.variables[f.weight].name if f.weight >= 0 else "none"))
	append(&app.output, Output_Item {
		kind     = .Table,
		title    = fmt.aprintf("Dataset: %s", app.data_name),
		subtitle = timestamp(),
		columns  = strs("Property", "Value"),
		rows     = rows,
	})
	app.output_focus = len(app.output) - 1
}

// Runs the syntax through the lexer and reports one row per command.
check_syntax :: proc(app: ^App) {
	src := string(cstring(&app.syntax_buf[0]))
	tokens, err := syntax.tokenize(src, context.temp_allocator)
	if e, failed := err.?; failed {
		log_error(app, "Syntax error", fmt.tprintf("line %d, column %d: %s", e.line, e.col, e.message))
		return
	}

	context.allocator = out_alloc(app)
	rows: [dynamic][]string
	start := 0
	for tok, i in tokens {
		if tok.kind != .End_Command { continue }
		if i > start {
			first := tokens[start]
			name := strings.to_upper(first.text)
			if start + 1 < i && tokens[start + 1].kind == .Identifier && is_two_word_command(name, tokens[start + 1].text) {
				name = fmt.aprintf("%s %s", name, strings.to_upper(tokens[start + 1].text))
			}
			append(&rows, strs(fmt.aprintf("%d", first.line), name, fmt.aprintf("%d", i - start), "parsed"))
		}
		start = i + 1
	}
	append(&app.output, Output_Item {
		kind     = .Table,
		title    = "Syntax check",
		subtitle = fmt.aprintf("%s · %d commands · engine not implemented yet", timestamp(), len(rows)),
		columns  = strs("Line", "Command", "Tokens", "Status"),
		rows     = rows[:],
	})
	app.output_focus = len(app.output) - 1
}

@(private = "file")
is_two_word_command :: proc(first, second: string) -> bool {
	switch first {
	case "GET", "SAVE", "DATA", "VARIABLE", "VALUE", "MISSING", "SORT", "SPLIT", "SELECT", "MATCH", "ADD", "DO", "END", "BEGIN", "T-TEST", "NPAR", "LOGISTIC", "QUICK", "DATASET", "OUTPUT":
		return true
	}
	return false
}

request_open :: proc(app: ^App, path: string) {
	sync.mutex_lock(&app.open_lock)
	defer sync.mutex_unlock(&app.open_lock)
	app.pending_open = strings.clone(path, context.allocator)
}

take_pending_open :: proc(app: ^App) -> (path: string, ok: bool) {
	sync.mutex_lock(&app.open_lock)
	defer sync.mutex_unlock(&app.open_lock)
	path, app.pending_open = app.pending_open, ""
	return path, path != ""
}

// A synthetic survey large enough to exercise the virtualized grid.
load_demo_dataset :: proc(app: ^App) {
	N :: 250_000
	reset_dataset(app)
	context.allocator = virtual.arena_allocator(&app.data_arena)
	f := &app.data
	f.n_cases = N
	f.weight = -1
	f.sysmis = sav.SYSMIS
	f.encoding = "UTF-8"
	f.compression = .Bytecode
	app.data_name = "survey (demo)"

	F :: proc(w, d: u8) -> sav.Format { return {type = 5, width = w, decimals = d} }
	add :: proc(f: ^sav.File, name, label: string, measure: sav.Measure, format: sav.Format) -> ^sav.Variable {
		append(&f.variables, sav.Variable{name = name, label = label, measure = measure, print = format, write = format})
		return &f.variables[len(f.variables) - 1]
	}

	id := add(f, "id", "Respondent ID", .Nominal, F(8, 0))
	group := add(f, "group", "Experimental group", .Nominal, F(1, 0))
	append(&group.value_labels, sav.Value_Label{value = 1, label = "Control"}, sav.Value_Label{value = 2, label = "Treatment A"}, sav.Value_Label{value = 3, label = "Treatment B"})
	region := add(f, "region", "Region", .Nominal, F(1, 0))
	append(&region.value_labels, sav.Value_Label{value = 1, label = "North"}, sav.Value_Label{value = 2, label = "Northeast"}, sav.Value_Label{value = 3, label = "Center-West"}, sav.Value_Label{value = 4, label = "Southeast"}, sav.Value_Label{value = 5, label = "South"})
	age := add(f, "age", "Age in years", .Scale, F(3, 0))
	satisfaction := add(f, "satisfaction", "Overall satisfaction", .Ordinal, F(1, 0))
	append(&satisfaction.value_labels, sav.Value_Label{value = 1, label = "Very dissatisfied"}, sav.Value_Label{value = 2, label = "Dissatisfied"}, sav.Value_Label{value = 3, label = "Neutral"}, sav.Value_Label{value = 4, label = "Satisfied"}, sav.Value_Label{value = 5, label = "Very satisfied"}, sav.Value_Label{value = 9, label = "No answer"})
	satisfaction.missing = {kind = .Discrete, count = 1, values = {9, 0, 0}}
	score := add(f, "score", "Test score", .Scale, F(6, 2))
	income := add(f, "income", "Monthly income (BRL)", .Scale, F(10, 2))

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
	for &v in f.variables { v.n_segments = 1 }
	add_dataset_summary(app, "generated in memory")
}
