#!/usr/bin/env python3
"""Fail early when analyzer quick-fixes reintroduce incompatible source APIs."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "lib/AmitarGalleryPlayer.dart"
PUBSPEC = ROOT / "pubspec.yaml"
LOCK = ROOT / "pubspec.lock"
ACTIVITY = ROOT / "android/app/src/main/kotlin/com/amitar/amitar_gallery_player/MainActivity.kt"


def validate() -> list[str]:
    errors: list[str] = []
    source = SOURCE.read_text(encoding="utf-8")
    pubspec = PUBSPEC.read_text(encoding="utf-8")
    lock = LOCK.read_text(encoding="utf-8")
    activity = ACTIVITY.read_text(encoding="utf-8")

    if re.search(r"(?m)^\s*cross_file\s*:", pubspec):
        errors.append("cross_file must remain a transitive dependency; do not add it directly.")
    if "package:cross_file/" in source:
        errors.append("The application must not import package:cross_file directly.")
    for obsolete in (".fileSystem(", ".scopedStorage("):
        if obsolete in source:
            errors.append(f"The incompatible XFile API {obsolete} is still present.")
    if "onReorderItem: c.reorderQueue" not in source:
        errors.append("The queue must use ReorderableListView.onReorderItem.")
    if re.search(r"\bonReorder\s*:", source):
        errors.append("Deprecated onReorder callback remains in the application source.")

    match = re.search(
        r"(?ms)^  cross_file:\n(.*?)(?=^  [A-Za-z0-9_]+:\n|\Z)", lock
    )
    if match is None:
        errors.append("pubspec.lock does not contain the cross_file package record.")
    else:
        block = match.group(1)
        if "dependency: transitive" not in block:
            errors.append("pubspec.lock must record cross_file as transitive.")
        if 'version: "0.3.5+5"' not in block:
            errors.append("pubspec.lock must resolve cross_file 0.3.5+5 for file_picker 13.x.")

    channel = "com.amitar.amitar_gallery_player/content_uri"
    for label, text in (("Dart", source), ("Android", activity)):
        if channel not in text:
            errors.append(f"{label} content-URI channel does not match the project contract.")
    if "copyToCache" not in source or "copyToCache" not in activity:
        errors.append("Dart and Android must both implement copyToCache.")
    if "_readAndroidContentUriBytes" not in source or "ContentResolver" not in activity:
        errors.append("Legacy Android content:// reads are not wired end-to-end.")
    if "Media.memory(" not in source:
        errors.append("Scoped-storage playback must use the bounded in-memory media path.")
    if "media_kit_libs_video:" not in pubspec or "media_kit_libs_audio:" in pubspec:
        errors.append("The project must use exactly the media_kit video runtime bundle.")

    return errors


def main() -> int:
    errors = validate()
    if errors:
        for error in errors:
            print(f"::error::{error}", file=sys.stderr)
        print(f"Source contract validation failed with {len(errors)} issue(s).", file=sys.stderr)
        return 1
    print("Dart, pubspec.lock, file_picker, queue and Android content-URI contracts are consistent.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
