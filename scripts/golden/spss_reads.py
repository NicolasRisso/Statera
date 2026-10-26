"""Check that real SPSS opens a .sav file, and print what it sees.

Run with the Python bundled with SPSS:
    "C:\\Program Files\\IBM\\SPSS\\Statistics\\25\\Python3\\python.exe" scripts/golden/spss_reads.py file.sav [...]

Used to verify files written by Statera. Must stay compatible with Python 3.4.
"""
import sys

import spss

def describe(path):
    spss.Submit("GET FILE='%s'." % path.replace("\\", "/"))
    print("==", path)
    n = spss.GetVariableCount()
    for i in range(n):
        print("  %-12s type=%-3d fmt=%-8s measure=%-8s label=%r missing=%r" % (
            spss.GetVariableName(i), spss.GetVariableType(i), spss.GetVariableFormat(i),
            spss.GetVariableMeasurementLevel(i), spss.GetVariableLabel(i),
            spss.GetVarMissingValues(i)))
    cur = spss.Cursor()
    rows = cur.fetchall()
    cur.close()
    print("  cases:", len(rows))
    for row in rows:
        print("   ", row)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        describe(p)
