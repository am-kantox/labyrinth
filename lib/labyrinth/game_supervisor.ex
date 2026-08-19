defmodule Labyrinth.GameSupervisor do
  @moduledoc """
  Dynamic supervisor for spawning and managing active Labyrinth game processes.
  """

  alias Labyrinth.GameServer

  def start_game(opts) do
    game_id = Keyword.fetch!(opts, :game_id)

    case Registry.lookup(Labyrinth.GameRegistry, game_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        spec = {GameServer, opts}
        DynamicSupervisor.start_child(Labyrinth.GameSupervisor, spec)
    end
  end

  def stop_game(game_id) do
    case Registry.lookup(Labyrinth.GameRegistry, game_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(Labyrinth.GameSupervisor, pid)
      [] -> :ok
    end
  end
end
