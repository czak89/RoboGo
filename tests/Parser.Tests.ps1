# Tests for the log parser. Sample lines have the shapes captured from real robocopy runs.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$app = Join-Path $PSScriptRoot '..\RoboGo.ps1'
. $app -NoUI

$T = [string][char]9
$CR = [string][char]13
$LF = [string][char]10

function New-FileLine {
    param([string]$Class, [long]$Size, [string]$Path)
    return ($T + $Class + $T + $T + ([string]$Size).PadLeft(8) + $T + $Path)
}
function New-DirLine {
    param([string]$Class, [int]$Count, [string]$Path)
    return ($T + $Class + ([string]$Count).PadLeft(10) + $T + $Path)
}

# --- splitting raw text into lines ---
$r = Split-RoboLogText ('a' + $CR + $LF + 'b' + $CR + ' 10%' + $CR + ' 20%')
Assert-Equal 'a|b| 10%| 20%' ($r.Lines -join '|') 'split: CR and LF both end a line, a trailing percent is complete'
Assert-Equal '' $r.Rest 'split: nothing is left over after a percent'
$r = Split-RoboLogText ('x' + $CR + $LF + $T + 'partial')
Assert-Equal 'x' ($r.Lines -join '|') 'split: complete lines are returned'
Assert-Equal ($T + 'partial') $r.Rest 'split: an unfinished line is kept for the next read'
$r = Split-RoboLogText 'abc'
Assert-Equal 0 $r.Lines.Count 'split: text without a line end gives no lines'
Assert-Equal 'abc' $r.Rest 'split: and is kept whole'
$r = Split-RoboLogText ('done' + $CR + $LF)
Assert-Equal 'done' ($r.Lines -join '|') 'split: a terminated line is complete'
Assert-Equal '' $r.Rest 'split: with nothing left over'
$r = Split-RoboLogText ''
Assert-Equal 0 $r.Lines.Count 'split: empty text'

# --- one thread: file line, partial percents, 100% ---
$s = New-RoboProgress -Threads 1 -DestinationPath 'C:\d'
Update-RoboProgress $s @(
    (New-DirLine '  New Dir ' 2 'C:\s\'),
    (New-FileLine '    New File  ' 1002 'C:\s\a.txt'),
    '100%  ',
    (New-FileLine '    New File  ' 16777216 'C:\s\mid.bin'),
    '  6.2%',
    ' 50.0%'
)
Assert-Equal 1 $s.CompletedFiles 'single: the first file completes at 100%'
Assert-Equal 1002 $s.CompletedBytes 'single: completed bytes'
Assert-Equal 8389610 ([long](Get-RoboDoneBytes $s)) 'single: done bytes include half of the running file'
Assert-Equal 'C:\s\mid.bin' $s.CurrentFile 'single: current file'
Assert-Equal 2 $s.SeenFiles 'single: files seen'
Assert-Equal 16778218 $s.SeenBytes 'single: bytes seen'
Update-RoboProgress $s @('100%  ')
Assert-Equal 2 $s.CompletedFiles 'single: the second file completes'
Assert-Equal 16778218 $s.CompletedBytes 'single: all bytes completed'
Assert-Equal 0 $s.Pending.Count 'single: nothing pending at the end'
Update-RoboProgress $s @((New-FileLine '    New File  ' 1000 'C:\s\c.bin'), ' 12,5%')
Assert-Equal 16778343 ([long](Get-RoboDoneBytes $s)) 'single: a decimal comma in the percent is understood'

# --- failure and retry: the file line is printed again, the file never reaches 100% ---
$err = '2026/10/06 04:19:35 ERROR 32 (0x00000020) Copying File C:\s\a.txt'
$s = New-RoboProgress -Threads 1
Update-RoboProgress $s @(
    (New-FileLine '    Newer     ' 3002 'C:\s\a.txt'),
    $err,
    'Proces nie moze uzyskac dostepu do pliku.',
    'Waiting 1 seconds... Retrying...',
    (New-FileLine '    Newer     ' 3002 'C:\s\a.txt'),
    $err,
    'ERROR: RETRY LIMIT EXCEEDED.',
    (New-DirLine '          ' 1 'C:\s\sub\'),
    (New-FileLine '    New File  ' 500 'C:\s\sub\b.txt'),
    '100%  '
)
Assert-Equal 2 $s.Errors 'retry: both error lines are counted'
Assert-Equal 2 $s.SeenFiles 'retry: a retried file is seen once'
Assert-Equal 1 $s.CompletedFiles 'retry: the failed file is not counted as copied'
Assert-Equal 500 $s.CompletedBytes 'retry: only the good file adds bytes'
Assert-True ($s.LastError -like '*ERROR 32*') 'retry: the last error line is kept'

# --- extra items in the destination are not copies ---
$s = New-RoboProgress -Threads 1 -DestinationPath 'C:\d'
Update-RoboProgress $s @(
    (New-DirLine '*EXTRA Dir ' -1 'C:\d\extra dir\'),
    (New-FileLine '  *EXTRA File ' 3 'C:\d\extra dir\x.txt'),
    (New-FileLine '  *EXTRA File ' 3 'C:\d\extra.txt'),
    (New-FileLine '  Sonstiges ' 7 'C:\D\other.txt'),
    (New-FileLine '    Newer     ' 2002 'C:\s\a.txt'),
    '100%  '
)
Assert-Equal 1 $s.ExtraDirs 'extras: starred folder line'
Assert-Equal 3 $s.ExtraFiles 'extras: starred lines plus one recognised by its location under the destination'
Assert-Equal 1 $s.SeenFiles 'extras: are not seen as files to copy'
Assert-Equal 1 $s.CompletedFiles 'extras: the real copy still completes'
Assert-Equal 2002 $s.CompletedBytes 'extras: and adds its bytes'

# --- several threads: lines can interleave ---
$lines = @((New-FileLine 'New File' 100 'C:\s\a'), (New-FileLine 'New File' 200 'C:\s\b'), '100%  ', '100%  ')
$s = New-RoboProgress -Threads 8
Update-RoboProgress $s $lines
Assert-Equal 2 $s.CompletedFiles 'threads: interleaved lines still complete both files'
Assert-Equal 300 $s.CompletedBytes 'threads: with all their bytes'
$s = New-RoboProgress -Threads 1
Update-RoboProgress $s $lines
Assert-Equal 1 $s.CompletedFiles 'single: a file replaced before reaching 100% is not counted'
Assert-Equal 200 $s.CompletedBytes 'single: only the finished file adds bytes'

# --- job summary, including 12-digit byte counts ---
$s = New-RoboProgress
Update-RoboProgress $s @(
    '------------------------------------------------------------------------------',
    '                  Total       Copied   Skipped  Mismatch    FAILED    Extras',
    '    Dirs :            1            1         0         0         0         0',
    '   Files :            4            2         1         0         1         3',
    '   Bytes : 164282499072 164282499072         0         0      3002         6',
    '   Times :      0:00:00      0:00:00                       0:00:00   0:00:00',
    '   Speed :           28 937 106 Bytes/sec.',
    '   Ended : wtorek, 6 pazdziernika 2026 04:19:32'
)
Assert-True ($null -ne $s.Summary) 'summary: found'
Assert-Equal 1 $s.Summary.Dirs.Total 'summary: dirs total'
Assert-Equal 4 $s.Summary.Files.Total 'summary: files total'
Assert-Equal 2 $s.Summary.Files.Copied 'summary: files copied'
Assert-Equal 1 $s.Summary.Files.Skipped 'summary: files skipped'
Assert-Equal 1 $s.Summary.Files.Failed 'summary: files failed'
Assert-Equal 3 $s.Summary.Files.Extras 'summary: files extra'
Assert-Equal 164282499072 $s.Summary.Bytes.Copied 'summary: 12-digit byte count'
Assert-Equal 3002 $s.Summary.Bytes.Failed 'summary: failed bytes'

$s = New-RoboProgress
Update-RoboProgress $s @(
    '  Started : wtorek, 6 pazdziernika 2026 04:19:33',
    '   Source : C:\s\',
    '     Dest : C:\d\',
    '    Files : *.*',
    '  Options : *.* /FP /BYTES /S /E /DCOPY:DA /COPY:DAT /R:1 /W:1 '
)
Assert-Equal 0 $s.SummaryRows.Count 'summary: job header lines are not mistaken for summary rows'
Assert-True ($null -eq $s.Summary) 'summary: none yet'

# --- verdict ---
$sum = @{
    Dirs  = @{ Total = 3; Copied = 3; Skipped = 0; Mismatch = 0; Failed = 0; Extras = 1 }
    Files = @{ Total = 4; Copied = 4; Skipped = 0; Mismatch = 0; Failed = 0; Extras = 2 }
    Bytes = @{ Total = 67115170; Copied = 67115170; Skipped = 0; Mismatch = 0; Failed = 0; Extras = 6 }
}
$v = Get-RoboVerdict -ExitCode 1 -Summary $sum
Assert-Equal 'ok' $v.Level 'verdict: copied is ok'
Assert-Equal 'Done. Copied 4 file(s), 64.0 MB, 3 extra item(s) in the destination left alone.' $v.Text 'verdict: copied, extras untouched'
$v = Get-RoboVerdict -ExitCode 3 -Summary $sum -Mirror
Assert-Equal 'Done. Copied 4 file(s), 64.0 MB, 3 extra item(s) deleted from the destination.' $v.Text 'verdict: mirror deleted the extras'
$v = Get-RoboVerdict -ExitCode 3 -Summary $sum -DryRun -Mirror
Assert-Equal 'Dry run, nothing was changed. Would copy 4 file(s), 64.0 MB, 3 extra item(s) would be deleted from the destination.' $v.Text 'verdict: dry run of a mirror'

$bad = @{
    Dirs  = @{ Total = 3; Copied = 0; Skipped = 3; Mismatch = 0; Failed = 0; Extras = 0 }
    Files = @{ Total = 4; Copied = 0; Skipped = 3; Mismatch = 0; Failed = 1; Extras = 0 }
    Bytes = @{ Total = 16785522; Copied = 0; Skipped = 16782520; Mismatch = 0; Failed = 3002; Extras = 0 }
}
$v = Get-RoboVerdict -ExitCode 8 -Summary $bad
Assert-Equal 'error' $v.Level 'verdict: a failed copy is an error'
Assert-Equal 'Finished with errors. Copied 0 file(s), 0 B, 3 skipped, 1 FAILED. See the log for the files that failed.' $v.Text 'verdict: failure text'

$v = Get-RoboVerdict -ExitCode 0 -Summary $null
Assert-Equal 'ok' $v.Level 'verdict: nothing to do is ok'
Assert-Equal 'Nothing to copy, the destination is already up to date.' $v.Text 'verdict: nothing to do'
$v = Get-RoboVerdict -ExitCode 16 -Summary $null
Assert-Equal 'error' $v.Level 'verdict: exit 16 is fatal'
Assert-True ($v.Text -like 'Fatal error (robocopy exit code 16)*') 'verdict: fatal text names the exit code'
Assert-Equal 'error' (Get-RoboVerdict -ExitCode -1 -Summary $null).Level 'verdict: a killed process is an error unless cancelled'
$v = Get-RoboVerdict -ExitCode -1 -Summary $null -Cancelled
Assert-Equal 'warn' $v.Level 'verdict: cancelled is a warning'
Assert-Equal 'Cancelled. Files that were already copied stay in the destination.' $v.Text 'verdict: cancelled text'
Assert-Equal 'warn' (Get-RoboVerdict -ExitCode 5 -Summary $sum).Level 'verdict: mismatches are a warning'

exit (Complete-Tests 'Parser')
