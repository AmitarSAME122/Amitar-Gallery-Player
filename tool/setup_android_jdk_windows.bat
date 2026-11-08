@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_android_jdk_windows.ps1" %*
exit /b %errorlevel%
