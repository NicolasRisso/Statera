# Number display in pivot tables
Status: draft (verified by tests/golden/desc_basic, freq_basic, freq_stats)
Sources: black-box runs (OMS XML `text` vs `number` attributes).

## Behaviour
- Each cell holds the full value and its text, rendered with a fixed number of decimals.
- **Rounding:** half away from zero at the displayed precision (6.25 → `6.3`, 18.75 → `18.8`).
- **Leading zero:** dropped when |x| < 1: `0.396` → `.396`, `-0.654` → `-.654`.
- Counts (N, Frequency) are integers with no decimals.
- No thousands separators for F formats (`1204.25`).

## Decimal rules (d = decimals of the variable's print format)
| Statistic | Decimals |
|---|---|
| N, Frequency | 0 |
| Minimum, Maximum, Range, Sum, Mode | d |
| Mean, Median | d + 2 |
| Std. Deviation, Std. Error of Mean | d + 3 |
| Variance | 3 *(observed for d = 0 and d = 2; see open questions)* |
| Skewness, Kurtosis and their standard errors | 3 |
| Percent, Valid Percent, Cumulative Percent | 1 |

Values printed in a category label (e.g. a frequency-table row without a value label) use the variable's print format (`F6.2` → `58.00`).

## Open questions
- Is Variance's decimal count really fixed at 3, or `min(d + 3, 3)` style? Needs a d ≥ 3 case.
- Caps on decimals for wide formats, and very large or small magnitudes (E notation).
