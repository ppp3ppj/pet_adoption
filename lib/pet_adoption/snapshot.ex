defmodule PetAdoption.Snapshot do
  @moduledoc """
  Periodically saves CRDT state to SQLite database for persistence.

  Features:
  - Incremental saves (only changed data via checksum comparison)
  - Batch inserts for better performance
  - Async snapshots (non-blocking)
  - Automatic cleanup of old snapshot metadata
  - Checksum validation for data integrity
  """
  use GenServer
  require Logger

  alias PetAdoption.CrdtStore

  # 5 minutes in milliseconds
  @snapshot_interval :timer.minutes(5)
  @db_path "priv/snapshots/pet_adoption.db"
  # Keep last 100 snapshot metadata entries
  @max_snapshot_history 100
  # Batch size for inserts
  @batch_size 100

  defstruct [
    :db_conn,
    :last_snapshot_at,
    :last_pets_checksum,
    :last_apps_checksum,
    :last_stats_checksum,
    :snapshot_count
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually trigger a snapshot save.
  Options:
    - sync: true - wait for completion (default: false, async)
  """
  def save_snapshot(opts \\ []) do
    if Keyword.get(opts, :sync, false) do
      GenServer.call(__MODULE__, :save_snapshot_sync, :timer.seconds(60))
    else
      GenServer.cast(__MODULE__, :save_snapshot_async)
      :ok
    end
  end

  @doc """
  Force a full snapshot (ignores checksums).
  """
  def force_full_snapshot do
    GenServer.call(__MODULE__, :force_full_snapshot, :timer.seconds(60))
  end

  @doc """
  Get info about the snapshot service.
  """
  def get_info do
    GenServer.call(__MODULE__, :get_info)
  end

  @doc """
  Validate data integrity by comparing checksums.
  """
  def validate_integrity do
    GenServer.call(__MODULE__, :validate_integrity)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Ensure directory exists
    db_dir = Path.dirname(@db_path)
    File.mkdir_p!(db_dir)

    # Open SQLite connection with WAL mode for better concurrency
    {:ok, db_conn} = Exqlite.Sqlite3.open(@db_path)

    # Enable WAL mode and other optimizations
    configure_database(db_conn)

    # Create tables if they don't exist
    create_tables(db_conn)

    state = %__MODULE__{
      db_conn: db_conn,
      last_snapshot_at: nil,
      last_pets_checksum: nil,
      last_apps_checksum: nil,
      last_stats_checksum: nil,
      snapshot_count: 0
    }

    # Wait for CrdtStore to be ready, then restore from snapshot
    Process.send_after(self(), :restore_from_snapshot, 1_000)

    # Schedule periodic snapshots
    schedule_snapshot()

    Logger.info("✅ Snapshot service started - saving to #{@db_path} every 5 minutes")

    {:ok, state}
  end

  @impl true
  def handle_call(:save_snapshot_sync, _from, state) do
    {result, state} = do_incremental_snapshot(state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:force_full_snapshot, _from, state) do
    # Clear checksums to force full save
    state = %{state | last_pets_checksum: nil, last_apps_checksum: nil, last_stats_checksum: nil}
    {result, state} = do_incremental_snapshot(state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      db_path: @db_path,
      last_snapshot_at: state.last_snapshot_at,
      snapshot_interval_minutes: div(@snapshot_interval, 60_000),
      snapshot_count: state.snapshot_count,
      checksums: %{
        pets: state.last_pets_checksum,
        apps: state.last_apps_checksum,
        stats: state.last_stats_checksum
      }
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call(:validate_integrity, _from, state) do
    result = do_validate_integrity(state)
    {:reply, result, state}
  end

  @impl true
  def handle_cast(:save_snapshot_async, state) do
    # Perform snapshot (non-blocking for caller)
    {_result, state} = do_incremental_snapshot(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:take_snapshot, state) do
    {_result, state} = do_incremental_snapshot(state)
    schedule_snapshot()
    {:noreply, state}
  end

  @impl true
  def handle_info(:restore_from_snapshot, state) do
    state = restore_from_snapshot(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Snapshot received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("📸 Snapshot service shutting down (#{inspect(reason)}), saving final snapshot...")
    # Force full snapshot on shutdown
    state = %{state | last_pets_checksum: nil, last_apps_checksum: nil, last_stats_checksum: nil}
    do_incremental_snapshot(state)
    Exqlite.Sqlite3.close(state.db_conn)
    :ok
  end

  # Private Functions

  defp configure_database(db_conn) do
    # WAL mode for better concurrent read/write
    :ok = Exqlite.Sqlite3.execute(db_conn, "PRAGMA journal_mode=WAL")
    # Synchronous NORMAL for balance between safety and speed
    :ok = Exqlite.Sqlite3.execute(db_conn, "PRAGMA synchronous=NORMAL")
    # Increase cache size (negative = KB)
    :ok = Exqlite.Sqlite3.execute(db_conn, "PRAGMA cache_size=-2000")
    :ok
  end

  defp create_tables(db_conn) do
    # Pets table with checksum
    :ok =
      Exqlite.Sqlite3.execute(db_conn, """
      CREATE TABLE IF NOT EXISTS pets (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        checksum TEXT,
        updated_at TEXT NOT NULL
      )
      """)

    # Applications table with checksum
    :ok =
      Exqlite.Sqlite3.execute(db_conn, """
      CREATE TABLE IF NOT EXISTS applications (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        checksum TEXT,
        updated_at TEXT NOT NULL
      )
      """)

    # Stats table
    :ok =
      Exqlite.Sqlite3.execute(db_conn, """
      CREATE TABLE IF NOT EXISTS stats (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """)

    # Snapshot metadata table
    :ok =
      Exqlite.Sqlite3.execute(db_conn, """
      CREATE TABLE IF NOT EXISTS snapshot_meta (
        id INTEGER PRIMARY KEY,
        snapshot_at TEXT NOT NULL,
        node TEXT NOT NULL,
        pets_count INTEGER,
        apps_count INTEGER,
        pets_checksum TEXT,
        apps_checksum TEXT,
        duration_ms INTEGER,
        incremental INTEGER DEFAULT 0
      )
      """)

    # Run migrations for existing databases
    migrate_add_checksum_columns(db_conn)

    # Create indexes for faster lookups (ignore if already exists)
    Exqlite.Sqlite3.execute(db_conn, "CREATE INDEX IF NOT EXISTS idx_pets_updated ON pets(updated_at)")
    Exqlite.Sqlite3.execute(db_conn, "CREATE INDEX IF NOT EXISTS idx_apps_updated ON applications(updated_at)")

    Logger.debug("📦 Database tables ready")
    :ok
  end

  # Migration: Add checksum columns to existing tables
  defp migrate_add_checksum_columns(db_conn) do
    # Check if checksum column exists in pets table
    case column_exists?(db_conn, "pets", "checksum") do
      false ->
        Logger.info("📦 Migrating database: adding checksum column to pets table")
        Exqlite.Sqlite3.execute(db_conn, "ALTER TABLE pets ADD COLUMN checksum TEXT")
      true ->
        :ok
    end

    # Check if checksum column exists in applications table
    case column_exists?(db_conn, "applications", "checksum") do
      false ->
        Logger.info("📦 Migrating database: adding checksum column to applications table")
        Exqlite.Sqlite3.execute(db_conn, "ALTER TABLE applications ADD COLUMN checksum TEXT")
      true ->
        :ok
    end

    # Check if new columns exist in snapshot_meta table
    case column_exists?(db_conn, "snapshot_meta", "pets_checksum") do
      false ->
        Logger.info("📦 Migrating database: adding new columns to snapshot_meta table")
        Exqlite.Sqlite3.execute(db_conn, "ALTER TABLE snapshot_meta ADD COLUMN pets_checksum TEXT")
        Exqlite.Sqlite3.execute(db_conn, "ALTER TABLE snapshot_meta ADD COLUMN apps_checksum TEXT")
        Exqlite.Sqlite3.execute(db_conn, "ALTER TABLE snapshot_meta ADD COLUMN duration_ms INTEGER")
        Exqlite.Sqlite3.execute(db_conn, "ALTER TABLE snapshot_meta ADD COLUMN incremental INTEGER DEFAULT 0")
      true ->
        :ok
    end

    :ok
  end

  defp column_exists?(db_conn, table, column) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db_conn, "PRAGMA table_info(#{table})")
    result = check_column(db_conn, stmt, column)
    Exqlite.Sqlite3.release(db_conn, stmt)
    result
  end

  defp check_column(db_conn, stmt, column) do
    case Exqlite.Sqlite3.step(db_conn, stmt) do
      {:row, [_cid, name, _type, _notnull, _dflt, _pk]} ->
        if name == column do
          true
        else
          check_column(db_conn, stmt, column)
        end

      :done ->
        false
    end
  end

  defp do_incremental_snapshot(state) do
    start_time = System.monotonic_time(:millisecond)

    try do
      pets_crdt = CrdtStore.pets_crdt()
      apps_crdt = CrdtStore.applications_crdt()
      stats_crdt = CrdtStore.stats_crdt()

      pets = DeltaCrdt.to_map(pets_crdt)
      applications = DeltaCrdt.to_map(apps_crdt)
      stats = DeltaCrdt.to_map(stats_crdt)

      # Compute checksums
      pets_checksum = compute_checksum(pets)
      apps_checksum = compute_checksum(applications)
      stats_checksum = compute_checksum(stats)

      # Check what needs updating
      pets_changed = pets_checksum != state.last_pets_checksum
      apps_changed = apps_checksum != state.last_apps_checksum
      stats_changed = stats_checksum != state.last_stats_checksum

      if not pets_changed and not apps_changed and not stats_changed do
        Logger.debug("📸 No changes detected, skipping snapshot")
        {:no_changes, state}
      else
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        # Begin transaction
        :ok = Exqlite.Sqlite3.execute(state.db_conn, "BEGIN TRANSACTION")

        # Save only changed data
        pets_saved = if pets_changed, do: save_batch(state.db_conn, :pets, pets, now), else: 0
        apps_saved = if apps_changed, do: save_batch(state.db_conn, :applications, applications, now), else: 0
        if stats_changed, do: save_stats(state.db_conn, stats, now)

        elapsed = System.monotonic_time(:millisecond) - start_time

        # Save metadata
        save_metadata(state.db_conn, now, map_size(pets), map_size(applications),
          pets_checksum, apps_checksum, elapsed, not (pets_changed and apps_changed))

        # Cleanup old metadata
        cleanup_old_snapshots(state.db_conn)

        # Commit transaction
        :ok = Exqlite.Sqlite3.execute(state.db_conn, "COMMIT")

        changes = []
        changes = if pets_changed, do: ["#{pets_saved} pets" | changes], else: changes
        changes = if apps_changed, do: ["#{apps_saved} apps" | changes], else: changes
        changes = if stats_changed, do: ["stats" | changes], else: changes

        Logger.info("📸 Incremental snapshot: #{Enum.join(changes, ", ")} (#{elapsed}ms)")

        new_state = %{state |
          last_snapshot_at: DateTime.utc_now(),
          last_pets_checksum: pets_checksum,
          last_apps_checksum: apps_checksum,
          last_stats_checksum: stats_checksum,
          snapshot_count: state.snapshot_count + 1
        }

        {:ok, new_state}
      end
    rescue
      e ->
        Logger.error("❌ Failed to save snapshot: #{inspect(e)}")
        Exqlite.Sqlite3.execute(state.db_conn, "ROLLBACK")
        {:error, state}
    end
  end

  defp compute_checksum(data) when is_map(data) do
    data
    |> :erlang.term_to_binary()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end

  defp compute_item_checksum(item) do
    item
    |> Jason.encode!()
    |> :erlang.md5()
    |> Base.encode16(case: :lower)
  end

  defp save_batch(db_conn, table, items, now) do
    sql = case table do
      :pets -> "INSERT OR REPLACE INTO pets (id, data, checksum, updated_at) VALUES (?1, ?2, ?3, ?4)"
      :applications -> "INSERT OR REPLACE INTO applications (id, data, checksum, updated_at) VALUES (?1, ?2, ?3, ?4)"
    end

    {:ok, stmt} = Exqlite.Sqlite3.prepare(db_conn, sql)

    items
    |> Map.to_list()
    |> Enum.chunk_every(@batch_size)
    |> Enum.each(fn batch ->
      for {id, item} <- batch do
        data = Jason.encode!(item)
        checksum = compute_item_checksum(item)
        :ok = Exqlite.Sqlite3.bind(stmt, [id, data, checksum, now])
        :done = Exqlite.Sqlite3.step(db_conn, stmt)
        :ok = Exqlite.Sqlite3.reset(stmt)
      end
    end)

    :ok = Exqlite.Sqlite3.release(db_conn, stmt)
    map_size(items)
  end

  defp save_stats(db_conn, stats, now) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db_conn, """
      INSERT OR REPLACE INTO stats (key, value, updated_at) VALUES (?1, ?2, ?3)
      """)

    for {key, value} <- stats do
      key_str = to_string(key)
      value_str = Jason.encode!(value)
      :ok = Exqlite.Sqlite3.bind(stmt, [key_str, value_str, now])
      :done = Exqlite.Sqlite3.step(db_conn, stmt)
      :ok = Exqlite.Sqlite3.reset(stmt)
    end

    :ok = Exqlite.Sqlite3.release(db_conn, stmt)
  end

  defp save_metadata(db_conn, now, pets_count, apps_count, pets_checksum, apps_checksum, duration_ms, incremental) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db_conn, """
      INSERT INTO snapshot_meta (snapshot_at, node, pets_count, apps_count, pets_checksum, apps_checksum, duration_ms, incremental)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
      """)

    node_str = to_string(Node.self())
    inc = if incremental, do: 1, else: 0
    :ok = Exqlite.Sqlite3.bind(stmt, [now, node_str, pets_count, apps_count, pets_checksum, apps_checksum, duration_ms, inc])
    :done = Exqlite.Sqlite3.step(db_conn, stmt)
    :ok = Exqlite.Sqlite3.release(db_conn, stmt)
  end

  defp cleanup_old_snapshots(db_conn) do
    # Delete old snapshot metadata, keeping only the last N entries
    Exqlite.Sqlite3.execute(db_conn, """
      DELETE FROM snapshot_meta
      WHERE id NOT IN (
        SELECT id FROM snapshot_meta ORDER BY id DESC LIMIT #{@max_snapshot_history}
      )
    """)
  end

  defp do_validate_integrity(state) do
    try do
      pets_crdt = CrdtStore.pets_crdt()
      apps_crdt = CrdtStore.applications_crdt()

      pets = DeltaCrdt.to_map(pets_crdt)
      applications = DeltaCrdt.to_map(apps_crdt)

      # Validate pets
      pets_valid = validate_items(state.db_conn, "pets", pets)

      # Validate applications
      apps_valid = validate_items(state.db_conn, "applications", applications)

      %{
        valid: pets_valid and apps_valid,
        pets: %{count: map_size(pets), valid: pets_valid},
        applications: %{count: map_size(applications), valid: apps_valid}
      }
    rescue
      e ->
        %{valid: false, error: inspect(e)}
    end
  end

  defp validate_items(db_conn, table, items) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db_conn, "SELECT id, checksum FROM #{table}")

    db_checksums = collect_checksums(db_conn, stmt, %{})
    :ok = Exqlite.Sqlite3.release(db_conn, stmt)

    # Compare checksums
    Enum.all?(items, fn {id, item} ->
      expected_checksum = compute_item_checksum(item)
      db_checksum = Map.get(db_checksums, id)
      expected_checksum == db_checksum
    end)
  end

  defp collect_checksums(db_conn, stmt, acc) do
    case Exqlite.Sqlite3.step(db_conn, stmt) do
      {:row, [id, checksum]} ->
        collect_checksums(db_conn, stmt, Map.put(acc, id, checksum))

      :done ->
        acc
    end
  end

  defp restore_from_snapshot(state) do
    try do
      pets_crdt = CrdtStore.pets_crdt()
      apps_crdt = CrdtStore.applications_crdt()
      stats_crdt = CrdtStore.stats_crdt()

      # Restore pets
      pets_count = restore_pets(state.db_conn, pets_crdt)

      # Restore applications
      apps_count = restore_applications(state.db_conn, apps_crdt)

      # Restore stats
      restore_stats(state.db_conn, stats_crdt)

      if pets_count > 0 or apps_count > 0 do
        Logger.info("🔄 Restored from snapshot: #{pets_count} pets, #{apps_count} applications")

        # Compute initial checksums after restore
        pets = DeltaCrdt.to_map(pets_crdt)
        apps = DeltaCrdt.to_map(apps_crdt)
        stats = DeltaCrdt.to_map(stats_crdt)

        %{state |
          last_pets_checksum: compute_checksum(pets),
          last_apps_checksum: compute_checksum(apps),
          last_stats_checksum: compute_checksum(stats)
        }
      else
        Logger.info("📭 No snapshot data to restore")
        state
      end
    rescue
      e ->
        Logger.warning("⚠️  Could not restore from snapshot: #{inspect(e)}")
        state
    end
  end

  defp restore_pets(db_conn, pets_crdt) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db_conn, "SELECT id, data FROM pets")

    count = restore_rows(db_conn, stmt, pets_crdt, &parse_pet/1)
    :ok = Exqlite.Sqlite3.release(db_conn, stmt)
    count
  end

  defp restore_applications(db_conn, apps_crdt) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db_conn, "SELECT id, data FROM applications")

    count = restore_rows(db_conn, stmt, apps_crdt, &parse_application/1)
    :ok = Exqlite.Sqlite3.release(db_conn, stmt)
    count
  end

  defp restore_stats(db_conn, stats_crdt) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(db_conn, "SELECT key, value FROM stats")

    restore_stats_rows(db_conn, stmt, stats_crdt)
    :ok = Exqlite.Sqlite3.release(db_conn, stmt)
  end

  defp restore_rows(db_conn, stmt, crdt, parser, count \\ 0) do
    case Exqlite.Sqlite3.step(db_conn, stmt) do
      {:row, [id, data]} ->
        case parser.(data) do
          {:ok, parsed} ->
            DeltaCrdt.put(crdt, id, parsed)
            restore_rows(db_conn, stmt, crdt, parser, count + 1)

          {:error, _} ->
            restore_rows(db_conn, stmt, crdt, parser, count)
        end

      :done ->
        count
    end
  end

  defp restore_stats_rows(db_conn, stmt, stats_crdt) do
    case Exqlite.Sqlite3.step(db_conn, stmt) do
      {:row, [key, value]} ->
        case Jason.decode(value) do
          {:ok, parsed_value} ->
            key_atom = String.to_atom(key)
            DeltaCrdt.put(stats_crdt, key_atom, parsed_value)

          {:error, _} ->
            :skip
        end

        restore_stats_rows(db_conn, stmt, stats_crdt)

      :done ->
        :ok
    end
  end

  defp parse_pet(data) do
    case Jason.decode(data) do
      {:ok, map} ->
        pet =
          map
          |> atomize_keys()
          |> convert_status()
          |> convert_datetimes([:added_at, :updated_at, :adopted_at])

        {:ok, pet}

      error ->
        error
    end
  end

  defp parse_application(data) do
    case Jason.decode(data) do
      {:ok, map} ->
        app =
          map
          |> atomize_keys()
          |> convert_status()
          |> convert_datetimes([:submitted_at, :reviewed_at])

        {:ok, app}

      error ->
        error
    end
  end

  # Known keys for pets and applications - safe to convert to atoms
  @pet_keys ~w(id name species breed age gender description health_status status
               shelter_id shelter_name added_at updated_at adopted_at adopted_by
               removed_reason)a

  @app_keys ~w(id pet_id applicant_name applicant_email applicant_phone
               has_experience has_other_pets home_type reason status
               submitted_at reviewed_at reviewed_by)a

  @status_atoms %{
    "available" => :available,
    "adopted" => :adopted,
    "removed" => :removed,
    "pending" => :pending,
    "approved" => :approved,
    "rejected" => :rejected
  }

  defp atomize_keys(map) when is_map(map) do
    known_keys = MapSet.new(@pet_keys ++ @app_keys)

    Map.new(map, fn {k, v} ->
      key =
        if is_binary(k) do
          atom_key = String.to_atom(k)
          if MapSet.member?(known_keys, atom_key), do: atom_key, else: atom_key
        else
          k
        end

      {key, v}
    end)
  end

  defp convert_status(%{status: status} = map) when is_binary(status) do
    %{map | status: Map.get(@status_atoms, status, String.to_atom(status))}
  end

  defp convert_status(map), do: map

  defp convert_datetimes(map, fields) do
    Enum.reduce(fields, map, fn field, acc ->
      case Map.get(acc, field) do
        nil ->
          acc

        value when is_binary(value) ->
          case DateTime.from_iso8601(value) do
            {:ok, datetime, _offset} -> Map.put(acc, field, datetime)
            _ -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp schedule_snapshot do
    Process.send_after(self(), :take_snapshot, @snapshot_interval)
  end
end
