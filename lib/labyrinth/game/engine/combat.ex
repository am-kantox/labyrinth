defmodule Labyrinth.Game.Engine.Combat do
  @moduledoc """
  Combat resolution for Labyrinth: bullet raycasting and shot damage application.

  Extracted from `Labyrinth.Game.Engine` to keep the core engine module focused
  on state orchestration. This module handles the two pure combat operations:

  * `trace_shot/5` - raycasts a bullet up to `max_range` cells, returning whether
    it hit a wall, the Minotaur, a player, or nothing.
  * `apply_shot_damage/2` - reduces a player's HP by 1, transitions their status,
    and drops the treasure if they were carrying it.

  Both functions operate on the immutable game engine struct and return updated
  versions, keeping the engine free of side effects.
  """

  alias Labyrinth.MapUtils

  @doc """
  Raycasts a bullet from a position in a cardinal direction up to `max_range`
  cells. Returns a `{result, message, target_id}` tuple where:

  * `result` - `"shot_ricochet"`, `"shot_hit_minotaur"`, `"shot_hit"`, or `"shot_miss"`
  * `message` - a human-readable combat log string
  * `target_id` - the shot player's id, `:minotaur`, or `nil`

  A bullet stops at the first wall it encounters (self-wounding the shooter via
  ricochet), and hits the first player or the Minotaur in its path.
  """
  @spec trace_shot(
          Labyrinth.Game.Engine.t(),
          MapUtils.point(),
          atom(),
          pos_integer(),
          binary()
        ) :: {String.t(), String.t(), binary() | :minotaur | nil}
  def trace_shot(game, {sx, sy}, dir, max_range, shooter_id) do
    {dx, dy} = MapUtils.dir_delta(dir)

    Enum.reduce_while(
      1..max_range,
      {"shot_miss", "Gunshot fired #{dir} into empty corridor.", nil},
      fn dist, _acc ->
        curr = {sx + dx * (dist - 1), sy + dy * (dist - 1)}
        nxt = {sx + dx * dist, sy + dy * dist}

        if MapUtils.out_of_bounds?(nxt, game.width, game.height) or
             has_wall?(game.walls, curr, nxt) do
          shooter = Enum.find(game.players, fn p -> p.id == shooter_id end)
          shooter_name = if shooter, do: shooter.name, else: "the shooter"

          {:halt,
           {"shot_ricochet",
            "💥 Gunshot fired #{dir} hit a wall and RICOCHETED, self-wounding #{shooter_name}! (-1 HP)",
            shooter_id}}
        else
          minotaur_hit? = game.minotaur != nil and game.minotaur == nxt

          target_player =
            Enum.find(game.players, fn p ->
              {p.x, p.y} == nxt and p.status in [:active, :wounded, :stunned]
            end)

          cond do
            minotaur_hit? ->
              {:halt,
               {"shot_hit_minotaur", "🎯 BOOM! Gunshot HIT and KILLED the Minotaur 👹!", :minotaur}}

            target_player != nil ->
              {:halt, {"shot_hit", "🎯 Gunshot hit #{target_player.name}!", target_player.id}}

            true ->
              {:cont, {"shot_miss", "Gunshot fired #{dir} into empty corridor.", nil}}
          end
        end
      end
    )
  end

  @doc """
  Applies 1 point of damage to a player. Updates their health and status:

  * `0 HP` -> `:eliminated`
  * `1-2 HP` -> `:wounded`
  * `3+ HP` -> stays `:active`

  If the player was carrying the treasure, it is dropped at their current cell.
  Returns the updated game engine.
  """
  @spec apply_shot_damage(Labyrinth.Game.Engine.t(), binary()) ::
          Labyrinth.Game.Engine.t()
  def apply_shot_damage(game, player_id) do
    player = Enum.find(game.players, fn p -> p.id == player_id end)

    if player != nil do
      new_hp = max(0, player.health - 1)

      updated_player =
        cond do
          new_hp <= 0 ->
            %{player | health: 0, status: :eliminated, has_treasure: false}

          new_hp in [1, 2] ->
            %{player | health: new_hp, status: :wounded, has_treasure: false}

          true ->
            %{player | health: new_hp}
        end

      game_updated = update_player_in_game(game, updated_player)

      # Drop treasure if player was carrying it when shot
      if player.has_treasure do
        drop_pos = {player.x, player.y}

        msg =
          "💎 #{player.name} got shot and DROPPED THE TREASURE at (#{elem(drop_pos, 0)}, #{elem(drop_pos, 1)})!"

        %{game_updated | treasure: drop_pos, log_entries: [msg | game_updated.log_entries]}
      else
        game_updated
      end
    else
      game
    end
  end

  defp update_player_in_game(game, updated_player) do
    updated_players =
      Enum.map(game.players, fn p ->
        if p.id == updated_player.id, do: updated_player, else: p
      end)

    %{game | players: updated_players}
  end

  defp has_wall?(walls, p1, p2) do
    pair = MapUtils.normalize_wall(p1, p2)
    MapSet.member?(walls, pair)
  end
end
