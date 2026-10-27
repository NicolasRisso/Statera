// Command engine: runs syntax against the active dataset and collects output items.
package engine

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:strings"

import "../io/sav"
import "../output"
import "../procs"
import "../syntax"
import "../transform"

MAX_SPLIT :: 8

// Per-dataset settings that procedures honour (the weight lives in sav.File.weight).
Settings :: struct {
	filter:     int, // variable index, -1 when off
	split:      [MAX_SPLIT]int,
	n_split:    int,
	split_mode: procs.Split_Mode,
}

// Don't copy a Session: allocators inside its data point at its arenas.
Session :: struct {
	data_arena:    ^virtual.Arena, // heap-allocated so the dataset's allocators keep a stable address
	data:          sav.File,
	settings:      Settings,
	data_name:     string,
	has_data:      bool,

	// TEMPORARY: a working copy used by the next procedure only.
	temp_on:       bool,
	temp_arena:    ^virtual.Arena,
	temp_data:     sav.File,
	temp_settings: Settings,

	out_arena:     virtual.Arena,
	items:         [dynamic]output.Item,
}

data_allocator :: proc(s: ^Session) -> runtime.Allocator {
	return virtual.arena_allocator(s.data_arena)
}

out_allocator :: proc(s: ^Session) -> runtime.Allocator {
	return virtual.arena_allocator(&s.out_arena)
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

destroy :: proc(s: ^Session) {
	end_temporary(s)
	free_arena(s.data_arena)
	virtual.arena_destroy(&s.out_arena)
	s^ = {}
}

// Replaces the active dataset; `file` must have been allocated from `arena` (from new_arena).
set_dataset :: proc(s: ^Session, file: sav.File, arena: ^virtual.Arena, name: string) {
	end_temporary(s)
	free_arena(s.data_arena)
	s.data_arena = arena
	s.data = file
	s.settings = {filter = -1, split_mode = .Off}
	s.data_name = strings.clone(name, data_allocator(s))
	s.has_data = true
}

clear_output :: proc(s: ^Session) {
	virtual.arena_destroy(&s.out_arena)
	s.out_arena = {}
	s.items = {}
}

// The dataset and settings commands act on: the TEMPORARY copy while one is active.
active :: proc(s: ^Session) -> (^sav.File, ^Settings) {
	if s.temp_on { return &s.temp_data, &s.temp_settings }
	return &s.data, &s.settings
}

active_allocator :: proc(s: ^Session) -> runtime.Allocator {
	return virtual.arena_allocator(s.temp_arena) if s.temp_on else data_allocator(s)
}

begin_temporary :: proc(s: ^Session) {
	if s.temp_on { return }
	s.temp_arena = new_arena()
	s.temp_data = sav.clone(&s.data, virtual.arena_allocator(s.temp_arena))
	s.temp_settings = s.settings
	s.temp_on = true
}

// Called after every procedure: TEMPORARY changes last for exactly one.
end_temporary :: proc(s: ^Session) {
	if !s.temp_on { return }
	free_arena(s.temp_arena)
	s.temp_arena, s.temp_data, s.temp_on = nil, {}, false
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
	// Hyphenated command names lex as several tokens: T-TEST is `T` `-` `TEST`.
	word, start := head.text, 1
	if len(toks) >= 3 && toks[1].kind == .Minus && toks[2].kind == .Identifier &&
	   toks[1].col == head.col + len(head.text) && toks[2].col == toks[1].col + 1 {
		word, start = fmt.tprintf("%s-%s", head.text, toks[2].text), 3
	}
	for c in COMMANDS {
		if !keyword_matches(word, c.name) { continue }
		cmd := Cmd{name = c.name, toks = toks, pos = start, s = s}
		if c.second != "" {
			if !accept_keyword(&cmd, c.second) { continue }
			cmd.name = fmt.tprintf("%s %s", c.name, c.second)
		}
		ok := c.run(s, &cmd)
		if c.procedure { end_temporary(s) }
		return ok
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

at_subcommand_end :: proc(c: ^Cmd) -> bool {
	t, ok := peek(c)
	return !ok || t.kind == .Slash
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

// Parses a variable list: names, `a TO b` (dictionary order) and ALL. Stops at '/', '(' or the end.
parse_varlist :: proc(c: ^Cmd, numeric_only := true) -> (vars: [dynamic]int, ok: bool) {
	vars = make([dynamic]int, context.temp_allocator)
	file, _ := active(c.s)
	for {
		t, has := peek(c)
		if !has || t.kind == .Slash || t.kind == .L_Paren { break }
		if t.kind == .Keyword && (strings.equal_fold(t.text, "BY") || strings.equal_fold(t.text, "WITH")) { break }
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

// Builds the case stream for a procedure: FILTER, weight validity, then SPLIT FILE groups.
// Spec: docs/specs/engine/procedure-context.md
make_context :: proc(c: ^Cmd) -> procs.Context {
	file, st := active(c.s)
	rows := make([dynamic]int, 0, file.n_cases, context.temp_allocator)
	weights := make([dynamic]f64, 0, file.n_cases, context.temp_allocator)
	bad_weight := false
	for r in 0 ..< file.n_cases {
		if st.filter >= 0 {
			fv := &file.variables[st.filter]
			x := fv.numbers[r]
			if x == 0 || transform.is_missing(fv, x, file.sysmis) { continue }
		}
		w := 1.0
		if file.weight >= 0 {
			wv := &file.variables[file.weight]
			w = wv.numbers[r]
			if transform.is_missing(wv, w, file.sysmis) || w <= 0 {
				bad_weight = true
				continue
			}
		}
		append(&rows, r)
		append(&weights, w)
	}
	if bad_weight {
		warn(c, "Warning # 3211. On at least one case, the value of the weight variable was zero, negative, or missing. Such cases are invisible to statistical procedures and graphs which need positively weighted cases, but remain on the file and are processed by non-statistical procedures and transformations.")
	}

	ctx := procs.Context{file = file, mode = st.split_mode if st.n_split > 0 else .Off}
	if st.n_split == 0 {
		groups := make([]procs.Group, 1, context.temp_allocator)
		groups[0] = {rows = rows[:], weights = weights[:]}
		ctx.groups = groups
		return ctx
	}

	groups := make([dynamic]procs.Group, context.temp_allocator)
	start := 0
	for i in 0 ..= len(rows) {
		if i < len(rows) && (i == start || same_split(file, st, rows[i], rows[start])) { continue }
		if i > start {
			labels := make([]string, st.n_split, context.temp_allocator)
			parts := make([]string, st.n_split, context.temp_allocator)
			for k in 0 ..< st.n_split {
				v := &file.variables[st.split[k]]
				labels[k] = procs.value_text(v, v.numbers[rows[start]])
				parts[k] = fmt.tprintf("%s = %s", procs.var_title(v), labels[k])
			}
			append(&groups, procs.Group {
				rows    = rows[start:i],
				weights = weights[start:i],
				labels  = labels,
				caption = procs.caption(parts),
			})
		}
		start = i
	}
	if len(groups) == 0 { append(&groups, procs.Group{}) } // no cases at all: one empty group
	ctx.groups = groups[:]
	return ctx
}

@(private)
same_split :: proc(file: ^sav.File, st: ^Settings, a, b: int) -> bool {
	for k in 0 ..< st.n_split {
		v := &file.variables[st.split[k]]
		if v.numbers[a] != v.numbers[b] { return false }
	}
	return true
}
