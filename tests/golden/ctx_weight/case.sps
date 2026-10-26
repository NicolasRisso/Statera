* WEIGHT: fractional weights, then zero and missing weights, then WEIGHT OFF.
GET FILE='@ROOT@/tests/golden/data/expected/survey.sav'.
WEIGHT BY wgt.
FREQUENCIES VARIABLES=grp rating /STATISTICS=MEAN MEDIAN MODE STDDEV SUM.
DESCRIPTIVES age score /STATISTICS=ALL.
COMPUTE w2 = wgt * (id <> 3).
COMPUTE w3 = w2 / (id <> 5).
WEIGHT BY w3.
FREQUENCIES VARIABLES=sex.
DESCRIPTIVES age.
WEIGHT OFF.
DESCRIPTIVES age.
