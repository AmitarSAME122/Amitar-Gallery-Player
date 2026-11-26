# گزارش بازبینی و نهایی‌سازی AmitarGalleryPlayer 1.0.0

## خلاصهٔ اجرایی

این بازبینی روی آرشیو کامل ارسالی انجام شد؛ ساختار موجود، رابط کاربری، فایل Dart اصلی، دارایی‌های رسانه‌ای و برندینگ، تنظیمات وابستگی، پیکربندی Android، ابزارهای CI، تست‌ها و مستندات حفظ شدند. اصلاحات به‌صورت هدفمند انجام شده‌اند و فایل‌ها یا قابلیت‌های اصلی صرفاً برای ساده‌سازی حذف نشده‌اند.

## اصلاحات اصلی

### Flutter و مدیریت فایل

- مهاجرت از `FilePicker.getDirectoryPath()` منسوخ به `FilePicker.pickDirectory()` مبتنی بر `Uri`.
- فقط URI با scheme برابر `file:` به مسیر فایل تبدیل می‌شود؛ URIهایی مانند `content://` به مسیر جعلی فایل تبدیل نمی‌شوند.
- نسخهٔ `file_picker` در `pubspec.yaml` و lockfile با API جدید هماهنگ شد.
- قراردادهای منبع برای جلوگیری از بازگشت API منسوخ و ناسازگاری قرارداد Android `content://` به آزمون‌های نگهبان افزوده/به‌روزرسانی شدند.

### Android و زنجیرهٔ ساخت

- زنجیرهٔ نسخه‌ای هماهنگ و مستند: AGP `8.13.2`، Gradle Wrapper `8.14.6` و Kotlin Gradle Plugin `2.4.21`.
- JDKهای `17` تا `24` برای اجرای Gradle انتخاب‌شده پذیرفته می‌شوند؛ JDK `17` baseline پیشنهادی CI است. نسخه‌های خارج از این بازه با خطای تشخیصی متوقف می‌شوند.
- پیش‌بررسی واقعی JDK در `tool/build.py` با سیاست مستند و تست‌ها هماهنگ شد.
- فایل‌های Android Adaptive Icon برای Android 8+ تکمیل شدند: XML launcher، رنگ background شفاف، لایهٔ foreground و monochrome.
- دریافت Gradle Wrapper همچنان به commit ثابت و SHA-256 تأییدشده متکی است؛ فایل JAR باینری عمداً در سورس نگهداری نمی‌شود و bootstrap آن را در محیط مقصد بازیابی و راستی‌آزمایی می‌کند.
- مسیرهای محلی رایانه، `android/local.properties` و cacheهای تولیدشده از بستهٔ نهایی حذف شدند.

### CI، تست و مستندات

- CI روی Flutter stable `3.50.1` تنظیم شده و حداقل نسخهٔ اعلام‌شدهٔ پروژه `3.47.9` باقی مانده است.
- ماتریس سازگاری Flutter/Dart/Java/AGP/Gradle/Kotlin و محدودیت‌های پلتفرمی مستند شد.
- دو لینک پوستر ناموجود در READMEها به پیش‌نمایش دوزبانهٔ موجود اصلاح شدند.
- تست‌های قراردادی File Picker، URI، زنجیرهٔ Gradle و دامنهٔ JDK همگام شدند.
- manifest هش‌ها برای فایل‌های موجود بازتولید/به‌روزرسانی شد؛ دو ورودی پوستر که فایل متناظرشان در آرشیو موجود نبود حذف شدند.

## نتیجهٔ آزمون‌های اجراشده در محیط بازبینی

| آزمون | نتیجه |
|---|---|
| تست‌های Python پروژه (`unittest`) | ۸۴ تست؛ ۸۲ موفق، ۲ ردشده به علت نبود Git index، صفر شکست |
| `tool/check_release_version.py` | موفق؛ نسخهٔ `1.0.0+1` سازگار است |
| `tool/validate_source_contracts.py` | موفق؛ قرارداد Dart، lockfile، File Picker و Android URI سازگار است |
| `python -m compileall -q tool` | موفق |
| parse فایل‌های YAML پروژه | موفق |
| parse فایل‌های XML منابع Adaptive Android | موفق |
| لینک‌های رسانه‌ای READMEها | موفق؛ تمام مسیرهای معرفی‌شده موجودند |
| عدم وجود فایل‌های محلی/cache در سورس | موفق |
| SHA-256 فایل‌های manifest | در بستهٔ خروجی کنترل شده است |

## مواردی که در این محیط قابل تأیید نبودند

این محیط Flutter SDK و Dart SDK نصب‌شده ندارد و دسترسی شبکه برای دریافت SDK نیز در دسترس نبود. بنابراین موارد زیر اجرا نشده‌اند و نباید به‌عنوان تست موفق‌شده تلقی شوند:

- `dart format` و `flutter analyze` روی کد Dart کامل؛
- `flutter test`؛
- `flutter build apk`, `appbundle`, `windows`, `linux`, `macos`, `ios` و `web`؛
- اجرای اپ روی دستگاه واقعی و بررسی رفتار codec/permission در هر سیستم‌عامل.

در خروجی `flutter analyze` قبلی کاربر ۶۶ مورد info/warning (و صفر error) گزارش شده بود. این بازبینی تعدادی از موارد API و ساختار را اصلاح کرده، اما بدون اجرای analyzer با SDK دقیق پروژه ادعای رفع قطعی تمام ۶۶ مورد مطرح نمی‌شود. پس از نصب Flutter توصیه می‌شود خروجی analyzer دوباره ثبت و موارد باقی‌مانده مرحله‌به‌مرحله اصلاح شوند.

## محدودیت سازگاری نسخه‌ها

سازگاری با «هر نسخه» از Gradle، JDK، Kotlin، Flutter یا Android SDK از نظر فنی ممکن نیست؛ این ابزارها حداقل نسخه، سقف سازگاری و تغییرات ناسازگار دارند. این پروژه یک بازهٔ آزمون‌پذیر مشخص کرده است: Flutter از `3.47.9` به بعد، CI روی `3.50.1`، و JDK `17–24` با زنجیرهٔ Gradle/AGP/Kotlin ثبت‌شده. برای عبور از این بازه باید ماتریس وابستگی‌ها هم‌زمان به‌روزرسانی و روی همهٔ runnerهای میزبان Build شود.

## راه‌اندازی در Windows

از CMD در ریشهٔ پروژه اجرا کنید:

```cmd
python tool\bootstrap_platforms.py
flutter doctor -v
flutter pub get
python tool\check_release_version.py
python tool\validate_source_contracts.py
python -m unittest discover -s tool -p "test_*.py" -v
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
python tool\verify_platform_icons.py
python tool\build.py android
```

برای Android، خروجی `flutter doctor -v` باید JDK بین 17 تا 24 را گزارش کند؛ JDK 17 گزینهٔ مرجع CI است. برای نصب/انتخاب JDK مرجع در Windows:

```cmd
tool\setup_android_jdk_windows.bat -InstallIfMissing
```

ساخت Windows باید روی Windows، Linux روی Linux، و macOS/iOS روی macOS انجام شود. برای ساخت هر پلتفرم باید SDK و ابزار native همان میزبان نصب باشند. ساخت Release قابل انتشار نیز به کلید امضای اختصاصی ناشر نیاز دارد.

---

**وضعیت تحویل:** سورس و ابزارهای پشتیبان اصلاح و آزمون‌های Python موفق شده‌اند؛ تأیید نهایی Flutter analyzer و Build واقعی هر سیستم‌عامل به اجرای دستورات فوق روی میزبان‌های دارای SDK مربوطه وابسته است.
