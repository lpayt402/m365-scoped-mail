# Read-only customer validation

This tool checks an existing Exchange configuration. It does not create an
application, grant permissions, sign in, or send email.

## What you need

Ask the customer's Microsoft 365 administrator for these values:

| Value | Meaning |
| --- | --- |
| TenantId | The customer tenant's directory ID |
| ClientId | The application's application/client ID |
| ServicePrincipalObjectId | Object ID from **Enterprise applications in the customer tenant**, not App registrations |
| ScopeName | The existing Exchange management scope's exact name |
| AuthorizedMailbox | Primary SMTP address of the one approved user or shared mailbox |
| DeniedMailbox | Primary SMTP addresses of one or more existing, unrelated mailboxes |

Use ordinary primary SMTP addresses. Display names, aliases, wildcard scope names,
and unusual address formats are deliberately unsupported in this first increment.
All mailboxes must exist in the same test tenant. A nonexistent mailbox is an
incomplete test, never evidence of successful denial.

The administrator needs an existing unprefixed Exchange Online V3 REST session
(module version 3.0.0 or later) and access to the read/test cmdlets. Use a dedicated
PowerShell window with exactly one connection to the expected tenant. This project
does not install modules, start sign-in, or change administrator access.

## Run the check

The following values are fictional. Replace them with the customer's verified
configuration; they cannot validate a real tenant as written.

```powershell
$validation = @{
    TenantId = '11111111-1111-1111-1111-111111111111'
    ClientId = '22222222-2222-2222-2222-222222222222'
    ServicePrincipalObjectId = '33333333-3333-3333-3333-333333333333'
    ScopeName = 'M365ScopedMail-Acme-Billing'
    AuthorizedMailbox = 'billing@acme.example'
    DeniedMailbox = @('sales@acme.example', 'ceo@acme.example')
}
$report = .\scripts\validate-customer.ps1 @validation
$report | Format-List ValidationStatus, SecurityModelProven, EntraPermissionReview, GraphSendTests
$report.MailboxChecks | Format-Table
```

Expected Exchange-only result:

```text
ValidationStatus      : ExchangeChecksPassed
SecurityModelProven   : False
EntraPermissionReview : NotRun
GraphSendTests        : NotRun

Mailbox                ExpectedInScope InScope
billing@acme.example    True            True
sales@acme.example      False           False
ceo@acme.example        False           False
```

The validator verifies both service-principal IDs and previews the scope with
`Get-Recipient -RecipientPreviewFilter ... -ResultSize Unlimited`. A second query
explicitly includes `GroupMailbox` recipients, which Exchange Online omits from
the default query. Both queries respect a configured recipient root. Exactly one
approved user/shared mailbox must match.
It resolves each test mailbox before using its recipient GUID in the authorization
test. All returned assignments must be `Application Mail.Send` in the checked custom
scope. Additional roles, different scopes, organization-wide grants, unknown Boolean
results, and empty responses stop validation.

## If it stops

- Check that the window has one connected Exchange session for the supplied tenant.
- Check the client ID against the customer's Enterprise Application object ID.
- Check that the named scope contains exactly the approved mailbox.
- Check that every denied mailbox is a different, existing primary address.
- Ask the administrator to inspect extra role assignments and cmdlet access.

Provider errors are replaced with a limited message. The tool does not print raw
responses, request headers, or credentials. It has no automatic retries; fix the
cause and rerun. Repeated checks make no configuration changes.

## Work still required before activation

1. Review the customer's Entra application grants and confirm there is no parallel
   tenant-wide `Mail.Send` grant or unnecessary access. This tool does not inspect Entra.
2. After appropriate propagation time, perform explicitly authorized Graph send
   tests in a test tenant: the approved mailbox must work and unrelated mailboxes
   must be denied. The local mock cannot perform or prove those tests.
3. Record those separate results and the credential review. Do not mark a customer
   active from this report alone.

See [Microsoft's authorization test reference](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/test-serviceprincipalauthorization?view=exchange-ps),
[connection information reference](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-connectioninformation?view=exchange-ps),
[recipient preview reference](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-recipient?view=exchange-ps), and
[service-principal reference](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-serviceprincipal?view=exchange-ps).
