@echo off
rem Builds RoboGo.exe with the C# compiler that is part of the .NET Framework 4.x, so it
rem needs nothing but Windows. The exe starts RoboGo.ps1 without a console window, and it
rem carries the app inside itself (script, icon, languages): copied somewhere alone, it is
rem the whole program.
rem Usage: build.cmd      (double-click, waits for a key at the end)
rem        build.cmd /q   (for scripts, no waiting)
setlocal EnableDelayedExpansion
cd /d "%~dp0"
set "RC=0"
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" goto :nocompiler
rem What travels inside the exe: name on disk, then the name it is unpacked under.
set "RES=/resource:RoboGo.ps1,RoboGo.ps1 /resource:RoboGo.ico,RoboGo.ico"
for %%F in (lang\*.json) do set "RES=!RES! /resource:lang\%%~nxF,lang/%%~nxF"
"%CSC%" /nologo /target:winexe /optimize+ /win32icon:RoboGo.ico /reference:System.Windows.Forms.dll %RES% /out:RoboGo.exe launcher\RoboGoLauncher.cs
if errorlevel 1 goto :failed
echo [OK] RoboGo.exe is built. It runs from this folder, and on its own anywhere else.
goto :done

:nocompiler
echo [X]  The C# compiler of the .NET Framework 4 was not found.
echo      RoboGo.cmd starts the app without the launcher.
set "RC=1"
goto :done

:failed
echo [X]  The build failed.
set "RC=1"

:done
if /i not "%~1"=="/q" pause
endlocal & exit /b %RC%
