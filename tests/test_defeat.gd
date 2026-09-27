extends "res://tests/base_test.gd"
## "Why you lost": a real loss carries reasons; each cause shows up when it
## should; at most three, strongest first.


func run() -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	var h := Combat.gen_hero("F", 1)
	h.id = "h%d" % GameState.next_id
	GameState.next_id += 1
	GameState.heroes.append(h)
	var ids: Array[String] = [h.id]
	GameState.runs_started = 3
	GameState.start_run("greater", ids, null)
	GameState.engage_node()
	var st: Dictionary = GameState.run["node_state"]["combat_state"]
	for m in st["monsters"]:
		m["dmg"] = 999
	for i in 200:
		if GameState.run["node_state"].has("result"):
			break
		var nxt := Combat.peek_next_turn(st)
		if str(nxt["type"]) == "hero":
			st["pending_actions"][str(nxt["id"])] = {"action": "attack", "target": 0}
		GameState.resolve_turn_now()
	var res: Dictionary = GameState.run["node_state"].get("result", {})
	check(not bool(res.get("won", true)), "a lone F-rank loses a Greater fight")
	var reasons: Array = res.get("defeat_reasons", [])
	check(not reasons.is_empty() and reasons.size() <= 3, "a loss explains itself (%d reasons)" % reasons.size())
	check(str(reasons[0][0]).begins_with("Underpowered"), "being far under the recommended power leads")
	GameState.finish_run()

	# Each cause from a synthetic fight state.
	var party: Array[Hero] = [Combat.gen_hero("C", 8)]
	party[0].formation = "back"
	var base := {"party": party, "monsters": [{"max_hp": 100.0, "hp": 0.0}], "diff": {"rec_power": 1}, "round_num": 5, "is_boss": false}
	var s1 := base.duplicate(true)
	s1["party"] = party
	s1["_stats"] = {"undefended_heavy": 2.0, "heavy_dmg": 80.0, "taken": 200.0, "abilities": 1.0}
	check(defeat_has(s1, "heavy blow"), "undefended heavy blows are called out")
	var s2 := base.duplicate(true)
	s2["party"] = party
	s2["_stats"] = {"taken": 100.0, "dot": 50.0, "abilities": 1.0}
	check(defeat_has(s2, "Burn and poison"), "damage over time is called out")
	var s3 := base.duplicate(true)
	s3["party"] = party
	s3["_stats"] = {"enemy_heal": 40.0, "abilities": 1.0}
	check(defeat_has(s3, "healed"), "enemy healing is called out")
	var s4 := base.duplicate(true)
	s4["party"] = party
	s4["_start_hp_pct"] = 0.3
	s4["_stats"] = {"abilities": 1.0}
	check(defeat_has(s4, "started the fight at 30%"), "entering wounded is called out")
	var s5 := base.duplicate(true)
	s5["party"] = party
	s5["_stats"] = {}
	check(defeat_has(s5, "No Abilities"), "unused abilities are called out")


func defeat_has(state: Dictionary, needle: String) -> bool:
	return Combat.defeat_reasons(state).any(func(r): return str(r[0]).contains(needle))
