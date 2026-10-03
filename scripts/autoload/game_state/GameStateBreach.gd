extends "res://scripts/autoload/game_state/GameStateRuns.gd"
## Riftbreaks (docs/design/riftbreak.md, numbers in GameDataBreach): a rift
## swells, counts down in days, and is either sealed in time or breaks. A
## broken rift blocks rift runs until the guild defends (DefenseRun), and
## resolve_breach() pays out or takes its toll: Gold and Essence, damaged
## buildings (see lvl()) and wounded heroes.


func breach_unlocked() -> bool:
	return campaign_act >= GameData.BREACH_UNLOCK_ACT


func breach_active() -> bool:
	return not breach.is_empty()


func breach_broken() -> bool:
	return not breach.is_empty() and bool(breach.get("broken", false))


## A broken rift has to be defended before any other rift run.
func breach_blocks_runs() -> bool:
	return breach_broken()


func breach_days_left() -> int:
	return maxi(0, int(breach.get("breaks_on", day)) - day)


func breach_rank_id() -> String:
	return str(GameData.RIFT_RANKS[int(breach.get("rank", 0))]["id"])


## Where it breaks, for text: "your camp" or the region's name.
func breach_place() -> String:
	var region := str(breach.get("region", "vale"))
	return tr("your camp") if region == "camp" else tr(str(GameData.BIOMES.get(region, GameData.BIOMES["vale"])["name"]))


func breach_warn_days() -> int:
	return GameData.BREACH_WARN + (1 if lvl("def.watch") >= 1 else 0) + (1 if lvl("def.watch") >= 3 else 0)


## What the Defenses research brings to a defense (DefenseRun opts).
func defense_opts() -> Dictionary:
	var a := lvl("def.armory")
	var e := lvl("def.engineering")
	var p := lvl("def.palisade")
	var towers: Array = ["ballista", "brazier"]
	for pair in [[1, "frost"], [2, "ward"], [3, "chapel"]]:
		if a >= int(pair[0]):
			towers.append(pair[1])
	return {"towers": towers, "max_tier": 3 if e >= 3 else 2, "supplies": 20 * p, "integrity": 2 * p,
		"tower_dmg": 1.0 + 0.06 * a, "cost": 1.0 - 0.06 * e, "sell_back": 1.0 if e >= 5 else GameData.DEFENSE_SELL_BACK,
		"hero_hp": 1.0 + 0.06 * lvl("def.watch"), "foe_mult": tide_strength() / tidewall_factor() if breach.has("tide") else 1.0}


## Idle heroes fit to stand at a post (not wounded), strongest first.
func defense_candidates() -> Array[Hero]:
	var out: Array[Hero] = idle_heroes().filter(func(h): return h.down_runs == 0 and h.hp > 0)
	out.sort_custom(func(a, b): return Combat.power_of(a) > Combat.power_of(b))
	return out


## Rewards scale with the breach's ladder rank (and a tide's strength).
func breach_scale() -> float:
	return (1.0 + GameData.BREACH_RANK_SCALE * int(breach.get("rank", 0))) * tide_strength()


## How much the guild's tidewalls divide a tide's strength by.
func tidewall_factor() -> float:
	return 1.0 + GameData.TIDEWALL_STEP * tidewalls


## The next tidewall's [Gold, Essence].
func tidewall_cost() -> Array:
	return [int(GameData.TIDEWALL_COST[0]) + int(GameData.TIDEWALL_COST_STEP[0]) * tidewalls,
		int(GameData.TIDEWALL_COST[1]) + int(GameData.TIDEWALL_COST_STEP[1]) * tidewalls]


## "" if a tidewall can be raised now, else why not.
func tidewall_lock() -> String:
	if accord_ending != "break":
		return tr("Only a guild that broke the Accord faces the tides")
	var c := tidewall_cost()
	if coins < int(c[0]) or crystals < int(c[1]):
		return tr("Needs %d Gold and %d Essence") % [int(c[0]), int(c[1])]
	return ""


func raise_tidewall() -> String:
	var lock := tidewall_lock()
	if lock != "":
		return lock
	var c := tidewall_cost()
	coins -= int(c[0])
	crystals -= int(c[1])
	tidewalls += 1
	_news(tr("A tidewall is raised against the Open Hollow (%d in all).") % tidewalls)
	save()
	state_changed.emit()
	return ""


## How much stronger this tide is than the first (1.0 for a normal breach).
func tide_strength() -> float:
	return 1.0 + GameData.TIDE_GROWTH * int(breach.get("held_before", int(breach.get("tide", 1)) - 1))


var _resolving := false


func _on_day_passed() -> void:
	check_completion_board()
	if not breach_unlocked() or _resolving or accord_ending == "renew":   # the Accord renewed: the rifts stay shut
		return
	if breach.is_empty():
		if breach_next_day < 0:
			breach_next_day = day + GameData.BREACH_FIRST_DELAY
		elif day >= breach_next_day:
			_swell_breach()
		return
	if not breach_broken() and day >= int(breach["breaks_on"]):
		breach["broken"] = true
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": tr("The rift has broken!"),
			"text": tr("Monsters pour out near %s. Defend before your next rift run.") % breach_place()})
		_news(tr("A Rank %s rift broke near %s.") % [tr(breach_rank_id()), breach_place()])


## A new breach: your best sealed rank, sometimes one above if it's open.
func _swell_breach() -> void:
	if accord_ending == "break":   # the Open Hollow: a tide, stronger each time
		tide_count += 1
		var tr_idx := GameData.rift_rank_index(GameData.TIDE_RANK)
		breach = {"rank": tr_idx, "region": "camp" if tr_idx >= GameData.rift_rank_index(GameData.BREACH_CAMP_RANK) else pick_biome(),
			"started": day, "breaks_on": day + GameData.TIDE_WARN, "broken": false, "tide": tide_count, "held_before": tides_held}
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": tr("Tide %d of the Open Hollow") % tide_count,
			"text": tr("It breaks over %s in %d days, %d%% stronger than the first. A tide can't be sealed away; it has to be held.") % [breach_place(), breach_days_left(), int(round((tide_strength() - 1.0) * 100.0))]})
		return
	var best := maxi(0, best_rift_rank_sealed)
	var idx := best
	if randf() < GameData.BREACH_UP_CHANCE and best + 1 < GameData.RIFT_RANKS.size() and ladder_rank_lock(str(GameData.RIFT_RANKS[best + 1]["id"])) == "":
		idx = best + 1
	var camp := idx >= GameData.rift_rank_index(GameData.BREACH_CAMP_RANK)
	breach = {"rank": idx, "region": "camp" if camp else pick_biome(), "started": day, "breaks_on": day + breach_warn_days(), "broken": false}
	pending_toasts.append({"cls_id": "", "pool_id": "", "title": tr("A rift is swelling"),
		"text": tr("A Rank %s rift near %s breaks in %d days. Seal a Rank %s rift or higher before then, or prepare to defend.") % [tr(breach_rank_id()), breach_place(), breach_days_left(), tr(breach_rank_id())]})


## Sealing a ladder rift at or above the breach's rank closes it in time.
func _on_rift_sealed(rank_idx: int) -> void:
	if not breach_active() or breach_broken() or rank_idx < int(breach["rank"]) or breach.has("tide"):
		return
	var ess := int(round(GameData.BREACH_PREVENT_ESSENCE * breach_scale()))
	crystals += ess
	pending_toasts.append({"cls_id": "", "pool_id": "", "title": tr("The swelling rift is closed"),
		"text": tr("Sealing that rift closed it before it broke. +%d Essence.") % ess})
	_news(tr("A swelling Rank %s rift was closed in time.") % tr(breach_rank_id()))
	_close_breach()


func _close_breach() -> void:
	breach = {}
	var wait := randi_range(GameData.BREACH_EVERY_MIN, GameData.BREACH_EVERY_MAX)
	wait -= int(founding_rule("breach_sooner", 0))   # the Hollow knows the Last of the Accord
	if sworn("long_watch"):
		wait = maxi(2, wait / 2)
	# The Accord broken: a tide breaks every week (it swells TIDE_WARN days
	# before, and holding it takes a day).
	breach_next_day = day + (GameData.TIDE_DAYS - GameData.TIDE_WARN - 1 if accord_ending == "break" else wait)


## The defense's outcome. result: {held: bool, integrity: 0-1 kept,
## fallen: [hero ids of posted heroes who fell; wounded only on a loss]}. Returns what happened, for the results screen:
## {held, coins, crystals, lost_coins, lost_crystals, damaged: [names], wounded: [names]}.
## A defense takes the guild's day.
func resolve_breach(result: Dictionary) -> Dictionary:
	var held := bool(result.get("held", false))
	_resolving = true   # the day passing below mustn't tick breaches
	pass_time()   # the defense takes the day; its wounds come after
	_resolving = false
	var out := {"held": held, "coins": 0, "crystals": 0, "lost_coins": 0, "lost_crystals": 0, "damaged": [], "wounded": []}
	# Defenders who fell are only hurt for real when the defense is lost.
	for hid in ([] if held else result.get("fallen", [])):
		var h := find_hero(str(hid))
		if h and h.down_runs == 0:
			knock_out(h)
			(out["wounded"] as Array).append(h.name)
	if held:
		var keep := clampf(float(result.get("integrity", 1.0)), 0.0, 1.0)
		out["coins"] = int(round(GameData.BREACH_HELD_GOLD * breach_scale() * (0.5 + 0.5 * keep)))
		out["crystals"] = int(round(GameData.BREACH_HELD_ESSENCE * breach_scale() * (0.5 + 0.5 * keep)))
		coins += int(out["coins"])
		crystals += int(out["crystals"])
		if breach.has("tide"):
			tides_held += 1
			_add_postgame_laurels(GameData.TIDE_LAURELS, {"best_tide": tides_held})
			out["laurels"] = GameData.TIDE_LAURELS
		_news(tr("The guild held against a Rank %s Riftbreak.") % tr(breach_rank_id()))
	else:
		# Never the coming payday's wages: the loss comes out of what's above the bill.
		out["lost_coins"] = int(maxi(0, coins - int(payday_forecast()["bill"])) * GameData.BREACH_LOSS_SHARE)
		out["lost_crystals"] = int(crystals * GameData.BREACH_LOSS_SHARE)
		coins -= int(out["lost_coins"])
		crystals -= int(out["lost_crystals"])
		for k in (2 if str(breach.get("region", "")) == "camp" else 1):
			var name := _damage_building()
			if name != "":
				(out["damaged"] as Array).append(name)
		_news(tr("A Rank %s Riftbreak overran the defenders.") % tr(breach_rank_id()))
	_close_breach()
	save()
	state_changed.emit()
	return out


## Damages one working Guild Management building (a level lost until
## repaired). Returns its name, or "" if nothing is built.
func _damage_building() -> String:
	var working: Array = []
	for b in GameData.BRANCHES:
		for n in b["nodes"]:
			var key := "%s.%s" % [b["id"], n["id"]]
			if lvl(key) > 0:
				working.append([key, str(n["name"])])
	if working.is_empty():
		return ""
	var pick: Array = working[randi() % working.size()]
	damaged[pick[0]] = int(damaged.get(pick[0], 0)) + 1
	return tr(str(pick[1]))


func repair_cost(key: String) -> int:
	return GameData.BREACH_REPAIR_BASE + GameData.BREACH_REPAIR_STEP * int(upgrades.get(key, 0))


## Repairs one damaged level of a building. "" on success, else why not.
func repair_building(key: String) -> String:
	if int(damaged.get(key, 0)) <= 0:
		return tr("Nothing to repair.")
	var cost := repair_cost(key)
	if coins < cost:
		return tr("Not enough Gold.")
	coins -= cost
	damaged[key] = int(damaged[key]) - 1
	if int(damaged[key]) <= 0:
		damaged.erase(key)
	save()
	state_changed.emit()
	return ""
