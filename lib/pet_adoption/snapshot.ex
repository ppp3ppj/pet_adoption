defmodule PetAdoption.Snapshot do
  @moduledoc """
  Periodically saves CRDT state to SQLite database for persistence.
  Snapshots are taken every 5 minutes and on graceful shutdown.
  On startup, restores state from the latest snapshot if available.
  """
  use GenServer
  require Logger

  alias PetAdoption.CrdtStore

  # 5 minutes in milliseconds
  @snapshot_interval :timer.minutes(5)
  @db_path "priv/snapshots/pet_adoption.db"

  defstruct [:db_conn, :last_snapshot_at]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Manually trigger a snapshot save.
  """
  def save_snapshot do
    GenServer.call(__MODULE__, :save_snapshot, :timer.seconds(30))
  end

  @doc """
  Get info about the last snapshot.
  """
  def get_info do
    GenServer.call(__MODULE__, :get_info)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Ensure directory exists
    db_dir = Path.dirname(@db_path)
    File.mkdir_p!(db_dir)

    # Open SQLite connection
    {:ok, db_conn} = Exqlite.Sqlite3.open(@db_path)

    # Create tables if they don't exist
    create_tables(db_conn)

    state = %__MODULE__{
      db_conn: db_conn,
      last_snapshot_at: nil
    }

    # Wait for CrdtStore to be ready, then restore from snapshot
    Process.send_after(self(), :restore_from_snapshot, 1_000)

    # Schedule periodic snapshots
    schedule_snapshot()

    Logger.info("✅ Snapshot service started - saving to #{@db_path} every 5 minutes")

    {:ok, state}
  end

  @impl true
  def handle_call(:save_snapshot, _from, state) do
    state = do_save_snapshot(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      db_path: @db_path,
      last_snapshot_at: state.last_snapshot_at,
      snapshot_interval_minutes: div(@snapshot_interval, 60_000)
    }

    {:reply, info, state}
  end

  @impl true
  def handle_info(:take_snapshot, state) do
    state = do_save_snapshot(state)
    schedule_snapshot()
    {:noreply, state}
  end

  @impl true
  def handle_info(:restore_from_snapshot, state) do
    restore_from_snapshot(state.db_conn)
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
    do_save_snapshot(state)
    Exqlite.Sqlite3.close(state.db_conn)
    :ok
  end

  # Private Functions

  defp create_tables(db_conn) do
    # Pets table
    :ok =
      Exqlite.Sqlite3.execute(db_conn, """
      CREATE TABLE IF NOT EXISTS pets (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
      """)

    # Applications table
    :ok =
      Exqlite.Sqlite3.execute(db_conn, """
      CREATE TABLE IF NOT EXISTS applications (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
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
        apps_count INTEGER
      )
      """)

    Logger.debug("📦 Database tables ready")
    :ok
  end

  defp do_save_snapshot(state) do
    start_time = System.monotonic_time(:millisecond)

    try do
      pets_crdt = CrdtStore.pets_crdt()
      apps_crdt = CrdtStore.applications_crdt()
      stats_crdt = CrdtStore.stats_crdt()

      pets = DeltaCrdt.to_map(pets_crdt)
      applications = DeltaCrdt.to_map(apps_crdt)
      stats = DeltaCrdt.to_map(stats_crdt)

      now = DateTime.utc_now() |> DateTime.to_iso8601()

      # Begin transaction
      :ok = Exqlite.Sqlite3.execute(state.db_conn, "BEGIN TRANSACTION")

      # Save pets
      save_pets(state.db_conn, pets, now)

      # Save applications
      save_applications(state.db_conn, applications, now)

      # Save stats
      save_stats(state.db_conn, stats, now)

      # Save metadata
      save_metadata(state.db_conn, now, map_size(pets), map_size(applications))

      # Commit transaction
      :ok = Exqlite.Sqlite3.execute(state.db_conn, "COMMIT")

      elapsed = System.monotonic_time(:millisecond) - start_time

      Logger.info(
        "📸 Snapshot saved: #{map_size(pets)} pets, #{map_size(applications)} applications (#{elapsed}ms)"
      )

      %{state | last_snapshot_at: DateTime.utc_now()}
    rescue
      e ->
        Logger.error("❌ Failed to save snapshot: #{inspect(e)}")
        Exqlite.Sqlite3.execute(state.db_conn, "ROLLBACK")
        state
    end
  end

  defp save_pets(db_conn, pets, now) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db_conn, """
      INSERT OR REPLACE INTO pets (id, data, updated_at) VALUES (?1, ?2, ?3)
      """)

    for {id, pet} <- pets do
      data = Jason.encode!(pet)
      :ok = Exqlite.Sqlite3.bind(stmt, [id, data, now])
      :done = Exqlite.Sqlite3.step(db_conn, stmt)
      :ok = Exqlite.Sqlite3.reset(stmt)
    end

    :ok = Exqlite.Sqlite3.release(db_conn, stmt)
  end

  defp save_applications(db_conn, applications, now) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db_conn, """
      INSERT OR REPLACE INTO applications (id, data, updated_at) VALUES (?1, ?2, ?3)
      """)

    for {id, app} <- applications do
      data = Jason.encode!(app)
      :ok = Exqlite.Sqlite3.bind(stmt, [id, data, now])
      :done = Exqlite.Sqlite3.step(db_conn, stmt)
      :ok = Exqlite.Sqlite3.reset(stmt)
    end

    :ok = Exqlite.Sqlite3.release(db_conn, stmt)
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

  defp save_metadata(db_conn, now, pets_count, apps_count) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(db_conn, """
      INSERT INTO snapshot_meta (snapshot_at, node, pets_count, apps_count)
      VALUES (?1, ?2, ?3, ?4)
      """)

    node_str = to_string(Node.self())
    :ok = Exqlite.Sqlite3.bind(stmt, [now, node_str, pets_count, apps_count])
    :done = Exqlite.Sqlite3.step(db_conn, stmt)
    :ok = Exqlite.Sqlite3.release(db_conn, stmt)
  end

  defp restore_from_snapshot(db_conn) do
    try do
      pets_crdt = CrdtStore.pets_crdt()
      apps_crdt = CrdtStore.applications_crdt()
      stats_crdt = CrdtStore.stats_crdt()

      # Restore pets
      pets_count = restore_pets(db_conn, pets_crdt)

      # Restore applications
      apps_count = restore_applications(db_conn, apps_crdt)

      # Restore stats
      restore_stats(db_conn, stats_crdt)

      if pets_count > 0 or apps_count > 0 do
        Logger.info("🔄 Restored from snapshot: #{pets_count} pets, #{apps_count} applications")
      else
        Logger.info("📭 No snapshot data to restore")
      end
    rescue
      e ->
        Logger.warning("⚠️  Could not restore from snapshot: #{inspect(e)}")
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
            # Convert key back to atom for stats
            key_atom = String.to_existing_atom(key)
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
        # Convert string keys to atoms and handle special fields
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
