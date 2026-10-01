#Requires -Version 5.1
Set-StrictMode -Version Latest

function Get-RequiredProperty {
    param([object]$InputObject, [string]$Name)
    if ($null -eq $InputObject -or $null -eq $InputObject.PSObject.Properties[$Name]) {
        throw "Incomplete Exchange response: missing $Name."
    }
    return $InputObject.$Name
}

function ConvertTo-CheckedBoolean {
    param([object]$Value)
    if ($Value -is [bool]) { return $Value }
    if ($Value -is [string] -and $Value -ceq 'True') { return $true }
    if ($Value -is [string] -and $Value -ceq 'False') { return $false }
    throw 'Exchange returned an unknown Boolean result; validation is incomplete.'
}

function Test-GuidMatch {
    param([object]$Value, [guid]$Expected)
    $parsed = [guid]::Empty
    return ([guid]::TryParse([string]$Value, [ref]$parsed) -and $parsed -eq $Expected)
}

function Assert-PrimaryAddress {
    param([string]$Address)
    # Intentionally accept only ordinary primary SMTP addresses in this first increment.
    if ($Address.Length -gt 254 -or $Address -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*@[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,63}$') {
        throw 'Use an ordinary primary SMTP address, without display names, aliases, or wildcards.'
    }
}

function Invoke-ValidationRead {
    param([string]$Operation, [scriptblock]$Read)
    try { & $Read }
    catch {
        # Provider errors may contain tenant data or request headers. Do not echo them.
        throw "Could not read $Operation. Validation is incomplete; check the connection and administrator access."
    }
}

function Invoke-M365ScopedMailValidation {
    <#
    .SYNOPSIS
    Checks one-mailbox Exchange Application RBAC configuration without changing it.
    .DESCRIPTION
    Uses an existing administrator Exchange session. Does not sign in, grant roles,
    acquire application tokens, or send mail. A successful report is partial evidence:
    Entra grant review and real Graph positive/negative send tests remain NotRun.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][guid]$TenantId,
        [Parameter(Mandatory)][guid]$ClientId,
        [Parameter(Mandatory)][guid]$ServicePrincipalObjectId,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ScopeName,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$AuthorizedMailbox,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string[]]$DeniedMailbox
    )

    if ($TenantId -eq [guid]::Empty -or $ClientId -eq [guid]::Empty -or $ServicePrincipalObjectId -eq [guid]::Empty) {
        throw 'Tenant, application/client, and customer service-principal IDs must be non-empty GUIDs.'
    }
    if ($ClientId -eq $ServicePrincipalObjectId) {
        throw 'Use the application/client ID and the distinct customer Enterprise Application object ID.'
    }
    if ([string]::IsNullOrWhiteSpace($ScopeName) -or $ScopeName -match '[\x00-\x1f*?]') {
        throw 'Use an exact, non-empty management scope name without wildcards.'
    }
    Assert-PrimaryAddress $AuthorizedMailbox
    $addresses = @($AuthorizedMailbox) + @($DeniedMailbox)
    $seenAddresses = @{}
    foreach ($address in $addresses) {
        Assert-PrimaryAddress $address
        if ($seenAddresses.ContainsKey($address)) {
            throw 'The approved and denied mailboxes must be distinct primary SMTP addresses.'
        }
        $seenAddresses[$address] = $true
    }

    $requiredCommands = @('Get-ConnectionInformation', 'Get-ServicePrincipal', 'Get-ManagementScope',
        'Get-Recipient', 'Get-Mailbox', 'Test-ServicePrincipalAuthorization')
    foreach ($command in $requiredCommands) {
        if ($null -eq (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "Missing $command. Use an existing unprefixed Exchange Online V3 administrator session."
        }
    }

    $connections = @(Invoke-ValidationRead 'Exchange connection information' {
        Get-ConnectionInformation -ErrorAction Stop
    })
    if ($connections.Count -ne 1) {
        throw 'Use a PowerShell session with exactly one Exchange Online connection.'
    }
    $connection = $connections[0]
    if ((Get-RequiredProperty $connection 'State') -ne 'Connected' -or
        -not (Test-GuidMatch (Get-RequiredProperty $connection 'TenantID') $TenantId) -or
        -not [string]::IsNullOrEmpty([string](Get-RequiredProperty $connection 'ModulePrefix')) -or
        (ConvertTo-CheckedBoolean (Get-RequiredProperty $connection 'IsEopSession'))) {
        throw 'The Exchange connection must be active, unprefixed, and bound to the expected customer tenant.'
    }

    $principals = @(Invoke-ValidationRead 'the Exchange service-principal pointer' {
        Get-ServicePrincipal -Identity $ServicePrincipalObjectId.ToString() -ErrorAction Stop
    })
    if ($principals.Count -ne 1 -or
        -not (Test-GuidMatch (Get-RequiredProperty $principals[0] 'ObjectId') $ServicePrincipalObjectId) -or
        -not (Test-GuidMatch (Get-RequiredProperty $principals[0] 'AppId') $ClientId)) {
        throw 'The Exchange pointer must match both the client ID and the customer Enterprise Application object ID.'
    }

    $scopes = @(Invoke-ValidationRead 'the management scope' {
        Get-ManagementScope -Identity $ScopeName -ErrorAction Stop
    })
    if ($scopes.Count -ne 1 -or (Get-RequiredProperty $scopes[0] 'Name') -ne $ScopeName) {
        throw 'The named management scope was not uniquely resolved.'
    }
    $scope = $scopes[0]
    if (ConvertTo-CheckedBoolean (Get-RequiredProperty $scope 'Exclusive')) {
        throw 'Exclusive management scopes do not restrict Application RBAC access.'
    }
    $filter = [string](Get-RequiredProperty $scope 'RecipientFilter')
    if ([string]::IsNullOrWhiteSpace($filter)) {
        throw 'A non-empty recipient filter is required for the one-mailbox scope.'
    }
    $previewParameters = @{ RecipientPreviewFilter = $filter; ResultSize = 'Unlimited'; ErrorAction = 'Stop' }
    $recipientRoot = Get-RequiredProperty $scope 'RecipientRoot'
    if (-not [string]::IsNullOrWhiteSpace([string]$recipientRoot)) {
        $previewParameters['OrganizationalUnit'] = $recipientRoot
    }
    $scopeRecipients = @(Invoke-ValidationRead 'the complete scope recipient set' {
        Get-Recipient @previewParameters
    })
    # Exchange Online omits Microsoft 365 Groups from the default recipient query.
    # Check them explicitly with the same filter/root so a hidden group cannot make
    # a broader scope look like the approved mailbox is its only recipient.
    $groupPreviewParameters = $previewParameters.Clone()
    $groupPreviewParameters['RecipientTypeDetails'] = 'GroupMailbox'
    $scopeRecipients += @(Invoke-ValidationRead 'the scope Microsoft 365 Groups' {
        Get-Recipient @groupPreviewParameters
    })
    if ($scopeRecipients.Count -ne 1 -or
        [string](Get-RequiredProperty $scopeRecipients[0] 'PrimarySmtpAddress') -ne $AuthorizedMailbox -or
        (Get-RequiredProperty $scopeRecipients[0] 'RecipientTypeDetails') -notin @('UserMailbox', 'SharedMailbox')) {
        throw 'The resource scope must resolve to exactly the approved user or shared mailbox.'
    }

    $mailboxChecks = @()
    $seenMailboxIds = @{}
    foreach ($address in $addresses) {
        $mailboxes = @(Invoke-ValidationRead 'a test mailbox' {
            Get-Mailbox -Identity $address -ErrorAction Stop
        })
        if ($mailboxes.Count -ne 1 -or
            [string](Get-RequiredProperty $mailboxes[0] 'PrimarySmtpAddress') -ne $address) {
            throw 'Each test mailbox must exist and match its primary SMTP address; aliases are not accepted.'
        }
        $mailboxId = [guid]::Empty
        if (-not [guid]::TryParse([string](Get-RequiredProperty $mailboxes[0] 'Guid'), [ref]$mailboxId) -or
            $mailboxId -eq [guid]::Empty -or $seenMailboxIds.ContainsKey($mailboxId.ToString())) {
            throw 'Test mailboxes must resolve to distinct, non-empty Exchange recipient GUIDs.'
        }
        $seenMailboxIds[$mailboxId.ToString()] = $true
        $rows = @(Invoke-ValidationRead 'Exchange authorization test results' {
            Test-ServicePrincipalAuthorization -Identity $ServicePrincipalObjectId.ToString() -Resource $mailboxId.ToString() -ErrorAction Stop
        })
        if ($rows.Count -eq 0) {
            throw 'Exchange returned no authorization rows; validation is incomplete.'
        }
        $inScope = $false
        foreach ($row in $rows) {
            $permissions = @(Get-RequiredProperty $row 'GrantedPermissions')
            if ((Get-RequiredProperty $row 'RoleName') -ne 'Application Mail.Send' -or
                $permissions.Count -ne 1 -or [string]$permissions[0] -ne 'Mail.Send') {
                throw 'Only Application Mail.Send is supported; unexpected application permissions require review.'
            }
            if ((Get-RequiredProperty $row 'ScopeType') -ne 'CustomRecipientScope' -or
                (Get-RequiredProperty $row 'AllowedResourceScope') -ne $ScopeName) {
                throw 'Every role assignment must use the explicitly checked custom recipient scope.'
            }
            $rowInScope = ConvertTo-CheckedBoolean (Get-RequiredProperty $row 'InScope')
            $inScope = $inScope -or $rowInScope
        }
        $expected = $address -eq $AuthorizedMailbox
        if ($inScope -ne $expected) {
            throw 'Exchange authorization did not match the approved/denied mailbox expectations.'
        }
        $mailboxChecks += [pscustomobject]@{ Mailbox = $address; ExpectedInScope = $expected; InScope = $inScope }
    }

    # Deliberately no overall Passed/Active flag: Exchange tests omit Entra grants
    # and bypass the live authorization cache. This is not proof of Graph denial.
    [pscustomobject]@{
        ValidationStatus = 'ExchangeChecksPassed'
        SecurityModelProven = $false
        EntraPermissionReview = 'NotRun'
        GraphSendTests = 'NotRun'
        TenantId = $TenantId.ToString()
        ClientId = $ClientId.ToString()
        ServicePrincipalObjectId = $ServicePrincipalObjectId.ToString()
        ScopeName = $ScopeName
        ScopeRecipientCount = $scopeRecipients.Count
        MailboxChecks = $mailboxChecks
        CheckedAtUtc = [datetime]::UtcNow.ToString('o')
    }
}

Export-ModuleMember -Function Invoke-M365ScopedMailValidation
