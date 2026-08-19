defmodule Labyrinth.Game.Engine do
  @moduledoc """
  Core state engine and rules processor for Labyrinth.
  Implements blind exploration, GM feedback, combat, sound echo propagation,
  and Minotaur turn progression.
  """

  defstruct [
    :id,
    :name,
    :width,
    :height,
    :entrance,
    :exit,
    :treasure,
    :hospital,
    :arsenal,
    :minotaur,
    :pits,
    :teleporters,
    :walls,
    :destroyed_walls,
    # list of player maps
    :players,
    # integer index in players
    :turn_index,
    :round_number,
    # :lobby, :in_progress, :finished
    :status,
    :winner_name,
    :last_action_result,
    :log_entries,
    :settings
  ]

  alias Labyrinth.Game.Generator

  @type direction :: :north | :south | :east | :west

  def new_game(name, opts \\ []) do
    {:ok, map_data} = Generator.generate_map(opts)
    minotaur_enabled? = Keyword.get(opts, :minotaur_enabled, true)

    %__MODULE__{
      id: Ecto.UUID.generate(),
      name: name,
      width: map_data.width,
      height: map_data.height,
      entrance: map_data.entrance,
      exit: map_data.exit,
      treasure: map_data.treasure,
      hospital: map_data.hospital,
      arsenal: map_data.arsenal,
      minotaur: if(minotaur_enabled?, do: map_data.minotaur, else: nil),
      pits: map_data.pits,
      teleporters: map_data.teleporters,
      walls: parse_walls(map_data.walls),
      destroyed_walls: MapSet.new(),
      players: [],
      turn_index: 0,
      round_number: 1,
      status: :lobby,
      winner_name: nil,
      last_action_result: nil,
      log_entries: ["Game created. Waiting for players to join."],
      settings: %{
        "minotaur_enabled" => minotaur_enabled?
      }
    }
  end

  def add_player(game, player_id, name, is_bot \\ false) do
    if Enum.any?(game.players, fn p -> p.id == player_id end) do
      game
    else
      player = %{
        id: player_id,
        name: name,
        is_bot: is_bot,
        x: elem(game.entrance, 0),
        y: elem(game.entrance, 1),
        health: 3,
        bullets: 3,
        grenades: 3,
        has_treasure: false,
        # :active, :stunned, :eliminated, :escaped
        status: :active,
        visited_cells: MapSet.new([game.entrance]),
        known_walls: MapSet.new(),
        rel_x: 0,
        rel_y: 0,
        visited_rel_cells: MapSet.new([{0, 0}]),
        known_rel_walls: MapSet.new(),
        discovered_rel_features: %{}
      }

      updated_players = game.players ++ [player]
      %{game | players: updated_players}
    end
  end

  def reset_bot_rel_tracking(game, bot_id) do
    bot = Enum.find(game.players, fn p -> p.id == bot_id end)

    if bot do
      reset_bot = %{
        bot
        | rel_x: 0,
          rel_y: 0,
          visited_rel_cells: MapSet.new([{0, 0}]),
          known_rel_walls: MapSet.new(),
          discovered_rel_features: %{}
      }

      update_player_in_game(game, reset_bot)
    else
      game
    end
  end

  def start_game(%__MODULE__{status: :lobby} = game) do
    if length(game.players) >= 1 do
      # Gather all valid non-trap, non-exit, non-treasure cells for randomized spawn
      valid_start_cells =
        for x <- 0..(game.width - 1),
            y <- 0..(game.height - 1),
            pos = {x, y},
            pos not in game.pits,
            pos != game.exit,
            pos != game.treasure,
            do: pos

      shuffled_starts = Enum.shuffle(valid_start_cells)

      {updated_players, _} =
        Enum.reduce(game.players, {[], shuffled_starts}, fn p, {acc_p, remaining_starts} ->
          {start_cell, rest_starts} =
            case remaining_starts do
              [s | rest] -> {s, rest}
              [] -> {game.entrance, []}
            end

          updated_p = %{
            p
            | x: elem(start_cell, 0),
              y: elem(start_cell, 1),
              visited_cells: MapSet.put(p.visited_cells, start_cell)
          }

          {acc_p ++ [updated_p], rest_starts}
        end)

      minotaur_enabled? = Map.get(game.settings || %{}, "minotaur_enabled", true)
      final_minotaur = if minotaur_enabled?, do: game.minotaur, else: nil

      %{
        game
        | status: :in_progress,
          players: updated_players,
          minotaur: final_minotaur,
          turn_index: 0,
          round_number: 1,
          log_entries: [
            "The game has started! Explorers spawned at randomized initial positions."
            | game.log_entries
          ]
      }
    else
      game
    end
  end

  def start_game(game), do: game

  def current_player(%__MODULE__{players: []}), do: nil

  def current_player(%__MODULE__{players: players, turn_index: idx}) do
    Enum.at(players, idx)
  end

  @doc """
  Processes a player's turn action.
  Action: {:move, dir}, {:shoot, dir}, or :pass
  Returns {updated_game, turn_summary}
  """
  def process_turn(%__MODULE__{status: :in_progress} = game, player_id, action) do
    player = current_player(game)

    if player == nil or player.id != player_id do
      {:error, :not_your_turn}
    else
      case player.status do
        :stunned ->
          # Player recovers from pit stun but loses this turn
          updated_player = %{player | status: :active}
          game_updated = update_player_in_game(game, updated_player)

          summary = %{
            player_id: player.id,
            player_name: player.name,
            action_type: "pass",
            direction: nil,
            result: "stunned_pass",
            message: "#{player.name} climbed out of pit and skipped turn.",
            sound_effects: [],
            pos_before: {player.x, player.y},
            pos_after: {player.x, player.y}
          }

          advance_turn(game_updated, summary)

        status when status in [:active, :wounded] ->
          {game_after_action, summary} = execute_action(game, player, action)
          advance_turn(game_after_action, summary)

        _ ->
          {:error, :player_inactive}
      end
    end
  end

  def process_turn(_game, _player_id, _action), do: {:error, :game_not_in_progress}

  defp execute_action(game, player, {:move, dir}) when dir in [:north, :south, :east, :west] do
    pos_before = {player.x, player.y}
    target_pos = neighbor_in_dir(pos_before, dir)

    wall_blocked? =
      is_out_of_bounds(target_pos, game.width, game.height) or
        has_wall?(game.walls, pos_before, target_pos)

    rx = Map.get(player, :rel_x, 0)
    ry = Map.get(player, :rel_y, 0)
    {dx, dy} = dir_delta(dir)
    target_rx = rx + dx
    target_ry = ry + dy

    if wall_blocked? do
      # Bump wall
      updated_known_walls =
        MapSet.put(player.known_walls, normalize_wall_pair(pos_before, target_pos))

      updated_rel_walls =
        MapSet.put(
          Map.get(player, :known_rel_walls, MapSet.new()),
          normalize_wall_pair({rx, ry}, {target_rx, target_ry})
        )

      updated_player = %{
        player
        | known_walls: updated_known_walls,
          known_rel_walls: updated_rel_walls
      }

      game_updated = update_player_in_game(game, updated_player)

      summary = %{
        player_id: player.id,
        player_name: player.name,
        action_type: "move",
        direction: Atom.to_string(dir),
        result: "wall",
        message: "#{player.name} tried to move #{dir} but bumped into a Wall!",
        sound_effects: [],
        pos_before: pos_before,
        pos_after: pos_before
      }

      {game_updated, summary}
    else
      # Clear move
      {final_pos, move_result, special_msg, updated_player} =
        resolve_cell_landing(game, player, target_pos, {target_rx, target_ry})

      game_updated = update_player_in_game(game, updated_player)

      # Sound echo calculation for nearby players
      sound_echoes = calculate_sound_echoes(game_updated, updated_player, :move, dir)

      summary = %{
        player_id: player.id,
        player_name: player.name,
        action_type: "move",
        direction: Atom.to_string(dir),
        result: move_result,
        message: special_msg,
        sound_effects: sound_echoes,
        pos_before: pos_before,
        pos_after: final_pos
      }

      {game_updated, summary}
    end
  end

  defp execute_action(game, player, {:shoot, dir}) when dir in [:north, :south, :east, :west] do
    pos_before = {player.x, player.y}

    if player.bullets <= 0 do
      summary = %{
        player_id: player.id,
        player_name: player.name,
        action_type: "shoot",
        direction: Atom.to_string(dir),
        result: "no_ammo",
        message: "#{player.name} tried to shoot #{dir} but is out of ammunition!",
        sound_effects: [],
        pos_before: pos_before,
        pos_after: pos_before
      }

      {game, summary}
    else
      updated_player = %{player | bullets: player.bullets - 1}
      game_updated = update_player_in_game(game, updated_player)

      # Projectile raycast up to 3 cells
      {hit_result, hit_msg, hit_player_id} = trace_shot(game_updated, pos_before, dir, 3)

      game_after_hit =
        case hit_player_id do
          :minotaur ->
            %{game_updated | minotaur: nil}

          nil ->
            game_updated

          p_id ->
            apply_shot_damage(game_updated, p_id)
        end

      sound_echoes = calculate_sound_echoes(game_after_hit, updated_player, :shoot, dir)

      summary = %{
        player_id: player.id,
        player_name: player.name,
        action_type: "shoot",
        direction: Atom.to_string(dir),
        result: hit_result,
        message: hit_msg,
        sound_effects: sound_echoes,
        pos_before: pos_before,
        pos_after: pos_before
      }

      {game_after_hit, summary}
    end
  end

  defp execute_action(game, player, {:grenade, dir}) when dir in [:north, :south, :east, :west] do
    pos_before = {player.x, player.y}

    if Map.get(player, :grenades, 3) <= 0 do
      summary = %{
        player_id: player.id,
        player_name: player.name,
        action_type: "grenade",
        direction: Atom.to_string(dir),
        result: "no_grenades",
        message: "#{player.name} tried to throw a grenade #{dir} but has NO GRENADES left!",
        sound_effects: [],
        pos_before: pos_before,
        pos_after: pos_before
      }

      {game, summary}
    else
      target_pos = neighbor_in_dir(pos_before, dir)
      wall_pair = normalize_wall_pair(pos_before, target_pos)

      # Check if wall is outer perimeter of the whole labyrinth
      outer_boundary? = is_out_of_bounds(target_pos, game.width, game.height)

      updated_player = %{player | grenades: max(0, Map.get(player, :grenades, 3) - 1)}

      if outer_boundary? do
        game_updated = update_player_in_game(game, updated_player)

        summary = %{
          player_id: player.id,
          player_name: player.name,
          action_type: "grenade",
          direction: Atom.to_string(dir),
          result: "indestructible_wall",
          message:
            "💥 Grenade hit the Outer Perimeter Wall! The outer boundary is indestructible!",
          sound_effects: ["Explosion echoed off outer fortress wall"],
          pos_before: pos_before,
          pos_after: pos_before
        }

        {game_updated, summary}
      else
        if MapSet.member?(game.walls, wall_pair) do
          # Demolish internal wall segment and track broken wall debris
          new_walls = MapSet.delete(game.walls, wall_pair)

          new_destroyed =
            MapSet.put(Map.get(game, :destroyed_walls) || MapSet.new(), wall_pair)

          game_updated =
            %{game | walls: new_walls, destroyed_walls: new_destroyed}
            |> update_player_in_game(updated_player)

          sound_echoes = calculate_sound_echoes(game_updated, updated_player, :grenade, dir)

          summary = %{
            player_id: player.id,
            player_name: player.name,
            action_type: "grenade",
            direction: Atom.to_string(dir),
            result: "wall_destroyed",
            message:
              "💥 BOOM! #{player.name} threw a grenade #{dir} and DEMOLISHED the wall segment!",
            sound_effects: ["Massive Explosion! Wall Demolished" | sound_echoes],
            pos_before: pos_before,
            pos_after: pos_before
          }

          {game_updated, summary}
        else
          # Threw grenade into open corridor
          game_updated = update_player_in_game(game, updated_player)
          sound_echoes = calculate_sound_echoes(game_updated, updated_player, :grenade, dir)

          summary = %{
            player_id: player.id,
            player_name: player.name,
            action_type: "grenade",
            direction: Atom.to_string(dir),
            result: "grenade_miss",
            message: "💥 #{player.name} threw a grenade #{dir} into an open corridor! BOOM!",
            sound_effects: ["Corridor Explosion" | sound_echoes],
            pos_before: pos_before,
            pos_after: pos_before
          }

          {game_updated, summary}
        end
      end
    end
  end

  defp execute_action(game, player, :pass) do
    pos = {player.x, player.y}

    summary = %{
      player_id: player.id,
      player_name: player.name,
      action_type: "pass",
      direction: nil,
      result: "passed",
      message: "#{player.name} passed their turn.",
      sound_effects: [],
      pos_before: pos,
      pos_after: pos
    }

    {game, summary}
  end

  defp resolve_cell_landing(game, player, target_pos, target_rel_pos) do
    visited = MapSet.put(player.visited_cells, target_pos)

    {rx, ry} = target_rel_pos
    rel_visited = MapSet.put(Map.get(player, :visited_rel_cells, MapSet.new()), {rx, ry})
    rel_feats = Map.get(player, :discovered_rel_features, %{})

    base_player = %{
      player
      | x: elem(target_pos, 0),
        y: elem(target_pos, 1),
        visited_cells: visited,
        rel_x: rx,
        rel_y: ry,
        visited_rel_cells: rel_visited
    }

    cond do
      # 1. Pit / Trap
      has_pit?(game.pits, target_pos) ->
        updated_rel_feats = Map.put(rel_feats, {rx, ry}, "pit")

        updated_player = %{
          base_player
          | status: :stunned,
            discovered_rel_features: updated_rel_feats
        }

        {target_pos, "pit", "#{player.name} fell into a Pit trap! (Loses next turn)",
         updated_player}

      # 2. Teleporter portal
      has_teleport?(game.teleporters, target_pos) ->
        destination = get_teleport_dest(game.teleporters, target_pos)
        teleport_visited = MapSet.put(visited, destination)
        updated_rel_feats = Map.put(rel_feats, {rx, ry}, "teleport")

        updated_player = %{
          base_player
          | x: elem(destination, 0),
            y: elem(destination, 1),
            visited_cells: teleport_visited,
            discovered_rel_features: updated_rel_feats
        }

        {destination, "teleport", "#{player.name} stepped on a Teleporter and was warped!",
         updated_player}

      # 3. Hospital Cell
      target_pos == game.hospital ->
        updated_rel_feats = Map.put(rel_feats, {rx, ry}, "hospital")

        {updated_player, msg} =
          if base_player.status == :wounded or base_player.health < 3 do
            p_healed = %{
              base_player
              | health: 3,
                status: :active,
                discovered_rel_features: updated_rel_feats
            }

            {p_healed,
             "🏥 #{player.name} visited the Hospital! Fully healed back to 3 HP (Healthy)!"}
          else
            p_with_feat = %{base_player | discovered_rel_features: updated_rel_feats}
            {p_with_feat, "🏥 #{player.name} visited the Hospital (already at full 3 HP)."}
          end

        {target_pos, "hospital", msg, updated_player}

      # 4. Arsenal Cell: Restock Ammunition to 3 bullets & 3 grenades
      target_pos == game.arsenal ->
        updated_rel_feats = Map.put(rel_feats, {rx, ry}, "arsenal")

        {updated_player, msg} =
          if base_player.bullets < 3 or Map.get(base_player, :grenades, 3) < 3 do
            p_reloaded = %{
              base_player
              | bullets: 3,
                grenades: 3,
                discovered_rel_features: updated_rel_feats
            }

            {p_reloaded,
             "⚔️ #{player.name} visited the Arsenal! Bullets (3/3) & Grenades (3/3) fully reloaded 💣🔫!"}
          else
            p_with_feat = %{base_player | discovered_rel_features: updated_rel_feats}

            {p_with_feat,
             "⚔️ #{player.name} visited the Arsenal (already fully loaded with 3 bullets & 3 grenades)."}
          end

        {target_pos, "arsenal", msg, updated_player}

      # 5. Treasure cell
      target_pos == game.treasure and not player.has_treasure ->
        updated_rel_feats = Map.put(rel_feats, {rx, ry}, "treasure")

        updated_player = %{
          base_player
          | has_treasure: true,
            discovered_rel_features: updated_rel_feats
        }

        {target_pos, "treasure", "💎 #{player.name} FOUND THE TREASURE! Now escape to the Exit!",
         updated_player}

      # 6. Exit cell with treasure
      target_pos == game.exit and base_player.has_treasure ->
        updated_rel_feats = Map.put(rel_feats, {rx, ry}, "exit")

        updated_player = %{
          base_player
          | status: :escaped,
            discovered_rel_features: updated_rel_feats
        }

        {target_pos, "escaped", "🏆 #{player.name} ESCAPED THE LABYRINTH WITH THE TREASURE!",
         updated_player}

      # 7. Regular clear cell
      true ->
        {target_pos, "moved", "#{player.name} moved 1 cell.", base_player}
    end
  end

  defp advance_turn(game, turn_summary) do
    is_bot = String.starts_with?(turn_summary.player_id || "", "bot")
    icon = if is_bot, do: "🤖", else: "👤"
    dir_str = if turn_summary.direction, do: String.upcase(turn_summary.direction), else: "PASS"

    res_str =
      case turn_summary.result do
        "wall" -> "WALL 🧱"
        "moved" -> "MOVED 🚶"
        "pit" -> "PIT 🕳"
        "teleport" -> "TELEPORT 🌀"
        "treasure" -> "TREASURE 💎"
        "escaped" -> "ESCAPED 🏆"
        "shot_hit_minotaur" -> "MINOTAUR KILLED 👹💥"
        "shot_hit" -> "SHOT HIT 🎯"
        "shot_wall" -> "SHOT WALL 🧱"
        "shot_miss" -> "SHOT MISS 💨"
        _ -> String.upcase(turn_summary.result || "")
      end

    formatted_msg =
      "#{icon} #{turn_summary.player_name}: #{String.upcase(turn_summary.action_type)} #{dir_str} → #{res_str}"

    sound_logs = Enum.map(turn_summary.sound_effects || [], fn echo -> "🔊 #{echo}" end)
    active_player = Enum.find(game.players, fn p -> p.id == turn_summary.player_id end)

    stink_log =
      if active_player && game.minotaur && active_player.status in [:active, :wounded] do
        {mx, my} = parse_point(game.minotaur)

        if abs(active_player.x - mx) + abs(active_player.y - my) <= 2 do
          "🦨 #{active_player.name} smelled the Minotaur's foul stink wafting from nearby! (Within 2 cells)"
        else
          nil
        end
      else
        nil
      end

    stink_logs = if stink_log, do: [stink_log], else: []
    divider = "─── Round #{game.round_number} • #{icon} #{turn_summary.player_name} ───"

    new_log_batch = [divider, formatted_msg] ++ stink_logs ++ sound_logs ++ [turn_summary.message]
    updated_logs = new_log_batch ++ game.log_entries

    game = %{game | last_action_result: turn_summary, log_entries: updated_logs}

    # Check for game winner
    escaped_player = Enum.find(game.players, fn p -> p.status == :escaped end)

    if escaped_player != nil do
      final_game = %{
        game
        | status: :finished,
          winner_name: escaped_player.name,
          log_entries: ["🏆 Game Finished! Winner: #{escaped_player.name}" | updated_logs]
      }

      {final_game, turn_summary}
    else
      # Advance turn index to next active/stunned player
      num_players = length(game.players)
      next_idx = rem(game.turn_index + 1, num_players)

      # If round completed, move Minotaur
      {game_after_round, minotaur_msg} =
        if next_idx == 0 do
          step_minotaur(game)
        else
          {game, nil}
        end

      # Check again if winner or active players remain
      active_players =
        Enum.filter(game_after_round.players, fn p ->
          p.status in [:active, :wounded, :stunned]
        end)

      final_game =
        cond do
          length(active_players) == 0 ->
            %{
              game_after_round
              | status: :finished,
                winner_name: "Minotaur (No Survivors)",
                log_entries: [
                  "👹 All players were eliminated! Minotaur wins!" | game_after_round.log_entries
                ]
            }

          true ->
            %{
              game_after_round
              | turn_index: next_idx,
                round_number:
                  if(next_idx == 0, do: game.round_number + 1, else: game.round_number)
            }
        end

      turn_summary_with_minotaur =
        if minotaur_msg do
          Map.update(turn_summary, :message, turn_summary.message, fn msg ->
            "#{msg} #{minotaur_msg}"
          end)
        else
          turn_summary
        end

      {final_game, turn_summary_with_minotaur}
    end
  end

  defp step_minotaur(%__MODULE__{minotaur: nil} = game), do: {game, nil}

  defp step_minotaur(game) do
    cond do
      game.minotaur == nil or Map.get(game.settings || %{}, "minotaur_enabled", true) == false ->
        {game, nil}

      Enum.filter(game.players, fn p -> p.status in [:active, :wounded, :stunned] end) == [] ->
        {game, nil}

      true ->
        active_players =
          Enum.filter(game.players, fn p -> p.status in [:active, :wounded, :stunned] end)

        {mx, my} = game.minotaur
        nearest_player = Enum.min_by(active_players, fn p -> abs(p.x - mx) + abs(p.y - my) end)

        dx = signum(nearest_player.x - mx)
        dy = signum(nearest_player.y - my)

        target_step =
          cond do
            dx != 0 and not has_wall?(game.walls, {mx, my}, {mx + dx, my}) -> {mx + dx, my}
            dy != 0 and not has_wall?(game.walls, {mx, my}, {mx, my + dy}) -> {mx, my + dy}
            true -> {mx, my}
          end

        game_updated = %{game | minotaur: target_step}

        victims =
          Enum.filter(game_updated.players, fn p ->
            {p.x, p.y} == target_step and p.status in [:active, :stunned]
          end)

        {game_after_kills, kill_msgs} =
          Enum.reduce(victims, {game_updated, []}, fn victim, {g_acc, msg_acc} ->
            updated_v = %{victim | status: :eliminated, has_treasure: false}
            g_updated = update_player_in_game(g_acc, updated_v)

            g_final =
              if victim.has_treasure, do: %{g_updated | treasure: target_step}, else: g_updated

            msg = "👹 Minotaur moved to #{inspect(target_step)} and ELIMINATED #{victim.name}!"
            {g_final, [msg | msg_acc]}
          end)

        msg_str =
          if kill_msgs != [],
            do: Enum.join(kill_msgs, " "),
            else: "👹 Minotaur stepped in the shadows."

        {game_after_kills, msg_str}
    end
  end

  defp calculate_sound_echoes(game, acting_player, action_type, _dir) do
    pos = {acting_player.x, acting_player.y}

    active_other_players =
      Enum.filter(game.players, fn p ->
        p.id != acting_player.id and p.status in [:active, :stunned]
      end)

    Enum.flat_map(active_other_players, fn p ->
      dist = abs(p.x - elem(pos, 0)) + abs(p.y - elem(pos, 1))

      if dist <= 3 do
        cardinal_rel = relative_direction({p.x, p.y}, pos)
        sound_type = if action_type == :shoot, do: "A gunshot echoed", else: "Footsteps heard"
        ["Player #{p.name}: #{sound_type} from #{cardinal_rel}"]
      else
        []
      end
    end)
  end

  defp trace_shot(game, {sx, sy}, dir, max_range) do
    {dx, dy} = dir_delta(dir)

    Enum.reduce_while(
      1..max_range,
      {"shot_miss", "Gunshot fired #{dir} into empty corridor.", nil},
      fn dist, _acc ->
        curr = {sx + dx * (dist - 1), sy + dy * (dist - 1)}
        nxt = {sx + dx * dist, sy + dy * dist}

        if is_out_of_bounds(nxt, game.width, game.height) or has_wall?(game.walls, curr, nxt) do
          {:halt, {"shot_wall", "Gunshot fired #{dir} hit a stone wall!", nil}}
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

  defp apply_shot_damage(game, player_id) do
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
      Enum.map(game.players, fn p -> if p.id == updated_player.id, do: updated_player, else: p end)

    %{game | players: updated_players}
  end

  defp neighbor_in_dir({x, y}, :north), do: {x, y - 1}
  defp neighbor_in_dir({x, y}, :south), do: {x, y + 1}
  defp neighbor_in_dir({x, y}, :east), do: {x + 1, y}
  defp neighbor_in_dir({x, y}, :west), do: {x - 1, y}

  defp dir_delta(:north), do: {0, -1}
  defp dir_delta(:south), do: {0, 1}
  defp dir_delta(:east), do: {1, 0}
  defp dir_delta(:west), do: {-1, 0}

  defp relative_direction({from_x, from_y}, {to_x, to_y}) do
    dx = to_x - from_x
    dy = to_y - from_y

    cond do
      abs(dy) >= abs(dx) and dy < 0 -> "North"
      abs(dy) >= abs(dx) and dy > 0 -> "South"
      abs(dx) > abs(dy) and dx > 0 -> "East"
      true -> "West"
    end
  end

  defp is_out_of_bounds({x, y}, w, h), do: x < 0 or x >= w or y < 0 or y >= h

  defp has_wall?(walls, p1, p2) do
    pair = normalize_wall_pair(p1, p2)
    MapSet.member?(walls, pair)
  end

  defp parse_point({x, y}), do: {x, y}
  defp parse_point(%{"x" => x, "y" => y}), do: {x, y}
  defp parse_point([x, y]), do: {x, y}
  defp parse_point(_), do: nil

  defp has_pit?(pits, pos) do
    Enum.any?(pits || [], fn p -> parse_point(p) == pos end)
  end

  defp has_teleport?(teleporters, pos) do
    Enum.any?(teleporters || [], fn
      {p1, p2} -> parse_point(p1) == pos or parse_point(p2) == pos
      [p1, p2] -> parse_point(p1) == pos or parse_point(p2) == pos
      %{"p1" => p1, "p2" => p2} -> parse_point(p1) == pos or parse_point(p2) == pos
      _ -> false
    end)
  end

  defp get_teleport_dest(teleporters, pos) do
    Enum.find_value(teleporters || [], pos, fn
      {p1, p2} ->
        tp1 = parse_point(p1)
        tp2 = parse_point(p2)

        cond do
          tp1 == pos -> tp2
          tp2 == pos -> tp1
          true -> nil
        end

      [p1, p2] ->
        tp1 = parse_point(p1)
        tp2 = parse_point(p2)

        cond do
          tp1 == pos -> tp2
          tp2 == pos -> tp1
          true -> nil
        end

      %{"p1" => p1, "p2" => p2} ->
        tp1 = parse_point(p1)
        tp2 = parse_point(p2)

        cond do
          tp1 == pos -> tp2
          tp2 == pos -> tp1
          true -> nil
        end

      _ ->
        nil
    end)
  end

  defp normalize_wall_pair(p1, p2) do
    if p1 <= p2, do: {p1, p2}, else: {p2, p1}
  end

  defp parse_walls(walls) when is_list(walls) do
    walls
    |> Enum.map(fn
      %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2} -> normalize_wall_pair({x1, y1}, {x2, y2})
      {{x1, y1}, {x2, y2}} -> normalize_wall_pair({x1, y1}, {x2, y2})
    end)
    |> MapSet.new()
  end

  defp parse_walls(walls) when is_struct(walls, MapSet), do: walls

  defp signum(val) when val > 0, do: 1
  defp signum(val) when val < 0, do: -1
  defp signum(_), do: 0
end
