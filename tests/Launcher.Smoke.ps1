# Smoke test for the real app. Builds RoboGo.exe when needed, starts it the way Explorer
# does and watches for console windows while it starts. Then it drives the real window
# through UI Automation: language button, help panel, a dry run, a copy without and with a
# kept log. Everything the app writes goes to a throwaway ROBOGO_HOME.
# Windows are on screen for about twenty seconds, so this is not part of Run-Tests.ps1.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type -Namespace RoboGoTest -Name Native -UsingNamespace System.Collections.Generic, System.Text -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
[DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder text, int max);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int max);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr lparam);
[DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
[DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT point);
[DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
[StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
public delegate bool EnumProc(IntPtr hwnd, IntPtr lparam);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
// One line per visible top-level window: handle|process id|class|title
public static string[] VisibleWindows()
{
    List<string> found = new List<string>();
    EnumWindows(delegate(IntPtr hwnd, IntPtr lparam)
    {
        if (IsWindowVisible(hwnd))
        {
            StringBuilder name = new StringBuilder(256);
            StringBuilder title = new StringBuilder(256);
            GetClassName(hwnd, name, 256);
            GetWindowText(hwnd, title, 256);
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            found.Add(hwnd.ToInt64().ToString() + "|" + pid.ToString() + "|" + name.ToString() + "|" + title.ToString());
        }
        return true;
    }, IntPtr.Zero);
    return found.ToArray();
}
'@
[void][RoboGoTest.Native]::SetProcessDPIAware()

# Classes of the windows a console program can show: the classic console, Windows Terminal,
# and the window of a pseudo console.
$script:ConsoleClasses = @('ConsoleWindowClass', 'CASCADIA_HOSTING_WINDOW_CLASS', 'PseudoConsoleWindow')

function Watch-Launch {
    # Starts a program the way Explorer does and polls the visible top-level windows every
    # 15 ms. With -ExpectWindow it watches until the RoboGo window has been up for a moment,
    # otherwise for WatchMs. Returns the console windows that showed up and the RoboGo window.
    param([string]$FilePath, [string]$Arguments = '', [switch]$ExpectWindow, [int]$WatchMs = 2500, [int]$TimeoutSec = 30)
    $known = @{}
    foreach ($line in [RoboGoTest.Native]::VisibleWindows()) { $known[($line -split '\|')[0]] = $true }
    $result = @{ Consoles = (New-Object System.Collections.Generic.List[string]); Handle = [IntPtr]::Zero; ProcessId = 0; Seconds = 0.0 }
    $start = @{ FilePath = $FilePath; WorkingDirectory = (Split-Path -Parent $FilePath) }
    if ($Arguments -ne '') { $start['ArgumentList'] = $Arguments }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $settle = $null
    Start-Process @start
    while ($clock.Elapsed.TotalSeconds -lt $TimeoutSec) {
        foreach ($line in [RoboGoTest.Native]::VisibleWindows()) {
            $field = $line -split '\|', 4
            if ($known.ContainsKey($field[0])) { continue }
            $known[$field[0]] = $true
            if ($script:ConsoleClasses -contains $field[2]) { $result.Consoles.Add($field[2]) }
            elseif (($field[3] -eq 'RoboGo') -and $field[2].StartsWith('HwndWrapper')) {
                $result.Handle = [IntPtr][long]$field[0]
                $result.ProcessId = [int]$field[1]
                $result.Seconds = $clock.Elapsed.TotalSeconds
                $settle = [System.Diagnostics.Stopwatch]::StartNew()
            }
        }
        if ($ExpectWindow) {
            if (($null -ne $settle) -and ($settle.ElapsedMilliseconds -gt 1200)) { break }
        }
        elseif ($clock.ElapsedMilliseconds -gt $WatchMs) { break }
        Start-Sleep -Milliseconds 15
    }
    return $result
}
function Format-Seconds {
    param([double]$Seconds)
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.0}', $Seconds)
}
function Find-Control {
    # WPF exposes x:Name as the automation id.
    param($Window, [string]$Id)
    $condition = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $Id)
    $element = $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
    if ($null -eq $element) { throw "Control '$Id' was not found in the window." }
    return $element
}
function Find-Popup {
    # An open WPF popup is a window of its own (class Popup). UI Automation lists it below
    # the window that owns it. Returns $null when no popup is open.
    param($Window)
    $condition = New-Object System.Windows.Automation.PropertyCondition ([System.Windows.Automation.AutomationElement]::ClassNameProperty, 'Popup')
    return $Window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
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
function Get-ControlValue {
    param($Window, [string]$Id)
    $pattern = (Find-Control $Window $Id).GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    return [string]$pattern.Current.Value
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
function Wait-Until {
    # A click sent through UI Automation is handled a moment later. Polls until the
    # condition holds; the assertion that follows reports what is there either way.
    param([scriptblock]$Condition, [int]$TimeoutMs = 5000)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while ($clock.ElapsedMilliseconds -lt $TimeoutMs) {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 100
    }
}
function Invoke-MouseClick {
    # A real left click in the middle of a control. Only when the RoboGo window is what lies
    # under that point: a click must never land in another program. Returns $false otherwise.
    param($Window, [string]$Id, [IntPtr]$Handle)
    $box = (Find-Control $Window $Id).Current.BoundingRectangle
    $point = New-Object RoboGoTest.Native+POINT
    $point.X = [int]($box.Left + $box.Width / 2)
    $point.Y = [int]($box.Top + $box.Height / 2)
    $under = [RoboGoTest.Native]::GetAncestor([RoboGoTest.Native]::WindowFromPoint($point), 2)
    if ($under -ne $Handle) { return $false }
    [void][RoboGoTest.Native]::SetCursorPos($point.X, $point.Y)
    Start-Sleep -Milliseconds 60
    [RoboGoTest.Native]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [RoboGoTest.Native]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 600
    return $true
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
function Close-App {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return $true }
    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $true }
    [void]$process.CloseMainWindow()
    if ($process.WaitForExit(10000)) { return $true }
    $process.Kill()
    return $false
}
function Get-LogCount {
    param([string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory)) { return 0 }
    return @(Get-ChildItem -LiteralPath $Directory -Filter '*.log' -File).Count
}

$repo = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $repo 'RoboGo.exe'
$build = Join-Path $repo 'build.cmd'
$source = Join-Path $repo 'launcher\RoboGoLauncher.cs'
$oldLauncher = Join-Path $repo 'RoboGo.cmd'
if (-not (Test-Path -LiteralPath $build)) {
    Write-Host '[X]  launcher: build.cmd does not exist'
    exit 1
}
$shots = Join-Path ([System.IO.Path]::GetTempPath()) 'RoboGoShots'
if (-not (Test-Path -LiteralPath $shots)) { New-Item -ItemType Directory -Force -Path $shots | Out-Null }
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('RoboGoSmokeTest-' + [guid]::NewGuid().ToString('N'))
$src = Join-Path $root 'src'
$dst = Join-Path $root 'dst'
$workLogs = Join-Path ([System.IO.Path]::GetTempPath()) 'RoboGo'
# The launcher and the app inherit the variable, so settings, kept logs and languages of
# this run live in a folder of their own.
$env:ROBOGO_HOME = Join-Path $root 'home'
$keptLogs = Join-Path $env:ROBOGO_HOME 'logs'
$appId = 0

try {
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    New-Item -ItemType Directory -Force -Path $keptLogs | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $env:ROBOGO_HOME 'lang') | Out-Null
    foreach ($i in 1..30) { [System.IO.File]::WriteAllBytes((Join-Path $src ('file' + $i + '.bin')), (New-Object byte[] 100000)) }
    [System.IO.File]::WriteAllText((Join-Path $env:ROBOGO_HOME 'lang\xx.json'), '{ "_name": "Test", "ui.from": "OD" }', (New-Object System.Text.UTF8Encoding $false))
    [System.IO.File]::WriteAllText((Join-Path $keptLogs 'old.log'), 'old')
    [System.IO.File]::WriteAllText((Join-Path $keptLogs 'fresh.log'), 'fresh')
    (Get-Item -LiteralPath (Join-Path $keptLogs 'old.log')).LastWriteTime = (Get-Date).AddDays(-31)
    $workLogsBefore = Get-LogCount $workLogs

    # --- build ---
    $stale = $true
    if (Test-Path -LiteralPath $exe) { $stale = ((Get-Item -LiteralPath $exe).LastWriteTime -lt (Get-Item -LiteralPath $source).LastWriteTime) }
    if ($stale) {
        $output = & $build '/q' 2>&1 | Out-String
        Write-Host ('       ' + $output.Trim())
        Assert-Equal 0 $LASTEXITCODE 'build: build.cmd compiles the launcher'
    }
    Assert-True (Test-Path -LiteralPath $exe) 'build: RoboGo.exe exists'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'RoboGo.exe was not built.' }

    # --- the watcher can see a console window ---
    $control = Watch-Launch (Join-Path $env:SystemRoot 'System32\conhost.exe') 'cmd.exe /c ping -n 2 127.0.0.1' -WatchMs 2500
    Assert-True ($control.Consoles.Count -ge 1) 'watcher: a console window that is really shown is seen'

    # --- for comparison: the 0.1 launcher ---
    $old = Watch-Launch $oldLauncher -ExpectWindow
    Write-Host ('       RoboGo.cmd: ' + $old.Consoles.Count + ' console window(s) while starting, window after ' + (Format-Seconds $old.Seconds) + ' s')
    [void](Close-App $old.ProcessId)

    # --- RoboGo.exe opens the window and nothing else ---
    $new = Watch-Launch $exe -ExpectWindow
    $appId = $new.ProcessId
    Assert-True ($appId -gt 0) 'launcher: RoboGo.exe opens the window'
    if ($appId -le 0) { throw 'No RoboGo window appeared within 30 seconds.' }
    Assert-Equal 0 $new.Consoles.Count 'launcher: no console window shows up while RoboGo.exe starts'
    $app = Get-Process -Id $appId
    Write-Host ('       RoboGo.exe: window after ' + (Format-Seconds $new.Seconds) + ' s, hosted by ' + $app.ProcessName + ' (pid ' + $appId + ')')
    $window = [System.Windows.Automation.AutomationElement]::FromHandle($new.Handle)
    Assert-Equal 'Ready.' (Get-ControlText $window 'TxtStatus') 'live: starts idle'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $keptLogs 'old.log'))) 'launch: a kept log older than 30 days is removed'
    Assert-True (Test-Path -LiteralPath (Join-Path $keptLogs 'fresh.log')) 'launch: a newer one stays'

    # --- language button ---
    Assert-Equal 'EN|FROM' ((Get-ControlText $window 'BtnLang') + '|' + (Get-ControlText $window 'LblFrom')) 'live: starts in English'
    Invoke-ControlClick $window 'BtnLang'
    Wait-Until { (Get-ControlText $window 'BtnLang') -eq 'XX' }
    Assert-Equal 'XX|OD' ((Get-ControlText $window 'BtnLang') + '|' + (Get-ControlText $window 'LblFrom')) 'live: the language button switches the texts'
    Assert-True ((Get-Content -LiteralPath (Join-Path $env:ROBOGO_HOME 'settings.json') -Raw) -like '*"Language": "xx"*') 'live: the language is saved next to the program'
    Invoke-ControlClick $window 'BtnLang'
    Wait-Until { (Get-ControlText $window 'BtnLang') -eq 'EN' }
    Assert-Equal 'EN|FROM' ((Get-ControlText $window 'BtnLang') + '|' + (Get-ControlText $window 'LblFrom')) 'live: and back'

    # --- help panel ---
    Invoke-ControlClick $window 'BtnHelp'
    Wait-Until { $null -ne (Find-Popup $window) }
    $popup = Find-Popup $window
    Assert-True ($null -ne $popup) 'help: the ? button opens the panel'
    if ($null -ne $popup) {
        $panel = $popup.Current.BoundingRectangle
        $button = (Find-Control $window 'BtnHelp').Current.BoundingRectangle
        Assert-True ([math]::Abs($panel.Right - $button.Right) -le 2) 'help: the panel ends at the right edge of the ? button'
        Assert-True ((($panel.Top - $button.Bottom) -ge 2) -and (($panel.Top - $button.Bottom) -le 10)) 'help: and hangs just below it'
        (Find-Control $popup 'help.fft').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Wait-Until { (Get-ControlValue $window 'TxtExtra') -ne '' }
        Assert-Equal '/FFT' (Get-ControlValue $window 'TxtExtra') 'help: ticking a switch writes it into EXTRA'
        Invoke-ControlClick $popup 'setup.big'
        Wait-Until { (Get-ControlValue $window 'TxtThreads') -eq '1' }
        Assert-Equal '1|/J' ((Get-ControlValue $window 'TxtThreads') + '|' + (Get-ControlValue $window 'TxtExtra')) 'help: a setup sets THREADS and its switch'
        Save-RealWindowPng ([IntPtr]$popup.Current.NativeWindowHandle) (Join-Path $shots 'live-help.png')
        Invoke-ControlClick $popup 'setup.default'
        Wait-Until { (Get-ControlValue $window 'TxtThreads') -eq '8' }
        Assert-Equal '8|' ((Get-ControlValue $window 'TxtThreads') + '|' + (Get-ControlValue $window 'TxtExtra')) 'help: the default setup undoes it'
        Invoke-ControlClick $window 'BtnHelp'
        Wait-Until { $null -eq (Find-Popup $window) }
        Assert-True ($null -eq (Find-Popup $window)) 'help: the ? button closes the panel again'
    }

    # --- the help panel with the real mouse: a second click on ? and a click elsewhere close it ---
    $cursor = New-Object RoboGoTest.Native+POINT
    [void][RoboGoTest.Native]::GetCursorPos([ref]$cursor)
    # the app ignores a click on ? for a quarter of a second after the panel closed
    Start-Sleep -Milliseconds 500
    if (Invoke-MouseClick $window 'BtnHelp' $new.Handle) {
        Assert-True ($null -ne (Find-Popup $window)) 'mouse: a click on ? opens the panel'
        [void](Invoke-MouseClick $window 'BtnHelp' $new.Handle)
        Assert-True ($null -eq (Find-Popup $window)) 'mouse: a second click on ? closes it and it stays closed'
        [void](Invoke-MouseClick $window 'BtnHelp' $new.Handle)
        Assert-True ($null -ne (Find-Popup $window)) 'mouse: a third click opens it again'
        [void](Invoke-MouseClick $window 'LblPaths' $new.Handle)
        Assert-True ($null -eq (Find-Popup $window)) 'mouse: a click somewhere else in the window closes it'
    }
    else {
        Write-Host '[--] mouse: skipped, another window covers the ? button'
    }
    [void][RoboGoTest.Native]::SetCursorPos($cursor.X, $cursor.Y)

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

    # --- the real copy, scan first, log only in the window ---
    Invoke-ControlClick $window 'BtnRun'
    $status = Wait-Status $window 'Done.*'
    Assert-Equal 'Done. Copied 30 file(s), 2.9 MB.' $status 'live: the copy finishes with its verdict'
    Assert-Equal '100%' (Get-ControlText $window 'TxtPercent') 'live: percent ends at 100%'
    Assert-Equal '30 / 30' (Get-ControlText $window 'TxtFiles') 'live: file counter'
    Assert-Equal 30 (@(Get-ChildItem -LiteralPath $dst -File).Count) 'live: the files really arrive'
    Assert-True ((Get-ControlValue $window 'TxtLog') -like '*file30.bin*') 'live: the log box shows the copied files'
    Assert-Equal $workLogsBefore (Get-LogCount $workLogs) 'logs: no working log is left in TEMP'
    Assert-Equal 1 (Get-LogCount $keptLogs) 'logs: nothing is kept by default'

    Save-RealWindowPng $new.Handle (Join-Path $shots 'live-window.png')
    Write-Host ('       pictures: ' + $shots + '\live-window.png, live-help.png')
    $picture = New-Object System.Drawing.Bitmap (Join-Path $shots 'live-window.png')
    $pixel = $picture.GetPixel([int]($picture.Width / 2), 12)
    $picture.Dispose()
    Assert-True (($pixel.R + $pixel.G + $pixel.B) -lt 120) 'live: the title bar is dark like the rest of the window'

    # --- the same copy again with Keep log file ---
    (Find-Control $window 'ChkKeepLog').GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
    Set-ControlText $window 'TxtDest' ($dst + '2')
    Invoke-ControlClick $window 'BtnRun'
    # the status line still shows the verdict of the first copy, so wait for the saved log
    Wait-Until { (Get-LogCount $keptLogs) -ge 2 } 30000
    $status = Wait-Status $window 'Done.*'
    Assert-Equal 'Done. Copied 30 file(s), 2.9 MB.' $status 'logs: the second copy finishes'
    Assert-Equal 2 (Get-LogCount $keptLogs) 'logs: with Keep log file the log is saved in logs next to the program'
    Assert-Equal $workLogsBefore (Get-LogCount $workLogs) 'logs: and TEMP stays clean'
    Assert-True ((Get-Content -LiteralPath (Join-Path $env:ROBOGO_HOME 'settings.json') -Raw) -like '*"KeepLog": true*') 'logs: the choice is saved'

    # --- closing ---
    Assert-True (Close-App $appId) 'launcher: the window closes on request'
    $appId = 0

    # --- without PowerShell 7 on the PATH the launcher falls back to Windows PowerShell ---
    $savedPath = $env:PATH
    try {
        $env:PATH = (Join-Path $env:SystemRoot 'System32') + ';' + $env:SystemRoot
        $plain = Watch-Launch $exe -ExpectWindow
    }
    finally {
        $env:PATH = $savedPath
    }
    $appId = $plain.ProcessId
    Assert-True ($appId -gt 0) 'fallback: the window also opens without PowerShell 7'
    if ($appId -gt 0) {
        Assert-Equal 'powershell' (Get-Process -Id $appId).ProcessName 'fallback: hosted by Windows PowerShell 5.1'
        Assert-Equal 0 $plain.Consoles.Count 'fallback: no console window either'
        Write-Host ('       RoboGo.exe on Windows PowerShell: window after ' + (Format-Seconds $plain.Seconds) + ' s')
        Assert-True (Close-App $appId) 'fallback: closes on request'
        $appId = 0
    }
}
finally {
    if ($appId -gt 0) { [void](Close-App $appId) }
    $env:ROBOGO_HOME = $null
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

exit (Complete-Tests 'Smoke')
