extends "res://tests/base_test.gd"
## Champion draft, scaling, Boon, Call, oath and swear-in.

func run() -> void:
	seed(31)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	GameState.coins = 1000
	var ids: Array[String] = []
	for r in ["D", "C"]:
		var h := Combat.gen_hero(r, 6)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	var c := GameState.ensure_champion()
	check(c.level == 6, "champion levels to the strongest hero (Lv%d)" % c.level)
	check(c.attr_points == 0, "champion's points auto-spent")
	check(GameState.champion_offers.size() == GameData.CHAMPION_OFFER_COUNT, "3 offers")

	# Gear release on swap.
	var it := Combat.gen_item("common", "weapon")
	GameState.items.append(it)
	GameState.equip_item(c.id, "weapon", 0, it.id)
	var eq_ok := it.equipped_to == c.id
	var old_id := c.id
	GameState.choose_champion(1)
	check(eq_ok and it.equipped_to == "" and GameState.current_champion.id != old_id, "swapping returns the old champion's gear")
	check(GameState.champion_offers.is_empty() and GameState.current_champion.level == 6, "chosen champion synced, offers used up")
	GameState.reroll_champion()
	check(GameState.champion_offers.size() == 3 and GameState.coins == 1000 - GameData.CHAMPION_REROLL_COST, "new offers cost %d" % GameData.CHAMPION_REROLL_COST)

	# Boon only during a run, only while standing.
	c = GameState.current_champion
	var b: Dictionary = GameData.CHAMPION_BOONS[GameState.champion_role(c)]
	var h0: Hero = GameState.find_hero(ids[0])
	check(GameState.champion_boon(str(b["kind"])) == 0.0, "no boon outside a run")
	GameState.start_run("lesser", ids, null, false, false)
	check(GameState.champion_boon(str(b["kind"])) > 0.0, "boon %s active in a run" % b["kind"])
	var src := Combat.hero_skill_sources(h0, str(b["kind"])).any(func(p): return p[0] == "Champion Boon")
	check(src, "boon shows in the stat breakdown")
	c.hp = 0
	check(GameState.champion_boon(str(b["kind"])) == 0.0, "boon stops when the champion falls")
	c.hp = Combat.max_hp(c)

	# Call: once per rift, only the champion.
	check(GameState.champion_call_ready(c) and not GameState.champion_call_ready(h0), "call ready for champion only")
	GameState.run["node_state"] = {}
	GameState.choose_node_type("combat")
	GameState.engage_node()
	var state: Dictionary = GameState.run["node_state"]["combat_state"]
	var used := false
	for step in 30:
		if GameState.run["node_state"].has("result"):
			break
		var nxt := Combat.peek_next_turn(state)
		if str(nxt["type"]) == "hero" and str(nxt["id"]) == c.id and not used:
			var log0 := (state["log"] as Array).size()
			GameState.set_hero_action(c.id, "call")
			GameState.resolve_turn_now()
			var call_name := str(GameState.champion_call(c)["name"])
			used = (state["log"] as Array).slice(log0).any(func(l): return str(l).contains(call_name))
			continue
		GameState.resolve_turn_now()
	check(used and GameState.run.get("champion_call_used", false), "call fires and is spent")
	check(not GameState.champion_call_ready(c), "call not ready again this rift")
	GameState.save()
	GameState.load_save()
	check(bool(GameState.run.get("champion_call_used", false)), "spent call survives a reload")
	c = GameState.current_champion
	check(GameState.champion_offers.size() == 3 and c.level == 6, "champion + offers saved")

	# Oath: 3 seals standing, then swear in.
	GameState.run = {}
	for i in 3:
		GameState.start_run("lesser", ids, null, false, false)
		c.hp = Combat.max_hp(c)
		GameState.seal_rift()
		GameState.finish_run() if GameState.has_method("finish_run") else null
		GameState.run = {}
	check(c.oath == 3 and GameState.current_champion == c, "champion stays across seals, oath 3 (%d)" % c.oath)
	check(GameState.champion_can_swear(), "ready to swear in")
	var n_heroes := GameState.heroes.size()
	check(GameState.swear_in_champion() == "", "swear in")
	check(GameState.heroes.size() == n_heroes + 1 and not c.is_champion and c.name.contains(" the ") and c.skill_points >= c.level - 1, "sworn champion is a roster hero: %s, SP %d" % [c.name, c.skill_points])
	check(GameState.current_champion != null and GameState.current_champion != c, "a new champion steps up")
