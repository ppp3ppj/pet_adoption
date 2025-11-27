defmodule PetAdoption.Shelter do
  @moduledoc """
  Manages shelter information and configuration.
  """
  use Agent

  defstruct [:node_id, :shelter_id, :shelter_name]

  @doc """
  Starts the Shelter agent with configuration from application environment.
  """
  def start_link(_opts) do
    shelter_info = %__MODULE__{
      node_id: Node.self(),
      shelter_id: Application.get_env(:pet_adoption, :shelter_id, "shelter1"),
      shelter_name: Application.get_env(:pet_adoption, :shelter_name, "Animal Rescue Center")
    }

    Agent.start_link(fn -> shelter_info end, name: __MODULE__)
  end

  @doc """
  Gets the current shelter information.
  """
  def get_info do
    Agent.get(__MODULE__, & &1)
  end

  @doc """
  Gets detailed shelter info including connected nodes.
  """
  def get_detailed_info do
    info = get_info()

    %{
      node_id: info.node_id,
      shelter_id: info.shelter_id,
      shelter_name: info.shelter_name,
      connected_nodes: Node.list()
    }
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end
end
