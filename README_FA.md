# اصلاحیهٔ تکمیلی ابزارهای GitHub Actions — AmitarGalleryPlayer

## علت این اصلاحیه

در اجرای اخیر، ۶۲ تست Python و `flutter pub get` موفق بودند، اما Workflow در مرحلهٔ بررسی قراردادها با این خطا متوقف شد:

```text
python3: can't open file 'tool/validate_source_contracts.py': [Errno 2] No such file or directory
```

بررسی ZIP سورس نشان داد Workflow به نسخهٔ جدیدتری ارتقا یافته، اما همهٔ فایل‌های ابزارِ موردنیاز همان Workflow به شاخه اضافه نشده‌اند. علاوه بر Validator، ابزارهای انتقال Snapshot نیز لازم‌اند؛ در غیر این صورت پس از عبور از مرحلهٔ فعلی، Jobهای Native در مراحل بعدی با خطای فایل مفقود متوقف می‌شدند.

## روش اعمال

1. این ZIP را در ریشهٔ مخزن `Amitar-Gallery-Player` و شاخهٔ `Amitar` استخراج کن.
2. گزینهٔ جایگزینی فایل‌های هم‌نام را بپذیر.
3. مسیرها باید دقیقاً از ریشهٔ مخزن باشند؛ برای مثال فایل باید در `tool/validate_source_contracts.py` قرار بگیرد، نه `AGP_CI_MISSING_TOOLS_FIX/tool/validate_source_contracts.py`.
4. فایل‌های موجود `assets/` و `presentation/` را حفظ کن؛ این بسته آن‌ها را شامل نمی‌شود.
5. همهٔ فایل‌های اضافه‌شده و جایگزین‌شده را در یک Commit ثبت کن.
6. هیچ دستور محلی PowerShell، Flutter یا Dart لازم نیست؛ اجرای بررسی‌ها در GitHub Actions انجام می‌شود.

## فایل‌های بسته

- دو Workflow هماهنگ‌شده: `build.yml` و `refresh-source-manifest.yml`.
- ابزارهای موردنیاز برای جمع‌آوری و اعمال Source Snapshot.
- Validator قراردادهای کد Dart، Pubspec، Lockfile و Android.
- نسخه‌های هماهنگ‌شدهٔ Bootstrap و تست‌های مربوط به آن‌ها.
- تست جدید `test_workflow_tool_paths.py` که تمام فرمان‌های Python داخل Workflowها را با فایل‌های واقعاً موجود تطبیق می‌دهد.

## رفتار مورد انتظار

ابتدا تست‌های Python باید اجرا شوند. تست جدید، وجود تمام فایل‌های Python فراخوانی‌شده در Workflowها را پیش از اجرای Validator کنترل می‌کند. سپس `validate_source_contracts.py` باید قراردادهای API و وابستگی را بررسی کند. Jobهای ساخت نیز همان Source Snapshot و Lockfile آزمایش‌شده را دریافت می‌کنند.

`SHA256SUMS.txt` را دستی ویرایش نکن؛ Workflow آن را از روی فایل‌های Track‌شده بازتولید می‌کند.

## محدودیت تأیید

این اصلاحیه روی ZIP سورسِ ارائه‌شده ادغام و با تست‌های Python قابل‌اجرا بررسی شده است. محیط آماده‌سازی Flutter/Dart SDK ندارد؛ بنابراین موفقیت `flutter analyze`، `flutter test` و Buildهای Native فقط پس از اجرای GitHub Actions قابل تأیید است.
