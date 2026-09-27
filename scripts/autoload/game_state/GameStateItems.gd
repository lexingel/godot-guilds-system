extends "res://scripts/autoload/game_state/GameStateHeroes.gd"
## GameState, part 3: gear and relics — equipping, crafting, reforging, selling, supplies.


func buy_incense(incense_id: String) -> String:
	var def := GameData.find_incense(incense_id)
	if def.is_empty():
		return ""
	var cost := int(def["cost"])
	if coins < cost:
		return "Not enough Gold"
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
		return "Not enough Gold"
	coins -= GameData.TONIC_COST
	tonics += 1
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
		if h.hp <= 0:
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
		return "Not enough Essence"
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


## Every flat kind->value an item contributes (what Combat.hero_item_total
## sums for it).
func item_stat_map(it: Item) -> Dictionary:
	var m := {}
	if it == null:
		return m
	for pair in [[it.kind, it.value], [it.secondary_kind, it.secondary_value], [it.tertiary_kind, it.tertiary_value],
			[it.implicit_kind, it.implicit_value], [it.drawback_kind, it.drawback_value]]:
		if str(pair[0]) != "":
			m[pair[0]] = float(m.get(pair[0], 0.0)) + float(pair[1])
	return m


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


func equip_item(hero_id: String, slot_type: String, idx: int, item_id: String) -> void:
	var h := find_hero(hero_id)
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
			return "Not enough Essence"
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
			return "Not enough Essence"
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
