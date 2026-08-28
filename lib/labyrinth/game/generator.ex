defmodule Labyrinth.Game.Generator do
  @moduledoc """
  Generates procedural Labyrinth maps with customizable width, height, and game elements.
  Validates each map using Prolog reachability rules before returning.
  """

  alias Labyrinth.Prolog.Validator
  alias Labyrinth.MapUtils

  @doc """
  Generates a complete maze map with all entities, landmarks, and walls.
  Ensures path solvability from Entrance to Exit.
  Options:
    - `:width` (default 10)
    - `:height` (default 10)
    - `:pit_count` (default 3)
    - `:teleport_count` (default 1)
  """
  def generate_map(opts \\ []) do
    width = Keyword.get(opts, :width, 10) |> max(5) |> min(20)
    height = Keyword.get(opts, :height, 10) |> max(5) |> min(20)
    pit_count = Keyword.get(opts, :pit_count, 3)
    teleport_count = Keyword.get(opts, :teleport_count, 5)
    wall_density = Keyword.get(opts, :wall_density, 70)

    do_generate(width, height, pit_count, teleport_count, wall_density, 1)
  end

  defp do_generate(width, height, pit_count, teleport_count, wall_density, attempt)
       when attempt <= 30 do
    entrance = {0, 0}

    # Gather all perimeter edge cells and pick random exit cell (distinct from entrance)
    perimeter_cells =
      for x <- 0..(width - 1),
          y <- 0..(height - 1),
          x == 0 or x == width - 1 or y == 0 or y == height - 1,
          do: {x, y}

    exit_cell =
      perimeter_cells
      |> Enum.reject(fn c -> c == entrance end)
      |> Enum.shuffle()
      |> List.first()

    # Generate initial maze walls using wall_density (0..100)
    walls = generate_maze_walls(width, height, wall_density)

    # Pick candidate positions for key items (ensure distinct cells)
    all_cells = for x <- 0..(width - 1), y <- 0..(height - 1), do: {x, y}
    reserved = [entrance, exit_cell]
    available_cells = Enum.reject(all_cells, fn c -> c in reserved end) |> Enum.shuffle()

    [treasure | rest1] = available_cells
    [hospital | rest2] = rest1
    [arsenal | rest3] = rest2
    [minotaur | rest4] = rest3

    {pits, rest5} = Enum.split(rest4, pit_count)

    # Teleport pairs
    teleporters =
      if teleport_count > 0 and length(rest5) >= 2 do
        rest5
        |> Enum.take(teleport_count * 2)
        |> Enum.chunk_every(2)
        |> Enum.map(fn [p1, p2] -> {p1, p2} end)
      else
        []
      end

    map_data = %{
      width: width,
      height: height,
      entrance: entrance,
      exit: exit_cell,
      treasure: treasure,
      hospital: hospital,
      arsenal: arsenal,
      minotaur: minotaur,
      pits: pits,
      teleporters: teleporters,
      walls: normalize_walls_to_json(walls)
    }

    if entities_disjoint?(map_data) do
      case Validator.validate_map(map_data) do
        {:ok, validation_info} ->
          {:ok, Map.put(map_data, :validation_info, validation_info)}

        {:error, _reason} ->
          do_generate(width, height, pit_count, teleport_count, wall_density, attempt + 1)
      end
    else
      do_generate(width, height, pit_count, teleport_count, wall_density, attempt + 1)
    end
  end

  defp do_generate(width, height, _pit_count, _teleport_count, _wall_density, _attempt) do
    # Fallback with guaranteed disjoint entity positions
    all_cells = for x <- 0..(width - 1), y <- 0..(height - 1), do: {x, y}
    [entrance, exit_cell, treasure, hospital, arsenal, minotaur | _] = Enum.shuffle(all_cells)

    map_data = %{
      width: width,
      height: height,
      entrance: entrance,
      exit: exit_cell,
      treasure: treasure,
      hospital: hospital,
      arsenal: arsenal,
      minotaur: minotaur,
      pits: [],
      teleporters: [],
      walls: []
    }

    {:ok, Map.put(map_data, :validation_info, %{method: :fallback})}
  end

  @doc """
  Verifies that no two entities (entrance, exit, treasure, hospital, arsenal, minotaur, pits, teleporters)
  share the same cell coordinate on the map.
  """
  def entities_disjoint?(map_data) do
    tp_cells =
      (Map.get(map_data, :teleporters) || [])
      |> Enum.flat_map(fn
        {p1, p2} -> [parse_point(p1), parse_point(p2)]
        [p1, p2] -> [parse_point(p1), parse_point(p2)]
        _ -> []
      end)

    pits = Enum.map(Map.get(map_data, :pits) || [], &parse_point/1)

    single_entities =
      [
        parse_point(map_data.entrance),
        parse_point(map_data.exit),
        parse_point(map_data.treasure),
        parse_point(map_data.hospital),
        parse_point(map_data.arsenal),
        parse_point(map_data.minotaur)
      ]
      |> Enum.reject(&is_nil/1)

    all_coords = single_entities ++ pits ++ tp_cells

    length(all_coords) == length(Enum.uniq(all_coords))
  end

  defp parse_point({x, y}), do: {x, y}
  defp parse_point(%{"x" => x, "y" => y}), do: {x, y}
  defp parse_point([x, y]), do: {x, y}
  defp parse_point(_), do: nil

  defp generate_maze_walls(width, height, wall_density) do
    # Create grid of cells, connect adjacent with full internal walls
    edges =
      for x <- 0..(width - 1), y <- 0..(height - 1), into: [] do
        e1 = if x + 1 < width, do: [MapUtils.normalize_wall({x, y}, {x + 1, y})], else: []
        e2 = if y + 1 < height, do: [MapUtils.normalize_wall({x, y}, {x, y + 1})], else: []
        e1 ++ e2
      end
      |> List.flatten()

    density = max(0, min(100, wall_density))

    cond do
      density == 0 ->
        []

      density == 100 ->
        edges

      true ->
        # Kruskal's MST to form initial spanning maze
        sets = for x <- 0..(width - 1), y <- 0..(height - 1), into: %{}, do: {{x, y}, {x, y}}
        shuffled_edges = Enum.shuffle(edges)

        {spanning_walls, _sets} =
          Enum.reduce(shuffled_edges, {[], sets}, fn {p1, p2} = edge, {wall_acc, set_acc} ->
            root1 = find_root(set_acc, p1)
            root2 = find_root(set_acc, p2)

            if root1 != root2 do
              # Carve path (don't add to walls)
              new_set_acc = Map.put(set_acc, root1, root2)
              {wall_acc, new_set_acc}
            else
              # Keep as wall
              {[edge | wall_acc], set_acc}
            end
          end)

        target_count = round(length(spanning_walls) * (density / 100.0))
        spanning_walls |> Enum.shuffle() |> Enum.take(target_count)
    end
  end

  defp find_root(sets, elem) do
    parent = Map.get(sets, elem, elem)

    if parent == elem do
      elem
    else
      find_root(sets, parent)
    end
  end

  defp normalize_walls_to_json(walls) do
    Enum.map(walls, fn {{x1, y1}, {x2, y2}} ->
      %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}
    end)
  end
end
