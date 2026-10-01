using System.Text.Json;
using M365ScopedMail.Core;

return await RunAsync(args);

static async Task<int> RunAsync(string[] arguments)
{
    if (arguments is [] or ["help"] or ["--help"] or ["-h"])
    {
        Console.WriteLine("M365ScopedMail — local mock simulation; no network or credentials.");
        Console.WriteLine("simulate --config <json> --request <json> --state <directory> [--scenario accepted|token-failure|authorization-denied|throttle-once|uncertain]");
        return 0;
    }
    try
    {
        if (arguments[0] != "simulate") throw new ValidationException("UnsupportedMode");
        var options = new Dictionary<string, string>(StringComparer.Ordinal);
        for (var i = 1; i < arguments.Length; i += 2)
        {
            if (i + 1 >= arguments.Length || arguments[i] is not ("--config" or "--request" or "--state" or "--scenario") ||
                string.IsNullOrWhiteSpace(arguments[i + 1]) || !options.TryAdd(arguments[i], arguments[i + 1]))
                throw new ValidationException("InvalidArguments");
        }
        if (!options.ContainsKey("--config") || !options.ContainsKey("--request") || !options.ContainsKey("--state"))
            throw new ValidationException("InvalidArguments");
        var scenario = options.GetValueOrDefault("--scenario", "accepted") switch
        {
            "accepted" => MockScenario.Accepted,
            "token-failure" => MockScenario.TokenFailure,
            "authorization-denied" => MockScenario.AuthorizationDenied,
            "throttle-once" => MockScenario.ThrottleOnce,
            "uncertain" => MockScenario.Uncertain,
            _ => throw new ValidationException("InvalidScenario")
        };
        var registry = StrictJson.Read<CustomerRegistry>(await ReadBoundedAsync(options["--config"], 1048576));
        var request = StrictJson.Read<SendRequest>(await ReadBoundedAsync(options["--request"], 2097152));
        var sender = new SendCoordinator(registry, new MockTokenProvider(scenario), new MockSendTransport(scenario),
            new FileStateStore(options["--state"]), new JsonLineAuditSink(options["--state"]));
        using var cancellation = new CancellationTokenSource();
        ConsoleCancelEventHandler cancel = (_, eventArgs) => { eventArgs.Cancel = true; cancellation.Cancel(); };
        Console.CancelKeyPress += cancel;
        SendResult result;
        try { result = await sender.SendAsync(request, cancellation.Token); }
        finally { Console.CancelKeyPress -= cancel; }
        Console.WriteLine(JsonSerializer.Serialize(result, StrictJson.Options));
        return result.Status is "MockAccepted" or "DuplicateSuppressed" ? 0 : 2;
    }
    catch (ValidationException ex) { return Reject(ex.Category); }
    catch (JsonException) { return Reject("InvalidJson"); }
    catch { return Reject("InputOrStateFailure"); }
}

static async Task<string> ReadBoundedAsync(string path, int limit)
{
    await using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
    if (file.Length > limit) throw new ValidationException("InputTooLarge");
    using var reader = new StreamReader(file, System.Text.Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
    var text = await reader.ReadToEndAsync();
    if (System.Text.Encoding.UTF8.GetByteCount(text) > limit) throw new ValidationException("InputTooLarge");
    return text;
}

static int Reject(string category)
{
    Console.WriteLine(JsonSerializer.Serialize(new SendResult("Mock", "Rejected", Guid.NewGuid().ToString("D"),
        null, null, null, 0, 0, category, TimeProvider.System.GetUtcNow()), StrictJson.Options));
    return 2;
}
