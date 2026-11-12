#!/usr/bin/env python3
"""Safely apply the exact source and dependency lock analyzed by quality CI."""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
ROOT_CONFIGS = {"pubspec.yaml", "analysis_options.yaml"}


def allowed_source_path(relative: str) -> bool:
    if not relative or any(ord(character) < 32 for character in relative):
        return False
    path = PurePosixPath(relative)
    if path.is_absolute() or ".." in path.parts or "\\" in relative:
        return False
    if path.as_posix() != relative:
        return False
    if relative in ROOT_CONFIGS:
        return True
    return (
        len(path.parts) >= 2
        and path.parts[0] in {"lib", "test"}
        and path.suffix == ".dart"
    )


def _inside(base: Path, candidate: Path) -> bool:
    try:
        candidate.resolve(strict=False).relative_to(base.resolve())
        return True
    except ValueError:
        return False


def _reject_symlink_components(base: Path, candidate: Path) -> None:
    base = base.resolve()
    try:
        relative = candidate.relative_to(base)
    except ValueError as error:
        raise ValueError(f"Path escapes expected root: {candidate}") from error
    current = base
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError(f"Symbolic links are not permitted in snapshot paths: {current}")


def apply_snapshot(
    root: Path,
    artifact_dir: Path,
    lock_file: Path | None = None,
) -> list[str]:
    root = root.resolve()
    if artifact_dir.is_symlink():
        raise ValueError("Snapshot artifact directory must not be a symbolic link.")
    artifact_dir = artifact_dir.resolve()
    manifest = artifact_dir / "changed-files.txt"
    if not manifest.is_file() or manifest.is_symlink() or not _inside(artifact_dir, manifest):
        raise FileNotFoundError(f"Missing safe CI snapshot manifest: {manifest}")

    raw_names = manifest.read_text(encoding="utf-8").splitlines()
    names: list[str] = []
    seen: set[str] = set()
    for raw in raw_names:
        if not raw:
            continue
        if not allowed_source_path(raw):
            raise ValueError(f"Snapshot contains a disallowed path: {raw!r}")
        if raw in seen:
            raise ValueError(f"Snapshot contains a duplicate path: {raw}")
        seen.add(raw)
        names.append(raw)

    for relative in names:
        parts = PurePosixPath(relative).parts
        source = artifact_dir.joinpath(*parts)
        destination = root.joinpath(*parts)
        _reject_symlink_components(artifact_dir, source)
        _reject_symlink_components(root, destination)
        if not source.is_file() or not _inside(artifact_dir, source):
            raise ValueError(f"Snapshot source is missing or unsafe: {relative}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + ".ci-snapshot-tmp")
        shutil.copyfile(source, temporary)
        temporary.replace(destination)

    if lock_file is not None:
        lock_input = Path(lock_file)
        if lock_input.is_symlink():
            raise ValueError("Resolved pubspec.lock artifact must not be a symbolic link.")
        lock_source = lock_input.resolve()
        lock_destination = root / "pubspec.lock"
        _reject_symlink_components(root, lock_destination)
        if not lock_source.is_file():
            raise FileNotFoundError(f"Resolved pubspec.lock artifact is missing: {lock_source}")
        temporary = lock_destination.with_name(lock_destination.name + ".ci-snapshot-tmp")
        shutil.copyfile(lock_source, temporary)
        temporary.replace(lock_destination)
        names.append("pubspec.lock")

    print(f"Applied {len(names)} analyzed source/config files to {root}.")
    for name in names:
        print(f"  {name}")
    return names


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--artifact-dir", type=Path, required=True)
    parser.add_argument("--lock-file", type=Path)
    args = parser.parse_args()
    try:
        apply_snapshot(args.root, args.artifact_dir, args.lock_file)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"CI SNAPSHOT APPLICATION FAILED: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
