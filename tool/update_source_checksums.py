#!/usr/bin/env python3
"""Generate a cross-platform SHA-256 manifest for tracked project source files.

Text files are hashed in canonical LF form. This is important for extensionless
Flutter files such as ``.metadata``: Git can consider CRLF and LF checkouts
identical while a raw-byte SHA-256 still differs between Windows and Linux.
Binary assets are always hashed byte-for-byte.
"""
from __future__ import annotations

import hashlib
import os
import subprocess
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "SHA256SUMS.txt"

# Keep this list in sync with the invariant test. Unknown/extensionless files
# default to text so `.metadata` and `pubspec.lock` receive deterministic hashes.
BINARY_SUFFIXES = frozenset(
    {
        ".png",
        ".pdf",
        ".ico",
        ".jpg",
        ".jpeg",
        ".gif",
        ".webp",
        ".bmp",
        ".zip",
        ".aab",
        ".apk",
        ".exe",
        ".dmg",
        ".deb",
        ".tar",
        ".gz",
        ".jar",
        ".woff",
        ".woff2",
        ".ttf",
        ".otf",
        ".dll",
        ".so",
        ".dylib",
        ".class",
        ".wasm",
        ".bin",
        ".mp4",
        ".mov",
        ".mp3",
        ".wav",
        ".aiff",
        ".sqlite",
        ".db",
        ".jks",
        ".keystore",
    }
)

# These are machine-local, secret-bearing, generated or separately verified
# files. They must not enter the source manifest, even if accidentally tracked.
EXCLUDED_PATHS = frozenset(
    {
        "SHA256SUMS.txt",
        "android/local.properties",
        "android/key.properties",
        "android/gradle/wrapper/gradle-wrapper.jar",
    }
)


def canonicalize_source_bytes(relative_path: str | Path, data: bytes) -> bytes:
    """Return the bytes used for source hashing, independent of checkout EOL.

    Only known binary formats are hashed verbatim. All other tracked files are
    treated as UTF-8/text sources and CRLF is normalized to LF. This deliberately
    treats dotfiles without suffixes (notably `.metadata`) as text.
    """
    relative = PurePosixPath(str(relative_path).replace("\\", "/"))
    name = relative.as_posix()
    suffix = Path(name).suffix.lower()
    if name.endswith(".tar.gz") or suffix in BINARY_SUFFIXES:
        return data
    return data.replace(b"\r\n", b"\n")


def tracked_source_paths() -> list[str]:
    """Return sorted repository-relative paths from Git's index."""
    command = ["git", "ls-files", "-z"]
    result = subprocess.run(
        command,
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"Could not list Git-tracked source files: {message}")

    paths: list[str] = []
    for raw_path in result.stdout.split(b"\0"):
        if not raw_path:
            continue
        relative = PurePosixPath(os.fsdecode(raw_path).replace("\\", "/"))
        normalized = relative.as_posix()
        if relative.is_absolute() or ".." in relative.parts:
            raise RuntimeError(f"Unsafe path returned by Git: {normalized}")
        if normalized in EXCLUDED_PATHS:
            continue
        paths.append(normalized)
    return sorted(set(paths))


def build_manifest() -> str:
    lines: list[str] = []
    for relative in tracked_source_paths():
        target = ROOT.joinpath(*PurePosixPath(relative).parts)
        if not target.is_file():
            raise FileNotFoundError(
                f"Git tracks {relative}, but the working-tree file is missing. "
                "Restore it or stage its deletion before generating the manifest."
            )
        raw = target.read_bytes()
        canonical = canonicalize_source_bytes(relative, raw)
        digest = hashlib.sha256(canonical).hexdigest()
        lines.append(f"{digest}  {relative}")
    return "\n".join(lines) + "\n"


def main() -> int:
    try:
        manifest_text = build_manifest()
        temporary = MANIFEST.with_name(MANIFEST.name + ".tmp")
        temporary.write_text(manifest_text, encoding="utf-8", newline="\n")
        temporary.replace(MANIFEST)
    except (OSError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    count = sum(1 for line in manifest_text.splitlines() if line)
    print(f"Updated {MANIFEST.name}: {count} tracked files (canonical LF text hashes).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
