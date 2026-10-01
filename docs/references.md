# Implementation references

These are the primary sources used for the design and handoff. They support the
design choices; they do not establish that this repository has passed live tests.

| Topic | Primary reference |
| --- | --- |
| Scoped Mail.Send, additive grants, service-principal pointer, testing/cache | [Exchange Application RBAC](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac) |
| Authorization result rows and resource selection | [Test-ServicePrincipalAuthorization](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/test-serviceprincipalauthorization?view=exchange-ps) |
| Preview filters, unlimited results, GroupMailbox inclusion | [Get-Recipient](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-recipient?view=exchange-ps) |
| Exact recipient filter properties and SMTP warning | [RecipientFilter properties](https://learn.microsoft.com/en-us/powershell/exchange/recipientfilter-properties?view=exchange-ps) |
| Exchange connection tenant/state/prefix | [Get-ConnectionInformation](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-connectioninformation?view=exchange-ps) |
| Customer Exchange service-principal identity | [Get-ServicePrincipal](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-serviceprincipal?view=exchange-ps) |
| App object versus customer service principal | [Entra application objects](https://learn.microsoft.com/en-us/entra/identity-platform/app-objects-and-service-principals) |
| Provisioning an existing multitenant app | [Create servicePrincipal](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-post-serviceprincipals?view=graph-rest-1.0) |
| Explicit-tenant certificate/MSAL client credential flow | [MSAL client credentials](https://learn.microsoft.com/en-us/entra/msal/dotnet/acquiring-tokens/web-apps-apis/client-credential-flows) |
| Token flow and app-only authorization | [Client credentials protocol](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-client-creds-grant-flow) |
| Graph request shape and acceptance semantics | [user: sendMail](https://learn.microsoft.com/en-us/graph/api/user-sendmail?view=graph-rest-1.0) |
| PDF attachment shape | [fileAttachment](https://learn.microsoft.com/en-us/graph/api/resources/fileattachment?view=graph-rest-1.0) |
| Retry-After and throttling | [Graph throttling](https://learn.microsoft.com/en-us/graph/throttling) |
| Future managed-identity federation | [Application trusts managed identity](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-config-app-trust-managed-identity) |
| Direct managed identity directory limitations | [Managed identities FAQ](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identities-faq) |
| SDK/runtime servicing | [.NET support policy](https://dotnet.microsoft.com/en-us/platform/support/policy/dotnet-core) |
| Official SDK checksum metadata | [.NET 10 release metadata](https://builds.dotnet.microsoft.com/dotnet/release-metadata/10.0/releases.json) |
| Portable local publishing | [.NET single-file deployment](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview) |
| Optional PowerShell lint | [Microsoft PSScriptAnalyzer 1.25.0](https://www.powershellgallery.com/packages/PSScriptAnalyzer/1.25.0) |
