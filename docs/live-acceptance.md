# Live acceptance: not run

The local demo is ready for review. It does not establish that Microsoft 365 will
allow the approved mailbox and deny every other mailbox. I want that evidence
before adding a live sending path or marking a customer active.

This is a checklist for a later, explicitly approved test. Nothing here has been
provisioned, granted, connected, or sent. Keep customer administration in a
dedicated window and use a dedicated test application, existing test tenants,
controlled recipients, and synthetic message content.

## Inputs and people

| Needed | Why |
| --- | --- |
| Home tenant and a separate customer test tenant | Prove external multitenant provisioning, not merely same-tenant behavior |
| Second customer context for cross-tenant proof | Confirm one customer cannot select another customer's tenant/mailbox |
| Home application administrator | Register a dedicated multitenant test app and its public certificate |
| Customer Cloud/Application Administrator | Provision that app's customer service principal |
| Customer Exchange administrator with role-assignment rights | Create the Exchange pointer, exact recipient scope and `Application Mail.Send` assignment |
| One approved mailbox, two unrelated existing mailboxes and a controlled inbox | Exercise successful sending and meaningful denial |
| Agreed owner, short credential lifetime and cleanup window | Limit the test's duration and verify revocation |

App registration/client ID and the customer's Enterprise Application object ID
are different identifiers. Verify both; Exchange's service-principal pointer must
use the customer object ID. Microsoft’s [application/service principal model](https://learn.microsoft.com/en-us/entra/identity-platform/app-objects-and-service-principals)
and [Exchange Application RBAC guidance](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)
explain the relationship.

For direct customer service-principal creation, Microsoft's Graph operation uses
the app's `appId`; delegated `Application.ReadWrite.All` is the administration
tool's permission, with the documented customer administrator role. It is not a
permission to add to the sender. Provisioning need not grant tenant-wide
`Mail.Send`. [Create servicePrincipal reference](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-post-serviceprincipals?view=graph-rest-1.0)

## Proposed test sequence

1. Review and approve the exact tenants, app, controlled recipients, commands,
   temporary certificate plan and cleanup before making any live change. Use an
   explicit customer tenant authority for app-only tokens, rather than `common`.
   No private key should leave the Windows store; only the public certificate
   would be registered. See the [MSAL certificate flow](https://learn.microsoft.com/en-us/entra/msal/dotnet/acquiring-tokens/web-apps-apis/client-credential-flows).
2. Provision the customer service principal and Exchange pointer. Resolve the
   approved mailbox's stable object ID and scope that exact recipient. Preview the
   full scope, including Microsoft 365 groups, before assigning Mail.Send. Prefer
   an exact supported `ExternalDirectoryObjectId` filter; Microsoft's filter
   documentation warns against `PrimarySmtpAddress` filters because alias matching
   can broaden them. [Filter properties](https://learn.microsoft.com/en-us/powershell/exchange/recipientfilter-properties?view=exchange-ps),
   [recipient preview](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-recipient?view=exchange-ps).
3. Run the read-only validator. Separately inventory the customer's Entra grants
   and all Exchange application assignments. Confirm there is no parallel unscoped
   Entra `Mail.Send` or unrelated access. The Exchange test excludes Entra grants;
   the two grant systems are additive.
4. After propagation, make one controlled Graph attempt from the approved mailbox
   and one from each unrelated existing mailbox. The two negative probes must go
   directly to Graph under the same application identity so they exercise Exchange,
   even though the application guard would reject them earlier. Record sanitized
   UTC time, tenant, app/mailbox IDs, HTTP status, Graph request ID and outcome.
   Do not retain tokens, payload bodies or private headers. A `202` proves request
   acceptance; observe the controlled inbox separately if delivery matters.
5. Verify application cross-customer isolation with two mapped customer contexts.
   A request for customer A cannot select customer B's tenant or sender. Record
   that separately from the direct Graph mailbox denials.
6. Remove only the dedicated test assignment, allow propagation, and attempt the
   formerly approved mailbox again. It must be denied. Then remove the test-only
   credential and objects according to the approved cleanup plan; preserve the
   sanitized evidence and record what was removed.

Exchange's test cmdlet bypasses its live permission cache. Microsoft describes
cache behavior lasting roughly 30 minutes to two hours. Don't infer immediate
Graph denial from the cmdlet or blindly retry real mail while waiting.
[RBAC testing and cache behavior](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)

## Evidence status

| Check | Current evidence |
| --- | --- |
| Local binding, payload and recovery decisions | Synthetic tests; see [verification](verification.md) |
| Real Exchange command compatibility/scope | NotRun |
| Home/customer service-principal provisioning | NotRun |
| Entra permission inventory | NotRun |
| Certificate presence, private-key access, rotation | NotRun |
| Approved Graph request and two denied mailbox requests | NotRun |
| Real two-customer token/Graph isolation | NotRun |
| Revocation followed by denied Graph request | NotRun |

The next live work requires those concrete inputs and explicit permission. This
repository cannot grant that permission, and local green tests cannot replace it.
