# Minimal dependency-free test harness for Windows PowerShell 5.1 and PowerShell 7.
$script:TestPassed = 0
$script:TestFailed = 0

function Assert-Equal {
    param($Expected, $Actual, [string]$Name)
    $e = [string]$Expected
    $a = [string]$Actual
    if ($e -ceq $a) {
        $script:TestPassed++
        Write-Host "[OK] $Name"
    }
    else {
        $script:TestFailed++
        Write-Host "[X]  $Name"
        Write-Host "       expected: $e"
        Write-Host "       actual:   $a"
    }
}

function Assert-True {
    param($Condition, [string]$Name)
    Assert-Equal 'True' ([string][bool]$Condition) $Name
}

function Complete-Tests {
    param([string]$Suite)
    Write-Host ''
    Write-Host ('{0}: {1} passed, {2} failed' -f $Suite, $script:TestPassed, $script:TestFailed)
    return $script:TestFailed
}
