#!/usr/bin/env python3
"""Run Flutter or Dart through the same robust resolver used by build tooling."""
from __future__ import annotations

import subprocess
import sys

from flutter_command import sdk_command


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in {"flutter", "dart"}:
        print("Usage: python tool/run_sdk.py <flutter|dart> <arguments...>", file=sys.stderr)
        return 2
    try:
        command = sdk_command(sys.argv[1], *sys.argv[2:])
        print("+", " ".join(command), flush=True)
        return subprocess.run(command, check=False).returncode
    except (FileNotFoundError, OSError, ValueError) as error:
        print(f"SDK COMMAND FAILED: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
