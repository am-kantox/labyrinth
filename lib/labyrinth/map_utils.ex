defmodule Labyrinth.MapUtils do
  @moduledoc """
  Shared map, wall, and coordinate utilities for Labyrinth.
  Provides standardized functions for wall normalization, distance calculations,
  grid boundaries, and neighbor lookups across engine, validator, generator, and UI components.
  """

  @type point :: {integer(), integer()}
  @type wall_pair :: {point(), point()}

  @doc """
  Normalizes two points defining a wall segment so that p1 <= p2.
  Supports tuple pairs, maps with x1/y1/x2/y2 keys, or 4-element coordinate lists.
  """
  @spec normalize_wall(any(), any()) :: wall_pair()
  def normalize_wall({x1, y1}, {x2, y2}) do
    if {x1, y1} <= {x2, y2} do
      {{x1, y1}, {x2, y2}}
    else
      {{x2, y2}, {x1, y1}}
    end
  end

  def normalize_wall(%{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}, _p2) do
    normalize_wall({x1, y1}, {x2, y2})
  end

  def normalize_wall([x1, y1, x2, y2], _p2) do
    normalize_wall({x1, y1}, {x2, y2})
  end

  @doc """
  Normalizes a single wall input which might be a map, list, or pair of points.
  """
  @spec normalize_wall_pair(any()) :: wall_pair()
  def normalize_wall_pair({{x1, y1}, {x2, y2}}), do: normalize_wall({x1, y1}, {x2, y2})

  def normalize_wall_pair(%{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2}),
    do: normalize_wall({x1, y1}, {x2, y2})

  def normalize_wall_pair([x1, y1, x2, y2]), do: normalize_wall({x1, y1}, {x2, y2})
  def normalize_wall_pair(other), do: other

  @doc """
  Normalizes wall pair given two parameters. Alias for `normalize_wall/2`.
  """
  @spec normalize_wall_pair(any(), any()) :: wall_pair()
  def normalize_wall_pair(p1, p2), do: normalize_wall(p1, p2)

  @doc """
  Converts a list or map of raw walls into a MapSet of normalized wall pairs.
  """
  @spec normalize_walls(Enumerable.t()) :: MapSet.t(wall_pair())
  def normalize_walls(walls) when is_map(walls) or is_list(walls) do
    walls
    |> Enum.map(fn
      {{x1, y1}, {x2, y2}} -> normalize_wall({x1, y1}, {x2, y2})
      [x1, y1, x2, y2] -> normalize_wall({x1, y1}, {x2, y2})
      %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2} -> normalize_wall({x1, y1}, {x2, y2})
      wall -> normalize_wall_pair(wall)
    end)
    |> MapSet.new()
  end

  @doc """
  Returns cardinal neighbor positions for a given point.
  """
  @spec neighbors(point()) :: [point()]
  def neighbors({x, y}) do
    [{x, y - 1}, {x, y + 1}, {x - 1, y}, {x + 1, y}]
  end

  @doc """
  Returns cardinal neighbors paired with their direction atom.
  """
  @spec directional_neighbors(point()) :: [{atom(), point()}]
  def directional_neighbors({x, y}) do
    [
      north: {x, y - 1},
      south: {x, y + 1},
      west: {x - 1, y},
      east: {x + 1, y}
    ]
  end

  @doc """
  Checks if a coordinate point is within grid boundaries.
  """
  @spec in_bounds?(point(), integer(), integer()) :: boolean()
  def in_bounds?({x, y}, width, height) do
    x >= 0 and x < width and y >= 0 and y < height
  end

  @doc """
  Calculates Manhattan distance between two points.
  """
  @spec manhattan_distance(point(), point()) :: integer()
  def manhattan_distance({x1, y1}, {x2, y2}) do
    abs(x1 - x2) + abs(y1 - y2)
  end

  @doc """
  Returns the neighbor position in a cardinal direction.
  """
  @spec neighbor_in_dir(point(), atom()) :: point()
  def neighbor_in_dir({x, y}, :north), do: {x, y - 1}
  def neighbor_in_dir({x, y}, :south), do: {x, y + 1}
  def neighbor_in_dir({x, y}, :east), do: {x + 1, y}
  def neighbor_in_dir({x, y}, :west), do: {x - 1, y}

  @doc """
  Returns the (dx, dy) delta for a cardinal direction atom.
  """
  @spec dir_delta(atom()) :: {integer(), integer()}
  def dir_delta(:north), do: {0, -1}
  def dir_delta(:south), do: {0, 1}
  def dir_delta(:east), do: {1, 0}
  def dir_delta(:west), do: {-1, 0}

  @doc """
  Checks if a coordinate point is outside the grid boundaries.
  """
  @spec out_of_bounds?(point(), integer(), integer()) :: boolean()
  def out_of_bounds?({x, y}, width, height) do
    x < 0 or x >= width or y < 0 or y >= height
  end

  @doc """
  Normalizes a coordinate into a `{x, y}` tuple.
  Accepts tuple, map with `x`/`y` keys, or 2-element list. Returns `nil` for
  unrecognized input.
  """
  @spec parse_point(any()) :: point() | nil
  def parse_point({x, y}), do: {x, y}
  def parse_point(%{"x" => x, "y" => y}), do: {x, y}
  def parse_point([x, y]), do: {x, y}
  def parse_point(_), do: nil

  @doc """
  Returns the cardinal direction string from a source point to a target point.
  Used for spatial auditory feedback ("Footsteps heard from South").
  """
  @spec relative_direction(point(), point()) :: String.t()
  def relative_direction({from_x, from_y}, {to_x, to_y}) do
    dx = to_x - from_x
    dy = to_y - from_y

    cond do
      abs(dy) >= abs(dx) and dy < 0 -> "North"
      abs(dy) >= abs(dx) and dy > 0 -> "South"
      abs(dx) > abs(dy) and dx > 0 -> "East"
      true -> "West"
    end
  end
end
