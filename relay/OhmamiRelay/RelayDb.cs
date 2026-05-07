using Npgsql;

public sealed class RelayDb
{
    private readonly NpgsqlDataSource _dataSource;
    private readonly RelayOptions _options;

    public RelayDb(NpgsqlDataSource dataSource, RelayOptions options)
    {
        _dataSource = dataSource;
        _options = options;
    }

    public async Task InitializeAsync(CancellationToken ct)
    {
        const string sql = """
        create table if not exists mobile_devices (
            id uuid primary key,
            device_id text not null unique,
            device_name text not null,
            token_hash text not null,
            created_at timestamptz not null,
            last_seen_at timestamptz not null
        );

        create table if not exists agents (
            id uuid primary key,
            agent_id text not null unique,
            name text not null,
            created_at timestamptz not null,
            last_seen_at timestamptz not null
        );

        create table if not exists pairings (
            id uuid primary key,
            mobile_device_id uuid not null references mobile_devices(id) on delete cascade,
            agent_db_id uuid not null references agents(id) on delete cascade,
            created_at timestamptz not null,
            revoked_at timestamptz null,
            unique (mobile_device_id, agent_db_id)
        );

        create table if not exists pairing_codes (
            id uuid primary key,
            agent_db_id uuid not null references agents(id) on delete cascade,
            code text not null unique,
            created_at timestamptz not null,
            expires_at timestamptz not null,
            used_at timestamptz null
        );
        """;

        await using var connection = await _dataSource.OpenConnectionAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        await command.ExecuteNonQueryAsync(ct);
    }

    public async Task UpsertAgentAsync(string agentId, string name, CancellationToken ct)
    {
        const string sql = """
        insert into agents (id, agent_id, name, created_at, last_seen_at)
        values (@id, @agentId, @name, now(), now())
        on conflict (agent_id)
        do update set name = excluded.name, last_seen_at = now();
        """;

        await using var connection = await _dataSource.OpenConnectionAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", Guid.NewGuid());
        command.Parameters.AddWithValue("agentId", agentId);
        command.Parameters.AddWithValue("name", name);
        await command.ExecuteNonQueryAsync(ct);
    }

    public async Task<bool> AgentExistsAsync(string agentId, CancellationToken ct)
    {
        const string sql = "select exists(select 1 from agents where agent_id = @agentId);";
        await using var connection = await _dataSource.OpenConnectionAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("agentId", agentId);
        return (bool)(await command.ExecuteScalarAsync(ct) ?? false);
    }

    public async Task<(string AccessToken, MobileDeviceAuth Device)> RegisterMobileDeviceAsync(
        string deviceId,
        string? deviceName,
        CancellationToken ct)
    {
        var token = SecurityHelpers.GenerateToken();
        var tokenHash = SecurityHelpers.HashToken(token);
        var resolvedName = string.IsNullOrWhiteSpace(deviceName) ? "Mobile device" : deviceName.Trim();

        const string sql = """
        insert into mobile_devices (id, device_id, device_name, token_hash, created_at, last_seen_at)
        values (@id, @deviceId, @deviceName, @tokenHash, now(), now())
        on conflict (device_id)
        do update set device_name = excluded.device_name, token_hash = excluded.token_hash, last_seen_at = now()
        returning id, device_id, device_name;
        """;

        await using var connection = await _dataSource.OpenConnectionAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", Guid.NewGuid());
        command.Parameters.AddWithValue("deviceId", deviceId);
        command.Parameters.AddWithValue("deviceName", resolvedName);
        command.Parameters.AddWithValue("tokenHash", tokenHash);

        await using var reader = await command.ExecuteReaderAsync(ct);
        await reader.ReadAsync(ct);
        var device = new MobileDeviceAuth(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2));

        return (token, device);
    }

    public async Task<MobileDeviceAuth?> AuthenticateMobileDeviceAsync(string deviceId, string accessToken, CancellationToken ct)
    {
        const string sql = """
        select id, device_id, device_name, token_hash
        from mobile_devices
        where device_id = @deviceId;
        """;

        await using var connection = await _dataSource.OpenConnectionAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("deviceId", deviceId);

        await using var reader = await command.ExecuteReaderAsync(ct);
        if (!await reader.ReadAsync(ct))
        {
            return null;
        }

        var hash = reader.GetString(3);
        if (!string.Equals(hash, SecurityHelpers.HashToken(accessToken), StringComparison.Ordinal))
        {
            return null;
        }

        var device = new MobileDeviceAuth(
            reader.GetGuid(0),
            reader.GetString(1),
            reader.GetString(2));

        await reader.CloseAsync();

        const string updateSql = "update mobile_devices set last_seen_at = now() where id = @id;";
        await using var update = new NpgsqlCommand(updateSql, connection);
        update.Parameters.AddWithValue("id", device.Id);
        await update.ExecuteNonQueryAsync(ct);

        return device;
    }

    public async Task<CreatePairingCodeResponse> CreatePairingCodeAsync(string agentId, CancellationToken ct)
    {
        const string findSql = "select id from agents where agent_id = @agentId;";
        await using var connection = await _dataSource.OpenConnectionAsync(ct);
        await using var find = new NpgsqlCommand(findSql, connection);
        find.Parameters.AddWithValue("agentId", agentId);
        var agentDbIdObj = await find.ExecuteScalarAsync(ct);
        if (agentDbIdObj is not Guid agentDbId)
        {
            throw new InvalidOperationException($"Agent '{agentId}' is not registered");
        }

        var code = SecurityHelpers.GeneratePairingCode();
        var expiresAt = DateTimeOffset.UtcNow.AddMinutes(Math.Max(1, _options.PairingCodeTtlMinutes));

        const string sql = """
        insert into pairing_codes (id, agent_db_id, code, created_at, expires_at, used_at)
        values (@id, @agentDbId, @code, now(), @expiresAt, null);
        """;
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("id", Guid.NewGuid());
        command.Parameters.AddWithValue("agentDbId", agentDbId);
        command.Parameters.AddWithValue("code", code);
        command.Parameters.AddWithValue("expiresAt", expiresAt.UtcDateTime);
        await command.ExecuteNonQueryAsync(ct);

        return new CreatePairingCodeResponse(code, expiresAt);
    }

    public async Task<AccessibleAgent?> PairMobileDeviceAsync(Guid mobileDeviceId, string code, Func<string, bool> isOnline, CancellationToken ct)
    {
        await using var connection = await _dataSource.OpenConnectionAsync(ct);
        await using var tx = await connection.BeginTransactionAsync(ct);

        const string consumeSql = """
        update pairing_codes pc
        set used_at = now()
        where pc.code = @code
          and pc.used_at is null
          and pc.expires_at > now()
        returning pc.agent_db_id;
        """;

        await using var consume = new NpgsqlCommand(consumeSql, connection, tx);
        consume.Parameters.AddWithValue("code", code);
        var agentDbIdObj = await consume.ExecuteScalarAsync(ct);
        if (agentDbIdObj is not Guid agentDbId)
        {
            await tx.RollbackAsync(ct);
            return null;
        }

        const string pairSql = """
        insert into pairings (id, mobile_device_id, agent_db_id, created_at, revoked_at)
        values (@id, @mobileDeviceId, @agentDbId, now(), null)
        on conflict (mobile_device_id, agent_db_id)
        do update set revoked_at = null;
        """;

        await using var pair = new NpgsqlCommand(pairSql, connection, tx);
        pair.Parameters.AddWithValue("id", Guid.NewGuid());
        pair.Parameters.AddWithValue("mobileDeviceId", mobileDeviceId);
        pair.Parameters.AddWithValue("agentDbId", agentDbId);
        await pair.ExecuteNonQueryAsync(ct);

        const string agentSql = """
        select a.agent_id, a.name, a.last_seen_at, p.created_at
        from agents a
        join pairings p on p.agent_db_id = a.id
        where a.id = @agentDbId and p.mobile_device_id = @mobileDeviceId and p.revoked_at is null;
        """;

        await using var agentCommand = new NpgsqlCommand(agentSql, connection, tx);
        agentCommand.Parameters.AddWithValue("agentDbId", agentDbId);
        agentCommand.Parameters.AddWithValue("mobileDeviceId", mobileDeviceId);
        await using var reader = await agentCommand.ExecuteReaderAsync(ct);
        await reader.ReadAsync(ct);
        var agentId = reader.GetString(0);
        var result = new AccessibleAgent(
            agentId,
            reader.GetString(1),
            isOnline(agentId),
            new DateTimeOffset(DateTime.SpecifyKind(reader.GetFieldValue<DateTime>(2), DateTimeKind.Utc)),
            new DateTimeOffset(DateTime.SpecifyKind(reader.GetFieldValue<DateTime>(3), DateTimeKind.Utc)));
        await reader.CloseAsync();

        await tx.CommitAsync(ct);
        return result;
    }

    public async Task<IReadOnlyList<AccessibleAgent>> GetAgentsForMobileDeviceAsync(Guid mobileDeviceId, Func<string, bool> isOnline, CancellationToken ct)
    {
        const string sql = """
        select a.agent_id, a.name, a.last_seen_at, p.created_at
        from pairings p
        join agents a on a.id = p.agent_db_id
        where p.mobile_device_id = @mobileDeviceId
          and p.revoked_at is null
        order by a.name, a.agent_id;
        """;

        var results = new List<AccessibleAgent>();

        await using var connection = await _dataSource.OpenConnectionAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("mobileDeviceId", mobileDeviceId);
        await using var reader = await command.ExecuteReaderAsync(ct);

        while (await reader.ReadAsync(ct))
        {
            var agentId = reader.GetString(0);
            results.Add(new AccessibleAgent(
                agentId,
                reader.GetString(1),
                isOnline(agentId),
                new DateTimeOffset(DateTime.SpecifyKind(reader.GetFieldValue<DateTime>(2), DateTimeKind.Utc)),
                new DateTimeOffset(DateTime.SpecifyKind(reader.GetFieldValue<DateTime>(3), DateTimeKind.Utc))));
        }

        return results;
    }

    public async Task<bool> HasPairingAsync(Guid mobileDeviceId, string agentId, CancellationToken ct)
    {
        const string sql = """
        select exists(
            select 1
            from pairings p
            join agents a on a.id = p.agent_db_id
            where p.mobile_device_id = @mobileDeviceId
              and a.agent_id = @agentId
              and p.revoked_at is null
        );
        """;

        await using var connection = await _dataSource.OpenConnectionAsync(ct);
        await using var command = new NpgsqlCommand(sql, connection);
        command.Parameters.AddWithValue("mobileDeviceId", mobileDeviceId);
        command.Parameters.AddWithValue("agentId", agentId);
        return (bool)(await command.ExecuteScalarAsync(ct) ?? false);
    }
}
