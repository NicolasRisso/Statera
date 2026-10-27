* ONEWAY: default ANOVA, then descriptives, homogeneity (Levene) and Welch.
GET FILE='@ROOT@/tests/golden/data/expected/survey.sav'.
ONEWAY score BY grp.
ONEWAY score age BY grp /STATISTICS=DESCRIPTIVES HOMOGENEITY WELCH.
