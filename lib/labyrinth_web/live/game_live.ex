defmodule LabyrinthWeb.GameLive do
  use LabyrinthWeb, :live_view

  alias Labyrinth.GameServer
  alias Labyrinth.GameSupervisor
  alias Labyrinth.Presence
  alias Labyrinth.Games

  @impl true
  def mount(%{"id" => game_id}, session, socket) do
    # Ensure GameServer process is running
    {:ok, _pid} = GameSupervisor.start_game(game_id: game_id)

    player_id = session["player_id"] || Ecto.UUID.generate()
    player_name = "Player " <> String.slice(player_id, 0, 4)

    # Join game as player
    {:ok, engine} = GameServer.add_player(game_id, player_id, player_name)

    # Auto start game if in lobby status
    engine =
      if engine.status == :lobby do
        case GameServer.start_game(game_id) do
          {:ok, started_engine} -> started_engine
          _ -> engine
        end
      else
        engine
      end

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Labyrinth.PubSub, "game:#{game_id}")

      # Presence tracking
      Presence.track(self(), "game:#{game_id}", player_id, %{
        name: player_name,
        online_at: inspect(System.system_time(:second))
      })
    end

    post_its = Games.list_post_its(game_id, player_id)
    presences = Presence.list("game:#{game_id}")

    {:ok,
     socket
     |> assign(:page_title, "Labyrinth - #{engine.name}")
     |> assign(:game_id, game_id)
     |> assign(:player_id, player_id)
     |> assign(:player_name, player_name)
     |> assign(:engine, engine)
     # :move or :shoot
     |> assign(:action_mode, :move)
     # Toggle GM full map view
     |> assign(:gm_mode, false)
     |> assign(:presences, presences)
     |> assign(:post_its, post_its)
     |> assign(:bot_pins, %{})
     |> assign(:pinning_bot_id, nil)}
  end

  @impl true
  def handle_event("start_game", _params, socket) do
    case GameServer.start_game(socket.assigns.game_id) do
      {:ok, engine} ->
        {:noreply, assign(socket, :engine, engine)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not start game: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("add_bot", _params, socket) do
    case GameServer.add_bot(socket.assigns.game_id) do
      {:ok, engine} ->
        {:noreply, assign(socket, :engine, engine)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not add bot: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("set_action_mode", %{"mode" => mode}, socket) do
    mode_atom =
      case mode do
        "shoot" -> :shoot
        "grenade" -> :grenade
        _ -> :move
      end

    {:noreply, assign(socket, :action_mode, mode_atom)}
  end

  @impl true
  def handle_event("toggle_gm_mode", _params, socket) do
    {:noreply, assign(socket, :gm_mode, not socket.assigns.gm_mode)}
  end

  @impl true
  def handle_event("do_action", %{"dir" => dir_str}, socket) do
    dir = String.to_existing_atom(dir_str)

    action =
      case socket.assigns.action_mode do
        :shoot -> {:shoot, dir}
        :grenade -> {:grenade, dir}
        _ -> {:move, dir}
      end

    case GameServer.take_turn(socket.assigns.game_id, socket.assigns.player_id, action) do
      {:ok, engine, _summary} ->
        {:noreply,
         socket
         |> assign(:engine, engine)
         |> assign(:action_mode, :move)}

      {:error, :not_your_turn} ->
        {:noreply, put_flash(socket, :error, "It is not your turn yet! Please wait.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Action failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("pass_turn", _params, socket) do
    case GameServer.take_turn(socket.assigns.game_id, socket.assigns.player_id, :pass) do
      {:ok, engine, _summary} ->
        {:noreply,
         socket
         |> assign(:engine, engine)
         |> assign(:action_mode, :move)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Pass failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("force_my_turn", _params, socket) do
    case GameServer.force_turn(socket.assigns.game_id, socket.assigns.player_id) do
      {:ok, engine} ->
        {:noreply, assign(socket, :engine, engine)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("handle_keydown", %{"key" => key}, socket) do
    dir =
      case String.downcase(key) do
        k when k in ["w", "arrowup"] -> :north
        k when k in ["s", "arrowdown"] -> :south
        k when k in ["a", "arrowleft"] -> :west
        k when k in ["d", "arrowright"] -> :east
        _ -> nil
      end

    cond do
      key in ["g", "G"] ->
        new_mode = if socket.assigns.action_mode == :grenade, do: :move, else: :grenade
        {:noreply, assign(socket, :action_mode, new_mode)}

      key in ["e", "E"] ->
        new_mode = if socket.assigns.action_mode == :shoot, do: :move, else: :shoot
        {:noreply, assign(socket, :action_mode, new_mode)}

      dir != nil ->
        action =
          case socket.assigns.action_mode do
            :shoot -> {:shoot, dir}
            :grenade -> {:grenade, dir}
            _ -> {:move, dir}
          end

        case GameServer.take_turn(socket.assigns.game_id, socket.assigns.player_id, action) do
          {:ok, engine, _summary} ->
            {:noreply,
             socket
             |> assign(:engine, engine)
             |> assign(:action_mode, :move)}

          _ ->
            {:noreply, socket}
        end

      key == " " ->
        case GameServer.take_turn(socket.assigns.game_id, socket.assigns.player_id, :pass) do
          {:ok, engine, _summary} ->
            {:noreply,
             socket
             |> assign(:engine, engine)
             |> assign(:action_mode, :move)}

          _ ->
            {:noreply, socket}
        end

      true ->
        {:noreply, socket}
    end
  end

  # Post-It Handlers
  @impl true
  def handle_event("add_post_it", %{"color" => color}, socket) do
    new_post_it = %{
      game_id: socket.assigns.game_id,
      player_id: socket.assigns.player_id,
      title: "Hint Note #{length(socket.assigns.post_its) + 1}",
      color: color,
      x_pos: 20 + length(socket.assigns.post_its) * 15,
      y_pos: 20 + length(socket.assigns.post_its) * 15,
      text: "",
      grid_marks: %{}
    }

    {:ok, saved} = Games.save_post_it(new_post_it)
    {:noreply, assign(socket, :post_its, socket.assigns.post_its ++ [saved])}
  end

  @impl true
  def handle_event("update_post_it_text", %{"id" => id, "text" => text}, socket) do
    Games.save_post_it(%{
      "id" => id,
      "game_id" => socket.assigns.game_id,
      "player_id" => socket.assigns.player_id,
      "text" => text
    })

    updated =
      Enum.map(socket.assigns.post_its, fn p ->
        if to_string(p.id) == id, do: %{p | text: text}, else: p
      end)

    {:noreply, assign(socket, :post_its, updated)}
  end

  @impl true
  def handle_event(
        "toggle_post_it_mark",
        %{"id" => id, "cell" => cell_str, "symbol" => symbol},
        socket
      ) do
    post_it = Enum.find(socket.assigns.post_its, fn p -> to_string(p.id) == id end)

    if post_it do
      current_marks = post_it.grid_marks || %{}

      new_marks =
        if Map.get(current_marks, cell_str) == symbol do
          Map.delete(current_marks, cell_str)
        else
          Map.put(current_marks, cell_str, symbol)
        end

      {:ok, saved} =
        Games.save_post_it(%{
          "id" => id,
          "game_id" => socket.assigns.game_id,
          "player_id" => socket.assigns.player_id,
          "grid_marks" => new_marks
        })

      updated =
        Enum.map(socket.assigns.post_its, fn p -> if to_string(p.id) == id, do: saved, else: p end)

      {:noreply, assign(socket, :post_its, updated)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_stick_post_it", %{"id" => id}, socket) do
    post_it = Enum.find(socket.assigns.post_its, fn p -> to_string(p.id) == id end)

    if post_it do
      new_stuck = not (post_it.is_stuck || false)

      case Games.save_post_it(%{
             id: post_it.id,
             game_id: socket.assigns.game_id,
             player_id: socket.assigns.player_id,
             is_stuck: new_stuck
           }) do
        {:ok, saved} ->
          updated =
            Enum.map(socket.assigns.post_its, fn p ->
              if to_string(p.id) == id, do: saved, else: p
            end)

          {:noreply, assign(socket, :post_its, updated)}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_post_it", %{"id" => id}, socket) do
    Games.delete_post_it(id)
    updated = Enum.reject(socket.assigns.post_its, fn p -> to_string(p.id) == id end)
    {:noreply, assign(socket, :post_its, updated)}
  end

  @impl true
  def handle_event("select_pin_bot", %{"bot_id" => bot_id}, socket) do
    bot = Enum.find(socket.assigns.engine.players, fn p -> p.id == bot_id end)

    if bot do
      {:noreply,
       socket
       |> assign(:pinning_bot_id, bot_id)
       |> put_flash(
         :info,
         "📌 Pin Mode Active! Click any cell on the main map to anchor #{bot.name}'s relative origin (0, 0)."
       )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("unpin_bot", %{"bot_id" => bot_id}, socket) do
    updated_pins = Map.delete(socket.assigns[:bot_pins] || %{}, bot_id)

    {:noreply,
     socket
     |> assign(:bot_pins, updated_pins)
     |> put_flash(:info, "Unpinned all fragment snapshots for this bot.")}
  end

  @impl true
  def handle_event("remove_snapshot", %{"bot_id" => bot_id, "snap_id" => snap_id}, socket) do
    existing_snaps = Map.get(socket.assigns[:bot_pins] || %{}, bot_id, [])
    updated_snaps = Enum.reject(existing_snaps, fn s -> s.id == snap_id end)

    updated_pins =
      if updated_snaps == [] do
        Map.delete(socket.assigns[:bot_pins] || %{}, bot_id)
      else
        Map.put(socket.assigns[:bot_pins] || %{}, bot_id, updated_snaps)
      end

    {:noreply,
     socket
     |> assign(:bot_pins, updated_pins)
     |> put_flash(:info, "Removed pinned fragment snapshot.")}
  end

  @impl true
  def handle_event("cell_click", %{"x" => x_str, "y" => y_str}, socket) do
    pinning_bot_id = socket.assigns[:pinning_bot_id]

    if pinning_bot_id do
      x = String.to_integer(x_str)
      y = String.to_integer(y_str)
      bot = Enum.find(socket.assigns.engine.players, fn p -> p.id == pinning_bot_id end)
      bot_name = if bot, do: bot.name, else: pinning_bot_id

      snapshot = %{
        id: Ecto.UUID.generate(),
        bot_id: pinning_bot_id,
        bot_name: bot_name,
        anchor: {x, y},
        visited_rel_cells: Map.get(bot || %{}, :visited_rel_cells, MapSet.new([{0, 0}])),
        known_rel_walls: Map.get(bot || %{}, :known_rel_walls, MapSet.new()),
        discovered_rel_features: Map.get(bot || %{}, :discovered_rel_features, %{})
      }

      existing_snaps = Map.get(socket.assigns[:bot_pins] || %{}, pinning_bot_id, [])

      updated_pins =
        Map.put(socket.assigns[:bot_pins] || %{}, pinning_bot_id, existing_snaps ++ [snapshot])

      # Reset the bot's active relative tracking in GameServer so future steps start a fresh (0,0) relative fragment!
      case GameServer.reset_bot_rel_tracking(socket.assigns.game_id, pinning_bot_id) do
        {:ok, updated_engine} ->
          {:noreply,
           socket
           |> assign(:engine, updated_engine)
           |> assign(:bot_pins, updated_pins)
           |> assign(:pinning_bot_id, nil)
           |> put_flash(
             :info,
             "📌 Pinned #{bot_name}'s fragment at (#{x}, #{y})! A new relative fragment tracking has started."
           )}

        _ ->
          {:noreply,
           socket
           |> assign(:bot_pins, updated_pins)
           |> assign(:pinning_bot_id, nil)}
      end
    else
      {:noreply, socket}
    end
  end

  defp bot_color_theme(bot_id_or_name) do
    idx =
      case Regex.run(~r/\d+/, to_string(bot_id_or_name)) do
        [num_str] -> String.to_integer(num_str)
        _ -> 1
      end

    case rem(max(0, idx - 1), 5) do
      0 ->
        %{
          id: 1,
          name: "amber",
          card_bg: "bg-amber-100 text-slate-950 border-amber-400",
          badge: "bg-amber-500 text-slate-950",
          text_color: "text-amber-400",
          hex: "#f59e0b"
        }

      1 ->
        %{
          id: 2,
          name: "sky",
          card_bg: "bg-sky-100 text-slate-950 border-sky-400",
          badge: "bg-sky-500 text-slate-950",
          text_color: "text-sky-400",
          hex: "#38bdf8"
        }

      2 ->
        %{
          id: 3,
          name: "emerald",
          card_bg: "bg-emerald-100 text-slate-950 border-emerald-400",
          badge: "bg-emerald-500 text-slate-950",
          text_color: "text-emerald-400",
          hex: "#34d399"
        }

      3 ->
        %{
          id: 4,
          name: "purple",
          card_bg: "bg-purple-100 text-slate-950 border-purple-400",
          badge: "bg-purple-500 text-slate-950",
          text_color: "text-purple-400",
          hex: "#c084fc"
        }

      4 ->
        %{
          id: 5,
          name: "rose",
          card_bg: "bg-rose-100 text-slate-950 border-rose-400",
          badge: "bg-rose-500 text-slate-950",
          text_color: "text-rose-400",
          hex: "#fb7185"
        }
    end
  end

  defp cell_feature_icon(cell_pos, engine) do
    cond do
      cell_pos == engine.entrance -> "🚪"
      cell_pos == engine.exit -> "🏁"
      cell_pos == engine.treasure and not Enum.any?(engine.players, & &1.has_treasure) -> "💎"
      cell_pos == Map.get(engine, :hospital) -> "🏥"
      cell_pos == Map.get(engine, :arsenal) -> "⚔️"
      has_portal?(engine.teleporters, cell_pos) -> "🌀"
      has_pit?(engine.pits, cell_pos) -> "🕳"
      true -> nil
    end
  end

  defp collect_stuck_marks(post_its) do
    Enum.reduce(post_its, %{}, fn post_it, acc ->
      if post_it.is_stuck and is_map(post_it.grid_marks) do
        Map.merge(acc, post_it.grid_marks)
      else
        acc
      end
    end)
  end

  @impl true
  def handle_info({:game_updated, engine}, socket) do
    {:noreply, assign(socket, :engine, engine)}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    presences = Presence.list("game:#{socket.assigns.game_id}")
    {:noreply, assign(socket, :presences, presences)}
  end

  defp current_player(engine, player_id) do
    Enum.find(engine.players, fn p -> p.id == player_id end)
  end

  defp active_turn_player(engine) do
    Labyrinth.Game.Engine.current_player(engine)
  end

  defp is_my_turn?(engine, player_id) do
    current = active_turn_player(engine)
    current != nil and current.id == player_id and engine.status == :in_progress
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div phx-window-keydown="handle_keydown" class="max-w-7xl mx-auto space-y-6">
        <%!-- Header Bar --%>
        <div class="bg-slate-900 border border-slate-800 rounded-xl p-4 shadow-lg flex flex-wrap items-center justify-between gap-4">
          <div class="space-y-1">
            <div class="flex items-center gap-3">
              <h1 class="text-2xl font-bold text-white tracking-tight">{@engine.name}</h1>
              <span class={[
                "text-xs font-bold uppercase px-2.5 py-0.5 rounded-full border flex items-center gap-1",
                cond do
                  @engine.status == :finished and
                      String.contains?(@engine.winner_name || "", "Minotaur") ->
                    "bg-rose-950/90 border-rose-500 text-rose-300 animate-pulse"

                  @engine.status == :finished ->
                    "bg-emerald-950/90 border-emerald-500 text-emerald-300"

                  @engine.status == :in_progress ->
                    "bg-emerald-500/10 border-emerald-500/30 text-emerald-400"

                  true ->
                    "bg-amber-500/10 border-amber-500/30 text-amber-400"
                end
              ]}>
                <%= if @engine.status == :finished do %>
                  {if String.contains?(@engine.winner_name || "", "Minotaur"),
                    do: "👹 Minotaur Victory!",
                    else: "🏆 Winner: #{@engine.winner_name}"}
                <% else %>
                  {@engine.status}
                <% end %>
              </span>
            </div>
            <p class="text-xs text-slate-400 flex items-center gap-3">
              <span>Grid: {@engine.width}×{@engine.height}</span>
              <span>•</span>
              <span>Round {@engine.round_number}</span>
              <span>•</span>
              <%= if active_turn_player(@engine) do %>
                <span class="text-amber-300 font-semibold">Current Turn: {active_turn_player(@engine).name}</span>
              <% end %>
            </p>
          </div>

          <div class="flex flex-wrap items-center gap-2">
            <%= if @engine.status == :lobby do %>
              <button
                phx-click="start_game"
                class="px-4 py-2 bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-xs rounded-lg shadow-lg shadow-emerald-600/20 transition-all flex items-center gap-1.5"
              >
                <.icon name="hero-play" class="w-4 h-4" /> Start Expedition
              </button>
            <% end %>

            <button
              phx-click="add_bot"
              disabled={@engine.status == :finished}
              class={[
                "px-3 py-2 text-xs font-semibold rounded-lg border transition-colors flex items-center gap-1.5",
                if(@engine.status == :finished,
                  do: "bg-slate-900 text-slate-600 border-slate-800 opacity-40 cursor-not-allowed",
                  else: "bg-slate-800 hover:bg-slate-700 text-slate-200 border-slate-700"
                )
              ]}
            >
              <.icon name="hero-cpu-chip" class="w-4 h-4 text-amber-400" /> Add AI Bot
            </button>

            <button
              phx-click="toggle_gm_mode"
              class={[
                "px-3 py-2 text-xs font-semibold rounded-lg border transition-colors flex items-center gap-1.5",
                if(@gm_mode,
                  do: "bg-purple-600 text-white border-purple-500",
                  else: "bg-slate-800 text-slate-300 border-slate-700 hover:bg-slate-700"
                )
              ]}
            >
              <.icon name="hero-eye" class="w-4 h-4" />
              {if @gm_mode, do: "GM Master Map (ON)", else: "Toggle GM View"}
            </button>

            <.link
              navigate={~p"/history/#{@game_id}"}
              class="px-3 py-2 bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs font-semibold rounded-lg border border-slate-700 transition-colors flex items-center gap-1.5"
            >
              <.icon name="hero-clock" class="w-4 h-4 text-slate-400" /> History Replay
            </.link>
          </div>
        </div>

        <%!-- Prominent Last Action Result Banner --%>
        <%= if last = @engine.last_action_result do %>
          <% is_bot = String.starts_with?(last.player_id || "", "bot") %>
          <% dir_arrow =
            case last.direction do
              "north" -> "NORTH ▲"
              "south" -> "SOUTH ▼"
              "east" -> "EAST ►"
              "west" -> "WEST ◄"
              _ -> "PASS"
            end %>
          <% res_badge =
            case last.result do
              "wall" -> "WALL 🧱"
              "moved" -> "MOVED 🚶"
              "pit" -> "PIT 🕳"
              "teleport" -> "TELEPORT 🌀"
              "treasure" -> "TREASURE 💎"
              "escaped" -> "ESCAPED 🏆"
              "shot_hit" -> "SHOT HIT 🎯"
              "shot_wall" -> "SHOT WALL 🧱"
              "shot_miss" -> "SHOT MISS 💨"
              _ -> String.upcase(last.result || "")
            end %>

          <div class={[
            "p-3.5 rounded-xl border font-mono text-xs shadow-xl flex flex-wrap items-center justify-between gap-3 transition-all",
            if(is_bot,
              do: "bg-indigo-950/90 border-indigo-500/60 text-indigo-200 ring-1 ring-indigo-500/30",
              else: "bg-amber-950/60 border-amber-500/60 text-amber-200"
            )
          ]}>
            <div class="flex items-center gap-3">
              <span class="text-lg">{if is_bot, do: "🤖", else: "👤"}</span>
              <div class="flex items-center gap-2">
                <span class="font-bold text-white text-sm">{last.player_name}</span>
                <span class="text-slate-400 font-normal">action:</span>
              </div>
              <span class="px-2.5 py-1 rounded bg-slate-900 border border-slate-700 text-amber-300 font-bold uppercase tracking-wider">
                {last.action_type} {dir_arrow}
              </span>
              <span class="text-slate-400">→</span>
              <span class={[
                "px-2.5 py-1 rounded font-bold uppercase tracking-wider border shadow",
                if(last.result == "wall",
                  do: "bg-rose-950/80 border-rose-600 text-rose-300",
                  else: "bg-emerald-950/80 border-emerald-600 text-emerald-300"
                )
              ]}>
                {res_badge}
              </span>
            </div>

            <%= if @gm_mode and last.pos_before && last.pos_after do %>
              <div class="text-[11px] text-slate-400 font-mono">
                GM Coordinates: ({format_pos(last.pos_before)}) → ({format_pos(last.pos_after)})
              </div>
            <% end %>
          </div>
        <% end %>

        <%!-- Main Game Dashboard (Board + Log + Post-Its) --%>
        <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
          <%!-- Left Column: Map Board & Controls (8 cols) --%>
          <div class="lg:col-span-8 space-y-6">
            <%!-- Player Status Bar --%>
            <%= if my_p = current_player(@engine, @player_id) do %>
              <div class="bg-slate-900 border border-slate-800 rounded-xl p-4 shadow-md flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-lg bg-amber-500/20 border border-amber-500/40 flex items-center justify-center text-amber-400 font-bold text-base">
                    👤
                  </div>
                  <div>
                    <h3 class="font-bold text-white text-sm">{my_p.name}</h3>
                    <p class="text-xs text-slate-400">Position: ({my_p.x}, {my_p.y})</p>
                  </div>
                </div>

                <div class="flex items-center gap-6 text-xs">
                  <div class="flex items-center gap-1.5">
                    <span class="text-rose-400">❤ Health:</span>
                    <span class="font-bold text-white">{my_p.health}/3</span>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <span class="text-amber-400">🔫 Bullets:</span>
                    <span class="font-bold text-white">{my_p.bullets}/3</span>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <span class="text-orange-400">💣 Grenades:</span>
                    <span class="font-bold text-white">{Map.get(my_p, :grenades, 3)}/3</span>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <span class="text-emerald-400">💎 Treasure:</span>
                    <span class="font-bold text-white">{if my_p.has_treasure, do: "YES 🏆", else: "NO"}</span>
                  </div>
                  <div class="flex items-center gap-1.5">
                    <span class="text-slate-400">Status:</span>
                    <span class={[
                      "font-bold text-xs px-2 py-0.5 rounded capitalize",
                      case my_p.status do
                        :wounded -> "bg-rose-950 text-rose-300 border border-rose-700 animate-pulse"
                        :active -> "bg-emerald-950 text-emerald-300 border border-emerald-800"
                        :stunned -> "bg-amber-950 text-amber-300 border border-amber-800"
                        :eliminated -> "bg-red-950 text-red-400 border border-red-800 font-extrabold"
                        _ -> "bg-indigo-950 text-indigo-300 border border-indigo-800"
                      end
                    ]}>
                      {case my_p.status do
                        :wounded -> "Wounded 🩸 (#{my_p.health}/3 HP)"
                        :active -> "Healthy 🤠 (3 HP)"
                        :stunned -> "Stunned 🕳"
                        :eliminated -> "Eliminated 💀"
                        :escaped -> "Escaped 🏆"
                        s -> Atom.to_string(s)
                      end}
                    </span>
                  </div>
                </div>
              </div>
            <% end %>

            <%!-- The Interactive Maze Grid --%>
            <div class="bg-slate-900 border border-slate-800 rounded-2xl p-6 shadow-2xl flex flex-col items-center justify-center relative w-full">
              <%= if @engine.status == :finished do %>
                <%= if String.contains?(@engine.winner_name || "", "Minotaur") do %>
                  <div class="w-full bg-gradient-to-r from-red-950 via-rose-900 to-red-950 border-2 border-red-600 rounded-xl p-4 mb-4 text-center shadow-2xl animate-pulse">
                    <div class="flex items-center justify-center gap-3 text-xl sm:text-2xl font-black text-red-100 tracking-wider">
                      <span class="text-3xl animate-bounce">👹</span>
                      <span>ALL PLAYERS WERE ELIMINATED! MINOTAUR WINS!</span>
                      <span class="text-3xl">💀</span>
                    </div>
                    <p class="text-xs text-red-200/90 font-mono mt-1">
                      The ferocious Minotaur claimed all explorers. Full maze layout revealed below.
                    </p>
                  </div>
                <% else %>
                  <div class="w-full bg-gradient-to-r from-emerald-950 via-teal-900 to-emerald-950 border-2 border-emerald-500 rounded-xl p-4 mb-4 text-center shadow-2xl">
                    <div class="flex items-center justify-center gap-3 text-xl sm:text-2xl font-black text-emerald-200 tracking-wider">
                      <span class="text-3xl">🏆</span>
                      <span>LABYRINTH ESCAPED! VICTORY FOR {@engine.winner_name}!</span>
                      <span class="text-3xl">💎</span>
                    </div>
                    <p class="text-xs text-emerald-300/90 font-mono mt-1">
                      The treasure was safely carried out of the exit corridor!
                    </p>
                  </div>
                <% end %>
              <% end %>

              <% me = current_player(@engine, @player_id) %>
              <% minotaur_pos = @engine.minotaur %>
              <% stink_detected? =
                me != nil and me.status in [:active, :wounded] and minotaur_pos != nil and
                  abs(me.x - elem(minotaur_pos, 0)) + abs(me.y - elem(minotaur_pos, 1)) <= 2 %>

              <%= if stink_detected? do %>
                <div class="w-full bg-amber-500/20 border border-amber-500/50 rounded-xl p-3 text-center shadow-lg animate-pulse flex items-center justify-center gap-2 text-amber-300 font-bold text-xs mb-3">
                  <span class="text-base">🦨</span>
                  <span>SENSORY WARNING: You smelled the Minotaur's foul stink wafting nearby! (Within 2 cells)</span>
                  <span class="text-base">👹</span>
                </div>
              <% end %>

              <div class="mb-3 text-xs text-slate-400 flex items-center justify-between w-full">
                <span>{cond do
                  @engine.status == :finished -> "🏁 Revealed Game Over Map"
                  @gm_mode -> "👁 Secret GM Master Map View"
                  true -> "🔍 Blind Fog-of-War Explorer Map"
                end}</span>
                <span class="font-mono">Use W/A/S/D or Arrow Keys to Move</span>
              </div>

              <% me = current_player(@engine, @player_id) %>
              <% visited_set = if(me, do: me.visited_cells, else: MapSet.new()) %>
              <% known_walls_set = if(me, do: me.known_walls, else: MapSet.new()) %>
              <% reveal_full_map? = @gm_mode or @engine.status == :finished %>
              <% stuck_marks_map = collect_stuck_marks(@post_its) %>

              <% bot_pins = @bot_pins || %{} %>
              <% all_snapshots = Enum.flat_map(bot_pins, fn {_bot_id, snaps} -> snaps end) %>

              <% pinned_bot_walls =
                Enum.reduce(all_snapshots, MapSet.new(), fn snap, acc ->
                  {ox, oy} = snap.anchor
                  rel_walls = snap.known_rel_walls

                  projected =
                    Enum.map(rel_walls, fn {{rx1, ry1}, {rx2, ry2}} ->
                      normalize_wall({ox + rx1, oy + ry1}, {ox + rx2, oy + ry2})
                    end)

                  MapSet.union(acc, MapSet.new(projected))
                end) %>

              <% pinned_bot_visited =
                Enum.reduce(all_snapshots, MapSet.new(), fn snap, acc ->
                  {ox, oy} = snap.anchor
                  rel_visited = snap.visited_rel_cells
                  projected = Enum.map(rel_visited, fn {rx, ry} -> {ox + rx, oy + ry} end)
                  MapSet.union(acc, MapSet.new(projected))
                end) %>

              <% pinned_bot_features =
                Enum.reduce(all_snapshots, %{}, fn snap, acc ->
                  {ox, oy} = snap.anchor
                  rel_feats = snap.discovered_rel_features

                  projected =
                    Enum.reduce(rel_feats, %{}, fn {{rx, ry}, feat}, f_acc ->
                      Map.put(f_acc, {ox + rx, oy + ry}, {snap.bot_id, snap.bot_name, feat})
                    end)

                  Map.merge(acc, projected)
                end) %>

              <div
                class="grid gap-1 bg-slate-950 p-3 rounded-xl border border-slate-800 shadow-inner"
                style={"grid-template-columns: repeat(#{@engine.width}, minmax(0, 1fr));"}
              >
                <%= for y <- 0..(@engine.height - 1) do %>
                  <%= for x <- 0..(@engine.width - 1) do %>
                    <% cell_pos = {x, y} %>
                    <% is_visited =
                      MapSet.member?(visited_set, cell_pos) or
                        MapSet.member?(pinned_bot_visited, cell_pos) or reveal_full_map? %>
                    <% stuck_symbol = Map.get(stuck_marks_map, "#{x},#{y}") %>
                    <% pinned_bot_feat = Map.get(pinned_bot_features, cell_pos) %>
                    <% active_players_here =
                      Enum.filter(@engine.players, fn p ->
                        {p.x, p.y} == cell_pos and p.status in [:active, :wounded, :stunned]
                      end) %>
                    <% eliminated_players_here =
                      Enum.filter(@engine.players, fn p ->
                        {p.x, p.y} == cell_pos and p.status == :eliminated
                      end) %>
                    <% is_me_here = me != nil and {me.x, me.y} == cell_pos %>
                    <% is_minotaur_here = reveal_full_map? and @engine.minotaur == cell_pos %>

                    <%!-- Cell Wall boundaries --%>
                    <% wall_source =
                      if(reveal_full_map?,
                        do: @engine.walls,
                        else: MapSet.union(known_walls_set, pinned_bot_walls)
                      ) %>
                    <% destroyed_wall_source = Map.get(@engine, :destroyed_walls, MapSet.new()) %>
                    <% n_wall =
                      MapSet.member?(wall_source, normalize_wall(cell_pos, {x, y - 1})) or y == 0 %>
                    <% s_wall =
                      MapSet.member?(wall_source, normalize_wall(cell_pos, {x, y + 1})) or
                        y == @engine.height - 1 %>
                    <% w_wall =
                      MapSet.member?(wall_source, normalize_wall(cell_pos, {x - 1, y})) or x == 0 %>
                    <% e_wall =
                      MapSet.member?(wall_source, normalize_wall(cell_pos, {x + 1, y})) or
                        x == @engine.width - 1 %>

                    <% n_destroyed =
                      MapSet.member?(destroyed_wall_source, normalize_wall(cell_pos, {x, y - 1})) %>
                    <% s_destroyed =
                      MapSet.member?(destroyed_wall_source, normalize_wall(cell_pos, {x, y + 1})) %>
                    <% w_destroyed =
                      MapSet.member?(destroyed_wall_source, normalize_wall(cell_pos, {x - 1, y})) %>
                    <% e_destroyed =
                      MapSet.member?(destroyed_wall_source, normalize_wall(cell_pos, {x + 1, y})) %>
                    <% has_debris? = n_destroyed or s_destroyed or w_destroyed or e_destroyed %>

                    <div
                      phx-click={if @pinning_bot_id != nil, do: "cell_click", else: nil}
                      phx-value-x={x}
                      phx-value-y={y}
                      class={[
                        "w-10 h-10 sm:w-12 sm:h-12 rounded flex items-center justify-center text-sm relative transition-all border",
                        if(@pinning_bot_id != nil,
                          do:
                            "cursor-pointer hover:ring-2 hover:ring-amber-400 bg-amber-500/20 animate-pulse",
                          else: ""
                        ),
                        if(is_visited,
                          do: "bg-slate-900 border-slate-800",
                          else: "bg-slate-950/80 border-slate-900/50 opacity-40"
                        ),
                        if(is_me_here and me.status in [:active, :wounded, :stunned],
                          do: "bg-amber-500/10"
                        ),
                        if(n_wall, do: "border-t-2 border-t-amber-600/80"),
                        if(s_wall, do: "border-b-2 border-b-amber-600/80"),
                        if(w_wall, do: "border-l-2 border-l-amber-600/80"),
                        if(e_wall, do: "border-r-2 border-r-amber-600/80"),
                        if(n_destroyed, do: "border-t-2 border-dashed border-t-orange-700/80"),
                        if(s_destroyed, do: "border-b-2 border-dashed border-b-orange-700/80"),
                        if(w_destroyed, do: "border-l-2 border-dashed border-l-orange-700/80"),
                        if(e_destroyed, do: "border-r-2 border-dashed border-r-orange-700/80")
                      ]}
                    >
                      <%= if stuck_symbol != nil and stuck_symbol != "" do %>
                        <span
                          class="absolute -top-1 -right-1 text-[9px] font-bold px-1 py-0.2 bg-amber-400 text-slate-950 rounded-full shadow border border-amber-300 font-mono z-10 animate-pulse"
                          title={"Stuck Post-It Hint: #{stuck_symbol}"}
                        >
                          📌 {stuck_symbol}
                        </span>
                      <% end %>

                      <%= if is_visited do %>
                        <%= cond do %>
                          <% is_minotaur_here -> %>
                            <span class={[
                              "text-lg",
                              if(@engine.status == :finished,
                                do:
                                  "text-2xl animate-bounce drop-shadow-[0_0_12px_rgba(239,68,68,0.9)]",
                                else: ""
                              )
                            ]}>👹</span>
                          <% is_me_here and me.status in [:active, :wounded, :stunned] -> %>
                            <span
                              class="text-lg animate-bounce"
                              title={
                                if me.status == :wounded, do: "Wounded Explorer", else: "Explorer"
                              }
                            >
                              {if me.status == :wounded, do: "🩸🤠", else: "🤠"}
                            </span>
                          <% active_players_here != [] -> %>
                            <% any_wounded? = Enum.any?(active_players_here, &(&1.status == :wounded)) %>
                            <% first_p = List.first(active_players_here) %>
                            <% p_theme =
                              if(first_p && first_p.is_bot,
                                do: bot_color_theme(first_p.id),
                                else: nil
                              ) %>

                            <span
                              class={[
                                "text-base font-bold rounded px-0.5 shadow-sm",
                                if(p_theme, do: p_theme.badge, else: "")
                              ]}
                              title={Enum.map_join(active_players_here, ", ", & &1.name)}
                            >
                              {if any_wounded?, do: "🩸👤", else: "👤"}
                            </span>
                          <% eliminated_players_here != [] -> %>
                            <% first_elim = List.first(eliminated_players_here) %>
                            <% elim_theme =
                              if(first_elim && first_elim.is_bot,
                                do: bot_color_theme(first_elim.id),
                                else: nil
                              ) %>
                            <% feature_icon = cell_feature_icon(cell_pos, @engine) %>

                            <span
                              class={[
                                "text-base font-bold rounded px-0.5 opacity-90 shadow-sm flex items-center justify-center gap-0.5",
                                if(elim_theme,
                                  do: elim_theme.badge,
                                  else: "bg-slate-800 text-rose-400 border border-slate-700"
                                )
                              ]}
                              title={"Eliminated: #{Enum.map_join(eliminated_players_here, ", ", & &1.name)}"}
                            >
                              <%= if elim_theme do %>
                                {if feature_icon, do: "#{feature_icon}💀", else: "💀"}
                              <% else %>
                                {if feature_icon, do: "#{feature_icon}💀🤠", else: "💀🤠"}
                              <% end %>
                            </span>
                          <% cell_pos == @engine.entrance -> %>
                            <span class="text-xs font-bold text-emerald-400">🚪</span>
                          <% cell_pos == @engine.exit -> %>
                            <span class="text-xs font-bold text-purple-400">🏁</span>
                          <% cell_pos == @engine.treasure and not Enum.any?(@engine.players, & &1.has_treasure) -> %>
                            <span class="text-base animate-bounce" title="Treasure Relic">💎</span>
                          <% cell_pos == Map.get(@engine, :hospital) -> %>
                            <span class="text-base" title="Hospital / Medical Sanctuary">🏥</span>
                          <% cell_pos == Map.get(@engine, :arsenal) -> %>
                            <span class="text-base" title="Arsenal / Armory">⚔️</span>
                          <% has_portal?(@engine.teleporters, cell_pos) -> %>
                            <span class="text-base animate-pulse" title="Teleporter Portal">🌀</span>
                          <% cell_pos in @engine.pits -> %>
                            <span class="text-base">🕳</span>
                          <% pinned_bot_feat != nil -> %>
                            <% {b_id, b_name, b_feat} = pinned_bot_feat %>
                            <% b_theme = bot_color_theme(b_id) %>
                            <span
                              class={[
                                "text-xs flex items-center justify-center font-bold px-1 py-0.5 rounded shadow-sm",
                                b_theme.badge
                              ]}
                              title={"Pinned from #{b_name}: #{b_feat}"}
                            >
                              📌{case b_feat do
                                "pit" -> "🕳"
                                "teleport" -> "🌀"
                                "hospital" -> "🏥"
                                "arsenal" -> "⚔️"
                                "treasure" -> "💎"
                                "exit" -> "🏁"
                                _ -> "❓"
                              end}
                            </span>
                          <% has_debris? -> %>
                            <span class="text-[10px] opacity-75" title="Demolished Wall Debris">🧱💥</span>
                          <% true -> %>
                            <span class="text-[9px] text-slate-700 font-mono">{x},{y}</span>
                        <% end %>
                      <% else %>
                        <%= if stuck_symbol != nil and stuck_symbol != "" do %>
                          <span
                            class="text-xs font-bold text-amber-300 opacity-90 font-mono flex items-center gap-0.5"
                            title={"Draft Stuck Hint: #{stuck_symbol}"}
                          >
                            📌{stuck_symbol}
                          </span>
                        <% else %>
                          <span class="text-[8px] text-slate-800 font-mono">?</span>
                        <% end %>
                      <% end %>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <%!-- Turn Status Banner & Directional D-Pad Controls --%>
            <div class="bg-slate-900 border border-slate-800 rounded-xl p-5 shadow-xl space-y-4">
              <% is_my_turn = is_my_turn?(@engine, @player_id) %>

              <div class={[
                "p-3 rounded-lg border text-xs font-bold flex items-center justify-between transition-all",
                if(is_my_turn,
                  do: "bg-emerald-950/80 border-emerald-600 text-emerald-300 animate-pulse",
                  else: "bg-amber-950/40 border-amber-800/60 text-amber-300"
                )
              ]}>
                <div class="flex items-center gap-2">
                  <span>{if is_my_turn, do: "🟢 YOUR TURN!", else: "⏳ WAITING FOR TURN..."}</span>
                  <span class="font-normal opacity-80 font-mono">
                    ({if is_my_turn,
                      do: "Click D-Pad or press W/A/S/D / Arrow keys to move",
                      else:
                        "Current turn: #{if active_turn_player(@engine), do: active_turn_player(@engine).name, else: "N/A"}"})
                  </span>
                </div>
                <%= if not is_my_turn and @engine.status == :in_progress do %>
                  <button
                    phx-click="force_my_turn"
                    class="px-2.5 py-1 bg-amber-500 hover:bg-amber-400 text-slate-950 text-[10px] font-bold rounded shadow transition-colors"
                  >
                    Take Turn Now
                  </button>
                <% end %>
              </div>

              <div class="flex flex-wrap items-center justify-between gap-6 pt-1">
                <div class="flex items-center gap-3">
                  <span class="text-xs font-bold text-slate-300">Action Mode:</span>
                  <button
                    phx-click="set_action_mode"
                    phx-value-mode="move"
                    class={[
                      "px-3 py-1.5 text-xs font-bold rounded-lg border transition-all flex items-center gap-1",
                      if(@action_mode == :move,
                        do: "bg-amber-500 text-slate-950 border-amber-400 shadow-md",
                        else: "bg-slate-800 text-slate-300 border-slate-700"
                      )
                    ]}
                  >
                    🚶 Move
                  </button>
                  <button
                    phx-click="set_action_mode"
                    phx-value-mode="shoot"
                    class={[
                      "px-3 py-1.5 text-xs font-bold rounded-lg border transition-all flex items-center gap-1",
                      if(@action_mode == :shoot,
                        do: "bg-rose-600 text-white border-rose-500 shadow-md",
                        else: "bg-slate-800 text-slate-300 border-slate-700"
                      )
                    ]}
                  >
                    🎯 Shoot
                  </button>
                  <button
                    phx-click="set_action_mode"
                    phx-value-mode="grenade"
                    class={[
                      "px-3 py-1.5 text-xs font-bold rounded-lg border transition-all flex items-center gap-1",
                      if(@action_mode == :grenade,
                        do:
                          "bg-orange-600 text-white border-orange-500 shadow-md ring-1 ring-orange-400 animate-pulse",
                        else: "bg-slate-800 text-slate-300 border-slate-700"
                      )
                    ]}
                    title="Blow up adjacent wall (HotKey: G)"
                  >
                    💣 Grenade (Blow Wall)
                  </button>
                </div>

                <%!-- D-Pad --%>
                <div class="flex items-center gap-2">
                  <div class="grid grid-cols-3 gap-1 w-36">
                    <div></div>
                    <button
                      phx-click="do_action"
                      phx-value-dir="north"
                      disabled={not is_my_turn}
                      class="py-2.5 bg-slate-800 hover:bg-slate-700 disabled:opacity-30 disabled:hover:bg-slate-800 text-white font-bold text-sm rounded border border-slate-700 flex items-center justify-center transition-colors"
                    >
                      ▲
                    </button>
                    <div></div>
                    <button
                      phx-click="do_action"
                      phx-value-dir="west"
                      disabled={not is_my_turn}
                      class="py-2.5 bg-slate-800 hover:bg-slate-700 disabled:opacity-30 disabled:hover:bg-slate-800 text-white font-bold text-sm rounded border border-slate-700 flex items-center justify-center transition-colors"
                    >
                      ◄
                    </button>
                    <button
                      phx-click="pass_turn"
                      disabled={not is_my_turn}
                      class="py-2.5 bg-amber-600/30 hover:bg-amber-600/50 text-amber-300 font-bold text-xs rounded border border-amber-500/40 flex items-center justify-center transition-colors"
                    >
                      PASS
                    </button>
                    <button
                      phx-click="do_action"
                      phx-value-dir="east"
                      disabled={not is_my_turn}
                      class="py-2.5 bg-slate-800 hover:bg-slate-700 disabled:opacity-30 disabled:hover:bg-slate-800 text-white font-bold text-sm rounded border border-slate-700 flex items-center justify-center transition-colors"
                    >
                      ►
                    </button>
                    <div></div>
                    <button
                      phx-click="do_action"
                      phx-value-dir="south"
                      disabled={not is_my_turn}
                      class="py-2.5 bg-slate-800 hover:bg-slate-700 disabled:opacity-30 disabled:hover:bg-slate-800 text-white font-bold text-sm rounded border border-slate-700 flex items-center justify-center transition-colors"
                    >
                      ▼
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <%!-- Right Column: Interactive Bot Post-Its, Telemetry Log & Roster (4 cols) --%>
          <div class="lg:col-span-4 space-y-6">
            <%!-- Bot Expedition Sub-Grid Post-Its --%>
            <div class="bg-slate-900 border border-slate-800 rounded-xl p-5 shadow-xl space-y-4">
              <div class="flex items-center justify-between border-b border-slate-800 pb-3">
                <h3 class="text-sm font-bold text-slate-100 flex items-center gap-2">
                  <.icon name="hero-document-duplicate" class="w-4 h-4 text-amber-400" />
                  Bot Expedition Post-Its
                </h3>
                <span class="text-[11px] font-mono text-slate-400">Blind relative fragments</span>
              </div>

              <% bot_players = Enum.filter(@engine.players, & &1.is_bot) %>

              <div class="space-y-4 max-h-[600px] overflow-y-auto pr-1">
                <%= if bot_players == [] do %>
                  <div class="p-6 text-center bg-slate-950/60 rounded-lg border border-dashed border-slate-800 text-slate-400 text-xs">
                    No bots in this expedition. Add bots from the lobby or control panel to trace their blind relative fragments!
                  </div>
                <% end %>

                <%= for bot <- bot_players do %>
                  <% b_theme = bot_color_theme(bot.id) %>
                  <% bot_snaps = Map.get(@bot_pins, bot.id, []) %>
                  <% is_selecting_pin = @pinning_bot_id == bot.id %>

                  <div class={[
                    "rounded-xl p-4 shadow-lg border space-y-3 relative transition-all",
                    if(is_selecting_pin,
                      do: "bg-amber-100 border-amber-500 ring-2 ring-amber-400 text-slate-950",
                      else: b_theme.card_bg
                    )
                  ]}>
                    <div class="flex items-center justify-between border-b border-slate-950/20 pb-2">
                      <div class="flex items-center gap-2">
                        <span class="font-bold text-xs uppercase tracking-wide truncate max-w-[150px]">🤖 {bot.name}</span>
                        <span class={[
                          "px-1.5 py-0.5 text-[9px] font-bold rounded font-mono shadow-sm",
                          b_theme.badge
                        ]}>
                          BOT #{b_theme.id}
                        </span>
                      </div>

                      <button
                        phx-click="select_pin_bot"
                        phx-value-bot_id={bot.id}
                        class={[
                          "px-2 py-1 text-[10px] font-bold rounded shadow-sm transition-all border",
                          if(is_selecting_pin,
                            do: "bg-amber-600 text-white border-amber-700 animate-pulse",
                            else: "bg-slate-900 text-amber-300 border-slate-800 hover:bg-slate-950"
                          )
                        ]}
                      >
                        📌 {if is_selecting_pin, do: "Click Map Cell...", else: "Pin Active Fragment"}
                      </button>
                    </div>

                    <%!-- Pinned Snapshots List --%>
                    <%= if bot_snaps != [] do %>
                      <div class="space-y-1 bg-slate-950/20 p-2 rounded border border-slate-950/30 text-[10px]">
                        <div class="font-bold uppercase opacity-80 flex items-center justify-between">
                          <span>📌 Pinned Snapshots ({length(bot_snaps)}):</span>
                          <button
                            phx-click="unpin_bot"
                            phx-value-bot_id={bot.id}
                            class="text-rose-700 hover:underline font-bold text-[9px]"
                          >
                            Clear All
                          </button>
                        </div>
                        <div class="space-y-1">
                          <%= for snap <- bot_snaps do %>
                            <div class="flex items-center justify-between bg-slate-950/40 p-1.5 rounded font-mono text-[10px]">
                              <span>📌 Anchor ({elem(snap.anchor, 0)}, {elem(snap.anchor, 1)})</span>
                              <button
                                phx-click="remove_snapshot"
                                phx-value-bot_id={bot.id}
                                phx-value-snap_id={snap.id}
                                class="text-slate-700 hover:text-rose-700 font-bold px-1"
                                title="Remove Snapshot"
                              >
                                ✕
                              </button>
                            </div>
                          <% end %>
                        </div>
                      </div>
                    <% end %>

                    <% rel_visited = Map.get(bot, :visited_rel_cells, MapSet.new([{0, 0}])) %>
                    <% rel_walls = Map.get(bot, :known_rel_walls, MapSet.new()) %>
                    <% rel_feats = Map.get(bot, :discovered_rel_features, %{}) %>

                    <% rel_xs = Enum.map(rel_visited, &elem(&1, 0)) %>
                    <% rel_ys = Enum.map(rel_visited, &elem(&1, 1)) %>
                    <% min_rx = Enum.min(rel_xs ++ [-2]) %>
                    <% max_rx = Enum.max(rel_xs ++ [2]) %>
                    <% min_ry = Enum.min(rel_ys ++ [-2]) %>
                    <% max_ry = Enum.max(rel_ys ++ [2]) %>

                    <div class="space-y-1">
                      <div class="text-[10px] font-semibold opacity-75">
                        Active Relative Fragment (New Tracking from 0,0):
                      </div>
                      <div class="p-2 bg-slate-950/80 rounded-lg border border-slate-900 overflow-x-auto flex items-center justify-center">
                        <div
                          class="grid gap-0.5"
                          style={"grid-template-columns: repeat(#{max_rx - min_rx + 1}, minmax(0, 1fr));"}
                        >
                          <%= for ry <- min_ry..max_ry do %>
                            <%= for rx <- min_rx..max_rx do %>
                              <% r_pos = {rx, ry} %>
                              <% is_r_visited = MapSet.member?(rel_visited, r_pos) %>
                              <% r_feat = Map.get(rel_feats, r_pos) %>
                              <% is_bot_current =
                                Map.get(bot, :rel_x, 0) == rx and Map.get(bot, :rel_y, 0) == ry %>

                              <% n_rwall =
                                MapSet.member?(rel_walls, normalize_wall(r_pos, {rx, ry - 1})) %>
                              <% s_rwall =
                                MapSet.member?(rel_walls, normalize_wall(r_pos, {rx, ry + 1})) %>
                              <% w_rwall =
                                MapSet.member?(rel_walls, normalize_wall(r_pos, {rx - 1, ry})) %>
                              <% e_rwall =
                                MapSet.member?(rel_walls, normalize_wall(r_pos, {rx + 1, ry})) %>

                              <div class={[
                                "w-6 h-6 rounded flex items-center justify-center text-[10px] relative transition-all border",
                                if(is_r_visited,
                                  do: "bg-slate-900 border-slate-800 text-white",
                                  else: "bg-slate-950 opacity-30 border-slate-900"
                                ),
                                if(is_bot_current, do: "ring-1 ring-amber-400 bg-amber-500/20"),
                                if(n_rwall, do: "border-t-2 border-t-amber-500"),
                                if(s_rwall, do: "border-b-2 border-b-amber-500"),
                                if(w_rwall, do: "border-l-2 border-l-amber-500"),
                                if(e_rwall, do: "border-r-2 border-r-amber-500")
                              ]}>
                                <%= cond do %>
                                  <% is_bot_current -> %>
                                    <span>🤖</span>
                                  <% r_feat == "pit" -> %>
                                    <span>🕳</span>
                                  <% r_feat == "teleport" -> %>
                                    <span>🌀</span>
                                  <% r_feat == "hospital" -> %>
                                    <span>🏥</span>
                                  <% r_feat == "arsenal" -> %>
                                    <span>⚔️</span>
                                  <% r_feat == "treasure" -> %>
                                    <span>💎</span>
                                  <% r_feat == "exit" -> %>
                                    <span>🏁</span>
                                  <% rx == 0 and ry == 0 -> %>
                                    <span class="text-[8px] font-mono text-emerald-400 font-bold">0,0</span>
                                  <% is_r_visited -> %>
                                    <span class="w-1.5 h-1.5 rounded-full bg-slate-600"></span>
                                  <% true -> %>
                                    <span></span>
                                <% end %>
                              </div>
                            <% end %>
                          <% end %>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- Event Feed & Auditory Log --%>
            <div class="bg-slate-900 border border-slate-800 rounded-xl p-5 shadow-xl space-y-3">
              <h3 class="text-sm font-bold text-slate-200 flex items-center gap-2">
                <.icon name="hero-speaker-wave" class="w-4 h-4 text-amber-400" />
                GM Feedback & Sensory Echo Log
              </h3>
              <div class="bg-slate-950 border border-slate-800 rounded-lg p-3.5 max-h-[30rem] overflow-y-auto space-y-1.5 font-mono text-xs text-slate-300 shadow-inner">
                <%= for log <- Enum.take(@engine.log_entries, 80) do %>
                  <%= if String.contains?(log, "───") do %>
                    <div class="my-2 py-1 px-2 bg-slate-900 border-y border-amber-500/30 text-amber-400 font-bold text-[10px] uppercase tracking-wider text-center flex items-center justify-center gap-2 rounded shadow-sm">
                      {log}
                    </div>
                  <% else %>
                    <div class="py-0.5 border-b border-slate-900/60 last:border-0 flex items-start gap-2">
                      <span class="text-amber-500 select-none">></span>
                      <span>{log}</span>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <%!-- Online Explorers / Presence Roster --%>
            <div class="bg-slate-900 border border-slate-800 rounded-xl p-5 shadow-xl space-y-3">
              <div class="flex items-center justify-between">
                <h3 class="text-sm font-bold text-slate-100 flex items-center gap-2">
                  <.icon name="hero-users" class="w-4 h-4 text-emerald-400" /> Explorers Roster
                </h3>
                <span class="text-xs font-mono text-emerald-400">
                  {map_size(@presences)} online
                </span>
              </div>

              <div class="space-y-2">
                <%= for p <- @engine.players do %>
                  <% is_online = Map.has_key?(@presences, p.id) or p.is_bot %>
                  <% is_current_turn =
                    active_turn_player(@engine) != nil and active_turn_player(@engine).id == p.id %>
                  <% p_theme = if(p.is_bot, do: bot_color_theme(p.id), else: nil) %>

                  <div class={[
                    "p-2.5 rounded-lg border text-xs flex items-center justify-between transition-all",
                    if(is_current_turn,
                      do: "bg-amber-500/10 border-amber-500/50 shadow",
                      else: "bg-slate-950 border-slate-800"
                    )
                  ]}>
                    <div class="flex items-center gap-2">
                      <span class={[
                        "w-2 h-2 rounded-full",
                        if(is_online, do: "bg-emerald-400 animate-pulse", else: "bg-slate-600")
                      ]}></span>
                      <span class={[
                        "font-bold",
                        if(p_theme, do: p_theme.text_color, else: "text-white")
                      ]}>{p.name}</span>
                      <%= if p.is_bot do %>
                        <span class={[
                          "text-[10px] font-bold px-1.5 py-0.5 rounded font-mono shadow-sm",
                          p_theme.badge
                        ]}>
                          BOT #{p_theme.id}
                        </span>
                      <% end %>
                    </div>
                    <div class="flex items-center gap-2 font-mono text-[11px]">
                      <span class={[
                        if(p.status == :wounded,
                          do: "text-rose-400 font-bold",
                          else: "text-slate-300"
                        ),
                        if(p.status == :eliminated, do: "text-red-500 line-through", else: "")
                      ]}>
                        {case p.status do
                          :wounded -> "🩸 #{p.health}/3 HP"
                          :eliminated -> "💀 DEAD"
                          _ -> "HP:#{p.health}/3"
                        end}
                      </span>
                      <span class="text-slate-400">🔫:{p.bullets}</span>
                      <span class="text-slate-400">💣:{Map.get(p, :grenades, 3)}</span>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp normalize_wall(p1, p2) do
    if p1 <= p2, do: {p1, p2}, else: {p2, p1}
  end

  defp has_portal?(teleporters, pos) do
    Enum.any?(teleporters || [], fn
      {p1, p2} -> p1 == pos or p2 == pos
      [p1, p2] -> p1 == pos or p2 == pos
      _ -> false
    end)
  end

  defp has_pit?(pits, pos) do
    Enum.any?(pits || [], fn
      {x, y} -> {x, y} == pos
      %{"x" => x, "y" => y} -> {x, y} == pos
      [x, y] -> {x, y} == pos
      _ -> false
    end)
  end

  defp format_pos({x, y}), do: "#{x}, #{y}"
  defp format_pos(%{"x" => x, "y" => y}), do: "#{x}, #{y}"
  defp format_pos(_), do: "?, ?"
end
