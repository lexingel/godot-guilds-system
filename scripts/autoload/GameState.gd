extends Node
## Current save state + run state — mirrors defaultState()/save()/load() and
## the state-mutating action functions (recruitHero, learnSkill, equipItem,
## engageCombat, etc.) from guild-system.html. Vertical-slice simplification:
## every value gated behind the Guild Management upgrade tree in the HTML
## version (hero slot cap, relic slot cap, recovery time, shop/broker fees,
## hazard guard, detector drops, Optimal Synergy's unlock) is fixed at its
## base/always-on value here — that whole tree is explicitly deferred.

signal state_changed

const SAVE_PATH := "user://save.json"
const RELIC_MAX_LEVEL := 5
const STARTING_RELIC_CHOICES := 2

var guild_name: String = ""
var next_id: int = 1
var coins: int = 60
var crystals: int = 15
var tokens: int = 0
var heroes: Array[Hero] = []
var relics: Array[Relic] = []
var items: Array[Item] = []
var recruit_pool: Array[Hero] = []
var run: Dictionary = {}   # {} = no active run


func recovery_ms() -> int:
	return 120000


func hero_slot_cap() -> int:
	return 4


func relic_slot_cap() -> int:
	return 3


func reset() -> void:
	guild_name = ""
	next_id = 1
	coins = 60
	crystals = 15
	tokens = 0
	heroes = []
	relics = []
	items = []
	recruit_pool = []
	run = {}


func save() -> void:
	var data := {
		"guild_name": guild_name, "next_id": next_id, "coins": coins,
		"crystals": crystals, "tokens": tokens,
		"heroes": heroes.map(func(h): return h.to_dict()),
		"relics": relics.map(func(r): return r.to_dict()),
		"items": items.map(func(it): return it.to_dict()),
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
	return true


func find_hero(hero_id: String) -> Hero:
	for h in heroes:
		if h.id == hero_id:
			return h
	return null


func gen_recruit_offer() -> Hero:
	return Combat.gen_hero(Combat.weighted_rank(), 1)


func refresh_recruit_pool() -> void:
	recruit_pool = [gen_recruit_offer(), gen_recruit_offer(), gen_recruit_offer(), gen_recruit_offer()]


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
	heroes.append(offer)
	recruit_pool[idx] = gen_recruit_offer()
	if is_dupe:
		var refund := int(round(float(rank["cost"]) * 0.5))
		coins += refund
	save()
	state_changed.emit()
	return ""


func current_party() -> Array[Hero]:
	var out: Array[Hero] = []
	for id in run.get("hero_ids", []):
		var h := find_hero(id)
		if h:
			out.append(h)
	return out


func start_run(diff_id: String, hero_ids: Array[String], starting_relic: Relic) -> void:
	var shield := 0
	for r in Combat.equipped_relics():
		shield += r.hp
	if starting_relic:
		shield += starting_relic.hp
		starting_relic.id = "rl" + str(next_id)
		next_id += 1
		starting_relic.equipped = false
		relics.append(starting_relic)
	run = {
		"diff_id": diff_id, "floor": 0, "hero_ids": hero_ids, "shield": shield,
		"node_kind": "", "node_state": {}, "sealed": null,
	}
	roll_node_kind()
	save()
	state_changed.emit()


func _diff() -> Dictionary:
	for d in GameData.DIFFICULTIES:
		if d["id"] == run["diff_id"]:
			return d
	return GameData.DIFFICULTIES[0]


func roll_node_kind() -> void:
	var diff := _diff()
	var floor_i: int = run["floor"]
	if floor_i >= int(diff["floors"]) - 1:
		run["node_kind"] = "boss"
	else:
		var r := randf()
		if r < 0.6:
			run["node_kind"] = "combat"
		elif r < 0.8:
			run["node_kind"] = "shop"
		else:
			run["node_kind"] = "hazard"
	run["node_state"] = {}


func engage_node(ability_used: String) -> void:
	var diff := _diff()
	var party := current_party().filter(func(h): return not h.is_downed() and h.hp > 0)
	if party.is_empty():
		return
	var kind: String = run["node_kind"]
	var result := Combat.resolve_combat(party, kind, diff, run["floor"], ability_used)
	if result["won"]:
		coins += int(result["coin"])
		crystals += int(result["crystal"])
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
	var party := current_party().filter(func(h): return not h.is_downed() and h.hp > 0)
	ensure_hazard()
	var ns: Dictionary = run["node_state"]
	var hz: Dictionary = ns["hazard"]
	var log: Array[String] = []
	var dmg: float = (6.0 + int(diff["floors"]) * 2.0) * float(hz["dmg_mult"])
	var guard: float = min(0.9, Combat.party_skill_total(party, "hazard_guard_pct") + Combat.relic_special_total("hazard_guard_pct") + Combat.synergy_value_for("hazard_guard_pct"))
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
	var offers: Array = []
	for i in 3:
		var rarity := Combat.weighted_rarity()
		var loot := Combat.gen_loot(rarity)
		var rar := GameData.find_rarity(rarity)
		var price := max(4, int(round(10 + 15 * float(rar["mult"]))))
		loot["price"] = price
		loot["bought"] = false
		offers.append(loot)
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
	run["floor"] = int(run["floor"]) + 1
	roll_node_kind()
	save()
	state_changed.emit()


func seal_rift() -> void:
	var diff := _diff()
	tokens += int(diff["token_base"])
	run["sealed"] = {"tokens": int(diff["token_base"])}
	refresh_recruit_pool()
	save()
	state_changed.emit()


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
	return 20 + 10 * spent


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
	var h := find_hero(hero_id)
	if not h or h.trait_name == "":
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


func sell_relic(relic_id: String) -> void:
	for r in relics:
		if r.id == relic_id and not r.equipped:
			var rar := GameData.find_rarity(r.rarity)
			var sale := int(round(15.0 * float(rar["mult"]) * 0.85))
			coins += sale
			relics.erase(r)
			save()
			state_changed.emit()
			return


func sell_item(item_id: String) -> void:
	for it in items:
		if it.id == item_id and it.equipped_to == "":
			var rar := GameData.find_rarity(it.rarity)
			var sale := int(round(15.0 * float(rar["mult"]) * 0.85))
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
