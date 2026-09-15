#!/usr/bin/env python3
"""Turn test-results/junit.xml into a per-row table and fail only when a
row that ACCEPTANCE.md marks as required for this repository did not pass.
Used by ci.yml and release.yml; the table goes into the job summary and the
release notes. Rows not required are recorded as they are."""
import collections, re, sys, xml.etree.ElementTree as ET

REQUIRED = {1, 2, 4, 6, 7, 8, 10, 13, 16, 17}
path = sys.argv[1] if len(sys.argv) > 1 else "test-results/junit.xml"
rows = collections.OrderedDict()
for c in ET.parse(path).getroot().iter("testcase"):
    m = re.match(r"test_row(\d+)", c.get("name", ""))
    if not m:
        continue
    st = "FAIL" if (c.find("failure") is not None or c.find("error") is not None) else (
        "SKIP" if c.find("skipped") is not None else "PASS")
    rows.setdefault(int(m.group(1)), []).append(st)
bad = []
print("| Row | Result |\n|---|---|")
for r in sorted(rows):
    st = "FAIL" if "FAIL" in rows[r] else ("SKIP" if set(rows[r]) == {"SKIP"} else "PASS")
    print(f"| {r} | {st}{' (required)' if r in REQUIRED else ''} |")
    if r in REQUIRED and st != "PASS":
        bad.append(r)
if bad:
    sys.exit(f"required rows not passing: {bad}")
