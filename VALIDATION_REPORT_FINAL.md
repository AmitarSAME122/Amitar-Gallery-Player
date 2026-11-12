# گزارش اعتبارسنجی بستهٔ نهایی AmitarGalleryPlayer

## ورودی‌های تحلیل‌شده

- `logs_117304365062.zip`
- `AmitarGalleryPlayer(2).zip`
- Checkout گزارش‌شده در لاگ: `9464e29caf77cc3990ad3917cba066e5700eebea`

## یافته‌های CI

در لاگ، `flutter pub get` موفق بود، اما `flutter analyze` هنوز ۱۳ فراخوانی منسوخ/ناموجود `XFile.fileSystem` و `XFile.scopedStorage` را در Checkout گزارش می‌کرد. همان اجرا نشان می‌داد که `dart fix --apply` یک `cross_file` را از وابستگی transitive به direct تبدیل کرده است. درحالی‌که ZIP سورس ارسالی حاوی نسخهٔ اصلاح‌شدهٔ `lib/AmitarGalleryPlayer.dart`، بدون import مستقیم `cross_file` و بدون این APIها بود. بنابراین CI و سورس ارسال‌شده یکسان نبودند.

## اصلاحات نهایی

- حذف `dart fix --apply` از اجرای خودکار CI تا ابزار Quick Fix نتواند بی‌اجازه `pubspec.yaml` یا وابستگی‌ها را تغییر دهد.
- اعتبارسنجی قراردادهای منبع و Lockfile بعد از `flutter pub get` و قبل از Analyzer.
- قالب‌بندی Dart روی شاخه‌ها و بررسی صرفاً read-only برای Tagها.
- جمع‌آوری Source Snapshot محدود و امن شامل فایل‌های Dart/config تغییرکرده، به‌همراه Lockfile به‌عنوان Artifact جداگانه.
- اعمال دقیق همان Snapshot و Lockfile در سه خانوادهٔ ساخت Linux/Android/Web، Windows و macOS/iOS پیش از `flutter pub get --enforce-lockfile`.
- انتقال Job ذخیرهٔ تغییرات به بعد از موفقیت Quality و تمام Buildهای Native؛ Commit شامل Source، Lockfile و Manifest است.
- محافظت در برابر race شاخه: اگر فایل محافظت‌شده پس از شروع Run تغییر کرده باشد، Job از overwrite خودداری می‌کند.
- تبدیل Workflow مستقل Manifest به حالت دستی برای حذف رقابت Push با Job ذخیرهٔ CI.
- بازیابی مجوز اجرایی `android/gradlew` در Runnerهای Unix.
- تست مسیرهای مجاز/غیرمجاز و جلوگیری از path traversal و symbolic link در انتقال Artifactها.
- تست‌های brand asset و آیکون Windows فقط در آرشیو کاهش‌یافته‌ای که این کاربر assets را از آن حذف کرده، Skip می‌شوند؛ روی مخزن کامل، آن تست‌ها همچنان اجرا می‌شوند.

## نتایج قابل تکرار در این محیط

- `python -m py_compile tool/*.py`: موفق.
- YAML parse برای هر دو Workflow با `yaml.BaseLoader`: موفق.
- `python -m unittest discover -s tool -p 'test_*.py' -v`: ۷۱ مورد؛ موفق، با ۴ Skip مورد انتظار.
  - ۲ Skip مربوط به نبود Git working tree در آرشیو استخراج‌شده.
  - ۲ Skip مربوط به حذف آگاهانهٔ منابع `assets/` و `presentation/` از ZIP ارسالی.
- اعتبارسنجی قرارداد منبع: موفق؛ هیچ `XFile.fileSystem`، `XFile.scopedStorage`، import مستقیم `cross_file` یا `onReorder` در کد اصلی باقی نمانده است.
- شبیه‌سازی واقعی Git bare remote: موفق؛ Source Snapshot و Lockfile روی branch tip جدید اعمال و Push شدند، SHA256 manifest بازسازی شد و Commit نامرتبط هم حفظ شد.
- ZIP نهایی با `testzip()` بررسی و SHA-256 آن محاسبه شده است.

## کارهایی که در این محیط انجام نشده‌اند

Flutter/Dart SDK در این محیط آماده‌سازی نصب نبود؛ بنابراین این بسته ادعای اجرای `flutter pub get`، `flutter analyze`، `flutter test` یا Buildهای Android، Web، Linux، Windows، macOS و iOS را ندارد. این مراحل باید در Run جدید GitHub Actions تأیید شوند. به‌دلیل حذف عمدی دارایی‌های تصویری از آرشیو ارسالی، آن دارایی‌ها در بستهٔ اصلاحی قرار ندارند و باید در مخزن اصلی حفظ شوند.
