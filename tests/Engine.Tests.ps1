# Integration tests: real robocopy runs inside a fresh folder under %TEMP%.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$app = Join-Path $PSScriptRoot '..\RoboGo.ps1'
. $app -NoUI

# --- speed meter (pure) ---
$m = New-RoboSpeedMeter
Add-RoboSpeedSample $m 0 0
Assert-Equal 0 (Get-RoboSpeed $m) 'speed: one sample is not enough'
Add-RoboSpeedSample $m 1000 1
Add-RoboSpeedSample $m 3000 2
Assert-Equal 1500 (Get-RoboSpeed $m) 'speed: bytes per second over the window'
Add-RoboSpeedSample $m 3000 20
Assert-Equal 0 (Get-RoboSpeed $m) 'speed: drops to zero when nothing moves'

# --- log housekeeping ---
$logDir = Join-Path ([System.IO.Path]::GetTempPath()) ('RoboGoLogTest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
try {
    foreach ($i in 1..5) {
        $file = Join-Path $logDir ('job' + $i + '.log')
        Set-Content -LiteralPath $file -Value 'x'
        (Get-Item -LiteralPath $file).LastWriteTime = (Get-Date).AddMinutes(-$i)
    }
    Set-Content -LiteralPath (Join-Path $logDir 'notes.txt') -Value 'x'
    Remove-RoboOldLogs -Keep 2 -Directory $logDir
    Assert-Equal 'job1.log|job2.log|notes.txt' ((Get-ChildItem -LiteralPath $logDir | Sort-Object Name | ForEach-Object { $_.Name }) -join '|') 'logs: only the newest log files are kept, other files are left alone'
}
finally {
    Remove-Item -LiteralPath $logDir -Recurse -Force
}

# --- helpers ---
$root = Join-Path ([System.IO.Path]::GetTempPath()) ('RoboGoTest-' + [guid]::NewGuid().ToString('N'))
# "zazolc" with its Polish diacritics plus one CJK character that OEM code page 852 cannot hold
$odd = 'za' + [char]0x017C + [char]0x00F3 + [char]0x0142 + [char]0x0107 + ' ' + [char]0x4E2D

function New-TestFile {
    param([string]$Path, [int]$Bytes)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $buffer = New-Object byte[] $Bytes
    (New-Object System.Random 42).NextBytes($buffer)
    [System.IO.File]::WriteAllBytes($Path, $buffer)
}
function Get-TreeStats {
    param([string]$Path)
    $files = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force)
    $bytes = [long]0
    foreach ($f in $files) { $bytes += $f.Length }
    return @{ Files = $files.Count; Bytes = $bytes }
}
function New-TestOptions {
    param([string]$Source, [string]$Destination, [int]$Threads = 1)
    $o = New-RoboOptions
    $o.Source = $Source
    $o.Destination = $Destination
    $o.Threads = $Threads
    $o.Retries = 1
    $o.Wait = 1
    return $o
}

try {
    $src = Join-Path $root 'src'
    New-TestFile (Join-Path $src 'a.txt') 1000
    New-TestFile (Join-Path $src 'sub one\b c.txt') 5000
    New-TestFile (Join-Path $src ($odd + '\' + $odd + '.txt')) 300
    New-TestFile (Join-Path $src 'big.bin') 25165824
    foreach ($i in 1..20) { New-TestFile (Join-Path $src ('many\f' + $i + '.dat')) (2000 * $i) }
    $want = Get-TreeStats $src
    Assert-Equal 24 $want.Files 'setup: 24 source files'

    # --- scan: totals without touching anything ---
    $dst = Join-Path $root 'dst'
    $job = Start-RoboJob (New-TestOptions $src $dst) 'Scan'
    [void](Wait-RoboJob $job)
    Assert-True ($null -ne $job.State.Summary) 'scan: the summary is parsed'
    Assert-Equal $want.Files $job.State.Summary.Files.Copied 'scan: number of files to copy'
    Assert-Equal $want.Bytes $job.State.Summary.Bytes.Copied 'scan: number of bytes to copy'
    Assert-True (-not (Test-Path -LiteralPath $dst)) 'scan: nothing is written'

    # --- run on one thread, slowed down so that progress can be observed ---
    $o = New-TestOptions $src $dst
    $o.Extra = '/IPG:30'
    $job = Start-RoboJob $o 'Run'
    $seen = New-Object System.Collections.Generic.List[double]
    $lines = Wait-RoboJob $job -OnTick { param($j) $seen.Add((Get-RoboDoneBytes $j.State)) }
    Assert-Equal 1 ($job.ExitCode -band 1) 'run: the exit code says files were copied'
    Assert-Equal 0 ($job.ExitCode -band 24) 'run: no failure bits in the exit code'
    Assert-Equal $want.Files $job.State.CompletedFiles 'run: every file reaches 100%'
    Assert-Equal $want.Bytes $job.State.CompletedBytes 'run: completed bytes match the tree'
    Assert-Equal $want.Bytes ([long](Get-RoboDoneBytes $job.State)) 'run: done bytes end at the total'
    Assert-Equal $want.Files $job.State.Summary.Files.Copied 'run: the summary agrees'
    Assert-Equal 0 $job.State.Errors 'run: no error lines'
    $got = Get-TreeStats $dst
    Assert-Equal $want.Files $got.Files 'run: the destination has every file'
    Assert-Equal $want.Bytes $got.Bytes 'run: the destination has every byte'
    Assert-True (Test-Path -LiteralPath (Join-Path $dst ($odd + '\' + $odd + '.txt'))) 'run: the file with non-ASCII characters arrives'
    Assert-True (@($lines | Where-Object { $_.Contains($odd) }).Count -gt 0) 'run: the log keeps characters outside the OEM code page'
    Assert-True (@($lines | Where-Object { $_.Trim().EndsWith('%') }).Count -eq 0) 'run: bare percent updates are filtered from the display lines'
    $mid = @($seen | Where-Object { ($_ -gt 0) -and ($_ -lt $want.Bytes) })
    Assert-True ($mid.Count -ge 3) 'run: progress is visible while copying, not only at the end'
    $ordered = $true
    for ($i = 1; $i -lt $seen.Count; $i++) { if ($seen[$i] -lt $seen[$i - 1]) { $ordered = $false } }
    Assert-True $ordered 'run: progress never goes backwards'
    Assert-True (Test-Path -LiteralPath $job.LogPath) 'run: the log file is kept'

    # --- second run: nothing to do ---
    $job = Start-RoboJob (New-TestOptions $src $dst) 'Run'
    [void](Wait-RoboJob $job)
    Assert-Equal 0 $job.ExitCode 'rerun: exit code 0'
    Assert-Equal 0 $job.State.Summary.Files.Copied 'rerun: nothing copied'
    Assert-True ((Get-RoboVerdict -ExitCode $job.ExitCode -Summary $job.State.Summary).Text -like 'Nothing to copy*') 'rerun: verdict says so'

    # --- eight threads ---
    $dstMt = Join-Path $root 'dst mt'
    $job = Start-RoboJob (New-TestOptions $src $dstMt 8) 'Run'
    [void](Wait-RoboJob $job)
    Assert-Equal $want.Bytes $job.State.Summary.Bytes.Copied 'threads: summary bytes'
    Assert-Equal $want.Files $job.State.CompletedFiles 'threads: every file is counted'
    Assert-Equal $want.Bytes $job.State.CompletedBytes 'threads: completed bytes match'
    Assert-Equal $want.Bytes (Get-TreeStats $dstMt).Bytes 'threads: the destination has every byte'

    # --- mirror: dry run first, then for real ---
    New-TestFile (Join-Path $dst 'extra.txt') 10
    New-TestFile (Join-Path $dst 'extra dir\x.txt') 10
    $o = New-TestOptions $src $dst
    $o.Mode = 'Mirror'
    $job = Start-RoboJob $o 'DryRun'
    [void](Wait-RoboJob $job)
    Assert-True (Test-Path -LiteralPath (Join-Path $dst 'extra.txt')) 'dry run: deletes nothing'
    Assert-Equal 2 $job.State.ExtraFiles 'dry run: lists the extra files'
    Assert-Equal 1 $job.State.ExtraDirs 'dry run: lists the extra folder'
    $v = Get-RoboVerdict -ExitCode $job.ExitCode -Summary $job.State.Summary -DryRun -Mirror
    Assert-True ($v.Text -like 'Dry run, nothing was changed.*3 extra item(s) would be deleted*') 'dry run: verdict announces the deletions'
    $job = Start-RoboJob $o 'Run'
    [void](Wait-RoboJob $job)
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $dst 'extra.txt'))) 'mirror: the extra file is deleted'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $dst 'extra dir'))) 'mirror: the extra folder is deleted'
    Assert-Equal 2 ($job.ExitCode -band 2) 'mirror: the exit code reports extras'

    # --- a locked source file fails after the retries ---
    Add-Content -LiteralPath (Join-Path $src 'a.txt') -Value 'changed'
    $lock = [System.IO.File]::Open((Join-Path $src 'a.txt'), 'Open', 'ReadWrite', 'None')
    try {
        $job = Start-RoboJob (New-TestOptions $src $dst) 'Run'
        [void](Wait-RoboJob $job)
    }
    finally {
        $lock.Close()
    }
    Assert-Equal 8 ($job.ExitCode -band 8) 'failure: the exit code reports a failed copy'
    Assert-True ($job.State.Errors -ge 1) 'failure: error lines are counted'
    Assert-Equal 1 $job.State.Summary.Files.Failed 'failure: the summary reports one failed file'
    Assert-Equal 0 $job.State.CompletedFiles 'failure: the locked file is not counted as copied'
    Assert-Equal 'error' (Get-RoboVerdict -ExitCode $job.ExitCode -Summary $job.State.Summary).Level 'failure: verdict is an error'

    # --- missing source: fatal ---
    $job = Start-RoboJob (New-TestOptions (Join-Path $root 'nope') $dst) 'Run'
    [void](Wait-RoboJob $job)
    Assert-Equal 16 $job.ExitCode 'missing source: exit code 16'
    Assert-True ($null -eq $job.State.Summary) 'missing source: no summary'
    Assert-True ($job.State.Errors -ge 1) 'missing source: the error line is counted'

    # --- cancel in the middle of a slow copy ---
    $dstCancel = Join-Path $root 'dst cancel'
    $o = New-TestOptions $src $dstCancel
    $o.Extra = '/IPG:200'
    $job = Start-RoboJob $o 'Run'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ((-not $job.Done) -and ($sw.ElapsedMilliseconds -lt 1500)) {
        [void](Read-RoboJob $job)
        Start-Sleep -Milliseconds 50
    }
    Assert-True (-not $job.Done) 'cancel: the slow copy is still running after 1.5 s'
    Stop-RoboJob $job
    $sw.Restart()
    while ((-not $job.Done) -and ($sw.ElapsedMilliseconds -lt 5000)) {
        [void](Read-RoboJob $job)
        Start-Sleep -Milliseconds 50
    }
    Assert-True $job.Done 'cancel: the job ends after Stop-RoboJob'
    Assert-True ((Get-TreeStats $dstCancel).Bytes -lt $want.Bytes) 'cancel: the copy really stopped early'
    Assert-Equal 'warn' (Get-RoboVerdict -ExitCode $job.ExitCode -Summary $job.State.Summary -Cancelled).Level 'cancel: verdict is a warning'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}

exit (Complete-Tests 'Engine')
