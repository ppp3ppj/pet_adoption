defmodule PetAdoptionWeb.PublicLive.Adopt do
  use PetAdoptionWeb, :live_view
  alias PetAdoption.PetManager
  alias PetAdoption.Schemas.AdoptionApplication

  @refresh_interval 3000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Adopt a Pet")
      |> assign(:filter_species, "All")
      |> assign(:show_application_modal, false)
      |> assign(:selected_pet, nil)
      |> assign_application_form(AdoptionApplication.form_changeset(%AdoptionApplication{}, %{}))
      |> load_pets()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(PetAdoption.PubSub, "pet_updates")
      schedule_refresh(socket)
    end

    {:ok, socket}
  end

  defp assign_application_form(socket, changeset) do
    assign(socket, :application_form, to_form(changeset, as: :application))
  end

  # Event Handlers

  @impl true
  def handle_event("filter_species", %{"species" => species}, socket) do
    {:noreply, assign(socket, :filter_species, species)}
  end

  @impl true
  def handle_event("show_application_form", %{"pet_id" => pet_id}, socket) do
    pet = PetManager.get_pet(pet_id)

    changeset =
      AdoptionApplication.form_changeset(%AdoptionApplication{}, %{"pet_id" => pet_id})

    socket =
      socket
      |> assign(:selected_pet, pet)
      |> assign(:show_application_modal, true)
      |> assign_application_form(changeset)

    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_application_form", _, socket) do
    socket =
      socket
      |> assign(:show_application_modal, false)
      |> assign_application_form(AdoptionApplication.form_changeset(%AdoptionApplication{}, %{}))

    schedule_refresh(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_application", %{"application" => app_params}, socket) do
    pet_id = if socket.assigns.selected_pet, do: socket.assigns.selected_pet.id, else: nil

    changeset =
      %AdoptionApplication{}
      |> AdoptionApplication.form_changeset(Map.put(app_params, "pet_id", pet_id))
      |> Map.put(:action, :validate)

    {:noreply, assign_application_form(socket, changeset)}
  end

  @impl true
  def handle_event("submit_application", %{"application" => app_params}, socket) do
    pet = socket.assigns.selected_pet

    attrs =
      app_params
      |> Map.put("pet_id", pet.id)

    changeset = AdoptionApplication.form_changeset(%AdoptionApplication{}, attrs)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, _valid_app} ->
        # Submit to PetManager
        case PetManager.submit_application(pet.id,
               applicant_name: app_params["applicant_name"],
               applicant_email: app_params["applicant_email"],
               applicant_phone: app_params["applicant_phone"],
               has_experience: app_params["has_experience"] == "true",
               has_other_pets: app_params["has_other_pets"] == "true",
               home_type: app_params["home_type"],
               reason: app_params["reason"]
             ) do
          {:ok, _application} ->
            socket =
              socket
              |> put_flash(:info, "Application submitted successfully! The shelter will contact you soon.")
              |> assign(:show_application_modal, false)
              |> assign_application_form(AdoptionApplication.form_changeset(%AdoptionApplication{}, %{}))
              |> load_pets()

            schedule_refresh(socket)
            {:noreply, socket}

          {:error, :pet_not_available} ->
            socket =
              socket
              |> put_flash(:error, "Sorry, this pet is no longer available.")
              |> assign(:show_application_modal, false)
              |> load_pets()

            schedule_refresh(socket)
            {:noreply, socket}

          {:error, error_changeset} when is_struct(error_changeset, Ecto.Changeset) ->
            {:noreply,
             socket
             |> assign_application_form(error_changeset)
             |> put_flash(:error, "Failed to submit application")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to submit application")}
        end

      {:error, changeset} ->
        {:noreply, assign_application_form(socket, changeset)}
    end
  end

  # Info Handlers

  @impl true
  def handle_info(:refresh, socket) do
    socket = load_pets(socket)
    schedule_refresh(socket)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:pet_update, _type, _data}, socket) do
    {:noreply, load_pets(socket)}
  end

  # Private Functions

  defp load_pets(socket) do
    pets = PetManager.list_pets(:available)
    stats = PetManager.get_stats()

    filtered_pets =
      case socket.assigns[:filter_species] || "All" do
        "All" -> pets
        species -> Enum.filter(pets, &(&1.species == species))
      end

    socket
    |> assign(:all_pets, pets)
    |> assign(:filtered_pets, filtered_pets)
    |> assign(:stats, stats)
    |> assign(:last_updated, DateTime.utc_now())
  end

  defp schedule_refresh(socket) do
    unless socket.assigns.show_application_modal do
      Process.send_after(self(), :refresh, @refresh_interval)
    end
  end

  # Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-base-200">
        <!-- Hero Section -->
        <div class="hero bg-gradient-to-r from-primary to-secondary text-primary-content py-16">
          <div class="hero-content text-center">
            <div class="max-w-3xl">
              <h1 class="text-5xl font-bold mb-4">🐾 Find Your Perfect Companion</h1>
              <p class="text-xl mb-8">Adopt a pet from our network of caring shelters</p>
              <div class="stats stats-horizontal bg-primary-content/10 shadow">
                <div class="stat">
                  <div class="stat-value">{@stats.available_pets}</div>
                  <div class="stat-desc text-primary-content/80">Pets Available</div>
                </div>
                <div class="stat">
                  <div class="stat-value">{@stats.adopted_pets}</div>
                  <div class="stat-desc text-primary-content/80">Happy Adoptions</div>
                </div>
                <div class="stat">
                  <div class="stat-value">{@stats.total_shelters}</div>
                  <div class="stat-desc text-primary-content/80">Partner Shelters</div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="container mx-auto px-4 py-8">
          <!-- Filter Section -->
          <div class="card bg-base-100 shadow-xl mb-8">
            <div class="card-body">
              <h2 class="card-title text-2xl mb-4">
                <.icon name="hero-funnel" class="w-6 h-6" /> Filter by Species
              </h2>
              <div class="flex gap-2 flex-wrap">
                <button
                  phx-click="filter_species"
                  phx-value-species="All"
                  class={["btn", @filter_species == "All" && "btn-primary" || "btn-ghost"]}
                >
                  All ({length(@all_pets)})
                </button>
                <%= for {species, count} <- @stats.pets_by_species do %>
                  <button
                    phx-click="filter_species"
                    phx-value-species={species}
                    class={["btn", @filter_species == species && "btn-primary" || "btn-ghost"]}
                  >
                    {species_emoji(species)} {species} ({count})
                  </button>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Pets Grid -->
          <.pets_grid pets={@filtered_pets} />

          <!-- How It Works Section -->
          <div class="card bg-base-100 shadow-xl mt-12">
            <div class="card-body">
              <h2 class="card-title text-3xl justify-center mb-8">How It Works</h2>
              <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
                <.step_card icon="🔍" title="Browse Pets" description="Search our network of shelters to find your perfect match" />
                <.step_card icon="📝" title="Apply Online" description="Submit your application instantly across all shelters" />
                <.step_card icon="❤️" title="Take Home" description="The shelter will contact you to complete the adoption" />
              </div>
            </div>
          </div>

          <!-- Footer -->
          <div class="mt-8 text-center text-base-content/60 text-sm">
            <p>Last updated: {Calendar.strftime(@last_updated, "%H:%M:%S UTC")}</p>
          </div>
        </div>

        <!-- Application Modal -->
        <.application_modal
          :if={@show_application_modal && @selected_pet}
          pet={@selected_pet}
          form={@application_form}
        />
      </div>
    </Layouts.app>
    """
  end

  # Components

  defp pets_grid(assigns) do
    ~H"""
    <%= if @pets == [] do %>
      <div class="card bg-base-100 shadow-xl">
        <div class="card-body items-center text-center py-16">
          <div class="text-8xl mb-4">🐾</div>
          <h3 class="text-2xl font-semibold">No pets available</h3>
          <p class="text-base-content/60">Check back soon or browse other categories!</p>
        </div>
      </div>
    <% else %>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        <%= for pet <- @pets do %>
          <.pet_card pet={pet} />
        <% end %>
      </div>
    <% end %>
    """
  end

  defp pet_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-all duration-300 hover:-translate-y-1">
      <figure class="h-48 bg-gradient-to-br from-primary/30 via-secondary/30 to-accent/30 flex items-center justify-center">
        <span class="text-8xl">{pet_emoji(@pet.species)}</span>
      </figure>
      <div class="card-body">
        <h2 class="card-title">
          {@pet.name}
          <span class="badge badge-secondary badge-sm">{@pet.species}</span>
        </h2>
        <p class="text-base-content/70">{@pet.breed} • {@pet.age} {if @pet.age == 1, do: "year", else: "years"}</p>
        <p class="line-clamp-2">{@pet.description}</p>

        <div class="flex flex-wrap gap-2 mt-2">
          <span class="badge badge-outline badge-sm">{@pet.gender}</span>
          <span class="badge badge-success badge-outline badge-sm">{@pet.health_status}</span>
        </div>

        <p class="text-sm text-base-content/60 mt-2">
          <.icon name="hero-map-pin" class="w-4 h-4 inline" /> {@pet.shelter_name}
        </p>

        <div class="card-actions justify-end mt-4">
          <button
            phx-click="show_application_form"
            phx-value-pet_id={@pet.id}
            class="btn btn-primary btn-block"
          >
            💝 Apply to Adopt
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp step_card(assigns) do
    ~H"""
    <div class="text-center">
      <div class="text-6xl mb-4">{@icon}</div>
      <h3 class="text-xl font-bold mb-2">{@title}</h3>
      <p class="text-base-content/60">{@description}</p>
    </div>
    """
  end

  defp application_modal(assigns) do
    ~H"""
    <div class="modal modal-open">
      <div class="modal-box max-w-2xl">
        <button
          phx-click="hide_application_form"
          class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
        >
          ✕
        </button>

        <h3 class="font-bold text-2xl">Adopt {@pet.name}</h3>
        <p class="text-base-content/70 mb-6">{@pet.breed} • {@pet.age} years • {@pet.gender}</p>

        <!-- Pet Info Card -->
        <div class="alert alert-info mb-6">
          <div>
            <p class="font-semibold">{@pet.description}</p>
            <p class="text-sm mt-1">Located at: {@pet.shelter_name}</p>
          </div>
        </div>

        <.form
          for={@form}
          id="application-form"
          phx-change="validate_application"
          phx-submit="submit_application"
        >
          <h4 class="font-semibold text-lg mb-4">Your Information</h4>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <.input
              field={@form[:applicant_name]}
              type="text"
              label="Full Name"
              placeholder="John Doe"
            />
            <.input
              field={@form[:applicant_email]}
              type="email"
              label="Email"
              placeholder="john@example.com"
            />
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
            <.input
              field={@form[:applicant_phone]}
              type="tel"
              label="Phone Number"
              placeholder="(555) 123-4567"
            />
            <.input
              field={@form[:home_type]}
              type="select"
              label="Home Type"
              prompt="Select..."
              options={["House", "Apartment", "Condo", "Farm"]}
            />
          </div>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
            <.input
              field={@form[:has_experience]}
              type="select"
              label="Experience with pets?"
              prompt="Select..."
              options={[{"Yes", "true"}, {"No", "false"}]}
            />
            <.input
              field={@form[:has_other_pets]}
              type="select"
              label="Do you have other pets?"
              prompt="Select..."
              options={[{"Yes", "true"}, {"No", "false"}]}
            />
          </div>

          <div class="mt-4">
            <.input
              field={@form[:reason]}
              type="textarea"
              label={"Why do you want to adopt #{@pet.name}?"}
              placeholder="Tell us why you'd be a great match..."
              rows="4"
            />
          </div>

          <div class="modal-action">
            <button type="submit" class="btn btn-primary" phx-disable-with="Submitting...">
              <.icon name="hero-paper-airplane" class="w-5 h-5" /> Submit Application
            </button>
            <button type="button" phx-click="hide_application_form" class="btn">
              Cancel
            </button>
          </div>
        </.form>
      </div>
      <div class="modal-backdrop bg-base-300/50" phx-click="hide_application_form"></div>
    </div>
    """
  end

  # Helper Functions

  defp pet_emoji("Dog"), do: "🐕"
  defp pet_emoji("Cat"), do: "🐈"
  defp pet_emoji("Rabbit"), do: "🐰"
  defp pet_emoji("Bird"), do: "🦜"
  defp pet_emoji(_), do: "🐾"

  defp species_emoji("Dog"), do: "🐕"
  defp species_emoji("Cat"), do: "🐈"
  defp species_emoji("Rabbit"), do: "🐰"
  defp species_emoji("Bird"), do: "🦜"
  defp species_emoji(_), do: "🐾"
end
