#!/usr/bin/env python3
"""Verify build outputs and generate runner-specific SHA-256 manifests."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
ENTRYPOINT = "lib/AmitarGalleryPlayer.dart"


def read_app_version() -> str:
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"(?m)^version:\s*['\"]?(\d+\.\d+\.\d+)\+\d+['\"]?\s*$", text)
    if not match:
        raise RuntimeError("Could not read a semantic app version from pubspec.yaml.")
    return match.group(1)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True, help="Stable runner label used in manifest filenames")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9-]+", args.label):
        parser.error("label must contain lowercase ASCII letters, digits or hyphens")

    manifest_path = DIST / "BUILD-MANIFEST.json"
    if not manifest_path.is_file():
        raise FileNotFoundError(f"Missing build manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    version = read_app_version()
    if manifest.get("version") != version or manifest.get("entrypoint") != ENTRYPOINT:
        raise RuntimeError("Build manifest version or Dart entrypoint does not match the source release identity.")
    if not (ROOT / ENTRYPOINT).is_file():
        raise FileNotFoundError(f"Missing declared Dart entrypoint: {ENTRYPOINT}")

    declared = manifest.get("artifacts")
    if not isinstance(declared, list) or not declared:
        raise RuntimeError("Build manifest contains no artifacts.")
    seen: set[str] = set()
    for item in declared:
        if not isinstance(item, dict):
            raise RuntimeError("Malformed artifact record in build manifest.")
        name = item.get("file")
        if not isinstance(name, str) or not name or "/" in name or "\\" in name or Path(name).name != name or name in seen:
            raise RuntimeError(f"Unsafe or duplicate artifact filename in manifest: {name!r}")
        seen.add(name)
        path = DIST / name
        if not path.is_file():
            raise FileNotFoundError(f"Build manifest references a missing artifact: {name}")
        if path.stat().st_size <= 0 or path.stat().st_size != item.get("bytes") or digest(path) != item.get("sha256"):
            raise RuntimeError(f"Artifact integrity mismatch: {name}")

    destination = DIST / f"BUILD-MANIFEST-{args.label}.json"
    manifest_path.replace(destination)
    old_sums = DIST / "SHA256SUMS.txt"
    if old_sums.exists():
        old_sums.unlink()
    sums = DIST / f"SHA256SUMS-{args.label}.txt"
    files = sorted(path for path in DIST.iterdir() if path.is_file() and path != sums)
    sums.write_text("".join(f"{digest(path)}  {path.name}\n" for path in files), encoding="utf-8")
    print(f"Verified {len(declared)} build artifacts for {args.label}; emitted {sums.name}.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, json.JSONDecodeError) as error:
        print(f"FINALIZE FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
