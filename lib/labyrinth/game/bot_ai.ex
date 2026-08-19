defmodule Labyrinth.Game.BotAI do
  @moduledoc """
  AI decision engine for Bot players participating in Labyrinth games.
  Uses fog-of-war memory, BFS target navigation, and line-of-sight combat.
  """

  @dirs [:north, :south, :east, :west]

  @doc """
  Determines the best move or shoot action for an AI bot.
  """
  def choose_action(game, bot) do
    pos = {bot.x, bot.y}

    shoot_dir = find_opponent_in_line_of_sight(game, bot)

    cond do
      # 1. Carrying treasure -> Navigate towards Exit cell
      bot.has_treasure ->
        case find_bfs_direction(pos, game.exit, game.width, game.height, bot.known_walls) do
          nil -> {:move, random_valid_dir(pos, game.width, game.height, bot.known_walls)}
          dir -> {:move, dir}
        end

      # 2. Combat opportunity: Shoot if opponent is visible in straight line
      bot.bullets > 0 and shoot_dir != nil ->
        if :rand.uniform(10) > 3 do
          {:shoot, shoot_dir}
        else
          {:move, explore_direction(game, bot, pos)}
        end

      # 3. Standard Exploration
      true ->
        {:move, explore_direction(game, bot, pos)}
    end
  end

  defp explore_direction(game, bot, pos) do
    valid_dirs =
      @dirs
      |> Enum.map(fn d -> {d, neighbor_pos(pos, d)} end)
      |> Enum.reject(fn {_d, npos} ->
        is_out_of_bounds(npos, game.width, game.height) or
          MapSet.member?(bot.known_walls, normalize_wall(pos, npos))
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

      not is_out_of_bounds(npos, w, h) and
        not MapSet.member?(known_walls, normalize_wall(pos, npos))
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
    queue = [{start, []}]
    visited = MapSet.new([start])
    bfs(queue, visited, target, w, h, known_walls)
  end

  defp bfs([], _visited, _target, _w, _h, _known_walls), do: nil

  defp bfs([{curr, path} | _tail], _visited, curr, _w, _h, _known_walls) do
    List.first(Enum.reverse(path))
  end

  defp bfs([{curr, path} | tail], visited, target, w, h, known_walls) do
    neighbors =
      @dirs
      |> Enum.map(fn d -> {d, neighbor_pos(curr, d)} end)
      |> Enum.reject(fn {_d, npos} ->
        is_out_of_bounds(npos, w, h) or
          MapSet.member?(known_walls, normalize_wall(curr, npos)) or
          MapSet.member?(visited, npos)
      end)

    {new_queue, new_visited} =
      Enum.reduce(neighbors, {tail, visited}, fn {d, npos}, {q_acc, v_acc} ->
        {q_acc ++ [{npos, [d | path]}], MapSet.put(v_acc, npos)}
      end)

    bfs(new_queue, new_visited, target, w, h, known_walls)
  end

  defp neighbor_pos({x, y}, :north), do: {x, y - 1}
  defp neighbor_pos({x, y}, :south), do: {x, y + 1}
  defp neighbor_pos({x, y}, :east), do: {x + 1, y}
  defp neighbor_pos({x, y}, :west), do: {x - 1, y}

  defp dir_delta(:north), do: {0, -1}
  defp dir_delta(:south), do: {0, 1}
  defp dir_delta(:east), do: {1, 0}
  defp dir_delta(:west), do: {-1, 0}

  defp is_out_of_bounds({x, y}, w, h), do: x < 0 or x >= w or y < 0 or y >= h

  defp normalize_wall(p1, p2) do
    if p1 <= p2, do: {p1, p2}, else: {p2, p1}
  end
end
