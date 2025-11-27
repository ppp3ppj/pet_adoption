defmodule PetAdoption.Stats do
  @moduledoc """
  Handles statistics calculation for pets and applications.
  """

  alias PetAdoption.CrdtStore

  @doc """
  Gets comprehensive statistics about pets and applications.
  """
  def get_stats do
    pets_crdt = CrdtStore.pets_crdt()
    applications_crdt = CrdtStore.applications_crdt()

    all_pets = DeltaCrdt.to_map(pets_crdt) |> Map.values()
    all_apps = DeltaCrdt.to_map(applications_crdt) |> Map.values()

    %{
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
  end

  @doc """
  Counts pets by species (only available pets).
  """
  def count_by_species(pets) do
    pets
    |> Enum.filter(&(&1.status == :available))
    |> Enum.group_by(& &1.species)
    |> Enum.map(fn {species, species_pets} -> {species, length(species_pets)} end)
    |> Enum.into(%{})
  end

  @doc """
  Gets recent adoptions up to the specified limit.
  """
  def get_recent_adoptions(pets, limit) do
    pets
    |> Enum.filter(&(&1.status == :adopted))
    |> Enum.sort_by(& &1.adopted_at, {:desc, DateTime})
    |> Enum.take(limit)
  end

  @doc """
  Increments the total applications counter.
  """
  def increment_applications do
    stats_crdt = CrdtStore.stats_crdt()
    current = DeltaCrdt.get(stats_crdt, :total_applications) || 0
    DeltaCrdt.put(stats_crdt, :total_applications, current + 1)
  end

  @doc """
  Increments the total adoptions counter.
  """
  def increment_adoptions do
    stats_crdt = CrdtStore.stats_crdt()
    current = DeltaCrdt.get(stats_crdt, :total_adoptions) || 0
    DeltaCrdt.put(stats_crdt, :total_adoptions, current + 1)
  end
end
