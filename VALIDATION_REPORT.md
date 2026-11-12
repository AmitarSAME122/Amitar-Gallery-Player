# گزارش اعتبارسنجی بستهٔ اصلاح کد اصلی

## ورودی

- Repository: `AmitarSAME122/Amitar-Gallery-Player`
- Branch: `Amitar`
- Commit دیده‌شده در آخرین Log: `b79c7067d3db287df8dc5a04d2b46f9fd5dcdbd9`
- Failed step: `flutter analyze`

## خطای واقعی

آخرین Log هنوز ۱۱ فراخوانی `XFile.fileSystem` و ۲ فراخوانی `XFile.scopedStorage` دارد؛ به‌علاوهٔ سه مورد informational مربوط به `file_names`، `unnecessary_import` و `deprecated_member_use`. `dart fix --apply` تعداد ۱۳۳ quick fix اعمال کرده، اما APIهای ناموجود را تبدیل نمی‌کند. همچنین همان مرحله به علت import مستقیم `cross_file` آن را در `pubspec.yaml` مستقیم کرده است.

## تغییر کد

- تمام importها و فراخوانی‌های XFile از فایل اصلی حذف شدند.
- مسیرهای فایل عادی به `universal_io.File` منتقل شدند.
- URIهای قدیمی Android از MethodChannel/ContentResolver عبور می‌کنند.
- مسیر پخش URI ذخیره‌شده پس از راه‌اندازی مجدد اصلاح شد تا به `readBytes` موقت وابسته نباشد.
- قید مستقیم cross_file از `pubspec.yaml` حذف شد و Lockfile آن را transitive ثبت می‌کند.
- صف پخش از API جدید `onReorderItem` استفاده می‌کند.

## آزمون‌های اجراشده

| آزمون | نتیجه |
|---|---:|
| Bootstrap | ۱۸/۱۸ موفق |
| Project invariants | ۲۵/۲۵ موفق |
| Release version | ۳/۳ موفق |
| کل تست‌های منتخب | ۴۶/۴۶ موفق |
| Python compileall | موفق |
| Workflow YAML parse | موفق |
| نبود import و APIهای XFile در Dart | موفق |
| ZIP integrity | موفق |

برای اجرای تست‌های وابسته به Git Manifest، سورس در یک مخزن Git آزمایشی قرار گرفت، bit اجرایی `android/gradlew` که ZIP حمل نمی‌کند بازیابی شد و Manifest از روی checkout آزمایشی تولید شد.

## محدودیت‌ها

ZIP سورس کاربر عمداً پوشه‌های `assets/` و `presentation/` را حذف کرده است. بنابراین تست‌های بصری/برندینگ وابسته به آن فایل‌ها در این محیط قابل اجرا نیستند و این گزارش آن‌ها را موفق اعلام نمی‌کند.

Flutter/Dart SDK در محیط آماده‌سازی حاضر نبود. بنابراین اجرای واقعی `flutter pub get`، `dart fix`، `dart format`، `flutter analyze`، `flutter test`، Gradle و Buildهای Android، Web، Linux، Windows، macOS و iOS از این محیط ممکن نشد. آخرین CI واقعی ۶۲ تست Python و `flutter pub get` را موفق نشان داده، اما Analyzer را شکست داده است. اجرای CI پس از جایگزینی کد اصلی هنوز لازم است.
