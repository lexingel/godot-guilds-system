# Guildhold

A guild-management roguelite in Godot 4. You run a guild of heroes: hire
them, pay them, keep their morale up, and send them through rifts in
turn-based fights, or steer them through the real-time Endless Rift.

**Play the test build:** https://lexingel.github.io/guildhold/
**Found something?** Use Feedback on the title screen, or open an
[issue](https://github.com/lexingel/guildhold/issues).

## The game

- **Turn-based rifts:** a map of forked nodes (fights, elites, shops,
  events, hazards, campfires) ending in a boss. Fights read like a puzzle:
  foes show their next move, attacks and defence build a shared Momentum
  pool, and each hero spends it on role skills and a signature Ability.
  Rifts come in ranks F to SSS, each with its own rules.
- **The Endless Rift:** a survivors-style run in one of three regions:
  five-minute wave cycles, elite packs with chests, weapon evolutions,
  rift relics, terrain and braziers, and a Rift Warden at 20:00 to beat.
- **The guild:** 93 subclasses to recruit and evolve, gear, relics and
  skill trees; weekly wages and upkeep, morale, hero requests, a rival
  guild with a monthly contest, Guild Management upgrades, a three-act
  campaign, the Tower of Trials and a quest board.

## Running it

Open `project.godot` in Godot 4.7 and press F5. The web build is exported
with the "Web" preset to the repo root (`index.html` + `index.pck`) and
served by GitHub Pages from `master`.

## Tests

```
godot --headless --path . res://tests/run_tests.tscn            # everything
godot --headless --path . res://tests/run_tests.tscn -- relic   # files matching "relic"
```

Each `tests/test_*.gd` extends `base_test.gd` and calls `check()`. The run
fails on any failed check or any script error (CI does the same on every
push). `test_ui_smoke.gd` draws every screen once, so UI script errors fail
too. Each test starts from its own random seed.

The balance sim (`tests/sim/balance_sim.tscn`) plays reference parties
headless: `-- ranks` (clear rates per rift rank), `-- calibrate`
(recommended power), `-- tower`, `-- survivors` (Endless Rift times).

## Code layout

- `scripts/autoload/`: the game itself, with no UI. `GameData` (constants,
  split across `game_data/`), `GameState` (the save and every rule that
  changes it, split across `game_state/`), `Combat` (stats, fights,
  generation, split across `combat/`) and `AudioManager`.
- `scripts/ui/`: the whole UI, built in code from state on every render
  (no per-screen scenes). A chain of classes, each adding screens:
  `UiKit` → `RosterView` → `BattleView` → `RiftRunView` → `GuildViews` →
  `Main`.
- `scripts/survivors/`: the Endless Rift, as a pure simulation
  (`SurvivorsRun`) and its view (`SurvivorsView`).
- `assets/`: pixel art (PixelLab and free packs), music and sounds.

Saves: a reload mid-fight restarts that fight (same foes); everything else
in a rift comes back exactly as it was.
