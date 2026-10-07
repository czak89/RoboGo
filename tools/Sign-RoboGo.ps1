# Signs RoboGo.exe (Authenticode, SHA-256, with a timestamp) and checks the result.
# The certificate never lives in the repository. It comes in through the environment:
#   SIGN_PFX_BASE64     the code-signing certificate with its private key, a .pfx file as Base64
#   SIGN_PFX_PASSWORD   the password of that .pfx
#   SIGN_TIMESTAMP_URL  optional timestamp server; "none" signs without a timestamp
# Without SIGN_PFX_BASE64 nothing is signed and the script ends without an error, so the
# same build works with and without a certificate.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\Sign-RoboGo.ps1 [-Path RoboGo.exe]
param([string]$Path = (Join-Path $PSScriptRoot '..\RoboGo.exe'))
$ErrorActionPreference = 'Stop'

function Write-Note {
    # A plain line, and a warning in the summary of a GitHub Actions run.
    param([string]$Text)
    if ($env:GITHUB_ACTIONS -eq 'true') { Write-Host ('::warning title=Code signing::' + $Text) }
    else { Write-Host ('WARNING: ' + $Text) }
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ('Nothing to sign: ' + $Path + ' does not exist.') }
$file = (Resolve-Path -LiteralPath $Path).Path
if ([string]::IsNullOrEmpty($env:SIGN_PFX_BASE64)) {
    Write-Note 'RoboGo.exe is NOT signed: no certificate was given (SIGN_PFX_BASE64 is empty).'
    exit 0
}

$bytes = [Convert]::FromBase64String(($env:SIGN_PFX_BASE64 -replace '\s', ''))
$certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($bytes, [string]$env:SIGN_PFX_PASSWORD)
try {
    if (-not $certificate.HasPrivateKey) { throw 'The certificate has no private key.' }
    $codeSigning = $false
    foreach ($extension in $certificate.Extensions) {
        if ($extension -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
            foreach ($usage in $extension.EnhancedKeyUsages) {
                if ($usage.Value -eq '1.3.6.1.5.5.7.3.3') { $codeSigning = $true }
            }
        }
    }
    if (-not $codeSigning) { throw 'The certificate is not a code-signing certificate.' }
    if ($certificate.NotAfter -lt (Get-Date)) { throw ('The certificate expired on ' + $certificate.NotAfter.ToString('yyyy-MM-dd') + '.') }
    Write-Host ('Signing with: ' + $certificate.Subject)
    Write-Host ('Thumbprint:   ' + $certificate.Thumbprint + ', valid until ' + $certificate.NotAfter.ToString('yyyy-MM-dd'))

    $timestamp = [string]$env:SIGN_TIMESTAMP_URL
    if ($timestamp.Trim() -eq '') { $timestamp = 'http://timestamp.digicert.com' }
    $arguments = @{ FilePath = $file; Certificate = $certificate; HashAlgorithm = 'SHA256'; IncludeChain = 'NotRoot' }
    if ($timestamp.Trim() -ne 'none') { $arguments['TimestampServer'] = $timestamp.Trim() }
    [void](Set-AuthenticodeSignature @arguments)

    $signature = Get-AuthenticodeSignature -LiteralPath $file
    if (($null -eq $signature.SignerCertificate) -or ($signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint)) {
        throw ('Signing failed: ' + $signature.Status + '. ' + $signature.StatusMessage)
    }
    if (($timestamp.Trim() -ne 'none') -and ($null -eq $signature.TimeStamperCertificate)) { throw 'Signing failed: the signature has no timestamp.' }
    if ($signature.Status -eq 'Valid') { Write-Host 'RoboGo.exe is signed, and Windows trusts the signature.' }
    elseif ($signature.Status -eq 'UnknownError') {
        # signed correctly, but the certificate does not lead to a root this computer trusts
        Write-Note ('RoboGo.exe is signed, but this computer does not trust the certificate: ' + $signature.StatusMessage)
    }
    else { throw ('Signing failed: ' + $signature.Status + '. ' + $signature.StatusMessage) }
}
finally {
    $certificate.Reset()
}
exit 0
