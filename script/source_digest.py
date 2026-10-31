#!/usr/bin/env python3
"""Hash the build and test inputs to bind evidence to the tested source."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def snapshot():
    paths = []
    for name in ("Core", "LogBatch", "Tests", "script", "vendor", "LogBatch.xcodeproj", ".codex"):
        paths.extend(path for path in (ROOT / name).rglob("*") if path.is_file()
                     and "__pycache__" not in path.parts and "xcuserdata" not in path.parts)
    paths.extend(ROOT / name for name in ("project.yml", "AGENTS.md", ".gitignore", "README.md"))
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(paths)}


if __name__ == "__main__":
    print(json.dumps(snapshot(), sort_keys=True, indent=2))

