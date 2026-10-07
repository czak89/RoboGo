# Writes or refreshes lang\<code>.json for translators: every key of the English text table,
# in a stable order. Translations that are already in the file are kept; keys that are new
# get the English text; keys that no longer exist are dropped.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\Export-Language.ps1 -Code pl -Name Polski
param(
    [Parameter(Mandatory = $true)][string]$Code,
    [string]$Name = ''
)
$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot '..\RoboGo.ps1'
. $app -NoUI

function ConvertTo-JsonText {
    param([string]$Text)
    $t = $Text.Replace('\', '\\').Replace('"', '\"')
    $t = $t.Replace([string][char]13, '').Replace([string][char]10, '\n').Replace([string][char]9, '\t')
    return ('"' + $t + '"')
}

$language = $Code.Trim().ToLowerInvariant()
$dir = Join-Path $script:RoboAppDir 'lang'
if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
$path = Join-Path $dir ($language + '.json')

$existing = @{}
if (Test-Path -LiteralPath $path) {
    $data = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($entry in $data.PSObject.Properties) {
        if ($entry.Value -is [string]) { $existing[$entry.Name] = $entry.Value }
    }
}
if ($Name -eq '') {
    if ($existing.ContainsKey('_name')) { $Name = $existing['_name'] } else { $Name = $language.ToUpperInvariant() }
}

[string[]]$keys = @($script:RoboText.Keys)
[System.Array]::Sort($keys, [System.StringComparer]::Ordinal)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('  "_name": ' + (ConvertTo-JsonText $Name))
$kept = 0
foreach ($key in $keys) {
    $value = [string]$script:RoboText[$key]
    if ($existing.ContainsKey($key) -and ($existing[$key] -ne '')) {
        $value = $existing[$key]
        if ($value -cne [string]$script:RoboText[$key]) { $kept++ }
    }
    $lines.Add('  ' + (ConvertTo-JsonText $key) + ': ' + (ConvertTo-JsonText $value))
}
$nl = [string][char]10
$json = '{' + $nl + ($lines -join (',' + $nl)) + $nl + '}' + $nl
[System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding $false))
Write-Host ('[OK] ' + $path + ': ' + $keys.Length + ' keys, ' + $kept + ' of them translated')
