defmodule Labyrinth.GameServer do
  @moduledoc """
  OTP GenServer representing an active Labyrinth game session.
  Manages state, process broadcasting, bot scheduling, turn timer, and async turn persistence.
  """
  use GenServer, restart: :transient

  alias Labyrinth.Game.Engine
  alias Labyrinth.Game.TurnFSM
  alias Labyrinth.Games

  @pubsub Labyrinth.PubSub
  @max_players 4

  defmodule State do
    @moduledoc false
    defstruct [:engine, :timer_ref]
  end

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
      case Games.get_db_game(game_id) do
        nil ->
          name = Keyword.get(opts, :name, "Labyrinth Game")
          width = Keyword.get(opts, :width, 10)
          height = Keyword.get(opts, :height, 10)
          bot_count = Keyword.get(opts, :bot_count, 1)
          pit_count = Keyword.get(opts, :pit_count, 3)
          teleport_count = Keyword.get(opts, :teleport_count, 5)
          wall_density = Keyword.get(opts, :wall_density, 70)
          minotaur_enabled = Keyword.get(opts, :minotaur_enabled, true)
          difficulty = Keyword.get(opts, :difficulty, :normal)

          e =
            Engine.new_game(name,
              id: game_id,
              width: width,
              height: height,
              pit_count: pit_count,
              teleport_count: teleport_count,
              wall_density: wall_density,
              minotaur_enabled: minotaur_enabled,
              difficulty: difficulty
            )

          # Save game record in DB synchronously so parent record exists before turns/updates are recorded
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
              minotaur_enabled: minotaur_enabled,
              difficulty: Atom.to_string(difficulty)
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
            minotaur_unseen: Map.get(map_data, :minotaur_unseen, 0),
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

    {:ok, %State{engine: engine, timer_ref: nil}}
  end

  @impl true
  def handle_call(:get_state, _from, %State{engine: engine} = state) do
    {:reply, engine, state}
  end

  @impl true
  def handle_call({:add_player, player_id, name, is_bot}, _from, %State{engine: engine} = state) do
    player_exists? = Enum.any?(engine.players, fn p -> p.id == player_id end)

    if not player_exists? and length(engine.players) >= @max_players do
      {:reply, {:error, :lobby_full}, state}
    else
      updated_engine = Engine.add_player(engine, player_id, name, is_bot)
      broadcast_state(updated_engine)
      {:reply, {:ok, updated_engine}, %{state | engine: updated_engine}}
    end
  end

  @impl true
  def handle_call({:add_bot, bot_name}, _from, %State{engine: engine} = state) do
    bot_count = Enum.count(engine.players, & &1.is_bot) + 1
    name = bot_name || "Bot Explorer #{bot_count}"
    bot_id = "bot-#{bot_count}-#{System.unique_integer([:positive])}"

    updated_engine = Engine.add_player(engine, bot_id, name, true)
    broadcast_state(updated_engine)
    {:reply, {:ok, updated_engine}, %{state | engine: updated_engine}}
  end

  @impl true
  def handle_call(:start_game, _from, %State{engine: engine} = state) do
    updated_engine = Engine.start_game(engine)
    async_update_game_status(updated_engine.id, updated_engine.status)

    {final_engine, _last_bot_summary} = TurnFSM.process_bot_sequence(updated_engine)

    new_state = reset_and_schedule_timer(state, final_engine)
    broadcast_state(final_engine)
    {:reply, {:ok, final_engine}, new_state}
  end

  @impl true
  def handle_call({:force_turn, player_id}, _from, %State{engine: engine} = state) do
    if player_in_game?(engine, player_id) do
      idx = Enum.find_index(engine.players, fn p -> p.id == player_id end)
      updated_engine = if idx != nil, do: %{engine | turn_index: idx}, else: engine
      {final_engine, _} = TurnFSM.process_bot_sequence(updated_engine)
      new_state = reset_and_schedule_timer(state, final_engine)
      broadcast_state(final_engine)
      {:reply, {:ok, final_engine}, new_state}
    else
      {:reply, {:error, :unknown_player}, state}
    end
  end

  @impl true
  def handle_call({:take_turn, player_id, action}, _from, %State{engine: engine} = state) do
    case Engine.process_turn(engine, player_id, action) do
      {%Engine{} = updated_engine, summary} ->
        # Persist turn in DB asynchronously using engine turn_counter
        turn_num = updated_engine.turn_counter || 1
        async_record_turn(updated_engine.id, turn_num, player_id, summary)

        if updated_engine.status == :finished do
          async_update_game_status(updated_engine.id, :finished, updated_engine.winner_name)
          new_state = reset_and_schedule_timer(state, updated_engine)
          broadcast_state(updated_engine)
          {:reply, {:ok, updated_engine, summary}, new_state}
        else
          # Process any consecutive bot turns deterministically via TurnFSM
          {final_engine, last_bot_summary} = TurnFSM.process_bot_sequence(updated_engine)
          effective_summary = last_bot_summary || summary

          new_state = reset_and_schedule_timer(state, final_engine)
          broadcast_state(final_engine)
          {:reply, {:ok, final_engine, effective_summary}, new_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:reset_bot_rel_tracking, bot_id}, _from, %State{engine: engine} = state) do
    engine_updated = Engine.reset_bot_rel_tracking(engine, bot_id)
    broadcast_state(engine_updated)
    {:reply, {:ok, engine_updated}, %{state | engine: engine_updated}}
  end

  @impl true
  def handle_info({:turn_timeout, player_id, turn_idx, round_num}, %State{engine: engine} = state) do
    curr = Engine.current_player(engine)

    if ((engine.status == :in_progress and curr) && curr.id == player_id) and
         engine.turn_index == turn_idx and engine.round_number == round_num do
      pass_msg = "⏱️ 30s turn timer expired! Auto-passed turn for #{curr.name}."
      game_with_log = %{engine | log_entries: [pass_msg | engine.log_entries]}

      case Engine.process_turn(game_with_log, player_id, :pass) do
        {%Engine{} = updated_engine, summary} ->
          turn_num = updated_engine.turn_counter || 1
          async_record_turn(updated_engine.id, turn_num, player_id, summary)

          {final_engine, _} = TurnFSM.process_bot_sequence(updated_engine)
          new_state = reset_and_schedule_timer(state, final_engine)
          broadcast_state(final_engine)

          {:noreply, new_state}

        _ ->
          {:noreply, state}
      end
    else
      {:noreply, state}
    end
  end

  # Helper functions

  defp reset_and_schedule_timer(%State{timer_ref: ref} = state, engine) do
    if ref, do: Process.cancel_timer(ref)

    if engine.status == :in_progress do
      curr = Engine.current_player(engine)

      if curr && not curr.is_bot && curr.status in [:active, :wounded, :stunned] do
        new_ref =
          Process.send_after(
            self(),
            {:turn_timeout, curr.id, engine.turn_index, engine.round_number},
            30_000
          )

        %{state | engine: engine, timer_ref: new_ref}
      else
        %{state | engine: engine, timer_ref: nil}
      end
    else
      %{state | engine: engine, timer_ref: nil}
    end
  end

  defp start_async_db_task(func) do
    if Application.get_env(:labyrinth, :async_db, true) and Mix.env() != :test do
      Task.Supervisor.start_child(Labyrinth.TaskSupervisor, func)
    else
      func.()
    end
  end

  defp async_record_turn(game_id, turn_number, player_id, summary) do
    start_async_db_task(fn ->
      Games.record_turn(game_id, turn_number, player_id, summary)
    end)
  end

  defp async_update_game_status(game_id, status, winner_name \\ nil) do
    start_async_db_task(fn ->
      Games.update_game_status(game_id, status, winner_name)
    end)
  end

  defp player_in_game?(engine, player_id) do
    Enum.any?(engine.players, fn p -> p.id == player_id end)
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
      "minotaur_unseen" => Map.get(engine, :minotaur_unseen, 0),
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
      minotaur_unseen: Map.get(data, "minotaur_unseen", 0),
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
