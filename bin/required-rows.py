#!/usr/bin/env python3
"""Turn test-results/junit.xml into a per-row table and fail when any row did
not PASS (a SKIP counts as a failure: a test that could not run proves
nothing). Used by ci.yml and release.yml; the table goes into the job
summary and the release notes."""
import collections, re, sys, xml.etree.ElementTree as ET

REQUIRED = set(range(1, 22))  # every row; a SKIP is a failure too
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
    if not rows:
        bad.append("no rows found")
if bad:
    sys.exit(f"required rows not passing: {bad}")
