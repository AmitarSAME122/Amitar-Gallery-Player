# بستهٔ اصلاح سازگاری وابستگی‌ها و Android — AmitarGalleryPlayer

این بسته فقط شامل فایل‌های اصلاح‌شده است و جایگزین کامل پروژه نیست.

## نکتهٔ مهم دربارهٔ ZIP ارسالی

در ZIP ورودی، محتوای `assets/` و `presentation/` موجود نبود. این بسته عمداً هیچ‌یک از فایل‌های آن دو پوشه را حذف یا بازسازی نمی‌کند. هنگام اعمال تغییرات روی مخزن اصلی GitHub، تمام تصاویر، آیکون‌ها، فایل‌های ارائه و سایر فایل‌های اصلی موجود در شاخهٔ `Amitar` را نگه دارید.

## فایل‌های این بسته

- `pubspec.yaml` و `pubspec.lock`: حذف وابستگی مستقیم ناسازگار `cross_file 0.4.0` و ثبت نسخهٔ سازگار transitive.
- `lib/AmitarGalleryPlayer.dart`: حذف APIهای `XFile 0.4` از برنامه؛ استفاده از `universal_io` برای مسیرهای محلی و پل Android برای URIهای قدیمی `content://`.
- `android/app/src/main/kotlin/com/amitar/amitar_gallery_player/MainActivity.kt`: پیاده‌سازی پل `ContentResolver` با اجرای I/O در executor پس‌زمینه، بافر ۶۴ کیلوبایتی، سقف ۲۵۶ MiB و پاک‌سازی فایل موقت توسط کد Dart.
- `tool/bootstrap_platforms.py`: حفظ `MainActivity.kt` سفارشی فقط در مرز اجرای `flutter create`، بدون جلوگیری از ایجاد Activity جدید در bootstrap اولیه.
- `tool/test_bootstrap_platforms.py` و `tool/test_project_invariants.py`: تست‌های رگرسیون برای solver، پل Android و رفتار bootstrap.
- `DEPENDENCIES.md`، `VALIDATION_REPORT.md` و `CHANGELOG.md`: همگام‌سازی مستندات با پیاده‌سازی.

## اعمال روی GitHub بدون اجرای ابزار محلی

1. مخزن `Amitar-Gallery-Player` را در GitHub باز کنید و شاخهٔ `Amitar` را انتخاب کنید.
2. محیط ویرایشگر وب GitHub (`github.dev`) را برای همان مخزن باز کنید.
3. فایل‌های همین بسته را در مسیرهای هم‌نام جایگزین کنید؛ فایل `MainActivity.kt` باید دقیقاً در مسیر اعلام‌شده قرار بگیرد.
4. فایل‌های موجود در `assets/` و `presentation/`، فایل `SHA256SUMS.txt` و سایر فایل‌های پروژه را حذف نکنید. `SHA256SUMS.txt` در CI از روی checkout کامل مخزن بازتولید می‌شود.
5. تغییرات را در یک شاخهٔ اصلاحی commit کنید و برای شاخهٔ `Amitar` یک Pull Request باز کنید.
6. نتیجهٔ GitHub Actions را بررسی کنید. ابتدا باید `flutter pub get` و تحلیل/تست Dart موفق شوند؛ سپس Jobهای ساخت پلتفرم‌ها اجرا می‌شوند.

## مرز اعتبارسنجی این بسته

در محیط آماده‌سازی، YAML فایل‌های Pub و Workflow تجزیه شده‌اند، همهٔ اسکریپت‌های Python با `py_compile` بررسی شده‌اند، ۱۸ تست bootstrap، ۳ تست رگرسیون وابستگی/پل Android و ۳ تست نسخه با موفقیت اجرا شده‌اند. کد Kotlin نیز از نظر syntax/type با stubهای حداقلی APIهای Android/Flutter کامپایل شده است.

در این محیط Flutter و Dart SDK نصب نبود؛ بنابراین `flutter pub get`، `dart format`، `flutter analyze`، تست‌های Flutter و Build واقعی Android/iOS/Desktop/Web اجرا نشده‌اند. علاوه بر این، تست‌هایی که به فایل‌های حذف‌شدهٔ `assets/` و `presentation/` وابسته‌اند فقط در checkout کامل GitHub قابل ارزیابی‌اند. نتیجهٔ نهایی فقط پس از اجرای GitHub Actions روی شاخهٔ اصلی پروژه تأیید می‌شود.
