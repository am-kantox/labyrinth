defmodule LabyrinthWeb.AuthController do
  use LabyrinthWeb, :controller

  plug Ueberauth

  alias LabyrinthWeb.UserAuth

  @doc """
  Callback for Ueberauth authentication (success or failure).
  """
  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    username = auth.info.nickname || auth.info.name || auth.uid || "Player"
    player_id = "user_" <> String.downcase(String.replace(username, ~r/[^\w]/, "_"))
    player_name = username

    conn
    |> UserAuth.log_in_player(player_id, player_name)
    |> put_flash(:info, "Successfully authenticated as #{player_name}!")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_failure: fails}} = conn, _params) do
    reason =
      fails.errors
      |> Enum.map(& &1.message)
      |> Enum.join(", ")

    conn
    |> put_flash(:error, "Failed to authenticate with Ueberauth: #{reason}")
    |> redirect(to: ~p"/")
  end

  @doc """
  Request action triggered when Ueberauth initiates auth flow.
  """
  def request(conn, _params) do
    conn
  end

  @doc """
  Logs out the user.
  """
  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_player()
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: ~p"/")
  end
end
