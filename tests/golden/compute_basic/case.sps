* COMPUTE: arithmetic, missing propagation, functions and logical results.
GET FILE='@ROOT@/tests/golden/data/expected/survey.sav'.
COMPUTE score_pct = score / 100.
COMPUTE age_sq = age ** 2.
COMPUTE z = (age - 40) / 10 + 2 * -1.
COMPUTE m = MEAN(score, rating, age).
COMPUTE m2 = MEAN.3(score, rating, age).
COMPUTE s = SUM(score, rating).
COMPUTE r = RND(score / 3).
COMPUTE t = TRUNC(-score / 3).
COMPUTE root = SQRT(age - 30).
COMPUTE lg = LN(age) + LG10(age) + EXP(1).
COMPUTE md = MOD(age, 7).
COMPUTE ab = ABS(30 - age).
COMPUTE mn = MIN(age, rating) + MAX(sex, grp).
COMPUTE nv = NVALID(score, rating) + 10 * NMISS(score, rating).
COMPUTE miss = MISSING(score) + 2 * SYSMIS(score).
COMPUTE raw = VALUE(score).
COMPUTE div0 = age / (sex - sex).
COMPUTE older = age > 40.
COMPUTE both = age > 40 AND score > 70.
COMPUTE either = age > 40 OR rating >= 4.
COMPUTE neg = NOT (sex = 1).
COMPUTE noteq = grp <> 2 & grp ~= 3.
COMPUTE age = age + 1.
SAVE OUTFILE='@OUT@/computed.sav'.
DESCRIPTIVES score_pct age_sq z m m2 s r t root lg md ab mn nv miss raw div0 older both either neg noteq age.
