# Developer handoff

The mock CLI can run without a tenant. The read-only Exchange validator requires
an existing connected Exchange session. The goal I'm exploring is one approved
mailbox per customer, with Exchange enforcing that permission boundary.

## What is ready

| Component | Location | Behavior |
| --- | --- | --- |
| Send core | `src/M365ScopedMail.Core` | Validates bindings/payloads, coordinates bounded submission and recovery |
| Mock CLI | `src/M365ScopedMail.Cli` | `simulate` only; safe JSON output and exit codes |
| Exchange validator | `src/M365ScopedMail.Validation.psm1` | Read-only checks in an existing administrator session |
| Local examples | `examples` | Two fictional customers, positive/negative requests, PDF, C# integration |
| Windows tools | `scripts/demo.ps1`, `scripts/verify.ps1` | Build/run demo and required local checks |
| Certificate metadata check | `scripts/test-certificate-config.ps1` | Syntax only; does not inspect or use credentials |

Build from the repository root with the pinned .NET SDK. The shared PowerShell
helper isolates SDK scratch/config paths in temporary storage and disables its
first-run development certificate generation. It changes no global PATH,
credentials, execution policy, or installed modules. There are no `PackageReference`
dependencies; `NuGet.Config` names only the recognized NuGet.org registry.

```powershell
.\scripts\verify.ps1
.\scripts\demo.ps1
```

On a constrained workstation, use `-DotNetPath` with an isolated SDK. The C# example
can be built and run through the same helper:

```powershell
Import-Module .\scripts\M365ScopedMail.Tools.psm1
$sdk = (Get-Command dotnet).Source
Invoke-M365ScopedMailProcess -FilePath $sdk -WorkingDirectory $PWD.Path -ArgumentList @(
    'restore', 'examples/integration/M365ScopedMail.Integration.csproj', '--configfile', 'NuGet.Config'
)
Invoke-M365ScopedMailProcess -FilePath $sdk -WorkingDirectory $PWD.Path -ArgumentList @(
    'run', '--no-restore', '--project', 'examples/integration', '--', $PWD.Path
)
```

## Adapter contract

`StrictJson.Read<CustomerRegistry>` and `StrictJson.Read<SendRequest>` produce the
public records. Construct `SendCoordinator` with the registry and four adapter
interfaces, then call `SendAsync`. [The compiled example](../examples/integration/Program.cs)
shows the complete wiring. Test-only `TimeProvider` and delay injection avoid real
waits in failure tests.

Exit 0 means `MockAccepted` or `DuplicateSuppressed`. Exit 2 covers rejected,
uncertain, and infrastructure-failure results. Treat `MockAcceptedAuditFailed` and
`MockAcceptedStateFailure` as submission already accepted with incomplete local
evidence. Neither is a safe instruction to blindly send again. Result categories
are suitable for a caller’s decision; raw provider exception text is suppressed.

The CLI requires `SyntheticOnly` registry entries and reports `mode: Mock` and
`securityModelProven: false`. It cannot send real mail. A future live entry point
would need to check a customer's evidence and get customer context from a trusted
caller identity. A customer ID in an unauthenticated request is not enough for a
hosted service.

## Next implementation

1. Complete the authorized live proof in [live-acceptance.md](live-acceptance.md).
   It must exercise Exchange denial directly, not merely this application’s guard.
2. Add a certificate-backed MSAL token adapter with an explicit customer tenant
   authority, token caching, and a reviewed credential lifetime/rotation plan.
   The local private key stays in Windows `CurrentUser\\My`; only the public
   certificate would be registered on the home application. This is the proposed
   local development path, not a credential created by this repository.
   [Microsoft’s client credential guidance](https://learn.microsoft.com/en-us/entra/msal/dotnet/acquiring-tokens/web-apps-apis/client-credential-flows)
3. Add a Graph adapter that classifies explicit authorization rejection, explicit
   throttling, acceptance, and ambiguous failure. Honor `Retry-After`; do not retry
   a timeout merely because no response reached the client.
4. Make customer onboarding/offboarding repeatable and verify revocation. Then
   decide whether a small authenticated API is useful enough to justify hosting.

Keep privileged customer administration separate from the sending application.
Do not add tenant-wide `Mail.Send` to solve a scoped authorization problem. Future
hosting can consider managed-identity federation; direct managed identities do
not support cross-directory access. Microsoft documents an application trusting
a home-tenant managed identity for multitenant access after customer provisioning.
[Federation guidance](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-config-app-trust-managed-identity),
[managed identity FAQ](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/managed-identities-faq).

## Decisions still open

The application/home tenant, real test tenants and controlled recipients, key
lifetime/rotation, live adapter package versions, retention, and eventual caller
authentication/hosting have not been selected or provisioned. The mock is not
production-ready. No license has been chosen for this repository; resolve that
before public distribution.
