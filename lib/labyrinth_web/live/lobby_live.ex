defmodule LabyrinthWeb.LobbyLive do
  use LabyrinthWeb, :live_view

  alias Labyrinth.Games
  alias Labyrinth.GameSupervisor
  alias Labyrinth.Prolog.Validator

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Labyrinth.PubSub, "lobby")
    end

    form = default_form()

    {:ok,
     socket
     |> assign(:page_title, "Labyrinth Lobby")
     |> assign(:form, form)
     |> assign(:prolog_status, nil)
     |> fetch_and_stream_games(:active, 1)}
  end

  @impl true
  def handle_event("select_tab", %{"tab" => tab_str}, socket) do
    tab = String.to_existing_atom(tab_str)
    {:noreply, fetch_and_stream_games(socket, tab, 1)}
  end

  @impl true
  def handle_event("next_page", _params, socket) do
    if socket.assigns.has_more do
      {:noreply,
       fetch_and_stream_games(socket, socket.assigns.active_tab, socket.assigns.page + 1)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("prev_page", _params, socket) do
    if socket.assigns.page > 1 do
      {:noreply,
       fetch_and_stream_games(socket, socket.assigns.active_tab, socket.assigns.page - 1)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("validate_prolog", params, socket) do
    width = String.to_integer(params["width"] || "10")
    height = String.to_integer(params["height"] || "10")
    pit_count = String.to_integer(params["pit_count"] || "3")
    teleport_count = String.to_integer(params["teleport_count"] || "1")
    wall_density = String.to_integer(params["wall_density"] || "70")

    {:ok, map_data} =
      Labyrinth.Game.Generator.generate_map(
        width: width,
        height: height,
        pit_count: pit_count,
        teleport_count: teleport_count,
        wall_density: wall_density
      )

    case Validator.validate_map(map_data) do
      {:ok, info} ->
        msg =
          "Prolog Engine Validated ✓ (Method: #{info[:method]}, Connectivity: #{trunc(info[:reachable_ratio] * 100)}%)"

        {:noreply, assign(socket, :prolog_status, {:ok, msg})}

      {:error, reason} ->
        {:noreply, assign(socket, :prolog_status, {:error, "Prolog Error: #{reason}"})}
    end
  end

  @impl true
  def handle_event("create_game", %{"game" => params}, socket) do
    name = params["name"]
    width = String.to_integer(params["width"] || "10")
    height = String.to_integer(params["height"] || "10")
    bot_count = String.to_integer(params["bot_count"] || "1")
    pit_count = String.to_integer(params["pit_count"] || "3")
    teleport_count = String.to_integer(params["teleport_count"] || "1")
    wall_density = String.to_integer(params["wall_density"] || "70")
    minotaur_enabled = Map.get(params, "minotaur_enabled", "true") in ["true", true]

    game_id = Ecto.UUID.generate()

    case GameSupervisor.start_game(
           game_id: game_id,
           name: name,
           width: width,
           height: height,
           bot_count: bot_count,
           pit_count: pit_count,
           teleport_count: teleport_count,
           wall_density: wall_density,
           minotaur_enabled: minotaur_enabled
         ) do
      {:ok, _pid} ->
        Phoenix.PubSub.broadcast(Labyrinth.PubSub, "lobby", :game_created)
        {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not create game: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info(:game_created, socket) do
    {:noreply, fetch_and_stream_games(socket, socket.assigns.active_tab, socket.assigns.page)}
  end

  defp fetch_and_stream_games(socket, tab, page) do
    {games, has_more} = Games.list_games_by_tab(tab, page, 30)

    socket
    |> assign(:active_tab, tab)
    |> assign(:page, page)
    |> assign(:has_more, has_more)
    |> stream(:games, games, reset: true)
  end

  defp default_form do
    to_form(
      %{
        "name" => "Labyrinth Expedition #{System.unique_integer([:positive])}",
        "width" => "10",
        "height" => "10",
        "bot_count" => "2",
        "pit_count" => "3",
        "teleport_count" => "5",
        "wall_density" => "70",
        "minotaur_enabled" => "true"
      },
      as: :game
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-6xl mx-auto space-y-8">
        <%!-- Hero Banner --%>
        <div class="bg-gradient-to-r from-slate-900 via-indigo-950 to-slate-900 rounded-2xl p-8 border border-indigo-900/40 shadow-2xl relative overflow-hidden">
          <div class="relative z-10 max-w-2xl">
            <h1 class="text-4xl font-extrabold text-amber-400 tracking-tight flex items-center gap-3">
              <span>🏰</span> LABYRINTH
            </h1>
            <p class="mt-3 text-slate-300 text-base leading-relaxed">
              Step into the unseen maze! Explore blindly guided only by sensory cues, map walls on your personal interactive post-it hints, locate the hidden treasure 💎, and escape before the Minotaur 👹 catches you.
            </p>
            <div class="mt-4 flex flex-wrap items-center gap-3">
              <span class="px-3 py-1 bg-amber-500/10 border border-amber-500/30 text-amber-300 text-xs font-semibold rounded-full flex items-center gap-1.5">
                <.icon name="hero-cpu-chip" class="w-4 h-4 text-amber-400" />
                Prolog Rule Validation Engine
              </span>
              <span class="px-3 py-1 bg-indigo-500/10 border border-indigo-500/30 text-indigo-300 text-xs font-semibold rounded-full flex items-center gap-1.5">
                <.icon name="hero-user-group" class="w-4 h-4 text-indigo-400" /> Multiplayer & AI Bots
              </span>
              <span class="px-3 py-1 bg-emerald-500/10 border border-emerald-500/30 text-emerald-300 text-xs font-semibold rounded-full flex items-center gap-1.5">
                <.icon name="hero-document-duplicate" class="w-4 h-4 text-emerald-400" />
                Draft Post-it Hints
              </span>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <%!-- Game Creation Form --%>
          <div class="lg:col-span-1 bg-slate-900 border border-slate-800 rounded-xl p-6 shadow-xl space-y-6">
            <div class="flex items-center justify-between border-b border-slate-800 pb-3">
              <h2 class="text-xl font-bold text-slate-100 flex items-center gap-2">
                <.icon name="hero-plus-circle" class="w-5 h-5 text-amber-400" /> Create New Labyrinth
              </h2>
            </div>

            <.form for={@form} id="create-game-form" phx-submit="create_game" class="space-y-4">
              <div>
                <label class="block text-xs font-medium text-slate-300 mb-1">Expedition Name</label>
                <.input
                  field={@form[:name]}
                  type="text"
                  class="w-full bg-slate-950 border-slate-700 text-white rounded-lg px-3 py-2 text-sm focus:border-amber-400 focus:ring-amber-400"
                />
              </div>

              <div class="grid grid-cols-2 gap-3">
                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Width (Cells)</label>
                  <.input
                    field={@form[:width]}
                    type="number"
                    min="5"
                    max="20"
                    class="w-full bg-slate-950 border-slate-700 text-white rounded-lg px-3 py-2 text-sm"
                  />
                </div>
                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Height (Cells)</label>
                  <.input
                    field={@form[:height]}
                    type="number"
                    min="5"
                    max="20"
                    class="w-full bg-slate-950 border-slate-700 text-white rounded-lg px-3 py-2 text-sm"
                  />
                </div>
              </div>

              <div class="grid grid-cols-4 gap-2">
                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Bots</label>
                  <.input
                    field={@form[:bot_count]}
                    type="number"
                    min="0"
                    max="4"
                    class="w-full bg-slate-950 border-slate-700 text-white rounded-lg px-2 py-2 text-sm"
                  />
                </div>
                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Pits</label>
                  <.input
                    field={@form[:pit_count]}
                    type="number"
                    min="1"
                    max="6"
                    class="w-full bg-slate-950 border-slate-700 text-white rounded-lg px-2 py-2 text-sm"
                  />
                </div>
                <div>
                  <label class="block text-xs font-medium text-slate-300 mb-1">Portals</label>
                  <.input
                    field={@form[:teleport_count]}
                    type="number"
                    min="0"
                    max="10"
                    class="w-full bg-slate-950 border-slate-700 text-white rounded-lg px-2 py-2 text-sm"
                  />
                </div>
                <div>
                  <label
                    class="block text-xs font-medium text-slate-300 mb-1"
                    title="Wall Density % (0=None, 100=Max)"
                  >Walls %</label>
                  <.input
                    field={@form[:wall_density]}
                    type="number"
                    min="0"
                    max="100"
                    class="w-full bg-slate-950 border-slate-700 text-white rounded-lg px-2 py-2 text-sm"
                  />
                </div>
              </div>

              <div class="flex items-center gap-2 pt-1">
                <.input
                  field={@form[:minotaur_enabled]}
                  type="checkbox"
                  class="rounded bg-slate-950 border-slate-700 text-amber-500 focus:ring-amber-400"
                />
                <label class="text-xs font-semibold text-slate-200 cursor-pointer select-none">
                  Include Roaming Minotaur 👹
                </label>
              </div>

              <div class="pt-2">
                <button
                  type="button"
                  phx-click="validate_prolog"
                  phx-value-width={@form[:width].value}
                  phx-value-height={@form[:height].value}
                  phx-value-pit_count={@form[:pit_count].value}
                  phx-value-teleport_count={@form[:teleport_count].value}
                  class="w-full py-2 px-3 bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs font-semibold rounded-lg border border-slate-700 flex items-center justify-center gap-1.5 transition-colors"
                >
                  <.icon name="hero-check-badge" class="w-4 h-4 text-emerald-400" />
                  Test Prolog Map Reachability
                </button>
              </div>

              <%= if @prolog_status do %>
                <% {status_kind, status_msg} = @prolog_status %>
                <div class={[
                  "p-3 rounded-lg text-xs font-mono border",
                  if(status_kind == :ok,
                    do: "bg-emerald-950/60 border-emerald-800 text-emerald-300",
                    else: "bg-rose-950/60 border-rose-800 text-rose-300"
                  )
                ]}>
                  {status_msg}
                </div>
              <% end %>

              <button
                type="submit"
                id="create-game-submit-btn"
                class="w-full py-3 bg-amber-500 hover:bg-amber-400 text-slate-950 font-bold text-sm rounded-lg shadow-lg shadow-amber-500/20 transition-all flex items-center justify-center gap-2"
              >
                <span>Generate & Launch Game</span>
                <.icon name="hero-arrow-right" class="w-4 h-4" />
              </button>
            </.form>
          </div>

          <%!-- Active Games List --%>
          <div class="lg:col-span-2 bg-slate-900 border border-slate-800 rounded-xl p-6 shadow-xl space-y-4">
            <div class="flex flex-wrap items-center justify-between border-b border-slate-800 pb-3 gap-3">
              <h2 class="text-xl font-bold text-slate-100 flex items-center gap-2">
                <.icon name="hero-rectangle-stack" class="w-5 h-5 text-indigo-400" /> Labyrinth Games
              </h2>

              <%!-- Tabs Header --%>
              <div class="flex items-center bg-slate-950 p-1 rounded-lg border border-slate-800 text-xs font-semibold">
                <button
                  phx-click="select_tab"
                  phx-value-tab="active"
                  class={[
                    "px-3 py-1.5 rounded-md transition-all flex items-center gap-1",
                    if(@active_tab == :active,
                      do: "bg-emerald-500 text-slate-950 font-bold shadow",
                      else: "text-slate-400 hover:text-slate-200"
                    )
                  ]}
                >
                  🟢 Active (&lt;10m)
                </button>
                <button
                  phx-click="select_tab"
                  phx-value-tab="stale"
                  class={[
                    "px-3 py-1.5 rounded-md transition-all flex items-center gap-1",
                    if(@active_tab == :stale,
                      do: "bg-amber-500 text-slate-950 font-bold shadow",
                      else: "text-slate-400 hover:text-slate-200"
                    )
                  ]}
                >
                  ⏳ Stale (&ge;10m)
                </button>
                <button
                  phx-click="select_tab"
                  phx-value-tab="finished"
                  class={[
                    "px-3 py-1.5 rounded-md transition-all flex items-center gap-1",
                    if(@active_tab == :finished,
                      do: "bg-purple-500 text-white font-bold shadow",
                      else: "text-slate-400 hover:text-slate-200"
                    )
                  ]}
                >
                  🏁 Finished
                </button>
              </div>
            </div>

            <div id="games-list" phx-update="stream" class="space-y-3">
              <div
                id="no-active-games"
                class="hidden only:block p-8 text-center bg-slate-950/50 rounded-xl border border-slate-800 text-slate-400 text-sm"
              >
                No {to_string(@active_tab)} games found in this category. Generate a new labyrinth to get started!
              </div>

              <div
                :for={{id, game} <- @streams.games}
                id={id}
                class="bg-slate-950 border border-slate-800 hover:border-slate-700 rounded-xl p-4 transition-all flex items-center justify-between group"
              >
                <div class="space-y-1">
                  <div class="flex items-center gap-2">
                    <h3 class="font-bold text-white group-hover:text-amber-400 transition-colors">
                      {game.name}
                    </h3>
                    <span class={[
                      "text-[10px] font-bold uppercase tracking-wider px-2 py-0.5 rounded-full border",
                      cond do
                        game.status == "in_progress" ->
                          "bg-emerald-500/10 border-emerald-500/30 text-emerald-400"

                        game.status == "finished" ->
                          "bg-purple-500/10 border-purple-500/30 text-purple-400"

                        true ->
                          "bg-amber-500/10 border-amber-500/30 text-amber-400"
                      end
                    ]}>
                      {game.status}
                    </span>
                  </div>
                  <div class="text-xs text-slate-400 flex items-center gap-3">
                    <span>Grid: {game.width}×{game.height}</span>
                    <span>•</span>
                    <span>Created {Calendar.strftime(game.inserted_at, "%H:%M:%S")}</span>
                    <%= if game.winner_name do %>
                      <span>•</span>
                      <span class="text-amber-300 font-semibold">Winner: {game.winner_name}</span>
                    <% end %>
                  </div>
                </div>

                <div class="flex items-center gap-2">
                  <%= if game.status != "finished" or @active_tab in [:active, :stale] do %>
                    <.link
                      navigate={~p"/games/#{game.id}"}
                      class="px-4 py-2 bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs rounded-lg shadow transition-colors flex items-center gap-1.5"
                    >
                      <.icon name="hero-play" class="w-3.5 h-3.5" />
                      <span>Join Game</span>
                    </.link>
                  <% end %>
                  <.link
                    navigate={~p"/history/#{game.id}"}
                    class="px-3 py-2 bg-slate-800 hover:bg-slate-700 text-slate-300 text-xs font-medium rounded-lg border border-slate-700 transition-colors flex items-center gap-1.5"
                  >
                    <.icon name="hero-clock" class="w-3.5 h-3.5 text-slate-400" />
                    <span>History</span>
                  </.link>
                </div>
              </div>
            </div>

            <%!-- Pagination Bar --%>
            <div class="flex items-center justify-between pt-3 border-t border-slate-800 text-xs font-mono text-slate-400">
              <span>Page {@page} ({to_string(@active_tab)})</span>
              <div class="flex items-center gap-2">
                <button
                  phx-click="prev_page"
                  disabled={@page <= 1}
                  class="px-3 py-1 bg-slate-800 hover:bg-slate-700 disabled:opacity-30 disabled:hover:bg-slate-800 text-white font-semibold rounded border border-slate-700 transition-colors"
                >
                  ◄ Prev 30
                </button>
                <button
                  phx-click="next_page"
                  disabled={not @has_more}
                  class="px-3 py-1 bg-slate-800 hover:bg-slate-700 disabled:opacity-30 disabled:hover:bg-slate-800 text-white font-semibold rounded border border-slate-700 transition-colors"
                >
                  Next 30 ►
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
