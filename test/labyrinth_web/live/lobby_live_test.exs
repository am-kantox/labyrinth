defmodule LabyrinthWeb.LobbyLiveTest do
  use LabyrinthWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias Labyrinth.Games

  setup do
    Ecto.Adapters.SQL.Sandbox.mode(Labyrinth.Repo, {:shared, self()})
    :ok
  end

  test "renders lobby page and allows tab navigation", %{conn: conn} do
    {:ok, db_game} =
      Games.create_game(%{
        id: Ecto.UUID.generate(),
        name: "Active Lobby Test Game",
        width: 10,
        height: 10,
        status: "lobby",
        map_data: %{"width" => 10, "height" => 10},
        settings: %{"bot_count" => 0}
      })

    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "Labyrinth Lobby"
    assert html =~ db_game.name

    # Switch tabs
    stale_html = render_click(view, "select_tab", %{"tab" => "stale"})
    assert stale_html =~ "Stale"

    finished_html = render_click(view, "select_tab", %{"tab" => "finished"})
    assert finished_html =~ "Finished"
  end

  test "supports pagination controls in lobby", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    next_html = render_click(view, "next_page", %{})
    assert is_binary(next_html)

    prev_html = render_click(view, "prev_page", %{})
    assert is_binary(prev_html)
  end
end
