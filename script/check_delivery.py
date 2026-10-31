#!/usr/bin/env python3
"""Recheck source, built resources, and preserved media evidence without a launch."""
import json
import re
from pathlib import Path
import subprocess
import sys

from source_digest import ROOT, snapshot

evidence = Path(sys.argv[1])
derived_data = Path.home() / "Library/Caches/LogBatch/DerivedData"
expected = json.loads((evidence / "tested-source.json").read_text())
assert snapshot() == expected, "Build or test inputs changed after the recorded test run"
test_log = (evidence / "tests.log").read_text()
assert "** TEST SUCCEEDED **" in test_log
test_counts = [int(value) for value in re.findall(r"Executed (\d+) tests, with 0 failures", test_log)]
assert test_counts and max(test_counts) >= 19
assert "** BUILD SUCCEEDED **" in (evidence / "build.log").read_text()
for relative in ("Core/Resources/Localizable.xcstrings", "LogBatch/Resources/Localizable.xcstrings",
                 "FinderExtension/Resources/Localizable.xcstrings"):
    catalog = json.loads((ROOT / relative).read_text())
    for key, entry in catalog["strings"].items():
        for locale in ("en", "zh-Hans", "ja", "ko"):
            unit = entry["localizations"][locale]["stringUnit"]
            assert unit["state"] == "translated" and unit["value"], (relative, key, locale)
for arguments in (
    ["script/sync_dji_luts.py"],
    ["script/verify_bundle.py", str(derived_data / "Build/Products/Debug/LogLift for DJI.app")],
    ["script/verify_media.py", str(evidence)],
):
    subprocess.run([sys.executable, *arguments], cwd=ROOT, check=True)
print("Delivery inputs match the tested source. Build, Swift tests, artwork, resources, media, and catalogs verified.")

