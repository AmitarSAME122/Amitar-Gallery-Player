#!/usr/bin/env python3
"""Collect the exact Dart/configuration source snapshot produced by quality CI.

Only files that are allowed to be modified by the quality job are included.
The resolved pubspec.lock is intentionally published as a separate artifact.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
ROOT_CONFIGS = {"pubspec.yaml", "analysis_options.yaml"}


def _git_paths(root: Path, args: list[str]) -> set[str]:
    result = subprocess.run(
        ["git", *args],
        cwd=root,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"Git could not enumerate CI source changes: {detail}")
    return {
        item.decode("utf-8", errors="strict").replace("\\", "/")
        for item in result.stdout.split(b"\0")
        if item
    }


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



def _reject_symlink_components(root: Path, candidate: Path) -> None:
    root = root.resolve()
    try:
        relative = candidate.relative_to(root)
    except ValueError as error:
        raise ValueError(f"Source path escapes the project root: {candidate}") from error
    current = root
    for part in relative.parts:
        current = current / part
        if current.is_symlink():
            raise ValueError(f"Symbolic links are not permitted in quality snapshots: {current}")


def collect(root: Path, output: Path) -> list[str]:
    root = root.resolve()
    output_input = Path(output)
    if output_input.is_symlink():
        raise ValueError("The snapshot output path must not be a symbolic link.")
    output = output_input.resolve()
    if output == root or root in output.parents:
        raise ValueError("The snapshot output directory must be outside the project root.")

    tracked = _git_paths(
        root,
        [
            "diff", "--name-only", "-z", "--diff-filter=ACMRT", "HEAD", "--",
            "lib", "test", "pubspec.yaml", "analysis_options.yaml",
        ],
    )
    untracked = _git_paths(
        root,
        ["ls-files", "--others", "--exclude-standard", "-z", "--", "lib", "test"],
    )
    files = sorted(path for path in tracked | untracked if allowed_source_path(path))

    if output.exists():
        if output.is_dir():
            shutil.rmtree(output)
        else:
            output.unlink()
    output.mkdir(parents=True, exist_ok=True)
    (output / "changed-files.txt").write_text(
        "".join(f"{name}\n" for name in files), encoding="utf-8", newline="\n"
    )

    for relative in files:
        source = root.joinpath(*PurePosixPath(relative).parts)
        _reject_symlink_components(root, source)
        if not source.is_file():
            raise RuntimeError(f"Refusing to include a missing or symlinked source: {relative}")
        destination = output.joinpath(*PurePosixPath(relative).parts)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)

    print(f"Collected {len(files)} CI-modified source/config files into {output}.")
    for name in files:
        print(f"  {name}")
    return files


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        collect(args.root, args.output_dir)
    except (OSError, RuntimeError, ValueError) as error:
        print(f"CI SNAPSHOT COLLECTION FAILED: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
