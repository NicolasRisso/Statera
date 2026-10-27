* MEANS: default cells, nested BY, chosen cells, ANOVA statistics.
GET FILE='@ROOT@/tests/golden/data/expected/survey.sav'.
MEANS TABLES=score age BY grp.
MEANS TABLES=age BY sex BY grp /CELLS=MEAN COUNT STDDEV MIN MAX SUM.
MEANS TABLES=score BY grp /STATISTICS=ANOVA.
