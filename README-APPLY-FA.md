# اعمال اصلاح نهایی خطاهای GitHub Actions

این بسته فقط اصلاحات لازم برای دو خطای گزارش‌شده در اجرای `0944e6d4afd252e9f1e937a435850ce48410f5ff` را دارد؛ سورس کامل برنامه داخل آن نیست.

## خطاهای رفع‌شده

1. `android/local.properties` هنوز در Git index ثبت شده بود، با اینکه در `.gitignore` قرار دارد. اسکریپت `APPLY-CI-FIX.ps1` آن را فقط از index حذف می‌کند و فایل محلی را روی رایانه نگه می‌دارد.
2. پس از Bootstrap، محتوای `.metadata` با نسخهٔ ثبت‌شده در `SHA256SUMS.txt` تفاوت پیدا می‌کرد. کد Bootstrap اکنون از ابتدا تا انتهای عملیات، Snapshot متادیتا را حفظ و در پایان حتی در صورت شکست بازیابی می‌کند. Workflow نیز بعد از Bootstrap فایل را از `HEAD` برمی‌گرداند.

## روش اعمال

1. ZIP را در ریشهٔ مخزن محلی `Amitar-Gallery-Player` استخراج کن و اجازه بده مسیرهای فایل‌های موجود جایگزین شوند.
2. PowerShell را در ریشهٔ مخزن باز کن و اجرا کن:

```powershell
powershell -ExecutionPolicy Bypass -File .\APPLY-CI-FIX.ps1
```

3. اسکریپت حذف `android/local.properties` از Git index را Stage می‌کند، اما فایل محلی را حذف نمی‌کند. همچنین SHA256SUMS را با فایل‌های tracked جدید بازسازی و فایل‌های اصلاح‌شده را Stage می‌کند.
4. تغییرات را بررسی کن:

```powershell
git diff --cached --stat
git status --short
```

5. وابستگی‌های تست را نصب و تست‌ها را اجرا کن:

```powershell
python -m pip install -r tool/requirements-branding.txt
python -m py_compile tool/*.py
python -m unittest discover -s tool -p "test_*.py" -v
python tool/check_release_version.py --tag v1.0.0
git diff --check
```

6. اگر تست‌ها موفق بودند، Commit و Push کن:

```powershell
git commit -m "Fix CI metadata restoration and untrack local Android SDK settings"
git push origin Amitar
```

## نکات ایمنی تغییرات

- `android/local.properties` با `git rm --cached` از مخزن خارج می‌شود؛ فایل محلی پاک نمی‌شود.
- آزمون `test_no_personal_android_sdk_path_is_committed` حذف یا تضعیف نشده است؛ همچنان وجود فایل در Git index را رد می‌کند.
- `.metadata` از آزمون Manifest حذف نشده است؛ نسخهٔ ردیابی‌شده حفظ می‌شود.
- فایل `dependabot.yml`، وابستگی‌های Flutter، کد Dart و نسخهٔ برنامه تغییر داده نشده‌اند.

اعتبارسنجی محلی این بسته شامل 62 آزمون Python، Compile پایتون، بررسی نسخه Release، بررسی ساختار YAML و کنترل SHA-256 است. اجرای واقعی Runnerهای GitHub و کامپایل بومی پلتفرم‌ها فقط پس از Push قابل تأیید است.
