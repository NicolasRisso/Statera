# Syntax lexer
Status: draft
Sources: IBM SPSS Statistics Command Syntax Reference, "Universals → Commands / Syntax rules" (public documentation).

## Behaviour

Syntax text is split into commands, and each command into tokens. This spec covers **interactive mode**, the syntax window default. Batch/INSERT modes (where a non-indented line starts a new command) come later.

### Command boundaries
- A command ends at a period `.` that is the last non-blank character on a line, or at a blank line.
- A period elsewhere is part of a token (a decimal point, or a character inside a name).

### Tokens
| Kind | Rule |
|---|---|
| Identifier | Starts with a letter or `@ # $`. Continues with letters, digits, `_ . @ # $`. A trailing `.` belongs to the identifier only if it isn't the command terminator. Case-insensitive. |
| Reserved keyword | `ALL AND BY EQ GE GT LE LT NE NOT OR TO WITH`. These can never be variable names. |
| Number | `123`, `1.5`, `.5`, `1e3`, `1.5E-3`. A leading sign is a separate token. |
| String | Delimited by `'` or `"`. The delimiter is escaped by doubling it. `X'…'` is hex, `U'…'` is a Unicode literal. A string can't span lines (multi-line strings use `+` concatenation, handled in the parser). |
| Punctuation | `/ = ( ) , [ ] :` |
| Operators | `+ - * ** < > <= >= <> ~= & \| ~` |

### Comments
- `/* … */` anywhere outside strings. If `*/` doesn't appear on the same line, the comment runs to the end of the line.
- A command that starts with `*` or `COMMENT` is a comment command. It extends to the command terminator, and the lexer yields no tokens for it.

## Edge cases
- `COMPUTE x = 1.` gives the number `1` followed by the terminator.
- `x.y` is a single identifier. `x.` at end of line is an identifier then the terminator.
- Keywords may be abbreviated (minimum 3 characters). Abbreviation is a parser concern, not a lexer one.

## Errors and warnings
- An unterminated string is an error at its opening quote.

## Open questions
- Exact batch-mode rules (column-1 continuation, `+`/`-` continuation markers).
- Whether a blank line inside `BEGIN DATA` is data (it is; the parser must read raw lines there).
