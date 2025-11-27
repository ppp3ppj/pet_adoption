defmodule PetAdoption.Pets do
  @moduledoc """
  Handles pet-related operations: adding, updating, removing, listing, and filtering pets.
  """
  require Logger

  alias PetAdoption.CrdtStore
  alias PetAdoption.Shelter
  alias PetAdoption.PubSubBroadcaster

  @doc """
  Adds a new pet to the system.
  """
  def add_pet(pet_data) do
    pets_crdt = CrdtStore.pets_crdt()
    shelter_info = Shelter.get_info()

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
      shelter_id: shelter_info.shelter_id,
      shelter_name: shelter_info.shelter_name,
      added_at: timestamp,
      updated_at: timestamp,
      adopted_at: nil,
      adopted_by: nil
    }

    DeltaCrdt.put(pets_crdt, pet_id, pet)
    PubSubBroadcaster.broadcast(:pet_added, pet)

    Logger.info("Pet added: #{pet.name} (#{pet_id}) at #{shelter_info.shelter_name}")

    {:ok, pet}
  end

  @doc """
  Updates an existing pet.
  """
  def update_pet(pet_id, updates) do
    pets_crdt = CrdtStore.pets_crdt()

    case DeltaCrdt.get(pets_crdt, pet_id) do
      nil ->
        {:error, :not_found}

      pet ->
        updated_pet =
          pet
          |> Map.merge(updates)
          |> Map.put(:updated_at, DateTime.utc_now())

        DeltaCrdt.put(pets_crdt, pet_id, updated_pet)
        PubSubBroadcaster.broadcast(:pet_updated, updated_pet)

        {:ok, updated_pet}
    end
  end

  @doc """
  Removes a pet from the system.
  """
  def remove_pet(pet_id, reason \\ :adopted) do
    pets_crdt = CrdtStore.pets_crdt()

    case DeltaCrdt.get(pets_crdt, pet_id) do
      nil ->
        {:error, :not_found}

      pet ->
        removed_pet =
          pet
          |> Map.put(:status, :removed)
          |> Map.put(:removed_reason, reason)
          |> Map.put(:updated_at, DateTime.utc_now())

        DeltaCrdt.put(pets_crdt, pet_id, removed_pet)
        PubSubBroadcaster.broadcast(:pet_removed, removed_pet)

        {:ok, removed_pet}
    end
  end

  @doc """
  Gets a single pet by ID.
  """
  def get_pet(pet_id) do
    pets_crdt = CrdtStore.pets_crdt()
    DeltaCrdt.get(pets_crdt, pet_id)
  end

  @doc """
  Lists pets with optional filter.
  Filter can be :all, :available, :adopted, or :removed.
  """
  def list_pets(filter \\ :all) do
    pets_crdt = CrdtStore.pets_crdt()

    pets_crdt
    |> DeltaCrdt.to_map()
    |> Map.values()
    |> filter_pets(filter)
    |> Enum.sort_by(& &1.added_at, {:desc, DateTime})
  end

  @doc """
  Marks a pet as adopted.
  """
  def mark_adopted(pet_id, adopted_by) do
    pets_crdt = CrdtStore.pets_crdt()

    case DeltaCrdt.get(pets_crdt, pet_id) do
      nil ->
        {:error, :not_found}

      pet ->
        adopted_pet =
          pet
          |> Map.put(:status, :adopted)
          |> Map.put(:adopted_by, adopted_by)
          |> Map.put(:adopted_at, DateTime.utc_now())
          |> Map.put(:updated_at, DateTime.utc_now())

        DeltaCrdt.put(pets_crdt, pet_id, adopted_pet)

        {:ok, adopted_pet}
    end
  end

  # Private Functions

  defp generate_pet_id do
    "pet_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp filter_pets(pets, :all), do: pets
  defp filter_pets(pets, :available), do: Enum.filter(pets, &(&1.status == :available))
  defp filter_pets(pets, :adopted), do: Enum.filter(pets, &(&1.status == :adopted))
  defp filter_pets(pets, :removed), do: Enum.filter(pets, &(&1.status == :removed))
end
