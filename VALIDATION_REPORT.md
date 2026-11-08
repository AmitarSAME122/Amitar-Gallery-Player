# گزارش اعتبارسنجی — AmitarGalleryPlayer 1.0.0+1

تاریخ بررسی: 2026-11-08

## اصلاحات انجام‌شده

- تمام ارجاع‌های build، bootstrap، version-check، artifact-finalizer، تست‌ها و راهنماها به فایل ورودی واقعی `lib/AmitarGalleryPlayer.dart` یکسان شدند.
- خطای بحرانی Gradle اصلاح شد: Flutter plugin loader در Settings و Flutter app Gradle plugin در ماژول `:app` قرار دارد؛ `includeBuild` به Flutter SDK اضافه شده است.
- Android روی AGP `8.13.2`، Gradle Wrapper `8.14.6`، Kotlin Gradle Plugin `2.4.21` و JDK `17` پین شده است. SHA-256 توزیع `-bin`: `7988ed071b2a07900e2ec715fca15c6ab72bce6db433af301fa7fa7e9407bd24` و SHA-256 Wrapper JAR: `ad16bca46cb71bb5887c546860d93992aeee35c1fdaf4a242b0a612375d937e0` است. Wrapper JAR هنگام bootstrap از میزبان رسمی Gradle دریافت و پیش از جایگزینی اعتبارسنجی می‌شود؛ فایل قدیمی/تأییدنشده در مخزن نگهداری نمی‌شود.
- مخازن پیش‌فرض plugin resolution شامل Google Maven، Maven Central و Gradle Plugin Portal هستند. mirror شخص ثالث به‌صورت پیش‌فرض فعال نیست؛ در صورت نیاز شبکه، فقط با متغیر `AMITAR_GOOGLE_MAVEN_MIRROR` و آدرس HTTPS مورداعتماد کاربر قابل افزودن است.
- namespace، applicationId، مسیر و package مربوط به `MainActivity` به `com.amitar.amitar_gallery_player` منتقل شد.
- مجوزهای رسانهٔ Android محدود و نسخه‌بندی‌شده‌اند؛ `MANAGE_EXTERNAL_STORAGE` درخواست نمی‌شود.
- امضای ناشر Android به شکل اختیاری و با کنترل کامل بودن مقادیر key.properties اضافه شده؛ فایل کلید و keystore در Git نادیده گرفته می‌شوند.
- URL مخزن بسته‌ها در lockfile به `pub.dev` استاندارد شد و override تکراری `cross_file` حذف شد.
- cacheها، مسیرهای محلی SDK، فایل‌های پشتیبان و خروجی‌های IDE از بستهٔ سورس حذف شدند.
- bootstrap پیکربندی‌های Android را به‌صورت idempotent اعمال می‌کند؛ میزبان‌های iOS/macOS/Windows/Linux/Web را با `flutter create` روی runner دارای Flutter تولید می‌کند.

- KGP از `2.3.21` به `2.4.21` ارتقا یافت؛ این نسخه طبق ماتریس رسمی Kotlin با AGP 8.13.2 و Gradle 8.14.6 سازگار است. به‌روزرسانی AGP 9.5 انجام نشد، زیرا KGP 2.4.21 حداکثر AGP 9.3.1 را در سازگاری کامل اعلام می‌کند و مهاجرت Flutter AGP 9 به سازگاری Kotlin داخلی و افزونه‌ها وابسته است.
- Gradle از `8.13` به `8.14.6` ارتقا یافت؛ توزیع `-bin` و Wrapper JAR با checksumهای رسمی مستقل Gradle پین شده‌اند. AGP `8.13.2` حداقل Gradle `8.13` می‌خواهد و این نسخهٔ Gradle در بازهٔ کامل پشتیبانی KGP `2.4.21` قرار دارد.
- یک ابزار اجباری `tool/verify_platform_icons.py` اضافه شد تا فایل‌ها و ارجاع‌های واقعی آیکون Android، iOS، macOS، Windows، Linux و Web را پس از تولید در هر runner بررسی کند؛ PNG از نظر ساختار chunk، CRC و ابعاد و ICO از نظر جدول تصاویر اعتبارسنجی می‌شود.
- تنظیم `kotlin.compilerOptions` از درون `android {}` خارج و به بلوک سطح پروژهٔ `kotlin {}` منتقل شد؛ آزمون رگرسیون این جایگاه و هدف JVM 17 را کنترل می‌کند.
- bootstrap لینوکس، آیکون پنجرهٔ GTK را در `linux/runner/resources/app_icon.png` قرار می‌دهد و کد runner را به‌صورت idempotent برای بارگذاری از مسیر Flutter assets نصب‌شده تنظیم می‌کند.
- بستهٔ DEB، آیکون‌های ۲۵۶ و ۵۱۲ پیکسل hicolor و launcher فارسی/انگلیسی را نصب می‌کند؛ تست یکپارچه DEB محتویات واقعی بسته، مسیر آیکون، desktop entry و وابستگی‌های GTK/libmpv را بررسی می‌کند.
- CI به‌جای تغییر فایل Dart در مرحلهٔ format، اکنون با `--output=none --set-exit-if-changed` قالب‌بندی را به‌صورت check انجام می‌دهد؛ bootstrap تکراری در job لینوکس نیز حذف شد.
- رفع خطای جدید `Plugin [id: 'com.android.application', version: '8.13.2'] was not found`: در `pluginManagement.resolutionStrategy.eachPlugin` شناسه‌های namespace `com.android` مستقیماً به مختصات رسمی `com.android.tools.build:gradle:<version>` نگاشت شدند. این روش رسمی Gradle، اتکا به marker artifact را حذف می‌کند؛ مخزن `google()` همچنان برای دریافت AGP اصلی الزامی است.
- mirror اختیاری Google Maven فقط در صورت تعریف `AMITAR_GOOGLE_MAVEN_MIRROR` فعال می‌شود و به HTTPS محدود شده است؛ تنظیم آن هم برای plugin repositories و هم برای dependency repositories اعمال می‌شود. هیچ mirror شخص ثالثی به‌صورت پیش‌فرض اضافه نشده است.
- ابزارهای Windows `tool/check_android_maven_windows.ps1` و `.bat` افزوده شدند. آن‌ها POM اصلی AGP را از Google Maven و POM marker را به‌صورت اطلاعاتی بررسی می‌کنند و در صورت نیاز دسترسی به mirror صریحاً پیکربندی‌شده را نیز می‌سنجند. گزارش تشخیصی بین خطای plugin-marker و عدم دسترسی واقعی به artifact اصلی تمایز می‌گذارد.
- راهنمای فارسی و انگلیسی با روش تازه‌سازی cache منفی Gradle و فرمان `--refresh-dependencies :app:assembleDebug` به‌روزرسانی شد.

## کنترل‌های قابل اجرا در این محیط

- `python3 -m py_compile tool/*.py` — موفق.
- `python3 -m unittest discover -s tool -p 'test_*.py' -v` — ۵۱ آزمون ابزار، بسته‌بندی، version identity، آیکون‌ها، Linux GTK، ساخت DEB، انتخاب JDK و تنظیم/تشخیص Google Maven؛ نتیجهٔ نهایی: **۵۱ از ۵۱ موفق**. آزمون‌های bootstrap دریافت Wrapper JAR، تطبیق checksum و حفظ فایل قبلی در صورت hash نامعتبر را بررسی می‌کنند. آزمون DEB از fixture آزمایشی استفاده می‌کند و جایگزین ساخت بسته از باینری واقعی برنامه نیست.
- `python3 tool/check_release_version.py --tag v1.0.0` — موفق؛ نسخهٔ `1.0.0` و build number `1` یکسان هستند.
- فایل‌های workflow و Dependabot با parser مربوط به YAML بارگذاری شدند — موفق.
- کنترل ZIP نهایی با `ZipFile.testzip()`، خواندن تمام entryها، اعتبارسنجی SHA-256 بسته و تطبیق manifest داخلی سورس انجام می‌شود.
- تست Dart/Flutter و تحلیل واقعی پروژه به اجرای Flutter SDK وابسته است. راستی‌آزمایی شش مجموعه آیکون در ابزار build اجباری است؛ خروجی CI باید مرحلهٔ آن را با موفقیت طی کند.
- اسکریپت تشخیصی Windows به دلیل نبود PowerShell و دسترسی به Windows host در این محیط اجرا نشده است؛ فقط محتوای آن و قراردادهای آن در آزمون‌های Python بررسی شده‌اند. دسترسی واقعی رایانهٔ کاربر به `dl.google.com` فقط با اجرای `tool\check_android_maven_windows.bat` روی همان رایانه قابل تعیین است.

## مرز اعتبارسنجی و انتشار

در محیط اجرای فعلی Flutter، Dart، Android SDK/NDK، Xcode، Visual Studio C++ و ابزارهای native packaging نصب نیستند. بنابراین در این نشست امکان اجرای `flutter pub get`، `dart format`، `flutter analyze`، `flutter test` و کامپایل واقعی APK/AAB، Web، Linux، Windows، macOS یا iOS وجود ندارد. این محدودیت به معنی شکست build نیست؛ به معنی اجرا نشدن آن است.

پوشه‌های میزبان iOS/macOS/Windows/Linux/Web در سورس ورودی موجود نبودند. اسکریپت bootstrap آن‌ها را از طریق `flutter create --platforms=android,ios,web,windows,macos,linux` روی runner ایجاد می‌کند و سپس تنظیمات مختص هر پلتفرم را اعمال می‌کند. CI این مرحله را اجرا می‌کند. برای اطمینان نهایی باید workflow روی GitHub Actions اجرا شود و نصب/پخش رسانه روی دستگاه‌ها و مرورگرهای مقصد آزموده شود.

خروجی iOS بدون signing یک `.app` آرشیوشده است، نه IPA نصب‌شونده. تولید IPA نیازمند گواهی، provisioning profile و ExportOptions ناشر است. امضای Windows/macOS نیز به گواهی ناشر نیاز دارد. پشتیبانی فرمت Web تابع decoder مرورگر است و به گستردگی libmpv بومی نیست؛ تضمین «همهٔ فرمت‌ها روی همهٔ سیستم‌ها» از نظر فنی معتبر نیست.
