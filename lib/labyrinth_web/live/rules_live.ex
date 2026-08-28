defmodule LabyrinthWeb.RulesLive do
  use LabyrinthWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:current_scope, nil)
     |> assign(:page_title, "Game Rules & Manual - Labyrinth")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-5xl mx-auto space-y-10 py-4">
        <%!-- Header Banner --%>
        <div class="bg-slate-900 border border-slate-800 rounded-2xl p-8 shadow-2xl relative overflow-hidden">
          <div class="absolute -right-10 -bottom-10 opacity-10 text-9xl pointer-events-none select-none">
            📜
          </div>

          <div class="relative z-10 space-y-3">
            <div class="inline-flex items-center gap-2 px-3 py-1 bg-amber-500/10 border border-amber-500/30 text-amber-300 text-xs font-semibold rounded-full">
              <.icon name="hero-book-open" class="w-4 h-4" /> Comprehensive Expedition Manual
            </div>
            <h1 class="text-3xl sm:text-4xl font-extrabold text-white tracking-tight">
              Labyrinth: Tactical Exploration Rules & Guide
            </h1>
            <p class="text-slate-400 text-sm sm:text-base max-w-3xl leading-relaxed">
              Welcome to the underground Labyrinth! Explore a foggy procedural maze, discover hidden landmarks, manage tactical weapons & items, avoid deadly pit traps, outwit the roaming Minotaur 👹, claim the Treasure 💎, and escape to victory!
            </p>
          </div>
        </div>

        <%!-- Quick Navigation Bar --%>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3 text-xs font-semibold">
          <a
            href="#objective"
            class="p-3 bg-slate-900 hover:bg-slate-800 border border-slate-800 rounded-xl text-slate-300 hover:text-amber-300 transition-colors flex items-center justify-center gap-2 shadow"
          >
            <span>🎯 Objective & Basics</span>
          </a>
          <a
            href="#actions"
            class="p-3 bg-slate-900 hover:bg-slate-800 border border-slate-800 rounded-xl text-slate-300 hover:text-amber-300 transition-colors flex items-center justify-center gap-2 shadow"
          >
            <span>⚔️ Combat & Actions</span>
          </a>
          <a
            href="#landmarks"
            class="p-3 bg-slate-900 hover:bg-slate-800 border border-slate-800 rounded-xl text-slate-300 hover:text-amber-300 transition-colors flex items-center justify-center gap-2 shadow"
          >
            <span>🏰 Landmarks & Items</span>
          </a>
          <a
            href="#interface"
            class="p-3 bg-slate-900 hover:bg-slate-800 border border-slate-800 rounded-xl text-slate-300 hover:text-amber-300 transition-colors flex items-center justify-center gap-2 shadow"
          >
            <span>🖥️ UI & Post-Its</span>
          </a>
        </div>

        <%!-- Section 1: Objective & Turn Mechanics --%>
        <div
          id="objective"
          class="bg-slate-900 border border-slate-800 rounded-2xl p-6 sm:p-8 shadow-xl space-y-6"
        >
          <h2 class="text-xl font-bold text-amber-400 flex items-center gap-2.5 border-b border-slate-800 pb-3">
            <.icon name="hero-trophy" class="w-5 h-5" /> 1. Objective & Turn Mechanics
          </h2>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-6 text-sm text-slate-300">
            <div class="space-y-3 bg-slate-950/60 p-5 rounded-xl border border-slate-800">
              <h3 class="font-bold text-white text-base flex items-center gap-2">
                <span>🏆 Victory Condition</span>
              </h3>
              <p class="leading-relaxed text-slate-400">
                To win an expedition, an explorer must navigate the maze to locate the <strong class="text-amber-300">Treasure 💎</strong>, grab it, and reach the <strong class="text-emerald-400">Exit 🏁</strong>.
              </p>
              <ul class="space-y-1.5 list-disc list-inside text-xs text-slate-400">
                <li>
                  Treasure can be grabbed from regular cells, pit traps, or teleporter destinations.
                </li>
                <li>
                  If a player carrying the treasure is wounded or killed, they drop the treasure at their position.
                </li>
              </ul>
            </div>

            <div class="space-y-3 bg-slate-950/60 p-5 rounded-xl border border-slate-800">
              <h3 class="font-bold text-white text-base flex items-center gap-2">
                <span>⏱️ Turn Sequence & 30s Timer</span>
              </h3>
              <p class="leading-relaxed text-slate-400">
                Players take turns in round-robin order. Active human turns feature a <strong class="text-amber-300">30-second turn limit</strong>:
              </p>
              <ul class="space-y-1.5 list-disc list-inside text-xs text-slate-400">
                <li>
                  If 30 seconds elapse without a move, your turn is automatically <strong class="text-amber-300">PASSED</strong>.
                </li>
                <li>Executing an action before 30s resets the timer for the next explorer.</li>
              </ul>
            </div>
          </div>

          <%!-- Difficulty Modes --%>
          <div class="space-y-3 pt-2">
            <h3 class="font-bold text-white text-sm">🎮 Difficulty Scaling</h3>
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-3 text-xs">
              <div class="p-3.5 bg-emerald-950/30 border border-emerald-500/40 rounded-xl space-y-1">
                <span class="font-bold text-emerald-400 text-sm">🟢 Easy</span>
                <p class="text-slate-300">3 HP • 4 Bullets • 4 Grenades</p>
                <p class="text-slate-400 text-[11px]">Starts with 🪢 Rope • Low pit count</p>
              </div>
              <div class="p-3.5 bg-amber-950/30 border border-amber-500/40 rounded-xl space-y-1">
                <span class="font-bold text-amber-400 text-sm">🟡 Normal</span>
                <p class="text-slate-300">3 HP • 3 Bullets • 3 Grenades</p>
                <p class="text-slate-400 text-[11px]">Standard maze walls & roaming Minotaur</p>
              </div>
              <div class="p-3.5 bg-rose-950/30 border border-rose-500/40 rounded-xl space-y-1">
                <span class="font-bold text-rose-400 text-sm">🔴 Hard</span>
                <p class="text-slate-300">2 HP • 2 Bullets • 2 Grenades</p>
                <p class="text-slate-400 text-[11px]">Dense walls & faster Sprinting Minotaur</p>
              </div>
            </div>
          </div>
        </div>

        <%!-- Section 2: Combat & Actions --%>
        <div
          id="actions"
          class="bg-slate-900 border border-slate-800 rounded-2xl p-6 sm:p-8 shadow-xl space-y-6"
        >
          <h2 class="text-xl font-bold text-amber-400 flex items-center gap-2.5 border-b border-slate-800 pb-3">
            <.icon name="hero-fire" class="w-5 h-5" /> 2. Actions & Combat Rules
          </h2>

          <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
              <div class="flex items-center gap-2 text-white font-bold">
                <span class="text-lg">🚶</span>
                <span>Move (Cardinal Direction)</span>
              </div>
              <p class="text-xs text-slate-400 leading-relaxed">
                Attempt to step 1 cell North, South, East, or West. Walking into a stone wall produces a loud
                <strong class="text-slate-300">THUD</strong>
                sound echo, revealing the wall to your map without causing health damage.
              </p>
            </div>

            <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
              <div class="flex items-center gap-2 text-white font-bold">
                <span class="text-lg">🔫</span>
                <span>Gunshot (Cardinal Direction)</span>
              </div>
              <p class="text-xs text-slate-400 leading-relaxed">
                Fires a bullet up to 3 cells in a straight line. Kills the Minotaur 👹 on hit or wounds another explorer (-1 HP).
              </p>
              <div class="p-2 bg-rose-950/40 border border-rose-800/60 rounded text-[11px] text-rose-300">
                ⚠️ <strong>Self-Wounding Wall Ricochet:</strong>
                Shooting directly into a stone wall causes the bullet to ricochet back, dealing -1 HP damage to yourself!
              </div>
            </div>

            <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
              <div class="flex items-center gap-2 text-white font-bold">
                <span class="text-lg">💣</span>
                <span>Grenade (Cardinal Direction)</span>
              </div>
              <p class="text-xs text-slate-400 leading-relaxed">
                Lobs an explosive grenade up to 2 cells away. Explodes on impact, damaging any entities in the target cell and destroying internal stone walls to open new pathways!
              </p>
            </div>

            <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
              <div class="flex items-center gap-2 text-white font-bold">
                <span class="text-lg">⏳</span>
                <span>Pass (Skip Turn)</span>
              </div>
              <p class="text-xs text-slate-400 leading-relaxed">
                Skips your turn to hold your position. Useful when waiting for the Minotaur to pass or coordinating with team members.
              </p>
            </div>
          </div>
        </div>

        <%!-- Section 3: Landmarks & Items --%>
        <div
          id="landmarks"
          class="bg-slate-900 border border-slate-800 rounded-2xl p-6 sm:p-8 shadow-xl space-y-6"
        >
          <h2 class="text-xl font-bold text-amber-400 flex items-center gap-2.5 border-b border-slate-800 pb-3">
            <.icon name="hero-map-pin" class="w-5 h-5" /> 3. Landmarks, Traps & Items
          </h2>

          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 text-xs">
            <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
              <div class="flex items-center gap-2 text-rose-400 font-bold text-sm">
                <span>🏥 Hospital</span>
              </div>
              <p class="text-slate-400 leading-relaxed">
                Stepping onto the Hospital cell immediately heals wounded explorers back to full 3 HP (Healthy status).
              </p>
            </div>

            <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
              <div class="flex items-center gap-2 text-amber-400 font-bold text-sm">
                <span>⚔️ Arsenal</span>
              </div>
              <p class="text-slate-400 leading-relaxed">
                Restocks ammunition to full capacity (3 bullets & 3 grenades) and grants a
                <strong class="text-white">Rope 🪢</strong>
                if you don't have one!
              </p>
            </div>

            <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
              <div class="flex items-center gap-2 text-purple-400 font-bold text-sm">
                <span>🪢 Rope Item</span>
              </div>
              <p class="text-slate-400 leading-relaxed">
                Single-use climbing item. Automatically consumed when falling into a Pit trap to climb out safely without skipping a turn!
              </p>
            </div>

            <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
              <div class="flex items-center gap-2 text-red-400 font-bold text-sm">
                <span>🕳 Pit Traps</span>
              </div>
              <p class="text-slate-400 leading-relaxed">
                Falling into a pit trap inflicts <strong class="text-amber-300">:stunned</strong>
                status, forcing you to skip your next turn (unless saved by a Rope).
              </p>
            </div>

            <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
              <div class="flex items-center gap-2 text-indigo-400 font-bold text-sm">
                <span>🌀 Teleporters</span>
              </div>
              <p class="text-slate-400 leading-relaxed">
                Paired portal cells that instantly warp explorers across distant sections of the labyrinth.
              </p>
            </div>

            <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
              <div class="flex items-center gap-2 text-red-500 font-bold text-sm">
                <span>👹 The Minotaur</span>
              </div>
              <p class="text-slate-400 leading-relaxed">
                Roams the maze towards the nearest explorer. Attacking an explorer deals 1 HP damage (wounding them). Minotaur sprints 2 cells/round when unseen for $>3$ turns!
              </p>
            </div>
          </div>
        </div>

        <%!-- Section 4: Interface & Post-Its --%>
        <div
          id="interface"
          class="bg-slate-900 border border-slate-800 rounded-2xl p-6 sm:p-8 shadow-xl space-y-6"
        >
          <h2 class="text-xl font-bold text-amber-400 flex items-center gap-2.5 border-b border-slate-800 pb-3">
            <.icon name="hero-computer-desktop" class="w-5 h-5" />
            4. Interface Features & Post-It Map Pinning
          </h2>

          <div class="space-y-4 text-xs sm:text-sm text-slate-300">
            <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
              <h3 class="font-bold text-white text-sm">
                📌 Post-It Fragment Pinning for Other Explorers
              </h3>
              <p class="text-slate-400 leading-relaxed">
                The <strong class="text-amber-300">Explorer Expedition Post-Its</strong>
                sidebar lists all other human players and bots in the expedition. Clicking
                <strong class="text-amber-400">📌 Pin Active Fragment</strong>
                puts the interface in Pin Mode:
              </p>
              <ul class="list-disc list-inside text-slate-400 space-y-1 text-xs">
                <li>
                  Click any cell on the main maze grid to anchor that explorer's relative origin <strong class="text-slate-200">(0, 0)</strong>.
                </li>
                <li>
                  The pinned Post-It note overlays that explorer's visited cells, discovered walls, and landmarks directly onto your map view with distinct color themes!
                </li>
              </ul>
            </div>

            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
                <h4 class="font-bold text-white text-xs flex items-center gap-2">
                  <span>🔊 Procedural Web Audio API</span>
                </h4>
                <p class="text-xs text-slate-400 leading-relaxed">
                  Real-time synthesized audio for footsteps, gunshots, explosions, and Minotaur roars. Sound echoes travel across corridors to alert nearby explorers of combat activity.
                </p>
              </div>

              <div class="p-4 bg-slate-950/60 border border-slate-800 rounded-xl space-y-2">
                <h4 class="font-bold text-white text-xs flex items-center gap-2">
                  <span>💬 Real-Time In-Game Chat</span>
                </h4>
                <p class="text-xs text-slate-400 leading-relaxed">
                  Communicate with team members in real-time using the PubSub chat widget on the right sidebar to share coordinates and landmark locations.
                </p>
              </div>
            </div>
          </div>
        </div>

        <%!-- Footer Back Button --%>
        <div class="flex items-center justify-between pt-4 border-t border-slate-800">
          <.link
            navigate={~p"/"}
            class="px-5 py-2.5 bg-amber-500 hover:bg-amber-400 text-slate-950 font-bold text-xs rounded-lg shadow-lg shadow-amber-500/20 transition-all flex items-center gap-2"
          >
            <.icon name="hero-arrow-left" class="w-4 h-4" /> Return to Lobby
          </.link>

          <span class="text-xs text-slate-500 font-mono">Labyrinth v1.0 • Tactical Rules</span>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
