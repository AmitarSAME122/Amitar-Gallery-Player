@echo off
echo Checking Android Gradle Plugin 8.13.2 via mirror (Aliyun)...
curl -s -o NUL -w "%%{http_code}" "https://maven.aliyun.com/repository/google/com/android/tools/build/gradle/8.13.2/gradle-8.13.2.pom" > "%TEMP%\amitar_check.txt"
set /p CODE=<"%TEMP%\amitar_check.txt"
if "%CODE%"=="200" (
    echo [OK] AGP POM reachable via mirror.
    exit /b 0
) else (
    echo [FAIL] HTTP %CODE% - mirror may be unreachable.
    exit /b 1
)