# Local examples

These examples use fictional customers, identifiers, addresses, and invoice
details. Every command uses the mock transport, so nothing connects to Microsoft
365 or delivers mail.

From the repository root, after `scripts/demo.ps1` has built the CLI:

```powershell
$state = Join-Path $env:TEMP 'm365scopedmail-my-local-workflow'
dotnet .\src\M365ScopedMail.Cli\bin\Release\net10.0\m365scopedmail.dll simulate `
    --config .\examples\customers.mock.json `
    --request .\examples\basic-send\request.json --state $state
```

Repeat that exact request with the same state folder to see `DuplicateSuppressed`.
Keep the state when testing recovery. A fresh directory means a fresh workflow,
so duplicate protection does not cross state directories.

| Request or scenario | Expected result |
| --- | --- |
| `basic-send/request.json` | `MockAccepted`, then `DuplicateSuppressed` |
| `invoice-send/request.json` | `MockAccepted` with the sample PDF |
| `negative/unauthorized-sender.json` | `Rejected / SenderMismatch` |
| `negative/cross-customer.json` | `Rejected / SenderMismatch` |
| `--scenario token-failure` | `Rejected / TokenFailure`; same key can recover |
| `--scenario authorization-denied` | `Rejected`; repeated separate keys open the customer circuit |
| `--scenario throttle-once` | One explicit mock throttle, then acceptance; two attempts |
| `--scenario uncertain` | `Uncertain`; same key stops for manual review |

Pass `--scenario` before its value at the end of the command. Use a new local key
and state for independent scenarios; reuse both when testing an interrupted/repeated
workflow. Normal output is a safe result, not the Graph payload. Exit 2 is expected
for negative scenarios.

`invoice-send/fictional-invoice.pdf` is a tiny valid PDF fixture. Its base64 appears
in the matching JSON request. The implementation does not scan PDFs or generate
real invoices. The [integration](integration) example is a small C# caller of
the same core; it also demonstrates suppressing the second submission.

## Proposed certificate metadata

```powershell
.\scripts\test-certificate-config.ps1 -Path .\examples\certificate-config.example.json
```

The all-`A` thumbprint is a placeholder. `ConfigurationSyntax: Valid` only confirms
the metadata shape. Certificate presence, private-key access, app registration,
and authorization remain `NotChecked`. Never put a private key, PFX, password,
secret, or token in these files. The sender does not read this configuration.
