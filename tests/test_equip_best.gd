extends "res://tests/base_test.gd"
## "Equip best": fills a hero's slots with the strongest free gear that fits,
## upgrades over weaker worn gear, and never takes another hero's items.


func run() -> void:
	GameState.reset()
	var h := Combat.gen_hero("A", 10)
	h.id = "h1"
	var other := Combat.gen_hero("A", 10)
	other.id = "h2"
	other.cls_id = h.cls_id
	other.pool_id = h.pool_id
	GameState.heroes.append(h)
	GameState.heroes.append(other)
	var n := 0
	for r in ["common", "rare", "epic", "legendary", "common", "rare", "epic", "legendary"]:
		for cat in ["weapon", "armor"]:
			var it := Combat.gen_item(r, cat)
			it.id = "i%d" % n
			n += 1
			it.attr_req = 0
			it.locked_role = ""
			it.locked_subclasses.clear()
			GameState.items.append(it)
	# The other hero wears the single best weapon.
	var weapons: Array = GameState.items.filter(func(it): return it.slot_type() == "weapon")
	weapons.sort_custom(func(a, b): return GameState.gear_score(a) > GameState.gear_score(b))
	var taken: Item = weapons[0]
	taken.equipped_to = "h2"
	taken.equipped_idx = 0

	check(GameState.equip_best_changes(h) > 0, "a bare hero has gear to equip")
	var before := Combat.power_of(h)
	GameState.equip_best("h1")
	var worn: Array = GameState.items.filter(func(it): return it.equipped_to == "h1")
	var wcap := GameData.weapon_slots(h.pool_id)
	var gcap := GameData.gear_slots(h.rank)
	check(worn.filter(func(it): return it.slot_type() == "weapon").size() == wcap, "every weapon slot filled (%d)" % wcap)
	check(worn.filter(func(it): return it.slot_type() == "gear").size() == gcap, "every gear slot filled (%d)" % gcap)
	check(taken.equipped_to == "h2", "another hero's gear is left alone")
	check(Combat.power_of(h) >= before, "power doesn't drop")
	var idxs := {}
	for it in worn:
		idxs["%s%d" % [it.slot_type(), it.equipped_idx]] = true
	check(idxs.size() == worn.size(), "no two items share a slot")
	check(weapons[1].equipped_to == "h1", "the best free weapon is picked")
	check(GameState.equip_best_changes(h) == 0, "nothing left to improve")

	# A stronger drop replaces the weakest worn piece.
	var best_now: float = worn.map(func(it): return GameState.gear_score(it)).max()
	var drop := Combat.gen_item("legendary", "armor")
	drop.id = "i_new"
	drop.attr_req = 0
	drop.locked_role = ""
	drop.locked_subclasses.clear()
	drop.kind = "dmg_pct"
	drop.value = best_now + 1.0
	GameState.items.append(drop)
	check(GameState.equip_best_changes(h) == 1, "one upgrade offered")
	GameState.equip_best("h1")
	check(drop.equipped_to == "h1", "the upgrade goes on")
