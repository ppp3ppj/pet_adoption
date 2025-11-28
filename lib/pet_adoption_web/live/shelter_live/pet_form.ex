defmodule PetAdoptionWeb.ShelterLive.PetForm do
  @moduledoc """
  Dedicated page for adding and editing pets.
  Isolated from PubSub updates to prevent form interruption.
  """
  use PetAdoptionWeb, :live_view

  alias PetAdoption.PetManager
  alias PetAdoption.Schemas.Pet

  @impl true
  def mount(%{"id" => pet_id}, _session, socket) do
    # Edit mode
    pet = PetManager.get_pet(pet_id)

    if pet do
      pet_params = %{
        "name" => pet.name,
        "species" => pet.species,
        "breed" => pet.breed,
        "age" => to_string(pet.age),
        "gender" => pet.gender,
        "description" => pet.description,
        "health_status" => pet.health_status
      }

      changeset = Pet.form_changeset(%Pet{}, pet_params)

      socket =
        socket
        |> assign(:page_title, "Edit #{pet.name}")
        |> assign(:mode, :edit)
        |> assign(:pet, pet)
        |> assign(:submitting, false)
        |> assign_form(changeset)

      {:ok, socket}
    else
      socket =
        socket
        |> put_flash(:error, "Pet not found.")
        |> redirect(to: ~p"/shelter/dashboard")

      {:ok, socket}
    end
  end

  def mount(_params, _session, socket) do
    # Add mode
    changeset = Pet.form_changeset(%Pet{}, %{})

    socket =
      socket
      |> assign(:page_title, "Add New Pet")
      |> assign(:mode, :new)
      |> assign(:pet, nil)
      |> assign(:submitting, false)
      |> assign_form(changeset)

    {:ok, socket}
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :pet))
  end

  # Event Handlers

  @impl true
  def handle_event("validate", %{"pet" => pet_params}, socket) do
    changeset =
      %Pet{}
      |> Pet.form_changeset(pet_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"pet" => pet_params}, socket) do
    changeset = Pet.form_changeset(%Pet{}, pet_params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, _valid_pet} ->
        socket = assign(socket, :submitting, true)

        case PetManager.add_pet(
               name: pet_params["name"],
               species: pet_params["species"],
               breed: pet_params["breed"],
               age: String.to_integer(pet_params["age"]),
               gender: pet_params["gender"],
               description: pet_params["description"],
               health_status: pet_params["health_status"] || "Healthy"
             ) do
          {:ok, _pet} ->
            socket =
              socket
              |> put_flash(:info, "🎉 Pet added successfully!")
              |> redirect(to: ~p"/shelter/dashboard")

            {:noreply, socket}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:submitting, false)
             |> put_flash(:error, "Failed to add pet. Please try again.")}
        end

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("update", %{"pet" => pet_params}, socket) do
    changeset = Pet.form_changeset(%Pet{}, pet_params)

    case Ecto.Changeset.apply_action(changeset, :update) do
      {:ok, _valid_pet} ->
        socket = assign(socket, :submitting, true)

        updates = %{
          name: pet_params["name"],
          species: pet_params["species"],
          breed: pet_params["breed"],
          age: String.to_integer(pet_params["age"]),
          gender: pet_params["gender"],
          description: pet_params["description"],
          health_status: pet_params["health_status"] || "Healthy"
        }

        case PetManager.update_pet(socket.assigns.pet.id, updates) do
          {:ok, _pet} ->
            socket =
              socket
              |> put_flash(:info, "✅ Pet updated successfully!")
              |> redirect(to: ~p"/shelter/dashboard")

            {:noreply, socket}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:submitting, false)
             |> put_flash(:error, "Failed to update pet. Please try again.")}
        end

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-base-200 py-8">
        <div class="container mx-auto px-4 max-w-2xl">
          <!-- Back Button -->
          <.link navigate={~p"/shelter/dashboard"} class="btn btn-ghost mb-6">
            <.icon name="hero-arrow-left" class="w-5 h-5" /> Back to Dashboard
          </.link>

          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <h1 class="card-title text-3xl mb-2">
                <%= if @mode == :new do %>
                  <.icon name="hero-plus-circle" class="w-8 h-8" /> Add New Pet
                <% else %>
                  <.icon name="hero-pencil-square" class="w-8 h-8" /> Edit {@pet.name}
                <% end %>
              </h1>
              <p class="text-base-content/70 mb-6">
                <%= if @mode == :new do %>
                  Fill out the form below to add a new pet to your shelter.
                <% else %>
                  Update the information for this pet.
                <% end %>
              </p>

              <.form
                for={@form}
                id="pet-form"
                phx-change="validate"
                phx-submit={if @mode == :new, do: "save", else: "update"}
              >
                <!-- Basic Information -->
                <div class="bg-base-200 rounded-lg p-4 mb-6">
                  <h3 class="font-semibold text-lg mb-4 flex items-center gap-2">
                    <.icon name="hero-identification" class="w-5 h-5" /> Basic Information
                  </h3>

                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <.input
                      field={@form[:name]}
                      type="text"
                      label="Name *"
                      placeholder="Enter pet name"
                    />
                    <.input
                      field={@form[:species]}
                      type="select"
                      label="Species *"
                      prompt="Select species..."
                      options={["Dog", "Cat", "Rabbit", "Bird", "Other"]}
                    />
                  </div>

                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
                    <.input
                      field={@form[:breed]}
                      type="text"
                      label="Breed *"
                      placeholder="e.g., Golden Retriever"
                    />
                    <.input
                      field={@form[:age]}
                      type="number"
                      label="Age (years) *"
                      placeholder="0-30"
                      min="0"
                      max="30"
                    />
                  </div>
                </div>

                <!-- Details -->
                <div class="bg-base-200 rounded-lg p-4 mb-6">
                  <h3 class="font-semibold text-lg mb-4 flex items-center gap-2">
                    <.icon name="hero-clipboard-document-list" class="w-5 h-5" /> Details
                  </h3>

                  <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                    <.input
                      field={@form[:gender]}
                      type="select"
                      label="Gender *"
                      prompt="Select gender..."
                      options={["Male", "Female"]}
                    />
                    <.input
                      field={@form[:health_status]}
                      type="text"
                      label="Health Status"
                      placeholder="e.g., Healthy, Vaccinated"
                    />
                  </div>

                  <div class="mt-4">
                    <.input
                      field={@form[:description]}
                      type="textarea"
                      label="Description *"
                      placeholder="Tell us about this pet's personality, history, and what makes them special..."
                      rows="4"
                    />
                  </div>
                </div>

                <!-- Submit -->
                <div class="flex flex-col sm:flex-row gap-4 justify-end">
                  <.link navigate={~p"/shelter/dashboard"} class="btn btn-ghost">
                    Cancel
                  </.link>
                  <button
                    type="submit"
                    class="btn btn-primary btn-lg"
                    disabled={@submitting}
                    phx-disable-with={if @mode == :new, do: "Adding...", else: "Updating..."}
                  >
                    <%= if @mode == :new do %>
                      <.icon name="hero-plus" class="w-5 h-5" /> Add Pet
                    <% else %>
                      <.icon name="hero-check" class="w-5 h-5" /> Update Pet
                    <% end %>
                  </button>
                </div>
              </.form>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
