# Current security boundary

The intended sending boundary is Exchange Online Application RBAC, with
`Application Mail.Send` assigned to an explicit mailbox scope. Application-level
tenant/mailbox binding is also enforced in the local mock core. That check is
separate from Microsoft 365's real permission boundary.

Microsoft documents Entra grants and Exchange RBAC grants as additive. A parallel
unrestricted Entra `Mail.Send` grant can bypass the intended mailbox restriction.
The Exchange authorization test does not evaluate those Entra grants. It also
bypasses the live permission cache; Microsoft describes a 30-minute to two-hour
cache window. A cmdlet's out-of-scope result alone does not prove Graph will deny a
send. [Microsoft's Application RBAC guidance](https://learn.microsoft.com/en-us/exchange/permissions-exo/application-rbac)

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

The validator is a read-only administrator aid, not an enforcement service.
Administrator visibility can itself be limited: an administrator must be able to
inspect the complete recipient set and all relevant application role assignments.
Data can change between reads. Synthetic tests prove the code's decisions against
fixtures, not Microsoft 365's live authorization behavior.

No onboarding/offboarding mutation, identity bootstrap, live application authentication,
or real sending is implemented here. Those are separate work requiring explicit
tenant authorization and a verified revocation workflow. See the
[live acceptance checklist](live-acceptance.md).

The CLI accepts only synthetic registry entries and constructs only mock providers.
The reusable interfaces are extension points, not proof that any future adapter is
safe. Registry and state files are trusted local operator inputs. Fingerprints
detect changed requests against intact state; they are not a signature, and an
operator can edit/delete state. Store access control, backup and retention need
review before unattended use. A hosted service will also need a trusted caller
identity before selecting a customer.
