@echo off
cd /d "%~dp0"
call flutter pub get
call flutter build apk --release
echo.
echo APK: build\app\outputs\flutter-apk\app-release.apk
call flutter build appbundle --release
echo AAB: build\app\outputs\bundle\release\app-release.aab
pause
