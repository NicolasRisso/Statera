* CROSSTABS statistics: chi-square family on R x C and 2 x 2 tables, PHI/CC, weighted counts.
GET FILE='@ROOT@/tests/golden/data/expected/survey.sav'.
COMPUTE young = age < 40.
CROSSTABS /TABLES=grp BY rating /STATISTICS=CHISQ.
CROSSTABS /TABLES=sex BY young /STATISTICS=CHISQ PHI CC.
WEIGHT BY wgt.
CROSSTABS /TABLES=sex BY grp /CELLS=COUNT ROW /STATISTICS=CHISQ.
