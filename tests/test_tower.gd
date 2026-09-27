extends "res://tests/base_test.gd"
## Tower of Trials: fixed floors, rules, guardians, first-clear rewards, the
## weekly ladder, and heroes leaving a trial exactly as they entered.


func _heroes(n: int, rank := "C", level := 8) -> Array[String]:
	var ids: Array[String] = []
	for i in n:
		var h := Combat.gen_hero(rank, level)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	return ids


## Plays the current tower fight out on auto (with a strong party; retries on
## a loss since combat rolls vary). Returns whether it was won.
func _fight() -> bool:
	GameState.quick_fight()
	var res: Dictionary = GameState.run.get("node_state", {}).get("result", {})
	return bool(res.get("won", false))


func run() -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	check(not GameState.feature_unlocked("tower"), "tower locked in Act I")
	GameState.campaign_act = 2
	check(GameState.feature_unlocked("tower") and GameState.tower_next_floor() == 1, "Act II opens the tower at floor 1")

	# Floors are fixed: same info and same foes every time.
	var a := GameState.tower_floor_info(37)
	var b := GameState.tower_floor_info(37)
	check(a["rules"] == b["rules"] and int(a["seed"]) == int(b["seed"]), "a floor's rules and seed never change")
	check(GameState.tower_floor_info(3)["rules"].is_empty() and GameState.tower_floor_info(12)["rules"].size() == 1, "no rules on the first floors, one after")
	check(GameState.tower_floor_info(95)["rules"].size() == 2 and GameState.tower_floor_info(95)["weekly"], "ladder floors carry two rules")
	var g := GameState.tower_floor_info(50)
	check(g["kind"] == "boss" and g["rules"].is_empty() and str(g["boss"]["name"]) == "Tidewarden Selk", "floor 50 is its guardian")
	check(GameState.tower_floor_info(15)["kind"] == "elite" and GameState.tower_floor_info(16)["kind"] == "combat", "every 5th floor is an elite")
	check(GameState._tower_diff(GameState.tower_floor_info(60))["monster_hp"] > GameState._tower_diff(GameState.tower_floor_info(20))["monster_hp"], "foes grow with the floor")

	# Guardian mechanics are the authored ones.
	var gd := GameState._tower_diff(g)
	var gm := Combat.gen_monsters(gd, GameData.TOWER_FIGHT_DEPTH, "boss")
	check(str(gm[0]["name"]) == "Tidewarden Selk" and gm[0]["mechanic"]["id"] == "warded" and gm[0].get("mechanic2", {}).get("id", "") == "regen", "guardian has its fixed name and mechanics")

	# Rules reach the monsters.
	var ironclad := {"floor": 30, "biome": "vale", "boss": {}, "rules": [GameData.TOWER_RULES[0]]}
	var im := Combat.gen_monsters(GameState._tower_diff(ironclad), 2, "combat")
	check(im.all(func(m): return float(m["armor"]) >= 0.3), "Ironclad armors every foe")
	var burn := {"floor": 30, "biome": "vale", "boss": {}, "rules": [GameData.TOWER_RULES[1]]}
	check(Combat.gen_monsters(GameState._tower_diff(burn), 2, "combat").all(func(m): return m["status"] == "burn"), "Scorching gives every foe burn")
	var swarm := {"floor": 30, "biome": "vale", "boss": {}, "rules": [GameData.TOWER_RULES[3]]}
	check(Combat.gen_monsters(GameState._tower_diff(swarm), 2, "combat").size() == 4, "Swarm fields four foes")
	var single := {"floor": 30, "biome": "vale", "boss": {}, "rules": [GameData.TOWER_RULES[5]]}
	check(Combat.gen_monsters(GameState._tower_diff(single), 2, "elite").size() == 1, "Colossus is a lone foe")
	var duo := {"floor": 30, "biome": "vale", "boss": {}, "rules": [GameData.TOWER_RULES[9]]}
	check(GameState.tower_floor_info(1)["party_cap"] == 4, "no cap without a rule")
	var capped := -1
	for f in range(6, 90):
		if GameState.tower_floor_info(f)["party_cap"] == 2:
			capped = f
			break
	check(capped > 0, "some floor carries the Duo rule")

	# Attempt floor 1 with a strong party: full HP in, restored out.
	var ids := _heroes(4, "A", 10)
	var h0 := GameState.find_hero(ids[0])
	h0.hp = 5
	var coins0 := GameState.coins
	var day0 := GameState.day
	GameState.start_tower(ids)
	check(int(GameState.run.get("tower", 0)) == 1 and GameState.current_node_kind() == "combat", "start_tower begins floor 1")
	GameState.save()
	GameState.load_save()
	check(int(GameState.run.get("tower", 0)) == 1 and GameState.run.get("tower_snap", {}).has(ids[0]), "tower run survives a reload")
	GameState.engage_node()
	check(GameState.find_hero(ids[0]).hp == Combat.max_hp(GameState.find_hero(ids[0])), "heroes fight at full HP")
	var won := _fight()
	check(won, "a strong party clears floor 1")
	var res: Dictionary = GameState.run["node_state"]["result"]
	check(res.get("reward_options", []).is_empty() and res.has("tower") and bool(res["tower"]["first"]), "no loot pick; a first-clear tower reward instead")
	check(GameState.tower_best == 1 and GameState.coins == coins0 + int(GameState.tower_reward(1)["coins"]), "floor 1 pays its first-clear coins")
	GameState.finish_run()
	h0 = GameState.find_hero(ids[0])
	check(GameState.run.is_empty() and h0.hp == 5 and GameState.day == day0, "heroes leave as they came; no day passes")
	check(GameState.tower_next_floor() == 2, "next floor is 2")

	# A loss downs no one and pays nothing.
	GameState.tower_best = 59
	var weak := _heroes(1, "F", 1)
	var coins1 := GameState.coins
	GameState.start_tower(weak)
	check(int(GameState.run["tower"]) == 60 and GameState.current_node_kind() == "boss", "floor 60 is a guardian fight")
	GameState.quick_fight()
	var lost: Dictionary = GameState.run["node_state"]["result"]
	check(not bool(lost["won"]), "a lone F-rank loses floor 60")
	GameState.finish_run()
	var wh := GameState.find_hero(weak[0])
	check(not wh.is_downed() and wh.hp > 0 and not wh.quirks.any(func(q): return GameData.quirk(q)["origin"] == "scar") and GameState.coins == coins1 and GameState.tower_best == 59, "a tower loss downs, scars and pays nothing")

	# Guardian first clear: relic + title.
	GameState.tower_best = 9
	var relics0 := GameState.relics.size()
	var got := GameState._complete_tower_floor(10)
	check(GameState.relics.size() == relics0 + 1 and GameState.relics[-1].unique_id == "t_gate_key" and str(got["relic"]) == "Gatekeeper's Key", "floor 10 gives the Gatekeeper's Key")
	check(str(got["title"]) == "Tower Initiate" and GameState.tower_title() == "Tower Initiate", "floor 10 earns the first title")
	check(GameData.find_unique_relic("t_gate_key").has("desc"), "tower relics have descriptions")
	check(GameState.relics[-1].specials.size() == 1 and str(GameState.relics[-1].specials[0]["kind"]) == "first_round_pct", "tower relic carries its special")

	# Weekly ladder.
	GameState.tower_best = 90
	GameState.tower_week_cleared = 0
	check(GameState.tower_next_floor() == 91, "past 90 the ladder starts at 91")
	var g91 := GameState._complete_tower_floor(91)
	check(bool(g91["first"]) and GameState.tower_next_floor() == 92, "first 91 clear advances the ladder")
	GameState.tower_week = GameState.tower_week_id() - 1   # a new week
	check(GameState.tower_next_floor() == 91 and GameState.tower_week_cleared == 0, "a new week resets the ladder")
	var again := GameState._complete_tower_floor(91)
	check(not bool(again["first"]) and int(again["coins"]) == int(GameState.tower_reward(91)["coins"]) / 2 , "a weekly re-clear pays half")
	GameState.tower_week_cleared = 10
	check(GameState.tower_next_floor() == 0, "nothing left once the week's ladder is done")
	GameState.tower_best = 100
	check(GameState.tower_title() == "Summit Keeper", "floor 100 earns Summit Keeper")

	# Save/load keeps progress.
	GameState.save()
	GameState.load_save()
	check(GameState.tower_best == 100 and GameState.tower_week_cleared == 10, "tower progress survives a reload")
