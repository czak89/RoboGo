# Window tests. Nothing is shown on screen: the window is loaded, driven through its
# controls, run against real robocopy, and rendered to PNG files for review.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$app = Join-Path $PSScriptRoot '..\RoboGo.ps1'
. $app -NoUI

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
    $ui = New-RoboGoWindow
    Assert-True ($null -ne $ui.Window) 'window: the XAML loads and every named control exists'
    Initialize-RoboGoWindow $ui
    Assert-Equal ('v' + $script:RoboGoVersion) $ui.TxtVersion.Text 'window: shows the version'
    Assert-Equal 'Ready.' $ui.TxtStatus.Text 'window: starts idle'
    Assert-Equal 'False' $ui.BtnCancel.IsEnabled 'window: cancel is off while idle'
    Assert-Equal 'Collapsed' $ui.TxtProblem.Visibility 'preview: empty paths do not nag before the first run'

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
    Assert-True ($ui.TxtModeHint.Text -like 'Copy adds*') 'mode: copy explains itself'

    # --- destructive mode ---
    $danger = $ui.Window.FindResource('Danger')
    $ui.RbMirror.IsChecked = $true
    Assert-True ((Get-CommandText $ui) -like '* /MIR *') 'mode: mirror adds /MIR'
    Assert-True ($ui.TxtModeHint.Text -like 'Mirror deletes*') 'mode: mirror shows its warning'
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
    Assert-Equal 'False' $ui.BtnRun.IsEnabled 'run: inputs are locked while busy'
    Assert-Equal 'True' $ui.BtnCancel.IsEnabled 'run: cancel is available'
    Step-UntilIdle
    Assert-True ($null -eq $script:RoboGo.Job) 'run: the job finishes'
    Assert-Equal '100%' $ui.TxtPercent.Text 'run: ends at 100%'
    Assert-Equal 100 $ui.Bar.Value 'run: the bar is full'
    Assert-Equal '13 / 13' $ui.TxtFiles.Text 'run: file counter'
    Assert-True ($ui.TxtStatus.Text -like 'Done. Copied 13 file(s), 6.6 MB*') 'run: verdict in the status line'
    Assert-True ([object]::ReferenceEquals($ui.TxtStatus.Foreground, $ui.Window.FindResource('Ok'))) 'run: the verdict is drawn in the ok colour'
    Assert-Equal 'TOOK' $ui.LblEta.Text 'run: the ETA cell turns into the elapsed time'
    Assert-True (Test-Path -LiteralPath (Join-Path $root 'dst\sub\g.bin')) 'run: files really arrive'
    Assert-True ($ui.TxtLog.Text -like '> robocopy *') 'run: the log starts with the command'
    Assert-True ($ui.TxtLog.Text -like '*g.bin*') 'run: the log shows the copied files'
    Assert-Equal 'True' $ui.BtnRun.IsEnabled 'run: inputs are unlocked afterwards'
    Assert-Equal 'True' $ui.BtnOpenLog.IsEnabled 'run: the log file can be opened'
    Save-WindowPng $ui (Join-Path $shots 'ui-done.png')
    Assert-Rendered (Join-Path $shots 'ui-done.png') 'render: the finished state is drawn'

    # --- dry run ---
    $ui.TxtDest.Text = Join-Path $root 'dst2'
    Start-RoboGoRun -DryRun
    Assert-Equal 'DryRun' $script:RoboGo.Phase 'dry run: skips the scan'
    Step-UntilIdle
    Assert-True ($ui.TxtStatus.Text -like 'Dry run, nothing was changed. Would copy 13 file(s)*') 'dry run: verdict'
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
    Save-WindowPng $ui (Join-Path $shots 'ui-running.png')
    Assert-Rendered (Join-Path $shots 'ui-running.png') 'render: the running state is drawn'
    Stop-RoboGoRun
    Step-UntilIdle 15
    Assert-True ($null -eq $script:RoboGo.Job) 'cancel: the job ends'
    Assert-True ($ui.TxtStatus.Text -like 'Cancelled.*') 'cancel: verdict'
    Assert-True ($ui.TxtPercent.Text -ne '100%') 'cancel: never claims 100%'
    Assert-Equal 'True' $ui.BtnRun.IsEnabled 'cancel: inputs are unlocked'

    # --- without a scan the total is unknown ---
    $ui.TxtDest.Text = Join-Path $root 'dst4'
    $ui.TxtExtra.Text = ''
    $ui.ChkScan.IsChecked = $false
    Start-RoboGoRun
    Assert-Equal 'Run' $script:RoboGo.Phase 'no scan: goes straight to the run'
    Assert-Equal 'True' $ui.Bar.IsIndeterminate 'no scan: the bar sweeps'
    Step-UntilIdle
    Assert-True ($ui.TxtStatus.Text -like 'Done. Copied 14 file(s)*') 'no scan: still finishes with a verdict'
    Assert-Equal '100%' $ui.TxtPercent.Text 'no scan: ends at 100%'
    Assert-Equal '14' $ui.TxtFiles.Text 'no scan: file counter without a total'

    $script:RoboGo.Timer.Stop()
    $ui.Window.Close()
    Write-Host ('       screenshots: ' + $shots)
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

exit (Complete-Tests 'Ui')
