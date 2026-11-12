# اصلاح نهایی خطای SHA-256 فایل `.metadata`

این Overlay برای اجرای GitHub Actions روی Commit `50bae0680ca5af4c2be73ca17f89ff48be45de81` تهیه شده است.

## تشخیص از لاگ واقعی

در اجرای ۱۲ نوامبر ۲۰۲۶، مرحلهٔ Bootstrap موفق بود و مرحلهٔ بازیابی نیز این فرمان‌ها را با موفقیت اجرا کرد:

```bash
git restore --source=HEAD --worktree -- .metadata pubspec.lock
git diff --exit-code HEAD -- .metadata pubspec.lock
```

از ۶۲ آزمون، ۶۱ آزمون موفق شدند. تنها شکست مربوط به هش خام `.metadata` بود:

- هش ثبت‌شده در Manifest: `7fbca2118bd3965d61738354f55dca16d8345fccec52c7c7ea05ed6ab85b85c7`
- هش بایت‌های canonical در Runner لینوکس: `b3c648d6da9cedbf59041b4127924a6a52708296a3d0c9f6c16533098b8c1c84`

علت: تولیدکنندهٔ Manifest و آزمون، سیاست یکسانی برای پایان‌خط فایل بدون پسوند `.metadata` نداشتند. Git می‌تواند CRLF و LF را از نظر diff معادل بداند، درحالی‌که SHA-256 روی بایت خام متفاوت است.

## فایل‌های اصلاح‌شده

- `tool/update_source_checksums.py`: همهٔ فایل‌های متنی، از جمله `.metadata` و `pubspec.lock`، پیش از هش به LF canonical تبدیل می‌شوند. فایل‌های باینری بدون تغییر هش می‌شوند. فایل‌های محلی Android و Wrapper همچنان از Manifest حذف‌اند.
- `tool/test_project_invariants.py`: آزمون رگرسیون مشخص برای `.metadata`، `pubspec.lock` و فایل باینری اضافه شده و آزمون Manifest از همان تابع canonicalization استفاده می‌کند.
- `APPLY-CHECKSUM-FIX.ps1`: Manifest را در مخزن محلی بازتولید می‌کند، آزمون‌ها و هویت نسخه را اجرا می‌کند و فقط پس از موفقیت، سه فایل تغییرکرده را Stage می‌کند.

## روش اعمال

1. ZIP را در ریشهٔ مخزن `Amitar-Gallery-Player` استخراج کن؛ مسیرهای `tool/` باید با مسیرهای موجود ادغام شوند.
2. PowerShell را در ریشهٔ مخزن باز کن و اجرا کن:

```powershell
powershell -ExecutionPolicy Bypass -File .\APPLY-CHECKSUM-FIX.ps1
```

3. اسکریپت ابتدا `SHA256SUMS.txt` را از فایل‌های tracked بازتولید می‌کند. سپس Python compile، کل آزمون‌های پروژه و کنترل نسخه را اجرا می‌کند. در صورت شکست، چیزی را Stage نمی‌کند.
4. اگر اسکریپت با موفقیت تمام شد:

```powershell
git diff --cached --stat
git status --short
git commit -m "Fix cross-platform source checksum normalization"
git push origin Amitar
```

`SHA256SUMS.txt` داخل ZIP قرار نگرفته است، چون باید از تمام ۱۱۶ فایل واقعی مخزن خودت بازتولید شود؛ اسکریپت آن را با نسخهٔ صحیح جایگزین می‌کند. هیچ فایل برنامه، `pubspec.yaml`، Workflow، Gradle یا تنظیم Dependabot در این اصلاح تغییر نمی‌کند.

## محدودهٔ اعتبارسنجی

این Overlay را در یک مخزن Git آزمایشی با فایل‌های CRLF/LF و فایل باینری جداگانه آزمایش می‌کنیم. اجرای کامل ۶۲ آزمون روی سورس خصوصی/فعلی GitHub فقط پس از اعمال Overlay روی همان Commit و اجرای GitHub Actions قابل تأیید است.

## بازبینی ساختار مخزن در Commit بررسی‌شده

بر اساس Manifest رسمی سورس در همان اجرای CI، ۱۱۶ مسیر Track‌شده در این گروه‌ها ثبت شده‌اند:

| بخش | تعداد فایل |
|---|---:|
| فایل‌های ریشه و مستندات | ۲۱ |
| `.github` | ۵ |
| `.vscode` | ۲ |
| `android` | ۲۲ |
| `assets` | ۲۰ |
| `presentation` | ۶ |
| `tool` | ۲۰ |
| `windows` | ۱۸ |
| `lib` | ۱ |
| `test` | ۱ |

Workflow پنج Job دارد: `quality`، `linux-android-web`، `windows`، `apple` و `publish-github-release`. در لاگ آخر، Bootstrap پلتفرم‌ها، کنترل Gradle Wrapper، بازگردانی `.metadata` و `pubspec.lock`، نصب وابستگی‌های تست و کنترل نسخه موفق بودند. فقط آزمون تطبیق Manifest برای `.metadata` شکست داشت.

پوشه‌های میزبان iOS، Linux، macOS و Web در Manifest منبع ثبت نشده‌اند؛ Workflow آن‌ها را با Flutter Bootstrap در Runner مربوطه تولید می‌کند و سپس سفارشی‌سازی‌های پروژه را اعمال می‌کند. بنابراین این Overlay عمداً آن پوشه‌ها یا Workflow را بازنویسی نمی‌کند.

**دامنهٔ دسترسی:** این بازبینی بر پایهٔ لاگ بارگذاری‌شده، Manifest ۱۱۶ فایلی و Snapshot فایل‌های Workflow و تست‌های همان Commit انجام شده است. دسترسی زنده و کامل به تمام فایل‌های GitHub از این نشست برقرار نبود؛ بنابراین ادعای ممیزی بایت‌به‌بایت کل مخزن زنده مطرح نمی‌شود.
