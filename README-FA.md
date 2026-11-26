# AmitarGalleryPlayer

پروژهٔ Flutter چندسکویی برای کتابخانهٔ رسانه و پخش‌کنندهٔ ویدئو/صوت، با رابط فارسی و انگلیسی.

- نام بسته: `amitar_gallery_player`
- نسخه: `1.0.0+1`
- فایل ورودی اصلی: `lib/AmitarGalleryPlayer.dart`
- سازنده: سید امیر محمد امامی (Seyed Amir Mohammad Emami)
- مستند راه‌اندازی و ساخت فارسی: [`BUILD_GUIDE_FA.md`](BUILD_GUIDE_FA.md)
- گزارش آخرین اعتبارسنجی: [`VALIDATION_REPORT_FINAL.md`](VALIDATION_REPORT_FINAL.md)

## راه‌اندازی در Windows / PowerShell

فرمان‌ها را از ریشهٔ پروژه اجرا کنید:

```powershell
python tool/bootstrap_platforms.py
flutter pub get
python tool/generate_platform_icons.py
dart fix --apply
dart format lib test
python tool/update_source_checksums.py
python tool/verify_platform_icons.py
python tool/check_release_version.py
python -m unittest discover -s tool -p 'test_*.py' -v
flutter analyze --fatal-infos
flutter test --reporter expanded
```

ترتیب مهم است: `flutter pub get` ممکن است `analysis_options.yaml` را توسط خود Flutter به‌روزرسانی کند. پس از دریافت وابستگی‌ها، تولید آیکون‌ها، اصلاحات Dart و format، باید `SHA256SUMS.txt` را بازسازی کنید و بعد آزمون‌های Python را اجرا کنید.

## اجرای برنامه

مسیر فایل Dart به‌تنهایی فرمان PowerShell نیست. فایل اصلی را با گزینهٔ `--target` معرفی کنید:

```powershell
flutter run -d chrome --target lib/AmitarGalleryPlayer.dart
```

برای Windows Desktop، در کنار Flutter به Visual Studio با workload مربوط به C++ نیاز است:

```powershell
flutter run -d windows --target lib/AmitarGalleryPlayer.dart
```

از افزودن `main:` زیر بخش `flutter:` در `pubspec.yaml` خودداری کنید؛ این کلید معتبر نیست. همهٔ اسکریپت‌های ساخت، ورودی اصلی را با `--target lib/AmitarGalleryPlayer.dart` تعیین می‌کنند.

## Gradle Wrapper و خطای شبکه

فایل Wrapper در سورس قرار نمی‌گیرد. Bootstrap آن را از endpoint رسمی Gradle دریافت و SHA-256 رسمی آن را بررسی می‌کند:

`https://services.gradle.org/distributions/gradle-8.14.6-wrapper.jar`

اگر Python نتواند به endpoint دسترسی پیدا کند، bootstrap محلی hostهای غیر Android را کامل می‌کند و هشدار می‌دهد؛ اما ساخت Android بدون Wrapper تأییدشده مجاز نیست. برای اجرای CI و ساخت Android، گزینهٔ `--require-gradle-wrapper` فعال است و در نبود Wrapper، fail-closed عمل می‌کند. بخش Windows در [`BUILD_GUIDE_FA.md`](BUILD_GUIDE_FA.md) راه جایگزین دریافت با PowerShell و کنترل هش را توضیح می‌دهد.

## آیکون پلتفرم‌ها

Bootstrap ابتدا hostهای Flutter را می‌سازد و آیکون Linux را در runner تنظیم می‌کند. سپس `tool/generate_platform_icons.py` آیکون‌های Android، iOS، macOS، Windows و Web را می‌سازد و تنظیم Linux را نیز دوباره به‌شکل idempotent اعمال می‌کند. پس از آن `tool/verify_platform_icons.py` فایل‌ها و ارجاع‌های هر شش پلتفرم را بررسی می‌کند.

## ساخت خروجی

```powershell
python tool/build.py android
python tool/build.py web
python tool/build.py windows
```

ساخت Android به JDK و Android SDK سازگار و Wrapper تأییدشده نیاز دارد. ساخت Windows Desktop به Visual Studio C++ Build Tools نیاز دارد. ساخت iOS و macOS باید روی macOS همراه Xcode انجام شود.

برای جزئیات وابستگی‌ها، محدودیت‌های codecها، مجوزها، بسته‌بندی و انتشار، راهنمای فارسی ساخت را مطالعه کنید.
