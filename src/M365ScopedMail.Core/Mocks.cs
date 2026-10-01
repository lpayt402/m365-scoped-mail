namespace M365ScopedMail.Core;

public enum MockScenario { Accepted, TokenFailure, AuthorizationDenied, ThrottleOnce, Uncertain }

public sealed class MockTokenProvider(MockScenario scenario) : ITokenProvider
{
    public Task<TokenEnvelope> AcquireAsync(string clientId, CustomerBinding customer, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (scenario == MockScenario.TokenFailure) throw new InvalidOperationException("Synthetic token failure.");
        return Task.FromResult(new TokenEnvelope(customer.TenantId, "synthetic-token-no-credentials"));
    }
}

public sealed class MockSendTransport(MockScenario scenario) : ISendTransport
{
    private int calls;
    public Task<TransportReply> SubmitAsync(string userPath, string payloadJson, TokenEnvelope token, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        calls++;
        return Task.FromResult(new TransportReply(scenario switch
        {
            MockScenario.AuthorizationDenied => TransportDisposition.AuthorizationDenied,
            MockScenario.ThrottleOnce when calls == 1 => TransportDisposition.Throttled,
            MockScenario.Uncertain => TransportDisposition.Uncertain,
            _ => TransportDisposition.Accepted
        }));
    }
}
