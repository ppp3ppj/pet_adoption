defmodule PetAdoption.Schemas.AdoptionApplication do  # ← Changed from Application
  @moduledoc """
  Adoption application schema with changeset validations.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :string, autogenerate: false}
  embedded_schema do
    field :pet_id, :string
    field :applicant_name, :string
    field :applicant_email, :string
    field :applicant_phone, :string
    field :has_experience, :boolean, default: false
    field :has_other_pets, :boolean, default: false
    field :home_type, :string
    field :reason, :string
    field :status, Ecto.Enum, values: [:pending, :approved, :rejected], default: :pending
    field :submitted_at, :utc_datetime
    field :reviewed_at, :utc_datetime
    field :reviewed_by, :string
  end

  @doc """
  Changeset for creating a new application.
  """
  def create_changeset(application \\ %__MODULE__{}, attrs) do
    application
    |> cast(attrs, [
      :id,
      :pet_id,
      :applicant_name,
      :applicant_email,
      :applicant_phone,
      :has_experience,
      :has_other_pets,
      :home_type,
      :reason
    ])
    |> validate_required([
      :pet_id,
      :applicant_name,
      :applicant_email,
      :applicant_phone,
      :home_type,
      :reason
    ])
    |> validate_length(:applicant_name, min: 2, max: 100)
    |> validate_format(:applicant_email, ~r/@/)
    |> validate_length(:applicant_phone, min: 7, max: 20)
    |> validate_inclusion(:home_type, ["House", "Apartment", "Condo", "Farm"])
    |> validate_length(:reason, min: 10, max: 1000)
    |> put_change(:submitted_at, DateTime.utc_now())
    |> put_change(:status, :pending)
  end

  @doc """
  Changeset for form validation (public adoption form).
  Maps friendly form field names to schema fields.
  """
  def form_changeset(application \\ %__MODULE__{}, attrs) do
    # Map form field names to schema field names
    mapped_attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("applicant_name", attrs["applicant_name"] || attrs[:applicant_name])
      |> Map.put("applicant_email", attrs["applicant_email"] || attrs[:applicant_email])
      |> Map.put("applicant_phone", attrs["applicant_phone"] || attrs[:applicant_phone])
      |> Map.put("has_experience", parse_boolean(attrs["has_experience"] || attrs[:has_experience]))
      |> Map.put("has_other_pets", parse_boolean(attrs["has_other_pets"] || attrs[:has_other_pets]))

    application
    |> cast(mapped_attrs, [
      :pet_id,
      :applicant_name,
      :applicant_email,
      :applicant_phone,
      :has_experience,
      :has_other_pets,
      :home_type,
      :reason
    ])
    |> validate_required([
      :applicant_name,
      :applicant_email,
      :applicant_phone,
      :home_type,
      :reason
    ])
    |> validate_length(:applicant_name, min: 2, max: 100)
    |> validate_format(:applicant_email, ~r/@/, message: "must be a valid email")
    |> validate_length(:applicant_phone, min: 7, max: 20)
    |> validate_inclusion(:home_type, ["House", "Apartment", "Condo", "Farm"])
    |> validate_length(:reason, min: 10, max: 1000, message: "must be between 10 and 1000 characters")
  end

  defp parse_boolean("true"), do: true
  defp parse_boolean("false"), do: false
  defp parse_boolean(true), do: true
  defp parse_boolean(false), do: false
  defp parse_boolean(_), do: nil

  @doc """
  Changeset for approving an application.
  """
  def approve_changeset(application, reviewer_name) do
    application
    |> change()
    |> put_change(:status, :approved)
    |> put_change(:reviewed_at, DateTime.utc_now())
    |> put_change(:reviewed_by, reviewer_name)
  end

  @doc """
  Changeset for rejecting an application.
  """
  def reject_changeset(application, reviewer_name) do
    application
    |> change()
    |> put_change(:status, :rejected)
    |> put_change(:reviewed_at, DateTime.utc_now())
    |> put_change(:reviewed_by, reviewer_name)
  end

  @doc """
  Converts the struct to a map for CRDT storage.
  """
  def to_map(%__MODULE__{} = application) do
    application
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
