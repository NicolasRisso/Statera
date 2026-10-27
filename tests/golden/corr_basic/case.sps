* CORRELATIONS: pairwise default, descriptives + cross-products, listwise, one-tailed, WITH.
GET FILE='@ROOT@/tests/golden/data/expected/survey.sav'.
CORRELATIONS /VARIABLES=age score rating.
CORRELATIONS /VARIABLES=age score /PRINT=ONETAIL NOSIG /STATISTICS=DESCRIPTIVES XPROD /MISSING=LISTWISE.
CORRELATIONS /VARIABLES=age rating WITH score.
COMPUTE age2 = age + MOD(id, 3).
COMPUTE agemix = age + 4 * MOD(id, 5).
CORRELATIONS /VARIABLES=age age2 agemix score /PRINT=NOSIG.
