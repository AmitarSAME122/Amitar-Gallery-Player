# گزارش اصلاحات تکمیلی AmitarGalleryPlayer

## مبنای بازبینی

این اصلاحات روی آخرین بستهٔ کامل پروژه (`AmitarGalleryPlayer_Windows_Fixed.zip`) انجام شده‌اند. فایل‌های اصلی، رابط کاربری، تصاویر برند، پوسترها، ساختار تک‌فایل Dart، تنظیمات Android و سایر قابلیت‌های موجود حفظ شده‌اند.

## خطاهای مشاهده‌شده در Windows و اصلاحات

### ۱) `FileNotFoundError: [WinError 2]` هنگام اجرای `flutter create`

علت: اسکریپت Python فرمان خام `flutter` را مستقیماً به `CreateProcess` می‌داد. در برخی نصب‌های PowerShell، Flutter از طریق profile/alias یا مسیری که به PATH پردازش فرزند منتقل نشده در دسترس است؛ Python نمی‌تواند alias یا function شل را اجرا کند.

اصلاح:
- resolver مشترک `tool/flutter_command.py` اضافه شد.
- جست‌وجو در PATH، `FLUTTER_ROOT`، PowerShell application discovery و مسیرهای متداول Windows انجام می‌شود.
- در Windows، resolver در صورت آماده‌بودن SDK مستقیماً `dart.exe` داخلی Flutter و `flutter_tools.snapshot` را اجرا می‌کند؛ در نتیجه به quoting شکنندهٔ `cmd.exe` وابسته نیست و مسیرهای دارای فاصله نیز به‌صورت آرگومان مستقل منتقل می‌شوند.
- فقط اگر cache داخلی Dart هنوز آماده نباشد، مسیر batch از fallback دارای nested quoting استفاده می‌کند.
- `bootstrap_platforms.py`، `build.py` و ابزار VS Code از resolver مشترک استفاده می‌کنند.
- پیام خطا اکنون روش دقیق اصلاح PATH/FLUTTER_ROOT را توضیح می‌دهد.

### ۲) شکست `flutter test` به‌دلیل نبود Visual Studio و CBuilder

علت: `hive_ce_flutter` نسخهٔ قفل‌شده، native build hook داشت و اجرای تست روی Windows را به کامپایلر MSVC وابسته می‌کرد؛ این وابستگی برای استفادهٔ پروژه از `Hive.initFlutter()` لازم نبود.

اصلاح:
- وابستگی مستقیم `hive_ce_flutter` حذف شد.
- برنامه از هستهٔ خالص Dart یعنی `hive_ce` استفاده می‌کند.
- مسیر ذخیره‌سازی Native از `path_provider` و application-support directory گرفته می‌شود.
- مسیر Web جداگانه مقداردهی می‌شود و به filesystem محلی وابسته نیست.
- رکورد مستقیم `hive_ce_flutter` از lockfile حذف شد؛ اجرای `flutter pub get` گراف قفل‌شده را با Pub SDK نصب‌شده دوباره حل و پاک‌سازی می‌کند.

نتیجهٔ مورد انتظار: تست‌های VM/Widget دیگر نباید به خاطر hook پکیج `hive_ce_flutter` به Visual Studio نیاز داشته باشند. اگر پکیج دیگری native build hook مستقل داشته باشد، خطای آن جداگانه باید بررسی شود.

### ۳) نبود منابع آیکون iOS

علت: منابع asset catalog در زمان تولید hostهای Flutter و اجرای `flutter_launcher_icons` ساخته می‌شوند. اجرای validator پیش از این مراحل، طبیعتاً `Contents.json` را پیدا نمی‌کرد.

اصلاح:
- ترتیب صحیح آماده‌سازی در README و Build Guide مشخص شد: ابتدا bootstrap و ساخت hostهای iOS/macOS، سپس `flutter pub get` و تولید آیکون‌ها.
- ابزار جدید `tool/generate_platform_icons.py` وجود پوشه‌های واقعی Asset Catalog را پیش‌بررسی می‌کند و در صورت نبود host به‌جای ایجاد خروجی نیمه‌کاره، دستور bootstrap را اعلام می‌کند.
- پس از اجرای `flutter_launcher_icons`، ابزار ارجاع‌های Android adaptive icon را به `@color/ic_launcher_background` و لایه‌های واقعی foreground/monochrome اصلاح و استاندارد می‌کند.
- validator عمداً read-only باقی مانده و فایل‌ها را بی‌صدا تولید یا تغییر نمی‌دهد.

### ۴) Visual Studio برای کدام هدف لازم است؟

- Android: خیر؛ JDK، Android SDK و Gradle Wrapper پروژه لازم‌اند.
- Web: خیر؛ Flutter و مرورگر/ابزارهای وب لازم‌اند.
- Flutter VM/Widget tests: پس از حذف hook غیرضروری Hive، نباید به MSVC نیاز داشته باشند.
- Windows Desktop: بله؛ Visual Studio 2022 یا جدیدتر / Build Tools با workload «Desktop development with C++»، ابزارهای MSVC x64/x86، Windows SDK، CMake و Ninja لازم‌اند.

اکنون `tool/build.py windows` پیش‌بررسی واضح دارد. فرمان `tool/build.py all` در Windows در صورت نبود MSVC هدف Windows را با پیام توضیحی رد می‌کند و می‌تواند Android و Web را ادامه دهد.

## پشتیبانی VS Code

- حذف مسیر مطلق CMake متعلق به رایانهٔ توسعه‌دهنده از `.vscode/settings.json`.
- تنظیمات قابل‌حمل Editor و جست‌وجو.
- `tasks.json` برای bootstrap، Pub get، تولید/اعتبارسنجی آیکون، Analyze، Test و Build.
- `launch.json` با انتخاب دستگاه، Windows و Chrome؛ شناسهٔ Emulator ثابت و وابسته به دستگاه حذف شد.
- `extensions.json` برای پیشنهاد افزونه‌های Dart، Flutter، Python و CMake.
- `tool/run_sdk.py` برای اجرای Dart/Flutter با resolver مشترک.
- وظیفهٔ Generate icons اکنون از wrapper یکسان `tool/generate_platform_icons.py` استفاده می‌کند.

## README و هویت پروژه

ترتیب ابتدای README به این شکل تنظیم شد:

1. لوگوی اصلی AmitarGalleryPlayer
2. پوستر دوزبانهٔ پیش‌نمایش شمارهٔ ۱
3. پوستر دوزبانهٔ پیش‌نمایش شمارهٔ ۲
4. اطلاعات کلی پروژه و سازنده

اطلاعات سازنده به‌صورت نام انگلیسی و فارسی ثبت شده است: **Seyed Amir Mohammad Emami — سید امیر محمد امامی**. هیچ ایمیل، وب‌سایت یا شناسهٔ اجتماعی حدس زده نشده است.

## اعتبارسنجی انجام‌شده در محیط بازبینی

- ۱۰۱ مورد Python کشف و اجرا شدند؛ ۹۸ مورد موفق و ۳ مورد وابسته به محیط skip شدند.
- ۳ تست وابسته به Windows واقعی یا Git index در این میزبان skip شدند.
- JSON تنظیمات VS Code parse شد.
- XMLهای موجود Android/Windows parse شدند.
- لینک فایل‌های لوگو و دو پوستر README بررسی شدند.
- قراردادهای Dart، `pubspec.yaml`، lockfile، File Picker و کانال Android Content URI بررسی شدند.
- manifest هش برای حالت آرشیو بدون `.git` بازتولید و آزمون شد.
- بیت اجرایی `android/gradlew` در بسته حفظ شد.

## اصلاحات تکمیلی بر اساس خروجی PowerShell

- اجرای Flutter در Windows در حالت عادی از `dart.exe` داخلی و `flutter_tools.snapshot` استفاده می‌کند؛ در fallback نیز nested quoting برای `cmd.exe` اصلاح شده است.
- کلید غیرمعتبر `flutter.main` در `pubspec.yaml` نباید استفاده شود. نقطهٔ ورود سفارشی `lib/AmitarGalleryPlayer.dart` از طریق `--target` در فرمان build انتخاب می‌شود.
- تولید آیکون به `tool/generate_platform_icons.py` منتقل شده است. این ابزار پیش از اجرا وجود hostهای Android/iOS/macOS/Web/Windows/Linux را کنترل می‌کند و بعد از اجرای `flutter_launcher_icons` ارجاع‌های foreground/background/monochrome آیکون تطبیقی Android را به منابع واقعی پروژه همسان می‌کند.
- به‌روزرسانی `SHA256SUMS.txt` پس از تولید آیکون‌ها انجام می‌شود تا فایل XML و تصاویر تولیدشده خارج از manifest نمانند.
- آزمون bit اجرایی Gradle wrapper روی Windows به‌درستی skip می‌شود؛ فایل‌سیستم Windows بیت POSIX را مانند Unix حفظ نمی‌کند. آزمون alias نیز متغیر `LOCALAPPDATA` میزبان را از fixture جدا می‌کند.
- اگر Pillow در Python 3.14 نصب‌شده باشد اما افزونهٔ native آن import نشود، تست‌های اختیاری برندینگ با پیام نصب مجدد dependency skip می‌شوند؛ سایر تست‌های پروژه اجرا می‌مانند. برای تولید پوستر/آیکون همچنان باید `tool/requirements-branding.txt` نصب باشد.

## محدودیت آزمون

در این نشست Flutter/Dart SDK و میزبان Windows واقعی در دسترس نبود؛ بنابراین Build بومی Android/Web/Windows و اجرای مستقیم `flutter_launcher_icons` در این محیط تکرار نشد. در عین حال، لاگ PowerShell ارسالی شما نشان می‌دهد `flutter pub get` موفق بوده، `flutter analyze --fatal-infos` پیام `No issues found!` داده و ۹ تست `flutter test` با موفقیت تمام شده‌اند. این نتایج متعلق به اجرای شما هستند، نه اجرای مجدد در این محیط. مجموعهٔ Python پروژه در این بازبینی ۱۰۱ مورد داشت: ۹۸ موفق و ۳ مورد skip وابسته به محیط؛ `validate_source_contracts.py`، `check_release_version.py` و `py_compile` نیز موفق شدند. بنابراین موفقیت Build نهایی Android/Web/Windows ادعا نمی‌شود؛ مسیر bootstrap و ابزار تولید آیکون برای رفع مانع‌های لاگ اصلاح شده است.

## دستورات پیشنهادی برای PowerShell

```powershell
python tool/bootstrap_platforms.py
flutter pub get
python tool/generate_platform_icons.py
python tool/verify_platform_icons.py
python tool/check_release_version.py
python -m unittest discover -s tool -p 'test_*.py' -v
dart fix --apply
dart format lib test
flutter analyze
flutter test --reporter expanded
python tool/build.py android
```

برای Build ویندوز دسکتاپ، ابتدا Visual Studio C++ workload را نصب کنید و سپس:

```powershell
python tool/build.py windows
```
