# راهنمای ساخت و انتشار AmitarGalleryPlayer 1.0.0

## مشخصات انتشار

- نام برنامه: `AmitarGalleryPlayer`
- نسخه: `1.0.0+1`
- فایل ورودی اصلی: `lib/AmitarGalleryPlayer.dart`
- سازنده: سید امیر محمد امامی
- مجوز کد برنامه: MIT
- زبان پیش‌فرض: فارسی (`fa_IR`، راست‌به‌چپ)
- زبان دوم: انگلیسی (`en_US`، چپ‌به‌راست)
- نسخهٔ مبنای Flutter در CI: `3.47.9` از کانال stable

## پیش‌نیاز عمومی

1. Flutter SDK پایدار نسخهٔ `3.47.9` یا بالاتر؛ نسخهٔ Dart باید با Flutter انتخابی سازگار باشد.
2. Python 3 برای اسکریپت‌های bootstrap، بسته‌بندی و اعتبارسنجی.
3. SDK و ابزار بومی همان سیستم‌عامل مقصد.
4. برای ساخت همهٔ خروجی‌های میزبان، هر سیستم‌عامل دسکتاپ باید روی runner یا رایانهٔ همان سیستم‌عامل ساخته شود.

## زنجیرهٔ ساخت Android (نسخه‌های ثابت‌شده در پیکربندی پروژه)

| مؤلفه | نسخه / تنظیم |
|---|---|
| Flutter | `3.47.9` stable |
| Dart | نسخهٔ همراه Flutter؛ در این شاخه `3.13.7` |
| JDK | `17` |
| Android Gradle Plugin | `8.13.2` |
| Gradle Wrapper | `8.14.6` با SHA-256 رسمی |
| Kotlin Gradle Plugin | `2.4.21` |
| Android compile SDK | مقدار مدیریت‌شده توسط Flutter (`flutter.compileSdkVersion`) |
| Android target SDK | مقدار مدیریت‌شده توسط Flutter (`flutter.targetSdkVersion`) |

ترکیب AGP/Kotlin/Gradle بر اساس ماتریس رسمی سازگاری انتخاب شده است: KGP `2.4.21` با AGP `8.13.2` و Gradle `8.14.6` در بازهٔ سازگاری کامل قرار دارد. AGP `9.5` به Gradle `9.6` نیاز دارد و از سقف سازگاری کامل AGP در KGP `2.4.21` (AGP تا `9.3.1`) فراتر می‌رود؛ علاوه بر آن مهاجرت AGP 9 در Flutter مستلزم بررسی و مهاجرت Kotlin داخلی و همهٔ افزونه‌های Android است. برای این نسخهٔ Flutter، ترکیب سازگار و قابل‌اتکای AGP 8.13 حفظ شده و Gradle به آخرین patch پایدار سری 8.14 ارتقا یافته است و ارتقای پرریسک و آزمایش‌نشده به AGP 9 انجام نشده است. از Gradle سیستمی استفاده نکنید؛ Android Studio باید روی **Gradle Wrapper پروژه** و JDK 17 تنظیم شود. فایل `android/local.properties` به‌صورت خودکار در رایانهٔ توسعه‌دهنده ساخته می‌شود و نباید commit شود. فایل `gradle-wrapper.jar` در سورس commit نمی‌شود. Bootstrap آن را از commit ثابت `c27417f` در مخزن رسمی Gradle دریافت می‌کند و SHA-256 آن را با checksum رسمی نسخهٔ 8.14.6 تطبیق می‌دهد. در صورت خطای شبکه یا عدم تطابق هش، bootstrap متوقف می‌شود و از Wrapper تأییدنشده استفاده نمی‌کند. Job کیفیت این JAR را به‌عنوان artifact موقت به Jobهای ساخت Linux، Windows و macOS منتقل می‌کند؛ هر Job پیش از ساخت دوباره checksum را کنترل می‌کند.

برای امضای ناشر Android، فایل `android/key.properties.example` را به `android/key.properties` کپی کنید، چهار مقدار را با کلید خصوصی خود جایگزین کنید و مسیر keystore را نسبت به پوشهٔ `android/` تنظیم کنید. فایل properties و keystore در `.gitignore` هستند. بدون این دو، APK/AAB با کلید debug ساخته می‌شوند و فقط خروجی QA محسوب می‌شوند؛ برای انتشار Play Store از کلید خود ناشر استفاده کنید. کلید واقعی در بستهٔ سورس قرار نمی‌گیرد.

در CI نیز می‌توانید چهار GitHub Actions Secret زیر را تعریف کنید تا APK/AAB خروجی با کلید ناشر امضا شود: `AMITAR_ANDROID_KEYSTORE_BASE64` (فایل JKS/PKCS12 به‌شکل Base64)، `AMITAR_ANDROID_STORE_PASSWORD`، `AMITAR_ANDROID_KEY_PASSWORD` و `AMITAR_ANDROID_KEY_ALIAS`. keystore فقط در `$RUNNER_TEMP` ساخته می‌شود و وارد checkout یا artifact سورس نمی‌شود. یا هر چهار مقدار را تنظیم کنید یا هیچ‌کدام؛ پیکربندی ناقص با خطا متوقف می‌شود.

## رفع خطای انتخاب Java در Windows (الزامی برای Android)

این پروژه برای اجرای Gradle از JDK `17` استفاده می‌کند. اگر `flutter doctor -v` جاوای همراه Android Studio یا `JAVA_HOME` را `25.x` گزارش کرد، Gradle Wrapper `8.14.6` با آن اجرا نمی‌شود. نسخهٔ Gradle را برای پنهان‌کردن این خطا به‌صورت دستی ارتقا ندهید؛ انتخاب JDK باید اصلاح شود.

از CMD در ریشهٔ پروژه اجرا کنید؛ اسکریپت JDK 17 را پیدا می‌کند، در صورت درخواست آن را با Windows Package Manager نصب می‌کند، `flutter config --jdk-dir` را تنظیم و نتیجه را با `flutter doctor -v` تأیید می‌کند:

```cmd
tool\setup_android_jdk_windows.bat -InstallIfMissing
```

بعد از مشاهدهٔ `Java version ... 17.x` اجرا کنید:

```cmd
flutter clean
flutter pub get
flutter run -t lib/AmitarGalleryPlayer.dart
```

اگر JDK 17 از قبل نصب شده است، می‌توانید `-InstallIfMissing` را حذف کنید. برای تنظیم دستی نیز از `flutter config --jdk-dir="C:\Path\To\JDK17"` استفاده کنید. این تنظیم در پیکربندی محلی Flutter ذخیره می‌شود و نباید مسیر اختصاصی رایانه در Git commit شود. اگر Android Studio را برای اجرای مستقیم Gradle استفاده می‌کنید، در Settings → Build, Execution, Deployment → Build Tools → Gradle نیز همان JDK 17 را انتخاب کنید.

## رفع خطای پیدا نشدن Android Gradle Plugin در Google Maven

اگر Gradle این خطا را گزارش کرد:

```text
Plugin [id: 'com.android.application', version: '8.13.2'] was not found
Could not resolve plugin artifact
```

این پیام به‌تنهایی به معنی نامعتبر بودن AGP نیست. AGP `8.13.2` در مخزن Google منتشر شده است. تنظیم `android/settings.gradle.kts` در این نسخه درخواست شناسهٔ `com.android.application` را مستقیماً به مختصات رسمی `com.android.tools.build:gradle:8.13.2` نگاشت می‌کند تا به POM واسط plugin-marker وابسته نباشد؛ مخزن رسمی `google()` نیز همچنان در فهرست باقی می‌ماند.

ابتدا در CMD از ریشهٔ پروژه بررسی کنید که فایل POM اصلی واقعاً از شبکهٔ رایانه قابل دریافت است:

```cmd
tool\check_android_maven_windows.bat
```

این ابزار هم POM اصلی AGP و هم POM مربوط به plugin-marker را بررسی می‌کند. POM marker صرفاً اطلاعاتی است؛ دسترسی به POM اصلی `com.android.tools.build:gradle` برای ساخت لازم است. اگر POM اصلی در دسترس نیست، مشکل شبکه، DNS، Proxy، TLS inspection یا Firewall است و تغییر نسخه‌های JDK/Gradle آن را حل نمی‌کند. فقط در صورتی که سازمان/شبکهٔ شما یک mirror معتبر و مورداعتماد برای Google Maven ارائه می‌کند، آن را به‌صورت HTTPS معرفی کنید:

```cmd
set "AMITAR_GOOGLE_MAVEN_MIRROR=https://YOUR-TRUSTED-GOOGLE-MAVEN-MIRROR"
tool\check_android_maven_windows.bat
```

از mirror ناشناس یا HTTP استفاده نکنید. mirror اختیاری قبل از `google()` قرار می‌گیرد و برای pluginهای Android و وابستگی‌های Android قابل استفاده است؛ بدون متغیر فوق، فقط مخازن رسمی/اصلی پروژه فعال‌اند.

پس از آنکه ابزار دسترسی به POM اصلی را تأیید کرد، cache منفی Gradle را یک‌بار تازه‌سازی کنید:

```cmd
flutter clean
flutter pub get
cd android
gradlew.bat --stop
gradlew.bat --refresh-dependencies :app:assembleDebug
cd ..
flutter run -t lib/AmitarGalleryPlayer.dart
```

اگر ابزار تشخیصی نتواند POM اصلی را دریافت کند، خروجی کامل آن و نتیجهٔ این دستور را بررسی کنید:

```cmd
curl.exe -I -L --max-time 20 https://dl.google.com/dl/android/maven2/com/android/tools/build/gradle/8.13.2/gradle-8.13.2.pom
```

کد HTTP `200` نشان‌دهندهٔ دسترسی به POM است؛ خطاهای DNS/timeout/TLS یا پاسخ `403`/`407` باید در تنظیم شبکه/Proxy حل شوند. نسخهٔ AGP را برای دور زدن این مشکل به‌صورت تصادفی downgrade یا upgrade نکنید.

## راه‌اندازی پروژه

از ریشهٔ مخزن اجرا کنید:

```bash
python3 tool/bootstrap_platforms.py
flutter pub get
python3 tool/check_release_version.py
flutter analyze
flutter test
```

اسکریپت bootstrap پوشه‌های میزبان Flutter را تولید می‌کند، مجوزهای محدود Android را درج می‌کند، توضیح‌های دسترسی Photos در Apple را تنظیم می‌کند و آیکون Linux را هم در منابع runner و هم در پنجرهٔ GTK ثبت می‌کند. مسیر آیکون پنجره از محل executable حل می‌شود و به working directory وابسته نیست. اجرای دوبارهٔ تنظیمات idempotent است. پس از تولید منابع، `tool/verify_platform_icons.py` ارجاع‌ها و فایل‌های آیکون Android، iOS، macOS، Windows، Linux و Web را اعتبارسنجی می‌کند. بستهٔ DEB نیز آیکون‌های ۲۵۶ و ۵۱۲ پیکسل را در hicolor و ورودی منوی فارسی/انگلیسی نصب می‌کند. فایل اصلی برنامه `lib/AmitarGalleryPlayer.dart` است و تمام فرمان‌های build به آن `--target` صریح می‌دهند.

## ساخت به تفکیک سیستم‌عامل

```bash
python3 tool/build.py android
python3 tool/build.py web
python3 tool/build.py linux
python3 tool/build.py windows
python3 tool/build.py macos
python3 tool/build.py ios
```

برای هر build دسکتاپ، روی میزبان مناسب اجرا کنید. `all` روی یک میزبان، خروجی Android و Web را به‌علاوهٔ هدف‌های قابل ساخت همان سیستم‌عامل تولید می‌کند؛ به این معنی نیست که یک سیستم‌عامل می‌تواند باینری نهایی Windows، macOS و Linux را همگی به‌صورت native کامپایل کند.

## بازتولید هویت بصری

تصویر ارسالی شما در مسیر `assets/brand/AmitarGalleryPlayer_UserProvided.png` به‌عنوان منبع یگانه و با حفظ بایت‌های اصلی نگهداری می‌شود. فایل RGBA است و خروجی‌های رنگی تمام کانال Alpha، حاشیه‌های شفاف و پیکسل‌های نیمه‌شفاف را حفظ می‌کنند؛ هیچ پس‌زمینه، سایه، گرادیان، قاب یا برش جدیدی به آیکون اصلی اضافه نمی‌شود. لایهٔ پس‌زمینهٔ Android Adaptive نیز کاملاً شفاف است.

استثنای فنی iOS: App Store آیکون اصلی کاملاً مات می‌خواهد؛ فایل `ios-app-store-1024.png` فقط برای این خروجی ساخته می‌شود. نسخهٔ `ios-dark-transparent-1024.png` همان طرح اصلی با Alpha را برای حالت Dark سیستم‌های پشتیبانی‌شده حفظ می‌کند. این استثنا تصویر اصلی و آیکون‌های شفاف سایر پلتفرم‌ها را تغییر نمی‌دهد. جزئیات در `ICON_POLICY.md` است.

برای بازتولید اختیاری آیکون و پوستر روی سیستم توسعه‌دهنده: 

```bash
python3 -m pip install -r tool/requirements-branding.txt
python3 tool/generate_brand_assets.py
```

اسکریپت برای شکل‌دهی صحیح متن فارسی به Pillow با پشتیبانی RAQM نیاز دارد. خروجی پوستر، PNG با ابعاد ۳۵۰۸×۴۹۶۱ و ۳۰۰ DPI و PDF تک‌صفحه‌ای A3 با اندازهٔ فیزیکی ۲۹۷×۴۲۰ میلی‌متر است. این وابستگی‌ها ابزار تولید مستندات و برندینگ هستند و به وابستگی‌های زمان اجرای Flutter اضافه نمی‌شوند.

## نیازمندی‌های هر پلتفرم

### Android

- Android SDK و ابزارهای Build Tools/Gradle سازگار با Flutter.
- JDK 17 در workflow فعلی CI.
- برای ساخت محلی، مجوزهای Android SDK را بپذیرید.
- خروجی: APKهای تفکیک‌شده بر اساس ABI و AAB.
- APK خروجی برای نصب و QA است؛ برای انتشار تجاری/فروشگاهی، keystore ناشر و پیکربندی signing لازم است. AAB مستقیماً مانند APK نصب نمی‌شود.

### Windows

- Windows 10/11 و Visual Studio با workload مربوط به Desktop development with C++.
- Inno Setup 6 برای تولید Setup EXE.
- خروجی: ZIP قابل‌حمل و در صورت حضور Inno Setup، `AmitarGalleryPlayer-Setup-Windows.exe`.
- EXE امضای Authenticode ندارد مگر ناشر جداگانه آن را امضا کند.

### Linux

برای Ubuntu/Debian، پیش‌نیازهای build در workflow نصب می‌شوند:

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libmpv-dev mpv
```

- خروجی: `TAR.GZ` و در صورت وجود `dpkg-deb`، بستهٔ `DEB`.
- DEB وابستگی‌های اصلی GTK و `libmpv` را در metadata اعلام می‌کند؛ مدیر بسته باید نسخهٔ سازگار را نصب کند.
- بستهٔ portable همچنان به کتابخانه‌های runtime سازگار توزیع مقصد نیاز دارد.

### macOS

- macOS و Xcode با command line tools و CocoaPods سازگار با Flutter.
- خروجی: ZIP مربوط به APP و DMG.
- فایل‌ها به‌صورت پیش‌فرض Developer ID امضا یا notarize نمی‌شوند؛ توزیع عمومی خارج از محیط توسعه نیازمند امضا و notarization ناشر است.

### iOS

- macOS، Xcode، CocoaPods، Apple Developer account و provisioning برای توزیع روی دستگاه.
- رفتار پیش‌فرض CI: `flutter build ios --release --no-codesign` و ZIP مربوط به `.app` برای اعتبارسنجی.
- این ZIP **IPA قابل نصب نیست**.
- برای IPA، فایل ExportOptions.plist معتبر را بسازید، signing identity و provisioning profile را در Xcode تنظیم کنید و متغیر محیطی `AMITAR_IOS_EXPORT_OPTIONS_PLIST` را به مسیر فایل بدهید. در این حالت اسکریپت `flutter build ipa` را اجرا می‌کند. نگهداری و استفاده از credentialها مسئولیت ناشر است.

### Web

- خروجی Web، سایت استاتیک داخل ZIP است و می‌تواند روی HTTPS میزبانی شود.
- دسترسی به فایل‌ها فقط از مسیر APIهای انتخاب/ذخیرهٔ فایل مرورگر انجام می‌شود؛ برنامه نمی‌تواند کل دیسک کاربر را بدون مجوز مرورگر بخواند.
- پشتیبانی codec وابسته به مرورگر و سیستم‌عامل است.

## ساخت خودکار و انتشار GitHub

Workflow در `.github/workflows/build.yml` پنج job اصلی دارد:

1. `quality`: ایجاد میزبان‌ها، کنترل نسخه، آزمون‌های Python، دریافت وابستگی‌ها، تولید آیکون‌ها، تحلیل و Flutter tests؛ سپس `pubspec.lock` حل‌شده را به‌عنوان artifact منتقل می‌کند.
2. `linux-android-web`: ساخت Linux، Android و Web روی Ubuntu با همان lockfile.
3. `windows`: ساخت Windows و Setup EXE روی Windows.
4. `apple`: ساخت macOS و خروجی iOS بدون امضا روی macOS.
5. `publish-github-release`: فقط برای tagهای `v*`، checksum هر runner را بررسی و فایل‌ها را به GitHub Release پیوست می‌کند.

مراحل انتشار از `GITHUB_TOKEN` با مجوز `contents: write` استفاده می‌کنند. در تنظیمات مخزن باید اجرای Actions و مجوز لازم برای ایجاد Release فعال باشد.

برای اولین انتشار:

```bash
git add .
git commit -m "Release AmitarGalleryPlayer 1.0.0"
git push origin main

git tag -a v1.0.0 -m "AmitarGalleryPlayer 1.0.0"
git push origin v1.0.0
```

در صورت نام شاخهٔ اصلی متفاوت، دستور push را با نام شاخهٔ خود جایگزین کنید. اسکریپت `check_release_version.py` tag را با نسخهٔ `pubspec.yaml`، مقدار Dart و نسخهٔ Inno Setup تطبیق می‌دهد.

## محتوای پوشهٔ خروجی

تمام buildها به `dist/` می‌روند. `BUILD-MANIFEST.json` شامل نسخه، entrypoint، سیستم‌عامل میزبان، Flutter version، اندازه و SHA-256 خروجی‌هاست. `SHA256SUMS.txt` نیز checksum خروجی‌های build را ثبت می‌کند. در CI، اسکریپت `finalize_artifacts.py` manifest و checksum مستقل هر runner را تولید می‌کند.

برای بررسی صحت بسته:

```bash
sha256sum --check SHA256SUMS.txt
```

## محدودیت منابع در اسکن و واردسازی

- اسکن پوشه و کتابخانهٔ دستگاه در هر اجرا حداکثر ۲۰٬۰۰۰ مورد را پردازش می‌کند تا کتابخانه‌های بسیار بزرگ باعث عملیات نامحدود نشوند.
- نگهداری موقت thumbnailها و previewها برای هر عملیات واردسازی/اسکن بودجهٔ حافظه دارد؛ فایل اصلی رسانه در واردسازی موبایل به‌صورت stream به فضای خصوصی برنامه منتقل می‌شود.
- در صورت رسیدن به سقف، برنامه صریحاً اعلام می‌کند که موارد باقی‌مانده در آن اجرا بررسی نشده‌اند.

## سیاست رسانه و فرمت‌ها

- Native از `media_kit`/libmpv بهره می‌برد و پوشش codec تابع بستهٔ codec، معماری، کتابخانه‌های runtime و سیستم‌عامل است.
- Web از decoder بومی مرورگر استفاده می‌کند و پوشش آن محدودتر است.
- پسوند، تنها برای دسته‌بندی است؛ تضمین decode نیست. پسوندهای ناشناخته در دستهٔ Unknown می‌مانند.
- اسکن کتابخانهٔ سیستم روی Android/iOS/macOS و فقط پس از مجوز کاربر است.
- اسکن پوشه فقط روی Windows/Linux/macOS و پس از انتخاب پوشه توسط کاربر فعال است.
- دسترسی iOS و Web به محدودیت‌های پلتفرم وابسته است؛ دسترسی نامحدود به فایل‌سیستم ارائه نمی‌شود.

## امنیت انتشار

- کلیدهای Android، فایل‌های `.p12`، provisioning profile، token و secret نباید commit شوند.
- از GitHub Actions Secrets/Environments استفاده کنید و حداقل مجوز لازم را بدهید.
- قبل از انتشار عمومی، نصب واقعی را روی دستگاه Android، Windows، Linux، macOS، iOS و مرورگرهای هدف آزمایش کنید.
- گزارش تست ابزارهای Python جایگزین `flutter analyze`، `flutter test`، build native، تست کدک و تست سخت‌افزار نیست.
