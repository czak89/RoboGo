@echo off
rem Builds RoboGo.exe, the launcher that starts RoboGo.ps1 without a console window.
rem Needs nothing but Windows: the C# compiler is part of the .NET Framework 4.x.
rem Usage: build.cmd      (double-click, waits for a key at the end)
rem        build.cmd /q   (for scripts, no waiting)
setlocal
cd /d "%~dp0"
set "RC=0"
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" goto :nocompiler
"%CSC%" /nologo /target:winexe /optimize+ /win32icon:RoboGo.ico /reference:System.Windows.Forms.dll /out:RoboGo.exe launcher\RoboGoLauncher.cs
if errorlevel 1 goto :failed
echo [OK] RoboGo.exe is built. Start RoboGo with it, or pin it to the taskbar.
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
