// Tokenizer for SPSS command syntax (interactive mode). Spec: docs/specs/syntax/lexer.md
package syntax

import "core:strconv"
import "core:strings"

Token_Kind :: enum u8 {
	Identifier,
	Keyword, // reserved: ALL AND BY EQ GE GT LE LT NE NOT OR TO WITH
	Number,
	String,
	Hex_String,
	Unicode_String,
	Slash, Equals, L_Paren, R_Paren, Comma, L_Bracket, R_Bracket, Colon,
	Plus, Minus, Star, Star_Star, Less, Greater, Less_Equal, Greater_Equal, Not_Equal,
	And_Op, Or_Op, Not_Op,
	End_Command,
}

Token :: struct {
	kind:   Token_Kind,
	text:   string, // slice of the source; for strings, the unescaped value (allocated)
	number: f64,
	line:   int,    // 1-based
	col:    int,    // 1-based
}

Lex_Error :: struct {
	message: string,
	line:    int,
	col:     int,
}

RESERVED := [?]string{"ALL", "AND", "BY", "EQ", "GE", "GT", "LE", "LT", "NE", "NOT", "OR", "TO", "WITH"}

tokenize :: proc(src: string, allocator := context.allocator) -> (tokens: [dynamic]Token, err: Maybe(Lex_Error)) {
	context.allocator = allocator
	l := Lexer{src = src, line = 1, line_start = 0, command_start = true}
	for {
		tok, done, e := next(&l)
		if e != nil { return tokens, e }
		if done { break }
		append(&tokens, tok)
	}
	if len(tokens) > 0 && tokens[len(tokens) - 1].kind != .End_Command {
		append(&tokens, Token{kind = .End_Command, line = l.line, col = l.pos - l.line_start + 1})
	}
	return tokens, nil
}

@(private)
Lexer :: struct {
	src:           string,
	pos:           int,
	line:          int,
	line_start:    int,
	command_start: bool, // no token emitted yet in the current command
}

@(private)
next :: proc(l: ^Lexer) -> (tok: Token, done: bool, err: Maybe(Lex_Error)) {
	for {
		skip_blanks(l)
		if l.pos >= len(l.src) { return {}, true, nil }
		c := l.src[l.pos]

		if c == '\n' {
			l.pos += 1
			blank := line_is_blank(l.src[l.line_start:l.pos])
			l.line += 1
			l.line_start = l.pos
			if blank && !l.command_start {
				return end_command(l), false, nil
			}
			continue
		}
		if c == '/' && peek(l, 1) == '*' {
			skip_inline_comment(l)
			continue
		}
		if l.command_start && is_comment_command(l) {
			skip_to_terminator(l)
			continue
		}
		if c == '.' && is_terminator(l) {
			l.pos += 1
			if l.command_start { continue }
			return end_command(l), false, nil
		}
		break
	}

	l.command_start = false
	start := l.pos
	tok = Token{line = l.line, col = start - l.line_start + 1}
	c := l.src[l.pos]

	switch {
	case (c == 'x' || c == 'X' || c == 'u' || c == 'U') && (peek(l, 1) == '\'' || peek(l, 1) == '"'):
		tok.kind = .Hex_String if c == 'x' || c == 'X' else .Unicode_String
		l.pos += 1
		tok.text = lex_string(l, tok) or_return
	case c == '\'' || c == '"':
		tok.kind = .String
		tok.text = lex_string(l, tok) or_return
	case is_digit(c) || (c == '.' && is_digit(peek(l, 1))):
		lex_number(l, &tok)
	case is_ident_start(c):
		for l.pos < len(l.src) && is_ident_char(l.src[l.pos]) {
			if l.src[l.pos] == '.' && is_terminator(l) { break }
			l.pos += 1
		}
		tok.text = l.src[start:l.pos]
		tok.kind = .Keyword if is_reserved(tok.text) else .Identifier
	case:
		tok.kind = lex_operator(l) or_return
		tok.text = l.src[start:l.pos]
	}
	return tok, false, nil
}

@(private)
end_command :: proc(l: ^Lexer) -> Token {
	l.command_start = true
	return Token{kind = .End_Command, line = l.line, col = l.pos - l.line_start}
}

@(private)
lex_string :: proc(l: ^Lexer, tok: Token) -> (value: string, err: Maybe(Lex_Error)) {
	quote := l.src[l.pos]
	l.pos += 1
	b := strings.builder_make()
	for {
		if l.pos >= len(l.src) || l.src[l.pos] == '\n' {
			return "", Lex_Error{"unterminated string", tok.line, tok.col}
		}
		ch := l.src[l.pos]
		l.pos += 1
		if ch == quote {
			if l.pos < len(l.src) && l.src[l.pos] == quote {
				l.pos += 1
			} else {
				break
			}
		}
		strings.write_byte(&b, ch)
	}
	return strings.to_string(b), nil
}

@(private)
lex_number :: proc(l: ^Lexer, tok: ^Token) {
	start := l.pos
	for l.pos < len(l.src) && is_digit(l.src[l.pos]) { l.pos += 1 }
	if l.pos < len(l.src) && l.src[l.pos] == '.' && !is_terminator(l) {
		l.pos += 1
		for l.pos < len(l.src) && is_digit(l.src[l.pos]) { l.pos += 1 }
	}
	if l.pos < len(l.src) && (l.src[l.pos] == 'e' || l.src[l.pos] == 'E') {
		save := l.pos
		l.pos += 1
		if l.pos < len(l.src) && (l.src[l.pos] == '+' || l.src[l.pos] == '-') { l.pos += 1 }
		if l.pos < len(l.src) && is_digit(l.src[l.pos]) {
			for l.pos < len(l.src) && is_digit(l.src[l.pos]) { l.pos += 1 }
		} else {
			l.pos = save
		}
	}
	tok.kind = .Number
	tok.text = l.src[start:l.pos]
	tok.number, _ = strconv.parse_f64(tok.text)
}

@(private)
lex_operator :: proc(l: ^Lexer) -> (kind: Token_Kind, err: Maybe(Lex_Error)) {
	c, n := l.src[l.pos], peek(l, 1)
	two :: proc(l: ^Lexer, k: Token_Kind) -> Token_Kind { l.pos += 2; return k }
	switch {
	case c == '*' && n == '*': return two(l, .Star_Star), nil
	case c == '<' && n == '=': return two(l, .Less_Equal), nil
	case c == '>' && n == '=': return two(l, .Greater_Equal), nil
	case c == '<' && n == '>': return two(l, .Not_Equal), nil
	case c == '~' && n == '=': return two(l, .Not_Equal), nil
	}
	l.pos += 1
	switch c {
	case '/': return .Slash, nil
	case '=': return .Equals, nil
	case '(': return .L_Paren, nil
	case ')': return .R_Paren, nil
	case ',': return .Comma, nil
	case '[': return .L_Bracket, nil
	case ']': return .R_Bracket, nil
	case ':': return .Colon, nil
	case '+': return .Plus, nil
	case '-': return .Minus, nil
	case '*': return .Star, nil
	case '<': return .Less, nil
	case '>': return .Greater, nil
	case '&': return .And_Op, nil
	case '|': return .Or_Op, nil
	case '~': return .Not_Op, nil
	}
	return {}, Lex_Error{"unexpected character", l.line, l.pos - l.line_start}
}

// A '.' at pos terminates the command when only blanks follow it on the line.
@(private)
is_terminator :: proc(l: ^Lexer) -> bool {
	for i := l.pos + 1; i < len(l.src); i += 1 {
		switch l.src[i] {
		case ' ', '\t', '\r': continue
		case '\n':            return true
		case:                 return false
		}
	}
	return true
}

@(private)
is_comment_command :: proc(l: ^Lexer) -> bool {
	rest := l.src[l.pos:]
	if rest[0] == '*' && !strings.has_prefix(rest, "**") { return true }
	if len(rest) >= 7 && strings.equal_fold(rest[:7], "COMMENT") {
		return len(rest) == 7 || !is_ident_char(rest[7])
	}
	return false
}

@(private)
skip_to_terminator :: proc(l: ^Lexer) {
	for l.pos < len(l.src) {
		c := l.src[l.pos]
		if c == '.' && is_terminator(l) {
			l.pos += 1
			return
		}
		if c == '\n' {
			l.pos += 1
			blank_follows := line_is_blank(l.src[l.pos:][:line_length(l.src[l.pos:])])
			l.line += 1
			l.line_start = l.pos
			if blank_follows { return }
			continue
		}
		l.pos += 1
	}
}

@(private)
skip_inline_comment :: proc(l: ^Lexer) {
	l.pos += 2
	for l.pos < len(l.src) && l.src[l.pos] != '\n' {
		if l.src[l.pos] == '*' && peek(l, 1) == '/' {
			l.pos += 2
			return
		}
		l.pos += 1
	}
}

@(private)
skip_blanks :: proc(l: ^Lexer) {
	for l.pos < len(l.src) && (l.src[l.pos] == ' ' || l.src[l.pos] == '\t' || l.src[l.pos] == '\r') {
		l.pos += 1
	}
}

@(private)
line_length :: proc(s: string) -> int {
	i := strings.index_byte(s, '\n')
	return len(s) if i < 0 else i
}

@(private)
line_is_blank :: proc(s: string) -> bool {
	return len(strings.trim_space(s)) == 0
}

@(private)
peek :: proc(l: ^Lexer, ahead: int) -> u8 {
	i := l.pos + ahead
	return l.src[i] if i < len(l.src) else 0
}

@(private)
is_digit :: proc(c: u8) -> bool { return c >= '0' && c <= '9' }

@(private)
is_letter :: proc(c: u8) -> bool { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c >= 0x80 }

@(private)
is_ident_start :: proc(c: u8) -> bool { return is_letter(c) || c == '@' || c == '#' || c == '$' }

@(private)
is_ident_char :: proc(c: u8) -> bool { return is_ident_start(c) || is_digit(c) || c == '_' || c == '.' }

@(private)
is_reserved :: proc(word: string) -> bool {
	for r in RESERVED {
		if strings.equal_fold(word, r) { return true }
	}
	return false
}
