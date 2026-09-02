# Labyrinth

**Labyrinth** (also known as *"Hunt for the Minotaur"*) is a multi-user, tactical turn-based exploration game built with **Elixir**, **Phoenix LiveView**, **Phoenix Presence**, **Finitomata** state machine orchestration, and **Prolog** logic validation powered by Robert Virding's `:erlog` Erlang engine.

Players explore a hidden, unseen maze step-by-step under fog-of-war conditions. Guided by Game Master (GM) feedback, spatial auditory echoes, and custom draftable Post-It notes, players maneuver through corridors, demolish internal walls with grenades, recover at medical sanctuaries, restock weapons at armories, locate the hidden treasure, and escape before rival explorers or the roaming Minotaur eliminate them.

---

## Overview & Core Concept

In Labyrinth, the maze structure is hidden from explorers. Only the Game Master (GM) has visibility over the complete map layout, active player positions, and Minotaur movements. 

Players navigate blindly, receiving positional logs and directionally muffled auditory feedback after every turn. To survive and conquer the maze, players must synthesize sensory clues, mark suspected layout paths on interactive Post-It notes, manage ammunition and explosives, and track rival explorers or AI computer bots across the labyrinth grid.

---

## Architecture & Technology Stack

The application is built on the Erlang OTP ecosystem using Phoenix v1.8 and a decoupled state architecture:

* **Elixir & Phoenix LiveView (v1.8):** Delivers real-time reactive UI updates, dynamic map renderings, and client-side hotkey handling via co-located hooks without full page reloads.
* **Phoenix Presence:** Manages active player lobbies, session connection states, and real-time room rosters.
* **OTP GenServer & DynamicSupervisor:** Every active game runs in an isolated GenServer process managed by `Labyrinth.GameSupervisor` and registered via `Labyrinth.GameRegistry`.
* **Finitomata State Machine (`Labyrinth.Game.TurnFSM`):** Enforces deterministic state transitions (`:lobby` -> `:awaiting_human` -> `:executing_bot` -> `:game_over`) and guarantees stall-free bot turn progression.
* **Prolog Verification Engine (`Labyrinth.Prolog.Validator`):** Executes Robert Virding's `:erlog` Erlang Prolog interpreter with fallback graph reachability analysis and SWI-Prolog (`swipl`) CLI execution to validate maze solvability and reachability rules.
* **PostgreSQL & Ecto:** Stores persistent game definitions, step-by-step turn audit records (`turns`), and player draft notes (`post_its`).
* **Tailwind CSS v4:** Styled using Tailwind CSS v4 source imports and modern CSS utility classes.

---

## Game Objective & Mechanics

### Exploration & Fog of War
* **Explorer View:** Displays only visited cells, known bumped walls, player status, and held inventory. Unexplored tiles remain hidden in fog of war.
* **GM View:** Toggleable master inspector view revealing all walls, traps, landmarks, active players, and the Minotaur.

### Player Attributes & Statuses
* **Health (❤):** Players start with 3 HP in Healthy status (🤠).
* **Wounded (🩸):** Taking gunshot damage reduces health to 2/3 HP or 1/3 HP, changing status to Wounded (🩸).
* **Eliminated (💀):** Reaching 0 HP eliminates the player from the game, dropping any held treasure at their current cell.
* **Stunned (🕳):** Falling into a pit stuns the player, forcing them to skip their next turn.
* **Escaped (🏆):** Carrying the treasure to the exit cell wins the game and updates status to Escaped (🏆).

### Inventory & Resources
* **Bullets (🔫):** 3 maximum. Used to fire ranged gunshots up to 3 cells in a cardinal direction.
* **Grenades (💣):** 3 maximum. Used to demolish internal wall segments, creating new tactical paths. Outer boundary walls are indestructible.

### Map Landmarks & Entities
* **Entrance (🚪):** The starting point where players enter the labyrinth grid.
* **Exit (🏁):** The target destination required to escape after retrieving the treasure.
* **Treasure (💎):** The primary objective cell. Must be collected and carried to the Exit (🏁) to win.
* **Hospital (🏥):** Stepping onto this sanctuary cell fully restores health to Healthy status (🤠, 3/3 HP).
* **Arsenal (⚔️):** Stepping onto this armory cell fully reloads Bullets (🔫 3/3) and Grenades (💣 3/3).
* **Pit (🕳):** A dangerous pit trap that stuns explorers for 1 turn upon entry.
* **Teleporter (🌀):** Paired portal cells that instantly warp players across the maze.
* **Minotaur (👹):** Optional roaming monster that stalks the nearest explorer after each round of player turns.

---

## Turn Actions & Spatial Auditory Feedback

On their turn, a player may execute one of the following actions:

1. **Move (🚶):** Step North, South, West, or East. Attempting to walk into a wall results in a bumped wall notification and ends the turn without position change.
2. **Shoot (🎯):** Fire a gunshot in a target direction up to 3 cells in a straight line (`E` hotkey). Hits damage rival players or Minotaur, wall impacts stop the bullet, and missed shots travel full range (💨).
3. **Grenade (💣):** Throw an explosive grenade (`G` hotkey) at an adjacent wall segment to demolish it (🧱).
4. **Pass:** Skip the current turn (`Spacebar`).

### Sensory Sound Propagation
Actions generate spatial sound echoes that notify nearby players within a 3-cell radius in their GM log:
* **Footsteps:** *“Footsteps heard from South”*
* **Gunshots:** *“A gunshot echoed from North”*
* **Explosions:** *“Massive Explosion! Wall Demolished from West”*

---

## The Minotaur & AI Computer Bots

### The Roaming Minotaur (👹)
* **Configuration:** Can be enabled or disabled during game creation.
* **Movement:** Moves 1 cell closer to the nearest player at the conclusion of each full round of player turns.
* **Stink Perception (🦨):** When an explorer comes within a 2-cell radius of the Minotaur, a sensory warning banner is displayed: `🦨 SENSORY WARNING: You smelled the Minotaur's foul stink wafting nearby!`.
* **Elimination:** If the Minotaur enters a cell occupied by a player, that explorer is immediately eliminated (💀) and drops any held treasure.

### AI Computer Bots (🤖)
* **Autonomous Decision Engine (`Labyrinth.Game.BotAI`):** Bots navigate under fog-of-war constraints using Breadth-First Search (BFS).
* **Behavior Priority:**
  1. If carrying the treasure (💎), compute the shortest BFS path to the Exit (🏁) using known wall memory.
  2. If an opponent or Minotaur is visible in a straight line-of-sight within range, fire bullets (🔫).
  3. Otherwise, explore unvisited adjacent cells.

---

## Interactive Post-It Notes & Bot Snapshot Overlay

### Post-It Note Drafting
Players can create draggable, color-coded Post-It notes on their interface to draft notes, mark suspected wall locations, and keep track of relative movements.

### Bot Fragment Tracking & Pinning (📌)
* **Relative Coordinate Sub-Grids:** AI bots track their movements, wall impacts, and discovered features on a personal relative coordinate system originating at `(0, 0)`. Each bot is assigned a distinct theme color.
* **Snapshot Pinning (📌):** Players can click **Pin Active Fragment** on a bot's Post-It card and select a cell `{X, Y}` on the main map to anchor its explored fragment.
* **Fragment Reset:** Pinning locks a static map snapshot overlay onto the main map board (projecting badges like `📌1 🕳`, `📌2 🌀`, `💎💀`) and resets the bot's live tracking to a fresh relative fragment starting at `(0, 0)`.

---

## Prolog Logic & Map Solvability Engine

Maze reachability and structural validity are verified using Prolog logic rules located in `priv/prolog/labyrinth_validator.pl` via `Labyrinth.Prolog.Validator`.

### Solvability Rules & Constraints
* Valid path exists from Entrance (🚪) to Treasure (💎).
* Valid path exists from Entrance (🚪) to Hospital (🏥).
* Valid path exists from Entrance (🚪) to Arsenal (⚔️).
* Valid path exists from Treasure (💎) to Exit (🏁).
* Valid path exists directly from Entrance (🚪) to Exit (🏁).
* Non-blocked cells must maintain continuous graph connectivity with a minimum reachability ratio of 85% (`>= 0.85`), preventing isolated dead zones.

### Execution Strategy
1. **Primary Runtime:** Robert Virding's `:erlog` OTP Erlang interpreter evaluates Prolog facts dynamically.
2. **Secondary Engine:** Internal graph adjacency BFS verification validates reachability ratios.
3. **CLI Fallback:** SWI-Prolog (`swipl`) system CLI execution is invoked if available.

---

## Turn Replay & History System

Every action, move, bullet shot, explosion, and sound echo is persisted to PostgreSQL in the `turns` database table.

Navigating to `/history/:id` for any past or active game unlocks the replay interface:
* **Step Slider:** Scrub forward and backward through turn progression step by step.
* **Auto Play:** Automated playback of all turn events.
* **Dual View:** Side-by-side display of historical player log feeds alongside full GM Master Map state progression.

---

## Keyboard Controls & Hotkeys

| Key | Action |
| :--- | :--- |
| **`W`** / **`Up Arrow`** | Move / Target **North** |
| **`S`** / **`Down Arrow`** | Move / Target **South** |
| **`A`** / **`Left Arrow`** | Move / Target **West** |
| **`D`** / **`Right Arrow`** | Move / Target **East** |
| **`E`** | Toggle **Shoot** Mode (🎯 Fire Pistol) |
| **`G`** | Toggle **Grenade** Mode (💣 Demolish Wall) |
| **`Spacebar`** | **Pass** Turn |

---

---

## 🚀 Game Improvements & Feature Upgrades

* **🎮 Scalable Difficulty Modes (`Easy`, `Normal`, `Hard`):** Scaled grid sizing, Minotaur counts, starting HP, and resource loads.
* **🪢 Tactical Items (`Torch`, `Shotgun`, `Rope`):** 
  * **Torch:** Expands active line-of-sight radius to 2 cells.
  * **Shotgun:** Fires 3-cell cone blasts.
  * **Rope:** Automatically consumed upon stepping into a Pit to climb out without losing a turn.
* **👹 Minotaur Sprint & Ambush:** Minotaur accelerates to 2 cells/round when unseen for >3 turns.
* **🤖 Smart Bot AI Memory:** Bots remember Hospital and Arsenal landmark positions, returning to heal or reload when low on resources.
* **🔊 Web Audio API Sound Synthesizer:** Zero-dependency, zero-latency client-side sound effects for footsteps, gunshots, explosions, and Minotaur roars using Web Audio API JS hook (`push_event`).
* **🌫️ Memory Fog Rendering:** Visually differentiates active line-of-sight cells from previously visited "memory fog" cells.
* **💬 Real-Time In-Game Chat & GM Event Injection:** Embedded live player chat channels and GM event dashboard.
* **⚡ OTP & BFS Performance:** Optimized $O(N^2)$ BFS queue operations to $O(V+E)$ with Erlang `:queue` and unified spatial utilities (`Labyrinth.MapUtils`).

---

## Setup & Installation

### Prerequisites
* **Elixir:** `~> 1.17`
* **Erlang/OTP:** `26+`
* **PostgreSQL:** Running locally (default user: `postgres`)
* **SWI-Prolog (`swipl`):** (Optional fallback engine)

### Setup Steps

1. **Clone repository & fetch Elixir dependencies:**
   ```bash
   mix deps.get
   ```

2. **Setup and migrate database:**
   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

3. **Build asset bundles:**
   ```bash
   mix assets.build
   ```

4. **Start Phoenix server:**
   ```bash
   mix phx.server
   ```

5. Access the application in your browser at **[http://localhost:4000](http://localhost:4000)**.

---

## Testing & Quality Assurance

Run the test suite and project verification using the mix aliases:

* **Execute precommit suite:**
  ```bash
  mix precommit
  ```

* **Run ExUnit test suite directly:**
  ```bash
  mix test
  ```

---

## Deployment

labyrinth runs as a systemd-supervised Mix release on the same shared AWS
EC2 instance as `yokerhood.com` (the `maze.yokerhood.com` subdomain),
bound to loopback only (`127.0.0.1:3060`). `.github/workflows/deploy.yml`
builds and ships a new release on every push to `main`, using the
app-agnostic `ops/scripts/deploy-release.sh` (atomic symlink switch,
restart, health-check-with-rollback) shared with that repository. Ecto
migrations run automatically on every restart via `ExecStartPre` in
`systemd/labyrinth.service` (see `lib/labyrinth/release.ex`) -- no
separate migration step in the workflow.

The reverse proxy (NGINX, TLS via certbot) and DNS both live in the
`yokerhood.com` repository (`ops/nginx/yokerhood.conf`), since they're
shared infrastructure for the whole `yokerhood.com` property, not
labyrinth-specific. `systemd/labyrinth.service` and
`systemd/labyrinth.env.example` here document the actual unit and its
required environment variables (`SECRET_KEY_BASE`, `PHX_HOST`, `PORT`,
`DATABASE_URL`); `systemd/labyrinth-pgdump.*` documents the nightly
`pg_dump` backup timer for its Postgres database, the only stateful
component of the whole property.

Requires these GitHub Actions repository secrets: `DEPLOY_SSH_HOST`,
`DEPLOY_SSH_USER`, `DEPLOY_SSH_PRIVATE_KEY`, `DEPLOY_SSH_KNOWN_HOSTS`.
