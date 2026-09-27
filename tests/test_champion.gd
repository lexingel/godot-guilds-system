extends "res://tests/base_test.gd"
## Champions for hire: offers, hiring, the Boon while standing, the Call.

func run() -> void:
	seed(31)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	GameState.coins = 5000
	var ids: Array[String] = []
	for r in ["D", "C"]:
		var h := Combat.gen_hero(r, 6)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	GameState.ensure_champion_offers()
	check(GameState.champion_offers.size() == GameData.CHAMPION_OFFER_COUNT, "3 offers")
	check(GameState.champion_offers.all(func(c): return c.level == 6), "offers are as experienced as your best hero")
	GameState.reroll_champion()
	check(GameState.champion_offers.size() == 3 and GameState.coins == 5000 - GameData.CHAMPION_REROLL_COST, "new offers cost %d" % GameData.CHAMPION_REROLL_COST)

	# Hiring.
	var offer: Hero = GameState.champion_offers[0]
	var cost := GameState.champion_hire_cost(offer)
	var gold0 := GameState.coins
	check(GameState.hire_champion(0) == "", "hire a champion")
	var c: Hero = GameState.heroes.back()
	check(c == offer and c.is_champion and GameState.coins == gold0 - cost, "they join the roster for %d Gold" % cost)
	check(GameState.champion_offers.size() == 2 and c.skill_points >= c.level - 1, "the offer is used up; they have their Skill Points")
	ids.append(c.id)

	# Boon only during a run, only while standing.
	var b: Dictionary = GameData.CHAMPION_BOONS[GameState.champion_role(c)]
	var h0: Hero = GameState.find_hero(ids[0])
	check(GameState.champion_boon(str(b["kind"])) == 0.0, "no boon outside a run")
	GameState.start_run("lesser", ids, null, false)
	check(GameState.champion_boon(str(b["kind"])) > 0.0, "boon %s active in a run" % b["kind"])
	check(Combat.hero_skill_sources(h0, str(b["kind"])).any(func(p): return p[0] == "Champion Boon"), "boon shows in the stat breakdown")
	c.hp = 0
	check(GameState.champion_boon(str(b["kind"])) == 0.0, "boon stops when the champion falls")
	c.hp = Combat.max_hp(c)

	# Call: once per rift, only a champion.
	check(GameState.champion_call_ready(c) and not GameState.champion_call_ready(h0), "call ready for the champion only")
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
	var back: Hero = GameState.find_hero(c.id)
	check(back != null and back.is_champion, "a hired champion stays a champion after a reload")
