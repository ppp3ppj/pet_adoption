defmodule PetAdoption.Cluster do
  @moduledoc """
  Manages cluster operations: node monitoring, partition simulation, and reconnection.
  """
  use GenServer
  require Logger

  alias PetAdoption.CrdtStore
  alias PetAdoption.PubSubBroadcaster

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Simulates a network partition for the specified duration.
  """
  def simulate_partition(duration_ms \\ 5000) do
    GenServer.cast(__MODULE__, {:simulate_partition, duration_ms})
  end

  @doc """
  Gets the list of connected nodes.
  """
  def connected_nodes do
    Node.list()
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    :net_kernel.monitor_nodes(true)
    Logger.info("✅ Cluster monitor started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:simulate_partition, duration_ms}, state) do
    Logger.warning("Simulating network partition for #{duration_ms}ms")
    Enum.each(Node.list(), &Node.disconnect/1)
    Process.send_after(self(), :reconnect, duration_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("Reconnecting to cluster...")
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("Shelter connected: #{node}")
    CrdtStore.setup_neighbors()
    PubSubBroadcaster.broadcast(:cluster_change, %{node: node, action: :up})
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.warning("Shelter disconnected: #{node}")
    PubSubBroadcaster.broadcast(:cluster_change, %{node: node, action: :down})
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Cluster received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end
