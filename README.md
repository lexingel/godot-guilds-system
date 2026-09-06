# Guilds System — Godot port

A from-scratch GDScript port of `guild-system.html`'s core loop, per the plan
recorded in `dreamy-munching-whistle.md`. Open `project.godot` in Godot 4.x
and press F5.

## Scope

**Fully ported (data + logic):** all 5 classes, 7 ranks, 3 rarities, all 50
`CLASS_POOL` entries, all 11 traits (6 universal + 5 role-exclusive), all 5
skill trees, relic types/specials/domains/synergy, item categories/slots
(including dual-wield + rank-scaled gear slots), hero stat math
(`Combat.gd`), hero/relic/item generation, skill learning + respec, trait
reroll/scrub, relic upgrades + equip, item equip, recruitment, Guild
Management's 20-node upgrade tree, Medical Bay, the Champion system, Endless
Rift, Rift Detectors, Hardcore Mode, hero Evolution, boss mechanics (Enraged/
Warded/Regenerating/Frenzied), Elite encounters, and branching rift paths
(forked node choices per floor).

**Combat** is turn-based: a fight resolves one round at a time, the player
picking Attack / Ability / Defend / Retreat each round (`Combat.gd`'s
`start_combat`/`resolve_round`) instead of the whole fight auto-resolving —
class abilities are a single use per fight on a cooldown, not a one-time
pre-fight choice.

**Screens:** Onboard → Rift Hall (Lesser + Endless Rift) → Party Assembly
(pick heroes, starting relic, Hardcore toggle) → Rift Run (combat/shop/
hazard/elite/boss nodes, forked paths, reward choice) → Guild Terminal
(Roster, Hero Recruits, Guild Management, Medical Bay tabs, with an
Inventory section for unequipped items/relics/detectors).

**Visuals:** a hand-authored `Theme` (`theme/guild_theme.tres`) applies a
recolored version of a free CraftPix UI kit (`assets/ui/`) — panels/buttons
as `StyleBoxTexture`s hue-shifted to the palette in `scripts/ui/Palette.gd`,
which mirrors the original HTML prototype's CSS custom properties. Hero
portraits (`assets/heroes/`) come from a separate free character pack,
background-keyed and cropped. Monster sprites/dungeon art are their own
mismatched sources by design — different rifts represent different worlds,
so that variety is intentional, not a gap.

**Known gaps:**
- An in-progress run only persists its stable fields (floor, party, chosen
  path) across an app restart — whatever single node was mid-progress (a
  fight, a shop browse) re-rolls fresh rather than resuming mid-round. See
  the comment atop `GameState._run_for_save()`.
- `export_presets.cfg` has a Web preset scaffolded but untested — needs
  Godot's Web export templates installed and a manual export/serve check.

## Project layout
See the "Project structure" section of the Godot-scaffolding plan in
`C:\Users\Semih\.claude\plans\dreamy-munching-whistle.md` for the intended
shape; `scripts/ui/Main.gd` builds the entire UI procedurally (no per-screen
.tscn files) rather than hand-authored scenes, mirroring how the HTML
version's `render()` rebuilds the DOM from state each time.
