# بستهٔ نهایی اصلاح هماهنگی سورس و GitHub Actions — AmitarGalleryPlayer

این بسته بر اساس دو ورودی همین نوبت ساخته شده است: لاگ آخرین اجرای `Analyze and regression tests` و آرشیو سورس شاخهٔ `Amitar` که پوشه‌های `assets/` و `presentation/` آن عمداً برای کاهش حجم حذف شده بودند.

## ریشهٔ مشکل

آخرین لاگ روی Commit `9464e29caf77cc3990ad3917cba066e5700eebea` اجرا شده و `flutter analyze` هنوز ۱۳ فراخوانی ناسازگار `XFile.fileSystem` و `XFile.scopedStorage` را در کد Checkout‌شده گزارش کرده بود. در همان اجرا، `dart fix --apply` نیز یک وابستگی `cross_file` را از transitive به direct تغییر داده بود. این رفتار با کد اصلاح‌شدهٔ موجود در سورس ZIP هم‌خوان نبود.

مشکل دوم در طراحی CI بود: Job کیفیت می‌توانست فایل‌های Dart را قالب‌بندی/اصلاح کند، ولی Jobهای Linux/Android/Web، Windows و Apple از Checkout اولیه می‌ساختند. بنابراین کدی که Analyze و Test شده بود لزوماً همان کدی نبود که برای ساخت native استفاده می‌شد. Lockfile نیز جداگانه منتقل می‌شد و نسخهٔ Pubspec و Source به شکل یک Snapshot واحد تضمین نمی‌شد.

## تغییرات این بسته

1. کد اصلی `lib/AmitarGalleryPlayer.dart`، فایل‌های وابستگی `pubspec.yaml` و `pubspec.lock`، و `MainActivity.kt` در بسته گنجانده شده‌اند تا جایگزینی مسیر اصلی و نسخهٔ اصلاح‌شده مبهم نباشد.
2. `dart fix --apply` از CI حذف شده است. این فرمان تغییرات خودکار و ناخواسته‌ای در `pubspec.yaml` ایجاد کرده بود؛ به‌جای آن، `validate_source_contracts.py` بعد از `flutter pub get` قرارداد API و وابستگی را کنترل می‌کند.
3. قالب‌بندی Dart روی شاخه‌ها انجام و نتیجهٔ بدون تغییر دوباره بررسی می‌شود. برای Tagها CI فقط قالب‌بندی موجود را بررسی می‌کند و سورس Tag را در زمان انتشار تغییر نمی‌دهد.
4. `collect_ci_snapshot.py` فایل‌های Dart و تنظیمات مجاز تغییرکرده را در Artifact محدودشده جمع‌آوری می‌کند. Lockfile به‌صورت Artifact جداگانه و پس از عبور Quality منتشر می‌شود.
5. هر سه خانوادهٔ Native، همان Source Snapshot و همان Lockfile را پس از Bootstrap دریافت و اعمال می‌کنند؛ سپس `flutter pub get --enforce-lockfile` اجرا می‌شود. بنابراین تفاوت کد تحلیل‌شده و کد ساخته‌شده حذف می‌شود.
6. `persist-quality-source-snapshot` فقط پس از موفقیت Quality و هر سه Job ساخت اجرا می‌شود. این Job سورس، Lockfile و `SHA256SUMS.txt` را روی آخرین Commit شاخه ثبت می‌کند و در صورت تغییر هم‌زمان یکی از فایل‌های محافظت‌شده، به‌جای بازنویسی آن، شکست ایمن می‌دهد.
7. Workflow مستقل بازسازی Manifest از Push خودکار خارج و فقط دستی شده است تا با Commit هم‌زمان Job ساخت رقابت نکند.
8. Bootstrap بیت اجرایی `android/gradlew` را روی Runnerهای Unix بازیابی می‌کند؛ آرشیوهای ZIP گاهی مجوز 100755 را از دست می‌دهند.
9. برای Snapshot helperها تست مسیرهای مجاز، فایل‌های تازه، Lockfile، traversal و symbolic link اضافه شده است.

## فایل‌های اصلی که جایگزین می‌شوند

- `.github/workflows/build.yml`
- `.github/workflows/refresh-source-manifest.yml`
- `lib/AmitarGalleryPlayer.dart`
- `pubspec.yaml`
- `pubspec.lock`
- `android/app/src/main/kotlin/com/amitar/amitar_gallery_player/MainActivity.kt`
- `tool/bootstrap_platforms.py`
- `tool/test_bootstrap_platforms.py`
- `tool/test_project_invariants.py`

## فایل‌های جدید

- `tool/collect_ci_snapshot.py`
- `tool/apply_ci_snapshot.py`
- `tool/validate_source_contracts.py`
- `tool/test_ci_snapshot.py`

## روش اعمال

1. ZIP را استخراج کن.
2. **محتویات داخل ZIP را مستقیماً در ریشهٔ مخزن GitHub** قرار بده؛ پوشهٔ والد ZIP را به‌عنوان زیرپوشهٔ جدید اضافه نکن.
3. در پنجرهٔ GitHub مطمئن شو مسیر فایل‌ها دقیقاً مثل فهرست بالا است.
4. پوشه‌های اصلی `assets/` و `presentation/` در مخزن را نگه دار. این دو پوشه عمداً در آرشیو ورودی و بستهٔ اصلاحی نیستند؛ فایل‌ها و تصاویر اصلی آن‌ها را حذف یا جایگزین نکن.
5. `SHA256SUMS.txt` را از بسته کپی نکن؛ Workflow پس از موفقیت همهٔ ساخت‌ها، Manifest را از Git index کامل شاخه بازتولید می‌کند.
6. تغییرات را در یک Commit روی شاخهٔ `Amitar` ثبت کن.

## تنظیم لازم GitHub

برای Commit خودکار پس از موفقیت همهٔ Buildها:

`Settings → Actions → General → Workflow permissions → Read and write permissions`

باید فعال باشد. قوانین محافظت شاخه نیز باید اجازهٔ نوشتن `github-actions[bot]` را بدهند؛ در غیر این صورت Job ذخیرهٔ Snapshot عمداً fail می‌شود و فایل‌های هم‌زمان را دور نمی‌زند.

## اعتبارسنجی این بسته

در محیط آماده‌سازی:

- Python compile برای اسکریپت‌ها موفق است.
- تست‌های Bootstrap: 19 مورد موفق.
- تست‌های Project Invariants و Snapshot: 33 مورد، 31 موفق و 2 مورد Skip‌شده به علت نبود Git index واقعی در ZIP/نبود منبع کامل Manifest.
- تست اضافه‌شدهٔ Snapshot از path traversal و symbolic link جلوگیری می‌کند.
- قرارداد کد اصلی، `cross_file` و Content URI با موفقیت بررسی شد.
- Workflowها با YAML BaseLoader تجزیه می‌شوند.

این محیط Flutter/Dart SDK ندارد؛ بنابراین `flutter analyze`، `flutter test` و Buildهای Android, Web, Linux, Windows, macOS و iOS هنوز در اینجا اجرا نشده‌اند. نتیجهٔ نهایی این مراحل فقط با Run جدید GitHub Actions مشخص می‌شود.
