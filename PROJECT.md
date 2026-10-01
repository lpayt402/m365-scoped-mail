# Project notes

## Purpose

M365 Scoped Mail explores how a small service could send routine messages from one approved Microsoft 365 mailbox per customer. The intended authorization boundary is Exchange Online Application RBAC. The project aims to avoid customer passwords, employee refresh tokens, and unnecessarily broad mailbox access.

This is a hobby project and a work in progress. It is independent of Microsoft and has no Microsoft endorsement or certification.

## Current state

The implemented sender is a local .NET mock. The CLI accepts only synthetic customer records, applies application-level tenant and sender checks, builds a Graph-shaped request, and records a safe result. It exercises duplicate suppression and recovery behavior against local mock providers. It has no live token provider, Graph transport, HTTP service, or credential access.

A separate PowerShell validator performs read-only checks in an existing Exchange Online session. It does not connect, provision objects, grant roles, inspect Entra application grants, or send email. Its success means only that the narrow Exchange responses matched the requested checks at that time.

No real-tenant behavior has been tested. `securityModelProven` remains `false`; Entra review, Graph positive and negative sends, cross-tenant behavior, and revocation are all **NotRun**. Local synthetic tests are useful for checking code paths but cannot prove Microsoft's live authorization behavior.

## Authorization rule to preserve

The intended design assigns Exchange `Application Mail.Send` to a specific recipient scope. Entra application grants and Exchange RBAC grants are additive. A separate unscoped Entra `Mail.Send` grant can bypass the intended mailbox restriction, so a scoped Exchange assignment alone is not sufficient evidence of least privilege.

Before any future live sender is activated, the project needs a reviewed permission inventory and authorized Graph tests that show the approved mailbox succeeds, unrelated existing mailboxes are denied, a second customer cannot select the first customer's context, and revocation prevents later sends after permission changes propagate. An Exchange authorization cmdlet result by itself does not prove those outcomes.

## Intended customer boundary

Each customer should authorize its own service principal and an explicit mailbox scope. The app registration's client ID and the customer tenant's Enterprise Application object ID are different values; the Exchange service-principal pointer must use the customer-side object ID. A trusted caller must select the customer context. A hosted endpoint must not accept an arbitrary tenant ID or mailbox from an unauthenticated request.

Keep customer administration separate from the eventual sending identity. Do not add a tenant-wide `Mail.Send` permission to compensate for a missing scope. The [live acceptance checklist](docs/live-acceptance.md) describes the evidence still needed; it is a future test plan, not a record of completed tenant work.

## Local implementation

- `src/M365ScopedMail.Core` validates registry and request data, enforces local tenant/mailbox bindings and payload limits, and coordinates duplicate protection, bounded retries, state recovery, and audit results.
- `src/M365ScopedMail.Cli` exposes `simulate` with mock providers only.
- `src/M365ScopedMail.Validation.psm1` runs the read-only Exchange checks.
- `scripts` contains the local demo, verification, packaging, certificate-metadata syntax check, and validator entry point.
- `examples` and `tests` use synthetic identifiers and fictional data. They make no network requests to Microsoft services.

Local JSON and state are operator-controlled files. The state is not signed or tamper-resistant, and it is not coordinated across machines. The mock's rate limits and circuit behavior do not control real Graph traffic. Any future live adapter needs independent review for credentials, caller identity, retries, concurrency, retention, and abuse controls.

## Work sequence

1. **Local mock:** implemented and covered by synthetic tests.
2. **Live authorization proof:** pending a separately approved test setup with dedicated test tenants, controlled mailboxes, a short-lived test credential, direct Graph positive/negative tests, and cleanup.
3. **Live adapters:** pending that evidence and a reviewed credential storage, rotation, token-cache, and retry design.
4. **Customer lifecycle:** repeatable setup, validation, offboarding, and revocation evidence remain future work.
5. **Hosted API:** only consider after a trusted caller identity and tenant isolation model are defined.

No production deployment or real message sending is part of the current implementation.

## Licensing and references

No license has been selected. Resolve that before asking others to contribute or treating the code as reusable. The .NET SDK may provide runtime license and third-party notice files for locally generated self-contained packages; those notices are copied into the package when available. Microsoft documentation links and the exact topics they support are listed in [references](docs/references.md).
