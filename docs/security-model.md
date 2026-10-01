# Current security boundary

The part I'm trying to get right is the gap between what the app checks and what
Microsoft authorizes. The intended sending boundary is Exchange Online Application
RBAC, with `Application Mail.Send` assigned to an explicit mailbox scope. The local
mock core also checks tenant/mailbox bindings, but that is application logic, not
Microsoft 365's permission boundary.

Microsoft documents Entra and Exchange RBAC grants as additive. An unrestricted
Entra `Mail.Send` grant can bypass the intended mailbox restriction. The Exchange
authorization test does not inspect Entra grants and bypasses the live permission
cache, which Microsoft says can last 30 minutes to two hours. An out-of-scope
cmdlet result alone does not prove Graph will deny a send. [Microsoft's Application
RBAC guidance](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)

The validator therefore always reports `SecurityModelProven = false`, with Entra
review and Graph send tests marked `NotRun`. It never activates a customer. Its
success means only that the observed Exchange responses meet the narrow
one-mailbox checks at that moment.

| Risk | Current protection | Remaining evidence or implementation |
| --- | --- | --- |
| Wrong customer tenant | Validator checks the single Exchange session; core uses a fixed customer mapping and checks token-envelope tenant | Real token adapter and cross-tenant send tests |
| Wrong service-principal pointer | Both customer object ID and client ID must match | Authorized multitenant bootstrap and verification |
| Scope contains extra recipients | Preview must contain exactly the approved mailbox | Periodic revalidation as tenant configuration changes |
| Denied mailbox unexpectedly allowed | Evaluate every returned assignment | Real Graph negative tests after cache propagation |
| Extra mailbox permissions | Reject unexpected roles or unverified scopes | Separate Entra grant inventory and review |
| False success after errors | Missing, malformed, or failed reads throw | Live compatibility testing in an authorized tenant |
| Credential or message leakage | Synthetic token only; audit omits recipients/content; raw provider errors suppressed | Real token validation, credential lifetime and storage review |
| Sending abuse | Mock core bounds recipients/PDF/text, persists rate/circuit limits and duplicate protection | Authenticated caller context, durable multi-host state, retention |

The validator is a read-only administrator aid, not an enforcement service. Its
results depend on the administrator being able to see the full recipient set and
relevant application role assignments, and tenant data can change between reads.
Synthetic tests show how the code responds to fixtures; they do not establish
Microsoft 365's live authorization behavior.

There is no onboarding/offboarding, identity bootstrap, live application
authentication, or real sending here. Those need tenant authorization and a
verified revocation workflow. See the
[live acceptance checklist](live-acceptance.md).

The CLI accepts only synthetic registry entries and constructs mock providers.
Its interfaces are extension points, not proof that a future adapter is safe.
Registry and state files are trusted local inputs. Fingerprints detect changed
requests when state is intact; they are not signatures, and an operator can edit
or delete the state. Access control, backup, and retention need review before
unattended use. A hosted service also needs a trusted caller identity to select a
customer.
