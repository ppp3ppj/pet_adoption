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

    filter_species = socket.assigns[:filter_species] || "All"
    filtered_pets = filter_pets_by_species(pets, filter_species)

    socket
    |> assign(:all_pets, pets)
    |> assign(:filtered_pets, filtered_pets)
    |> assign(:stats, stats)
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
          <.pets_grid pets={@filtered_pets} />
        </div>
      </div>
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
          <.pet_card pet={pet} />
        <% end %>
      </div>
    <% end %>
    """
  end

  defp pet_card(assigns) do
    ~H"""
    <.link navigate={~p"/adopt/#{@pet.id}/apply"} class="block group">
      <div class="card bg-base-100 shadow hover:shadow-lg transition-all duration-200 group-hover:-translate-y-0.5">
        <!-- Image -->
        <figure class="h-32 bg-gradient-to-br from-primary/10 via-secondary/10 to-accent/10 relative overflow-hidden">
          <span class="text-6xl group-hover:scale-110 transition-transform duration-200">
            {pet_emoji(@pet.species)}
          </span>
          <div class="absolute top-2 right-2">
            <span class="badge badge-sm">{@pet.species}</span>
          </div>
        </figure>

        <!-- Content -->
        <div class="card-body p-4">
          <!-- Name & Basic Info -->
          <h3 class="font-bold text-lg truncate" title={@pet.name}>{@pet.name}</h3>
          <p class="text-sm text-base-content/60 -mt-1">
            {@pet.breed} • {@pet.age}y • {@pet.gender}
          </p>

          <!-- Description -->
          <p class="text-sm line-clamp-2 mt-1">{@pet.description}</p>

          <!-- Footer -->
          <div class="flex items-center justify-between mt-3 pt-3 border-t border-base-200">
            <span class="text-xs text-base-content/50 truncate max-w-[120px]" title={@pet.shelter_name}>
              <.icon name="hero-map-pin" class="w-3 h-3 inline" /> {@pet.shelter_name}
            </span>
          </div>
        </div>
      </div>
    </.link>
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
