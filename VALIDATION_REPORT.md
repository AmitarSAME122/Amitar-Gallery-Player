# گزارش اصلاح و اعتبارسنجی — AmitarGalleryPlayer 1.0.0+1

تاریخ: ۹ نوامبر ۲۰۲۶  
نوع تحویل: سورس بازبینی‌شده و پیکربندی‌شده برای انتشار چندسکویی؛ نه باینری از پیش‌ساخته‌شده.

## پیکربندی نسخهٔ اول

| مؤلفه | مقدار تثبیت‌شده |
|---|---:|
| نسخهٔ برنامه | `1.0.0+1` |
| Flutter stable در CI | `3.47.9` |
| Dart | نسخهٔ همراه Flutter |
| JDK هدف Android | `17` |
| Android Gradle Plugin | `8.13.2` |
| Gradle Wrapper | `8.14.6` |
| Kotlin Gradle Plugin | `2.4.21` |
| شناسهٔ Android | `com.amitar.amitar_gallery_player` |

نسخه‌ها به‌صورت یک مجموعهٔ سازگار تثبیت شده‌اند؛ ارتقای مستقل و آزمایش‌نشده به AGP 9 یا Gradle 9 انجام نشده است. SHA-256 توزیع Gradle 8.14.6 نوع `bin` برابر `7988ed071b2a07900e2ec715fca15c6ab72bce6db433af301fa7fa7e9407bd24` است. SHA-256 فایل Gradle Wrapper JAR مورد انتظار برابر `ad16bca46cb71bb5887c546860d93992aeee35c1fdaf4a242b0a612375d937e0` است. فایل Wrapper JAR در سورس نگهداری نمی‌شود؛ bootstrap آن را از commit ثابت c27417f در مخزن رسمی Gradle دریافت و با checksum رسمی اعتبارسنجی می‌کند. CI این JAR تأییدشده را از Job کیفیت به Jobهای ساخت پلتفرم منتقل می‌کند و در هر Job دوباره hash را بررسی می‌کند.

## اصلاحات اعمال‌شده

- تنظیمات واقعی `settings.gradle.kts`، `build.gradle.kts`، `gradle.properties`، Wrapper، bootstrap و تست‌ها با یک مجموعهٔ نسخهٔ واحد هماهنگ شدند.
- فایل `android/local.properties` ممکن است در زمان اجرای `flutter create` به‌صورت محلی در Runner تولید شود؛ آزمون CI اکنون وضعیت Git index را بررسی می‌کند، نه نبود فایل موقت در working tree. مسیرهای محلی SDK و کلیدهای امضا در `.gitignore` هستند و فایل‌های محلی/امضا از manifest هش سورس نیز کنار گذاشته می‌شوند.
- نسخهٔ مستقیم `cross_file` به `^0.4.0` تغییر کرد و override تکراری حذف شد.
- URLهای lockfile به مخزن canonical یعنی `pub.dev` یکسان‌سازی شدند.
- فایل‌های cache، خروجی build، فایل‌های IDE، cache پایتون و فایل پشتیبان قدیمی از بستهٔ سورس کنار گذاشته شدند.
- اسکریپت‌های bootstrap میزبان‌های بومی iOS، macOS، Windows، Linux و Web را در runner مناسب ایجاد می‌کنند؛ تنظیم Android نیز idempotent است. Wrapper JAR از منبع upstream ثابت دریافت، checksum و ساختار آن بررسی، و سپس از طریق artifact کوتاه‌عمر بین runnerها منتقل می‌شود.
- آیکون‌های Android adaptive، iOS، macOS، Windows، Linux و Web با کنترل ساختاری PNG/ICO و ارجاع manifest اعتبارسنجی می‌شوند.
- اسکن کتابخانه/پوشه و واردسازی موبایل دارای سقف آیتم و بودجهٔ حافظه هستند؛ مسیرهای دسترسی فایل به مجوزهای پلتفرم محدود می‌مانند.
- یک موتور پخش `media_kit` حفظ شده است؛ موتور موازی یا لایهٔ ذخیره‌سازی تکراری افزوده نشده است.
- CI امضای اختیاری Android را پشتیبانی می‌کند. با تعریف هر چهار Secret با نام‌های `AMITAR_ANDROID_KEYSTORE_BASE64`، `AMITAR_ANDROID_STORE_PASSWORD`، `AMITAR_ANDROID_KEY_PASSWORD` و `AMITAR_ANDROID_KEY_ALIAS`، APK/AAB با کلید ناشر امضا می‌شوند. keystore فقط در `$RUNNER_TEMP` قرار می‌گیرد. پیکربندی ناقص باعث توقف build می‌شود؛ در نبود تمام Secretها خروجی صرفاً debug/QA خواهد بود.
- خطای نگارشی DPI پوستر در changelog اصلاح شد؛ خروجی PNG پوستر A3 برابر ۳۰۰ DPI است.
- آزمون عدم ثبت مسیر شخصی Android SDK به‌جای بررسی نبود فایل در working tree، Git index را بررسی می‌کند؛ در نتیجه `android/local.properties` تولیدشده توسط Flutter در CI موجب false negative نمی‌شود.
- تولیدکنندهٔ `SHA256SUMS.txt` در Git checkout فقط فایل‌های ثبت‌شده در Git index را هش می‌کند و فایل‌های محلی `android/local.properties`، `android/key.properties` و Wrapper دانلودشده را کنار می‌گذارد. در Source archive فاقد `.git` نیز fallback صریح با همین exclusions فعال است.
- فایل `.gitattributes` در بستهٔ اصلاحات وجود دارد تا ورودی فهرست SHA-256 نیز در مخزن Git ثبت شود.
- manifest هش SHA-256 سورس بازسازی و برای همهٔ فایل‌های ثبت‌شده کنترل می‌شود.

## آزمون‌های اجراشده در این محیط

- `python3 -m py_compile tool/*.py` — موفق.
- `python3 -m unittest discover -s tool -p 'test_*.py' -v` — **۵۷ از ۵۷ آزمون موفق**؛ شامل bootstrap و checksum Wrapper، یکپارچگی تنظیم Android، مدیریت JDK، امضا در CI، آیکون‌های شش پلتفرم، ساخت fixture بستهٔ DEB، manifest و نسخهٔ انتشار.
- `python3 tool/check_release_version.py --tag v1.0.0` — موفق؛ نسخهٔ `1.0.0` و build number `1` هماهنگ‌اند.
- فایل‌های YAML workflow و Dependabot با parser بارگذاری شدند؛ شاخهٔ `Amitar`، پنج job، artifact مربوط به Wrapper و سه مرحلهٔ دریافت آن نیز با کنترل ساختاری بررسی شدند.
- ZIP انتشار با `ZipFile.testzip()`، خواندن entryها و checksum کل بسته بررسی می‌شود؛ manifest SHA-256 داخلی نیز جداگانه تأیید می‌شود.

توجه: تست DEB از fixture بسته‌بندی استفاده می‌کند و اثبات نمی‌کند که باینری Flutter برنامه ساخته شده است. همین‌طور آزمون‌های Python جایگزین تحلیل Dart، اجرای تست Flutter یا تست روی دستگاه واقعی نیستند.

## مرز اعتبارسنجی باینری

در محیط این نشست Flutter، Dart، Gradle، Android SDK/NDK، Xcode و Visual Studio C++ موجود نیستند؛ Java نصب‌شده در محیط `21.0.12` است، درحالی‌که CI برای Android به‌طور صریح JDK `17` نصب می‌کند. بنابراین این محیط قادر به اجرای `flutter pub get`، `dart format`، `flutter analyze`، `flutter test` یا کامپایل واقعی و تولید installer نیست. خروجی تحویلی یک بستهٔ سورس آمادهٔ اجرای CI است، نه APK/EXE/DEB/DMG/IPA از پیش ساخته‌شده.

## خروجی‌هایی که CI روی میزبان مناسب تولید می‌کند

| میزبان ساخت | خروجی برنامه‌ریزی‌شده | نکتهٔ انتشار |
|---|---|---|
| Ubuntu/Linux | APKهای تفکیک‌شدهٔ ABI و AAB، Web ZIP، Linux TAR.GZ و DEB | Linux به GTK و libmpv سازگار نیاز دارد؛ AAB مستقیماً مثل APK نصب نمی‌شود. |
| Windows | ZIP قابل‌حمل و Setup EXE با Inno Setup | امضای Authenticode در پیکربندی فعلی انجام نمی‌شود. |
| macOS | APP ZIP و DMG | امضای Developer ID و notarization در پیکربندی پیش‌فرض نیست. |
| iOS | آرشیو ZIP شامل `.app` بدون امضا | IPA نصب‌شونده به گواهی، provisioning و ExportOptions معتبر ناشر نیاز دارد. |
| Web | ZIP سایت استاتیک | خروجی وب است، نه installer دسکتاپ؛ قابلیت decode تابع مرورگر است. |

ساخت Windows باید روی Windows، ساخت macOS/iOS روی macOS و ساخت Linux/Android/Web روی runner مناسب انجام شود. یک ماشین یا یک باینری واحد نمی‌تواند جایگزین SDK و امضای اختصاصی تمام پلتفرم‌ها شود. همچنین پشتیبانی «تمام فرمت‌های رسانه‌ای روی تمام سیستم‌ها» قابل تضمین نیست؛ پوشش codec به libmpv، بستهٔ codec، معماری و runtime هر پلتفرم بستگی دارد و Web محدودیت decoder مرورگر را دارد.

برای تأیید انتشار نسخهٔ واقعی، ابتدا repository را در GitHub قرار دهید، سپس workflow را اجرا کنید و موفقیت jobهای quality، linux-android-web، windows و apple را بررسی کنید. پیش از انتشار عمومی نیز نصب و پخش رسانه باید روی دستگاه‌ها و مرورگرهای هدف آزموده شود.
