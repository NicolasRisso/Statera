"""Generate golden reference output by running test cases on a licensed SPSS install.

Run with the Python that ships with SPSS (it provides the `spss` module), e.g.:
    "C:\\Program Files\\IBM\\SPSS\\Statistics\\25\\Python3\\python.exe" scripts/golden/make_reference.py [case ...]

Each case is a directory tests/golden/<case>/ containing `case.sps`. In the syntax,
`@OUT@` expands to the case's `expected/` directory and `@ROOT@` to the repository root
(cases share datasets via @ROOT@/tests/golden/data/...). Table output is captured as OMS XML
(Notes tables excluded, since they hold machine-specific paths and timings) into expected/oms.xml.

Must stay compatible with Python 3.4 (bundled with SPSS 25).
"""
import io
import os
import re
import sys

import spss

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GOLDEN = os.path.join(ROOT, "tests", "golden")


def fwd(path):
    return path.replace("\\", "/")


def run_case(name):
    case_dir = os.path.join(GOLDEN, name)
    expected = os.path.join(case_dir, "expected")
    if not os.path.isdir(expected):
        os.makedirs(expected)

    with io.open(os.path.join(case_dir, "case.sps"), encoding="utf-8") as f:
        syntax = f.read().replace("@OUT@", fwd(expected)).replace("@ROOT@", fwd(ROOT))

    oms_path = os.path.join(expected, "oms.xml")
    # OUTPUT CLOSE is rejected in external (headless) mode, so only reset the data side.
    spss.Submit("NEW FILE.\nDATASET CLOSE ALL.\nSET PRINTBACK=OFF.")
    spss.Submit("OMS /SELECT TABLES /EXCEPTIF SUBTYPES=['Notes'] "
                "/DESTINATION FORMAT=OXML OUTFILE='%s'." % fwd(oms_path))
    try:
        spss.Submit(syntax)
    finally:
        spss.Submit("OMSEND.")

    # Strip absolute paths of this machine so references are reproducible.
    with io.open(oms_path, encoding="utf-8") as f:
        xml = f.read()
    xml = xml.replace(fwd(expected), "@OUT@").replace(expected, "@OUT@")
    xml = xml.replace(fwd(ROOT), "@ROOT@").replace(ROOT, "@ROOT@")
    xml = re.sub(r'(date|duration)="[^"]*"', r'\1=""', xml)
    with io.open(oms_path, "w", encoding="utf-8", newline="\n") as f:
        f.write(xml)
    print("reference written:", name)


def main():
    cases = sys.argv[1:] or sorted(
        d for d in os.listdir(GOLDEN) if os.path.isfile(os.path.join(GOLDEN, d, "case.sps")))
    # `data` builds the shared datasets other cases read, so it runs first.
    if "data" in cases:
        cases.remove("data")
        cases.insert(0, "data")
    for name in cases:
        run_case(name)


if __name__ == "__main__":
    main()
