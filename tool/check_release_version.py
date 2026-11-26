#!/usr/bin/env python3
"""Fail fast when the Git tag, pubspec, Dart app and installer versions drift."""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", help="Optional Git tag; must be v<pubspec-version>.")
    args = parser.parse_args()

    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    dart = (ROOT / "lib/AmitarGalleryPlayer.dart").read_text(encoding="utf-8")
    installer = (ROOT / "tool/installer/AmitarGalleryPlayer.iss").read_text(encoding="utf-8")

    pubspec_match = re.search(r"(?m)^version:\s*['\"]?(\d+\.\d+\.\d+)\+(\d+)", pubspec)
    dart_match = re.search(r"const String appVersion = '(\d+\.\d+\.\d+)';", dart)
    installer_match = re.search(r'#define AppVersion "(\d+\.\d+\.\d+)"', installer)
    if not (pubspec_match and dart_match and installer_match):
        raise RuntimeError("Could not read all version declarations (pubspec, Dart and Inno Setup).")

    versions = {pubspec_match.group(1), dart_match.group(1), installer_match.group(1)}
    if len(versions) != 1:
        raise RuntimeError("Version mismatch: " + ", ".join(sorted(versions)))

    version = pubspec_match.group(1)
    if args.tag and args.tag != f"v{version}":
        raise RuntimeError(f"Tag {args.tag!r} must equal v{version}.")

    print(f"AmitarGalleryPlayer version is consistent: {version} (build {pubspec_match.group(2)}).")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f"VERSION CHECK FAILED: {error}", file=sys.stderr)
        raise SystemExit(1)
