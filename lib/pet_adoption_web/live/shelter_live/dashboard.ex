defmodule PetAdoptionWeb.ShelterLive.Dashboard do
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
      |> assign(:page_title, "Shelter Dashboard")
      |> assign(:active_tab, :pets)
      |> load_data()

    {:ok, socket}
  end

  # Event Handlers

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
                <.link navigate={~p"/shelter/pets/new"} class="btn btn-success">
                  <.icon name="hero-plus" class="w-5 h-5" /> Add Pet
                </.link>

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
        <h2 class="card-title flex-wrap">
          <span class="truncate max-w-[180px]" title={@pet.name}>{@pet.name}</span>
          <span class="badge badge-secondary badge-sm flex-shrink-0">{@pet.species}</span>
        </h2>
        <p class="text-base-content/70">{@pet.breed} • {@pet.age} years • {@pet.gender}</p>
        <p class="line-clamp-2">{@pet.description}</p>

        <%= if @type == :available do %>
          <div class="flex items-center justify-between mt-2">
            <span class="text-sm text-base-content/60 truncate">@ {@pet.shelter_name}</span>
            <span class="badge badge-success badge-outline flex-shrink-0">{@pet.health_status}</span>
          </div>
          <div class="card-actions justify-end mt-4 flex-wrap gap-2">
            <.link navigate={~p"/shelter/pets/#{@pet.id}/applications"} class="btn btn-primary btn-sm">
              <.icon name="hero-eye" class="w-4 h-4" />
              <span class="hidden sm:inline">Apps</span>
            </.link>
            <.link navigate={~p"/shelter/pets/#{@pet.id}/edit"} class="btn btn-secondary btn-sm">
              <.icon name="hero-pencil-square" class="w-4 h-4" />
              <span class="hidden sm:inline">Edit</span>
            </.link>
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
end
