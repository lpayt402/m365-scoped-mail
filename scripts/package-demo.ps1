#Requires -Version 5.1
[CmdletBinding()]
param([string] $DotNetPath)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'M365ScopedMail.Tools.psm1') -Force
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).ProviderPath
$sdk = Resolve-M365ScopedMailDotNet -DotNetPath $DotNetPath
$project = Join-Path $root 'src\M365ScopedMail.Cli\M365ScopedMail.Cli.csproj'
# A new output folder preserves any earlier package; no recursive cleanup.
$output = Join-Path $root ('artifacts\windows-demo-' + [guid]::NewGuid().ToString('N'))
$restore = Invoke-M365ScopedMailProcess -FilePath $sdk -WorkingDirectory $root -ArgumentList @(
    'restore', $project, '--runtime', 'win-x64', '--configfile', (Join-Path $root 'NuGet.Config'),
    '-p:SelfContained=true', '-p:PublishSingleFile=true'
)
Assert-M365ScopedMailSuccess -ProcessResult $restore -Operation 'Restore Windows runtime packs'
$publish = Invoke-M365ScopedMailProcess -FilePath $sdk -WorkingDirectory $root -ArgumentList @(
    'publish', $project, '--configuration', 'Release', '--runtime', 'win-x64',
    '--self-contained', 'true', '--no-restore', '--output', $output,
    '-p:PublishSingleFile=true', '-p:IncludeNativeLibrariesForSelfExtract=true',
    '-p:EnableCompressionInSingleFile=true', '-p:DebugType=None'
)
Assert-M365ScopedMailSuccess -ProcessResult $publish -Operation 'Publish local mock executable'
foreach ($folder in @('src', 'scripts', 'tests', 'examples', 'docs')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root $folder) -Recurse -File |
        Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' }) {
        $relative = $file.FullName.Substring($root.Length + 1)
        $destination = Join-Path $output $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination
    }
}
foreach ($name in @('README.md', 'PROJECT.md', 'Directory.Build.props', 'global.json', 'NuGet.Config', '.gitignore', '.gitattributes')) {
    Copy-Item -LiteralPath (Join-Path $root $name) -Destination $output
}
foreach ($name in @('LICENSE.txt', 'ThirdPartyNotices.txt')) {
    $notice = Join-Path (Split-Path -Parent $sdk) $name
    if (Test-Path -LiteralPath $notice -PathType Leaf) {
        $notices = Join-Path $output 'runtime-notices'
        New-Item -ItemType Directory -Path $notices -Force | Out-Null
        Copy-Item -LiteralPath $notice -Destination $notices
    }
}
$instructions = @'
M365ScopedMail local Windows x64 mock demo

Open PowerShell in this extracted folder:
  .\scripts\demo.ps1 -ExecutablePath .\m365scopedmail.exe

No SDK, credentials, tenant, or network is needed to run the mock.
The four checks cover acceptance, duplicate suppression and two sender denials.
The runtime is bundled. Rebuild the package for .NET security/runtime updates.
This is a local review artifact, not a production build or public release.
The source repository and its draft PR contain the build/test instructions.
'@
[IO.File]::WriteAllText((Join-Path $output 'START-HERE.txt'), $instructions)
$zip = $output + '.zip'
Compress-Archive -Path (Join-Path $output '*') -DestinationPath $zip
[pscustomobject]@{
    Directory = $output
    Archive = $zip
    Sha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    Mode = 'Mock'
    SecurityModelProven = $false
}
