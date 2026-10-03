extends "res://tests/base_test.gd"
## The Descent (the Endless Rift turn-based, with heroes) and the lost
## champions' pillars, there and on the ladder.


func run() -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "Deep Ones"
	GameState.hire_starters()
	GameState.roll_champions()
	GameState.campaign_act = 3   # Act II done: the Endless Rift is open
	GameState.best_rift_rank_sealed = GameData.rift_rank_index("B")
	for h in GameState.heroes:
		h.rank = "A"
		h.level = 10
	var ids: Array[String] = []
	for h in GameState.heroes:
		ids.append(h.id)
	var first_lost := GameState.next_lost_champion()
	check(first_lost != "" and GameState.descent_rank() == "B", "a lost champion waits, and the Descent is fought at the best sealed rank")

	# A Descent: depths of four floors, a guardian, then a pillar.
	GameState.start_descent(ids, null)
	var layers: Array = GameState.run["layers"]
	check(int(GameState.run["descent"]) == 1 and layers.size() == GameData.DESCENT_FLOORS and layers[-1]["options"] == ["elite"], "depth 1 is four floors ending in a guardian")
	var hp1 := float(GameState._diff()["monster_hp"])
	GameState.run["pos"] = layers.size() - 1
	GameState.advance_node()
	check(int(GameState.run["descent"]) == 2 and GameState.descent_best == 1 and (GameState.run["layers"] as Array).size() == 2 * GameData.DESCENT_FLOORS, "clearing a depth opens the next below")
	check(GameState.current_layer_options() == ["campfire"], "a new depth starts at a campfire")
	check(float(GameState._diff()["monster_hp"]) > hp1, "each depth is harder")
	check((GameState.run["layers"] as Array)[-1]["options"] == ["pillar"], "depth 2 ends at a lost champion's pillar")

	# The pillar's keeper fights as a rift warden; winning frees the champion.
	GameState.run["pos"] = (GameState.run["layers"] as Array).size() - 1
	GameState.choose_node_type("pillar")
	GameState.engage_node()
	var st: Dictionary = GameState.run["node_state"]["combat_state"]
	check(st.get("is_boss", false) or (st["monsters"] as Array).size() >= 1, "the pillar starts a warden fight")
	var posts := GameState.posts_freed()
	GameState._apply_combat_outcome({"done": true, "result": {"won": true, "coin": 10, "crystal": 5, "bonus_crystal": 0, "rounds": 3, "monster_name": "Keeper", "reward_options": []}})
	check(GameState.champion_unlocked(first_lost) and GameState.posts_freed() == posts + 1, "winning at the pillar frees the lost champion and empties a post")
	check(str(GameState.run["node_state"]["result"].get("freed", "")) != "", "the result names who was freed")

	# Falling in the Descent loses half of what it earned; climbing out keeps all.
	var c0 := int(GameState.run["start_coins"])
	GameState.coins = c0 + 400
	GameState.run["node_state"] = {"result": {"won": false}}
	GameState.finish_run()
	check(GameState.coins == c0 + 200 and GameState.run.is_empty(), "falling loses half of what the Descent earned")
	GameState.start_descent(ids, null)
	var c1 := int(GameState.run["start_coins"])
	GameState.coins = c1 + 400
	GameState.retreat_now()
	check(GameState.coins == c1 + 400, "climbing out keeps everything")

	# Pillars on the ladder: Rank B+ rifts, once the Endless Rift is open.
	check(GameState.ladder_pillar_open("B") and not GameState.ladder_pillar_open("C"), "a ladder pillar can wait in a Rank B+ rift")
	GameState.start_ladder_rift("B", ids, null)
	GameState._add_pillar()
	var any_pillar := (GameState.run["layers"] as Array).any(func(l): return (l["options"] as Array).has("pillar"))
	check(any_pillar and (GameState.run["layers"] as Array)[-1]["options"] == ["boss"], "a pillar sits on a fork, and the rift still ends at its warden")
	GameState.run = {}
	GameState.campaign_act = 2
	check(not GameState.ladder_pillar_open("B"), "no pillars before the Endless Rift opens")
	GameState.delete_slot(9)
