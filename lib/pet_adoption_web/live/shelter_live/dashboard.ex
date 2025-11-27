defmodule PetAdoptionWeb.ShelterLive.Dashboard do
  use PetAdoptionWeb, :live_view
  alias PetAdoption.PetManager
  alias PetAdoption.Schemas.Pet

  @refresh_interval 2000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PetAdoption.PubSub, "pet_updates")
      #      schedule_refresh() # it cause bug can reset input every 2 second
    end

    socket =
      socket
      |> assign(:page_title, "Shelter Dashboard")
      |> assign(:active_tab, "pets")
      |> assign(:show_add_pet_modal, false)
      |> assign(:show_application_modal, false)
      |> assign(:selected_pet, nil)
      |> assign(:selected_application, nil)
      |> load_data()

    {:ok, socket}
  end

  @impl true
  def handle_event("add_pet", %{"pet" => pet_params}, socket) do
    case PetManager.add_pet(
           name: pet_params["name"],
           species: pet_params["species"],
           breed: pet_params["breed"],
           age: String.to_integer(pet_params["age"]),
           gender: pet_params["gender"],
           description: pet_params["description"],
           health_status: pet_params["health_status"]
         ) do
      {:ok, _pet} ->
        socket =
          socket
          |> put_flash(:info, "Pet added successfully!")
          |> assign(:show_add_pet_modal, false)
          |> load_data()

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to add pet")}
    end
  end

  @impl true
  def handle_event("show_add_pet_modal", _, socket) do
    {:noreply, assign(socket, :show_add_pet_modal, true)}
  end

  @impl true
  def handle_event("hide_add_pet_modal", _, socket) do
    {:noreply, assign(socket, :show_add_pet_modal, false)}
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
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("simulate_partition", %{"duration" => duration}, socket) do
    duration_ms = String.to_integer(duration) * 1000
    PetManager.simulate_partition(duration_ms)

    socket = put_flash(socket, :info, "Simulating network partition for #{duration}s")
    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:pet_update, _type, _data}, socket) do
    {:noreply, load_data(socket)}
  end

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

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      <div class="container mx-auto px-4 py-8">
        <!-- Header -->
        <div class="bg-white rounded-lg shadow-lg p-6 mb-8">
          <div class="flex items-center justify-between">
            <div>
              <h1 class="text-4xl font-bold text-gray-800 mb-2">🐾 {@shelter_info.shelter_name}</h1>
              <p class="text-gray-600">Distributed Pet Adoption Network</p>
            </div>
            <div class="text-right">
              <p class="text-sm text-gray-500">
                Node: <span class="font-mono">{@shelter_info.node_id}</span>
              </p>
              <p class="text-sm text-gray-500">
                Connected Shelters:
                <span class="font-bold">{length(@shelter_info.connected_nodes)}</span>
              </p>
            </div>
          </div>
        </div>

    <!-- Stats Cards -->
        <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-1">
                <p class="text-gray-500 text-sm">Available Pets</p>
                <p class="text-3xl font-bold text-green-600">{@stats.available_pets}</p>
              </div>
              <div class="text-green-500 text-4xl">🐕</div>
            </div>
          </div>

          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-1">
                <p class="text-gray-500 text-sm">Adopted Pets</p>
                <p class="text-3xl font-bold text-purple-600">{@stats.adopted_pets}</p>
              </div>
              <div class="text-purple-500 text-4xl">❤️</div>
            </div>
          </div>

          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-1">
                <p class="text-gray-500 text-sm">Pending Apps</p>
                <p class="text-3xl font-bold text-blue-600">{@stats.pending_applications}</p>
              </div>
              <div class="text-blue-500 text-4xl">📋</div>
            </div>
          </div>

          <div class="bg-white rounded-lg shadow p-6">
            <div class="flex items-center">
              <div class="flex-1">
                <p class="text-gray-500 text-sm">Network Shelters</p>
                <p class="text-3xl font-bold text-indigo-600">{@stats.total_shelters}</p>
              </div>
              <div class="text-indigo-500 text-4xl">🏥</div>
            </div>
          </div>
        </div>

    <!-- Actions Bar -->
        <div class="bg-white rounded-lg shadow p-4 mb-6 flex gap-2 flex-wrap">
          <button
            phx-click="show_add_pet_modal"
            class="bg-green-600 hover:bg-green-700 text-white px-6 py-2 rounded-lg font-semibold transition"
          >
            ➕ Add Pet
          </button>
          <button
            phx-click="change_tab"
            phx-value-tab="pets"
            class={"px-6 py-2 rounded-lg font-semibold transition #{if @active_tab == "pets", do: "bg-blue-600 text-white", else: "bg-gray-200 text-gray-700"}"}
          >
            Available Pets
          </button>
          <button
            phx-click="change_tab"
            phx-value-tab="adopted"
            class={"px-6 py-2 rounded-lg font-semibold transition #{if @active_tab == "adopted", do: "bg-blue-600 text-white", else: "bg-gray-200 text-gray-700"}"}
          >
            Adopted Pets
          </button>
          <div class="ml-auto flex gap-2">
            <button
              phx-click="simulate_partition"
              phx-value-duration="5"
              class="bg-red-600 hover:bg-red-700 text-white px-4 py-2 rounded-lg text-sm transition"
            >
              🔌 Partition 5s
            </button>
          </div>
        </div>

    <!-- Pets List -->
        <%= if @active_tab == "pets" do %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for pet <- @available_pets do %>
              <div class="bg-white rounded-lg shadow-lg overflow-hidden hover:shadow-xl transition">
                <div class="h-48 bg-gradient-to-br from-blue-400 to-purple-500 flex items-center justify-center">
                  <span class="text-8xl">{pet_emoji(pet.species)}</span>
                </div>
                <div class="p-6">
                  <h3 class="text-2xl font-bold text-gray-800 mb-2">{pet.name}</h3>
                  <p class="text-gray-600 mb-4">{pet.breed} • {pet.age} years • {pet.gender}</p>
                  <p class="text-gray-700 mb-4 line-clamp-2">{pet.description}</p>
                  <div class="flex items-center justify-between mb-4">
                    <span class="text-sm text-gray-500">@ {pet.shelter_name}</span>
                    <span class="bg-green-100 text-green-800 px-3 py-1 rounded-full text-sm font-semibold">
                      {pet.health_status}
                    </span>
                  </div>
                  <div class="flex gap-2">
                    <button
                      phx-click="view_pet"
                      phx-value-id={pet.id}
                      class="flex-1 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg font-semibold transition"
                    >
                      View Applications
                    </button>
                    <button
                      phx-click="remove_pet"
                      phx-value-id={pet.id}
                      class="bg-red-600 hover:bg-red-700 text-white px-4 py-2 rounded-lg transition"
                      data-confirm="Are you sure?"
                    >
                      🗑️
                    </button>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

    <!-- Adopted Pets -->
        <%= if @active_tab == "adopted" do %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <%= for pet <- @adopted_pets do %>
              <div class="bg-white rounded-lg shadow-lg overflow-hidden">
                <div class="h-48 bg-gradient-to-br from-purple-400 to-pink-500 flex items-center justify-center">
                  <span class="text-8xl">{pet_emoji(pet.species)}</span>
                </div>
                <div class="p-6">
                  <h3 class="text-2xl font-bold text-gray-800 mb-2">{pet.name}</h3>
                  <p class="text-gray-600 mb-4">{pet.breed} • {pet.age} years</p>
                  <div class="bg-purple-100 rounded-lg p-4 mb-4">
                    <p class="text-sm text-purple-800 font-semibold">✅ Adopted by:</p>
                    <p class="text-purple-900 font-bold">{pet.adopted_by}</p>
                    <p class="text-xs text-purple-700 mt-2">
                      {format_datetime(pet.adopted_at)}
                    </p>
                  </div>
                  <p class="text-sm text-gray-500">From: {pet.shelter_name}</p>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

    <!-- Footer -->
        <div class="mt-8 text-center text-gray-600 text-sm">
          <p>Last updated: {Calendar.strftime(@last_updated, "%H:%M:%S UTC")}</p>
        </div>
      </div>

    <!-- Add Pet Modal -->
      <%= if @show_add_pet_modal do %>
        <div class="fixed inset-0 bg-base-100/50 flex items-center justify-center z-50">
          <div class="bg-base-100 rounded-lg shadow-2xl p-8 max-w-2xl w-full mx-4 max-h-[90vh] overflow-y-auto">
            <h2 class="text-3xl font-bold text-base-content mb-6">Add New Pet</h2>
            <form phx-submit="add_pet" onkeydown="return event.key != 'Enter';">
              <div class="grid grid-cols-2 gap-4 mb-4">
                <fieldset class="fieldset">
                  <legend class="fieldset-legend">Name *</legend>
                  <input
                    type="text"
                    name="pet[name]"
                    required
                    class="input"
                    placeholder="Enter pet name"
                  />
                </fieldset>
                <fieldset class="fieldset">
                  <legend class="fieldset-legend">Species *</legend>
                  <select
                    name="pet[species]"
                    required
                    class="select"
                  >
                    <option disabled value="">Select species...</option>
                    <option value="Dog">Dog</option>
                    <option value="Cat">Cat</option>
                    <option value="Rabbit">Rabbit</option>
                    <option value="Bird">Bird</option>
                    <option value="Other">Other</option>
                  </select>
                </fieldset>
              </div>
              <div class="grid grid-cols-2 gap-4 mb-4">
                <fieldset class="fieldset">
                  <legend class="fieldset-legend">Breed *</legend>
                  <input
                    type="text"
                    name="pet[breed]"
                    required
                    class="input"
                    placeholder="Enter e.g., Golden Retriever"
                  />
                </fieldset>
                <fieldset class="fieldset">
                  <legend class="fieldset-legend">Age (years) *</legend>
                  <input
                    type="number"
                    class="input validator"
                    required
                    name="pet[age]"
                    placeholder="Type a number between 1 to 100"
                    min="1"
                    max="100"
                    title="Must be between be 1 to 100"
                  />
                  <p class="validator-hint">Must be between be 1 to 100</p>
                </fieldset>
              </div>
              <div class="grid grid-cols-2 gap-4 mb-4">
                <fieldset class="fieldset">
                  <legend class="fieldset-legend">Gender *</legend>
                  <select
                    name="pet[gender]"
                    required
                    class="select"
                  >
                    <option disabled value="">Select gender...</option>
                    <option value="Male">Male</option>
                    <option value="Female">Female</option>
                  </select>
                </fieldset>
                <div>
                  <fieldset class="fieldset">
                    <legend class="fieldset-legend">Health Status</legend>
                    <input
                      type="text"
                      name="pet[health_status]"
                      value="Healthy"
                      required
                      class="input"
                      placeholder="Enter pet name"
                    />
                  </fieldset>
                </div>
              </div>
              <div class="mb-6">
                <fieldset class="fieldset">
                  <legend class="fieldset-legend">Description *</legend>
                  <textarea
                    placeholder="Tell us about this pet..."
                    name="pet[description]"
                    class="textarea h-24 w-full"
                  ></textarea>
                </fieldset>
              </div>
              <div class="flex gap-4">
                <button
                  type="submit"
                  class="btn btn-soft btn-primary flex-1"
                >
                  Add Pet
                </button>
                <button
                  phx-click="hide_add_pet_modal"
                  class="btn btn-soft btn-error flex-1"
                >
                  Cancel
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>

    <!-- Application Modal -->
      <%= if @show_application_modal && @selected_pet do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div class="bg-white rounded-lg shadow-2xl p-8 max-w-3xl w-full mx-4 max-h-[90vh] overflow-y-auto">
            <h2 class="text-3xl font-bold text-gray-800 mb-4">{@selected_pet.name}</h2>
            <p class="text-gray-600 mb-6">
              {@selected_pet.breed} • {@selected_pet.age} years • {@selected_pet.gender}
            </p>

            <h3 class="text-xl font-bold text-gray-800 mb-4">
              Applications ({length(@pet_applications)})
            </h3>

            <%= if length(@pet_applications) == 0 do %>
              <p class="text-gray-500 mb-6">No applications yet.</p>
            <% else %>
              <div class="space-y-4 mb-6">
                <%= for app <- @pet_applications do %>
                  <div class={"border rounded-lg p-4 #{application_border_color(app.status)}"}>
                    <div class="flex items-start justify-between mb-2">
                      <div>
                        <p class="font-bold text-gray-800">{app.applicant_name}</p>
                        <p class="text-sm text-gray-600">
                          {app.applicant_email} • {app.applicant_phone}
                        </p>
                      </div>
                      <span class={"px-3 py-1 rounded-full text-sm font-semibold #{application_badge_class(app.status)}"}>
                        {String.upcase(to_string(app.status))}
                      </span>
                    </div>
                    <p class="text-gray-700 mb-2"><strong>Reason:</strong> {app.reason}</p>
                    <p class="text-sm text-gray-600">
                      Experience: {if app.has_experience, do: "Yes", else: "No"} | Other Pets: {if app.has_other_pets,
                        do: "Yes",
                        else: "No"} | Home: {app.home_type}
                    </p>
                    <p class="text-xs text-gray-500 mt-2">
                      Submitted: {format_datetime(app.submitted_at)}
                    </p>

                    <%= if app.status == :pending && @selected_pet.status == :available do %>
                      <button
                        phx-click="approve_adoption"
                        phx-value-pet_id={@selected_pet.id}
                        phx-value-app_id={app.id}
                        class="mt-3 bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded-lg text-sm font-semibold transition"
                      >
                        ✅ Approve Adoption
                      </button>
                    <% end %>
                  </div>
                <% end %>
              </div>
            <% end %>

            <button
              phx-click="hide_application_modal"
              class="w-full bg-gray-300 hover:bg-gray-400 text-gray-800 px-6 py-3 rounded-lg font-semibold transition"
            >
              Close
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp pet_emoji("Dog"), do: "🐕"
  defp pet_emoji("Cat"), do: "🐈"
  defp pet_emoji("Rabbit"), do: "🐰"
  defp pet_emoji("Bird"), do: "🦜"
  defp pet_emoji(_), do: "🐾"

  defp format_datetime(nil), do: "N/A"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp application_badge_class(:pending), do: "bg-yellow-100 text-yellow-800"
  defp application_badge_class(:approved), do: "bg-green-100 text-green-800"
  defp application_badge_class(:rejected), do: "bg-red-100 text-red-800"

  defp application_border_color(:pending), do: "border-yellow-300"
  defp application_border_color(:approved), do: "border-green-300 bg-green-50"
  defp application_border_color(:rejected), do: "border-red-300 bg-red-50"
end
