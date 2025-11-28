defmodule PetAdoption.CrdtSyncNotifier do
  @moduledoc """
  Monitors CRDT changes and broadcasts updates via PubSub.
  This ensures LiveViews are notified when data syncs from other nodes.
  """
  use GenServer
  require Logger

  alias PetAdoption.CrdtStore

  @check_interval 1_000

  defstruct [:last_pets_hash, :last_apps_hash]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Wait a bit for CrdtStore to be fully ready
    Process.send_after(self(), :init_check, 500)

    state = %__MODULE__{
      last_pets_hash: nil,
      last_apps_hash: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_info(:init_check, state) do
    # Start monitoring after CrdtStore is ready
    schedule_check()

    # Get initial hashes
    pets_hash = compute_pets_hash()
    apps_hash = compute_apps_hash()

    Logger.info("✅ CrdtSyncNotifier started - monitoring for cross-node changes")

    {:noreply, %{state | last_pets_hash: pets_hash, last_apps_hash: apps_hash}}
  end

  @impl true
  def handle_info(:check_changes, state) do
    new_pets_hash = compute_pets_hash()
    new_apps_hash = compute_apps_hash()

    state =
      state
      |> maybe_broadcast_pets_change(new_pets_hash)
      |> maybe_broadcast_apps_change(new_apps_hash)

    schedule_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp schedule_check do
    Process.send_after(self(), :check_changes, @check_interval)
  end

  defp compute_pets_hash do
    try do
      pets_crdt = CrdtStore.pets_crdt()

      pets_crdt
      |> DeltaCrdt.to_map()
      |> :erlang.phash2()
    rescue
      _ -> nil
    end
  end

  defp compute_apps_hash do
    try do
      apps_crdt = CrdtStore.applications_crdt()

      apps_crdt
      |> DeltaCrdt.to_map()
      |> :erlang.phash2()
    rescue
      _ -> nil
    end
  end

  defp maybe_broadcast_pets_change(state, new_hash) do
    if state.last_pets_hash != nil and new_hash != state.last_pets_hash do
      Logger.debug("🔄 Detected pets change from remote node, broadcasting update")
      Phoenix.PubSub.local_broadcast(
        PetAdoption.PubSub,
        "pet_updates",
        {:pet_update, :sync, %{source: :remote}}
      )
    end

    %{state | last_pets_hash: new_hash}
  end

  defp maybe_broadcast_apps_change(state, new_hash) do
    if state.last_apps_hash != nil and new_hash != state.last_apps_hash do
      Logger.debug("🔄 Detected applications change from remote node, broadcasting update")
      Phoenix.PubSub.local_broadcast(
        PetAdoption.PubSub,
        "pet_updates",
        {:pet_update, :sync, %{source: :remote}}
      )
    end

    %{state | last_apps_hash: new_hash}
  end
end
