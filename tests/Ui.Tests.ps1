# Window tests. Nothing appears on screen: the window is loaded, driven through its
# controls, run against real robocopy, and rendered to PNG files for review.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
# Settings, kept logs and language files belong to the program folder. ROBOGO_HOME points
# the app at a throwaway one, with a small test language in it.
$env:ROBOGO_HOME = Join-Path ([System.IO.Path]::GetTempPath()) ('RoboGoHomeTest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $env:ROBOGO_HOME 'lang') | Out-Null
# The Send to shortcut goes to a folder of its own as well, never to the real Send to menu.
$env:ROBOGO_SENDTO = Join-Path $env:ROBOGO_HOME 'sendto'
[System.IO.File]::WriteAllText((Join-Path $env:ROBOGO_HOME 'lang\xx.json'), '{ "_name": "Test", "ui.from": "OD", "ph.source": "np. D:\\Zdjecia", "status.ready": "Gotowe." }', (New-Object System.Text.UTF8Encoding $false))
$app = Join-Path $PSScriptRoot '..\RoboGo.ps1'
. $app -NoUI
# The tests stay off the desktop of whoever runs them. They replace the few functions that
# would reach it: the clipboard, every yes/no question, and the flash and sound at the end
# of a job. The free space of the destination can be faked to stage a full disk.
$script:Clip = ''
function Set-RoboClipboard {
    param([string]$Text)
    $script:Clip = $Text
}
$script:Asked = New-Object System.Collections.Generic.List[string]
$script:Answer = $true
function Confirm-RoboGo {
    param([string]$Message)
    $script:Asked.Add($Message)
    return $script:Answer
}
$script:Signals = New-Object System.Collections.Generic.List[string]
function Invoke-RoboAttention {
    param($Handle, [string]$Level)
    $script:Signals.Add($Level)
}
function Invoke-RoboSound {
    # second line of defence: no test of the window may ever play a sound
    param([string]$Name)
    return $true
}
$script:FakeFree = $null
$script:RealFreeSpace = ${function:Get-RoboFreeSpace}
function Get-RoboFreeSpace {
    param([string]$Path)
    if ($null -ne $script:FakeFree) { return [long]$script:FakeFree }
    return (& $script:RealFreeSpace $Path)
}
function Get-Taskbar {
    param($UI)
    return [string]$UI.Window.TaskbarItemInfo.ProgressState
}
$workingLogsBefore = @(Get-ChildItem -LiteralPath (Get-RoboLogDir) -Filter '*.log' -File).Count

function Get-CommandText {
    # Rebuilds the command from the tape: a piece with a right margin ends a token.
    param($UI)
    $text = ''
    foreach ($piece in @($UI.CmdPanel.Children)) {
        $text += $piece.Text
        if ($piece.Margin.Right -gt 0) { $text += ' ' }
    }
    return $text.Trim()
}
function Save-WindowPng {
    # Renders the window content to a PNG file. WPF suspends layout below a window that was
    # never shown, so the window is shown once, far off screen and without taking focus.
    param($UI, [string]$Path, [double]$Scale = 1.5)
    $window = $UI.Window
    if (-not $window.IsVisible) {
        $window.WindowStartupLocation = 'Manual'
        $window.Left = -32000
        $window.Top = -32000
        $window.ShowInTaskbar = $false
        $window.ShowActivated = $false
        $window.Show()
    }
    $window.UpdateLayout()
    $window.Dispatcher.Invoke([Action] { }, [System.Windows.Threading.DispatcherPriority]::ApplicationIdle)
    $root = $UI.Root
    $w = [int][math]::Ceiling($root.ActualWidth * $Scale)
    $h = [int][math]::Ceiling($root.ActualHeight * $Scale)
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ($w, $h, (96 * $Scale), (96 * $Scale), [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($root)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Create($Path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}
function Test-DesktopDrawable {
    # Windows draws nothing for WPF while the session is locked or switched to another user,
    # and every render comes out blank. OpenInputDesktop fails in exactly those situations.
    if (-not ('RoboGoTest.Desktop' -as [type])) {
        Add-Type -Namespace RoboGoTest -Name Desktop -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access); [DllImport("user32.dll")] public static extern bool CloseDesktop(IntPtr handle);'
    }
    $handle = [RoboGoTest.Desktop]::OpenInputDesktop(0, $false, 0x0100)
    if ($handle -eq [IntPtr]::Zero) { return $false }
    [void][RoboGoTest.Desktop]::CloseDesktop($handle)
    return $true
}
function Assert-Rendered {
    # A real render of this window is far above 20 KB; a blank one is about 6 KB.
    param([string]$Path, [string]$Name)
    if (Test-DesktopDrawable) {
        Assert-True ((Get-Item -LiteralPath $Path).Length -gt 20000) $Name
    }
    else {
        Write-Host "[--] $Name (skipped: the Windows session is locked or switched away, so nothing is drawn)"
    }
}
function Save-ElementPng {
    # Renders an element that is not on screen (the help panel lives in a closed popup).
    param($Element, [string]$Path, [double]$Scale = 1.5)
    $Element.Measure((New-Object System.Windows.Size ([double]::PositiveInfinity, [double]::PositiveInfinity)))
    $size = $Element.DesiredSize
    $Element.Arrange((New-Object System.Windows.Rect $size))
    $Element.UpdateLayout()
    $w = [int][math]::Ceiling($size.Width * $Scale)
    $h = [int][math]::Ceiling($size.Height * $Scale)
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap ($w, $h, (96 * $Scale), (96 * $Scale), [System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($Element)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Create($Path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
}
function Get-ClippedControls {
    # Names of visible controls that stick out of the window content area.
    param($UI)
    $area = New-Object System.Windows.Rect (-0.5, -0.5, ($UI.Root.ActualWidth + 1), ($UI.Root.ActualHeight + 1))
    $bad = New-Object System.Collections.Generic.List[string]
    foreach ($name in $script:RoboGoControls) {
        $control = $UI[$name]
        if ([object]::ReferenceEquals($control, $UI.Root)) { continue }
        if (-not ($control -is [System.Windows.FrameworkElement])) { continue }
        if ((-not $control.IsVisible) -or (-not $control.IsDescendantOf($UI.Root))) { continue }
        $box = $control.TransformToAncestor($UI.Root).TransformBounds((New-Object System.Windows.Rect (0, 0, $control.ActualWidth, $control.ActualHeight)))
        if (-not $area.Contains($box)) { $bad.Add($name) }
    }
    return ($bad -join ' ')
}
function Get-WorkingLogCount {
    return @(Get-ChildItem -LiteralPath (Get-RoboLogDir) -Filter '*.log' -File).Count
}
function Step-UntilIdle {
    # Plays the role of the UI timer until the job is over.
    param([int]$TimeoutSec = 60)
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while (($null -ne $script:RoboGo.Job) -and ($clock.Elapsed.TotalSeconds -lt $TimeoutSec)) {
        Step-RoboGo
        Start-Sleep -Milliseconds 40
    }
}

$shots = Join-Path ([System.IO.Path]::GetTempPath()) 'RoboGoShots'
if (-not (Test-Path -LiteralPath $shots)) { New-Item -ItemType Directory -Force -Path $shots | Out-Null }
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('RoboGoUiTest-' + [guid]::NewGuid().ToString('N'))

try {
    # --- a window that finds a settings file: the fields of the last session come back ---
    $remembered = Read-RoboSettings
    $remembered.Last = @{ Source = 'D:\Old\From'; Destination = 'E:\Old\To'; Subfolders = $true; SkipJunctions = $false; OnlyNewer = $true; Restartable = $true; Threads = '4'; Retries = '7'; Wait = '9'; ExcludeFiles = '*.bak'; ExcludeDirs = 'tmp'; Extra = '/FFT'; Scan = $false }
    $remembered.RecentSources = @('D:\Old\From', 'D:\Older')
    $remembered.RecentDestinations = @('E:\Old\To')
    [void](Save-RoboSettings $remembered)
    $first = New-RoboGoWindow
    Initialize-RoboGoWindow $first
    Assert-Equal 'D:\Old\From|E:\Old\To|4|7|9|*.bak|tmp|/FFT' (($first.TxtSource.Text, $first.TxtDest.Text, $first.TxtThreads.Text, $first.TxtRetries.Text, $first.TxtWait.Text, $first.TxtXF.Text, $first.TxtXD.Text, $first.TxtExtra.Text) -join '|') 'restore: the texts of the last session are back in the fields'
    Assert-Equal 'True|False|True|True|False' (($first.ChkSub.IsChecked, $first.ChkJunction.IsChecked, $first.ChkNewer.IsChecked, $first.ChkRestart.IsChecked, $first.ChkScan.IsChecked) -join '|') 'restore: and the check boxes'
    Assert-Equal 'robocopy "D:\Old\From" "E:\Old\To" /E /MT:4 /R:7 /W:9 /Z /XO /XF *.bak /XD tmp /FFT' (Get-CommandText $first) 'restore: the command shows them'
    Assert-Equal 'True|True' ([string]$first.BtnRecentSource.IsEnabled + '|' + [string]$first.BtnRecentDest.IsEnabled) 'recent: both arrow buttons are on when there are paths'
    Update-RoboGoRecentRows 'Source'
    Assert-Equal 3 $first.RecentList.Children.Count 'recent: one row per path and one to clear the list'
    Assert-Equal 'D:\Old\From|D:\Older' (($first.RecentList.Children[0].Tag, $first.RecentList.Children[1].Tag) -join '|') 'recent: newest first'
    Save-ElementPng $first.RecentPanel (Join-Path $shots 'ui-recent.png')
    Select-RoboGoRecent 'D:\Older'
    Assert-Equal 'D:\Older' $first.TxtSource.Text 'recent: a row fills FROM'
    Update-RoboGoRecentRows 'Destination'
    Assert-Equal 2 $first.RecentList.Children.Count 'recent: the destinations have a list of their own'
    Select-RoboGoRecent 'E:\Old\To'
    Assert-Equal 'E:\Old\To' $first.TxtDest.Text 'recent: a row fills TO'
    Clear-RoboGoRecent
    Assert-Equal 'False|False' ([string]$first.BtnRecentSource.IsEnabled + '|' + [string]$first.BtnRecentDest.IsEnabled) 'recent: clearing the list turns the arrows off'
    $cleared = Read-RoboSettings
    Assert-Equal '0|0' ([string]$cleared.RecentSources.Count + '|' + [string]$cleared.RecentDestinations.Count) 'recent: and it is saved'
    $script:RoboGo.Timer.Stop()

    # --- started with a folder (Send to): FROM is that folder, TO is empty ---
    $given = Join-Path $env:ROBOGO_HOME 'given folder'
    New-Item -ItemType Directory -Force -Path $given | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $given 'one.txt'), 'x')
    $sent = New-RoboGoWindow
    Initialize-RoboGoWindow $sent -Source ($given + '\')
    Assert-Equal ($given + '||*.bak') (($sent.TxtSource.Text, $sent.TxtDest.Text, $sent.TxtXF.Text) -join '|') 'send to: the folder goes into FROM, TO is emptied, the other fields stay remembered'
    Assert-Equal 'Ready.' $sent.TxtStatus.Text 'send to: nothing to remark for a folder'
    $script:RoboGo.Timer.Stop()
    $sent = New-RoboGoWindow
    Initialize-RoboGoWindow $sent -Source (Join-Path $given 'one.txt')
    Assert-Equal $given $sent.TxtSource.Text 'send to: a file gives its folder'
    Assert-Equal 'That was a file, so its folder was taken.' $sent.TxtStatus.Text 'send to: and the status line says so'
    $script:RoboGo.Timer.Stop()
    # "D:\" "E:\x" on a command line reaches a program as one mangled argument: D:" E:\x
    $sent = New-RoboGoWindow
    Initialize-RoboGoWindow $sent -Source ($given + '" C:\other')
    Assert-Equal $given $sent.TxtSource.Text 'send to: what follows a stray quote is cut off'
    $script:RoboGo.Timer.Stop()
    [System.IO.File]::Delete((Get-RoboSettingsPath))

    # --- where the window was ---
    $probe = New-RoboGoWindow
    $spot = @{ Left = ([System.Windows.SystemParameters]::VirtualScreenLeft + 60); Top = ([System.Windows.SystemParameters]::VirtualScreenTop + 50); Width = 820; Height = 660 }
    Assert-True (Restore-RoboGoWindow $probe $spot) 'placement: a rectangle on the screen is taken'
    Assert-Equal ('Manual|' + $spot.Left + '|' + $spot.Top + '|820|660') (([string]$probe.Window.WindowStartupLocation, $probe.Window.Left, $probe.Window.Top, $probe.Window.Width, $probe.Window.Height) -join '|') 'placement: position and size are applied'
    $probe = New-RoboGoWindow
    Assert-True (-not (Restore-RoboGoWindow $probe @{ Left = 99999; Top = 99999; Width = 800; Height = 600 })) 'placement: a spot that is on no screen is refused'
    Assert-Equal 'CenterScreen' ([string]$probe.Window.WindowStartupLocation) 'placement: the window then opens in the middle'
    Assert-True (-not (Restore-RoboGoWindow $probe $null)) 'placement: nothing saved, nothing done'
    $spot.Width = 100
    $spot.Height = 100
    [void](Restore-RoboGoWindow $probe $spot)
    Assert-Equal ([string]$probe.Window.MinWidth + '|' + [string]$probe.Window.MinHeight) ([string]$probe.Window.Width + '|' + [string]$probe.Window.Height) 'placement: never smaller than the minimum size'

    # --- the main window of these tests starts without a settings file ---
    $ui = New-RoboGoWindow
    Assert-True ($null -ne $ui.Window) 'window: the XAML loads and every named control exists'
    Initialize-RoboGoWindow $ui
    Assert-Equal 'False|False' ([string]$ui.BtnRecentSource.IsEnabled + '|' + [string]$ui.BtnRecentDest.IsEnabled) 'recent: no arrows without earlier jobs'
    Assert-Equal 'Collapsed|Collapsed' ([string]$ui.BtnFailed.Visibility + '|' + [string]$ui.BtnTape.Visibility) 'window: the FAILED and SHOW ALL buttons wait until they are needed'
    Assert-Equal 'None' (Get-Taskbar $ui) 'taskbar: no progress while idle'

    # --- Send to toggle ---
    Assert-Equal 'SEND TO' $ui.BtnSendTo.Content 'send to: the toggle is in the header'
    Switch-RoboGoSendTo
    Assert-True (Test-RoboSendTo) 'send to: a click creates the shortcut'
    Assert-True ([object]::ReferenceEquals($ui.BtnSendTo.Foreground, $ui.Window.FindResource('Amber'))) 'send to: the toggle lights up'
    Assert-Equal 'RoboGo is now in the Send to menu of Explorer.' $ui.TxtStatus.Text 'send to: the status line confirms it'
    Switch-RoboGoSendTo
    Assert-True (-not (Test-RoboSendTo)) 'send to: a second click removes it'
    Assert-True ([object]::ReferenceEquals($ui.BtnSendTo.Foreground, $ui.Window.FindResource('Dim'))) 'send to: the toggle goes dim'
    Set-RoboGoStatus 'status.ready'
    Assert-Equal ('v' + $script:RoboGoVersion) $ui.TxtVersion.Text 'window: shows the version'
    Assert-Equal 'Ready.' $ui.TxtStatus.Text 'window: starts idle'
    Assert-Equal 'False' $ui.BtnCancel.IsEnabled 'window: cancel is off while idle'
    Assert-Equal 'Collapsed' $ui.TxtProblem.Visibility 'preview: empty paths do not nag before the first run'

    # --- compact layout ---
    Assert-True ($ui.Window.Width -le 760) 'size: the default width is at most 760'
    Assert-True ($ui.Window.Height -le 620) 'size: the default height is at most 620'
    Assert-Equal 'PATHS|OPTIONS|COMMAND|PROGRESS' (($ui.LblPaths.Text, $ui.LblOptions.Text, $ui.LblCommand.Text, $ui.LblProgress.Text) -join '|') 'rail: section names without numbers'
    Assert-Equal 'e.g. D:\Photos' $ui.TxtSource.Tag 'placeholder: FROM shows an example while empty'
    Assert-Equal 'e.g. \\nas\backup\Photos' $ui.TxtDest.Tag 'placeholder: TO'
    Assert-Equal 'e.g. *.tmp; thumbs.db' $ui.TxtXF.Tag 'placeholder: SKIP FILES'
    Assert-Equal 'e.g. node_modules; .git' $ui.TxtXD.Tag 'placeholder: SKIP FOLDERS'
    Assert-Equal 'e.g. *.jpg /MAXAGE:7' $ui.TxtExtra.Tag 'placeholder: EXTRA'
    Assert-Equal 'Collapsed' $ui.TxtModeHint.Visibility 'mode: no hint line for a plain copy'

    # --- language ---
    Assert-Equal 'EN' $ui.BtnLang.Content 'language: the button shows the current language'
    Assert-Equal 'FROM' $ui.LblFrom.Text 'language: English labels at first'
    Switch-RoboGoLanguage
    Assert-Equal 'XX' $ui.BtnLang.Content 'language: a click moves to the next language'
    Assert-Equal 'OD' $ui.LblFrom.Text 'language: labels come from the language file'
    Assert-Equal 'np. D:\Zdjecia' $ui.TxtSource.Tag 'language: placeholders too'
    Assert-Equal 'TO' $ui.LblTo.Text 'language: texts the file does not have stay English'
    Assert-Equal 'Gotowe.' $ui.TxtStatus.Text 'language: the idle status follows'
    Assert-Equal 'xx' (Read-RoboSettings).Language 'language: the choice is saved'
    Switch-RoboGoLanguage
    Assert-Equal 'EN' $ui.BtnLang.Content 'language: after the last language it is English again'
    Assert-Equal 'FROM' $ui.LblFrom.Text 'language: and the labels are back'
    Assert-Equal 'en' (Read-RoboSettings).Language 'language: saved again'

    # --- the log box keeps the newest lines only ---
    foreach ($i in 1..7000) { Add-RoboGoLog ('line ' + $i) }
    Update-RoboGoLogView
    $shown = @($ui.TxtLog.Text -split [Environment]::NewLine | Where-Object { $_ -ne '' })
    Assert-Equal 5000 $shown.Count 'log box: trimmed to the newest 5,000 lines once it passes 6,000'
    Assert-Equal 'line 2001|line 7000' ($shown[0] + '|' + $shown[$shown.Count - 1]) 'log box: the oldest lines go, the newest stay'
    Clear-RoboGoLog
    Assert-Equal '' $ui.TxtLog.Text 'log box: can be cleared'

    # --- help: useful switches and setups ---
    Assert-Equal @(Get-RoboHelpSwitches).Count $ui.HelpSwitches.Children.Count 'help: one row per switch'
    Assert-Equal @(Get-RoboHelpSetups).Count $ui.HelpSetups.Children.Count 'help: one row per setup'
    $rowJ = @($ui.HelpSwitches.Children) | Where-Object { $_.Tag -eq '/J' } | Select-Object -First 1
    $rowFft = @($ui.HelpSwitches.Children) | Where-Object { $_.Tag -eq '/FFT' } | Select-Object -First 1
    $rowJ.IsChecked = $true
    Assert-Equal '/J' $ui.TxtExtra.Text 'help: ticking a switch adds it to EXTRA'
    Assert-True ((Get-CommandText $ui) -like '* /J') 'help: and the command follows'
    $rowJ.IsChecked = $false
    Assert-Equal '' $ui.TxtExtra.Text 'help: unticking removes it'
    $ui.TxtExtra.Text = '*.png /fft'
    Assert-Equal 'True|False' ([string]$rowFft.IsChecked + '|' + [string]$rowJ.IsChecked) 'help: the boxes follow what is typed in EXTRA'
    Invoke-RoboGoSetup 'setup.big'
    Assert-Equal '1|*.png /J' ($ui.TxtThreads.Text + '|' + $ui.TxtExtra.Text) 'setup: sets THREADS and swaps the setup switches, the rest of EXTRA stays'
    Invoke-RoboGoSetup 'setup.nas'
    Assert-Equal '8|True|*.png /FFT' ($ui.TxtThreads.Text + '|' + [string]$ui.ChkRestart.IsChecked + '|' + $ui.TxtExtra.Text) 'setup: NAS turns on Restartable and /FFT'
    Save-ElementPng $ui.HelpPanel (Join-Path $shots 'ui-help.png')
    Assert-Rendered (Join-Path $shots 'ui-help.png') 'render: the help panel is drawn'
    Invoke-RoboGoSetup 'setup.default'
    Assert-Equal '8|False|*.png' ($ui.TxtThreads.Text + '|' + [string]$ui.ChkRestart.IsChecked + '|' + $ui.TxtExtra.Text) 'setup: the default one undoes the others'
    $ui.TxtExtra.Text = ''
    $ui.TxtExtra.Text = '/IPG:50'
    Assert-Equal 'Extra switches: /IPG only works with 1 thread. Set THREADS to 1.' $ui.TxtProblem.Text 'help: a switch that clashes with THREADS says so at once'
    $ui.TxtExtra.Text = ''

    # --- live preview ---
    $ui.TxtSource.Text = 'C:\src dir\'
    $ui.TxtDest.Text = 'D:\'
    Assert-Equal 'robocopy "C:\src dir" D:\ /E /MT:8 /R:2 /W:5 /XJ' (Get-CommandText $ui) 'preview: follows the path fields'
    Assert-Equal 'Collapsed' $ui.TxtProblem.Visibility 'preview: no problem for valid input'
    $pieces = @($ui.CmdPanel.Children | ForEach-Object { $_.Text })
    Assert-Equal 'robocopy|"C:\|src dir"|D:\|/E|/MT:8|/R:2|/W:5|/XJ' ($pieces -join '|') 'preview: a switch is one unbreakable piece, a path may break after a backslash'
    $ui.ChkJunction.IsChecked = $false
    $ui.TxtXF.Text = '*.tmp'
    Assert-Equal 'robocopy "C:\src dir" D:\ /E /MT:8 /R:2 /W:5 /XF *.tmp' (Get-CommandText $ui) 'preview: follows check boxes and lists'
    $ui.ChkJunction.IsChecked = $true
    $ui.TxtXF.Text = ''

    # --- destructive mode ---
    $danger = $ui.Window.FindResource('Danger')
    $ui.RbMirror.IsChecked = $true
    Assert-True ((Get-CommandText $ui) -like '* /MIR *') 'mode: mirror adds /MIR'
    Assert-True ($ui.TxtModeHint.Text -like 'Mirror deletes*') 'mode: mirror shows its warning'
    Assert-Equal 'Visible' $ui.TxtModeHint.Visibility 'mode: the warning line appears'
    Assert-Equal 'False' $ui.ChkSub.IsEnabled 'mode: mirror locks the subfolders box'
    $mir = @($ui.CmdPanel.Children) | Where-Object { $_.Text -eq '/MIR' } | Select-Object -First 1
    Assert-True ([object]::ReferenceEquals($mir.Foreground, $danger)) 'mode: /MIR is drawn in the danger colour'
    Assert-True ([object]::ReferenceEquals($ui.TxtModeHint.Foreground, $danger)) 'mode: the warning is drawn in the danger colour'
    Assert-True ([object]::ReferenceEquals($ui.TapeEdge.BorderBrush, $danger)) 'mode: the command tape gets a danger edge'
    $ui.TxtSource.Text = 'D:\Photos\2026 Summer'
    $ui.TxtDest.Text = '\\nas\backup\Photos\2026 Summer'
    $ui.TxtXF.Text = '*.tmp; thumbs.db'
    Save-WindowPng $ui (Join-Path $shots 'ui-mirror.png')
    Assert-Rendered (Join-Path $shots 'ui-mirror.png') 'render: the mirror state is drawn'
    Assert-Equal '' (Get-ClippedControls $ui) 'size: nothing is clipped at the default size, even with the warning line and a two-line command'
    Assert-Equal 'Collapsed' ([string]$ui.BtnTape.Visibility) 'tape: a command of two lines needs no SHOW ALL'
    Assert-True ($ui.TxtLog.ActualHeight -ge 60) 'size: the log box keeps at least 60 units'

    # --- hiding and showing the log (the window is shown off screen since the render) ---
    $tall = $ui.Window.ActualHeight
    Switch-RoboGoLog
    $ui.Window.UpdateLayout()
    Assert-Equal 'Collapsed' $ui.TxtLog.Visibility 'log: HIDE LOG collapses the log box'
    Assert-Equal 'SHOW LOG' $ui.BtnToggleLog.Content 'log: the button offers to show it again'
    Assert-True ($ui.Window.ActualHeight -lt ($tall - 50)) 'log: the window shrinks to what is left'
    Switch-RoboGoLog
    $ui.Window.UpdateLayout()
    Assert-Equal 'Visible' $ui.TxtLog.Visibility 'log: SHOW LOG brings the box back'
    Assert-Equal 'HIDE LOG' $ui.BtnToggleLog.Content 'log: the button offers to hide it again'
    Assert-Equal $tall $ui.Window.ActualHeight 'log: the window gets its height back'
    $ui.RbCopy.IsChecked = $true
    $ui.TxtXF.Text = ''
    Assert-Equal 'True' $ui.ChkSub.IsEnabled 'mode: copy unlocks the subfolders box'

    # --- problems ---
    $ui.TxtThreads.Text = 'abc'
    Assert-Equal 'Visible' $ui.TxtProblem.Visibility 'preview: a bad number shows a problem'
    Assert-Equal 'Threads must be a number from 1 to 128.' $ui.TxtProblem.Text 'preview: and names it'
    $ui.TxtThreads.Text = '8'
    Assert-Equal 'Collapsed' $ui.TxtProblem.Visibility 'preview: fixing it clears the problem'
    $ui.TxtSource.Text = Join-Path $root 'missing'
    $ui.TxtDest.Text = Join-Path $root 'dst'
    Start-RoboGoRun
    Assert-True ($null -eq $script:RoboGo.Job) 'run: a missing source does not start a job'
    Assert-Equal 'Source folder does not exist.' $ui.TxtProblem.Text 'run: and says why'

    # --- a real copy through the controller ---
    $src = Join-Path $root 'src'
    New-Item -ItemType Directory -Force -Path (Join-Path $src 'sub') | Out-Null
    foreach ($i in 1..12) { [System.IO.File]::WriteAllBytes((Join-Path $src ('f' + $i + '.bin')), (New-Object byte[] (50000 * $i))) }
    [System.IO.File]::WriteAllBytes((Join-Path $src 'sub\g.bin'), (New-Object byte[] 3000000))
    $ui.TxtSource.Text = $src
    Start-RoboGoRun
    Assert-True ($null -ne $script:RoboGo.Job) 'run: the job starts'
    Assert-Equal 'Scan' $script:RoboGo.Phase 'run: it begins with the scan'
    Assert-Equal 'Indeterminate' (Get-Taskbar $ui) 'taskbar: sweeping during the scan'
    $started = Read-RoboSettings
    Assert-Equal ($src + '|' + (Join-Path $root 'dst')) ($started.RecentSources[0] + '|' + $started.RecentDestinations[0]) 'recent: a started job files its two paths'
    Assert-Equal $src $started.Last.Source 'restore: and the fields are saved at that moment'
    Assert-Equal 'False' $ui.BtnRun.IsEnabled 'run: inputs are locked while busy'
    Assert-Equal 'True' $ui.BtnCancel.IsEnabled 'run: cancel is available'
    Step-UntilIdle
    Assert-True ($null -eq $script:RoboGo.Job) 'run: the job finishes'
    Assert-Equal '100%' $ui.TxtPercent.Text 'run: ends at 100%'
    Assert-Equal 100 $ui.Bar.Value 'run: the bar is full'
    Assert-Equal '13 / 13' $ui.TxtFiles.Text 'run: file counter'
    Assert-True ($ui.TxtStatus.Text -like 'Done. Files copied: 13 (6.6 MB).*') 'run: verdict in the status line'
    Assert-True ([object]::ReferenceEquals($ui.TxtStatus.Foreground, $ui.Window.FindResource('Ok'))) 'run: the verdict is drawn in the ok colour'
    Assert-Equal 'TOOK' $ui.LblEta.Text 'run: the ETA cell turns into the elapsed time'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'dst\sub\g.bin')) 'run: files really arrive'
    Assert-True ($ui.TxtLog.Text -like '> robocopy *') 'run: the log starts with the command'
    Assert-True ($ui.TxtLog.Text -like '*g.bin*') 'run: the log shows the copied files'
    Assert-Equal 'True' $ui.BtnRun.IsEnabled 'run: inputs are unlocked afterwards'
    Assert-Equal 'True|True' ([string]$ui.BtnRecentSource.IsEnabled + '|' + [string]$ui.BtnRecentDest.IsEnabled) 'recent: the arrows are on after the first job'
    Assert-Equal 'None' (Get-Taskbar $ui) 'taskbar: no progress left after a good end'
    Assert-Equal 'ok' ($script:Signals -join ',') 'done signal: one signal for the finished job, the window is not the active one'
    Assert-True ($ui.TxtLog.Text -match 'Free space in the destination: \d') 'free space: the room of the destination is written into the log'
    Assert-Equal 0 $script:Asked.Count 'free space: enough room, no question'
    Assert-Equal 'False' $ui.ChkKeepLog.IsChecked 'logs: keeping log files is off by default'
    Assert-Equal 'Collapsed' $ui.BtnOpenLog.Visibility 'logs: no OPEN LOG without a kept file'
    Assert-Equal $workingLogsBefore (Get-WorkingLogCount) 'logs: the working log is gone when the job is over'
    Assert-True (-not (Test-Path -LiteralPath (Get-RoboKeptLogDir))) 'logs: nothing is kept'
    Save-WindowPng $ui (Join-Path $shots 'ui-done.png')
    Assert-Rendered (Join-Path $shots 'ui-done.png') 'render: the finished state is drawn'

    # --- COPY and COPY LOG ---
    Copy-RoboGoCommand
    Assert-Equal (Get-RoboCommandLine (Get-RoboGoOptions $ui)) $script:Clip 'copy: COPY hands the command to the clipboard'
    Assert-Equal 'Command copied to the clipboard.' $ui.TxtStatus.Text 'copy: and says so'
    Copy-RoboGoLog
    Assert-True ($script:Clip -like '> robocopy *g.bin*== Done. Files copied: 13 *') 'copy log: COPY LOG hands over what the log box shows'
    Assert-Equal 'Log copied to the clipboard.' $ui.TxtStatus.Text 'copy log: and says so'
    $script:Clip = ''
    Clear-RoboGoLog
    Copy-RoboGoLog
    Assert-Equal '' $script:Clip 'copy log: an empty log box leaves the clipboard alone'

    # --- a mirror asks first ---
    $ui.RbMirror.IsChecked = $true
    $ui.TxtDest.Text = Join-Path $root 'dstm'
    $script:Answer = $false
    Start-RoboGoRun
    Assert-True ($null -eq $script:RoboGo.Job) 'question: a mirror that is not confirmed does not start'
    Assert-Equal 1 $script:Asked.Count 'question: it was asked once'
    Assert-True (($script:Asked[0] -like 'Mirror deletes*') -and $script:Asked[0].Contains($src) -and $script:Asked[0].Contains((Join-Path $root 'dstm'))) 'question: with the warning and both folders'
    $script:Answer = $true
    Start-RoboGoRun
    Step-UntilIdle
    Assert-True ($ui.TxtStatus.Text -like 'Done. Files copied: 13 *') 'question: confirmed, it runs'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'dstm\sub\g.bin')) 'question: and copies'
    $ui.RbCopy.IsChecked = $true
    $script:Asked.Clear()

    # --- a destination that is too small ---
    $script:FakeFree = 1000
    $script:Answer = $false
    $ui.TxtDest.Text = Join-Path $root 'dstfull'
    $signalsBefore = $script:Signals.Count
    Start-RoboGoRun
    Step-UntilIdle
    Assert-True ($null -eq $script:RoboGo.Job) 'free space: declined, the job is over after the scan'
    Assert-True (($script:Asked.Count -eq 1) -and ($script:Asked[0] -like 'The job needs 6.6 MB, but the destination has only 1000 B free.*Run it anyway?')) 'free space: the question names what is needed and what is there'
    Assert-Equal 'Not started. The job needs 6.6 MB, the destination has 1000 B free.' $ui.TxtStatus.Text 'free space: the status line says why nothing ran'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'dstfull'))) 'free space: nothing was copied'
    Assert-Equal 'True|False|None' (([string]$ui.BtnRun.IsEnabled, [string]$ui.Bar.IsIndeterminate, (Get-Taskbar $ui)) -join '|') 'free space: the window is idle again'
    Assert-Equal $workingLogsBefore (Get-WorkingLogCount) 'free space: the log of the scan is gone'
    Assert-Equal $signalsBefore $script:Signals.Count 'free space: no done signal for a job that never ran'
    $script:Answer = $true
    Start-RoboGoRun
    Step-UntilIdle
    Assert-True (($script:Asked.Count -eq 2) -and ($ui.TxtStatus.Text -like 'Done. Files copied: 13 *')) 'free space: with a yes it runs anyway'
    $script:FakeFree = $null
    $script:Asked.Clear()

    # --- dry run ---
    $ui.TxtDest.Text = Join-Path $root 'dst2'
    Start-RoboGoRun -DryRun
    Assert-Equal 'DryRun' $script:RoboGo.Phase 'dry run: skips the scan'
    Step-UntilIdle
    Assert-True ($ui.TxtStatus.Text -like 'Dry run, nothing was changed. Files to copy: 13 *') 'dry run: verdict'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $root 'dst2'))) 'dry run: nothing is written'
    Assert-Equal '--' $ui.TxtPercent.Text 'dry run: no percent'
    Assert-Equal '13' $ui.TxtFiles.Text 'dry run: counts the files it listed'

    # --- a slow copy: live numbers, then cancel ---
    [System.IO.File]::WriteAllBytes((Join-Path $src 'a-slow.bin'), (New-Object byte[] 20000000))
    $ui.TxtDest.Text = Join-Path $root 'dst3'
    $ui.TxtThreads.Text = '1'
    $ui.TxtExtra.Text = '/IPG:200'
    Start-RoboGoRun
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while (($null -ne $script:RoboGo.Job) -and ($clock.Elapsed.TotalSeconds -lt 15) -and (($script:RoboGo.Phase -ne 'Run') -or ($ui.Bar.Value -lt 5))) {
        Step-RoboGo
        Start-Sleep -Milliseconds 40
    }
    Assert-Equal 'Run' $script:RoboGo.Phase 'live: the run phase follows the scan'
    Assert-Equal 'False' $ui.Bar.IsIndeterminate 'live: the bar shows a real share after a scan'
    Assert-True (($ui.Bar.Value -ge 5) -and ($ui.Bar.Value -lt 100)) 'live: the bar is somewhere in the middle'
    Assert-True ($ui.TxtPercent.Text -match '^\d+\.\d%$') 'live: percent with a decimal point'
    Assert-True ($ui.TxtData.Text -like '* / 25.7 MB') 'live: data counter shows done and total'
    Assert-True ($ui.TxtCurrent.Text -like '*a-slow.bin') 'live: the current file is shown'
    Assert-Equal 'Normal' (Get-Taskbar $ui) 'taskbar: a real share during the copy'
    Assert-True (($ui.Window.TaskbarItemInfo.ProgressValue -ge 0.05) -and ($ui.Window.TaskbarItemInfo.ProgressValue -lt 1)) 'taskbar: and it follows the bar'
    Save-WindowPng $ui (Join-Path $shots 'ui-running.png')
    Assert-Rendered (Join-Path $shots 'ui-running.png') 'render: the running state is drawn'

    # --- the command is four lines long here: the tape shows two ---
    $lineHeight = $ui.CmdPanel.Children[0].DesiredSize.Height
    Assert-Equal 'Visible|SHOW ALL' ([string]$ui.BtnTape.Visibility + '|' + [string]$ui.BtnTape.Content) 'tape: a long command gets SHOW ALL'
    Assert-True (($ui.TapeClip.ActualHeight -le (2 * $lineHeight + 1)) -and ($ui.CmdPanel.Children.Count -gt 12)) 'tape: only two lines of it are shown'
    Assert-Equal 'Visible' ([string]$ui.TapeMore.Visibility) 'tape: three dots mark the place where it is cut'
    Switch-RoboGoTape
    $ui.Window.UpdateLayout()
    Assert-Equal 'SHOW LESS' $ui.BtnTape.Content 'tape: the button turns into SHOW LESS'
    Assert-Equal 'Collapsed' ([string]$ui.TapeMore.Visibility) 'tape: no dots on a whole command'
    Assert-True ($ui.TapeClip.ActualHeight -ge (3 * $lineHeight - 1)) 'tape: and the whole command is there'
    Switch-RoboGoTape
    $ui.Window.UpdateLayout()
    Assert-True ($ui.TapeClip.ActualHeight -le (2 * $lineHeight + 1)) 'tape: back to two lines'
    Assert-True ($ui.TxtLog.ActualHeight -ge 60) 'tape: which leaves the log box its room even with long paths'

    Stop-RoboGoRun
    Step-UntilIdle 15
    Assert-True ($null -eq $script:RoboGo.Job) 'cancel: the job ends'
    Assert-Equal 'warn' $script:Signals[$script:Signals.Count - 1] 'done signal: a cancelled job signals a warning'
    Assert-True ($ui.TxtStatus.Text -like 'Cancelled.*') 'cancel: verdict'
    Assert-True ($ui.TxtPercent.Text -ne '100%') 'cancel: never claims 100%'
    Assert-Equal 'True' $ui.BtnRun.IsEnabled 'cancel: inputs are unlocked'

    # --- a file that cannot be read: FAILED and the view of the failures ---
    $ui.TxtDest.Text = Join-Path $root 'dstfail'
    $ui.TxtExtra.Text = ''
    $ui.TxtThreads.Text = '8'
    $ui.TxtRetries.Text = '0'
    $lock = [System.IO.File]::Open((Join-Path $src 'f1.bin'), 'Open', 'ReadWrite', 'None')
    try {
        Start-RoboGoRun
        Step-UntilIdle
    }
    finally {
        $lock.Close()
    }
    Assert-True ($ui.TxtStatus.Text -like 'Finished with errors. Files copied: 13 *FAILED: 1.*') 'failed: the verdict counts the failure'
    Assert-Equal 'Visible|FAILED: 1' ([string]$ui.BtnFailed.Visibility + '|' + [string]$ui.BtnFailed.Content) 'failed: the button appears with the number'
    Assert-Equal 'Error' (Get-Taskbar $ui) 'taskbar: red after a job with failures'
    Assert-Equal 'error' $script:Signals[$script:Signals.Count - 1] 'done signal: a failed job signals an error'
    Assert-True ($ui.TxtLog.Text -like '*g.bin*') 'failed: the log box still shows the whole log'
    Switch-RoboGoFailed
    $failedLines = @($ui.TxtLog.Text -split [Environment]::NewLine | Where-Object { $_ -ne '' })
    Assert-Equal 2 $failedLines.Count 'failed: the view lists the failure and nothing else, on two short lines'
    Assert-True ($failedLines[0] -like 'Copying File *\f1.bin') 'failed: first what was being done with which file'
    Assert-True ($failedLines[1] -match '^    \d+ \(0x[0-9A-Fa-f]{8}\)  \S') 'failed: below it, indented, the error code and what Windows said'
    Assert-Equal 'FULL LOG' $ui.BtnFailed.Content 'failed: the button offers the way back'
    Copy-RoboGoLog
    Assert-True (($script:Clip -like '*f1.bin*') -and ($script:Clip -notlike '*g.bin*')) 'failed: COPY LOG copies what is shown'
    Save-WindowPng $ui (Join-Path $shots 'ui-failed.png')
    Assert-Rendered (Join-Path $shots 'ui-failed.png') 'render: the failed view is drawn'
    Switch-RoboGoFailed
    Assert-True (($ui.TxtLog.Text -like '*g.bin*') -and ($ui.BtnFailed.Content -eq 'FAILED: 1')) 'failed: FULL LOG brings everything back'
    $ui.TxtRetries.Text = '2'

    # --- without a scan the total is unknown ---
    $ui.TxtDest.Text = Join-Path $root 'dst4'
    $ui.TxtExtra.Text = ''
    $ui.ChkScan.IsChecked = $false
    $ui.ChkKeepLog.IsChecked = $true
    Assert-Equal 'True' (Read-RoboSettings).KeepLog 'logs: ticking Keep log file is saved'
    # a limit far below the size of any log, so the one that is about to be kept is "too big"
    $script:RoboGo.Settings.LogFileMaxMB = 0.001
    Start-RoboGoRun
    Assert-Equal 'Run' $script:RoboGo.Phase 'no scan: goes straight to the run'
    Assert-Equal 'Collapsed' ([string]$ui.BtnFailed.Visibility) 'failed: a new job starts without the button'
    Assert-Equal 'True' $ui.Bar.IsIndeterminate 'no scan: the bar sweeps'
    Step-UntilIdle
    Assert-True ($ui.TxtStatus.Text -like 'Done. Files copied: 14 *') 'no scan: still finishes with a verdict'
    Assert-Equal '100%' $ui.TxtPercent.Text 'no scan: ends at 100%'
    Assert-Equal '14' $ui.TxtFiles.Text 'no scan: file counter without a total'
    $keptLogs = @(Get-ChildItem -LiteralPath (Get-RoboKeptLogDir) -Filter '*.log' -File)
    Assert-Equal 1 $keptLogs.Count 'logs: with Keep log file on, the log lands in the logs folder next to the program'
    Assert-Equal 'Visible' $ui.BtnOpenLog.Visibility 'logs: OPEN LOG appears'
    Assert-True ($ui.TxtLog.Text.Contains($keptLogs[0].FullName)) 'logs: the log box names the saved file'
    Assert-True ($ui.TxtLog.Text -like '*bigger than 0.001 MB*next start*') 'logs: a kept log above the limit for one file says that the next start removes it'
    $script:RoboGo.Settings.LogFileMaxMB = 50
    Assert-Equal $workingLogsBefore (Get-WorkingLogCount) 'logs: and nothing stays in TEMP'
    Assert-Equal '' (Get-ClippedControls $ui) 'size: nothing is clipped after a job either'

    # --- a settings file that cannot be written (a read-only program folder) ---
    $settingsFile = Get-Item -LiteralPath (Get-RoboSettingsPath)
    $settingsFile.IsReadOnly = $true
    $ui.ChkKeepLog.IsChecked = $false
    Assert-Equal 'The setting could not be saved: the RoboGo folder is not writable.' $ui.TxtStatus.Text 'settings: a choice that cannot be saved is reported'
    Assert-Equal 'True' (Read-RoboSettings).KeepLog 'settings: and the file is left as it was'
    $settingsFile.IsReadOnly = $false
    $ui.TxtThreads.Text = '4'
    Assert-True ((Get-CommandText $ui) -like '* /MT:4 *') 'settings: the window keeps working after that'

    # --- the window on the taskbar: one identity for pin and window ---
    Assert-True (Set-RoboTaskbarIdentity $ui.Window) 'identity: the window takes its taskbar identity'
    $identity = (Get-RoboTaskbarIdentity $ui.Window) -split '\|'
    Assert-Equal 'Czak89.RoboGo|RoboGo' ($identity[0] + '|' + $identity[2]) 'identity: application id and display name'
    Assert-Equal ('"' + (Get-RoboLauncherPath) + '"') $identity[1] 'identity: a pin of the window starts the launcher'
    Assert-True ($identity[3] -like '*\RoboGo.ico,0') 'identity: with the RoboGo icon'
    Clear-RoboTaskbarIdentity $ui.Window
    Assert-Equal '|||' (Get-RoboTaskbarIdentity $ui.Window) 'identity: cleared again before the window goes'

    # --- closing remembers the fields and the place, but never the mode ---
    $ui.RbMirror.IsChecked = $true
    $ui.TxtXD.Text = 'cache'
    $lastSource = $ui.TxtSource.Text
    $script:RoboGo.Timer.Stop()
    $ui.Window.Close()
    $saved = Read-RoboSettings
    Assert-Equal ($lastSource + '|cache|4') (($saved.Last.Source, $saved.Last.ExcludeDirs, $saved.Last.Threads) -join '|') 'close: the fields are saved'
    Assert-True (($null -ne $saved.Window) -and ($saved.Window.Width -eq 760)) 'close: and the window rectangle'
    Assert-True ((Get-Content -LiteralPath (Get-RoboSettingsPath) -Raw) -notmatch 'Mirror|"Mode"') 'close: the mode is not written anywhere'

    # --- a new window picks up the saved choices ---
    $saved.Language = 'xx'
    $saved.KeepLog = $true
    [void](Save-RoboSettings $saved)
    $second = New-RoboGoWindow
    Initialize-RoboGoWindow $second
    Assert-Equal 'XX|True|OD' ([string]$second.BtnLang.Content + '|' + [string]$second.ChkKeepLog.IsChecked + '|' + $second.LblFrom.Text) 'settings: language and Keep log file are restored at the next start'
    Assert-Equal ($lastSource + '|cache|True') (($second.TxtSource.Text, $second.TxtXD.Text, [string]$second.RbCopy.IsChecked) -join '|') 'restore: the fields are back, and the mode is COPY although the last session ended on MIRROR'
    Assert-True (-not (Restore-RoboGoWindow $second $saved.Window)) 'placement: the off-screen spot of the test window is not taken over'
    $script:RoboGo.Timer.Stop()
    [void](Set-RoboLanguage 'en')
    Write-Host ('       screenshots: ' + $shots)
}
finally {
    # a test that broke off in the middle of a job must not leave robocopy running
    if (($null -ne $script:RoboGo) -and ($null -ne $script:RoboGo.Job)) {
        Stop-RoboJob $script:RoboGo.Job
        [void](Close-RoboJobLog $script:RoboGo.Job)
    }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    if (Test-Path -LiteralPath $env:ROBOGO_HOME) { Remove-Item -LiteralPath $env:ROBOGO_HOME -Recurse -Force }
    $env:ROBOGO_SENDTO = $null
}

exit (Complete-Tests 'Ui')
