extends "res://tests/base_test.gd"
## The session log behind the Feedback report: fights by hand and on Auto,
## time played, saved with the guild.


func run() -> void:
	seed(9)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	GameState.hire_starters()
	check(GameState.session.is_empty() and GameState.hero_slot_cap() == 6, "a new guild: an empty log, and room for a bench of two")
	var ids: Array[String] = []
	for h in GameState.heroes:
		ids.append(h.id)
	GameState.runs_started = 3
	GameState.start_run("lesser", ids, null)
	GameState.run["pos"] = 1
	GameState.choose_node_type("combat")
	GameState.quick_fight()
	var s: Dictionary = GameState.session
	check(int(s.get("auto_w", 0)) + int(s.get("auto_l", 0)) == 1 and int(s.get("hand_w", 0)) + int(s.get("hand_l", 0)) == 0, "a Quick fight counts as one fight on Auto")
	GameState.session_live = true
	GameState._process(0.5)
	GameState._process(30.0)   # a tab that was asleep
	check(is_equal_approx(float(GameState.session["secs"]), 0.5), "time counts while playing, not across a long pause")
	GameState.session_live = false
	GameState.save()
	GameState.load_save()
	check(is_equal_approx(float(GameState.session.get("secs", 0.0)), 0.5) and int(GameState.session.get("auto_w", 0)) + int(GameState.session.get("auto_l", 0)) == 1, "the log is saved with the guild")
