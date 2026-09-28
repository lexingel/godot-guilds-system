extends "res://tests/base_test.gd"
## Playing by hand: a fight won with no Auto and no hero down pays extra Gold.


func _fight(auto: bool) -> Dictionary:
	GameState.run["node_state"] = {}
	GameState.choose_node_type("combat")
	GameState.engage_node()
	var state: Dictionary = GameState.run["node_state"]["combat_state"]
	if auto:
		state["auto_used"] = true
	for step in 200:
		if GameState.run["node_state"].has("result"):
			break
		GameState.resolve_turn_now()
	return GameState.run["node_state"].get("result", {})


func run() -> void:
	seed(4321)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	var ids: Array[String] = []
	for r in ["A", "A", "A"]:
		var h := Combat.gen_hero(r, 30)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	GameState.start_run("lesser", ids, null)
	var res := _fight(false)
	check(res.get("won", false), "the strong party wins")
	var coins_before := GameState.coins
	check(int(res.get("hand_bonus", 0)) > 0, "a flawless fight played by hand pays a bonus (%d)" % int(res.get("hand_bonus", 0)))
	for h in GameState.heroes:
		h.hp = Combat.max_hp(h)
	var res2 := _fight(true)
	check(res2.get("won", false) and int(res2.get("hand_bonus", 0)) == 0, "no bonus once Auto played a turn")
	check(GameState.coins >= coins_before, "gold only goes up")
