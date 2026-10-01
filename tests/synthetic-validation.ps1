[System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Synthetic cmdlet mocks share fixture state only in the isolated test child process.')]
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$script:Passed = 0
$script:Failed = 0
$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:ModulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src/M365ScopedMail.Validation.psm1'

if (-not (Test-Path -LiteralPath $script:ModulePath -PathType Leaf)) {
    throw "Validation module not found: $script:ModulePath"
}
Import-Module -Name $script:ModulePath -Force

$script:TenantId = [guid]'11111111-1111-4111-8111-111111111111'
$script:ClientId = [guid]'22222222-2222-4222-8222-222222222222'
$script:ServicePrincipalObjectId = [guid]'33333333-3333-4333-8333-333333333333'
$script:AuthorizedMailbox = 'billing@acme.example'
$script:DeniedMailbox = @('sales@acme.example', 'ceo@acme.example')
$script:ScopeName = 'M365ScopedMail-TestScope'
$script:MailboxIds = @{
    'billing@acme.example' = [guid]'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    'sales@acme.example' = [guid]'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    'ceo@acme.example' = [guid]'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
}

function Get-SyntheticState {
    [pscustomobject]@{
        TenantId = $script:TenantId
        ClientId = $script:ClientId
        ServicePrincipalObjectId = $script:ServicePrincipalObjectId
        ScopeName = $script:ScopeName
        AuthorizedMailbox = $script:AuthorizedMailbox
        DeniedMailbox = @($script:DeniedMailbox)
        Connection = @([pscustomobject]@{
            State = 'Connected'; TenantID = $script:TenantId; ModulePrefix = ''; IsEopSession = $false
        })
        ServicePrincipal = @([pscustomobject]@{
            AppId = $script:ClientId; ObjectId = $script:ServicePrincipalObjectId
        })
        Scope = @([pscustomobject]@{
            Name = $script:ScopeName
            RecipientFilter = "ExternalDirectoryObjectId -eq '$($script:MailboxIds[$script:AuthorizedMailbox])'"
            RecipientRoot = $null
            Exclusive = $false
        })
        ScopeRecipients = @([pscustomobject]@{
            PrimarySmtpAddress = $script:AuthorizedMailbox; RecipientTypeDetails = 'SharedMailbox'
        })
        GroupScopeRecipients = @()
        Mailboxes = @{
            'billing@acme.example' = @([pscustomobject]@{ PrimarySmtpAddress = 'billing@acme.example'; Guid = $script:MailboxIds['billing@acme.example'] })
            'sales@acme.example' = @([pscustomobject]@{ PrimarySmtpAddress = 'sales@acme.example'; Guid = $script:MailboxIds['sales@acme.example'] })
            'ceo@acme.example' = @([pscustomobject]@{ PrimarySmtpAddress = 'ceo@acme.example'; Guid = $script:MailboxIds['ceo@acme.example'] })
        }
        Authorization = @{
            'billing@acme.example' = @([pscustomobject]@{ RoleName = 'Application Mail.Send'; GrantedPermissions = 'Mail.Send'; AllowedResourceScope = $script:ScopeName; ScopeType = 'CustomRecipientScope'; InScope = $true })
            'sales@acme.example' = @([pscustomobject]@{ RoleName = 'Application Mail.Send'; GrantedPermissions = 'Mail.Send'; AllowedResourceScope = $script:ScopeName; ScopeType = 'CustomRecipientScope'; InScope = $false })
            'ceo@acme.example' = @([pscustomobject]@{ RoleName = 'Application Mail.Send'; GrantedPermissions = 'Mail.Send'; AllowedResourceScope = $script:ScopeName; ScopeType = 'CustomRecipientScope'; InScope = $false })
        }
        Calls = [System.Collections.Generic.List[object]]::new()
        FailCommands = @()
    }
}

$global:M365ScopedMailSyntheticState = Get-SyntheticState

function global:Add-SyntheticCall {
    param([string]$Command, [hashtable]$Arguments)
    $global:M365ScopedMailSyntheticState.Calls.Add([pscustomobject]@{ Command = $Command; Arguments = $Arguments })
    if ($global:M365ScopedMailSyntheticState.FailCommands -contains $Command) {
        throw "SYNTHETIC_READ_FAILURE:$Command"
    }
}

function global:Get-ConnectionInformation {
    [CmdletBinding()]
    param()
    Add-SyntheticCall 'Get-ConnectionInformation' @{}
    return @($global:M365ScopedMailSyntheticState.Connection)
}

function global:Get-ServicePrincipal {
    [CmdletBinding()]
    param([string]$Identity, [string]$ResultSize)
    Add-SyntheticCall 'Get-ServicePrincipal' @{ Identity = $Identity; ResultSize = $ResultSize }
    return @($global:M365ScopedMailSyntheticState.ServicePrincipal)
}

function global:Get-ManagementScope {
    [CmdletBinding()]
    param([string]$Identity, [string]$Name, [string]$ResultSize)
    Add-SyntheticCall 'Get-ManagementScope' @{ Identity = $Identity; Name = $Name; ResultSize = $ResultSize }
    return @($global:M365ScopedMailSyntheticState.Scope)
}

function global:Get-Recipient {
    [CmdletBinding()]
    param([string]$Filter, [string]$RecipientPreviewFilter, [string]$ResultSize, [string]$OrganizationalUnit, [string]$RecipientTypeDetails)
    Add-SyntheticCall 'Get-Recipient' @{ Filter = $Filter; RecipientPreviewFilter = $RecipientPreviewFilter; ResultSize = $ResultSize; OrganizationalUnit = $OrganizationalUnit; RecipientTypeDetails = $RecipientTypeDetails }
    if ($RecipientTypeDetails -eq 'GroupMailbox') {
        return @($global:M365ScopedMailSyntheticState.GroupScopeRecipients)
    }
    return @($global:M365ScopedMailSyntheticState.ScopeRecipients)
}

function global:Get-Mailbox {
    [CmdletBinding()]
    param([string]$Identity, [string]$ResultSize)
    Add-SyntheticCall 'Get-Mailbox' @{ Identity = $Identity; ResultSize = $ResultSize }
    $key = ([string]$Identity).ToLowerInvariant()
    if ($global:M365ScopedMailSyntheticState.Mailboxes.ContainsKey($key)) {
        return @($global:M365ScopedMailSyntheticState.Mailboxes[$key])
    }
    return @()
}

function global:Test-ServicePrincipalAuthorization {
    [CmdletBinding()]
    param([string]$Identity, [string]$Resource, [string]$ResultSize)
    Add-SyntheticCall 'Test-ServicePrincipalAuthorization' @{ Identity = $Identity; Resource = $Resource; ResultSize = $ResultSize }
    foreach ($mailbox in $global:M365ScopedMailSyntheticState.Mailboxes.Keys) {
        foreach ($record in @($global:M365ScopedMailSyntheticState.Mailboxes[$mailbox])) {
            if ([string]$record.Guid -eq [string]$Resource) {
                return @($global:M365ScopedMailSyntheticState.Authorization[$mailbox])
            }
        }
    }
    return @()
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Throw {
    param([scriptblock]$Action, [string]$Because)
    try { & $Action } catch { return $_ }
    throw "Expected validation to fail: $Because"
}

function Invoke-SyntheticValidation {
    Invoke-M365ScopedMailValidation -TenantId $script:TenantId -ClientId $script:ClientId `
        -ServicePrincipalObjectId $script:ServicePrincipalObjectId -ScopeName $script:ScopeName `
        -AuthorizedMailbox $script:AuthorizedMailbox -DeniedMailbox $script:DeniedMailbox
}

function Invoke-TestCase {
    param([string]$Name, [scriptblock]$Body)
    try {
        & $Body
        $script:Passed++
        Write-Output "PASS $Name"
    } catch {
        $script:Failed++
        $script:Failures.Add("$Name - $($_.Exception.Message)")
        Write-Output "FAIL $Name - $($_.Exception.Message)"
    }
}

Invoke-TestCase 'accepts the exact scoped Exchange authorization' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $report = Invoke-SyntheticValidation
    Assert-True ($report.ValidationStatus -eq 'ExchangeChecksPassed') 'status should indicate Exchange checks passed'
    Assert-True ($report.SecurityModelProven -eq $false) 'Exchange checks must not claim the full security model is proven'
    Assert-True ($report.EntraPermissionReview -eq 'NotRun') 'Entra review must remain explicitly unrun'
    Assert-True ($report.GraphSendTests -eq 'NotRun') 'Graph send tests must remain explicitly unrun'
    Assert-True ($report.ScopeRecipientCount -eq 1) 'scope must contain exactly one recipient'
    Assert-True (@($report.MailboxChecks).Count -eq 3) 'must report the approved mailbox and both denials'
    Assert-True (@($report.MailboxChecks | Where-Object { $_.Mailbox -eq $script:AuthorizedMailbox -and $_.ExpectedInScope -and $_.InScope }).Count -eq 1) 'approved mailbox must be in scope'
    Assert-True (@($report.MailboxChecks | Where-Object { $_.Mailbox -in $script:DeniedMailbox -and -not $_.ExpectedInScope -and -not $_.InScope }).Count -eq 2) 'both unrelated mailboxes must be out of scope'
}

Invoke-TestCase 'binds exact identities and requests complete read results' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    [void](Invoke-SyntheticValidation)
    $calls = @($global:M365ScopedMailSyntheticState.Calls)
    $authCalls = @($calls | Where-Object Command -eq 'Test-ServicePrincipalAuthorization')
    Assert-True ($authCalls.Count -eq 3) 'must check authorization once for each mailbox'
    foreach ($call in $authCalls) {
        Assert-True ($call.Arguments.Identity -eq [string]$script:ServicePrincipalObjectId) 'authorization identity must be the tenant service principal object id'
        Assert-True ($call.Arguments.Resource -in @($script:MailboxIds.Values | ForEach-Object { [string]$_ })) 'authorization resource must be a resolved mailbox GUID'
    }
    $recipientCall = @($calls | Where-Object Command -eq 'Get-Recipient')
    Assert-True ($recipientCall.Count -eq 2) 'scope should be previewed for mailboxes and groups'
    foreach ($preview in $recipientCall) {
        Assert-True ($preview.Arguments.ResultSize -eq 'Unlimited') 'scope recipient query must request ResultSize Unlimited'
        Assert-True ($preview.Arguments.RecipientPreviewFilter -eq $global:M365ScopedMailSyntheticState.Scope[0].RecipientFilter) 'scope recipient query must use the filter returned by the exact named scope'
    }
    Assert-True (@($recipientCall | Where-Object { $_.Arguments.RecipientTypeDetails -eq 'GroupMailbox' }).Count -eq 1) 'the second preview must explicitly select Microsoft 365 groups'
}

Invoke-TestCase 'rejects mismatched tenant, client, and service principal object identifiers' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Connection[0].TenantID = [guid]'99999999-9999-4999-8999-999999999999'
    [void](Assert-Throw { Invoke-SyntheticValidation } 'wrong tenant')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.ServicePrincipal[0].AppId = [guid]'99999999-9999-4999-8999-999999999999'
    [void](Assert-Throw { Invoke-SyntheticValidation } 'wrong client id')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.ServicePrincipal[0].ObjectId = [guid]'99999999-9999-4999-8999-999999999999'
    [void](Assert-Throw { Invoke-SyntheticValidation } 'wrong object id')
}

Invoke-TestCase 'rejects missing, duplicate, and unknown session or directory results' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Connection = @()
    [void](Assert-Throw { Invoke-SyntheticValidation } 'missing session')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Connection += $global:M365ScopedMailSyntheticState.Connection[0]
    [void](Assert-Throw { Invoke-SyntheticValidation } 'duplicate session')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Connection[0].ModulePrefix = 'EXO'
    [void](Assert-Throw { Invoke-SyntheticValidation } 'prefixed session')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Connection[0].IsEopSession = $true
    [void](Assert-Throw { Invoke-SyntheticValidation } 'EOP session')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.ServicePrincipal = @()
    [void](Assert-Throw { Invoke-SyntheticValidation } 'missing service principal')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Scope = @($global:M365ScopedMailSyntheticState.Scope[0], $global:M365ScopedMailSyntheticState.Scope[0])
    [void](Assert-Throw { Invoke-SyntheticValidation } 'duplicate scope')
}

Invoke-TestCase 'rejects aliases and duplicate or unknown scope recipients' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.ScopeRecipients[0].PrimarySmtpAddress = 'billing-alias@acme.example'
    [void](Assert-Throw { Invoke-SyntheticValidation } 'scope contains an alias instead of exact primary SMTP')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.ScopeRecipients += $global:M365ScopedMailSyntheticState.ScopeRecipients[0]
    [void](Assert-Throw { Invoke-SyntheticValidation } 'duplicate scope recipient')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.ScopeRecipients += [pscustomobject]@{ PrimarySmtpAddress = 'other@acme.example'; RecipientTypeDetails = 'UserMailbox' }
    [void](Assert-Throw { Invoke-SyntheticValidation } 'extra scope recipient')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.ScopeRecipients = @()
    [void](Assert-Throw { Invoke-SyntheticValidation } 'empty scope')
}

Invoke-TestCase 'rejects duplicate authorized and denied input addresses' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    [void](Assert-Throw {
        Invoke-M365ScopedMailValidation -TenantId $script:TenantId -ClientId $script:ClientId `
            -ServicePrincipalObjectId $script:ServicePrincipalObjectId -ScopeName $script:ScopeName `
            -AuthorizedMailbox $script:AuthorizedMailbox -DeniedMailbox @($script:AuthorizedMailbox, $script:DeniedMailbox[0])
    } 'authorized mailbox repeated as a denial target')
}

Invoke-TestCase 'rejects organization-wide scope and altered scope filter' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Scope[0].RecipientFilter = 'RecipientTypeDetails -eq ''UserMailbox'''
    $global:M365ScopedMailSyntheticState.ScopeRecipients += [pscustomobject]@{ PrimarySmtpAddress = 'sales@acme.example'; RecipientTypeDetails = 'UserMailbox' }
    [void](Assert-Throw { Invoke-SyntheticValidation } 'unexpected broad filter')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Scope[0].RecipientRoot = 'OU=Senders,DC=acme,DC=example'
    $rootedReport = Invoke-SyntheticValidation
    Assert-True ($rootedReport.ValidationStatus -eq 'ExchangeChecksPassed') 'a rooted scope should pass when both complete previews are exact'
    $rootedCalls = @($global:M365ScopedMailSyntheticState.Calls | Where-Object Command -eq 'Get-Recipient')
    Assert-True ($rootedCalls.Count -eq 2) 'both rooted scope previews should run'
    foreach ($preview in $rootedCalls) {
        Assert-True ($preview.Arguments.OrganizationalUnit -eq 'OU=Senders,DC=acme,DC=example') 'both previews must preserve RecipientRoot'
        Assert-True ($preview.Arguments.ResultSize -eq 'Unlimited') 'both rooted previews must be complete'
    }
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Scope[0].Exclusive = $true
    [void](Assert-Throw { Invoke-SyntheticValidation } 'exclusive scope')
}

Invoke-TestCase 'rejects a hidden Microsoft 365 group in the recipient scope' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.GroupScopeRecipients = @([pscustomobject]@{
        PrimarySmtpAddress = 'billing-group@acme.example'; RecipientTypeDetails = 'GroupMailbox'
    })
    [void](Assert-Throw { Invoke-SyntheticValidation } 'group returned by the dedicated GroupMailbox scope preview')
    $groupCall = @($global:M365ScopedMailSyntheticState.Calls | Where-Object {
        $_.Command -eq 'Get-Recipient' -and $_.Arguments.RecipientTypeDetails -eq 'GroupMailbox'
    })
    Assert-True ($groupCall.Count -eq 1) 'the hidden Microsoft 365 group preview must run before validation fails'
}

Invoke-TestCase 'rejects mailbox lookup ambiguity and unknown mailbox identity' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Mailboxes['billing@acme.example'] += $global:M365ScopedMailSyntheticState.Mailboxes['billing@acme.example'][0]
    [void](Assert-Throw { Invoke-SyntheticValidation } 'duplicate mailbox lookup')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Mailboxes['billing@acme.example'][0].PrimarySmtpAddress = 'billing-alias@acme.example'
    [void](Assert-Throw { Invoke-SyntheticValidation } 'mailbox identity resolves to alias')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Mailboxes['ceo@acme.example'] = @()
    [void](Assert-Throw { Invoke-SyntheticValidation } 'unknown denied mailbox')
}

Invoke-TestCase 'rejects incorrect positive and any positive negative authorization row' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Authorization['billing@acme.example'][0].InScope = $false
    [void](Assert-Throw { Invoke-SyntheticValidation } 'approved mailbox denied')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Authorization['sales@acme.example'][0].InScope = $true
    [void](Assert-Throw { Invoke-SyntheticValidation } 'sales unexpectedly allowed')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Authorization['ceo@acme.example'] += [pscustomobject]@{ RoleName = 'Application Mail.Send'; GrantedPermissions = 'Mail.Send'; AllowedResourceScope = $script:ScopeName; ScopeType = 'CustomRecipientScope'; InScope = $true }
    [void](Assert-Throw { Invoke-SyntheticValidation } 'one positive row among duplicate negative-mailbox assignments')
}

Invoke-TestCase 'accepts duplicate same-scope assignments when all expected results agree' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Authorization['billing@acme.example'] += [pscustomobject]@{ RoleName = 'Application Mail.Send'; GrantedPermissions = 'Mail.Send'; AllowedResourceScope = $script:ScopeName; ScopeType = 'CustomRecipientScope'; InScope = 'True' }
    $global:M365ScopedMailSyntheticState.Authorization['sales@acme.example'] += [pscustomobject]@{ RoleName = 'Application Mail.Send'; GrantedPermissions = 'Mail.Send'; AllowedResourceScope = $script:ScopeName; ScopeType = 'CustomRecipientScope'; InScope = 'False' }
    $report = Invoke-SyntheticValidation
    Assert-True ($report.ValidationStatus -eq 'ExchangeChecksPassed') 'consistent duplicate assignments should be evaluated successfully'
}

Invoke-TestCase 'rejects organization-wide or differently scoped authorization rows' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Authorization['billing@acme.example'][0].ScopeType = 'Organization'
    [void](Assert-Throw { Invoke-SyntheticValidation } 'organization-wide authorization row')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Authorization['sales@acme.example'][0].AllowedResourceScope = 'OtherScope'
    [void](Assert-Throw { Invoke-SyntheticValidation } 'authorization row bound to another scope')
}

Invoke-TestCase 'rejects unknown authorization state and unexpected role or permission' {
    foreach ($unknown in @($null, 'Not Run', 'Unknown', '')) {
        $global:M365ScopedMailSyntheticState = Get-SyntheticState
        $global:M365ScopedMailSyntheticState.Authorization['billing@acme.example'][0].InScope = $unknown
        [void](Assert-Throw { Invoke-SyntheticValidation } "unknown InScope state '$unknown'")
    }
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Authorization['billing@acme.example'][0].RoleName = 'Application Mail.Read'
    [void](Assert-Throw { Invoke-SyntheticValidation } 'unexpected role')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.Authorization['billing@acme.example'][0].GrantedPermissions = 'Mail.Send, Mail.Read'
    [void](Assert-Throw { Invoke-SyntheticValidation } 'unexpected permission')
}

Invoke-TestCase 'accepts only explicit True and False Boolean or string authorization states' {
    foreach ($trueValue in @($true, 'True')) {
        $global:M365ScopedMailSyntheticState = Get-SyntheticState
        $global:M365ScopedMailSyntheticState.Authorization['billing@acme.example'][0].InScope = $trueValue
        $global:M365ScopedMailSyntheticState.Authorization['sales@acme.example'][0].InScope = 'False'
        $global:M365ScopedMailSyntheticState.Authorization['ceo@acme.example'][0].InScope = $false
        $report = Invoke-SyntheticValidation
        Assert-True ($report.ValidationStatus -eq 'ExchangeChecksPassed') "explicit state $trueValue should pass"
    }
}

Invoke-TestCase 'fails closed with sanitized errors when any Exchange read fails' {
    foreach ($cmd in @('Get-ConnectionInformation','Get-ServicePrincipal','Get-ManagementScope','Get-Recipient','Get-Mailbox','Test-ServicePrincipalAuthorization')) {
        $global:M365ScopedMailSyntheticState = Get-SyntheticState
        $global:M365ScopedMailSyntheticState.FailCommands = @($cmd)
        $errorRecord = Assert-Throw { Invoke-SyntheticValidation } "$cmd read failure"
        Assert-True ($errorRecord.Exception.Message -notmatch 'SYNTHETIC_READ_FAILURE|billing@acme\.example|11111111') "error should be sanitized for $cmd"
    }
}

Invoke-TestCase 'does not call mutation, Graph send, or general HTTP commands' {
    $scriptPaths = @($script:ModulePath, (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/validate-customer.ps1'))
    $commands = @()
    foreach ($path in $scriptPaths) {
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        Assert-True (@($parseErrors).Count -eq 0) "$([IO.Path]::GetFileName($path)) must parse without errors"
        $commands += @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
    }
    $forbidden = @('Connect-ExchangeOnline','Connect-MgGraph','New-PSSession','New-ServicePrincipal','New-ManagementScope','New-ManagementRoleAssignment','Set-ManagementScope','Set-ManagementRoleAssignment','Remove-ServicePrincipal','Remove-ManagementScope','Remove-ManagementRoleAssignment','Send-MgUserMail','Invoke-MgGraphRequest','Invoke-RestMethod','Invoke-WebRequest')
    foreach ($name in $forbidden) {
        Assert-True ($commands -notcontains $name) "module must not invoke $name"
    }
}

Invoke-TestCase 'validation wrapper exits nonzero when Exchange reads are unavailable' {
    $wrapperPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/validate-customer.ps1'
    $hostPath = (Get-Process -Id $PID).Path
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $hostPath -NoProfile -File $wrapperPath `
            -TenantId '11111111-1111-4111-8111-111111111111' `
            -ClientId '22222222-2222-4222-8222-222222222222' `
            -ServicePrincipalObjectId '33333333-3333-4333-8333-333333333333' `
            -ScopeName 'M365ScopedMail-TestScope' -AuthorizedMailbox 'billing@acme.example' `
            -DeniedMailbox 'sales@acme.example' 2>&1
        $wrapperExitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedPreference
    }
    Assert-True ($wrapperExitCode -ne 0) 'wrapper process must fail when Exchange reads cannot be performed'
    Assert-True ((@($output) -join "`n") -match 'Missing Get-ConnectionInformation|Could not read') 'failure should explain validation is incomplete'
}

Invoke-TestCase 'repeated validation is stable and a failed read does not poison later validation' {
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $first = Invoke-SyntheticValidation
    $second = Invoke-SyntheticValidation
    Assert-True ($first.ValidationStatus -eq $second.ValidationStatus) 'repeated status should be stable'
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $global:M365ScopedMailSyntheticState.FailCommands = @('Get-Recipient')
    [void](Assert-Throw { Invoke-SyntheticValidation } 'first read should fail')
    $global:M365ScopedMailSyntheticState = Get-SyntheticState
    $recovered = Invoke-SyntheticValidation
    Assert-True ($recovered.ValidationStatus -eq 'ExchangeChecksPassed') 'a fresh successful read should recover after failure'
}

Write-Output "`nSynthetic validation tests: $script:Passed passed, $script:Failed failed."
if ($script:Failed -gt 0) {
    foreach ($failure in $script:Failures) { Write-Output "  $failure" }
    exit 1
}
exit 0
