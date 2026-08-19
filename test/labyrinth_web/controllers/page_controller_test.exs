defmodule LabyrinthWeb.PageControllerTest do
  use LabyrinthWeb.ConnCase
  import Phoenix.LiveViewTest

  test "GET / loads LobbyLive", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "LABYRINTH"
    assert html =~ "Create New Labyrinth"
  end
end
