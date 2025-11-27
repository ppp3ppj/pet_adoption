defmodule PetAdoptionWeb.PublicLive.Adopt do
  use PetAdoptionWeb, :live_view
  alias PetAdoption.PetManager
  # ← Changed from Application
  alias PetAdoption.Schemas.AdoptionApplication

  @refresh_interval 3000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Adopt a Pet")
      |> assign(:filter_species, "All")
      |> assign(:show_application_form, false)
      |> assign(:selected_pet, nil)
      # ← Changed
      |> assign(
        :application_changeset,
        AdoptionApplication.create_changeset(%AdoptionApplication{}, %{})
      )
      |> load_pets()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(PetAdoption.PubSub, "pet_updates")
      schedule_refresh(socket)
    end

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_species", %{"species" => species}, socket) do
    {:noreply, assign(socket, :filter_species, species)}
  end

  @impl true
  def handle_event("show_application_form", %{"pet_id" => pet_id}, socket) do
    pet = PetManager.get_pet(pet_id)

    socket =
      socket
      |> assign(:selected_pet, pet)
      |> assign(:show_application_form, true)
      # ← Changed
      |> assign(
        :application_changeset,
        AdoptionApplication.create_changeset(%AdoptionApplication{}, %{"pet_id" => pet_id})
      )

    {:noreply, socket}
  end

  @impl true
  def handle_event("hide_application_form", _, socket) do
    socket = assign(socket, :show_application_form, false)
    schedule_refresh(socket)
    {:noreply, socket}
  end

# Add this helper function
  defp generate_application_id do
    "app_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  @impl true
  def handle_event("submit_application", %{"application" => app_params}, socket) do
    pet = socket.assigns.selected_pet |> IO.inspect(label: "Select Pet: ")
    IO.inspect(app_params, label: "App Params: ")

    attrs =
      Map.merge(app_params, %{
        "pet_id" => pet.id,
        "applicant_name" => app_params["name"],
        "applicant_email" => app_params["email"],
        "applicant_phone" => app_params["phone"],
        "has_experience" => app_params["has_experience"] == "true",
        "has_other_pets" => app_params["has_other_pets"] == "true"
      }) |> IO.inspect(label: "ATTRS: ")


    # Validate with changeset first
    # ← Changed
    changeset = AdoptionApplication.create_changeset(%AdoptionApplication{}, attrs) |> IO.inspect()

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, _valid_app} ->
        # Now actually submit to PetManager
        case PetManager.submit_application(pet.id,
               applicant_name: app_params["name"],
               applicant_email: app_params["email"],
               applicant_phone: app_params["phone"],
               has_experience: app_params["has_experience"] == "true",
               has_other_pets: app_params["has_other_pets"] == "true",
               home_type: app_params["home_type"],
               reason: app_params["reason"]
             ) do
          {:ok, _application} ->
            socket =
              socket
              |> put_flash(
                :info,
                "Application submitted successfully! The shelter will contact you soon."
              )
              |> assign(:show_application_form, false)
              # ← Changed
              |> assign(
                :application_changeset,
                AdoptionApplication.create_changeset(%AdoptionApplication{}, %{})
              )
              |> load_pets()

            schedule_refresh(socket)
            {:noreply, socket}

          {:error, :pet_not_available} ->
            socket =
              socket
              |> put_flash(:error, "Sorry, this pet is no longer available.")
              |> assign(:show_application_form, false)
              |> load_pets()

            schedule_refresh(socket)
            {:noreply, socket}

          {:error, changeset} ->
            socket =
              socket
              |> assign(:application_changeset, changeset)
              |> put_flash(:error, "Failed to submit: #{format_errors(changeset)}")

            {:noreply, socket}
        end

      {:error, changeset} ->
        socket =
          socket
          |> assign(:application_changeset, changeset)
          |> put_flash(:error, "Validation failed: #{format_errors(changeset)}")

        {:noreply, socket}
    end
  end

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
    # Don't schedule if modal is open
    unless socket.assigns.show_application_form do
      Process.send_after(self(), :refresh, @refresh_interval)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-purple-50 via-pink-50 to-blue-50">
      <!-- Hero Section -->
      <div class="bg-gradient-to-r from-purple-600 to-blue-600 text-white py-20">
        <div class="container mx-auto px-4 text-center">
          <h1 class="text-6xl font-bold mb-4">🐾 Find Your Perfect Companion</h1>
          <p class="text-2xl mb-8">Adopt a pet from our network of caring shelters</p>
          <div class="flex justify-center gap-8 text-center">
            <div>
              <p class="text-4xl font-bold">{@stats.available_pets}</p>
              <p class="text-lg">Pets Available</p>
            </div>
            <div>
              <p class="text-4xl font-bold">{@stats.adopted_pets}</p>
              <p class="text-lg">Happy Adoptions</p>
            </div>
            <div>
              <p class="text-4xl font-bold">{@stats.total_shelters}</p>
              <p class="text-lg">Partner Shelters</p>
            </div>
          </div>
        </div>
      </div>

      <div class="container mx-auto px-4 py-12">
        <!-- Filters -->
        <div class="bg-white rounded-lg shadow-lg p-6 mb-8">
          <h2 class="text-2xl font-bold text-gray-800 mb-4">Filter by Species</h2>
          <div class="flex gap-3 flex-wrap">
            <button
              phx-click="filter_species"
              phx-value-species="All"
              class={"px-6 py-3 rounded-lg font-semibold transition #{if @filter_species == "All", do: "bg-purple-600 text-white", else: "bg-gray-200 text-gray-700 hover:bg-gray-300"}"}
            >
              All ({length(@all_pets)})
            </button>
            <%= for {species, count} <- @stats.pets_by_species do %>
              <button
                phx-click="filter_species"
                phx-value-species={species}
                class={"px-6 py-3 rounded-lg font-semibold transition #{if @filter_species == species, do: "bg-purple-600 text-white", else: "bg-gray-200 text-gray-700 hover:bg-gray-300"}"}
              >
                {species} ({count})
              </button>
            <% end %>
          </div>
        </div>

    <!-- Pets Grid -->
        <%= if length(@filtered_pets) == 0 do %>
          <div class="bg-white rounded-lg shadow-lg p-12 text-center">
            <p class="text-2xl text-gray-600 mb-4">No pets available in this category yet.</p>
            <p class="text-gray-500">Check back soon or browse other categories!</p>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
            <%= for pet <- @filtered_pets do %>
              <div class="bg-white rounded-lg shadow-lg overflow-hidden hover:shadow-2xl transition transform hover:-translate-y-1">
                <div class="h-56 bg-gradient-to-br from-purple-400 via-pink-400 to-blue-400 flex items-center justify-center">
                  <span class="text-9xl">{pet_emoji(pet.species)}</span>
                </div>
                <div class="p-6">
                  <div class="flex items-start justify-between mb-2">
                    <h3 class="text-2xl font-bold text-gray-800">{pet.name}</h3>
                    <span class="bg-purple-100 text-purple-800 px-2 py-1 rounded text-xs font-semibold">
                      {pet.species}
                    </span>
                  </div>
                  <p class="text-gray-600 mb-3">
                    {pet.breed} • {pet.age} {if pet.age == 1, do: "year", else: "years"}
                  </p>
                  <p class="text-gray-700 mb-4 line-clamp-3">{pet.description}</p>

                  <div class="mb-4">
                    <p class="text-sm text-gray-500 mb-1">
                      <span class="font-semibold">Gender:</span> {pet.gender}
                    </p>
                    <p class="text-sm text-gray-500 mb-1">
                      <span class="font-semibold">Health:</span> {pet.health_status}
                    </p>
                    <p class="text-sm text-gray-500">
                      <span class="font-semibold">Location:</span> {pet.shelter_name}
                    </p>
                  </div>

                  <button
                    phx-click="show_application_form"
                    phx-value-pet_id={pet.id}
                    class="w-full bg-gradient-to-r from-purple-600 to-blue-600 hover:from-purple-700 hover:to-blue-700 text-white px-6 py-3 rounded-lg font-bold text-lg transition transform hover:scale-105"
                  >
                    💝 Apply to Adopt
                  </button>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>

    <!-- Info Section -->
        <div class="mt-12 bg-white rounded-lg shadow-lg p-8">
          <h2 class="text-3xl font-bold text-gray-800 mb-4">How It Works</h2>
          <div class="grid grid-cols-1 md:grid-cols-3 gap-8">
            <div class="text-center">
              <div class="text-5xl mb-3">🔍</div>
              <h3 class="text-xl font-bold text-gray-800 mb-2">Browse Pets</h3>
              <p class="text-gray-600">Search our network of shelters to find your perfect match</p>
            </div>
            <div class="text-center">
              <div class="text-5xl mb-3">📝</div>
              <h3 class="text-xl font-bold text-gray-800 mb-2">Apply Online</h3>
              <p class="text-gray-600">Submit your application instantly across all shelters</p>
            </div>
            <div class="text-center">
              <div class="text-5xl mb-3">❤️</div>
              <h3 class="text-xl font-bold text-gray-800 mb-2">Take Home</h3>
              <p class="text-gray-600">The shelter will contact you to complete the adoption</p>
            </div>
          </div>
        </div>

    <!-- Footer -->
        <div class="mt-8 text-center text-gray-600">
          <p class="text-sm">Last updated: {Calendar.strftime(@last_updated, "%H:%M:%S UTC")}</p>
        </div>
      </div>

    <!-- Application Form Modal -->
      <%= if @show_application_form && @selected_pet do %>
        <div
          class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4"
          phx-update="ignore"
          id="application-form-modal"
        >
          <div class="bg-white rounded-lg shadow-2xl max-w-3xl w-full max-h-[90vh] overflow-y-auto">
            <div class="sticky top-0 bg-gradient-to-r from-purple-600 to-blue-600 text-white p-6 rounded-t-lg">
              <h2 class="text-3xl font-bold">Adopt {@selected_pet.name}</h2>
              <p class="text-lg">{@selected_pet.breed} • {@selected_pet.age} years</p>
            </div>

            <form phx-submit="submit_application" onkeydown="return event.key != 'Enter';" class="p-8">
              <div class="mb-8 bg-purple-50 rounded-lg p-6">
                <h3 class="text-xl font-bold text-gray-800 mb-2">About {@selected_pet.name}</h3>
                <p class="text-gray-700 mb-2">{@selected_pet.description}</p>
                <p class="text-sm text-gray-600">
                  Located at: <span class="font-semibold">{@selected_pet.shelter_name}</span>
                </p>
              </div>

              <h3 class="text-2xl font-bold text-gray-800 mb-6">Your Information</h3>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
                <div>
                  <label class="block text-gray-700 font-semibold mb-2">Full Name *</label>
                  <input
                    type="text"
                    name="application[name]"
                    required
                    class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
                    placeholder="John Doe"
                  />
                </div>
                <div>
                  <label class="block text-gray-700 font-semibold mb-2">Email *</label>
                  <input
                    type="email"
                    name="application[email]"
                    required
                    class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
                    placeholder="john@example.com"
                  />
                </div>
              </div>

              <div class="mb-6">
                <label class="block text-gray-700 font-semibold mb-2">Phone Number *</label>
                <input
                  type="tel"
                  name="application[phone]"
                  required
                  class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
                  placeholder="(555) 123-4567"
                />
              </div>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
                <div>
                  <label class="block text-gray-700 font-semibold mb-2">Home Type *</label>
                  <select
                    name="application[home_type]"
                    required
                    class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
                  >
                    <option value="">Select...</option>
                    <option value="House">House</option>
                    <option value="Apartment">Apartment</option>
                    <option value="Condo">Condo</option>
                    <option value="Farm">Farm</option>
                  </select>
                </div>
                <div>
                  <label class="block text-gray-700 font-semibold mb-2">
                    Experience with pets? *
                  </label>
                  <select
                    name="application[has_experience]"
                    required
                    class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
                  >
                    <option value="">Select...</option>
                    <option value="true">Yes</option>
                    <option value="false">No</option>
                  </select>
                </div>
              </div>

              <div class="mb-6">
                <label class="block text-gray-700 font-semibold mb-2">
                  Do you have other pets? *
                </label>
                <select
                  name="application[has_other_pets]"
                  required
                  class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
                >
                  <option value="">Select...</option>
                  <option value="true">Yes</option>
                  <option value="false">No</option>
                </select>
              </div>

              <div class="mb-8">
                <label class="block text-gray-700 font-semibold mb-2">
                  Why do you want to adopt {@selected_pet.name}? *
                </label>
                <textarea
                  name="application[reason]"
                  required
                  rows="5"
                  class="w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500"
                  placeholder="Tell us why you'd be a great match..."
                ></textarea>
              </div>

              <div class="flex gap-4">
                <button
                  type="submit"
                  class="flex-1 bg-gradient-to-r from-purple-600 to-blue-600 hover:from-purple-700 hover:to-blue-700 text-white px-8 py-4 rounded-lg font-bold text-lg transition transform hover:scale-105"
                >
                  Submit Application
                </button>
                <button
                  type="button"
                  phx-click="hide_application_form"
                  class="flex-1 bg-gray-300 hover:bg-gray-400 text-gray-800 px-8 py-4 rounded-lg font-bold text-lg transition"
                >
                  Cancel
                </button>
              </div>
            </form>
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

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end
end
