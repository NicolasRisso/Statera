* CROSSTABS: default counts, cell percentages, several BY variables, user-missing rows.
GET FILE='@ROOT@/tests/golden/data/expected/survey.sav'.
CROSSTABS /TABLES=sex BY grp.
CROSSTABS /TABLES=grp BY rating /CELLS=COUNT ROW COLUMN TOTAL EXPECTED.
CROSSTABS /TABLES=sex grp BY rating.
