# ماتریس سازگاری و پیش‌نیازهای AmitarGalleryPlayer

این سند بازهٔ عملی و قابل‌اعتبارسنجی پروژه را مشخص می‌کند. هیچ پروژهٔ Flutter/Android را نمی‌توان با «هر نسخه‌ای» از Flutter، Gradle، JDK، Kotlin، Android SDK یا Xcode تضمین کرد؛ این ابزارها قراردادهای نسخه‌ای و breaking change دارند. این پروژه به‌جای نسخه‌های شناور و ناسازگار، یک زنجیرهٔ هماهنگ و یک حداقل Flutter مشخص دارد.

## نسخه‌های پایه

| مؤلفه | حداقل/بازهٔ قابل استفاده | مبنای CI یا نسخهٔ پیشنهادی |
|---|---|---|
| Flutter | `3.47.9` یا جدیدتر از stable | `3.50.1` stable |
| Dart | نسخهٔ همراه Flutter؛ مستقل downgrade نشود | `3.14.0` همراه Flutter `3.50.1` |
| Android JDK | `17` تا `24` با Gradle `8.14.6` | `17` |
| Android Gradle Plugin | `8.13.2` در پیکربندی فعلی | `8.13.2` |
| Gradle | Wrapper پروژه؛ حداقل موردنیاز AGP 8.13 برابر `8.13` | `8.14.6` |
| Kotlin Gradle Plugin | `2.4.21` در پیکربندی فعلی | `2.4.21` |
| Java bytecode target | `17` | `17` |
| File Picker | `13.4.1` یا جدیدتر در سری سازگار `13.x` | `13.4.1` در lock فعلی |

## چرا نسخه‌ها آزاد و نامحدود نیستند؟

- Flutter با Dart متناظر خودش منتشر می‌شود؛ Dart مستقل از Flutter جایگزین نشود.
- AGP `8.13` حداقل Gradle `8.13` و JDK `17` می‌خواهد.
- Gradle `8.14.x` روی Java `17` تا `24` قابل اجراست؛ Java `25` به Gradle `9.1` یا جدیدتر نیاز دارد. ارتقای Gradle به‌تنهایی کافی نیست و باید AGP، KGP، Flutter Gradle Plugin و افزونه‌های Android نیز با هم آزموده شوند.
- Kotlin Gradle Plugin `2.4.21` در جدول سازگاری رسمی با Gradle `7.6.3` تا `9.7.0` و AGP `8.5.2` تا `9.3.1` در محدودهٔ پشتیبانی کامل قرار دارد. AGP و Gradle انتخاب‌شدهٔ این پروژه در اشتراک این بازه‌اند.
- `FilePicker.pickDirectory()` در `file_picker 13.4.0` اضافه شده است؛ پروژه حداقل `13.4.1` را درخواست می‌کند تا API مبتنی بر `Uri` در دسترس باشد. URIهای `content://` نباید با `toFilePath()` به مسیر فایل تبدیل شوند؛ کد فعلی فقط `file:` را به مسیر محلی تبدیل می‌کند.

## سیاست JDK

JDK 17 گزینهٔ مرجع CI و پیشنهاد اصلی برای رفع ناسازگاری ابزارهاست. `tool/build.py` JDKهای 17 تا 24 را می‌پذیرد و خارج از این بازه با پیام تشخیصی متوقف می‌شود. در Windows می‌توان JDK سازگار را از طریق اسکریپت زیر انتخاب کرد:

```cmd
tool\setup_android_jdk_windows.bat -InstallIfMissing
```

این اسکریپت JDK 17 را پیدا می‌کند یا با اجازهٔ کاربر از Windows Package Manager نصب می‌کند و سپس انتخاب Flutter را با `flutter doctor -v` بررسی می‌کند. مقدار `JAVA_HOME`، JDK داخلی Android Studio و JDK انتخاب‌شده توسط Flutter می‌توانند متفاوت باشند؛ معیار نهایی برای Flutter خروجی `flutter doctor -v` است.

## پیش‌نیازهای پلتفرمی

| پلتفرم | پیش‌نیاز میزبان | محدودیت مهم |
|---|---|---|
| Android | Android SDK، Build Tools، NDK اعلام‌شده توسط Flutter، JDK سازگار | امضای انتشار نیازمند keystore اختصاصی است؛ کلید debug فقط QA است. |
| Windows | Windows و Visual Studio با Desktop development with C++، CMake/Ninja در صورت نیاز Flutter | ساخت Windows باید روی Windows اجرا شود. |
| Linux | Clang، CMake، Ninja، GTK 3، libmpv و کتابخانه‌های runtime | ساخت Linux روی Linux انجام شود؛ توزیع‌های مقصد باید runtime سازگار داشته باشند. |
| macOS | macOS، Xcode و CocoaPods/ابزارهای موردنیاز Flutter | ساخت macOS روی macOS انجام شود؛ امضا و notarization جداگانه‌اند. |
| iOS | macOS، Xcode، Apple signing و provisioning برای توزیع | خروجی بدون امضا IPA قابل نصب نیست. |
| Web | Flutter Web و مرورگر مدرن | پخش codec به decoder مرورگر و دسترسی فایل به مجوزهای مرورگر وابسته است. |

## راه‌اندازی و بررسی

از ریشهٔ پروژه:

```bash
python tool/bootstrap_platforms.py
flutter doctor -v
flutter pub get
python tool/check_release_version.py
python tool/validate_source_contracts.py
python -m unittest discover -s tool -p 'test_*.py' -v
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
```

برای ساخت خروجی‌های سیستم‌عامل‌ها از `python tool/build.py all` استفاده کنید. این فرمان فقط خروجی پلتفرم میزبان را می‌سازد؛ Windows، Linux، macOS و iOS باید روی runner میزبان مربوط به خودشان ساخته شوند. فایل `android/local.properties`، پوشه‌های `.dart_tool` و `.gradle` و فایل‌های plugin metadata محلی، خروجی‌های تولیدی‌اند و نباید از یک رایانه به رایانهٔ دیگر کپی شوند.

## منابع رسمی سازگاری

- Flutter release notes: https://docs.flutter.dev/release/release-notes
- Flutter Android setup: https://docs.flutter.dev/platform-integration/android/setup
- Android Gradle Plugin 8.13 release notes: https://developer.android.com/build/releases/agp-8-13-0-release-notes
- Gradle Java runtime compatibility: https://docs.gradle.org/current/userguide/compatibility.html
- Kotlin Gradle Plugin compatibility: https://kotlinlang.org/docs/gradle-configure-project.html
- File Picker changelog: https://pub.dev/packages/file_picker/changelog
