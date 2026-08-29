defmodule LabyrinthWeb.HistoryLiveTest do
  use LabyrinthWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Labyrinth.Games

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Labyrinth.Repo, {:shared, self()})
    :ok
  end

  test "renders history replay and responds to step slider and play toggle", %{conn: conn} do
    game_id = Ecto.UUID.generate()

    {:ok, game} =
      Games.create_game(%{
        id: game_id,
        name: "History Replay Game",
        width: 6,
        height: 6,
        status: "finished",
        map_data: %{
          "width" => 6,
          "height" => 6,
          "entrance" => %{"x" => 0, "y" => 0},
          "exit" => %{"x" => 5, "y" => 5},
          "treasure" => %{"x" => 3, "y" => 3},
          "hospital" => %{"x" => 2, "y" => 2},
          "arsenal" => %{"x" => 4, "y" => 4},
          "minotaur" => %{"x" => 1, "y" => 1},
          "pits" => [],
          "teleporters" => [],
          "walls" => []
        },
        settings: %{"bot_count" => 0}
      })

    {:ok, _turn} =
      Games.record_turn(%{
        game_id: game_id,
        turn_number: 1,
        player_id: "p1",
        player_name: "Explorer",
        action_type: "move",
        direction: "east",
        result: "moved",
        sound_effects: [],
        position_before: %{"x" => 0, "y" => 0},
        position_after: %{"x" => 1, "y" => 0}
      })

    {:ok, view, html} = live(conn, ~p"/history/#{game.id}")

    assert html =~ "History Replay Game"

    # Step slider change
    step_html = render_click(view, "set_step", %{"step" => "1"})
    assert step_html =~ "Explorer"

    # Toggle play auto-step
    play_html = render_click(view, "toggle_play", %{})
    assert play_html =~ "Pause" || play_html =~ "Play"
  end
end
