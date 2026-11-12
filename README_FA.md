# بستهٔ اصلاح نهایی خطای Flutter Analyze — AmitarGalleryPlayer

این بسته برای خطای ثبت‌شده در اجرای GitHub Actions روی شاخهٔ `Amitar` تهیه شده است.

## علت دقیق توقف آخرین اجرا

آخرین لاگ قابل‌بررسی، Commit زیر را Checkout کرده است:

`e334188d7d1ffbb43c3e68a4791b688edfa03e0b`

مراحل `flutter pub get`، تولید آیکون‌ها، ۶۲ تست Python و قالب‌بندی Dart با موفقیت اجرا شده‌اند. سپس `flutter analyze` با ۱۶ مورد متوقف شده است:

- ۱۱ فراخوانی `XFile.fileSystem` که در نسخهٔ حل‌شدهٔ `cross_file 0.3.5+5` وجود ندارند.
- ۲ فراخوانی `XFile.scopedStorage` که در همان نسخه وجود ندارند.
- یک پیام اطلاعاتی دربارهٔ نام فایل اصلی `AmitarGalleryPlayer.dart`.
- یک import غیرضروری `dart:typed_data`.
- یک پیام اطلاعاتی دربارهٔ منسوخ‌شدن `onReorder`.

نکتهٔ مهم: `dart fix --apply` در همان اجرا ۱۳۳ اصلاح خودکار انجام داده، اما این APIهای حذف‌شده را نمی‌تواند جایگزین کند. همچنین چون مرحلهٔ `flutter analyze` شکست خورده، Job وابستهٔ ذخیرهٔ خودکار فایل‌های قالب‌بندی‌شده اجرا نمی‌شود. بنابراین لازم است فایل منبع اصلاح‌شدهٔ این بسته واقعاً در شاخه Commit شود؛ صرف اجرای Quick Fix کافی نیست.

## اصلاحات این بسته

1. حذف import مستقیم `cross_file` از برنامه و حذف قید مستقیم ناسازگار آن از `pubspec.yaml`؛ `file_picker` نسخهٔ سازگار `cross_file 0.3.5+5` را به‌صورت وابستگی transitive دریافت می‌کند.
2. جایگزینی دسترسی‌های فایل محلی `XFile.fileSystem` با `universal_io`.
3. جایگزینی دسترسی‌های قدیمی Android `XFile.scopedStorage` با پل بومی `ContentResolver` برای URIهای `content://`. خواندن با بافر ۶۴ KiB در executor پس‌زمینه انجام می‌شود، سقف اندازه کنترل می‌شود و فایل موقت پس از خواندن حذف می‌شود.
4. حذف import غیرضروری `dart:typed_data`؛ انواع دادهٔ بایتی موردنیاز از `flutter/services.dart` در دسترس‌اند.
5. نگه‌داشتن نام ورودی اصلی با suppression موضعی `file_names`؛ نام فایل بنا به قرارداد پروژه `AmitarGalleryPlayer.dart` است.
6. جایگزینی `ReorderableListView.onReorder` با `onReorderItem` و حذف کاهش دستی اندیس که با قرارداد جدید اشتباه بود.
7. هماهنگ‌سازی `MainActivity.kt`، Lockfile، Bootstrap و تست‌های رگرسیون.
8. حفظ Workflow قالب‌بندی و ثبت تغییرات با حداقل مجوز نوشتن؛ Job کیفیت و Jobهای Build دسترسی نوشتن دریافت نمی‌کنند.

## فایل‌های داخل بسته

فهرست دقیق مسیرها در `PATCH_CONTENTS.txt` است. این بسته فقط فایل‌های تغییرکرده و مستندات مرتبط را دارد و کپی کامل پروژه نیست.

## نحوهٔ اعمال

1. ZIP را باز کن.
2. محتویات آن را روی ریشهٔ مخزن GitHub در شاخهٔ `Amitar` کپی کن و فایل‌های هم‌مسیر را جایگزین کن.
3. به‌ویژه فایل `lib/AmitarGalleryPlayer.dart` را حتماً جایگزین کن؛ این فایل تغییر اصلی لازم برای رفع ۱۳ خطای API است.
4. پوشه‌های `assets/` و `presentation/` را حذف یا جایگزین نکن. این دو پوشه در ZIP ورودی کوچک‌شده وجود نداشتند و در این بسته نیز نیازی به تغییر ندارند.
5. `SHA256SUMS.txt` را دستی اصلاح نکن؛ Workflow آن را روی Runner از روی فایل‌های ثبت‌شده در Git بازتولید می‌کند.
6. همهٔ تغییرات را در یک Commit روی شاخهٔ اصلاحی یا `Amitar` ثبت کن و GitHub Actions را اجرا کن.

برای ثبت خودکار تغییرات Formatter، در GitHub مسیر `Settings → Actions → General → Workflow permissions` باید اجازهٔ `Read and write permissions` برای Contents را بدهد و قواعد محافظت شاخه نباید Commit مجاز `github-actions[bot]` را مسدود کنند. این مجوز فقط در Job ثبت Formatter درخواست می‌شود.

## محدودهٔ اعتبارسنجی

- ۱۸ تست Bootstrap، ۲۴ تست Project Invariants و ۳ تست Release Version در محیط محلی این بسته موفق شده‌اند (۴۵ تست منتخب).
- `python3 -m compileall -q tool` موفق است.
- YAML فایل Workflow با PyYAML تجزیه شده است.
- بررسی منبع نشان می‌دهد هیچ فراخوانی `XFile.fileSystem` یا `XFile.scopedStorage` و هیچ import مستقیم `cross_file` در فایل اصلی باقی نمانده است.
- در آخرین CI واقعی، ۶۲ تست Python، حل وابستگی‌ها و تولید آیکون‌ها موفق بوده‌اند؛ شکست فقط در Static Analysis ثبت شده است.
- Flutter/Dart SDK در محیط ساخت این بسته موجود نبوده است؛ بنابراین پس از اعمال فایل‌ها، `flutter analyze`، `flutter test` و Buildهای Android/Windows/Linux/macOS/iOS/Web باید روی GitHub Actions تأیید شوند. موفقیت آن‌ها از پیش ادعا نمی‌شود.

گزارش جزئیات در `VALIDATION_REPORT.md` قرار دارد.
