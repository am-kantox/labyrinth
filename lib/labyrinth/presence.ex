defmodule Labyrinth.Presence do
  @moduledoc """
  Provides presence tracking for Labyrinth game rooms.
  """
  use Phoenix.Presence,
    otp_app: :labyrinth,
    pubsub_server: Labyrinth.PubSub
end
