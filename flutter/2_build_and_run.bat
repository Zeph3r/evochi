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
echo %date% %time% === build and run ===>> "%LOG%\status.txt"
set /a WAITED=0
:devmode
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense 2>nul | find "0x1" >nul
if errorlevel 1 (
  if !WAITED! EQU 0 echo %date% %time% WAITING_FOR_DEVELOPER_MODE>> "%LOG%\status.txt"
  echo Waiting for Developer Mode: Settings ^> System ^> For developers ^> Developer Mode ^(on^)
  set /a WAITED+=1
  if !WAITED! GEQ 360 ( echo %date% %time% GAVE_UP_WAITING>> "%LOG%\status.txt" & exit /b 3 )
  timeout /t 5 /nobreak >nul
  goto devmode
)
echo %date% %time% developer mode on>> "%LOG%\status.txt"
taskkill /im evochi.exe /f >nul 2>&1
rem a first configure that failed (e.g. a missing NuGet source) leaves CMake installing to Program Files
if exist build\windows\x64\CMakeCache.txt findstr /c:"CMAKE_INSTALL_PREFIX:PATH=C:/Program Files" build\windows\x64\CMakeCache.txt >nul && (
  echo %date% %time% resetting stale CMake cache>> "%LOG%\status.txt"
  rmdir /s /q build\windows
)
call :step build "build windows --debug -v"
set "BRC=!errorlevel!"
if "!BRC!"=="0" if exist build\windows\x64\runner\Debug\evochi.exe (
  echo %date% %time% launching>> "%LOG%\status.txt"
  start "" "build\windows\x64\runner\Debug\evochi.exe"
) else (
  echo %date% %time% NO_EXE>> "%LOG%\status.txt"
)
exit /b 0

:step
echo %date% %time% start %~1>> "%LOG%\status.txt"
echo [Evochi] %~1 ...
call "%FLUTTER%" %~2 > "%LOG%\%~1.txt" 2>&1
set "RC=!errorlevel!"
echo %date% %time% end %~1 exit=!RC!>> "%LOG%\status.txt"
exit /b !RC!
