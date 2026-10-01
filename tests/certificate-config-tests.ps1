#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$checker = Join-Path $root 'scripts/test-certificate-config.ps1'
$fixture = Get-Content -LiteralPath (Join-Path $root 'examples/certificate-config.example.json') -Raw
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('m365scopedmail-certificate-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$passed = 0

$valid = & $checker -Path (Join-Path $root 'examples/certificate-config.example.json')
if ($valid.ConfigurationSyntax -ne 'Valid' -or $valid.CertificatePresent -ne 'NotChecked' -or
    $valid.PrivateKeyAccessible -ne 'NotChecked' -or $valid.CredentialRegistered -ne 'NotChecked' -or
    $valid.SecurityModelProven -ne $false) { throw 'Valid metadata must preserve all unchecked statuses.' }
$passed++

$invalid = @(
    ($fixture -replace '"schemaVersion":\s*1', '"schemaVersion": []'),
    ($fixture -replace '"authentication":\s*"Certificate"', '"authentication": []'),
    ($fixture -replace '"certificateThumbprint":\s*"A{40}"', '"certificateThumbprint": []'),
    ($fixture -replace '"storeName":\s*"My"', '"storeName": []'),
    ($fixture -replace '"storeLocation":\s*"CurrentUser"', '"storeLocation": []'),
    ($fixture -replace '"schemaVersion":\s*1', '"schemaVersion": "1"'),
    ($fixture -replace '"schemaVersion":\s*1', '"schemaVersion": 1, "schemaVersion": 1'),
    ($fixture -replace '"schemaVersion":\s*1', '"schemaVersion": 1, "\u0073chemaVersion": 1'),
    ($fixture -replace '"schemaVersion":\s*1', '"schemaVersion": 1, "secret": "SYNTHETIC_PRIVATE_MARKER"'),
    ($fixture -replace '11111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000')
)
foreach ($json in $invalid) {
    $path = Join-Path $scratch ([guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($path, $json)
    $rejected = $false
    try { & $checker -Path $path | Out-Null }
    catch {
        $rejected = $true
        if ($_.Exception.Message -match 'SYNTHETIC_PRIVATE_MARKER') { throw 'Checker exposed private input.' }
    }
    if (-not $rejected) { throw 'Malformed metadata was accepted.' }
    $passed++
}
Write-Output "Certificate metadata tests: $passed passed, 0 failed. No credential store was accessed."

foreach ($folder in @('scripts', 'src', 'tests')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $folder) -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.psm1') }) {
        $tokens = $null
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count -ne 0) { throw "PowerShell parse failure: $($file.Name)" }
    }
}
Write-Output 'PASS all source, script and test PowerShell files parse.'
