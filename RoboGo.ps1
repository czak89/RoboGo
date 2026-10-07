<#
.SYNOPSIS
    RoboGo: builds a robocopy command, runs it and tracks the progress.
.DESCRIPTION
    Start it with RoboGo.cmd (double-click). It needs nothing but Windows 10 or 11:
    robocopy and WPF are part of the system.
.PARAMETER NoUI
    Only define the functions. The test scripts dot-source the file this way.
.PARAMETER SelfTest
    Run the built-in sanity checks, load the window without showing it and exit with the
    number of failed checks.
#>
[CmdletBinding()]
param(
    [switch]$NoUI,
    [switch]$SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RoboGoVersion = '0.2.0'
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

# ============================================================================
# 0. Texts, languages, settings
#    Every text the app itself shows lives in this table. A lang\<code>.json file
#    with the same keys overrides it for that language (tools\Export-Language.ps1
#    writes one). {0}, {1} are filled in by the code. Robocopy's own output is not
#    translated.
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

    # status line and log notes
    'status.ready'         = 'Ready.'
    'status.scanning'      = 'Scanning: counting what needs to be copied...'
    'status.dryRun'        = 'Dry run: listing what would happen. Nothing is changed.'
    'status.copying'       = 'Copying...'
    'status.copyingErrors' = 'Copying... {0} error(s) so far, see the log.'
    'status.stopping'      = 'Stopping...'
    'status.copied'        = 'Command copied to the clipboard.'
    'status.logCopied'     = 'Log copied to the clipboard.'
    'status.droppedFile'   = 'That was a file, so its folder was taken.'
    'status.error'         = 'Unexpected error: {0}'
    'status.settings'      = 'The setting could not be saved: the RoboGo folder is not writable.'
    'log.scan'             = 'Scan: {0} file(s), {1} to copy.'
    'log.scanNoTotals'     = 'Scan: no totals found, running without percent.'
    'log.saved'            = 'Log saved: {0}'

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
    'verdict.copied'        = 'Copied {0} file(s), {1}'
    'verdict.wouldCopy'     = 'Would copy {0} file(s), {1}'
    'verdict.skipped'       = ', {0} skipped'
    'verdict.failed'        = ', {0} FAILED'
    'verdict.extrasWould'   = ', {0} extra item(s) would be deleted from the destination'
    'verdict.extrasDeleted' = ', {0} extra item(s) deleted from the destination'
    'verdict.extrasLeft'    = ', {0} extra item(s) in the destination left alone'
    'verdict.fatal'         = 'Fatal error (robocopy exit code {0}). The job did not run properly: check the paths and the log.'
    'verdict.errors'        = 'Finished with errors. {0} See the log for the files that failed.'
    'verdict.dry'           = 'Dry run, nothing was changed. {0}'
    'verdict.mismatch'      = 'Done, but some items are mismatched (a file where a folder is expected, or the reverse). {0}'
    'verdict.done'          = 'Done. {0}'
    'verdict.nothing'       = 'Nothing to copy, the destination is already up to date. {0}'

    # dialogs
    'dialog.confirmTip'  = 'DRY RUN shows what would happen without touching anything.'
    'dialog.confirmAsk'  = 'Run it for real?'
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

function Read-RoboSettings {
    # The saved choices, or the defaults when there is no usable settings file.
    $settings = @{ Language = 'en'; KeepLog = $false }
    $path = Get-RoboSettingsPath
    if (Test-Path -LiteralPath $path) {
        try {
            $data = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if (($null -ne $data.PSObject.Properties['Language']) -and ($data.Language -is [string])) { $settings.Language = $data.Language }
            if (($null -ne $data.PSObject.Properties['KeepLog']) -and ($data.KeepLog -is [bool])) { $settings.KeepLog = $data.KeepLog }
        }
        catch { }
    }
    return $settings
}

function Save-RoboSettings {
    # Writes settings.json next to the program. Returns $false when the folder is not writable.
    param([hashtable]$Settings)
    $saved = $false
    try {
        $language = ([string]$Settings.Language).Replace('\', '').Replace('"', '')
        $keep = 'false'
        if ($Settings.KeepLog) { $keep = 'true' }
        $json = '{' + [Environment]::NewLine + '  "Language": "' + $language + '",' + [Environment]::NewLine + '  "KeepLog": ' + $keep + [Environment]::NewLine + '}' + [Environment]::NewLine
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

# ============================================================================
# 2. Log parser. It reads the structure of robocopy's log (tabs, digits, the
#    percent sign, the 0x error code), never its words, so the Windows display
#    language does not matter.
# ============================================================================

$script:RxRoboError = New-Object System.Text.RegularExpressions.Regex '^\S.*\s\d+ \(0x[0-9A-Fa-f]{8}\)\s'
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
    #   error        "date time ERROR 32 (0x00000020) "  -> counted, the file stays unfinished
    #   summary row  "  Files :  4  4  0  0  0  1"       -> the final numbers
    # A file counts as copied only when its 100% arrives.
    param([hashtable]$State, [string[]]$Lines)
    foreach ($line in $Lines) {
        if ($line.Length -eq 0) { continue }
        $first = [int]$line[0]
        if ($first -eq 9) {
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
    $detail = ''
    if ($Summary) {
        $key = 'verdict.copied'
        if ($DryRun) { $key = 'verdict.wouldCopy' }
        $detail = Get-RoboText $key $Summary.Files.Copied, (Format-RoboBytes $Summary.Bytes.Copied)
        if ($Summary.Files.Skipped -gt 0) { $detail += (Get-RoboText 'verdict.skipped' $Summary.Files.Skipped) }
        if ($Summary.Files.Failed -gt 0) { $detail += (Get-RoboText 'verdict.failed' $Summary.Files.Failed) }
        $extras = $Summary.Files.Extras + $Summary.Dirs.Extras
        if ($extras -gt 0) {
            if ($Mirror -and $DryRun) { $detail += (Get-RoboText 'verdict.extrasWould' $extras) }
            elseif ($Mirror) { $detail += (Get-RoboText 'verdict.extrasDeleted' $extras) }
            else { $detail += (Get-RoboText 'verdict.extrasLeft' $extras) }
        }
        $detail += '.'
    }
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

function Remove-RoboOldLogs {
    # Keeps the newest log files in the log folder and deletes the rest. CmdletBinding makes
    # a mistyped parameter an error instead of a silent run against the default folder.
    [CmdletBinding()]
    param([int]$Keep = 20, [string]$Directory = (Get-RoboLogDir))
    $files = @(Get-ChildItem -LiteralPath $Directory -Filter '*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
    for ($i = $Keep; $i -lt $files.Count; $i++) {
        Remove-Item -LiteralPath $files[$i].FullName -Force -ErrorAction SilentlyContinue
    }
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
# ============================================================================

$script:RoboGoControls = @(
    'Root', 'TxtVersion', 'TxtSource', 'BtnSource', 'TxtDest', 'BtnDest',
    'RbCopy', 'RbMirror', 'RbMove', 'TxtModeHint', 'ChkSub', 'ChkJunction', 'ChkNewer', 'ChkRestart',
    'TxtThreads', 'TxtRetries', 'TxtWait', 'TxtXF', 'TxtXD', 'TxtExtra',
    'BtnCopyCmd', 'TapeEdge', 'CmdPanel', 'TxtProblem', 'ChkScan', 'BtnDry', 'BtnRun', 'BtnCancel',
    'BtnToggleLog', 'BtnOpenLog', 'Bar', 'TxtPercent', 'TxtFiles', 'TxtData', 'TxtSpeed', 'LblEta', 'TxtEta',
    'TxtCurrent', 'TxtStatus', 'TxtLog'
)
# Controls that are locked while a job runs.
$script:RoboGoInputs = @(
    'TxtSource', 'BtnSource', 'TxtDest', 'BtnDest', 'RbCopy', 'RbMirror', 'RbMove',
    'ChkSub', 'ChkJunction', 'ChkNewer', 'ChkRestart', 'TxtThreads', 'TxtRetries', 'TxtWait',
    'TxtXF', 'TxtXD', 'TxtExtra', 'ChkScan', 'BtnDry', 'BtnRun'
)
$script:RoboGoPartBrush = @{ 'exe' = 'Dim'; 'path' = 'Ink'; 'switch' = 'Amber'; 'danger' = 'Danger'; 'value' = 'Ink' }
$script:RoboGo = $null

function Get-RoboGoXaml {
    return @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="RoboGo" Width="900" Height="860" MinWidth="780" MinHeight="680"
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
      <Setter Property="Padding" Value="0,14,0,14"/>
    </Style>
    <Style x:Key="Rail" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Margin" Value="0,7,0,0"/>
      <Setter Property="VerticalAlignment" Value="Top"/>
    </Style>
    <Style x:Key="Lbl" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Dim}"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>

    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="{StaticResource Bg2}"/>
      <Setter Property="Foreground" Value="{StaticResource Ink}"/>
      <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
      <Setter Property="FontFamily" Value="Cascadia Mono, Cascadia Code, Consolas"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="Padding" Value="8,5"/>
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
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
            </Border>
            <ControlTemplate.Triggers>
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
      <Setter Property="Padding" Value="14,4"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
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
            <Border x:Name="Bd" Background="{StaticResource Bg2}" BorderBrush="{StaticResource Line}" BorderThickness="1" Padding="18,4" Margin="0,0,-1,0">
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
      <Setter Property="Height" Value="18"/>
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
                      <DoubleAnimation Storyboard.TargetName="Sweep" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)" From="0" To="612" Duration="0:0:1.6"/>
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

  <Border x:Name="Root" Background="{StaticResource Bg0}" Padding="22,14,22,18">
    <Grid>
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>

      <DockPanel Grid.Row="0" Margin="0,0,0,12" LastChildFill="False">
        <TextBlock DockPanel.Dock="Left" Text="ROBOGO" FontSize="22" FontWeight="Bold" Foreground="{StaticResource Amber}"/>
        <TextBlock DockPanel.Dock="Left" Text="robocopy, minus the typing" Margin="14,0,0,4" VerticalAlignment="Bottom" Foreground="{StaticResource Dim}"/>
        <TextBlock x:Name="TxtVersion" DockPanel.Dock="Right" Margin="0,0,0,4" VerticalAlignment="Bottom" Foreground="{StaticResource Dim}"/>
      </DockPanel>

      <Border Grid.Row="1" Style="{StaticResource Section}">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="118"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <TextBlock Style="{StaticResource Rail}"><Run Text="01" Foreground="{StaticResource Amber}" FontWeight="Bold"/><Run Text="  PATHS"/></TextBlock>
          <Grid Grid.Column="1">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="48"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            <TextBlock Text="FROM" Style="{StaticResource Lbl}"/>
            <TextBox x:Name="TxtSource" Grid.Column="1" AllowDrop="True" ToolTip="The folder to copy from. Type, paste, browse, or drop a folder here."/>
            <Button x:Name="BtnSource" Grid.Column="2" Content="BROWSE" Margin="8,0,0,0"/>
            <TextBlock Grid.Row="1" Text="TO" Style="{StaticResource Lbl}" Margin="0,8,0,0"/>
            <TextBox x:Name="TxtDest" Grid.Row="1" Grid.Column="1" Margin="0,8,0,0" AllowDrop="True" ToolTip="The folder to copy into. It is created if it does not exist."/>
            <Button x:Name="BtnDest" Grid.Row="1" Grid.Column="2" Content="BROWSE" Margin="8,8,0,0"/>
            <TextBlock Grid.Row="2" Grid.Column="1" Grid.ColumnSpan="2" Margin="0,8,0,0" FontSize="11" Foreground="{StaticResource Dim}" TextWrapping="Wrap" Text="Robocopy copies what is inside FROM into TO. It does not create the FROM folder itself."/>
          </Grid>
        </Grid>
      </Border>

      <Border Grid.Row="2" Style="{StaticResource Section}">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="118"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <TextBlock Style="{StaticResource Rail}"><Run Text="02" Foreground="{StaticResource Amber}" FontWeight="Bold"/><Run Text="  OPTIONS"/></TextBlock>
          <StackPanel Grid.Column="1">
            <DockPanel LastChildFill="False">
              <RadioButton x:Name="RbCopy" DockPanel.Dock="Left" GroupName="Mode" Style="{StaticResource Seg}" Content="COPY" IsChecked="True" ToolTip="Add and update files in TO. Nothing is deleted."/>
              <RadioButton x:Name="RbMirror" DockPanel.Dock="Left" GroupName="Mode" Style="{StaticResource Seg}" Content="MIRROR" Tag="danger" ToolTip="/MIR  make TO identical to FROM. Whatever is extra in TO is deleted."/>
              <RadioButton x:Name="RbMove" DockPanel.Dock="Left" GroupName="Mode" Style="{StaticResource Seg}" Content="MOVE" Tag="danger" ToolTip="/MOVE  copy, then delete from FROM."/>
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                <TextBlock Text="THREADS" Style="{StaticResource Lbl}"/>
                <TextBox x:Name="TxtThreads" Width="46" Margin="8,0,18,0" Text="8" MaxLength="3" ToolTip="/MT:n  files copied in parallel. 1 turns it off."/>
                <TextBlock Text="RETRIES" Style="{StaticResource Lbl}"/>
                <TextBox x:Name="TxtRetries" Width="64" Margin="8,0,18,0" Text="2" MaxLength="7" ToolTip="/R:n  retries per failed file. Robocopy's own default is one million."/>
                <TextBlock Text="WAIT S" Style="{StaticResource Lbl}"/>
                <TextBox x:Name="TxtWait" Width="46" Margin="8,0,0,0" Text="5" MaxLength="4" ToolTip="/W:n  seconds to wait between retries."/>
              </StackPanel>
            </DockPanel>
            <TextBlock x:Name="TxtModeHint" Margin="0,8,0,0" FontSize="11" TextWrapping="Wrap" Foreground="{StaticResource Dim}"/>
            <WrapPanel Margin="0,12,0,0">
              <CheckBox x:Name="ChkSub" Content="Subfolders" IsChecked="True" Margin="0,0,26,0" ToolTip="/E  include subfolders, empty ones too."/>
              <CheckBox x:Name="ChkJunction" Content="Skip junctions" IsChecked="True" Margin="0,0,26,0" ToolTip="/XJ  do not follow junction points. Avoids endless loops in user profiles."/>
              <CheckBox x:Name="ChkNewer" Content="Keep newer files" Margin="0,0,26,0" ToolTip="/XO  do not overwrite a file in TO with an older one from FROM."/>
              <CheckBox x:Name="ChkRestart" Content="Restartable" ToolTip="/Z  resume a half-copied file after a network drop. Slower."/>
            </WrapPanel>
            <Grid Margin="0,12,0,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="86"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="SKIP FILES" Style="{StaticResource Lbl}"/>
              <TextBox x:Name="TxtXF" Grid.Column="1" ToolTip="/XF  file names or patterns to leave out, separated by ;    Example: *.tmp; thumbs.db"/>
              <TextBlock Grid.Column="2" Text="SKIP FOLDERS" Style="{StaticResource Lbl}" Margin="18,0,8,0"/>
              <TextBox x:Name="TxtXD" Grid.Column="3" ToolTip="/XD  folder names or paths to leave out, separated by ;    Example: node_modules; .git"/>
            </Grid>
            <Grid Margin="0,8,0,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="86"/>
                <ColumnDefinition Width="*"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="EXTRA" Style="{StaticResource Lbl}"/>
              <TextBox x:Name="TxtExtra" Grid.Column="1" ToolTip="Any other robocopy switches or file filters, added exactly as typed.    Example: *.jpg /MAXAGE:7"/>
            </Grid>
          </StackPanel>
        </Grid>
      </Border>

      <Border Grid.Row="3" Style="{StaticResource Section}">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="118"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <StackPanel>
            <TextBlock Style="{StaticResource Rail}"><Run Text="03" Foreground="{StaticResource Amber}" FontWeight="Bold"/><Run Text="  COMMAND"/></TextBlock>
            <Button x:Name="BtnCopyCmd" Style="{StaticResource Small}" Content="COPY" Margin="0,10,0,0" ToolTip="Copy the command to the clipboard."/>
          </StackPanel>
          <StackPanel Grid.Column="1">
            <Border x:Name="TapeEdge" BorderBrush="{StaticResource Amber}" BorderThickness="3,0,0,0">
              <Border Background="{StaticResource Bg1}" BorderBrush="{StaticResource Line}" BorderThickness="0,1,1,1" Padding="12,9">
                <WrapPanel x:Name="CmdPanel"/>
              </Border>
            </Border>
            <TextBlock x:Name="TxtProblem" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="{StaticResource Danger}" Visibility="Collapsed"/>
            <DockPanel Margin="0,12,0,0" LastChildFill="False">
              <CheckBox x:Name="ChkScan" DockPanel.Dock="Left" VerticalAlignment="Center" Content="Scan first for exact % and ETA" IsChecked="True" ToolTip="Counts what needs copying before the real run. Turn it off for huge trees: you then get counters but no percent."/>
              <Button x:Name="BtnCancel" DockPanel.Dock="Right" Content="CANCEL" Margin="8,0,0,0" IsEnabled="False"/>
              <Button x:Name="BtnRun" DockPanel.Dock="Right" Style="{StaticResource Primary}" Content="RUN" MinWidth="110" Margin="8,0,0,0"/>
              <Button x:Name="BtnDry" DockPanel.Dock="Right" Content="DRY RUN" ToolTip="/L  list what would happen without copying or deleting anything."/>
            </DockPanel>
          </StackPanel>
        </Grid>
      </Border>

      <Border Grid.Row="4" Style="{StaticResource Section}" Padding="0,14,0,0">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="118"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <StackPanel>
            <TextBlock Style="{StaticResource Rail}" Margin="0,2,0,0"><Run Text="04" Foreground="{StaticResource Amber}" FontWeight="Bold"/><Run Text="  PROGRESS"/></TextBlock>
            <Button x:Name="BtnToggleLog" Style="{StaticResource Small}" Content="HIDE LOG" Margin="0,10,0,0"/>
            <Button x:Name="BtnOpenLog" Style="{StaticResource Small}" Content="OPEN LOG" Margin="0,6,0,0" IsEnabled="False" ToolTip="Open the full robocopy log of the last job."/>
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
                <ColumnDefinition Width="82"/>
              </Grid.ColumnDefinitions>
              <ProgressBar x:Name="Bar" Minimum="0" Maximum="100" Value="0"/>
              <TextBlock x:Name="TxtPercent" Grid.Column="1" Text="--" TextAlignment="Right" VerticalAlignment="Center" FontSize="16" FontWeight="Bold" Foreground="{StaticResource Amber}"/>
            </Grid>
            <UniformGrid Grid.Row="1" Columns="4" Margin="0,10,0,0">
              <StackPanel>
                <TextBlock Text="FILES" Style="{StaticResource Lbl}"/>
                <TextBlock x:Name="TxtFiles" Text="--" FontSize="14" Margin="0,2,0,0"/>
              </StackPanel>
              <StackPanel>
                <TextBlock Text="DATA" Style="{StaticResource Lbl}"/>
                <TextBlock x:Name="TxtData" Text="--" FontSize="14" Margin="0,2,0,0"/>
              </StackPanel>
              <StackPanel>
                <TextBlock Text="SPEED" Style="{StaticResource Lbl}"/>
                <TextBlock x:Name="TxtSpeed" Text="--" FontSize="14" Margin="0,2,0,0"/>
              </StackPanel>
              <StackPanel>
                <TextBlock x:Name="LblEta" Text="ETA" Style="{StaticResource Lbl}"/>
                <TextBlock x:Name="TxtEta" Text="--" FontSize="14" Margin="0,2,0,0"/>
              </StackPanel>
            </UniformGrid>
            <TextBlock x:Name="TxtCurrent" Grid.Row="2" Margin="0,10,0,0" FontSize="11.5" Foreground="{StaticResource Dim}" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="TxtStatus" Grid.Row="3" Margin="0,6,0,0" TextWrapping="Wrap" Text="Ready."/>
            <TextBox x:Name="TxtLog" Grid.Row="4" Margin="0,10,0,0" MinHeight="70" IsReadOnly="True" AcceptsReturn="True" TextWrapping="NoWrap" VerticalContentAlignment="Stretch" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Background="{StaticResource Bg1}" Foreground="{StaticResource Dim}" FontSize="11.5"/>
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

function Set-RoboGoStatus {
    # Level: info, ok, warn or error.
    param([string]$Text, [string]$Level = 'info')
    $ui = $script:RoboGo.UI
    $brush = 'Ink'
    if ($Level -eq 'ok') { $brush = 'Ok' }
    elseif ($Level -eq 'warn') { $brush = 'Amber' }
    elseif ($Level -eq 'error') { $brush = 'Danger' }
    $ui.TxtStatus.Text = $Text
    $ui.TxtStatus.Foreground = $ui.Window.FindResource($brush)
}

function Invoke-RoboGoSafe {
    # Runs an event handler body. An unexpected error lands in the status line instead of
    # taking the window down.
    param([scriptblock]$Action)
    try { & $Action }
    catch { Set-RoboGoStatus ('Unexpected error: ' + $_.Exception.Message) 'error' }
}

function Update-RoboGoPreview {
    # Rebuilds the coloured command, the mode hint and the problem line from the fields.
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
            $piece.FontSize = 13.5
            $piece.TextWrapping = 'Wrap'
            $piece.Foreground = $brush
            # only the last piece of a token is followed by a gap
            $gap = 0
            if ($i -eq ($pieces.Count - 1)) { $gap = 9 }
            $piece.Margin = New-Object System.Windows.Thickness (0, 1, $gap, 1)
            [void]$ui.CmdPanel.Children.Add($piece)
        }
    }
    $danger = Get-RoboDanger $options
    if ($danger -ne '') {
        $ui.TxtModeHint.Text = $danger
        $ui.TxtModeHint.Foreground = $ui.Window.FindResource('Danger')
        $ui.TapeEdge.BorderBrush = $ui.Window.FindResource('Danger')
    }
    else {
        $ui.TxtModeHint.Text = 'Copy adds and updates files in TO. Nothing is deleted.'
        $ui.TxtModeHint.Foreground = $ui.Window.FindResource('Dim')
        $ui.TapeEdge.BorderBrush = $ui.Window.FindResource('Amber')
    }
    if ($null -eq $script:RoboGo.Job) { $ui.ChkSub.IsEnabled = ($options.Mode -ne 'Mirror') }
    # Empty paths are not nagged about while typing; Run checks everything, disk included.
    $all = Test-RoboOptions $options -SkipFileSystem
    $problems = @($all | Where-Object { $_ -notlike 'Pick a *' })
    if ($problems.Count -gt 0) {
        $ui.TxtProblem.Text = $problems[0]
        $ui.TxtProblem.Visibility = 'Visible'
    }
    else {
        $ui.TxtProblem.Visibility = 'Collapsed'
    }
}

function Add-RoboGoLog {
    param([string]$Line)
    $s = $script:RoboGo
    $s.LogLines.Add($Line)
    if ($s.LogLines.Count -gt 600) { $s.LogLines.RemoveRange(0, $s.LogLines.Count - 500) }
    $s.LogDirty = $true
}

function Update-RoboGoLogView {
    # The box shows the last few hundred lines; the full log is in the log file.
    $s = $script:RoboGo
    if (-not $s.LogDirty) { return }
    $s.UI.TxtLog.Text = [string]::Join([Environment]::NewLine, $s.LogLines.ToArray())
    $s.UI.TxtLog.ScrollToEnd()
    $s.LogDirty = $false
}

function Set-RoboGoBusy {
    param([bool]$Busy)
    $ui = $script:RoboGo.UI
    foreach ($name in $script:RoboGoInputs) { $ui[$name].IsEnabled = (-not $Busy) }
    $ui.BtnCancel.IsEnabled = $Busy
    if (-not $Busy) { $ui.ChkSub.IsEnabled = (-not [bool]$ui.RbMirror.IsChecked) }
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
    if ($Phase -eq 'Scan') { Set-RoboGoStatus 'Scanning: counting what needs to be copied...' }
    elseif ($Phase -eq 'DryRun') { Set-RoboGoStatus 'Dry run: listing what would happen. Nothing is changed.' }
    else { Set-RoboGoStatus 'Copying...' }
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
        $message = $danger + "`n`nFROM  " + (ConvertTo-RoboPath $options.Source) + "`nTO    " + (ConvertTo-RoboPath $options.Destination) + "`n`nDRY RUN shows what would happen without touching anything.`n`nRun it for real?"
        $answer = [System.Windows.MessageBox]::Show($ui.Window, $message, 'RoboGo', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning, [System.Windows.MessageBoxResult]::No)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }
    Remove-RoboOldLogs
    $s.Options = $options
    $s.DryRun = [bool]$DryRun
    $s.Cancelled = $false
    $s.TotalFiles = [long]-1
    $s.TotalBytes = [long]-1
    $s.ScanLines.Clear()
    $s.LogLines.Clear()
    $s.TotalClock = [System.Diagnostics.Stopwatch]::StartNew()
    $ui.Bar.Value = 0
    foreach ($name in 'TxtPercent', 'TxtFiles', 'TxtData', 'TxtSpeed', 'TxtEta') { $ui[$name].Text = '--' }
    $ui.LblEta.Text = 'ETA'
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
    Set-RoboGoStatus 'Stopping...' 'warn'
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
    $ui.TxtCurrent.Text = Get-RoboShortPath $state.CurrentFile 110
    if ($s.TotalBytes -gt 0) {
        # 100 is reserved for the moment robocopy has exited successfully.
        $pct = [math]::Min(99.9, (100.0 * $done / $s.TotalBytes))
        $ui.Bar.Value = $pct
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
    if ($state.Errors -gt 0) {
        Set-RoboGoStatus ('Copying... {0} error(s) so far, see the log.' -f $state.Errors) 'warn'
    }
}

function Complete-RoboGo {
    # The job is over (finished, failed or cancelled): show the verdict and unlock the window.
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
    $ui.LblEta.Text = 'TOOK'
    $ui.TxtEta.Text = Format-RoboDuration $s.TotalClock.Elapsed.TotalSeconds
    $ui.TxtCurrent.Text = ''
    Set-RoboGoStatus $verdict.Text $verdict.Level
    Add-RoboGoLog ('== ' + $verdict.Text)
    Update-RoboGoLogView
    $s.LastLog = $job.LogPath
    $ui.BtnOpenLog.IsEnabled = $true
    $s.Job = $null
    $s.Phase = 'Idle'
    Set-RoboGoBusy $false
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
            Add-RoboGoLog ('Scan: {0} file(s), {1} to copy.' -f $s.TotalFiles, (Format-RoboBytes $s.TotalBytes))
        }
        else {
            Add-RoboGoLog 'Scan: no totals found, running without percent.'
        }
        Start-RoboGoPhase 'Run'
        Update-RoboGoLogView
        return
    }
    foreach ($line in $lines) { Add-RoboGoLog $line }
    Update-RoboGoNumbers
    Update-RoboGoLogView
    if ($job.Done) { Complete-RoboGo }
}

function Stop-RoboGoOnError {
    # A tick failed unexpectedly: stop everything and say so.
    param($ErrorRecord)
    $s = $script:RoboGo
    $s.Timer.Stop()
    if ($null -ne $s.Job) {
        Stop-RoboJob $s.Job
        $s.Job = $null
    }
    $s.Phase = 'Idle'
    $s.UI.Bar.IsIndeterminate = $false
    Set-RoboGoBusy $false
    Set-RoboGoStatus ('Unexpected error: ' + $ErrorRecord.Exception.Message) 'error'
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
        $ui.BtnToggleLog.Content = 'SHOW LOG'
        $window.MinHeight = 0
        $window.SizeToContent = 'Height'
    }
    else {
        $window.SizeToContent = 'Manual'
        $window.MinHeight = $s.SavedMinHeight
        if ($s.SavedHeight -gt 0) { $window.Height = $s.SavedHeight }
        $ui.TxtLog.Visibility = 'Visible'
        $ui.BtnToggleLog.Content = 'HIDE LOG'
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
        if (-not ('RoboGo.Dwm' -as [type])) {
            Add-Type -Namespace RoboGo -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);'
        }
        $handle = (New-Object System.Windows.Interop.WindowInteropHelper $Window).EnsureHandle()
        $on = 1
        [void][RoboGo.Dwm]::DwmSetWindowAttribute($handle, 20, [ref]$on, 4)
        # 35 caption, 36 caption text, 34 border. A COLORREF is 0x00BBGGRR. Without these an
        # accent-coloured title bar would sit on top of the dark window. Windows 10 ignores them.
        $caption = 0x000E0C0B
        $captionText = 0x00E1E6E8
        $border = 0x00342E2A
        [void][RoboGo.Dwm]::DwmSetWindowAttribute($handle, 35, [ref]$caption, 4)
        [void][RoboGo.Dwm]::DwmSetWindowAttribute($handle, 36, [ref]$captionText, 4)
        [void][RoboGo.Dwm]::DwmSetWindowAttribute($handle, 34, [ref]$border, 4)
    }
    catch { }
}

function Initialize-RoboGoWindow {
    # Wires the events and creates the controller state. Kept apart from New-RoboGoWindow
    # so that the tests can drive the window without showing it.
    param($UI)
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:RoboGo = @{
        UI             = $UI
        Timer          = $timer
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
        LogDirty       = $false
        ScanLines      = (New-Object System.Collections.Generic.List[string])
        LastLog        = ''
        SavedHeight    = 0.0
        SavedMinHeight = 0.0
    }
    $UI.TxtVersion.Text = 'v' + $script:RoboGoVersion

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

    $UI.BtnSource.Add_Click({
            Invoke-RoboGoSafe {
                $box = $script:RoboGo.UI.TxtSource
                $picked = Select-RoboFolder $box.Text 'Pick the folder to copy FROM'
                if ($picked -ne '') { $box.Text = $picked }
            }
        })
    $UI.BtnDest.Add_Click({
            Invoke-RoboGoSafe {
                $box = $script:RoboGo.UI.TxtDest
                $picked = Select-RoboFolder $box.Text 'Pick the folder to copy TO'
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
                            Set-RoboGoStatus 'That was a file, so its folder was taken.'
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
    $UI.BtnCopyCmd.Add_Click({
            Invoke-RoboGoSafe {
                [System.Windows.Clipboard]::SetText((Get-RoboCommandLine (Get-RoboGoOptions $script:RoboGo.UI)))
                if ($null -eq $script:RoboGo.Job) { Set-RoboGoStatus 'Command copied to the clipboard.' }
            }
        })
    $UI.BtnToggleLog.Add_Click({ Invoke-RoboGoSafe { Switch-RoboGoLog } })
    $UI.BtnOpenLog.Add_Click({
            Invoke-RoboGoSafe {
                $log = $script:RoboGo.LastLog
                if (($log -ne '') -and (Test-Path -LiteralPath $log)) { Invoke-Item -LiteralPath $log }
            }
        })

    $UI.Window.Add_Closing({
            param($window, $e)
            $s = $script:RoboGo
            if ($null -ne $s.Job) {
                $answer = [System.Windows.MessageBox]::Show($s.UI.Window, 'A job is still running. Stop it and close RoboGo?', 'RoboGo', [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning, [System.Windows.MessageBoxResult]::No)
                if ($answer -ne [System.Windows.MessageBoxResult]::Yes) {
                    $e.Cancel = $true
                    return
                }
                $s.Timer.Stop()
                Stop-RoboJob $s.Job
                $s.Job = $null
            }
        })

    Update-RoboGoPreview
}

function Show-RoboGoWindow {
    $ui = New-RoboGoWindow
    Initialize-RoboGoWindow $ui
    $area = [System.Windows.SystemParameters]::WorkArea
    if ($ui.Window.Height -gt ($area.Height - 16)) {
        $ui.Window.Height = [math]::Max($ui.Window.MinHeight, ($area.Height - 16))
    }
    Set-RoboDarkTitleBar $ui.Window
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
        $windowOk = ($ui.CmdPanel.Children.Count -gt 0)
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
    else { Write-Host ('RoboGo ' + $script:RoboGoVersion + ' self-test: ' + $failed + ' check(s) failed') }
    return $failed
}

# ============================================================================
# Entry point
# ============================================================================

if ($NoUI) { return }
if ($SelfTest) { exit (Invoke-RoboGoSelfTest) }
try {
    Show-RoboGoWindow
}
catch {
    # The console is hidden when started through RoboGo.cmd, so say it in a box.
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show(('RoboGo could not start.' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message), 'RoboGo')
    exit 1
}
