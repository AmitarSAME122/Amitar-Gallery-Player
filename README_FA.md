# بستهٔ اصلاح کد اصلی AmitarGalleryPlayer

این بسته برای رفع خطای واقعی `flutter analyze` در شاخهٔ `Amitar` تهیه شده است.

## علت ریشه‌ای که در آخرین Log دیده شد

آخرین Log ارسالی، شاخهٔ `Amitar` را روی Commit زیر Checkout کرده است:

`b79c7067d3db287df8dc5a04d2b46f9fd5dcdbd9`

در فایل اصلی همان Commit هنوز `XFile.fileSystem(...)` و `XFile.scopedStorage(...)` استفاده شده‌اند. خروجی `dart fix --apply` نیز ۱۳۳ اصلاح خودکار اعمال کرده، اما APIهای فوق را نمی‌تواند جایگزین کند؛ سپس `flutter analyze` با ۱۶ مورد متوقف شده است. همان Log نشان می‌دهد `dart fix` به علت import مستقیم `cross_file`، آن را دوباره به‌عنوان dependency مستقیم به `pubspec.yaml` اضافه کرده است.

این یعنی کد منبع اصلاح‌شده هنوز در Commit بررسی‌شده حضور ندارد. تغییر Workflow به‌تنهایی نمی‌تواند این خطاهای Dart را رفع کند. در این بسته خود `lib/AmitarGalleryPlayer.dart` جایگزین شده است و لازم است حتماً همین فایل در شاخه ثبت شود.

## اصلاحات کد اصلی

1. حذف import مستقیم `package:cross_file/cross_file.dart` و همهٔ فراخوانی‌های `XFile.fileSystem` و `XFile.scopedStorage`؛ این APIها در نسخهٔ حل‌شدهٔ `cross_file 0.3.5+5` وجود ندارند.
2. جایگزینی خواندن فایل‌های محلی با `universal_io` و بررسی اندازه قبل از خواندن کامل در حافظه.
3. افزودن پل Android با `ContentResolver` برای رکوردهای قدیمی `content://`. کپی فایل با `Executor` پس‌زمینه، بافر ۶۴ KiB، سقف ۲۵۶ MiB و پاک‌سازی در خطا انجام می‌شود.
4. اصلاح مسیر پخش URIهای ذخیره‌شده پس از Restart: پیش‌تر کد پخش وجود `readBytes` موقت را اجباری می‌کرد؛ این Callback در Hive ذخیره نمی‌شود. اکنون مسیر پخش از `readEntryBytes` محدودشده استفاده می‌کند و در صورت نبود Callback، URI را از طریق ContentResolver می‌خواند. سقف حافظهٔ پخش ۴۸ MiB حفظ شده است.
5. اصلاح مسیر بارگذاری تصویر اصلی و callbacks فایل‌های محلی برای استفاده از `uio.File`.
6. اصلاح `ReorderableListView` به `onReorderItem` و حذف کاهش دستی اندیس قدیمی.
7. رفع import غیرضروری و مدیریت موضعی هشدار نام فایل ورودی که عمداً طبق قرارداد پروژه `AmitarGalleryPlayer.dart` است.

## اصلاحات پیکربندی و CI

- `pubspec.yaml` دیگر `cross_file` را مستقیم درخواست نمی‌کند.
- `pubspec.lock` نسخهٔ `cross_file 0.3.5+5` را به‌صورت transitive و از طریق `file_picker` ثبت می‌کند.
- `MainActivity.kt` پل Android هم‌نام با MethodChannel موجود در Dart را پیاده‌سازی می‌کند.
- `bootstrap_platforms.py` و تست‌هایش پیکربندی سفارشی Android را حفظ می‌کنند.
- Workflow اصلاحات خودکار Dart را قبل از Analyzer اعمال و در Job مستقل و با مجوز محدود ذخیره می‌کند.
- تست رگرسیون جدید تضمین می‌کند پخش URI ذخیره‌شده بعد از Restart به Callback موقت وابسته نباشد.

## فایل‌هایی که باید در مخزن جایگزین شوند

محتویات ZIP را روی ریشهٔ مخزن در شاخهٔ `Amitar` استخراج و فایل‌های هم‌مسیر را جایگزین کنید. فهرست دقیق در `PATCH_CONTENTS.txt` است.

**مهم‌ترین فایل: `lib/AmitarGalleryPlayer.dart`**. بدون جایگزینی این فایل، ۱۳ خطای `XFile` همچنان باقی می‌مانند؛ جایگزینی فقط Workflow یا `pubspec.yaml` کافی نیست.

پوشه‌های `assets/` و `presentation/` در این بسته نیستند و نباید از مخزن حذف یا جایگزین شوند. `SHA256SUMS.txt` نیز دستی ویرایش نشود؛ Workflow آن را در Runner از روی checkout کامل تولید می‌کند.

## نتیجهٔ آزمون‌هایی که واقعاً اجرا شدند

پس از اعمال بسته روی سورس کوچک‌شدهٔ ارسالی، مجموعهٔ زیر موفق شد:

- `test_bootstrap_platforms.py`: ۱۸ تست
- `test_project_invariants.py`: ۲۵ تست
- `test_release_version.py`: ۳ تست
- مجموع: ۴۶ تست منتخب موفق
- Python compileall، تجزیهٔ YAML، بررسی نبودن هر نوع import/فراخوانی `XFile` در فایل Dart، و ZIP integrity موفق.

Flutter و Dart SDK در محیط آماده‌سازی بسته نصب نبودند؛ بنابراین در این محیط ادعا نمی‌شود که `flutter analyze`، `flutter test` یا Build پلتفرم‌ها اجرا یا تأیید شده‌اند. باید بعد از Commit واقعی این فایل‌ها در GitHub Actions اجرا و نتیجه بررسی شود.
