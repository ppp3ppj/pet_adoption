defmodule PetAdoption.Schemas.Pet do
  @moduledoc """
  Pet schema with changeset validations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  embedded_schema do
    field :name, :string
    field :species, :string
    field :breed, :string
    field :age, :integer
    field :gender, :string
    field :description, :string
    field :health_status, :string, default: "Healthy"
    field :status, Ecto.Enum, values: [:available, :adopted, :removed], default: :available
    field :shelter_id, :string
    field :shelter_name, :string
    field :added_at, :utc_datetime
    field :updated_at, :utc_datetime
    field :adopted_at, :utc_datetime
    field :adopted_by, :string
    field :removed_reason, :string  # ✅ Fixed: Use :string instead of :atom
  end

  @doc """
  Changeset for creating a new pet.
  """
  def create_changeset(pet \\ %__MODULE__{}, attrs) do
    pet
    |> cast(attrs, [
      :id,
      :name,
      :species,
      :breed,
      :age,
      :gender,
      :description,
      :health_status,
      :shelter_id,
      :shelter_name
    ])
    |> validate_required([
      :id,
      :name,
      :species,
      :breed,
      :age,
      :gender,
      :description,
      :shelter_id,
      :shelter_name
    ])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_length(:breed, min: 2, max: 100)
    |> validate_number(:age, greater_than_or_equal_to: 0, less_than_or_equal_to: 30)
    |> validate_inclusion(:species, ["Dog", "Cat", "Rabbit", "Bird", "Other"])
    |> validate_inclusion(:gender, ["Male", "Female"])
    |> put_timestamps()
    |> put_change(:status, :available)
  end

  @doc """
  Changeset for updating a pet.
  """
  def update_changeset(pet, attrs) do
    pet
    |> cast(attrs, [
      :name,
      :species,
      :breed,
      :age,
      :gender,
      :description,
      :health_status,
      :status,
      :adopted_at,
      :adopted_by,
      :removed_reason
    ])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_length(:breed, min: 2, max: 100)
    |> validate_number(:age, greater_than_or_equal_to: 0, less_than_or_equal_to: 30)
    |> put_change(:updated_at, DateTime.utc_now())
  end

  @doc """
  Changeset for adopting a pet.
  """
  def adopt_changeset(pet, adopter_name) do
    pet
    |> change()
    |> put_change(:status, :adopted)
    |> put_change(:adopted_at, DateTime.utc_now())
    |> put_change(:adopted_by, adopter_name)
    |> put_change(:updated_at, DateTime.utc_now())
  end

  @doc """
  Changeset for removing a pet.
  """
  def remove_changeset(pet, reason) do
    # Convert atom to string if needed
    reason_string = if is_atom(reason), do: Atom.to_string(reason), else: reason

    pet
    |> change()
    |> put_change(:status, :removed)
    |> put_change(:removed_reason, reason_string)
    |> put_change(:updated_at, DateTime.utc_now())
  end

  defp put_timestamps(changeset) do
    now = DateTime.utc_now()

    changeset
    |> put_change(:added_at, now)
    |> put_change(:updated_at, now)
  end

  @doc """
  Converts the struct to a map for CRDT storage.
  """
  def to_map(%__MODULE__{} = pet) do
    pet
    |> Map.from_struct()
    |> Map.drop([:__meta__])
  end

  @doc """
  Converts a map from CRDT to struct.
  """
  def from_map(map) when is_map(map) do
    struct(__MODULE__, map)
  end
end
