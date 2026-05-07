public sealed class RelayDbInitializer : IHostedService
{
    private readonly RelayDb _db;

    public RelayDbInitializer(RelayDb db)
    {
        _db = db;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        return _db.InitializeAsync(cancellationToken);
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
