defmodule Labyrinth.Game.Params do
  @moduledoc """
  Validated parsing and clamping of game creation / map generation parameters.

  This module centralizes all user-supplied parameter handling (width, height,
  pit count, teleport count, wall density, bot count, difficulty) so that
  untrusted input from LiveView forms is sanitized before it reaches the game
  engine or map generator.

  The functions never raise on malformed input: they fall back to documented
  defaults and clamp values into safe ranges. This prevents an attacker from
  submitting unbounded integer values (e.g. `pit_count=1000000000`) that could
  cause excessive allocation or slow map generation in a LiveView process.
  """

  @type difficulty :: :easy | :normal | :hard

  @defaults %{
    width: 10,
    height: 10,
    bot_count: 1,
    pit_count: 3,
    teleport_count: 1,
    wall_density: 70,
    difficulty: :normal
  }

  @allowed_difficulties [:easy, :normal, :hard]

  @doc """
  Returns the default parameter map.
  """
  @spec defaults() :: map()
  def defaults, do: @defaults

  @doc """
  Parses a raw parameter map (with string keys, as received from a form) into a
  validated keyword list suitable for `Labyrinth.Game.Generator.generate_map/1`
  or `Labyrinth.GameServer.start_link/1`.

  Each numeric value is safely parsed, defaulted, and clamped. The `difficulty`
  value is converted to an atom using a strict whitelist, never `String.to_atom/1`,
  to avoid atom-table exhaustion from untrusted input.

  ## Examples

      iex> Labyrinth.Game.Params.parse(%{})
      [width: 10, height: 10, bot_count: 1, pit_count: 3, teleport_count: 1, wall_density: 70, difficulty: :normal]

      iex> Labyrinth.Game.Params.parse(%{"width" => "16", "difficulty" => "hard"})
      [width: 16, height: 10, bot_count: 1, pit_count: 3, teleport_count: 1, wall_density: 70, difficulty: :hard]
  """
  @spec parse(map()) :: Keyword.t()
  def parse(raw) do
    [
      width: integer(raw, :width, 5, 20),
      height: integer(raw, :height, 5, 20),
      bot_count: integer(raw, :bot_count, 0, 8),
      pit_count: integer(raw, :pit_count, 0, 30),
      teleport_count: integer(raw, :teleport_count, 0, 20),
      wall_density: integer(raw, :wall_density, 0, 100),
      difficulty: difficulty(raw)
    ]
  end

  @doc """
  Safely converts a difficulty value to an allowed atom.

  Returns `:normal` for any value not in the whitelist `[:easy, :normal, :hard]`.
  Accepts both string and atom inputs.

  ## Examples

      iex> Labyrinth.Game.Params.parse_difficulty("easy")
      :easy

      iex> Labyrinth.Game.Params.parse_difficulty("EVIL")
      :normal
  """
  @spec parse_difficulty(term()) :: difficulty()
  def parse_difficulty(value) do
    case value do
      difficulty when difficulty in @allowed_difficulties ->
        difficulty

      difficulty when is_binary(difficulty) ->
        downcased = String.downcase(difficulty)

        Enum.find(@allowed_difficulties, @defaults.difficulty, fn allowed ->
          Atom.to_string(allowed) == downcased
        end)

      _ ->
        @defaults.difficulty
    end
  end

  defp difficulty(raw) do
    parse_difficulty(Map.get(raw, "difficulty") || Map.get(raw, :difficulty))
  end

  @doc false
  defp integer(raw, key, min, max) do
    raw
    |> Map.get(to_string(key), Map.get(raw, key, @defaults[key]))
    |> to_integer()
    |> clamp(min, max)
  end

  defp to_integer(value) when is_integer(value), do: value

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end

  defp to_integer(_), do: nil

  defp clamp(nil, min, _max), do: min
  defp clamp(value, min, _max) when value < min, do: min
  defp clamp(value, _min, max) when value > max, do: max
  defp clamp(value, _min, _max), do: value
end
