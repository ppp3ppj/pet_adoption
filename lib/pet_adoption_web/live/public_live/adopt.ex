defmodule PetAdoptionWeb.PublicLive.Adopt do
  use PetAdoptionWeb, :live_view
  require Logger

  alias PetAdoption.PetManager

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PetAdoption.PubSub, "pet_updates")
    end

    socket =
      socket
      |> assign(:page_title, "Adopt a Pet")
      |> assign(:filter_species, "All")
      |> assign(:selected_pet, nil)
      |> load_pets()

    {:ok, socket}
  end

  # Event Handlers

  @impl true
  def handle_event("filter_species", %{"species" => species}, socket) do
    # Only update filter and recompute filtered_pets from cached all_pets
    filtered_pets = filter_pets_by_species(socket.assigns.all_pets, species)

    {:noreply,
     socket
     |> assign(:filter_species, species)
     |> assign(:filtered_pets, filtered_pets)}
  end

  @impl true
  def handle_event("show_pet_details", %{"id" => pet_id}, socket) do
    pet = Enum.find(socket.assigns.all_pets, &(&1.id == pet_id))
    {:noreply, assign(socket, :selected_pet, pet)}
  end

  @impl true
  def handle_event("close_pet_details", _params, socket) do
    {:noreply, assign(socket, :selected_pet, nil)}
  end

  # Noop handler to prevent click propagation on modal box
  @impl true
  def handle_event("noop", _params, socket) do
    {:noreply, socket}
  end

  # Info Handlers

  @impl true
  def handle_info({:pet_update, _type, _data}, socket) do
    # Reload pets only when notified of actual changes
    {:noreply, load_pets(socket)}
  end

  # Private Functions

  defp load_pets(socket) do
    pets = PetManager.list_pets(:available)
    stats = PetManager.get_stats()
    app_counts = PetManager.get_application_counts_by_pet()

    filter_species = socket.assigns[:filter_species] || "All"
    filtered_pets = filter_pets_by_species(pets, filter_species)

    socket
    |> assign(:all_pets, pets)
    |> assign(:filtered_pets, filtered_pets)
    |> assign(:stats, stats)
    |> assign(:app_counts, app_counts)
    |> assign(:last_updated, DateTime.utc_now())
  end

  defp filter_pets_by_species(pets, "All"), do: pets
  defp filter_pets_by_species(pets, species), do: Enum.filter(pets, &(&1.species == species))

  # Render

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-base-200">
        <!-- Compact Header -->
        <div class="navbar bg-primary text-primary-content shadow-lg">
          <div class="container mx-auto">
            <div class="flex-1">
              <span class="text-2xl font-bold">🐾 Pet Adoption</span>
            </div>
            <div class="flex-none gap-6">
              <div class="stats stats-horizontal bg-primary-content/10 shadow-sm hidden sm:flex">
                <div class="stat py-2 px-4">
                  <div class="stat-value text-lg">{@stats.available_pets}</div>
                  <div class="stat-desc text-primary-content/70 text-xs">Available</div>
                </div>
                <div class="stat py-2 px-4">
                  <div class="stat-value text-lg">{@stats.adopted_pets}</div>
                  <div class="stat-desc text-primary-content/70 text-xs">Adopted</div>
                </div>
                <div class="stat py-2 px-4">
                  <div class="stat-value text-lg text-warning">{@stats.pending_applications}</div>
                  <div class="stat-desc text-primary-content/70 text-xs">Pending</div>
                </div>
              </div>
              <.link navigate={~p"/shelter/dashboard"} class="btn btn-ghost btn-sm">
                <.icon name="hero-building-storefront" class="w-4 h-4" />
                <span class="hidden sm:inline">Shelter Portal</span>
              </.link>
            </div>
          </div>
        </div>

        <div class="container mx-auto px-4 py-6">
          <!-- Filter Bar -->
          <div class="flex flex-wrap items-center gap-3 mb-6">
            <span class="font-semibold text-base-content/70">
              <.icon name="hero-funnel" class="w-4 h-4 inline" /> Filter:
            </span>
            <div class="tabs tabs-boxed bg-base-100">
              <button
                phx-click="filter_species"
                phx-value-species="All"
                class={["tab", @filter_species == "All" && "tab-active"]}
              >
                All ({length(@all_pets)})
              </button>
              <%= for {species, count} <- @stats.pets_by_species do %>
                <button
                  phx-click="filter_species"
                  phx-value-species={species}
                  class={["tab", @filter_species == species && "tab-active"]}
                >
                  {species_emoji(species)} {species} ({count})
                </button>
              <% end %>
            </div>
          </div>

          <!-- Pets Grid -->
          <.pets_grid pets={@filtered_pets} app_counts={@app_counts} />
        </div>
      </div>

      <!-- Pet Detail Modal (Outside cards) -->
      <.pet_detail_modal pet={@selected_pet} />
    </Layouts.app>
    """
  end

  # Components

  defp pets_grid(assigns) do
    ~H"""
    <%= if @pets == [] do %>
      <div class="hero min-h-[300px] bg-base-100 rounded-box">
        <div class="hero-content text-center">
          <div>
            <div class="text-6xl mb-4">🐾</div>
            <h3 class="text-xl font-semibold">No pets available</h3>
            <p class="text-base-content/60">Check back soon!</p>
          </div>
        </div>
      </div>
    <% else %>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
        <%= for pet <- @pets do %>
          <.pet_card pet={pet} app_count={Map.get(@app_counts, pet.id, %{total: 0, pending: 0})} />
        <% end %>
      </div>
    <% end %>
    """
  end

  defp pet_card(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow hover:shadow-lg transition-all duration-200 hover:-translate-y-0.5">
      <!-- Image -->
      <figure class="h-32 bg-gradient-to-br from-primary/10 via-secondary/10 to-accent/10 relative overflow-hidden">
        <span class="text-6xl hover:scale-110 transition-transform duration-200">
          {pet_emoji(@pet.species)}
        </span>
        <div class="absolute top-2 right-2">
          <span class="badge badge-sm">{@pet.species}</span>
        </div>
        <!-- Real-time Application Count Badge -->
        <%= if @app_count.total > 0 do %>
          <div class="absolute top-2 left-2">
            <div class="badge badge-warning gap-1 animate-pulse">
              <.icon name="hero-document-text" class="w-3 h-3" />
              {@app_count.total}
            </div>
          </div>
        <% end %>
      </figure>

      <!-- Content -->
      <div class="card-body p-4">
        <!-- Name -->
        <div class="tooltip tooltip-bottom w-full" data-tip={@pet.name}>
          <h3 class="font-bold text-lg truncate text-left">{@pet.name}</h3>
        </div>

        <!-- Pet Details - Badges -->
        <div class="flex flex-wrap gap-1 -mt-1">
          <span class="badge badge-outline badge-sm">{@pet.breed}</span>
          <span class="badge badge-outline badge-sm">{@pet.age}y</span>
          <span class="badge badge-outline badge-sm">{@pet.gender}</span>
        </div>

        <!-- Description Preview -->
        <p class="text-sm line-clamp-2 mt-1 text-base-content/70">{@pet.description}</p>

        <!-- Action Buttons -->
        <div class="card-actions mt-3 gap-2">
          <button
            type="button"
            class="btn btn-ghost btn-xs flex-1"
            phx-click="show_pet_details"
            phx-value-id={@pet.id}
          >
            <.icon name="hero-eye" class="w-4 h-4" /> Details
          </button>
          <.link navigate={~p"/adopt/#{@pet.id}/apply"} class="btn btn-primary btn-xs flex-1">
            <.icon name="hero-heart" class="w-4 h-4" /> Apply
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp pet_detail_modal(assigns) do
    ~H"""
    <%= if @pet do %>
      <div class="modal modal-open" phx-click-away="close_pet_details" phx-window-keydown="close_pet_details" phx-key="escape">
        <div class="modal-box" phx-click="noop">
          <button
            type="button"
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
            phx-click="close_pet_details"
          >
            ✕
          </button>

          <div class="flex items-center gap-3 mb-4">
            <span class="text-4xl">{pet_emoji(@pet.species)}</span>
            <div>
              <h3 class="font-bold text-xl">{@pet.name}</h3>
              <span class="badge badge-secondary">{@pet.species}</span>
            </div>
          </div>

          <!-- Details Grid -->
          <div class="grid grid-cols-3 gap-2 mb-4">
            <div class="bg-base-200 rounded-lg p-3 text-center">
              <div class="text-xs text-base-content/60">Breed</div>
              <div class="font-semibold text-sm">{@pet.breed}</div>
            </div>
            <div class="bg-base-200 rounded-lg p-3 text-center">
              <div class="text-xs text-base-content/60">Age</div>
              <div class="font-semibold text-sm">{@pet.age} {if @pet.age == 1, do: "year", else: "years"}</div>
            </div>
            <div class="bg-base-200 rounded-lg p-3 text-center">
              <div class="text-xs text-base-content/60">Gender</div>
              <div class="font-semibold text-sm">{@pet.gender}</div>
            </div>
          </div>

          <!-- Description -->
          <div class="mb-4">
            <div class="text-xs text-base-content/60 mb-1">Description</div>
            <p class="text-sm">{@pet.description}</p>
          </div>

          <!-- Health & Shelter -->
          <div class="grid grid-cols-2 gap-2 mb-4">
            <div class="flex items-center gap-2 bg-success/10 rounded-lg p-3">
              <.icon name="hero-heart" class="w-5 h-5 text-success" />
              <div>
                <div class="text-xs text-base-content/60">Health</div>
                <div class="font-semibold text-sm">{@pet.health_status}</div>
              </div>
            </div>
            <div class="flex items-center gap-2 bg-primary/10 rounded-lg p-3">
              <.icon name="hero-map-pin" class="w-5 h-5 text-primary" />
              <div>
                <div class="text-xs text-base-content/60">Shelter</div>
                <div class="font-semibold text-sm">{@pet.shelter_name}</div>
              </div>
            </div>
          </div>

          <div class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="close_pet_details">
              Close
            </button>
            <.link navigate={~p"/adopt/#{@pet.id}/apply"} class="btn btn-primary">
              <.icon name="hero-heart" class="w-4 h-4" /> Apply to Adopt
            </.link>
          </div>
        </div>
        <div class="modal-backdrop bg-black/50" phx-click="close_pet_details"></div>
      </div>
    <% end %>
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
