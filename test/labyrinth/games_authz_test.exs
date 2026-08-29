defmodule Labyrinth.GamesAuthzTest do
  use ExUnit.Case, async: false

  alias Labyrinth.Games
  alias LabyrinthWeb.UserAuth
  alias Labyrinth.GameServer
  alias Labyrinth.GameSupervisor

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Labyrinth.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Labyrinth.Repo, {:shared, self()})
    :ok
  end

  defp create_test_game do
    game_id = Ecto.UUID.generate()

    {:ok, db_game} =
      Games.create_game(%{
        id: game_id,
        name: "Authz Test Game",
        width: 10,
        height: 10,
        status: "in_progress",
        map_data: %{"width" => 10, "height" => 10},
        settings: %{"bot_count" => 0, "pit_count" => 2}
      })

    db_game.id
  end

  describe "Post-It authorization" do
    test "player can create and update their own post-it note" do
      game_id = create_test_game()
      player1 = "player_alice"

      {:ok, created} =
        Games.save_post_it(
          %{
            "game_id" => game_id,
            "player_id" => player1,
            "title" => "Alice Note",
            "text" => "Secret map notes"
          },
          player1
        )

      assert created.player_id == player1
      assert Games.can_modify_post_it?(created, player1) == true

      {:ok, updated} =
        Games.save_post_it(
          %{
            "id" => created.id,
            "text" => "Updated map notes"
          },
          player1
        )

      assert updated.text == "Updated map notes"
    end

    test "player cannot update another player's post-it note" do
      game_id = create_test_game()
      player1 = "player_alice"
      player2 = "player_bob"

      {:ok, created} =
        Games.save_post_it(
          %{
            "game_id" => game_id,
            "player_id" => player1,
            "text" => "Alice's note"
          },
          player1
        )

      assert Games.can_modify_post_it?(created, player2) == false

      result =
        Games.save_post_it(
          %{
            "id" => created.id,
            "text" => "Bob trying to overwrite"
          },
          player2
        )

      assert result == {:error, :unauthorized}
    end

    test "player can delete their own post-it note but not others" do
      game_id = create_test_game()
      player1 = "player_alice"
      player2 = "player_bob"

      {:ok, note} =
        Games.save_post_it(
          %{
            "game_id" => game_id,
            "player_id" => player1,
            "text" => "Alice note"
          },
          player1
        )

      assert Games.delete_post_it(note.id, player2) == {:error, :unauthorized}
      assert {:ok, deleted} = Games.delete_post_it(note.id, player1)
      assert deleted.id == note.id
    end

    test "player can toggle stick state on their own post-it note but not others" do
      game_id = create_test_game()
      player1 = "player_alice"
      player2 = "player_bob"

      {:ok, note} =
        Games.save_post_it(
          %{
            "game_id" => game_id,
            "player_id" => player1,
            "text" => "Alice note"
          },
          player1
        )

      assert Games.toggle_stick_post_it(note.id, player2) == {:error, :unauthorized}
      assert {:ok, toggled} = Games.toggle_stick_post_it(note.id, player1)
      assert toggled.is_stuck == true
    end
  end

  describe "UserAuth signed tokens" do
    test "verifies valid signed token and rejects tampered token" do
      token = UserAuth.generate_player_token("p_123", "Player One")
      assert {:ok, %{id: "p_123", name: "Player One"}} = UserAuth.verify_player_token(token)

      assert {:error, _} = UserAuth.verify_player_token(token <> "tampered")
      assert {:error, _} = UserAuth.verify_player_token(nil)
    end
  end

  describe "GameServer max player cap" do
    test "enforces max player limit" do
      game_id = Ecto.UUID.generate()
      {:ok, _pid} = GameSupervisor.start_game(game_id: game_id, bot_count: 0)

      assert {:ok, _} = GameServer.add_player(game_id, "p1", "Player 1")
      assert {:ok, _} = GameServer.add_player(game_id, "p2", "Player 2")
      assert {:ok, _} = GameServer.add_player(game_id, "p3", "Player 3")
      assert {:ok, _} = GameServer.add_player(game_id, "p4", "Player 4")

      assert {:error, :lobby_full} = GameServer.add_player(game_id, "p5", "Player 5")

      # Re-adding an existing player is allowed
      assert {:ok, _} = GameServer.add_player(game_id, "p1", "Player 1")
    end
  end
end
