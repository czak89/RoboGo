<#
.SYNOPSIS
    RoboGo: builds a robocopy command, runs it and tracks the progress.
.DESCRIPTION
    Start it with RoboGo.exe (run build.cmd once to create it) or with RoboGo.cmd. It needs
    nothing but Windows 10 or 11: PowerShell, WPF and robocopy are part of the system.
    Everything it writes stays in its own folder: settings.json and, when logs are kept, logs\.
    settings.json also holds the limits for the log cleanup (LogMaxDays, LogFileMaxMB, LogMaxMB).
.PARAMETER NoUI
    Only define the functions. The test scripts dot-source the file this way.
.PARAMETER Source
    A folder to put into the FROM field at start. The launcher passes what Explorer's
    Send to menu hands it in the environment variable ROBOGO_SOURCE instead.
.PARAMETER SelfTest
    Run the built-in sanity checks, load the window without showing it and exit with the
    number of failed checks.
#>
[CmdletBinding()]
param(
    [switch]$NoUI,
    [switch]$SelfTest,
    [string]$Source = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RoboGoVersion = '0.3.0'
$script:RoboExe = Join-Path $env:SystemRoot 'System32\robocopy.exe'
$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
# Switches that would break progress tracking or keep robocopy from ever exiting.
$script:RoboBlockedSwitches = @('/LOG', '/UNILOG', '/NFL', '/NS', '/NC', '/NP', '/NJS', '/QUIT', '/MON', '/MOT', '/JOB', '/SAVE')

# The program folder holds everything RoboGo writes (settings.json, logs\) and the language
# files it reads (lang\), so the folder can be moved or copied as a whole. ROBOGO_HOME names
# another folder for those; the tests use it to stay out of the real one.
$script:RoboAppDir = $PSScriptRoot
$script:RoboDataDir = $PSScriptRoot
if (-not [string]::IsNullOrEmpty($env:ROBOGO_HOME)) { $script:RoboDataDir = $env:ROBOGO_HOME }
$script:RoboLanguage = 'en'
$script:RoboTextOverlay = @{}
# The identity of the window on the taskbar. A pin made from the running window carries it
# too, which is what makes pin and window share one button.
$script:RoboAppId = 'Czak89.RoboGo'
# Limits for the log cleanup at every start: age in days, megabytes for one log, megabytes
# for all logs of a folder. settings.json can change them under the same names.
$script:RoboLogLimits = @{ LogMaxDays = 30; LogFileMaxMB = 50; LogMaxMB = 100 }

# ============================================================================
# 0. Texts, languages, settings
#    Every text the app itself shows lives in this table. A lang\<code>.json file
#    with the same keys overrides it for that language (tools\Export-Language.ps1
#    writes one). {0}, {1} are filled in by the code. Robocopy's own output is not
#    translated. No text may depend on a number being one or many: counts are
#    written as "Label: number." because plural rules differ between languages.
# ============================================================================

$script:RoboText = @{
    # labels
    'ui.subtitle'      = 'robocopy, minus the typing'
    'ui.paths'         = 'PATHS'
    'ui.options'       = 'OPTIONS'
    'ui.command'       = 'COMMAND'
    'ui.progress'      = 'PROGRESS'
    'ui.from'          = 'FROM'
    'ui.to'            = 'TO'
    'ui.browse'        = 'BROWSE'
    'ui.copy'          = 'COPY'
    'ui.mirror'        = 'MIRROR'
    'ui.move'          = 'MOVE'
    'ui.threads'       = 'THREADS'
    'ui.retries'       = 'RETRIES'
    'ui.wait'          = 'WAIT S'
    'ui.subfolders'    = 'Subfolders'
    'ui.junctions'     = 'Skip junctions'
    'ui.newer'         = 'Keep newer files'
    'ui.restartable'   = 'Restartable'
    'ui.skipFiles'     = 'SKIP FILES'
    'ui.skipDirs'      = 'SKIP FOLDERS'
    'ui.extra'         = 'EXTRA'
    'ui.copyCommand'   = 'COPY'
    'ui.scan'          = 'Scan first'
    'ui.keepLog'       = 'Keep log file'
    'ui.dryRun'        = 'DRY RUN'
    'ui.run'           = 'RUN'
    'ui.cancel'        = 'CANCEL'
    'ui.hideLog'       = 'HIDE LOG'
    'ui.showLog'       = 'SHOW LOG'
    'ui.copyLog'       = 'COPY LOG'
    'ui.openLog'       = 'OPEN LOG'
    'ui.files'         = 'FILES'
    'ui.data'          = 'DATA'
    'ui.speed'         = 'SPEED'
    'ui.eta'           = 'ETA'
    'ui.took'          = 'TOOK'
    'ui.sendTo'        = 'SEND TO'
    'ui.showAll'       = 'SHOW ALL'
    'ui.showLess'      = 'SHOW LESS'
    'ui.failed'        = 'FAILED: {0}'
    'ui.fullLog'       = 'FULL LOG'
    'ui.clearRecent'   = 'Clear the list'
    'ui.helpSwitches'  = 'USEFUL SWITCHES'
    'ui.helpNote'      = 'Tick a switch to add it to EXTRA, untick it to remove it. Values such as 7 or *.jpg are examples: edit them in the EXTRA field.'
    'ui.helpSetups'    = 'RECOMMENDED SETUPS'
    'ui.helpSetupNote' = 'Click one to set THREADS, Restartable and its switches.'

    # example texts shown in empty fields
    'ph.source'        = 'e.g. D:\Photos'
    'ph.dest'          = 'e.g. \\nas\backup\Photos'
    'ph.skipFiles'     = 'e.g. *.tmp; thumbs.db'
    'ph.skipDirs'      = 'e.g. node_modules; .git'
    'ph.extra'         = 'e.g. *.jpg /MAXAGE:7'

    # tooltips
    'tip.source'       = 'The folder to copy from. Type, paste, browse, or drop a folder here. Robocopy copies what is inside it, not the folder itself.'
    'tip.dest'         = 'The folder to copy into. It is created if it does not exist.'
    'tip.copy'         = 'Add and update files in TO. Nothing is deleted.'
    'tip.mirror'       = '/MIR  make TO identical to FROM. Whatever is extra in TO is deleted.'
    'tip.move'         = '/MOVE  copy, then delete from FROM.'
    'tip.threads'      = '/MT:n  files copied in parallel. 1 turns it off.'
    'tip.retries'      = '/R:n  retries per failed file. Robocopy''s own default is one million.'
    'tip.wait'         = '/W:n  seconds to wait between retries.'
    'tip.subfolders'   = '/E  include subfolders, empty ones too.'
    'tip.junctions'    = '/XJ  do not follow junction points. Avoids endless loops in user profiles.'
    'tip.newer'        = '/XO  do not overwrite a file in TO with an older one from FROM.'
    'tip.restartable'  = '/Z  resume a half-copied file after a network drop. Slower.'
    'tip.skipFiles'    = '/XF  file names or patterns to leave out, separated by ;'
    'tip.skipDirs'     = '/XD  folder names or paths to leave out, separated by ;'
    'tip.extra'        = 'Any other robocopy switches or file filters, added exactly as typed.'
    'tip.help'         = 'Useful switches and recommended setups.'
    'tip.copyCommand'  = 'Copy the command to the clipboard.'
    'tip.scan'         = 'Counts what needs copying before the real run, which gives an exact percent and ETA. Turn it off for huge trees: you then get counters but no percent.'
    'tip.keepLog'      = 'Keep the full robocopy log of every job in the logs folder next to RoboGo. Off: the log is only shown here.'
    'tip.dryRun'       = '/L  list what would happen without copying or deleting anything.'
    'tip.copyLog'      = 'Copy the log shown here to the clipboard.'
    'tip.openLog'      = 'Open the kept log file of the last job.'
    'tip.language'     = 'Language'
    'tip.sendTo'       = 'Puts RoboGo into the Send to menu of Explorer: right-click a folder, Send to, RoboGo. Click again to take it out. The shortcut for that menu is the only thing RoboGo writes outside its own folder.'
    'tip.recent'       = 'Folders of earlier jobs.'
    'tip.tape'         = 'Show the whole command, or only its first two lines.'
    'tip.failed'       = 'Show only what failed, or the whole log again.'

    # status line and log notes
    'status.ready'         = 'Ready.'
    'status.scanning'      = 'Scanning: counting what needs to be copied...'
    'status.dryRun'        = 'Dry run: listing what would happen. Nothing is changed.'
    'status.copying'       = 'Copying...'
    'status.copyingErrors' = 'Copying... Errors so far: {0}. See the log.'
    'status.stopping'      = 'Stopping...'
    'status.copied'        = 'Command copied to the clipboard.'
    'status.logCopied'     = 'Log copied to the clipboard.'
    'status.droppedFile'   = 'That was a file, so its folder was taken.'
    'status.error'         = 'Unexpected error: {0}'
    'status.settings'      = 'The setting could not be saved: the RoboGo folder is not writable.'
    'status.sendToOn'      = 'RoboGo is now in the Send to menu of Explorer.'
    'status.sendToOff'     = 'RoboGo was taken out of the Send to menu.'
    'status.sendToFail'    = 'The Send to shortcut could not be changed.'
    'status.noSpace'       = 'Not started. The job needs {0}, the destination has {1} free.'
    'log.scan'             = 'Scan done. Files to copy: {0}. Data to copy: {1}.'
    'log.space'            = 'Free space in the destination: {0}.'
    'log.scanNoTotals'     = 'Scan: no totals found, running without percent.'
    'log.saved'            = 'Log saved: {0}'
    'log.savedBig'         = 'This log is bigger than {0} MB, the limit for one log (LogFileMaxMB in settings.json). The next start of RoboGo removes it.'

    # warnings for modes that delete
    'danger.mirror'    = 'Mirror deletes everything in the destination that is not in the source.'
    'danger.move'      = 'Move deletes the files from the source after copying them.'

    # reasons a job cannot start
    'problem.source'        = 'Pick a source folder.'
    'problem.sourceMissing' = 'Source folder does not exist.'
    'problem.dest'          = 'Pick a destination folder.'
    'problem.same'          = 'Source and destination are the same folder.'
    'problem.inside'        = 'Destination is inside the source folder.'
    'problem.mirrorInside'  = 'Mirror would delete the source, because it sits inside the destination.'
    'problem.threads'       = 'Threads must be a number from 1 to 128.'
    'problem.retries'       = 'Retries must be a number from 0 to 1000000.'
    'problem.wait'          = 'Wait must be a number of seconds from 0 to 3600.'
    'problem.blocked'       = 'Extra switches: {0} is not supported, RoboGo needs robocopy''s standard log output.'
    'problem.ipg'           = 'Extra switches: /IPG only works with 1 thread. Set THREADS to 1.'

    # result of a job
    'verdict.cancelled'     = 'Cancelled. Files that were already copied stay in the destination.'
    'verdict.copied'        = 'Files copied: {0} ({1}).'
    'verdict.wouldCopy'     = 'Files to copy: {0} ({1}).'
    'verdict.skipped'       = 'Skipped: {0}.'
    'verdict.failed'        = 'FAILED: {0}.'
    'verdict.extrasWould'   = 'Extra items that would be deleted from the destination: {0}.'
    'verdict.extrasDeleted' = 'Extra items deleted from the destination: {0}.'
    'verdict.extrasLeft'    = 'Extra items left alone in the destination: {0}.'
    'verdict.fatal'         = 'Fatal error (robocopy exit code {0}). The job did not run properly: check the paths and the log.'
    'verdict.errors'        = 'Finished with errors. {0} See the log for the files that failed.'
    'verdict.dry'           = 'Dry run, nothing was changed. {0}'
    'verdict.mismatch'      = 'Done, but some items are mismatched (a file where a folder is expected, or the reverse). {0}'
    'verdict.done'          = 'Done. {0}'
    'verdict.nothing'       = 'Nothing to copy, the destination is already up to date. {0}'

    # dialogs
    'dialog.confirmTip'  = 'DRY RUN shows what would happen without touching anything.'
    'dialog.confirmAsk'  = 'Run it for real?'
    'dialog.noSpace'     = 'The job needs {0}, but the destination has only {1} free.'
    'dialog.runAnyway'   = 'Run it anyway?'
    'dialog.closing'     = 'A job is still running. Stop it and close RoboGo?'
    'dialog.pickSource'  = 'Pick the folder to copy FROM'
    'dialog.pickDest'    = 'Pick the folder to copy TO'
    'dialog.startFail'   = 'RoboGo could not start.'

    # help panel: switches
    'help.filter'    = 'Copy only files of this type. Any name or pattern works, several are allowed.'
    'help.xa'        = 'Skip hidden and system files.'
    'help.maxage'    = 'Only files changed in the last 7 days.'
    'help.minage'    = 'Only files not changed for at least 30 days.'
    'help.max'       = 'Only files up to 100 MB. The size is given in bytes.'
    'help.lev'       = 'Only the top 2 levels of the folder tree.'
    'help.j'         = 'Unbuffered copying. Faster for very large files, slower for small ones.'
    'help.fft'       = 'Tolerate 2-second time differences. Stops needless re-copying to a NAS, Linux or exFAT.'
    'help.dst'       = 'Tolerate the 1-hour daylight saving shift some FAT and exFAT drives show.'
    'help.dcopy'     = 'Keep the dates of folders too. Without it copied folders get today''s date.'
    'help.compress'  = 'Ask for network compression when both ends support it.'
    'help.ipg'       = 'Pause 50 ms between blocks to leave bandwidth for others. Needs THREADS 1.'
    'help.sl'        = 'Copy symbolic links as links instead of the files they point to.'
    'help.create'    = 'Create the folder tree and empty files only, no data.'
    'help.is'        = 'Copy files again even when they look identical.'

    # help panel: setups
    'setup.nas'      = 'NAS or network share: restartable, 2-second time tolerance, 8 threads.'
    'setup.big'      = 'A few very large files (video, disk images): unbuffered, 1 thread.'
    'setup.small'    = 'Many small files between fast drives: 16 threads.'
    'setup.usb'      = 'USB stick or SD card (FAT, exFAT): time tolerance, 1 thread.'
    'setup.default'  = 'Back to the defaults: 8 threads, not restartable, setup switches removed.'
}

function Get-RoboText {
    # The text for a key in the current language. Falls back to English, then to the key.
    param([string]$Key, [object[]]$Values)
    $text = $null
    if ($script:RoboTextOverlay.ContainsKey($Key)) { $text = [string]$script:RoboTextOverlay[$Key] }
    if ([string]::IsNullOrEmpty($text)) {
        if ($script:RoboText.ContainsKey($Key)) { $text = [string]$script:RoboText[$Key] } else { $text = $Key }
    }
    if (($null -ne $Values) -and ($Values.Count -gt 0)) { return [string]::Format($script:Inv, $text, $Values) }
    return $text
}

function Get-RoboLanguageDir {
    return (Join-Path $script:RoboDataDir 'lang')
}

function Get-RoboLanguages {
    # English is built in. Every lang\<code>.json adds a language.
    $codes = New-Object System.Collections.Generic.List[string]
    $codes.Add('en')
    $dir = Get-RoboLanguageDir
    if (Test-Path -LiteralPath $dir -PathType Container) {
        foreach ($file in (Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | Sort-Object Name)) {
            $code = $file.BaseName.ToLowerInvariant()
            if (-not $codes.Contains($code)) { $codes.Add($code) }
        }
    }
    return , $codes.ToArray()
}

function Set-RoboLanguage {
    # Makes a language current and returns its code. A missing or unreadable language file
    # leaves the app in English.
    param([string]$Code)
    $language = ([string]$Code).Trim().ToLowerInvariant()
    $overlay = @{}
    if (($language -ne 'en') -and ($language -ne '')) {
        $path = Join-Path (Get-RoboLanguageDir) ($language + '.json')
        try {
            $data = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($entry in $data.PSObject.Properties) {
                if (($entry.Value -is [string]) -and ($entry.Value -ne '')) { $overlay[$entry.Name] = $entry.Value }
            }
        }
        catch {
            $language = 'en'
            $overlay = @{}
        }
    }
    if ($language -eq '') { $language = 'en' }
    $script:RoboLanguage = $language
    $script:RoboTextOverlay = $overlay
    return $language
}

function Get-RoboSettingsPath {
    return (Join-Path $script:RoboDataDir 'settings.json')
}

function ConvertTo-RoboLimit {
    # A log limit as read from settings.json: a whole number from 1 to 1,000,000.
    # Anything else gives the default.
    param($Value, [int]$Default)
    if (($Value -is [int]) -or ($Value -is [long]) -or ($Value -is [double]) -or ($Value -is [decimal])) {
        if (($Value -ge 1) -and ($Value -le 1000000) -and ([math]::Floor($Value) -eq $Value)) { return [int]$Value }
    }
    return $Default
}

# What is remembered of the fields between sessions. The mode is not: every start is a
# plain copy, so a leftover MIRROR or MOVE cannot delete anything by reflex.
$script:RoboLastTexts = @('Source', 'Destination', 'Threads', 'Retries', 'Wait', 'ExcludeFiles', 'ExcludeDirs', 'Extra')
$script:RoboLastFlags = @('Subfolders', 'SkipJunctions', 'OnlyNewer', 'Restartable', 'Scan')

function ConvertTo-RoboJsonString {
    # A text as a JSON string. PowerShell 5.1 and 7 escape differently, this does not.
    param([string]$Text)
    $out = New-Object System.Text.StringBuilder
    [void]$out.Append('"')
    foreach ($c in ([string]$Text).ToCharArray()) {
        $code = [int]$c
        if ($code -eq 34) { [void]$out.Append('\"') }
        elseif ($code -eq 92) { [void]$out.Append('\\') }
        elseif ($code -eq 9) { [void]$out.Append('\t') }
        elseif ($code -eq 10) { [void]$out.Append('\n') }
        elseif ($code -eq 13) { [void]$out.Append('\r') }
        elseif ($code -lt 32) { [void]$out.Append('\u' + $code.ToString('x4', $script:Inv)) }
        else { [void]$out.Append($c) }
    }
    [void]$out.Append('"')
    return $out.ToString()
}

function Test-RoboNumber {
    param($Value)
    return (($Value -is [int]) -or ($Value -is [long]) -or ($Value -is [double]) -or ($Value -is [decimal]))
}

function ConvertTo-RoboWindowRect {
    # The window rectangle from settings.json, or $null when it is not four numbers.
    param($Data)
    if (($null -eq $Data) -or ($Data.GetType().Name -ne 'PSCustomObject')) { return $null }
    $rect = @{}
    foreach ($key in 'Left', 'Top', 'Width', 'Height') {
        $entry = $Data.PSObject.Properties[$key]
        if (($null -eq $entry) -or (-not (Test-RoboNumber $entry.Value))) { return $null }
        $rect[$key] = [double]$entry.Value
    }
    if (($rect.Width -lt 1) -or ($rect.Height -lt 1)) { return $null }
    return $rect
}

function ConvertTo-RoboLastJob {
    # The remembered fields from settings.json. Entries of the wrong type are left out.
    param($Data)
    if (($null -eq $Data) -or ($Data.GetType().Name -ne 'PSCustomObject')) { return $null }
    $last = @{}
    foreach ($key in $script:RoboLastTexts) {
        $entry = $Data.PSObject.Properties[$key]
        if (($null -ne $entry) -and ($entry.Value -is [string])) { $last[$key] = $entry.Value }
    }
    foreach ($key in $script:RoboLastFlags) {
        $entry = $Data.PSObject.Properties[$key]
        if (($null -ne $entry) -and ($entry.Value -is [bool])) { $last[$key] = $entry.Value }
    }
    return $last
}

function ConvertTo-RoboPathList {
    # A list of recent paths from settings.json: texts only, no empty ones, at most ten.
    param($Data)
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Data)) {
        if (($item -is [string]) -and ($item.Trim() -ne '') -and ($list.Count -lt 10)) { $list.Add($item) }
    }
    return , $list.ToArray()
}

function Add-RoboRecent {
    # Puts a path at the front of a recent list. The same folder is never listed twice
    # (case and a trailing backslash do not count), and the list keeps the newest ones.
    param([string[]]$List, [string]$Path, [int]$Max = 10)
    $new = New-Object System.Collections.Generic.List[string]
    $clean = ConvertTo-RoboPath $Path
    $same = ''
    if ($clean -ne '') {
        $new.Add($clean)
        $same = Get-RoboComparablePath $clean
    }
    foreach ($item in @($List)) {
        if ([string]::IsNullOrEmpty($item)) { continue }
        if (($clean -ne '') -and ((Get-RoboComparablePath $item) -eq $same)) { continue }
        if ($new.Count -ge $Max) { break }
        $new.Add($item)
    }
    return , $new.ToArray()
}

function Read-RoboSettings {
    # The saved choices, or the defaults when there is no usable settings file.
    $settings = @{ Language = 'en'; KeepLog = $false; Window = $null; Last = $null }
    $settings.RecentSources = [string[]]@()
    $settings.RecentDestinations = [string[]]@()
    foreach ($key in $script:RoboLogLimits.Keys) { $settings[$key] = $script:RoboLogLimits[$key] }
    $path = Get-RoboSettingsPath
    if (Test-Path -LiteralPath $path) {
        try {
            $data = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if (($null -ne $data.PSObject.Properties['Language']) -and ($data.Language -is [string])) { $settings.Language = $data.Language }
            if (($null -ne $data.PSObject.Properties['KeepLog']) -and ($data.KeepLog -is [bool])) { $settings.KeepLog = $data.KeepLog }
            foreach ($key in $script:RoboLogLimits.Keys) {
                if ($null -ne $data.PSObject.Properties[$key]) { $settings[$key] = ConvertTo-RoboLimit $data.$key $script:RoboLogLimits[$key] }
            }
            if ($null -ne $data.PSObject.Properties['Window']) { $settings.Window = ConvertTo-RoboWindowRect $data.Window }
            if ($null -ne $data.PSObject.Properties['Last']) { $settings.Last = ConvertTo-RoboLastJob $data.Last }
            if ($null -ne $data.PSObject.Properties['RecentSources']) { $settings.RecentSources = ConvertTo-RoboPathList $data.RecentSources }
            if ($null -ne $data.PSObject.Properties['RecentDestinations']) { $settings.RecentDestinations = ConvertTo-RoboPathList $data.RecentDestinations }
        }
        catch { }
    }
    return $settings
}

function Save-RoboSettings {
    # Writes settings.json next to the program: language, Keep log file, the three log
    # limits, and what is remembered between sessions (window rectangle, the fields of the
    # last job, recent paths). Returns $false when the folder is not writable.
    param([hashtable]$Settings)
    $saved = $false
    try {
        $nl = [Environment]::NewLine
        $language = ([string]$Settings.Language).Replace('\', '').Replace('"', '')
        $keep = 'false'
        if ($Settings.KeepLog) { $keep = 'true' }
        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('  "Language": "' + $language + '"')
        $lines.Add('  "KeepLog": ' + $keep)
        # the limits are always written, so they can be found and changed in the file
        foreach ($key in 'LogMaxDays', 'LogFileMaxMB', 'LogMaxMB') {
            $value = $script:RoboLogLimits[$key]
            if ($Settings.ContainsKey($key)) { $value = ConvertTo-RoboLimit $Settings[$key] $value }
            $lines.Add('  "' + $key + '": ' + $value)
        }
        if ($Settings.ContainsKey('Window') -and ($Settings.Window -is [hashtable])) {
            $cells = New-Object System.Collections.Generic.List[string]
            foreach ($key in 'Left', 'Top', 'Width', 'Height') {
                $cells.Add('"' + $key + '": ' + [string]::Format($script:Inv, '{0}', [math]::Round([double]$Settings.Window[$key], 1)))
            }
            $lines.Add('  "Window": { ' + ($cells -join ', ') + ' }')
        }
        if ($Settings.ContainsKey('Last') -and ($Settings.Last -is [hashtable])) {
            $cells = New-Object System.Collections.Generic.List[string]
            foreach ($key in $script:RoboLastTexts) {
                if ($Settings.Last.ContainsKey($key)) { $cells.Add('    "' + $key + '": ' + (ConvertTo-RoboJsonString ([string]$Settings.Last[$key]))) }
            }
            foreach ($key in $script:RoboLastFlags) {
                if ($Settings.Last.ContainsKey($key)) { $cells.Add('    "' + $key + '": ' + ([string][bool]$Settings.Last[$key]).ToLowerInvariant()) }
            }
            $lines.Add('  "Last": {' + $nl + ($cells -join (',' + $nl)) + $nl + '  }')
        }
        foreach ($key in 'RecentSources', 'RecentDestinations') {
            $cells = New-Object System.Collections.Generic.List[string]
            if ($Settings.ContainsKey($key)) {
                foreach ($item in @($Settings[$key])) {
                    if (-not [string]::IsNullOrEmpty($item)) { $cells.Add('    ' + (ConvertTo-RoboJsonString ([string]$item))) }
                }
            }
            if ($cells.Count -eq 0) { $lines.Add('  "' + $key + '": []') }
            else { $lines.Add('  "' + $key + '": [' + $nl + ($cells -join (',' + $nl)) + $nl + '  ]') }
        }
        $json = '{' + $nl + ($lines -join (',' + $nl)) + $nl + '}' + $nl
        [System.IO.File]::WriteAllText((Get-RoboSettingsPath), $json, (New-Object System.Text.UTF8Encoding $false))
        $saved = $true
    }
    catch { }
    return $saved
}

function Get-RoboHelpSwitches {
    # The switches offered in the help panel. Token is what goes into EXTRA.
    return @(
        @{ Token = '*.jpg'; Key = 'help.filter' }
        @{ Token = '/XA:SH'; Key = 'help.xa' }
        @{ Token = '/MAXAGE:7'; Key = 'help.maxage' }
        @{ Token = '/MINAGE:30'; Key = 'help.minage' }
        @{ Token = '/MAX:104857600'; Key = 'help.max' }
        @{ Token = '/LEV:2'; Key = 'help.lev' }
        @{ Token = '/J'; Key = 'help.j' }
        @{ Token = '/FFT'; Key = 'help.fft' }
        @{ Token = '/DST'; Key = 'help.dst' }
        @{ Token = '/DCOPY:DAT'; Key = 'help.dcopy' }
        @{ Token = '/COMPRESS'; Key = 'help.compress' }
        @{ Token = '/IPG:50'; Key = 'help.ipg' }
        @{ Token = '/SL'; Key = 'help.sl' }
        @{ Token = '/CREATE'; Key = 'help.create' }
        @{ Token = '/IS'; Key = 'help.is' }
    )
}

function Get-RoboHelpSetups {
    # Recommended combinations. Extra lists the switches the setup wants in EXTRA.
    return @(
        @{ Key = 'setup.nas'; Threads = 8; Restartable = $true; Extra = '/FFT' }
        @{ Key = 'setup.big'; Threads = 1; Restartable = $false; Extra = '/J' }
        @{ Key = 'setup.small'; Threads = 16; Restartable = $false; Extra = '' }
        @{ Key = 'setup.usb'; Threads = 1; Restartable = $false; Extra = '/FFT /DST' }
        @{ Key = 'setup.default'; Threads = 8; Restartable = $false; Extra = '' }
    )
}

function Test-RoboExtraToken {
    # Is this switch (by name) or file filter (by exact text) in the EXTRA text?
    param([string]$Extra, [string]$Token)
    $name = ($Token -split ':')[0]
    foreach ($piece in (([string]$Extra) -split '\s+')) {
        if ($piece -eq '') { continue }
        if ($Token.StartsWith('/')) {
            if ((($piece -split ':')[0]) -eq $name) { return $true }
        }
        elseif ($piece -eq $Token) { return $true }
    }
    return $false
}

function Switch-RoboExtraToken {
    # Adds the token to the EXTRA text, or removes it when it is already there. A switch is
    # recognised by its name (the part before the colon), a file filter by its exact text.
    param([string]$Extra, [string]$Token)
    $name = ($Token -split ':')[0]
    $kept = New-Object System.Collections.Generic.List[string]
    $found = $false
    foreach ($piece in (([string]$Extra) -split '\s+')) {
        if ($piece -eq '') { continue }
        $same = $false
        if ($Token.StartsWith('/')) { $same = ((($piece -split ':')[0]) -eq $name) } else { $same = ($piece -eq $Token) }
        if ($same) { $found = $true } else { $kept.Add($piece) }
    }
    if (-not $found) { $kept.Add($Token) }
    return ($kept -join ' ')
}

function Get-RoboSetupExtra {
    # The EXTRA text after applying a setup: switches that belong to any setup are taken out,
    # the ones of this setup are put in, everything else the user typed stays.
    param([string]$Extra, [string]$SetupExtra)
    $result = [string]$Extra
    foreach ($setup in (Get-RoboHelpSetups)) {
        foreach ($token in ($setup.Extra -split '\s+')) {
            if (($token -ne '') -and (Test-RoboExtraToken $result $token)) { $result = Switch-RoboExtraToken $result $token }
        }
    }
    foreach ($token in (([string]$SetupExtra) -split '\s+')) {
        if (($token -ne '') -and (-not (Test-RoboExtraToken $result $token))) { $result = Switch-RoboExtraToken $result $token }
    }
    return (($result -split '\s+' | Where-Object { $_ -ne '' }) -join ' ')
}

# ============================================================================
# 1. Pure helpers: paths, command line, validation, formatting
# ============================================================================

function New-RoboOptions {
    # Everything the window lets the user choose, with the defaults.
    return [pscustomobject]@{
        Source        = ''
        Destination   = ''
        Mode          = 'Copy'      # Copy | Mirror | Move
        Subfolders    = $true
        Threads       = 8
        Retries       = 2
        Wait          = 5
        Restartable   = $false
        SkipJunctions = $true
        OnlyNewer     = $false
        ExcludeFiles  = ''
        ExcludeDirs   = ''
        Extra         = ''
    }
}

function ConvertTo-RoboPath {
    # Cleans a folder path that was typed, pasted or dropped. No quoting here.
    param([string]$Path)
    if ($null -eq $Path) { return '' }
    $p = $Path.Trim().Trim('"').Trim()
    if ($p -eq '') { return '' }
    $p = $p.Replace('/', '\')
    if ($p -match '^[A-Za-z]:\\*$') { return ($p.Substring(0, 2) + '\') }
    return $p.TrimEnd('\')
}

function Format-RoboArgPath {
    # Quotes a path for the command line. A quoted path must never end with a backslash:
    # robocopy reads \" as an escaped quote and swallows the rest of the line.
    param([string]$Path)
    $p = ConvertTo-RoboPath $Path
    if ($p -eq '') { return '""' }
    if ($p -match '^[A-Za-z]:\\$') { return $p }
    return ('"' + $p + '"')
}

function Get-RoboComparablePath {
    # Full, lower-case path without a trailing backslash, for comparing two folders.
    param([string]$Path)
    $p = ConvertTo-RoboPath $Path
    try { $p = [System.IO.Path]::GetFullPath($p) } catch { }
    return $p.TrimEnd('\').ToLowerInvariant()
}

function Get-RoboShortPath {
    # Shortens a long path for display, keeping the end (the file name matters most).
    param([string]$Path, [int]$Max = 100)
    if ($null -eq $Path) { return '' }
    if ($Path.Length -le $Max) { return $Path }
    return ('...' + $Path.Substring($Path.Length - ($Max - 3)))
}

function Split-RoboList {
    # Splits "a; b c; d" into its items.
    param([string]$Text)
    $items = New-Object System.Collections.Generic.List[string]
    foreach ($part in (([string]$Text) -split '[;\r\n]+')) {
        $item = $part.Trim().Trim('"').Trim()
        if ($item -ne '') { $items.Add($item) }
    }
    return , $items.ToArray()
}

function ConvertTo-RoboInt {
    # Returns the number in the text, or $null when it is not a whole number.
    param([string]$Text)
    $n = 0
    if ([int]::TryParse(([string]$Text).Trim(), [ref]$n)) { return $n }
    return $null
}

function Format-RoboListItem {
    param([string]$Item)
    $i = $Item.TrimEnd('\')
    if ($i -match '\s') { return ('"' + $i + '"') }
    return $i
}

function Get-RoboSwitches {
    # The chosen options as command-line tokens, without the two paths.
    param($Options)
    $t = New-Object System.Collections.Generic.List[string]
    switch ($Options.Mode) {
        'Mirror' { $t.Add('/MIR') }
        'Move' {
            if ($Options.Subfolders) { $t.Add('/E'); $t.Add('/MOVE') } else { $t.Add('/MOV') }
        }
        default {
            if ($Options.Subfolders) { $t.Add('/E') }
        }
    }
    if ([int]$Options.Threads -gt 1) { $t.Add('/MT:' + [int]$Options.Threads) }
    $t.Add('/R:' + [int]$Options.Retries)
    $t.Add('/W:' + [int]$Options.Wait)
    if ($Options.Restartable) { $t.Add('/Z') }
    if ($Options.SkipJunctions) { $t.Add('/XJ') }
    if ($Options.OnlyNewer) { $t.Add('/XO') }
    $files = Split-RoboList $Options.ExcludeFiles
    if ($files.Count -gt 0) {
        $t.Add('/XF')
        foreach ($f in $files) { $t.Add((Format-RoboListItem $f)) }
    }
    $dirs = Split-RoboList $Options.ExcludeDirs
    if ($dirs.Count -gt 0) {
        $t.Add('/XD')
        foreach ($d in $dirs) { $t.Add((Format-RoboListItem $d)) }
    }
    $extra = ([string]$Options.Extra).Trim()
    if ($extra -ne '') { $t.Add($extra) }
    return , $t.ToArray()
}

function Get-RoboCommandLine {
    # The command exactly as the user could type it in a terminal.
    param($Options)
    $parts = @('robocopy', (Format-RoboArgPath $Options.Source), (Format-RoboArgPath $Options.Destination)) + (Get-RoboSwitches $Options)
    return ($parts -join ' ')
}

function Get-RoboCommandParts {
    # The same command as coloured pieces for the preview. Each piece is @{ Text; Kind }
    # and Kind is exe, path, switch, danger or value.
    param($Options)
    $parts = New-Object System.Collections.Generic.List[object]
    $parts.Add(@{ Text = 'robocopy'; Kind = 'exe' })
    $parts.Add(@{ Text = (Format-RoboArgPath $Options.Source); Kind = 'path' })
    $parts.Add(@{ Text = (Format-RoboArgPath $Options.Destination); Kind = 'path' })
    foreach ($token in (Get-RoboSwitches $Options)) {
        foreach ($piece in ($token -split ' ')) {
            if ($piece -eq '') { continue }
            $kind = 'value'
            if ($piece.StartsWith('/')) {
                $kind = 'switch'
                if ($piece -match '^/(MIR|PURGE|MOV|MOVE)$') { $kind = 'danger' }
            }
            $parts.Add(@{ Text = $piece; Kind = $kind })
        }
    }
    return , $parts.ToArray()
}

function Get-RoboArguments {
    # The argument string RoboGo really starts robocopy with. Kind is Run, Scan or DryRun.
    # /BYTES and /FP make the log parseable. /UNILOG gives a UTF-16 log file: piped output
    # is OEM code page text and loses characters. /L makes scan and dry run list-only.
    param($Options, [string]$Kind, [string]$LogPath)
    $t = New-Object System.Collections.Generic.List[string]
    $t.Add((Format-RoboArgPath $Options.Source))
    $t.Add((Format-RoboArgPath $Options.Destination))
    foreach ($s in (Get-RoboSwitches $Options)) { $t.Add($s) }
    if ($Kind -eq 'Scan') {
        foreach ($s in '/L', '/NFL', '/NDL', '/NJH') { $t.Add($s) }
    }
    elseif ($Kind -eq 'DryRun') {
        $t.Add('/L')
    }
    $t.Add('/BYTES')
    $t.Add('/FP')
    $t.Add('/UNILOG:"' + $LogPath + '"')
    return ($t -join ' ')
}

function Test-RoboRange {
    param($Value, [int]$Min, [int]$Max)
    if ($null -eq $Value) { return $false }
    $n = 0
    if (-not [int]::TryParse([string]$Value, [ref]$n)) { return $false }
    return (($n -ge $Min) -and ($n -le $Max))
}

function Test-RoboOptions {
    # Returns the problems that stop a run, as sentences. Empty means good to go.
    # -SkipFileSystem leaves out the disk check and -SkipEmptyPaths the two "pick a folder"
    # problems; the live preview uses both, so it does not nag before anything is typed.
    param($Options, [switch]$SkipFileSystem, [switch]$SkipEmptyPaths)
    $problems = New-Object System.Collections.Generic.List[string]
    $src = ConvertTo-RoboPath $Options.Source
    $dst = ConvertTo-RoboPath $Options.Destination
    if ($src -eq '') {
        if (-not $SkipEmptyPaths) { $problems.Add((Get-RoboText 'problem.source')) }
    }
    elseif ((-not $SkipFileSystem) -and (-not (Test-Path -LiteralPath $src -PathType Container))) {
        $problems.Add((Get-RoboText 'problem.sourceMissing'))
    }
    if (($dst -eq '') -and (-not $SkipEmptyPaths)) { $problems.Add((Get-RoboText 'problem.dest')) }
    if (($src -ne '') -and ($dst -ne '')) {
        $s = Get-RoboComparablePath $src
        $d = Get-RoboComparablePath $dst
        if ($s -eq $d) {
            $problems.Add((Get-RoboText 'problem.same'))
        }
        elseif ($d.StartsWith($s + '\')) {
            $problems.Add((Get-RoboText 'problem.inside'))
        }
        elseif (($Options.Mode -eq 'Mirror') -and $s.StartsWith($d + '\')) {
            $problems.Add((Get-RoboText 'problem.mirrorInside'))
        }
    }
    if (-not (Test-RoboRange $Options.Threads 1 128)) { $problems.Add((Get-RoboText 'problem.threads')) }
    if (-not (Test-RoboRange $Options.Retries 0 1000000)) { $problems.Add((Get-RoboText 'problem.retries')) }
    if (-not (Test-RoboRange $Options.Wait 0 3600)) { $problems.Add((Get-RoboText 'problem.wait')) }
    foreach ($token in (([string]$Options.Extra) -split '\s+')) {
        if (-not $token.StartsWith('/')) { continue }
        $name = ($token.ToUpperInvariant() -split ':')[0].TrimEnd('+')
        if ($script:RoboBlockedSwitches -contains $name) {
            $problems.Add((Get-RoboText 'problem.blocked' $name))
        }
        elseif (($name -eq '/IPG') -and ([int]$Options.Threads -gt 1)) {
            # robocopy itself refuses /IPG together with /MT
            $problems.Add((Get-RoboText 'problem.ipg'))
        }
    }
    return , $problems.ToArray()
}

function Get-RoboDanger {
    # A warning sentence when the options delete data, otherwise an empty string.
    param($Options)
    $extra = (' ' + [string]$Options.Extra + ' ').ToUpperInvariant()
    if (($Options.Mode -eq 'Mirror') -or ($extra -match '\s/(MIR|PURGE)\s')) {
        return (Get-RoboText 'danger.mirror')
    }
    if (($Options.Mode -eq 'Move') -or ($extra -match '\s/MOVE?\s')) {
        return (Get-RoboText 'danger.move')
    }
    return ''
}

function Format-RoboBytes {
    # 1536 -> "1.5 KB". Binary units with the labels Explorer uses, always a decimal point.
    param([double]$Bytes)
    if ($Bytes -lt 0) { $Bytes = 0 }
    $units = @('B', 'KB', 'MB', 'GB', 'TB')
    $i = 0
    while (($Bytes -ge 1024) -and ($i -lt ($units.Count - 1))) {
        $Bytes = $Bytes / 1024
        $i++
    }
    if ($i -eq 0) { return [string]::Format($script:Inv, '{0:0} B', $Bytes) }
    return [string]::Format($script:Inv, '{0:0.0} {1}', $Bytes, $units[$i])
}

function Format-RoboDuration {
    # 3725 -> "1h 02m". Unknown or negative -> "--".
    param([double]$Seconds)
    if ([double]::IsNaN($Seconds) -or [double]::IsInfinity($Seconds) -or ($Seconds -lt 0)) { return '--' }
    $total = [long][math]::Round($Seconds)
    $h = [long][math]::Floor($total / 3600)
    $m = [long][math]::Floor(($total % 3600) / 60)
    $s = $total % 60
    if ($h -gt 0) { return ('{0}h {1:00}m' -f $h, $m) }
    if ($m -gt 0) { return ('{0}m {1:00}s' -f $m, $s) }
    return ('{0}s' -f $s)
}

function Get-RoboLauncherPath {
    # What starts the app: RoboGo.exe once it is built, RoboGo.cmd otherwise.
    $exe = Join-Path $script:RoboAppDir 'RoboGo.exe'
    if (Test-Path -LiteralPath $exe) { return $exe }
    return (Join-Path $script:RoboAppDir 'RoboGo.cmd')
}

function Get-RoboSendToPath {
    # The shortcut that puts RoboGo into the Send to menu of Explorer. It is the only file
    # RoboGo ever writes outside its own folder, and only when the user switches it on.
    # ROBOGO_SENDTO names another folder; the tests use it to stay out of the real one.
    $dir = $env:ROBOGO_SENDTO
    if ([string]::IsNullOrEmpty($dir)) { $dir = [Environment]::GetFolderPath('SendTo') }
    return (Join-Path $dir 'RoboGo.lnk')
}

function Test-RoboSendTo {
    return (Test-Path -LiteralPath (Get-RoboSendToPath) -PathType Leaf)
}

function Set-RoboSendTo {
    # Creates or removes the Send to shortcut. Returns $false when that did not work.
    param([bool]$On)
    try {
        $path = Get-RoboSendToPath
        if ($On) {
            $dir = [System.IO.Path]::GetDirectoryName($path)
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
            $shell = New-Object -ComObject WScript.Shell
            $link = $shell.CreateShortcut($path)
            $link.TargetPath = Get-RoboLauncherPath
            $link.WorkingDirectory = $script:RoboAppDir
            $icon = Join-Path $script:RoboAppDir 'RoboGo.ico'
            if (Test-Path -LiteralPath $icon) { $link.IconLocation = $icon + ',0' }
            $link.Description = 'RoboGo'
            $link.Save()
        }
        elseif (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
        return $true
    }
    catch {
        return $false
    }
}

function Update-RoboSendTo {
    # At start: a Send to shortcut that points somewhere else (the folder was moved, or the
    # exe was built since) is written again. Without a shortcut nothing happens.
    if (-not (Test-RoboSendTo)) { return }
    try {
        $shell = New-Object -ComObject WScript.Shell
        if ($shell.CreateShortcut((Get-RoboSendToPath)).TargetPath -ne (Get-RoboLauncherPath)) { [void](Set-RoboSendTo $true) }
    }
    catch { }
}

# The Windows calls PowerShell has no cmdlet for, in one small C# type (C# 5, so that the
# compiler of Windows PowerShell 5.1 takes it): dark title bar, free space of a folder on
# any drive or share, flashing taskbar button, the sound of a sound-scheme event, and the
# identity of the window on the taskbar.
$script:RoboNativeSource = @'
using System;
using System.Runtime.InteropServices;

namespace RoboGo
{
    public static class Native
    {
        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetDiskFreeSpaceEx(string directory, out ulong freeForCaller, out ulong total, out ulong totalFree);

        // Bytes the caller may still write below this folder, or -1.
        public static long FreeSpace(string directory)
        {
            ulong free, total, totalFree;
            if (!GetDiskFreeSpaceEx(directory, out free, out total, out totalFree)) { return -1; }
            return free > (ulong)long.MaxValue ? long.MaxValue : (long)free;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FLASHWINFO
        {
            public uint cbSize;
            public IntPtr hwnd;
            public uint dwFlags;
            public uint uCount;
            public uint dwTimeout;
        }

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool FlashWindowEx(ref FLASHWINFO info);

        // Flashes the taskbar button until the window comes to the foreground.
        public static void Flash(IntPtr hwnd)
        {
            FLASHWINFO info = new FLASHWINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO));
            info.hwnd = hwnd;
            info.dwFlags = 2 | 12;
            info.uCount = uint.MaxValue;
            info.dwTimeout = 0;
            FlashWindowEx(ref info);
        }

        [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool PlaySound(string name, IntPtr module, uint flags);

        // Plays the sound the Windows sound scheme has for an event such as "SystemAsterisk".
        // The sound comes from this process, in the System Sounds entry of the volume mixer.
        // An event without a sound stays silent. The call does not wait for the sound to end,
        // so true only means that Windows took the request.
        public static bool PlayEvent(string name)
        {
            // SND_ASYNC 0x1, SND_NODEFAULT 0x2, SND_ALIAS 0x10000, SND_SYSTEM 0x200000
            return PlaySound(name, IntPtr.Zero, 0x1 | 0x2 | 0x10000 | 0x200000);
        }

        // The property store of a window holds what the taskbar needs to treat the window
        // and a pinned RoboGo.exe as one program: an application id, and how to start it again.
        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        private struct PROPERTYKEY
        {
            public Guid fmtid;
            public uint pid;
        }

        [StructLayout(LayoutKind.Explicit, Size = 24)]
        private struct PROPVARIANT
        {
            [FieldOffset(0)] public ushort vt;
            [FieldOffset(8)] public IntPtr pointer;
        }

        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPropertyStore
        {
            [PreserveSig] int GetCount(out uint count);
            [PreserveSig] int GetAt(uint index, out PROPERTYKEY key);
            [PreserveSig] int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
            [PreserveSig] int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
            [PreserveSig] int Commit();
        }

        [DllImport("shell32.dll")]
        private static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(ref PROPVARIANT value);

        // System.AppUserModel: 5 ID, 2 RelaunchCommand, 4 RelaunchDisplayNameResource, 3 RelaunchIconResource
        private static readonly Guid AppModel = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3");

        private static IPropertyStore Store(IntPtr hwnd)
        {
            Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
            IPropertyStore store;
            int result = SHGetPropertyStoreForWindow(hwnd, ref iid, out store);
            return result == 0 ? store : null;
        }

        private static void Put(IPropertyStore store, uint pid, string text)
        {
            PROPERTYKEY key = new PROPERTYKEY();
            key.fmtid = AppModel;
            key.pid = pid;
            PROPVARIANT value = new PROPVARIANT();
            if (!String.IsNullOrEmpty(text))
            {
                value.vt = 31;
                value.pointer = Marshal.StringToCoTaskMemUni(text);
            }
            try { store.SetValue(ref key, ref value); }
            finally { PropVariantClear(ref value); }
        }

        private static string Take(IPropertyStore store, uint pid)
        {
            PROPERTYKEY key = new PROPERTYKEY();
            key.fmtid = AppModel;
            key.pid = pid;
            PROPVARIANT value;
            if (store.GetValue(ref key, out value) != 0) { return ""; }
            try { return value.vt == 31 ? Marshal.PtrToStringUni(value.pointer) : ""; }
            finally { PropVariantClear(ref value); }
        }

        public static bool SetIdentity(IntPtr hwnd, string id, string command, string name, string icon)
        {
            IPropertyStore store = Store(hwnd);
            if (store == null) { return false; }
            try
            {
                Put(store, 2, command);
                Put(store, 4, name);
                Put(store, 3, icon);
                Put(store, 5, id);
                return store.Commit() == 0;
            }
            finally { Marshal.ReleaseComObject(store); }
        }

        // "id|command|name|icon" as the taskbar sees it.
        public static string GetIdentity(IntPtr hwnd)
        {
            IPropertyStore store = Store(hwnd);
            if (store == null) { return ""; }
            try { return Take(store, 5) + "|" + Take(store, 2) + "|" + Take(store, 4) + "|" + Take(store, 3); }
            finally { Marshal.ReleaseComObject(store); }
        }

        // Windows asks for the relaunch properties to be removed before the window goes away.
        public static void ClearIdentity(IntPtr hwnd)
        {
            IPropertyStore store = Store(hwnd);
            if (store == null) { return; }
            try
            {
                Put(store, 2, null);
                Put(store, 4, null);
                Put(store, 3, null);
                Put(store, 5, null);
                store.Commit();
            }
            finally { Marshal.ReleaseComObject(store); }
        }
    }
}
'@

function Initialize-RoboNative {
    # Compiles the helper type once per process.
    if ('RoboGo.Native' -as [type]) { return }
    Add-Type -TypeDefinition $script:RoboNativeSource
}

function Get-RoboFreeSpace {
    # Bytes the user may still write to the drive or share of a folder, or -1 when that
    # cannot be told. The folder need not exist yet: the nearest one above it is asked.
    param([string]$Path)
    $p = ConvertTo-RoboPath $Path
    if ($p -eq '') { return [long]-1 }
    try { $p = [System.IO.Path]::GetFullPath($p) }
    catch { return [long]-1 }
    while (-not (Test-Path -LiteralPath $p -PathType Container)) {
        $parent = [System.IO.Path]::GetDirectoryName($p)
        if ([string]::IsNullOrEmpty($parent)) { return [long]-1 }
        $p = $parent
    }
    try {
        Initialize-RoboNative
        return [long][RoboGo.Native]::FreeSpace($p.TrimEnd('\') + '\')
    }
    catch {
        return [long]-1
    }
}

# ============================================================================
# 2. Log parser. It reads the structure of robocopy's log (tabs, digits, the
#    percent sign, the 0x error code), never its words, so the Windows display
#    language does not matter.
# ============================================================================

$script:RxRoboError = New-Object System.Text.RegularExpressions.Regex '^\S.*\s\d+ \(0x[0-9A-Fa-f]{8}\)\s'
$script:RxRoboFailure = New-Object System.Text.RegularExpressions.Regex '\s(\d+ \(0x[0-9A-Fa-f]{8}\))\s+(\S.*)$'
$script:RxRoboSummary = New-Object System.Text.RegularExpressions.Regex '^\s*\S[^:]*:\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$'

function Split-RoboLogText {
    # Splits decoded log text into complete lines. Robocopy separates progress updates with
    # a bare CR, so CR and LF both end a line. An unfinished last line is returned in Rest,
    # except a percent update, which is complete as soon as its percent sign is there.
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return @{ Lines = @(); Rest = '' } }
    $last = [int]$Text[$Text.Length - 1]
    $complete = (($last -eq 10) -or ($last -eq 13))
    $pieces = $Text.Split([char[]]@([char]13, [char]10), [System.StringSplitOptions]::RemoveEmptyEntries)
    $rest = ''
    if ((-not $complete) -and ($pieces.Length -gt 0)) {
        $tail = $pieces[$pieces.Length - 1]
        $isPercent = (([int]$tail[0] -ne 9) -and $tail.TrimEnd().EndsWith('%'))
        if (-not $isPercent) {
            $rest = $tail
            if ($pieces.Length -eq 1) { $pieces = @() } else { $pieces = $pieces[0..($pieces.Length - 2)] }
        }
    }
    return @{ Lines = $pieces; Rest = $rest }
}

function New-RoboProgress {
    # State for Update-RoboProgress. Threads decides how many unfinished files may be pending
    # at once. DestinationPath lets the parser recognise extra files by their location.
    param([int]$Threads = 1, [string]$DestinationPath = '')
    $prefix = ''
    $dst = ConvertTo-RoboPath $DestinationPath
    if ($dst -ne '') {
        try { $dst = [System.IO.Path]::GetFullPath($dst) } catch { }
        $prefix = $dst.TrimEnd('\') + '\'
    }
    return @{
        MaxPending     = $(if ($Threads -le 1) { 1 } else { $Threads * 4 })
        DestPrefix     = $prefix
        Pending        = (New-Object System.Collections.Generic.List[object])
        CompletedFiles = 0
        CompletedBytes = [long]0
        SeenFiles      = 0
        SeenBytes      = [long]0
        ExtraFiles     = 0
        ExtraDirs      = 0
        Errors         = 0
        LastError      = ''
        Failures       = (New-Object System.Collections.Generic.List[object])
        FailureKeys    = (New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase))
        FailurePending = $null
        CurrentFile    = ''
        SummaryRows    = (New-Object System.Collections.Generic.List[object])
        Summary        = $null
    }
}

function ConvertTo-RoboSummary {
    # Rows arrive in a fixed order: Dirs, Files, Bytes. Columns are fixed too.
    param($Rows)
    $columns = @('Total', 'Copied', 'Skipped', 'Mismatch', 'Failed', 'Extras')
    $names = @('Dirs', 'Files', 'Bytes')
    $summary = @{}
    for ($r = 0; $r -lt 3; $r++) {
        $row = @{}
        for ($k = 0; $k -lt 6; $k++) { $row[$columns[$k]] = $Rows[$r][$k] }
        $summary[$names[$r]] = $row
    }
    return $summary
}

function Update-RoboProgress {
    # Feeds log lines into the state.
    #   file line    TAB class TAB TAB size TAB path     -> a file robocopy is about to copy
    #   percent      "  6.2%" ... "100%"                 -> progress of the newest pending file
    #   error        "date time ERROR 32 (0x00000020) "  -> counted, the file stays unfinished;
    #                                                        listed once in Failures, with the
    #                                                        message robocopy prints on the next line
    #   summary row  "  Files :  4  4  0  0  0  1"       -> the final numbers
    # A file counts as copied only when its 100% arrives.
    param([hashtable]$State, [string[]]$Lines)
    foreach ($line in $Lines) {
        if ($line.Length -eq 0) { continue }
        $first = [int]$line[0]
        if ($first -eq 9) {
            $State.FailurePending = $null
            $cells = $line.Split([char]9)
            if (($cells.Length -ge 5) -and ($cells[2].Length -eq 0)) {
                $size = [long]0
                if (-not [long]::TryParse($cells[3].Trim(), [ref]$size)) { continue }
                $class = $cells[1].Trim()
                $path = $cells[4]
                $extra = $class.StartsWith('*')
                if ((-not $extra) -and ($State.DestPrefix -ne '') -and $path.StartsWith($State.DestPrefix, [System.StringComparison]::OrdinalIgnoreCase)) { $extra = $true }
                if ($extra) {
                    $State.ExtraFiles++
                    continue
                }
                $known = $false
                for ($i = $State.Pending.Count - 1; $i -ge 0; $i--) {
                    if ($State.Pending[$i].Path -eq $path) {
                        # the same file again: robocopy is retrying it
                        $State.Pending[$i].Pct = 0.0
                        $known = $true
                        break
                    }
                }
                if (-not $known) {
                    $State.SeenFiles++
                    $State.SeenBytes += $size
                    while ($State.Pending.Count -ge $State.MaxPending) { $State.Pending.RemoveAt(0) }
                    $State.Pending.Add(@{ Path = $path; Size = $size; Pct = 0.0 })
                }
                $State.CurrentFile = $path
            }
            elseif (($cells.Length -eq 3) -and $cells[2].EndsWith('\') -and $cells[1].TrimStart().StartsWith('*')) {
                $State.ExtraDirs++
            }
            continue
        }
        $text = $line.Trim()
        if ($text.Length -eq 0) { continue }
        if ($text.EndsWith('%')) {
            $pct = 0.0
            $number = $text.Substring(0, $text.Length - 1).Trim().Replace(',', '.')
            if ([double]::TryParse($number, [System.Globalization.NumberStyles]::Float, $script:Inv, [ref]$pct)) {
                $n = $State.Pending.Count
                if ($n -gt 0) {
                    if ($pct -ge 100) {
                        $State.CompletedBytes += $State.Pending[$n - 1].Size
                        $State.CompletedFiles++
                        $State.Pending.RemoveAt($n - 1)
                    }
                    else {
                        $State.Pending[$n - 1].Pct = $pct
                    }
                }
                continue
            }
        }
        if (($line.IndexOf('(0x') -gt 0) -and $script:RxRoboError.IsMatch($line)) {
            $State.Errors++
            $State.LastError = $text
            # Retries print the same error again: every path with its code is kept once.
            $State.FailurePending = $null
            $m = $script:RxRoboFailure.Match($line)
            if ($m.Success) {
                $what = $m.Groups[2].Value.Trim()
                $code = $m.Groups[1].Value
                if (($State.Failures.Count -lt 2000) -and $State.FailureKeys.Add($what + '|' + $code)) {
                    $entry = @{ What = $what; Code = $code; Detail = '' }
                    $State.Failures.Add($entry)
                    $State.FailurePending = $entry
                }
            }
            continue
        }
        if ($null -ne $State.FailurePending) {
            # the line after a new error is what Windows says about it
            $State.FailurePending.Detail = $text
            $State.FailurePending = $null
            continue
        }
        if (($first -eq 32) -and ($State.SummaryRows.Count -lt 3) -and ($line.IndexOf(':') -gt 0)) {
            $m = $script:RxRoboSummary.Match($line)
            if ($m.Success) {
                $row = New-Object 'long[]' 6
                for ($k = 0; $k -lt 6; $k++) { $row[$k] = [long]$m.Groups[$k + 1].Value }
                $State.SummaryRows.Add($row)
                if ($State.SummaryRows.Count -eq 3) { $State.Summary = ConvertTo-RoboSummary $State.SummaryRows }
            }
        }
    }
}

function Get-RoboFailureLines {
    # One text per failure, on two short lines so that nothing important ends up beyond the
    # right edge of the log box: what robocopy was doing with which path, and indented
    # below it the error code and the message of Windows.
    param([hashtable]$State)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($failure in $State.Failures) {
        $second = '    ' + $failure.Code
        if ($failure.Detail -ne '') { $second += '  ' + $failure.Detail }
        $lines.Add($failure.What + [Environment]::NewLine + $second)
    }
    return , $lines.ToArray()
}

function Get-RoboDoneBytes {
    # Bytes copied so far: finished files plus the copied share of the unfinished ones.
    param([hashtable]$State)
    $bytes = [double]$State.CompletedBytes
    foreach ($p in $State.Pending) {
        if ($p.Pct -gt 0) { $bytes += $p.Size * $p.Pct / 100.0 }
    }
    return $bytes
}

function Get-RoboVerdict {
    # Turns robocopy's exit code (a bit mask: 1 copied, 2 extras, 4 mismatches, 8 failures,
    # 16 fatal) and the summary into one sentence. Level is ok, warn or error.
    param([int]$ExitCode, $Summary, [switch]$DryRun, [switch]$Cancelled, [switch]$Mirror)
    if ($Cancelled) {
        return @{ Level = 'warn'; Text = (Get-RoboText 'verdict.cancelled') }
    }
    # whole sentences, joined by a space: nothing a translator has to glue together
    $parts = New-Object System.Collections.Generic.List[string]
    if ($Summary) {
        $key = 'verdict.copied'
        if ($DryRun) { $key = 'verdict.wouldCopy' }
        $parts.Add((Get-RoboText $key $Summary.Files.Copied, (Format-RoboBytes $Summary.Bytes.Copied)))
        if ($Summary.Files.Skipped -gt 0) { $parts.Add((Get-RoboText 'verdict.skipped' $Summary.Files.Skipped)) }
        if ($Summary.Files.Failed -gt 0) { $parts.Add((Get-RoboText 'verdict.failed' $Summary.Files.Failed)) }
        $extras = $Summary.Files.Extras + $Summary.Dirs.Extras
        if ($extras -gt 0) {
            if ($Mirror -and $DryRun) { $parts.Add((Get-RoboText 'verdict.extrasWould' $extras)) }
            elseif ($Mirror) { $parts.Add((Get-RoboText 'verdict.extrasDeleted' $extras)) }
            else { $parts.Add((Get-RoboText 'verdict.extrasLeft' $extras)) }
        }
    }
    $detail = ($parts -join ' ')
    if (($ExitCode -lt 0) -or ($ExitCode -ge 16)) {
        return @{ Level = 'error'; Text = (Get-RoboText 'verdict.fatal' $ExitCode) }
    }
    if (($ExitCode -band 8) -ne 0) {
        return @{ Level = 'error'; Text = (Get-RoboText 'verdict.errors' $detail).Replace('  ', ' ') }
    }
    if ($DryRun) {
        return @{ Level = 'ok'; Text = (Get-RoboText 'verdict.dry' $detail).Trim() }
    }
    if (($ExitCode -band 4) -ne 0) {
        return @{ Level = 'warn'; Text = (Get-RoboText 'verdict.mismatch' $detail).Trim() }
    }
    if (($ExitCode -band 1) -ne 0) {
        return @{ Level = 'ok'; Text = (Get-RoboText 'verdict.done' $detail).Trim() }
    }
    return @{ Level = 'ok'; Text = (Get-RoboText 'verdict.nothing' $detail).Trim() }
}

# ============================================================================
# 3. Engine: start robocopy hidden, follow its log file, stop it.
#    Progress comes from a /UNILOG file because that is real UTF-16. Robocopy's
#    piped output is OEM code page text and turns many characters into "?".
#    The file is a working file in TEMP: Close-RoboJobLog deletes it when the
#    job is over, or moves it next to the program when the user keeps logs.
#    Limit-RoboLogs clears out what is too old or too big at every start.
# ============================================================================

function Get-RoboLogDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) 'RoboGo'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    return $dir
}

function New-RoboLogPath {
    param([string]$Kind)
    $stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff', $script:Inv)
    return (Join-Path (Get-RoboLogDir) ($stamp + '-' + $Kind.ToLowerInvariant() + '.log'))
}

function Get-RoboKeptLogDir {
    # Where logs go when the user wants to keep them: next to the program.
    return (Join-Path $script:RoboDataDir 'logs')
}

function Test-RoboFileFree {
    # Can the file be opened for us alone? No while any program has it open, robocopy in
    # the middle of a job included.
    param([string]$Path)
    try {
        $probe = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $probe.Dispose()
        return $true
    }
    catch {
        return $false
    }
}

function Limit-RoboLogs {
    # Housekeeping at every start, for the working folder in TEMP and for the kept logs,
    # each folder on its own:
    #   1. logs older than Days go,
    #   2. logs bigger than MaxFileMB go, whatever their age,
    #   3. while the rest is bigger than MaxTotalMB together, the oldest log goes.
    # 1 MB is 1,048,576 bytes. A log that some program has open is never touched: another
    # RoboGo window may be in the middle of a job and reading exactly that file.
    # CmdletBinding makes a mistyped parameter an error instead of a silent run against the
    # default folders.
    [CmdletBinding()]
    param(
        [double]$Days = $script:RoboLogLimits.LogMaxDays,
        [double]$MaxFileMB = $script:RoboLogLimits.LogFileMaxMB,
        [double]$MaxTotalMB = $script:RoboLogLimits.LogMaxMB,
        [string[]]$Directory = @((Get-RoboLogDir), (Get-RoboKeptLogDir))
    )
    $oldest = (Get-Date).AddDays(-$Days)
    $fileLimit = $MaxFileMB * 1048576
    $totalLimit = $MaxTotalMB * 1048576
    foreach ($dir in $Directory) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        $rest = New-Object System.Collections.Generic.List[object]
        foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.log' -File -ErrorAction SilentlyContinue)) {
            $unwanted = (($file.LastWriteTime -lt $oldest) -or ($file.Length -gt $fileLimit))
            if ($unwanted -and (Test-RoboFileFree $file.FullName)) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            }
            else {
                $rest.Add($file)
            }
        }
        $total = [double]0
        foreach ($file in $rest) { $total += $file.Length }
        foreach ($file in @($rest | Sort-Object LastWriteTime)) {
            if ($total -le $totalLimit) { break }
            if (-not (Test-RoboFileFree $file.FullName)) { continue }
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            $total -= $file.Length
        }
    }
}

function Close-RoboJobLog {
    # Call when a job is over. The working log in TEMP is deleted, or with -Keep moved to the
    # logs folder next to the program. Returns the path of the kept file, or '' when nothing
    # was kept. A file that cannot be moved or deleted is left to the cleanup at a later start.
    param([hashtable]$Job, [switch]$Keep)
    $kept = ''
    if ($null -ne $Job.Stream) {
        $Job.Stream.Dispose()
        $Job.Stream = $null
    }
    if (Test-Path -LiteralPath $Job.LogPath) {
        try {
            if ($Keep) {
                $dir = Get-RoboKeptLogDir
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                $target = Join-Path $dir ([System.IO.Path]::GetFileName($Job.LogPath))
                Move-Item -LiteralPath $Job.LogPath -Destination $target -Force
                $Job.LogPath = $target
                $kept = $target
            }
            else {
                Remove-Item -LiteralPath $Job.LogPath -Force
            }
        }
        catch {
            # the program folder is not writable: the log stays where robocopy wrote it
            if ($Keep) { $kept = $Job.LogPath }
        }
    }
    return $kept
}

function Start-RoboJob {
    # Starts robocopy without a window. Kind is Run, Scan or DryRun. Returns the job that
    # Read-RoboJob polls.
    param($Options, [ValidateSet('Run', 'Scan', 'DryRun')][string]$Kind)
    $log = New-RoboLogPath $Kind
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $script:RoboExe
    $info.Arguments = Get-RoboArguments $Options $Kind $log
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($info)
    return @{
        Kind      = $Kind
        Process   = $process
        Arguments = $info.Arguments
        LogPath   = $log
        Stream    = $null
        Decoder   = [System.Text.Encoding]::Unicode.GetDecoder()
        Buffer    = (New-Object 'byte[]' 262144)
        Chars     = (New-Object 'char[]' 262144)
        Rest      = ''
        First     = $true
        State     = (New-RoboProgress -Threads ([int]$Options.Threads) -DestinationPath $Options.Destination)
        Done      = $false
        ExitCode  = $null
    }
}

function Read-RoboJob {
    # Reads what robocopy appended to its log since the last call and updates Job.State.
    # Returns the new lines worth showing (blank lines and bare percent updates removed).
    # Sets Job.Done and Job.ExitCode once robocopy has exited and the log is fully read.
    # BudgetMs caps the time spent per call so the window stays responsive on huge logs.
    param([hashtable]$Job, [int]$BudgetMs = 120)
    $display = New-Object System.Collections.Generic.List[string]
    if ($Job.Done) { return , $display.ToArray() }
    # Ask before reading: if robocopy has already exited, this read sees everything it wrote.
    $exited = $Job.Process.HasExited
    if (($null -eq $Job.Stream) -and (Test-Path -LiteralPath $Job.LogPath)) {
        try {
            $Job.Stream = New-Object System.IO.FileStream($Job.LogPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, ([System.IO.FileShare]'ReadWrite, Delete'))
        }
        catch {
            $Job.Stream = $null
        }
    }
    $drained = $true
    if ($null -ne $Job.Stream) {
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        while ($true) {
            $count = $Job.Stream.Read($Job.Buffer, 0, $Job.Buffer.Length)
            if ($count -le 0) { break }
            $chars = $Job.Decoder.GetChars($Job.Buffer, 0, $count, $Job.Chars, 0)
            $text = $Job.Rest + [string]::new($Job.Chars, 0, $chars)
            if ($Job.First) {
                $text = $text.TrimStart([char]0xFEFF)
                $Job.First = $false
            }
            $split = Split-RoboLogText $text
            $Job.Rest = $split.Rest
            if ($split.Lines.Length -gt 0) {
                Update-RoboProgress -State $Job.State -Lines $split.Lines
                foreach ($line in $split.Lines) {
                    $trimmed = $line.Trim()
                    if ($trimmed.Length -eq 0) { continue }
                    if ($trimmed.EndsWith('%') -and ([int]$line[0] -ne 9)) { continue }
                    $display.Add($line)
                }
            }
            if ((-not $exited) -and ($clock.ElapsedMilliseconds -ge $BudgetMs)) {
                $drained = $false
                break
            }
        }
    }
    if ($exited -and $drained) {
        if ($Job.Rest.Trim() -ne '') {
            Update-RoboProgress -State $Job.State -Lines @($Job.Rest)
            $display.Add($Job.Rest)
        }
        $Job.Rest = ''
        $Job.Process.WaitForExit()
        $Job.ExitCode = $Job.Process.ExitCode
        if ($null -ne $Job.Stream) {
            $Job.Stream.Dispose()
            $Job.Stream = $null
        }
        $Job.Done = $true
    }
    return , $display.ToArray()
}

function Stop-RoboJob {
    # Kills robocopy. Files already copied stay where they are.
    param([hashtable]$Job)
    try {
        if (-not $Job.Process.HasExited) {
            $Job.Process.Kill()
            [void]$Job.Process.WaitForExit(3000)
        }
    }
    catch { }
}

function Wait-RoboJob {
    # Polls a job to its end and returns every display line. The window does the same from
    # a timer; this blocking version is for the tests and the self-test.
    param([hashtable]$Job, [int]$TimeoutSec = 600, [scriptblock]$OnTick)
    $all = New-Object System.Collections.Generic.List[string]
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $Job.Done) {
        foreach ($line in (Read-RoboJob $Job)) { $all.Add($line) }
        if ($OnTick) { & $OnTick $Job }
        if ($Job.Done) { break }
        if ($clock.Elapsed.TotalSeconds -gt $TimeoutSec) {
            Stop-RoboJob $Job
            throw 'The robocopy job did not finish in time.'
        }
        Start-Sleep -Milliseconds 50
    }
    return , $all.ToArray()
}

function New-RoboSpeedMeter {
    return @{ Samples = (New-Object System.Collections.Generic.List[object]); WindowSec = 5.0 }
}

function Add-RoboSpeedSample {
    # Records "Bytes done at Seconds" and forgets samples older than the window.
    param($Meter, [double]$Bytes, [double]$Seconds)
    $Meter.Samples.Add(@{ Time = $Seconds; Bytes = $Bytes })
    while (($Meter.Samples.Count -gt 2) -and (($Seconds - $Meter.Samples[0].Time) -gt $Meter.WindowSec)) {
        $Meter.Samples.RemoveAt(0)
    }
}

function Get-RoboSpeed {
    # Bytes per second between the oldest and the newest sample in the window.
    param($Meter)
    $n = $Meter.Samples.Count
    if ($n -lt 2) { return 0.0 }
    $span = $Meter.Samples[$n - 1].Time - $Meter.Samples[0].Time
    if ($span -le 0) { return 0.0 }
    return [math]::Max(0.0, ($Meter.Samples[$n - 1].Bytes - $Meter.Samples[0].Bytes) / $span)
}

# ============================================================================
# 4. Window. Look: an instrument panel. Near-black, one amber accent, red only
#    for things that delete, monospace type because the subject is a command.
#    The XAML holds no texts: Update-RoboGoLanguage puts them on the controls.
# ============================================================================

$script:RoboGoControls = @(
    'Root', 'LblSubtitle', 'TxtVersion', 'BtnSendTo', 'BtnLang',
    'LblPaths', 'LblFrom', 'TxtSource', 'BtnRecentSource', 'BtnSource', 'LblTo', 'TxtDest', 'BtnRecentDest', 'BtnDest',
    'RecentPopup', 'RecentPanel', 'RecentList',
    'LblOptions', 'RbCopy', 'RbMirror', 'RbMove', 'LblThreads', 'TxtThreads', 'LblRetries', 'TxtRetries', 'LblWait', 'TxtWait',
    'TxtModeHint', 'ChkSub', 'ChkJunction', 'ChkNewer', 'ChkRestart',
    'LblSkipFiles', 'TxtXF', 'LblSkipDirs', 'TxtXD', 'LblExtra', 'TxtExtra', 'BtnHelp',
    'HelpPopup', 'HelpPanel', 'HelpScroll', 'LblHelpSetups', 'LblHelpSetupNote', 'HelpSetups', 'LblHelpSwitches', 'LblHelpNote', 'HelpSwitches',
    'LblCommand', 'BtnCopyCmd', 'BtnTape', 'TapeEdge', 'TapeClip', 'TapeMore', 'CmdPanel', 'TxtProblem', 'ChkScan', 'ChkKeepLog', 'BtnDry', 'BtnRun', 'BtnCancel',
    'LblProgress', 'BtnToggleLog', 'BtnCopyLog', 'BtnFailed', 'BtnOpenLog', 'Bar', 'TxtPercent',
    'LblFiles', 'TxtFiles', 'LblData', 'TxtData', 'LblSpeed', 'TxtSpeed', 'LblEta', 'TxtEta',
    'TxtCurrent', 'TxtStatus', 'TxtLog'
)
# Controls that are locked while a job runs.
$script:RoboGoInputs = @(
    'TxtSource', 'BtnRecentSource', 'BtnSource', 'TxtDest', 'BtnRecentDest', 'BtnDest', 'RbCopy', 'RbMirror', 'RbMove',
    'ChkSub', 'ChkJunction', 'ChkNewer', 'ChkRestart', 'TxtThreads', 'TxtRetries', 'TxtWait',
    'TxtXF', 'TxtXD', 'TxtExtra', 'ChkScan', 'BtnDry', 'BtnRun', 'HelpPanel'
)
# Which text goes where: control, property, key in the text table. Tag is the example
# text a field shows while it is empty.
$script:RoboGoTextMap = @(
    @('LblSubtitle', 'Text', 'ui.subtitle'),
    @('BtnLang', 'ToolTip', 'tip.language'),
    @('BtnSendTo', 'Content', 'ui.sendTo'),
    @('BtnSendTo', 'ToolTip', 'tip.sendTo'),
    @('BtnRecentSource', 'ToolTip', 'tip.recent'),
    @('BtnRecentDest', 'ToolTip', 'tip.recent'),
    @('BtnTape', 'ToolTip', 'tip.tape'),
    @('BtnFailed', 'ToolTip', 'tip.failed'),
    @('LblPaths', 'Text', 'ui.paths'),
    @('LblOptions', 'Text', 'ui.options'),
    @('LblCommand', 'Text', 'ui.command'),
    @('LblProgress', 'Text', 'ui.progress'),
    @('LblFrom', 'Text', 'ui.from'),
    @('TxtSource', 'Tag', 'ph.source'),
    @('TxtSource', 'ToolTip', 'tip.source'),
    @('BtnSource', 'Content', 'ui.browse'),
    @('LblTo', 'Text', 'ui.to'),
    @('TxtDest', 'Tag', 'ph.dest'),
    @('TxtDest', 'ToolTip', 'tip.dest'),
    @('BtnDest', 'Content', 'ui.browse'),
    @('RbCopy', 'Content', 'ui.copy'),
    @('RbCopy', 'ToolTip', 'tip.copy'),
    @('RbMirror', 'Content', 'ui.mirror'),
    @('RbMirror', 'ToolTip', 'tip.mirror'),
    @('RbMove', 'Content', 'ui.move'),
    @('RbMove', 'ToolTip', 'tip.move'),
    @('LblThreads', 'Text', 'ui.threads'),
    @('TxtThreads', 'ToolTip', 'tip.threads'),
    @('LblRetries', 'Text', 'ui.retries'),
    @('TxtRetries', 'ToolTip', 'tip.retries'),
    @('LblWait', 'Text', 'ui.wait'),
    @('TxtWait', 'ToolTip', 'tip.wait'),
    @('ChkSub', 'Content', 'ui.subfolders'),
    @('ChkSub', 'ToolTip', 'tip.subfolders'),
    @('ChkJunction', 'Content', 'ui.junctions'),
    @('ChkJunction', 'ToolTip', 'tip.junctions'),
    @('ChkNewer', 'Content', 'ui.newer'),
    @('ChkNewer', 'ToolTip', 'tip.newer'),
    @('ChkRestart', 'Content', 'ui.restartable'),
    @('ChkRestart', 'ToolTip', 'tip.restartable'),
    @('LblSkipFiles', 'Text', 'ui.skipFiles'),
    @('TxtXF', 'Tag', 'ph.skipFiles'),
    @('TxtXF', 'ToolTip', 'tip.skipFiles'),
    @('LblSkipDirs', 'Text', 'ui.skipDirs'),
    @('TxtXD', 'Tag', 'ph.skipDirs'),
    @('TxtXD', 'ToolTip', 'tip.skipDirs'),
    @('LblExtra', 'Text', 'ui.extra'),
    @('TxtExtra', 'Tag', 'ph.extra'),
    @('TxtExtra', 'ToolTip', 'tip.extra'),
    @('BtnHelp', 'ToolTip', 'tip.help'),
    @('LblHelpSetups', 'Text', 'ui.helpSetups'),
    @('LblHelpSetupNote', 'Text', 'ui.helpSetupNote'),
    @('LblHelpSwitches', 'Text', 'ui.helpSwitches'),
    @('LblHelpNote', 'Text', 'ui.helpNote'),
    @('BtnCopyCmd', 'Content', 'ui.copyCommand'),
    @('BtnCopyCmd', 'ToolTip', 'tip.copyCommand'),
    @('ChkScan', 'Content', 'ui.scan'),
    @('ChkScan', 'ToolTip', 'tip.scan'),
    @('ChkKeepLog', 'Content', 'ui.keepLog'),
    @('ChkKeepLog', 'ToolTip', 'tip.keepLog'),
    @('BtnDry', 'Content', 'ui.dryRun'),
    @('BtnDry', 'ToolTip', 'tip.dryRun'),
    @('BtnRun', 'Content', 'ui.run'),
    @('BtnCancel', 'Content', 'ui.cancel'),
    @('BtnCopyLog', 'Content', 'ui.copyLog'),
    @('BtnCopyLog', 'ToolTip', 'tip.copyLog'),
    @('BtnOpenLog', 'Content', 'ui.openLog'),
    @('BtnOpenLog', 'ToolTip', 'tip.openLog'),
    @('LblFiles', 'Text', 'ui.files'),
    @('LblData', 'Text', 'ui.data'),
    @('LblSpeed', 'Text', 'ui.speed')
)
$script:RoboGoPartBrush = @{ 'exe' = 'Dim'; 'path' = 'Ink'; 'switch' = 'Amber'; 'danger' = 'Danger'; 'value' = 'Ink' }
$script:RoboGo = $null

function Get-RoboGoXaml {
    return @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="RoboGo" Width="760" Height="620" MinWidth="700" MinHeight="580"
        WindowStartupLocation="CenterScreen" Background="#0B0C0E" Foreground="#E8E6E1"
        FontFamily="Cascadia Mono, Cascadia Code, Consolas" FontSize="12.5"
        UseLayoutRounding="True" SnapsToDevicePixels="True">
  <Window.Resources>
    <SolidColorBrush x:Key="Bg0" Color="#0B0C0E"/>
    <SolidColorBrush x:Key="Bg1" Color="#131518"/>
    <SolidColorBrush x:Key="Bg2" Color="#1B1E22"/>
    <SolidColorBrush x:Key="Line" Color="#2A2E34"/>
    <SolidColorBrush x:Key="Ink" Color="#E8E6E1"/>
    <SolidColorBrush x:Key="Dim" Color="#8A8D91"/>
    <SolidColorBrush x:Key="Amber" Color="#FFB000"/>
    <SolidColorBrush x:Key="Danger" Color="#FF4D3D"/>
    <SolidColorBrush x:Key="Ok" Color="#6BD968"/>
    <SolidColorBrush x:Key="{x:Static SystemColors.ControlBrushKey}" Color="#0B0C0E"/>
    <LinearGradientBrush x:Key="SegOn" MappingMode="Absolute" SpreadMethod="Repeat" StartPoint="0,0" EndPoint="9,0">
      <GradientStop Color="#FFB000" Offset="0"/>
      <GradientStop Color="#FFB000" Offset="0.667"/>
      <GradientStop Color="#00FFB000" Offset="0.667"/>
      <GradientStop Color="#00FFB000" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="SegOff" MappingMode="Absolute" SpreadMethod="Repeat" StartPoint="0,0" EndPoint="9,0">
      <GradientStop Color="#24282D" Offset="0"/>
      <GradientStop Color="#24282D" Offset="0.667"/>
      <GradientStop Color="#0024282D" Offset="0.667"/>
      <GradientStop Color="#0024282D" Offset="1"/>
    </LinearGradientBrush>

    <Style x:Key="Section" TargetType="Border">
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="0,1,0,0"/>
      <Setter Property="Padding" Value="0,7,0,7"/>
    </Style>
    <Style x:Key="Rail" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="MinWidth" Value="76"/>
      <Setter Property="Margin" Value="0,5,10,0"/>
      <Setter Property="VerticalAlignment" Value="Top"/>
    </Style>
    <Style x:Key="Lbl" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>
    <Style x:Key="Head" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Amber}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="Bold"/>
    </Style>
    <Style x:Key="Note" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Margin" Value="0,2,0,0"/>
    </Style>

    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="{StaticResource Bg2}"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="FontFamily" Value="Cascadia Mono, Cascadia Code, Consolas"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="Padding" Value="8,5"/>
      <Setter Property="ContentTemplate">
        <Setter.Value>
          <DataTemplate>
            <TextBlock Text="{Binding}" TextWrapping="Wrap" MaxWidth="430"/>
          </DataTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{StaticResource Bg2}"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CaretBrush" Value="{StaticResource Amber}"/>
      <Setter Property="SelectionBrush" Value="{StaticResource Amber}"/>
      <Setter Property="Padding" Value="7,3"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
              <Grid>
                <TextBlock x:Name="Hint" Text="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}" Margin="{TemplateBinding Padding}" Padding="9,0,0,0" VerticalAlignment="Center" Foreground="{StaticResource Dim}" Opacity="0.6" IsHitTestVisible="False" TextTrimming="CharacterEllipsis" Visibility="Collapsed"/>
                <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="Text" Value="">
                <Setter TargetName="Hint" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Amber}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.5"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="Button">
      <Setter Property="Background" Value="{StaticResource Bg2}"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,4"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Amber}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Amber}"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.7"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="{StaticResource Amber}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Amber}"/>
      <Setter Property="Foreground" Value="#0B0C0E"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#FFC64D"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="Small" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Padding" Value="8,3"/>
      <Setter Property="FontSize" Value="10.5"/>
      <Setter Property="HorizontalAlignment" Value="Left"/>
    </Style>

    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="Box" Width="16" Height="16" VerticalAlignment="Center" Background="{StaticResource Bg2}" BorderBrush="{StaticResource Line}" BorderThickness="1">
                <Rectangle x:Name="Mark" Width="8" Height="8" Fill="{StaticResource Amber}" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Mark" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Amber}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Amber}"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="Seg" TargetType="RadioButton">
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="Bd" Background="{StaticResource Bg2}" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="14,4" Margin="0,0,-1,0">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Foreground" Value="{StaticResource Ink}"/>
              </Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True">
                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Amber}"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Amber}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Amber}"/>
                <Setter Property="Foreground" Value="#0B0C0E"/>
                <Setter Property="FontWeight" Value="Bold"/>
              </Trigger>
              <MultiTrigger>
                <MultiTrigger.Conditions>
                  <Condition Property="IsChecked" Value="True"/>
                  <Condition Property="Tag" Value="danger"/>
                </MultiTrigger.Conditions>
                <Setter TargetName="Bd" Property="Background" Value="{StaticResource Danger}"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Danger}"/>
              </MultiTrigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="16"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid ClipToBounds="True">
              <Rectangle x:Name="PART_Track" Fill="{StaticResource SegOff}"/>
              <Rectangle x:Name="PART_Indicator" HorizontalAlignment="Left" Fill="{StaticResource SegOn}"/>
              <Rectangle x:Name="Sweep" Width="126" HorizontalAlignment="Left" Fill="{StaticResource SegOn}" Visibility="Collapsed">
                <Rectangle.RenderTransform>
                  <TranslateTransform X="0"/>
                </Rectangle.RenderTransform>
              </Rectangle>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsIndeterminate" Value="True">
                <Setter TargetName="Sweep" Property="Visibility" Value="Visible"/>
                <Setter TargetName="PART_Indicator" Property="Visibility" Value="Collapsed"/>
                <Trigger.EnterActions>
                  <BeginStoryboard x:Name="SweepStory">
                    <Storyboard RepeatBehavior="Forever" AutoReverse="True">
                      <DoubleAnimation Storyboard.TargetName="Sweep" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" From="0" To="432" Duration="0:0:1.4"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.EnterActions>
                <Trigger.ExitActions>
                  <StopStoryboard BeginStoryboardName="SweepStory"/>
                </Trigger.ExitActions>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="ScrollBar">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Width" Value="10"/>
      <Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Grid Background="{TemplateBinding Background}">
              <Track x:Name="PART_Track" IsDirectionReversed="True">
                <Track.Thumb>
                  <Thumb>
                    <Thumb.Template>
                      <ControlTemplate TargetType="Thumb">
                        <Border Background="#3A3F47" Margin="3,0,1,0"/>
                      </ControlTemplate>
                    </Thumb.Template>
                  </Thumb>
                </Track.Thumb>
              </Track>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="MinWidth" Value="0"/>
          <Setter Property="Height" Value="10"/>
          <Setter Property="MinHeight" Value="10"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Grid Background="{TemplateBinding Background}">
                  <Track x:Name="PART_Track" IsDirectionReversed="False">
                    <Track.Thumb>
                      <Thumb>
                        <Thumb.Template>
                          <ControlTemplate TargetType="Thumb">
                            <Border Background="#3A3F47" Margin="0,3,0,1"/>
                          </ControlTemplate>
                        </Thumb.Template>
                      </Thumb>
                    </Track.Thumb>
                  </Track>
                </Grid>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Border x:Name="Root" Background="{StaticResource Bg0}" Padding="16,10,16,10">
    <Grid Grid.IsSharedSizeScope="True">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <DockPanel Grid.Row="0" Margin="0,0,0,6" LastChildFill="False">
        <TextBlock DockPanel.Dock="Left" Text="ROBOGO" FontSize="18" FontWeight="Bold" Foreground="{StaticResource Amber}"/>
        <TextBlock x:Name="LblSubtitle" DockPanel.Dock="Left" Margin="12,0,0,3" VerticalAlignment="Bottom" FontSize="11.5" Foreground="{StaticResource Dim}"/>
        <Button x:Name="BtnLang" DockPanel.Dock="Right" Style="{StaticResource Small}" MinWidth="34" VerticalAlignment="Center"/>
        <Button x:Name="BtnSendTo" DockPanel.Dock="Right" Style="{StaticResource Small}" Margin="0,0,6,0" VerticalAlignment="Center" Foreground="{StaticResource Dim}"/>
        <TextBlock x:Name="TxtVersion" DockPanel.Dock="Right" Margin="0,0,10,3" VerticalAlignment="Bottom" FontSize="11" Foreground="{StaticResource Dim}"/>
      </DockPanel>

      <Border Grid.Row="1" Style="{StaticResource Section}">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto" SharedSizeGroup="Rail"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <TextBlock x:Name="LblPaths" Style="{StaticResource Rail}"/>
          <Grid Grid.Column="1">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto" SharedSizeGroup="Lbl"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock x:Name="LblFrom" Style="{StaticResource Lbl}" Margin="0,0,10,0"/>
            <TextBox x:Name="TxtSource" Grid.Column="1" AllowDrop="True"/>
            <Button x:Name="BtnRecentSource" Grid.Column="2" Margin="-1,0,0,0" Padding="7,4" IsEnabled="False">
              <Path Data="M0,0 L4,4 L8,0" Stroke="{StaticResource Ink}" StrokeThickness="1.5" VerticalAlignment="Center"/>
            </Button>
            <Button x:Name="BtnSource" Grid.Column="3" Margin="6,0,0,0"/>
            <TextBlock x:Name="LblTo" Grid.Row="1" Style="{StaticResource Lbl}" Margin="0,6,10,0"/>
            <TextBox x:Name="TxtDest" Grid.Row="1" Grid.Column="1" Margin="0,6,0,0" AllowDrop="True"/>
            <Button x:Name="BtnRecentDest" Grid.Row="1" Grid.Column="2" Margin="-1,6,0,0" Padding="7,4" IsEnabled="False">
              <Path Data="M0,0 L4,4 L8,0" Stroke="{StaticResource Ink}" StrokeThickness="1.5" VerticalAlignment="Center"/>
            </Button>
            <Button x:Name="BtnDest" Grid.Row="1" Grid.Column="3" Margin="6,6,0,0"/>
            <Popup x:Name="RecentPopup" Grid.Column="1" Placement="Custom" StaysOpen="False" PopupAnimation="None">
              <Border x:Name="RecentPanel" MinWidth="260" Background="{StaticResource Bg1}" BorderBrush="{StaticResource Amber}" BorderThickness="1" Padding="4,4,4,2"
                      TextElement.Foreground="{StaticResource Ink}" TextElement.FontFamily="Cascadia Mono, Cascadia Code, Consolas" TextElement.FontSize="12.5">
                <StackPanel x:Name="RecentList"/>
              </Border>
            </Popup>
          </Grid>
        </Grid>
      </Border>

      <Border Grid.Row="2" Style="{StaticResource Section}">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto" SharedSizeGroup="Rail"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <TextBlock x:Name="LblOptions" Style="{StaticResource Rail}"/>
          <StackPanel Grid.Column="1">
            <DockPanel LastChildFill="False">
              <RadioButton x:Name="RbCopy" DockPanel.Dock="Left" GroupName="Mode" Style="{StaticResource Seg}" IsChecked="True"/>
              <RadioButton x:Name="RbMirror" DockPanel.Dock="Left" GroupName="Mode" Style="{StaticResource Seg}" Tag="danger"/>
              <RadioButton x:Name="RbMove" DockPanel.Dock="Left" GroupName="Mode" Style="{StaticResource Seg}" Tag="danger"/>
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                <TextBlock x:Name="LblThreads" Style="{StaticResource Lbl}"/>
                <TextBox x:Name="TxtThreads" Width="46" Margin="6,0,14,0" Text="8" MaxLength="3"/>
                <TextBlock x:Name="LblRetries" Style="{StaticResource Lbl}"/>
                <TextBox x:Name="TxtRetries" Width="64" Margin="6,0,14,0" Text="2" MaxLength="7"/>
                <TextBlock x:Name="LblWait" Style="{StaticResource Lbl}"/>
                <TextBox x:Name="TxtWait" Width="46" Margin="6,0,0,0" Text="5" MaxLength="4"/>
              </StackPanel>
            </DockPanel>
            <TextBlock x:Name="TxtModeHint" Margin="0,6,0,0" FontSize="11" TextWrapping="Wrap" Foreground="{StaticResource Danger}" Visibility="Collapsed"/>
            <WrapPanel Margin="0,8,0,0">
              <CheckBox x:Name="ChkSub" IsChecked="True" Margin="0,0,22,0"/>
              <CheckBox x:Name="ChkJunction" IsChecked="True" Margin="0,0,22,0"/>
              <CheckBox x:Name="ChkNewer" Margin="0,0,22,0"/>
              <CheckBox x:Name="ChkRestart"/>
            </WrapPanel>
            <Grid Margin="0,8,0,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto" SharedSizeGroup="Lbl"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <TextBlock x:Name="LblSkipFiles" Style="{StaticResource Lbl}" Margin="0,0,10,0"/>
              <TextBox x:Name="TxtXF" Grid.Column="1"/>
              <TextBlock x:Name="LblSkipDirs" Grid.Column="2" Style="{StaticResource Lbl}" Margin="14,0,8,0"/>
              <TextBox x:Name="TxtXD" Grid.Column="3"/>
            </Grid>
            <Grid Margin="0,6,0,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto" SharedSizeGroup="Lbl"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock x:Name="LblExtra" Style="{StaticResource Lbl}" Margin="0,0,10,0"/>
              <TextBox x:Name="TxtExtra" Grid.Column="1"/>
              <Button x:Name="BtnHelp" Grid.Column="2" Content="?" Margin="6,0,0,0" Padding="9,4" FontWeight="Bold" Foreground="{StaticResource Amber}"/>
              <Popup x:Name="HelpPopup" Grid.Column="2" Placement="Custom" StaysOpen="False" PopupAnimation="None">
                <Border x:Name="HelpPanel" Width="716" Background="{StaticResource Bg1}" BorderBrush="{StaticResource Amber}" BorderThickness="1" Padding="14,10,4,10"
                        TextElement.Foreground="{StaticResource Ink}" TextElement.FontFamily="Cascadia Mono, Cascadia Code, Consolas" TextElement.FontSize="12.5">
                  <ScrollViewer x:Name="HelpScroll" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled" Focusable="False">
                    <StackPanel Margin="0,0,10,0">
                      <TextBlock x:Name="LblHelpSetups" Style="{StaticResource Head}"/>
                      <TextBlock x:Name="LblHelpSetupNote" Style="{StaticResource Note}"/>
                      <StackPanel x:Name="HelpSetups" Margin="0,6,0,0"/>
                      <TextBlock x:Name="LblHelpSwitches" Style="{StaticResource Head}" Margin="0,8,0,0"/>
                      <TextBlock x:Name="LblHelpNote" Style="{StaticResource Note}"/>
                      <StackPanel x:Name="HelpSwitches" Margin="0,7,0,0"/>
                    </StackPanel>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </StackPanel>
        </Grid>
      </Border>

      <Border Grid.Row="3" Style="{StaticResource Section}">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto" SharedSizeGroup="Rail"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <StackPanel>
            <TextBlock x:Name="LblCommand" Style="{StaticResource Rail}"/>
            <Button x:Name="BtnCopyCmd" Style="{StaticResource Small}" Margin="0,6,10,0"/>
            <Button x:Name="BtnTape" Style="{StaticResource Small}" Margin="0,4,10,0" Visibility="Collapsed"/>
          </StackPanel>
          <StackPanel Grid.Column="1">
            <Border x:Name="TapeEdge" BorderBrush="{StaticResource Amber}" BorderThickness="3,0,0,0">
              <Border Background="{StaticResource Bg1}" BorderBrush="{StaticResource Line}" BorderThickness="0,1,1,1" Padding="10,6">
                <Grid>
                  <Border x:Name="TapeClip" ClipToBounds="True">
                    <WrapPanel x:Name="CmdPanel" VerticalAlignment="Top"/>
                  </Border>
                  <TextBlock x:Name="TapeMore" Text="..." HorizontalAlignment="Right" VerticalAlignment="Bottom" Padding="6,0,0,1" FontSize="13" FontWeight="Bold" Foreground="{StaticResource Amber}" Background="{StaticResource Bg1}" Visibility="Collapsed"/>
                </Grid>
              </Border>
            </Border>
            <TextBlock x:Name="TxtProblem" Margin="0,6,0,0" TextWrapping="Wrap" Foreground="{StaticResource Danger}" Visibility="Collapsed"/>
            <DockPanel Margin="0,8,0,0" LastChildFill="False">
              <CheckBox x:Name="ChkScan" DockPanel.Dock="Left" VerticalAlignment="Center" IsChecked="True" Margin="0,0,20,0"/>
              <CheckBox x:Name="ChkKeepLog" DockPanel.Dock="Left" VerticalAlignment="Center"/>
              <Button x:Name="BtnCancel" DockPanel.Dock="Right" Margin="6,0,0,0" IsEnabled="False"/>
              <Button x:Name="BtnRun" DockPanel.Dock="Right" Style="{StaticResource Primary}" MinWidth="96" Margin="6,0,0,0"/>
              <Button x:Name="BtnDry" DockPanel.Dock="Right"/>
            </DockPanel>
          </StackPanel>
        </Grid>
      </Border>

      <Border Grid.Row="4" Style="{StaticResource Section}" Padding="0,8,0,0">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto" SharedSizeGroup="Rail"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <StackPanel>
            <TextBlock x:Name="LblProgress" Style="{StaticResource Rail}" Margin="0,1,10,0"/>
            <Button x:Name="BtnToggleLog" Style="{StaticResource Small}" Margin="0,7,10,0"/>
            <Button x:Name="BtnCopyLog" Style="{StaticResource Small}" Margin="0,4,10,0"/>
            <Button x:Name="BtnFailed" Style="{StaticResource Small}" Margin="0,4,10,0" Foreground="{StaticResource Danger}" Visibility="Collapsed"/>
            <Button x:Name="BtnOpenLog" Style="{StaticResource Small}" Margin="0,4,10,0" Visibility="Collapsed"/>
          </StackPanel>
          <Grid Grid.Column="1">
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="*"/>
            </Grid.RowDefinitions>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="70"/>
              </Grid.ColumnDefinitions>
              <ProgressBar x:Name="Bar" Minimum="0" Maximum="100" Value="0"/>
              <TextBlock x:Name="TxtPercent" Grid.Column="1" Text="--" TextAlignment="Right" VerticalAlignment="Center" FontSize="15" FontWeight="Bold" Foreground="{StaticResource Amber}"/>
            </Grid>
            <UniformGrid Grid.Row="1" Columns="4" Margin="0,7,0,0">
              <StackPanel>
                <TextBlock x:Name="LblFiles" Style="{StaticResource Lbl}"/>
                <TextBlock x:Name="TxtFiles" Text="--" FontSize="13" Margin="0,1,0,0"/>
              </StackPanel>
              <StackPanel>
                <TextBlock x:Name="LblData" Style="{StaticResource Lbl}"/>
                <TextBlock x:Name="TxtData" Text="--" FontSize="13" Margin="0,1,0,0"/>
              </StackPanel>
              <StackPanel>
                <TextBlock x:Name="LblSpeed" Style="{StaticResource Lbl}"/>
                <TextBlock x:Name="TxtSpeed" Text="--" FontSize="13" Margin="0,1,0,0"/>
              </StackPanel>
              <StackPanel>
                <TextBlock x:Name="LblEta" Style="{StaticResource Lbl}"/>
                <TextBlock x:Name="TxtEta" Text="--" FontSize="13" Margin="0,1,0,0"/>
              </StackPanel>
            </UniformGrid>
            <TextBlock x:Name="TxtCurrent" Grid.Row="2" Margin="0,6,0,0" FontSize="11.5" Foreground="{StaticResource Dim}" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="TxtStatus" Grid.Row="3" Margin="0,4,0,0" TextWrapping="Wrap"/>
            <TextBox x:Name="TxtLog" Grid.Row="4" Margin="0,8,0,0" MinHeight="40" IsReadOnly="True" AcceptsReturn="True" TextWrapping="NoWrap" VerticalContentAlignment="Stretch" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Background="{StaticResource Bg1}" Foreground="{StaticResource Dim}" FontSize="11.5"/>
          </Grid>
        </Grid>
      </Border>
    </Grid>
  </Border>
</Window>
'@
}

function New-RoboGoWindow {
    # Loads the XAML and returns a hashtable: Window plus every named control.
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
    $reader = New-Object System.Xml.XmlNodeReader ([xml](Get-RoboGoXaml))
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $ui = @{ Window = $window }
    foreach ($name in $script:RoboGoControls) {
        $control = $window.FindName($name)
        if ($null -eq $control) { throw "Control '$name' is missing from the XAML." }
        $ui[$name] = $control
    }
    return $ui
}

function Get-RoboGoOptions {
    # Reads the fields into an options object. A number that does not parse becomes $null.
    param($UI)
    $o = New-RoboOptions
    $o.Source = $UI.TxtSource.Text
    $o.Destination = $UI.TxtDest.Text
    if ($UI.RbMirror.IsChecked) { $o.Mode = 'Mirror' }
    elseif ($UI.RbMove.IsChecked) { $o.Mode = 'Move' }
    else { $o.Mode = 'Copy' }
    $o.Subfolders = [bool]$UI.ChkSub.IsChecked
    $o.SkipJunctions = [bool]$UI.ChkJunction.IsChecked
    $o.OnlyNewer = [bool]$UI.ChkNewer.IsChecked
    $o.Restartable = [bool]$UI.ChkRestart.IsChecked
    $o.Threads = ConvertTo-RoboInt $UI.TxtThreads.Text
    $o.Retries = ConvertTo-RoboInt $UI.TxtRetries.Text
    $o.Wait = ConvertTo-RoboInt $UI.TxtWait.Text
    $o.ExcludeFiles = $UI.TxtXF.Text
    $o.ExcludeDirs = $UI.TxtXD.Text
    $o.Extra = $UI.TxtExtra.Text
    return $o
}

function Show-RoboGoStatus {
    # Draws the status line. Level: info, ok, warn or error.
    param([string]$Text, [string]$Level)
    $ui = $script:RoboGo.UI
    $brush = 'Ink'
    if ($Level -eq 'ok') { $brush = 'Ok' }
    elseif ($Level -eq 'warn') { $brush = 'Amber' }
    elseif ($Level -eq 'error') { $brush = 'Danger' }
    $ui.TxtStatus.Text = $Text
    $ui.TxtStatus.Foreground = $ui.Window.FindResource($brush)
}

function Set-RoboGoStatus {
    # Shows a text of the table in the status line and remembers its key, so that a change
    # of language can redraw it.
    param([string]$Key, [object[]]$Values = @(), [string]$Level = 'info')
    $s = $script:RoboGo
    $s.StatusKey = $Key
    $s.StatusValues = $Values
    Show-RoboGoStatus (Get-RoboText $Key $Values) $Level
}

function Set-RoboGoStatusText {
    # Shows a finished sentence (the verdict of a job) in the status line.
    param([string]$Text, [string]$Level = 'info')
    $script:RoboGo.StatusKey = ''
    Show-RoboGoStatus $Text $Level
}

function Invoke-RoboGoSafe {
    # Runs an event handler body. An unexpected error lands in the status line instead of
    # taking the window down.
    param([scriptblock]$Action)
    try { & $Action }
    catch { Set-RoboGoStatus 'status.error' @($_.Exception.Message) 'error' }
}

function Confirm-RoboGo {
    # Every yes/no question of the app goes through here. The tests replace this function,
    # so they never open a dialog.
    param([string]$Message)
    $answer = [System.Windows.MessageBox]::Show($script:RoboGo.UI.Window, $Message, 'RoboGo', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning, [System.Windows.MessageBoxResult]::No)
    return ($answer -eq [System.Windows.MessageBoxResult]::Yes)
}

function Get-RoboSoundName {
    # The event of the Windows sound scheme that fits the end of a job.
    param([string]$Level)
    if ($Level -eq 'error') { return 'SystemHand' }
    if ($Level -eq 'warn') { return 'SystemExclamation' }
    return 'SystemAsterisk'
}

function Invoke-RoboSound {
    # Plays the sound the Windows sound scheme has for an event, without waiting for it to
    # end. RoboGo plays it itself: the SystemSounds class of .NET only hands a request to
    # Windows (MessageBeep), and that request can report success without any sound coming out.
    # The tests replace this function.
    param([string]$Name)
    try {
        Initialize-RoboNative
        return [RoboGo.Native]::PlayEvent($Name)
    }
    catch {
        return $false
    }
}

function Invoke-RoboAttention {
    # A job ended while the user was elsewhere: the taskbar button flashes until the window
    # is looked at, and a Windows system sound plays. The tests replace this function.
    param([IntPtr]$Handle, [string]$Level)
    try {
        Initialize-RoboNative
        if ($Handle -ne [IntPtr]::Zero) { [RoboGo.Native]::Flash($Handle) }
    }
    catch { }
    [void](Invoke-RoboSound (Get-RoboSoundName $Level))
}

function Set-RoboGoTaskbar {
    # Progress on the taskbar button. State: None, Indeterminate (sweeping), Normal (green),
    # Paused (yellow) or Error (red). Value runs from 0 to 1.
    param([string]$State, [double]$Value = 0)
    $info = $script:RoboGo.UI.Window.TaskbarItemInfo
    if ($null -eq $info) { return }
    $info.ProgressState = $State
    $info.ProgressValue = [math]::Max(0.0, [math]::Min(1.0, $Value))
}

function Set-RoboTaskbarIdentity {
    # Gives the window an application id of its own and tells the taskbar how to start the
    # app again. A pin made from the running window then launches RoboGo.exe and shares its
    # button with the window, although the window lives in a PowerShell process.
    param($Window)
    try {
        Initialize-RoboNative
        $handle = (New-Object System.Windows.Interop.WindowInteropHelper $Window).EnsureHandle()
        $icon = Join-Path $script:RoboAppDir 'RoboGo.ico'
        $iconRef = ''
        if (Test-Path -LiteralPath $icon) { $iconRef = $icon + ',0' }
        return [RoboGo.Native]::SetIdentity($handle, $script:RoboAppId, ('"' + (Get-RoboLauncherPath) + '"'), 'RoboGo', $iconRef)
    }
    catch {
        return $false
    }
}

function Get-RoboTaskbarIdentity {
    # "id|command|name|icon" as the taskbar sees the window.
    param($Window)
    try {
        Initialize-RoboNative
        return [RoboGo.Native]::GetIdentity((New-Object System.Windows.Interop.WindowInteropHelper $Window).Handle)
    }
    catch {
        return ''
    }
}

function Clear-RoboTaskbarIdentity {
    param($Window)
    try {
        Initialize-RoboNative
        $handle = (New-Object System.Windows.Interop.WindowInteropHelper $Window).Handle
        if ($handle -ne [IntPtr]::Zero) { [RoboGo.Native]::ClearIdentity($handle) }
    }
    catch { }
}

function Get-RoboGoLast {
    # The fields as they are now, in the shape settings.json keeps them. No mode.
    param($UI)
    return @{
        Source        = $UI.TxtSource.Text
        Destination   = $UI.TxtDest.Text
        Threads       = $UI.TxtThreads.Text
        Retries       = $UI.TxtRetries.Text
        Wait          = $UI.TxtWait.Text
        ExcludeFiles  = $UI.TxtXF.Text
        ExcludeDirs   = $UI.TxtXD.Text
        Extra         = $UI.TxtExtra.Text
        Subfolders    = [bool]$UI.ChkSub.IsChecked
        SkipJunctions = [bool]$UI.ChkJunction.IsChecked
        OnlyNewer     = [bool]$UI.ChkNewer.IsChecked
        Restartable   = [bool]$UI.ChkRestart.IsChecked
        Scan          = [bool]$UI.ChkScan.IsChecked
    }
}

function Set-RoboGoLast {
    # Puts remembered fields back. Whatever is missing keeps its default.
    param($UI, $Last)
    if (-not ($Last -is [hashtable])) { return }
    $boxes = @{ Source = 'TxtSource'; Destination = 'TxtDest'; Threads = 'TxtThreads'; Retries = 'TxtRetries'; Wait = 'TxtWait'; ExcludeFiles = 'TxtXF'; ExcludeDirs = 'TxtXD'; Extra = 'TxtExtra' }
    foreach ($key in $boxes.Keys) {
        if ($Last.ContainsKey($key)) { $UI[$boxes[$key]].Text = [string]$Last[$key] }
    }
    $checks = @{ Subfolders = 'ChkSub'; SkipJunctions = 'ChkJunction'; OnlyNewer = 'ChkNewer'; Restartable = 'ChkRestart'; Scan = 'ChkScan' }
    foreach ($key in $checks.Keys) {
        if ($Last.ContainsKey($key)) { $UI[$checks[$key]].IsChecked = [bool]$Last[$key] }
    }
}

function Get-RoboGoWindowRect {
    # Where the window is, or $null while it has never been on screen. A maximized or
    # minimized window reports the rectangle it would go back to.
    $s = $script:RoboGo
    $window = $s.UI.Window
    if (-not $window.IsLoaded) { return $null }
    if ($window.WindowState -ne [System.Windows.WindowState]::Normal) {
        $bounds = $window.RestoreBounds
        if ($bounds.IsEmpty) { return $null }
        return @{ Left = $bounds.Left; Top = $bounds.Top; Width = $bounds.Width; Height = $bounds.Height }
    }
    $height = $window.ActualHeight
    # with the log hidden the window is short; remember the height it has with the log
    if (($s.UI.TxtLog.Visibility -ne [System.Windows.Visibility]::Visible) -and ($s.SavedHeight -gt 0)) { $height = $s.SavedHeight }
    return @{ Left = $window.Left; Top = $window.Top; Width = $window.ActualWidth; Height = $height }
}

function Restore-RoboGoWindow {
    # Puts the window where it was when it was closed. Returns $false and leaves it alone
    # when nothing is saved or that place is not on any screen now.
    param($UI, $Rect)
    if (-not ($Rect -is [hashtable])) { return $false }
    $window = $UI.Window
    $width = [math]::Max($window.MinWidth, [double]$Rect.Width)
    $height = [math]::Max($window.MinHeight, [double]$Rect.Height)
    $left = [double]$Rect.Left
    $top = [double]$Rect.Top
    $screenLeft = [System.Windows.SystemParameters]::VirtualScreenLeft
    $screenTop = [System.Windows.SystemParameters]::VirtualScreenTop
    $screenRight = $screenLeft + [System.Windows.SystemParameters]::VirtualScreenWidth
    $screenBottom = $screenTop + [System.Windows.SystemParameters]::VirtualScreenHeight
    # enough of the title bar must be reachable to grab the window
    $reachX = [math]::Min($left + $width, $screenRight) - [math]::Max($left, $screenLeft)
    $reachY = [math]::Min($top + 60, $screenBottom) - [math]::Max($top, $screenTop)
    if (($reachX -lt 120) -or ($reachY -lt 40)) { return $false }
    $window.WindowStartupLocation = 'Manual'
    $window.Left = $left
    $window.Top = $top
    $window.Width = $width
    $window.Height = $height
    return $true
}

function Save-RoboGoState {
    # Remembers the fields and the window rectangle for the next start. With -Job the two
    # paths also go to the front of the recent lists. A folder that cannot be written to
    # is not worth a message here.
    param([switch]$Job)
    $s = $script:RoboGo
    $ui = $s.UI
    $s.Settings.Last = Get-RoboGoLast $ui
    if ($Job) {
        $s.Settings.RecentSources = Add-RoboRecent $s.Settings.RecentSources $ui.TxtSource.Text
        $s.Settings.RecentDestinations = Add-RoboRecent $s.Settings.RecentDestinations $ui.TxtDest.Text
    }
    $rect = Get-RoboGoWindowRect
    if ($null -ne $rect) { $s.Settings.Window = $rect }
    [void](Save-RoboSettings $s.Settings)
}

function Update-RoboGoRecentButtons {
    # The arrows next to BROWSE are only on when there is something to show.
    $s = $script:RoboGo
    $idle = ($null -eq $s.Job)
    $s.UI.BtnRecentSource.IsEnabled = ($idle -and (@($s.Settings.RecentSources).Count -gt 0))
    $s.UI.BtnRecentDest.IsEnabled = ($idle -and (@($s.Settings.RecentDestinations).Count -gt 0))
}

function Update-RoboGoRecentRows {
    # Fills the list of recent paths for FROM (Source) or TO (Destination): a row per path,
    # newest first, and a last row that empties both lists.
    param([string]$Which)
    $s = $script:RoboGo
    $ui = $s.UI
    $s.RecentTarget = $Which
    $paths = $s.Settings.RecentSources
    if ($Which -eq 'Destination') { $paths = $s.Settings.RecentDestinations }
    $ui.RecentList.Children.Clear()
    $n = 0
    foreach ($path in @($paths)) {
        if ([string]::IsNullOrEmpty($path)) { continue }
        $text = New-Object System.Windows.Controls.TextBlock
        $text.Text = $path
        $text.TextTrimming = 'CharacterEllipsis'
        $button = New-Object System.Windows.Controls.Button
        $button.Tag = $path
        $button.Content = $text
        $button.HorizontalContentAlignment = 'Left'
        $button.Padding = New-Object System.Windows.Thickness (8, 3, 8, 3)
        $button.Margin = New-Object System.Windows.Thickness (0, 0, 0, 2)
        [System.Windows.Automation.AutomationProperties]::SetAutomationId($button, ('recent.' + $n))
        [System.Windows.Automation.AutomationProperties]::SetName($button, $path)
        $button.Add_Click($s.OnRecent)
        [void]$ui.RecentList.Children.Add($button)
        $n++
    }
    $text = New-Object System.Windows.Controls.TextBlock
    $text.Text = Get-RoboText 'ui.clearRecent'
    $text.FontSize = 11
    $text.Foreground = $ui.Window.FindResource('Dim')
    $button = New-Object System.Windows.Controls.Button
    $button.Content = $text
    $button.HorizontalContentAlignment = 'Left'
    $button.Padding = New-Object System.Windows.Thickness (8, 3, 8, 3)
    $button.Margin = New-Object System.Windows.Thickness (0, 2, 0, 2)
    [System.Windows.Automation.AutomationProperties]::SetAutomationId($button, 'recent.clear')
    [System.Windows.Automation.AutomationProperties]::SetName($button, $text.Text)
    $button.Add_Click($s.OnRecentClear)
    [void]$ui.RecentList.Children.Add($button)
}

function Show-RoboGoRecent {
    # An arrow button: opens the list under its field, as wide as the field.
    param([string]$Which)
    $s = $script:RoboGo
    $ui = $s.UI
    $popup = $ui.RecentPopup
    $sameAsBefore = ($Which -eq $s.RecentTarget)
    if ($popup.IsOpen) {
        $popup.IsOpen = $false
        if ($sameAsBefore) { return }
    }
    # A click on the arrow of the open list closes it first and then arrives here.
    elseif ($sameAsBefore -and (([DateTime]::UtcNow - $s.RecentClosed).TotalMilliseconds -lt 250)) { return }
    Update-RoboGoRecentRows $Which
    $field = $ui.TxtSource
    if ($Which -eq 'Destination') { $field = $ui.TxtDest }
    $popup.PlacementTarget = $field
    if ($field.ActualWidth -gt 0) { $ui.RecentPanel.Width = $field.ActualWidth }
    $popup.IsOpen = $true
}

function Select-RoboGoRecent {
    # A row of the list was clicked: the path goes into the field the list belongs to.
    param([string]$Path)
    $s = $script:RoboGo
    $s.UI.RecentPopup.IsOpen = $false
    if ($Path -eq '') { return }
    if ($s.RecentTarget -eq 'Destination') { $s.UI.TxtDest.Text = $Path }
    else { $s.UI.TxtSource.Text = $Path }
}

function Clear-RoboGoRecent {
    # The last row of the list: both lists are emptied, in the settings file too.
    $s = $script:RoboGo
    $s.UI.RecentPopup.IsOpen = $false
    $s.Settings.RecentSources = [string[]]@()
    $s.Settings.RecentDestinations = [string[]]@()
    Save-RoboGoSettings
    Update-RoboGoRecentButtons
}

function Update-RoboGoSendTo {
    # The SEND TO toggle is lit when the shortcut exists.
    $ui = $script:RoboGo.UI
    if (Test-RoboSendTo) {
        $ui.BtnSendTo.Foreground = $ui.Window.FindResource('Amber')
        $ui.BtnSendTo.BorderBrush = $ui.Window.FindResource('Amber')
    }
    else {
        $ui.BtnSendTo.Foreground = $ui.Window.FindResource('Dim')
        $ui.BtnSendTo.BorderBrush = $ui.Window.FindResource('Line')
    }
}

function Switch-RoboGoSendTo {
    # The SEND TO toggle: puts RoboGo into the Send to menu of Explorer or takes it out.
    $s = $script:RoboGo
    $on = (-not (Test-RoboSendTo))
    $done = Set-RoboSendTo $on
    Update-RoboGoSendTo
    if ($null -ne $s.Job) { return }
    if (-not $done) { Set-RoboGoStatus 'status.sendToFail' @() 'warn' }
    elseif ($on) { Set-RoboGoStatus 'status.sendToOn' }
    else { Set-RoboGoStatus 'status.sendToOff' }
}

function Update-RoboGoTape {
    # The command tape shows two lines. A command that needs more gets a button that opens
    # the rest. The lines are counted from the widths of the pieces, the way the tape wraps
    # them, so nothing here depends on how tall the tape happens to be drawn.
    $s = $script:RoboGo
    $ui = $s.UI
    $room = $ui.TapeClip.ActualWidth
    $pieces = @($ui.CmdPanel.Children)
    if (($room -le 0) -or ($pieces.Count -eq 0)) { return }
    $everything = New-Object System.Windows.Size ([double]::PositiveInfinity, [double]::PositiveInfinity)
    $lines = 1
    $used = 0.0
    $lineHeight = 0.0
    foreach ($piece in $pieces) {
        if (-not $piece.IsMeasureValid) { $piece.Measure($everything) }
        $width = [math]::Ceiling($piece.DesiredSize.Width)
        if ($piece.DesiredSize.Height -gt $lineHeight) { $lineHeight = $piece.DesiredSize.Height }
        if (($used -gt 0) -and (($used + $width) -gt $room)) {
            $lines++
            $used = 0.0
        }
        $used += $width
    }
    if (($lines -gt 2) -and ($lineHeight -gt 0)) {
        $ui.BtnTape.Visibility = 'Visible'
        if ($s.TapeOpen) {
            $ui.TapeClip.MaxHeight = [double]::PositiveInfinity
            $ui.TapeMore.Visibility = 'Collapsed'
            $ui.BtnTape.Content = Get-RoboText 'ui.showLess'
        }
        else {
            # three dots over the end of the second line show where the command is cut
            $ui.TapeClip.MaxHeight = [math]::Ceiling(2 * $lineHeight)
            $ui.TapeMore.Visibility = 'Visible'
            $ui.BtnTape.Content = Get-RoboText 'ui.showAll'
        }
    }
    else {
        $ui.BtnTape.Visibility = 'Collapsed'
        $ui.TapeMore.Visibility = 'Collapsed'
        $ui.TapeClip.MaxHeight = [double]::PositiveInfinity
    }
}

function Switch-RoboGoTape {
    # SHOW ALL and SHOW LESS.
    $s = $script:RoboGo
    $s.TapeOpen = (-not $s.TapeOpen)
    Update-RoboGoTape
}

function Update-RoboGoPreview {
    # Rebuilds the coloured command, the warning line and the problem line from the fields.
    $ui = $script:RoboGo.UI
    $options = Get-RoboGoOptions $ui
    # The tape is a WrapPanel of small text pieces, so lines break only between pieces.
    # A switch is one piece and is never split in the middle. A path is cut into one piece
    # per folder, so a long path breaks after a backslash and still reads top to bottom.
    $ui.CmdPanel.Children.Clear()
    foreach ($part in (Get-RoboCommandParts $options)) {
        $brush = $ui.Window.FindResource($script:RoboGoPartBrush[$part.Kind])
        $pieces = @($part.Text)
        if ($part.Kind -eq 'path') { $pieces = @([regex]::Split($part.Text, '(?<=\\)') | Where-Object { $_ -ne '' }) }
        for ($i = 0; $i -lt $pieces.Count; $i++) {
            $piece = New-Object System.Windows.Controls.TextBlock
            $piece.Text = $pieces[$i]
            $piece.FontSize = 13
            $piece.TextWrapping = 'Wrap'
            $piece.Foreground = $brush
            # only the last piece of a token is followed by a gap
            $gap = 0
            if ($i -eq ($pieces.Count - 1)) { $gap = 8 }
            $piece.Margin = New-Object System.Windows.Thickness (0, 1, $gap, 1)
            [void]$ui.CmdPanel.Children.Add($piece)
        }
    }
    # A plain copy needs no explanation. Modes that delete get a red line and a red tape edge.
    $danger = Get-RoboDanger $options
    if ($danger -ne '') {
        $ui.TxtModeHint.Text = $danger
        $ui.TxtModeHint.Foreground = $ui.Window.FindResource('Danger')
        $ui.TxtModeHint.Visibility = 'Visible'
        $ui.TapeEdge.BorderBrush = $ui.Window.FindResource('Danger')
    }
    else {
        $ui.TxtModeHint.Visibility = 'Collapsed'
        $ui.TapeEdge.BorderBrush = $ui.Window.FindResource('Amber')
    }
    if ($null -eq $script:RoboGo.Job) { $ui.ChkSub.IsEnabled = ($options.Mode -ne 'Mirror') }
    # Empty paths are not nagged about while typing; Run checks everything, disk included.
    $problems = Test-RoboOptions $options -SkipFileSystem -SkipEmptyPaths
    if ($problems.Count -gt 0) {
        $ui.TxtProblem.Text = $problems[0]
        $ui.TxtProblem.Visibility = 'Visible'
    }
    else {
        $ui.TxtProblem.Visibility = 'Collapsed'
    }
    Update-RoboGoTape
}

function Update-RoboGoHelpRows {
    # Fills the help panel: a button per recommended setup, a check box per useful switch.
    $s = $script:RoboGo
    $ui = $s.UI
    $ui.HelpSetups.Children.Clear()
    foreach ($setup in (Get-RoboHelpSetups)) {
        $text = New-Object System.Windows.Controls.TextBlock
        $text.Text = Get-RoboText $setup.Key
        $text.TextWrapping = 'Wrap'
        $text.FontSize = 11.5
        $button = New-Object System.Windows.Controls.Button
        $button.Tag = $setup.Key
        $button.Content = $text
        $button.HorizontalContentAlignment = 'Left'
        $button.Padding = New-Object System.Windows.Thickness (10, 4, 10, 4)
        $button.Margin = New-Object System.Windows.Thickness (0, 0, 0, 4)
        # id and name for screen readers and for the smoke test
        [System.Windows.Automation.AutomationProperties]::SetAutomationId($button, $setup.Key)
        [System.Windows.Automation.AutomationProperties]::SetName($button, $text.Text)
        $button.Add_Click($s.OnHelpSetup)
        [void]$ui.HelpSetups.Children.Add($button)
    }
    $ui.HelpSwitches.Children.Clear()
    foreach ($item in (Get-RoboHelpSwitches)) {
        $token = New-Object System.Windows.Controls.TextBlock
        $token.Text = $item.Token
        $token.Width = 118
        $token.Foreground = $ui.Window.FindResource('Amber')
        $about = New-Object System.Windows.Controls.TextBlock
        $about.Text = Get-RoboText $item.Key
        $about.TextWrapping = 'Wrap'
        $about.FontSize = 11.5
        $about.MaxWidth = 530
        $about.VerticalAlignment = 'Center'
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'
        [void]$row.Children.Add($token)
        [void]$row.Children.Add($about)
        $box = New-Object System.Windows.Controls.CheckBox
        $box.Tag = $item.Token
        $box.Content = $row
        $box.Margin = New-Object System.Windows.Thickness (0, 0, 0, 5)
        [System.Windows.Automation.AutomationProperties]::SetAutomationId($box, $item.Key)
        [System.Windows.Automation.AutomationProperties]::SetName($box, ($item.Token + ' ' + $about.Text))
        $box.Add_Checked($s.OnHelpSwitch)
        $box.Add_Unchecked($s.OnHelpSwitch)
        [void]$ui.HelpSwitches.Children.Add($box)
    }
    Sync-RoboGoHelp
}

function Sync-RoboGoHelp {
    # Ticks the switch rows whose switch is in EXTRA and unticks the others.
    $s = $script:RoboGo
    $extra = $s.UI.TxtExtra.Text
    $s.HelpSync = $true
    try {
        foreach ($box in @($s.UI.HelpSwitches.Children)) {
            $box.IsChecked = (Test-RoboExtraToken $extra ([string]$box.Tag))
        }
    }
    finally {
        $s.HelpSync = $false
    }
}

function Set-RoboGoHelpSwitch {
    # A switch row was ticked or unticked: make EXTRA agree with it.
    param($Box)
    $s = $script:RoboGo
    if ($s.HelpSync) { return }
    $extra = $s.UI.TxtExtra.Text
    $token = [string]$Box.Tag
    if ((Test-RoboExtraToken $extra $token) -ne [bool]$Box.IsChecked) {
        $s.UI.TxtExtra.Text = Switch-RoboExtraToken $extra $token
    }
}

function Invoke-RoboGoSetup {
    # A recommended setup was clicked: set THREADS, Restartable and the setup switches.
    # Everything else in EXTRA stays as typed.
    param([string]$Key)
    $s = $script:RoboGo
    $ui = $s.UI
    if ($null -ne $s.Job) { return }
    foreach ($setup in (Get-RoboHelpSetups)) {
        if ($setup.Key -ne $Key) { continue }
        $ui.TxtThreads.Text = [string]$setup.Threads
        $ui.ChkRestart.IsChecked = [bool]$setup.Restartable
        $ui.TxtExtra.Text = Get-RoboSetupExtra $ui.TxtExtra.Text $setup.Extra
    }
}

function Get-RoboGoHelpRoom {
    # The height left for the help panel between the EXTRA row and the bottom of the screen
    # the window is on. A panel that is taller than this scrolls.
    $ui = $script:RoboGo.UI
    $room = 440.0
    try {
        $source = [System.Windows.PresentationSource]::FromVisual($ui.BtnHelp)
        if ($null -ne $source) {
            Add-Type -AssemblyName System.Windows.Forms
            $handle = (New-Object System.Windows.Interop.WindowInteropHelper $ui.Window).Handle
            $screen = [System.Windows.Forms.Screen]::FromHandle($handle).WorkingArea
            # PointToScreen and the screen area are in pixels, the panel is measured in WPF units
            $below = $ui.BtnHelp.PointToScreen((New-Object System.Windows.Point (0, $ui.BtnHelp.ActualHeight)))
            $scale = $source.CompositionTarget.TransformToDevice.M22
            if ($scale -gt 0) { $room = (($screen.Bottom - $below.Y) / $scale) - 12 }
        }
    }
    catch { }
    return [math]::Max(240.0, $room)
}

function Show-RoboGoHelp {
    # The ? button: opens the help panel under the EXTRA row, or closes it.
    $s = $script:RoboGo
    $ui = $s.UI
    $popup = $ui.HelpPopup
    if ($popup.IsOpen) {
        $popup.IsOpen = $false
        return
    }
    # A click on ? while the panel is open closes it first (it closes on any click outside)
    # and then arrives here. Do not open it again right away.
    if (([DateTime]::UtcNow - $s.HelpClosed).TotalMilliseconds -lt 250) { return }
    Sync-RoboGoHelp
    # 22 = border and padding of the panel around the scrolling part
    $ui.HelpScroll.MaxHeight = (Get-RoboGoHelpRoom) - 22
    $popup.IsOpen = $true
}

function Update-RoboGoLanguage {
    # Puts the texts of the current language on every control.
    $s = $script:RoboGo
    $ui = $s.UI
    foreach ($entry in $script:RoboGoTextMap) {
        $property = $entry[1]
        $ui[$entry[0]].$property = Get-RoboText $entry[2]
    }
    $ui.BtnLang.Content = $script:RoboLanguage.ToUpperInvariant()
    $ui.LblEta.Text = Get-RoboText $s.EtaKey
    if ($ui.TxtLog.Visibility -eq [System.Windows.Visibility]::Visible) { $ui.BtnToggleLog.Content = Get-RoboText 'ui.hideLog' }
    else { $ui.BtnToggleLog.Content = Get-RoboText 'ui.showLog' }
    if ($s.StatusKey -ne '') { $ui.TxtStatus.Text = Get-RoboText $s.StatusKey $s.StatusValues }
    Update-RoboGoHelpRows
    Update-RoboGoPreview
    Update-RoboGoFailed
}

function Save-RoboGoSettings {
    # Writes the settings and says so when the program folder cannot be written to.
    $s = $script:RoboGo
    if ((-not (Save-RoboSettings $s.Settings)) -and ($null -eq $s.Job)) { Set-RoboGoStatus 'status.settings' @() 'warn' }
}

function Switch-RoboGoLanguage {
    # The language button: moves to the next language that loads, and remembers it.
    $s = $script:RoboGo
    $codes = Get-RoboLanguages
    $at = [array]::IndexOf($codes, $script:RoboLanguage)
    if ($at -lt 0) { $at = 0 }
    for ($step = 1; $step -le $codes.Count; $step++) {
        $next = $codes[($at + $step) % $codes.Count]
        if ((Set-RoboLanguage $next) -eq $next) { break }
    }
    $s.Settings.Language = $script:RoboLanguage
    Update-RoboGoLanguage
    Save-RoboGoSettings
}

function Set-RoboGoKeepLog {
    # The "Keep log file" box.
    param([bool]$Keep)
    $s = $script:RoboGo
    $s.Settings.KeepLog = $Keep
    Save-RoboGoSettings
}

function Add-RoboGoLog {
    param([string]$Line)
    $script:RoboGo.LogPending.Add($Line)
}

function Update-RoboGoLogView {
    # Takes over the lines collected since the last call. The box holds the newest lines of
    # the job: once it has grown past 6,000 it is rebuilt from the last 5,000. While the
    # failed view is on, the box is left alone and only the lines are kept.
    $s = $script:RoboGo
    if ($s.LogPending.Count -eq 0) { return }
    $box = $s.UI.TxtLog
    $nl = [Environment]::NewLine
    # follow the end, unless the user has scrolled up to read
    $follow = (($box.VerticalOffset + $box.ViewportHeight) -ge ($box.ExtentHeight - 24))
    $s.LogLines.AddRange($s.LogPending)
    $trimmed = $false
    if ($s.LogLines.Count -gt 6000) {
        $s.LogLines.RemoveRange(0, ($s.LogLines.Count - 5000))
        $trimmed = $true
    }
    if ($s.LogView -eq 'all') {
        if ($trimmed) { $box.Text = [string]::Join($nl, $s.LogLines.ToArray()) + $nl }
        else { $box.AppendText([string]::Join($nl, $s.LogPending.ToArray()) + $nl) }
        if ($follow) { $box.ScrollToEnd() }
    }
    $s.LogPending.Clear()
}

function Show-RoboGoLogText {
    # Fills the log box from scratch for the view that is on: the whole log, or the failures.
    $s = $script:RoboGo
    $box = $s.UI.TxtLog
    $nl = [Environment]::NewLine
    if ($s.LogView -eq 'failed') {
        $box.Text = $s.FailedText
        $box.ScrollToHome()
    }
    else {
        $text = ''
        if ($s.LogLines.Count -gt 0) { $text = [string]::Join($nl, $s.LogLines.ToArray()) + $nl }
        $box.Text = $text
        $box.ScrollToEnd()
    }
}

function Update-RoboGoFailed {
    # Keeps the FAILED button and the failed view in step with the failures of the job.
    $s = $script:RoboGo
    $ui = $s.UI
    if ($null -ne $s.Job) {
        $lines = Get-RoboFailureLines $s.Job.State
        $text = ''
        if ($lines.Count -gt 0) { $text = [string]::Join([Environment]::NewLine, $lines) + [Environment]::NewLine }
        if ($text -ne $s.FailedText) {
            $s.FailedCount = $lines.Count
            $s.FailedText = $text
            if ($s.LogView -eq 'failed') { Show-RoboGoLogText }
        }
    }
    if ($s.FailedCount -gt 0) {
        $ui.BtnFailed.Visibility = 'Visible'
        if ($s.LogView -eq 'failed') { $ui.BtnFailed.Content = Get-RoboText 'ui.fullLog' }
        else { $ui.BtnFailed.Content = Get-RoboText 'ui.failed' $s.FailedCount }
    }
    else {
        $ui.BtnFailed.Visibility = 'Collapsed'
        if ($s.LogView -eq 'failed') {
            $s.LogView = 'all'
            Show-RoboGoLogText
        }
    }
}

function Switch-RoboGoFailed {
    # The FAILED button: only the failures, or the whole log again.
    $s = $script:RoboGo
    Update-RoboGoLogView
    if ($s.LogView -eq 'failed') { $s.LogView = 'all' }
    elseif ($s.FailedCount -gt 0) { $s.LogView = 'failed' }
    Show-RoboGoLogText
    Update-RoboGoFailed
}

function Clear-RoboGoLog {
    $s = $script:RoboGo
    $s.LogLines.Clear()
    $s.LogPending.Clear()
    $s.UI.TxtLog.Clear()
}

function Set-RoboClipboard {
    # The one place that writes to the clipboard. The tests replace it, so they never
    # touch what the user has copied.
    param([string]$Text)
    [System.Windows.Clipboard]::SetText($Text)
}

function Copy-RoboGoCommand {
    # The COPY button: the command as shown goes to the clipboard.
    $s = $script:RoboGo
    Set-RoboClipboard (Get-RoboCommandLine (Get-RoboGoOptions $s.UI))
    if ($null -eq $s.Job) { Set-RoboGoStatus 'status.copied' }
}

function Copy-RoboGoLog {
    # The COPY LOG button: what the log box shows goes to the clipboard.
    $s = $script:RoboGo
    Update-RoboGoLogView
    $text = $s.UI.TxtLog.Text
    if ($text -eq '') { return }
    Set-RoboClipboard $text
    if ($null -eq $s.Job) { Set-RoboGoStatus 'status.logCopied' }
}

function Set-RoboGoBusy {
    param([bool]$Busy)
    $ui = $script:RoboGo.UI
    foreach ($name in $script:RoboGoInputs) { $ui[$name].IsEnabled = (-not $Busy) }
    $ui.BtnCancel.IsEnabled = $Busy
    if (-not $Busy) {
        $ui.ChkSub.IsEnabled = (-not [bool]$ui.RbMirror.IsChecked)
        Update-RoboGoRecentButtons
    }
}

function Start-RoboGoPhase {
    # Phase is Scan, Run or DryRun, which is also the job kind.
    param([string]$Phase)
    $s = $script:RoboGo
    $s.Phase = $Phase
    $s.Job = Start-RoboJob $s.Options $Phase
    $s.Meter = New-RoboSpeedMeter
    $s.Clock = [System.Diagnostics.Stopwatch]::StartNew()
    $s.UI.Bar.IsIndeterminate = (($Phase -ne 'Run') -or ($s.TotalBytes -le 0))
    if ($s.UI.Bar.IsIndeterminate) { Set-RoboGoTaskbar 'Indeterminate' }
    else { Set-RoboGoTaskbar 'Normal' 0 }
    if ($Phase -eq 'Scan') { Set-RoboGoStatus 'status.scanning' }
    elseif ($Phase -eq 'DryRun') { Set-RoboGoStatus 'status.dryRun' }
    else { Set-RoboGoStatus 'status.copying' }
}

function Start-RoboGoRun {
    # The Run and Dry run buttons: validate, confirm destructive jobs, start the first phase.
    param([switch]$DryRun)
    $s = $script:RoboGo
    $ui = $s.UI
    if ($null -ne $s.Job) { return }
    $options = Get-RoboGoOptions $ui
    $problems = Test-RoboOptions $options
    if ($problems.Count -gt 0) {
        $ui.TxtProblem.Text = ($problems -join '  ')
        $ui.TxtProblem.Visibility = 'Visible'
        return
    }
    $danger = Get-RoboDanger $options
    if (($danger -ne '') -and (-not $DryRun)) {
        $nl = [Environment]::NewLine
        $message = $danger + $nl + $nl + (Get-RoboText 'ui.from') + '  ' + (ConvertTo-RoboPath $options.Source) + $nl + (Get-RoboText 'ui.to') + '  ' + (ConvertTo-RoboPath $options.Destination) + $nl + $nl + (Get-RoboText 'dialog.confirmTip') + $nl + $nl + (Get-RoboText 'dialog.confirmAsk')
        if (-not (Confirm-RoboGo $message)) { return }
    }
    $ui.HelpPopup.IsOpen = $false
    $ui.RecentPopup.IsOpen = $false
    # the fields of a job that starts are worth remembering, and so are its two folders
    Save-RoboGoState -Job
    $s.FailedCount = 0
    $s.FailedText = ''
    $s.LogView = 'all'
    Update-RoboGoFailed
    $s.Options = $options
    $s.DryRun = [bool]$DryRun
    $s.Cancelled = $false
    $s.TotalFiles = [long]-1
    $s.TotalBytes = [long]-1
    $s.ScanLines.Clear()
    Clear-RoboGoLog
    $s.TotalClock = [System.Diagnostics.Stopwatch]::StartNew()
    $ui.Bar.Value = 0
    foreach ($name in 'TxtPercent', 'TxtFiles', 'TxtData', 'TxtSpeed', 'TxtEta') { $ui[$name].Text = '--' }
    $s.EtaKey = 'ui.eta'
    $ui.LblEta.Text = Get-RoboText $s.EtaKey
    $ui.TxtCurrent.Text = ''
    $ui.TxtProblem.Visibility = 'Collapsed'
    $suffix = ''
    if ($DryRun) { $suffix = ' /L' }
    Add-RoboGoLog ('> ' + (Get-RoboCommandLine $options) + $suffix)
    Set-RoboGoBusy $true
    try {
        if ($DryRun) { Start-RoboGoPhase 'DryRun' }
        elseif ($ui.ChkScan.IsChecked) { Start-RoboGoPhase 'Scan' }
        else { Start-RoboGoPhase 'Run' }
    }
    catch {
        $s.Job = $null
        $s.Phase = 'Idle'
        Set-RoboGoBusy $false
        throw
    }
    Update-RoboGoLogView
    $s.Timer.Start()
}

function Stop-RoboGoRun {
    # The Cancel button.
    $s = $script:RoboGo
    if ($null -eq $s.Job) { return }
    $s.Cancelled = $true
    Set-RoboGoStatus 'status.stopping' @() 'warn'
    Stop-RoboJob $s.Job
}

function Update-RoboGoNumbers {
    # Refreshes bar, counters, speed and ETA from the running job.
    $s = $script:RoboGo
    $ui = $s.UI
    $state = $s.Job.State
    if ($s.Phase -eq 'DryRun') {
        $ui.TxtFiles.Text = [string]$state.SeenFiles
        $ui.TxtData.Text = Format-RoboBytes $state.SeenBytes
        return
    }
    $done = Get-RoboDoneBytes $state
    Add-RoboSpeedSample $s.Meter $done $s.Clock.Elapsed.TotalSeconds
    $speed = Get-RoboSpeed $s.Meter
    $ui.TxtSpeed.Text = (Format-RoboBytes $speed) + '/s'
    $ui.TxtCurrent.Text = Get-RoboShortPath $state.CurrentFile 100
    if ($s.TotalBytes -gt 0) {
        # 100 is reserved for the moment robocopy has exited successfully.
        $pct = [math]::Min(99.9, (100.0 * $done / $s.TotalBytes))
        $ui.Bar.Value = $pct
        if ($state.Errors -gt 0) { Set-RoboGoTaskbar 'Paused' ($pct / 100) }
        else { Set-RoboGoTaskbar 'Normal' ($pct / 100) }
        $ui.TxtPercent.Text = [string]::Format($script:Inv, '{0:0.0}%', $pct)
        $ui.TxtFiles.Text = '{0} / {1}' -f $state.CompletedFiles, $s.TotalFiles
        $ui.TxtData.Text = (Format-RoboBytes $done) + ' / ' + (Format-RoboBytes $s.TotalBytes)
        if ($speed -gt 0) { $ui.TxtEta.Text = Format-RoboDuration (($s.TotalBytes - $done) / $speed) }
        else { $ui.TxtEta.Text = '--' }
    }
    else {
        $ui.TxtFiles.Text = [string]$state.CompletedFiles
        $ui.TxtData.Text = Format-RoboBytes $done
    }
    if (($state.Errors -gt 0) -and (-not $s.Cancelled)) {
        Set-RoboGoStatus 'status.copyingErrors' @($state.Errors) 'warn'
    }
}

function Complete-RoboGo {
    # The job is over (finished, failed or cancelled): show the verdict, put the log away
    # and unlock the window.
    $s = $script:RoboGo
    $ui = $s.UI
    $job = $s.Job
    $s.Timer.Stop()
    $state = $job.State
    $verdict = Get-RoboVerdict -ExitCode ([int]$job.ExitCode) -Summary $state.Summary -DryRun:$s.DryRun -Cancelled:$s.Cancelled -Mirror:($s.Options.Mode -eq 'Mirror')
    $ui.Bar.IsIndeterminate = $false
    if (($s.Phase -eq 'Run') -and (-not $s.Cancelled)) {
        if ($verdict.Level -ne 'error') {
            $ui.Bar.Value = 100
            $ui.TxtPercent.Text = '100%'
        }
        if ($null -ne $state.Summary) {
            $copied = $state.Summary.Bytes.Copied
            if ($s.TotalFiles -ge 0) { $ui.TxtFiles.Text = '{0} / {1}' -f $state.Summary.Files.Copied, $s.TotalFiles }
            else { $ui.TxtFiles.Text = [string]$state.Summary.Files.Copied }
            $ui.TxtData.Text = Format-RoboBytes $copied
            $seconds = $s.Clock.Elapsed.TotalSeconds
            if ($seconds -gt 0) { $ui.TxtSpeed.Text = (Format-RoboBytes ($copied / $seconds)) + '/s' }
        }
    }
    elseif ($s.Phase -ne 'Run') {
        $ui.Bar.Value = 0
        $ui.TxtPercent.Text = '--'
    }
    $s.EtaKey = 'ui.took'
    $ui.LblEta.Text = Get-RoboText $s.EtaKey
    $ui.TxtEta.Text = Format-RoboDuration $s.TotalClock.Elapsed.TotalSeconds
    $ui.TxtCurrent.Text = ''
    Set-RoboGoStatusText $verdict.Text $verdict.Level
    Add-RoboGoLog ('== ' + $verdict.Text)
    # The working log is deleted, or moved next to the program when logs are kept.
    $s.LastLog = Close-RoboJobLog $job -Keep:([bool]$s.Settings.KeepLog)
    if ($s.LastLog -ne '') {
        Add-RoboGoLog (Get-RoboText 'log.saved' $s.LastLog)
        # It stays for this session so OPEN LOG works, but the cleanup at the next start
        # would remove it without a word.
        $size = [long]0
        try { $size = (Get-Item -LiteralPath $s.LastLog).Length }
        catch { }
        if ($size -gt ($s.Settings.LogFileMaxMB * 1048576)) { Add-RoboGoLog (Get-RoboText 'log.savedBig' $s.Settings.LogFileMaxMB) }
        $ui.BtnOpenLog.Visibility = 'Visible'
    }
    else {
        $ui.BtnOpenLog.Visibility = 'Collapsed'
    }
    # the failures of this job stay available after it is gone
    $failures = Get-RoboFailureLines $state
    $s.FailedCount = $failures.Count
    $s.FailedText = ''
    if ($failures.Count -gt 0) { $s.FailedText = [string]::Join([Environment]::NewLine, $failures) + [Environment]::NewLine }
    Update-RoboGoLogView
    $s.Job = $null
    $s.Phase = 'Idle'
    Update-RoboGoFailed
    if ($s.LogView -eq 'failed') { Show-RoboGoLogText }
    # red on the taskbar for a failed job, nothing otherwise
    if ($verdict.Level -eq 'error') { Set-RoboGoTaskbar 'Error' 1 }
    else { Set-RoboGoTaskbar 'None' }
    Set-RoboGoBusy $false
    # whoever is looking at another window gets a flash and a sound
    if (-not $ui.Window.IsActive) {
        $handle = (New-Object System.Windows.Interop.WindowInteropHelper $ui.Window).Handle
        Invoke-RoboAttention $handle $verdict.Level
    }
}

function Step-RoboGo {
    # One timer tick: read new log output, refresh the numbers, move to the next phase.
    $s = $script:RoboGo
    $job = $s.Job
    if ($null -eq $job) {
        $s.Timer.Stop()
        return
    }
    $lines = Read-RoboJob $job
    if ($s.Phase -eq 'Scan') {
        foreach ($line in $lines) { $s.ScanLines.Add($line) }
        if (-not $job.Done) { return }
        if ($s.Cancelled) {
            Complete-RoboGo
            return
        }
        if (($job.ExitCode -lt 0) -or ($job.ExitCode -ge 16)) {
            foreach ($line in $s.ScanLines) { Add-RoboGoLog $line }
            Complete-RoboGo
            return
        }
        $summary = $job.State.Summary
        if ($null -ne $summary) {
            $s.TotalFiles = [long]$summary.Files.Copied
            $s.TotalBytes = [long]$summary.Bytes.Copied
            Add-RoboGoLog (Get-RoboText 'log.scan' @($s.TotalFiles, (Format-RoboBytes $s.TotalBytes)))
        }
        else {
            Add-RoboGoLog (Get-RoboText 'log.scanNoTotals')
        }
        # Is there room? The scan knows what the job needs. A mirror deletes first and
        # compression can make things fit, so the user may run it anyway.
        if ($null -ne $summary) {
            $free = Get-RoboFreeSpace $s.Options.Destination
            if ($free -ge 0) { Add-RoboGoLog (Get-RoboText 'log.space' (Format-RoboBytes $free)) }
            if (($free -ge 0) -and ($s.TotalBytes -gt $free)) {
                $need = Format-RoboBytes $s.TotalBytes
                $have = Format-RoboBytes $free
                $nl = [Environment]::NewLine
                # no ticks while the question is open
                $s.Timer.Stop()
                $go = Confirm-RoboGo ((Get-RoboText 'dialog.noSpace' @($need, $have)) + $nl + $nl + (Get-RoboText 'dialog.runAnyway'))
                if (-not $go) {
                    [void](Close-RoboJobLog $job)
                    $s.Job = $null
                    $s.Phase = 'Idle'
                    $s.UI.Bar.IsIndeterminate = $false
                    Set-RoboGoTaskbar 'None'
                    Set-RoboGoBusy $false
                    Set-RoboGoStatus 'status.noSpace' @($need, $have) 'warn'
                    Add-RoboGoLog ('== ' + (Get-RoboText 'status.noSpace' @($need, $have)))
                    Update-RoboGoLogView
                    return
                }
                $s.Timer.Start()
            }
        }
        # the log of the scan is never kept, the run that follows writes its own
        [void](Close-RoboJobLog $job)
        Start-RoboGoPhase 'Run'
        Update-RoboGoLogView
        return
    }
    foreach ($line in $lines) { Add-RoboGoLog $line }
    Update-RoboGoNumbers
    Update-RoboGoLogView
    Update-RoboGoFailed
    if ($job.Done) { Complete-RoboGo }
}

function Stop-RoboGoOnError {
    # A tick failed unexpectedly: stop everything and say so.
    param($ErrorRecord)
    $s = $script:RoboGo
    $s.Timer.Stop()
    if ($null -ne $s.Job) {
        Stop-RoboJob $s.Job
        [void](Close-RoboJobLog $s.Job)
        $s.Job = $null
    }
    $s.Phase = 'Idle'
    $s.UI.Bar.IsIndeterminate = $false
    Set-RoboGoTaskbar 'None'
    Set-RoboGoBusy $false
    Set-RoboGoStatus 'status.error' @($ErrorRecord.Exception.Message) 'error'
}

function Switch-RoboGoLog {
    # Hides or shows the log box and resizes the window to match.
    $s = $script:RoboGo
    $ui = $s.UI
    $window = $ui.Window
    if ($ui.TxtLog.Visibility -eq [System.Windows.Visibility]::Visible) {
        $s.SavedHeight = $window.ActualHeight
        $s.SavedMinHeight = $window.MinHeight
        $ui.TxtLog.Visibility = 'Collapsed'
        $ui.BtnToggleLog.Content = Get-RoboText 'ui.showLog'
        $window.MinHeight = 0
        $window.SizeToContent = 'Height'
    }
    else {
        $window.SizeToContent = 'Manual'
        $window.MinHeight = $s.SavedMinHeight
        if ($s.SavedHeight -gt 0) { $window.Height = $s.SavedHeight }
        $ui.TxtLog.Visibility = 'Visible'
        $ui.BtnToggleLog.Content = Get-RoboText 'ui.hideLog'
    }
}

function Select-RoboFolder {
    # Folder picker. Uses the modern Windows dialog when the runtime has it (.NET 8 and up,
    # that is PowerShell 7.4 and up), otherwise the classic one.
    param([string]$Initial, [string]$Title)
    $start = ConvertTo-RoboPath $Initial
    if (($start -ne '') -and (-not (Test-Path -LiteralPath $start -PathType Container))) { $start = '' }
    $picked = ''
    $modern = 'Microsoft.Win32.OpenFolderDialog' -as [type]
    if ($null -ne $modern) {
        $dialog = [System.Activator]::CreateInstance($modern)
        $dialog.Title = $Title
        if ($start -ne '') { $dialog.InitialDirectory = $start }
        if ($dialog.ShowDialog($script:RoboGo.UI.Window)) { $picked = $dialog.FolderName }
    }
    else {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        try {
            $dialog.Description = $Title
            if ($start -ne '') { $dialog.SelectedPath = $start }
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $picked = $dialog.SelectedPath }
        }
        finally {
            $dialog.Dispose()
        }
    }
    return $picked
}

function Set-RoboDarkTitleBar {
    # Dark title bar (DWMWA_USE_IMMERSIVE_DARK_MODE), and on Windows 11 the caption, its
    # text and the border in the colours of the window itself. Cosmetic only.
    param($Window)
    try {
        Initialize-RoboNative
        $handle = (New-Object System.Windows.Interop.WindowInteropHelper $Window).EnsureHandle()
        $on = 1
        [void][RoboGo.Native]::DwmSetWindowAttribute($handle, 20, [ref]$on, 4)
        # 35 caption, 36 caption text, 34 border. A COLORREF is 0x00BBGGRR. Without these an
        # accent-coloured title bar would sit on top of the dark window. Windows 10 ignores them.
        $caption = 0x000E0C0B
        $captionText = 0x00E1E6E8
        $border = 0x00342E2A
        [void][RoboGo.Native]::DwmSetWindowAttribute($handle, 35, [ref]$caption, 4)
        [void][RoboGo.Native]::DwmSetWindowAttribute($handle, 36, [ref]$captionText, 4)
        [void][RoboGo.Native]::DwmSetWindowAttribute($handle, 34, [ref]$border, 4)
    }
    catch { }
}

function Initialize-RoboGoWindow {
    # Wires the events and creates the controller state. Kept apart from New-RoboGoWindow
    # so that the tests can drive the window without showing it.
    param($UI, [string]$Source = '')
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $settings = Read-RoboSettings
    [void](Set-RoboLanguage $settings.Language)
    $script:RoboGo = @{
        UI             = $UI
        Timer          = $timer
        Settings       = $settings
        Job            = $null
        Phase          = 'Idle'
        Options        = $null
        DryRun         = $false
        Cancelled      = $false
        TotalFiles     = [long]-1
        TotalBytes     = [long]-1
        Meter          = $null
        Clock          = $null
        TotalClock     = $null
        LogLines       = (New-Object System.Collections.Generic.List[string])
        LogPending     = (New-Object System.Collections.Generic.List[string])
        ScanLines      = (New-Object System.Collections.Generic.List[string])
        LastLog        = ''
        EtaKey         = 'ui.eta'
        StatusKey      = ''
        StatusValues   = @()
        HelpSync       = $false
        HelpClosed     = [DateTime]::MinValue
        OnHelpSwitch   = $null
        OnHelpSetup    = $null
        LogView        = 'all'
        FailedCount    = 0
        FailedText     = ''
        TapeOpen       = $false
        RecentTarget   = ''
        RecentClosed   = [DateTime]::MinValue
        OnRecent       = $null
        OnRecentClear  = $null
        SavedHeight    = 0.0
        SavedMinHeight = 0.0
    }
    # One handler for all rows of the help panel; the rows are rebuilt with every language.
    $script:RoboGo.OnHelpSwitch = {
        param($control, $e)
        Invoke-RoboGoSafe { Set-RoboGoHelpSwitch $control }
    }
    $script:RoboGo.OnHelpSetup = {
        param($control, $e)
        Invoke-RoboGoSafe { Invoke-RoboGoSetup ([string]$control.Tag) }
    }
    $script:RoboGo.OnRecent = {
        param($control, $e)
        Invoke-RoboGoSafe { Select-RoboGoRecent ([string]$control.Tag) }
    }
    $script:RoboGo.OnRecentClear = {
        param($control, $e)
        Invoke-RoboGoSafe { Clear-RoboGoRecent }
    }
    $UI.TxtVersion.Text = 'v' + $script:RoboGoVersion
    $UI.ChkKeepLog.IsChecked = [bool]$settings.KeepLog
    $UI.Window.TaskbarItemInfo = New-Object System.Windows.Shell.TaskbarItemInfo
    # The fields of the last session come back, before any handler listens. The mode does
    # not: it is always COPY at start. A folder handed over at start (Send to) goes into
    # FROM and empties TO, so that an old destination is not reused by accident.
    Set-RoboGoLast $UI $settings.Last
    # Explorer quotes what it hands over. "D:\" then reaches a program as D:" and may drag
    # a second path along; whatever follows a stray quote is cut off.
    $given = ConvertTo-RoboPath ((([string]$Source).Trim().Trim('"') -split '"')[0])
    $givenFile = $false
    if ($given -ne '') {
        if (Test-Path -LiteralPath $given -PathType Leaf) {
            $given = [System.IO.Path]::GetDirectoryName($given)
            $givenFile = $true
        }
        $UI.TxtSource.Text = $given
        $UI.TxtDest.Text = ''
    }
    $icon = Join-Path $script:RoboAppDir 'RoboGo.ico'
    if (Test-Path -LiteralPath $icon) {
        try { $UI.Window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri $icon)) }
        catch { }
    }

    $timer.Add_Tick({
            try { Step-RoboGo }
            catch { Stop-RoboGoOnError $_ }
        })

    $refresh = { Invoke-RoboGoSafe { Update-RoboGoPreview } }
    foreach ($name in 'TxtSource', 'TxtDest', 'TxtThreads', 'TxtRetries', 'TxtWait', 'TxtXF', 'TxtXD', 'TxtExtra') {
        $UI[$name].Add_TextChanged($refresh)
    }
    foreach ($name in 'RbCopy', 'RbMirror', 'RbMove', 'ChkSub', 'ChkJunction', 'ChkNewer', 'ChkRestart') {
        $UI[$name].Add_Checked($refresh)
        $UI[$name].Add_Unchecked($refresh)
    }
    $UI.TxtExtra.Add_TextChanged({ Invoke-RoboGoSafe { Sync-RoboGoHelp } })

    $UI.BtnSource.Add_Click({
            Invoke-RoboGoSafe {
                $box = $script:RoboGo.UI.TxtSource
                $picked = Select-RoboFolder $box.Text (Get-RoboText 'dialog.pickSource')
                if ($picked -ne '') { $box.Text = $picked }
            }
        })
    $UI.BtnDest.Add_Click({
            Invoke-RoboGoSafe {
                $box = $script:RoboGo.UI.TxtDest
                $picked = Select-RoboFolder $box.Text (Get-RoboText 'dialog.pickDest')
                if ($picked -ne '') { $box.Text = $picked }
            }
        })

    # A text box refuses file drops unless the preview events say otherwise.
    foreach ($name in 'TxtSource', 'TxtDest') {
        $UI[$name].Add_PreviewDragOver({
                param($control, $e)
                if ($e.Data.GetDataPresent([System.Windows.DataFormats]::FileDrop)) { $e.Effects = [System.Windows.DragDropEffects]::Copy }
                else { $e.Effects = [System.Windows.DragDropEffects]::None }
                $e.Handled = $true
            })
        $UI[$name].Add_PreviewDrop({
                param($control, $e)
                Invoke-RoboGoSafe {
                    $dropped = $e.Data.GetData([System.Windows.DataFormats]::FileDrop)
                    if ($dropped) {
                        $path = [string]@($dropped)[0]
                        if (Test-Path -LiteralPath $path -PathType Leaf) {
                            $path = [System.IO.Path]::GetDirectoryName($path)
                            Set-RoboGoStatus 'status.droppedFile'
                        }
                        $control.Text = $path
                    }
                }
                $e.Handled = $true
            })
    }

    $UI.BtnRun.Add_Click({ Invoke-RoboGoSafe { Start-RoboGoRun } })
    $UI.BtnDry.Add_Click({ Invoke-RoboGoSafe { Start-RoboGoRun -DryRun } })
    $UI.BtnCancel.Add_Click({ Invoke-RoboGoSafe { Stop-RoboGoRun } })
    $UI.BtnCopyCmd.Add_Click({ Invoke-RoboGoSafe { Copy-RoboGoCommand } })
    $UI.BtnToggleLog.Add_Click({ Invoke-RoboGoSafe { Switch-RoboGoLog } })
    $UI.BtnCopyLog.Add_Click({ Invoke-RoboGoSafe { Copy-RoboGoLog } })
    $UI.BtnOpenLog.Add_Click({
            Invoke-RoboGoSafe {
                $log = $script:RoboGo.LastLog
                if (($log -ne '') -and (Test-Path -LiteralPath $log)) { Invoke-Item -LiteralPath $log }
            }
        })
    $UI.BtnLang.Add_Click({ Invoke-RoboGoSafe { Switch-RoboGoLanguage } })
    $UI.BtnSendTo.Add_Click({ Invoke-RoboGoSafe { Switch-RoboGoSendTo } })
    $UI.BtnTape.Add_Click({ Invoke-RoboGoSafe { Switch-RoboGoTape } })
    $UI.BtnFailed.Add_Click({ Invoke-RoboGoSafe { Switch-RoboGoFailed } })
    $UI.BtnRecentSource.Add_Click({ Invoke-RoboGoSafe { Show-RoboGoRecent 'Source' } })
    $UI.BtnRecentDest.Add_Click({ Invoke-RoboGoSafe { Show-RoboGoRecent 'Destination' } })
    # the tape is counted again whenever its width or its content has been laid out
    $UI.TapeClip.Add_SizeChanged({ Invoke-RoboGoSafe { Update-RoboGoTape } })
    $UI.CmdPanel.Add_SizeChanged({ Invoke-RoboGoSafe { Update-RoboGoTape } })
    # The list of recent paths hangs under its field, left edges in line, or above it
    # when there is no room below.
    $UI.RecentPopup.CustomPopupPlacementCallback = {
        param($popupSize, $targetSize, $offset)
        $axis = [System.Windows.Controls.Primitives.PopupPrimaryAxis]::Vertical
        $below = New-Object System.Windows.Point (0, ($targetSize.Height + 2))
        $above = New-Object System.Windows.Point (0, (-$popupSize.Height - 2))
        $first = New-Object System.Windows.Controls.Primitives.CustomPopupPlacement ($below, $axis)
        $second = New-Object System.Windows.Controls.Primitives.CustomPopupPlacement ($above, $axis)
        return [System.Windows.Controls.Primitives.CustomPopupPlacement[]]@($first, $second)
    }
    $UI.RecentPopup.Add_Closed({ $script:RoboGo.RecentClosed = [DateTime]::UtcNow })
    # looking at the window is enough to take the red off the taskbar button
    $UI.Window.Add_Activated({
            $s = $script:RoboGo
            if (($null -eq $s.Job) -and ($s.UI.Window.TaskbarItemInfo.ProgressState -eq [System.Windows.Shell.TaskbarItemProgressState]::Error)) { Set-RoboGoTaskbar 'None' }
        })
    $UI.ChkKeepLog.Add_Checked({ Invoke-RoboGoSafe { Set-RoboGoKeepLog $true } })
    $UI.ChkKeepLog.Add_Unchecked({ Invoke-RoboGoSafe { Set-RoboGoKeepLog $false } })

    # The help panel hangs under the ? button with its right edge on the button's right
    # edge. If there is no room below, it goes above the button.
    $UI.HelpPopup.PlacementTarget = $UI.BtnHelp
    $UI.HelpPopup.CustomPopupPlacementCallback = {
        param($popupSize, $targetSize, $offset)
        $x = $targetSize.Width - $popupSize.Width
        $axis = [System.Windows.Controls.Primitives.PopupPrimaryAxis]::Vertical
        $below = New-Object System.Windows.Point ($x, ($targetSize.Height + 4))
        $above = New-Object System.Windows.Point ($x, (-$popupSize.Height - 4))
        $first = New-Object System.Windows.Controls.Primitives.CustomPopupPlacement ($below, $axis)
        $second = New-Object System.Windows.Controls.Primitives.CustomPopupPlacement ($above, $axis)
        return [System.Windows.Controls.Primitives.CustomPopupPlacement[]]@($first, $second)
    }
    $UI.HelpPopup.Add_Closed({ $script:RoboGo.HelpClosed = [DateTime]::UtcNow })
    $UI.BtnHelp.Add_Click({ Invoke-RoboGoSafe { Show-RoboGoHelp } })

    $UI.Window.Add_Closing({
            param($window, $e)
            $s = $script:RoboGo
            if ($null -ne $s.Job) {
                if (-not (Confirm-RoboGo (Get-RoboText 'dialog.closing'))) {
                    $e.Cancel = $true
                    return
                }
                $s.Timer.Stop()
                Stop-RoboJob $s.Job
                [void](Close-RoboJobLog $s.Job)
                $s.Job = $null
            }
            $s.UI.HelpPopup.IsOpen = $false
            $s.UI.RecentPopup.IsOpen = $false
            # what the next start should find again
            try { Save-RoboGoState }
            catch { }
            Clear-RoboTaskbarIdentity $s.UI.Window
        })

    Set-RoboGoStatus 'status.ready'
    if ($givenFile) { Set-RoboGoStatus 'status.droppedFile' }
    Update-RoboGoLanguage
    Update-RoboGoRecentButtons
    Update-RoboGoSendTo
}

function Show-RoboGoWindow {
    param([string]$Source = '')
    # First start: write settings.json, so the log limits in it can be found and changed.
    $settings = Read-RoboSettings
    if (-not (Test-Path -LiteralPath (Get-RoboSettingsPath))) { [void](Save-RoboSettings $settings) }
    # Then the cleanup: logs that are too old or too big go, in TEMP and in the logs folder.
    try { Limit-RoboLogs -Days $settings.LogMaxDays -MaxFileMB $settings.LogFileMaxMB -MaxTotalMB $settings.LogMaxMB }
    catch { }
    # A Send to shortcut that points at an old place of this folder is put right.
    Update-RoboSendTo
    $ui = New-RoboGoWindow
    Initialize-RoboGoWindow $ui -Source $Source
    [void](Restore-RoboGoWindow $ui $script:RoboGo.Settings.Window)
    $area = [System.Windows.SystemParameters]::WorkArea
    if ($ui.Window.Height -gt ($area.Height - 16)) {
        $ui.Window.Height = [math]::Max($ui.Window.MinHeight, ($area.Height - 16))
    }
    Set-RoboDarkTitleBar $ui.Window
    [void](Set-RoboTaskbarIdentity $ui.Window)
    [void]$ui.Window.ShowDialog()
}

function Invoke-RoboGoSelfTest {
    # A quick built-in check that needs nothing but this file. Returns the number of failures.
    $checks = New-Object System.Collections.Generic.List[object]
    $o = New-RoboOptions
    $o.Source = 'C:\a b\'
    $o.Destination = 'D:\'
    $checks.Add(@('command builder', ((Get-RoboCommandLine $o) -eq 'robocopy "C:\a b" D:\ /E /MT:8 /R:2 /W:5 /XJ')))
    $tab = [string][char]9
    $state = New-RoboProgress
    Update-RoboProgress $state @(($tab + 'New File' + $tab + $tab + '10' + $tab + 'C:\a b\x.txt'), '100%')
    $checks.Add(@('log parser', (($state.CompletedFiles -eq 1) -and ($state.CompletedBytes -eq 10))))
    $checks.Add(@('robocopy.exe is present', (Test-Path -LiteralPath $script:RoboExe)))
    $windowOk = $false
    try {
        $ui = New-RoboGoWindow
        Initialize-RoboGoWindow $ui
        $windowOk = (($ui.CmdPanel.Children.Count -gt 0) -and ($ui.HelpSwitches.Children.Count -gt 0) -and ($ui.LblFrom.Text -ne ''))
    }
    catch {
        Write-Host ('       ' + $_.Exception.Message)
    }
    $checks.Add(@('window loads', $windowOk))
    $failed = 0
    foreach ($check in $checks) {
        if ($check[1]) { Write-Host ('[OK] ' + $check[0]) }
        else {
            Write-Host ('[X]  ' + $check[0])
            $failed++
        }
    }
    if ($failed -eq 0) { Write-Host ('RoboGo ' + $script:RoboGoVersion + ' self-test: all good') }
    else { Write-Host ('RoboGo ' + $script:RoboGoVersion + ' self-test, failed checks: ' + $failed) }
    return $failed
}

# ============================================================================
# Entry point
# ============================================================================

if ($NoUI) { return }
if ($SelfTest) { exit (Invoke-RoboGoSelfTest) }
# The launcher hands over a folder in the environment, where no quoting can go wrong.
if (($Source -eq '') -and (-not [string]::IsNullOrEmpty($env:ROBOGO_SOURCE))) { $Source = $env:ROBOGO_SOURCE }
$env:ROBOGO_SOURCE = $null
try {
    Show-RoboGoWindow -Source $Source
}
catch {
    # There is no console to print to when the launcher started the app, so say it in a box.
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show(((Get-RoboText 'dialog.startFail') + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message), 'RoboGo')
    exit 1
}
