# Procedure context: WEIGHT, FILTER, SELECT IF, SPLIT FILE, TEMPORARY, SORT CASES
Status: draft (verified by tests/golden/ctx_weight, ctx_filter, ctx_split)
Sources: Command Syntax Reference (public); black-box runs; the reference architecture ([architecture.md](../architecture.md)), which shows the core prepares the case stream and procedures apply weights.

## Case stream seen by a procedure
1. Start from the active dataset after all executed transformations.
2. **FILTER BY v** excludes cases whose `v` is 0 or missing. The cases stay in the file. `FILTER OFF` ends it.
3. **WEIGHT BY v** (`WEIGHT OFF` ends it): each case counts with weight `v`. Cases whose weight is **zero, negative or missing are excluded**, and the procedure emits **Warning 3211** once ("On at least one case, the value of the weight variable was zero, negative, or missing…").
4. **SPLIT FILE**: the stream is cut into groups of *consecutive* cases with equal values of the split variables. The file isn't sorted automatically, so use SORT CASES first.

## Commands
- `SELECT IF (expr)` permanently deletes cases where expr is not true (false or missing).
- `TEMPORARY` makes the transformations and settings that follow (COMPUTE, SELECT IF, WEIGHT, FILTER, SPLIT FILE) apply **only to the next procedure**. After that procedure everything reverts. Procedures include FREQUENCIES, DESCRIPTIVES, SAVE and EXECUTE.
- `SORT CASES BY v1 [(A|D)] v2 …` is a stable sort. The direction applies to the variables listed before it. SYSMIS sorts lowest.
- `SPLIT FILE [LAYERED | SEPARATE] BY varlist` (LAYERED is the default). `SPLIT FILE OFF` ends it.

## Weighted statistics (W = sum of the weights of valid cases)
- Counts (N, Frequency, Valid N listwise) are **unrounded weighted sums**. The display rounds them to integers half away from zero (9.5 → `10`).
- Percentages use the unrounded counts.
- Moments: mean = Σwx/W; variance = Σw(x−mean)²/(W−1). Skewness, kurtosis and every standard error use the unweighted formulas **with n replaced by W**.
- Sum = Σwx, displayed with the variable's decimals (43.5 with d = 0 → `44`).
- Mode: the value with the largest weighted count. Ties take the smallest value and add the footnote.
- Percentiles (HAVERAGE): expand the sorted values by cumulative weight. t = (W+1)p and k = ⌊t⌋; the value at position k plus (t−k)·(next value − it), where the value at position j is the first value whose cumulative weight is ≥ j.

## Split-file output
- **LAYERED:** one table per output. The split values (value label, or else the formatted value) become the outermost row categories, nested in split-variable order: `Male / Age (years)`, or with two variables `Blended / Male / …`. FREQUENCIES' Statistics table repeats `N / Valid`, `N / Missing` and the statistics within each group.
- **SEPARATE:** each group's tables are preceded by a heading `Sex = Male`, and each table carries the same text as a table caption (a table-level footnote in OMS). The text is the split variable's label (or name), ` = `, and the value label.
- Groups appear in data order.

## Other observed details
- FREQUENCIES emits the "Frequency Table" heading only when more than one variable is analysed. With one variable, the Statistics table puts that variable in the layer dimension.

## Open questions
- The caption text format for SEPARATE with more than one split variable.
- Missing values of a split variable.
- Whether WEIGHT by a user-missing value excludes the case (assumed yes).
