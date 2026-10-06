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

$script:RoboGoVersion = '0.1.0'
$script:RoboExe = Join-Path $env:SystemRoot 'System32\robocopy.exe'
$script:Inv = [System.Globalization.CultureInfo]::InvariantCulture
# Switches that would break progress tracking or keep robocopy from ever exiting.
$script:RoboBlockedSwitches = @('/LOG', '/UNILOG', '/NFL', '/NS', '/NC', '/NP', '/NJS', '/QUIT', '/MON', '/MOT', '/JOB', '/SAVE')

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
    # -SkipFileSystem leaves out the disk check; the live preview uses it on every keystroke.
    param($Options, [switch]$SkipFileSystem)
    $problems = New-Object System.Collections.Generic.List[string]
    $src = ConvertTo-RoboPath $Options.Source
    $dst = ConvertTo-RoboPath $Options.Destination
    if ($src -eq '') {
        $problems.Add('Pick a source folder.')
    }
    elseif ((-not $SkipFileSystem) -and (-not (Test-Path -LiteralPath $src -PathType Container))) {
        $problems.Add('Source folder does not exist.')
    }
    if ($dst -eq '') { $problems.Add('Pick a destination folder.') }
    if (($src -ne '') -and ($dst -ne '')) {
        $s = Get-RoboComparablePath $src
        $d = Get-RoboComparablePath $dst
        if ($s -eq $d) {
            $problems.Add('Source and destination are the same folder.')
        }
        elseif ($d.StartsWith($s + '\')) {
            $problems.Add('Destination is inside the source folder.')
        }
        elseif (($Options.Mode -eq 'Mirror') -and $s.StartsWith($d + '\')) {
            $problems.Add('Mirror would delete the source, because it sits inside the destination.')
        }
    }
    if (-not (Test-RoboRange $Options.Threads 1 128)) { $problems.Add('Threads must be a number from 1 to 128.') }
    if (-not (Test-RoboRange $Options.Retries 0 1000000)) { $problems.Add('Retries must be a number from 0 to 1000000.') }
    if (-not (Test-RoboRange $Options.Wait 0 3600)) { $problems.Add('Wait must be a number of seconds from 0 to 3600.') }
    foreach ($token in (([string]$Options.Extra) -split '\s+')) {
        if (-not $token.StartsWith('/')) { continue }
        $name = ($token.ToUpperInvariant() -split ':')[0].TrimEnd('+')
        if ($script:RoboBlockedSwitches -contains $name) {
            $problems.Add("Extra switches: $name is not supported, RoboGo needs robocopy's standard log output.")
        }
    }
    return , $problems.ToArray()
}

function Get-RoboDanger {
    # A warning sentence when the options delete data, otherwise an empty string.
    param($Options)
    $extra = (' ' + [string]$Options.Extra + ' ').ToUpperInvariant()
    if (($Options.Mode -eq 'Mirror') -or ($extra -match '\s/(MIR|PURGE)\s')) {
        return 'Mirror deletes everything in the destination that is not in the source.'
    }
    if (($Options.Mode -eq 'Move') -or ($extra -match '\s/MOVE?\s')) {
        return 'Move deletes the files from the source after copying them.'
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
        return @{ Level = 'warn'; Text = 'Cancelled. Files that were already copied stay in the destination.' }
    }
    $detail = ''
    if ($Summary) {
        $verb = $(if ($DryRun) { 'Would copy' } else { 'Copied' })
        $detail = '{0} {1} file(s), {2}' -f $verb, $Summary.Files.Copied, (Format-RoboBytes $Summary.Bytes.Copied)
        if ($Summary.Files.Skipped -gt 0) { $detail += (', {0} skipped' -f $Summary.Files.Skipped) }
        if ($Summary.Files.Failed -gt 0) { $detail += (', {0} FAILED' -f $Summary.Files.Failed) }
        $extras = $Summary.Files.Extras + $Summary.Dirs.Extras
        if ($extras -gt 0) {
            if ($Mirror -and $DryRun) { $detail += (', {0} extra item(s) would be deleted from the destination' -f $extras) }
            elseif ($Mirror) { $detail += (', {0} extra item(s) deleted from the destination' -f $extras) }
            else { $detail += (', {0} extra item(s) in the destination left alone' -f $extras) }
        }
        $detail += '.'
    }
    if (($ExitCode -lt 0) -or ($ExitCode -ge 16)) {
        return @{ Level = 'error'; Text = "Fatal error (robocopy exit code $ExitCode). The job did not run properly: check the paths and the log." }
    }
    if (($ExitCode -band 8) -ne 0) {
        return @{ Level = 'error'; Text = ("Finished with errors. $detail See the log for the files that failed.").Replace('  ', ' ') }
    }
    if ($DryRun) {
        return @{ Level = 'ok'; Text = ("Dry run, nothing was changed. $detail").Trim() }
    }
    if (($ExitCode -band 4) -ne 0) {
        return @{ Level = 'warn'; Text = ("Done, but some items are mismatched (a file where a folder is expected, or the reverse). $detail").Trim() }
    }
    if (($ExitCode -band 1) -ne 0) {
        return @{ Level = 'ok'; Text = ("Done. $detail").Trim() }
    }
    return @{ Level = 'ok'; Text = ("Nothing to copy, the destination is already up to date. $detail").Trim() }
}
