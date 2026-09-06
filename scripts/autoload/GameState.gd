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
var next_id: int = 1
var coins: int = 60
var crystals: int = 15
var tokens: int = 0
var heroes: Array[Hero] = []
var relics: Array[Relic] = []
var items: Array[Item] = []
var detectors: Array[Dictionary] = []   # [{"id":..., "tier": "lesser"|"greater"|"ascendant"}]
var recruit_pool: Array[Hero] = []
var upgrades: Dictionary = {}    # "branch.node" -> level int
var caps: Dictionary = {}        # "branch.node" -> bool
var current_champion: Hero = null
var best_endless_cycle: int = 0
var triage_used_this_cycle: bool = false
var pending_shop_boost: bool = false
var run: Dictionary = {}   # {} = no active run


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
	next_id = 1
	coins = 60
	crystals = 15
	tokens = 0
	heroes = []
	relics = []
	items = []
	detectors = []
	recruit_pool = []
	upgrades = {}
	caps = {}
	current_champion = null
	best_endless_cycle = 0
	triage_used_this_cycle = false
	pending_shop_boost = false
	run = {}


func save() -> void:
	var data := {
		"guild_name": guild_name, "next_id": next_id, "coins": coins,
		"crystals": crystals, "tokens": tokens,
		"heroes": heroes.map(func(h): return h.to_dict()),
		"relics": relics.map(func(r): return r.to_dict()),
		"items": items.map(func(it): return it.to_dict()),
		"detectors": detectors,
		"upgrades": upgrades, "caps": caps,
		"current_champion": current_champion.to_dict() if current_champion else null,
		"best_endless_cycle": best_endless_cycle,
		"triage_used_this_cycle": triage_used_this_cycle,
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
	next_id = data.get("next_id", 1)
	coins = data.get("coins", 60)
	crystals = data.get("crystals", 15)
	tokens = data.get("tokens", 0)
	heroes.assign(data.get("heroes", []).map(func(d): return Hero.from_dict(d)))
	relics.assign(data.get("relics", []).map(func(d): return Relic.from_dict(d)))
	items.assign(data.get("items", []).map(func(d): return Item.from_dict(d)))
	detectors.assign(data.get("detectors", []))
	upgrades = data.get("upgrades", {})
	caps = data.get("caps", {})
	var champ_data = data.get("current_champion")
	current_champion = Hero.from_dict(champ_data) if champ_data != null else null
	best_endless_cycle = data.get("best_endless_cycle", 0)
	triage_used_this_cycle = data.get("triage_used_this_cycle", false)
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


func start_run(diff_id: String, hero_ids: Array[String], starting_relic: Relic, hardcore: bool, endless: bool) -> void:
	var shield := 0
	for r in Combat.equipped_relics():
		shield += r.hp
	if starting_relic:
		shield += starting_relic.hp
		starting_relic.id = "rl" + str(next_id)
		next_id += 1
		starting_relic.equipped = false
		relics.append(starting_relic)
	var diff := Combat.endless_diff_for_cycle(0) if endless else GameData.DIFFICULTIES[0]
	run = {
		"diff_id": diff_id, "endless": endless, "cycle": 0, "hardcore": hardcore,
		"layers": Combat.build_layers(diff), "pos": 0, "chosen": {},
		"hero_ids": hero_ids, "shield": shield, "boss_rounds": 0,
		"node_kind": "", "node_state": {}, "sealed": null, "anchor_used": false,
	}
	ensure_champion()
	auto_resolve_single_option()
	save()
	state_changed.emit()


func _diff() -> Dictionary:
	if run.get("endless", false):
		return Combat.endless_diff_for_cycle(int(run.get("cycle", 0)))
	for d in GameData.DIFFICULTIES:
		if d["id"] == run["diff_id"]:
			return d
	return GameData.DIFFICULTIES[0]


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


func engage_node(ability_used: String) -> void:
	var diff := _diff()
	var party: Array[Hero] = []
	party.assign(current_party().filter(func(h): return not h.is_downed() and h.hp > 0))
	if party.is_empty():
		return
	var kind := current_node_kind()
	var hardcore: bool = run.get("hardcore", false)
	var result := Combat.resolve_combat(party, kind, diff, int(run["pos"]), ability_used, hardcore)
	if result["won"]:
		coins += int(result["coin"])
		crystals += int(result["crystal"]) + int(result["bonus_crystal"])
		if kind == "boss":
			run["boss_rounds"] = int(result["rounds"])
	elif hardcore:
		for h in party:
			heroes.erase(h)
	run["node_state"] = {"type": "combat", "result": result, "reward_chosen": false}
	save()
	state_changed.emit()


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
	var hz: Dictionary = GameData.HAZARD_TYPES[randi() % GameData.HAZARD_TYPES.size()]
	ns["hazard"] = hz
	ns["resolved"] = false
	run["node_state"] = ns


func push_through_hazard() -> void:
	var diff := _diff()
	var party: Array[Hero] = []
	party.assign(current_party().filter(func(h): return not h.is_downed() and h.hp > 0))
	ensure_hazard()
	var ns: Dictionary = run["node_state"]
	var hz: Dictionary = ns["hazard"]
	var log: Array[String] = []
	var dmg: float = (6.0 + int(diff["floors"]) * 2.0) * float(hz["dmg_mult"])
	if not run.get("anchor_used", false) and anchor_artifact():
		run["anchor_used"] = true
		log.append("The Anchor Artifact snuffs the hazard before it strikes.")
		dmg = 0.0
	else:
		var guard: float = min(0.9, hazard_severity_reduction() + Combat.party_skill_total(party, "hazard_guard_pct") + Combat.relic_special_total("hazard_guard_pct") + Combat.synergy_value_for("hazard_guard_pct"))
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
	if randf() < float(hz["bonus_chance"]):
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


func advance_node() -> void:
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


func assign_to_bed(hero_id: String) -> void:
	var h := find_hero(hero_id)
	if not h or not h.is_downed() or h.bedded:
		return
	if occupied_beds() >= medical_bed_cap():
		return
	var remaining := h.downed_until - int(Time.get_unix_time_from_system() * 1000)
	h.downed_until = int(Time.get_unix_time_from_system() * 1000) + int(round(remaining * 0.4))
	h.bedded = true
	save()
	state_changed.emit()


func occupied_beds() -> int:
	var n := 0
	for h in heroes:
		if h.bedded and h.is_downed():
			n += 1
	return n


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


func retreat_now() -> void:
	run = {}
	save()
	state_changed.emit()


func finish_run() -> void:
	run = {}
	save()
	state_changed.emit()


func learn_skill(hero_id: String, skill_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	var n := GameData.find_skill_node(h.cls_id, skill_id)
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
		elif next_lvl >= 3:
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
