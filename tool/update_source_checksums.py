#!/usr/bin/env python3
"""Regenerate the deterministic SHA-256 manifest for tracked project files."""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "SHA256SUMS.txt"
EXCLUDED_PARTS = {".git", "__pycache__", ".dart_tool", ".pub", ".pub-cache", "build", "dist"}
EXCLUDED_FILES = {"android/gradle/wrapper/gradle-wrapper.jar"}  # downloaded and SHA-256 verified during bootstrap


def digest(path: Path) -> str:
    hasher = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def main() -> int:
    files = [
        path for path in ROOT.rglob("*")
        if path.is_file()
        and path != MANIFEST
        and path.relative_to(ROOT).as_posix() not in EXCLUDED_FILES
        and not any(part in EXCLUDED_PARTS for part in path.relative_to(ROOT).parts)
    ]
    lines = [f"{digest(path)}  {path.relative_to(ROOT).as_posix()}" for path in sorted(files)]
    MANIFEST.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {len(lines)} SHA-256 entries to {MANIFEST.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
