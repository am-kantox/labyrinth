defmodule Labyrinth.Game.BotAI do
  @moduledoc """
  AI decision engine for Bot players participating in Labyrinth games.
  Uses fog-of-war memory, BFS target navigation, and line-of-sight combat.
  """

  alias Labyrinth.MapUtils

  @dirs [:north, :south, :east, :west]

  @doc """
  Determines the best move or shoot action for an AI bot.
  """
  def choose_action(game, bot) do
    pos = {bot.x, bot.y}

    shoot_dir = find_opponent_in_line_of_sight(game, bot)

    hospital_known? = MapSet.member?(bot.visited_cells, game.hospital)
    arsenal_known? = MapSet.member?(bot.visited_cells, game.arsenal)

    cond do
      # 1. Carrying treasure -> Navigate towards Exit cell
      bot.has_treasure ->
        case find_bfs_direction(pos, game.exit, game.width, game.height, bot.known_walls) do
          nil -> {:move, random_valid_dir(pos, game.width, game.height, bot.known_walls)}
          dir -> {:move, dir}
        end

      # 2. Combat opportunity: Shoot if opponent is visible in straight line
      bot.bullets > 0 and shoot_dir != nil ->
        if :rand.uniform(10) > 2 do
          {:shoot, shoot_dir}
        else
          {:move, explore_direction(game, bot, pos)}
        end

      # 3. Wounded & knows hospital -> Navigate to Hospital to heal
      bot.health < 3 and hospital_known? and pos != game.hospital ->
        case find_bfs_direction(pos, game.hospital, game.width, game.height, bot.known_walls) do
          nil -> {:move, explore_direction(game, bot, pos)}
          dir -> {:move, dir}
        end

      # 4. Out of bullets & knows arsenal -> Navigate to Arsenal for ammo reload
      bot.bullets == 0 and arsenal_known? and pos != game.arsenal ->
        case find_bfs_direction(pos, game.arsenal, game.width, game.height, bot.known_walls) do
          nil -> {:move, explore_direction(game, bot, pos)}
          dir -> {:move, dir}
        end

      # 5. Standard Exploration
      true ->
        {:move, explore_direction(game, bot, pos)}
    end
  end

  defp explore_direction(game, bot, pos) do
    valid_dirs =
      @dirs
      |> Enum.map(fn d -> {d, neighbor_pos(pos, d)} end)
      |> Enum.reject(fn {_d, npos} ->
        not MapUtils.in_bounds?(npos, game.width, game.height) or
          MapSet.member?(bot.known_walls, MapUtils.normalize_wall(pos, npos))
      end)

    if valid_dirs == [] do
      :north
    else
      # Prefer unvisited cells
      unvisited =
        Enum.filter(valid_dirs, fn {_d, npos} -> not MapSet.member?(bot.visited_cells, npos) end)

      case unvisited do
        [first | _] ->
          elem(first, 0)

        [] ->
          # All adjacent visited -> pick random
          {dir, _} = Enum.random(valid_dirs)
          dir
      end
    end
  end

  defp random_valid_dir(pos, w, h, known_walls) do
    @dirs
    |> Enum.shuffle()
    |> Enum.find(:north, fn d ->
      npos = neighbor_pos(pos, d)

      MapUtils.in_bounds?(npos, w, h) and
        not MapSet.member?(known_walls, MapUtils.normalize_wall(pos, npos))
    end)
  end

  defp find_opponent_in_line_of_sight(game, bot) do
    pos = {bot.x, bot.y}

    other_players =
      Enum.filter(game.players, fn p ->
        p.id != bot.id and p.status in [:active, :wounded, :stunned]
      end)

    Enum.find(@dirs, fn d ->
      {dx, dy} = dir_delta(d)
      target1 = {elem(pos, 0) + dx, elem(pos, 1) + dy}
      target2 = {elem(pos, 0) + dx * 2, elem(pos, 1) + dy * 2}
      target3 = {elem(pos, 0) + dx * 3, elem(pos, 1) + dy * 3}

      targets = [target1, target2, target3]
      minotaur_hit? = game.minotaur != nil and game.minotaur in targets

      minotaur_hit? or Enum.any?(other_players, fn p -> {p.x, p.y} in targets end)
    end)
  end

  defp find_bfs_direction(start, target, w, h, known_walls) do
    queue = :queue.in({start, nil}, :queue.new())
    visited = MapSet.new([start])
    bfs(queue, visited, target, w, h, known_walls)
  end

  defp bfs(queue, visited, target, w, h, known_walls) do
    case :queue.out(queue) do
      {:empty, _} ->
        nil

      {{:value, {^target, first_dir}}, _rest} ->
        first_dir

      {{:value, {curr, first_dir}}, rest_queue} ->
        neighbors =
          @dirs
          |> Enum.map(fn d ->
            {d, neighbor_pos(curr, d), if(first_dir == nil, do: d, else: first_dir)}
          end)
          |> Enum.reject(fn {_d, npos, _fdir} ->
            not MapUtils.in_bounds?(npos, w, h) or
              MapSet.member?(known_walls, MapUtils.normalize_wall(curr, npos)) or
              MapSet.member?(visited, npos)
          end)

        {new_queue, new_visited} =
          Enum.reduce(neighbors, {rest_queue, visited}, fn {_d, npos, fdir}, {q_acc, v_acc} ->
            {:queue.in({npos, fdir}, q_acc), MapSet.put(v_acc, npos)}
          end)

        bfs(new_queue, new_visited, target, w, h, known_walls)
    end
  end

  defp neighbor_pos({x, y}, :north), do: {x, y - 1}
  defp neighbor_pos({x, y}, :south), do: {x, y + 1}
  defp neighbor_pos({x, y}, :east), do: {x + 1, y}
  defp neighbor_pos({x, y}, :west), do: {x - 1, y}

  defp dir_delta(:north), do: {0, -1}
  defp dir_delta(:south), do: {0, 1}
  defp dir_delta(:east), do: {1, 0}
  defp dir_delta(:west), do: {-1, 0}
end
