* Small dataset covering numeric formats, labels, user-missing and system-missing.
DATA LIST FREE / id grp score (F8.0 F8.0 F8.2).
BEGIN DATA
1 1 10.5
2 1 12.25
3 2 9
4 2 .
5 2 15.75
6 1 99
END DATA.
VARIABLE LABELS score 'Test score'.
VALUE LABELS grp 1 'Control' 2 'Treatment'.
MISSING VALUES score (99).
VARIABLE LEVEL id (NOMINAL) grp (NOMINAL) score (SCALE).
SAVE OUTFILE='@OUT@/uncompressed.sav' /UNCOMPRESSED.
SAVE OUTFILE='@OUT@/compressed.sav' /COMPRESSED.
SAVE OUTFILE='@OUT@/zcompressed.zsav' /ZCOMPRESSED.
FREQUENCIES grp.
DESCRIPTIVES score /STATISTICS=MEAN STDDEV MIN MAX.
