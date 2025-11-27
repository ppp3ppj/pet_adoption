defmodule PetAdoption.CrdtStore do
  @moduledoc """
  Manages CRDT processes for distributed state synchronization.
  Handles initialization, neighbor setup, and provides access to CRDT instances.
  """
  use GenServer
  require Logger

  @crdt_sync_interval 2_000

  defstruct [:pets_crdt, :applications_crdt, :stats_crdt]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the pets CRDT process.
  """
  def pets_crdt do
    GenServer.call(__MODULE__, :pets_crdt)
  end

  @doc """
  Returns the applications CRDT process.
  """
  def applications_crdt do
    GenServer.call(__MODULE__, :applications_crdt)
  end

  @doc """
  Returns the stats CRDT process.
  """
  def stats_crdt do
    GenServer.call(__MODULE__, :stats_crdt)
  end

  @doc """
  Sets up CRDT neighbors for cluster synchronization.
  """
  def setup_neighbors do
    GenServer.cast(__MODULE__, :setup_neighbors)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, pets_crdt} =
      DeltaCrdt.start_link(
        DeltaCrdt.AWLWWMap,
        sync_interval: @crdt_sync_interval,
        name: :pets_crdt
      )

    {:ok, applications_crdt} =
      DeltaCrdt.start_link(
        DeltaCrdt.AWLWWMap,
        sync_interval: @crdt_sync_interval,
        name: :applications_crdt
      )

    {:ok, stats_crdt} =
      DeltaCrdt.start_link(
        DeltaCrdt.AWLWWMap,
        sync_interval: @crdt_sync_interval,
        name: :stats_crdt
      )

    # Initialize stats
    DeltaCrdt.put(stats_crdt, :total_adoptions, 0)
    DeltaCrdt.put(stats_crdt, :total_applications, 0)

    state = %__MODULE__{
      pets_crdt: pets_crdt,
      applications_crdt: applications_crdt,
      stats_crdt: stats_crdt
    }

    schedule_sync()

    Logger.info("✅ CrdtStore started")

    {:ok, state}
  end

  @impl true
  def handle_call(:pets_crdt, _from, state) do
    {:reply, state.pets_crdt, state}
  end

  @impl true
  def handle_call(:applications_crdt, _from, state) do
    {:reply, state.applications_crdt, state}
  end

  @impl true
  def handle_call(:stats_crdt, _from, state) do
    {:reply, state.stats_crdt, state}
  end

  @impl true
  def handle_cast(:setup_neighbors, state) do
    do_setup_neighbors(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:sync_check, state) do
    do_setup_neighbors(state)
    schedule_sync()
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("CrdtStore received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp do_setup_neighbors(state) do
    neighbor_nodes = Node.list()

    if length(neighbor_nodes) > 0 do
      pets_neighbors = Enum.map(neighbor_nodes, fn node -> {:pets_crdt, node} end)
      apps_neighbors = Enum.map(neighbor_nodes, fn node -> {:applications_crdt, node} end)
      stats_neighbors = Enum.map(neighbor_nodes, fn node -> {:stats_crdt, node} end)

      try do
        DeltaCrdt.set_neighbours(state.pets_crdt, pets_neighbors)
        DeltaCrdt.set_neighbours(state.applications_crdt, apps_neighbors)
        DeltaCrdt.set_neighbours(state.stats_crdt, stats_neighbors)
        Logger.debug("✅ Set CRDT neighbors for #{length(neighbor_nodes)} nodes")
      rescue
        e -> Logger.debug("⚠️  Could not set neighbors: #{inspect(e)}")
      end
    end
  end

  defp schedule_sync do
    Process.send_after(self(), :sync_check, @crdt_sync_interval)
  end
end
