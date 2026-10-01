using System.Text.Json;

namespace M365ScopedMail.Core;

public sealed class SendState
{
    public required int SchemaVersion { get; init; }
    public required Dictionary<string, SubmissionState> Submissions { get; init; }
    public required Dictionary<string, CustomerState> Customers { get; init; }
    public static SendState Empty() => new() { SchemaVersion = 1, Submissions = [], Customers = [] };
}

public sealed class SubmissionState
{
    public required string Fingerprint { get; init; }
    public required string Customer { get; init; }
    public required string Status { get; set; }
    public required string EventId { get; init; }
}

public sealed class CustomerState
{
    public required List<DateTimeOffset> Attempts { get; init; }
    public required int AuthorizationFailures { get; set; }
    public required DateTimeOffset? CircuitUntil { get; set; }
}

public interface IStateLease : IAsyncDisposable
{
    SendState State { get; }
    Task SaveAsync();
}

public interface IStateStore
{
    Task<IStateLease> AcquireAsync(CancellationToken cancellationToken);
}

public sealed class FileStateStore(string directory) : IStateStore
{
    public async Task<IStateLease> AcquireAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var fullDirectory = Path.GetFullPath(directory);
        Directory.CreateDirectory(fullDirectory);
        var statePath = Path.Combine(fullDirectory, "state.json");
        // Never wait for another invocation: lock contention fails closed.
        var handle = new FileStream(Path.Combine(fullDirectory, "state.lock"), FileMode.OpenOrCreate,
            FileAccess.ReadWrite, FileShare.None);
        try
        {
            SendState state;
            if (File.Exists(statePath))
            {
                if (new FileInfo(statePath).Length > 8388608) throw new InvalidDataException("State too large.");
                state = StrictJson.Read<SendState>(await File.ReadAllTextAsync(statePath, cancellationToken));
                Validate(state);
            }
            else state = SendState.Empty();
            return new FileLease(handle, statePath, state);
        }
        catch { await handle.DisposeAsync(); throw; }
    }

    private static void Validate(SendState state)
    {
        if (state.SchemaVersion != 1 || state.Submissions is null || state.Customers is null ||
            state.Submissions.Count > 10000 || state.Customers.Count > 1000)
            throw new InvalidDataException("Invalid state.");
        foreach (var (key, entry) in state.Submissions)
            if (!HexHash(key) || entry is null || !HexHash(entry.Fingerprint) || !InputValidation.ValidId(entry.Customer) ||
                !InputValidation.ValidGuid(entry.EventId) || entry.Status is not ("Pending" or "Accepted" or "Retryable" or "Uncertain" or "Rejected"))
                throw new InvalidDataException("Invalid submission state.");
        foreach (var (key, entry) in state.Customers)
            if (!InputValidation.ValidId(key) || entry is null || entry.Attempts is null || entry.Attempts.Count > 5 ||
                entry.AuthorizationFailures is < 0 or > 2)
                throw new InvalidDataException("Invalid customer state.");
        foreach (var entry in state.Submissions.Values)
            if (!state.Customers.ContainsKey(entry.Customer)) throw new InvalidDataException("Missing customer state.");
    }

    private static bool HexHash(string? value) => value is { Length: 64 } && value.All(c => c is >= '0' and <= '9' or >= 'A' and <= 'F');

    private sealed class FileLease(FileStream handle, string path, SendState state) : IStateLease
    {
        public SendState State { get; } = state;
        public async Task SaveAsync()
        {
            var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                await using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                    4096, FileOptions.WriteThrough))
                {
                    await JsonSerializer.SerializeAsync(file, State, StrictJson.Options);
                    await file.FlushAsync();
                    file.Flush(flushToDisk: true);
                }
                File.Move(temporary, path, overwrite: true);
            }
            finally { if (File.Exists(temporary)) File.Delete(temporary); }
        }
        public ValueTask DisposeAsync() => handle.DisposeAsync();
    }
}

public sealed class JsonLineAuditSink(string directory) : IAuditSink
{
    public Task WriteAsync(SendResult result, CancellationToken cancellationToken) =>
        File.AppendAllTextAsync(Path.Combine(Path.GetFullPath(directory), "audit.jsonl"),
            JsonSerializer.Serialize(result, StrictJson.Options) + Environment.NewLine, cancellationToken);
}
