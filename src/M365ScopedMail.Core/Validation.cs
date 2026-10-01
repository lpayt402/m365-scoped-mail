using System.Net.Mail;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace M365ScopedMail.Core;

public static partial class InputValidation
{
    public static void Registry(CustomerRegistry registry)
    {
        if (registry.SchemaVersion != 1 || !ValidGuid(registry.ClientId) || registry.Customers is not { Length: > 0 and <= 1000 })
            throw new ValidationException("InvalidRegistry");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        var tenants = new HashSet<Guid>();
        foreach (var customer in registry.Customers)
        {
            if (customer is null || !ValidId(customer.Id) || !ids.Add(customer.Id) ||
                !ValidGuid(customer.TenantId) || !tenants.Add(Guid.Parse(customer.TenantId)) ||
                !ValidGuid(customer.ServicePrincipalObjectId) || !ValidGuid(customer.MailboxObjectId) ||
                !Address(customer.SenderMailbox) || string.IsNullOrWhiteSpace(customer.DisplayName) ||
                customer.DisplayName.Length > 120 || customer.ValidationStatus != "SyntheticOnly")
                throw new ValidationException("InvalidRegistry");
        }
    }

    public static CustomerBinding Resolve(CustomerRegistry registry, SendRequest request)
    {
        if (!ValidId(request.Customer)) throw new ValidationException("InvalidCustomer");
        var customer = registry.Customers.SingleOrDefault(x => x.Id == request.Customer)
            ?? throw new ValidationException("UnknownCustomer");
        if (!customer.Enabled) throw new ValidationException("DisabledCustomer");
        if (customer.ValidationStatus != "SyntheticOnly") throw new ValidationException("UnvalidatedCustomer");
        if (!Address(request.From) || !request.From.Equals(customer.SenderMailbox, StringComparison.OrdinalIgnoreCase))
            throw new ValidationException("SenderMismatch");
        if (request.To is not { Length: > 0 and <= 10 } || request.To.Any(x => !Address(x)) ||
            request.To.Distinct(StringComparer.OrdinalIgnoreCase).Count() != request.To.Length)
            throw new ValidationException("InvalidRecipients");
        if (string.IsNullOrWhiteSpace(request.Subject) || request.Subject.Length > 200 || request.Subject.Any(char.IsControl) ||
            string.IsNullOrWhiteSpace(request.Text) || Encoding.UTF8.GetByteCount(request.Text) > 65536 ||
            request.Text.Any(c => char.IsControl(c) && c is not '\r' and not '\n' and not '\t') ||
            string.IsNullOrWhiteSpace(request.IdempotencyKey) || request.IdempotencyKey.Length > 128 ||
            request.IdempotencyKey.Any(char.IsControl)) throw new ValidationException("InvalidPayload");
        if (request.Attachment is { } attachment)
        {
            if (string.IsNullOrWhiteSpace(attachment.Name) || attachment.Name.Length > 120 ||
                !PdfName().IsMatch(attachment.Name) || attachment.Name.Contains("..", StringComparison.Ordinal) ||
                attachment.ContentBase64 is null || attachment.ContentBase64.Length > 1398104)
                throw new ValidationException("InvalidAttachment");
            byte[] content;
            try { content = Convert.FromBase64String(attachment.ContentBase64); }
            catch (FormatException) { throw new ValidationException("InvalidAttachment"); }
            if (content.Length is < 5 or > 1048576 || !content.AsSpan(0, 5).SequenceEqual("%PDF-"u8))
                throw new ValidationException("InvalidAttachment");
        }
        return customer;
    }

    public static bool ValidGuid(string? value) => value is not null && Guid.TryParseExact(value, "D", out var id) && id != Guid.Empty;
    public static bool ValidId(string? value) => value is not null && CustomerId().IsMatch(value);
    public static bool Address(string? value)
    {
        if (value is null || value.Length > 254 || !OrdinaryAddress().IsMatch(value)) return false;
        var localPart = value.AsSpan(0, value.IndexOf('@'));
        if (localPart.Length > 64 || localPart[^1] == '.' || localPart.Contains("..", StringComparison.Ordinal)) return false;
        return MailAddress.TryCreate(value, out var parsed) && parsed.Address == value && parsed.DisplayName.Length == 0;
    }

    [GeneratedRegex("^[a-z0-9][a-z0-9_-]{0,63}$", RegexOptions.CultureInvariant)]
    private static partial Regex CustomerId();
    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9._%+\\-]*@[A-Za-z0-9](?:[A-Za-z0-9\\-]*[A-Za-z0-9])?(?:\\.[A-Za-z0-9](?:[A-Za-z0-9\\-]*[A-Za-z0-9])?)+$", RegexOptions.CultureInvariant)]
    private static partial Regex OrdinaryAddress();
    [GeneratedRegex("^[A-Za-z0-9][A-Za-z0-9 _().-]*\\.pdf$", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant)]
    private static partial Regex PdfName();
}

public static class GraphPayload
{
    public static string Build(SendRequest request)
    {
        var message = new Dictionary<string, object>
        {
            ["subject"] = request.Subject,
            ["body"] = new { contentType = "Text", content = request.Text },
            ["from"] = new { emailAddress = new { address = request.From } },
            ["toRecipients"] = request.To.Select(address => new { emailAddress = new { address } }).ToArray()
        };
        if (request.Attachment is { } attachment)
            message["attachments"] = new[] { new Dictionary<string, object>
            {
                ["@odata.type"] = "#microsoft.graph.fileAttachment",
                ["name"] = attachment.Name,
                ["contentType"] = "application/pdf",
                ["contentBytes"] = attachment.ContentBase64
            } };
        return JsonSerializer.Serialize(new { message, saveToSentItems = true });
    }
}
