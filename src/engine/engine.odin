// Command engine: runs syntax against the active dataset and collects output items.
package engine

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../io/sav"
import "../output"
import "../procs"
import "../syntax"
import "../transform"

// Don't copy a Session: allocators inside its data point at its arenas.
Session :: struct {
	data_arena: ^virtual.Arena, // heap-allocated so the dataset's allocators keep a stable address
	data:       sav.File,
	data_name:  string,
	has_data:   bool,
	out_arena:  virtual.Arena,
	items:      [dynamic]output.Item,
}

data_allocator :: proc(s: ^Session) -> runtime.Allocator {
	return virtual.arena_allocator(s.data_arena)
}

// A fresh arena for building a dataset; hand it to set_dataset or free it with free_arena.
new_arena :: proc() -> ^virtual.Arena {
	return new(virtual.Arena, runtime.heap_allocator())
}

free_arena :: proc(a: ^virtual.Arena) {
	if a == nil { return }
	virtual.arena_destroy(a)
	free(a, runtime.heap_allocator())
}

out_allocator :: proc(s: ^Session) -> runtime.Allocator {
	return virtual.arena_allocator(&s.out_arena)
}

destroy :: proc(s: ^Session) {
	free_arena(s.data_arena)
	virtual.arena_destroy(&s.out_arena)
	s^ = {}
}

// Replaces the active dataset; `file` must have been allocated from `arena` (from new_arena).
set_dataset :: proc(s: ^Session, file: sav.File, arena: ^virtual.Arena, name: string) {
	free_arena(s.data_arena)
	s.data_arena = arena
	s.data = file
	s.data_name = strings.clone(name, data_allocator(s))
	s.has_data = true
}

clear_output :: proc(s: ^Session) {
	virtual.arena_destroy(&s.out_arena)
	s.out_arena = {}
	s.items = {}
}

// Runs every command in `src`. Returns the number of commands that failed.
run :: proc(s: ^Session, src: string) -> (errors: int) {
	context.allocator = out_allocator(s)
	if s.items == nil { s.items = make([dynamic]output.Item) }

	tokens, lex_err := syntax.tokenize(src, context.temp_allocator)
	if e, failed := lex_err.?; failed {
		report(s, .Error, "", fmt.tprintf("Line %d, column %d: %s.", e.line, e.col, e.message))
		return 1
	}

	start := 0
	for tok, i in tokens {
		if tok.kind != .End_Command { continue }
		if i > start {
			if !run_command(s, tokens[start:i]) { errors += 1 }
		}
		start = i + 1
	}
	return errors
}

report :: proc(s: ^Session, kind: output.Text_Kind, command, text: string) {
	append(&s.items, output.Text{kind = kind, command = strings.clone(command), text = strings.clone(text)})
}

@(private)
Command :: struct {
	name: string,
	run:  proc(s: ^Session, c: ^Cmd) -> bool,
}

@(private)
COMMANDS := [?]Command {
	{"COMPUTE", cmd_compute},
	{"DESCRIPTIVES", cmd_descriptives},
	{"EXECUTE", proc(s: ^Session, c: ^Cmd) -> bool { return true }},
	{"FREQUENCIES", cmd_frequencies},
	{"GET", cmd_get},
	{"SAVE", cmd_save},
}

// Parsing state for one command's tokens (terminator excluded).
Cmd :: struct {
	name: string,
	toks: []syntax.Token,
	pos:  int,
	s:    ^Session,
}

@(private)
run_command :: proc(s: ^Session, toks: []syntax.Token) -> bool {
	head := toks[0]
	if head.kind != .Identifier {
		report(s, .Error, "", fmt.tprintf("Line %d: a command must start with a command name, not '%s'.", head.line, head.text))
		return false
	}
	for c in COMMANDS {
		if !keyword_matches(head.text, c.name) { continue }
		cmd := Cmd{name = c.name, toks = toks, pos = 1, s = s}
		return c.run(s, &cmd)
	}
	report(s, .Error, "", fmt.tprintf("Line %d: unrecognized or not yet implemented command %s.", head.line, strings.to_upper(head.text, context.temp_allocator)))
	return false
}

// SPSS keywords may be abbreviated to their first three or more characters.
keyword_matches :: proc(word, keyword: string) -> bool {
	if len(word) == len(keyword) { return strings.equal_fold(word, keyword) }
	return len(word) >= 3 && len(word) < len(keyword) && strings.equal_fold(word, keyword[:len(word)])
}

// --- token helpers ---

peek :: proc(c: ^Cmd) -> (syntax.Token, bool) {
	if c.pos >= len(c.toks) { return {}, false }
	return c.toks[c.pos], true
}

at_end :: proc(c: ^Cmd) -> bool {
	return c.pos >= len(c.toks)
}

accept_kind :: proc(c: ^Cmd, kind: syntax.Token_Kind) -> bool {
	if t, ok := peek(c); ok && t.kind == kind {
		c.pos += 1
		return true
	}
	return false
}

accept_keyword :: proc(c: ^Cmd, keyword: string) -> bool {
	if t, ok := peek(c); ok && (t.kind == .Identifier || t.kind == .Keyword) && keyword_matches(t.text, keyword) {
		c.pos += 1
		return true
	}
	return false
}

fail :: proc(c: ^Cmd, format: string, args: ..any) -> bool {
	t, ok := peek(c)
	where_ := fmt.tprintf("line %d", t.line) if ok else "end of command"
	report(c.s, .Error, c.name, fmt.tprintf("%s (%s): %s", c.name, where_, fmt.tprintf(format, ..args)))
	return false
}

warn :: proc(c: ^Cmd, format: string, args: ..any) {
	report(c.s, .Warning, c.name, fmt.tprintf("%s: %s", c.name, fmt.tprintf(format, ..args)))
}

need_data :: proc(c: ^Cmd) -> bool {
	if c.s.has_data { return true }
	return fail(c, "there is no active dataset. Open one with GET FILE first.")
}

// Parses a variable list: names, `a TO b` (dictionary order) and ALL. Stops at '/' or the end.
parse_varlist :: proc(c: ^Cmd, numeric_only := true) -> (vars: [dynamic]int, ok: bool) {
	vars = make([dynamic]int, context.temp_allocator)
	file := &c.s.data
	for {
		t, has := peek(c)
		if !has || t.kind == .Slash { break }
		if t.kind == .Keyword && strings.equal_fold(t.text, "ALL") {
			c.pos += 1
			for v, i in file.variables {
				if !numeric_only || v.width == 0 { append(&vars, i) }
			}
			continue
		}
		if t.kind != .Identifier {
			return vars, fail(c, "expected a variable name, found '%s'", t.text)
		}
		first := transform.find_variable(file, t.text)
		if first < 0 { return vars, fail(c, "variable %s does not exist", t.text) }
		c.pos += 1
		last := first
		if to, has_to := peek(c); has_to && to.kind == .Keyword && strings.equal_fold(to.text, "TO") {
			c.pos += 1
			end, has_end := peek(c)
			if !has_end || end.kind != .Identifier { return vars, fail(c, "expected a variable name after TO") }
			last = transform.find_variable(file, end.text)
			if last < 0 { return vars, fail(c, "variable %s does not exist", end.text) }
			if last < first { return vars, fail(c, "%s TO %s: the second variable must follow the first in the file", t.text, end.text) }
			c.pos += 1
		}
		for i in first ..= last {
			if numeric_only && file.variables[i].width > 0 {
				warn(c, "string variable %s ignored", file.variables[i].name)
				continue
			}
			append(&vars, i)
		}
		accept_kind(c, .Comma)
	}
	if len(vars) == 0 { return vars, fail(c, "no variables were specified") }
	return vars, true
}

// Parses `KEYWORD = 'string'` (the '=' is optional).
parse_file_spec :: proc(c: ^Cmd, keyword: string) -> (path: string, ok: bool) {
	if !accept_keyword(c, keyword) { return "", fail(c, "expected %s='file name'", keyword) }
	accept_kind(c, .Equals)
	t, has := peek(c)
	if !has || t.kind != .String { return "", fail(c, "expected a quoted file name after %s", keyword) }
	c.pos += 1
	return t.text, true
}

// --- commands ---

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
	data, err := sav.write(&s.data, compression, context.temp_allocator)
	if err != nil { return fail(c, "cannot encode the dataset") }
	if os.write_entire_file(path, data) != nil { return fail(c, "cannot write %s", path) }
	return true
}

@(private)
cmd_compute :: proc(s: ^Session, c: ^Cmd) -> bool {
	need_data(c) or_return
	target, ok := peek(c)
	if !ok || target.kind != .Identifier { return fail(c, "expected a target variable name") }
	c.pos += 1
	if !accept_kind(c, .Equals) { return fail(c, "expected '=' after the target variable") }

	file := &s.data
	expr: ^transform.Node
	perr: Maybe(transform.Parse_Error)
	{
		context.allocator = context.temp_allocator
		expr, perr = transform.parse(c.toks[c.pos:], file)
	}
	if e, failed := perr.?; failed {
		return fail(c, "%s (line %d, column %d)", e.message, e.token.line, e.token.col)
	}

	idx := transform.find_variable(file, target.text)
	if idx < 0 {
		da := data_allocator(s)
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

	if n := warnings[.Division_By_Zero]; n > 0 {
		warn(c, "Warning # 511. A division by zero was attempted in %d case(s); the result was set to system-missing.", n)
	}
	if n := warnings[.Sqrt_Negative]; n > 0 {
		warn(c, "Warning # 603. The argument to SQRT was negative in %d case(s); the result was set to system-missing.", n)
	}
	if n := warnings[.Log_Domain]; n > 0 {
		warn(c, "The argument to LN or LG10 was not positive in %d case(s); the result was set to system-missing.", n)
	}
	return true
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
		stats = {}
		for !at_end(c) {
			t, _ := peek(c)
			if t.kind == .Slash { break }
			found := false
			names := [?]struct {
				word: string,
				stat: procs.Desc_Stats,
			}{
				{"DEFAULT", procs.DESC_DEFAULT}, {"ALL", procs.DESC_ALL}, {"MEAN", {.Mean}}, {"SEMEAN", {.Semean}},
				{"STDDEV", {.Stddev}}, {"VARIANCE", {.Variance}}, {"RANGE", {.Range}}, {"MIN", {.Min}},
				{"MAX", {.Max}}, {"SUM", {.Sum}}, {"SKEWNESS", {.Skewness}}, {"KURTOSIS", {.Kurtosis}},
			}
			for n in names {
				if accept_keyword(c, n.word) {
					stats += n.stat
					found = true
					break
				}
			}
			if !found { return fail(c, "unknown statistic %s", t.text) }
		}
		if stats == {} { stats = procs.DESC_DEFAULT }
	}
	append(&s.items, procs.descriptives(&s.data, vars[:], stats))
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
			for !at_end(c) {
				t, _ := peek(c)
				if t.kind == .Slash { break }
				if accept_keyword(c, "NOTABLE") {
					opts.no_table = true
				} else {
					c.pos += 1
					warn(c, "FORMAT keyword %s is not implemented yet and was ignored", t.text)
				}
			}
		case accept_keyword(c, "STATISTICS"):
			accept_kind(c, .Equals)
			any_named := false
			for !at_end(c) {
				t, _ := peek(c)
				if t.kind == .Slash { break }
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
				found := false
				for n in names {
					if accept_keyword(c, n.word) {
						opts.stats += n.stat
						found, any_named = true, true
						break
					}
				}
				if !found { return fail(c, "unknown statistic %s", t.text) }
			}
			if !any_named { opts.stats = procs.FREQ_DEFAULT }
		case:
			t, _ := peek(c)
			return fail(c, "subcommand %s is not implemented yet", t.text)
		}
	}
	procs.frequencies(&s.data, vars[:], opts, &s.items)
	return true
}
