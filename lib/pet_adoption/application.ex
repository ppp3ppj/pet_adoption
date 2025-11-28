defmodule PetAdoption.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies, [])

    children = [
      {Cluster.Supervisor, [topologies, [name: PetAdoption.ClusterSupervisor]]},
      PetAdoptionWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:pet_adoption, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: PetAdoption.PubSub},
      # Core services - order matters!
      PetAdoption.Shelter,
      PetAdoption.CrdtStore,
      PetAdoption.Cluster,
      # Monitor CRDT changes for cross-node LiveView updates
      PetAdoption.CrdtSyncNotifier,
      # Start to serve requests, typically the last entry
      PetAdoptionWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: PetAdoption.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PetAdoptionWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
