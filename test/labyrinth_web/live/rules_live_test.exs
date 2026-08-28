defmodule LabyrinthWeb.RulesLiveTest do
  use LabyrinthWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders game rules and manual page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/rules")

    assert html =~ "Labyrinth: Tactical Exploration Rules &amp; Guide"
    assert html =~ "Objective &amp; Turn Mechanics"
    assert html =~ "Actions &amp; Combat Rules"
    assert html =~ "Landmarks, Traps &amp; Items"
    assert html =~ "Explorer Expedition Post-Its"
  end
end
