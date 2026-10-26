package syntax

import "core:testing"

@(private = "file")
kinds :: proc(t: ^testing.T, src: string, want: []Token_Kind) -> [dynamic]Token {
	toks, err := tokenize(src, context.temp_allocator)
	testing.expect_value(t, err, nil)
	if !testing.expectf(t, len(toks) == len(want), "%q: got %d tokens, want %d: %v", src, len(toks), len(want), toks) {
		return toks
	}
	for tok, i in toks {
		testing.expectf(t, tok.kind == want[i], "%q token %d: got %v want %v", src, i, tok.kind, want[i])
	}
	return toks
}

@(test)
test_compute_with_terminator :: proc(t: ^testing.T) {
	toks := kinds(t, "COMPUTE x = 1.\n", {.Identifier, .Identifier, .Equals, .Number, .End_Command})
	testing.expect_value(t, toks[3].number, 1)
}

@(test)
test_periods_inside_tokens :: proc(t: ^testing.T) {
	toks := kinds(t, "COMPUTE x.y = .5 + 1.5e-3.", {.Identifier, .Identifier, .Equals, .Number, .Plus, .Number, .End_Command})
	testing.expect_value(t, toks[1].text, "x.y")
	testing.expect_value(t, toks[3].number, 0.5)
	testing.expect_value(t, toks[5].number, 0.0015)
}

@(test)
test_strings :: proc(t: ^testing.T) {
	toks := kinds(t, `VARIABLE LABELS x 'it''s' y "say ""hi""" z X'41'.`,
		{.Identifier, .Identifier, .Identifier, .String, .Identifier, .String, .Identifier, .Hex_String, .End_Command})
	testing.expect_value(t, toks[3].text, "it's")
	testing.expect_value(t, toks[5].text, `say "hi"`)
	testing.expect_value(t, toks[7].text, "41")
}

@(test)
test_reserved_and_operators :: proc(t: ^testing.T) {
	kinds(t, "IF (a GE 2 & b ~= 3 | c <= d) x = a ** 2.",
		{.Identifier, .L_Paren, .Identifier, .Keyword, .Number, .And_Op, .Identifier, .Not_Equal, .Number,
		 .Or_Op, .Identifier, .Less_Equal, .Identifier, .R_Paren, .Identifier, .Equals, .Identifier, .Star_Star,
		 .Number, .End_Command})
}

@(test)
test_comments :: proc(t: ^testing.T) {
	src := "* a comment command\n  spanning lines.\nCOMMENT another.\nFREQUENCIES /* inline */ x.\n"
	kinds(t, src, {.Identifier, .Identifier, .End_Command})
}

@(test)
test_blank_line_ends_command :: proc(t: ^testing.T) {
	kinds(t, "FREQUENCIES x\n\nDESCRIPTIVES y", {.Identifier, .Identifier, .End_Command, .Identifier, .Identifier, .End_Command})
}

@(test)
test_multiline_command :: proc(t: ^testing.T) {
	toks := kinds(t, "CROSSTABS\n  /TABLES=a BY b\n  /STATISTICS=CHISQ.\n",
		{.Identifier, .Slash, .Identifier, .Equals, .Identifier, .Keyword, .Identifier, .Slash, .Identifier, .Equals,
		 .Identifier, .End_Command})
	testing.expect_value(t, toks[2].line, 2)
	testing.expect_value(t, toks[2].col, 4)
}

@(test)
test_unterminated_string :: proc(t: ^testing.T) {
	_, err := tokenize("TITLE 'oops.\n", context.temp_allocator)
	e, ok := err.?
	testing.expect(t, ok)
	testing.expect_value(t, e.col, 7)
}
