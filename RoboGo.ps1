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
