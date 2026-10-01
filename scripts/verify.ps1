#Requires -Version 5.1
[CmdletBinding()]
param(
    [string] $DotNetPath,

    [string] $AnalyzerPath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'M365ScopedMail.Tools.psm1') -Force

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
$cliProject = Join-Path $repositoryRoot 'src\M365ScopedMail.Cli\M365ScopedMail.Cli.csproj'
$testsProject = Join-Path $repositoryRoot 'tests\M365ScopedMail.Core.Tests\M365ScopedMail.Core.Tests.csproj'
$integrationProject = Join-Path $repositoryRoot 'examples\integration\M365ScopedMail.Integration.csproj'
$dotNetExecutable = Resolve-M365ScopedMailDotNet -DotNetPath $DotNetPath

function Invoke-M365ScopedMailCheckedStep {
    param(
        [Parameter(Mandatory = $true)] [string] $Name,
        [Parameter(Mandatory = $true)] [string[]] $Arguments
    )

    $result = Invoke-M365ScopedMailProcess -FilePath $script:dotNetExecutable -WorkingDirectory $script:repositoryRoot -ArgumentList $Arguments
    if ($result.ExitCode -ne 0) {
        if (-not [string]::IsNullOrWhiteSpace($result.StdOut)) { Write-Output $result.StdOut.TrimEnd() }
        if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) { Write-Output $result.StdErr.TrimEnd() }
        throw "$Name failed with exit code $($result.ExitCode)."
    }
    Write-Output "PASS $Name"
}

Invoke-M365ScopedMailCheckedStep -Name 'restore CLI project' -Arguments @('restore', $cliProject, '--configfile', (Join-Path $repositoryRoot 'NuGet.Config'))
Invoke-M365ScopedMailCheckedStep -Name 'restore console test project' -Arguments @('restore', $testsProject, '--configfile', (Join-Path $repositoryRoot 'NuGet.Config'))
Invoke-M365ScopedMailCheckedStep -Name 'restore integration example' -Arguments @('restore', $integrationProject, '--configfile', (Join-Path $repositoryRoot 'NuGet.Config'))
Invoke-M365ScopedMailCheckedStep -Name 'build CLI (Release)' -Arguments @('build', $cliProject, '--configuration', 'Release', '--no-restore')
Invoke-M365ScopedMailCheckedStep -Name 'build console test harness (Release)' -Arguments @('build', $testsProject, '--configuration', 'Release', '--no-restore')
Invoke-M365ScopedMailCheckedStep -Name 'run console test harness' -Arguments @('run', '--no-build', '--no-restore', '--configuration', 'Release', '--project', $testsProject)
Invoke-M365ScopedMailCheckedStep -Name 'build integration example (Release)' -Arguments @('build', $integrationProject, '--configuration', 'Release', '--no-restore')
Invoke-M365ScopedMailCheckedStep -Name 'run integration example' -Arguments @('run', '--no-build', '--no-restore', '--configuration', 'Release', '--project', $integrationProject, '--', $repositoryRoot)

$powershellCommand = Get-Command -Name 'powershell.exe' -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
if ($null -eq $powershellCommand) {
    $powershellCommand = Get-Command -Name 'pwsh.exe', 'pwsh' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
}
if ($null -eq $powershellCommand) {
    throw 'Could not find powershell.exe or pwsh to run tests/run-tests.ps1 in a child process.'
}

$legacyTestPath = Join-Path $repositoryRoot 'tests\run-tests.ps1'
$legacyResult = Invoke-M365ScopedMailProcess -FilePath $powershellCommand.Source -WorkingDirectory $repositoryRoot -ArgumentList @('-NoProfile', '-File', $legacyTestPath)
if ($legacyResult.ExitCode -ne 0) {
    if (-not [string]::IsNullOrWhiteSpace($legacyResult.StdOut)) { Write-Output $legacyResult.StdOut.TrimEnd() }
    if (-not [string]::IsNullOrWhiteSpace($legacyResult.StdErr)) { Write-Output $legacyResult.StdErr.TrimEnd() }
    throw "Existing PowerShell tests failed with exit code $($legacyResult.ExitCode)."
}
if (-not [string]::IsNullOrWhiteSpace($legacyResult.StdOut)) { Write-Output $legacyResult.StdOut.TrimEnd() }
Write-Output 'PASS existing PowerShell tests (child process)'

Invoke-M365ScopedMailCheckedStep -Name 'dotnet format CLI project' -Arguments @('format', 'whitespace', $cliProject, '--verify-no-changes', '--no-restore')
Invoke-M365ScopedMailCheckedStep -Name 'dotnet format console test project' -Arguments @('format', 'whitespace', $testsProject, '--verify-no-changes', '--no-restore')
Invoke-M365ScopedMailCheckedStep -Name 'dotnet format integration example' -Arguments @('format', 'whitespace', $integrationProject, '--verify-no-changes', '--no-restore')

$resolvedAnalyzerPath = $null
if (-not [string]::IsNullOrWhiteSpace($AnalyzerPath)) {
    if (Test-Path -LiteralPath $AnalyzerPath -PathType Leaf) {
        $resolvedAnalyzerPath = (Resolve-Path -LiteralPath $AnalyzerPath -ErrorAction Stop).ProviderPath
    }
    elseif (Test-Path -LiteralPath $AnalyzerPath -PathType Container) {
        $analyzerManifest = Join-Path $AnalyzerPath 'PSScriptAnalyzer.psd1'
        if (Test-Path -LiteralPath $analyzerManifest -PathType Leaf) {
            $resolvedAnalyzerPath = (Resolve-Path -LiteralPath $analyzerManifest -ErrorAction Stop).ProviderPath
        }
        else {
            throw "-AnalyzerPath directory does not contain PSScriptAnalyzer.psd1: $AnalyzerPath"
        }
    }
    else {
        throw "PSScriptAnalyzer path was not found: $AnalyzerPath"
    }
}
else {
    $availableAnalyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer |
        Select-Object -First 1
    if ($null -ne $availableAnalyzer) {
        $resolvedAnalyzerPath = $availableAnalyzer.Path
    }
}

if ($null -eq $resolvedAnalyzerPath) {
    Write-Output 'SKIP PSScriptAnalyzer: not installed and no -AnalyzerPath was supplied.'
}
else {
    Import-Module -Name $resolvedAnalyzerPath -Force -ErrorAction Stop
    $analyzerCommand = Get-Command -Name Invoke-ScriptAnalyzer -ErrorAction Stop
    $analysis = @(& $analyzerCommand -Path $repositoryRoot -Recurse -Severity @('Error', 'Warning'))
    foreach ($finding in $analysis) {
        Write-Output ("{0}: {1}:{2} {3} - {4}" -f $finding.Severity, $finding.ScriptPath, $finding.Line, $finding.RuleName, $finding.Message)
    }
    if ($analysis.Count -gt 0) {
        throw "PSScriptAnalyzer reported $($analysis.Count) error or warning finding(s)."
    }
    Write-Output 'PASS PSScriptAnalyzer (repository scripts)'
}

Write-Output 'Verification completed. All executed checks passed.'
