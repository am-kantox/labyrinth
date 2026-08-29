defmodule Labyrinth.Games do
  @moduledoc """
  Database context for Labyrinth games, history logs, and player post-its.
  Includes authorization checks to ensure players only access and modify their own assets.
  """

  import Ecto.Query, warn: false
  alias Labyrinth.Repo
  alias Labyrinth.Schema.{Game, Turn, PostIt}

  def list_games do
    from(g in Game, order_by: [desc: g.inserted_at])
    |> Repo.all()
  end

  def list_games_by_tab(tab, page \\ 1, page_size \\ 30) do
    ten_mins_ago = NaiveDateTime.utc_now() |> NaiveDateTime.add(-600, :second)
    offset = max(0, page - 1) * page_size

    base_query =
      case tab do
        :active ->
          from(g in Game,
            where: g.status in ["lobby", "in_progress"] and g.updated_at >= ^ten_mins_ago,
            order_by: [desc: g.updated_at]
          )

        :stale ->
          from(g in Game,
            where: g.status in ["lobby", "in_progress"] and g.updated_at < ^ten_mins_ago,
            order_by: [desc: g.updated_at]
          )

        :finished ->
          from(g in Game,
            where: g.status == "finished",
            order_by: [desc: g.updated_at]
          )

        _ ->
          from(g in Game, order_by: [desc: g.updated_at])
      end

    games_plus_one =
      base_query
      |> limit(^(page_size + 1))
      |> offset(^offset)
      |> Repo.all()

    has_more = length(games_plus_one) > page_size
    games = Enum.take(games_plus_one, page_size)

    {games, has_more}
  end

  def get_db_game(id) do
    Repo.get(Game, id)
  rescue
    Ecto.QueryError -> nil
  end

  def get_game(id) do
    db_game = get_db_game(id)

    if db_game do
      db_game
    else
      case Registry.lookup(Labyrinth.GameRegistry, id) do
        [{pid, _}] when pid != self() ->
          case Labyrinth.GameServer.get_state(id) do
            %Labyrinth.Game.Engine{} = engine ->
              %{
                id: engine.id,
                name: engine.name,
                width: engine.width,
                height: engine.height,
                status: to_string(engine.status),
                winner_name: engine.winner_name,
                map_data: %{
                  "width" => engine.width,
                  "height" => engine.height,
                  "entrance" => %{
                    "x" => elem(engine.entrance, 0),
                    "y" => elem(engine.entrance, 1)
                  },
                  "exit" => %{"x" => elem(engine.exit, 0), "y" => elem(engine.exit, 1)},
                  "treasure" => %{
                    "x" => elem(engine.treasure, 0),
                    "y" => elem(engine.treasure, 1)
                  },
                  "hospital" =>
                    if(engine.hospital,
                      do: %{"x" => elem(engine.hospital, 0), "y" => elem(engine.hospital, 1)},
                      else: nil
                    ),
                  "arsenal" =>
                    if(engine.arsenal,
                      do: %{"x" => elem(engine.arsenal, 0), "y" => elem(engine.arsenal, 1)},
                      else: nil
                    ),
                  "minotaur" =>
                    if(engine.minotaur,
                      do: %{"x" => elem(engine.minotaur, 0), "y" => elem(engine.minotaur, 1)},
                      else: nil
                    ),
                  "pits" => Enum.map(engine.pits, fn {px, py} -> %{"x" => px, "y" => py} end),
                  "walls" =>
                    Enum.map(engine.walls, fn {{x1, y1}, {x2, y2}} ->
                      %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}
                    end)
                }
              }

            _ ->
              nil
          end

        _ ->
          nil
      end
    end
  end

  def create_game(attrs) do
    %Game{}
    |> Game.changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
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

  def get_post_it(id) do
    Repo.get(PostIt, id)
  end

  def can_modify_post_it?(%PostIt{player_id: owner_id}, requesting_player_id) do
    owner_id == requesting_player_id
  end

  def can_modify_post_it?(id, requesting_player_id) when is_binary(id) or is_integer(id) do
    case get_post_it(id) do
      %PostIt{} = post_it -> can_modify_post_it?(post_it, requesting_player_id)
      nil -> false
    end
  end

  def can_modify_post_it?(_, _), do: false

  def save_post_it(attrs, requesting_player_id \\ nil) do
    case attrs["id"] || attrs[:id] do
      nil ->
        final_attrs =
          if requesting_player_id do
            Map.put(attrs, "player_id", requesting_player_id)
          else
            attrs
          end

        %PostIt{}
        |> PostIt.changeset(final_attrs)
        |> Repo.insert()

      id ->
        case Repo.get(PostIt, id) do
          nil ->
            {:error, :not_found}

          post_it ->
            if requesting_player_id == nil or post_it.player_id == requesting_player_id do
              post_it
              |> PostIt.changeset(attrs)
              |> Repo.update()
            else
              {:error, :unauthorized}
            end
        end
    end
  end

  def delete_post_it(id, requesting_player_id \\ nil) do
    case Repo.get(PostIt, id) do
      nil ->
        {:error, :not_found}

      post_it ->
        if requesting_player_id == nil or post_it.player_id == requesting_player_id do
          Repo.delete(post_it)
        else
          {:error, :unauthorized}
        end
    end
  end

  def toggle_stick_post_it(id, requesting_player_id \\ nil) do
    case Repo.get(PostIt, id) do
      nil ->
        {:error, :not_found}

      post_it ->
        if requesting_player_id == nil or post_it.player_id == requesting_player_id do
          post_it
          |> PostIt.changeset(%{is_stuck: not post_it.is_stuck})
          |> Repo.update()
        else
          {:error, :unauthorized}
        end
    end
  end
end
