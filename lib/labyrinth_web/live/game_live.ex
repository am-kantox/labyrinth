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
     |> assign(:post_its, post_its)}
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
      {:ok, engine, summary} ->
        {:noreply, maybe_handle_disorientation(socket, engine, summary)}

      {:error, :not_your_turn} ->
        {:noreply, put_flash(socket, :error, "It is not your turn yet! Please wait.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Action failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("pass_turn", _params, socket) do
    case GameServer.take_turn(socket.assigns.game_id, socket.assigns.player_id, :pass) do
      {:ok, engine, summary} ->
        {:noreply, maybe_handle_disorientation(socket, engine, summary)}

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
          {:ok, engine, summary} ->
            {:noreply, maybe_handle_disorientation(socket, engine, summary)}

          _ ->
            {:noreply, socket}
        end

      key == " " ->
        case GameServer.take_turn(socket.assigns.game_id, socket.assigns.player_id, :pass) do
          {:ok, engine, summary} ->
            {:noreply, maybe_handle_disorientation(socket, engine, summary)}

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

  defp maybe_handle_disorientation(socket, engine, summary) do
    if summary && summary.result in ["pit", "teleport"] do
      game_id = Map.get(socket.assigns, :game_id) || engine.id
      player_id = Map.get(socket.assigns, :player_id)
      existing_post_its = Map.get(socket.assigns, :post_its, [])

      if player_id do
        disorientation_title =
          "Disorientation Note: #{String.upcase(summary.result)} (Round #{engine.round_number})"

        color = if summary.result == "pit", do: "pink", else: "blue"

        new_post_it = %{
          game_id: game_id,
          player_id: player_id,
          title: disorientation_title,
          color: color,
          x_pos: 10 + length(existing_post_its) * 15,
          y_pos: 10 + length(existing_post_its) * 15,
          text:
            "Disoriented by #{summary.result}! Sketch local corridor layout and click 'Stick to Map' to overlay hints.",
          grid_marks: %{},
          is_stuck: true
        }

        case Games.save_post_it(new_post_it) do
          {:ok, saved} ->
            socket
            |> assign(:engine, engine)
            |> assign(:post_its, existing_post_its ++ [saved])
            |> put_flash(
              :info,
              "🌀 Disorientation! A new Post-It note popped up to help you reconstruct your path."
            )

          _ ->
            assign(socket, :engine, engine)
        end
      else
        assign(socket, :engine, engine)
      end
    else
      assign(socket, :engine, engine)
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
              class="px-3 py-2 bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-semibold rounded-lg border border-slate-700 transition-colors flex items-center gap-1.5"
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

              <div
                class="grid gap-1 bg-slate-950 p-3 rounded-xl border border-slate-800 shadow-inner"
                style={"grid-template-columns: repeat(#{@engine.width}, minmax(0, 1fr));"}
              >
                <%= for y <- 0..(@engine.height - 1) do %>
                  <%= for x <- 0..(@engine.width - 1) do %>
                    <% cell_pos = {x, y} %>
                    <% is_visited = MapSet.member?(visited_set, cell_pos) or reveal_full_map? %>
                    <% stuck_symbol = Map.get(stuck_marks_map, "#{x},#{y}") %>
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
                    <% wall_source = if(reveal_full_map?, do: @engine.walls, else: known_walls_set) %>
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

                    <div class={[
                      "w-10 h-10 sm:w-12 sm:h-12 rounded flex items-center justify-center text-sm relative transition-all border",
                      if(is_visited,
                        do: "bg-slate-900 border-slate-800",
                        else: "bg-slate-950/80 border-slate-900/50 opacity-40"
                      ),
                      if(is_me_here and me.status in [:active, :wounded, :stunned],
                        do: "ring-2 ring-amber-400 bg-amber-500/10"
                      ),
                      if(n_wall, do: "border-t-2 border-t-amber-600/80"),
                      if(s_wall, do: "border-b-2 border-b-amber-600/80"),
                      if(w_wall, do: "border-l-2 border-l-amber-600/80"),
                      if(e_wall, do: "border-r-2 border-r-amber-600/80"),
                      if(n_destroyed, do: "border-t-2 border-dashed border-t-orange-700/80"),
                      if(s_destroyed, do: "border-b-2 border-dashed border-b-orange-700/80"),
                      if(w_destroyed, do: "border-l-2 border-dashed border-l-orange-700/80"),
                      if(e_destroyed, do: "border-r-2 border-dashed border-r-orange-700/80")
                    ]}>
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
                            <span
                              class="text-base"
                              title={Enum.map_join(active_players_here, ", ", & &1.name)}
                            >
                              {if any_wounded?, do: "🩸👤", else: "👤"}
                            </span>
                          <% eliminated_players_here != [] -> %>
                            <span
                              class="text-base"
                              title={"Eliminated: #{Enum.map_join(eliminated_players_here, ", ", & &1.name)}"}
                            >💀</span>
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

          <%!-- Right Column: Telemetry Log, Roster & Interactive Post-It Hints (4 cols) --%>
          <div class="lg:col-span-4 space-y-6">
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
                      <span class="font-bold text-white">{p.name}</span>
                      <%= if p.is_bot do %>
                        <span class="text-[10px] bg-slate-800 text-amber-300 px-1.5 py-0.5 rounded font-mono">BOT</span>
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

            <%!-- Interactive Post-it Notes Canvas Panel --%>
            <div class="bg-slate-900 border border-slate-800 rounded-xl p-5 shadow-xl space-y-4">
              <div class="flex items-center justify-between border-b border-slate-800 pb-3">
                <h3 class="text-sm font-bold text-slate-100 flex items-center gap-2">
                  <.icon name="hero-document-duplicate" class="w-4 h-4 text-amber-400" />
                  Your Post-It Map Hints
                </h3>
                <div class="flex items-center gap-1">
                  <button
                    phx-click="add_post_it"
                    phx-value-color="yellow"
                    class="w-5 h-5 rounded bg-amber-300 hover:ring-2 hover:ring-white transition-all"
                    title="Add Yellow Post-It"
                  ></button>
                  <button
                    phx-click="add_post_it"
                    phx-value-color="pink"
                    class="w-5 h-5 rounded bg-pink-400 hover:ring-2 hover:ring-white transition-all"
                    title="Add Pink Post-It"
                  ></button>
                  <button
                    phx-click="add_post_it"
                    phx-value-color="green"
                    class="w-5 h-5 rounded bg-emerald-300 hover:ring-2 hover:ring-white transition-all"
                    title="Add Green Post-It"
                  ></button>
                  <button
                    phx-click="add_post_it"
                    phx-value-color="blue"
                    class="w-5 h-5 rounded bg-sky-300 hover:ring-2 hover:ring-white transition-all"
                    title="Add Blue Post-It"
                  ></button>
                </div>
              </div>

              <div class="space-y-4 max-h-[600px] overflow-y-auto pr-1">
                <%= if @post_its == [] do %>
                  <div class="p-6 text-center bg-slate-950/60 rounded-lg border border-dashed border-slate-800 text-slate-400 text-xs">
                    No Post-its drawn yet. Click a color button above to add a draft note!
                  </div>
                <% end %>

                <%= for post_it <- @post_its do %>
                  <% color_bg =
                    case post_it.color do
                      "pink" -> "bg-pink-300 text-slate-950"
                      "green" -> "bg-emerald-200 text-slate-950"
                      "blue" -> "bg-sky-200 text-slate-950"
                      _ -> "bg-amber-200 text-slate-950"
                    end %>

                  <div class={[
                    "rounded-xl p-4 shadow-lg border border-slate-700/50 space-y-3 relative transition-transform hover:-translate-y-0.5",
                    color_bg
                  ]}>
                    <div class="flex items-center justify-between border-b border-slate-950/20 pb-2">
                      <span class="font-bold text-xs uppercase tracking-wide truncate max-w-[150px]">{post_it.title}</span>
                      <div class="flex items-center gap-1.5">
                        <button
                          phx-click="toggle_stick_post_it"
                          phx-value-id={post_it.id}
                          class={[
                            "px-2 py-0.5 text-[10px] font-bold rounded transition-all flex items-center gap-1 shadow-sm border",
                            if(post_it.is_stuck,
                              do:
                                "bg-slate-950 text-amber-300 border-amber-400 font-extrabold ring-1 ring-amber-400",
                              else:
                                "bg-slate-900/30 text-slate-900 border-slate-800/40 hover:bg-slate-900/50"
                            )
                          ]}
                          title="Stick/Unstick this note's marks onto main game map"
                        >
                          📌 {if post_it.is_stuck, do: "Stuck to Map", else: "Stick to Map"}
                        </button>

                        <button
                          phx-click="delete_post_it"
                          phx-value-id={post_it.id}
                          class="text-slate-700 hover:text-rose-700 text-xs font-bold px-1"
                          title="Delete Note"
                        >
                          ✕
                        </button>
                      </div>
                    </div>

                    <%!-- Mini-Grid Sketch Canvas --%>
                    <div>
                      <span class="text-[10px] font-bold block mb-1 uppercase opacity-75">Mini-Grid Map Sketch (Stamp Symbols)</span>
                      <div class="grid grid-cols-5 gap-1 bg-slate-950/20 p-2 rounded border border-slate-950/30">
                        <%= for gy <- 0..4 do %>
                          <%= for gx <- 0..4 do %>
                            <% cell_key = "#{gx},#{gy}" %>
                            <% symbol = Map.get(post_it.grid_marks || %{}, cell_key) %>

                            <button
                              phx-click="toggle_post_it_mark"
                              phx-value-id={post_it.id}
                              phx-value-cell={cell_key}
                              phx-value-symbol="🧱"
                              class="w-6 h-6 rounded bg-white/40 hover:bg-white/80 border border-slate-900/20 flex items-center justify-center text-xs font-bold transition-colors"
                            >
                              {symbol || ""}
                            </button>
                          <% end %>
                        <% end %>
                      </div>

                      <%!-- Symbol Toolbar --%>
                      <div class="flex items-center gap-1 mt-2">
                        <%= for s <- ["🧱", "🚪", "💎", "🕳", "🌀", "👹", "❓"] do %>
                          <button
                            phx-click="toggle_post_it_mark"
                            phx-value-id={post_it.id}
                            phx-value-cell="0,0"
                            phx-value-symbol={s}
                            class="px-1.5 py-0.5 bg-white/50 hover:bg-white/90 text-xs rounded border border-slate-900/20"
                          >
                            {s}
                          </button>
                        <% end %>
                      </div>
                    </div>

                    <%!-- Text Note Area --%>
                    <div>
                      <span class="text-[10px] font-bold block mb-1 uppercase opacity-75">Exploration Notes</span>
                      <textarea
                        phx-blur="update_post_it_text"
                        phx-value-id={post_it.id}
                        class="w-full h-16 bg-white/40 border border-slate-950/20 rounded p-1.5 text-xs text-slate-950 focus:bg-white/80 focus:outline-none"
                        placeholder="Write wall hypotheses or sensory clues..."
                      >{post_it.text}</textarea>
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

  defp format_pos({x, y}), do: "#{x}, #{y}"
  defp format_pos(%{"x" => x, "y" => y}), do: "#{x}, #{y}"
  defp format_pos(_), do: "?, ?"
end
