# Validation report — CI helper-file restoration

## Failure confirmed from the latest Actions log

The run completed all 62 existing Python tests and `flutter pub get`, then exited at the step `Validate source and resolved dependency contracts` because `tool/validate_source_contracts.py` was absent from the checked-out repository.

The workflow revision used by the run also calls the CI snapshot collector and applier. The uploaded reduced source ZIP did not contain those files either. Therefore adding only the validator would have exposed the next missing-file failure later in the run.

## Files restored/aligned by this patch

- `tool/validate_source_contracts.py`
- `tool/collect_ci_snapshot.py`
- `tool/apply_ci_snapshot.py`
- `tool/test_ci_snapshot.py`
- synchronized versions of `bootstrap_platforms.py` and its regression tests
- synchronized `test_project_invariants.py`
- `test_workflow_tool_paths.py`, which verifies every `python tool/*.py` / `python3 tool/*.py` invocation in both workflows points to a committed file
- synchronized `build.yml` and manual-only `refresh-source-manifest.yml`

## Validation actually performed

The patch was overlaid onto the uploaded reduced source ZIP in a temporary test checkout. The Unix executable bit on `android/gradlew` was restored to match the mode confirmed by the actual GitHub-run tests, because ZIP extraction does not reliably preserve Git executable mode.

Results:

- `tool/validate_source_contracts.py`: passed
- `tool/test_workflow_tool_paths.py`: 2 tests passed
- complete Python discovery over `tool/test_*.py`: 73 tests, `OK (skipped=2)`
- source-checksum generator and tracked-manifest verification: passed in a temporary Git repository
- both workflow YAML files: parsed successfully with PyYAML BaseLoader
- patch ZIP integrity: passed

The two skipped test groups depend on brand asset files intentionally omitted from the uploaded reduced source ZIP.

## Not claimed

Flutter/Dart SDK was not available in the patch-preparation environment. No claim is made that `flutter analyze`, `flutter test`, or native platform builds have passed. These remain to be confirmed by the next GitHub Actions run after the files are committed.
