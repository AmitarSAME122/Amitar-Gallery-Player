# راهنمای اعمال اصلاح واقعی خطای flutter analyze

این بسته برای اصلاح خطایی است که در خروجی `flutter analyze` با پیام‌های زیر دیده می‌شود:

- `XFile.fileSystem` تعریف نشده است.
- `XFile.scopedStorage` تعریف نشده است.
- وابستگی `cross_file` به‌اشتباه مستقیم شده است.
- callback قدیمی `onReorder` استفاده شده است.

## نکتهٔ بسیار مهم دربارهٔ لاگ فعلی

اگر پس از اعمال این بسته هنوز همان خطاها و همان مسیر `lib/AmitarGalleryPlayer.dart` را می‌بینید، اجرای GitHub Actions هنوز از نسخهٔ قدیمی فایل استفاده می‌کند. در نسخهٔ اصلاح‌شده:

- تعداد `XFile.fileSystem` برابر صفر است.
- تعداد `XFile.scopedStorage` برابر صفر است.
- import از `package:cross_file/cross_file.dart` وجود ندارد.
- `cross_file` وابستگی مستقیم `pubspec.yaml` نیست و فقط به‌صورت transitive در lockfile باقی می‌ماند.
- صف پخش از `onReorderItem` استفاده می‌کند.

## روش اعمال از GitHub Web

1. ZIP را روی رایانه باز کنید.
2. محتویات داخل ZIP را انتخاب کنید؛ پوشه‌های `.github` و `android` و `lib` و `tool` به‌همراه `pubspec.yaml` و `pubspec.lock` باید مستقیماً در ریشهٔ مخزن قرار بگیرند.
3. پوشهٔ والد ZIP را به‌عنوان یک پوشهٔ جدید به مخزن اضافه نکنید. ساختار باید دقیقاً این‌گونه باشد:
   - `.github/workflows/build.yml`
   - `android/app/src/main/kotlin/com/amitar/amitar_gallery_player/MainActivity.kt`
   - `lib/AmitarGalleryPlayer.dart`
   - `pubspec.yaml`
   - `pubspec.lock`
   - `tool/...`
4. فایل‌های هم‌مسیر را در شاخهٔ `Amitar` جایگزین و Commit کنید.
5. پوشه‌های `assets/` و `presentation/` را حذف یا جایگزین نکنید؛ این بسته شامل آن‌ها نیست.
6. `SHA256SUMS.txt` را دستی ویرایش نکنید؛ Workflow آن را روی Runner از روی فایل‌های tracked بازتولید می‌کند.

## محافظت اضافه‌شده در CI

Workflow ابتدا تست‌های Python پروژه را اجرا می‌کند. تست‌های invariant صراحتاً وجود APIهای قدیمی `XFile`، وابستگی مستقیم `cross_file` و callback قدیمی `onReorder` را بررسی می‌کنند. اگر فایل قدیمی باقی مانده باشد، CI قبل از `flutter analyze` با تست مشخص و پیام قابل تشخیص متوقف می‌شود؛ دیگر لازم نیست منتظر خطاهای پراکندهٔ Analyzer بمانید.

## آنچه در این محیط اعتبارسنجی شده

- بستهٔ جایگزینی از سورس پروژهٔ ارسالی ساخته شده است.
- فایل اصلاح‌شده هیچ‌یک از APIهای قدیمی `XFile` را ندارد.
- `pubspec.yaml` وابستگی مستقیم `cross_file` ندارد.
- ۴۶ تست Python مربوط به Bootstrap، invariantها و نسخهٔ Release در مخزن ادغام‌شده موفق شده‌اند.
- `SHA256SUMS.txt` در محیط آزمایش پس از overlay دوباره تولید شده است.
- اجرای واقعی Flutter/Dart analyze و Build پلتفرم‌ها در این محیط انجام نشده است؛ این کار را GitHub Actions انجام می‌دهد.
