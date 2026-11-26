from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import flutter_command


class FlutterCommandTests(unittest.TestCase):
    def test_resolves_path_executable(self):
        with tempfile.TemporaryDirectory() as folder:
            executable = Path(folder) / "flutter"
            executable.write_text("#!/bin/sh\n", encoding="utf-8")
            with mock.patch.object(flutter_command.shutil, "which", side_effect=lambda name: str(executable) if name == "flutter" else None), \
                 mock.patch.object(flutter_command, "_powershell_application", return_value=None):
                self.assertEqual(flutter_command.resolve_tool("flutter"), str(executable.resolve()))

    @unittest.skipUnless(os.name == "nt", "Windows batch executable resolution")
    def test_prefers_direct_windows_batch_executable(self):
        with tempfile.TemporaryDirectory() as folder:
            executable = Path(folder) / "flutter.bat"
            executable.write_text("@echo off\n", encoding="utf-8")
            with mock.patch.object(flutter_command.shutil, "which", side_effect=lambda name: str(executable) if name == "flutter.bat" else None), \
                 mock.patch.object(flutter_command, "_powershell_application", return_value=None):
                self.assertEqual(flutter_command.resolve_tool("flutter"), str(executable.resolve()))


    @unittest.skipUnless(os.name == "nt", "Windows Flutter SDK default layout")
    def test_finds_flutter_in_default_local_android_sdk_layout(self):
        with tempfile.TemporaryDirectory() as folder:
            local = Path(folder)
            sdk = local / "Android" / "flutter"
            executable = sdk / "bin" / "flutter.bat"
            executable.parent.mkdir(parents=True)
            executable.write_text("@echo off\n", encoding="utf-8")
            with mock.patch.object(flutter_command.shutil, "which", return_value=None), \
                 mock.patch.object(flutter_command, "_powershell_application", return_value=None), \
                 mock.patch.dict(os.environ, {"LOCALAPPDATA": str(local), "FLUTTER_ROOT": ""}):
                self.assertEqual(flutter_command.resolve_tool("flutter"), str(executable.resolve()))


    def test_windows_flutter_uses_bundled_dart_and_tools_snapshot(self):
        with tempfile.TemporaryDirectory() as folder:
            sdk = Path(folder)
            flutter_bat = sdk / "bin/flutter.bat"
            dart_exe = sdk / "bin/cache/dart-sdk/bin/dart.exe"
            snapshot = sdk / "bin/cache/flutter_tools.snapshot"
            flutter_bat.parent.mkdir(parents=True)
            dart_exe.parent.mkdir(parents=True)
            snapshot.parent.mkdir(parents=True, exist_ok=True)
            flutter_bat.write_text("@echo off\n", encoding="utf-8")
            dart_exe.write_bytes(b"dart")
            snapshot.write_bytes(b"snapshot")
            command = flutter_command._windows_cached_dart_command(
                str(flutter_bat), "flutter", ("create", "--no-pub", ".")
            )
            self.assertIsNotNone(command)
            self.assertEqual(command[0], str(dart_exe))
            self.assertIn(str(snapshot), command)
            self.assertIn("--disable-dart-dev", command)
            self.assertEqual(command[-2:], ["--no-pub", "."])

    def test_windows_batch_fallback_uses_nested_cmd_quotes(self):
        with mock.patch.object(flutter_command.os, "name", "nt"), \
             mock.patch.object(flutter_command, "resolve_tool", return_value=r"C:\Flutter SDK\bin\flutter.bat"), \
             mock.patch.object(flutter_command, "_windows_cached_dart_command", return_value=None), \
             mock.patch.object(flutter_command.shutil, "which", return_value=r"C:\Windows\System32\cmd.exe"):
            command = flutter_command.sdk_command("flutter", "create", "--no-pub", ".")
        self.assertEqual(command[1:4], ["/d", "/s", "/c"])
        self.assertTrue(command[4].startswith('""C:\\Flutter SDK\\bin\\flutter.bat" '), command[4])
        self.assertTrue(command[4].endswith('"'), command[4])
        self.assertIn("--no-pub", command[4])

    def test_reports_shell_alias_only_as_actionable_error(self):
        with mock.patch.object(flutter_command.shutil, "which", return_value=None), \
             mock.patch.object(flutter_command, "_powershell_application", return_value=None), \
             mock.patch.dict(os.environ, {"FLUTTER_ROOT": "", "LOCALAPPDATA": ""}):
            with self.assertRaisesRegex(FileNotFoundError, "PowerShell function/alias"):
                flutter_command.resolve_tool("flutter")

    def test_rejects_unknown_sdk_command(self):
        with self.assertRaises(ValueError):
            flutter_command.resolve_tool("gradle")


if __name__ == "__main__":
    unittest.main()
