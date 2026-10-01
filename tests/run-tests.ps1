#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$hostPath = (Get-Process -Id $PID -ErrorAction Stop).Path
foreach ($testName in @('synthetic-validation.ps1', 'certificate-config-tests.ps1')) {
    & $hostPath -NoProfile -File (Join-Path $PSScriptRoot $testName)
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
exit 0
