defmodule Labyrinth.Game.Engine.Landing do
  @moduledoc """
  Resolves what happens when a player lands on a cell.

  Extracted from `Labyrinth.Game.Engine` to keep the core engine focused on
  state orchestration. This module handles the branching rules for cell landing:
  pits, teleporters, the hospital, the arsenal, the exit, the treasure, or a
  plain move.

  Each resolution returns a `{final_pos, result, message, updated_player}` tuple
  used by the engine's move action.
  """

  alias Labyrinth.MapUtils

  @doc """
  Resolves a player landing on `target_pos`, applying any special cell effects.

  Returns `{final_pos, result, message, updated_player}`.
  """
  @spec resolve(
          Labyrinth.Game.Engine.t(),
          map(),
          MapUtils.point(),
          MapUtils.point()
        ) :: {MapUtils.point(), String.t(), String.t(), map()}
  def resolve(game, player, target_pos, target_rel_pos) do
    visited = MapSet.put(player.visited_cells, target_pos)

    {rx, ry} = target_rel_pos
    rel_visited = MapSet.put(Map.get(player, :visited_rel_cells, MapSet.new()), {rx, ry})
    rel_feats = Map.get(player, :discovered_rel_features, %{})

    treasure_grabbed? =
      MapUtils.parse_point(target_pos) == MapUtils.parse_point(game.treasure) and
        not player.has_treasure

    base_player = %{
      player
      | x: elem(target_pos, 0),
        y: elem(target_pos, 1),
        visited_cells: visited,
        rel_x: rx,
        rel_y: ry,
        visited_rel_cells: rel_visited,
        has_treasure: player.has_treasure or treasure_grabbed?
    }

    t_prefix = if treasure_grabbed?, do: "💎 #{player.name} GRABBED THE TREASURE! ", else: ""

    ctx = %{
      base_player: base_player,
      rel: {rx, ry},
      rel_feats: rel_feats,
      visited: visited,
      t_prefix: t_prefix
    }

    cond do
      has_pit?(game.pits, target_pos) ->
        resolve_pit(ctx, target_pos)

      has_teleport?(game.teleporters, target_pos) ->
        resolve_teleport(game, ctx, target_pos)

      target_pos == game.hospital ->
        resolve_hospital(ctx, target_pos)

      target_pos == game.arsenal ->
        resolve_arsenal(ctx, target_pos)

      target_pos == game.exit and base_player.has_treasure ->
        resolve_exit(ctx, target_pos)

      treasure_grabbed? ->
        resolve_treasure(ctx, target_pos)

      true ->
        {target_pos, "moved", "#{player.name} moved 1 cell.", base_player}
    end
  end

  defp resolve_pit(ctx, target_pos) do
    base_player = ctx.base_player
    {rx, ry} = ctx.rel
    rel_feats = Map.put(ctx.rel_feats, {rx, ry}, "pit")
    player_items = Map.get(base_player, :items, MapSet.new())

    if MapSet.member?(player_items, :rope) do
      updated_items = MapSet.delete(player_items, :rope)

      updated_player = %{
        base_player
        | items: updated_items,
          discovered_rel_features: rel_feats
      }

      msg =
        "#{ctx.t_prefix}🪢 #{base_player.name} fell into a Pit but used a Rope to climb out safely!"

      {target_pos, "pit_escaped", msg, updated_player}
    else
      updated_player = %{
        base_player
        | status: :stunned,
          discovered_rel_features: rel_feats
      }

      msg = "#{ctx.t_prefix}#{base_player.name} fell into a Pit trap! (Loses next turn)"
      {target_pos, "pit", msg, updated_player}
    end
  end

  defp resolve_teleport(game, ctx, target_pos) do
    base_player = ctx.base_player
    {rx, ry} = ctx.rel
    destination = get_teleport_dest(game.teleporters, target_pos)
    teleport_visited = MapSet.put(ctx.visited, destination)
    rel_feats = Map.put(ctx.rel_feats, {rx, ry}, "teleport")

    dest_grabbed? =
      MapUtils.parse_point(destination) == MapUtils.parse_point(game.treasure) and
        not base_player.has_treasure

    updated_player = %{
      base_player
      | x: elem(destination, 0),
        y: elem(destination, 1),
        visited_cells: teleport_visited,
        discovered_rel_features: rel_feats,
        has_treasure: base_player.has_treasure or dest_grabbed?
    }

    warp_prefix = if dest_grabbed?, do: "💎 GRABBED TREASURE AT WARP DESTINATION! ", else: ""

    msg =
      "#{ctx.t_prefix}#{warp_prefix}#{base_player.name} stepped on a Teleporter and was warped to #{inspect(destination)}!"

    {destination, "teleport", msg, updated_player}
  end

  defp resolve_hospital(ctx, target_pos) do
    base_player = ctx.base_player
    {rx, ry} = ctx.rel
    rel_feats = Map.put(ctx.rel_feats, {rx, ry}, "hospital")

    {updated_player, msg} =
      if base_player.status == :wounded or base_player.health < 3 do
        p_healed = %{
          base_player
          | health: 3,
            status: :active,
            discovered_rel_features: rel_feats
        }

        {p_healed,
         "🏥 #{base_player.name} visited the Hospital! Fully healed back to 3 HP (Healthy)!"}
      else
        p_with_feat = %{base_player | discovered_rel_features: rel_feats}
        {p_with_feat, "🏥 #{base_player.name} visited the Hospital (already at full 3 HP)."}
      end

    {target_pos, "hospital", ctx.t_prefix <> msg, updated_player}
  end

  defp resolve_arsenal(ctx, target_pos) do
    base_player = ctx.base_player
    {rx, ry} = ctx.rel
    rel_feats = Map.put(ctx.rel_feats, {rx, ry}, "arsenal")
    curr_items = Map.get(base_player, :items, MapSet.new())
    has_rope? = MapSet.member?(curr_items, :rope)
    new_items = MapSet.put(curr_items, :rope)

    {updated_player, msg} =
      if base_player.bullets < 3 or Map.get(base_player, :grenades, 3) < 3 or not has_rope? do
        p_reloaded =
          base_player
          |> Map.put(:items, new_items)
          |> Map.merge(%{
            bullets: 3,
            grenades: 3,
            discovered_rel_features: rel_feats
          })

        rope_msg = if not has_rope?, do: " and picked up a Rope 🪢!", else: "!"

        {p_reloaded,
         "⚔️ #{base_player.name} visited the Arsenal! Ammunition fully reloaded (3/3 💣🔫)#{rope_msg}"}
      else
        p_with_feat = %{base_player | discovered_rel_features: rel_feats}

        {p_with_feat,
         "⚔️ #{base_player.name} visited the Arsenal (already fully loaded with ammo & Rope 🪢)."}
      end

    {target_pos, "arsenal", ctx.t_prefix <> msg, updated_player}
  end

  defp resolve_exit(ctx, target_pos) do
    base_player = ctx.base_player
    {rx, ry} = ctx.rel
    rel_feats = Map.put(ctx.rel_feats, {rx, ry}, "exit")

    updated_player = %{
      base_player
      | status: :escaped,
        discovered_rel_features: rel_feats
    }

    {target_pos, "escaped", "🏆 #{base_player.name} ESCAPED THE LABYRINTH WITH THE TREASURE!",
     updated_player}
  end

  defp resolve_treasure(ctx, target_pos) do
    base_player = ctx.base_player
    {rx, ry} = ctx.rel
    rel_feats = Map.put(ctx.rel_feats, {rx, ry}, "treasure")
    updated_player = %{base_player | discovered_rel_features: rel_feats}

    {target_pos, "treasure", "💎 #{base_player.name} FOUND THE TREASURE! Now escape to the Exit!",
     updated_player}
  end

  defp has_pit?(pits, pos) do
    Enum.any?(pits || [], fn p -> MapUtils.parse_point(p) == pos end)
  end

  defp has_teleport?(teleporters, pos) do
    Enum.any?(teleporters || [], fn
      {p1, p2} ->
        MapUtils.parse_point(p1) == pos or MapUtils.parse_point(p2) == pos

      [p1, p2] ->
        MapUtils.parse_point(p1) == pos or MapUtils.parse_point(p2) == pos

      %{"p1" => p1, "p2" => p2} ->
        MapUtils.parse_point(p1) == pos or MapUtils.parse_point(p2) == pos

      _ ->
        false
    end)
  end

  defp get_teleport_dest(teleporters, pos) do
    Enum.find_value(teleporters || [], pos, fn
      {p1, p2} ->
        tp1 = MapUtils.parse_point(p1)
        tp2 = MapUtils.parse_point(p2)

        cond do
          tp1 == pos -> tp2
          tp2 == pos -> tp1
          true -> nil
        end

      [p1, p2] ->
        tp1 = MapUtils.parse_point(p1)
        tp2 = MapUtils.parse_point(p2)

        cond do
          tp1 == pos -> tp2
          tp2 == pos -> tp1
          true -> nil
        end

      %{"p1" => p1, "p2" => p2} ->
        tp1 = MapUtils.parse_point(p1)
        tp2 = MapUtils.parse_point(p2)

        cond do
          tp1 == pos -> tp2
          tp2 == pos -> tp1
          true -> nil
        end

      _ ->
        nil
    end)
  end
end
