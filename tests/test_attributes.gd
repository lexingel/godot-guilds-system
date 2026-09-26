extends "res://tests/base_test.gd"
## Attributes: level-up points, derived bonuses, requirements, migration, icons.

func run() -> void:
	seed(11)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	var h := Combat.gen_hero("D", 1)
	h.id = "h1"
	GameState.heroes.append(h)
	check(h.attrs.size() == 3 and h.attr_points == 0, "recruit has 3 attrs, no loose points %s" % [h.attrs])

	# Level-up: 3 points, 5% growth.
	var hp0 := h.base_hp
	h.level = 1
	h.xp = 0
	Combat.gain_xp(h, Combat.xp_to_next(1))
	check(h.level == 2 and h.attr_points == 3, "level-up grants 3 points (%d)" % h.attr_points)
	check(h.base_hp == int(round(hp0 * 1.05)), "base HP grows 5%% (%d -> %d)" % [hp0, h.base_hp])

	# Derived bonuses.
	var dmg0 := Combat.dmg_of(h)
	var m0 := Combat.hero_attr(h, "might")
	GameState.spend_attr_point("h1", "might")
	GameState.spend_attr_point("h1", "might")
	check(Combat.hero_attr(h, "might") == m0 + 2 and h.attr_points == 1, "spending raises Might and uses points")
	check(Combat.dmg_of(h) >= dmg0, "Might raises damage (%d -> %d)" % [dmg0, Combat.dmg_of(h)])
	check(is_equal_approx(Combat.attr_kind_total(h, "dmg_pct"), (m0 + 2 - GameData.ATTR_BASELINE) * 0.02), "dmg_pct from Might matches table")
	GameState.spend_attr_point("h1", "bogus")
	check(h.attr_points == 1, "unknown attribute is ignored")
	GameState.auto_assign_attrs("h1")
	check(h.attr_points == 0, "Auto spends the rest")

	# Requirement gating.
	var it := Combat.gen_item("legendary", "weapon")
	it.id = "i1"
	GameState.items.append(it)
	check(it.attr != "" and it.attr_req == GameData.ITEM_ATTR_REQ["legendary"], "legendary rolls attr %s req %d" % [it.attr, it.attr_req])
	h.attrs[it.attr] = it.attr_req - 1
	GameState.equip_item("h1", it.slot_type(), 0, "i1")
	check(it.equipped_to == "", "under-requirement equip refused")
	var common := Combat.gen_item("common", it.category)
	common.id = "i0"
	GameState.items.append(common)
	GameState.equip_item("h1", it.slot_type(), 0, "i0")
	GameState.equip_item("h1", it.slot_type(), 0, "i1")
	check(common.equipped_to == "h1", "refused equip leaves the slot's item in place")
	h.attrs[it.attr] = it.attr_req
	GameState.equip_item("h1", it.slot_type(), 0, "i1")
	check(it.equipped_to == "h1" and common.equipped_to == "", "meeting requirement equips and swaps")
	check(Combat.hero_attr(h, it.attr) == it.attr_req + it.attr_bonus, "item bonus counts toward the attribute")
	check(GameState.attr_req_met(it, h), "own bonus doesn't let an item prop itself up (still met at exact req)")
	h.attrs[it.attr] = it.attr_req - 1
	check(not GameState.attr_req_met(it, h), "own bonus excluded from its own requirement")

	# Ability power: debuffs get stronger, buffs get stronger.
	h.attrs["focus"] = GameData.ATTR_BASELINE + 10
	var ap := Combat.attr_kind_total(h, "ability_power")
	check(ap > 0.0, "Focus gives ability power (%.2f)" % ap)

	# Save round-trip.
	var d := h.to_dict()
	var back := Hero.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(Combat.hero_attr(back, "focus") == Combat.hero_attr(h, "focus") and back.attr_points == h.attr_points, "hero attrs survive save/load")
	var it_back := Item.from_dict(JSON.parse_string(JSON.stringify(it.to_dict())))
	check(it_back.attr == it.attr and it_back.attr_bonus == it.attr_bonus and it_back.attr_req == it.attr_req, "item attr survives save/load")

	# Old-save migration.
	var old := d.duplicate()
	old.erase("attrs")
	old.erase("attr_points")
	old["level"] = 6
	old["base_hp"] = 140
	old["base_dmg"] = 20
	old["is_champion"] = false
	var n0 := Hero.attrs_migrated
	var mig := Hero.from_dict(old)
	check(mig.attr_points == 15 and Hero.attrs_migrated == n0 + 1, "L6 legacy hero gets 15 points (%d)" % mig.attr_points)
	check(mig.base_hp == int(round(140 * 1.25 / 1.40)), "legacy HP rescaled 8%%->5%% growth (%d)" % mig.base_hp)
	old["is_champion"] = true
	check(Hero.from_dict(old).attr_points == 0, "legacy champion gets no loose points")
	var old_it := it.to_dict()
	old_it.erase("attr")
	old_it.erase("attr_bonus")
	old_it.erase("attr_req")
	var mi := Item.from_dict(old_it)
	check(mi.attr != "" and mi.attr_req == 0 and mi.attr_bonus > 0, "legacy item gets an attr, bonus %d, no requirement" % mi.attr_bonus)

	# Icons resolve for every base noun and legendary.
	var missing := []
	for u in GameData.UNIQUE_ITEMS:
		if not ResourceLoader.exists("res://assets/items/u_%s.png" % u["id"]):
			missing.append(u["id"])
	for s in 40:
		var g := Combat.gen_item(["common", "rare", "epic"][s % 3])
		if not GameData.item_icon(g).begins_with("res://assets/items/") or GameData.item_icon(g).contains("itemsA"):
			missing.append(g.name)
	check(missing.is_empty(), "every item has its own icon %s" % [missing])
