defmodule PetAdoptionWeb.ShelterLive.Applications do
  @moduledoc """
  Dedicated page for viewing and managing pet applications.
  """
  use PetAdoptionWeb, :live_view

  alias PetAdoption.PetManager

  @impl true
  def mount(%{"pet_id" => pet_id}, _session, socket) do
    pet = PetManager.get_pet(pet_id)

    if pet do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(PetAdoption.PubSub, "pet_updates")
      end

      applications = PetManager.get_applications(pet_id)

      socket =
        socket
        |> assign(:page_title, "Applications for #{pet.name}")
        |> assign(:pet, pet)
        |> assign(:applications, applications)
        |> assign(:filter, :all)

      {:ok, socket}
    else
      socket =
        socket
        |> put_flash(:error, "Pet not found.")
        |> redirect(to: ~p"/shelter/dashboard")

      {:ok, socket}
    end
  end

  # Event Handlers

  @impl true
  def handle_event("approve_adoption", %{"app_id" => app_id}, socket) do
    pet = socket.assigns.pet

    case PetManager.approve_adoption(pet.id, app_id) do
      {:ok, _pet} ->
        socket =
          socket
          |> put_flash(:info, "🎉 Adoption approved! The applicant will be notified.")
          |> redirect(to: ~p"/shelter/dashboard")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to approve adoption. Please try again.")}
    end
  end

  @impl true
  def handle_event("filter", %{"status" => status}, socket) do
    filter = String.to_existing_atom(status)
    {:noreply, assign(socket, :filter, filter)}
  end

  # Info Handlers

  @impl true
  def handle_info({:pet_update, _type, _data}, socket) do
    # Reload applications when updates come in
    pet = PetManager.get_pet(socket.assigns.pet.id)

    if pet do
      applications = PetManager.get_applications(pet.id)

      {:noreply,
       socket
       |> assign(:pet, pet)
       |> assign(:applications, applications)}
    else
      # Pet was removed
      {:noreply,
       socket
       |> put_flash(:info, "This pet is no longer available.")
       |> redirect(to: ~p"/shelter/dashboard")}
    end
  end

  # Private Functions

  defp filtered_applications(applications, :all), do: applications

  defp filtered_applications(applications, status) do
    Enum.filter(applications, &(&1.status == status))
  end

  # Render

  @impl true
  def render(assigns) do
    filtered = filtered_applications(assigns.applications, assigns.filter)
    assigns = assign(assigns, :filtered_applications, filtered)

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="min-h-screen bg-base-200 py-8">
        <div class="container mx-auto px-4 max-w-4xl">
          <!-- Back Button -->
          <.link navigate={~p"/shelter/dashboard"} class="btn btn-ghost mb-6">
            <.icon name="hero-arrow-left" class="w-5 h-5" /> Back to Dashboard
          </.link>

          <!-- Pet Info Header -->
          <div class="card bg-base-100 shadow-xl mb-6">
            <div class="card-body">
              <div class="flex flex-col md:flex-row gap-6">
                <div class="flex-shrink-0">
                  <div class="w-32 h-32 bg-gradient-to-br from-primary/30 via-secondary/30 to-accent/30 rounded-xl flex items-center justify-center">
                    <span class="text-6xl">{pet_emoji(@pet.species)}</span>
                  </div>
                </div>
                <div class="flex-1 min-w-0">
                  <h1 class="text-3xl font-bold flex items-center gap-2 flex-wrap">
                    <span class="truncate" title={@pet.name}>{@pet.name}</span>
                    <span class={["badge flex-shrink-0", status_badge_class(@pet.status)]}>{@pet.status}</span>
                  </h1>
                  <p class="text-base-content/70 mt-1">
                    {@pet.species} • {@pet.breed} • {@pet.age} {if @pet.age == 1, do: "year", else: "years"} • {@pet.gender}
                  </p>
                  <p class="mt-2">{@pet.description}</p>
                  <div class="flex gap-2 mt-3">
                    <span class="badge badge-success badge-outline">{@pet.health_status}</span>
                    <span class="badge badge-ghost">@ {@pet.shelter_name}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Applications Section -->
          <div class="card bg-base-100 shadow-xl">
            <div class="card-body">
              <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 mb-6">
                <h2 class="text-2xl font-bold flex items-center gap-2">
                  <.icon name="hero-document-text" class="w-6 h-6" />
                  Applications
                  <span class="badge badge-neutral">{length(@applications)}</span>
                </h2>

                <!-- Filter Tabs -->
                <div class="join">
                  <button
                    phx-click="filter"
                    phx-value-status="all"
                    class={["join-item btn btn-sm", @filter == :all && "btn-primary"]}
                  >
                    All ({length(@applications)})
                  </button>
                  <button
                    phx-click="filter"
                    phx-value-status="pending"
                    class={["join-item btn btn-sm", @filter == :pending && "btn-warning"]}
                  >
                    Pending ({Enum.count(@applications, &(&1.status == :pending))})
                  </button>
                  <button
                    phx-click="filter"
                    phx-value-status="approved"
                    class={["join-item btn btn-sm", @filter == :approved && "btn-success"]}
                  >
                    Approved ({Enum.count(@applications, &(&1.status == :approved))})
                  </button>
                </div>
              </div>

              <%= if @filtered_applications == [] do %>
                <div class="text-center py-12">
                  <div class="text-6xl mb-4">📭</div>
                  <h3 class="text-xl font-semibold">No applications found</h3>
                  <p class="text-base-content/60">
                    <%= if @filter == :all do %>
                      No one has applied to adopt {@pet.name} yet.
                    <% else %>
                      No {to_string(@filter)} applications.
                    <% end %>
                  </p>
                </div>
              <% else %>
                <div class="space-y-4">
                  <%= for app <- @filtered_applications do %>
                    <.application_card app={app} pet={@pet} />
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Components

  defp application_card(assigns) do
    ~H"""
    <div class={[
      "card border-2",
      application_border_class(@app.status)
    ]}>
      <div class="card-body">
        <div class="flex flex-col lg:flex-row lg:items-start justify-between gap-4">
          <!-- Applicant Info -->
          <div class="flex-1">
            <div class="flex items-center gap-3 mb-2">
              <div class="avatar placeholder">
                <div class="bg-neutral text-neutral-content rounded-full w-12">
                  <span class="text-lg">{String.first(@app.applicant_name)}</span>
                </div>
              </div>
              <div>
                <h3 class="font-bold text-lg">{@app.applicant_name}</h3>
                <p class="text-sm text-base-content/70">{@app.applicant_email}</p>
              </div>
              <span class={["badge ml-auto lg:ml-0", application_badge_class(@app.status)]}>
                {String.upcase(to_string(@app.status))}
              </span>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-2 text-sm mt-4">
              <div class="flex items-center gap-2">
                <.icon name="hero-phone" class="w-4 h-4 text-base-content/60" />
                {@app.applicant_phone}
              </div>
              <div class="flex items-center gap-2">
                <.icon name="hero-home" class="w-4 h-4 text-base-content/60" />
                {@app.home_type}
              </div>
              <div class="flex items-center gap-2">
                <.icon name="hero-academic-cap" class="w-4 h-4 text-base-content/60" />
                Pet experience: {if @app.has_experience, do: "Yes", else: "No"}
              </div>
              <div class="flex items-center gap-2">
                <.icon name="hero-heart" class="w-4 h-4 text-base-content/60" />
                Has other pets: {if @app.has_other_pets, do: "Yes", else: "No"}
              </div>
            </div>

            <div class="mt-4 p-3 bg-base-200 rounded-lg">
              <p class="text-sm font-medium text-base-content/70 mb-1">Why they want to adopt:</p>
              <p>{@app.reason}</p>
            </div>

            <p class="text-xs text-base-content/60 mt-3">
              <.icon name="hero-clock" class="w-3 h-3 inline" />
              Submitted: {format_datetime(@app.submitted_at)}
            </p>
          </div>

          <!-- Actions -->
          <%= if @app.status == :pending && @pet.status == :available do %>
            <div class="flex flex-col gap-2">
              <button
                phx-click="approve_adoption"
                phx-value-app_id={@app.id}
                class="btn btn-success"
                data-confirm="Are you sure you want to approve this adoption? This will mark #{@pet.name} as adopted."
              >
                <.icon name="hero-check-circle" class="w-5 h-5" />
                Approve Adoption
              </button>
            </div>
          <% end %>

          <%= if @app.status == :approved do %>
            <div class="alert alert-success">
              <.icon name="hero-check-badge" class="w-6 h-6" />
              <div>
                <p class="font-bold">Adoption Approved!</p>
                <p class="text-sm">Reviewed: {format_datetime(@app.reviewed_at)}</p>
              </div>
            </div>
          <% end %>
        </div>
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
    Calendar.strftime(datetime, "%B %d, %Y at %H:%M")
  end

  defp status_badge_class(:available), do: "badge-success"
  defp status_badge_class(:adopted), do: "badge-secondary"
  defp status_badge_class(_), do: "badge-ghost"

  defp application_badge_class(:pending), do: "badge-warning"
  defp application_badge_class(:approved), do: "badge-success"
  defp application_badge_class(:rejected), do: "badge-error"
  defp application_badge_class(_), do: "badge-ghost"

  defp application_border_class(:pending), do: "border-warning bg-warning/5"
  defp application_border_class(:approved), do: "border-success bg-success/5"
  defp application_border_class(:rejected), do: "border-error bg-error/5"
  defp application_border_class(_), do: "border-base-300"
end
