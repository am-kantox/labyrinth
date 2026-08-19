defmodule Labyrinth.Games do
  @moduledoc """
  Database context for Labyrinth games, history logs, and player post-its.
  """

  import Ecto.Query, warn: false
  alias Labyrinth.Repo
  alias Labyrinth.Schema.{Game, Turn, PostIt}

  def list_games do
    from(g in Game, order_by: [desc: g.inserted_at])
    |> Repo.all()
  end

  def get_game(id) do
    Repo.get(Game, id)
  end

  def create_game(attrs) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert()
  end

  def update_game_status(game_id, status, winner_name \\ nil) do
    case Repo.get(Game, game_id) do
      nil ->
        {:error, :not_found}

      game ->
        game
        |> Game.changeset(%{status: to_string(status), winner_name: winner_name})
        |> Repo.update()
    end
  end

  def record_turn(attrs) do
    %Turn{}
    |> Turn.changeset(attrs)
    |> Repo.insert()
  end

  def list_turns_for_game(game_id) do
    from(t in Turn, where: t.game_id == ^game_id, order_by: [asc: t.turn_number])
    |> Repo.all()
  end

  def list_post_its(game_id, player_id) do
    from(p in PostIt,
      where: p.game_id == ^game_id and p.player_id == ^player_id,
      order_by: [asc: p.inserted_at]
    )
    |> Repo.all()
  end

  def save_post_it(attrs) do
    case attrs["id"] || attrs[:id] do
      nil ->
        %PostIt{}
        |> PostIt.changeset(attrs)
        |> Repo.insert()

      id ->
        case Repo.get(PostIt, id) do
          nil ->
            %PostIt{}
            |> PostIt.changeset(attrs)
            |> Repo.insert()

          post_it ->
            post_it
            |> PostIt.changeset(attrs)
            |> Repo.update()
        end
    end
  end

  def delete_post_it(id) do
    case Repo.get(PostIt, id) do
      nil -> {:error, :not_found}
      post_it -> Repo.delete(post_it)
    end
  end
end
