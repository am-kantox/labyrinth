defmodule Labyrinth.GameTest do
  use Labyrinth.DataCase, async: false

  alias Labyrinth.Game.{Engine, Generator}
  alias Labyrinth.Prolog.Validator
  alias Labyrinth.Games
  alias Labyrinth.MapUtils

  describe "Prolog Maze Validation & Generation" do
    test "generates valid solvable map and satisfies Prolog reachability rules" do
      {:ok, map_data} =
        Generator.generate_map(width: 8, height: 8, pit_count: 2, teleport_count: 1)

      assert map_data.width == 8
      assert map_data.height == 8
      assert map_data.entrance != nil
      assert map_data.treasure != nil
      assert map_data.exit != nil

      assert {:ok, _info} = Validator.validate_map(map_data)
    end
  end

  describe "Game Engine Mechanics" do
    test "initializes new game with default parameters" do
      game = Engine.new_game("Test Labyrinth", width: 8, height: 8)
      assert game.name == "Test Labyrinth"
      assert game.status == :lobby
      assert game.players == []
    end

    test "adds human and bot players and transitions turn state" do
      game = Engine.new_game("Multiplayer Test", width: 8, height: 8)
      game = Engine.add_player(game, "player-1", "Alice")
      game = Engine.add_player(game, "bot-1", "Bot Bob", true)

      assert length(game.players) == 2

      game_started = Engine.start_game(game)
      assert game_started.status == :in_progress

      current = Engine.current_player(game_started)
      assert current.id == "player-1"
    end

    test "processes valid player move and records action summary" do
      game = Engine.new_game("Move Test", width: 8, height: 8)
      game = Engine.add_player(game, "p1", "Player 1")
      game = Engine.start_game(game)

      # Attempt move east or south
      {updated_game, summary} = Engine.process_turn(game, "p1", {:move, :east})

      assert summary.player_id == "p1"
      assert summary.action_type == "move"

      assert summary.result in [
               "moved",
               "wall",
               "pit",
               "pit_escaped",
               "teleport",
               "hospital",
               "arsenal",
               "treasure",
               "escaped"
             ]

      assert %Engine{} = updated_game
    end

    test "supports difficulty levels (easy, hard)" do
      game_easy = Engine.new_game("Easy", difficulty: :easy)
      game_easy = Engine.add_player(game_easy, "p1", "Easy Player")
      p_easy = List.first(game_easy.players)
      assert p_easy.health == 3
      assert p_easy.bullets == 4

      game_hard = Engine.new_game("Hard", difficulty: :hard)
      game_hard = Engine.add_player(game_hard, "p2", "Hard Player")
      p_hard = List.first(game_hard.players)
      assert p_hard.health == 2
      assert p_hard.bullets == 2
    end

    test "rope item prevents pit stun" do
      game = Engine.new_game("Rope Test", width: 6, height: 6)
      clean_walls = MapSet.delete(game.walls, MapUtils.normalize_wall({0, 0}, {1, 0}))

      game = %{
        game
        | entrance: {0, 0},
          hospital: {5, 5},
          arsenal: {5, 5},
          treasure: {5, 5},
          exit: {5, 5},
          pits: [{1, 0}],
          teleporters: [],
          walls: clean_walls
      }

      game = Engine.add_player(game, "p1", "Climber")
      started_game = Engine.start_game(game)
      p1 = List.first(started_game.players)
      p1_with_rope = %{p1 | x: 0, y: 0, items: MapSet.new([:rope])}
      ready_game = %{started_game | minotaur: nil, players: [p1_with_rope]}

      {updated_game, summary} = Engine.process_turn(ready_game, "p1", {:move, :east})
      assert summary.result == "pit_escaped"
      player_after = List.first(updated_game.players)
      assert player_after.status == :active
      assert not MapSet.member?(player_after.items, :rope)
    end

    test "TurnFSM.process_bot_sequence returns 2-tuple when all players are eliminated" do
      game = Engine.new_game("FSM Test", width: 6, height: 6)
      game = Engine.add_player(game, "bot-1", "Bot 1", true)
      game = Engine.add_player(game, "bot-2", "Bot 2", true)
      started = Engine.start_game(game)

      elim_players = Enum.map(started.players, fn p -> %{p | status: :eliminated} end)
      elim_game = %{started | players: elim_players}

      assert {final_engine, summary} = Labyrinth.Game.TurnFSM.process_bot_sequence(elim_game)
      assert %Engine{} = final_engine
      assert final_engine.status == :finished
      assert summary == nil
    end

    test "shooting directly into a wall self-wounds the shooter" do
      game = Engine.new_game("Shoot Wall Test", width: 6, height: 6)
      game = Engine.add_player(game, "p1", "Shooter")
      p1 = List.first(game.players)
      wall_in_front = MapUtils.normalize_wall({0, 0}, {0, 1})
      game = %{game | entrance: {0, 0}, walls: MapSet.new([wall_in_front])}
      started = Engine.start_game(game)

      ready = %{started | minotaur: nil, players: [%{p1 | x: 0, y: 0, health: 3, bullets: 3}]}

      {updated_game, summary} = Engine.process_turn(ready, "p1", {:shoot, :south})
      assert summary.result == "shot_ricochet"
      shooter_after = List.first(updated_game.players)
      assert shooter_after.health == 2
      assert shooter_after.status == :wounded
    end

    test "generated maps guarantee 100% disjoint entity coordinates" do
      {:ok, map_data} =
        Generator.generate_map(width: 8, height: 8, pit_count: 3, teleport_count: 2)

      assert Generator.entities_disjoint?(map_data) == true
    end

    test "player grabs treasure when stepping into a pit containing treasure" do
      game = Engine.new_game("Pit Treasure Test", width: 6, height: 6)
      clean_walls = MapSet.delete(game.walls, MapUtils.normalize_wall({0, 0}, {1, 0}))

      game = %{
        game
        | entrance: {0, 0},
          treasure: {1, 0},
          pits: [{1, 0}],
          teleporters: [],
          walls: clean_walls
      }

      game = Engine.add_player(game, "p1", "Looter")
      started_game = Engine.start_game(game)
      p1 = List.first(started_game.players)

      ready_game = %{
        started_game
        | players: [%{p1 | x: 0, y: 0, status: :active, has_treasure: false}]
      }

      {updated_game, summary} = Engine.process_turn(ready_game, "p1", {:move, :east})
      assert summary.result == "pit"
      assert String.contains?(summary.message, "GRABBED THE TREASURE")
      looter_after = List.first(updated_game.players)
      assert looter_after.has_treasure == true
    end

    test "player grabs treasure when stepping on a teleporter landing on treasure" do
      game = Engine.new_game("Teleport Treasure Test", width: 6, height: 6)
      clean_walls = MapSet.delete(game.walls, MapUtils.normalize_wall({0, 0}, {1, 0}))

      game = %{
        game
        | entrance: {0, 0},
          treasure: {4, 4},
          pits: [],
          teleporters: [{{1, 0}, {4, 4}}],
          walls: clean_walls
      }

      game = Engine.add_player(game, "p1", "WarpLooter")
      started_game = Engine.start_game(game)
      p1 = List.first(started_game.players)

      ready_game = %{
        started_game
        | players: [%{p1 | x: 0, y: 0, status: :active, has_treasure: false}]
      }

      {updated_game, summary} = Engine.process_turn(ready_game, "p1", {:move, :east})
      assert summary.result == "teleport"
      looter_after = List.first(updated_game.players)
      assert looter_after.x == 4 and looter_after.y == 4
      assert looter_after.has_treasure == true
    end

    test "start_game never places any player on teleporters or pits" do
      game = Engine.new_game("Start Position Test", width: 6, height: 6)
      pits = [{1, 1}, {2, 2}]
      teleporters = [{{0, 0}, {3, 3}}, {{4, 4}, {5, 5}}]
      game = %{game | pits: pits, teleporters: teleporters}

      game = Engine.add_player(game, "p1", "Player 1")
      game = Engine.add_player(game, "p2", "Player 2")
      started = Engine.start_game(game)

      forbidden = MapSet.new([{1, 1}, {2, 2}, {0, 0}, {3, 3}, {4, 4}, {5, 5}])

      for p <- started.players do
        refute MapSet.member?(forbidden, {p.x, p.y})
      end
    end

    test "minotaur attack wounds player (-1 HP) instead of instant kill" do
      game = Engine.new_game("Minotaur Wound Test", width: 6, height: 6)
      game = Engine.add_player(game, "p1", "Survivor")
      p1 = List.first(game.players)

      ready = %{
        game
        | status: :in_progress,
          minotaur: {1, 0},
          walls: MapSet.new(),
          players: [%{p1 | x: 0, y: 0, health: 3, status: :active}]
      }

      {updated_game, summary} = Engine.process_turn(ready, "p1", :pass)
      assert String.contains?(summary.message, "Minotaur attacked Survivor")
      survivor = List.first(updated_game.players)
      assert survivor.health == 2
      assert survivor.status == :wounded
    end

    test "GameServer auto-passes turn when 30s turn timeout is received" do
      game_id = Ecto.UUID.generate()

      {:ok, _pid} =
        Labyrinth.GameServer.start_link(game_id: game_id, name: "Timer Test", bot_count: 0)

      {:ok, _engine} = Labyrinth.GameServer.add_player(game_id, "p1", "LazyPlayer", false)
      {:ok, started} = Labyrinth.GameServer.start_game(game_id)
      assert started.status == :in_progress

      p1 = List.first(started.players)
      via = Labyrinth.GameServer.via_tuple(game_id)
      server_pid = GenServer.whereis(via)
      send(server_pid, {:turn_timeout, p1.id, started.turn_index, started.round_number})

      updated = Labyrinth.GameServer.get_state(game_id)

      assert Enum.any?(updated.log_entries, fn entry ->
               String.contains?(entry, "Auto-passed turn for LazyPlayer")
             end)
    end
  end

  describe "Games Database Persistence Context" do
    test "records turns and retrieves post-its" do
      game_id = Ecto.UUID.generate()

      {:ok, game} =
        Games.create_game(%{
          id: game_id,
          name: "DB Test Game",
          width: 10,
          height: 10,
          status: "lobby",
          map_data: %{
            "entrance" => %{"x" => 0, "y" => 0},
            "exit" => %{"x" => 9, "y" => 9},
            "treasure" => %{"x" => 5, "y" => 5},
            "walls" => []
          },
          settings: %{bot_count: 1}
        })

      assert game.id == game_id

      {:ok, turn} =
        Games.record_turn(%{
          game_id: game_id,
          turn_number: 1,
          player_id: "p1",
          player_name: "Alice",
          action_type: "move",
          direction: "east",
          result: "moved",
          sound_effects: ["Footsteps heard to East"],
          position_before: %{"x" => 0, "y" => 0},
          position_after: %{"x" => 1, "y" => 0}
        })

      assert turn.turn_number == 1

      turns_list = Games.list_turns_for_game(game_id)
      assert length(turns_list) == 1

      {:ok, post_it} =
        Games.save_post_it(%{
          game_id: game_id,
          player_id: "p1",
          title: "Draft Note 1",
          color: "yellow",
          text: "Wall suspected at 2,3"
        })

      assert post_it.title == "Draft Note 1"
      saved_notes = Games.list_post_its(game_id, "p1")
      assert length(saved_notes) == 1
    end
  end

  describe "GameSupervisor and GameServer Process Lifecycle" do
    test "starts a new game server without calling_self errors" do
      game_id = Ecto.UUID.generate()

      assert {:ok, pid} =
               Labyrinth.GameSupervisor.start_game(
                 game_id: game_id,
                 name: "Supervisor Test Game",
                 width: 8,
                 height: 8,
                 bot_count: 1
               )

      assert Process.alive?(pid)

      state = Labyrinth.GameServer.get_state(game_id)
      assert state.id == game_id
      assert state.name == "Supervisor Test Game"
    end

    test "game transitions to finished status when a player exits with the treasure" do
      game = Engine.new_game("Escape Test", width: 6, height: 6)
      game = Engine.add_player(game, "p1", "Hero Explorer")
      game = Engine.start_game(game)

      # Give player treasure and move into exit cell
      {exit_x, exit_y} = game.exit
      p1 = Enum.find(game.players, &(&1.id == "p1"))

      # Pick neighbor cell and direction into exit
      {start_x, start_y, dir} =
        cond do
          exit_x > 0 -> {exit_x - 1, exit_y, :east}
          exit_y > 0 -> {exit_x, exit_y - 1, :south}
          true -> {exit_x + 1, exit_y, :west}
        end

      # Clear any wall between start and exit
      cleared_walls =
        Enum.reject(game.walls, fn {p1_w, p2_w} ->
          (p1_w == {start_x, start_y} and p2_w == {exit_x, exit_y}) or
            (p2_w == {start_x, start_y} and p1_w == {exit_x, exit_y})
        end)
        |> MapSet.new()

      updated_p1 = %{p1 | x: start_x, y: start_y, has_treasure: true}
      game_ready = %{game | players: [updated_p1], walls: cleared_walls}

      {finished_game, summary} = Engine.process_turn(game_ready, "p1", {:move, dir})

      assert finished_game.status == :finished
      assert finished_game.winner_name == "Hero Explorer"
      assert summary.result == "escaped"
    end
  end
end
