# COMPUTE and numeric expressions
Status: draft (verified by tests/golden/compute_basic: SPSS's saved data is compared value by value)
Sources: Command Syntax Reference "Transformation expressions" (public); black-box runs.

## Syntax
`COMPUTE target = expression.` The target is a variable name. A new target becomes a numeric variable with format F8.2 and no label.

## Operators (highest precedence first)
1. `**`
2. unary `-`
3. `*` `/`
4. `+` `-`
5. relational: `= EQ`, `<> ~= NE`, `< LT`, `<= LE`, `> GT`, `>= GE`
6. `NOT ~`
7. `AND &`
8. `OR |`

Binary operators of the same level associate left to right. Relational and logical results are 1 (true) or 0 (false).

## Missing values
- User-missing values of a variable are treated as missing in expressions (they become SYSMIS), except inside `VALUE(var)`.
- Arithmetic, relational operators and most functions with a missing operand yield SYSMIS.
- **Exceptions (golden-verified):** `0 * missing = 0`, `0 / missing = 0`, `MOD(0, missing) = 0`. But `missing ** 0` is SYSMIS.
- `-2 ** 2 = -4`, because `**` binds tighter than unary minus.
- **Logical operators use three-valued logic:** `0 AND missing = 0`, `1 OR missing = 1`, and otherwise missing → SYSMIS. `NOT missing = SYSMIS`.
- Division by zero → SYSMIS with **warning 511**. SQRT of a negative → SYSMIS with **warning 603**. LN/LG10 of x ≤ 0 → SYSMIS (with a warning). A `**` result that isn't real → SYSMIS.

## Functions implemented
| Function | Notes |
|---|---|
| ABS, SQRT, EXP, LN, LG10 | one argument |
| RND(x) | round half away from zero |
| TRUNC(x) | toward zero |
| MOD(a, b) | sign follows a; b = 0 → SYSMIS |
| SUM, MEAN, SD, VARIANCE, MIN, MAX | over the valid arguments. `FN.n(...)` requires at least n valid arguments, otherwise SYSMIS. The default minimum is 1 (2 for SD/VARIANCE). |
| NVALID, NMISS | count of valid / missing arguments |
| MISSING(x) | 1 if x is user- or system-missing |
| SYSMIS(x) | 1 if x is system-missing |
| VALUE(var) | the raw value, ignoring user-missing status |

## Open questions
- Exact warning texts and when SPSS stops repeating them (MXWARNS); string expressions; date functions.
