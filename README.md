# 🏰 Labyrinth — Multiuser Tactical Strategy Game

**Labyrinth** (also known as *"Hunt for the Minotaur"*) is a tactical turn-based exploration game built with **Elixir**, **Phoenix LiveView**, **Phoenix Presence**, **Finitomata** state machine flow, and **Prolog** logic validation powered by Robert Virding's [`erlog`](https://github.com/rvirding/erlog) engine.

Players explore a hidden, unseen maze step-by-step, receiving Game Master (GM) feedback and auditory echoes, drafting hypothetical wall layouts on interactive **Post-It notes**, demolishing internal walls with **Grenades 💣**, healing at the **Hospital 🏥**, restocking at the **Arsenal ⚔️**, locating the secret **Treasure 💎**, and escaping through the **Exit 🚪** before rival explorers or the roaming **Minotaur 👹** eliminate them.

---

## 🎯 Game Objective & Mechanics

1. **Blind Exploration & Fog-of-War:**
   * Only the **Game Master (GM)** sees the full map layout.
   * Players see only their own visited path and bumped walls.
   * Toggle **"GM View"** at any time to inspect the secret master map, active players, and the Minotaur.

2. **Turn Actions:**
   * **🚶 Move:** Declare a direction: `North` (▲ / `W`), `South` (▼ / `S`), `West` (◄ / `A`), or `East` (► / `D`).
   * **🎯 Shoot:** Fire a ranged gunshot up to 3 cells in a straight line (`E` hotkey). Shots hit walls or deal damage to rival explorers.
   * **💣 Grenade:** Throw a grenade (`G` hotkey) to **demolish internal wall segments**, creating new strategic corridors! *(Note: The outer boundary surrounding the entire labyrinth is indestructible).*
   * **⏩ Pass:** Skip your current turn (`Spacebar`).

3. **Special Map Landmarks:**
   * **🏥 Hospital / Medical Sanctuary:** Stepping onto the Hospital cell fully heals a **Wounded 🩸** player back to **Healthy 🤠 (3/3 HP)**.
   * **⚔️ Arsenal / Armory:** Stepping onto the Arsenal cell fully reloads both **Bullets (3/3 🔫)** and **Grenades (3/3 💣)**.
   * **🕳 Pit / Trap:** Falling into a pit stuns the player, skipping their next turn.
   * **🌀 Teleporter:** Instantly warps the player to a paired portal cell.
   * **💎 Treasure:** Claim the treasure and escape to the Exit.
   * **🚪 / 🏁 Exit:** Escape carrying the treasure to win the expedition!

4. **Wounded & Health System:**
   * Explorers start with **3 HP** (`Healthy 🤠`).
   * The first two gunshot hits deal 1 damage each, placing the explorer into **Wounded 🩸 status** (`2/3 HP` or `1/3 HP`).
   * The 3rd gunshot hit reduces HP to 0 and eliminates the player (`Eliminated 💀`).

5. **Sensory & Sound Echoes:**
   * When players move, shoot, or throw grenades, nearby players (within 3 cells) receive auditory echoes in their GM feedback log:
     * *“Player Alice: Footsteps heard from South”*
     * *“Player Bob: A gunshot echoed from North”*
     * *“Massive Explosion! Wall Demolished from West”*

6. **The Minotaur 👹 (Optional):**
   * Can be toggled on/off when creating a game.
   * After each complete round of player turns, the Minotaur steps 1 cell closer to the nearest explorer.
   * If the Minotaur enters a cell occupied by a player, that explorer is **eliminated** and drops any held treasure!

7. **AI Computer Bots:**
   * Add computer AI bots (`Labyrinth.Game.BotAI`) at room creation or during gameplay.
   * Bots navigate fog-of-war memory, use BFS to reach the exit when holding treasure, and shoot visible opponents in line-of-sight.

---

## 🧠 Prolog Engine & Map Validation

Labyrinth map reachability and connectivity rules are defined in Prolog (`priv/prolog/labyrinth_validator.pl`) and executed via **Robert Virding's `erlog` Erlang Prolog engine** (`rvirding/erlog`):

* **Rule Validation:**
  * Path exists from `Entrance` to `Treasure`.
  * Path exists from `Entrance` to `Hospital 🏥`.
  * Path exists from `Entrance` to `Arsenal ⚔️`.
  * Path exists from `Treasure` to `Exit`.
  * Path exists directly from `Entrance` to `Exit`.
  * Non-blocked cells maintain graph connectivity (≥ 85% reachability).
* **Dual Execution:**
  1. **Primary:** `:erlog` OTP Erlang interpreter loaded at runtime.
  2. **Secondary/Fallback:** System SWI-Prolog (`swipl`) CLI execution.

---

## 📌 Bot Expedition Post-Its & Interactive Map Overlay

Players can track AI computer bots using blind relative sub-grid fragments and pin them to the master map:

* **🤖 Blind Relative Sub-Grid Fragments:**
  * Each AI bot records its relative movements, bumped walls, and discovered landmarks (`🕳`, `🌀`, `🏥`, `⚔️`, `💎`, `🏁`) on a personal relative coordinate grid originating from `(0,0)`.
  * Each bot is assigned a distinct theme color (**Amber 🟡, Sky Blue 🔵, Emerald Green 🟢, Purple 🟣, Rose Pink 🔴**) that styles its map icons, roster badges, and Post-It cards.

* **📌 Snapshot Pinning & Fresh Fragment Reset:**
  * Click **"📌 Pin Active Fragment"** on any bot's Post-It card and select a cell `{X, Y}` on the main map to anchor its explored fragment.
  * Pinning saves a **fixed map snapshot overlay** on the game board and immediately resets the bot's active tracking to a **fresh relative fragment starting at `(0,0)`**, allowing players to continuously trace bot movements across multiple maze segments.
  * Pinned snapshots project feature badges (`📌1 🕳`, `📌2 🌀`, `💎💀`, etc.) directly onto the main map grid.

* **🦨 Minotaur Stink Perception & Configurable Wall Density:**
  * **Minotaur Stink Detection (2-Cell Radius):** When an explorer comes within 2 cells of the Minotaur 👹, an animated warning banner (`🦨 SENSORY WARNING: You smelled the Minotaur's foul stink wafting nearby!`) is displayed.
  * **Configurable Wall Density (0%..100%):** Set maze wall density during room creation from `0%` (open cavern) to `100%` (maximum wall density).

---

## 📜 History & Turn Replay

Every move, shot, grenade explosion, sound echo, and position change is recorded in PostgreSQL (`turns` table).
Visit `/history/:id` for any game to:
* Step turn-by-turn through game history.
* Use **Auto Play ⏯** or the step slider.
* View side-by-side player log feed and full GM Master Map progression.

---

## 🛠 Setup & Installation

### Prerequisites
* Elixir ~> 1.17 & Erlang/OTP 26+
* PostgreSQL running locally (default database user `postgres`)
* SWI-Prolog (`swipl`) installed (optional fallback)

### Commands

1. **Install dependencies:**
   ```bash
   mix deps.get
   ```

2. **Set up database:**
   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

3. **Build assets:**
   ```bash
   mix assets.build
   ```

4. **Start Phoenix dev server:**
   ```bash
   mix phx.server
   ```

5. Open **[http://localhost:4000](http://localhost:4000)** in your browser!

---

## 🎮 Keyboard Controls & Hotkeys

| Key | Action |
| :--- | :--- |
| **`W`** / **`Up Arrow`** | Action **North** ▲ |
| **`S`** / **`Down Arrow`** | Action **South** ▼ |
| **`A`** / **`Left Arrow`** | Action **West** ◄ |
| **`D`** / **`Right Arrow`** | Action **East** ► |
| **`E`** | Toggle **Shoot** Mode 🎯 (Fire Pistol) |
| **`G`** | Toggle **Grenade** Mode 💣 (Demolish Wall) |
| **`Spacebar`** | **Pass** Turn |

---

## 🧪 Running Tests & Precommit

To run tests and code verification:
```bash
mix precommit
```
or run test suite directly:
```bash
mix test
```
