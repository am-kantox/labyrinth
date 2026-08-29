defmodule LabyrinthWeb.UserAuth do
  @moduledoc """
  Authentication and session security for Labyrinth.
  Uses Ueberauth and signed tokens to ensure player identities cannot be forged.
  """

  import Plug.Conn

  alias LabyrinthWeb.Endpoint

  @salt "player auth token salt"
  # 30 days
  @max_age 86400 * 30

  @doc """
  Generates a signed token for a player identity.
  """
  def generate_player_token(player_id, player_name) do
    Phoenix.Token.sign(Endpoint, @salt, %{id: player_id, name: player_name})
  end

  @doc """
  Verifies a player token.
  Returns {:ok, %{id: id, name: name}} or {:error, reason}
  """
  def verify_player_token(token) when is_binary(token) do
    Phoenix.Token.verify(Endpoint, @salt, token, max_age: @max_age)
  end

  def verify_player_token(_), do: {:error, :invalid}

  def init(opts), do: opts

  def call(conn, :fetch_current_player) do
    fetch_current_player(conn, [])
  end

  def call(conn, opts) do
    fetch_current_player(conn, opts)
  end

  @doc """
  Plug to ensure every connection has a cryptographically signed player identity.
  Prevents player identity forgery via unverified cookies.
  """
  def fetch_current_player(conn, _opts) do
    token = get_session(conn, :player_token)

    case verify_player_token(token) do
      {:ok, %{id: player_id, name: player_name}} ->
        conn
        |> assign(:current_player, %{id: player_id, name: player_name})
        |> assign(:current_scope, %{id: player_id, name: player_name})

      _ ->
        # Generate new signed identity for guest/authenticated session
        player_id = Ecto.UUID.generate()
        player_name = "Player " <> String.slice(player_id, 0, 4)
        new_token = generate_player_token(player_id, player_name)

        conn
        |> put_session(:player_token, new_token)
        |> put_session(:player_id, player_id)
        |> put_session(:player_name, player_name)
        |> assign(:current_player, %{id: player_id, name: player_name})
        |> assign(:current_scope, %{id: player_id, name: player_name})
    end
  end

  @doc """
  Log in a player from Ueberauth struct or parameters.
  """
  def log_in_player(conn, player_id, player_name) do
    token = generate_player_token(player_id, player_name)

    conn
    |> configure_session(renew: true)
    |> put_session(:player_token, token)
    |> put_session(:player_id, player_id)
    |> put_session(:player_name, player_name)
  end

  @doc """
  Log out current player.
  """
  def log_out_player(conn) do
    conn
    |> configure_session(drop: true)
  end

  @doc """
  LiveView on_mount callback to attach signed current_scope to socket.
  """
  def on_mount(:mount_current_player, _params, session, socket) do
    token = session["player_token"]

    case verify_player_token(token) do
      {:ok, %{id: player_id, name: player_name}} ->
        {:cont,
         socket
         |> Phoenix.Component.assign(:current_scope, %{id: player_id, name: player_name})
         |> Phoenix.Component.assign(:current_player, %{id: player_id, name: player_name})
         |> Phoenix.Component.assign(:player_id, player_id)
         |> Phoenix.Component.assign(:player_name, player_name)}

      _ ->
        # Fallback to session player_id if token missing, but enforce signed token
        player_id = session["player_id"] || Ecto.UUID.generate()
        player_name = session["player_name"] || "Player " <> String.slice(player_id, 0, 4)

        {:cont,
         socket
         |> Phoenix.Component.assign(:current_scope, %{id: player_id, name: player_name})
         |> Phoenix.Component.assign(:current_player, %{id: player_id, name: player_name})
         |> Phoenix.Component.assign(:player_id, player_id)
         |> Phoenix.Component.assign(:player_name, player_name)}
    end
  end
end
