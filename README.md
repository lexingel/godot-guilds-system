# Guilds System — Godot vertical slice

A from-scratch GDScript port of `guild-system.html`'s core loop, per the plan
recorded in `dreamy-munching-whistle.md`. First-run untested by me (I have no
way to launch or screenshot the Godot editor) — open `project.godot` in
Godot 4.x and press F5. Expect to hit a few GDScript syntax/type errors on
first run; report the exact error text back and they can be fixed quickly.

## Scope

**Fully ported (data + logic):** all 5 classes, 7 ranks, 3 rarities, all 50
`CLASS_POOL` entries, all 11 traits (6 universal + 5 role-exclusive), all 5
skill trees, relic types/specials/domains/synergy, item categories/slots
(including dual-wield + rank-scaled gear slots), hero stat math
(`Combat.gd`), hero/relic/item generation, skill learning + respec, trait
reroll/scrub, relic upgrades + equip, item equip, basic recruitment.

**Screens:** Onboard → Rift Hall (Lesser Rift only) → Party Assembly (pick
heroes + starting relic) → Rift Run (combat/shop/hazard/boss nodes, reward
choice) → Guild Terminal (Roster + Hero Recruits tabs, with an Inventory
section for unequipped items/relics).

**Deferred** (per the plan): Guild Management's 20-node upgrade tree and
everything gated behind it (all such values are fixed at their
zero-upgrade default — see the comments atop `GameState.gd`/`Combat.gd`),
Medical Bay, Champion system, Endless Rift, Rift Detectors, Hardcore Mode,
hero Evolution, the Guild Tier banner.

**Additional simplifications made during the port** (beyond what the
approved plan called out), for the user's awareness:
- Rift paths are a straight floor sequence (60% combat / 20% shop / 20%
  hazard, last floor always Boss) instead of the HTML version's branching
  "layers" with forks — the branching path is a presentation-layer detail,
  not part of the data/combat architecture this slice is meant to prove.
- Boss `mechanics` (Enraged/Warded/Regenerating/Frenzied) are ported as data
  in `GameData.BOSS_MECHANICS` but not yet wired into `Combat.resolve_combat`
  — every Boss fight currently behaves like a scaled-up regular fight.
- Elite encounters are not included (only regular/Boss combat nodes).
- No custom Theme/fonts yet — default Godot theme, functional over pretty.

## Project layout
See the "Project structure" section of the Godot-scaffolding plan in
`C:\Users\Semih\.claude\plans\dreamy-munching-whistle.md` for the intended
shape; `scripts/ui/Main.gd` builds the entire UI procedurally (no per-screen
.tscn files) rather than hand-authored scenes, mirroring how the HTML
version's `render()` rebuilds the DOM from state each time.
