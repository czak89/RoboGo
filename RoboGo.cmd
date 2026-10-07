@echo off
rem Starts RoboGo without building anything. A console window flashes for a moment;
rem RoboGo.exe (created by build.cmd) starts the app without that.
rem Prefers PowerShell 7 (modern folder picker), falls back to Windows PowerShell 5.1.
setlocal
set "APP=%~dp0RoboGo.ps1"
set "PS=powershell.exe"
rem A folder dropped on this file or sent to it goes to the app in a variable.
set "ROBOGO_SOURCE=%~1"
where pwsh.exe >nul 2>nul && set "PS=pwsh.exe"
start "" conhost.exe --headless %PS% -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%APP%"
endlocal
