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
rem Recording Shorts instead (Claude drops _transfer\run_shorts.flag, its first line naming them)
if exist "_transfer\run_shorts.flag" (
  set "SHORTS="
  set /p SHORTS=<"_transfer\run_shorts.flag"
  del "_transfer\run_shorts.flag"
  if not defined SHORTS set "SHORTS=all"
  echo %date% %time% === shorts !SHORTS! ===>> "%LOG%\status.txt"
  rem one Short per run of the recorder (a clean slate each)
  if exist "%LOG%\shorts.txt" del "%LOG%\shorts.txt"
  set "LIST=!SHORTS:,= !"
  for %%S in (!LIST!) do (
    echo %date% %time% short %%S>> "%LOG%\status.txt"
    call "%FLUTTER%" test tool\shorts\record_test.dart --dart-define=SHORTS=%%S >> "%LOG%\shorts.txt" 2>&1
  )
  echo %date% %time% === shorts done ===>> "%LOG%\status.txt"
  exit /b 0
)
echo %date% %time% === check ===>> "%LOG%\status.txt"
call :step doctor "doctor -v"
if not exist windows\runner\main.cpp (
  call :step create "create --platforms=windows,android --project-name evochi --org com.evochi ."
  if exist test\widget_test.dart del /q test\widget_test.dart
  if exist windows\runner\main.cpp powershell -NoProfile -Command "$f='windows\runner\main.cpp'; (Get-Content $f) -replace 'size\(1280, 720\)','size(400, 760)' | Set-Content $f"
)
call :step pub "pub get"
call :step analyze "analyze --no-fatal-infos --no-fatal-warnings"
call :step test "test"
echo %date% %time% === check done ===>> "%LOG%\status.txt"
exit /b 0

:step
echo %date% %time% start %~1>> "%LOG%\status.txt"
echo [Evochi] %~1 ...
call "%FLUTTER%" %~2 > "%LOG%\%~1.txt" 2>&1
set "RC=!errorlevel!"
echo %date% %time% end %~1 exit=!RC!>> "%LOG%\status.txt"
exit /b !RC!
