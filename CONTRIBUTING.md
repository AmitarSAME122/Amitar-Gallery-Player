# Contributing

Thank you for considering a contribution.

## Before changing code

1. Check whether the requested behavior already exists in `lib/AmitarGalleryPlayer.dart`.
2. Avoid adding dependencies with overlapping responsibilities. See `DEPENDENCIES.md`.
3. Preserve Persian-first localization, RTL/LTR directionality, accessibility labels and responsive layouts.
4. Do not weaken scoped-storage, user-picker or platform sandbox boundaries to make file access appear unrestricted.
5. Do not claim a media format or platform combination works until it has been tested on that target.

## Local validation

```bash
python3 -m unittest discover -s tool -p 'test_*.py' -v
python3 tool/check_release_version.py
flutter pub get
dart format lib test
flutter analyze
flutter test
```

For native changes, run the relevant platform build and test on the target OS. Attach the exact Flutter/Dart version, OS version, build log and a short reproduction to the pull request.

## Pull requests

- Keep each change focused and describe why it is needed.
- Add or update tests for new behavior.
- Update Persian and English user-visible strings together.
- Update `CHANGELOG.md`, supported-platform notes and screenshots/poster only when relevant.
- Never commit keystores, provisioning profiles, certificates, credentials, personal media or generated `build/` output.
