# Verification

These results are for the sanitized local candidate, rechecked on 2026-10-01. They do not include live Microsoft 365 tests.

| Check | Result |
| --- | --- |
| Release CLI, core, console harness, and C# integration builds | Passed; no warnings/errors |
| Core synthetic console harness | 27/27 passed |
| Exchange synthetic suite, Windows PowerShell 5.1 and PowerShell 7 | 18/18 passed in each |
| Certificate-metadata syntax suite, both PowerShell versions | 11/11 passed in each |
| PowerShell parsing and PSScriptAnalyzer | Passed; zero error/warning findings |
| C# formatting checks | Passed |
| Source four-case local demo | Passed |
| Self-contained Windows x64 package and packaged demo in both shells | Passed |
| Package extraction into a path with spaces and interrupted/repeated-flow checks | Passed; 17/17 packaged checks |
| Old private repository links, user identifiers, and packaged binary in candidate files | None found |
| Real tenant, credentials, Entra grant inventory, Graph mail, cross-tenant proof, revocation | **NotRun** |

The synthetic tests exercise local decision-making only. The Exchange validator is read-only and does not inspect Entra grants. Real authorization remains unproven, and the application continues to report `securityModelProven: false`. No production deployment or public release has been performed.

Build and run these checks with `scripts/verify.ps1` and `scripts/package-demo.ps1`. See [testing](testing.md) for commands and coverage. The package is generated locally under ignored `artifacts/`; no packaged executable is included in source history.
