# بسته اصلاح خطای Dart Formatter در AmitarGalleryPlayer

## تشخیص از آخرین اجرای GitHub Actions

- شاخه: `Amitar`
- Commit اجرا: `f146ad34fde783d5bcbfd4a626cffffde9aa9ed9`
- مرحله `flutter pub get`: موفق؛ حل وابستگی‌ها پایان یافته و `Got dependencies!` ثبت شده است.
- مرحله تولید آیکون‌ها: موفق؛ آیکون‌های پلتفرم‌ها ساخته شده‌اند.
- تنها مرحله شکست‌خورده در این لاگ: `dart format --output=none --set-exit-if-changed lib test` با Exit Code 1.
- سه فایل گزارش‌شده توسط Formatter: `lib/AmitarGalleryPlayer.dart`، `lib/assets.dart` و `test/model_serialization_test.dart`.

## تغییرات این بسته

1. Workflow ابتدا `dart format lib test` را اجرا می‌کند و سپس با همان Flutter/Dart نصب‌شده در GitHub Runner، قالب‌بندی را به‌صورت غیرتغییردهنده تأیید می‌کند.
2. اگر اجرای Workflow روی یک Branch باشد و فایل‌های Dart ردیابی‌شده تغییر کرده باشند، فقط همان فایل‌های Dart در یک Git worktree تمیز از آخرین سرشاخه اعمال می‌شوند؛ فایل‌های تولیدی Android/iOS/Desktop یا خروجی‌های ساخت وارد Commit نمی‌شوند.
3. اسکریپت موجود `tool/update_source_checksums.py` در همان worktree اجرا می‌شود تا `SHA256SUMS.txt` با نسخه قالب‌بندی‌شده هماهنگ شود. سپس فایل‌های Dart و Manifest در یک Commit رباتی ثبت و به همان Branch Push می‌شوند.
4. اجازه `contents: write` فقط به Job مستقل `persist-dart-format` داده شده است؛ Job کیفیت، تست‌ها و تمام Jobهای ساخت همچنان مجوز خواندن دارند. فایل‌های قالب‌بندی‌شده ابتدا به‌صورت Artifact یک‌روزه از Job کیفیت منتقل می‌شوند تا Job دارای مجوز نوشتن هیچ کد پروژه‌ای را اجرا نکند.
5. پیش از اعمال تغییرات خودکار، Workflow بررسی می‌کند که فایل‌های Dart در Branch از زمان شروع Run تغییر مستقل نکرده باشند. در صورت تغییر هم‌زمان، از بازنویسی آن تغییر جلوگیری و خطای واضح ثبت می‌شود.
6. در رویداد `pull_request` هیچ Push خودکاری انجام نمی‌شود. در رویداد `push` یا `workflow_dispatch` روی Branch، اصلاحات در همان Branch ثبت می‌شوند.

## فایل‌هایی که باید جایگزین شوند

- `.github/workflows/build.yml`
- `tool/test_project_invariants.py`

فایل کامل پروژه در این بسته نیست. محتویات `assets/` و `presentation/` دست‌نخورده می‌مانند و نیازی به بارگذاری مجدد آن‌ها نیست.

## تنظیم مجوز GitHub

در `Settings → Actions → General → Workflow permissions` مطمئن شو Workflowها اجازه نوشتن در Contents را دارند و سیاست سازمانی/مخزن آن را مسدود نکرده است. همچنین اگر Branch protection به Commit مستقیم اجازه نمی‌دهد، باید طبق سیاست خود مخزن دسترسی ربات GitHub Actions را مجاز کنی یا روش تأیید مبتنی بر Pull Request را به‌کار ببری. این Workflow هیچ قانون محافظت شاخه‌ای را دور نمی‌زند.

Commit ربات با `GITHUB_TOKEN` به‌تنهایی Workflow دیگری را به‌صورت خودکار اجرا نمی‌کند؛ به همین دلیل Manifest در همان Commit به‌روزرسانی می‌شود و حلقه تکرار CI ایجاد نمی‌شود. مطابق رفتار مستند GitHub، رویدادهای ناشی از `GITHUB_TOKEN` (به‌جز `workflow_dispatch` و `repository_dispatch`) Workflow جدید ایجاد نمی‌کنند.

## اعتبارسنجی انجام‌شده

- YAML فایل Workflow با PyYAML BaseLoader تجزیه شد.
- تست رگرسیون جدید برای ترتیب Formatter، محدودیت مجوز و مسیر Commit موفق شد.
- منطق Git worktree در یک مخزن آزمایشی واقعی با Remote شبیه‌سازی شد؛ تغییر هم‌زمان Manifest، انتقال فایل‌های Dart، Commit و Push و تطبیق SHA-256 Manifest با موفقیت بررسی شدند.

این محیط Dart/Flutter SDK ندارد؛ بنابراین خود `dart format` در این محیط اجرا نشده است. اجرای واقعی Formatter، `flutter analyze`، تست‌های Flutter و Build پلتفرم‌ها در GitHub Actions بعد از اعمال این دو فایل انجام می‌شود. لاگ فعلی قبل از رسیدن به `flutter analyze` و `flutter test` متوقف شده است؛ پس درباره موفقیت آن مراحل ادعایی نمی‌شود.
