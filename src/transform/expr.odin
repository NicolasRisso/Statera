// Numeric expressions for COMPUTE and friends. Spec: docs/specs/transform/compute.md
package transform

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

import "../io/sav"
import "../syntax"

SYSMIS :: sav.SYSMIS

Op :: enum u8 {
	Add, Sub, Mul, Div, Pow,
	Eq, Ne, Lt, Le, Gt, Ge,
	And, Or,
}

Func :: enum u8 {
	Abs, Sqrt, Exp, Ln, Lg10, Rnd, Trunc, Mod,
	Sum, Mean, Sd, Variance, Min, Max,
	Nvalid, Nmiss, Missing, Sysmis, Value,
}

Node :: struct {
	kind:      enum u8 { Number, Var, Neg, Not, Binary, Call },
	op:        Op,
	fn:        Func,
	number:    f64,
	var:       int, // variable index for .Var
	min_valid: int, // FN.n suffix
	args:      []^Node,
}

Parse_Error :: struct {
	message: string,
	token:   syntax.Token,
}

Warning :: enum u8 {
	Division_By_Zero, // SPSS warning 511
	Sqrt_Negative,    // SPSS warning 603
	Log_Domain,
}

Warnings :: [Warning]int

@(private)
Parser :: struct {
	toks: []syntax.Token,
	pos:  int,
	file: ^sav.File,
}

// Parses tokens (excluding the command terminator) into an expression tree allocated with context.allocator.
parse :: proc(toks: []syntax.Token, file: ^sav.File) -> (n: ^Node, err: Maybe(Parse_Error)) {
	p := Parser{toks = toks, file = file}
	n = parse_or(&p) or_return
	if p.pos < len(p.toks) {
		return nil, Parse_Error{"unexpected token in expression", p.toks[p.pos]}
	}
	return n, nil
}

@(private)
peek :: proc(p: ^Parser) -> (syntax.Token, bool) {
	if p.pos >= len(p.toks) { return {}, false }
	return p.toks[p.pos], true
}

@(private)
is_word :: proc(t: syntax.Token, word: string) -> bool {
	return (t.kind == .Keyword || t.kind == .Identifier) && strings.equal_fold(t.text, word)
}

@(private)
binary :: proc(op: Op, a, b: ^Node) -> ^Node {
	n := new(Node)
	n.kind, n.op, n.args = .Binary, op, make([]^Node, 2)
	n.args[0], n.args[1] = a, b
	return n
}

@(private)
parse_or :: proc(p: ^Parser) -> (n: ^Node, err: Maybe(Parse_Error)) {
	n = parse_and(p) or_return
	for t, ok := peek(p); ok && (t.kind == .Or_Op || is_word(t, "OR")); t, ok = peek(p) {
		p.pos += 1
		n = binary(.Or, n, parse_and(p) or_return)
	}
	return n, nil
}

@(private)
parse_and :: proc(p: ^Parser) -> (n: ^Node, err: Maybe(Parse_Error)) {
	n = parse_not(p) or_return
	for t, ok := peek(p); ok && (t.kind == .And_Op || is_word(t, "AND")); t, ok = peek(p) {
		p.pos += 1
		n = binary(.And, n, parse_not(p) or_return)
	}
	return n, nil
}

@(private)
parse_not :: proc(p: ^Parser) -> (n: ^Node, err: Maybe(Parse_Error)) {
	if t, ok := peek(p); ok && (t.kind == .Not_Op || is_word(t, "NOT")) {
		p.pos += 1
		n = new(Node)
		n.kind, n.args = .Not, make([]^Node, 1)
		n.args[0] = parse_not(p) or_return
		return n, nil
	}
	return parse_rel(p)
}

@(private)
parse_rel :: proc(p: ^Parser) -> (n: ^Node, err: Maybe(Parse_Error)) {
	n = parse_add(p) or_return
	for {
		t, ok := peek(p)
		if !ok { break }
		op: Op
		switch {
		case t.kind == .Equals || is_word(t, "EQ"):                      op = .Eq
		case t.kind == .Not_Equal || is_word(t, "NE"):                   op = .Ne
		case t.kind == .Less || is_word(t, "LT"):                        op = .Lt
		case t.kind == .Less_Equal || is_word(t, "LE"):                  op = .Le
		case t.kind == .Greater || is_word(t, "GT"):                     op = .Gt
		case t.kind == .Greater_Equal || is_word(t, "GE"):               op = .Ge
		case:                                                            return n, nil
		}
		p.pos += 1
		n = binary(op, n, parse_add(p) or_return)
	}
	return n, nil
}

@(private)
parse_add :: proc(p: ^Parser) -> (n: ^Node, err: Maybe(Parse_Error)) {
	n = parse_mul(p) or_return
	for t, ok := peek(p); ok && (t.kind == .Plus || t.kind == .Minus); t, ok = peek(p) {
		p.pos += 1
		n = binary(.Add if t.kind == .Plus else .Sub, n, parse_mul(p) or_return)
	}
	return n, nil
}

@(private)
parse_mul :: proc(p: ^Parser) -> (n: ^Node, err: Maybe(Parse_Error)) {
	n = parse_unary(p) or_return
	for t, ok := peek(p); ok && (t.kind == .Star || t.kind == .Slash); t, ok = peek(p) {
		p.pos += 1
		n = binary(.Mul if t.kind == .Star else .Div, n, parse_unary(p) or_return)
	}
	return n, nil
}

// Unary minus binds looser than **: -2**2 = -4.
@(private)
parse_unary :: proc(p: ^Parser) -> (n: ^Node, err: Maybe(Parse_Error)) {
	if t, ok := peek(p); ok && (t.kind == .Minus || t.kind == .Plus) {
		p.pos += 1
		inner := parse_unary(p) or_return
		if t.kind == .Plus { return inner, nil }
		n = new(Node)
		n.kind, n.args = .Neg, make([]^Node, 1)
		n.args[0] = inner
		return n, nil
	}
	return parse_pow(p)
}

@(private)
parse_pow :: proc(p: ^Parser) -> (n: ^Node, err: Maybe(Parse_Error)) {
	n = parse_primary(p) or_return
	for t, ok := peek(p); ok && t.kind == .Star_Star; t, ok = peek(p) {
		p.pos += 1
		rhs: ^Node
		if m, has := peek(p); has && m.kind == .Minus {
			p.pos += 1
			rhs = new(Node)
			rhs.kind, rhs.args = .Neg, make([]^Node, 1)
			rhs.args[0] = parse_primary(p) or_return
		} else {
			rhs = parse_primary(p) or_return
		}
		n = binary(.Pow, n, rhs)
	}
	return n, nil
}

@(private)
parse_primary :: proc(p: ^Parser) -> (n: ^Node, err: Maybe(Parse_Error)) {
	t, ok := peek(p)
	if !ok {
		end := p.toks[len(p.toks) - 1] if len(p.toks) > 0 else syntax.Token{}
		return nil, Parse_Error{"expression ends unexpectedly", end}
	}
	p.pos += 1
	#partial switch t.kind {
	case .Number:
		n = new(Node)
		n.kind, n.number = .Number, t.number
		return n, nil
	case .L_Paren:
		n = parse_or(p) or_return
		if c, has := peek(p); !has || c.kind != .R_Paren {
			return nil, Parse_Error{"missing right parenthesis", t}
		}
		p.pos += 1
		return n, nil
	case .Identifier:
		if next, has := peek(p); has && next.kind == .L_Paren {
			return parse_call(p, t)
		}
		idx := find_variable(p.file, t.text)
		if idx < 0 {
			return nil, Parse_Error{fmt.aprintf("undefined variable %s", t.text), t}
		}
		n = new(Node)
		n.kind, n.var = .Var, idx
		return n, nil
	}
	return nil, Parse_Error{"expected a number, variable or function", t}
}

@(private)
FUNCS := [Func]string {
	.Abs = "ABS", .Sqrt = "SQRT", .Exp = "EXP", .Ln = "LN", .Lg10 = "LG10", .Rnd = "RND", .Trunc = "TRUNC",
	.Mod = "MOD", .Sum = "SUM", .Mean = "MEAN", .Sd = "SD", .Variance = "VARIANCE", .Min = "MIN", .Max = "MAX",
	.Nvalid = "NVALID", .Nmiss = "NMISS", .Missing = "MISSING", .Sysmis = "SYSMIS", .Value = "VALUE",
}

@(private)
parse_call :: proc(p: ^Parser, name_tok: syntax.Token) -> (n: ^Node, err: Maybe(Parse_Error)) {
	name, _, suffix := strings.partition(name_tok.text, ".")
	fn, found := Func(0), false
	for f in Func {
		if strings.equal_fold(FUNCS[f], name) { fn, found = f, true }
	}
	if !found {
		return nil, Parse_Error{fmt.aprintf("unknown function %s", name_tok.text), name_tok}
	}
	p.pos += 1 // '('
	args: [dynamic]^Node
	for {
		append(&args, parse_or(p) or_return)
		t, ok := peek(p)
		if !ok { return nil, Parse_Error{"missing right parenthesis", name_tok} }
		p.pos += 1
		if t.kind == .R_Paren { break }
		if t.kind != .Comma { return nil, Parse_Error{"expected , or )", t} }
	}

	n = new(Node)
	n.kind, n.fn, n.args = .Call, fn, args[:]
	n.min_valid = 2 if fn == .Sd || fn == .Variance else 1
	if suffix != "" {
		v, ok := strconv.parse_int(suffix)
		if !ok || v < 1 { return nil, Parse_Error{"invalid minimum-valid suffix", name_tok} }
		n.min_valid = v
	}

	arity := -1
	#partial switch fn {
	case .Abs, .Sqrt, .Exp, .Ln, .Lg10, .Rnd, .Trunc, .Missing, .Sysmis, .Value: arity = 1
	case .Mod:                                                                     arity = 2
	}
	if arity > 0 && len(args) != arity {
		return nil, Parse_Error{fmt.aprintf("%s takes %d argument(s)", FUNCS[fn], arity), name_tok}
	}
	if fn == .Value && args[0].kind != .Var {
		return nil, Parse_Error{"VALUE requires a variable name", name_tok}
	}
	return n, nil
}

find_variable :: proc(file: ^sav.File, name: string) -> int {
	for v, i in file.variables {
		if strings.equal_fold(v.name, name) { return i }
	}
	return -1
}

// Evaluates `n` for case `row`. Missing results are SYSMIS.
eval :: proc(n: ^Node, file: ^sav.File, row: int, warnings: ^Warnings) -> f64 {
	switch n.kind {
	case .Number:
		return n.number
	case .Var:
		v := &file.variables[n.var]
		x := v.numbers[row]
		return SYSMIS if is_missing(v, x, file.sysmis) else x
	case .Neg:
		x := eval(n.args[0], file, row, warnings)
		return SYSMIS if x == SYSMIS else -x
	case .Not:
		x := eval(n.args[0], file, row, warnings)
		return SYSMIS if x == SYSMIS else (1 if x == 0 else 0)
	case .Binary:
		return eval_binary(n, file, row, warnings)
	case .Call:
		return eval_call(n, file, row, warnings)
	}
	return SYSMIS
}

@(private)
eval_binary :: proc(n: ^Node, file: ^sav.File, row: int, warnings: ^Warnings) -> f64 {
	a := eval(n.args[0], file, row, warnings)
	b := eval(n.args[1], file, row, warnings)
	am, bm := a == SYSMIS, b == SYSMIS

	switch n.op {
	case .And:
		if (!am && a == 0) || (!bm && b == 0) { return 0 }
		return SYSMIS if am || bm else 1
	case .Or:
		if (!am && a != 0) || (!bm && b != 0) { return 1 }
		return SYSMIS if am || bm else 0
	case .Mul:
		if (a == 0 && bm) || (b == 0 && am) { return 0 }
	case .Div:
		if a == 0 && bm { return 0 }
	case .Add, .Sub, .Pow, .Eq, .Ne, .Lt, .Le, .Gt, .Ge:
	}
	if am || bm { return SYSMIS }

	switch n.op {
	case .Add: return a + b
	case .Sub: return a - b
	case .Mul: return a * b
	case .Div:
		if b == 0 {
			warnings[.Division_By_Zero] += 1
			return SYSMIS
		}
		return a / b
	case .Pow:
		r := math.pow(a, b)
		return SYSMIS if math.is_nan(r) || math.is_inf(r) else r
	case .Eq: return 1 if a == b else 0
	case .Ne: return 1 if a != b else 0
	case .Lt: return 1 if a < b else 0
	case .Le: return 1 if a <= b else 0
	case .Gt: return 1 if a > b else 0
	case .Ge: return 1 if a >= b else 0
	case .And, .Or:
	}
	return SYSMIS
}

@(private)
eval_call :: proc(n: ^Node, file: ^sav.File, row: int, warnings: ^Warnings) -> f64 {
	#partial switch n.fn {
	case .Value:
		return file.variables[n.args[0].var].numbers[row]
	case .Missing, .Sysmis:
		arg := n.args[0]
		if arg.kind == .Var {
			v := &file.variables[arg.var]
			x := v.numbers[row]
			if n.fn == .Sysmis { return 1 if x == file.sysmis else 0 }
			return 1 if is_missing(v, x, file.sysmis) else 0
		}
		return 1 if eval(arg, file, row, warnings) == SYSMIS else 0
	case .Mod:
		a := eval(n.args[0], file, row, warnings)
		b := eval(n.args[1], file, row, warnings)
		if a == 0 { return 0 }
		if a == SYSMIS || b == SYSMIS || b == 0 { return SYSMIS }
		return a - b * math.trunc(a / b)
	case .Sum, .Mean, .Sd, .Variance, .Min, .Max, .Nvalid, .Nmiss:
		return eval_aggregate(n, file, row, warnings)
	}

	x := eval(n.args[0], file, row, warnings)
	if x == SYSMIS { return SYSMIS }
	#partial switch n.fn {
	case .Abs:   return abs(x)
	case .Trunc: return math.trunc(x)
	case .Rnd:   return round_half_away(x)
	case .Sqrt:
		if x < 0 {
			warnings[.Sqrt_Negative] += 1
			return SYSMIS
		}
		return math.sqrt(x)
	case .Exp:
		r := math.exp(x)
		return SYSMIS if math.is_inf(r) else r
	case .Ln, .Lg10:
		if x <= 0 {
			warnings[.Log_Domain] += 1
			return SYSMIS
		}
		return math.ln(x) if n.fn == .Ln else math.log10(x)
	}
	return SYSMIS
}

@(private)
eval_aggregate :: proc(n: ^Node, file: ^sav.File, row: int, warnings: ^Warnings) -> f64 {
	count, missing := 0, 0
	sum, mn, mx := 0.0, math.F64_MAX, -math.F64_MAX
	vals := make([]f64, len(n.args), context.temp_allocator)
	for arg in n.args {
		x := eval(arg, file, row, warnings)
		if x == SYSMIS {
			missing += 1
			continue
		}
		vals[count] = x
		count += 1
		sum += x
		mn, mx = min(mn, x), max(mx, x)
	}
	#partial switch n.fn {
	case .Nvalid: return f64(count)
	case .Nmiss:  return f64(missing)
	}
	if count < n.min_valid { return SYSMIS }
	#partial switch n.fn {
	case .Sum:  return sum
	case .Mean: return sum / f64(count)
	case .Min:  return mn
	case .Max:  return mx
	case .Sd, .Variance:
		mean := sum / f64(count)
		ss := 0.0
		for x in vals[:count] { ss += (x - mean) * (x - mean) }
		variance := ss / f64(count - 1)
		return math.sqrt(variance) if n.fn == .Sd else variance
	}
	return SYSMIS
}

is_missing :: proc(v: ^sav.Variable, x, sysmis: f64) -> bool {
	if x == sysmis { return true }
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

round_half_away :: proc(x: f64) -> f64 {
	y := math.floor(abs(x) + 0.5 + abs(x) * 1e-13)
	return math.copy_sign(y, x)
}
