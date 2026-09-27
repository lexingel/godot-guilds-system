extends "res://scripts/autoload/game_state/GameStateRuns.gd"
## GameState, part 7 (the autoload): starting special runs, Guild Orders, and loading/resetting a guild.
## The chain, bottom up: game_state/GameStateCore.gd (state, formulas, saving)
## -> Heroes -> Items -> Quests -> Modes -> Runs -> this file. Each part only calls
## down the chain; every var/const/signal lives in Core.


func reset() -> void:
	guild_name = ""
	guild_crest = 1
	next_id = 1
	coins = 100
	crystals = 15
	heroes = []
	relics = []
	items = []
	tonics = {}
	recruit_pool = []
	upgrades = {}
	caps = {}
	champion_offers = []
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
	rival_name = str(GameData.RIVAL_NAMES[randi() % GameData.RIVAL_NAMES.size()])
	rival_renown = 0
	rival_ahead = 0
	feast_week = -1
	payday_report = {}
	guild_news = []
	triage_used_this_cycle = false
	pending_shop_boost = false
	guide_hidden = false
	run = {}
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
	last_export_day = -1
	tips_off = false
	board_refresh_day = 0
	quest_tally = {}
	milestones_claimed = []
	bonds = {}


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


func load_save() -> bool:
	var parsed := _read_slot(active_slot)
	if parsed.is_empty():
		return false
	if restored_from_backup:
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Save restored",
			"text": "Your last save was damaged, so the one just before it was loaded."})
	var data: Dictionary = _migrate_save(parsed)
	# A save file can exist on disk for a slot that was never actually
	# founded (e.g. a stray write while "Name Your Guild" was still open) —
	# slot_summary() already treats a blank guild_name as "empty" for slot
	# selection, so this has to agree: otherwise _switch_slot()'s "if not
	# load_save(): reset()" skips reset() for a slot that looks reusable,
	# and every field reset() seeds is left at its bare class default.
	if String(data.get("guild_name", "")) == "":
		return false
	guild_name = data.get("guild_name", "")
	guild_crest = data.get("guild_crest", 1)
	next_id = data.get("next_id", 1)
	coins = data.get("coins", 60)
	crystals = data.get("crystals", 15)
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
	var tn = data.get("tonics", {})
	tonics = tn if tn is Dictionary else ({"healing": int(tn)} if int(tn) > 0 else {})
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
			"text": "Upgrades are fewer and much stronger now. %d Essence spent on the old tree were refunded." % int(data["_mgmt_refund"])})
	champion_offers.assign((data.get("champion_offers", []) as Array).map(func(c): return Hero.from_dict(c)))
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
	rival_name = str(data.get("rival_name", GameData.RIVAL_NAMES[0]))
	rival_renown = int(data.get("rival_renown", 0))
	rival_ahead = int(data.get("rival_ahead", 0))
	feast_week = int(data.get("feast_week", -1))
	payday_report = data.get("payday_report", {})
	guild_news = data.get("guild_news", [])
	runs_started = int(data.get("runs_started", 0 if rifts_sealed == 0 and monsters_seen.is_empty() else 1))
	pending_stories = []
	if data.has("campaign_act"):
		campaign_act = int(data["campaign_act"])
	else:
		# A guild from before the campaign keeps what it had unlocked.
		campaign_act = 3 if int(data.get("best_endless_cycle", 0)) > 0 else (2 if rifts_sealed >= 3 else 1)
	hints_seen = data.get("hints_seen", [])
	last_export_day = int(data.get("last_export_day", -1))
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
	if run_data.get("endless", false):
		# A run of the old, floor-by-floor Endless Rift: it's a survival mode
		# now, so the run ends here (heroes keep their HP and loot).
		run_data = {}
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": "The Endless Rift has changed",
			"text": "Your Endless run was closed: it's a real-time survival run now (Rift Hall)."})
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
			"diff_id": run_data.get("diff_id", ""),
			"layers": run_data.get("layers", []), "pos": run_data.get("pos", 0),
			"chosen": chosen_fixed, "hero_ids": run_data.get("hero_ids", []),
			"shield": run_data.get("shield", 0), "boss_rounds": run_data.get("boss_rounds", 0),
			"node_kind": run_data.get("node_kind", ""), "node_state": _unpack(run_data.get("node_state", {})), "seed": int(run_data.get("seed", randi())),
			"sealed": run_data.get("sealed"), "anchor_used": run_data.get("anchor_used", false),
			"start_coins": run_data.get("start_coins", coins), "start_crystals": run_data.get("start_crystals", crystals),
			"heroes_lost": run_data.get("heroes_lost", 0),
			"rift_rank": run_data.get("rift_rank", ""), "champion_call_used": bool(run_data.get("champion_call_used", false)),
			"injured": run_data.get("injured", []), "left_behind": run_data.get("left_behind", []), "heal_used": bool(run_data.get("heal_used", false)),
			"any_ko": bool(run_data.get("any_ko", false)),
			"champion_calls": int(run_data.get("champion_calls", 1 if run_data.get("champion_call_used", false) else 0)), "phoenix_used": bool(run_data.get("phoenix_used", false)),
			"finale": int(run_data.get("finale", 0)), "momentum_bonus": int(run_data.get("momentum_bonus", 0)), "training": bool(run_data.get("training", false)), "biome": str(run_data.get("biome", "vale")),
			"orders_used": int(run_data.get("orders_used", 0)), "boons": run_data.get("boons", []), "events_seen": run_data.get("events_seen", []),
		}
		if int(run_data.get("daily", -1)) >= 0:
			run["daily"] = int(run_data["daily"])
		if run_data.has("tower"):
			run["tower"] = int(run_data["tower"])
			run["tower_snap"] = run_data.get("tower_snap", {})
	return true


## Starts the current act's finale rift: its tier's rift, tougher by the act's
## mult, ending in the act's named foe.
func start_finale(hero_ids: Array[String], starting_relic: Relic) -> void:
	if not finale_ready():
		return
	var act := current_act()
	start_run(str(act["tier"]), hero_ids, starting_relic)
	run["finale"] = int(act["act"])
	run["training"] = false
	run["biome"] = str(GameData.ACT_BIOME[int(act["act"])])
	run["layers"] = Combat.build_layers(_diff())
	save()


func start_daily(hero_ids: Array[String]) -> void:
	if not daily_available():
		return
	var info := daily_info()
	start_run(str(info["diff_id"]), hero_ids, null)
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
		"diff_id": "tower",
		"layers": [{"options": [info["kind"]]}], "pos": 0, "chosen": {},
		"hero_ids": ids, "shield": shield, "boss_rounds": 0,
		"node_kind": "", "node_state": {}, "sealed": null, "anchor_used": false,
		"start_coins": coins, "start_crystals": crystals, "heroes_lost": 0,
		"rift_rank": "", "seed": int(info["seed"]), "biome": str(info["biome"]), "tower": f,
	}
	var snap := {}
	for h in current_party():
		snap[h.id] = [h.hp, h.down_runs, h.bedded]
	run["tower_snap"] = snap
	auto_resolve_single_option()
	save()
	state_changed.emit()
