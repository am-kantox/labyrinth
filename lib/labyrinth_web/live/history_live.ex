defmodule LabyrinthWeb.HistoryLive do
  use LabyrinthWeb, :live_view

  alias Labyrinth.Games

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    game = Games.get_game(game_id)
    turns = Games.list_turns_for_game(game_id)

    {:ok,
     socket
     |> assign(:page_title, "Labyrinth History - #{if game, do: game.name, else: "Replay"}")
     |> assign(:game, game)
     |> assign(:turns, turns)
     # 0 to length(turns)
     |> assign(:current_step, 0)
     |> assign(:playing, false)}
  end

  @impl true
  def handle_event("set_step", %{"step" => step_str}, socket) do
    step = String.to_integer(step_str)
    max_step = length(socket.assigns.turns)
    clamped_step = max(0, min(step, max_step))

    {:noreply, assign(socket, :current_step, clamped_step)}
  end

  @impl true
  def handle_event("toggle_play", _params, socket) do
    if socket.assigns.playing do
      {:noreply, assign(socket, :playing, false)}
    else
      Process.send_after(self(), :auto_step, 800)
      {:noreply, assign(socket, :playing, true)}
    end
  end

  @impl true
  def handle_info(:auto_step, socket) do
    if socket.assigns.playing do
      max_step = length(socket.assigns.turns)
      next_step = socket.assigns.current_step + 1

      if next_step <= max_step do
        Process.send_after(self(), :auto_step, 800)
        {:noreply, assign(socket, :current_step, next_step)}
      else
        {:noreply, assign(socket, :playing, false)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto space-y-6">
        <%= if @game == nil do %>
          <div class="p-8 text-center bg-slate-900 border border-slate-800 rounded-xl text-slate-400">
            Game history not found.
          </div>
        <% else %>
          <% max_steps = length(@turns) %>
          <% current_turn = if(@current_step > 0, do: Enum.at(@turns, @current_step - 1), else: nil) %>

          <%!-- Header --%>
          <div class="bg-slate-900 border border-slate-800 rounded-xl p-5 shadow-lg flex flex-wrap items-center justify-between gap-4">
            <div>
              <h1 class="text-2xl font-bold text-white tracking-tight flex items-center gap-2">
                <span>📜</span> Turn-by-Turn History: {@game.name}
              </h1>
              <p class="text-xs text-slate-400 mt-1">
                Grid: {@game.width}×{@game.height} • Total Recorded Turns: {max_steps} • Winner: {@game.winner_name ||
                  "N/A"}
              </p>
            </div>

            <.link
              navigate={~p"/games/#{@game.id}"}
              class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-xs rounded-lg shadow transition-colors flex items-center gap-1.5"
            >
              <.icon name="hero-arrow-left" class="w-4 h-4" /> Return to Game
            </.link>
          </div>

          <%!-- Replay Controls Bar --%>
          <div class="bg-slate-900 border border-slate-800 rounded-xl p-5 shadow-xl space-y-4">
            <div class="flex flex-wrap items-center justify-between gap-4">
              <div class="flex items-center gap-2">
                <button
                  phx-click="set_step"
                  phx-value-step="0"
                  class="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-bold rounded border border-slate-700"
                >
                  ⏮ First
                </button>
                <button
                  phx-click="set_step"
                  phx-value-step={@current_step - 1}
                  class="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-bold rounded border border-slate-700"
                >
                  ◀ Prev
                </button>
                <button
                  phx-click="toggle_play"
                  class={[
                    "px-4 py-1.5 text-xs font-bold rounded shadow transition-all flex items-center gap-1",
                    if(@playing,
                      do: "bg-rose-600 text-white",
                      else: "bg-amber-500 text-slate-950 hover:bg-amber-400"
                    )
                  ]}
                >
                  {if @playing, do: "⏸ Pause", else: "▶ Auto Play"}
                </button>
                <button
                  phx-click="set_step"
                  phx-value-step={@current_step + 1}
                  class="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-bold rounded border border-slate-700"
                >
                  Next ▶
                </button>
                <button
                  phx-click="set_step"
                  phx-value-step={max_steps}
                  class="px-3 py-1.5 bg-slate-800 hover:bg-slate-700 text-slate-200 text-xs font-bold rounded border border-slate-700"
                >
                  Last ⏭
                </button>
              </div>

              <div class="text-xs text-slate-300 font-mono">
                Step <span class="text-amber-400 font-bold">{@current_step}</span> of {max_steps}
              </div>
            </div>

            <div>
              <input
                type="range"
                min="0"
                max={max_steps}
                value={@current_step}
                phx-change="set_step"
                name="step"
                class="w-full accent-amber-400 cursor-pointer"
              />
            </div>
          </div>

          <%!-- Replay Display: Map State & Current Turn Info --%>
          <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
            <%!-- Map View (8 cols) --%>
            <div class="lg:col-span-8 bg-slate-900 border border-slate-800 rounded-2xl p-6 shadow-2xl flex flex-col items-center justify-center">
              <div class="mb-3 text-xs text-slate-400 flex items-center justify-between w-full">
                <span>🏰 Full Master Map at Step {@current_step}</span>
                <%= if current_turn do %>
                  <span class="text-amber-300 font-semibold font-mono">Turn #{current_turn.turn_number}: {current_turn.player_name} ({current_turn.action_type})</span>
                <% end %>
              </div>

              <% walls = parse_walls_from_map(@game.map_data["walls"] || []) %>
              <% entrance = map_to_tuple(@game.map_data["entrance"]) %>
              <% exit_cell = map_to_tuple(@game.map_data["exit"]) %>
              <% treasure = map_to_tuple(@game.map_data["treasure"]) %>
              <% minotaur = map_to_tuple(@game.map_data["minotaur"]) %>
              <% pits = Enum.map(@game.map_data["pits"] || [], &map_to_tuple/1) %>

              <div
                class="grid gap-1 bg-slate-950 p-3 rounded-xl border border-slate-800 shadow-inner"
                style={"grid-template-columns: repeat(#{@game.width}, minmax(0, 1fr));"}
              >
                <%= for y <- 0..(@game.height - 1) do %>
                  <%= for x <- 0..(@game.width - 1) do %>
                    <% cell_pos = {x, y} %>

                    <% is_active_pos =
                      (current_turn != nil and current_turn.position_after) &&
                        current_turn.position_after["x"] == x && current_turn.position_after["y"] == y %>
                    <% is_before_pos =
                      (current_turn != nil and current_turn.position_before) &&
                        current_turn.position_before["x"] == x &&
                        current_turn.position_before["y"] == y %>

                    <% n_wall = MapSet.member?(walls, normalize_wall(cell_pos, {x, y - 1})) or y == 0 %>
                    <% s_wall =
                      MapSet.member?(walls, normalize_wall(cell_pos, {x, y + 1})) or
                        y == @game.height - 1 %>
                    <% w_wall = MapSet.member?(walls, normalize_wall(cell_pos, {x - 1, y})) or x == 0 %>
                    <% e_wall =
                      MapSet.member?(walls, normalize_wall(cell_pos, {x + 1, y})) or
                        x == @game.width - 1 %>

                    <div class={[
                      "w-10 h-10 sm:w-12 sm:h-12 rounded flex items-center justify-center text-sm relative transition-all border bg-slate-900 border-slate-800",
                      if(is_active_pos, do: "ring-2 ring-amber-400 bg-amber-500/20"),
                      if(is_before_pos and not is_active_pos,
                        do: "ring-1 ring-slate-400 bg-slate-800/80"
                      ),
                      if(n_wall, do: "border-t-2 border-t-amber-600/80"),
                      if(s_wall, do: "border-b-2 border-b-amber-600/80"),
                      if(w_wall, do: "border-l-2 border-l-amber-600/80"),
                      if(e_wall, do: "border-r-2 border-r-amber-600/80")
                    ]}>
                      <%= cond do %>
                        <% is_active_pos -> %>
                          <span class="text-base font-bold animate-bounce">👤</span>
                        <% cell_pos == minotaur -> %>
                          <span class="text-lg">👹</span>
                        <% cell_pos == entrance -> %>
                          <span class="text-xs font-bold text-emerald-400">🚪</span>
                        <% cell_pos == exit_cell -> %>
                          <span class="text-xs font-bold text-purple-400">🏁</span>
                        <% cell_pos == treasure -> %>
                          <span class="text-base">💎</span>
                        <% cell_pos in pits -> %>
                          <span class="text-base">🕳</span>
                        <% true -> %>
                          <span class="text-[9px] text-slate-700 font-mono">{x},{y}</span>
                      <% end %>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>

            <%!-- Turn Summary Card & Event List (4 cols) --%>
            <div class="lg:col-span-4 space-y-6">
              <%= if current_turn do %>
                <div class="bg-slate-900 border border-slate-800 rounded-xl p-5 shadow-xl space-y-3">
                  <h3 class="text-sm font-bold text-amber-400 flex items-center gap-2">
                    <.icon name="hero-information-circle" class="w-4 h-4" />
                    Turn #{current_turn.turn_number} Summary
                  </h3>

                  <div class="space-y-2 text-xs text-slate-300 font-mono">
                    <div class="flex justify-between border-b border-slate-800 pb-1">
                      <span class="text-slate-400">Player:</span>
                      <span class="font-bold text-white">{current_turn.player_name}</span>
                    </div>
                    <div class="flex justify-between border-b border-slate-800 pb-1">
                      <span class="text-slate-400">Action:</span>
                      <span class="font-bold text-amber-300 uppercase">{current_turn.action_type} {current_turn.direction}</span>
                    </div>
                    <div class="flex justify-between border-b border-slate-800 pb-1">
                      <span class="text-slate-400">Result:</span>
                      <span class="font-bold text-emerald-400">{current_turn.result}</span>
                    </div>
                  </div>

                  <%= if current_turn.sound_effects != [] do %>
                    <div class="pt-2">
                      <span class="text-[10px] font-bold text-slate-400 block mb-1 uppercase">Sensory Echoes</span>
                      <ul class="space-y-1 text-xs text-indigo-300 font-mono bg-slate-950 p-2 rounded border border-slate-800">
                        <%= for echo <- current_turn.sound_effects do %>
                          <li>🔊 {echo}</li>
                        <% end %>
                      </ul>
                    </div>
                  <% end %>
                </div>
              <% end %>

              <div class="bg-slate-900 border border-slate-800 rounded-xl p-5 shadow-xl space-y-3 max-h-96 overflow-y-auto">
                <h3 class="text-sm font-bold text-slate-200">Full Game Log History</h3>
                <div class="space-y-2">
                  <%= for {turn, idx} <- Enum.with_index(@turns, 1) do %>
                    <button
                      phx-click="set_step"
                      phx-value-step={idx}
                      class={[
                        "w-full text-left p-2 rounded text-xs font-mono border transition-colors flex items-center justify-between",
                        if(@current_step == idx,
                          do: "bg-amber-500/20 border-amber-400 text-amber-300",
                          else: "bg-slate-950 border-slate-800 text-slate-300 hover:bg-slate-800"
                        )
                      ]}
                    >
                      <span>#{turn.turn_number}. {turn.player_name} ({turn.action_type})</span>
                      <span class="text-[10px] text-slate-400">{turn.result}</span>
                    </button>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp parse_walls_from_map(walls_list) do
    walls_list
    |> Enum.map(fn %{"x1" => x1, "y1" => y1, "x2" => x2, "y2" => y2} ->
      normalize_wall({x1, y1}, {x2, y2})
    end)
    |> MapSet.new()
  end

  defp map_to_tuple(%{"x" => x, "y" => y}), do: {x, y}
  defp map_to_tuple(_), do: {0, 0}

  defp normalize_wall(p1, p2) do
    if p1 <= p2, do: {p1, p2}, else: {p2, p1}
  end
end
