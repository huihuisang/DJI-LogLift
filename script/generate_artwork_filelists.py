#!/usr/bin/env python3
"""Declare the pinned artwork inputs and generated outputs for Xcode's script sandbox."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    products = json.loads((ROOT / "LogBatch/Resources/ProductImages/manifest.json").read_text())["products"]
    source_root = "$(SRCROOT)/LogBatch/Resources/ProductImages/"
    output_root = "$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/PreparedProductImages"
    lists = {
        "artwork-inputs.xcfilelist": [source_root + "manifest.json"] + [source_root + p["file"] for p in products],
        "artwork-outputs.xcfilelist": [output_root, output_root + "/manifest.json"] + [
            output_root + "/" + p["id"] + ".png" for p in products
        ],
    }
    for name, paths in lists.items():
        path = ROOT / "script" / name
        content = "\n".join(paths) + "\n"
        if args.check:
            if not path.is_file() or path.read_text() != content:
                parser.error("Artwork file lists are stale. Run xcodegen generate.")
        elif not path.is_file() or path.read_text() != content:
            path.write_text(content)


if __name__ == "__main__":
    main()
