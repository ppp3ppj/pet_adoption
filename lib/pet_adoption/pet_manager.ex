defmodule PetAdoption.PetManager do
  @moduledoc """
  Facade module that provides the main API for pet adoption operations.
  Delegates to specialized modules for actual implementation.
  """

  alias PetAdoption.Pets
  alias PetAdoption.Applications
  alias PetAdoption.Stats
  alias PetAdoption.Shelter
  alias PetAdoption.Cluster

  # Pet Operations

  @doc """
  Adds a new pet to the system.
  """
  defdelegate add_pet(pet_data), to: Pets

  @doc """
  Updates an existing pet.
  """
  defdelegate update_pet(pet_id, updates), to: Pets

  @doc """
  Removes a pet from the system.
  """
  def remove_pet(pet_id, reason \\ :adopted) do
    Pets.remove_pet(pet_id, reason)
  end

  @doc """
  Lists pets with optional filter (:all, :available, :adopted, :removed).
  """
  def list_pets(filter \\ :all) do
    Pets.list_pets(filter)
  end

  @doc """
  Gets a single pet by ID.
  """
  defdelegate get_pet(pet_id), to: Pets

  # Application Operations

  @doc """
  Submits a new adoption application.
  """
  defdelegate submit_application(pet_id, application_data), to: Applications

  @doc """
  Approves an adoption application.
  """
  defdelegate approve_adoption(pet_id, application_id), to: Applications

  @doc """
  Gets all applications for a specific pet.
  """
  defdelegate get_applications(pet_id), to: Applications

  # Stats Operations

  @doc """
  Gets comprehensive statistics.
  """
  defdelegate get_stats(), to: Stats

  # Shelter Operations

  @doc """
  Gets shelter information.
  """
  def get_shelter_info do
    Shelter.get_detailed_info()
  end

  # Cluster Operations

  @doc """
  Simulates a network partition for testing.
  """
  def simulate_partition(duration_ms \\ 5000) do
    Cluster.simulate_partition(duration_ms)
  end
end
