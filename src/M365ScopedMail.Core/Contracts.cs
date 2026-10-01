using System.Text.Json;
using System.Text.Json.Serialization;

namespace M365ScopedMail.Core;

public sealed record CustomerRegistry
{
    public required int SchemaVersion { get; init; }
    public required string ClientId { get; init; }
    public required CustomerBinding[] Customers { get; init; }
}

public sealed record CustomerBinding
{
    public required string Id { get; init; }
    public required string DisplayName { get; init; }
    public required string TenantId { get; init; }
    public required string ServicePrincipalObjectId { get; init; }
    public required string MailboxObjectId { get; init; }
    public required string SenderMailbox { get; init; }
    public required bool Enabled { get; init; }
    public required string ValidationStatus { get; init; }
}

public sealed record SendRequest
{
    public required string Customer { get; init; }
    public required string From { get; init; }
    public required string[] To { get; init; }
    public required string Subject { get; init; }
    public required string Text { get; init; }
    public required string IdempotencyKey { get; init; }
    public PdfAttachment? Attachment { get; init; }
}

public sealed record PdfAttachment
{
    public required string Name { get; init; }
    public required string ContentBase64 { get; init; }
}

public static class StrictJson
{
    public static JsonSerializerOptions Options { get; } = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        PropertyNameCaseInsensitive = false,
        MaxDepth = 16
    };

    public static T Read<T>(string json)
    {
        // Reject duplicate properties as well as unknown properties; accepting the last
        // value would make review of customer bindings ambiguous.
        using var document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 16 });
        RejectDuplicates(document.RootElement);
        return JsonSerializer.Deserialize<T>(json, Options) ?? throw new JsonException("Null document.");
    }

    private static void RejectDuplicates(JsonElement element)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in element.EnumerateObject())
            {
                if (!names.Add(property.Name)) throw new JsonException("Duplicate property.");
                RejectDuplicates(property.Value);
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
            foreach (var child in element.EnumerateArray()) RejectDuplicates(child);
    }
}

public sealed record TokenEnvelope(string TenantId, string OpaqueValue);
public enum TransportDisposition { Accepted, AuthorizationDenied, Throttled, Uncertain }
public sealed record TransportReply(TransportDisposition Disposition);

public interface ITokenProvider
{
    Task<TokenEnvelope> AcquireAsync(string clientId, CustomerBinding customer, CancellationToken cancellationToken);
}

public interface ISendTransport
{
    Task<TransportReply> SubmitAsync(string userPath, string payloadJson, TokenEnvelope token, CancellationToken cancellationToken);
}

public interface IAuditSink
{
    Task WriteAsync(SendResult result, CancellationToken cancellationToken);
}

public sealed record SendResult(string Mode, string Status, string EventId, string? Customer,
    string? TenantId, string? SenderMailbox, int RecipientCount, int Attempts,
    string? ErrorCategory, DateTimeOffset TimestampUtc, bool SecurityModelProven = false);

public sealed class ValidationException(string category) : Exception(category)
{
    public string Category { get; } = category;
}
