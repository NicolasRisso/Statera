* REGRESSION: simple and multiple linear regression with METHOD=ENTER.
GET FILE='@ROOT@/tests/golden/data/expected/survey.sav'.
REGRESSION /DEPENDENT score /METHOD=ENTER age.
REGRESSION /STATISTICS COEFF OUTS CI(95) R ANOVA /DEPENDENT score /METHOD=ENTER age rating sex.
REGRESSION /DESCRIPTIVES MEAN STDDEV CORR SIG N /DEPENDENT age /METHOD=ENTER score rating.
