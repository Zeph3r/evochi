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
echo.
echo  Android SDK licenses
echo  --------------------
echo  Each license is printed in full. Type  y  and press Enter for each one.
echo.
call "%FLUTTER%" doctor --android-licenses
echo %date% %time% android licenses: exit=!errorlevel!>> "%LOG%\status.txt"
echo.
echo  All done. You can close this window.
pause >nul
