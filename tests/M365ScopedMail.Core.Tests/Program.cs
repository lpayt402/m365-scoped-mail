using System.Text;
using System.Text.Json;
using M365ScopedMail.Core;

var tests = new (string Name, Func<Task> Run)[]
{
    ("mock send uses registry mailbox and Graph plain-text PDF shape", Positive),
    ("unknown disabled and wrong sender stop before providers", Rejections),
    ("invalid registry IDs tenants and status rejected", InvalidRegistries),
    ("token tenant mismatch stops transport", WrongToken),
    ("file-backed accepted replay survives coordinator recreation", Replay),
    ("changed payload cannot reuse key", Conflict),
    ("token failure before submission allows recovery", TokenRecovery),
    ("ambiguous outcome requires review without resend", Uncertain),
    ("transport exception is uncertain without retry", ExceptionUncertain),
    ("cancellation after pending is uncertain without resend", CancelPending),
    ("persisted interrupted pending blocks resend", InterruptedPending),
    ("explicit throttle retries once with bounded delay", Throttle),
    ("repeated throttle stops after two attempts", ThrottleBound),
    ("authorization hard-stops and persists customer circuit", Authorization),
    ("persisted rate limit isolates customers", RateLimit),
    ("payload and PDF restrictions reject before tokens", InvalidPayloads),
    ("strict JSON rejects unknown duplicate missing and credential fields", JsonRejections),
    ("corrupt state fails closed", CorruptState),
    ("exclusive state lock fails concurrent invocation closed", ConcurrentLock),
    ("state failure before pending prevents transport", StateFailureBefore),
    ("state failure after acceptance preserves pending replay protection", StateFailureAfter),
    ("audit failure after acceptance preserves acceptance and suppresses replay", AuditFailure),
    ("audit and persisted state contain metadata only", Privacy),
    ("UTC timestamps reflect rejected accepted and replay occurrences", OccurrenceTimestamps),
    ("state capacity never evicts protected records", StateCapacity),
    ("caller array mutation cannot alter validated payload or routing", MutationIsolation),
    ("cancellation before token performs no submission", CancelBefore)
};
var failures = 0;
foreach (var (name, run) in tests)
{
    try { await run(); Console.WriteLine("PASS " + name); }
    catch (Exception ex) { failures++; Console.Error.WriteLine("FAIL " + name + ": " + ex.Message); }
}
Console.WriteLine($"{tests.Length - failures}/{tests.Length} passed; {failures} failed. Synthetic tests only.");
return failures == 0 ? 0 : 1;

static async Task Positive()
{
    var fixture = new Fixture();
    var request = Request() with { Attachment = new PdfAttachment { Name = "report.pdf", ContentBase64 = Convert.ToBase64String("%PDF-1.7\nsynthetic"u8) } };
    var result = await fixture.Sender().SendAsync(request);
    Equal("MockAccepted", result.Status); Equal(1, result.Attempts); Equal(false, result.SecurityModelProven);
    Equal("/v1.0/users/33333333-3333-4333-8333-333333333333/sendMail", fixture.Transport.Path);
    using var json = JsonDocument.Parse(fixture.Transport.Payload!);
    var message = json.RootElement.GetProperty("message");
    Equal("Text", message.GetProperty("body").GetProperty("contentType").GetString());
    Equal(request.Text, message.GetProperty("body").GetProperty("content").GetString());
    Equal(request.From, message.GetProperty("from").GetProperty("emailAddress").GetProperty("address").GetString());
    Equal(request.To[0], message.GetProperty("toRecipients")[0].GetProperty("emailAddress").GetProperty("address").GetString());
    var attachment = message.GetProperty("attachments")[0];
    Equal("#microsoft.graph.fileAttachment", attachment.GetProperty("@odata.type").GetString());
    Equal("application/pdf", attachment.GetProperty("contentType").GetString());
    Equal(request.Attachment.ContentBase64, attachment.GetProperty("contentBytes").GetString());
    Equal(true, json.RootElement.GetProperty("saveToSentItems").GetBoolean());
    Equal(Registry().ClientId, fixture.Tokens.ClientId);
    Equal(Registry().Customers[0].ServicePrincipalObjectId, fixture.Tokens.Customer!.ServicePrincipalObjectId);
}

static async Task Rejections()
{
    foreach (var request in new[] { Request() with { Customer = "unknown" }, Request() with { From = "other@example.test" }, Request() with { Customer = "beta" } })
    {
        var fixture = new Fixture(); Equal("Rejected", (await fixture.Sender().SendAsync(request)).Status);
        Equal(0, fixture.Tokens.Calls); Equal(0, fixture.Transport.Calls);
    }
    var disabled = new Fixture();
    var registry = Registry(); registry.Customers[0] = registry.Customers[0] with { Enabled = false };
    Equal("DisabledCustomer", (await disabled.Sender(registry).SendAsync(Request())).ErrorCategory);
    Equal(0, disabled.Tokens.Calls);
}

static Task InvalidRegistries()
{
    foreach (var registry in new[]
    {
        Registry() with { ClientId = Guid.Empty.ToString() }, Registry() with { ClientId = "bad" },
        Registry() with { Customers = [Registry().Customers[0], Registry().Customers[0] with { Id = "beta" }] },
        Registry() with { Customers = [Registry().Customers[0] with { MailboxObjectId = "" }] },
        Registry() with { Customers = [Registry().Customers[0] with { ServicePrincipalObjectId = "bad" }] },
        Registry() with { Customers = [Registry().Customers[0] with { ValidationStatus = "Verified" }] },
        Registry() with { Customers = [Registry().Customers[0], Registry().Customers[1] with { Id = "alpha" }] }
    }) Throws<ValidationException>(() => InputValidation.Registry(registry));
    return Task.CompletedTask;
}

static async Task WrongToken()
{
    var fixture = new Fixture(); fixture.Tokens.Handler = (_, _) => Task.FromResult(new TokenEnvelope(Registry().Customers[1].TenantId, "secret"));
    Equal("TokenTenantMismatch", (await fixture.Sender().SendAsync(Request())).ErrorCategory); Equal(0, fixture.Transport.Calls);
}

static async Task Replay()
{
    var fixture = new Fixture(); Equal("MockAccepted", (await fixture.Sender().SendAsync(Request())).Status);
    var recreated = new Fixture(fixture.Directory);
    Equal("DuplicateSuppressed", (await recreated.Sender().SendAsync(Request())).Status);
    Equal(0, recreated.Tokens.Calls); Equal(0, recreated.Transport.Calls);
}

static async Task Conflict()
{
    var fixture = new Fixture(); await fixture.Sender().SendAsync(Request());
    Equal("IdempotencyConflict", (await fixture.Sender().SendAsync(Request() with { Text = "Changed" })).ErrorCategory);
    Equal(1, fixture.Transport.Calls);
}

static async Task TokenRecovery()
{
    var fixture = new Fixture(); fixture.Tokens.Handler = (_, _) => throw new InvalidOperationException("secret token failure");
    Equal("TokenFailure", (await fixture.Sender().SendAsync(Request())).ErrorCategory); Equal(0, fixture.Transport.Calls);
    var recreated = new Fixture(fixture.Directory); Equal("MockAccepted", (await recreated.Sender().SendAsync(Request())).Status);
}

static async Task Uncertain()
{
    var fixture = new Fixture(); fixture.Transport.Handler = _ => Task.FromResult(new TransportReply(TransportDisposition.Uncertain));
    Equal("Uncertain", (await fixture.Sender().SendAsync(Request())).Status);
    Equal("Uncertain", (await new Fixture(fixture.Directory).Sender().SendAsync(Request())).Status);
    Equal(1, fixture.Transport.Calls);
}

static async Task ExceptionUncertain()
{
    var fixture = new Fixture(); fixture.Transport.Handler = _ => throw new IOException("private provider message");
    Equal("Uncertain", (await fixture.Sender().SendAsync(Request())).Status);
    Equal("Uncertain", (await fixture.Sender().SendAsync(Request())).Status); Equal(1, fixture.Transport.Calls);
}

static async Task CancelPending()
{
    var fixture = new Fixture(); using var cts = new CancellationTokenSource();
    fixture.Transport.Handler = ct => { cts.Cancel(); ct.ThrowIfCancellationRequested(); return Task.FromResult(new TransportReply(TransportDisposition.Accepted)); };
    Equal("Uncertain", (await fixture.Sender().SendAsync(Request(), cts.Token)).Status);
    Equal("Uncertain", (await new Fixture(fixture.Directory).Sender().SendAsync(Request())).Status); Equal(1, fixture.Transport.Calls);
}

static async Task InterruptedPending()
{
    var fixture = new Fixture(); fixture.Transport.Handler = _ => Task.FromResult(new TransportReply(TransportDisposition.Uncertain));
    await fixture.Sender().SendAsync(Request());
    await using (var lease = await fixture.Store.AcquireAsync(default)) { lease.State.Submissions.Single().Value.Status = "Pending"; await lease.SaveAsync(); }
    var recreated = new Fixture(fixture.Directory);
    Equal("ManualReviewRequired", (await recreated.Sender().SendAsync(Request())).ErrorCategory); Equal(0, recreated.Transport.Calls);
}

static async Task Throttle()
{
    var fixture = new Fixture(); fixture.Transport.Handler = _ => Task.FromResult(new TransportReply(fixture.Transport.Calls == 1 ? TransportDisposition.Throttled : TransportDisposition.Accepted));
    var result = await fixture.Sender().SendAsync(Request()); Equal("MockAccepted", result.Status); Equal(2, result.Attempts);
    Equal(1, fixture.Delays.Count); Equal(TimeSpan.FromMilliseconds(250), fixture.Delays[0]);
}

static async Task ThrottleBound()
{
    var fixture = new Fixture(); fixture.Transport.Handler = _ => Task.FromResult(new TransportReply(TransportDisposition.Throttled));
    Equal("Throttled", (await fixture.Sender().SendAsync(Request())).ErrorCategory); Equal(2, fixture.Transport.Calls); Equal(1, fixture.Delays.Count);
}

static async Task Authorization()
{
    var fixture = new Fixture(); fixture.Transport.Handler = _ => Task.FromResult(new TransportReply(TransportDisposition.AuthorizationDenied));
    Equal("AuthorizationDenied", (await fixture.Sender().SendAsync(Request())).ErrorCategory); Equal(1, fixture.Transport.Calls); Equal(0, fixture.Delays.Count);
    await fixture.Sender().SendAsync(Request() with { IdempotencyKey = "second" }); Equal(2, fixture.Transport.Calls);
    var recreated = new Fixture(fixture.Directory);
    Equal("CircuitOpen", (await recreated.Sender().SendAsync(Request() with { IdempotencyKey = "third" })).ErrorCategory); Equal(0, recreated.Tokens.Calls);
    Equal("MockAccepted", (await recreated.Sender().SendAsync(Beta())).Status);
}

static async Task RateLimit()
{
    var fixture = new Fixture();
    for (var i = 0; i < 5; i++) Equal("MockAccepted", (await fixture.Sender().SendAsync(Request() with { IdempotencyKey = "key" + i })).Status);
    var recreated = new Fixture(fixture.Directory);
    Equal("RateLimited", (await recreated.Sender().SendAsync(Request() with { IdempotencyKey = "key6" })).ErrorCategory);
    Equal(0, recreated.Transport.Calls); Equal(0, recreated.Tokens.Calls); Equal("MockAccepted", (await recreated.Sender().SendAsync(Beta())).Status);
    fixture.Clock.Now = fixture.Clock.Now.AddMinutes(1);
    Equal("MockAccepted", (await fixture.Sender().SendAsync(Request() with { IdempotencyKey = "key6" })).Status);
}

static async Task InvalidPayloads()
{
    var pdf = Convert.ToBase64String("%PDF-synthetic"u8);
    var badRequests = new[]
    {
        Request() with { To = [] }, Request() with { To = Enumerable.Repeat("recipient@example.test", 11).ToArray() },
        Request() with { To = ["Recipient <recipient@example.test>"] }, Request() with { To = ["x@example.test\r\nsecret"] },
        Request() with { To = ["x@example.test", "X@example.test"] }, Request() with { To = [null!] },
        Request() with { Subject = "" }, Request() with { Subject = new string('x', 201) }, Request() with { Subject = "a\nb" },
        Request() with { Text = "" }, Request() with { Text = new string('x', 65537) }, Request() with { IdempotencyKey = "" },
        Request() with { Attachment = new() { Name = "../secret.pdf", ContentBase64 = pdf } },
        Request() with { Attachment = new() { Name = "secret.txt", ContentBase64 = pdf } },
        Request() with { Attachment = new() { Name = "secret.pdf", ContentBase64 = "bad!" } },
        Request() with { Attachment = new() { Name = "secret.pdf", ContentBase64 = Convert.ToBase64String("notpdf"u8) } },
        Request() with { Attachment = new() { Name = "secret.pdf", ContentBase64 = Convert.ToBase64String(new byte[1048577]) } }
    };
    foreach (var request in badRequests)
    {
        var fixture = new Fixture(); Equal("Rejected", (await fixture.Sender().SendAsync(request)).Status);
        Equal(0, fixture.Tokens.Calls); Equal(0, fixture.Transport.Calls);
    }
}

static Task JsonRejections()
{
    var request = JsonSerializer.Serialize(Request(), StrictJson.Options);
    foreach (var extra in new[] { "tenantId", "html", "credentialPath", "certificateThumbprint", "clientSecret" })
        Throws<JsonException>(() => StrictJson.Read<SendRequest>(request.Insert(1, $"\"{extra}\":\"forbidden\",")));
    Throws<JsonException>(() => StrictJson.Read<SendRequest>(request.Insert(1, "\"customer\":\"beta\",")));
    Throws<JsonException>(() => StrictJson.Read<SendRequest>("{}"));
    Throws<JsonException>(() => StrictJson.Read<SendRequest>("{"));
    var registry = JsonSerializer.Serialize(Registry(), StrictJson.Options);
    Throws<JsonException>(() => StrictJson.Read<CustomerRegistry>(registry.Insert(1, "\"credentialPath\":\"forbidden\",")));
    return Task.CompletedTask;
}

static async Task CorruptState()
{
    var fixture = new Fixture(); System.IO.Directory.CreateDirectory(fixture.Directory);
    foreach (var text in new[] { "{", "{}", "null", "{\"schemaVersion\":1,\"submissions\":null,\"customers\":{}}" })
    {
        await File.WriteAllTextAsync(Path.Combine(fixture.Directory, "state.json"), text);
        Equal("StateUnavailable", (await fixture.Sender().SendAsync(Request())).ErrorCategory);
    }
    Equal(0, fixture.Tokens.Calls); Equal(0, fixture.Transport.Calls);
}

static async Task ConcurrentLock()
{
    var fixture = new Fixture(); await using var lease = await fixture.Store.AcquireAsync(default);
    var competing = new Fixture(fixture.Directory);
    Equal("StateUnavailable", (await competing.Sender().SendAsync(Request())).ErrorCategory); Equal(0, competing.Tokens.Calls);
}

static async Task StateFailureBefore()
{
    var fixture = new Fixture(); var store = new FailingStore(fixture.Store, 2);
    Equal("StateUnavailable", (await fixture.Sender(store: store).SendAsync(Request())).ErrorCategory); Equal(0, fixture.Transport.Calls);
}

static async Task StateFailureAfter()
{
    var fixture = new Fixture(); var store = new FailingStore(fixture.Store, 3);
    Equal("MockAcceptedStateFailure", (await fixture.Sender(store: store).SendAsync(Request())).Status);
    var recreated = new Fixture(fixture.Directory); Equal("Uncertain", (await recreated.Sender().SendAsync(Request())).Status);
    Equal(0, recreated.Transport.Calls);
}

static async Task AuditFailure()
{
    var fixture = new Fixture(); fixture.Audit.Fail = true;
    Equal("MockAcceptedAuditFailed", (await fixture.Sender().SendAsync(Request())).Status);
    var recreated = new Fixture(fixture.Directory); Equal("DuplicateSuppressed", (await recreated.Sender().SendAsync(Request())).Status); Equal(0, recreated.Transport.Calls);
}

static async Task Privacy()
{
    var fixture = new Fixture(); var request = Request() with { Attachment = new() { Name = "private-attachment.pdf", ContentBase64 = Convert.ToBase64String("%PDF-private-contents"u8) } };
    fixture.Transport.Handler = _ =>
    {
        fixture.Clock.Now = fixture.Clock.Now.AddSeconds(45);
        return Task.FromResult(new TransportReply(TransportDisposition.Accepted));
    };
    await fixture.Sender(audit: new JsonLineAuditSink(fixture.Directory)).SendAsync(request);
    var audit = await File.ReadAllTextAsync(Path.Combine(fixture.Directory, "audit.jsonl"));
    var state = await File.ReadAllTextAsync(Path.Combine(fixture.Directory, "state.json"));
    foreach (var sensitive in new[] { request.Subject, request.Text, request.To[0], request.Attachment.Name, request.Attachment.ContentBase64, request.IdempotencyKey, "synthetic-secret" })
    {
        Check(!audit.Contains(sensitive, StringComparison.Ordinal), "Audit leaked content.");
        Check(!state.Contains(sensitive, StringComparison.Ordinal), "State leaked content.");
    }
    using var parsed = JsonDocument.Parse(audit); Equal(false, parsed.RootElement.GetProperty("securityModelProven").GetBoolean());
    var timestamp = parsed.RootElement.GetProperty("timestampUtc").GetDateTimeOffset();
    Equal(fixture.Clock.Now, timestamp); Equal(TimeSpan.Zero, timestamp.Offset);
}

static async Task OccurrenceTimestamps()
{
    var fixture = new Fixture(); var sender = fixture.Sender();
    Equal(fixture.Clock.Now, (await sender.SendAsync(Request() with { Customer = "unknown" })).TimestampUtc);
    using var canceled = new CancellationTokenSource(); canceled.Cancel();
    fixture.Clock.Now = fixture.Clock.Now.AddSeconds(10);
    Equal(fixture.Clock.Now, (await sender.SendAsync(Request(), canceled.Token)).TimestampUtc);
    fixture.Tokens.Handler = (_, _) => throw new InvalidOperationException("Synthetic token failure");
    fixture.Clock.Now = fixture.Clock.Now.AddSeconds(10);
    Equal(fixture.Clock.Now, (await sender.SendAsync(Request())).TimestampUtc);
    fixture.Tokens.Handler = null;
    fixture.Clock.Now = fixture.Clock.Now.AddSeconds(10);
    var accepted = await sender.SendAsync(Request());
    Equal("MockAccepted", accepted.Status); Equal(fixture.Clock.Now, accepted.TimestampUtc);
    fixture.Clock.Now = fixture.Clock.Now.AddSeconds(10);
    var replay = await sender.SendAsync(Request());
    Equal("DuplicateSuppressed", replay.Status); Equal(accepted.EventId, replay.EventId);
    Equal(fixture.Clock.Now, replay.TimestampUtc); Equal(TimeSpan.Zero, replay.TimestampUtc.Offset);
    Check(replay.TimestampUtc > accepted.TimestampUtc, "Replay should have its own occurrence time.");
}

static async Task StateCapacity()
{
    var fixture = new Fixture(); await using (var lease = await fixture.Store.AcquireAsync(default))
    {
        lease.State.Customers.Add("alpha", new() { Attempts = [], AuthorizationFailures = 0, CircuitUntil = null });
        for (var i = 0; i < 10000; i++) lease.State.Submissions.Add(i.ToString("X64"), new()
        { Customer = "alpha", Fingerprint = new string('A', 64), EventId = Guid.NewGuid().ToString(), Status = "Pending" });
        await lease.SaveAsync();
    }
    Equal("StateCapacity", (await fixture.Sender().SendAsync(Request())).ErrorCategory); Equal(0, fixture.Tokens.Calls);
    await using var check = await fixture.Store.AcquireAsync(default); Equal(10000, check.State.Submissions.Count);
}

static async Task CancelBefore()
{
    var fixture = new Fixture(); using var cts = new CancellationTokenSource(); cts.Cancel();
    Equal("CanceledBeforeSubmission", (await fixture.Sender().SendAsync(Request(), cts.Token)).ErrorCategory); Equal(0, fixture.Tokens.Calls); Equal(0, fixture.Transport.Calls);
}

static async Task MutationIsolation()
{
    var fixture = new Fixture(); var request = Request(); var registry = Registry();
    var sender = fixture.Sender(registry);
    registry.Customers[0] = registry.Customers[1];
    fixture.Tokens.Handler = (customer, _) =>
    {
        request.To[0] = "changed@other.test";
        return Task.FromResult(new TokenEnvelope(customer.TenantId, "synthetic-secret"));
    };
    Equal("MockAccepted", (await sender.SendAsync(request)).Status);
    using var payload = JsonDocument.Parse(fixture.Transport.Payload!);
    Equal("private-recipient@example.test", payload.RootElement.GetProperty("message").GetProperty("toRecipients")[0].GetProperty("emailAddress").GetProperty("address").GetString());
}

static SendRequest Request() => new() { Customer = "alpha", From = "sender@alpha.example", To = ["private-recipient@example.test"], Subject = "Private subject", Text = "Private message body", IdempotencyKey = "private-key" };
static SendRequest Beta() => Request() with { Customer = "beta", From = "sender@beta.example" };
static CustomerRegistry Registry() => TestData.Registry();
static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
static void Equal<T>(T expected, T actual) { if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new InvalidOperationException($"Expected {expected}; got {actual}."); }
static void Throws<T>(Action action) where T : Exception
{
    try { action(); } catch (T) { return; }
    throw new InvalidOperationException("Expected " + typeof(T).Name);
}

internal static class TestData
{
    internal static CustomerRegistry Registry() => new()
    {
        SchemaVersion = 1,
        ClientId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        Customers =
        [
            new() { Id = "alpha", DisplayName = "Alpha synthetic", TenantId = "11111111-1111-4111-8111-111111111111", ServicePrincipalObjectId = "22222222-2222-4222-8222-222222222222", MailboxObjectId = "33333333-3333-4333-8333-333333333333", SenderMailbox = "sender@alpha.example", Enabled = true, ValidationStatus = "SyntheticOnly" },
            new() { Id = "beta", DisplayName = "Beta synthetic", TenantId = "44444444-4444-4444-8444-444444444444", ServicePrincipalObjectId = "55555555-5555-4555-8555-555555555555", MailboxObjectId = "66666666-6666-4666-8666-666666666666", SenderMailbox = "sender@beta.example", Enabled = true, ValidationStatus = "SyntheticOnly" }
        ]
    };
}

internal sealed class Fixture(string? directory = null)
{
    internal string Directory { get; } = directory ?? Path.Combine(Path.GetTempPath(), "m365scopedmail-synthetic-tests", Guid.NewGuid().ToString("N"));
    internal FileStateStore Store => new(Directory);
    internal SpyTokens Tokens { get; } = new();
    internal SpyTransport Transport { get; } = new();
    internal SpyAudit Audit { get; } = new();
    internal Clock Clock { get; } = new();
    internal List<TimeSpan> Delays { get; } = [];
    internal SendCoordinator Sender(CustomerRegistry? registry = null, IStateStore? store = null, IAuditSink? audit = null) =>
        new(registry ?? TestData.Registry(), Tokens, Transport, store ?? Store, audit ?? Audit, Clock,
            (duration, ct) => { ct.ThrowIfCancellationRequested(); Delays.Add(duration); return Task.CompletedTask; });
}

internal sealed class SpyTokens : ITokenProvider
{
    internal int Calls { get; private set; }
    internal string? ClientId { get; private set; }
    internal CustomerBinding? Customer { get; private set; }
    internal Func<CustomerBinding, CancellationToken, Task<TokenEnvelope>>? Handler { get; set; }
    public Task<TokenEnvelope> AcquireAsync(string clientId, CustomerBinding customer, CancellationToken cancellationToken)
    {
        Calls++; ClientId = clientId; Customer = customer;
        return Handler?.Invoke(customer, cancellationToken) ?? Task.FromResult(new TokenEnvelope(customer.TenantId, "synthetic-secret"));
    }
}

internal sealed class SpyTransport : ISendTransport
{
    internal int Calls { get; private set; }
    internal string? Path { get; private set; }
    internal string? Payload { get; private set; }
    internal Func<CancellationToken, Task<TransportReply>>? Handler { get; set; }
    public Task<TransportReply> SubmitAsync(string userPath, string payloadJson, TokenEnvelope token, CancellationToken cancellationToken)
    {
        Calls++; Path = userPath; Payload = payloadJson;
        return Handler?.Invoke(cancellationToken) ?? Task.FromResult(new TransportReply(TransportDisposition.Accepted));
    }
}

internal sealed class SpyAudit : IAuditSink
{
    internal bool Fail { get; set; }
    public Task WriteAsync(SendResult result, CancellationToken cancellationToken)
    {
        if (Fail) throw new IOException("Private audit failure");
        return Task.CompletedTask;
    }
}

internal sealed class Clock : TimeProvider
{
    internal DateTimeOffset Now { get; set; } = new(2026, 10, 1, 0, 0, 0, TimeSpan.Zero);
    public override DateTimeOffset GetUtcNow() => Now;
}

internal sealed class FailingStore(IStateStore inner, int failAt) : IStateStore
{
    public async Task<IStateLease> AcquireAsync(CancellationToken cancellationToken) => new Lease(await inner.AcquireAsync(cancellationToken), failAt);
    private sealed class Lease(IStateLease innerLease, int failAt) : IStateLease
    {
        private int saves;
        public SendState State => innerLease.State;
        public Task SaveAsync() => ++saves == failAt ? throw new IOException("Synthetic write fault.") : innerLease.SaveAsync();
        public ValueTask DisposeAsync() => innerLease.DisposeAsync();
    }
}
