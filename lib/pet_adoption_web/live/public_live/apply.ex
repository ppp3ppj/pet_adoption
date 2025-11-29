defmodule PetAdoptionWeb.PublicLive.Apply do
  @moduledoc """
  Dedicated page for submitting adoption applications.
  Isolated from PubSub updates to prevent form interruption.
  """
  use PetAdoptionWeb, :live_view

  alias PetAdoption.PetManager
  alias PetAdoption.Schemas.AdoptionApplication

  @impl true
  def mount(%{"pet_id" => pet_id}, _session, socket) do
    pet = PetManager.get_pet(pet_id)

    if pet && pet.status == :available do
      changeset = AdoptionApplication.form_changeset(%AdoptionApplication{}, %{"pet_id" => pet_id})

      socket =
        socket
        |> assign(:page_title, "Apply to Adopt #{pet.name}")
        |> assign(:pet, pet)
        |> assign(:submitting, false)
        |> assign_form(changeset)

      {:ok, socket}
    else
      # Pet not found or not available
      socket =
        socket
        |> put_flash(:error, "Sorry, this pet is no longer available for adoption.")
        |> redirect(to: ~p"/adopt")

      {:ok, socket}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :application))
  end

  # Event Handlers

  @impl true
  def handle_event("validate", %{"application" => app_params}, socket) do
    changeset =
      %AdoptionApplication{}
      |> AdoptionApplication.form_changeset(Map.put(app_params, "pet_id", socket.assigns.pet.id))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("submit", %{"application" => app_params}, socket) do
    pet = socket.assigns.pet

    changeset =
      %AdoptionApplication{}
      |> AdoptionApplication.form_changeset(Map.put(app_params, "pet_id", pet.id))

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, _valid_app} ->
        # Mark as submitting to prevent double-submit
        socket = assign(socket, :submitting, true)

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
              |> put_flash(:info, "🎉 Application submitted successfully! The shelter will contact you soon.")
              |> redirect(to: ~p"/adopt")

            {:noreply, socket}

          {:error, :pet_not_available} ->
            socket =
              socket
              |> put_flash(:error, "Sorry, this pet is no longer available.")
              |> redirect(to: ~p"/adopt")

            {:noreply, socket}

          {:error, error_changeset} when is_struct(error_changeset, Ecto.Changeset) ->
            {:noreply,
             socket
             |> assign(:submitting, false)
             |> assign_form(error_changeset)
             |> put_flash(:error, "Please fix the errors below.")}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:submitting, false)
             |> put_flash(:error, "Failed to submit application. Please try again.")}
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
        <div class="container mx-auto px-4 max-w-4xl">
          <!-- Back Button -->
          <.link navigate={~p"/adopt"} class="btn btn-ghost mb-6">
            <.icon name="hero-arrow-left" class="w-5 h-5" /> Back to Pets
          </.link>

          <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
            <!-- Pet Info Card (Sidebar) -->
            <div class="lg:col-span-1">
              <div class="card bg-base-100 shadow-xl sticky top-8">
                <figure class="h-48 bg-gradient-to-br from-primary/30 via-secondary/30 to-accent/30 flex items-center justify-center">
                  <span class="text-8xl">{pet_emoji(@pet.species)}</span>
                </figure>
                <div class="card-body">
                  <h2 class="card-title text-2xl flex-wrap">
                    <span class="truncate" title={@pet.name}>{@pet.name}</span>
                    <span class="badge badge-secondary flex-shrink-0">{@pet.species}</span>
                  </h2>

                  <!-- Pet Details - Badges for better readability -->
                  <div class="flex flex-wrap gap-2">
                    <span class="badge badge-outline">{@pet.breed}</span>
                    <span class="badge badge-outline">{@pet.age} {if @pet.age == 1, do: "yr", else: "yrs"}</span>
                    <span class="badge badge-outline">{@pet.gender}</span>
                  </div>

                  <!-- Description with Modal -->
                  <p class="mt-2 text-sm line-clamp-2">{@pet.description}</p>
                  <button
                    type="button"
                    class="btn btn-xs btn-ghost text-primary"
                    onclick="description_modal.showModal()"
                  >
                    See more
                  </button>

                  <div class="divider my-2"></div>

                  <!-- Health & Shelter - Icons with Tooltips -->
                  <div class="flex gap-4 justify-center">
                    <div class="tooltip" data-tip={@pet.health_status}>
                      <div class="btn btn-circle btn-ghost btn-lg text-success">
                        <.icon name="hero-heart" class="w-8 h-8" />
                      </div>
                    </div>
                    <div class="tooltip" data-tip={@pet.shelter_name}>
                      <div class="btn btn-circle btn-ghost btn-lg text-primary">
                        <.icon name="hero-map-pin" class="w-8 h-8" />
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <!-- Application Form -->
            <div class="lg:col-span-2">
              <div class="card bg-base-100 shadow-xl">
                <div class="card-body">
                  <h1 class="card-title text-3xl mb-2">
                    <.icon name="hero-document-text" class="w-8 h-8" />
                    Adoption Application
                  </h1>
                  <p class="text-base-content/70 mb-6">
                    Please fill out the form below to apply to adopt {@pet.name}.
                    The shelter will review your application and contact you.
                  </p>

                  <.form
                    for={@form}
                    id="application-form"
                    phx-change="validate"
                    phx-submit="submit"
                  >
                    <!-- Personal Information -->
                    <div class="bg-base-200 rounded-lg p-4 mb-6">
                      <h3 class="font-semibold text-lg mb-4 flex items-center gap-2">
                        <.icon name="hero-user" class="w-5 h-5" /> Personal Information
                      </h3>

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
                          label="Email Address"
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
                          prompt="Select your home type..."
                          options={["House", "Apartment", "Condo", "Farm"]}
                        />
                      </div>
                    </div>

                    <!-- Pet Experience -->
                    <div class="bg-base-200 rounded-lg p-4 mb-6">
                      <h3 class="font-semibold text-lg mb-4 flex items-center gap-2">
                        <.icon name="hero-sparkles" class="w-5 h-5" /> Pet Experience
                      </h3>

                      <div class="space-y-4">
                        <.input
                          field={@form[:has_experience]}
                          type="select"
                          label="Do you have experience with pets?"
                          prompt="Select..."
                          options={[{"Yes, I have pet experience", "true"}, {"No, this is my first pet", "false"}]}
                        />
                        <.input
                          field={@form[:has_other_pets]}
                          type="select"
                          label="Do you currently have other pets?"
                          prompt="Select..."
                          options={[{"Yes", "true"}, {"No", "false"}]}
                        />
                      </div>
                    </div>

                    <!-- Why Adopt -->
                    <div class="bg-base-200 rounded-lg p-4 mb-6">
                      <h3 class="font-semibold text-lg mb-4 flex items-center gap-2">
                        <.icon name="hero-heart" class="w-5 h-5" /> Why {@pet.name}?
                      </h3>

                      <.input
                        field={@form[:reason]}
                        type="textarea"
                        label={"Tell us why you'd be a great match for #{@pet.name}"}
                        placeholder="Share your story... Why do you want to adopt this pet? What kind of home and care can you provide?"
                        rows="5"
                      />
                    </div>

                    <!-- Submit -->
                    <div class="flex flex-col sm:flex-row gap-4 justify-end">
                      <.link navigate={~p"/adopt"} class="btn btn-ghost">
                        Cancel
                      </.link>
                      <button
                        type="submit"
                        class="btn btn-primary btn-lg"
                        disabled={@submitting}
                        phx-disable-with="Submitting..."
                      >
                        <.icon name="hero-paper-airplane" class="w-5 h-5" />
                        Submit Application
                      </button>
                    </div>
                  </.form>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Description Modal -->
      <dialog id="description_modal" class="modal">
        <div class="modal-box">
          <h3 class="font-bold text-lg flex items-center gap-2">
            <span class="text-2xl">{pet_emoji(@pet.species)}</span>
            About {@pet.name}
          </h3>
          <p class="py-4">{@pet.description}</p>
          <div class="modal-action">
            <form method="dialog">
              <button class="btn">Close</button>
            </form>
          </div>
        </div>
        <form method="dialog" class="modal-backdrop">
          <button>close</button>
        </form>
      </dialog>
    </Layouts.app>
    """
  end

  # Helper Functions

  defp pet_emoji("Dog"), do: "🐕"
  defp pet_emoji("Cat"), do: "🐈"
  defp pet_emoji("Rabbit"), do: "🐰"
  defp pet_emoji("Bird"), do: "🦜"
  defp pet_emoji(_), do: "🐾"
end
