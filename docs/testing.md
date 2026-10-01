# Tests and verification

From the repository root with the .NET 10 SDK:

```powershell
.\scripts\verify.ps1
.\scripts\demo.ps1
```

`verify.ps1` explicitly restores and builds the CLI, console harness and C# integration
example. It runs all three local workflows, the isolated PowerShell suites, and
`dotnet format whitespace --verify-no-changes --no-restore` for each C# entry project.
Warnings are build errors. The .NET tests are a dependency-free executable harness;
use the verifier rather than `dotnet test`, which would not discover these cases.
No live tenant, credentials, Graph SDK or Exchange module is needed.

The harness covers binding before providers, payload/PDF shapes and limits,
immutable request snapshots, persistent duplicate/conflict handling, token recovery,
pending/uncertain restart behavior, cancellation, bounded throttling, rate/circuit
isolation, corrupt/capacity state, concurrent lock contention, state-save failures,
and audit privacy/failure/timestamp handling. See [the recorded results](verification.md)
for exact counts and current revision evidence.

## PowerShell-only checks

```powershell
pwsh -NoProfile -File .\tests\run-tests.ps1
powershell.exe -NoProfile -File .\tests\run-tests.ps1
```

The launcher uses separate `-NoProfile` children so synthetic Exchange cmdlets
cannot replace commands in the caller’s session. The Exchange suite covers identity
and scope mix-ups, hidden groups, malformed/empty responses, unexpected grants,
safe error handling and repeated validation. Certificate tests check syntax only,
including scalar types and duplicate/unknown fields. All PowerShell source files
are parsed. A narrow validator AST check rejects known mutation/network cmdlets;
that is useful evidence, not a full security audit.

The Exchange fixtures have one documented `PSAvoidGlobalVars` suppression because
the mocks share fixture state inside their isolated child. Production validator
code has no rule suppressions.

Optional lint uses Microsoft’s [PSScriptAnalyzer 1.25.0](https://www.powershellgallery.com/packages/PSScriptAnalyzer/1.25.0):

```powershell
.\scripts\verify.ps1 -AnalyzerPath 'C:\path\to\PSScriptAnalyzer.psd1'
```

If neither that path nor an installed module is available, the verifier explicitly
reports lint as skipped. Other failures stop the script with a nonzero exit code.
In a restrictive sandbox, Roslyn’s formatting host may need permission for local
named pipes; report that failure rather than pretending formatting passed.

## Local Windows package

```powershell
.\scripts\package-demo.ps1
```

This creates a fresh ignored `artifacts/windows-demo-*` directory and ZIP without
deleting earlier output. The initial build downloads Microsoft runtime packs from
the configured NuGet.org source. It publishes a self-contained Windows x64 mock;
running the resulting demo requires no SDK or network. This is a local review
artifact. It is not uploaded or released by the script. Single-file extraction
uses the runtime’s temporary cache. Runtime updates require rebuilding.
[Microsoft single-file guidance](https://learn.microsoft.com/en-us/dotnet/core/deploying/single-file/overview)

Run `scripts/demo.ps1 -ExecutablePath .\m365scopedmail.exe` in the extracted package.
Repeat it, then run the PDF request and exceptional scenarios from [the examples](../examples/README.md).
Use the same state for recovery checks. Accepted duplicates must not submit again;
ambiguous/pending attempts must stop for investigation.

For the executable-level recovery checks, use the folder returned by packaging:

```powershell
.\tests\packaged-flows.ps1 -PackagePath .\artifacts\windows-demo-<folder-id>
```

That focused suite launches separate packaged processes for PDF/replay, token
recovery, ambiguous repeats, throttle/replay, changed payload, corrupt state,
lock contention/recovery, persistent authorization circuit, and forbidden caller
tenant fields. It uses only new temporary synthetic state.

## Live evidence

All real tenant, permission inventory, certificate, Graph and revocation checks
remain **NotRun**. Local tests prove decisions against synthetic adapters, not
Microsoft 365 authorization. See [live-acceptance.md](live-acceptance.md) for the
separate approved test sequence. There is no UI in this increment; browser/UI
checks are not applicable.
