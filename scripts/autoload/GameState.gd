extends Node
## Current save state + run state — mirrors defaultState()/save()/load() and
## the state-mutating action functions (recruitHero, learnSkill, equipItem,
## engageCombat, etc.) from guild-system.html. Guild Management's upgrade
## tree (`upgrades`/`caps`) now backs every formula function below exactly
## like the HTML version's lvl()/hasCap().

signal state_changed

const RELIC_MAX_LEVEL := 5
const SLOT_COUNT := 3
## Bumped whenever the save's shape changes. load_save() runs
## _migrate_save() on anything older before reading it. (Older, per-field
## fallbacks still live in the model from_dicts: Hero attrs, Item attrs,
## Relic specials, the Guild Board's old contract/daily format.)
const SAVE_VERSION := 3
const ACTIVE_SLOT_PATH := "user://active_slot.cfg"
const SETTINGS_PATH := "user://settings.json"

var active_slot: int = 0
# Player/device prefs — global across save slots, not part of any guild's
# own save data, so they survive Reset Guild and switching slots.
var music_volume: float = 1.0
var combat_speed: float = 1.0
var reduce_motion := false   # no shakes, sways, zooms or flashes in fights (settings.json)
var colorblind := false      # blue instead of green against red, rarity letters on items (settings.json)
var ui_scale: float = 1.0   # whole-UI scale (Window.content_scale_factor), a settings.json preference   # animation time scale inside a rift (x1/x2/x3), a settings.json preference
var sfx_volume: float = 1.0
var resolution_idx: int = 0

var guild_name: String = ""
var guild_crest: int = 1   # 1-8, index into GameData.CREST_PATH
var next_id: int = 1
var coins: int = 60
var crystals: int = 15
var tokens: int = 0
var heroes: Array[Hero] = []
var relics: Array[Relic] = []
var items: Array[Item] = []
var detectors: Array[Dictionary] = []   # [{"id":..., "tier": "lesser"|"greater"|"ascendant"}]
var evolution_stones: Dictionary = {}   # rank_id ("E".."S") -> count, dropped by seal_rift() on a ranked Rift Map clear
var consumables: Array[Dictionary] = []   # owned, unused incense: [{"id":..., "incense_id": "vigor"|"warding"}]
var active_incense: Dictionary = {}       # {} = none active this run, else {"kind":..., "value":..., "name":...}
var runestones: Array[Dictionary] = []    # owned, unsocketed: [{"id":..., "runestone_id": "impact"|"aegis"}]
var tonics: int = 0   # Field Tonics carried (see GameData.TONIC_*)
var recruit_pool: Array[Hero] = []
var upgrades: Dictionary = {}    # "branch.node" -> level int
var caps: Dictionary = {}        # "branch.node" -> bool
var current_champion: Hero = null
var champion_offers: Array[Hero] = []   # pick one to replace current_champion (refreshed each seal)
var best_endless_cycle: int = 0
var daily_attempt_day: int = -1  # daily_id() of the last Daily Rift started (one a day)
var daily_clears: int = 0
var daily_streak: int = 0
var daily_last_clear: int = -1
var run_history: Array = []      # newest first, capped (GameData.RUN_HISTORY_MAX)
var runs_finished: int = 0
var fallen: Array = []           # memorial: heroes lost for good
var heroes_lost_total: int = 0
var best_endless_time: int = 0   # seconds survived in the Endless Rift (survivors mode)
var endless_runs: int = 0
var boon_set4_reached: bool = false
var tower_best: int = 0          # highest Tower of Trials floor ever cleared
var tower_week: int = 0          # tower_week_id() the weekly ladder progress belongs to
var tower_week_cleared: int = 0  # ladder floors (91+) cleared this week
var rifts_sealed: int = 0   # any rift, lesser/greater/endless — gates greater_rift_unlocked()
var best_rift_rank_sealed: int = -1   # highest Rift Map rank sealed (GameData.RIFT_RANKS index) — gates Riftborn nodes
var triage_used_this_cycle: bool = false
var pending_shop_boost: bool = false
var guide_hidden: bool = false   # the camp's "Getting started" checklist was dismissed
## One-shot flag for a hero/Champion that just rolled Rank S from any of the
## blind-reroll sources (recruit-offer reroll, Champion reroll, or the free
## automatic refresh on rift seal) — {} = none. Consumed by Main.render() the
## same way _flavor_toast is, so the celebration fires wherever the player
## happens to be, not just on the Recruits screen.
var pending_s_rank_reveal: Dictionary = {}
var pending_toasts: Array = []   # UI-only, never saved: [{cls_id, pool_id, title, text}] for Main's portrait pop-ups
var bonds: Dictionary = {}   # "<hero_id>|<hero_id>" (sorted) -> rifts sealed together; see GameData.BOND_LEVEL_RIFTS
var run: Dictionary = {}   # {} = no active run
var rift_map: Array[Dictionary] = []   # 6 slots: [{"rank":String, "runs_left":int, "bounty"?}] or [{}] (empty, refilled lazily)
var pending_riftbreak_ranks: Array[String] = []   # ranks that broke since the last Terminal visit, merged into one encounter
var monsters_seen: Array[String] = []      # bestiary — every monster/elite/boss name ever encountered
var bosses_defeated: Array[String] = []    # bestiary — boss names ever defeated
var hazards_seen: Array[String] = []       # bestiary — hazard type ids ever rolled

# --- Quests (Guild Board contracts/dailies, Milestones, Rift Map bounties,
# escort quests folded into combat, Reputation currency) ---
var reputation: int = 0
var monster_kill_counts: Dictionary = {}   # monster/elite/boss name -> all-time kill count
var crafts_performed: int = 0
var flawless_wins: int = 0   # wins where no hero was ever knocked out
var elites_won: int = 0      # every Elite win, unlike bosses_defeated/monsters_seen which only track distinct names
var bosses_won: int = 0      # every Boss win, same distinction
var guild_board: Array[Dictionary] = []    # rotating pool of quest dicts, see roll_quest()
var day: int = 0   # in-game days: one passes per rift run or rest (see pass_time)
var runs_started: int = 0   # the first one is a training rift (GameData.TRAINING_RIFT)
var campaign_act: int = 1   # the act in progress (GameData.CAMPAIGN); CAMPAIGN.size()+1 = campaign complete
var pending_stories: Array = []   # story cards Main shows before anything else: {title, subtitle, text}
var features_seen: Array = []   # unlocked features already announced (see check_feature_unlocks)
var hints_seen: Array = []   # coach tips dismissed
var tips_off: bool = false
var board_refresh_day: int = 0   # the day the Guild Board's unaccepted postings are replaced
var quest_tally: Dictionary = {}   # counters only quests read: boss:<name>, map:<uid>, rank_seals:<i>, *_seals, flawless_rifts
var milestones_claimed: Array[String] = []  # GameData.MILESTONES ids already granted


func lvl(key: String) -> int:
	return upgrades.get(key, 0)


func has_cap(key: String) -> bool:
	return caps.get(key, false)


func upgrade_node(key: String) -> String:
	var node := GameData.find_branch_node(key)
	if node.is_empty():
		return ""
	var cur := lvl(key)
	if cur >= int(node["max"]):
		return ""
	var cost: int = int(node["cost_base"]) + int(node["cost_step"]) * cur
	if crystals < cost:
		return "Not enough Crystals"
	crystals -= cost
	upgrades[key] = cur + 1
	save()
	state_changed.emit()
	return ""


# ---------------- Guild Management-derived formulas ----------------
func hero_slot_cap() -> int:
	return 4 + 2 * lvl("ops.barracks")


func relic_slot_cap() -> int:
	var l := lvl("res.vault")
	return 3 + (1 if l >= 3 else 0) + (1 if l >= 5 else 0)


func medical_recovery_reduction() -> float:
	return 0.15 * lvl("ops.infirmary")


## Runs a downed hero sits out (Medical upgrades bring it down to 1). A new
## guild (fewer than 3 rifts sealed, i.e. before Greater Rifts open) only ever
## loses a hero for 1 run: early wipes are common and a small roster otherwise
## sits idle while the Rift Map counts down.
func recovery_runs() -> int:
	if rifts_sealed < 3:
		return 1
	return max(1, int(round(GameData.DOWNED_RECOVERY_RUNS * (1.0 - medical_recovery_reduction()))))


## A hero knocked out during a run: +1 because the run it happened in counts
## down when it ends, so they then miss recovery_runs() whole runs.
func knock_out(h: Hero) -> void:
	h.hp = 0
	if not run.is_empty() and not h.is_champion:
		run["any_ko"] = true
	h.down_runs = recovery_runs() + (0 if run.is_empty() else 1)


func medical_bed_cap() -> int:
	return 1 + int(ceil(lvl("ops.infirmary") / 2.0))


func guild_mentor() -> bool:
	return lvl("ops.barracks") >= 3


func xp_mult() -> float:
	return 1.2 if lvl("ops.barracks") >= 5 else 1.0


func field_triage_available() -> bool:
	return lvl("ops.infirmary") >= 3


func full_heal_between_runs() -> bool:
	return lvl("ops.infirmary") >= 5


## Drill Yard: party damage (Combat.start_combat) and max HP (Combat.max_hp).
func tactical_bonus() -> float:
	return 1.0 + 0.04 * lvl("ops.drill")


func vanguard() -> bool:
	return lvl("ops.drill") >= 3


func abilities_ready_each_fight() -> bool:
	return lvl("ops.drill") >= 5


func respec_fee_reduction() -> float:
	return 0.3 if lvl("res.lab") >= 3 else 0.0


func trait_reroll_cost() -> int:
	return int(round(60 * (1.0 - respec_fee_reduction())))


func crystal_yield_bonus() -> float:
	return 1.0 + 0.08 * lvl("infra.amplifiers")


func energy_extract_chance() -> float:
	return 0.25 if lvl("infra.amplifiers") >= 3 else 0.0


func crystal_resonance() -> bool:
	return lvl("infra.amplifiers") >= 5


func hazard_severity_reduction() -> float:
	return 0.12 * lvl("infra.wardstones")


func anchor_artifact() -> bool:
	return lvl("infra.wardstones") >= 3


func hazards_nonlethal() -> bool:
	return lvl("infra.wardstones") >= 5


func seal_token_bonus() -> float:
	return 1.0 + 0.10 * lvl("infra.wardstones")


func broker_fee_reduction() -> float:
	return 0.02 * lvl("log.trade")


func black_market_unlocked() -> bool:
	return lvl("log.trade") >= 3


func merchant_price_reduction() -> float:
	return 0.06 * lvl("log.trade")


func detector_drop_bonus() -> float:
	return 0.05 * lvl("log.trade")


func shop_guaranteed_epic() -> bool:
	return lvl("log.trade") >= 5


func recruit_offer_count() -> int:
	var l := lvl("log.scouts")
	return 4 + (1 if l >= 1 else 0) + (1 if l >= 4 else 0)


func headhunter_guarantee() -> bool:
	return lvl("log.scouts") >= 3


func recruit_reroll_cost() -> int:
	return GameData.RECRUIT_REROLL_COST / (2 if lvl("log.scouts") >= 5 else 1)


func relic_choice_count() -> int:
	var l := lvl("res.vault")
	if l >= 4: return 4
	if l >= 2: return 3
	if l == 1: return 2
	return 0


func inherited_power() -> bool:
	return lvl("res.vault") >= 5


## Multiplier on relic element-set bonuses (Arcane Lab).
func set_bonus_mult() -> float:
	return 1.0 + 0.10 * lvl("res.lab")


func recycle_unlocked() -> bool:
	return lvl("res.lab") >= 1


func relic_upgrade_cost(r: Relic) -> int:
	var cost := 15.0 * float(GameData.find_rarity(r.rarity)["mult"]) * r.level
	return int(round(cost * (0.75 if lvl("res.lab") >= 5 else 1.0)))


## Which art a hamlet building shows (1-3), see GameData.HAMLET_BUILDINGS.
func hamlet_tier(b: Dictionary) -> int:
	match str(b.get("tier", "")):
		"node":
			var l := lvl(str(b["node"]))
			return 1 + (1 if l >= 3 else 0) + (1 if l >= 5 else 0)
		"guild":
			var name := str(Combat.guild_tier_info()["name"])
			return 3 if name == "Legendary Guild" else (2 if name in ["Established Guild", "Renowned Guild"] else 1)
		"act":
			return clampi(campaign_act, 1, 3)
	return 1


func hamlet_texture(b: Dictionary) -> String:
	if str(b.get("tier", "")) == "":
		return "res://assets/hamlet/%s.png" % b["id"]
	return "res://assets/hamlet/%s_t%d.png" % [b["id"], hamlet_tier(b)]


## Crystals a pre-rework save spent on the old Guild Management tree.
static func old_mgmt_refund(old_upgrades: Dictionary, old_caps: Dictionary) -> int:
	var total := 0
	for key in old_upgrades:
		var c: Array = GameData.OLD_MGMT_COSTS.get(key, [0, 0])
		for i in int(old_upgrades[key]):
			total += int(c[0]) + int(c[1]) * i
	for key in old_caps:
		if old_caps[key]:
			total += int(GameData.OLD_MGMT_CAP_COSTS.get(key, 0))
	return total


func reset() -> void:
	guild_name = ""
	guild_crest = 1
	next_id = 1
	coins = 60
	crystals = 15
	tokens = 0
	heroes = []
	relics = []
	items = []
	detectors = []
	consumables = []
	active_incense = {}
	runestones = []
	tonics = 0
	recruit_pool = []
	upgrades = {}
	caps = {}
	current_champion = null
	champion_offers = []
	best_endless_cycle = 0
	daily_attempt_day = -1
	daily_clears = 0
	daily_streak = 0
	daily_last_clear = -1
	run_history = []
	runs_finished = 0
	fallen = []
	heroes_lost_total = 0
	best_endless_time = 0
	endless_runs = 0
	boon_set4_reached = false
	tower_best = 0
	tower_week = 0
	tower_week_cleared = 0
	rifts_sealed = 0
	best_rift_rank_sealed = -1
	triage_used_this_cycle = false
	pending_shop_boost = false
	guide_hidden = false
	run = {}
	rift_map = []
	for i in 6:
		rift_map.append({})
	pending_riftbreak_ranks = []
	monsters_seen = []
	bosses_defeated = []
	hazards_seen = []
	reputation = 0
	monster_kill_counts = {}
	crafts_performed = 0
	flawless_wins = 0
	elites_won = 0
	bosses_won = 0
	guild_board = []
	day = 0
	runs_started = 0
	campaign_act = 1
	pending_stories = [_act_intro_card(1)]
	features_seen = []
	hints_seen = []
	tips_off = false
	board_refresh_day = 0
	quest_tally = {}
	milestones_claimed = []
	bonds = {}


## node_state is saved through _pack (Items/Relics as dicts) minus the live
## fight, which holds Hero references: a reload mid-fight restarts that fight
## (same monsters — engage_node seeds from the run's seed), while shops, events,
## treasure, campfires, hazards and a finished fight's result come back exactly
## as they were, so reloading can't re-roll or re-pay a node.
func _run_for_save() -> Dictionary:
	if run.is_empty():
		return {}
	var out := {
		"diff_id": run.get("diff_id", ""), "endless": run.get("endless", false),
		"cycle": run.get("cycle", 0), "hardcore": run.get("hardcore", false),
		"layers": run.get("layers", []), "pos": run.get("pos", 0),
		"chosen": run.get("chosen", {}), "hero_ids": run.get("hero_ids", []),
		"shield": run.get("shield", 0), "boss_rounds": run.get("boss_rounds", 0),
		"node_kind": run.get("node_kind", ""), "node_state": _pack(_saveable_node_state()), "seed": run.get("seed", 0),
		"sealed": run.get("sealed"), "anchor_used": run.get("anchor_used", false),
		"start_coins": run.get("start_coins", coins), "start_crystals": run.get("start_crystals", crystals),
		"start_tokens": run.get("start_tokens", tokens), "heroes_lost": run.get("heroes_lost", 0),
		"rift_rank": run.get("rift_rank", ""), "is_riftbreak": run.get("is_riftbreak", false),
		"riftbreak_severity": run.get("riftbreak_severity", 0),
		"riftbreak_worst_index": run.get("riftbreak_worst_index", 0),
		"riftbreak_flavor": run.get("riftbreak_flavor", ""),
		"bounty": run.get("bounty", {}), "champion_call_used": run.get("champion_call_used", false),
		"injured": run.get("injured", []), "left_behind": run.get("left_behind", []), "heal_used": run.get("heal_used", false),
		"map_uid": run.get("map_uid", ""), "any_ko": run.get("any_ko", false),
		"champion_calls": run.get("champion_calls", 0), "phoenix_used": run.get("phoenix_used", false),
		"finale": run.get("finale", 0), "training": run.get("training", false), "biome": run.get("biome", "vale"),
		"orders_used": run.get("orders_used", 0), "boons": run.get("boons", []), "events_seen": run.get("events_seen", []), "daily": run.get("daily", -1),
	}
	if run.has("tower"):
		out["tower"] = run["tower"]
		out["tower_snap"] = run.get("tower_snap", {})
	return out


func _saveable_node_state() -> Dictionary:
	var ns: Dictionary = run.get("node_state", {}).duplicate()
	if ns.has("combat_state"):
		ns.erase("combat_state")
		if not ns.has("result"):
			ns.erase("type")   # mid-fight: back to "an encounter awaits"
	return ns


static func _pack(v: Variant) -> Variant:
	if v is Item:
		return {"__item": v.to_dict()}
	if v is Relic:
		return {"__relic": v.to_dict()}
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _pack(v[k])
		return d
	if v is Array:
		return v.map(func(x): return _pack(x))
	return v


static func _unpack(v: Variant) -> Variant:
	if v is Dictionary:
		if v.has("__item"):
			return Item.from_dict(v["__item"])
		if v.has("__relic"):
			return Relic.from_dict(v["__relic"])
		var d := {}
		for k in v:
			d[k] = _unpack(v[k])
		return d
	if v is Array:
		return v.map(func(x): return _unpack(x))
	return v


func _slot_path(slot: int) -> String:
	return "user://save_slot_%d.json" % slot


func load_active_slot() -> void:
	active_slot = 0
	if FileAccess.file_exists(ACTIVE_SLOT_PATH):
		var f := FileAccess.open(ACTIVE_SLOT_PATH, FileAccess.READ)
		active_slot = clampi(int(f.get_as_text().strip_edges()), 0, SLOT_COUNT - 1)


func set_active_slot(slot: int) -> void:
	active_slot = clampi(slot, 0, SLOT_COUNT - 1)
	var f := FileAccess.open(ACTIVE_SLOT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(str(active_slot))


## Peeks at a slot's save file without touching live state — used by the
## Settings screen's slot picker to show a summary before switching.
func slot_summary(slot: int) -> Dictionary:
	var path := _slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"empty": true}
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or String(parsed.get("guild_name", "")) == "":
		return {"empty": true}
	return {
		"empty": false,
		"guild_name": parsed.get("guild_name", ""),
		"rifts_sealed": parsed.get("rifts_sealed", 0),
	}


func delete_slot(slot: int) -> void:
	var path := _slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.open("user://").remove(path.trim_prefix("user://"))


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"music_volume": music_volume, "sfx_volume": sfx_volume, "resolution_idx": resolution_idx, "combat_speed": combat_speed, "ui_scale": ui_scale,
			"reduce_motion": reduce_motion, "colorblind": colorblind,
		}))


func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		# First launch in a browser: follow its reduced-motion preference.
		if OS.has_feature("web"):
			reduce_motion = bool(JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches", true))
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		music_volume = parsed.get("music_volume", 1.0)
		combat_speed = float(parsed.get("combat_speed", 1.0))
		ui_scale = float(parsed.get("ui_scale", 1.0))
		reduce_motion = bool(parsed.get("reduce_motion", false))
		colorblind = bool(parsed.get("colorblind", false))
		sfx_volume = parsed.get("sfx_volume", 1.0)
		resolution_idx = parsed.get("resolution_idx", 0)


func save() -> void:
	# No guild loaded = nothing worth saving, and writing it would clobber the
	# active slot: render() runs its world-tick resolvers (resolve_guild_board
	# etc., which save) on the title screen too, before any slot is loaded — so
	# every boot used to overwrite the active slot with a blank default state
	# that load_save()/slot_summary() then treat as empty.
	if guild_name == "":
		return
	var data := {
		"save_version": SAVE_VERSION,
		"guild_name": guild_name, "guild_crest": guild_crest, "next_id": next_id, "coins": coins,
		"crystals": crystals, "tokens": tokens,
		"heroes": heroes.map(func(h): return h.to_dict()),
		"recruit_pool": recruit_pool.map(func(h): return h.to_dict()),
		"relics": relics.map(func(r): return r.to_dict()),
		"items": items.map(func(it): return it.to_dict()),
		"detectors": detectors, "evolution_stones": evolution_stones,
		"consumables": consumables, "active_incense": active_incense, "runestones": runestones, "tonics": tonics,
		"upgrades": upgrades, "caps": caps,
		"current_champion": current_champion.to_dict() if current_champion else null,
		"champion_offers": champion_offers.map(func(c): return c.to_dict()),
		"best_endless_cycle": best_endless_cycle,
		"tower_best": tower_best, "tower_week": tower_week, "tower_week_cleared": tower_week_cleared,
		"daily_attempt_day": daily_attempt_day, "daily_clears": daily_clears, "daily_streak": daily_streak, "daily_last_clear": daily_last_clear,
		"run_history": run_history, "runs_finished": runs_finished, "fallen": fallen, "heroes_lost_total": heroes_lost_total, "best_endless_time": best_endless_time, "endless_runs": endless_runs, "boon_set4_reached": boon_set4_reached,
		"rifts_sealed": rifts_sealed, "best_rift_rank_sealed": best_rift_rank_sealed,
		"triage_used_this_cycle": triage_used_this_cycle,
		"pending_shop_boost": pending_shop_boost,
		"guide_hidden": guide_hidden,
		"run": _run_for_save(),
		"rift_map": rift_map, "pending_riftbreak_ranks": pending_riftbreak_ranks,
		"monsters_seen": monsters_seen, "bosses_defeated": bosses_defeated, "hazards_seen": hazards_seen,
		"reputation": reputation, "monster_kill_counts": monster_kill_counts,
		"crafts_performed": crafts_performed, "flawless_wins": flawless_wins,
		"elites_won": elites_won, "bosses_won": bosses_won,
		"guild_board": guild_board, "day": day, "runs_started": runs_started, "campaign_act": campaign_act, "features_seen": features_seen, "hints_seen": hints_seen, "tips_off": tips_off, "board_refresh_day": board_refresh_day, "quest_tally": quest_tally, "milestones_claimed": milestones_claimed,
		"bonds": bonds,
	}
	var f := FileAccess.open(_slot_path(active_slot), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


## One-time migration for saves from before skill ids were namespaced by
## kind (see Hero.skills' doc comment): a bare key ("cap", "mastery", ...)
## always meant "the hero's one active tree" back then, which was always
## their current class's kind — so it's unambiguous to prefix it now. A
## hero who'd already evolved through several different kinds under the old
## flat-key system is the one case this can misattribute (no way to recover
## which historical kind a bare id belonged to) — self-healing via Respec
## if it ever shows. No-ops instantly once a hero's keys are already namespaced.
func migrate_hero_skill_keys(h: Hero) -> void:
	var cur_kind: String = GameData.find_class(h.pool_id).get("kind", "dmg_pct")
	var migrated := {}
	var changed := false
	for key in h.skills.keys():
		if str(key).contains(":") or key in ["edge", "hide", "signature"]:
			migrated[key] = h.skills[key]
		else:
			migrated[GameData.skill_storage_key(cur_kind, str(key))] = h.skills[key]
			changed = true
	if changed:
		h.skills = migrated


## Brings a save dict up to SAVE_VERSION, one step at a time. Version 1 is
## every save written before versioning existed; its missing fields are all
## handled by per-model defaults, so 1 -> 2 only stamps the version.
func _migrate_save(data: Dictionary) -> Dictionary:
	var v := int(data.get("save_version", 1))
	if v > SAVE_VERSION:
		push_warning("Save is from a newer version (%d > %d)" % [v, SAVE_VERSION])
	if v < 3:
		# Guild Management was rebuilt (9 nodes, perks instead of capstones):
		# refund every Crystal spent on the old tree.
		var refund := old_mgmt_refund(data.get("upgrades", {}), data.get("caps", {}))
		data["upgrades"] = {}
		data["caps"] = {}
		data["crystals"] = int(data.get("crystals", 0)) + refund
		if refund > 0:
			data["_mgmt_refund"] = refund
		v = 3
	# if v < 4: ...next migration goes here, then v = 4
	data["save_version"] = max(v, SAVE_VERSION)
	return data


## The active slot's save as text, for backing up or moving to another device.
func export_save_text() -> String:
	save()
	if not FileAccess.file_exists(_slot_path(active_slot)):
		return ""
	return FileAccess.get_file_as_string(_slot_path(active_slot))


## Replaces `slot` with an exported save. Returns "" or why it was refused.
func import_save_text(text: String, slot: int) -> String:
	var parsed = JSON.parse_string(text.strip_edges())
	if typeof(parsed) != TYPE_DICTIONARY or String(parsed.get("guild_name", "")) == "":
		return "That doesn't look like a Guild System save"
	if int(parsed.get("save_version", 1)) > SAVE_VERSION:
		return "That save is from a newer version of the game"
	var f := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if not f:
		return "Couldn't write the save slot"
	f.store_string(JSON.stringify(parsed))
	f.close()
	return ""


func load_save() -> bool:
	if not FileAccess.file_exists(_slot_path(active_slot)):
		return false
	var f := FileAccess.open(_slot_path(active_slot), FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = _migrate_save(parsed)
	# A save file can exist on disk for a slot that was never actually
	# founded (e.g. a stray write while "Name Your Guild" was still open) —
	# slot_summary() already treats a blank guild_name as "empty" for slot
	# selection, so this has to agree: otherwise _switch_slot()'s "if not
	# load_save(): reset()" skips reset() for a slot that looks reusable,
	# and every field reset() seeds (rift_map among them) is left at its
	# bare class default — an empty array here, permanently, since nothing
	# else ever grows it back to size.
	if String(data.get("guild_name", "")) == "":
		return false
	guild_name = data.get("guild_name", "")
	guild_crest = data.get("guild_crest", 1)
	next_id = data.get("next_id", 1)
	coins = data.get("coins", 60)
	crystals = data.get("crystals", 15)
	tokens = data.get("tokens", 0)
	Hero.attrs_migrated = 0
	heroes.assign(data.get("heroes", []).map(func(d): return Hero.from_dict(d)))
	if Hero.attrs_migrated > 0:
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Heroes have attributes now",
			"text": "Might, Agility and Focus — each hero has points from their past levels to spend (Roster > Hero)."})
	recruit_pool.assign(data.get("recruit_pool", []).map(func(d): return Hero.from_dict(d)))
	for h in heroes:
		migrate_hero_skill_keys(h)
	for h in recruit_pool:
		migrate_hero_skill_keys(h)
	if recruit_pool.is_empty() and guild_name != "":
		# Saves from before recruit_pool was persisted (or an old save with no
		# key at all) would otherwise show an empty Hero Recruits screen until
		# the next rift seal — refresh_recruit_pool() always produces exactly
		# 4 offers, so a genuinely empty pool only ever means "missing data,"
		# never "no offers today."
		refresh_recruit_pool()
	relics.assign(data.get("relics", []).map(func(d): return Relic.from_dict(d)))
	items.assign(data.get("items", []).map(func(d): return Item.from_dict(d)))
	detectors.assign(data.get("detectors", []))
	evolution_stones = data.get("evolution_stones", {})
	consumables.assign(data.get("consumables", []))
	active_incense = data.get("active_incense", {})
	runestones.assign(data.get("runestones", []))
	tonics = int(data.get("tonics", 0))
	rift_map.assign(data.get("rift_map", []))
	if rift_map.is_empty() and guild_name != "":
		# Saves from before the Rift Map existed — seed 6 empty slots so
		# resolve_rift_map() fills them with real rifts on the next render(),
		# same fallback shape as the recruit_pool fix above.
		for i in 6:
			rift_map.append({})
	pending_riftbreak_ranks.assign(data.get("pending_riftbreak_ranks", []))
	monsters_seen.assign(data.get("monsters_seen", []))
	bosses_defeated.assign(data.get("bosses_defeated", []))
	hazards_seen.assign(data.get("hazards_seen", []))
	reputation = data.get("reputation", 0)
	monster_kill_counts = data.get("monster_kill_counts", {})
	crafts_performed = data.get("crafts_performed", 0)
	flawless_wins = data.get("flawless_wins", 0)
	elites_won = data.get("elites_won", 0)
	bosses_won = data.get("bosses_won", 0)
	guild_board.assign(data.get("guild_board", []))
	day = int(data.get("day", 0))
	board_refresh_day = int(data.get("board_refresh_day", 0))
	quest_tally = data.get("quest_tally", {})
	milestones_claimed.assign(data.get("milestones_claimed", []))
	bonds = data.get("bonds", {})
	upgrades = data.get("upgrades", {})
	caps = data.get("caps", {})
	if int(data.get("_mgmt_refund", 0)) > 0:
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Guild Management rebuilt",
			"text": "Upgrades are fewer and much stronger now. %d Crystals spent on the old tree were refunded." % int(data["_mgmt_refund"])})
	var champ_data = data.get("current_champion")
	current_champion = Hero.from_dict(champ_data) if champ_data != null else null
	if current_champion:
		migrate_hero_skill_keys(current_champion)
	champion_offers.assign((data.get("champion_offers", []) as Array).map(func(c): return Hero.from_dict(c)))
	best_endless_cycle = data.get("best_endless_cycle", 0)
	tower_best = int(data.get("tower_best", 0))
	daily_attempt_day = int(data.get("daily_attempt_day", -1))
	daily_clears = int(data.get("daily_clears", 0))
	daily_streak = int(data.get("daily_streak", 0))
	daily_last_clear = int(data.get("daily_last_clear", -1))
	run_history = data.get("run_history", [])
	runs_finished = int(data.get("runs_finished", 0))
	fallen = data.get("fallen", [])
	heroes_lost_total = int(data.get("heroes_lost_total", 0))
	best_endless_time = int(data.get("best_endless_time", 0))
	endless_runs = int(data.get("endless_runs", 0))
	boon_set4_reached = bool(data.get("boon_set4_reached", false))
	tower_week = int(data.get("tower_week", 0))
	tower_week_cleared = int(data.get("tower_week_cleared", 0))
	rifts_sealed = data.get("rifts_sealed", 0)
	best_rift_rank_sealed = int(data.get("best_rift_rank_sealed", -1))
	runs_started = int(data.get("runs_started", 0 if rifts_sealed == 0 and monsters_seen.is_empty() else 1))
	pending_stories = []
	if data.has("campaign_act"):
		campaign_act = int(data["campaign_act"])
	else:
		# A guild from before the campaign keeps what it had unlocked.
		campaign_act = 3 if best_endless_cycle > 0 else (2 if rifts_sealed >= 3 else 1)
	hints_seen = data.get("hints_seen", [])
	tips_off = bool(data.get("tips_off", false))
	if data.has("features_seen"):
		features_seen = data["features_seen"]
	else:
		# A guild from before staged unlocks: everything it already has is old news.
		features_seen = GameData.FEATURE_UNLOCKS.keys().filter(func(f): return feature_unlocked(f))
	triage_used_this_cycle = data.get("triage_used_this_cycle", false)
	pending_shop_boost = data.get("pending_shop_boost", false)
	guide_hidden = data.get("guide_hidden", false)

	var run_data: Dictionary = data.get("run", {})
	if run_data.is_empty():
		run = {}
	else:
		# JSON round-trips Dictionary keys as strings, but `chosen` is keyed
		# by int rift position everywhere it's read (current_node_kind() etc).
		var chosen_raw: Dictionary = run_data.get("chosen", {})
		var chosen_fixed: Dictionary = {}
		for k in chosen_raw:
			chosen_fixed[int(k)] = chosen_raw[k]
		run = {
			"diff_id": run_data.get("diff_id", ""), "endless": run_data.get("endless", false),
			"cycle": run_data.get("cycle", 0), "hardcore": run_data.get("hardcore", false),
			"layers": run_data.get("layers", []), "pos": run_data.get("pos", 0),
			"chosen": chosen_fixed, "hero_ids": run_data.get("hero_ids", []),
			"shield": run_data.get("shield", 0), "boss_rounds": run_data.get("boss_rounds", 0),
			"node_kind": run_data.get("node_kind", ""), "node_state": _unpack(run_data.get("node_state", {})), "seed": int(run_data.get("seed", randi())),
			"sealed": run_data.get("sealed"), "anchor_used": run_data.get("anchor_used", false),
			"start_coins": run_data.get("start_coins", coins), "start_crystals": run_data.get("start_crystals", crystals),
			"start_tokens": run_data.get("start_tokens", tokens), "heroes_lost": run_data.get("heroes_lost", 0),
			"rift_rank": run_data.get("rift_rank", ""), "is_riftbreak": run_data.get("is_riftbreak", false),
			"riftbreak_severity": run_data.get("riftbreak_severity", 0),
			"riftbreak_worst_index": run_data.get("riftbreak_worst_index", 0),
			"riftbreak_flavor": run_data.get("riftbreak_flavor", ""),
			"bounty": run_data.get("bounty", {}), "champion_call_used": bool(run_data.get("champion_call_used", false)),
			"injured": run_data.get("injured", []), "left_behind": run_data.get("left_behind", []), "heal_used": bool(run_data.get("heal_used", false)),
			"map_uid": str(run_data.get("map_uid", "")), "any_ko": bool(run_data.get("any_ko", false)),
			"champion_calls": int(run_data.get("champion_calls", 1 if run_data.get("champion_call_used", false) else 0)), "phoenix_used": bool(run_data.get("phoenix_used", false)),
			"finale": int(run_data.get("finale", 0)), "training": bool(run_data.get("training", false)), "biome": str(run_data.get("biome", "vale")),
			"orders_used": int(run_data.get("orders_used", 0)), "boons": run_data.get("boons", []), "events_seen": run_data.get("events_seen", []),
		}
		if int(run_data.get("daily", -1)) >= 0:
			run["daily"] = int(run_data["daily"])
		if run_data.has("tower"):
			run["tower"] = int(run_data["tower"])
			run["tower_snap"] = run_data.get("tower_snap", {})
	return true


## Queues a portrait pop-up (Main drains these on its next render).
func push_toast(h: Hero, title: String, text: String) -> void:
	pending_toasts.append({"cls_id": h.cls_id, "pool_id": h.pool_id, "title": title, "text": text})


func _bond_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func bond_rifts(a: String, b: String) -> int:
	return int(bonds.get(_bond_key(a, b), 0))


## Unlocks every GameData.EARNED_TRAITS entry `h` now qualifies for; returns
## the newly earned trait names (for a "X earned Bosskiller" line).
func check_earned_traits(h: Hero) -> Array[String]:
	var gained: Array[String] = []
	if h.is_champion:
		return gained
	for t in GameData.EARNED_TRAITS:
		if not h.earned_traits.has(t["id"]) and int(h.history.get(t["stat"], 0)) >= int(t["need"]):
			h.earned_traits.append(t["id"])
			gained.append("%s earned %s!" % [h.name, t["name"]])
			var what: String = Combat.describe_skill(str(t["kind"]), float(t["value"])) if t.has("kind") else Combat.describe_effect(t["effects"][0])
			push_toast(h, "Trait earned: %s" % t["name"], "%s — %s" % [h.name.split(" the ")[0], what])
	return gained


func find_hero(hero_id: String) -> Hero:
	for h in heroes:
		if h.id == hero_id:
			return h
	return null


func gen_recruit_offer(force_rank: String = "") -> Hero:
	return Combat.gen_hero(force_rank if force_rank != "" else Combat.weighted_rank(), 1)


## Flags pending_s_rank_reveal whenever a blind roll (recruit offer, Champion
## reroll/init) lands Rank S — Main.render() consumes it once, the same way
## it already consumes _flavor_toast, so the celebration shows up wherever
## the player is instead of only on the Recruits screen.
func _maybe_flag_s_rank(h: Hero, source: String) -> void:
	if h.rank == "S":
		pending_s_rank_reveal = {"name": h.name, "cls_id": h.cls_id, "pool_id": h.pool_id, "source": source}


func refresh_recruit_pool() -> void:
	recruit_pool = []
	for i in recruit_offer_count():
		recruit_pool.append(gen_recruit_offer())
	if headhunter_guarantee():
		var order: Array[String] = []
		for r in GameData.RANKS:
			order.append(r["id"])
		var has_good := recruit_pool.any(func(h): return order.find(h.rank) >= 3)
		if not has_good:
			var good_ranks := ["C", "B", "A", "S"]
			recruit_pool[0] = gen_recruit_offer(good_ranks[randi() % good_ranks.size()])
	for h in recruit_pool:
		_maybe_flag_s_rank(h, "recruit")


func recruit_hero(offer_id: String) -> String:
	var idx := -1
	for i in recruit_pool.size():
		if recruit_pool[i].id == offer_id:
			idx = i
			break
	if idx < 0:
		return ""
	if heroes.size() >= hero_slot_cap():
		return "Roster is full."
	var offer := recruit_pool[idx]
	var rank := GameData.find_rank(offer.rank)
	if coins < int(rank["cost"]):
		return "Not enough Coins."
	coins -= int(rank["cost"])
	var is_dupe := heroes.any(func(h): return h.pool_id == offer.pool_id)
	if guild_mentor():
		offer.level = 2
		offer.skill_points += 1
		offer.base_hp = int(round(offer.base_hp * 1.08))
		offer.base_dmg = int(round(offer.base_dmg * 1.08))
		offer.hp = Combat.max_hp(offer)
	heroes.append(offer)
	recruit_pool[idx] = gen_recruit_offer()
	if is_dupe:
		var refund := int(round(float(rank["cost"]) * 0.5))
		coins += refund
	save()
	state_changed.emit()
	return ""


func ensure_champion() -> Hero:
	if not current_champion:
		current_champion = Combat.generate_champion()
		_maybe_flag_s_rank(current_champion, "champion")
	if champion_offers.is_empty():
		refresh_champion_offers()
	sync_champion_level()
	current_champion.hp = Combat.max_hp(current_champion)
	current_champion.down_runs = 0
	return current_champion


func reroll_recruit_offer(offer_id: String) -> String:
	var idx := -1
	for i in recruit_pool.size():
		if recruit_pool[i].id == offer_id:
			idx = i
			break
	if idx < 0:
		return ""
	if coins < recruit_reroll_cost():
		return "Not enough Coins."
	coins -= recruit_reroll_cost()
	recruit_pool[idx] = gen_recruit_offer()
	_maybe_flag_s_rank(recruit_pool[idx], "recruit")
	save()
	state_changed.emit()
	return ""


## A fresh set of Champion offers for Coins (a free set arrives every seal).
func reroll_champion() -> String:
	if coins < GameData.CHAMPION_REROLL_COST:
		return "Not enough Coins."
	coins -= GameData.CHAMPION_REROLL_COST
	refresh_champion_offers()
	save()
	state_changed.emit()
	return ""


func refresh_champion_offers() -> void:
	champion_offers.clear()
	var roles := {}
	for i in GameData.CHAMPION_OFFER_COUNT:
		# Different roles where the dice allow, so it's a real choice of Boon/Call.
		var c := Combat.generate_champion()
		for attempt in 12:
			if not roles.has(champion_role(c)):
				break
			c = Combat.generate_champion()
		roles[champion_role(c)] = true
		_maybe_flag_s_rank(c, "champion")
		_sync_level(c)
		c.hp = Combat.max_hp(c)
		champion_offers.append(c)


## Swaps in one of the offers. The outgoing Champion's gear returns to the
## Inventory and their oath resets — the new one starts at 0.
func choose_champion(idx: int) -> void:
	if not run.is_empty() or idx < 0 or idx >= champion_offers.size():
		return
	_release_champion_gear()
	current_champion = champion_offers[idx]
	champion_offers.clear()
	sync_champion_level()
	current_champion.hp = Combat.max_hp(current_champion)
	save()
	state_changed.emit()


func _release_champion_gear() -> void:
	if not current_champion:
		return
	for it in items:
		if it.equipped_to == current_champion.id:
			it.equipped_to = ""
			it.equipped_idx = -1


## The Champion keeps pace with your strongest hero (never drops a level).
func sync_champion_level() -> void:
	if current_champion:
		_sync_level(current_champion)


func _sync_level(c: Hero) -> void:
	var target := 1
	for h in heroes:
		target = max(target, h.level)
	while c.level < target:
		c.level += 1
		c.base_hp = int(round(c.base_hp * (1.0 + GameData.LEVEL_GROWTH)))
		c.base_dmg = int(round(c.base_dmg * (1.0 + GameData.LEVEL_GROWTH)))
		c.attr_points += GameData.ATTR_POINTS_PER_LEVEL
	Combat.auto_spend_attrs(c)


func champion_role(c: Hero) -> String:
	return str(GameData.find_class(c.pool_id).get("role", "warrior"))


## The party-wide Boon while the Champion is standing in a run.
func champion_boon(kind: String) -> float:
	if run.is_empty() or current_champion == null or current_champion.hp <= 0:
		return 0.0
	var b: Dictionary = GameData.CHAMPION_BOONS.get(champion_role(current_champion), {})
	if b.get("kind", "") != kind:
		return 0.0
	return float(b["value"]) * float(GameData.find_rank(current_champion.rank)["mult"])


func champion_boon_text(c: Hero) -> String:
	var b: Dictionary = GameData.CHAMPION_BOONS.get(champion_role(c), {})
	if b.is_empty():
		return ""
	return "%s — party %s" % [b["name"], Combat.describe_skill(str(b["kind"]), float(b["value"]) * float(GameData.find_rank(c.rank)["mult"]))]


## The Champion's Call as an Active-Ability-shaped dict {name, effect, value}.
func champion_call(c: Hero) -> Dictionary:
	return GameData.CHAMPION_CALLS.get(champion_role(c), GameData.CHAMPION_CALLS["warrior"])


func champion_call_ready(h: Hero) -> bool:
	if not h.is_champion or run.is_empty():
		return false
	var allowed := 2 if Combat.party_has_unique_relic("crown_of_oaths") else 1
	return int(run.get("champion_calls", 0)) < allowed


func champion_can_swear() -> bool:
	return current_champion != null and current_champion.oath >= GameData.CHAMPION_OATH_SEALS and heroes.size() < hero_slot_cap()


## The Champion joins the roster for good: a named hero with their level,
## gear and Skill Points for every level; one of the offers steps up.
func swear_in_champion() -> String:
	if not run.is_empty():
		return "Finish the rift first"
	if not champion_can_swear():
		return "Not ready"
	var c := current_champion
	var cls := GameData.find_class(c.pool_id)
	if not c.name.contains(" the "):   # a Champion from before they had names
		var free: Array = GameData.FIRST_NAMES.filter(func(n): return not heroes.any(func(o): return o.name.begins_with(n + " ")))
		c.name = "%s the %s" % [(free if not free.is_empty() else GameData.FIRST_NAMES).pick_random(), cls.get("name", c.name)]
	c.is_champion = false
	c.cls_id = str(cls.get("role", "warrior"))
	c.innate_value = Combat.hero_innate_value(cls, GameData.rank_index(c.rank))
	c.trait_name = Combat.pick_trait_name(c.cls_id)
	c.skill_points = c.level - 1
	c.oath = 0
	heroes.append(c)
	push_toast(c, "Sworn to the guild", "%s joins your roster for good" % c.name.split(" the ")[0])
	if champion_offers.is_empty():
		refresh_champion_offers()
	current_champion = champion_offers.pop_front()
	sync_champion_level()
	current_champion.hp = Combat.max_hp(current_champion)
	save()
	state_changed.emit()
	return ""


func current_party() -> Array[Hero]:
	var out: Array[Hero] = []
	if current_champion:
		out.append(current_champion)
	for id in run.get("hero_ids", []):
		var h := find_hero(id)
		if h:
			out.append(h)
	return out


## Folds a mapped rift's RIFT_RANK_MODIFIERS into a copy of `diff` — shared by
## start_run() (so the *initial* build_layers() call already sees the biased
## elite/shop pool) and _diff() (so every later call, e.g. Combat.start_combat
## at each node and ensure_hazard's severity roll, sees the same modified
## numbers too — _diff() re-derives its base diff fresh from GameData.DIFFICULTIES
## on every call, so a one-off modified copy from start_run alone wouldn't
## actually apply for the rest of the run).
func _apply_rift_rank_modifiers(diff: Dictionary, rift_rank: String) -> Dictionary:
	if rift_rank == "":
		return diff
	var mods: Dictionary = GameData.RIFT_RANK_MODIFIERS.get(rift_rank, {})
	if mods.is_empty():
		return diff
	var out := diff.duplicate(true)
	out["monster_hp"] = int(round(float(out["monster_hp"]) * float(mods.get("monster_hp_mult", 1.0))))
	out["monster_dmg"] = int(round(float(out["monster_dmg"]) * float(mods.get("monster_dmg_mult", 1.0))))
	out["hazard_severity_up"] = int(mods.get("hazard_severity_up", 0))
	out["elite_chance_up"] = bool(mods.get("elite_chance_up", false))
	out["shop_chance_down"] = bool(mods.get("shop_chance_down", false))
	out["boss_double_mechanic"] = bool(mods.get("boss_double_mechanic", false))
	return out


## `rift_rank` is "" for every existing caller (Rift Hall's Lesser/Endless
## picker) — only GameState.start_map_rift() passes a real rank, applying
## RIFT_RANK_MODIFIERS on top of the normal Lesser Rift difficulty.
## relic_rarity_floor_down is read directly against Main.gd's
## _pending_rift_rank at Party Assembly's starting-relic roll (that roll
## happens before a `diff`/run even exists, so it can't flow through here).
func start_run(diff_id: String, hero_ids: Array[String], starting_relic: Relic, hardcore: bool, endless: bool, rift_rank: String = "") -> void:
	var shield := 0
	for r in Combat.equipped_relics():
		shield += r.hp
	if starting_relic:
		shield += starting_relic.hp
		starting_relic.id = "rl" + str(next_id)
		next_id += 1
		starting_relic.equipped = false
		relics.append(starting_relic)
	var diff := Combat.endless_diff_for_cycle(0)
	if not endless:
		diff = GameData.DIFFICULTIES[0]
		for d in GameData.DIFFICULTIES:
			if d["id"] == diff_id:
				diff = d
	diff = _apply_rift_rank_modifiers(diff, rift_rank)
	var training := runs_started == 0 and not endless and rift_rank == ""
	if training:
		diff = _apply_training(diff)
	runs_started += 1
	run = {
		"diff_id": diff_id, "endless": endless, "cycle": 0, "hardcore": hardcore,
		"layers": Combat.build_layers(diff), "pos": 0, "chosen": {},
		"hero_ids": hero_ids, "shield": shield, "boss_rounds": 0,
		"node_kind": "", "node_state": {}, "sealed": null, "anchor_used": false,
		"start_coins": coins, "start_crystals": crystals, "start_tokens": tokens, "heroes_lost": 0,
		"rift_rank": rift_rank, "seed": randi(), "training": training, "biome": pick_biome(),
	}
	if training:
		# No elites in the training rift — a campfire takes their place.
		for layer in run["layers"]:
			layer["options"] = (layer["options"] as Array).map(func(o): return "campfire" if o == "elite" else o)
	ensure_champion()
	auto_resolve_single_option()
	save()
	state_changed.emit()


## The rift rank newly generated items drop at (GameData.ITEM_RANK_MULT): a
## Rift Map rift's own rank; Greater Rift reads as D; Endless climbs one rank
## per cycle from D; Lesser and anything outside a run (shop restock etc.) is F.
func loot_rank() -> String:
	if run.is_empty():
		return "F"
	var mapped: String = str(run.get("rift_rank", ""))
	if mapped != "":
		return mapped
	if run.get("endless", false):
		return str(GameData.RIFT_RANKS[min(GameData.RIFT_RANKS.size() - 1, 2 + int(run.get("cycle", 0)))]["id"])
	if run.get("diff_id", "") == "greater":
		return "D"
	return "F"


func _diff() -> Dictionary:
	if run.has("tower"):
		return _tower_diff(tower_floor_info(int(run["tower"])))
	var diff: Dictionary
	if run.get("endless", false):
		diff = Combat.endless_diff_for_cycle(int(run.get("cycle", 0)))
	else:
		diff = GameData.DIFFICULTIES[0]
		for d in GameData.DIFFICULTIES:
			if d["id"] == run["diff_id"]:
				diff = d
	if run.get("is_riftbreak", false):
		return _apply_riftbreak_severity(diff, int(run.get("riftbreak_severity", 0)))
	diff = _apply_rift_rank_modifiers(diff, str(run.get("rift_rank", "")))
	if not run.is_empty() and not run.get("is_riftbreak", false):
		diff = diff.duplicate()
		diff["biome"] = run_biome()
	if run.has("daily"):
		diff = _apply_daily(diff)
	if int(run.get("finale", 0)) > 0:
		return _apply_finale(diff)
	return _apply_training(diff) if run.get("training", false) else diff


func _apply_training(diff: Dictionary) -> Dictionary:
	var out := diff.duplicate(true)
	var t: Dictionary = GameData.TRAINING_RIFT
	out["floors"] = int(t["floors"])
	out["monster_hp"] = int(round(float(out["monster_hp"]) * float(t["monster_hp_mult"])))
	out["monster_dmg"] = int(round(float(out["monster_dmg"]) * float(t["monster_dmg_mult"])))
	return out


## Whether a staged feature (GameData.FEATURE_UNLOCKS) is open yet; anything
## not in the table is always open.
func feature_unlocked(id: String) -> bool:
	match id:
		"inventory": return not items.is_empty() or not relics.is_empty() or rifts_sealed > 0
		"medical": return runs_started > 1 or (runs_started == 1 and run.is_empty()) or rifts_sealed > 0
		"bestiary": return not monsters_seen.is_empty()
		"crafting", "quests", "management": return rifts_sealed >= 1
		"rift_map": return rifts_sealed >= 2
		"tower": return campaign_act >= 2
	return true


## Announces each feature the first time it unlocks (once per render, like
## check_milestones). Returns the ids newly announced.
func check_feature_unlocks() -> Array:
	var fresh: Array = []
	for f in GameData.FEATURE_UNLOCKS:
		if not features_seen.has(f) and feature_unlocked(f):
			features_seen.append(f)
			fresh.append(f)
	if fresh.size() == 1:
		var def: Dictionary = GameData.FEATURE_UNLOCKS[fresh[0]]
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": "New: %s" % def["name"], "text": str(def["news"])})
	elif fresh.size() > 1:
		# Several at once (e.g. the first seal): one toast, not a stack.
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": "New at camp", "text": ", ".join(fresh.map(func(f): return GameData.FEATURE_UNLOCKS[f]["name"])) + " — check the tabs above."})
	if not fresh.is_empty():
		save()
	return fresh


func hint_pending(id: String) -> bool:
	return not tips_off and not hints_seen.has(id)


func dismiss_hint(id: String) -> void:
	if not hints_seen.has(id):
		hints_seen.append(id)
	save()


## Scales a Riftbreak encounter's difficulty by the summed severity index of
## every merged pending rank (capped at 3x so a large backlog doesn't produce
## an unwinnable fight) — mirrors _apply_rift_rank_modifiers's shape but keyed
## off a raw severity number rather than a single rank id, since a Riftbreak
## can merge several different ranks into one fight.
func _apply_riftbreak_severity(diff: Dictionary, severity: int) -> Dictionary:
	if severity <= 0:
		return diff
	var mult: float = min(3.0, 1.0 + 0.15 * float(severity))
	var out := diff.duplicate(true)
	out["monster_hp"] = int(round(float(out["monster_hp"]) * mult))
	out["monster_dmg"] = int(round(float(out["monster_dmg"]) * mult))
	return out


func current_layer_options() -> Array:
	var layers: Array = run["layers"]
	return layers[int(run["pos"])]["options"]


func auto_resolve_single_option() -> void:
	var options := current_layer_options()
	var chosen: Dictionary = run["chosen"]
	if options.size() == 1 and not chosen.has(int(run["pos"])):
		choose_node_type(options[0])


func choose_node_type(kind: String) -> void:
	var chosen: Dictionary = run["chosen"]
	chosen[int(run["pos"])] = kind
	run["chosen"] = chosen
	run["node_kind"] = kind
	run["node_state"] = {}
	save()
	state_changed.emit()


func current_node_kind() -> String:
	var chosen: Dictionary = run.get("chosen", {})
	return chosen.get(int(run.get("pos", 0)), "")


## Rolls the battle backdrop the moment a fresh combat node is stood on
## (called from the pre-engage screen), rather than leaving it to
## Combat.start_combat() at Engage time — so the "encounter awaits" screen
## and the arena you fight in are the same room instead of a jarring swap.
func ensure_combat_bg() -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.has("bg_idx") or ns.has("combat_state"):
		return
	var bgs: Array = GameData.BIOMES.get(run_biome(), {}).get("backgrounds", [])
	ns["bg_idx"] = int(bgs[randi() % bgs.size()]) if not bgs.is_empty() else randi() % GameData.BATTLE_BACKGROUNDS.size()
	run["node_state"] = ns


func engage_node() -> void:
	var diff := _diff()
	var party: Array[Hero] = []
	party.assign(current_party().filter(func(h): return not h.is_downed() and h.hp > 0))
	if party.is_empty():
		return
	var kind := current_node_kind()
	if run.has("tower"):
		for h in party:
			h.hp = Combat.max_hp(h)
	seed(hash([int(run.get("seed", 0)), int(run.get("cycle", 0)), int(run["pos"])]))
	var state := Combat.start_combat(party, kind, diff, int(run["pos"]))
	randomize()
	var prior_bg_idx := int(run["node_state"].get("bg_idx", -1))
	if prior_bg_idx >= 0:
		state["background_idx"] = prior_bg_idx
	for m in state["monsters"]:
		# Boss names are generated as "Vaelith, Lesser Warden" — split off the
		# difficulty suffix so the same boss counts as seen regardless of tier.
		var mname := str(m["name"]).split(",")[0]
		if not monsters_seen.has(mname):
			monsters_seen.append(mname)
	# bg_idx stays alongside so a reload mid-fight (which drops combat_state)
	# brings back the same arena.
	run["node_state"] = {"type": "combat", "combat_state": state, "reward_chosen": false, "bg_idx": int(state.get("background_idx", prior_bg_idx))}
	save()
	state_changed.emit()


## Quick fight: engages the node and plays it out instantly with the auto
## policy (Combat.auto_action), landing straight on the result screen.
func quick_fight() -> void:
	engage_node()
	var st: Dictionary = run.get("node_state", {}).get("combat_state", {})
	for i in 600:
		if st.is_empty() or run.get("node_state", {}).has("result"):
			break
		var nxt := Combat.peek_next_turn(st)
		if str(nxt["type"]) == "hero":
			var h := Combat._find_party_hero(st["party"], str(nxt["id"]))
			if h and h.hp > 0:
				st["pending_actions"][h.id] = Combat.auto_action(st, h)
		resolve_turn_now()


## Sets one hero's pending action for the round about to resolve — a pure
## "what will they do" toggle, no combat math, mirrors how e.g.
## choose_node_type() just records a choice.
## `target` is a monster index into state["monsters"], meaningful only for
## "attack" — ignored (but still stored, harmlessly) for "ability"/"defend".
## Party Assembly's Front/Back toggle — checks the roster first, then the
## Champion (find_hero only searches `heroes`, and the Champion needs this
## toggle too since their row has no other picker interaction).
func set_hero_formation(hero_id: String, formation: String) -> void:
	var h := find_hero(hero_id)
	if not h and current_champion and current_champion.id == hero_id:
		h = current_champion
	if not h:
		return
	h.formation = formation
	save()
	state_changed.emit()


## `ally_id` is the hero a "guard" action protects.
func set_hero_action(hero_id: String, action: String, target: int = 0, ally_id: String = "") -> void:
	var ns: Dictionary = run.get("node_state", {})
	var state: Dictionary = ns.get("combat_state", {})
	if state.is_empty():
		return
	var pending: Dictionary = state["pending_actions"]
	pending[hero_id] = {"action": action, "target": target, "ally": ally_id}
	save()
	state_changed.emit()


func _apply_combat_outcome(outcome: Dictionary) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var state: Dictionary = ns.get("combat_state", {})
	if outcome["done"]:
		var result: Dictionary = outcome["result"]
		if not result["won"] and not bool(result.get("retreated", false)):
			result["defeat_reasons"] = Combat.defeat_reasons(state)
		if run.has("tower"):
			# The Tower pays per floor (first clear), not per fight.
			result["reward_options"] = []
			result["bonus_crystal"] = 0
			if result["won"]:
				result["tower"] = _complete_tower_floor(int(run["tower"]))
		var kind := current_node_kind()
		var hardcore: bool = run.get("hardcore", false)
		if result["won"]:
			# A Riftbreak win is a consequence contained, not an opportunity —
			# no Coin/Crystal reward, no reward-choice screen (Main.gd skips
			# straight to "Return to Terminal" for this case).
			if not run.get("is_riftbreak", false):
				coins += int(result["coin"])
				crystals += int(result["crystal"]) + int(result["bonus_crystal"])
				_attune_gear(state.get("party", []))
				if kind == "boss":
					run["boss_rounds"] = int(result["rounds"])
					var bname := str(result["monster_name"]).split(",")[0]
					if not bosses_defeated.has(bname):
						bosses_defeated.append(bname)
					bosses_won += 1
					_bump("boss:" + bname)
				elif kind == "elite":
					elites_won += 1
					if not run.has("tower"):
						result["boon_offer"] = roll_boon_offer()
			# Quest tallies — every monster in a won fight is by definition dead,
			# so state["monsters"] (still the pre-cleanup fight roster) is a
			# reliable "what did we just kill" list regardless of Riftbreak.
			for m in state.get("monsters", []):
				var mname := str(m.get("name", ""))
				if mname != "":
					monster_kill_counts[mname] = int(monster_kill_counts.get(mname, 0)) + 1
			var flawless := true
			for h in state.get("party", []):
				if h.hp <= 0:
					flawless = false
					break
			if flawless:
				flawless_wins += 1
			# An escort NPC (start_combat's ~25% chance on a "combat" node) pays
			# out a small bonus only if it survived the whole fight — dying
			# mid-fight is a softer failure than a party wipe, so it never
			# affects the fight's own win/loss. Gated the same as every other
			# reward here: a Riftbreak win is a consequence contained, not an
			# opportunity, so it grants nothing extra either.
			if kind != "boss" and not run.get("is_riftbreak", false) and not run.has("tower"):
				_note_injuries("critical" if kind == "elite" else "wounded")
			var escort: Dictionary = state.get("escort", {})
			if not run.get("is_riftbreak", false) and not escort.is_empty() and float(escort.get("hp", 0.0)) > 0.0:
				add_reputation(2)
				tokens += 1
				result["escort_saved"] = str(escort["name"])
		elif hardcore and not bool(result.get("retreated", false)):
			var party: Array[Hero] = state["party"]
			var lost := 0
			for h in party:
				if not h.is_champion:
					lost += 1
					_memorialize(h, "Fell in a Hardcore %s against %s" % [_run_label(), str(result.get("monster_name", "the rift")).split(",")[0]])
				heroes.erase(h)
			run["heroes_lost"] = int(run.get("heroes_lost", 0)) + lost
			if lost > 0:
				result["flavor"] = GameData.narrative_line("hardcore_hero_lost")
		# A Riftbreak that ends any way other than a win — a real loss OR a
		# retreat — means the rift's threat wasn't actually contained, so both
		# carry the same consequence. At/below Rank A that's a Coin/Crystal
		# "compensation" penalty on top of the normal downing (retreating
		# skips the downing itself, just not this penalty) — the game-over
		# branch (Rank S+) is handled entirely in Main.gd's result rendering,
		# before finish_run() is ever called, so it doesn't belong here.
		# Stashed on `result` (not applied here as a live coins/crystals
		# mutation) so Main.gd can render the exact amount without
		# re-computing it, and so this stays a pure one-time effect of the
		# round transitioning to "done" rather than something a render()
		# could accidentally repeat.
		if run.get("is_riftbreak", false) and not result["won"] and int(run.get("riftbreak_worst_index", 0)) <= 5:
			var sev := int(run.get("riftbreak_severity", 0))
			var comp_coins: int = min(coins, 20 + sev * 10)
			var comp_crystals: int = min(crystals, 5 + sev * 2)
			coins -= comp_coins
			crystals -= comp_crystals
			result["riftbreak_compensation_coins"] = comp_coins
			result["riftbreak_compensation_crystals"] = comp_crystals
		# Hero history (kills/knockouts are tallied inside Combat as they
		# happen; boss/elite wins are only known here) and any traits it earns.
		if result["won"] and kind in ["boss", "elite"]:
			for h in state.get("party", []):
				h.history[kind + "_kills"] = int(h.history.get(kind + "_kills", 0)) + 1
		var earned: Array[String] = []
		for h in state.get("party", []):
			earned.append_array(check_earned_traits(h))
		if not earned.is_empty():
			result["flavor"] = (str(result.get("flavor", "")) + " " + " ".join(earned)).strip_edges()
		ns["result"] = result
	run["node_state"] = ns
	save()
	state_changed.emit()


## Resolves whichever actor's turn is next (see Combat.resolve_turn — a
## living hero's pending action, or a living monster's retaliation). Once it
## reports the fight done, applies the same roster-level bookkeeping
## engage_node used to do in one shot (coin/crystal gain, boss_rounds
## tracking, hardcore hero removal on a real loss — not a retreat).
func resolve_turn_now() -> void:
	var ns: Dictionary = run.get("node_state", {})
	var state: Dictionary = ns.get("combat_state", {})
	if state.is_empty():
		return
	_apply_combat_outcome(Combat.resolve_turn(state))


## Ends the current fight by player choice, forfeiting rewards — heroes keep
## whatever HP they currently have, no one is downed or removed.
func combat_retreat() -> void:
	var ns: Dictionary = run.get("node_state", {})
	var state: Dictionary = ns.get("combat_state", {})
	if state.is_empty():
		return
	_apply_combat_outcome(Combat.retreat_combat(state))


func pick_combat_reward(idx: int) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var result: Dictionary = ns.get("result", {})
	var options: Array = result.get("reward_options", [])
	if ns.get("reward_chosen", false) or idx < 0 or idx >= options.size():
		return
	var opt: Dictionary = options[idx]
	if opt["loot_type"] == "item":
		var it: Item = opt["obj"]
		it.id = "it" + str(next_id)
		next_id += 1
		items.append(it)
	else:
		var r: Relic = opt["obj"]
		r.id = "rl" + str(next_id)
		next_id += 1
		r.equipped = Combat.equipped_relics().size() < relic_slot_cap()
		relics.append(r)
	ns["reward_chosen"] = true
	save()
	state_changed.emit()


# ---------------- Campfire / event / treasure nodes ----------------

## Campfire: one of Rest (heal), Train (XP) or Sharpen (abilities ready).
func campfire_choose(choice: String) -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.get("resolved", false):
		return
	var party := current_party().filter(func(h): return h.hp > 0)
	var log: Array[String] = []
	match choice:
		"rest":
			for h in party:
				h.hp = min(Combat.max_hp(h), h.hp + int(ceil(Combat.max_hp(h) * GameData.CAMPFIRE_HEAL_PCT)))
			log.append("The party rests by the fire and recovers %d%% HP." % int(GameData.CAMPFIRE_HEAL_PCT * 100))
		"train":
			for h in party:
				Combat.gain_xp(h, GameData.CAMPFIRE_TRAIN_XP)
			log.append("The party drills together: +%d XP each." % GameData.CAMPFIRE_TRAIN_XP)
		"sharpen":
			for h in party:
				h.ability_cooldown = 0
			log.append("Weapons sharpened, focus restored — every ability is ready.")
	ns["type"] = "campfire"
	ns["resolved"] = true
	ns["log"] = log
	run["node_state"] = ns
	save()
	state_changed.emit()


func ensure_event() -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.has("event"):
		return
	ns["type"] = "event"
	var seen: Array = run.get("events_seen", [])
	var fresh: Array = GameData.RIFT_EVENTS.filter(func(e): return not seen.has(e["id"]))
	if fresh.is_empty():
		fresh = GameData.RIFT_EVENTS
	ns["event"] = fresh[randi() % fresh.size()]
	seen.append(str(ns["event"]["id"]))
	run["events_seen"] = seen
	ns["resolved"] = false
	run["node_state"] = ns


func can_afford(cost: Dictionary) -> bool:
	return coins >= int(cost.get("coins", 0)) and crystals >= int(cost.get("crystals", 0))


func resolve_event(choice_idx: int) -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.get("resolved", false) or not ns.has("event"):
		return
	var choices: Array = ns["event"]["choices"]
	if choice_idx < 0 or choice_idx >= choices.size():
		return
	var c: Dictionary = choices[choice_idx]
	var cost: Dictionary = c.get("cost", {})
	if not can_afford(cost):
		return
	coins -= int(cost.get("coins", 0))
	crystals -= int(cost.get("crystals", 0))
	var log: Array[String] = []
	if c.has("check"):
		var chk: Dictionary = c["check"]
		var info := event_check(chk)
		var passed := randf() < float(info["chance"])
		log.append("%s check (%s, %d vs %d): %s." % [GameData.ATTR_LABEL[chk["attr"]], info["hero"], int(info["value"]), int(info["target"]), "passed" if passed else "failed"])
		log.append_array(_apply_event_effect(chk["win"] if passed else chk["lose"]))
	elif c.has("gamble"):
		var g: Dictionary = c["gamble"]
		var won := randf() < float(g["chance"])
		log.append("Luck is with you." if won else "Luck is not with you.")
		log.append_array(_apply_event_effect(g["win"] if won else g["lose"]))
	else:
		log.append_array(_apply_event_effect(c.get("effect", {})))
	if log.is_empty():
		log.append("You move on.")
	ns["resolved"] = true
	ns["log"] = log
	run["node_state"] = ns
	save()
	state_changed.emit()


## An event attribute check: the party member with the best score, that
## score, the target, and the chance to pass.
func event_check(chk: Dictionary) -> Dictionary:
	var attr := str(chk["attr"])
	var party := current_party().filter(func(h): return h.hp > 0)
	var avg_lv := 1.0
	if not party.is_empty():
		avg_lv = party.reduce(func(acc, h): return acc + h.level, 0) / float(party.size())
	# Attributes grow ~3 points a level, so the bar rises with the party.
	var target := int(chk["target"]) + int(round(GameData.EVENT_CHECK_PER_LEVEL * avg_lv)) + (0 if str(run.get("diff_id", "lesser")) == "lesser" and str(run.get("rift_rank", "")) == "" else 3)
	var best: Hero = null
	for h in current_party():
		if h.hp > 0 and (best == null or Combat.hero_attr(h, attr) > Combat.hero_attr(best, attr)):
			best = h
	var value := Combat.hero_attr(best, attr) if best else GameData.ATTR_BASELINE
	var chance := clampf(GameData.EVENT_CHECK_BASE + GameData.EVENT_CHECK_PER_POINT * (value - target), 0.1, 0.95)
	return {"hero": best.name.split(" the ")[0] if best else "nobody", "value": value, "target": target, "chance": chance}


func _event_amount(v) -> int:
	return randi_range(int(v[0]), int(v[1])) if v is Array else int(v)


func _apply_event_effect(e: Dictionary) -> Array[String]:
	var log: Array[String] = []
	var party := current_party().filter(func(h): return h.hp > 0)
	if e.has("coins"):
		var n := _event_amount(e["coins"])
		coins += n
		log.append("+%d Coins." % n)
	if e.has("crystals"):
		var n2 := _event_amount(e["crystals"])
		crystals += n2
		log.append("+%d Crystals." % n2)
	if e.has("reputation"):
		var r := int(e["reputation"])
		add_reputation(r)
		log.append("%+d Reputation." % r)
	if e.has("xp_all"):
		for h in party:
			Combat.gain_xp(h, int(e["xp_all"]))
		log.append("Every hero gains %d XP." % int(e["xp_all"]))
	if e.has("heal_pct"):
		for h in party:
			h.hp = min(Combat.max_hp(h), h.hp + int(ceil(Combat.max_hp(h) * float(e["heal_pct"]))))
		log.append("The party heals %d%% HP." % int(float(e["heal_pct"]) * 100))
	if e.has("hurt_pct"):
		for h in party:
			h.hp = max(1, h.hp - int(ceil(Combat.max_hp(h) * float(e["hurt_pct"]))))
		log.append("Everyone loses %d%% HP." % int(float(e["hurt_pct"]) * 100))
	if e.get("ready", false):
		for h in party:
			h.ability_cooldown = 0
		log.append("Every ability is ready.")
	if e.has("tokens"):
		tokens += int(e["tokens"])
		log.append("+%d Seal Tokens." % int(e["tokens"]))
	if e.has("tonic"):
		var add := mini(int(e["tonic"]), GameData.TONIC_CAP - tonics)
		tonics += add
		log.append("+%d Field Tonic." % add if add > 0 else "You can't carry another tonic.")
	if e.has("shield"):
		run["shield"] = int(run.get("shield", 0)) + int(e["shield"])
		log.append("A %d-point shield against hazards." % int(e["shield"]))
	for kind in ["item", "relic"]:
		if e.has(kind):
			var rr := Combat.weighted_rarity()
			if _rarity_order(rr) < _rarity_order(str(e[kind])):
				rr = str(e[kind])
			var lt: Dictionary = {"loot_type": "item", "obj": Combat.gen_item(rr)} if kind == "item" else {"loot_type": "relic", "obj": Combat.gen_relic(rr)}
			_grant_loot(lt)
			log.append("You receive: %s (%s)." % [lt["obj"].name, rr.capitalize()])
	if e.has("loot"):
		var rarity := Combat.weighted_rarity()
		if _rarity_order(rarity) < _rarity_order(str(e["loot"])):
			rarity = str(e["loot"])
		var loot: Dictionary = Combat.gen_loot(rarity)
		_grant_loot(loot)
		log.append("You receive: %s (%s)." % [loot["obj"].name, rarity.capitalize()])
	return log


func _rarity_order(r: String) -> int:
	return ["common", "rare", "epic", "legendary"].find(r)


## Adds a rolled loot entry ({loot_type, obj}) to the guild's stash.
func _grant_loot(loot: Dictionary) -> void:
	if loot["loot_type"] == "item":
		var it: Item = loot["obj"]
		it.id = "it" + str(next_id)
		next_id += 1
		items.append(it)
	else:
		var r: Relic = loot["obj"]
		r.id = "rl" + str(next_id)
		next_id += 1
		r.equipped = Combat.equipped_relics().size() < relic_slot_cap()
		relics.append(r)


## Treasure: pick one of two loot drops, no fight.
func ensure_treasure() -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.has("options"):
		return
	ns["type"] = "treasure"
	ns["options"] = [Combat.gen_loot(Combat.weighted_rarity()), Combat.gen_loot(Combat.weighted_rarity())]
	ns["picked"] = false
	run["node_state"] = ns


func pick_treasure(idx: int) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var options: Array = ns.get("options", [])
	if ns.get("picked", false) or idx < 0 or idx >= options.size():
		return
	_grant_loot(options[idx])
	ns["picked"] = true
	save()
	state_changed.emit()


func ensure_hazard() -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.has("hazard"):
		return
	# A mapped rift's "hazard_severity_up" modifier (0-2) biases the roll
	# toward worse hazards by filtering out the mildest ones first, rather
	# than reordering HAZARD_TYPES itself — falls back to the full list if
	# filtering would leave nothing (never happens at today's 3 severity
	# steps against 5 hazard types spanning dmg_mult 0.8-1.3, but kept safe).
	var severity_up := int(_diff().get("hazard_severity_up", 0))
	var min_mult: float = [0.0, 1.0, 1.2][clampi(severity_up, 0, 2)]
	var eligible: Array = GameData.HAZARD_TYPES.filter(func(h): return float(h["dmg_mult"]) >= min_mult)
	if eligible.is_empty():
		eligible = GameData.HAZARD_TYPES
	var hz: Dictionary = eligible[randi() % eligible.size()]
	ns["hazard"] = hz
	ns["resolved"] = false
	run["node_state"] = ns
	var hz_id := str(hz["id"])
	if not hazards_seen.has(hz_id):
		hazards_seen.append(hz_id)


## Shared core for all 3 hazard choices — `dmg_scale` multiplies the normal
## damage roll (1.0 = unchanged), `bonus_chance_override` replaces the
## hazard's own bonus_chance when >= 0.0 (a negative value means "use the
## hazard's own chance unmodified").
## What a hazard choice would do, without doing it: the hazard's damage is
## fixed (no roll), so this is exact. `dmg_scale` is 1.0 to push through, 2.0
## to risk it. {anchor, total, absorbed, per_hero, downs: [hero names]}.
## _apply_hazard uses the same numbers, so the preview can't drift from it.
func hazard_preview(dmg_scale: float) -> Dictionary:
	ensure_hazard()
	var party: Array[Hero] = []
	party.assign(current_party().filter(func(h): return not h.is_downed() and h.hp > 0))
	if not run.get("anchor_used", false) and anchor_artifact():
		return {"anchor": true, "total": 0, "absorbed": 0, "per_hero": 0, "downs": [], "party": party}
	var hz: Dictionary = run["node_state"]["hazard"]
	var dmg: float = (6.0 + int(_diff()["floors"]) * 2.0) * float(hz["dmg_mult"]) * dmg_scale
	var guard: float = min(0.9, hazard_severity_reduction() + Combat.party_skill_total(party, "hazard_guard_pct") + Combat.relic_special_total("hazard_guard_pct") + Combat.relic_drawback_total("hazard_guard_pct") + Combat.synergy_value_for("hazard_guard_pct") + Combat.bond_bonus_for(party, "hazard_guard_pct"))
	dmg = round(dmg * (1.0 - guard))
	var absorbed: int = min(int(run.get("shield", 0)), int(dmg))
	dmg -= absorbed
	var per: float = dmg / party.size() if party.size() > 0 else 0.0
	var downs: Array[String] = []
	for h in party:
		if dmg > 0 and int(round(h.hp - per)) <= 0:
			downs.append(h.name.split(" the ")[0])
	return {"anchor": false, "total": int(dmg), "absorbed": absorbed, "per_hero": int(round(per)), "downs": downs, "party": party}


func _apply_hazard(dmg_scale: float, bonus_chance_override: float) -> void:
	var pv := hazard_preview(dmg_scale)
	var party: Array[Hero] = pv["party"]
	var ns: Dictionary = run["node_state"]
	var hz: Dictionary = ns["hazard"]
	var log: Array[String] = []
	if pv["anchor"]:
		run["anchor_used"] = true
		log.append("The Anchor Artifact snuffs the hazard before it strikes.")
	else:
		var absorbed: int = pv["absorbed"]
		run["shield"] = int(run.get("shield", 0)) - absorbed
		if absorbed > 0:
			log.append("Relic wards absorb %d of the hazard." % absorbed)
		var dmg: int = pv["total"]
		if dmg > 0 and party.size() > 0:
			var per: float = float(dmg) / party.size()
			for h in party:
				h.hp = max(1 if hazards_nonlethal() else 0, int(round(h.hp - per)))
				if h.hp <= 0:
					knock_out(h)
			log.append("The hazard deals %d damage across the party." % dmg)
			_note_injuries("wounded")
	var bonus_chance: float = float(hz["bonus_chance"]) if bonus_chance_override < 0.0 else bonus_chance_override
	if randf() < bonus_chance:
		var c := randi() % 5 + 2
		if hz["bonus_type"] == "coins":
			coins += c
			log.append("You scavenge %d stray Coins." % c)
		else:
			crystals += c
			log.append("Stray Crystals found in the rubble: +%d." % c)
	ns["resolved"] = true
	ns["log"] = log
	run["node_state"] = ns
	save()
	state_changed.emit()


## The safe default: full damage roll, the hazard's own normal bonus chance.
func push_through_hazard() -> void:
	_apply_hazard(1.0, -1.0)


## The gambler's choice: double damage exposure, guaranteed bonus reward.
func risk_hazard() -> void:
	_apply_hazard(2.0, 1.0)


const HAZARD_BYPASS_COST := 15


func can_afford_hazard_bypass() -> bool:
	return crystals >= HAZARD_BYPASS_COST


## Pay Crystals to skip the hazard entirely — no damage, no reward, no
## resistance/anchor math (there's nothing to resist or block).
func bypass_hazard() -> void:
	if not can_afford_hazard_bypass():
		return
	ensure_hazard()
	var ns: Dictionary = run["node_state"]
	crystals -= HAZARD_BYPASS_COST
	ns["resolved"] = true
	ns["log"] = ["You pay %d Crystals and bypass the hazard entirely." % HAZARD_BYPASS_COST]
	run["node_state"] = ns
	save()
	state_changed.emit()


func ensure_shop_offers() -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.get("type") == "shop":
		return
	var boosted := pending_shop_boost
	var offers: Array = []
	for i in 3:
		offers.append(_gen_shop_offer((boosted or shop_guaranteed_epic()) and i == 0))
	if boosted:
		pending_shop_boost = false
	run["node_state"] = {"type": "shop", "offers": offers, "rerolls": 0}


func _gen_shop_offer(force_epic: bool = false) -> Dictionary:
	var rarity := "epic" if force_epic else Combat.weighted_rarity()
	var loot: Dictionary = {"loot_type": "relic", "obj": Combat.gen_relic(rarity)} if force_epic else Combat.gen_loot(rarity)
	var rar := GameData.find_rarity(rarity)
	loot["price"] = max(4, int(round((10.0 + 15.0 * float(rar["mult"])) * (1.0 - merchant_price_reduction()))))
	loot["bought"] = false
	return loot


## Rerolling a shop costs more each time in the same shop.
func shop_reroll_cost() -> int:
	return 8 + 6 * int(run.get("node_state", {}).get("rerolls", 0))


## Replaces every offer not yet bought with a fresh one.
func reroll_shop() -> void:
	var ns: Dictionary = run.get("node_state", {})
	var cost := shop_reroll_cost()
	if ns.get("type") != "shop" or coins < cost:
		return
	coins -= cost
	var offers: Array = ns["offers"]
	for i in offers.size():
		if not offers[i].get("bought", false):
			offers[i] = _gen_shop_offer()
	ns["rerolls"] = int(ns.get("rerolls", 0)) + 1
	save()
	state_changed.emit()


func buy_shop_offer(idx: int) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var offers: Array = ns.get("offers", [])
	if idx < 0 or idx >= offers.size():
		return
	var off: Dictionary = offers[idx]
	if off.get("bought", false):
		return
	if coins < int(off["price"]):
		return
	coins -= int(off["price"])
	off["bought"] = true
	if off["loot_type"] == "item":
		var it: Item = off["obj"]
		it.id = "it" + str(next_id)
		next_id += 1
		items.append(it)
	else:
		var r: Relic = off["obj"]
		r.id = "rl" + str(next_id)
		next_id += 1
		r.equipped = Combat.equipped_relics().size() < relic_slot_cap()
		relics.append(r)
	save()
	state_changed.emit()


## Ability cooldowns live on the Hero (not reset per fight) and already tick
## down once per combat round inside Combat.resolve_round. A shop/hazard node
## has no rounds of its own, so without this it would give abilities a free
## pass — call this once per non-combat node so cooldowns count every node
## as a "turn", combat or not.
func tick_ability_cooldowns() -> void:
	for h in current_party():
		if h.ability_cooldown > 0:
			h.ability_cooldown -= 1


func advance_node() -> void:
	if not pending_injuries().is_empty():
		return   # decide what happens to the downed first (see _note_injuries)
	if not (current_node_kind() in ["combat", "boss", "elite"]):
		tick_ability_cooldowns()
	run["pos"] = int(run["pos"]) + 1
	run["node_state"] = {}
	auto_resolve_single_option()
	save()
	state_changed.emit()


func seal_rift() -> void:
	_rescue_left_behind()
	if int(run.get("finale", 0)) > 0 and int(run["finale"]) == campaign_act:
		_complete_act(campaign_act)
	var diff := _diff()
	var fast_clear: bool = int(run.get("boss_rounds", 99)) <= 6
	var token_mult: float = seal_token_bonus() * (1.5 if run.get("hardcore", false) else 1.0)
	var earned_tokens := int(round(float(diff["token_base"]) * token_mult))
	var got_detector := false
	if randf() < float(diff["detector_chance"]) + detector_drop_bonus():
		var tier: String = "ascendant" if run.get("endless", false) else str(diff["id"])
		detectors.append({"id": "d" + str(next_id), "tier": tier})
		next_id += 1
		got_detector = true
	# Only a Rift Map rift carries a rank at all (run["rift_rank"], set by
	# start_map_rift) — a Lesser/Greater/Endless Riftbreak never drops one.
	var got_stone := ""
	var mapped_rank: String = str(run.get("rift_rank", ""))
	if mapped_rank != "":
		best_rift_rank_sealed = max(best_rift_rank_sealed, GameData.rift_rank_index(mapped_rank))
	if mapped_rank != "":
		var stone_tier := GameData.stone_tier_for_rift_rank(mapped_rank)
		if stone_tier != "" and randf() < GameData.EVOLUTION_STONE_DROP_CHANCE:
			evolution_stones[stone_tier] = int(evolution_stones.get(stone_tier, 0)) + 1
			got_stone = stone_tier
	tokens += earned_tokens
	var just_unlocked_greater := rifts_sealed == 2
	rifts_sealed += 1
	# Guild Board tallies (see _quest_current).
	if mapped_rank != "":
		_bump("rank_seals:%d" % GameData.rift_rank_index(mapped_rank))
	if str(run.get("map_uid", "")) != "":
		_bump("map:" + str(run["map_uid"]))
	if str(diff.get("id", "")) == "greater":
		_bump("greater_seals")
	if not bool(run.get("any_ko", false)):
		_bump("flawless_rifts")
	if (run.get("hero_ids", []) as Array).size() <= 2:
		_bump("small_seals")
	if run.get("hardcore", false):
		_bump("hardcore_seals")
	var flavor := GameData.narrative_line("fast_clear" if fast_clear else "rift_sealed")
	if just_unlocked_greater:
		flavor += " " + GameData.narrative_line("greater_rift_unlocked")
	# Rift history + bonds: every roster hero who saw this rift through counts
	# it, and every pair of them grows their bond (see GameData.BOND_LEVEL_RIFTS).
	var sealers: Array[Hero] = []
	sealers.assign(current_party().filter(func(h): return not h.is_champion))
	for i in sealers.size():
		sealers[i].history["rifts_cleared"] = int(sealers[i].history.get("rifts_cleared", 0)) + 1
		for j in range(i + 1, sealers.size()):
			var key := _bond_key(sealers[i].id, sealers[j].id)
			var before := GameData.bond_level(int(bonds.get(key, 0)))
			bonds[key] = int(bonds.get(key, 0)) + 1
			if GameData.bond_level(int(bonds[key])) > before:
				flavor += " %s and %s's bond deepens (Lv%d)." % [sealers[i].name.split(" the ")[0], sealers[j].name.split(" the ")[0], before + 1]
				push_toast(sealers[i], "Bond deepened — Lv%d" % (before + 1), "%s & %s: +%d%% party damage while both stand" % [sealers[i].name.split(" the ")[0], sealers[j].name.split(" the ")[0], int(round(GameData.BOND_DMG_PER_LEVEL * (before + 1) * 100))])
	for h in sealers:
		for line in check_earned_traits(h):
			flavor += " " + line
	triage_used_this_cycle = false
	refresh_recruit_pool()
	# The Champion stays; standing at the seal counts toward their oath, and a
	# fresh set of offers arrives if you'd rather swap.
	if current_champion and current_champion.hp > 0:
		current_champion.oath += 1
		if current_champion.oath == GameData.CHAMPION_OATH_SEALS:
			push_toast(current_champion, "An oath offered", "%s would swear to the guild — see Recruits" % current_champion.name)
	refresh_champion_offers()
	# A Rift Map bounty (see resolve_rift_map/start_map_rift) — {} for any
	# rift not entered from the map, or a mapped rift that didn't roll one.
	var bounty: Dictionary = run.get("bounty", {})
	if not bounty.is_empty():
		coins += int(bounty.get("coins", 0))
		add_reputation(int(bounty.get("reputation", 0)))
	if run.get("endless", false):
		var new_cycle: int = int(run.get("cycle", 0)) + 1
		if new_cycle > best_endless_cycle:
			best_endless_cycle = new_cycle
		run["cycle"] = new_cycle
		var extra := Combat.build_layers(Combat.endless_diff_for_cycle(new_cycle))
		var layers: Array = run["layers"]
		var old_len := layers.size()
		layers.append_array(extra)
		run["layers"] = layers
		run["pos"] = old_len
		run["node_state"] = {}
		run["boss_rounds"] = 0
		auto_resolve_single_option()
		run["sealed"] = {"tokens": earned_tokens, "fast_clear": fast_clear, "got_detector": got_detector, "got_stone": got_stone, "continuing": true, "cycle": new_cycle, "flavor": flavor, "bounty": bounty}
		save()
		state_changed.emit()
		return
	run["sealed"] = {"tokens": earned_tokens, "fast_clear": fast_clear, "got_detector": got_detector, "got_stone": got_stone, "flavor": flavor, "bounty": bounty}
	if run.has("daily"):
		run["sealed"]["daily"] = _complete_daily()
	save()
	state_changed.emit()


func continue_endless() -> void:
	run["sealed"] = null
	save()
	state_changed.emit()


## Earned by playing (sealing 3 rifts, lesser/greater/endless all count),
## not by spending Guild Management currency like every other unlock today.
## Pays out a finished Endless Rift (survivors) run: coins and crystals for
## time and kills, XP for every hero, loot for elites and wardens. Returns
## what was earned for the result screen.
func finish_survivors(r: SurvivorsRun) -> Dictionary:
	var pay := r.rewards()
	coins += int(pay["coins"])
	crystals += int(pay["crystals"])
	var names: Array = []
	for h in r.heroes:
		Combat.gain_xp(h["hero"], int(pay["xp"]))
		names.append(h["hero"].name.split(" the ")[0])
	var loot_names: Array = []
	for i in int(pay["loot"]):
		var loot := Combat.gen_loot(Combat.weighted_rarity())
		_grant_loot(loot)
		loot_names.append(loot["obj"].name)
	for name in r.kill_counts:
		monster_kill_counts[name] = int(monster_kill_counts.get(name, 0)) + int(r.kill_counts[name])
	var t := int(r.time)
	var best := t > best_endless_time
	best_endless_time = maxi(best_endless_time, t)
	endless_runs += 1
	runs_finished += 1
	run_history.push_front({"day": day, "kind": "Endless Rift", "result": "Survived", "floor": "", "time": t, "kills": r.kills,
		"heroes": names, "boons": [], "coins": int(pay["coins"]), "crystals": int(pay["crystals"])})
	if run_history.size() > GameData.RUN_HISTORY_MAX:
		run_history.resize(GameData.RUN_HISTORY_MAX)
	save()
	state_changed.emit()
	return {"coins": int(pay["coins"]), "crystals": int(pay["crystals"]), "xp": int(pay["xp"]), "loot": loot_names, "best": best}


func greater_rift_unlocked() -> bool:
	return campaign_act >= 2


func endless_unlocked() -> bool:
	return campaign_act >= 3


# ---------------- Campaign ----------------

func campaign_done() -> bool:
	return campaign_act > GameData.CAMPAIGN.size()


func current_act() -> Dictionary:
	return {} if campaign_done() else GameData.CAMPAIGN[campaign_act - 1]


func campaign_objective_progress(o: Dictionary) -> int:
	var t := str(o["type"])
	if t.begins_with("boss:"):
		return int(quest_tally.get(t, 0))
	match t:
		"rifts_sealed": return rifts_sealed
		"heroes": return heroes.size()
		"greater_seals": return int(quest_tally.get("greater_seals", 0))
		"reputation": return reputation
		"map_rank": return best_rift_rank_sealed + 1 if best_rift_rank_sealed >= int(o["target"]) else 0
		"quests_done": return int(quest_tally.get("quests_done", 0))
	return 0


func campaign_objective_met(o: Dictionary) -> bool:
	if str(o["type"]) == "map_rank":
		return best_rift_rank_sealed >= int(o["target"])
	return campaign_objective_progress(o) >= int(o["target"])


func finale_ready() -> bool:
	var act := current_act()
	return not act.is_empty() and (act["objectives"] as Array).all(func(o): return campaign_objective_met(o))


func finale_recommended_power() -> int:
	var act := current_act()
	if act.is_empty():
		return 0
	return int(round(Combat.recommended_power(str(act["tier"]), false) * float(act["mult"])))


## Starts the current act's finale rift: its tier's rift, tougher by the act's
## mult, ending in the act's named foe.
func start_finale(hero_ids: Array[String], starting_relic: Relic) -> void:
	if not finale_ready():
		return
	var act := current_act()
	start_run(str(act["tier"]), hero_ids, starting_relic, false, false)
	run["finale"] = int(act["act"])
	run["training"] = false
	run["biome"] = str(GameData.ACT_BIOME[int(act["act"])])
	run["layers"] = Combat.build_layers(_diff())
	save()


## A biome for a new rift: the Vale in Act I, the Vale or the Marshes in Act
## II, any of the three after that.
func pick_biome() -> String:
	var open := ["vale"] if campaign_act <= 1 else (["vale", "marsh", "marsh"] if campaign_act == 2 else ["vale", "marsh", "ashen"])
	return str(open[randi() % open.size()])


## The run's biome (Endless rotates through all three, one per cycle).
func run_biome() -> String:
	if run.get("endless", false):
		return ["vale", "marsh", "ashen"][int(run.get("cycle", 0)) % 3]
	return str(run.get("biome", "vale"))


func _apply_finale(diff: Dictionary) -> Dictionary:
	var act: Dictionary = GameData.CAMPAIGN[int(run["finale"]) - 1]
	var out := diff.duplicate(true)
	out["monster_hp"] = int(round(float(out["monster_hp"]) * float(act["mult"])))
	out["monster_dmg"] = int(round(float(out["monster_dmg"]) * float(act["mult"])))
	out["boss_name"] = str(act["boss"])
	out["boss_double_mechanic"] = int(act["act"]) >= 3
	return out


## Sealing a finale: the act's reward, a Legendary relic, the next act.
func _complete_act(act_num: int) -> void:
	var act: Dictionary = GameData.CAMPAIGN[act_num - 1]
	var reward: Dictionary = act["reward"]
	crystals += int(reward.get("crystals", 0))
	tokens += int(reward.get("tokens", 0))
	var relic := Combat.gen_unique_relic()
	relics.append(relic)
	campaign_act = act_num + 1
	var subtitle := "Act %s complete — +%d Crystals, +%d Seal Tokens, %s" % [_roman(act_num), int(reward.get("crystals", 0)), int(reward.get("tokens", 0)), relic.name]
	if str(act["opens"]) != "":
		subtitle += " · %s unlocked" % act["opens"]
	pending_stories.append({"title": act["finale"] + " — sealed", "subtitle": subtitle, "text": str(act["outro"])})
	if campaign_done():
		pending_stories.append({"title": "The End", "subtitle": "The campaign is complete", "text": "Thank you for playing. Your guild endures: push the Endless Rift, clear the Rift Map, and take on the Guild Board for as long as rifts keep opening."})
	else:
		pending_stories.append(_act_intro_card(campaign_act))


func _act_intro_card(act_num: int) -> Dictionary:
	var act: Dictionary = GameData.CAMPAIGN[act_num - 1]
	return {"title": "Act %s — %s" % [_roman(act_num), act["name"]], "subtitle": "Foe: %s" % act["foe"], "text": str(act["intro"])}


static func _roman(n: int) -> String:
	return ["I", "II", "III", "IV"][clampi(n - 1, 0, 3)]


# ---------------- Daily Rift ----------------

static func daily_id() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


## Today's Daily Rift: difficulty, rule, starting boon, region and seed.
func daily_info(day: int = -1) -> Dictionary:
	if day < 0:
		day = daily_id()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["daily", day])
	var rules: Array = GameData.TOWER_RULES.filter(func(r): return not r.has("party_cap"))
	var rule: Dictionary = rules[rng.randi() % rules.size()]
	var boon: Dictionary = GameData.BOONS[rng.randi() % GameData.BOONS.size()]
	var biomes := ["vale", "marsh", "ashen"]
	return {"day": day, "diff_id": "greater" if greater_rift_unlocked() else "lesser", "rule": rule, "boon": str(boon["id"]),
		"biome": biomes[rng.randi() % biomes.size()], "seed": rng.randi()}


func daily_available() -> bool:
	return rifts_sealed >= 1 and daily_attempt_day != daily_id()


func start_daily(hero_ids: Array[String]) -> void:
	if not daily_available():
		return
	var info := daily_info()
	start_run(str(info["diff_id"]), hero_ids, null, false, false)
	run["daily"] = int(info["day"])
	run["training"] = false
	run["seed"] = int(info["seed"])
	run["biome"] = str(info["biome"])
	run["boons"] = [info["boon"]]
	seed(int(info["seed"]))
	run["layers"] = Combat.build_layers(_diff())
	randomize()
	run["pos"] = 0
	run["chosen"] = {}
	auto_resolve_single_option()
	daily_attempt_day = int(info["day"])
	save()
	state_changed.emit()


func _apply_daily(diff: Dictionary) -> Dictionary:
	var rule: Dictionary = daily_info(int(run["daily"]))["rule"]
	var d := diff.duplicate(true)
	d.merge(rule.get("diff", {}), true)
	var hp := float(d["monster_hp"]) * float(d.get("hp_mult", 1.0)) * (2.0 if d.get("tower_single", false) else 1.0)
	d["monster_hp"] = int(round(hp))
	d["monster_dmg"] = int(round(float(d["monster_dmg"]) * float(d.get("dmg_mult", 1.0))))
	return d


## Sealing today's Daily Rift: the bonus, and the streak.
func _complete_daily() -> Dictionary:
	var day := int(run["daily"])
	daily_clears += 1
	daily_streak = daily_streak + 1 if daily_last_clear == day - 1 else 1
	daily_last_clear = day
	var cr := GameData.DAILY_CLEAR_CRYSTALS + GameData.DAILY_CLEAR_CRYSTALS_PER_ACT * mini(campaign_act, 3)
	crystals += cr
	tokens += GameData.DAILY_CLEAR_TOKENS
	return {"crystals": cr, "tokens": GameData.DAILY_CLEAR_TOKENS, "streak": daily_streak}


# ---------------- Records: run history, memorial ----------------

func _run_label() -> String:
	if run.has("daily"):
		return "Daily Rift"
	if run.get("endless", false):
		return "Endless Rift"
	if str(run.get("rift_rank", "")) != "":
		return "Rank %s rift" % run["rift_rank"]
	if int(run.get("finale", 0)) > 0:
		return "Act %s finale" % _roman(int(run["finale"]))
	return str(_diff().get("name", "Rift"))


## Appends the run that's ending to run_history (newest first).
func _record_run(outcome: String) -> void:
	if run.is_empty() or run.has("tower") or run.get("is_riftbreak", false):
		return
	var names: Array = []
	for h in current_party():
		names.append(h.name.split(" the ")[0])
	var entry := {"day": day, "kind": _run_label(), "result": outcome,
		"floor": "%d/%d" % [mini(int(run.get("pos", 0)) + 1, (run.get("layers", []) as Array).size()), (run.get("layers", []) as Array).size()],
		"cycle": int(run.get("cycle", 0)), "heroes": names, "boons": run.get("boons", []),
		"coins": coins - int(run.get("start_coins", coins)), "crystals": crystals - int(run.get("start_crystals", crystals))}
	run_history.push_front(entry)
	if run_history.size() > GameData.RUN_HISTORY_MAX:
		run_history.resize(GameData.RUN_HISTORY_MAX)
	runs_finished += 1


func _run_outcome() -> String:
	if run.get("sealed") != null:
		return "Sealed"
	var res: Dictionary = run.get("node_state", {}).get("result", {})
	if bool(res.get("retreated", false)):
		return "Retreated"
	if not res.is_empty() and not bool(res.get("won", true)):
		return "Defeated"
	return "Left"


## Remembers a hero lost for good (Hardcore, or left behind in a rift).
func _memorialize(h: Hero, cause: String) -> void:
	if h.is_champion:
		return
	fallen.push_front({"name": h.name, "cls_id": h.cls_id, "pool_id": h.pool_id, "rank": h.rank, "level": h.level,
		"day": day, "cause": cause, "rifts": int(h.history.get("rifts_cleared", 0)), "kills": int(h.history.get("kills", 0))})
	heroes_lost_total += 1


# ---------------- Run boons ----------------

func boon_family_counts() -> Dictionary:
	var counts := {}
	for id in run.get("boons", []):
		var fam := str(GameData.find_boon(str(id)).get("family", ""))
		if fam != "":
			counts[fam] = int(counts.get(fam, 0)) + 1
	return counts


## Three boons not yet owned; when you already lean into a family, one slot
## favours it so a build can come together.
func roll_boon_offer() -> Array:
	var owned: Array = run.get("boons", [])
	var pool: Array = GameData.BOONS.filter(func(b): return not owned.has(b["id"])).map(func(b): return str(b["id"]))
	pool.shuffle()
	var offer: Array = []
	var counts := boon_family_counts()
	if not counts.is_empty():
		var fams := counts.keys()
		var fav := str(fams[randi() % fams.size()])
		for id in pool:
			if GameData.find_boon(id)["family"] == fav:
				offer.append(id)
				break
	for id in pool:
		if offer.size() >= GameData.BOON_OFFER_SIZE:
			break
		if not offer.has(id):
			offer.append(id)
	return offer


## Takes offered boon `idx` (or -1 to skip) from the current fight's result.
func pick_boon(idx: int) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var res: Dictionary = ns.get("result", {})
	var offer: Array = res.get("boon_offer", [])
	if ns.get("boon_chosen", false) or offer.is_empty():
		return
	if idx >= 0 and idx < offer.size():
		var boons: Array = run.get("boons", [])
		boons.append(str(offer[idx]))
		run["boons"] = boons
		if boon_family_counts().values().any(func(n): return int(n) >= 4):
			boon_set4_reached = true
	ns["boon_chosen"] = true
	run["node_state"] = ns
	save()
	state_changed.emit()


func boon_pending() -> bool:
	var ns: Dictionary = run.get("node_state", {})
	return not (ns.get("result", {}).get("boon_offer", []) as Array).is_empty() and not ns.get("boon_chosen", false)


# ---------------- Guild Orders ----------------

## Orders whose node is at GameData.ORDER_UNLOCK_LEVEL or above.
func orders_unlocked() -> Array:
	return GameData.GUILD_ORDERS.keys().filter(func(id): return lvl(str(GameData.GUILD_ORDERS[id]["node"])) >= GameData.ORDER_UNLOCK_LEVEL)


## Orders per rift: 1 once any is unlocked, +1 at Renowned and Legendary tier.
func orders_per_rift() -> int:
	if orders_unlocked().is_empty():
		return 0
	var total := int(Combat.guild_tier_info()["total"])
	return 1 + (1 if total >= 25 else 0) + (1 if total >= 40 else 0)


func orders_left() -> int:
	return maxi(0, orders_per_rift() - int(run.get("orders_used", 0)))


## "" if `id` can be used right now, else why not.
func order_blocker(id: String) -> String:
	if run.is_empty():
		return "Only inside a rift"
	if run.has("tower"):
		return "The Tower is a trial: no orders"
	if not orders_unlocked().has(id):
		return "Not unlocked"
	if orders_left() <= 0:
		return "No orders left this rift"
	var ns: Dictionary = run.get("node_state", {})
	var in_fight: bool = ns.has("combat_state") and not ns.has("result")
	match id:
		"supply":
			if in_fight:
				return "Not during a fight"
			if not current_party().any(func(h): return h.hp > 0 and h.hp < Combat.max_hp(h)):
				return "Everyone is at full HP"
		"rally":
			if not in_fight:
				return "Only during a fight"
		"requisition":
			var res: Dictionary = ns.get("result", {})
			if not bool(res.get("won", false)) or (res.get("reward_options", []) as Array).is_empty() or ns.get("reward_chosen", false):
				return "Only when choosing a fight's loot"
		"scout":
			if current_node_kind() != "" or current_layer_options().size() < 2:
				return "Only when choosing a path"
	return ""


func use_order(id: String) -> String:
	var why := order_blocker(id)
	if why != "":
		return why
	var ns: Dictionary = run.get("node_state", {})
	match id:
		"supply":
			for h in current_party():
				if h.hp > 0:
					h.hp = mini(Combat.max_hp(h), h.hp + int(ceil(Combat.max_hp(h) * 0.35)))
		"rally":
			Combat.apply_rally(ns["combat_state"])
		"requisition":
			var res: Dictionary = ns["result"]
			var opts: Array = []
			for i in (res["reward_options"] as Array).size():
				opts.append(Combat.gen_loot(Combat.weighted_rarity()))
			res["reward_options"] = opts
		"scout":
			var layer: Dictionary = run["layers"][int(run["pos"])]
			var old: Array = layer["options"]
			var pool: Array = Combat.FORK_POOL.filter(func(k): return not old.has(k))
			pool.shuffle()
			var a: String = pool[0]
			var rest: Array = pool.filter(func(k): return k != a)
			layer["options"] = [a, rest[0]]
	run["orders_used"] = int(run.get("orders_used", 0)) + 1
	save()
	state_changed.emit()
	return ""


# ---------------- Tower of Trials ----------------

static func tower_week_id() -> int:
	return int(Time.get_unix_time_from_system() / 604800.0)


func _tower_roll_week() -> void:
	if tower_week != tower_week_id():
		tower_week = tower_week_id()
		tower_week_cleared = 0


## The floor a new attempt fights: the next uncleared one, or, once floor 90
## is cleared, this week's next ladder floor (91-100). 0 = nothing left this week.
func tower_next_floor() -> int:
	_tower_roll_week()
	var from := GameData.TOWER_WEEKLY_FROM
	if tower_best < from - 1:
		return tower_best + 1
	var f := from + tower_week_cleared
	return f if f <= GameData.TOWER_FLOORS else 0


## Everything fixed about a floor: its fight kind, region, guardian, rules
## (seeded by the floor; floors 91+ also by the week) and first-clear reward.
func tower_floor_info(f: int) -> Dictionary:
	var boss: Dictionary = GameData.TOWER_BOSSES.get(f, {})
	var weekly := f >= GameData.TOWER_WEEKLY_FROM
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["tower", f, tower_week_id() if weekly else 0])
	var rules: Array = []
	if boss.is_empty() and f > 5:
		var pool: Array = GameData.TOWER_RULES.duplicate()
		for i in (2 if weekly else 1):
			rules.append(pool.pop_at(rng.randi() % pool.size()))
	var cap := 4
	for r in rules:
		cap = mini(cap, int(r.get("party_cap", 4)))
	return {"floor": f, "kind": "boss" if not boss.is_empty() else ("elite" if f % 5 == 0 else "combat"),
		"biome": str(boss.get("biome", ["vale", "marsh", "ashen"][((f - 1) / 10) % 3])),
		"boss": boss, "rules": rules, "weekly": weekly, "party_cap": cap, "seed": rng.randi(), "reward": tower_reward(f)}


## First-clear reward for a floor. A weekly re-clear pays half the Coins and
## Crystals and nothing else.
func tower_reward(f: int) -> Dictionary:
	return {"coins": 20 + 4 * f, "crystals": 8 + int(1.5 * f), "tokens": (2 + f / 10) if f % 5 == 0 else 0,
		"relic": GameData.TOWER_RELICS.get(f, {})}


## Fit to the balance sim: a party of this power clears about half its tries.
func tower_recommended_power(f: int) -> int:
	return int(round(114.0 * pow(1.015, f - 1)))


func _tower_diff(info: Dictionary) -> Dictionary:
	var f := int(info["floor"])
	var d := {"id": "tower", "name": "Tower of Trials", "floors": 1, "power": "Trial",
		"coin": [0, 0], "crystal": [0, 0], "token_base": 0, "detector_chance": 0.0,
		"rec_power": tower_recommended_power(f), "biome": info["biome"]}
	for r in info["rules"]:
		d.merge(r.get("diff", {}), true)
	var hp := float(GameData.TOWER_BASE["monster_hp"]) * pow(1.0 + GameData.TOWER_HP_GROWTH, f - 1) * float(d.get("hp_mult", 1.0))
	if d.get("tower_single", false):
		hp *= 2.0
	d["monster_hp"] = int(round(hp))
	d["monster_dmg"] = int(round(float(GameData.TOWER_BASE["monster_dmg"]) * pow(1.0 + GameData.TOWER_DMG_GROWTH, f - 1) * float(d.get("dmg_mult", 1.0))))
	var boss: Dictionary = info["boss"]
	if not boss.is_empty():
		d["boss_name"] = str(boss["name"])
		d["boss_mechanics"] = boss["mechanics"]
	return d


func tower_title() -> String:
	var t := ""
	for e in GameData.TOWER_TITLES:
		if tower_best >= int(e[0]):
			t = str(e[1])
	return t


## One fight on the next floor. Heroes fight at full HP with abilities ready;
## _end_tower puts them back exactly as they were (no downing, no time passing).
func start_tower(hero_ids: Array[String]) -> void:
	var f := tower_next_floor()
	if f <= 0 or not feature_unlocked("tower"):
		return
	var info := tower_floor_info(f)
	var ids: Array[String] = []
	ids.assign(hero_ids.slice(0, int(info["party_cap"])))
	var shield := 0
	for r in Combat.equipped_relics():
		shield += r.hp
	run = {
		"diff_id": "tower", "endless": false, "cycle": 0, "hardcore": false,
		"layers": [{"options": [info["kind"]]}], "pos": 0, "chosen": {},
		"hero_ids": ids, "shield": shield, "boss_rounds": 0,
		"node_kind": "", "node_state": {}, "sealed": null, "anchor_used": false,
		"start_coins": coins, "start_crystals": crystals, "start_tokens": tokens, "heroes_lost": 0,
		"rift_rank": "", "seed": int(info["seed"]), "biome": str(info["biome"]), "tower": f,
	}
	ensure_champion()
	var snap := {}
	for h in current_party():
		snap[h.id] = [h.hp, h.down_runs, h.bedded, h.ability_cooldown]
		h.ability_cooldown = 0
	run["tower_snap"] = snap
	auto_resolve_single_option()
	save()
	state_changed.emit()


## Pays a cleared floor (from _apply_combat_outcome, once) and returns what
## it paid for the result screen.
func _complete_tower_floor(f: int) -> Dictionary:
	var first := f > tower_best
	var rw := tower_reward(f)
	var got := {"floor": f, "first": first, "coins": int(rw["coins"]), "crystals": int(rw["crystals"]), "tokens": 0, "relic": "", "title": ""}
	if first:
		got["tokens"] = int(rw["tokens"])
		var rdef: Dictionary = rw["relic"]
		if not rdef.is_empty():
			var r := Combat.relic_from_unique(rdef)
			r.equipped = Combat.equipped_relics().size() < relic_slot_cap()
			relics.append(r)
			got["relic"] = r.name
		var old_title := tower_title()
		tower_best = f
		if tower_title() != old_title:
			got["title"] = tower_title()
	else:
		got["coins"] = int(got["coins"]) / 2
		got["crystals"] = int(got["crystals"]) / 2
	if f >= GameData.TOWER_WEEKLY_FROM:
		_tower_roll_week()
		tower_week_cleared = maxi(tower_week_cleared, f - GameData.TOWER_WEEKLY_FROM + 1)
	coins += int(got["coins"])
	crystals += int(got["crystals"])
	tokens += int(got["tokens"])
	return got


func _end_tower() -> void:
	var snap: Dictionary = run.get("tower_snap", {})
	for h in current_party():
		if snap.has(h.id):
			var s: Array = snap[h.id]
			h.hp = int(s[0])
			h.down_runs = int(s[1])
			h.bedded = bool(s[2])
			h.ability_cooldown = int(s[3])
	run = {}
	_clamp_hp_to_max()
	save()
	state_changed.emit()


# ---------------- Downed mid-rift ----------------

## Adds every roster hero in the party who's down and not yet decided on to
## run["injured"] — the rift can't continue until each is dealt with.
func _note_injuries(severity: String) -> void:
	var injured: Array = run.get("injured", [])
	for hid in run.get("hero_ids", []):
		var h := find_hero(str(hid))
		if h and h.hp <= 0 and not injured.any(func(e): return str(e["id"]) == h.id):
			injured.append({"id": h.id, "severity": severity})
	run["injured"] = injured


func pending_injuries() -> Array:
	return run.get("injured", [])


func _injury(hero_id: String) -> Dictionary:
	for e in run.get("injured", []):
		if str(e["id"]) == hero_id:
			return e
	return {}


func _resolve_injury(hero_id: String, leave_party: bool) -> void:
	run["injured"] = (run.get("injured", []) as Array).filter(func(e): return str(e["id"]) != hero_id)
	if leave_party:
		run["hero_ids"] = (run.get("hero_ids", []) as Array).filter(func(x): return str(x) != hero_id)


## Idle roster heroes who could go fetch someone: not in the rift, not
## recovering, not already away — the lowest level first.
func idle_heroes() -> Array[Hero]:
	var out: Array[Hero] = []
	var in_rift: Array = run.get("hero_ids", [])
	for h in heroes:
		if not in_rift.has(h.id) and h.is_available():
			out.append(h)
	out.sort_custom(func(a, b): return a.level < b.level)
	return out


## Who in the party can patch a downed hero up mid-rift ("" if nobody).
func field_healer() -> String:
	if bool(run.get("heal_used", false)):
		return ""
	var min_rank := GameData.rank_index(GameData.FIELD_HEALER_MIN_RANK)
	for hid in run.get("hero_ids", []):
		var h := find_hero(str(hid))
		if h and h.hp > 0 and GameData.hero_role(h) == "cleric" and GameData.rank_index(h.rank) >= min_rank:
			return h.name.split(" the ")[0]
	if current_champion and current_champion.hp > 0 and champion_role(current_champion) == "cleric":
		return current_champion.name.split(" the ")[0]
	if field_triage_available():
		return "Field Triage"
	return ""


## Carry them out: a day passes (the Rift Map counts down) and they head home.
func injury_carry(hero_id: String) -> String:
	if _injury(hero_id).is_empty():
		return ""
	_resolve_injury(hero_id, true)
	if not Combat.party_has_unique_relic("lantern_of_the_lost"):
		pass_time()
	save()
	state_changed.emit()
	return ""


func injury_reinforce(hero_id: String) -> String:
	var e := _injury(hero_id)
	if e.is_empty():
		return ""
	var sev := str(e["severity"])
	var need := int(GameData.INJURY_REINFORCEMENTS[sev])
	var idle := idle_heroes()
	if idle.size() < need:
		return "Needs %d idle hero%s at camp" % [need, "" if need == 1 else "es"]
	for i in need:
		idle[i].busy_runs = int(GameData.INJURY_BUSY_RUNS[sev])
	_resolve_injury(hero_id, true)
	save()
	state_changed.emit()
	return ""


func injury_heal(hero_id: String) -> String:
	if _injury(hero_id).is_empty():
		return ""
	if field_healer() == "":
		return "No healer can do it"
	var h := find_hero(hero_id)
	h.down_runs = 0
	h.battered = true
	h.hp = max(1, int(round(Combat.max_hp(h) * GameData.FIELD_HEAL_HP_PCT)))
	run["heal_used"] = true
	_resolve_injury(hero_id, false)
	save()
	state_changed.emit()
	return ""


func injury_leave(hero_id: String) -> String:
	if _injury(hero_id).is_empty():
		return ""
	if rifts_sealed < 3:
		return "A new guild can't leave anyone behind"
	var lb: Array = run.get("left_behind", [])
	lb.append(hero_id)
	run["left_behind"] = lb
	_resolve_injury(hero_id, true)
	save()
	state_changed.emit()
	return ""


## Sealing the rift finds everyone left behind alive; they come home to recover.
func _rescue_left_behind() -> void:
	for hid in run.get("left_behind", []):
		var h := find_hero(str(hid))
		if h:
			push_toast(h, "Found alive", "%s is carried home from the sealed rift" % h.name.split(" the ")[0])
	run["left_behind"] = []


## The run ended without a seal: anyone left in the rift is lost. Their gear
## is recovered and returns to the Inventory.
func _lose_left_behind() -> void:
	for hid in run.get("left_behind", []):
		var h := find_hero(str(hid))
		if not h:
			continue
		for it in items:
			if it.equipped_to == h.id:
				it.equipped_to = ""
				it.equipped_idx = -1
		push_toast(h, "Lost in the rift", "%s was left behind and never came back" % h.name.split(" the ")[0])
		_memorialize(h, "Left behind in a %s" % _run_label())
		heroes.erase(h)
		run["heroes_lost"] = int(run.get("heroes_lost", 0)) + 1
	run["left_behind"] = []


## True for any hero worth a bed — actually downed, or merely wounded (hp
## below max but still able to fight). Beds are a shared resource across
## both, matching the original design intent ("heroes without a bed still
## recover, just at the normal slower passive rate").
func needs_recovery(h: Hero) -> bool:
	return h.is_downed() or (h.hp > 0 and h.hp < Combat.max_hp(h))


func assign_to_bed(hero_id: String) -> void:
	var h := find_hero(hero_id)
	if not h or h.bedded or not needs_recovery(h):
		return
	if occupied_beds() >= medical_bed_cap():
		return
	# A bed takes one run off a downed hero's recovery (never below one), and
	# heals a wounded one fully the next time time passes (see pass_time).
	if h.is_downed():
		h.down_runs = max(1, h.down_runs - 1)
	h.bedded = true
	save()
	state_changed.emit()


func occupied_beds() -> int:
	var n := 0
	for h in heroes:
		if h.bedded and needs_recovery(h):
			n += 1
	return n


## Safety net, run once per render(): a hero at 0 HP who somehow isn't
## counting down (older saves) starts recovering, and a bed held by someone
## who no longer needs it is freed.
func resolve_recovery() -> void:
	var changed := false
	for h in heroes:
		if h.hp <= 0 and h.down_runs <= 0:
			knock_out(h)
			changed = true
		elif h.bedded and not needs_recovery(h):
			h.bedded = false
			changed = true
	if changed:
		save()


## Guild time moves one step whenever a rift run ends (or the guild rests
## instead): downed heroes count down their recovery, wounded ones heal, and
## every rift on the map counts down — one that runs out spills out as a
## Riftbreak. Replaces the old wall-clock timers, which kept ticking while
## the game was closed.
func pass_time() -> void:
	day += 1
	var in_rift: Array = run.get("hero_ids", []) if not run.is_empty() else []
	for h in heroes:
		if h.busy_runs > 0:
			h.busy_runs -= 1
		if in_rift.has(h.id):
			continue   # a day passing mid-rift (carrying someone out) doesn't rest the party
		var mx := Combat.max_hp(h)
		if h.down_runs > 0:
			h.down_runs -= 1
			if h.down_runs == 0:
				h.hp = mx
				h.bedded = false
		elif h.hp > 0 and h.hp < mx:
			h.hp = mx if h.bedded or full_heal_between_runs() else min(mx, h.hp + int(ceil(mx * GameData.WOUND_HEAL_PER_RUN)))
			if h.hp >= mx:
				h.bedded = false
	for i in rift_map.size():
		var slot: Dictionary = rift_map[i]
		if slot.has("rank") and feature_unlocked("rift_map"):
			if Combat.party_has_unique_relic("wardens_seal") and day % 3 == 0:
				continue   # the Warden's Seal holds the fuses for a day
			slot["runs_left"] = int(slot.get("runs_left", 1)) - 1
			if int(slot["runs_left"]) <= 0:
				pending_riftbreak_ranks.append(str(slot["rank"]))
				rift_map[i] = {}
	resolve_rift_map()
	resolve_guild_board()


## Rest instead of running a rift: time passes (see pass_time) without a
## fight — heroes recover, but the map's rifts count down too.
func rest_guild() -> void:
	if not run.is_empty():
		return
	pass_time()
	save()
	state_changed.emit()


## Refills empty Rift Map slots with fresh rolls (run once per render();
## expiry itself happens in pass_time). Also moves any wall-clock-era slot
## onto the run countdown.
func resolve_rift_map() -> void:
	if not feature_unlocked("rift_map"):
		return
	var changed := false
	for i in rift_map.size():
		var old: Dictionary = rift_map[i]
		if old.has("rank") and not old.has("runs_left"):
			old["runs_left"] = int(GameData.find_rift_rank(str(old["rank"]))["fuse_runs"])
			old.erase("expires_at")
			changed = true
	for i in rift_map.size():
		if rift_map[i].is_empty():
			var rank := Combat.weighted_rift_rank()
			var slot := {"rank": rank, "runs_left": int(GameData.find_rift_rank(rank)["fuse_runs"]), "uid": "rift%d" % next_id}
			next_id += 1
			# ~35% of freshly-rolled rifts carry a bounty, scaled by the same
			# 0-8 rank severity index Riftbreak already uses — paid out by
			# seal_rift() once this specific rift is cleared.
			if randf() < 0.35:
				var sev := GameData.rift_rank_index(rank)
				slot["bounty"] = {"coins": 15 * (sev + 1), "reputation": 1 + sev}
			rift_map[i] = slot
			changed = true
	if changed:
		save()


## Enters a mapped rift chosen from the Rift Map hub. Builds a normal run
## exactly like start_run() already does (same Party Assembly flow, same
## build_layers pipeline) but folds the slot's rank into RIFT_RANK_MODIFIERS
## via start_run()'s own rift_rank param, and forces hardcore off — Hardcore
## Mode is retired from mapped rifts for now. Clears the slot immediately
## (claimed the moment the player steps in, regardless of how the run ends);
## start_run()'s own save() at the end covers this mutation too.
func start_map_rift(slot_idx: int, hero_ids: Array[String], starting_relic: Relic) -> void:
	if slot_idx < 0 or slot_idx >= rift_map.size():
		return
	var rank := str(rift_map[slot_idx].get("rank", "F"))
	var bounty: Dictionary = rift_map[slot_idx].get("bounty", {})
	var uid := str(rift_map[slot_idx].get("uid", ""))
	rift_map[slot_idx] = {}
	start_run("lesser", hero_ids, starting_relic, false, false, rank)
	run["map_uid"] = uid
	if not bounty.is_empty():
		run["bounty"] = bounty
		save()


## Called from Main.gd's render() right after resolve_rift_map(), only when
## idle at the Terminal with no run already active. Merges every rank in
## pending_riftbreak_ranks into a single forced fight by building a "fake"
## single-node run shaped exactly like start_run() already produces (see the
## Phase 11 plan's "fake single-node run" trick) — this lets the entire
## existing rift_run/combat_node/_play_round pipeline drive the fight
## completely unchanged (difficulty scaling happens in _diff(), which checks
## run["is_riftbreak"]). Draws from the whole roster, not current_party() —
## there's no Party Assembly step for a forced encounter, every healthy hero
## on hand gets pulled in. Falls back to a direct resource penalty if no
## hero is available to fight at all.
func start_riftbreak_encounter() -> void:
	if pending_riftbreak_ranks.is_empty():
		return
	var severity := 0
	var worst_index := 0
	for rank in pending_riftbreak_ranks:
		var idx := GameData.rift_rank_index(str(rank))
		severity += idx
		worst_index = max(worst_index, idx)
	var available: Array[Hero] = heroes.filter(func(h): return h.is_available())
	if available.is_empty():
		coins = max(0, coins - (20 + severity * 10))
		crystals = max(0, crystals - (5 + severity * 2))
		pending_riftbreak_ranks.clear()
		save()
		state_changed.emit()
		return
	var hero_ids: Array[String] = []
	for h in available:
		hero_ids.append(h.id)
	run = {
		"diff_id": "lesser", "endless": false, "cycle": 0, "hardcore": false,
		"layers": [{"options": ["combat"]}], "pos": 0, "chosen": {},
		"hero_ids": hero_ids, "shield": 0, "boss_rounds": 0,
		"node_kind": "", "node_state": {}, "sealed": null, "anchor_used": false,
		"start_coins": coins, "start_crystals": crystals, "start_tokens": tokens, "heroes_lost": 0,
		"rift_rank": "", "is_riftbreak": true, "riftbreak_severity": severity,
		"riftbreak_worst_index": worst_index, "riftbreak_flavor": GameData.narrative_line("riftbreak_begins"),
		"seed": randi(),
	}
	ensure_champion()
	auto_resolve_single_option()
	pending_riftbreak_ranks.clear()
	save()
	state_changed.emit()


func sell_detector(detector_id: String) -> void:
	for d in detectors:
		if d["id"] == detector_id:
			var base := int(GameData.DETECTOR_BASE_SALE[d["tier"]])
			var bonus := 1.3 if black_market_unlocked() else 1.0
			var fee: float = max(0.05, 0.15 - broker_fee_reduction())
			var sale := int(round(base * bonus * (1.0 - fee)))
			coins += sale
			detectors.erase(d)
			save()
			state_changed.emit()
			return


func use_detector_for_shop_boost(detector_id: String) -> String:
	if pending_shop_boost:
		return "A Shop Boost is already armed"
	for d in detectors:
		if d["id"] == detector_id:
			detectors.erase(d)
			pending_shop_boost = true
			save()
			state_changed.emit()
			return ""
	return ""


## The B/A/S jump (a real named subclass forking off — see the CLASS_POOL doc
## comment) additionally consumes one same-tier Evolution Stone; the earlier
## F-E-D-C climb (still the same un-named identity throughout) doesn't need
## one, same as before this system existed. The player picks which candidate
## (`target_pool_id`, one of GameData.evolution_choices) — the biggest build
## decision a hero gets, so it's a choice, not a roll.
func evolve_hero(hero_id: String, target_pool_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	if h.level < 10:
		return "Must be Level 10 to evolve"
	var cur_cls := GameData.find_class(h.pool_id)
	if cur_cls.is_empty():
		return "This hero predates the evolution system"
	var choices := GameData.evolution_choices(cur_cls)
	if choices.is_empty():
		return "No further evolution available"
	var next_rank_id: String = choices[0]["rank"]
	var next_rank := GameData.find_rank(next_rank_id)
	if crystals < int(next_rank["cost"]):
		return "Not enough Crystals"
	var needs_stone: bool = next_rank_id in ["B", "A", "S"]
	if needs_stone and int(evolution_stones.get(next_rank_id, 0)) <= 0:
		return "Need a %s-Rank Evolution Stone" % next_rank_id
	var picked: Array = choices.filter(func(c): return c["id"] == target_pool_id)
	if picked.is_empty():
		return "Pick an evolution path"
	var next: Dictionary = picked[0]
	var cur_rank := GameData.find_rank(cur_cls["rank"])
	crystals -= int(next_rank["cost"])
	if needs_stone:
		evolution_stones[next_rank_id] = int(evolution_stones.get(next_rank_id, 0)) - 1
	# Keeps exactly the one stage being left behind reachable — see the doc
	# comment on Hero.prior_pool_id for why this isn't an unbounded history.
	h.prior_pool_id = h.pool_id
	h.prior_innate_kind = h.innate_kind
	h.prior_innate_value = h.innate_value
	var ratio_mult: float = (float(next["hp_ratio"]) / float(cur_cls["hp_ratio"])) * (float(next_rank["mult"]) / float(cur_rank["mult"]))
	var dmg_ratio_mult: float = (float(next["dmg_ratio"]) / float(cur_cls["dmg_ratio"])) * (float(next_rank["mult"]) / float(cur_rank["mult"]))
	h.base_hp = int(round(h.base_hp * ratio_mult))
	h.base_dmg = int(round(h.base_dmg * dmg_ratio_mult))
	h.pool_id = next["id"]
	h.rank = next["rank"]
	h.type = next["type"]
	h.flavor = next["flavor"]
	h.innate_kind = next["kind"]
	var rank_idx := GameData.rank_index(next["rank"])
	h.innate_value = Combat.hero_innate_value(next, rank_idx)
	h.name = "%s the %s" % [h.name.split(" the ")[0], next["name"]]
	h.hp = Combat.max_hp(h)
	var passive := GameData.subclass_passive(h.pool_id)
	push_toast(h, "Evolved — Rank %s" % h.rank, "%s · new passive: %s" % [h.name, str(passive.get("name", "none"))])
	save()
	state_changed.emit()
	return ""


## An Evolution Stone whose tier matches a hero's CURRENT rank (not the rank
## above) can't evolve them further — they're not sitting one rank below
## anymore — so it converts into a bonus skill point toward whatever tree
## they just unlocked instead, capped per subclass (GameData's
## EVOLUTION_STONE_BONUS_SP_CAP) so a stone stockpile can't become an
## unbounded SP faucet on one hero.
func reinforce_hero(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	var tier := h.rank
	if int(evolution_stones.get(tier, 0)) <= 0:
		return "Need a %s-Rank Evolution Stone" % tier
	var used := int(h.stone_bonus_used.get(h.pool_id, 0))
	if used >= GameData.EVOLUTION_STONE_BONUS_SP_CAP:
		return "Already reinforced this subclass to the max"
	evolution_stones[tier] = int(evolution_stones.get(tier, 0)) - 1
	h.stone_bonus_used[h.pool_id] = used + 1
	h.skill_points += 1
	save()
	state_changed.emit()
	return ""


## A hero topped up to a buffed max_hp (e.g. by Vigor Incense's +hp_pct)
## while active_incense was active would otherwise be left with hp above
## their real max once the buff drops off back at camp.
func _clamp_hp_to_max() -> void:
	for h in heroes:
		h.battered = false   # back at camp, the field patch-up no longer holds them back
		h.hp = min(h.hp, Combat.max_hp(h))
	if current_champion:
		current_champion.hp = min(current_champion.hp, Combat.max_hp(current_champion))


func retreat_now() -> void:
	if run.has("tower"):
		_end_tower()
		return
	_record_run("Retreated")
	_lose_left_behind()
	run = {}
	active_incense = {}
	_clamp_hp_to_max()
	pass_time()
	save()
	state_changed.emit()


func finish_run() -> void:
	if run.has("tower"):
		_end_tower()
		return
	_record_run(_run_outcome())
	_lose_left_behind()
	run = {}
	active_incense = {}
	_clamp_hp_to_max()
	pass_time()
	save()
	state_changed.emit()


func buy_incense(incense_id: String) -> String:
	var def := GameData.find_incense(incense_id)
	if def.is_empty():
		return ""
	var cost := int(def["cost"])
	if coins < cost:
		return "Not enough Coins"
	coins -= cost
	consumables.append({"id": "cs" + str(next_id), "incense_id": incense_id})
	next_id += 1
	save()
	state_changed.emit()
	return ""


## Consuming an incense applies its bonus for the rift about to start —
## cleared on retreat_now()/finish_run() same as the rest of run state.
func use_incense(consumable_id: String) -> void:
	for c in consumables:
		if c["id"] == consumable_id:
			var def := GameData.find_incense(str(c["incense_id"]))
			if def.is_empty():
				return
			active_incense = {"kind": def["kind"], "value": def["value"], "name": def["name"]}
			consumables.erase(c)
			save()
			state_changed.emit()
			return


func buy_tonic() -> String:
	if tonics >= GameData.TONIC_CAP:
		return "You can carry %d at most" % GameData.TONIC_CAP
	if coins < GameData.TONIC_COST:
		return "Not enough Coins"
	coins -= GameData.TONIC_COST
	tonics += 1
	save()
	state_changed.emit()
	return ""


func buy_runestone(runestone_id: String) -> String:
	var def := GameData.find_runestone(runestone_id)
	if def.is_empty():
		return ""
	var cost := int(def["cost"])
	if coins < cost:
		return "Not enough Coins"
	coins -= cost
	runestones.append({"id": "rs" + str(next_id), "runestone_id": runestone_id})
	next_id += 1
	save()
	state_changed.emit()
	return ""


## Sockets a runestone permanently into one equipped item — its bonus stacks
## on top of the item's own stat for as long as it stays equipped. One socket
## per item (no replacing an already-socketed one), and only into the
## matching slot_type (weapon runestones into weapon items, gear runestones
## into armor/focus items).
func socket_runestone(runestone_consumable_id: String, item_id: String) -> String:
	var owned: Dictionary = {}
	for r in runestones:
		if r["id"] == runestone_consumable_id:
			owned = r
			break
	if owned.is_empty():
		return ""
	var def := GameData.find_runestone(str(owned["runestone_id"]))
	if def.is_empty():
		return ""
	var target: Item = null
	for it in items:
		if it.id == item_id:
			target = it
			break
	if not target:
		return ""
	if target.slot_type() != str(def["category"]):
		return "Wrong socket type"
	if target.socketed_kind != "":
		return "Already socketed"
	target.socketed_kind = def["kind"]
	target.socketed_value = def["value"]
	runestones.erase(owned)
	save()
	state_changed.emit()
	return ""


## `kind` identifies which of the hero's unlocked trees `skill_id` belongs
## to (a bare node id — "cap", "mastery", ...) — ignored for the universal
## Tier-1 roots ("edge"/"hide"), which are shared across every tree.
func learn_skill(hero_id: String, kind: String, skill_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	var n := GameData.find_skill_node(kind, skill_id, h.cls_id)
	var key := GameData.skill_storage_key(kind, skill_id)
	if n.is_empty() or h.skills.get(key, false):
		return ""
	if h.level < int(n["req_level"]):
		return "Requires Level %d" % n["req_level"]
	for req in n["requires"]:
		if not h.skills.get(GameData.skill_storage_key(kind, req), false):
			return "Learn the prerequisite skill(s) first"
	if not n.get("requires_any", []).is_empty() and not n["requires_any"].any(func(r): return h.skills.get(GameData.skill_storage_key(kind, r), false)):
		return "Master one of this tree's paths first"
	for excl in n.get("excludes", []):
		if h.skills.get(GameData.skill_storage_key(kind, excl), false):
			return "Locked out — you already chose the other path"
	if n.has("rift_rank") and best_rift_rank_sealed < GameData.rift_rank_index(str(n["rift_rank"])):
		return "Seal a Rank %s or higher Rift Map rift first" % n["rift_rank"]
	var stone := ""
	if n.get("stone", false):
		for r in GameData.RANKS:
			if int(evolution_stones.get(r["id"], 0)) > 0:
				stone = str(r["id"])
				break
		if stone == "":
			return "Needs an Evolution Stone"
	var cost := skill_node_cost(h, kind, n)
	if h.skill_points < cost:
		return "Not enough Skill Points"
	h.skill_points -= cost
	if stone != "":
		evolution_stones[stone] = int(evolution_stones[stone]) - 1
	h.skills[key] = true
	save()
	state_changed.emit()
	return ""


## Spends SP once to make a hero's existing Active Ability trigger more
## often (see GameData's Ability Awakening doc comment) — a second SP sink
## next to the skill tree, not a replacement for it. One-time per hero:
## already-awakened is a no-op refusal, not a stacking cooldown reduction.
## A Tier-3 fork costs 1 SP less (never below 1) for a hero whose trait
## already leans into its stat, or whose scar the fork would shore up.
func skill_node_cost(h: Hero, kind: String, n: Dictionary) -> int:
	var cost := int(n.get("cost", 0))
	if int(n.get("tier", 0)) == 3 and fork_discounted(h, str(n.get("kind", ""))):
		cost = max(1, cost - 1)
	return cost


func fork_discounted(h: Hero, stat: String) -> bool:
	if float(GameData.TRAIT_TABLE.get(h.trait_name, {}).get(stat, 0.0)) > 0.0:
		return true
	for tid in h.earned_traits:
		var t := GameData.find_earned_trait(tid)
		if t.get("kind", "") == stat and float(t.get("value", 0.0)) > 0.0:
			return true
	for scar in h.scars:
		if float(GameData.SCAR_TABLE.get(scar, {}).get(stat, 0.0)) < 0.0:
			return true
	return false


func awaken_ability(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	if not Combat.qualifies_for_ability(h):
		return "This hero has no Active Ability yet"
	if h.ability_awakened:
		return "Already awakened"
	if h.skill_points < GameData.ABILITY_AWAKENING_COST:
		return "Not enough Skill Points"
	h.skill_points -= GameData.ABILITY_AWAKENING_COST
	h.ability_awakened = true
	save()
	state_changed.emit()
	return ""


## Kind -> hero-count across the CURRENT run's party — {} outside a run, so
## every synergy helper below naturally returns 0/false with no active run.
func _party_kind_counts() -> Dictionary:
	var counts := {}
	for hid in run.get("hero_ids", []):
		var h2 := find_hero(str(hid))
		if not h2:
			continue
		var cls := GameData.find_class(h2.pool_id)
		if cls.is_empty():
			continue
		var k: String = cls.get("kind", "")
		counts[k] = int(counts.get(k, 0)) + 1
	return counts


## Resonance — this run's party has 2+ heroes CURRENTLY building the same
## kind. Computed live off run["hero_ids"], never cached, so it can't drift
## if the party or a hero's tree ever changes mid-assembly.
func party_resonance_bonus(kind: String) -> float:
	if run.is_empty():
		return 0.0
	return GameData.PARTY_RESONANCE_BONUS if int(_party_kind_counts().get(kind, 0)) >= 2 else 0.0


## Eclectic — the opposite of Resonance: 3+ party members, no kind repeated.
func party_eclectic_bonus() -> float:
	if run.is_empty():
		return 0.0
	var counts := _party_kind_counts()
	for k in counts:
		if int(counts[k]) >= 2:
			return 0.0
	return GameData.PARTY_ECLECTIC_BONUS if counts.size() >= 3 else 0.0


## For a KIND_SKILL_PACKAGE finisher's `combo_kind` field (GameData doc
## comment above KIND_SKILL_PACKAGE) — true if some OTHER current-run party
## member has reached `kind`'s own Tier-3 capstone (cap or cap_alt; the
## asymmetric kinds' cap_third/no-fork shapes still resolve through "cap").
func party_has_other_kind_capstone(exclude_hero_id: String, kind: String) -> bool:
	if run.is_empty():
		return false
	for hid in run.get("hero_ids", []):
		if str(hid) == exclude_hero_id:
			continue
		var h2 := find_hero(str(hid))
		if not h2:
			continue
		if h2.skills.get(GameData.skill_storage_key(kind, "cap"), false) or h2.skills.get(GameData.skill_storage_key(kind, "cap_alt"), false):
			return true
	return false


## Real SP cost of a set of learned skill keys — sums each node's actual
## `cost`, not just a count of learned nodes (those differ, since Tier-3/4
## nodes cost more SP than Tier-1/2 ones — counting nodes instead of summing
## cost under-refunded a hero who'd learned any higher-tier node).
func _skill_keys_sp_cost(keys: Array, h: Hero = null) -> int:
	var total := 0
	for key in keys:
		var key_str := str(key)
		if not key_str.contains(":"):
			total += int(GameData.find_skill_node("", key_str).get("cost", 0))
		else:
			var parts := key_str.split(":", true, 1)
			if parts.size() == 2:
				var n := GameData.find_skill_node(parts[0], parts[1])
				total += skill_node_cost(h, parts[0], n) if h else int(n.get("cost", 0))
	return total


func respec_cost(spent_sp: int) -> int:
	return int(round(float(20 + 10 * spent_sp) * (1.0 - respec_fee_reduction())))


## Coin cost to respec a hero's `kind` tree right now (or every tree, if
## `kind` is empty) — same accounting respec_hero() itself uses, exposed so
## the UI can show the real price on the button instead of guessing.
func tree_respec_cost(h: Hero, kind: String = "") -> int:
	var target_keys: Array = []
	for key in h.skills.keys():
		if h.skills[key] and (kind == "" or str(key).begins_with("%s:" % kind)):
			target_keys.append(key)
	return respec_cost(_skill_keys_sp_cost(target_keys, h))


## `kind` empty respecs every tree at once (and the universal Tier-1 roots);
## given, only that one tree's own nodes clear — the universal roots and any
## other tree's progress are untouched. A hero holds at most 2 trees at once
## (see Hero.prior_pool_id), so "just this one" is a real, much cheaper
## option next to nuking everything to fix one fork choice.
func respec_hero(hero_id: String, kind: String = "") -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	var target_keys: Array = []
	for key in h.skills.keys():
		if not h.skills[key]:
			continue
		if kind == "" or str(key).begins_with("%s:" % kind):
			target_keys.append(key)
	if target_keys.is_empty():
		return ""
	var spent_sp := _skill_keys_sp_cost(target_keys, h)
	var cost := respec_cost(spent_sp)
	if coins < cost:
		return "Need %d Coins" % cost
	coins -= cost
	h.skill_points += spent_sp
	for key in target_keys:
		h.skills.erase(key)
	save()
	state_changed.emit()
	return ""


func reroll_trait(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	if coins < trait_reroll_cost():
		return "Need %d Coins" % trait_reroll_cost()
	coins -= trait_reroll_cost()
	h.trait_name = Combat.pick_trait_name(h.cls_id)
	h.hp = min(Combat.max_hp(h), h.hp)
	save()
	state_changed.emit()
	return ""


func scrub_trait(hero_id: String) -> String:
	if lvl("res.lab") < 1:
		return "Build the Arcane Lab first"
	var h := find_hero(hero_id)
	var scrubbable := h and (GameData.NEG_TRAITS.has(h.trait_name) or GameData.is_role_trait(h.trait_name))
	if not scrubbable:
		return ""
	if coins < 30:
		return "Need 30 Coins"
	coins -= 30
	h.trait_name = ""
	h.hp = Combat.max_hp(h)
	save()
	state_changed.emit()
	return ""


## Same gate/cost as scrub_trait — removes one named scar rather than the
## base trait, and doesn't touch h.hp (a scar isn't tied to a heal-to-full
## the way clearing the base trait is).
func scrub_scar(hero_id: String, scar_name: String) -> String:
	if lvl("res.lab") < 1:
		return "Build the Arcane Lab first"
	var h := find_hero(hero_id)
	if not h or not h.scars.has(scar_name):
		return ""
	if coins < 30:
		return "Need 30 Coins"
	coins -= 30
	h.scars.erase(scar_name)
	save()
	state_changed.emit()
	return ""


func toggle_equip_relic(relic_id: String) -> void:
	for r in relics:
		if r.id == relic_id:
			if not r.equipped and Combat.equipped_relics().size() >= relic_slot_cap():
				return
			r.equipped = not r.equipped
			save()
			state_changed.emit()
			return


func scrap_relic(relic_id: String) -> void:
	if not recycle_unlocked():
		return
	for r in relics:
		if r.id == relic_id and not r.equipped:
			var rar := GameData.find_rarity(r.rarity)
			var gain := int(round(6.0 * float(rar["mult"])))
			crystals += gain
			relics.erase(r)
			save()
			state_changed.emit()
			return


func sell_relic(relic_id: String) -> void:
	for r in relics:
		if r.id == relic_id and not r.equipped:
			var rar := GameData.find_rarity(r.rarity)
			var fee: float = max(0.05, 0.15 - broker_fee_reduction())
			var sale := int(round(15.0 * float(rar["mult"]) * (1.0 - fee)))
			coins += sale
			relics.erase(r)
			save()
			state_changed.emit()
			return


## Crafting Hall: combine 3 unequipped items/relics of the same category (or
## relic type) and rarity into 1 of the next rarity up — a sink for excess
## common/rare loot beyond selling it. Legendary is deliberately not on this
## ladder (uniques are hand-authored fixed drops, not something Combat.gen_*
## can roll toward), so epic is the ceiling a craft can produce.
const CRAFT_RARITY_UP := {"common": "rare", "rare": "epic"}


func craft_items(category: String, rarity: String) -> void:
	if not CRAFT_RARITY_UP.has(rarity):
		return
	var matches: Array[Item] = []
	for it in items:
		if it.category == category and it.rarity == rarity and it.equipped_to == "":
			matches.append(it)
	if matches.size() < 3:
		return
	# The crafted item keeps the best rank among the three fed in — feeding
	# high-rank commons shouldn't hand back a Rank-F rare.
	var best_rank_idx := 0
	for i in 3:
		best_rank_idx = max(best_rank_idx, GameData.rift_rank_index(matches[i].item_rank))
		items.erase(matches[i])
	items.append(Combat.gen_item(str(CRAFT_RARITY_UP[rarity]), category, str(GameData.RIFT_RANKS[best_rank_idx]["id"])))
	crafts_performed += 1
	save()
	state_changed.emit()


func craft_relics(type: String, rarity: String) -> void:
	if not CRAFT_RARITY_UP.has(rarity):
		return
	var matches: Array[Relic] = []
	for r in relics:
		if r.type == type and r.rarity == rarity and not r.equipped:
			matches.append(r)
	if matches.size() < 3:
		return
	for i in 3:
		relics.erase(matches[i])
	relics.append(Combat.gen_relic(str(CRAFT_RARITY_UP[rarity]), type))
	crafts_performed += 1
	save()
	state_changed.emit()


## A won fight counts toward every equipped item on the heroes still standing.
func _attune_gear(party: Array) -> void:
	for h in party:
		if h.hp <= 0 or h.is_champion:
			continue
		for it in items:
			if it.equipped_to != h.id or it.attune_level >= GameData.ATTUNE_MAX:
				continue
			it.attune_wins += 1
			if it.attune_wins >= GameData.ATTUNE_WINS * (it.attune_level + 1):
				it.attune_level += 1
				var g := 1.0 + GameData.ATTUNE_STEP
				it.value = snappedf(it.value * g, 0.001)
				it.secondary_value = snappedf(it.secondary_value * g, 0.001)
				it.tertiary_value = snappedf(it.tertiary_value * g, 0.001)
				push_toast(h, "Gear attuned", "%s grows stronger (%d/%d)" % [it.name, it.attune_level, GameData.ATTUNE_MAX])


func reforge_cost(it: Item) -> int:
	return int(round(GameData.REFORGE_CRYSTALS * float(GameData.find_rarity(it.rarity)["mult"]) * (it.reforges + 1)))


## Rerolls one stat line (0 primary, 1 secondary, 2 tertiary) of an unequipped
## generated item: the primary keeps its kind (the name comes from it), the
## others can land on any kind the item doesn't already have.
func reforge_item(item_id: String, line: int) -> String:
	var it: Item = null
	for x in items:
		if x.id == item_id:
			it = x
	if not it or it.unique_id != "" or it.equipped_to != "":
		return "Can't reforge this item"
	var kinds := [it.kind, it.secondary_kind, it.tertiary_kind]
	if line < 0 or line > 2 or str(kinds[line]) == "":
		return "No such stat"
	var cost := reforge_cost(it)
	if crystals < cost:
		return "Not enough Crystals"
	crystals -= cost
	it.reforges += 1
	var kind: String = kinds[line]
	if line > 0:
		var pool: Array = GameData.ITEM_CATEGORY_KINDS[it.category].filter(func(k): return not kinds.has(k))
		pool.append(kind)
		kind = str(pool[randi() % pool.size()])
	var val := Combat.item_line_value(kind, it.rarity, line, it.item_rank) * pow(1.0 + GameData.ATTUNE_STEP, it.attune_level)
	match line:
		0:
			it.value = val
		1:
			it.secondary_kind = kind
			it.secondary_value = val
			var suffixes: Array = GameData.ITEM_AFFIX_SUFFIX[kind]
			it.name = "%s %s" % [it.name.split(" of ")[0], str(suffixes[randi() % suffixes.size()])]
		2:
			it.tertiary_kind = kind
			it.tertiary_value = val
	save()
	state_changed.emit()
	return ""


func salvage_value(it: Item) -> int:
	return int(round(GameData.SALVAGE_CRYSTALS * float(GameData.find_rarity(it.rarity)["mult"])))


func salvage_item(item_id: String) -> void:
	if not recycle_unlocked():
		return
	for it in items:
		if it.id == item_id and it.equipped_to == "":
			crystals += salvage_value(it)
			items.erase(it)
			save()
			state_changed.emit()
			return


func sell_item(item_id: String) -> void:
	for it in items:
		if it.id == item_id and it.equipped_to == "":
			var rar := GameData.find_rarity(it.rarity)
			var fee: float = max(0.05, 0.15 - broker_fee_reduction())
			var sale := int(round(15.0 * float(rar["mult"]) * (1.0 - fee)))
			coins += sale
			items.erase(it)
			save()
			state_changed.emit()
			return


func find_item(item_id: String) -> Item:
	for it in items:
		if it.id == item_id:
			return it
	return null


func item_slot_type_of(it: Item) -> String:
	return it.slot_type()


## A Legendary item's locked_role/locked_subclasses restricts who can equip
## it — empty on both means no restriction (every normal item, and most
## Legendaries).
## Has this hero enough of the item's attribute to equip it?
func attr_req_met(it: Item, h: Hero) -> bool:
	return it.attr_req <= 0 or Combat.hero_attr(h, it.attr) - (it.attr_bonus if it.equipped_to == h.id else 0) >= it.attr_req


## Every flat kind->value an item contributes (what Combat.hero_item_total
## sums for it).
func item_stat_map(it: Item) -> Dictionary:
	var m := {}
	if it == null:
		return m
	for pair in [[it.kind, it.value], [it.secondary_kind, it.secondary_value], [it.tertiary_kind, it.tertiary_value],
			[it.implicit_kind, it.implicit_value], [it.socketed_kind, it.socketed_value], [it.drawback_kind, it.drawback_value]]:
		if str(pair[0]) != "":
			m[pair[0]] = float(m.get(pair[0], 0.0)) + float(pair[1])
	return m


const GEAR_SCORE_WEIGHT := {"dmg_pct": 1.0, "hp_pct": 0.9, "dodge_pct": 0.8, "mend_pct": 0.8, "ability_power": 0.7, "speed_pct": 0.6, "escalate_pct": 0.5}


## How much an item helps, for "Equip best": its stat lines weighted (damage
## and health count most) plus a flat bonus per special effect.
## ponytail: role-blind weights; weigh by the hero's archetype if picks feel off.
func gear_score(it: Item) -> float:
	var s := 0.0
	var stats := item_stat_map(it)
	for k in stats:
		s += float(stats[k]) * float(GEAR_SCORE_WEIGHT.get(k, 0.4))
	var fx: Array = GameData.find_unique_item(it.unique_id).get("effects", []) if it.unique_id != "" else it.effects
	return s + 0.08 * fx.size()


## The best free (or already worn) gear for a hero: {slot_type: [items]},
## never taking an item another hero is wearing.
func best_gear(h: Hero) -> Dictionary:
	var out := {}
	for st in ["weapon", "gear"]:
		var cap := GameData.weapon_slots(h.pool_id) if st == "weapon" else GameData.gear_slots(h.rank)
		var pool: Array = items.filter(func(it): return it.slot_type() == st and (it.equipped_to == "" or it.equipped_to == h.id) and item_fits_hero(it, h) and attr_req_met(it, h))
		pool.sort_custom(func(a, b): return gear_score(a) > gear_score(b))
		out[st] = pool.slice(0, cap)
	return out


## How many items "Equip best" would put on `h` that it isn't wearing.
func equip_best_changes(h: Hero) -> int:
	var n := 0
	var best := best_gear(h)
	for st in best:
		n += (best[st] as Array).filter(func(it): return it.equipped_to != h.id).size()
	return n


func equip_best(hero_id: String) -> void:
	var h := find_hero(hero_id)
	if not h:
		return
	var best := best_gear(h)
	for st in best:
		for it in items:
			if it.equipped_to == h.id and it.slot_type() == st:
				it.equipped_to = ""
				it.equipped_idx = -1
		var idx := 0
		for it in best[st]:
			it.equipped_to = h.id
			it.equipped_idx = idx
			idx += 1
	save()
	state_changed.emit()


func auto_assign_attrs(hero_id: String) -> void:
	var h := find_hero(hero_id)
	if not h or h.attr_points <= 0:
		return
	Combat.auto_spend_attrs(h)
	save()
	state_changed.emit()


## Points a hero has put into attributes beyond their role's starting spread.
func attr_points_spent(h: Hero) -> int:
	var base := GameData.role_attrs(GameData.hero_role(h))
	var n := 0
	for a in GameData.ATTRIBUTES:
		n += int(h.attrs.get(a, GameData.ATTR_BASELINE)) - int(base[a])
	return max(n, 0)


func attr_respec_cost(h: Hero) -> int:
	return h.level * GameData.RESPEC_TOKENS_PER_LEVEL


## Refunds every spent attribute point for Seal Tokens. Gear whose requirement
## the hero no longer meets comes off (otherwise a reset could keep gear on
## that the new build couldn't equip).
func respec_attrs(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if not h or h.is_champion:
		return "Can't reset this hero"
	var refund := attr_points_spent(h)
	if refund <= 0:
		return "Nothing to reset"
	var cost := attr_respec_cost(h)
	if tokens < cost:
		return "Not enough Seal Tokens"
	tokens -= cost
	h.attrs = GameData.role_attrs(GameData.hero_role(h))
	h.attr_points += refund
	for it in items:
		if it.equipped_to == h.id and not attr_req_met(it, h):
			it.equipped_to = ""
			it.equipped_idx = -1
	save()
	state_changed.emit()
	return ""


func attr_train_cost(h: Hero) -> int:
	return GameData.ATTR_TRAIN_COST * (h.attr_trained + 1)


## Buys one attribute point with Coins (see ATTR_TRAIN_CAP).
func train_attr(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if not h or h.is_champion:
		return "Can't train this hero"
	if h.attr_trained >= GameData.ATTR_TRAIN_CAP:
		return "Fully trained"
	var cost := attr_train_cost(h)
	if coins < cost:
		return "Not enough Coins"
	coins -= cost
	h.attr_trained += 1
	h.attr_points += 1
	save()
	state_changed.emit()
	return ""


func spend_attr_point(hero_id: String, a: String) -> void:
	var h := find_hero(hero_id)
	if not h or h.attr_points <= 0 or not GameData.ATTRIBUTES.has(a):
		return
	h.attrs[a] = int(h.attrs.get(a, GameData.ATTR_BASELINE)) + 1
	h.attr_points -= 1
	save()
	state_changed.emit()


func item_fits_hero(it: Item, h: Hero) -> bool:
	if it.locked_role != "" and h.cls_id != it.locked_role:
		return false
	if not it.locked_subclasses.is_empty() and not it.locked_subclasses.has(h.pool_id):
		return false
	return true


func equip_item(hero_id: String, slot_type: String, idx: int, item_id: String) -> void:
	var h := find_hero(hero_id)
	if not h and current_champion and current_champion.id == hero_id:
		h = current_champion   # the Champion's gear slots (Recruits tab)
	if not h:
		return
	# Validate the new item first — a rejected equip must not empty the slot.
	var target: Item = null
	if item_id != "":
		for it in items:
			if it.id == item_id:
				target = it
				break
		if not target or target.slot_type() != slot_type:
			return
		if not item_fits_hero(target, h) or not attr_req_met(target, h):
			return
		var cap := GameData.weapon_slots(h.pool_id) if slot_type == "weapon" else GameData.gear_slots(h.rank)
		if idx >= cap:
			return
	for it in items:
		if it.equipped_to == hero_id and it.slot_type() == slot_type and it.equipped_idx == idx:
			it.equipped_to = ""
			it.equipped_idx = -1
	if target == null:
		save()
		state_changed.emit()
		return
	target.equipped_to = hero_id
	target.equipped_idx = idx
	save()
	state_changed.emit()


func relic_reroll_cost(r: Relic) -> int:
	return int(round(GameData.RELIC_REROLL_CRYSTALS * float(GameData.find_rarity(r.rarity)["mult"]) * (r.rerolls + 1)))


## Rerolls one effect of a normal relic: special `idx`, or its trigger (idx -1).
func reroll_relic(relic_id: String, idx: int) -> String:
	for r in relics:
		if r.id != relic_id:
			continue
		if r.unique_id != "":
			return "Legendaries can't be rerolled"
		var cost := relic_reroll_cost(r)
		if crystals < cost:
			return "Not enough Crystals"
		if idx < 0:
			if r.trigger.is_empty():
				return "No trigger"
			crystals -= cost
			var lvl_mult := pow(1.1, r.level - 1)
			r.trigger = Combat.roll_relic_trigger(r.rarity)
			r.trigger["value"] = snappedf(float(r.trigger["value"]) * lvl_mult, 0.001)
		else:
			if idx >= r.specials.size():
				return "No such effect"
			crystals -= cost
			var others: Array = []
			for i in r.specials.size():
				if i != idx:
					others.append(r.specials[i]["kind"])
			var s := Combat.roll_relic_special(r.type, r.rarity, others)
			s["value"] = snappedf(float(s["value"]) * pow(1.12, r.level - 1), 0.001)
			s["label"] = Combat.relic_special_label(str(s["kind"]), float(s["value"]))
			r.specials[idx] = s
			if idx == 0:
				var words := r.name.split(" of ")[0]
				r.name = "%s %s" % [words, GameData.RELIC_SPECIAL_SUFFIX.get(str(s["kind"]), "")]
		r.rerolls += 1
		save()
		state_changed.emit()
		return ""
	return ""


func upgrade_relic(relic_id: String) -> String:
	for r in relics:
		if r.id != relic_id:
			continue
		if r.level >= RELIC_MAX_LEVEL:
			return "Already max level"
		var cost := relic_upgrade_cost(r)
		if crystals < cost:
			return "Not enough Crystals"
		crystals -= cost
		r.dmg = int(round(r.dmg * 1.15))
		r.hp = int(round(r.hp * 1.15))
		var next_lvl := r.level + 1
		for sp in r.specials:
			sp["value"] = snappedf(float(sp["value"]) * 1.12, 0.001)
			sp["label"] = Combat.relic_special_label(str(sp["kind"]), float(sp["value"]))
		if not r.trigger.is_empty():
			r.trigger["value"] = snappedf(float(r.trigger["value"]) * 1.1, 0.001)
		# Level 5 awakens a normal relic: one more special.
		if next_lvl >= RELIC_MAX_LEVEL and r.unique_id == "" and not r.awakened:
			r.awakened = true
			r.specials.append(Combat.roll_relic_special(r.type, r.rarity, r.specials.map(func(x): return x["kind"])))
			pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Relic awakened", "text": "%s gains a new power" % r.name})
		r.level = next_lvl
		save()
		state_changed.emit()
		return ""
	return ""


# ---------------- Quests: Guild Board (Contracts + Dailies) & Milestones ----------------
## Every Reputation gain routes through here so crossing a 20-point tier can
## auto-arm a Shop Boost (the same mechanic a Detector already grants) —
## Reputation losses (none exist yet, but kept symmetrical) skip the roll.
func add_reputation(amount: int) -> void:
	if amount <= 0:
		reputation += amount
		return
	var before := reputation / 20
	reputation += amount
	if reputation / 20 > before:
		pending_shop_boost = true


## ---------------- Guild Board ----------------
## QUEST_POSTED quests are posted at a time; accept up to QUEST_ACTIVE_MAX.
## Every QUEST_REFRESH_DAYS days (a day = one rift run or rest) the unaccepted
## postings are replaced; accepted ones stay until claimed or abandoned.
## Progress is read off quest_tally / the all-time counters minus a baseline
## taken when the quest is accepted, so only work done after accepting counts.

func _quest_reward(diff: int) -> Dictionary:
	match diff:
		3:
			var stone := "D" if greater_rift_unlocked() else "E"
			return {"coins": 110 + randi() % 50, "crystals": 16 + randi() % 9, "tokens": 6 + randi() % 4, "reputation": 4, "stone": stone}
		2:
			return {"coins": 70 + randi() % 40, "crystals": 10 + randi() % 7, "tokens": 3 + randi() % 3, "reputation": 2}
	return {"coins": 40 + randi() % 30, "crystals": 5 + randi() % 6, "reputation": 1}


func _tally(key: String) -> int:
	return int(quest_tally.get(key, 0))


func _bump(key: String, n: int = 1) -> void:
	quest_tally[key] = _tally(key) + n


## Rolls one posting of a random type the guild can actually attempt now.
func roll_quest() -> Dictionary:
	var types := ["hunt", "hunt", "elite", "bounty", "seal_rank", "trial_small", "trial_flawless", "craft", "flawless_win"]
	if rift_map.any(func(sl): return sl.has("rank") and sl.has("uid")):
		types.append_array(["seal_map", "seal_map"])
	if greater_rift_unlocked():
		types.append("seal_greater")
	if rifts_sealed >= 1:
		types.append("trial_hardcore")
	var type: String = types[randi() % types.size()]
	var q := {"id": "quest%d" % next_id, "type": type, "param": "", "target": 1, "diff": 1, "status": "posted", "baseline": 0}
	next_id += 1
	match type:
		"hunt":
			var pool: Array = monsters_seen.filter(func(n): return GameData.MONSTER_NAMES.has(n))
			if pool.size() < 3:
				pool = GameData.MONSTER_NAMES
			q["param"] = str(pool[randi() % pool.size()])
			q["target"] = 4 + randi() % 4
		"elite":
			q["target"] = 1 + randi() % 2
			q["diff"] = q["target"]
		"bounty":
			q["param"] = str(GameData.BOSS_NAMES[randi() % GameData.BOSS_NAMES.size()])
			q["diff"] = 2
		"seal_map":
			var slots := rift_map.filter(func(sl): return sl.has("rank") and sl.has("uid"))
			var sl: Dictionary = slots[randi() % slots.size()]
			q["param"] = str(sl["uid"])
			q["rank"] = str(sl["rank"])
			var ri := GameData.rift_rank_index(q["rank"])
			q["diff"] = 1 if ri <= 1 else (2 if ri <= 3 else 3)
		"seal_rank":
			var r: int = clampi(max(best_rift_rank_sealed, 0) + randi() % 2, 1, 5)
			q["param"] = str(GameData.RIFT_RANKS[r]["id"])
			q["diff"] = 2 if r <= 3 else 3
		"seal_greater":
			q["diff"] = 3
		"trial_small":
			q["diff"] = 2
		"trial_flawless", "trial_hardcore":
			q["diff"] = 3
		"craft":
			q["target"] = 1 + randi() % 2
		"flawless_win":
			q["target"] = 1 + randi() % 2
	q["reward"] = _quest_reward(int(q["diff"]))
	return q


## The all-time count a quest's progress is measured against.
func _quest_current(q: Dictionary) -> int:
	match str(q["type"]):
		"hunt": return int(monster_kill_counts.get(str(q["param"]), 0))
		"elite": return elites_won
		"bounty": return _tally("boss:" + str(q["param"]))
		"seal_map": return _tally("map:" + str(q["param"]))
		"seal_rank":
			var n := 0
			for i in range(GameData.rift_rank_index(str(q["param"])), GameData.RIFT_RANKS.size()):
				n += _tally("rank_seals:%d" % i)
			return n
		"seal_greater": return _tally("greater_seals")
		"trial_small": return _tally("small_seals")
		"trial_flawless": return _tally("flawless_rifts")
		"trial_hardcore": return _tally("hardcore_seals")
		"craft": return crafts_performed
		"flawless_win": return flawless_wins
	return 0


func quest_progress(q: Dictionary) -> int:
	if str(q.get("status", "")) != "active":
		return 0
	return min(int(q["target"]), max(0, _quest_current(q) - int(q.get("baseline", 0))))


## Seeds a fresh board (new guild, or a save from the old contract/daily
## board), refreshes postings when their days are up, and fails any quest
## whose Rift Map rift broke open before it was sealed.
func resolve_guild_board() -> void:
	var changed := false
	if guild_board.is_empty() or guild_board.any(func(q): return not q.has("status")):
		guild_board = []
		board_refresh_day = day
		changed = true
	if day >= board_refresh_day:
		guild_board.assign(guild_board.filter(func(q): return str(q["status"]) == "active"))
		while guild_board.filter(func(q): return str(q["status"]) == "posted").size() < GameData.QUEST_POSTED:
			guild_board.append(roll_quest())
		board_refresh_day = day + GameData.QUEST_REFRESH_DAYS
		changed = true
	for q in guild_board:
		if str(q["type"]) == "seal_map" and str(q["status"]) != "failed" and _tally("map:" + str(q["param"])) == 0 \
				and not rift_map.any(func(sl): return str(sl.get("uid", "")) == str(q["param"])) \
				and not (not run.is_empty() and str(run.get("map_uid", "")) == str(q["param"])):
			q["status"] = "failed"
			changed = true
	if changed:
		save()


func active_quests() -> Array:
	return guild_board.filter(func(q): return str(q["status"]) == "active")


func accept_quest(quest_id: String) -> String:
	if active_quests().size() >= GameData.QUEST_ACTIVE_MAX:
		return "You can only take %d at a time" % GameData.QUEST_ACTIVE_MAX
	for q in guild_board:
		if str(q["id"]) == quest_id and str(q["status"]) == "posted":
			q["status"] = "active"
			q["baseline"] = _quest_current(q)
			save()
			state_changed.emit()
			return ""
	return ""


func abandon_quest(quest_id: String) -> void:
	guild_board.assign(guild_board.filter(func(q): return str(q["id"]) != quest_id))
	save()
	state_changed.emit()


func quest_desc(q: Dictionary) -> String:
	var t := int(q["target"])
	var s := "" if t == 1 else "s"
	match str(q["type"]):
		"hunt": return "Hunt: defeat %s ×%d" % [q["param"], t]
		"elite": return "Hunt: win %d Elite fight%s" % [t, s]
		"bounty": return "Bounty: defeat %s" % q["param"]
		"seal_map": return "Seal: close the Rank %s rift on the Rift Map before it breaks" % q.get("rank", "?")
		"seal_rank": return "Seal: seal a Rank %s+ Rift Map rift" % q["param"]
		"seal_greater": return "Seal: seal a Greater Rift"
		"trial_small": return "Trial: seal a rift with 2 heroes or fewer (plus the Champion)"
		"trial_flawless": return "Trial: seal a rift without any hero going down"
		"trial_hardcore": return "Trial: seal a rift in Hardcore Mode"
		"craft": return "Supply: craft %d item%s or relic%s" % [t, s, s]
		"flawless_win": return "Trial: win %d fight%s without a hero going down" % [t, s]
	return "?"


func quest_reward_desc(reward: Dictionary) -> String:
	var parts: Array[String] = []
	if int(reward.get("coins", 0)) > 0:
		parts.append("%d Coins" % int(reward["coins"]))
	if int(reward.get("crystals", 0)) > 0:
		parts.append("%d Crystals" % int(reward["crystals"]))
	if int(reward.get("tokens", 0)) > 0:
		parts.append("%d Tokens" % int(reward["tokens"]))
	if int(reward.get("reputation", 0)) > 0:
		parts.append("%d Reputation" % int(reward["reputation"]))
	if str(reward.get("stone", "")) != "":
		parts.append("a Rank %s Evolution Stone" % reward["stone"])
	return ", ".join(parts)


func claim_quest(quest_id: String) -> void:
	for q in guild_board:
		if str(q["id"]) != quest_id or quest_progress(q) < int(q["target"]):
			continue
		var reward: Dictionary = q["reward"]
		var ledger := 1.5 if Combat.party_has_unique_relic("quartermasters_ledger") else 1.0
		coins += int(round(int(reward.get("coins", 0)) * ledger))
		crystals += int(round(int(reward.get("crystals", 0)) * ledger))
		tokens += int(reward.get("tokens", 0))
		add_reputation(int(reward.get("reputation", 0)))
		if str(reward.get("stone", "")) != "":
			evolution_stones[reward["stone"]] = int(evolution_stones.get(reward["stone"], 0)) + 1
		guild_board.erase(q)
		_bump("quests_done")
		save()
		state_changed.emit()
		return


func milestone_progress(m: Dictionary) -> int:
	match str(m["type"]):
		"rifts_sealed": return rifts_sealed
		"total_kills":
			var s := 0
			for v in monster_kill_counts.values():
				s += int(v)
			return s
		"elites_won": return elites_won
		"bosses_won": return bosses_won
		"crafts_performed": return crafts_performed
		"full_roster": return 1 if heroes.size() >= hero_slot_cap() else 0
		"guild_tier_renowned":
			var tname := str(Combat.guild_tier_info()["name"])
			return 1 if tname == "Renowned Guild" or tname == "Legendary Guild" else 0
		"greater_unlocked": return 1 if greater_rift_unlocked() else 0
		"campaign_act": return campaign_act
		"flawless_rifts": return int(quest_tally.get("flawless_rifts", 0))
		"tower_best": return tower_best
		"endless_cycle": return best_endless_cycle
		"endless_time": return best_endless_time
		"daily_clears": return daily_clears
		"daily_streak": return daily_streak
		"boon_set4": return 1 if boon_set4_reached else 0
		"guild_tier_legendary": return 1 if str(Combat.guild_tier_info()["name"]) == "Legendary Guild" else 0
		"max_level": return 1 if heroes.any(func(h): return h.level >= 10) else 0
		"roster_size": return heroes.size()
		_: return 0


## Called once per render() — cheap (8-item loop) — grants any not-yet-claimed
## milestone the instant its condition becomes true. Returns the ids newly
## granted this call (usually 0 or 1) so the caller can show a flavor toast.
func check_milestones() -> Array[String]:
	var newly: Array[String] = []
	for m in GameData.MILESTONES:
		var mid := str(m["id"])
		if milestones_claimed.has(mid):
			continue
		if milestone_progress(m) >= int(m["target"]):
			milestones_claimed.append(mid)
			var reward: Dictionary = m["reward"]
			coins += int(reward.get("coins", 0))
			crystals += int(reward.get("crystals", 0))
			tokens += int(reward.get("tokens", 0))
			add_reputation(int(reward.get("reputation", 0)))
			newly.append(mid)
	if not newly.is_empty():
		save()
		state_changed.emit()
	return newly
