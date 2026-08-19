defmodule LabyrinthWeb.PageController do
  use LabyrinthWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
