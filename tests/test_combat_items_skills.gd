extends "res://tests/base_test.gd"
## Row swap and tonics, reforge/salvage/attunement, rift skill nodes, fork discount.

func run() -> void:
	seed(99)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	GameState.coins = 1000
	GameState.crystals = 500
	var ids: Array[String] = []
	for r in ["C", "C", "D"]:
		var h := Combat.gen_hero(r, 8)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)

	# ---- Tonics
	for i in 7:
		GameState.buy_tonic(["healing", "iron", "focus"][i % 3])
	check(GameState.tonic_count() == GameData.TONIC_CAP and GameState.tonic_count("healing") == 2 and GameState.tonic_count("focus") == 1, "one belt of %d across kinds" % GameData.TONIC_CAP)
	var t2 := Hero.from_dict(GameState.heroes[0].to_dict())
	GameState.save()
	GameState.load_save()
	check(GameState.tonic_count() == GameData.TONIC_CAP and GameState.tonic_count("iron") == 2, "tonics saved")

	# ---- Swap + tonic in a fight
	GameState.start_run("lesser", ids, null)
	GameState.run["node_state"] = {}
	GameState.choose_node_type("combat")
	GameState.engage_node()
	var state: Dictionary = GameState.run["node_state"]["combat_state"]
	var swapped := false
	var tonic_ok := false
	for step in 40:
		if GameState.run["node_state"].has("result"):
			break
		var nxt := Combat.peek_next_turn(state)
		if str(nxt["type"]) == "hero":
			var h := GameState.find_hero(str(nxt["id"]))
			if h and not swapped:
				var f0 := h.formation
				GameState.set_hero_action(h.id, "swap")
				GameState.resolve_turn_now()
				swapped = h.formation != f0
				continue
			if h and not tonic_ok:
				var patient: Hero = GameState.find_hero(ids[1])
				patient.hp = max(1, patient.hp - 20)
				var hp0 := patient.hp
				var t0 := GameState.tonic_count("healing")
				GameState.set_hero_action(h.id, "tonic:healing", 0, patient.id)
				GameState.resolve_turn_now()
				tonic_ok = GameState.tonic_count("healing") == t0 - 1 and patient.hp > hp0
				continue
		GameState.resolve_turn_now()
	check(swapped, "swap action changes row")
	check(tonic_ok, "tonic heals the chosen ally and is used up")

	# ---- Reforge / salvage / attune
	var it := Combat.gen_item("epic", "weapon")
	GameState.items.append(it)
	var k1 := it.secondary_kind
	var cr0 := GameState.crystals
	var cost := GameState.reforge_cost(it)
	check(GameState.reforge_item(it.id, 1) == "" and GameState.crystals == cr0 - cost and it.reforges == 1, "reforge spends %d crystals" % cost)
	check(it.secondary_kind != it.kind and it.secondary_kind != it.tertiary_kind, "rerolled line stays distinct (%s, was %s)" % [it.secondary_kind, k1])
	check(it.name.contains(" of "), "name keeps a suffix: %s" % it.name)
	check(GameState.reforge_cost(it) > cost, "second reforge costs more")
	check(GameState.reforge_item(it.id, 0) == "" and it.kind != "", "primary value rerolls")
	var uni := Combat.gen_unique_item()
	GameState.items.append(uni)
	check(GameState.reforge_item(uni.id, 0) != "", "legendaries can't be reforged")
	var h0: Hero = GameState.find_hero(ids[0])
	h0.attrs[it.attr] = 30
	GameState.equip_item(h0.id, "weapon", 0, it.id)
	var v0 := it.value
	for w in GameData.ATTUNE_WINS:
		GameState._attune_gear([h0])
	check(it.attune_level == 1 and absf(it.value - v0 * (1.0 + GameData.ATTUNE_STEP)) < 0.002, "8 wins attune once (+4%%)")
	var back := Item.from_dict(JSON.parse_string(JSON.stringify(it.to_dict())))
	check(back.attune_level == 1 and back.attune_wins == it.attune_wins and back.reforges == it.reforges, "item upkeep fields saved")
	var junk := Combat.gen_item("rare")
	GameState.items.append(junk)
	GameState.salvage_item(junk.id)
	check(GameState.items.has(junk), "salvage locked without Recycling")
	GameState.upgrades["res.lab"] = 1
	if GameState.recycle_unlocked():
		cr0 = GameState.crystals
		GameState.salvage_item(junk.id)
		check(not GameState.items.has(junk) and GameState.crystals > cr0, "salvage gives crystals")

	# ---- Rift nodes
	var h1: Hero = GameState.find_hero(ids[1])
	h1.level = 10
	h1.skill_points = 20
	var kind := h1.innate_kind
	check(GameState.learn_skill(h1.id, kind, "riftborn").begins_with("Seal a Rank"), "riftborn needs a Rank C+ seal")
	GameState.best_rift_rank_sealed = GameData.rift_rank_index("C")
	check(GameState.learn_skill(h1.id, kind, "riftborn") == "", "riftborn learnable after a C seal")
	var tot := Combat.hero_skill_total(h1, kind)
	check(tot > 0.0, "riftborn adds %s" % kind)
	for id in ["edge", "hide"]:
		GameState.learn_skill(h1.id, kind, id)
	var t2n: Array = GameData.KIND_SKILL_PACKAGE[kind].filter(func(n): return int(n["tier"]) == 2)
	for n in t2n:
		GameState.learn_skill(h1.id, kind, str(n["id"]))
	GameState.learn_skill(h1.id, kind, "cap")
	GameState.crystals = 0
	check(GameState.learn_skill(h1.id, kind, "stonebound") == "Needs %d Essence" % GameData.STONEBOUND_CRYSTALS, "stonebound needs Essence")
	GameState.crystals = GameData.STONEBOUND_CRYSTALS
	var ap0 := Combat.hero_skill_total(h1, "ability_power")
	check(GameState.learn_skill(h1.id, kind, "stonebound") == "" and GameState.crystals == 0, "stonebound spends the Essence")
	check(Combat.hero_skill_total(h1, "ability_power") > ap0, "stonebound adds ability power")

	# ---- Fork discount + consistent refund
	var h2: Hero = GameState.find_hero(ids[2])
	h2.level = 10
	h2.skill_points = 30
	var cap_node: Dictionary = GameData.find_skill_node(h2.innate_kind, "cap")
	h2.quirks.clear()
	for t in GameData.quirks_from("born"):
		if float(GameData.QUIRKS[t].get("stats", {}).get(str(cap_node["kind"]), 0.0)) > 0.0:
			h2.quirks.assign([t])
			break
	if not h2.quirks.is_empty():
		check(GameState.skill_node_cost(h2, h2.innate_kind, cap_node) == int(cap_node["cost"]) - 1, "quirk %s discounts the %s fork" % [h2.quirks[0], cap_node["kind"]])
	else:
		print("   (no trait boosts %s; discount check skipped)" % cap_node["kind"])
	var sp0 := h2.skill_points
	for id in ["edge", "hide"]:
		GameState.learn_skill(h2.id, h2.innate_kind, id)
	for n in GameData.KIND_SKILL_PACKAGE[h2.innate_kind].filter(func(n): return int(n["tier"]) == 2):
		GameState.learn_skill(h2.id, h2.innate_kind, str(n["id"]))
	GameState.learn_skill(h2.id, h2.innate_kind, "cap")
	GameState.coins = 100000
	GameState.respec_hero(h2.id)
	check(h2.skill_points == sp0, "full respec refunds exactly what was paid (%d vs %d)" % [h2.skill_points, sp0])
