@echo off
rem RoboGo launcher. Starts the app without leaving a console window behind.
rem Prefers PowerShell 7 (modern folder picker), falls back to Windows PowerShell 5.1.
setlocal
set "APP=%~dp0RoboGo.ps1"
set "PS=powershell.exe"
where pwsh.exe >nul 2>nul && set "PS=pwsh.exe"
start "" conhost.exe --headless %PS% -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File "%APP%"
endlocal
