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
var key_hints := false      # keycaps on the fight's command buttons (settings.json); tooltips always name the key
var colorblind := false      # blue instead of green against red, rarity letters on items (settings.json)
var language := "en"         # a GameData.LANGUAGES locale (settings.json)
var hearing_aid := false     # captions for meaningful sounds + an edge pulse on big hits (settings.json; see AudioManager.cue)
var ui_scale: float = 1.0   # whole-UI scale (Window.content_scale_factor), a settings.json preference   # animation time scale inside a rift (x1/x2/x3), a settings.json preference
var sfx_volume: float = 1.0
var resolution_idx: int = 0
var guild_name: String = ""
var guild_crest: int = 1   # 1-8, index into GameData.CREST_PATH
var next_id: int = 1
var coins: int = 60
var crystals: int = 15
var heroes: Array[Hero] = []
var relics: Array[Relic] = []
var items: Array[Item] = []
var tonics: Dictionary = {}   # tonic id -> count carried (GameData.TONIC_TYPES; belt of TONIC_CAP)
var recruit_pool: Array[Hero] = []
var recruit_until: Dictionary = {}   # offer id -> the last day it waits on the board
var recruit_rerolls: int = 0         # rerolls and commissions since payday (each doubles the next)
var upgrades: Dictionary = {}    # "branch.node" -> level int
var caps: Dictionary = {}        # "branch.node" -> bool
var champion_roll: Array[String] = []   # this guild's champions (GameData.CHAMPION_ROLL of the pool)
var champions: Dictionary = {}   # freed champion id -> level
var overseer: String = ""        # the champion overseeing rift runs
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
var endless_best := {}             # region id -> best seconds there
var endless_milestones: Array = []   # ENDLESS_MILESTONES "at" values already paid
var boon_set4_reached: bool = false
var tower_best: int = 0          # highest Tower of Trials floor ever cleared
var tower_week: int = 0          # tower_week_id() the weekly ladder progress belongs to
var tower_week_cleared: int = 0  # ladder floors (91+) cleared this week
var rifts_sealed: int = 0   # any rift, lesser/greater/endless — gates greater_rift_unlocked()
var best_rift_rank_sealed: int = -1   # highest ladder rank sealed (GameData.RIFT_RANKS index) — opens the next rank
var triage_used_this_cycle: bool = false
var pending_shop_boost: bool = false
var guide_hidden: bool = false   # the camp's "Getting started" checklist was dismissed
var last_party: Array[String] = []   # the heroes who went out last (party assembly opens on them)
var party_presets: Array = [[], [], []]   # saved loadouts: [[hero id, row], ...] each
var accord_pages: int = 0     # pages of the Grandmaster's ledger found (GameData.LEDGER_PAGES, in order)
var relics_found: Array = []   # every Legendary relic id this guild has held (the Compendium's record)

## One-shot flag for a hero/Champion that just rolled Rank S from any of the
## blind-reroll sources (recruit-offer reroll, Champion reroll, or the free
## automatic refresh on rift seal) — {} = none. Consumed by Main.render() the
## same way _flavor_toast is, so the celebration fires wherever the player
## happens to be, not just on the Recruits screen.
var pending_s_rank_reveal: Dictionary = {}
var pending_toasts: Array = []   # UI-only, never saved: [{cls_id, pool_id, title, text}] for Main's portrait pop-ups
var bonds: Dictionary = {}   # "<hero_id>|<hero_id>" (sorted) -> rifts sealed together; see GameData.BOND_LEVEL_RIFTS
var run: Dictionary = {}   # {} = no active run
var monsters_seen: Array[String] = []      # bestiary — every monster/elite/boss name ever encountered
var bosses_defeated: Array[String] = []    # bestiary — boss names ever defeated
var hazards_seen: Array[String] = []       # bestiary — hazard type ids ever rolled

# --- Quests (Guild Board contracts/dailies, Milestones,
# escort quests folded into combat, Reputation currency) ---
var reputation: int = 0
var monster_kill_counts: Dictionary = {}   # monster/elite/boss name -> all-time kill count
var crafts_performed: int = 0
var flawless_wins: int = 0   # wins where no hero was ever knocked out
var elites_won: int = 0      # every Elite win, unlike bosses_defeated/monsters_seen which only track distinct names
var bosses_won: int = 0      # every Boss win, same distinction
var guild_board: Array[Dictionary] = []    # rotating pool of quest dicts, see roll_quest()
var day: int = 0   # in-game days: one passes per rift run or rest (see pass_time)
var rival_name: String = ""      # the rival guild (GameData.RIVAL_NAMES)
var rival_renown: int = 0
var rival_ahead: int = 0          # set at payday: 1 = we lead (better recruits), -1 = they lead, 0 = not compared yet
var feast_week: int = -1          # the payday week a feast was last held
var training_week: int = -1       # the week the Training Yard count below belongs to
var trained_this_week: int = 0
## What the Feedback report says about how the guild was played: seconds
## in the game ("secs") and fights won and lost by hand and on Auto
## ("hand_w", "hand_l", "auto_w", "auto_l").
var session: Dictionary = {}
var rival_event: Dictionary = {}   # the rival's move waiting for an answer ({type, day, ...}; see maybe_rival_move)
var contest_start: Dictionary = {}   # both guilds' Renown when this month's contest began ({ours, theirs}; empty: not started)
var hero_request: Dictionary = {}   # this week's request: {type, ids, day}, or empty
var wage_raise: Dictionary = {}     # hero id -> extra wage share from granted raises
var pay_rate: Dictionary = {}       # hero id -> "half"/"bonus" set in the Ledger (absent = full pay)
var week_start_coins: int = -1   # Gold right after the last payday (-1: not yet), for "since payday"
var payday_report: Dictionary = {}   # the last payday: {day, due, paid, unpaid, left, rival}
var guild_news: Array = []        # recent rival/contract/payday lines for the Ledger (newest first)
var runs_started: int = 0   # the first one is a training rift (GameData.TRAINING_RIFT)
var campaign_act: int = 1   # the act in progress (GameData.CAMPAIGN); CAMPAIGN.size()+1 = campaign complete
var pending_stories: Array = []   # story cards Main shows before anything else: {title, subtitle, text}
var features_seen: Array = []   # unlocked features already announced (see check_feature_unlocks)
var hints_seen: Array = []   # coach tips dismissed
var last_export_day: int = -1   # day the save was last exported as a backup (-1 = never)
var tips_off: bool = false
var board_refresh_day: int = 0   # the day the Guild Board's unaccepted postings are replaced
var quest_tally: Dictionary = {}   # counters only quests read: boss:<name>, map:<uid>, rank_seals:<i>, *_seals, flawless_rifts
var milestones_claimed: Array[String] = []  # GameData.MILESTONES ids already granted
var breach: Dictionary = {}       # a swelling rift: {rank (ladder index), region ("camp" or a biome), started, breaks_on, broken}, or empty
var breach_next_day: int = -1     # the day the next rift swells (-1: breaches not started yet)
var damaged: Dictionary = {}      # Guild Management key -> levels lost to a Riftbreak until repaired




## A Guild Management upgrade's working level: a building damaged in a
## Riftbreak works that many levels lower until repaired.
func lvl(key: String) -> int:
	return maxi(0, int(upgrades.get(key, 0)) - int(damaged.get(key, 0)))


## Hooks for GameStateBreach (later in the chain): a day passed, a ladder rift was sealed.
func _on_day_passed() -> void:
	pass


func _on_rift_sealed(_rank_idx: int) -> void:
	pass


func has_cap(key: String) -> bool:
	return caps.get(key, false)


func upgrade_node(key: String) -> String:
	var node := GameData.find_branch_node(key)
	if node.is_empty():
		return ""
	var cur := int(upgrades.get(key, 0))   # the built level (a damaged building still keeps it)
	if cur >= int(node["max"]):
		return ""
	var cost: int = int(node["cost_base"]) + int(node["cost_step"]) * cur
	var gold := str(node.get("currency", "")) == "gold"
	if (coins if gold else crystals) < cost:
		return tr("Not enough Gold") if gold else tr("Not enough Essence")
	if gold:
		coins -= cost
	else:
		crystals -= cost
	upgrades[key] = cur + 1
	save()
	state_changed.emit()
	return ""


# ---------------- Guild Management-derived formulas ----------------
## Two more than a party holds from the start, so there's a bench to choose from.
func hero_slot_cap() -> int:
	return 6 + 2 * lvl("ops.barracks")


func relic_slot_cap() -> int:
	var l := lvl("res.vault")
	return 3 + (1 if l >= 3 else 0) + (1 if l >= 5 else 0)


func medical_recovery_reduction() -> float:
	return 0.15 * lvl("ops.infirmary")


## Runs a downed hero sits out (Medical upgrades bring it down to 1). A new
## guild (fewer than 3 rifts sealed, i.e. before Greater Rifts open) only ever
## loses a hero for 1 run: early wipes are common and a small roster otherwise
## sits idle.
func recovery_runs() -> int:
	if rifts_sealed < 3:
		return 1
	return max(1, int(round(GameData.DOWNED_RECOVERY_RUNS * (1.0 - medical_recovery_reduction()))))


## A hero knocked out during a run: +1 because the run it happened in counts
## down when it ends, so they then miss recovery_runs() whole runs.
func knock_out(h: Hero) -> void:
	h.hp = 0
	if not run.is_empty():
		run["any_ko"] = true
	h.down_runs = recovery_runs() + (0 if run.is_empty() else 1)
	h.morale = clampi(h.morale + GameData.MORALE_KNOCKOUT, 0, 100)


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


func seal_bonus_mult() -> float:
	return 1.0 + 0.10 * lvl("infra.wardstones")


func broker_fee_reduction() -> float:
	return 0.02 * lvl("log.trade")


func black_market_unlocked() -> bool:
	return lvl("log.trade") >= 3


func merchant_price_reduction() -> float:
	return 0.06 * lvl("log.trade")


func cache_chance_bonus() -> float:
	return 0.05 * lvl("log.trade")


func shop_guaranteed_epic() -> bool:
	return lvl("log.trade") >= 5


## A line in the guild's news (the Ledger), newest first.
func _news(line: String) -> void:
	guild_news.push_front(tr("Day %d: %s") % [day, tr(str(line))])
	if guild_news.size() > 12:
		guild_news.resize(12)


## Whether a staged feature (GameData.FEATURE_UNLOCKS) is open yet; anything
## not in the table is always open, and so is anything already announced. The
## first seals open one thing at a time, so a new player meets them in turn.
func feature_unlocked(id: String) -> bool:
	if features_seen.has(id):
		return true
	match id:
		"inventory": return not items.is_empty() or not relics.is_empty() or rifts_sealed > 0
		"medical": return runs_started > 1 or (runs_started == 1 and run.is_empty()) or rifts_sealed > 0
		"bestiary": return not monsters_seen.is_empty()
		"quests": return rifts_sealed >= 1
		"management": return rifts_sealed >= 2
		"crafting", "daily", "rival": return rifts_sealed >= 3
		"tower": return campaign_act >= 2
		"champions": return not champions.is_empty()
	return true


func recruit_offer_count() -> int:
	var l := lvl("log.scouts")
	return 4 + (1 if l >= 1 else 0) + (1 if l >= 4 else 0) + rival_ahead


func headhunter_guarantee() -> bool:
	return lvl("log.scouts") >= 3


func recruit_reroll_cost() -> int:
	return recruit_reroll_base() * (1 << mini(recruit_rerolls, GameData.RECRUIT_REROLL_DOUBLINGS))


## The week's first reroll (the Scouts' Lodge halves it).
func recruit_reroll_base() -> int:
	return GameData.RECRUIT_REROLL_COST / (2 if lvl("log.scouts") >= 5 else 1)


func relic_choice_count() -> int:
	var l := lvl("res.vault")
	if l >= 4: return 4
	if l >= 2: return 3
	if l == 1: return 2
	return 0


func inherited_power() -> bool:
	return lvl("res.vault") >= 5


## Multiplier on every relic effect (Arcane Lab).
func relic_power_mult() -> float:
	return 1.0 + 0.05 * lvl("res.lab")


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


## node_state is saved through _pack (Items/Relics as dicts) minus the live
## fight, which holds Hero references: a reload mid-fight restarts that fight
## (same monsters — engage_node seeds from the run's seed), while shops, events,
## treasure, campfires, hazards and a finished fight's result come back exactly
## as they were, so reloading can't re-roll or re-pay a node.
func _run_for_save() -> Dictionary:
	if run.is_empty():
		return {}
	var out := {
		"diff_id": run.get("diff_id", ""),
		"layers": run.get("layers", []), "pos": run.get("pos", 0),
		"chosen": run.get("chosen", {}), "hero_ids": run.get("hero_ids", []),
		"shield": run.get("shield", 0), "boss_rounds": run.get("boss_rounds", 0),
		"node_kind": run.get("node_kind", ""), "node_state": _pack(_saveable_node_state()), "seed": run.get("seed", 0),
		"sealed": run.get("sealed"), "anchor_used": run.get("anchor_used", false),
		"start_coins": run.get("start_coins", coins), "start_crystals": run.get("start_crystals", crystals),
		"heroes_lost": run.get("heroes_lost", 0), "start_snap": run.get("start_snap", {}),
		"rift_rank": run.get("rift_rank", ""), "champion_call_used": run.get("champion_call_used", false),
		"injured": run.get("injured", []), "left_behind": run.get("left_behind", []), "heal_used": run.get("heal_used", false),
		"any_ko": run.get("any_ko", false),
		"champion_calls": run.get("champion_calls", 0), "overseer": run.get("overseer", ""), "phoenix_used": run.get("phoenix_used", false),
		"finale": run.get("finale", 0), "momentum_bonus": run.get("momentum_bonus", 0), "training": run.get("training", false), "biome": run.get("biome", "vale"),
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


## Writes a slot without ever leaving it half-written: the text goes to a
## temp file first, the previous save is kept as .bak, then the temp file
## takes its place. A crash or a closed tab mid-save can't eat the guild.
func _write_slot(slot: int, text: String) -> bool:
	var path := _slot_path(slot)
	var name := path.get_file()
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if not f:
		return false
	f.store_string(text)
	f.close()
	var dir := DirAccess.open("user://")
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(path + ".bak"):
			dir.remove(name + ".bak")
		dir.rename(name, name + ".bak")
	return dir.rename(name + ".tmp", name) == OK

## A slot's save as a Dictionary with a guild in it, falling back to the
## previous save (.bak) if the main file is missing or damaged. {} if neither
## holds one. Sets `restored_from_backup` when the fallback was used.
var restored_from_backup := false


func _read_slot(slot: int) -> Dictionary:
	restored_from_backup = false
	var path := _slot_path(slot)
	for p in [path, path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if typeof(parsed) == TYPE_DICTIONARY and String(parsed.get("guild_name", "")) != "":
			restored_from_backup = p != path
			return parsed
	return {}


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
	var parsed := _read_slot(slot)
	if parsed.is_empty():
		return {"empty": true}
	return {
		"empty": false,
		"guild_name": parsed.get("guild_name", ""),
		"rifts_sealed": parsed.get("rifts_sealed", 0),
	}


func delete_slot(slot: int) -> void:
	var path := _slot_path(slot)
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.open("user://").remove(p.get_file())


func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"music_volume": music_volume, "sfx_volume": sfx_volume, "resolution_idx": resolution_idx, "combat_speed": combat_speed, "ui_scale": ui_scale,
			"reduce_motion": reduce_motion, "colorblind": colorblind, "hearing_aid": hearing_aid, "language": language, "key_hints": key_hints,
		}))


## Switches every translated line to `language` (the next render redraws).
func apply_language() -> void:
	if _names == null:
		# Hero, item, relic and warden names, assembled from translated parts.
		_names = load("res://scripts/autoload/NameTranslation.gd").new("tr")
		TranslationServer.add_translation(_names)
	TranslationServer.set_locale(language)


var _names: Translation = null


# A script-backed Translation left in the TranslationServer crashes the engine
# at shutdown (its script is freed first), so take it out on the way out.
func _exit_tree() -> void:
	if _names != null:
		TranslationServer.remove_translation(_names)
		_names = null


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
		key_hints = bool(parsed.get("key_hints", false))
		hearing_aid = bool(parsed.get("hearing_aid", false))
		language = str(parsed.get("language", "en"))
		sfx_volume = parsed.get("sfx_volume", 1.0)
		resolution_idx = parsed.get("resolution_idx", 0)


## Records every Legendary relic the guild holds, so the Compendium
## remembers one after it's sold. Runs on every save.
func note_relics_found() -> void:
	for r in relics:
		if r.unique_id != "" and not relics_found.has(r.unique_id):
			relics_found.append(r.unique_id)


func save() -> void:
	# No guild loaded = nothing worth saving, and writing it would clobber the
	# active slot: render() runs its world-tick resolvers (resolve_guild_board
	# etc., which save) on the title screen too, before any slot is loaded — so
	# every boot used to overwrite the active slot with a blank default state
	# that load_save()/slot_summary() then treat as empty.
	if guild_name == "":
		return
	note_relics_found()
	var data := {
		"save_version": SAVE_VERSION,
		"guild_name": guild_name, "guild_crest": guild_crest, "next_id": next_id, "coins": coins,
		"crystals": crystals,
		"heroes": heroes.map(func(h): return h.to_dict()),
		"recruit_pool": recruit_pool.map(func(h): return h.to_dict()),
		"recruit_until": recruit_until, "recruit_rerolls": recruit_rerolls, "party_presets": party_presets,
		"relics": relics.map(func(r): return r.to_dict()),
		"items": items.map(func(it): return it.to_dict()),
		"tonics": tonics,
		"upgrades": upgrades, "caps": caps,
		"champion_roll": champion_roll, "champions": champions, "overseer": overseer,
		"tower_best": tower_best, "tower_week": tower_week, "tower_week_cleared": tower_week_cleared,
		"daily_attempt_day": daily_attempt_day, "daily_clears": daily_clears, "daily_streak": daily_streak, "daily_last_clear": daily_last_clear,
		"run_history": run_history, "runs_finished": runs_finished, "fallen": fallen, "heroes_lost_total": heroes_lost_total, "best_endless_time": best_endless_time, "endless_runs": endless_runs, "endless_best": endless_best, "endless_milestones": endless_milestones, "boon_set4_reached": boon_set4_reached,
		"rifts_sealed": rifts_sealed, "best_rift_rank_sealed": best_rift_rank_sealed, "rival_name": rival_name, "rival_renown": rival_renown, "rival_ahead": rival_ahead, "feast_week": feast_week, "training_week": training_week, "trained_this_week": trained_this_week, "payday_report": payday_report, "week_start_coins": week_start_coins, "hero_request": hero_request, "wage_raise": wage_raise, "pay_rate": pay_rate, "contest_start": contest_start, "rival_event": rival_event, "session": session, "guild_news": guild_news, "breach": breach, "breach_next_day": breach_next_day, "damaged": damaged,
		"triage_used_this_cycle": triage_used_this_cycle,
		"pending_shop_boost": pending_shop_boost,
		"guide_hidden": guide_hidden, "last_party": last_party, "relics_found": relics_found, "accord_pages": accord_pages,
		"run": _run_for_save(),
		
		"monsters_seen": monsters_seen, "bosses_defeated": bosses_defeated, "hazards_seen": hazards_seen,
		"reputation": reputation, "monster_kill_counts": monster_kill_counts,
		"crafts_performed": crafts_performed, "flawless_wins": flawless_wins,
		"elites_won": elites_won, "bosses_won": bosses_won,
		"guild_board": guild_board, "day": day, "runs_started": runs_started, "campaign_act": campaign_act, "features_seen": features_seen, "hints_seen": hints_seen, "last_export_day": last_export_day, "tips_off": tips_off, "board_refresh_day": board_refresh_day, "quest_tally": quest_tally, "milestones_claimed": milestones_claimed,
		"bonds": bonds,
	}
	_write_slot(active_slot, JSON.stringify(data))


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


## The active slot's save as text, for backing up or moving to another device.
func export_save_text() -> String:
	if guild_name != "":
		last_export_day = day
	save()
	if not FileAccess.file_exists(_slot_path(active_slot)):
		return ""
	return FileAccess.get_file_as_string(_slot_path(active_slot))


## Replaces `slot` with an exported save. Returns "" or why it was refused.
func import_save_text(text: String, slot: int) -> String:
	var parsed = JSON.parse_string(text.strip_edges())
	if typeof(parsed) != TYPE_DICTIONARY or String(parsed.get("guild_name", "")) == "":
		return tr("That doesn't look like a Guildhold save")
	if int(parsed.get("save_version", 1)) > SAVE_VERSION:
		return tr("That save is from a newer version of the game")
	# The slot's current save is kept as .bak by _write_slot.
	if not _write_slot(slot, JSON.stringify(parsed)):
		return tr("Couldn't write the save slot")
	return ""
const HAZARD_BYPASS_COST := 15


func greater_rift_unlocked() -> bool:
	return campaign_act >= 2


func endless_unlocked() -> bool:
	return campaign_act >= 3

## Crafting Hall: combine 3 unequipped items/relics of the same category (or
## relic type) and rarity into 1 of the next rarity up — a sink for excess
## common/rare loot beyond selling it. Legendary is deliberately not on this
## ladder (uniques are hand-authored fixed drops, not something Combat.gen_*
## can roll toward), so epic is the ceiling a craft can produce.
const CRAFT_RARITY_UP := {"common": "rare", "rare": "epic"}
const GEAR_SCORE_WEIGHT := {"dmg_pct": 1.0, "hp_pct": 0.9, "dodge_pct": 0.8, "mend_pct": 0.8, "ability_power": 0.7, "speed_pct": 0.6, "escalate_pct": 0.5}


func tonic_count(id: String = "") -> int:
	if id != "":
		return int(tonics.get(id, 0))
	var n := 0
	for k in tonics:
		n += int(tonics[k])
	return n


func add_tonic(id: String, n: int = 1) -> int:
	var add := mini(n, GameData.TONIC_CAP - tonic_count())
	if add > 0:
		tonics[id] = tonic_count(id) + add
	return add


## Weekly Gold for every Guild Management level (GameData.UPKEEP_PER_LEVEL).
func upkeep() -> int:
	var levels := 0
	for k in upgrades:
		levels += int(upgrades[k])
	return levels * GameData.UPKEEP_PER_LEVEL


func training_slots() -> int:
	return GameData.TRAINING_SLOTS + lvl("ops.drill") / 2


func training_left() -> int:
	return training_slots() - (trained_this_week if training_week == day / GameData.PAYDAY_DAYS else 0)


func feast_seats() -> int:
	return GameData.FEAST_SEATS + lvl("log.trade")

