# راهنمای دریافت و شروع کار — AmitarGalleryPlayer 1.0.0

## بستهٔ اصلی

فایل `AmitarGalleryPlayer_v1.0.0_source.zip` بستهٔ کامل سورس پروژه است؛ فایل نصبی Android/Windows/macOS نیست. این بسته شامل کد اصلی، تنظیمات وابستگی، تست‌ها، آیکون‌ها، پوستر و ابزارهای ساخت چندسکویی است.

## فایل ورودی اصلی

`lib/AmitarGalleryPlayer.dart`

نام فایل اصلی عمداً همین است. همهٔ دستورهای ساخت پروژه باید از طریق `tool/build.py` اجرا شوند تا پارامتر `--target` به این فایل اشاره کند.

## دریافت Gradle Wrapper

فایل باینری `android/gradle/wrapper/gradle-wrapper.jar` عمداً داخل بستهٔ سورس قرار ندارد. هنگام اجرای `tool/bootstrap_platforms.py`، نسخهٔ موردنیاز از منبع ثابت Gradle دریافت و با SHA-256 رسمی اعتبارسنجی می‌شود. اگر شبکه به `raw.githubusercontent.com` دسترسی نداشته باشد یا checksum برابر نباشد، فرآیند متوقف می‌شود و از فایل تأییدنشده استفاده نمی‌کند.

## شروع کار

پس از استخراج ZIP و نصب Flutter پایدار سازگار با پروژه، از ریشهٔ پوشه اجرا کنید:

```bash
python3 tool/bootstrap_platforms.py
flutter pub get
python3 tool/check_release_version.py
flutter analyze
flutter test
```

## ساخت خروجی

ساخت native باید روی runner/رایانهٔ همان سیستم‌عامل انجام شود:

```bash
python3 tool/build.py android
python3 tool/build.py web
python3 tool/build.py linux
python3 tool/build.py windows
python3 tool/build.py macos
python3 tool/build.py ios
```

خروجی‌ها در `dist/` قرار می‌گیرند. iOS بدون تنظیم امضای Apple فقط APP اعتبارسنجی‌شده و unsigned تولید می‌کند؛ Windows و macOS نیز بدون گواهی ناشر امضاشده نیستند. برای Android انتشار فروشگاهی، keystore اختصاصی ناشر لازم است.

## کنترل سلامت بسته

در کنار فایل ZIP، فایل checksum مستقل ارائه می‌شود. برای بررسی صحت فایل:

```bash
sha256sum --check AmitarGalleryPlayer_v1.0.0_source.zip.sha256
```

برای مشاهدهٔ فهرست محتوا بدون استخراج:

```bash
unzip -l AmitarGalleryPlayer_v1.0.0_source.zip
```

## مرز اعتبارسنجی

آزمون‌های Python ابزارهای ساخت، پیکربندی و بسته‌بندی را بررسی می‌کنند. تا زمانی که `flutter analyze`، `flutter test` و ساخت native روی runnerهای متناظر با موفقیت اجرا نشده باشند، فایل‌های نصب‌شونده را نباید تأییدشده یا production-ready نامید.
