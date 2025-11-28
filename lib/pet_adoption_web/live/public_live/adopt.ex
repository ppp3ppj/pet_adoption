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
          <.link
            navigate={~p"/adopt/#{@pet.id}/apply"}
            class="btn btn-primary btn-block"
          >
            💝 Apply to Adopt
          </.link>
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
