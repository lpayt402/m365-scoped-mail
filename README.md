# M365 Scoped Mail

**Least-privilege application email for Microsoft 365**

M365 Scoped Mail is an independent hobby project exploring unattended service-generated email from one approved Microsoft 365 mailbox. The intended design uses an application identity and Exchange Application RBAC, without customer passwords or an employee's refresh token. This project is not affiliated with, endorsed by, or certified by Microsoft.

## What works today

The repository contains a local mock sender and a read-only Exchange validator. The mock exercises input checks, tenant/mailbox binding, duplicate suppression, failure recovery, and privacy-conscious audit output. It never signs in or sends mail. The validator can inspect an already connected Exchange session; it does not sign in, change permissions, or send a message.

There is no credential or token adapter, Microsoft Graph transport, customer onboarding/offboarding workflow, hosted service, or live authorization proof. Every real-tenant check remains **NotRun**, and the program reports `securityModelProven: false`. Treat the code as a learning and review project, not a production mail service.

## Try the local demo

On Windows, install the [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0), open PowerShell in this folder, and run:

```powershell
.\scripts\demo.ps1
```

The four checks use fictional customers and local mock providers. A typical run reports an accepted mock request, duplicate suppression, and two rejected senders. No Microsoft account, tenant, certificate, Exchange module, or network connection is needed for this demo. All sample email addresses use the reserved `.example` domain.

To run the complete local checks:

```powershell
.\scripts\verify.ps1
```

See [tests and packaging](docs/testing.md) for the test coverage and how to build a self-contained Windows demo package locally. This repository does not provide a downloadable public binary.

## Read next

- [Architecture](docs/architecture.md) describes the mock workflow and its limits.
- [Security boundary](docs/security-model.md) explains which checks are local and which are still unproven.
- [Examples](examples/README.md) shows accepted, repeated, and rejected synthetic requests.
- [Read-only validation](docs/validation.md) explains the Exchange validator.
- [Live acceptance checklist](docs/live-acceptance.md) records evidence still needed before any real sending path.
- [Microsoft references](docs/references.md) links the primary documentation behind the design.
- [Project notes](PROJECT.md) records scope and future steps.

## Licensing

No project license has been selected. Public visibility does not grant permission to reuse or redistribute the code. Decide on and add a license before inviting contributions or presenting this as a reusable library. Local demo packages include applicable .NET runtime notices when the SDK supplies them.
