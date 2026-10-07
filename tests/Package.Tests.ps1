# Tests for the single-file RoboGo.exe: build it, copy it alone into an empty folder and let
# it check itself there. Nothing is shown on screen.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$exe = Join-Path $root 'RoboGo.exe'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('RoboGoPackTest-' + [guid]::NewGuid().ToString('N'))
$alone = Join-Path $work 'app'
New-Item -ItemType Directory -Force -Path $alone | Out-Null
# The exe must never find the real settings or the real Send to folder.
$env:ROBOGO_HOME = $null
$env:ROBOGO_EXE = $null
$env:ROBOGO_SOURCE = $null
$env:ROBOGO_SENDTO = Join-Path $work 'sendto'

function Get-Sha256 {
    param([string]$Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return [System.BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($Path))) }
    finally { $sha.Dispose() }
}

function Invoke-Exe {
    # Runs a windowless exe, waits for it, and returns its exit code and what it printed.
    param([string]$Path, [string]$Arguments)
    $out = Join-Path $work ('out-' + [guid]::NewGuid().ToString('N') + '.txt')
    $err = $out + '.err'
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -WorkingDirectory ([System.IO.Path]::GetDirectoryName($Path)) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    return @{ Code = $process.ExitCode; Text = ([System.IO.File]::ReadAllText($out) + [System.IO.File]::ReadAllText($err)) }
}

try {
    # --- build ---
    $build = Start-Process -FilePath $env:ComSpec -ArgumentList ('/c ""' + (Join-Path $root 'build.cmd') + '" /q"') -WorkingDirectory $root -WindowStyle Hidden -Wait -PassThru
    Assert-Equal 0 $build.ExitCode 'build: build.cmd succeeds'
    Assert-True (Test-Path -LiteralPath $exe -PathType Leaf) 'build: RoboGo.exe is there'
    $source = [System.IO.File]::ReadAllText((Join-Path $root 'RoboGo.ps1'))
    $version = [regex]::Match($source, "RoboGoVersion = '(\d+\.\d+\.\d+)'").Groups[1].Value
    Assert-True ($version -ne '') 'build: the app has a version'
    Assert-Equal ($version + '.0') ([System.Diagnostics.FileVersionInfo]::GetVersionInfo($exe).FileVersion) 'build: the exe carries the version of the app'
    Assert-True ((Get-Item -LiteralPath $exe).Length -lt 2MB) 'build: the exe stays small'

    # --- in the folder of the repository the script next to the exe is the one that runs ---
    $run = Invoke-Exe $exe '/selftest'
    Assert-Equal 0 $run.Code 'in its folder: the self-test passes'
    Assert-True ($run.Text -match [regex]::Escape('app folder:  ' + $root)) 'in its folder: the app runs from the folder of the exe'

    # --- alone in an empty folder ---
    $lonely = Join-Path $alone 'RoboGo.exe'
    Copy-Item -LiteralPath $exe -Destination $lonely
    $run = Invoke-Exe $lonely '/selftest'
    Assert-Equal 0 $run.Code 'alone: the self-test passes'
    Assert-True ($run.Text -match ('RoboGo ' + [regex]::Escape($version) + ' self-test: all good')) 'alone: it is this version, and every check is good'
    # TEMP can be spelled in two ways (short and long names), so folders are told by their ends
    $unpacked = [regex]::Match($run.Text, 'app folder:  (.+)').Groups[1].Value.Trim()
    $tail = '\' + (Split-Path $work -Leaf) + '\app'
    Assert-True ($unpacked -match '\\RoboGo\\app-[0-9a-f]{12}$') 'alone: the app is unpacked below TEMP\RoboGo'
    Assert-True ([regex]::Match($run.Text, 'data folder: (.+)').Groups[1].Value.Trim().EndsWith($tail, [System.StringComparison]::OrdinalIgnoreCase)) 'alone: settings and logs belong next to the exe'
    Assert-True ([regex]::Match($run.Text, 'launcher:    (.+)').Groups[1].Value.Trim().EndsWith(($tail + '\RoboGo.exe'), [System.StringComparison]::OrdinalIgnoreCase)) 'alone: the exe is what starts the app'
    Assert-True ($run.Text -match 'languages:   en, .*pl') 'alone: the languages came along'
    $same = $false
    if (($unpacked -ne '') -and (Test-Path -LiteralPath (Join-Path $unpacked 'RoboGo.ps1'))) {
        $same = ((Get-Sha256 (Join-Path $unpacked 'RoboGo.ps1')) -eq (Get-Sha256 (Join-Path $root 'RoboGo.ps1')))
    }
    Assert-True $same 'alone: the unpacked script is the one of the repository, byte for byte'
    Assert-True (Test-Path -LiteralPath (Join-Path $unpacked 'RoboGo.ico')) 'alone: the icon is unpacked'
    Assert-True (Test-Path -LiteralPath (Join-Path $unpacked 'lang\pl.json')) 'alone: the Polish texts are unpacked'
    Assert-Equal 'RoboGo.exe' ((Get-ChildItem -LiteralPath $alone -Force | ForEach-Object { $_.Name }) -join ',') 'alone: a self-test leaves nothing next to the exe'

    # --- a changed or missing unpacked file is put right at the next start ---
    if ($same) {
        [System.IO.File]::WriteAllText((Join-Path $unpacked 'RoboGo.ps1'), 'exit 7')
        Remove-Item -LiteralPath (Join-Path $unpacked 'lang\pl.json') -Force
        $run = Invoke-Exe $lonely '/selftest'
        Assert-Equal 0 $run.Code 'repair: a tampered script is replaced by the one inside the exe'
        Assert-True (Test-Path -LiteralPath (Join-Path $unpacked 'lang\pl.json')) 'repair: a deleted file comes back'
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
exit (Complete-Tests 'Package')
