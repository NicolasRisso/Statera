package engine

import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

import "../io/sav"
import "../procs"
import "../transform"

@(private)
Command :: struct {
	name:      string,
	second:    string, // second keyword of two-word commands (SELECT IF, SPLIT FILE, SORT CASES)
	run:       proc(s: ^Session, c: ^Cmd) -> bool,
	procedure: bool,   // reads the data: ends TEMPORARY
}

@(private)
COMMANDS := [?]Command {
	{name = "COMPUTE", run = cmd_compute},
	{name = "CROSSTABS", run = cmd_crosstabs, procedure = true},
	{name = "DESCRIPTIVES", run = cmd_descriptives, procedure = true},
	{name = "EXECUTE", run = proc(s: ^Session, c: ^Cmd) -> bool { return true }, procedure = true},
	{name = "FILTER", run = cmd_filter},
	{name = "FREQUENCIES", run = cmd_frequencies, procedure = true},
	{name = "GET", run = cmd_get},
	{name = "SAVE", run = cmd_save, procedure = true},
	{name = "SELECT", second = "IF", run = cmd_select_if},
	{name = "SORT", second = "CASES", run = cmd_sort_cases},
	{name = "SPLIT", second = "FILE", run = cmd_split_file},
	{name = "TEMPORARY", run = cmd_temporary},
	{name = "WEIGHT", run = cmd_weight},
}

@(private)
cmd_get :: proc(s: ^Session, c: ^Cmd) -> bool {
	path := parse_file_spec(c, "FILE") or_return
	arena := new_arena()
	file, err := sav.read_file(path, virtual.arena_allocator(arena))
	if err != nil {
		free_arena(arena)
		e := err.(sav.Read_Error)
		if e.kind == .Io { return fail(c, "cannot open %s", path) }
		return fail(c, "%s is not a readable SPSS data file (%v at byte %d)", path, e.kind, e.offset)
	}
	set_dataset(s, file, arena, filepath.base(path))
	return true
}

@(private)
cmd_save :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	path := parse_file_spec(c, "OUTFILE") or_return
	compression := sav.Compression.Bytecode
	for accept_kind(c, .Slash) {
		switch {
		case accept_keyword(c, "COMPRESSED"):   compression = .Bytecode
		case accept_keyword(c, "UNCOMPRESSED"): compression = .None
		case:                                   return fail(c, "unsupported subcommand")
		}
	}
	file, _ := active(s)
	data, err := sav.write(file, compression, context.temp_allocator)
	if err != nil { return fail(c, "cannot encode the dataset") }
	if os.write_entire_file(path, data) != nil { return fail(c, "cannot write %s", path) }
	return true
}

@(private)
parse_expression :: proc(c: ^Cmd, file: ^sav.File) -> (expr: ^transform.Node, ok: bool) {
	perr: Maybe(transform.Parse_Error)
	{
		context.allocator = context.temp_allocator
		expr, perr = transform.parse(c.toks[c.pos:], file)
	}
	if e, failed := perr.?; failed {
		return nil, fail(c, "%s (line %d, column %d)", e.message, e.token.line, e.token.col)
	}
	c.pos = len(c.toks)
	return expr, true
}

@(private)
report_warnings :: proc(c: ^Cmd, warnings: transform.Warnings) {
	if n := warnings[.Division_By_Zero]; n > 0 {
		warn(c, "Warning # 511. A division by zero was attempted in %d case(s); the result was set to system-missing.", n)
	}
	if n := warnings[.Sqrt_Negative]; n > 0 {
		warn(c, "Warning # 603. The argument to SQRT was negative in %d case(s); the result was set to system-missing.", n)
	}
	if n := warnings[.Log_Domain]; n > 0 {
		warn(c, "The argument to LN or LG10 was not positive in %d case(s); the result was set to system-missing.", n)
	}
}

@(private)
cmd_compute :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	target, ok := peek(c)
	if !ok || target.kind != .Identifier { return fail(c, "expected a target variable name") }
	c.pos += 1
	if !accept_kind(c, .Equals) { return fail(c, "expected '=' after the target variable") }

	file, _ := active(s)
	expr := parse_expression(c, file) or_return

	idx := transform.find_variable(file, target.text)
	if idx < 0 {
		da := active_allocator(s)
		v := sav.Variable {
			name    = strings.clone(target.text, da),
			print   = {type = 5, width = 8, decimals = 2},
			write   = {type = 5, width = 8, decimals = 2},
			measure = .Scale,
		}
		v.numbers = make([dynamic]f64, file.n_cases, da)
		append(&file.variables, v)
		idx = len(file.variables) - 1
	} else if file.variables[idx].width > 0 {
		return fail(c, "string targets are not supported yet")
	}

	// Evaluate every case before storing, so the target's old values feed the expression.
	results := make([]f64, file.n_cases, context.temp_allocator)
	warnings: transform.Warnings
	for row in 0 ..< file.n_cases {
		results[row] = transform.eval(expr, file, row, &warnings)
	}
	copy(file.variables[idx].numbers[:], results)
	report_warnings(c, warnings)
	return true
}

@(private)
cmd_select_if :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	file, _ := active(s)
	expr := parse_expression(c, file) or_return
	keep := make([]bool, file.n_cases, context.temp_allocator)
	warnings: transform.Warnings
	kept := 0
	for row in 0 ..< file.n_cases {
		x := transform.eval(expr, file, row, &warnings)
		keep[row] = x != transform.SYSMIS && x != 0
		if keep[row] { kept += 1 }
	}
	report_warnings(c, warnings)
	for &v in file.variables {
		n := 0
		for row in 0 ..< file.n_cases {
			if !keep[row] { continue }
			if v.width == 0 { v.numbers[n] = v.numbers[row] } else { v.strings[n] = v.strings[row] }
			n += 1
		}
		if v.width == 0 { resize(&v.numbers, kept) } else { resize(&v.strings, kept) }
	}
	file.n_cases = kept
	return true
}

@(private)
cmd_temporary :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	begin_temporary(s)
	return true
}

@(private)
cmd_weight :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	file, _ := active(s)
	if accept_keyword(c, "OFF") {
		file.weight = -1
		return true
	}
	if !accept_keyword(c, "BY") { return fail(c, "expected BY or OFF") }
	vars := parse_varlist(c) or_return
	if len(vars) != 1 { return fail(c, "WEIGHT takes exactly one numeric variable") }
	file.weight = vars[0]
	return true
}

@(private)
cmd_filter :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	_, st := active(s)
	if accept_keyword(c, "OFF") {
		st.filter = -1
		return true
	}
	if !accept_keyword(c, "BY") { return fail(c, "expected BY or OFF") }
	vars := parse_varlist(c) or_return
	if len(vars) != 1 { return fail(c, "FILTER takes exactly one numeric variable") }
	st.filter = vars[0]
	return true
}

@(private)
cmd_split_file :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	_, st := active(s)
	if accept_keyword(c, "OFF") {
		st.n_split, st.split_mode = 0, .Off
		return true
	}
	mode := procs.Split_Mode.Layered
	if accept_keyword(c, "SEPARATE") {
		mode = .Separate
	} else {
		accept_keyword(c, "LAYERED")
	}
	if !accept_keyword(c, "BY") { return fail(c, "expected BY") }
	vars := parse_varlist(c) or_return
	if len(vars) > MAX_SPLIT { return fail(c, "at most %d split variables are allowed", MAX_SPLIT) }
	st.n_split, st.split_mode = len(vars), mode
	copy(st.split[:], vars[:])
	return true
}

@(private)
Sort_Key :: struct {
	var:        int,
	descending: bool,
}

@(private)
cmd_sort_cases :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	accept_keyword(c, "BY")
	file, _ := active(s)
	keys := make([dynamic]Sort_Key, context.temp_allocator)
	for !at_end(c) {
		vars := parse_varlist(c, numeric_only = false) or_return
		descending := false
		if accept_kind(c, .L_Paren) {
			switch {
			case accept_keyword(c, "A"): descending = false
			case accept_keyword(c, "D"): descending = true
			case:                        return fail(c, "expected (A) or (D)")
			}
			if !accept_kind(c, .R_Paren) { return fail(c, "expected )") }
		}
		for v in vars { append(&keys, Sort_Key{v, descending}) }
	}
	if len(keys) == 0 { return fail(c, "no sort variables") }

	order := make([]int, file.n_cases, context.temp_allocator)
	for &o, i in order { o = i }
	// Stable sort by the keys; procs can't capture, so pass state through context.user_ptr.
	Sort_State :: struct {
		file: ^sav.File,
		keys: []Sort_Key,
	}
	state := Sort_State{file, keys[:]}
	context.user_ptr = &state
	slice.stable_sort_by(order, proc(a, b: int) -> bool {
		st := (^Sort_State)(context.user_ptr)
		for k in st.keys {
			v := &st.file.variables[k.var]
			c := 0
			if v.width == 0 {
				x, y := v.numbers[a], v.numbers[b]
				c = -1 if x < y else (1 if x > y else 0)
			} else {
				c = strings.compare(v.strings[a], v.strings[b])
			}
			if c != 0 { return (c > 0) if k.descending else (c < 0) }
		}
		return false
	})

	for &v in file.variables {
		if v.width == 0 {
			tmp := slice.clone(v.numbers[:], context.temp_allocator)
			for o, i in order { v.numbers[i] = tmp[o] }
		} else {
			tmp := slice.clone(v.strings[:], context.temp_allocator)
			for o, i in order { v.strings[i] = tmp[o] }
		}
	}
	return true
}

@(private)
parse_stat_keywords :: proc(c: ^Cmd, $T: typeid, names: []struct {
		word: string,
		stat: T,
	}) -> (stats: T, any_named: bool, ok: bool) {
	for !at_subcommand_end(c) {
		t, _ := peek(c)
		found := false
		for n in names {
			if accept_keyword(c, n.word) {
				stats += n.stat
				found, any_named = true, true
				break
			}
		}
		if !found { return stats, any_named, fail(c, "unknown statistic %s", t.text) }
	}
	return stats, any_named, true
}

@(private)
cmd_descriptives :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	if accept_keyword(c, "VARIABLES") { accept_kind(c, .Equals) }
	vars := parse_varlist(c) or_return
	stats := procs.DESC_DEFAULT
	for accept_kind(c, .Slash) {
		if !accept_keyword(c, "STATISTICS") { return fail(c, "unsupported subcommand") }
		accept_kind(c, .Equals)
		names := [?]struct {
			word: string,
			stat: procs.Desc_Stats,
		}{
			{"DEFAULT", procs.DESC_DEFAULT}, {"ALL", procs.DESC_ALL}, {"MEAN", {.Mean}}, {"SEMEAN", {.Semean}},
			{"STDDEV", {.Stddev}}, {"VARIANCE", {.Variance}}, {"RANGE", {.Range}}, {"MIN", {.Min}},
			{"MAX", {.Max}}, {"SUM", {.Sum}}, {"SKEWNESS", {.Skewness}}, {"KURTOSIS", {.Kurtosis}},
		}
		named, any_named := parse_stat_keywords(c, procs.Desc_Stats, names[:]) or_return
		stats = named if any_named else procs.DESC_DEFAULT
	}
	ctx := make_context(c)
	procs.descriptives(&ctx, vars[:], stats, &s.items)
	return true
}

@(private)
cmd_crosstabs :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	pairs := make([dynamic]procs.Xtab_Pair, context.temp_allocator)
	opts: procs.Xtab_Options
	first := true
	for !at_end(c) {
		slash := accept_kind(c, .Slash)
		switch {
		case accept_keyword(c, "TABLES") || (first && !slash):
			accept_kind(c, .Equals)
			rows := parse_varlist(c) or_return
			if !accept_keyword(c, "BY") { return fail(c, "expected BY in the table list") }
			cols := parse_varlist(c) or_return
			if t, ok := peek(c); ok && t.kind == .Keyword && strings.equal_fold(t.text, "BY") {
				return fail(c, "layer variables (a second BY) are not implemented yet")
			}
			for r in rows {
				for col in cols { append(&pairs, procs.Xtab_Pair{r, col}) }
			}
		case accept_keyword(c, "CELLS"):
			accept_kind(c, .Equals)
			names := [?]struct {
				word: string,
				stat: procs.Xtab_Cells,
			}{
				{"COUNT", {.Count}}, {"EXPECTED", {.Expected}}, {"ROW", {.Row}}, {"COLUMN", {.Column}},
				{"TOTAL", {.Total}}, {"ALL", {.Count, .Expected, .Row, .Column, .Total}}, {"NONE", {}},
			}
			opts.cells, _ = parse_stat_keywords(c, procs.Xtab_Cells, names[:]) or_return
		case accept_keyword(c, "STATISTICS"):
			accept_kind(c, .Equals)
			names := [?]struct {
				word: string,
				stat: procs.Xtab_Stats,
			}{{"CHISQ", {.Chisq}}, {"PHI", {.Phi}}, {"CC", {.Cc}}, {"NONE", {}}}
			opts.stats, _ = parse_stat_keywords(c, procs.Xtab_Stats, names[:]) or_return
		case:
			t, _ := peek(c)
			return fail(c, "subcommand %s is not implemented yet", t.text)
		}
		first = false
	}
	if len(pairs) == 0 { return fail(c, "no table list (TABLES = rows BY columns)") }
	ctx := make_context(c)
	procs.crosstabs(&ctx, pairs[:], opts, &s.items)
	return true
}

@(private)
cmd_frequencies :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	if accept_keyword(c, "VARIABLES") { accept_kind(c, .Equals) }
	vars := parse_varlist(c) or_return
	opts: procs.Freq_Options
	for accept_kind(c, .Slash) {
		switch {
		case accept_keyword(c, "FORMAT"):
			accept_kind(c, .Equals)
			for !at_subcommand_end(c) {
				t, _ := peek(c)
				if accept_keyword(c, "NOTABLE") {
					opts.no_table = true
				} else {
					c.pos += 1
					warn(c, "FORMAT keyword %s is not implemented yet and was ignored", t.text)
				}
			}
		case accept_keyword(c, "STATISTICS"):
			accept_kind(c, .Equals)
			names := [?]struct {
				word: string,
				stat: procs.Freq_Stats,
			}{
				{"DEFAULT", procs.FREQ_DEFAULT}, {"ALL", procs.FREQ_ALL}, {"NONE", {}}, {"MEAN", {.Mean}},
				{"SEMEAN", {.Semean}}, {"MEDIAN", {.Median}}, {"MODE", {.Mode}}, {"STDDEV", {.Stddev}},
				{"VARIANCE", {.Variance}}, {"SKEWNESS", {.Skewness}}, {"SESKEW", {.Seskew}},
				{"KURTOSIS", {.Kurtosis}}, {"SEKURT", {.Sekurt}}, {"RANGE", {.Range}},
				{"MINIMUM", {.Min}}, {"MAXIMUM", {.Max}}, {"SUM", {.Sum}},
			}
			named, any_named := parse_stat_keywords(c, procs.Freq_Stats, names[:]) or_return
			opts.stats = named if any_named else procs.FREQ_DEFAULT
		case:
			t, _ := peek(c)
			return fail(c, "subcommand %s is not implemented yet", t.text)
		}
	}
	ctx := make_context(c)
	procs.frequencies(&ctx, vars[:], opts, &s.items)
	return true
}
