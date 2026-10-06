# Runs every *.Tests.ps1 in this folder, each in its own process of the current PowerShell host.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1 [-Filter Core]
param([string]$Filter = '*')

$hostExe = (Get-Process -Id $PID).Path
$failed = 0
$files = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter ($Filter + '.Tests.ps1') | Sort-Object Name)
if ($files.Count -eq 0) {
    Write-Host "[X]  no test files match '$Filter'"
    exit 1
}
foreach ($file in $files) {
    Write-Host ''
    Write-Host ('=== ' + $file.Name + ' on PowerShell ' + $PSVersionTable.PSVersion + ' ===')
    & $hostExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $file.FullName
    if ($LASTEXITCODE -ne 0) { $failed++ }
}
Write-Host ''
if ($failed -eq 0) { Write-Host '[OK] ALL SUITES PASSED' } else { Write-Host "[X]  $failed suite(s) FAILED" }
exit $failed
