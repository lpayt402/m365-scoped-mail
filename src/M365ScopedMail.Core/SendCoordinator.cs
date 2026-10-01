using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace M365ScopedMail.Core;

// This coordinator is a bounded local simulation. The injected token envelope is
// checked for routing consistency; that check does not validate a real OAuth token.
public sealed class SendCoordinator
{
    private readonly CustomerRegistry registry;
    private readonly ITokenProvider tokens;
    private readonly ISendTransport transport;
    private readonly IStateStore stateStore;
    private readonly IAuditSink audit;
    private readonly TimeProvider time;
    private readonly Func<TimeSpan, CancellationToken, Task> delay;
    private readonly Func<string> eventIds;

    public SendCoordinator(CustomerRegistry registry, ITokenProvider tokens, ISendTransport transport,
        IStateStore stateStore, IAuditSink audit, TimeProvider? time = null,
        Func<TimeSpan, CancellationToken, Task>? delay = null, Func<string>? eventIds = null)
    {
        // Snapshot mutable array storage before validating or crossing an await.
        this.registry = registry with { Customers = registry.Customers?.ToArray()! };
        InputValidation.Registry(this.registry);
        this.tokens = tokens;
        this.transport = transport;
        this.stateStore = stateStore;
        this.audit = audit;
        this.time = time ?? TimeProvider.System;
        this.delay = delay ?? ((duration, ct) => Task.Delay(duration, this.time, ct));
        this.eventIds = eventIds ?? (() => Guid.NewGuid().ToString("D"));
    }

    public async Task<SendResult> SendAsync(SendRequest request, CancellationToken cancellationToken = default)
    {
        var eventId = eventIds();
        request = request with { To = request.To?.ToArray()! };
        CustomerBinding customer;
        try { customer = InputValidation.Resolve(registry, request); }
        catch (ValidationException ex) { return Result("Rejected", eventId, null, 0, 0, ex.Category); }
        var attempts = 0;
        SendResult Finish(string status, string? error = null) => Result(status, eventId, customer, request.To.Length, attempts, error);
        IStateLease lease;
        try { lease = await stateStore.AcquireAsync(cancellationToken); }
        catch (OperationCanceledException) { return Finish("Rejected", "CanceledBeforeSubmission"); }
        catch { return Finish("Rejected", "StateUnavailable"); }
        await using (lease)
        {
            var state = lease.State;
            var key = Hash(request.Customer + "\n" + request.IdempotencyKey);
            var fingerprint = Hash(JsonSerializer.Serialize(new { registry.ClientId, customer, request }, StrictJson.Options));
            if (state.Submissions.TryGetValue(key, out var existing))
            {
                if (existing.Fingerprint != fingerprint) return await AuditAsync(Finish("Rejected", "IdempotencyConflict"));
                eventId = existing.EventId;
                if (existing.Status == "Accepted") return await AuditAsync(Finish("DuplicateSuppressed"));
                if (existing.Status is "Pending" or "Uncertain") return await AuditAsync(Finish("Uncertain", "ManualReviewRequired"));
                if (existing.Status == "Rejected") return await AuditAsync(Finish("Rejected", "PriorRejection"));
            }
            var now = time.GetUtcNow();
            if (!state.Customers.TryGetValue(customer.Id, out var customerState))
            {
                if (state.Customers.Count >= 1000) return Finish("Rejected", "StateCapacity");
                customerState = new CustomerState { Attempts = [], AuthorizationFailures = 0, CircuitUntil = null };
                state.Customers.Add(customer.Id, customerState);
            }
            if (customerState.CircuitUntil > now) return await AuditAsync(Finish("Rejected", "CircuitOpen"));
            if (customerState.CircuitUntil is not null)
            {
                customerState.CircuitUntil = null;
                customerState.AuthorizationFailures = 0;
            }
            customerState.Attempts.RemoveAll(stamp => stamp <= now.AddMinutes(-1));
            if (customerState.Attempts.Count >= 5) return await AuditAsync(Finish("Rejected", "RateLimited"));
            if (existing is null)
            {
                if (state.Submissions.Count >= 10000) return Finish("Rejected", "StateCapacity");
                existing = new SubmissionState { Customer = customer.Id, EventId = eventId, Fingerprint = fingerprint, Status = "Retryable" };
                state.Submissions.Add(key, existing);
            }
            try { await lease.SaveAsync(); }
            catch { return Finish("Rejected", "StateUnavailable"); }
            TokenEnvelope token;
            try { token = await tokens.AcquireAsync(registry.ClientId, customer, cancellationToken); }
            catch (OperationCanceledException) { return await AuditAsync(Finish("Rejected", "CanceledBeforeSubmission")); }
            catch { return await AuditAsync(Finish("Rejected", "TokenFailure")); }
            if (token is null || !InputValidation.ValidGuid(token.TenantId) ||
                Guid.Parse(token.TenantId) != Guid.Parse(customer.TenantId) || string.IsNullOrEmpty(token.OpaqueValue))
            {
                existing.Status = "Rejected";
                try { await lease.SaveAsync(); }
                catch { return Finish("Rejected", "StateUnavailable"); }
                return await AuditAsync(Finish("Rejected", "TokenTenantMismatch"));
            }
            for (var retry = 0; retry < 2; retry++)
            {
                if (cancellationToken.IsCancellationRequested) return await AuditAsync(Finish("Rejected", "CanceledBeforeSubmission"));
                now = time.GetUtcNow();
                customerState.Attempts.RemoveAll(stamp => stamp <= now.AddMinutes(-1));
                if (customerState.Attempts.Count >= 5) return await AuditAsync(Finish("Rejected", "RateLimited"));
                customerState.Attempts.Add(now);
                existing.Status = "Pending";
                try { await lease.SaveAsync(); }
                catch { return Finish("Rejected", "StateUnavailable"); }
                attempts++;
                TransportReply reply;
                try
                {
                    reply = await transport.SubmitAsync("/v1.0/users/" + customer.MailboxObjectId + "/sendMail",
                        GraphPayload.Build(request), token, cancellationToken);
                }
                catch { reply = new TransportReply(TransportDisposition.Uncertain); }
                var status = "Uncertain";
                string? error = "ManualReviewRequired";
                switch (reply?.Disposition)
                {
                    case TransportDisposition.Accepted:
                        existing.Status = "Accepted";
                        customerState.AuthorizationFailures = 0;
                        status = "MockAccepted";
                        error = null;
                        break;
                    case TransportDisposition.AuthorizationDenied:
                        existing.Status = "Rejected";
                        customerState.AuthorizationFailures = Math.Min(2, customerState.AuthorizationFailures + 1);
                        if (customerState.AuthorizationFailures >= 2) customerState.CircuitUntil = now.AddMinutes(5);
                        status = "Rejected";
                        error = "AuthorizationDenied";
                        break;
                    case TransportDisposition.Throttled:
                        existing.Status = "Retryable";
                        status = "Rejected";
                        error = "Throttled";
                        break;
                    default: existing.Status = "Uncertain"; break;
                }
                try { await lease.SaveAsync(); }
                catch { return Finish(status == "MockAccepted" ? "MockAcceptedStateFailure" : "Uncertain", "StatePersistenceFailure"); }
                if (reply?.Disposition == TransportDisposition.Throttled && retry == 0)
                {
                    try { await delay(TimeSpan.FromMilliseconds(250), cancellationToken); }
                    catch (OperationCanceledException) { return await AuditAsync(Finish("Rejected", "CanceledBeforeSubmission")); }
                    catch { return await AuditAsync(Finish("Rejected", "RetryDelayFailure")); }
                    continue;
                }
                return await AuditAsync(Finish(status, error));
            }
            throw new InvalidOperationException("Unreachable retry state.");
        }
    }

    private async Task<SendResult> AuditAsync(SendResult result)
    {
        try { await audit.WriteAsync(result, CancellationToken.None); return result; }
        catch { return result with { Status = result.Status == "MockAccepted" ? "MockAcceptedAuditFailed" : result.Status, ErrorCategory = "AuditFailure" }; }
    }

    private SendResult Result(string status, string eventId, CustomerBinding? customer, int recipients, int attempts, string? error) =>
        new("Mock", status, eventId, customer?.Id, customer?.TenantId, customer?.SenderMailbox, recipients, attempts, error,
            time.GetUtcNow().ToUniversalTime());
    private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
}
