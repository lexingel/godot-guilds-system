extends "res://tests/base_test.gd"
## Guild Management: the rebuilt tree, its perks, and the old-save refund.


func run() -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"

	# Old-save refund: every Crystal spent on the old tree comes back.
	var old := {"save_version": 2, "crystals": 10, "upgrades": {"ops.roster": 5, "res.vault": 2}, "caps": {"ops.roster": true}}
	var migrated := GameState._migrate_save(old)
	check(int(migrated["crystals"]) == 10 + 350 + 140 + 400 and migrated["upgrades"].is_empty() and migrated["caps"].is_empty(), "old tree refunded (%d)" % int(migrated["crystals"]))
	check(int(migrated["save_version"]) == GameState.SAVE_VERSION and int(migrated["_mgmt_refund"]) == 890, "refund noted for the toast")

	# Tree shape and costs.
	var nodes := 0
	for b in GameData.BRANCHES:
		for n in b["nodes"]:
			nodes += 1
			check(GameData.MANAGEMENT_NODE_ICON.has("%s.%s" % [b["id"], n["id"]]), "icon for %s" % n["id"])
			check(Combat.describe_node_effect(n["id"], 3) != "", "description for %s" % n["id"])
	check(nodes == 9, "9 upgrades")
	GameState.crystals = 10000
	for i in 6:
		GameState.upgrade_node("ops.barracks")
	check(GameState.lvl("ops.barracks") == 5 and GameState.crystals == 10000 - 750, "5 levels cost 750, no 6th")

	# Operations.
	check(GameState.hero_slot_cap() == 14 and GameState.guild_mentor() and GameState.xp_mult() > 1.0, "Barracks: slots, mentor, XP")
	var h := Combat.gen_hero("C", 3)
	var hp0 := Combat.max_hp(h)
	GameState.upgrades["ops.drill"] = 5
	check(Combat.max_hp(h) > hp0 and GameState.vanguard() and GameState.abilities_ready_each_fight(), "Drill Yard: HP, Vanguard, abilities ready")
	h.ability_cooldown = 3
	var party: Array[Hero] = [h]
	Combat.start_combat(party, "combat", GameData.DIFFICULTIES[0], 1)
	check(h.ability_cooldown == 0, "Drill Yard Lv5 readies abilities at fight start")
	var xp0 := h.xp
	Combat.gain_xp(h, 10)
	check(h.xp - xp0 == 12 or h.level > 3, "Barracks Lv5: +20% XP")
	GameState.upgrades["ops.infirmary"] = 5
	check(GameState.field_triage_available() and GameState.full_heal_between_runs() and GameState.medical_bed_cap() == 4, "Infirmary perks")

	# Infrastructure.
	GameState.upgrades["infra.amplifiers"] = 5
	GameState.upgrades["infra.wardstones"] = 5
	check(is_equal_approx(GameState.crystal_yield_bonus(), 1.4) and GameState.energy_extract_chance() > 0.0 and GameState.crystal_resonance(), "Amplifiers perks")
	check(GameState.anchor_artifact() and GameState.hazards_nonlethal() and is_equal_approx(GameState.seal_bonus_mult(), 1.5), "Wardstones perks")

	# Logistics.
	GameState.upgrades["log.scouts"] = 5
	GameState.refresh_recruit_pool()
	check(GameState.recruit_pool.size() == 6 and GameState.headhunter_guarantee() and GameState.recruit_reroll_cost() == GameData.RECRUIT_REROLL_COST / 2, "Scouts' Lodge perks")
	check(GameState.recruit_pool.any(func(x): return GameData.rank_index(x.rank) >= GameData.rank_index("C")), "Headhunter: a C+ offer")
	GameState.upgrades["log.trade"] = 5
	check(GameState.black_market_unlocked() and GameState.shop_guaranteed_epic() and is_equal_approx(GameState.merchant_price_reduction(), 0.3), "Trade Network perks")

	# Research.
	var r := Combat.gen_relic("epic")
	r.level = 2
	var c0 := GameState.relic_upgrade_cost(r)
	GameState.upgrades["res.vault"] = 5
	GameState.upgrades["res.lab"] = 5
	check(GameState.relic_slot_cap() == 5 and GameState.relic_choice_count() == 4 and GameState.inherited_power(), "Relic Vault perks")
	check(GameState.relic_upgrade_cost(r) < c0 and GameState.quirk_treat_cost() == 21 and GameState.recycle_unlocked() and is_equal_approx(GameState.set_bonus_mult(), 1.5), "Arcane Lab perks")

	# A boss win with Resonance pays a Crystal cache.
	var champ := Combat.gen_hero("S", 10)
	champ.hp = Combat.max_hp(champ)
	var bp: Array[Hero] = [champ]
	var st := Combat.start_combat(bp, "boss", GameData.DIFFICULTIES[0], 1)
	for m in st["monsters"]:
		m["hp"] = 1.0
	var res := {}
	for t in 60:
		var out := Combat.resolve_turn(st)
		if out["done"]:
			res = out["result"]
			break
	check(bool(res.get("won", false)) and int(res.get("crystal_cache", 0)) > 0 and int(res.get("guild_crystal", 0)) >= 0, "Resonance: boss Crystal cache")

	_orders()


func _orders() -> void:
	GameState.reset()
	GameState.guild_name = "T"
	check(GameState.orders_per_rift() == 0, "no orders without Lv2 nodes")
	GameState.upgrades = {"ops.infirmary": 2, "ops.drill": 2, "log.trade": 2, "log.scouts": 2}
	check(GameState.orders_unlocked().size() == 4 and GameState.orders_per_rift() == 1, "four orders unlocked, 1 per rift")
	GameState.upgrades["ops.barracks"] = 5
	GameState.upgrades["res.vault"] = 5
	GameState.upgrades["res.lab"] = 5
	GameState.upgrades["infra.amplifiers"] = 5
	check(GameState.orders_per_rift() == 2, "Renowned tier: 2 orders")
	var ids: Array[String] = []
	for i in 3:
		var h := Combat.gen_hero("C", 8)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	GameState.runs_started = 3
	GameState.start_run("lesser", ids, null, false)
	check(GameState.order_blocker("rally") != "" and GameState.order_blocker("requisition") != "", "rally/requisition need their moment")
	# Supply Drop heals.
	var h0 := GameState.find_hero(ids[0])
	h0.hp = 1
	check(GameState.use_order("supply") == "" and h0.hp > 1, "Supply Drop heals")
	check(GameState.orders_left() == 1, "one order spent")
	# Rally in a fight: heroes first for the rest of the round.
	GameState.engage_node()
	var st: Dictionary = GameState.run["node_state"]["combat_state"]
	var mult0 := float(st["_attack_mult"])
	check(GameState.use_order("rally") == "", "Rally in a fight")
	var idx := int(st["turn_idx"])
	var rest: Array = (st["turn_order"] as Array).slice(idx)
	var first_monster := rest.find(rest.filter(func(t): return t["type"] != "hero")[0]) if rest.any(func(t): return t["type"] != "hero") else rest.size()
	check(rest.slice(0, first_monster).all(func(t): return t["type"] == "hero") and rest.slice(first_monster).all(func(t): return t["type"] != "hero"), "Rally: heroes act first")
	check(float(st["_attack_mult"]) > mult0 and GameState.orders_left() == 0, "Rally: +damage, orders spent")
	check(GameState.order_blocker("supply") != "", "no orders left")
	GameState.save()
	GameState.load_save()
	check(int(GameState.run.get("orders_used", 0)) == 2, "orders used survive a reload")
	GameState.finish_run()
	# Scout Ahead rerolls a fork; Requisition rerolls loot.
	GameState.start_run("lesser", ids, null, false)
	GameState.run["pos"] = 1
	GameState.run["chosen"] = {}
	var before: Array = (GameState.current_layer_options() as Array).duplicate()
	check(GameState.use_order("scout") == "" and GameState.current_layer_options() != before and GameState.current_layer_options().size() == 2, "Scout Ahead rerolls the fork")
	GameState.run["node_state"] = {"type": "combat", "result": {"won": true, "reward_options": [Combat.gen_loot("common"), Combat.gen_loot("common")]}, "reward_chosen": false}
	var o0: Array = GameState.run["node_state"]["result"]["reward_options"]
	check(GameState.use_order("requisition") == "" and GameState.run["node_state"]["result"]["reward_options"] != o0, "Requisition rerolls loot")
	GameState.finish_run()
	_camp_props()


func _camp_props() -> void:
	GameState.reset()
	for b in GameData.HAMLET_BUILDINGS:
		if str(b.get("node", "")) != "":
			check(not GameData.find_branch_node(str(b["node"])).is_empty(), "%s tied to a real upgrade" % b["id"])
		for lv in [0, 3, 5]:
			if str(b.get("node", "")) != "":
				GameState.upgrades[str(b["node"])] = lv
			check(ResourceLoader.exists(GameState.hamlet_texture(b)), "hamlet art %s" % GameState.hamlet_texture(b))
	var barracks: Dictionary = GameData.HAMLET_BUILDINGS.filter(func(x): return x["id"] == "barracks")[0]
	GameState.upgrades["ops.barracks"] = 2
	check(GameState.hamlet_tier(barracks) == 1, "Barracks tier 1 below Lv3")
	GameState.upgrades["ops.barracks"] = 4
	check(GameState.hamlet_tier(barracks) == 2, "Barracks tier 2 at Lv3-4")
	GameState.upgrades["ops.barracks"] = 5
	check(GameState.hamlet_tier(barracks) == 3, "Barracks tier 3 at Lv5")
	GameState.campaign_act = 3
	check(GameState.hamlet_tier(GameData.HAMLET_BUILDINGS.filter(func(x): return x["id"] == "gate")[0]) == 3, "Rift Gate follows the act")
