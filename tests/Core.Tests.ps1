# Tests for the pure helpers: paths, quoting, command line, validation, formatting.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
# The app keeps settings, kept logs and language files in its own folder. ROBOGO_HOME points
# it at a throwaway folder, so the tests never touch the real one.
$env:ROBOGO_HOME = Join-Path ([System.IO.Path]::GetTempPath()) ('RoboGoHomeTest-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $env:ROBOGO_HOME | Out-Null
$app = Join-Path $PSScriptRoot '..\RoboGo.ps1'
. $app -NoUI
$utf8 = New-Object System.Text.UTF8Encoding $false

# --- paths ---
Assert-Equal 'C:\data' (ConvertTo-RoboPath ' "C:\data\" ') 'path: trims spaces, quotes and the trailing backslash'
Assert-Equal 'D:\' (ConvertTo-RoboPath 'D:') 'path: a bare drive becomes its root'
Assert-Equal 'D:\' (ConvertTo-RoboPath 'D:\') 'path: a drive root keeps its backslash'
Assert-Equal '\\nas\share' (ConvertTo-RoboPath '\\nas\share\') 'path: a UNC share loses the trailing backslash'
Assert-Equal 'C:\a\b' (ConvertTo-RoboPath 'C:/a/b/') 'path: forward slashes are converted'
Assert-Equal '' (ConvertTo-RoboPath '   ') 'path: blank stays blank'
Assert-Equal '"C:\My Data"' (Format-RoboArgPath 'C:\My Data\') 'arg: quoted and never ending in backslash-quote'
Assert-Equal 'D:\' (Format-RoboArgPath 'D:\') 'arg: a drive root is written unquoted'
Assert-Equal '""' (Format-RoboArgPath '') 'arg: an empty path shows as empty quotes'
Assert-Equal 'C:\a\b.txt' (Get-RoboShortPath 'C:\a\b.txt' 100) 'short path: short paths are untouched'
Assert-Equal '...ile.txt' (Get-RoboShortPath 'C:\folder\file.txt' 10) 'short path: long paths keep their end'
Assert-Equal 'a|b c|d' ((Split-RoboList ' a; "b c" ;;d ') -join '|') 'list: split on semicolons, trimmed, blanks dropped'
Assert-Equal 0 (Split-RoboList '').Count 'list: empty text gives no items'
Assert-Equal 12 (ConvertTo-RoboInt ' 12 ') 'int: parses a trimmed number'
Assert-True ($null -eq (ConvertTo-RoboInt 'abc')) 'int: text that is not a number gives null'

# --- command line ---
$o = New-RoboOptions
$o.Source = 'C:\src dir\'
$o.Destination = 'D:\'
Assert-Equal 'robocopy "C:\src dir" D:\ /E /MT:8 /R:2 /W:5 /XJ' (Get-RoboCommandLine $o) 'cmd: defaults'
$o.Mode = 'Mirror'
$o.Threads = 1
$o.SkipJunctions = $false
Assert-Equal 'robocopy "C:\src dir" D:\ /MIR /R:2 /W:5' (Get-RoboCommandLine $o) 'cmd: mirror, one thread'
$o.Mode = 'Move'
Assert-Equal 'robocopy "C:\src dir" D:\ /E /MOVE /R:2 /W:5' (Get-RoboCommandLine $o) 'cmd: move with subfolders'
$o.Subfolders = $false
Assert-Equal 'robocopy "C:\src dir" D:\ /MOV /R:2 /W:5' (Get-RoboCommandLine $o) 'cmd: move without subfolders'

$o = New-RoboOptions
$o.Source = 'C:\a'
$o.Destination = 'C:\b'
$o.Subfolders = $false
$o.Threads = 1
$o.SkipJunctions = $false
$o.Restartable = $true
$o.OnlyNewer = $true
$o.ExcludeFiles = '*.tmp; thumbs.db;my file.txt'
$o.ExcludeDirs = 'node_modules;C:\a\old stuff\'
$o.Extra = ' /DCOPY:DAT '
Assert-Equal 'robocopy "C:\a" "C:\b" /R:2 /W:5 /Z /XO /XF *.tmp thumbs.db "my file.txt" /XD node_modules "C:\a\old stuff" /DCOPY:DAT' (Get-RoboCommandLine $o) 'cmd: every option, quoting inside the exclusion lists'

$o = New-RoboOptions
$o.Source = 'C:\a'
$o.Destination = 'C:\b'
Assert-Equal '"C:\a" "C:\b" /E /MT:8 /R:2 /W:5 /XJ /BYTES /FP /UNILOG:"C:\t\x.log"' (Get-RoboArguments $o 'Run' 'C:\t\x.log') 'args: run adds the tracking switches'
Assert-Equal '"C:\a" "C:\b" /E /MT:8 /R:2 /W:5 /XJ /L /NFL /NDL /NJH /BYTES /FP /UNILOG:"C:\t\x.log"' (Get-RoboArguments $o 'Scan' 'C:\t\x.log') 'args: scan is list-only and prints only the summary'
Assert-Equal '"C:\a" "C:\b" /E /MT:8 /R:2 /W:5 /XJ /L /BYTES /FP /UNILOG:"C:\t\x.log"' (Get-RoboArguments $o 'DryRun' 'C:\t\x.log') 'args: dry run is list-only'

$o.Mode = 'Mirror'
$o.Extra = '/purge *.jpg'
$parts = Get-RoboCommandParts $o
Assert-Equal 'exe path path danger switch switch switch switch danger value' (($parts | ForEach-Object { $_.Kind }) -join ' ') 'parts: every token has a kind, destructive switches are flagged'
Assert-Equal (Get-RoboCommandLine $o) (($parts | ForEach-Object { $_.Text }) -join ' ') 'parts: joined text equals the command line'

# --- validation ---
function Get-Problems {
    param($Options, [switch]$Disk)
    if ($Disk) { return ((Test-RoboOptions $Options) -join '|') }
    return ((Test-RoboOptions $Options -SkipFileSystem) -join '|')
}
$o = New-RoboOptions
Assert-Equal 'Pick a source folder.|Pick a destination folder.' (Get-Problems $o) 'validate: empty paths'
$o.Source = 'C:\a'
$o.Destination = 'C:\b'
Assert-Equal '' (Get-Problems $o) 'validate: a plain copy is fine'
$o.Destination = 'c:\A\'
Assert-Equal 'Source and destination are the same folder.' (Get-Problems $o) 'validate: same folder, ignoring case and trailing backslash'
$o.Destination = 'C:\a\backup'
Assert-Equal 'Destination is inside the source folder.' (Get-Problems $o) 'validate: destination inside source'
$o.Source = 'C:\a\b'
$o.Destination = 'C:\a'
Assert-Equal '' (Get-Problems $o) 'validate: copying up into a parent is allowed'
$o.Mode = 'Mirror'
Assert-Equal 'Mirror would delete the source, because it sits inside the destination.' (Get-Problems $o) 'validate: mirror into a parent is blocked'

$o = New-RoboOptions
$o.Source = 'C:\a'
$o.Destination = 'C:\b'
$o.Threads = 0
Assert-Equal 'Threads must be a number from 1 to 128.' (Get-Problems $o) 'validate: threads range'
$o.Threads = $null
$o.Retries = -1
$o.Wait = 99999
Assert-Equal 'Threads must be a number from 1 to 128.|Retries must be a number from 0 to 1000000.|Wait must be a number of seconds from 0 to 3600.' (Get-Problems $o) 'validate: missing and out-of-range numbers'

$o = New-RoboOptions
$o.Source = 'C:\a'
$o.Destination = 'C:\b'
$o.Extra = '/np /log+:x.txt /DCOPY:DAT'
Assert-Equal "Extra switches: /NP is not supported, RoboGo needs robocopy's standard log output.|Extra switches: /LOG is not supported, RoboGo needs robocopy's standard log output." (Get-Problems $o) 'validate: switches that break progress tracking'

$o = New-RoboOptions
$o.Source = Join-Path $env:TEMP 'RoboGo-no-such-folder-1234'
$o.Destination = 'C:\b'
Assert-Equal 'Source folder does not exist.' (Get-Problems $o -Disk) 'validate: missing source on disk'
$o.Source = $env:SystemRoot
$o.Destination = 'C:\RoboGo-no-such-destination'
Assert-Equal '' (Get-Problems $o -Disk) 'validate: existing source, new destination'

# --- danger ---
$o = New-RoboOptions
Assert-Equal '' (Get-RoboDanger $o) 'danger: copy is harmless'
$o.Mode = 'Mirror'
Assert-True ((Get-RoboDanger $o) -like 'Mirror deletes*') 'danger: mirror'
$o.Mode = 'Move'
Assert-True ((Get-RoboDanger $o) -like 'Move deletes*') 'danger: move'
$o.Mode = 'Copy'
$o.Extra = '*.jpg /purge'
Assert-True ((Get-RoboDanger $o) -like 'Mirror deletes*') 'danger: /PURGE typed into Extra counts'
$o.Extra = '/MOV'
Assert-True ((Get-RoboDanger $o) -like 'Move deletes*') 'danger: /MOV typed into Extra counts'

# --- formatting ---
Assert-Equal '0 B' (Format-RoboBytes 0) 'bytes: zero'
Assert-Equal '1023 B' (Format-RoboBytes 1023) 'bytes: below one KB'
Assert-Equal '1.0 KB' (Format-RoboBytes 1024) 'bytes: one KB'
Assert-Equal '1.5 KB' (Format-RoboBytes 1536) 'bytes: decimal point whatever the Windows culture is'
Assert-Equal '64.0 MB' (Format-RoboBytes 67115170) 'bytes: MB'
Assert-Equal '153.0 GB' (Format-RoboBytes 164282499072) 'bytes: GB'
Assert-Equal '5s' (Format-RoboDuration 5) 'duration: seconds'
Assert-Equal '1m 15s' (Format-RoboDuration 75) 'duration: minutes'
Assert-Equal '1h 02m' (Format-RoboDuration 3725) 'duration: hours'
Assert-Equal '--' (Format-RoboDuration -1) 'duration: unknown'

# --- /IPG and the preview variant of the validation ---
$o = New-RoboOptions
$o.Source = 'C:\a'
$o.Destination = 'C:\b'
$o.Extra = '/IPG:50'
Assert-Equal 'Extra switches: /IPG only works with 1 thread. Set THREADS to 1.' (Get-Problems $o) 'validate: /IPG with several threads is refused'
$o.Threads = 1
Assert-Equal '' (Get-Problems $o) 'validate: /IPG with one thread is fine'
$o = New-RoboOptions
$o.Threads = 0
Assert-Equal 'Threads must be a number from 1 to 128.' ((Test-RoboOptions $o -SkipFileSystem -SkipEmptyPaths) -join '|') 'validate: -SkipEmptyPaths drops only the two pick-a-folder problems'

# --- texts and languages ---
Assert-Equal 'Ready.' (Get-RoboText 'status.ready') 'text: a known key gives its English text'
Assert-Equal 'no.such.key' (Get-RoboText 'no.such.key') 'text: an unknown key gives the key itself'
Assert-Equal 'Scan: 3 file(s), 1.5 KB to copy.' (Get-RoboText 'log.scan' 3, '1.5 KB') 'text: values are filled in'
Assert-Equal 'en' ((Get-RoboLanguages) -join ',') 'languages: only English without a lang folder'
$langDir = Join-Path $env:ROBOGO_HOME 'lang'
New-Item -ItemType Directory -Force -Path $langDir | Out-Null
$browse = 'Przegl' + [char]0x0105 + 'daj'
[System.IO.File]::WriteAllText((Join-Path $langDir 'xx.json'), ('{ "_name": "Test", "status.ready": "Gotowe.", "ui.from": "", "ui.browse": "' + $browse + '" }'), $utf8)
[System.IO.File]::WriteAllText((Join-Path $langDir 'bad.json'), '{ this is not json', $utf8)
Assert-Equal 'en,bad,xx' ((Get-RoboLanguages) -join ',') 'languages: every lang\<code>.json adds one'
Assert-Equal 'xx' (Set-RoboLanguage 'XX') 'languages: switching returns the active code'
Assert-Equal 'Gotowe.' (Get-RoboText 'status.ready') 'languages: the language file wins'
Assert-Equal $browse (Get-RoboText 'ui.browse') 'languages: the file is read as UTF-8'
Assert-Equal 'FROM' (Get-RoboText 'ui.from') 'languages: an empty value falls back to English'
Assert-Equal 'TO' (Get-RoboText 'ui.to') 'languages: a missing key falls back to English'
Assert-Equal 'en' (Set-RoboLanguage 'bad') 'languages: a broken file falls back to English'
Assert-Equal 'Ready.' (Get-RoboText 'status.ready') 'languages: and the English texts are back'
Assert-Equal 'en' (Set-RoboLanguage 'zz') 'languages: an unknown code falls back to English'

$plPath = Join-Path $PSScriptRoot '..\lang\pl.json'
$pl = [System.IO.File]::ReadAllText($plPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$plKeys = @($pl.PSObject.Properties | ForEach-Object { $_.Name } | Where-Object { $_ -ne '_name' } | Sort-Object)
$enKeys = @($script:RoboText.Keys | Sort-Object)
Assert-Equal ($enKeys -join '|') ($plKeys -join '|') 'language file: lang\pl.json has exactly the keys of the English table'
Assert-True ($pl.PSObject.Properties['_name'] -and ($pl._name -ne '')) 'language file: it names its language'

# --- settings ---
Assert-Equal (Join-Path $env:ROBOGO_HOME 'settings.json') (Get-RoboSettingsPath) 'settings: the file lives in the program folder (ROBOGO_HOME here)'
$s = Read-RoboSettings
Assert-Equal 'en|False' ($s.Language + '|' + $s.KeepLog) 'settings: defaults without a file'
$s.Language = 'xx'
$s.KeepLog = $true
Assert-True (Save-RoboSettings $s) 'settings: saving reports success'
$s = Read-RoboSettings
Assert-Equal 'xx|True' ($s.Language + '|' + $s.KeepLog) 'settings: what was saved comes back'
[System.IO.File]::WriteAllText((Get-RoboSettingsPath), '{ broken', $utf8)
$s = Read-RoboSettings
Assert-Equal 'en|False' ($s.Language + '|' + $s.KeepLog) 'settings: a broken file gives the defaults'
[System.IO.File]::WriteAllText((Get-RoboSettingsPath), '{ "Language": 5, "Other": 1 }', $utf8)
$s = Read-RoboSettings
Assert-Equal 'en|False' ($s.Language + '|' + $s.KeepLog) 'settings: wrong types and unknown entries are ignored'

# --- switches in the EXTRA field ---
Assert-Equal '/J' (Switch-RoboExtraToken '' '/J') 'token: added to an empty field'
Assert-Equal '*.jpg /J' (Switch-RoboExtraToken '*.jpg' '/J') 'token: appended, the rest is kept'
Assert-Equal '*.jpg' (Switch-RoboExtraToken '*.jpg /j' '/J') 'token: removed when present, ignoring case'
Assert-Equal '/FFT' (Switch-RoboExtraToken '/maxage:30 /FFT' '/MAXAGE:7') 'token: a switch is recognised by its name, whatever its value'
Assert-Equal '/J' (Switch-RoboExtraToken '/J *.jpg' '*.jpg') 'token: a file filter is matched by its exact text'
Assert-Equal '/J *.jpg *.png' (Switch-RoboExtraToken '/J *.jpg' '*.png') 'token: another filter is simply added'
Assert-True (Test-RoboExtraToken ' /dcopy:DAT ' '/DCOPY:DAT') 'token: presence is tested by name'
Assert-True (-not (Test-RoboExtraToken '/JOB:x' '/J')) 'token: a longer switch name is not a match'
Assert-Equal '*.jpg /FFT' (Get-RoboSetupExtra '*.jpg /J' '/FFT') 'setup: its switches replace those of another setup, the rest stays'
Assert-Equal '*.jpg' (Get-RoboSetupExtra '*.jpg /fft /DST' '') 'setup: the default one only removes setup switches'

# --- help data ---
$switches = @(Get-RoboHelpSwitches)
Assert-True ($switches.Count -ge 10) 'help: a useful number of switches'
Assert-Equal 0 (@($switches | Where-Object { (Get-RoboText $_.Key) -eq $_.Key }).Count) 'help: every switch has an explanation'
Assert-Equal 0 (@($switches | Where-Object { $script:RoboBlockedSwitches -contains (($_.Token -split ':')[0].ToUpperInvariant()) }).Count) 'help: no switch that RoboGo refuses'
$o = New-RoboOptions
$o.Source = 'C:\a'
$o.Destination = 'C:\b'
$o.Threads = 1
$refused = @($switches | Where-Object { $o.Extra = $_.Token; (Test-RoboOptions $o -SkipFileSystem).Count -gt 0 })
Assert-Equal 0 $refused.Count 'help: every switch passes the validation on its own'
$setups = @(Get-RoboHelpSetups)
Assert-True ($setups.Count -ge 4) 'help: several recommended setups'
Assert-Equal 0 (@($setups | Where-Object { (Get-RoboText $_.Key) -eq $_.Key }).Count) 'help: every setup has a text'
$o.Threads = 8
$refused = @($setups | Where-Object { $o.Threads = $_.Threads; $o.Extra = $_.Extra; (Test-RoboOptions $o -SkipFileSystem).Count -gt 0 })
Assert-Equal 0 $refused.Count 'help: every setup passes the validation'

Remove-Item -LiteralPath $env:ROBOGO_HOME -Recurse -Force
exit (Complete-Tests 'Core')
