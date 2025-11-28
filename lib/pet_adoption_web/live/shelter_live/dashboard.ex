defmodule PetAdoptionWeb.ShelterLive.Dashboard do
  use PetAdoptionWeb, :live_view
  require Logger

  alias PetAdoption.PetManager
  alias PetAdoption.Schemas.Pet

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PetAdoption.PubSub, "pet_updates")
    end

    socket =
      socket
      |> assign(:page_title, "Shelter Dashboard")
      |> assign(:active_tab, :pets)
      |> assign(:show_add_pet_modal, false)
      |> assign(:show_edit_pet_modal, false)
      |> assign(:show_application_modal, false)
      |> assign(:selected_pet, nil)
      |> assign(:editing_pet, nil)
      |> assign(:pet_applications, [])
      |> assign_pet_form(Pet.form_changeset(%Pet{}, %{}))
      |> assign_edit_pet_form(Pet.form_changeset(%Pet{}, %{}))
      |> load_data()

    {:ok, socket}
  end

  defp assign_pet_form(socket, changeset) do
    assign(socket, :pet_form, to_form(changeset, as: :pet))
  end

  defp assign_edit_pet_form(socket, changeset) do
    assign(socket, :edit_pet_form, to_form(changeset, as: :pet))
  end

  # Event Handlers

  @impl true
  def handle_event("validate_pet", %{"pet" => pet_params}, socket) do
    changeset =
      %Pet{}
      |> Pet.form_changeset(pet_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_pet_form(socket, changeset)}
  end

  @impl true
  def handle_event("save_pet", %{"pet" => pet_params}, socket) do
    changeset = Pet.form_changeset(%Pet{}, pet_params)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, _valid_pet} ->
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
              |> put_flash(:info, "Pet added successfully!")
              |> assign(:show_add_pet_modal, false)
              |> assign_pet_form(Pet.form_changeset(%Pet{}, %{}))
              |> load_data()

            {:noreply, socket}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to add pet")}
        end

      {:error, changeset} ->
        {:noreply, assign_pet_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("show_add_pet_modal", _, socket) do
    socket =
      socket
      |> assign(:show_add_pet_modal, true)
      |> assign_pet_form(Pet.form_changeset(%Pet{}, %{}))

    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_add_pet_modal", _, socket) do
    {:noreply, assign(socket, :show_add_pet_modal, false)}
  end

  @impl true
  def handle_event("show_edit_pet_modal", %{"id" => pet_id}, socket) do
    pet = PetManager.get_pet(pet_id)

    if pet do
      # Convert pet map to form params
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
        |> assign(:show_edit_pet_modal, true)
        |> assign(:editing_pet, pet)
        |> assign_edit_pet_form(changeset)

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Pet not found")}
    end
  end

  @impl true
  def handle_event("hide_edit_pet_modal", _, socket) do
    socket =
      socket
      |> assign(:show_edit_pet_modal, false)
      |> assign(:editing_pet, nil)

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_edit_pet", %{"pet" => pet_params}, socket) do
    changeset =
      %Pet{}
      |> Pet.form_changeset(pet_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_edit_pet_form(socket, changeset)}
  end

  @impl true
  def handle_event("update_pet", %{"pet" => pet_params}, socket) do
    editing_pet = socket.assigns.editing_pet
    changeset = Pet.form_changeset(%Pet{}, pet_params)

    case Ecto.Changeset.apply_action(changeset, :update) do
      {:ok, _valid_pet} ->
        updates = %{
          name: pet_params["name"],
          species: pet_params["species"],
          breed: pet_params["breed"],
          age: String.to_integer(pet_params["age"]),
          gender: pet_params["gender"],
          description: pet_params["description"],
          health_status: pet_params["health_status"] || "Healthy"
        }

        case PetManager.update_pet(editing_pet.id, updates) do
          {:ok, _pet} ->
            socket =
              socket
              |> put_flash(:info, "Pet updated successfully!")
              |> assign(:show_edit_pet_modal, false)
              |> assign(:editing_pet, nil)
              |> assign_edit_pet_form(Pet.form_changeset(%Pet{}, %{}))
              |> load_data()

            {:noreply, socket}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to update pet")}
        end

      {:error, changeset} ->
        {:noreply, assign_edit_pet_form(socket, changeset)}
    end
  end

  @impl true
  def handle_event("view_pet", %{"id" => pet_id}, socket) do
    pet = PetManager.get_pet(pet_id)
    applications = PetManager.get_applications(pet_id)

    socket =
      socket
      |> assign(:selected_pet, pet)
      |> assign(:pet_applications, applications)
      |> assign(:show_application_modal, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_application_modal", _, socket) do
    {:noreply, assign(socket, :show_application_modal, false)}
  end

  @impl true
  def handle_event("approve_adoption", %{"pet_id" => pet_id, "app_id" => app_id}, socket) do
    case PetManager.approve_adoption(pet_id, app_id) do
      {:ok, _pet} ->
        socket =
          socket
          |> put_flash(:info, "Adoption approved!")
          |> assign(:show_application_modal, false)
          |> load_data()

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve adoption")}
    end
  end

  @impl true
  def handle_event("remove_pet", %{"id" => pet_id}, socket) do
    case PetManager.remove_pet(pet_id, :other) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(:info, "Pet removed from listings")
          |> load_data()

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove pet")}
    end
  end

  @impl true
  def handle_event("change_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, String.to_existing_atom(tab))}
  end

  @impl true
  def handle_event("simulate_partition", %{"duration" => duration}, socket) do
    duration_ms = String.to_integer(duration) * 1000
    PetManager.simulate_partition(duration_ms)

    socket = put_flash(socket, :info, "Simulating network partition for #{duration}s")
    {:noreply, socket}
  end

  # Info Handlers

  @impl true
  def handle_info({:pet_update, type, _data}, socket) do
    # Reload data for any pet update type (:pet_added, :pet_updated, :pet_removed, :sync, etc.)
    Logger.debug("Received pet update: #{inspect(type)}")
    {:noreply, load_data(socket)}
  end

  # Private Functions

  defp load_data(socket) do
    shelter_info = PetManager.get_shelter_info()
    stats = PetManager.get_stats()
    available_pets = PetManager.list_pets(:available)
    adopted_pets = PetManager.list_pets(:adopted)

    socket
    |> assign(:shelter_info, shelter_info)
    |> assign(:stats, stats)
    |> assign(:available_pets, available_pets)
    |> assign(:adopted_pets, adopted_pets)
    |> assign(:last_updated, DateTime.utc_now())
  end

  # Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-base-200">
        <div class="container mx-auto px-4 py-8">
          <!-- Header Card -->
          <div class="card bg-base-100 shadow-xl mb-8">
            <div class="card-body">
              <div class="flex flex-col md:flex-row items-start md:items-center justify-between gap-4">
                <div>
                  <h1 class="card-title text-3xl md:text-4xl">
                    🐾 {@shelter_info.shelter_name}
                  </h1>
                  <p class="text-base-content/70">Distributed Pet Adoption Network</p>
                </div>
                <div class="text-right">
                  <p class="text-sm text-base-content/60">
                    Node: <code class="badge badge-ghost">{@shelter_info.node_id}</code>
                  </p>
                  <p class="text-sm text-base-content/60">
                    Connected Shelters:
                    <span class="badge badge-primary">{length(@shelter_info.connected_nodes)}</span>
                  </p>
                </div>
              </div>
            </div>
          </div>

          <!-- Stats Cards -->
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
            <.stat_card
              title="Available Pets"
              value={@stats.available_pets}
              icon="🐕"
              color="success"
            />
            <.stat_card title="Adopted Pets" value={@stats.adopted_pets} icon="❤️" color="secondary" />
            <.stat_card
              title="Pending Apps"
              value={@stats.pending_applications}
              icon="📋"
              color="info"
            />
            <.stat_card
              title="Network Shelters"
              value={@stats.total_shelters}
              icon="🏥"
              color="primary"
            />
          </div>

          <!-- Action Bar -->
          <div class="card bg-base-100 shadow mb-6">
            <div class="card-body py-4">
              <div class="flex flex-wrap gap-2 items-center">
                <button phx-click="show_add_pet_modal" class="btn btn-success">
                  <.icon name="hero-plus" class="w-5 h-5" /> Add Pet
                </button>

                <div class="join">
                  <button
                    phx-click="change_tab"
                    phx-value-tab="pets"
                    class={["join-item btn", @active_tab == :pets && "btn-primary"]}
                  >
                    Available Pets
                  </button>
                  <button
                    phx-click="change_tab"
                    phx-value-tab="adopted"
                    class={["join-item btn", @active_tab == :adopted && "btn-primary"]}
                  >
                    Adopted Pets
                  </button>
                </div>

                <div class="ml-auto">
                  <button
                    phx-click="simulate_partition"
                    phx-value-duration="5"
                    class="btn btn-error btn-sm"
                  >
                    <.icon name="hero-bolt-slash" class="w-4 h-4" /> Partition 5s
                  </button>
                </div>
              </div>
            </div>
          </div>

          <!-- Pets Grid -->
          <%= if @active_tab == :pets do %>
            <.pets_grid pets={@available_pets} type={:available} />
          <% else %>
            <.pets_grid pets={@adopted_pets} type={:adopted} />
          <% end %>

          <!-- Footer -->
          <div class="mt-8 text-center text-base-content/60 text-sm">
            <p>Last updated: {Calendar.strftime(@last_updated, "%H:%M:%S UTC")}</p>
          </div>
        </div>

        <!-- Add Pet Modal -->
        <.add_pet_modal :if={@show_add_pet_modal} form={@pet_form} />

        <!-- Edit Pet Modal -->
        <.edit_pet_modal :if={@show_edit_pet_modal && @editing_pet} form={@edit_pet_form} pet={@editing_pet} />

        <!-- Application Modal -->
        <.application_modal
          :if={@show_application_modal && @selected_pet}
          pet={@selected_pet}
          applications={@pet_applications}
        />
      </div>
    </Layouts.app>
    """
  end

  # Components

  defp stat_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow">
      <div class="card-body py-4">
        <div class="flex items-center justify-between">
          <div>
            <p class="text-base-content/60 text-sm">{@title}</p>
            <p class={"text-3xl font-bold text-#{@color}"}>{@value}</p>
          </div>
          <div class="text-4xl">{@icon}</div>
        </div>
      </div>
    </div>
    """
  end

  defp pets_grid(assigns) do
    ~H"""
    <%= if @pets == [] do %>
      <div class="card bg-base-100 shadow">
        <div class="card-body items-center text-center py-12">
          <div class="text-6xl mb-4">🐾</div>
          <h3 class="text-xl font-semibold">No pets found</h3>
          <p class="text-base-content/60">
            <%= if @type == :available do %>
              Add your first pet to get started!
            <% else %>
              No pets have been adopted yet.
            <% end %>
          </p>
        </div>
      </div>
    <% else %>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <%= for pet <- @pets do %>
          <.pet_card pet={pet} type={@type} />
        <% end %>
      </div>
    <% end %>
    """
  end

  defp pet_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-shadow">
      <figure class={[
        "h-48 flex items-center justify-center",
        @type == :available && "bg-gradient-to-br from-primary/20 to-secondary/20",
        @type == :adopted && "bg-gradient-to-br from-secondary/20 to-accent/20"
      ]}>
        <span class="text-8xl">{pet_emoji(@pet.species)}</span>
      </figure>
      <div class="card-body">
        <h2 class="card-title">
          {@pet.name}
          <span class="badge badge-secondary badge-sm">{@pet.species}</span>
        </h2>
        <p class="text-base-content/70">{@pet.breed} • {@pet.age} years • {@pet.gender}</p>
        <p class="line-clamp-2">{@pet.description}</p>

        <%= if @type == :available do %>
          <div class="flex items-center justify-between mt-2">
            <span class="text-sm text-base-content/60">@ {@pet.shelter_name}</span>
            <span class="badge badge-success badge-outline">{@pet.health_status}</span>
          </div>
          <div class="card-actions justify-end mt-4">
            <button phx-click="view_pet" phx-value-id={@pet.id} class="btn btn-primary btn-sm">
              <.icon name="hero-eye" class="w-4 h-4" /> Applications
            </button>
            <button phx-click="show_edit_pet_modal" phx-value-id={@pet.id} class="btn btn-secondary btn-sm">
              <.icon name="hero-pencil-square" class="w-4 h-4" /> Edit
            </button>
            <button
              phx-click="remove_pet"
              phx-value-id={@pet.id}
              data-confirm="Are you sure you want to remove this pet?"
              class="btn btn-error btn-sm btn-outline"
            >
              <.icon name="hero-trash" class="w-4 h-4" />
            </button>
          </div>
        <% else %>
          <div class="alert alert-success mt-4">
            <div>
              <p class="font-semibold">✅ Adopted by: {@pet.adopted_by}</p>
              <p class="text-sm">{format_datetime(@pet.adopted_at)}</p>
            </div>
          </div>
          <p class="text-sm text-base-content/60 mt-2">From: {@pet.shelter_name}</p>
        <% end %>
      </div>
    </div>
    """
  end

  defp add_pet_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-2xl">
        <h3 class="font-bold text-2xl mb-6">Add New Pet</h3>

        <.form for={@form} id="pet-form" phx-change="validate_pet" phx-submit="save_pet">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input field={@form[:name]} type="text" label="Name" placeholder="Enter pet name" />
            <.input
              field={@form[:species]}
              type="select"
              label="Species"
              prompt="Select species..."
              options={["Dog", "Cat", "Rabbit", "Bird", "Other"]}
            />
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
            <.input
              field={@form[:breed]}
              type="text"
              label="Breed"
              placeholder="e.g., Golden Retriever"
            />
            <.input
              field={@form[:age]}
              type="number"
              label="Age (years)"
              placeholder="0-30"
              min="0"
              max="30"
            />
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
            <.input
              field={@form[:gender]}
              type="select"
              label="Gender"
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
              label="Description"
              placeholder="Tell us about this pet..."
              rows="3"
            />
          </div>

          <div class="modal-action">
            <button type="submit" class="btn btn-primary" phx-disable-with="Saving...">
              <.icon name="hero-check" class="w-5 h-5" /> Add Pet
            </button>
            <button type="button" phx-click="hide_add_pet_modal" class="btn">Cancel</button>
          </div>
        </.form>
      </div>
      <div class="modal-backdrop bg-base-300/50" phx-click="hide_add_pet_modal"></div>
    </div>
    """
  end

  defp edit_pet_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-2xl">
        <h3 class="font-bold text-2xl mb-6">
          <.icon name="hero-pencil-square" class="w-6 h-6 inline-block mr-2" />
          Edit Pet: {@pet.name}
        </h3>

        <.form for={@form} id="edit-pet-form" phx-change="validate_edit_pet" phx-submit="update_pet">
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input field={@form[:name]} type="text" label="Name" placeholder="Enter pet name" />
            <.input
              field={@form[:species]}
              type="select"
              label="Species"
              prompt="Select species..."
              options={["Dog", "Cat", "Rabbit", "Bird", "Other"]}
            />
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
            <.input
              field={@form[:breed]}
              type="text"
              label="Breed"
              placeholder="e.g., Golden Retriever"
            />
            <.input
              field={@form[:age]}
              type="number"
              label="Age (years)"
              placeholder="0-30"
              min="0"
              max="30"
            />
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
            <.input
              field={@form[:gender]}
              type="select"
              label="Gender"
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
              label="Description"
              placeholder="Tell us about this pet..."
              rows="3"
            />
          </div>

          <div class="modal-action">
            <button type="submit" class="btn btn-primary" phx-disable-with="Updating...">
              <.icon name="hero-check" class="w-5 h-5" /> Update Pet
            </button>
            <button type="button" phx-click="hide_edit_pet_modal" class="btn">Cancel</button>
          </div>
        </.form>
      </div>
      <div class="modal-backdrop bg-base-300/50" phx-click="hide_edit_pet_modal"></div>
    </div>
    """
  end

  defp application_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-3xl">
        <h3 class="font-bold text-2xl">{@pet.name}</h3>
        <p class="text-base-content/70 mb-6">
          {@pet.breed} • {@pet.age} years • {@pet.gender}
        </p>

        <h4 class="font-semibold text-lg mb-4">
          Applications
          <span class="badge badge-neutral ml-2">{length(@applications)}</span>
        </h4>

        <%= if @applications == [] do %>
          <div class="alert">
            <.icon name="hero-inbox" class="w-6 h-6" />
            <span>No applications yet.</span>
          </div>
        <% else %>
          <div class="space-y-4 max-h-96 overflow-y-auto">
            <%= for app <- @applications do %>
              <.application_card app={app} pet={@pet} />
            <% end %>
          </div>
        <% end %>

        <div class="modal-action">
          <button phx-click="hide_application_modal" class="btn">Close</button>
        </div>
      </div>
      <div class="modal-backdrop bg-base-300/50" phx-click="hide_application_modal"></div>
    </div>
    """
  end

  defp application_card(assigns) do
    ~H"""
    <div class={[
      "card bg-base-200 border",
      application_border_class(@app.status)
    ]}>
      <div class="card-body py-4">
        <div class="flex items-start justify-between">
          <div>
            <p class="font-bold">{@app.applicant_name}</p>
            <p class="text-sm text-base-content/70">
              {@app.applicant_email} • {@app.applicant_phone}
            </p>
          </div>
          <span class={["badge", application_badge_class(@app.status)]}>
            {String.upcase(to_string(@app.status))}
          </span>
        </div>

        <p class="mt-2"><strong>Reason:</strong> {@app.reason}</p>

        <div class="flex flex-wrap gap-2 mt-2 text-sm">
          <span class="badge badge-outline">
            Experience: {if @app.has_experience, do: "Yes", else: "No"}
          </span>
          <span class="badge badge-outline">
            Other Pets: {if @app.has_other_pets, do: "Yes", else: "No"}
          </span>
          <span class="badge badge-outline">Home: {@app.home_type}</span>
        </div>

        <p class="text-xs text-base-content/60 mt-2">
          Submitted: {format_datetime(@app.submitted_at)}
        </p>

        <%= if @app.status == :pending && @pet.status == :available do %>
          <div class="card-actions justify-end mt-2">
            <button
              phx-click="approve_adoption"
              phx-value-pet_id={@pet.id}
              phx-value-app_id={@app.id}
              class="btn btn-success btn-sm"
            >
              <.icon name="hero-check" class="w-4 h-4" /> Approve Adoption
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Helper Functions

  defp pet_emoji("Dog"), do: "🐕"
  defp pet_emoji("Cat"), do: "🐈"
  defp pet_emoji("Rabbit"), do: "🐰"
  defp pet_emoji("Bird"), do: "🦜"
  defp pet_emoji(_), do: "🐾"

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp application_badge_class(:pending), do: "badge-warning"
  defp application_badge_class(:approved), do: "badge-success"
  defp application_badge_class(:rejected), do: "badge-error"
  defp application_badge_class(_), do: "badge-ghost"

  defp application_border_class(:pending), do: "border-warning"
  defp application_border_class(:approved), do: "border-success bg-success/10"
  defp application_border_class(:rejected), do: "border-error bg-error/10"
  defp application_border_class(_), do: ""
end
