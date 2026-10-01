#Requires -Version 5.1
[CmdletBinding()]
param(
    [string] $DotNetPath,

    [string] $ExecutablePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'M365ScopedMail.Tools.psm1') -Force

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
$cliProject = Join-Path $repositoryRoot 'src\M365ScopedMail.Cli\M365ScopedMail.Cli.csproj'
$configPath = Join-Path $repositoryRoot 'examples\customers.mock.json'
$approvedRequest = Join-Path $repositoryRoot 'examples\basic-send\request.json'
$unauthorizedRequest = Join-Path $repositoryRoot 'examples\negative\unauthorized-sender.json'
$crossCustomerRequest = Join-Path $repositoryRoot 'examples\negative\cross-customer.json'

foreach ($requiredPath in @($configPath, $approvedRequest, $unauthorizedRequest, $crossCustomerRequest)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required demo example was not found: $requiredPath"
    }
}

if (-not [string]::IsNullOrWhiteSpace($ExecutablePath)) {
    if (-not [string]::IsNullOrWhiteSpace($DotNetPath)) {
        throw 'Supply either -ExecutablePath or -DotNetPath, not both.'
    }
    $cliExecutable = Resolve-M365ScopedMailExecutable -Path $ExecutablePath -Description 'Packaged M365ScopedMail CLI executable'
    $cliArguments = @()
}
else {
    $dotNetExecutable = Resolve-M365ScopedMailDotNet -DotNetPath $DotNetPath
    $restoreResult = Invoke-M365ScopedMailProcess -FilePath $dotNetExecutable -WorkingDirectory $repositoryRoot -ArgumentList @(
        'restore', $cliProject, '--configfile', (Join-Path $repositoryRoot 'NuGet.Config')
    )
    if ($restoreResult.ExitCode -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace($restoreResult.StdOut)) { Write-Output $restoreResult.StdOut.TrimEnd() }
        if (-not [string]::IsNullOrWhiteSpace($restoreResult.StdErr)) { Write-Output $restoreResult.StdErr.TrimEnd() }
        throw "Restoring the M365ScopedMail CLI failed with exit code $($restoreResult.ExitCode)."
    }
    $buildResult = Invoke-M365ScopedMailProcess -FilePath $dotNetExecutable -WorkingDirectory $repositoryRoot -ArgumentList @(
        'build', $cliProject, '--configuration', 'Release', '--no-restore'
    )
    if ($buildResult.ExitCode -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace($buildResult.StdOut)) { Write-Output $buildResult.StdOut.TrimEnd() }
        if (-not [string]::IsNullOrWhiteSpace($buildResult.StdErr)) { Write-Output $buildResult.StdErr.TrimEnd() }
        throw "Building the M365ScopedMail CLI failed with exit code $($buildResult.ExitCode)."
    }
    $cliExecutable = $dotNetExecutable
    $cliArguments = @('run', '--no-build', '--no-restore', '--configuration', 'Release', '--project', $cliProject, '--')
}

function Invoke-M365ScopedMailDemoCase {
    param(
        [Parameter(Mandatory = $true)] [string] $Name,
        [Parameter(Mandatory = $true)] [string] $RequestPath,
        [Parameter(Mandatory = $true)] [string] $StatePath,
        [Parameter(Mandatory = $true)] [string[]] $ExpectedStatuses,
        [Parameter(Mandatory = $true)] [bool] $ExpectSuccess
    )

    $arguments = @($cliArguments) + @(
        'simulate', '--config', $configPath, '--request', $RequestPath,
        '--state', $StatePath, '--scenario', 'accepted'
    )
    $result = Invoke-M365ScopedMailProcess -FilePath $cliExecutable -WorkingDirectory $repositoryRoot -ArgumentList $arguments
    $jsonText = $result.StdOut.Trim()
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        throw "Demo case '$Name' did not return its safe JSON result."
    }

    try {
        $response = ConvertFrom-Json -InputObject $jsonText -ErrorAction Stop
    }
    catch {
        throw "Demo case '$Name' returned invalid JSON. The response was not displayed to avoid exposing message data."
    }

    if ($null -eq $response.PSObject.Properties['mode'] -or
        $null -eq $response.PSObject.Properties['status'] -or
        $null -eq $response.PSObject.Properties['securityModelProven']) {
        throw "Demo case '$Name' omitted a required safe result field."
    }
    if ($response.mode -ne 'Mock') {
        throw "Demo case '$Name' returned a non-mock result."
    }
    if ($response.securityModelProven -ne $false) {
        throw "Demo case '$Name' must report securityModelProven=false for this local mock."
    }

    $statusMatches = $ExpectedStatuses -contains [string] $response.status
    if ($ExpectSuccess -and ($result.ExitCode -ne 0 -or -not $statusMatches)) {
        throw "Demo case '$Name' did not complete with an expected success status (exit $($result.ExitCode), status $($response.status))."
    }
    if (-not $ExpectSuccess -and ($result.ExitCode -eq 0 -or -not $statusMatches)) {
        throw "Demo case '$Name' did not fail as expected (exit $($result.ExitCode), status $($response.status))."
    }

    Write-Output ("PASS {0}: {1} (exit {2})" -f $Name, $response.status, $result.ExitCode)
}

$demoState = Join-Path ([IO.Path]::GetTempPath()) ('m365scopedmail-demo-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $demoState -Force | Out-Null
$approvedState = Join-Path $demoState 'approved'
New-Item -ItemType Directory -Path $approvedState -Force | Out-Null

Invoke-M365ScopedMailDemoCase -Name 'approved sender' -RequestPath $approvedRequest -StatePath $approvedState -ExpectedStatuses @('MockAccepted') -ExpectSuccess $true
Invoke-M365ScopedMailDemoCase -Name 'duplicate request' -RequestPath $approvedRequest -StatePath $approvedState -ExpectedStatuses @('DuplicateSuppressed') -ExpectSuccess $true
Invoke-M365ScopedMailDemoCase -Name 'unauthorized sender' -RequestPath $unauthorizedRequest -StatePath (Join-Path $demoState 'unauthorized') -ExpectedStatuses @('Rejected', 'Unauthorized', 'Denied') -ExpectSuccess $false
Invoke-M365ScopedMailDemoCase -Name 'cross-customer sender' -RequestPath $crossCustomerRequest -StatePath (Join-Path $demoState 'cross-customer') -ExpectedStatuses @('Rejected', 'Unauthorized', 'Denied') -ExpectSuccess $false

Write-Output 'All four checks used the local mock sender. No message body or private headers were printed.'
Write-Output 'The demo does not prove Microsoft Graph or Exchange authorization security.'
