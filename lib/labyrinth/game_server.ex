defmodule Labyrinth.GameServer do
  @moduledoc """
  OTP GenServer representing an active Labyrinth game session.
  Manages state, process broadcasting, bot scheduling, and turn persistence.
  """
  use GenServer, restart: :transient

  alias Labyrinth.Game.Engine
  alias Labyrinth.Game.TurnFSM
  alias Labyrinth.Games

  @pubsub Labyrinth.PubSub

  # Client API

  def via_tuple(game_id) do
    {:via, Registry, {Labyrinth.GameRegistry, game_id}}
  end

  def start_link(opts) do
    game_id = Keyword.fetch!(opts, :game_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(game_id))
  end

  def get_state(game_id) do
    GenServer.call(via_tuple(game_id), :get_state)
  end

  def add_player(game_id, player_id, name, is_bot \\ false) do
    GenServer.call(via_tuple(game_id), {:add_player, player_id, name, is_bot})
  end

  def add_bot(game_id, bot_name \\ nil) do
    GenServer.call(via_tuple(game_id), {:add_bot, bot_name})
  end

  def start_game(game_id) do
    GenServer.call(via_tuple(game_id), :start_game)
  end

  def take_turn(game_id, player_id, action) do
    GenServer.call(via_tuple(game_id), {:take_turn, player_id, action})
  end

  def force_turn(game_id, player_id) do
    GenServer.call(via_tuple(game_id), {:force_turn, player_id})
  end

  def reset_bot_rel_tracking(game_id, bot_id) do
    GenServer.call(via_tuple(game_id), {:reset_bot_rel_tracking, bot_id})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    game_id = Keyword.fetch!(opts, :game_id)

    # Check if existing game in DB or create new
    engine =
      case Games.get_game(game_id) do
        nil ->
          name = Keyword.get(opts, :name, "Labyrinth Game")
          width = Keyword.get(opts, :width, 10)
          height = Keyword.get(opts, :height, 10)
          bot_count = Keyword.get(opts, :bot_count, 1)
          pit_count = Keyword.get(opts, :pit_count, 3)
          teleport_count = Keyword.get(opts, :teleport_count, 5)
          wall_density = Keyword.get(opts, :wall_density, 70)
          minotaur_enabled = Keyword.get(opts, :minotaur_enabled, true)

          e =
            Engine.new_game(name,
              width: width,
              height: height,
              pit_count: pit_count,
              teleport_count: teleport_count,
              wall_density: wall_density,
              minotaur_enabled: minotaur_enabled
            )

          # Save game record in DB
          {:ok, _db_game} =
            Games.create_game(%{
              id: e.id,
              name: e.name,
              width: e.width,
              height: e.height,
              status: "lobby",
              map_data: serialize_map_data(e),
              settings: %{
                bot_count: bot_count,
                pit_count: pit_count,
                teleport_count: teleport_count,
                wall_density: wall_density,
                minotaur_enabled: minotaur_enabled
              }
            })

          # Add requested bots
          if bot_count > 0 do
            Enum.reduce(1..bot_count, e, fn idx, acc ->
              Engine.add_player(acc, "bot-#{idx}", "Bot Explorer #{idx}", true)
            end)
          else
            e
          end

        db_game ->
          # Restore from DB map_data
          map_data = deserialize_map_data(db_game.map_data)

          e = %Engine{
            id: db_game.id,
            name: db_game.name,
            width: db_game.width,
            height: db_game.height,
            entrance: map_data.entrance,
            exit: map_data.exit,
            treasure: map_data.treasure,
            minotaur: map_data.minotaur,
            pits: map_data.pits,
            teleporters: map_data.teleporters,
            walls: map_data.walls,
            destroyed_walls: Map.get(map_data, :destroyed_walls, MapSet.new()),
            players: [],
            turn_index: 0,
            round_number: 1,
            status: String.to_atom(db_game.status),
            winner_name: db_game.winner_name,
            log_entries: ["Game loaded from storage."]
          }

          # Add default bot if needed
          Engine.add_player(e, "bot-1", "Bot Explorer 1", true)
      end

    {:ok, engine}
  end

  @impl true
  def handle_call(:get_state, _from, engine) do
    {:reply, engine, engine}
  end

  @impl true
  def handle_call({:add_player, player_id, name, is_bot}, _from, engine) do
    updated_engine = Engine.add_player(engine, player_id, name, is_bot)
    broadcast_state(updated_engine)
    {:reply, {:ok, updated_engine}, updated_engine}
  end

  @impl true
  def handle_call({:add_bot, bot_name}, _from, engine) do
    bot_count = Enum.count(engine.players, & &1.is_bot) + 1
    name = bot_name || "Bot Explorer #{bot_count}"
    bot_id = "bot-#{bot_count}-#{System.unique_integer([:positive])}"

    updated_engine = Engine.add_player(engine, bot_id, name, true)
    broadcast_state(updated_engine)
    {:reply, {:ok, updated_engine}, updated_engine}
  end

  @impl true
  def handle_call(:start_game, _from, engine) do
    updated_engine = Engine.start_game(engine)
    Games.update_game_status(updated_engine.id, updated_engine.status)

    {final_engine, _last_bot_summary} = TurnFSM.process_bot_sequence(updated_engine)

    broadcast_state(final_engine)
    {:reply, {:ok, final_engine}, final_engine}
  end

  @impl true
  def handle_call({:force_turn, player_id}, _from, engine) do
    idx = Enum.find_index(engine.players, fn p -> p.id == player_id end)
    updated_engine = if idx != nil, do: %{engine | turn_index: idx}, else: engine
    {final_engine, _} = TurnFSM.process_bot_sequence(updated_engine)
    broadcast_state(final_engine)
    {:reply, {:ok, final_engine}, final_engine}
  end

  @impl true
  def handle_call({:take_turn, player_id, action}, _from, engine) do
    case Engine.process_turn(engine, player_id, action) do
      {%Engine{} = updated_engine, summary} ->
        # Persist human turn in DB
        Games.record_turn(%{
          game_id: updated_engine.id,
          turn_number: length(Games.list_turns_for_game(updated_engine.id)) + 1,
          player_id: player_id,
          player_name: summary.player_name,
          action_type: summary.action_type,
          direction: summary.direction,
          result: summary.result,
          sound_effects: summary.sound_effects,
          position_before: %{
            "x" => elem(summary.pos_before, 0),
            "y" => elem(summary.pos_before, 1)
          },
          position_after: %{"x" => elem(summary.pos_after, 0), "y" => elem(summary.pos_after, 1)}
        })

        if updated_engine.status == :finished do
          Games.update_game_status(updated_engine.id, :finished, updated_engine.winner_name)
          broadcast_state(updated_engine)
          {:reply, {:ok, updated_engine, summary}, updated_engine}
        else
          # Process any consecutive bot turns deterministically via TurnFSM
          {final_engine, last_bot_summary} = TurnFSM.process_bot_sequence(updated_engine)
          effective_summary = last_bot_summary || summary

          broadcast_state(final_engine)
          {:reply, {:ok, final_engine, effective_summary}, final_engine}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, engine}
    end
  end

  @impl true
  def handle_call({:reset_bot_rel_tracking, bot_id}, _from, engine) do
    engine_updated = Engine.reset_bot_rel_tracking(engine, bot_id)
    broadcast_state(engine_updated)
    {:reply, {:ok, engine_updated}, engine_updated}
  end

  defp broadcast_state(engine) do
    Phoenix.PubSub.broadcast(@pubsub, "game:#{engine.id}", {:game_updated, engine})
  end

  defp serialize_map_data(engine) do
    %{
      "entrance" => tuple_to_map(engine.entrance),
      "exit" => tuple_to_map(engine.exit),
      "treasure" => tuple_to_map(engine.treasure),
      "hospital" => tuple_to_map(engine.hospital),
      "arsenal" => tuple_to_map(engine.arsenal),
      "minotaur" => tuple_to_map(engine.minotaur),
      "pits" => Enum.map(engine.pits, &tuple_to_map/1),
      "teleporters" =>
        Enum.map(engine.teleporters, fn {p1, p2} ->
          %{"p1" => tuple_to_map(p1), "p2" => tuple_to_map(p2)}
        end),
      "walls" =>
        Enum.map(engine.walls, fn {{x1, y1}, {x2, y2}} ->
          %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}
        end),
      "destroyed_walls" =>
        Enum.map(Map.get(engine, :destroyed_walls, MapSet.new()), fn {{x1, y1}, {x2, y2}} ->
          %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}
        end)
    }
  end

  defp deserialize_map_data(data) do
    %{
      entrance: map_to_tuple(data["entrance"]),
      exit: map_to_tuple(data["exit"]),
      treasure: map_to_tuple(data["treasure"]),
      hospital:
        map_to_tuple(
          data["hospital"] ||
            %{"x" => div(data["width"] || 10, 2) - 1, "y" => div(data["height"] || 10, 2)}
        ),
      arsenal:
        map_to_tuple(
          data["arsenal"] ||
            %{"x" => div(data["width"] || 10, 2) + 1, "y" => div(data["height"] || 10, 2)}
        ),
      minotaur: map_to_tuple(data["minotaur"]),
      pits: Enum.map(data["pits"] || [], &map_to_tuple/1),
      teleporters:
        Enum.map(data["teleporters"] || [], fn t ->
          {map_to_tuple(t["p1"]), map_to_tuple(t["p2"])}
        end),
      walls:
        Enum.map(data["walls"] || [], fn w -> {{w["x1"], w["y1"]}, {w["x2"], w["y2"]}} end)
        |> MapSet.new(),
      destroyed_walls:
        Enum.map(data["destroyed_walls"] || [], fn w ->
          {{w["x1"], w["y1"]}, {w["x2"], w["y2"]}}
        end)
        |> MapSet.new()
    }
  end

  defp tuple_to_map(nil), do: nil
  defp tuple_to_map({x, y}), do: %{"x" => x, "y" => y}

  defp map_to_tuple(nil), do: nil
  defp map_to_tuple(%{"x" => x, "y" => y}), do: {x, y}
end
