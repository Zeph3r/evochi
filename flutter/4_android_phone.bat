@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
if not exist logs mkdir logs
set "LOG=%~dp0logs"
set "FLUTTER="
for /f "delims=" %%F in ('where flutter.bat 2^>nul') do if not defined FLUTTER set "FLUTTER=%%F"
if not defined FLUTTER for %%P in ("%USERPROFILE%\dev\flutter" "%USERPROFILE%\src\flutter" "%USERPROFILE%\flutter" "C:\src\flutter" "C:\flutter" "C:\dev\flutter" "%LOCALAPPDATA%\flutter" "%USERPROFILE%\scoop\apps\flutter\current" "C:\tools\flutter" "%USERPROFILE%\AppData\Local\Programs\flutter") do if not defined FLUTTER if exist "%%~P\bin\flutter.bat" set "FLUTTER=%%~P\bin\flutter.bat"
if not defined FLUTTER (
  echo FLUTTER_NOT_FOUND>> "%LOG%\status.txt"
  echo Could not find Flutter. See logs\status.txt
  timeout /t 8 >nul
  exit /b 2
)
echo flutter=!FLUTTER!>> "%LOG%\status.txt"
echo %date% %time% === android phone ===>> "%LOG%\status.txt"
set "ADB="
for %%P in ("%ANDROID_HOME%" "%ANDROID_SDK_ROOT%" "%LOCALAPPDATA%\Android\Sdk") do if not defined ADB if exist "%%~P\platform-tools\adb.exe" set "ADB=%%~P\platform-tools\adb.exe"
echo.
echo  Building the Evochi APK. The first build downloads Gradle and the Android libraries,
echo  so it can take 5 to 10 minutes. Later builds take about a minute.
echo.
call :step apk "build apk --release"
set "ARC=!errorlevel!"
if not "!ARC!"=="0" (
  echo  The build failed. Details are in logs\apk.txt
  echo %date% %time% APK_FAILED>> "%LOG%\status.txt"
  pause >nul
  exit /b 1
)
copy /y "build\app\outputs\flutter-apk\app-release.apk" "Evochi.apk" >nul
if errorlevel 1 (
  echo  The APK wasn't produced. If another build window is still open, close it and run this again.
  echo %date% %time% APK_MISSING>> "%LOG%\status.txt"
  pause >nul
  exit /b 1
)
echo %date% %time% apk ready: Evochi.apk>> "%LOG%\status.txt"
echo  Built: %~dp0Evochi.apk
if not defined ADB (
  echo %date% %time% NO_ADB>> "%LOG%\status.txt"
  goto done
)
"%ADB%" devices > "%LOG%\adb_devices.txt" 2>&1
set "DEV="
set "UNAUTH="
for /f "skip=1 tokens=1,2" %%a in ('type "%LOG%\adb_devices.txt"') do (
  if "%%b"=="device" if not defined DEV set "DEV=%%a"
  if "%%b"=="unauthorized" set "UNAUTH=%%a"
)
if not defined DEV (
  if defined UNAUTH (
    echo %date% %time% PHONE_UNAUTHORIZED>> "%LOG%\status.txt"
    echo  Your phone is connected but hasn't allowed this PC yet: unlock it and tap Allow on the USB debugging prompt, then run this again.
  ) else (
    echo %date% %time% NO_PHONE>> "%LOG%\status.txt"
    echo  No phone found over USB. Copy Evochi.apk to your phone to install it, or connect with USB debugging and run this again.
  )
  goto done
)
echo  Installing on your phone (!DEV!) ...
"%ADB%" -s !DEV! install -r "Evochi.apk" > "%LOG%\adb_install.txt" 2>&1
echo %date% %time% install on !DEV! exit=!errorlevel!>> "%LOG%\status.txt"
"%ADB%" -s !DEV! shell monkey -p com.evochi.evochi -c android.intent.category.LAUNCHER 1 >nul 2>&1
echo %date% %time% launched on phone>> "%LOG%\status.txt"
echo  Evochi is on your phone.
:done
echo.
echo  Press any key to close.
pause >nul
exit /b 0

:step
echo %date% %time% start %~1>> "%LOG%\status.txt"
echo [Evochi] %~1 ...
call "%FLUTTER%" %~2 > "%LOG%\%~1.txt" 2>&1
set "RC=!errorlevel!"
echo %date% %time% end %~1 exit=!RC!>> "%LOG%\status.txt"
exit /b !RC!
