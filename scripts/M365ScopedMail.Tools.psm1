# Shared helpers for the local-only M365ScopedMail demo and verification scripts.
#Requires -Version 5.1

Set-StrictMode -Version 2.0

function Resolve-M365ScopedMailExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    $command = Get-Command -Name $Path -ErrorAction SilentlyContinue
    if ($null -ne $command -and $command.CommandType -eq 'Application') {
        $resolvedPath = $command.Source
    }
    elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).ProviderPath
    }
    else {
        throw "$Description was not found as an executable file: $Path"
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "$Description does not resolve to a file: $resolvedPath"
    }

    return $resolvedPath
}

function Resolve-M365ScopedMailDotNet {
    [CmdletBinding()]
    param(
        [string] $DotNetPath
    )

    if (-not [string]::IsNullOrWhiteSpace($DotNetPath)) {
        return Resolve-M365ScopedMailExecutable -Path $DotNetPath -Description '.NET SDK executable'
    }

    foreach ($candidate in @('dotnet.exe', 'dotnet')) {
        $command = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $command) {
            return Resolve-M365ScopedMailExecutable -Path $command.Source -Description '.NET SDK executable'
        }
    }

    throw 'The .NET SDK executable was not found. Supply -DotNetPath with the full path to dotnet.exe.'
}

function ConvertTo-M365ScopedMailWindowsArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Value
    )

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object System.Text.StringBuilder
    [void] $builder.Append('"')
    $slashes = 0

    for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        if ($character -eq '\') {
            $slashes++
            continue
        }

        if ($character -eq '"') {
            if ($slashes -gt 0) {
                [void] $builder.Append(('\' * (2 * $slashes)))
            }
            [void] $builder.Append('\"')
            $slashes = 0
            continue
        }

        if ($slashes -gt 0) {
            [void] $builder.Append(('\' * $slashes))
            $slashes = 0
        }
        [void] $builder.Append($character)
    }

    if ($slashes -gt 0) {
        [void] $builder.Append(('\' * (2 * $slashes)))
    }
    [void] $builder.Append('"')
    return $builder.ToString()
}

function Invoke-M365ScopedMailProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [string[]] $ArgumentList,

        [Parameter(Mandatory = $true)]
        [string] $WorkingDirectory
    )

    $resolvedFile = Resolve-M365ScopedMailExecutable -Path $FilePath -Description 'Process executable'
    $resolvedWorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory -ErrorAction Stop).ProviderPath
    $quotedArguments = @(
        foreach ($argument in $ArgumentList) {
            ConvertTo-M365ScopedMailWindowsArgument -Value $argument
        }
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $resolvedFile
    $startInfo.Arguments = [string]::Join(' ', $quotedArguments)
    $startInfo.WorkingDirectory = $resolvedWorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    if ([IO.Path]::GetFileNameWithoutExtension($resolvedFile) -ieq 'dotnet') {
        $dotNetCliHome = Join-Path ([IO.Path]::GetTempPath()) 'm365scopedmail-dotnet-cli-home'
        if (-not (Test-Path -LiteralPath $dotNetCliHome -PathType Container)) {
            New-Item -ItemType Directory -Path $dotNetCliHome -Force | Out-Null
        }
        $startInfo.EnvironmentVariables['DOTNET_CLI_HOME'] = $dotNetCliHome
        $startInfo.EnvironmentVariables['APPDATA'] = $dotNetCliHome
        $startInfo.EnvironmentVariables['NUGET_PACKAGES'] = Join-Path $dotNetCliHome 'nuget-packages'
        $startInfo.EnvironmentVariables['DOTNET_SKIP_FIRST_TIME_EXPERIENCE'] = '1'
        $startInfo.EnvironmentVariables['DOTNET_CLI_TELEMETRY_OPTOUT'] = '1'
        $startInfo.EnvironmentVariables['DOTNET_ADD_GLOBAL_TOOLS_TO_PATH'] = '0'
        $startInfo.EnvironmentVariables['DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE'] = '1'
        $startInfo.EnvironmentVariables['DOTNET_NOLOGO'] = '1'
        $startInfo.EnvironmentVariables['DOTNET_GENERATE_ASPNET_CERTIFICATE'] = 'false'
    }

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        if (-not $process.Start()) {
            throw "Could not start executable: $resolvedFile"
        }

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = $stdout
            StdErr   = $stderr
        }
    }
    finally {
        $process.Dispose()
    }
}

function Assert-M365ScopedMailSuccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject] $ProcessResult,

        [Parameter(Mandatory = $true)]
        [string] $Operation
    )

    if ($ProcessResult.ExitCode -ne 0) {
        $details = ($ProcessResult.StdErr -split "`r?`n" | Where-Object { $_ }) -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($details)) {
            $details = ($ProcessResult.StdOut -split "`r?`n" | Where-Object { $_ }) -join [Environment]::NewLine
        }
        if (-not [string]::IsNullOrWhiteSpace($details)) {
            throw "$Operation failed with exit code $($ProcessResult.ExitCode). Output:`n$details"
        }
        throw "$Operation failed with exit code $($ProcessResult.ExitCode)."
    }
}

Export-ModuleMember -Function Resolve-M365ScopedMailExecutable, Resolve-M365ScopedMailDotNet, Invoke-M365ScopedMailProcess, Assert-M365ScopedMailSuccess
