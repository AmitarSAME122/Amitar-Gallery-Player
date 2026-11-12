# بستهٔ نهایی اصلاحات CI و سازگاری AmitarGalleryPlayer

این بسته بر اساس آخرین لاگ `Analyze and regression tests` ساخته شده است.

## علت خطای آخر

`flutter pub get` موفق بوده و `cross_file 0.3.5+5` را به‌صورت وابستگی انتقالی دریافت کرده است؛ اما فایل برنامه هنوز از سازنده‌های مختص API قدیمی/ناسازگار `XFile.fileSystem` و `XFile.scopedStorage` استفاده می‌کرد. در نتیجه ۱۳ خطای `undefined_method` گزارش شد. علاوه بر آن، Analyzer تعداد زیادی پیام info مربوط به قواعد Lint ثبت کرده بود.

## فایل‌های بسته

- `.github/workflows/build.yml` — اجرای `dart fix --apply`، قالب‌بندی، بررسی نهایی و ثبت امن تغییرات با مجوز نوشتن جداگانه.
- `pubspec.yaml` و `pubspec.lock` — حذف وابستگی مستقیم متعارض و نگه‌داشتن `cross_file 0.3.5+5` به‌صورت transitive.
- `lib/AmitarGalleryPlayer.dart` — حذف تمام فراخوانی‌های ناسازگار XFile، استفاده از `universal_io` برای مسیرهای محلی، پل محدود Android برای URIهای قدیمی `content://`، نگه‌داشتن نام فایل ورودی موردنیاز پروژه و اصلاح API مرتب‌سازی صف.
- `android/app/src/main/kotlin/com/amitar/amitar_gallery_player/MainActivity.kt` — پیاده‌سازی پل `ContentResolver` با I/O در executor پس‌زمینه، بافر ۶۴ KiB و سقف انتقال ۲۵۶ MiB.
- `tool/bootstrap_platforms.py` و تست آن — حفظ Activity سفارشی هنگام اجرای `flutter create`.
- `tool/test_project_invariants.py` — تست رگرسیون وابستگی، پل Android، Workflow و قرارداد جدید مرتب‌سازی.
- فایل‌های Dependency، Changelog و Validation Report برای همگام‌سازی مستندات.

## روش اعمال

۱. در شاخهٔ `Amitar` مسیرهای داخل ZIP را جایگزین کن و فایل جدید را در مسیر مشخص‌شده اضافه کن.
۲. فایل‌ها و پوشه‌های `assets/` و `presentation/` را حذف یا جایگزین نکن. این پوشه‌ها عمداً در این بسته نیستند و نسخهٔ کامل مخزن باید آن‌ها را نگه دارد.
۳. `SHA256SUMS.txt` را دستی ویرایش نکن؛ Workflow آن را با ابزار پروژه از محتوای واقعی checkout بازتولید می‌کند.
۴. تغییرات را Commit کن. در صورت اجرای push مستقیم به شاخه، مجوز `Contents: Read and write` در تنظیمات Actions و قوانین محافظت شاخه باید اجازهٔ Commit ربات را بدهند. در Pull Request، Job ثبت خودکار قالب‌بندی اجرا نمی‌شود؛ پس از Merge، اجرای push آن را ثبت می‌کند.

## مرز اعتبارسنجی

این بسته از لاگ CI، سورس ZIP موجود و فایل‌های اصلاحی قبلی ترکیب شده است. آزمون‌های Python، تجزیهٔ YAML، یکپارچگی ZIP و بررسی ایستا در این محیط انجام می‌شوند. این محیط Flutter/Dart SDK ندارد؛ بنابراین موفقیت واقعی `dart fix`، `flutter analyze`، `flutter test` یا Buildهای Android/iOS/macOS/Windows/Linux/Web تا زمان اجرای GitHub Actions قابل تأیید نیست.
