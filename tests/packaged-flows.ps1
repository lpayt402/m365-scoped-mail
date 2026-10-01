[CmdletBinding()]
param([Parameter(Mandatory)][string]$PackagePath)
$ErrorActionPreference = 'Stop'
$package = (Resolve-Path -LiteralPath $PackagePath).ProviderPath
Import-Module (Join-Path $package 'scripts/M365ScopedMail.Tools.psm1') -Force
$executable = Join-Path $package 'm365scopedmail.exe'
$config = Join-Path $package 'examples/customers.mock.json'
$request = Join-Path $package 'examples/basic-send/request.json'
$scratch = Join-Path $env:TEMP ('m365scopedmail packaged checks ' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$script:Count = 0
function Invoke-Case {
    param([string]$Name, [string]$State, [string]$Scenario, [string]$Expected,
        [string]$Category, [string]$RequestPath = $request, [string]$ConfigPath = $config)
    $process = Invoke-M365ScopedMailProcess -FilePath $executable -WorkingDirectory $package -ArgumentList @(
        'simulate','--config',$ConfigPath,'--request',$RequestPath,'--state',$State,'--scenario',$Scenario)
    $result = $process.StdOut.Trim() | ConvertFrom-Json
    $expectedExit = if ($Expected -in @('MockAccepted','DuplicateSuppressed')) { 0 } else { 2 }
    if ($process.ExitCode -ne $expectedExit -or $result.mode -ne 'Mock' -or
        $result.securityModelProven -ne $false -or $result.status -ne $Expected -or
        ($Category -and $result.errorCategory -ne $Category) -or $process.StdErr.Trim()) {
        throw "Packaged case failed: $Name"
    }
    if ($process.StdOut -match 'receiving@acme.example|Sample invoice|fictional M365ScopedMail demo|contentBase64|synthetic-token') {
        throw "Packaged output leaked content: $Name"
    }
    # PowerShell 7 converts JSON dates to local DateTime; validate the wire value.
    $wireTime = [regex]::Match($process.StdOut, '"timestampUtc":"([^"]+)"').Groups[1].Value
    if (-not $wireTime -or [datetimeoffset]::Parse($wireTime).Offset -ne [timespan]::Zero) { throw 'Expected UTC timestamp.' }
    $script:Count++
    Write-Verbose "PASS $Name" -Verbose
    return $result
}
$invoice = Join-Path $package 'examples/invoice-send/request.json'
$invoiceState = Join-Path $scratch 'invoice'
$first = Invoke-Case 'PDF acceptance' $invoiceState accepted MockAccepted -RequestPath $invoice
$again = Invoke-Case 'PDF duplicate' $invoiceState accepted DuplicateSuppressed -RequestPath $invoice
if ($first.eventId -ne $again.eventId) { throw 'PDF duplicate changed event ID.' }
$tokenState = Join-Path $scratch 'token recovery'
$failed = Invoke-Case 'token failure' $tokenState token-failure Rejected TokenFailure
$recovered = Invoke-Case 'token recovery across processes' $tokenState accepted MockAccepted
if ($failed.eventId -ne $recovered.eventId) { throw 'Token recovery changed event ID.' }
$null = Invoke-Case 'recovered duplicate' $tokenState accepted DuplicateSuppressed
$uncertainState = Join-Path $scratch 'uncertain'
$null = Invoke-Case 'ambiguous submission' $uncertainState uncertain Uncertain ManualReviewRequired
$stopped = Invoke-Case 'ambiguous repeat stops' $uncertainState accepted Uncertain ManualReviewRequired
if ($stopped.attempts -ne 0) { throw 'Ambiguous repeat attempted transport.' }
$throttleState = Join-Path $scratch 'throttle'
$throttled = Invoke-Case 'bounded throttle retry' $throttleState throttle-once MockAccepted
if ($throttled.attempts -ne 2) { throw 'Expected exactly two throttle attempts.' }
$null = Invoke-Case 'throttle replay' $throttleState accepted DuplicateSuppressed
$changed = Get-Content -LiteralPath $request -Raw | ConvertFrom-Json
$changed.subject = 'Changed synthetic subject'
$changedPath = Join-Path $scratch 'changed.json'
$changed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $changedPath -Encoding UTF8
$null = Invoke-Case 'changed payload rejected' $tokenState accepted Rejected IdempotencyConflict -RequestPath $changedPath
$corruptState = Join-Path $scratch 'corrupt'
New-Item -ItemType Directory -Path $corruptState | Out-Null
[IO.File]::WriteAllText((Join-Path $corruptState 'state.json'), '{bad json')
$null = Invoke-Case 'corrupt state stops' $corruptState accepted Rejected StateUnavailable
$lockedState = Join-Path $scratch 'locked'
New-Item -ItemType Directory -Path $lockedState | Out-Null
$lock = [IO.File]::Open((Join-Path $lockedState 'state.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try { $null = Invoke-Case 'concurrent file lock stops' $lockedState accepted Rejected StateUnavailable }
finally { $lock.Dispose() }
$null = Invoke-Case 'lock release recovery' $lockedState accepted MockAccepted
$authState = Join-Path $scratch 'authorization circuit'
foreach ($number in 1..3) {
    $newRequest = Get-Content -LiteralPath $request -Raw | ConvertFrom-Json
    $newRequest.idempotencyKey = "mock-auth-$number"
    $newPath = Join-Path $scratch "auth-$number.json"
    $newRequest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $newPath -Encoding UTF8
    $category = if ($number -eq 3) { 'CircuitOpen' } else { 'AuthorizationDenied' }
    $result = Invoke-Case "authorization circuit step $number" $authState authorization-denied Rejected $category -RequestPath $newPath
    if ($number -eq 3 -and $result.attempts -ne 0) { throw 'Open circuit attempted transport.' }
}
$unknownPath = Join-Path $scratch 'unknown-property.json'
[IO.File]::WriteAllText($unknownPath, ((Get-Content -LiteralPath $request -Raw) -replace '"customer":', '"tenantId":"11111111-1111-4111-8111-111111111111","customer":'))
$null = Invoke-Case 'caller tenant property rejected' (Join-Path $scratch 'unknown') accepted Rejected InvalidJson -RequestPath $unknownPath
Write-Output "Packaged CLI checks: $script:Count passed, 0 failed; each call used a separate process."
