using System.Text.Json;
using M365ScopedMail.Core;

if (args.Length != 1)
{
    Console.Error.WriteLine("Usage: M365ScopedMail.Integration <repository-folder>. Local mocks only.");
    return 2;
}

var root = Path.GetFullPath(args[0]);
var registry = StrictJson.Read<CustomerRegistry>(
    await File.ReadAllTextAsync(Path.Combine(root, "examples", "customers.mock.json")));
var request = StrictJson.Read<SendRequest>(
    await File.ReadAllTextAsync(Path.Combine(root, "examples", "basic-send", "request.json")));
var state = Path.Combine(Path.GetTempPath(), "m365scopedmail-integration-" + Guid.NewGuid().ToString("N"));
var sender = new SendCoordinator(registry,
    new MockTokenProvider(MockScenario.Accepted), new MockSendTransport(MockScenario.Accepted),
    new FileStateStore(state), new JsonLineAuditSink(state));

var first = await sender.SendAsync(request);
var repeated = await sender.SendAsync(request);
Console.WriteLine(JsonSerializer.Serialize(first, StrictJson.Options));
Console.WriteLine(JsonSerializer.Serialize(repeated, StrictJson.Options));
return first.Status == "MockAccepted" && repeated.Status == "DuplicateSuppressed" ? 0 : 2;
