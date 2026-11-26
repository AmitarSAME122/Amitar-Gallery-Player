"""Ensure every Python helper invoked by checked-in GitHub workflows exists."""
from __future__ import annotations

import re
import unittest
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = (
    ROOT / ".github/workflows/build.yml",
    ROOT / ".github/workflows/refresh-source-manifest.yml",
)
PYTHON_TOOL_COMMAND = re.compile(
    r"(?<![A-Za-z0-9_])python3?\s+(tool/[A-Za-z0-9_./-]+\.py)(?![A-Za-z0-9_./-])"
)


class WorkflowToolPathTests(unittest.TestCase):
    def test_every_python_tool_invoked_by_workflows_exists(self) -> None:
        missing: list[str] = []
        referenced: set[str] = set()
        for workflow in WORKFLOWS:
            self.assertTrue(workflow.is_file(), f"Missing workflow: {workflow.relative_to(ROOT)}")
            content = workflow.read_text(encoding="utf-8")
            for raw_path in PYTHON_TOOL_COMMAND.findall(content):
                path = PurePosixPath(raw_path)
                self.assertFalse(path.is_absolute(), raw_path)
                self.assertNotIn("..", path.parts, raw_path)
                relative = path.as_posix()
                referenced.add(relative)
                if not (ROOT / relative).is_file():
                    missing.append(f"{workflow.relative_to(ROOT)} -> {relative}")
        self.assertTrue(referenced, "No Python tool invocations were found in the workflows.")
        self.assertFalse(
            missing,
            "GitHub Actions references Python tool files that are not committed:\n"
            + "\n".join(missing),
        )

    def test_snapshot_and_contract_helpers_are_part_of_the_tooling(self) -> None:
        required = {
            "tool/validate_source_contracts.py",
            "tool/collect_ci_snapshot.py",
            "tool/apply_ci_snapshot.py",
            "tool/test_ci_snapshot.py",
        }
        absent = sorted(path for path in required if not (ROOT / path).is_file())
        self.assertFalse(absent, "Missing CI snapshot/contract helpers: " + ", ".join(absent))


if __name__ == "__main__":
    unittest.main()
