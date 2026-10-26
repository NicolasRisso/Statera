* Shared synthetic survey used by the procedure golden cases.
* Ties, value labels, user-missing (score 999, rating 9) and system-missing values are deliberate.
DATA LIST FREE / id sex grp age score rating wgt.
BEGIN DATA
 1 1 1 23  71.5  4 1.0
 2 2 1 35  64.25 3 2.0
 3 1 2 41  88    5 1.0
 4 2 2 29  .     2 0.5
 5 2 3 52  79.75 4 1.0
 6 1 3 47  999   9 1.5
 7 1 1 23  71.5  1 1.0
 8 2 2 61  92.5  5 1.0
 9 2 1 38  58    3 2.5
10 1 3 33  66.75 3 1.0
11 2 2 45  .     4 1.0
12 1 1 27  83.5  9 1.0
13 2 3 55  77    2 0.5
14 1 2 31  69.25 4 1.0
15 2 1 42  71.5  5 1.0
16 1 3 36  95    3 2.0
17 2 2 50  61.5  1 1.0
18 1 1 23  74    4 1.0
19 2 3 64  80.25 5 1.0
20 1 2 39  999   3 1.0
END DATA.
FORMATS id sex grp rating (F2.0) age (F3.0) score (F6.2) wgt (F4.1).
VARIABLE LABELS sex 'Sex' grp 'Study group' age 'Age (years)' score 'Exam score'
  rating 'Course rating' wgt 'Sampling weight'.
VALUE LABELS sex 1 'Male' 2 'Female'
  /grp 1 'Control' 2 'Online' 3 'Blended'
  /rating 1 'Very poor' 2 'Poor' 3 'Fair' 4 'Good' 5 'Excellent' 9 'No answer'.
MISSING VALUES score (999) rating (9).
VARIABLE LEVEL id sex grp (NOMINAL) rating (ORDINAL) age score wgt (SCALE).
SAVE OUTFILE='@OUT@/survey.sav'.
