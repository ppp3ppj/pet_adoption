defmodule PetAdoption.PetManager do
  alias PetAdoption.Schemas.Pet
  alias PetAdoption.Schemas.AdoptionApplication

  @moduledoc """
  Manages distributed pet adoption state using CRDTs.
  """
  use GenServer
  require Logger

  @crdt_sync_interval 2_000

  defstruct [
    :node_id,
    :shelter_id,
    :shelter_name,
    :pets_crdt,
    :applications_crdt,
    :stats_crdt
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def add_pet(pet_data) do
    GenServer.call(__MODULE__, {:add_pet, pet_data})
  end

  def update_pet(pet_id, updates) do
    GenServer.call(__MODULE__, {:update_pet, pet_id, updates})
  end

  def submit_application(pet_id, application_data) do
    GenServer.call(__MODULE__, {:submit_application, pet_id, application_data})
  end

  def approve_adoption(pet_id, application_id) do
    GenServer.call(__MODULE__, {:approve_adoption, pet_id, application_id})
  end

  def remove_pet(pet_id, reason \\ :adopted) do
    GenServer.call(__MODULE__, {:remove_pet, pet_id, reason})
  end

  def list_pets(filter \\ :all) do
    GenServer.call(__MODULE__, {:list_pets, filter})
  end

  def get_pet(pet_id) do
    GenServer.call(__MODULE__, {:get_pet, pet_id})
  end

  def get_applications(pet_id) do
    GenServer.call(__MODULE__, {:get_applications, pet_id})
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  def get_shelter_info do
    GenServer.call(__MODULE__, :get_shelter_info)
  end

  def simulate_partition(duration_ms \\ 5000) do
    GenServer.cast(__MODULE__, {:simulate_partition, duration_ms})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    node_id = Node.self()
    shelter_id = Application.get_env(:pet_adoption, :shelter_id, "shelter1")
    shelter_name = Application.get_env(:pet_adoption, :shelter_name, "Animal Rescue Center")

    # Start CRDT processes with LOCAL registration
    {:ok, pets_crdt} =
      DeltaCrdt.start_link(
        DeltaCrdt.AWLWWMap,
        sync_interval: @crdt_sync_interval,
        # Local registration
        name: :pets_crdt
      )

    {:ok, applications_crdt} =
      DeltaCrdt.start_link(
        DeltaCrdt.AWLWWMap,
        sync_interval: @crdt_sync_interval,
        # Local registration
        name: :applications_crdt
      )

    {:ok, stats_crdt} =
      DeltaCrdt.start_link(
        DeltaCrdt.AWLWWMap,
        sync_interval: @crdt_sync_interval,
        # Local registration
        name: :stats_crdt
      )

    # Monitor cluster changes
    :net_kernel.monitor_nodes(true)

    # Initialize stats
    DeltaCrdt.put(stats_crdt, :total_adoptions, 0)
    DeltaCrdt.put(stats_crdt, :total_applications, 0)

    state = %__MODULE__{
      node_id: node_id,
      shelter_id: shelter_id,
      shelter_name: shelter_name,
      pets_crdt: pets_crdt,
      applications_crdt: applications_crdt,
      stats_crdt: stats_crdt
    }

    schedule_sync()

    Logger.info("✅ PetManager started - Shelter: #{shelter_name} (#{shelter_id}) on #{node_id}")

    {:ok, state}
  end

  @impl true
  def handle_call({:add_pet, pet_data}, _from, state) do
    pet_id = generate_pet_id()
    timestamp = DateTime.utc_now()

    pet = %{
      id: pet_id,
      name: pet_data[:name],
      species: pet_data[:species],
      breed: pet_data[:breed],
      age: pet_data[:age],
      gender: pet_data[:gender],
      description: pet_data[:description],
      health_status: pet_data[:health_status] || "Healthy",
      status: :available,
      shelter_id: state.shelter_id,
      shelter_name: state.shelter_name,
      added_at: timestamp,
      updated_at: timestamp,
      adopted_at: nil,
      adopted_by: nil
    }

    DeltaCrdt.put(state.pets_crdt, pet_id, pet)
    broadcast_update(:pet_added, pet)

    Logger.info("Pet added: #{pet.name} (#{pet_id}) at #{state.shelter_name}")

    {:reply, {:ok, pet}, state}
  end

  @impl true
  def handle_call({:update_pet, pet_id, updates}, _from, state) do
    case DeltaCrdt.get(state.pets_crdt, pet_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      pet ->
        updated_pet =
          pet
          |> Map.merge(updates)
          |> Map.put(:updated_at, DateTime.utc_now())

        DeltaCrdt.put(state.pets_crdt, pet_id, updated_pet)
        broadcast_update(:pet_updated, updated_pet)

        {:reply, {:ok, updated_pet}, state}
    end
  end

  @impl true
  def handle_call({:submit_application, pet_id, application_data}, _from, state) do
    pet_map = DeltaCrdt.get(state.pets_crdt, pet_id)

    IO.inspect(pet_map, label: "handle call: submit:")

    if pet_map && pet_map[:status] == :available do
      application_id = generate_application_id()

      attrs =
        application_data
        |> Keyword.put(:id, application_id)
        |> Keyword.put(:pet_id, pet_id)
        |> Enum.into(%{})

      # ← Changed
      changeset = AdoptionApplication.create_changeset(%AdoptionApplication{}, attrs)

      case Ecto.Changeset.apply_action(changeset, :insert) do
        {:ok, application} ->
          # ← Changed
          app_map = AdoptionApplication.to_map(application)
          DeltaCrdt.put(state.applications_crdt, application_id, app_map)

          current_apps = DeltaCrdt.get(state.stats_crdt, :total_applications) || 0
          DeltaCrdt.put(state.stats_crdt, :total_applications, current_apps + 1)

          broadcast_update(:application_submitted, app_map)

          Logger.info("Application submitted for pet #{pet_id} by #{application.applicant_name}")
          {:reply, {:ok, app_map}, state}

        {:error, changeset} ->
          Logger.error("Failed to submit application: #{inspect(changeset.errors)}")
          {:reply, {:error, changeset}, state}
      end
    else
      {:reply, {:error, :pet_not_available}, state}
    end
  end

  @impl true
  def handle_call({:approve_adoption, pet_id, application_id}, _from, state) do
    pet_map = DeltaCrdt.get(state.pets_crdt, pet_id)
    app_map = DeltaCrdt.get(state.applications_crdt, application_id)

    if pet_map && app_map && pet_map[:status] == :available do
      # Convert to structs
      pet = Pet.from_map(pet_map)
      # ← Changed
      application = AdoptionApplication.from_map(app_map)

      # Apply changesets
      pet_changeset = Pet.adopt_changeset(pet, application.applicant_name)
      # ← Changed
      app_changeset = AdoptionApplication.approve_changeset(application, state.shelter_name)

      with {:ok, adopted_pet} <- Ecto.Changeset.apply_action(pet_changeset, :update),
           {:ok, approved_app} <- Ecto.Changeset.apply_action(app_changeset, :update) do
        adopted_pet_map = Pet.to_map(adopted_pet)
        # ← Changed
        approved_app_map = AdoptionApplication.to_map(approved_app)

        DeltaCrdt.put(state.pets_crdt, pet_id, adopted_pet_map)
        DeltaCrdt.put(state.applications_crdt, application_id, approved_app_map)

        current_adoptions = DeltaCrdt.get(state.stats_crdt, :total_adoptions) || 0
        DeltaCrdt.put(state.stats_crdt, :total_adoptions, current_adoptions + 1)

        reject_other_applications(state, pet_id, application_id)

        broadcast_update(:pet_adopted, %{pet: adopted_pet_map, application: approved_app_map})

        Logger.info("Pet #{adopted_pet.name} adopted by #{application.applicant_name}")

        {:reply, {:ok, adopted_pet_map}, state}
      else
        {:error, changeset} ->
          Logger.error("Failed to approve adoption: #{inspect(changeset.errors)}")
          {:reply, {:error, changeset}, state}
      end
    else
      {:reply, {:error, :cannot_approve}, state}
    end
  end

  @impl true
  def handle_call({:remove_pet, pet_id, reason}, _from, state) do
    case DeltaCrdt.get(state.pets_crdt, pet_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      pet ->
        removed_pet =
          pet
          |> Map.put(:status, :removed)
          |> Map.put(:removed_reason, reason)
          |> Map.put(:updated_at, DateTime.utc_now())

        DeltaCrdt.put(state.pets_crdt, pet_id, removed_pet)
        broadcast_update(:pet_removed, removed_pet)

        {:reply, {:ok, removed_pet}, state}
    end
  end

  @impl true
  def handle_call({:list_pets, filter}, _from, state) do
    pets =
      state.pets_crdt
      |> DeltaCrdt.to_map()
      |> Map.values()
      |> filter_pets(filter)
      |> Enum.sort_by(& &1.added_at, {:desc, DateTime})

    {:reply, pets, state}
  end

  @impl true
  def handle_call({:get_pet, pet_id}, _from, state) do
    pet = DeltaCrdt.get(state.pets_crdt, pet_id)
    {:reply, pet, state}
  end

  @impl true
  def handle_call({:get_applications, pet_id}, _from, state) do
    applications =
      state.applications_crdt
      |> DeltaCrdt.to_map()
      |> Map.values()
      |> Enum.filter(&(&1.pet_id == pet_id))
      |> Enum.sort_by(& &1.submitted_at, {:desc, DateTime})

    {:reply, applications, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    all_pets = DeltaCrdt.to_map(state.pets_crdt) |> Map.values()
    all_apps = DeltaCrdt.to_map(state.applications_crdt) |> Map.values()

    stats = %{
      total_pets: length(all_pets),
      available_pets: Enum.count(all_pets, &(&1.status == :available)),
      adopted_pets: Enum.count(all_pets, &(&1.status == :adopted)),
      total_applications: length(all_apps),
      pending_applications: Enum.count(all_apps, &(&1.status == :pending)),
      approved_applications: Enum.count(all_apps, &(&1.status == :approved)),
      connected_shelters: length(Node.list()),
      total_shelters: length(Node.list()) + 1,
      pets_by_species: count_by_species(all_pets),
      recent_adoptions: get_recent_adoptions(all_pets, 5)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call(:get_shelter_info, _from, state) do
    info = %{
      node_id: state.node_id,
      shelter_id: state.shelter_id,
      shelter_name: state.shelter_name,
      connected_nodes: Node.list()
    }

    {:reply, info, state}
  end

  @impl true
  def handle_cast({:simulate_partition, duration_ms}, state) do
    Logger.warning("Simulating network partition for #{duration_ms}ms")
    Enum.each(Node.list(), &Node.disconnect/1)
    Process.send_after(self(), :reconnect, duration_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:sync_check, state) do
    setup_crdt_neighbors(state)
    schedule_sync()
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
    setup_crdt_neighbors(state)
    broadcast_update(:cluster_change, %{node: node, action: :up})
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.warning("Shelter disconnected: #{node}")
    broadcast_update(:cluster_change, %{node: node, action: :down})
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    # Catch-all for unexpected messages (like internal CRDT messages)
    Logger.debug("Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp generate_pet_id do
    "pet_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp generate_application_id do
    "app_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp setup_crdt_neighbors(state) do
    neighbor_nodes = Node.list()

    if length(neighbor_nodes) > 0 do
      # Build neighbor list using remote registered names
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

  defp reject_other_applications(state, pet_id, approved_application_id) do
    state.applications_crdt
    |> DeltaCrdt.to_map()
    |> Enum.each(fn {app_id, app} ->
      if app.pet_id == pet_id && app.id != approved_application_id && app.status == :pending do
        rejected_app =
          app
          |> Map.put(:status, :rejected)
          |> Map.put(:reviewed_at, DateTime.utc_now())
          |> Map.put(:reviewed_by, state.shelter_name)

        DeltaCrdt.put(state.applications_crdt, app_id, rejected_app)
      end
    end)
  end

  defp filter_pets(pets, :all), do: pets
  defp filter_pets(pets, :available), do: Enum.filter(pets, &(&1.status == :available))
  defp filter_pets(pets, :adopted), do: Enum.filter(pets, &(&1.status == :adopted))
  defp filter_pets(pets, :removed), do: Enum.filter(pets, &(&1.status == :removed))

  defp count_by_species(pets) do
    pets
    |> Enum.filter(&(&1.status == :available))
    |> Enum.group_by(& &1.species)
    |> Enum.map(fn {species, pets} -> {species, length(pets)} end)
    |> Enum.into(%{})
  end

  defp get_recent_adoptions(pets, limit) do
    pets
    |> Enum.filter(&(&1.status == :adopted))
    |> Enum.sort_by(& &1.adopted_at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  defp broadcast_update(type, data) do
    Phoenix.PubSub.broadcast(
      PetAdoption.PubSub,
      "pet_updates",
      {:pet_update, type, data}
    )
  end

  defp schedule_sync do
    Process.send_after(self(), :sync_check, @crdt_sync_interval)
  end
end
