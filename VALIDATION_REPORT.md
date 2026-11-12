# گزارش اعتبارسنجی — اصلاح خطای Flutter Analyze

## ورودی CI بررسی‌شده

- مخزن: `AmitarSAME122/Amitar-Gallery-Player`
- شاخه: `Amitar`
- Commit: `e334188d7d1ffbb43c3e68a4791b688edfa03e0b`
- Workflow: `Verify and build AmitarGalleryPlayer`
- Job متوقف‌شده: `Analyze and regression tests`
- مرحلهٔ متوقف‌شده: `flutter analyze`

## نتیجهٔ اجرای واقعی در GitHub Actions

| مرحله | نتیجهٔ لاگ |
|---|---|
| Checkout شاخه | موفق |
| تنظیم Java 17 و Flutter 3.47.9 | موفق |
| Bootstrap میزبان‌های پلتفرم | موفق |
| تولید و بررسی Source Manifest | موفق |
| نصب وابستگی‌های Python | موفق |
| تست‌های Python | ۶۲ از ۶۲ موفق |
| `flutter pub get` | موفق |
| تولید آیکون‌های پلتفرم | موفق |
| `dart fix --apply` | ۱۳۳ اصلاح اعمال‌شده |
| `dart format lib test` | ۳ فایل قالب‌بندی‌شده |
| `flutter analyze` | ناموفق؛ ۱۶ مورد |

### تشخیص دقیق Analyzer

از ۱۶ مورد گزارش‌شده:

- ۱۱ مورد `undefined_method` برای `XFile.fileSystem`؛
- ۲ مورد `undefined_method` برای `XFile.scopedStorage`؛
- یک مورد `file_names` برای نام عمدی ورودی برنامه؛
- یک مورد `unnecessary_import` برای `dart:typed_data`؛
- یک مورد `deprecated_member_use` برای `onReorder`.

نسخهٔ حل‌شدهٔ `cross_file` در لاگ `0.3.5+5` است. کد شاخه هنوز سازنده‌های متعلق به API جدیدتر `0.4.x` را فراخوانی کرده است. Quick Fix خودکار، APIهای حذف‌شده را تبدیل نمی‌کند؛ به همین علت با وجود ۱۳۳ Quick Fix و اجرای موفق Formatter، Analyzer شکست خورده است.

## اصلاحات موجود در بسته

- `lib/AmitarGalleryPlayer.dart`: حذف استفاده از APIهای ناسازگار، استفاده از `universal_io` برای فایل‌های محلی، پل Android برای URIهای قدیمی `content://`، رفع سه پیام اطلاعاتی، اصلاح callback صف.
- `pubspec.yaml` و `pubspec.lock`: عدم وابستگی مستقیم به `cross_file 0.4.x`؛ حفظ `cross_file 0.3.5+5` به‌صورت transitive.
- `MainActivity.kt`: پیاده‌سازی MethodChannel با `ContentResolver`، I/O در executor، بافر ۶۴ KiB، محدودیت حجم و پاک‌سازی فایل ناقص در خطا.
- `build.yml`: اجرای Quick Fix و Formatter، اعتبارسنجی نتیجه و Job مجزای ثبت تغییرات Formatter با دسترسی نوشتن محدود.
- `bootstrap_platforms.py` و تست‌ها: حفظ MainActivity سفارشی و پوشش Regression برای bootstrap و APIهای مورد استفاده.

## اعتبارسنجی مستقل انجام‌شده برای بسته

| بررسی | نتیجه |
|---|---:|
| `python3 -m compileall -q tool` | موفق |
| `test_bootstrap_platforms.py` | ۱۸ از ۱۸ موفق |
| `test_project_invariants.py` | ۲۴ از ۲۴ موفق |
| `test_release_version.py` | ۳ از ۳ موفق |
| تست‌های منتخب Python | ۴۵ از ۴۵ موفق |
| تجزیهٔ YAML Workflow | موفق |
| ZIP integrity و SHA-256 | موفق |

تست‌های منتخب در یک fixture محلی Git اجرا شدند تا رفتار Manifest مبتنی بر Git index نیز قابل بررسی باشد. فایل `android/gradlew` در fixture دارای مجوز اجرایی شد؛ ZIPهای ساخته‌شده روی برخی میزبان‌ها لزوماً bit اجرایی Unix را نگه نمی‌دارند و بستهٔ اصلاحی این فایل را جایگزین نمی‌کند.

## محدودیت فایل منبع کوچک‌شده

در ZIP ارسالی، محتوای `assets/` و `presentation/` عمداً حذف شده بود. به همین علت اجرای کامل مجموعهٔ تست روی آن ZIP، تست‌هایی را که به تصاویر برند، آیکون‌ها و پوستر وابسته‌اند با `FileNotFoundError` مواجه می‌کند. این خطاها از حذف فایل‌ها در بستهٔ ارسالی ناشی می‌شوند و دربارهٔ فایل‌های کامل شاخهٔ GitHub نتیجه‌گیری نمی‌کنند.

همین‌طور Flutter و Dart SDK در محیط ساخت این بسته نصب نبودند؛ پس `flutter analyze`، `flutter test` و Build واقعی پلتفرم‌ها در این محیط اجرا نشده‌اند. نتیجهٔ نهایی Analyzer فقط پس از Commit کردن این بسته و اجرای CI واقعی مشخص می‌شود.

## تأیید مورد انتظار در اجرای بعدی

پس از اعمال بسته، موارد زیر باید در GitHub Actions بررسی شوند:

1. `flutter pub get` بدون تغییر مستقیم‌شدن `cross_file`.
2. `dart fix --apply` بدون افزودن وابستگی غیرضروری.
3. `dart format --output=none --set-exit-if-changed lib test` بدون تغییر باقی‌مانده.
4. `flutter analyze` با صفر issue.
5. `flutter test --reporter expanded`.
6. Jobهای build برای Linux/Android/Web، Windows و macOS/iOS.

این گزارش هیچ‌یک از Buildهای بعدی را پیشاپیش موفق اعلام نمی‌کند.
