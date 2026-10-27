* T-TEST: one-sample, independent samples, paired samples.
GET FILE='@ROOT@/tests/golden/data/expected/survey.sav'.
T-TEST /TESTVAL=70 /VARIABLES=score age.
T-TEST GROUPS=sex(1 2) /VARIABLES=score age.
T-TEST PAIRS=age WITH score (PAIRED).
