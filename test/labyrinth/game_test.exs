defmodule Labyrinth.GameTest do
  use Labyrinth.DataCase, async: true

  alias Labyrinth.Game.{Engine, Generator}
  alias Labyrinth.Prolog.Validator
  alias Labyrinth.Games

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
               "teleport",
               "hospital",
               "arsenal",
               "treasure",
               "escaped"
             ]

      assert %Engine{} = updated_game
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
end
