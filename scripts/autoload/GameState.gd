extends Node
## Current save state + run state — mirrors defaultState()/save()/load() and
## the state-mutating action functions (recruitHero, learnSkill, equipItem,
## engageCombat, etc.) from guild-system.html. Guild Management's upgrade
## tree (`upgrades`/`caps`) now backs every formula function below exactly
## like the HTML version's lvl()/hasCap().

signal state_changed

const SAVE_PATH := "user://save.json"
const RELIC_MAX_LEVEL := 5

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
var consumables: Array[Dictionary] = []   # owned, unused incense: [{"id":..., "incense_id": "vigor"|"warding"}]
var active_incense: Dictionary = {}       # {} = none active this run, else {"kind":..., "value":..., "name":...}
var runestones: Array[Dictionary] = []    # owned, unsocketed: [{"id":..., "runestone_id": "impact"|"aegis"}]
var recruit_pool: Array[Hero] = []
var upgrades: Dictionary = {}    # "branch.node" -> level int
var caps: Dictionary = {}        # "branch.node" -> bool
var current_champion: Hero = null
var best_endless_cycle: int = 0
var rifts_sealed: int = 0   # any rift, lesser/greater/endless — gates greater_rift_unlocked()
var triage_used_this_cycle: bool = false
var pending_shop_boost: bool = false
var run: Dictionary = {}   # {} = no active run
var rift_map: Array[Dictionary] = []   # 6 slots: [{"rank":String,"expires_at":int}] or [{}] (empty, refilled lazily)
var pending_riftbreak_ranks: Array[String] = []   # ranks that broke since the last Terminal visit, merged into one encounter


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


func buy_cap(key: String) -> String:
	var node := GameData.find_branch_node(key)
	var cap: Dictionary = node.get("cap", {})
	if node.is_empty() or cap.is_empty():
		return ""
	if lvl(key) < int(node["max"]) or has_cap(key):
		return ""
	var cost := int(cap["cost"])
	if crystals < cost:
		return "Not enough Crystals"
	crystals -= cost
	caps[key] = true
	save()
	state_changed.emit()
	return ""


# ---------------- Guild Management-derived formulas ----------------
func hero_slot_cap() -> int:
	return 4 + 2 * lvl("ops.roster")


func relic_slot_cap() -> int:
	return 3 + lvl("res.vault")


func medical_recovery_reduction() -> float:
	return min(0.5, 0.10 * lvl("ops.medical"))


func recovery_ms() -> int:
	return int(round(120000.0 * (1.0 - medical_recovery_reduction())))


func medical_bed_cap() -> int:
	return 1 + int(ceil(lvl("ops.medical") / 2.0))


func guild_mentor() -> bool:
	return has_cap("ops.roster")


func field_triage_available() -> bool:
	return has_cap("ops.medical")


func tactical_bonus() -> float:
	return 1.0 + 0.03 * lvl("ops.drill")


func respec_fee_reduction() -> float:
	return min(0.5, 0.10 * lvl("ops.trait"))


func crystal_yield_bonus() -> float:
	return 1.0 + 0.05 * lvl("infra.crystal")


func hazard_severity_reduction() -> float:
	return min(0.8, 0.08 * lvl("infra.stab"))


func anchor_artifact() -> bool:
	return has_cap("infra.stab")


func seal_token_bonus() -> float:
	return 1.0 + 0.10 * lvl("infra.seal")


func energy_extract_chance() -> float:
	return 0.05 * lvl("infra.energy")


func broker_fee_reduction() -> float:
	return min(0.10, 0.03 * lvl("log.broker"))


func black_market_unlocked() -> bool:
	return has_cap("log.broker")


func headhunter_guarantee() -> bool:
	return has_cap("log.scout")


func merchant_price_reduction() -> float:
	return min(0.6, 0.05 * lvl("log.merchant"))


func detector_drop_bonus() -> float:
	return 0.05 * lvl("log.detector")


func relic_choice_count() -> int:
	var l := lvl("res.relic")
	if l >= 3: return 4
	if l == 2: return 3
	if l == 1: return 2
	return 0


func inherited_power() -> bool:
	return has_cap("res.relic")


func synergy_unlocked() -> bool:
	return has_cap("res.theory")


func recycle_unlocked() -> bool:
	return lvl("res.recycle") > 0


func cartography_unlocked() -> bool:
	return lvl("res.cart") > 0


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
	recruit_pool = []
	upgrades = {}
	caps = {}
	current_champion = null
	best_endless_cycle = 0
	rifts_sealed = 0
	triage_used_this_cycle = false
	pending_shop_boost = false
	run = {}
	rift_map = []
	for i in 6:
		rift_map.append({})
	pending_riftbreak_ranks = []


## Only run's primitive/ID-based fields survive a save — node_state can hold
## live Hero/Item/Relic references mid-node (an in-progress fight, rolled shop
## offers), which JSON can't round-trip. Rather than building a full recursive
## serializer for that, node_state is always saved empty: on load, the run
## resumes at the right floor/party, but whatever single node was mid-progress
## just re-rolls fresh, the same as arriving at it for the first time (every
## node renderer already has that "nothing started yet" branch).
func _run_for_save() -> Dictionary:
	if run.is_empty():
		return {}
	return {
		"diff_id": run.get("diff_id", ""), "endless": run.get("endless", false),
		"cycle": run.get("cycle", 0), "hardcore": run.get("hardcore", false),
		"layers": run.get("layers", []), "pos": run.get("pos", 0),
		"chosen": run.get("chosen", {}), "hero_ids": run.get("hero_ids", []),
		"shield": run.get("shield", 0), "boss_rounds": run.get("boss_rounds", 0),
		"node_kind": run.get("node_kind", ""), "node_state": {},
		"sealed": run.get("sealed"), "anchor_used": run.get("anchor_used", false),
		"start_coins": run.get("start_coins", coins), "start_crystals": run.get("start_crystals", crystals),
		"start_tokens": run.get("start_tokens", tokens), "heroes_lost": run.get("heroes_lost", 0),
		"rift_rank": run.get("rift_rank", ""), "is_riftbreak": run.get("is_riftbreak", false),
		"riftbreak_severity": run.get("riftbreak_severity", 0),
		"riftbreak_worst_index": run.get("riftbreak_worst_index", 0),
	}


func save() -> void:
	var data := {
		"guild_name": guild_name, "guild_crest": guild_crest, "next_id": next_id, "coins": coins,
		"crystals": crystals, "tokens": tokens,
		"heroes": heroes.map(func(h): return h.to_dict()),
		"recruit_pool": recruit_pool.map(func(h): return h.to_dict()),
		"relics": relics.map(func(r): return r.to_dict()),
		"items": items.map(func(it): return it.to_dict()),
		"detectors": detectors,
		"consumables": consumables, "active_incense": active_incense, "runestones": runestones,
		"upgrades": upgrades, "caps": caps,
		"current_champion": current_champion.to_dict() if current_champion else null,
		"best_endless_cycle": best_endless_cycle,
		"rifts_sealed": rifts_sealed,
		"triage_used_this_cycle": triage_used_this_cycle,
		"pending_shop_boost": pending_shop_boost,
		"run": _run_for_save(),
		"rift_map": rift_map, "pending_riftbreak_ranks": pending_riftbreak_ranks,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	guild_name = data.get("guild_name", "")
	guild_crest = data.get("guild_crest", 1)
	next_id = data.get("next_id", 1)
	coins = data.get("coins", 60)
	crystals = data.get("crystals", 15)
	tokens = data.get("tokens", 0)
	heroes.assign(data.get("heroes", []).map(func(d): return Hero.from_dict(d)))
	recruit_pool.assign(data.get("recruit_pool", []).map(func(d): return Hero.from_dict(d)))
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
	consumables.assign(data.get("consumables", []))
	active_incense = data.get("active_incense", {})
	runestones.assign(data.get("runestones", []))
	rift_map.assign(data.get("rift_map", []))
	if rift_map.is_empty() and guild_name != "":
		# Saves from before the Rift Map existed — seed 6 empty slots so
		# resolve_rift_map() fills them with real rifts on the next render(),
		# same fallback shape as the recruit_pool fix above.
		for i in 6:
			rift_map.append({})
	pending_riftbreak_ranks.assign(data.get("pending_riftbreak_ranks", []))
	upgrades = data.get("upgrades", {})
	caps = data.get("caps", {})
	var champ_data = data.get("current_champion")
	current_champion = Hero.from_dict(champ_data) if champ_data != null else null
	best_endless_cycle = data.get("best_endless_cycle", 0)
	rifts_sealed = data.get("rifts_sealed", 0)
	triage_used_this_cycle = data.get("triage_used_this_cycle", false)
	pending_shop_boost = data.get("pending_shop_boost", false)

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
			"node_kind": run_data.get("node_kind", ""), "node_state": {},
			"sealed": run_data.get("sealed"), "anchor_used": run_data.get("anchor_used", false),
			"start_coins": run_data.get("start_coins", coins), "start_crystals": run_data.get("start_crystals", crystals),
			"start_tokens": run_data.get("start_tokens", tokens), "heroes_lost": run_data.get("heroes_lost", 0),
			"rift_rank": run_data.get("rift_rank", ""), "is_riftbreak": run_data.get("is_riftbreak", false),
			"riftbreak_severity": run_data.get("riftbreak_severity", 0),
			"riftbreak_worst_index": run_data.get("riftbreak_worst_index", 0),
		}
	return true


func find_hero(hero_id: String) -> Hero:
	for h in heroes:
		if h.id == hero_id:
			return h
	return null


func gen_recruit_offer(force_rank: String = "") -> Hero:
	return Combat.gen_hero(force_rank if force_rank != "" else Combat.weighted_rank(), 1)


func refresh_recruit_pool() -> void:
	recruit_pool = [gen_recruit_offer(), gen_recruit_offer(), gen_recruit_offer(), gen_recruit_offer()]
	if headhunter_guarantee():
		var order: Array[String] = []
		for r in GameData.RANKS:
			order.append(r["id"])
		var has_good := recruit_pool.any(func(h): return order.find(h.rank) >= 3)
		if not has_good:
			var good_ranks := ["C", "B", "A", "S"]
			recruit_pool[0] = gen_recruit_offer(good_ranks[randi() % good_ranks.size()])


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
	current_champion.hp = Combat.max_hp(current_champion)
	current_champion.downed_until = 0
	return current_champion


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
	run = {
		"diff_id": diff_id, "endless": endless, "cycle": 0, "hardcore": hardcore,
		"layers": Combat.build_layers(diff), "pos": 0, "chosen": {},
		"hero_ids": hero_ids, "shield": shield, "boss_rounds": 0,
		"node_kind": "", "node_state": {}, "sealed": null, "anchor_used": false,
		"start_coins": coins, "start_crystals": crystals, "start_tokens": tokens, "heroes_lost": 0,
		"rift_rank": rift_rank,
	}
	ensure_champion()
	auto_resolve_single_option()
	save()
	state_changed.emit()


func _diff() -> Dictionary:
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
	return _apply_rift_rank_modifiers(diff, str(run.get("rift_rank", "")))


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


func engage_node() -> void:
	var diff := _diff()
	var party: Array[Hero] = []
	party.assign(current_party().filter(func(h): return not h.is_downed() and h.hp > 0))
	if party.is_empty():
		return
	var kind := current_node_kind()
	var state := Combat.start_combat(party, kind, diff, int(run["pos"]))
	run["node_state"] = {"type": "combat", "combat_state": state, "reward_chosen": false}
	save()
	state_changed.emit()


## Sets one hero's pending action for the round about to resolve — a pure
## "what will they do" toggle, no combat math, mirrors how e.g.
## choose_node_type() just records a choice.
## `target` is a monster index into state["monsters"], meaningful only for
## "attack" — ignored (but still stored, harmlessly) for "ability"/"defend".
func set_hero_action(hero_id: String, action: String, target: int = 0) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var state: Dictionary = ns.get("combat_state", {})
	if state.is_empty():
		return
	var pending: Dictionary = state["pending_actions"]
	pending[hero_id] = {"action": action, "target": target}
	save()
	state_changed.emit()


func _apply_combat_outcome(outcome: Dictionary) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var state: Dictionary = ns.get("combat_state", {})
	if outcome["done"]:
		var result: Dictionary = outcome["result"]
		var kind := current_node_kind()
		var hardcore: bool = run.get("hardcore", false)
		if result["won"]:
			# A Riftbreak win is a consequence contained, not an opportunity —
			# no Coin/Crystal reward, no reward-choice screen (Main.gd skips
			# straight to "Return to Terminal" for this case).
			if not run.get("is_riftbreak", false):
				coins += int(result["coin"])
				crystals += int(result["crystal"]) + int(result["bonus_crystal"])
				if kind == "boss":
					run["boss_rounds"] = int(result["rounds"])
		elif hardcore and not bool(result.get("retreated", false)):
			var party: Array[Hero] = state["party"]
			var lost := 0
			for h in party:
				if not h.is_champion:
					lost += 1
				heroes.erase(h)
			run["heroes_lost"] = int(run.get("heroes_lost", 0)) + lost
		# A Riftbreak loss (not a retreat) that stayed at or below Rank A costs
		# a Coin/Crystal "compensation" penalty on top of the normal downing —
		# the game-over branch (Rank S+) is handled entirely in Main.gd's
		# result rendering, before finish_run() is ever called, so it doesn't
		# belong here. Stashed on `result` (not applied here as a live
		# coins/crystals mutation) so Main.gd can render the exact amount
		# without re-computing it, and so this stays a pure one-time effect of
		# the round transitioning to "done" rather than something a render()
		# could accidentally repeat.
		if run.get("is_riftbreak", false) and not result["won"] and not bool(result.get("retreated", false)) and int(run.get("riftbreak_worst_index", 0)) <= 5:
			var sev := int(run.get("riftbreak_severity", 0))
			var comp_coins: int = min(coins, 20 + sev * 10)
			var comp_crystals: int = min(crystals, 5 + sev * 2)
			coins -= comp_coins
			crystals -= comp_crystals
			result["riftbreak_compensation_coins"] = comp_coins
			result["riftbreak_compensation_crystals"] = comp_crystals
		ns["result"] = result
	run["node_state"] = ns
	save()
	state_changed.emit()


## Resolves every living hero's pending action for one round (see
## Combat.resolve_round). Once it reports the fight done, applies the same
## roster-level bookkeeping engage_node used to do in one shot (coin/crystal
## gain, boss_rounds tracking, hardcore hero removal on a real loss — not a
## retreat).
func resolve_round_now() -> void:
	var ns: Dictionary = run.get("node_state", {})
	var state: Dictionary = ns.get("combat_state", {})
	if state.is_empty():
		return
	_apply_combat_outcome(Combat.resolve_round(state))


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
	if idx < 0 or idx >= options.size():
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


## Shared core for all 3 hazard choices — `dmg_scale` multiplies the normal
## damage roll (1.0 = unchanged), `bonus_chance_override` replaces the
## hazard's own bonus_chance when >= 0.0 (a negative value means "use the
## hazard's own chance unmodified").
func _apply_hazard(dmg_scale: float, bonus_chance_override: float) -> void:
	var diff := _diff()
	var party: Array[Hero] = []
	party.assign(current_party().filter(func(h): return not h.is_downed() and h.hp > 0))
	ensure_hazard()
	var ns: Dictionary = run["node_state"]
	var hz: Dictionary = ns["hazard"]
	var log: Array[String] = []
	var dmg: float = (6.0 + int(diff["floors"]) * 2.0) * float(hz["dmg_mult"]) * dmg_scale
	if not run.get("anchor_used", false) and anchor_artifact():
		run["anchor_used"] = true
		log.append("The Anchor Artifact snuffs the hazard before it strikes.")
		dmg = 0.0
	else:
		var guard: float = min(0.9, hazard_severity_reduction() + Combat.party_skill_total(party, "hazard_guard_pct") + Combat.relic_special_total("hazard_guard_pct") + Combat.relic_drawback_total("hazard_guard_pct") + Combat.synergy_value_for("hazard_guard_pct"))
		dmg = round(dmg * (1.0 - guard))
		var shield: int = run.get("shield", 0)
		var abs_amt: int = min(shield, int(dmg))
		shield -= abs_amt
		dmg -= abs_amt
		run["shield"] = shield
		if abs_amt > 0:
			log.append("Relic wards absorb %d of the hazard." % abs_amt)
		if dmg > 0 and party.size() > 0:
			var per := dmg / party.size()
			for h in party:
				h.hp = max(0, int(round(h.hp - per)))
				if h.hp <= 0:
					h.downed_until = int(Time.get_unix_time_from_system() * 1000) + recovery_ms()
			log.append("The hazard deals %d damage across the party." % int(dmg))
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
		var force_epic := boosted and i == 0
		var rarity := "epic" if force_epic else Combat.weighted_rarity()
		var loot: Dictionary = {"loot_type": "relic", "obj": Combat.gen_relic(rarity)} if force_epic else Combat.gen_loot(rarity)
		var rar := GameData.find_rarity(rarity)
		var price: int = max(4, int(round((10.0 + 15.0 * float(rar["mult"])) * (1.0 - merchant_price_reduction()))))
		loot["price"] = price
		loot["bought"] = false
		offers.append(loot)
	if boosted:
		pending_shop_boost = false
	run["node_state"] = {"type": "shop", "offers": offers}


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
	if not (current_node_kind() in ["combat", "boss", "elite"]):
		tick_ability_cooldowns()
	run["pos"] = int(run["pos"]) + 1
	run["node_state"] = {}
	auto_resolve_single_option()
	save()
	state_changed.emit()


func seal_rift() -> void:
	var diff := _diff()
	var fast_clear: bool = int(run.get("boss_rounds", 99)) <= 6
	var token_mult: float = (seal_token_bonus() if fast_clear else 1.0) * (1.5 if run.get("hardcore", false) else 1.0)
	var earned_tokens := int(round(float(diff["token_base"]) * token_mult))
	var got_detector := false
	if randf() < float(diff["detector_chance"]) + detector_drop_bonus():
		var tier: String = "ascendant" if run.get("endless", false) else str(diff["id"])
		detectors.append({"id": "d" + str(next_id), "tier": tier})
		next_id += 1
		got_detector = true
	tokens += earned_tokens
	rifts_sealed += 1
	triage_used_this_cycle = false
	refresh_recruit_pool()
	current_champion = Combat.generate_champion()
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
		run["sealed"] = {"tokens": earned_tokens, "fast_clear": fast_clear, "got_detector": got_detector, "continuing": true, "cycle": new_cycle}
		save()
		state_changed.emit()
		return
	run["sealed"] = {"tokens": earned_tokens, "fast_clear": fast_clear, "got_detector": got_detector}
	save()
	state_changed.emit()


func continue_endless() -> void:
	run["sealed"] = null
	save()
	state_changed.emit()


## Earned by playing (sealing 3 rifts, lesser/greater/endless all count),
## not by spending Guild Management currency like every other unlock today.
func greater_rift_unlocked() -> bool:
	return rifts_sealed >= 3


func field_triage_action() -> String:
	if not field_triage_available():
		return "Unlock Field Triage first"
	if triage_used_this_cycle:
		return "Already used this rift cycle"
	for h in heroes:
		h.downed_until = 0
		h.hp = Combat.max_hp(h)
	triage_used_this_cycle = true
	save()
	state_changed.emit()
	return ""


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
	var now := int(Time.get_unix_time_from_system() * 1000)
	if h.is_downed():
		var remaining := h.downed_until - now
		h.downed_until = now + int(round(remaining * 0.4))
	else:
		if h.heal_until <= 0:
			var missing := 1.0 - float(h.hp) / float(Combat.max_hp(h))
			h.heal_until = now + int(recovery_ms() * missing)
		var remaining2 := h.heal_until - now
		h.heal_until = now + int(round(remaining2 * 0.4))
	h.bedded = true
	save()
	state_changed.emit()


func occupied_beds() -> int:
	var n := 0
	for h in heroes:
		if h.bedded and needs_recovery(h):
			n += 1
	return n


## Lazily resolves every hero's recovery timers against wall-clock time —
## called once per render() the same way is_downed() already lazily compares
## against Time.get_unix_time_from_system(). Closes a real gap: previously a
## downed hero's `downed_until` elapsing never actually restored their HP,
## and a merely-wounded hero (survived a fight below max HP) had no recovery
## timer at all, so Medical Bay's "recovering passively" label was aspirational.
func resolve_recovery() -> void:
	var now := int(Time.get_unix_time_from_system() * 1000)
	var changed := false
	for h in heroes:
		if h.hp <= 0 and h.downed_until <= 0:
			# Safety net for saves from before the per-hero knockout fix: a
			# hero could reach 0 HP mid-fight (party kept fighting and won)
			# with no downed_until ever set, permanently invisible to
			# needs_recovery()/Medical Bay. Give them a timer retroactively.
			h.downed_until = now + recovery_ms()
			changed = true
		elif h.downed_until > 0 and now >= h.downed_until:
			h.downed_until = 0
			h.heal_until = 0
			h.bedded = false
			h.hp = Combat.max_hp(h)
			changed = true
		elif h.hp > 0 and h.hp < Combat.max_hp(h) and not h.is_downed():
			if h.heal_until <= 0:
				var missing := 1.0 - float(h.hp) / float(Combat.max_hp(h))
				h.heal_until = now + int(recovery_ms() * missing)
				changed = true
			elif now >= h.heal_until:
				h.hp = Combat.max_hp(h)
				h.heal_until = 0
				h.bedded = false
				changed = true
		elif h.heal_until != 0:
			h.heal_until = 0
			changed = true
	if changed:
		save()


## Lazily resolves the Rift Map's countdowns — same "compare a stored
## timestamp against now, once per render()" idiom as resolve_recovery()
## above. An expired slot's rank moves into pending_riftbreak_ranks (merged
## into one forced encounter next time the player reaches the Terminal) and
## the slot refills immediately with a fresh roll, so a slot only reads
## "empty" for the instant between those two steps, never on screen.
func resolve_rift_map() -> void:
	var now := int(Time.get_unix_time_from_system() * 1000)
	var changed := false
	for i in rift_map.size():
		var slot: Dictionary = rift_map[i]
		if slot.has("rank") and now >= int(slot.get("expires_at", 0)):
			pending_riftbreak_ranks.append(str(slot["rank"]))
			rift_map[i] = {}
			changed = true
	for i in rift_map.size():
		if rift_map[i].is_empty():
			var rank := Combat.weighted_rift_rank()
			var fuse_minutes := int(GameData.find_rift_rank(rank)["fuse_minutes"])
			rift_map[i] = {"rank": rank, "expires_at": now + fuse_minutes * 60000}
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
	rift_map[slot_idx] = {}
	start_run("lesser", hero_ids, starting_relic, false, false, rank)


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
	var available: Array[Hero] = heroes.filter(func(h): return not h.is_downed() and h.hp > 0)
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
		"riftbreak_worst_index": worst_index,
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


func evolution_target(cls: Dictionary) -> Dictionary:
	var rank_idx := GameData.rank_index(cls["rank"])
	for i in range(rank_idx + 1, GameData.RANKS.size()):
		for c in GameData.CLASS_POOL:
			if c["role"] == cls["role"] and c["rank"] == GameData.RANKS[i]["id"]:
				return c
	return {}


func evolve_hero(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	if h.level < 10:
		return "Must be Level 10 to evolve"
	var cur_cls := GameData.find_class(h.pool_id)
	if cur_cls.is_empty():
		return "This hero predates the evolution system"
	var next := evolution_target(cur_cls)
	if next.is_empty():
		return "Already at the top of this path"
	var next_rank := GameData.find_rank(next["rank"])
	if crystals < int(next_rank["cost"]):
		return "Not enough Crystals"
	var cur_rank := GameData.find_rank(cur_cls["rank"])
	crystals -= int(next_rank["cost"])
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
	save()
	state_changed.emit()
	return ""


## A hero topped up to a buffed max_hp (e.g. by Vigor Incense's +hp_pct)
## while active_incense was active would otherwise be left with hp above
## their real max once the buff drops off back at camp.
func _clamp_hp_to_max() -> void:
	for h in heroes:
		h.hp = min(h.hp, Combat.max_hp(h))
	if current_champion:
		current_champion.hp = min(current_champion.hp, Combat.max_hp(current_champion))


func retreat_now() -> void:
	run = {}
	active_incense = {}
	_clamp_hp_to_max()
	save()
	state_changed.emit()


func finish_run() -> void:
	run = {}
	active_incense = {}
	_clamp_hp_to_max()
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


func learn_skill(hero_id: String, skill_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	var n := GameData.find_skill_node(h.pool_id, skill_id)
	if n.is_empty() or h.skills.get(skill_id, false):
		return ""
	if h.level < int(n["req_level"]):
		return "Requires Level %d" % n["req_level"]
	for req in n["requires"]:
		if not h.skills.get(req, false):
			return "Learn the prerequisite skill(s) first"
	if h.skill_points < int(n["cost"]):
		return "Not enough Skill Points"
	h.skill_points -= int(n["cost"])
	h.skills[skill_id] = true
	save()
	state_changed.emit()
	return ""


func respec_cost(spent: int) -> int:
	return int(round(float(20 + 10 * spent) * (1.0 - respec_fee_reduction())))


func respec_hero(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	var spent := h.skills.values().count(true)
	if spent == 0:
		return ""
	var cost := respec_cost(spent)
	if coins < cost:
		return "Need %d Coins" % cost
	coins -= cost
	h.skill_points += spent
	h.skills = {}
	save()
	state_changed.emit()
	return ""


func reroll_trait(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	if coins < 60:
		return "Need 60 Coins"
	coins -= 60
	h.trait_name = Combat.pick_trait_name(h.cls_id)
	h.hp = min(Combat.max_hp(h), h.hp)
	save()
	state_changed.emit()
	return ""


func scrub_trait(hero_id: String) -> String:
	if lvl("ops.trait") < 1:
		return "Unlock the Trait Management Office first"
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
	if lvl("ops.trait") < 1:
		return "Unlock the Trait Management Office first"
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


func item_slot_type_of(it: Item) -> String:
	return it.slot_type()


## A Legendary item's locked_role/locked_subclasses restricts who can equip
## it — empty on both means no restriction (every normal item, and most
## Legendaries).
func item_fits_hero(it: Item, h: Hero) -> bool:
	if it.locked_role != "" and h.cls_id != it.locked_role:
		return false
	if not it.locked_subclasses.is_empty() and not it.locked_subclasses.has(h.pool_id):
		return false
	return true


func equip_item(hero_id: String, slot_type: String, idx: int, item_id: String) -> void:
	var h := find_hero(hero_id)
	if not h:
		return
	for it in items:
		if it.equipped_to == hero_id and it.slot_type() == slot_type and it.equipped_idx == idx:
			it.equipped_to = ""
			it.equipped_idx = -1
	if item_id == "":
		save()
		state_changed.emit()
		return
	var target: Item = null
	for it in items:
		if it.id == item_id:
			target = it
			break
	if not target or target.slot_type() != slot_type:
		return
	if not item_fits_hero(target, h):
		return
	var cap := GameData.weapon_slots(h.pool_id) if slot_type == "weapon" else GameData.gear_slots(h.rank)
	if idx >= cap:
		return
	target.equipped_to = hero_id
	target.equipped_idx = idx
	save()
	state_changed.emit()


func upgrade_relic(relic_id: String) -> String:
	for r in relics:
		if r.id != relic_id:
			continue
		if r.level >= RELIC_MAX_LEVEL:
			return "Already max level"
		var rar := GameData.find_rarity(r.rarity)
		var cost := int(round(15.0 * float(rar["mult"]) * r.level))
		if crystals < cost:
			return "Not enough Crystals"
		crystals -= cost
		r.dmg = int(round(r.dmg * 1.15))
		r.hp = int(round(r.hp * 1.15))
		var next_lvl := r.level + 1
		if r.has_special():
			var growth := 1.30 if r.level >= 3 else 1.15
			r.special_value = snappedf(r.special_value * growth, 0.001)
		elif next_lvl >= 3 and r.unique_id == "":
			var domain := Combat.domain_for_type(r.type)
			var pool: Array = GameData.RELIC_SPECIALS.filter(func(x): return x["domain"] == domain)
			var s: Dictionary = pool[randi() % pool.size()]
			r.special_kind = s["kind"]
			r.special_value = snappedf(s["value"] * float(rar["mult"]), 0.001)
			r.special_label = s["label"]
		r.level = next_lvl
		save()
		state_changed.emit()
		return ""
	return ""
