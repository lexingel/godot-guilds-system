extends "res://tests/base_test.gd"
## Rift nodes survive a reload and can't be re-rolled or re-paid.

func _reload() -> void:
	GameState.save()
	GameState.load_save()


func run() -> void:
	seed(77)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	GameState.coins = 500
	var ids: Array[String] = []
	for r in ["C", "C", "D"]:
		var h := Combat.gen_hero(r, 8)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	GameState.start_run("lesser", ids, null, false)

	# Shop: offers survive, bought flags survive.
	GameState.run["node_state"] = {}
	GameState.choose_node_type("shop")
	GameState.ensure_shop_offers()
	var names: Array = GameState.run["node_state"]["offers"].map(func(o): return o["obj"].name)
	GameState.buy_shop_offer(0)
	var n_items := GameState.items.size() + GameState.relics.size()
	_reload()
	var ns: Dictionary = GameState.run["node_state"]
	check(ns.get("type") == "shop" and ns["offers"].map(func(o): return o["obj"].name) == names, "shop offers identical after reload")
	GameState.buy_shop_offer(0)
	check(GameState.items.size() + GameState.relics.size() == n_items, "bought offer can't be bought again after reload")

	# Treasure: picked once stays picked.
	GameState.run["node_state"] = {}
	GameState.choose_node_type("treasure")
	GameState.ensure_treasure()
	GameState.pick_treasure(0)
	n_items = GameState.items.size() + GameState.relics.size()
	_reload()
	GameState.ensure_treasure()
	GameState.pick_treasure(1)
	check(GameState.items.size() + GameState.relics.size() == n_items, "treasure can't be picked twice across a reload")

	# Event: same event after reload, resolved stays resolved.
	GameState.run["node_state"] = {}
	GameState.choose_node_type("event")
	GameState.ensure_event()
	var ev_id := str(GameState.run["node_state"]["event"]["id"])
	_reload()
	GameState.ensure_event()
	check(str(GameState.run["node_state"]["event"]["id"]) == ev_id, "same event after reload")
	GameState.resolve_event(0)
	var c0 := GameState.coins
	_reload()
	GameState.resolve_event(0)
	check(GameState.run["node_state"].get("resolved", false) and GameState.coins == c0, "resolved event stays resolved")

	# Campfire.
	GameState.run["node_state"] = {}
	GameState.choose_node_type("campfire")
	GameState.campfire_choose("train")
	var xp := GameState.heroes[0].xp
	_reload()
	GameState.campfire_choose("train")
	check(GameState.find_hero(ids[0]).xp == xp, "campfire can't be used twice across a reload")

	# Hazard: same hazard.
	GameState.run["node_state"] = {}
	GameState.choose_node_type("hazard")
	GameState.ensure_hazard()
	var hz := str(GameState.run["node_state"]["hazard"]["id"])
	_reload()
	GameState.ensure_hazard()
	check(str(GameState.run["node_state"]["hazard"]["id"]) == hz, "same hazard after reload")

	# Combat: mid-fight reload restarts the same monsters; finished fight keeps its result.
	for h in GameState.current_party():
		h.hp = Combat.max_hp(h)
	GameState.run["node_state"] = {}
	GameState.choose_node_type("combat")
	GameState.engage_node()
	var mon: Array = GameState.run["node_state"]["combat_state"]["monsters"].map(func(m): return m["name"])
	_reload()
	check(not GameState.run["node_state"].has("combat_state") and not GameState.run["node_state"].has("result"), "mid-fight reload -> encounter awaits")
	GameState.engage_node()
	check(GameState.run["node_state"]["combat_state"]["monsters"].map(func(m): return m["name"]) == mon, "re-engaged fight has the same monsters %s" % [mon])
	for step in 60:
		if GameState.run["node_state"].has("result"):
			break
		GameState.resolve_turn_now()
	var res: Dictionary = GameState.run["node_state"].get("result", {})
	check(not res.is_empty(), "fight finished")
	c0 = GameState.coins
	_reload()
	var ns2: Dictionary = GameState.run["node_state"]
	check(ns2.has("result") and GameState.coins == c0, "finished fight keeps its result, no re-pay")
	if res.get("won", false) and not res.get("reward_options", []).is_empty():
		n_items = GameState.items.size() + GameState.relics.size()
		GameState.pick_combat_reward(0)
		_reload()
		GameState.pick_combat_reward(0)
		check(GameState.items.size() + GameState.relics.size() == n_items + 1, "reward picked once across reload")
