#Requires -Version 5.1
<#
.SYNOPSIS
Checks certificate configuration syntax without inspecting a store or signing in.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try {
    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer -or $item.Length -gt 16384) { throw 'Invalid configuration file.' }
    $json = Get-Content -LiteralPath $item.FullName -Raw -ErrorAction Stop
    # The supported metadata needs no escapes. Reject them so encoded duplicate
    # property names cannot hide from the literal-field duplicate check below.
    if ($json.Contains('\')) { throw 'Escaped certificate metadata is unsupported.' }
    $config = $json | ConvertFrom-Json -ErrorAction Stop
    $expected = @('schemaVersion','authentication','homeTenantId','clientId','certificateThumbprint','storeName','storeLocation')
    $actual = @($config.PSObject.Properties.Name)
    if ($actual.Count -ne $expected.Count -or @($actual | Where-Object { $_ -cnotin $expected }).Count -gt 0) {
        throw 'Unexpected or missing configuration field.'
    }
    # Only these literal scalar fields are supported. Counting them also rejects
    # duplicate properties that Windows PowerShell's JSON reader would overwrite.
    $fieldPattern = '(?<!\\)"(?:schemaVersion|authentication|homeTenantId|clientId|certificateThumbprint|storeName|storeLocation)"\s*:'
    if ([regex]::Matches($json, $fieldPattern).Count -ne 7 -or
        ($config.schemaVersion -isnot [int] -and $config.schemaVersion -isnot [long])) {
        throw 'Invalid configuration structure.'
    }
    foreach ($name in @('authentication','homeTenantId','clientId','certificateThumbprint','storeName','storeLocation')) {
        if ($config.$name -isnot [string]) { throw 'Expected scalar string metadata.' }
    }
    if ($config.schemaVersion -ne 1 -or $config.authentication -cne 'Certificate' -or
        $config.storeName -cne 'My' -or $config.storeLocation -cne 'CurrentUser' -or
        $config.certificateThumbprint -cnotmatch '^[A-Fa-f0-9]{40}$') { throw 'Invalid certificate metadata.' }
    foreach ($identifier in @($config.homeTenantId, $config.clientId)) {
        $parsed = [guid]::Empty
        if (-not [guid]::TryParseExact($identifier, 'D', [ref]$parsed) -or $parsed -eq [guid]::Empty) {
            throw 'Invalid identifier.'
        }
    }
} catch {
    throw 'Certificate configuration syntax is invalid or unavailable. Use the documented metadata fields; do not include keys, tokens, passwords, or secrets.'
}

[pscustomobject]@{
    ConfigurationSyntax = 'Valid'
    CertificatePresent = 'NotChecked'
    PrivateKeyAccessible = 'NotChecked'
    CredentialRegistered = 'NotChecked'
    SecurityModelProven = $false
}
