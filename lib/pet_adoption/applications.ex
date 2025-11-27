defmodule PetAdoption.Applications do
  @moduledoc """
  Handles adoption application operations: submit, approve, reject, and list applications.
  """
  require Logger

  alias PetAdoption.CrdtStore
  alias PetAdoption.Shelter
  alias PetAdoption.PubSubBroadcaster
  alias PetAdoption.Schemas.Pet
  alias PetAdoption.Schemas.AdoptionApplication

  @doc """
  Submits a new adoption application for a pet.
  """
  def submit_application(pet_id, application_data) do
    pets_crdt = CrdtStore.pets_crdt()
    applications_crdt = CrdtStore.applications_crdt()
    stats_crdt = CrdtStore.stats_crdt()

    pet_map = DeltaCrdt.get(pets_crdt, pet_id)

    if pet_map && pet_map[:status] == :available do
      application_id = generate_application_id()

      attrs =
        application_data
        |> Keyword.put(:id, application_id)
        |> Keyword.put(:pet_id, pet_id)
        |> Enum.into(%{})

      changeset = AdoptionApplication.create_changeset(%AdoptionApplication{}, attrs)

      case Ecto.Changeset.apply_action(changeset, :insert) do
        {:ok, application} ->
          app_map = AdoptionApplication.to_map(application)
          DeltaCrdt.put(applications_crdt, application_id, app_map)

          current_apps = DeltaCrdt.get(stats_crdt, :total_applications) || 0
          DeltaCrdt.put(stats_crdt, :total_applications, current_apps + 1)

          PubSubBroadcaster.broadcast(:application_submitted, app_map)

          Logger.info("Application submitted for pet #{pet_id} by #{application.applicant_name}")
          {:ok, app_map}

        {:error, changeset} ->
          Logger.error("Failed to submit application: #{inspect(changeset.errors)}")
          {:error, changeset}
      end
    else
      {:error, :pet_not_available}
    end
  end

  @doc """
  Approves an adoption application and marks the pet as adopted.
  """
  def approve_adoption(pet_id, application_id) do
    pets_crdt = CrdtStore.pets_crdt()
    applications_crdt = CrdtStore.applications_crdt()
    stats_crdt = CrdtStore.stats_crdt()
    shelter_info = Shelter.get_info()

    pet_map = DeltaCrdt.get(pets_crdt, pet_id)
    app_map = DeltaCrdt.get(applications_crdt, application_id)

    if pet_map && app_map && pet_map[:status] == :available do
      pet = Pet.from_map(pet_map)
      application = AdoptionApplication.from_map(app_map)

      pet_changeset = Pet.adopt_changeset(pet, application.applicant_name)
      app_changeset = AdoptionApplication.approve_changeset(application, shelter_info.shelter_name)

      with {:ok, adopted_pet} <- Ecto.Changeset.apply_action(pet_changeset, :update),
           {:ok, approved_app} <- Ecto.Changeset.apply_action(app_changeset, :update) do
        adopted_pet_map = Pet.to_map(adopted_pet)
        approved_app_map = AdoptionApplication.to_map(approved_app)

        DeltaCrdt.put(pets_crdt, pet_id, adopted_pet_map)
        DeltaCrdt.put(applications_crdt, application_id, approved_app_map)

        current_adoptions = DeltaCrdt.get(stats_crdt, :total_adoptions) || 0
        DeltaCrdt.put(stats_crdt, :total_adoptions, current_adoptions + 1)

        reject_other_applications(pet_id, application_id)

        PubSubBroadcaster.broadcast(:pet_adopted, %{pet: adopted_pet_map, application: approved_app_map})

        Logger.info("Pet #{adopted_pet.name} adopted by #{application.applicant_name}")

        {:ok, adopted_pet_map}
      else
        {:error, changeset} ->
          Logger.error("Failed to approve adoption: #{inspect(changeset.errors)}")
          {:error, changeset}
      end
    else
      {:error, :cannot_approve}
    end
  end

  @doc """
  Gets all applications for a specific pet.
  """
  def get_applications(pet_id) do
    applications_crdt = CrdtStore.applications_crdt()

    applications_crdt
    |> DeltaCrdt.to_map()
    |> Map.values()
    |> Enum.filter(&(&1.pet_id == pet_id))
    |> Enum.sort_by(& &1.submitted_at, {:desc, DateTime})
  end

  @doc """
  Gets all applications in the system.
  """
  def list_all_applications do
    applications_crdt = CrdtStore.applications_crdt()

    applications_crdt
    |> DeltaCrdt.to_map()
    |> Map.values()
    |> Enum.sort_by(& &1.submitted_at, {:desc, DateTime})
  end

  # Private Functions

  defp generate_application_id do
    "app_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp reject_other_applications(pet_id, approved_application_id) do
    applications_crdt = CrdtStore.applications_crdt()
    shelter_info = Shelter.get_info()

    applications_crdt
    |> DeltaCrdt.to_map()
    |> Enum.each(fn {app_id, app} ->
      if app.pet_id == pet_id && app.id != approved_application_id && app.status == :pending do
        rejected_app =
          app
          |> Map.put(:status, :rejected)
          |> Map.put(:reviewed_at, DateTime.utc_now())
          |> Map.put(:reviewed_by, shelter_info.shelter_name)

        DeltaCrdt.put(applications_crdt, app_id, rejected_app)
      end
    end)
  end
end
