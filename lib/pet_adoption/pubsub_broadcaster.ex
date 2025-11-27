defmodule PetAdoption.PubSubBroadcaster do
  @moduledoc """
  Handles PubSub broadcasting for pet adoption events.
  """

  @topic "pet_updates"

  @doc """
  Broadcasts an update to all subscribers.
  """
  def broadcast(type, data) do
    Phoenix.PubSub.broadcast(
      PetAdoption.PubSub,
      @topic,
      {:pet_update, type, data}
    )
  end

  @doc """
  Returns the topic name for subscriptions.
  """
  def topic, do: @topic
end
