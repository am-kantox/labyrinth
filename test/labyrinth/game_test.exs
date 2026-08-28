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
      ready_game = %{started_game | players: [p1_with_rope]}

      {updated_game, summary} = Engine.process_turn(ready_game, "p1", {:move, :east})
      assert summary.result == "pit_escaped"
      player_after = List.first(updated_game.players)
      assert player_after.status == :active
      assert not MapSet.member?(player_after.items, :rope)
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
