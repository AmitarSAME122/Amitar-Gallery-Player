#!/usr/bin/env python3
"""Resolve Flutter/Dart executables consistently from PATH and PowerShell sessions.

PowerShell profiles may expose Flutter as a function or alias while omitting its
SDK directory from the inherited process PATH. Python subprocesses cannot execute
those shell functions. This resolver asks PowerShell for the real application
path and returns flutter.bat/dart.bat (or the native executable) instead.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path


def _powershell_application(name: str) -> str | None:
    shell = shutil.which("pwsh") or shutil.which("powershell")
    if not shell:
        return None
    script = (
        f"$c = Get-Command -Name '{name}' -CommandType Application "
        "-ErrorAction SilentlyContinue | Select-Object -First 1; "
        "if ($null -ne $c) { [Console]::Write($c.Source) }"
    )
    try:
        result = subprocess.run(
            [shell, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", script],
            check=False, capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    candidate = result.stdout.strip()
    return candidate if candidate and Path(candidate).is_file() else None


def resolve_tool(name: str, *, required: bool = True) -> str | None:
    """Return a directly executable Flutter/Dart CLI path, never a shell alias."""
    if name not in {"flutter", "dart"}:
        raise ValueError(f"Unsupported SDK command: {name}")

    candidates: list[str] = []
    located = shutil.which(name)
    if located:
        candidates.append(located)
    if os.name == "nt":
        located_bat = shutil.which(f"{name}.bat")
        if located_bat:
            candidates.append(located_bat)
        powershell_path = _powershell_application(name)
        if powershell_path:
            candidates.append(powershell_path)
        roots = []
        root = os.environ.get("FLUTTER_ROOT")
        if root:
            roots.append(Path(root))
        local_app_data = os.environ.get("LOCALAPPDATA")
        if local_app_data:
            local = Path(local_app_data)
            # Common Windows SDK layouts, including the default
            # %LOCALAPPDATA%\Android\flutter location reported by Flutter Doctor.
            roots.extend([
                local / "Android" / "flutter",
                local / "flutter",
            ])
        roots.extend([Path("C:/src/flutter"), Path("C:/flutter")])
        for sdk_root in roots:
            candidates.extend([
                str(sdk_root / "bin" / f"{name}.bat"),
                str(sdk_root / "bin" / name),
            ])

    for candidate in candidates:
        path = Path(candidate)
        if path.is_file():
            return str(path.resolve())

    if required:
        raise FileNotFoundError(
            f"Cannot locate the Flutter SDK command '{name}'. Add <Flutter SDK>\\bin to PATH, "
            "set FLUTTER_ROOT, or ensure PowerShell can resolve the actual executable. "
            "A PowerShell function/alias alone is not visible to Python subprocesses."
        )
    return None


def _windows_cached_dart_command(executable: str, name: str, arguments: tuple[str, ...]) -> list[str] | None:
    """Use Flutter's bundled dart.exe directly, avoiding cmd.exe batch quoting.

    Flutter's Windows launcher ultimately invokes this exact Dart executable and
    `flutter_tools.snapshot`. Calling them directly is more reliable for Python
    subprocesses, especially when either the SDK or project path contains spaces.
    """
    sdk_root = Path(executable).parent.parent
    dart_executable = sdk_root / "bin" / "cache" / "dart-sdk" / "bin" / "dart.exe"
    if not dart_executable.is_file():
        return None
    if name == "dart":
        return [str(dart_executable), *arguments]
    flutter_snapshot = sdk_root / "bin" / "cache" / "flutter_tools.snapshot"
    if not flutter_snapshot.is_file():
        return None
    return [str(dart_executable), "--disable-dart-dev", str(flutter_snapshot), *arguments]


def sdk_command(name: str, *arguments: str) -> list[str]:
    """Build a subprocess argv using native SDK executables where possible."""
    executable = resolve_tool(name)
    assert executable is not None
    if os.name == "nt" and Path(executable).suffix.lower() in {".bat", ".cmd"}:
        cached_command = _windows_cached_dart_command(executable, name, arguments)
        if cached_command is not None:
            return cached_command

        # Fallback for an SDK whose bundled Dart cache has not been initialized.
        # The doubled outer quotes are required by cmd.exe's /s /c parsing rules;
        # the executable itself is always quoted even when its path has no spaces.
        cmd = shutil.which("cmd.exe") or os.environ.get("COMSPEC", "cmd.exe")
        quoted_executable = f'"{executable}"'
        quoted_arguments = subprocess.list2cmdline(list(arguments))
        command_line = f'"{quoted_executable} {quoted_arguments}"' if quoted_arguments else f'"{quoted_executable}"'
        return [cmd, "/d", "/s", "/c", command_line]
    return [executable, *arguments]


if __name__ == "__main__":
    try:
        print(resolve_tool(sys.argv[1] if len(sys.argv) > 1 else "flutter") or "")
    except (ValueError, FileNotFoundError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(2)
