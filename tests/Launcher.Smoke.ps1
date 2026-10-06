# Smoke test for the real app: starts RoboGo.cmd, drives the real window through UI
# Automation (a dry run and a copy inside a temp folder), saves a picture of it and closes it.
# The window is on screen for about ten seconds, so this is not part of Run-Tests.ps1.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type -Namespace RoboGoTest -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
'@
[void][RoboGoTest.Native]::SetProcessDPIAware()

function Find-Control {
    # WPF exposes x:Name as the automation id.
    param($Window, [string]$Id)
    $condition = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
    $element = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
    if ($null -eq $element) { throw "Control '$Id' was not found in the window." }
    return $element
}
function Set-ControlText {
    param($Window, [string]$Id, [string]$Text)
    $pattern = (Find-Control $Window $Id).GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $pattern.SetValue($Text)
}
function Get-ControlText {
    param($Window, [string]$Id)
    return [string](Find-Control $Window $Id).Current.Name
}
function Invoke-ControlClick {
    param($Window, [string]$Id)
    $pattern = (Find-Control $Window $Id).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $pattern.Invoke()
}
function Wait-Status {
    # Waits until the status line matches, and returns the last text seen either way.
    param($Window, [string]$Like, [int]$TimeoutSec = 30)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $text = ''
    while ($clock.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $text = Get-ControlText $Window 'TxtStatus'
        if ($text -like $Like) { break }
        Start-Sleep -Milliseconds 150
    }
    return $text
}
function Save-RealWindowPng {
    # Captures only this one window, title bar included.
    param([IntPtr]$Handle, [string]$Path)
    $rect = New-Object RoboGoTest.Native+RECT
    [void][RoboGoTest.Native]::GetWindowRect($Handle, [ref]$rect)
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    if (($w -le 0) -or ($h -le 0)) { return }
    $bitmap = New-Object System.Drawing.Bitmap ($w, $h)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    try { [void][RoboGoTest.Native]::PrintWindow($Handle, $hdc, 2) }
    finally {
        $graphics.ReleaseHdc($hdc)
        $graphics.Dispose()
    }
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
}

$launcher = Join-Path $PSScriptRoot '..\RoboGo.cmd'
if (-not (Test-Path -LiteralPath $launcher)) {
    Write-Host '[X]  launcher: RoboGo.cmd does not exist'
    exit 1
}
$shots = Join-Path ([System.IO.Path]::GetTempPath()) 'RoboGoShots'
if (-not (Test-Path -LiteralPath $shots)) { New-Item -ItemType Directory -Force -Path $shots | Out-Null }
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('RoboGoSmokeTest-' + [guid]::NewGuid().ToString('N'))
$src = Join-Path $root 'src'
$dst = Join-Path $root 'dst'
$app = $null

try {
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    foreach ($i in 1..30) { [System.IO.File]::WriteAllBytes((Join-Path $src ('file' + $i + '.bin')), (New-Object byte[] 100000)) }

    # --- the launcher opens the window ---
    $before = @(Get-Process | Where-Object { $_.MainWindowTitle -eq 'RoboGo' } | ForEach-Object { $_.Id })
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Process -FilePath $launcher -WindowStyle Hidden
    while (($null -eq $app) -and ($clock.Elapsed.TotalSeconds -lt 30)) {
        Start-Sleep -Milliseconds 100
        $app = Get-Process | Where-Object { ($_.MainWindowTitle -eq 'RoboGo') -and ($before -notcontains $_.Id) } | Select-Object -First 1
    }
    Assert-True ($null -ne $app) 'launcher: the window opens'
    if ($null -eq $app) { throw 'No RoboGo window appeared within 30 seconds.' }
    $seconds = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.0}', $clock.Elapsed.TotalSeconds)
    Write-Host ('       opened after ' + $seconds + ' s, hosted by ' + $app.ProcessName + ' (pid ' + $app.Id + ')')
    $window = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
    Assert-Equal 'Ready.' (Get-ControlText $window 'TxtStatus') 'live: starts idle'

    # --- typing into the fields reaches the event handlers ---
    Set-ControlText $window 'TxtSource' $src
    Set-ControlText $window 'TxtDest' $dst
    Set-ControlText $window 'TxtThreads' 'abc'
    Assert-Equal 'Threads must be a number from 1 to 128.' (Get-ControlText $window 'TxtProblem') 'live: the preview handler runs in the real window'
    Set-ControlText $window 'TxtThreads' '8'

    # --- dry run: the real timer drives the job ---
    Invoke-ControlClick $window 'BtnDry'
    $status = Wait-Status $window 'Dry run, nothing was changed.*'
    Assert-Equal 'Dry run, nothing was changed. Would copy 30 file(s), 2.9 MB.' $status 'live: the dry run finishes with its verdict'
    Assert-True (-not (Test-Path -LiteralPath $dst)) 'live: the dry run writes nothing'

    # --- the real copy, scan first ---
    Invoke-ControlClick $window 'BtnRun'
    $status = Wait-Status $window 'Done.*'
    Assert-Equal 'Done. Copied 30 file(s), 2.9 MB.' $status 'live: the copy finishes with its verdict'
    Assert-Equal '100%' (Get-ControlText $window 'TxtPercent') 'live: percent ends at 100%'
    Assert-Equal '30 / 30' (Get-ControlText $window 'TxtFiles') 'live: file counter'
    Assert-Equal 30 (@(Get-ChildItem -LiteralPath $dst -File).Count) 'live: the files really arrive'

    Save-RealWindowPng $app.MainWindowHandle (Join-Path $shots 'live-window.png')
    Write-Host ('       picture: ' + (Join-Path $shots 'live-window.png'))
    $picture = New-Object System.Drawing.Bitmap (Join-Path $shots 'live-window.png')
    $pixel = $picture.GetPixel([int]($picture.Width / 2), 12)
    $picture.Dispose()
    Assert-True (($pixel.R + $pixel.G + $pixel.B) -lt 120) 'live: the title bar is dark like the rest of the window'

    # --- closing ---
    [void]$app.CloseMainWindow()
    Assert-True ($app.WaitForExit(10000)) 'launcher: the window closes on request'
}
finally {
    if (($null -ne $app) -and (-not $app.HasExited)) {
        [void]$app.CloseMainWindow()
        if (-not $app.WaitForExit(5000)) { $app.Kill() }
    }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

exit (Complete-Tests 'Smoke')
