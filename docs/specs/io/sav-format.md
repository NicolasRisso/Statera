# SPSS system file (.sav / .zsav)
Status: draft (reader subset verified against `tests/golden/sav_basic`)
Sources: GNU PSPP manual, "System File Format" appendix (public documentation); hex study of files we generated (`tests/golden/sav_basic/expected/*.sav`).

## Behaviour

A system file is a sequence of records: one file header, then dictionary records, then a terminator, then case data. All integers are 32-bit and all floats 64-bit IEEE-754, in the byte order of the writing machine. A reader detects the byte order from `layout_code` in the header, which must read as 2 or 3. Strings are space-padded, not NUL-terminated.

### File header (176 bytes)
| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic: `$FL2` for .sav, `$FL3` for .zsav |
| 4 | 60 | product name of the writer (free text) |
| 64 | 4 | layout_code (2 or 3, also the endianness probe) |
| 68 | 4 | nominal_case_size: 8-byte segments per case, or -1 if unknown |
| 72 | 4 | compression: 0 none, 1 bytecode, 2 zlib (`$FL3` only) |
| 76 | 4 | weight_index: 1-based segment index of the weight variable, 0 if unweighted |
| 80 | 4 | ncases, or -1 if unknown |
| 84 | 8 | bias for bytecode compression (always 100.0 in practice) |
| 92 | 9 | creation date `dd mmm yy` |
| 101 | 8 | creation time `hh:mm:ss` |
| 109 | 64 | file label |
| 173 | 3 | padding |

### Dictionary records (each starts with an int32 record type)

**Type 2: variable.** One record per 8-byte segment.
- `width`: 0 = numeric; 1..255 = string width; -1 = continuation segment of the preceding string (it carries no other information and isn't a user-visible variable).
- `has_label` (0/1), `n_missing` (0..3 discrete values; -2 = range; -3 = range plus one discrete value), `print` and `write` formats, then an 8-byte short name.
- If `has_label`: int32 length, then the label bytes padded to a multiple of 4.
- Then `|n_missing|` 8-byte missing values. For strings these are 8 raw bytes each.
- A format is packed into an int32: bits 0–7 = decimals, 8–15 = width, 16–23 = format type (5 = F, 1 = A, …).

**Type 3: value labels**, immediately followed by **type 4**.
- Type 3: int32 count, then per label 8 raw value bytes, a u8 label length, and label bytes, padded so that (1 + length) is a multiple of 8.
- Type 4: int32 count, then that many 1-based **segment** indexes of the variables the labels apply to.

**Type 6: documents.** int32 line count, then 80-byte lines.

**Type 7: extension.** int32 subtype, int32 element size, int32 element count, then size×count bytes. Unknown subtypes must be skipped. Subtypes the reader uses:
| Subtype | Meaning |
|---|---|
| 3 | machine integer info (version, character code) |
| 4 | machine float info: SYSMIS, HIGHEST, LOWEST (3 × f64) |
| 11 | per-variable display info: count×3 int32 (measure, width, alignment) per user variable; measure 1 nominal, 2 ordinal, 3 scale |
| 13 | long names: `SHORT=Long` pairs separated by tab |
| 14 | very long strings (>255) |
| 16 | 64-bit case count |
| 20 | character encoding name (e.g. `UTF-8`) |
| 21, 22 | value labels / missing values for long strings |

**Type 999: end of dictionary**, followed by an int32 filler (0).

### Case data
- **Uncompressed:** each case is `nominal_case_size` 8-byte segments. A numeric is one f64. A string of width w uses ceil(w/8) segments.
- **Bytecode (compression=1):** the stream is groups of 8 one-byte opcodes. Each opcode yields one segment:
  - 0: padding, yields nothing
  - 1–251: numeric value `opcode - bias`
  - 252: end of data
  - 253: the segment is the next 8 raw bytes, which follow the opcode group in order
  - 254: 8 spaces (string segment)
  - 255: SYSMIS
- **Zlib (compression=2, `$FL3`):** after the dictionary comes a 24-byte zheader: zheader_ofs, ztrailer_ofs, ztrailer_len (int64 each). The ztrailer holds bias (i64), zero (i64), block_size (i32), n_blocks (i32), then per block: uncompressed_ofs (i64), compressed_ofs (i64), uncompressed_size (i32), compressed_size (i32). Each block is an independent zlib stream. Concatenated, the blocks form a bytecode stream decoded as above.

## Edge cases
- ncases may be -1. Read until end of data (opcode 252 or EOF on a segment boundary).
- SYSMIS is -DBL_MAX (bits `0xFFEFFFFFFFFFFFFF`). Readers take the value from subtype 4 when present.
- Variable indexes in type 4 records and `weight_index` count **segments**, not variables.
- Short names are upper-case. The case the user typed comes from subtype 13.

## Errors and warnings
- Bad magic or a layout_code other than 2/3 in either byte order means the file isn't a system file.
- A truncated record means a corrupt file. Report the byte offset.

## Open questions
- The writer side: which optional records SPSS 25 always emits, and in what order (needed for byte-identical writes).
- Behavior of opcode 0 at the end of the data stream vs. at the end of an opcode group.
