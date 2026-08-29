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
    :minotaur_unseen,
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
    :settings,
    :turn_counter
  ]

  alias Labyrinth.Game.Generator
  alias Labyrinth.Game.Engine.{Combat, Landing}
  alias Labyrinth.MapUtils

  @type direction :: :north | :south | :east | :west
  @type action :: {:move, direction()} | {:shoot, direction()} | {:grenade, direction()} | :pass
  @type player_status :: :active | :wounded | :stunned | :eliminated | :escaped
  @type game_status :: :lobby | :in_progress | :finished

  @type t :: %__MODULE__{
          id: binary() | nil,
          name: binary() | nil,
          width: integer() | nil,
          height: integer() | nil,
          entrance: MapUtils.point() | nil,
          exit: MapUtils.point() | nil,
          treasure: MapUtils.point() | nil,
          hospital: MapUtils.point() | nil,
          arsenal: MapUtils.point() | nil,
          minotaur: MapUtils.point() | nil,
          minotaur_unseen: non_neg_integer() | nil,
          pits: [MapUtils.point()] | nil,
          teleporters: [{MapUtils.point(), MapUtils.point()}] | nil,
          walls: MapSet.t(MapUtils.wall_pair()) | nil,
          destroyed_walls: MapSet.t(MapUtils.wall_pair()) | nil,
          players: [map()] | nil,
          turn_index: non_neg_integer() | nil,
          round_number: pos_integer() | nil,
          status: game_status() | nil,
          winner_name: binary() | nil,
          last_action_result: map() | nil,
          log_entries: [binary()] | nil,
          settings: map() | nil,
          turn_counter: non_neg_integer() | nil
        }

  @spec new_game(binary(), Keyword.t()) :: t()
  def new_game(name, opts \\ []) do
    {:ok, map_data} = Generator.generate_map(opts)
    minotaur_enabled? = Keyword.get(opts, :minotaur_enabled, true)
    id = Keyword.get(opts, :id, Ecto.UUID.generate())

    %__MODULE__{
      id: id,
      name: name,
      width: map_data.width,
      height: map_data.height,
      entrance: map_data.entrance,
      exit: map_data.exit,
      treasure: map_data.treasure,
      hospital: map_data.hospital,
      arsenal: map_data.arsenal,
      minotaur: if(minotaur_enabled?, do: map_data.minotaur, else: nil),
      minotaur_unseen: 0,
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
        "minotaur_enabled" => minotaur_enabled?,
        "difficulty" => Keyword.get(opts, :difficulty, :normal)
      }
    }
  end

  @spec add_player(t(), binary(), binary(), boolean()) :: t()
  def add_player(game, player_id, name, is_bot \\ false) do
    if Enum.any?(game.players, fn p -> p.id == player_id end) do
      game
    else
      diff = Map.get(game.settings || %{}, "difficulty", :normal)

      {start_hp, bullets, grenades, start_items} =
        case diff do
          :easy -> {3, 4, 4, MapSet.new([:rope])}
          :hard -> {2, 2, 2, MapSet.new()}
          _ -> {3, 3, 3, MapSet.new()}
        end

      player = %{
        id: player_id,
        name: name,
        is_bot: is_bot,
        x: elem(game.entrance, 0),
        y: elem(game.entrance, 1),
        health: start_hp,
        max_hp: start_hp,
        bullets: bullets,
        max_bullets: bullets,
        grenades: grenades,
        max_grenades: grenades,
        has_treasure: false,
        items: start_items,
        sight_radius: 1,
        # :active, :stunned, :eliminated, :escaped
        status: :active,
        visited_cells: MapSet.new(),
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

  @spec reset_bot_rel_tracking(t(), binary()) :: t()
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

  @spec start_game(t()) :: t()
  def start_game(%__MODULE__{status: :lobby} = game) do
    if length(game.players) >= 1 do
      teleport_cells =
        (game.teleporters || [])
        |> Enum.flat_map(fn
          {p1, p2} -> [MapUtils.parse_point(p1), MapUtils.parse_point(p2)]
          [p1, p2] -> [MapUtils.parse_point(p1), MapUtils.parse_point(p2)]
          %{"p1" => p1, "p2" => p2} -> [MapUtils.parse_point(p1), MapUtils.parse_point(p2)]
          _ -> []
        end)
        |> MapSet.new()

      pit_cells =
        (game.pits || [])
        |> Enum.map(&MapUtils.parse_point/1)
        |> MapSet.new()

      forbidden_cells =
        [
          teleport_cells,
          pit_cells,
          MapSet.new(
            [
              MapUtils.parse_point(game.exit),
              MapUtils.parse_point(game.treasure),
              MapUtils.parse_point(game.minotaur)
            ]
            |> Enum.reject(&is_nil/1)
          )
        ]
        |> Enum.reduce(MapSet.new(), &MapSet.union/2)

      valid_start_cells =
        for x <- 0..(game.width - 1),
            y <- 0..(game.height - 1),
            pos = {x, y},
            not MapSet.member?(forbidden_cells, pos),
            do: pos

      shuffled_starts = Enum.shuffle(valid_start_cells)

      {updated_players, _} =
        Enum.reduce(game.players, {[], shuffled_starts}, fn p, {acc_p, remaining_starts} ->
          {start_cell, rest_starts} =
            case remaining_starts do
              [s | rest] -> {s, rest}
              [] -> {List.first(shuffled_starts) || game.entrance, []}
            end

          updated_p = %{
            p
            | x: elem(start_cell, 0),
              y: elem(start_cell, 1),
              visited_cells: MapSet.new([start_cell])
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

  @spec current_player(t()) :: map() | nil
  def current_player(%__MODULE__{players: []}), do: nil

  def current_player(%__MODULE__{players: players, turn_index: idx}) do
    Enum.at(players, idx)
  end

  @doc """
  Processes a player's turn action.
  Action: {:move, dir}, {:shoot, dir}, or :pass
  Returns {updated_game, turn_summary}
  """
  @spec process_turn(t(), binary(), action()) ::
          {:ok, t(), map()} | {:error, atom()}
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
    target_pos = MapUtils.neighbor_in_dir(pos_before, dir)

    wall_blocked? =
      MapUtils.out_of_bounds?(target_pos, game.width, game.height) or
        has_wall?(game.walls, pos_before, target_pos)

    rx = Map.get(player, :rel_x, 0)
    ry = Map.get(player, :rel_y, 0)
    {dx, dy} = MapUtils.dir_delta(dir)
    target_rx = rx + dx
    target_ry = ry + dy

    if wall_blocked? do
      # Bump wall
      updated_known_walls =
        MapSet.put(player.known_walls, MapUtils.normalize_wall(pos_before, target_pos))

      updated_rel_walls =
        MapSet.put(
          Map.get(player, :known_rel_walls, MapSet.new()),
          MapUtils.normalize_wall({rx, ry}, {target_rx, target_ry})
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
        Landing.resolve(game, player, target_pos, {target_rx, target_ry})

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
      {hit_result, hit_msg, hit_player_id} =
        Combat.trace_shot(game_updated, pos_before, dir, 3, player.id)

      game_after_hit =
        case hit_player_id do
          :minotaur ->
            %{game_updated | minotaur: nil}

          nil ->
            game_updated

          p_id ->
            Combat.apply_shot_damage(game_updated, p_id)
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
      target_pos = MapUtils.neighbor_in_dir(pos_before, dir)
      wall_pair = MapUtils.normalize_wall(pos_before, target_pos)

      # Check if wall is outer perimeter of the whole labyrinth
      outer_boundary? = MapUtils.out_of_bounds?(target_pos, game.width, game.height)

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
        {mx, my} = MapUtils.parse_point(game.minotaur)

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
    turn_counter = (game.turn_counter || 0) + 1

    game = %{
      game
      | last_action_result: turn_summary,
        log_entries: updated_logs,
        turn_counter: turn_counter
    }

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
        dist = abs(nearest_player.x - mx) + abs(nearest_player.y - my)

        unseen_count = Map.get(game, :minotaur_unseen, 0)
        unseen_count = if dist > 3, do: unseen_count + 1, else: 0
        sprint? = unseen_count >= 3

        steps_to_take = if sprint?, do: 2, else: 1

        {final_mpos, _} =
          Enum.reduce(1..steps_to_take, {{mx, my}, game}, fn _, {{cur_mx, cur_my}, g_acc} ->
            dx = signum(nearest_player.x - cur_mx)
            dy = signum(nearest_player.y - cur_my)

            next_pos =
              cond do
                dx != 0 and not has_wall?(g_acc.walls, {cur_mx, cur_my}, {cur_mx + dx, cur_my}) ->
                  {cur_mx + dx, cur_my}

                dy != 0 and not has_wall?(g_acc.walls, {cur_mx, cur_my}, {cur_mx, cur_my + dy}) ->
                  {cur_mx, cur_my + dy}

                true ->
                  {cur_mx, cur_my}
              end

            {next_pos, g_acc}
          end)

        game_updated = %{game | minotaur: final_mpos, minotaur_unseen: unseen_count}

        victims =
          Enum.filter(game_updated.players, fn p ->
            {p.x, p.y} == final_mpos and p.status in [:active, :wounded, :stunned]
          end)

        {game_after_hits, hit_msgs} =
          Enum.reduce(victims, {game_updated, []}, fn victim, {g_acc, msg_acc} ->
            g_updated = Combat.apply_shot_damage(g_acc, victim.id)
            v_after = Enum.find(g_updated.players, fn p -> p.id == victim.id end)

            msg =
              if v_after && v_after.status == :eliminated do
                "👹 Minotaur mauled and ELIMINATED #{victim.name}!"
              else
                "👹 Minotaur attacked #{victim.name}! (-1 HP, Wounded)"
              end

            {g_updated, [msg | msg_acc]}
          end)

        msg_str =
          if hit_msgs != [],
            do: Enum.join(hit_msgs, " "),
            else: "👹 Minotaur stepped in the shadows."

        {game_after_hits, msg_str}
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
        cardinal_rel = MapUtils.relative_direction({p.x, p.y}, pos)
        sound_type = if action_type == :shoot, do: "A gunshot echoed", else: "Footsteps heard"
        ["Player #{p.name}: #{sound_type} from #{cardinal_rel}"]
      else
        []
      end
    end)
  end

  defp update_player_in_game(game, updated_player) do
    updated_players =
      Enum.map(game.players, fn p -> if p.id == updated_player.id, do: updated_player, else: p end)

    %{game | players: updated_players}
  end

  defp has_wall?(walls, p1, p2) do
    pair = MapUtils.normalize_wall(p1, p2)
    MapSet.member?(walls, pair)
  end

  defp parse_walls(walls) when is_struct(walls, MapSet), do: walls
  defp parse_walls(walls), do: MapUtils.normalize_walls(walls)

  defp signum(val) when val > 0, do: 1
  defp signum(val) when val < 0, do: -1
  defp signum(_), do: 0
end
