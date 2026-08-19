defmodule Labyrinth.Game.TurnFSM do
  @moduledoc """
  Finite State Machine (FSM) managing turn progression and state transitions for Labyrinth.
  Uses `Finitomata` for deterministic state transitions and bot turn orchestration.

  States:
  * `:lobby` - Waiting for expedition start
  * `:awaiting_human` - Waiting for human player input
  * `:executing_bot` - Executing AI bot turn(s)
  * `:game_over` - Expedition finished
  """

  @fsm """
  lobby --> |start_expedition| awaiting_human
  lobby --> |start_expedition_bot| executing_bot
  awaiting_human --> |turn_completed_human| awaiting_human
  awaiting_human --> |turn_completed_bot| executing_bot
  awaiting_human --> |finish_game| game_over
  executing_bot --> |bot_step_bot| executing_bot
  executing_bot --> |bot_step_human| awaiting_human
  executing_bot --> |finish_game| game_over
  """

  use Finitomata, fsm: @fsm, auto_terminate: false

  alias Labyrinth.Game.Engine

  @doc """
  Determines the appropriate next FSM state for a given game engine.
  """
  def target_state(%Engine{status: :lobby}), do: :lobby
  def target_state(%Engine{status: :finished}), do: :game_over

  def target_state(%Engine{status: :in_progress} = engine) do
    curr = Engine.current_player(engine)

    cond do
      curr == nil -> :awaiting_human
      curr.is_bot and curr.status in [:active, :wounded, :stunned] -> :executing_bot
      true -> :awaiting_human
    end
  end

  @doc """
  Executes bot turns continuously until a human player's turn or game end is reached.
  Guarantees zero-stall execution by safely recovering if a bot cannot act.
  """
  def process_bot_sequence(engine) do
    do_process_bot_sequence(engine, 0)
  end

  defp do_process_bot_sequence(engine, depth) when depth > 20 do
    # Circuit breaker against infinite loops
    force_advance_turn(engine)
  end

  defp do_process_bot_sequence(%Engine{status: :in_progress} = engine, depth) do
    curr = Engine.current_player(engine)

    cond do
      curr == nil ->
        {engine, nil}

      curr.status in [:eliminated, :escaped] ->
        # Automatically skip eliminated or escaped players
        forced = force_advance_turn(engine)
        do_process_bot_sequence(forced, depth + 1)

      curr.is_bot and curr.status in [:active, :wounded, :stunned] ->
        action = Labyrinth.Game.BotAI.choose_action(engine, curr)

        case Engine.process_turn(engine, curr.id, action) do
          {%Engine{} = updated_engine, summary} ->
            # Record turn in DB
            Labyrinth.Games.record_turn(%{
              game_id: updated_engine.id,
              turn_number: length(Labyrinth.Games.list_turns_for_game(updated_engine.id)) + 1,
              player_id: curr.id,
              player_name: summary.player_name,
              action_type: summary.action_type,
              direction: summary.direction,
              result: summary.result,
              sound_effects: summary.sound_effects,
              position_before: %{
                "x" => elem(summary.pos_before, 0),
                "y" => elem(summary.pos_before, 1)
              },
              position_after: %{
                "x" => elem(summary.pos_after, 0),
                "y" => elem(summary.pos_after, 1)
              }
            })

            if updated_engine.status == :finished do
              Labyrinth.Games.update_game_status(
                updated_engine.id,
                :finished,
                updated_engine.winner_name
              )

              {updated_engine, summary}
            else
              # Continue sequence for consecutive bots or return to human
              do_process_bot_sequence(updated_engine, depth + 1)
            end

          _ ->
            # If bot action failed, safely force advance turn to avoid stalling
            forced = force_advance_turn(engine)
            do_process_bot_sequence(forced, depth + 1)
        end

      true ->
        {engine, nil}
    end
  end

  defp do_process_bot_sequence(engine, _depth), do: {engine, nil}

  defp force_advance_turn(engine) do
    num = length(engine.players)

    if num > 0 do
      next_idx = rem(engine.turn_index + 1, num)
      %{engine | turn_index: next_idx}
    else
      engine
    end
  end

  @impl Finitomata
  def on_transition(:lobby, :start_expedition, _payload, state) do
    {:ok, :awaiting_human, state}
  end

  @impl Finitomata
  def on_transition(:lobby, :start_expedition_bot, _payload, state) do
    {:ok, :executing_bot, state}
  end

  @impl Finitomata
  def on_transition(:awaiting_human, :turn_completed_human, _payload, state) do
    {:ok, :awaiting_human, state}
  end

  @impl Finitomata
  def on_transition(:awaiting_human, :turn_completed_bot, _payload, state) do
    {:ok, :executing_bot, state}
  end

  @impl Finitomata
  def on_transition(:executing_bot, :bot_step_bot, _payload, state) do
    {:ok, :executing_bot, state}
  end

  @impl Finitomata
  def on_transition(:executing_bot, :bot_step_human, _payload, state) do
    {:ok, :awaiting_human, state}
  end

  @impl Finitomata
  def on_transition(_, :finish_game, _payload, state) do
    {:ok, :game_over, state}
  end
end
