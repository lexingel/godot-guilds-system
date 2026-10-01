extends "res://tests/base_test.gd"
## Daily Rift, run history, memorial and the achievement list.


func _heroes(n: int) -> Array[String]:
	var ids: Array[String] = []
	for i in n:
		var h := Combat.gen_hero("C", 8)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	return ids


func run() -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	var ids := _heroes(3)
	GameState.runs_started = 3

	# Daily Rift: the same for everyone on a day, different day to day.
	var today := GameState.daily_id()
	var a := GameState.daily_info(today)
	check(a["rule"] == GameState.daily_info(today)["rule"] and a["boon"] == GameState.daily_info(today)["boon"] and int(a["seed"]) == int(GameState.daily_info(today)["seed"]), "a day's twist is fixed")
	var differs := false
	for d in range(1, 8):
		var b := GameState.daily_info(today + d)
		if int(b["seed"]) != int(a["seed"]):
			differs = true
	check(differs, "other days differ")
	check(not a["rule"].has("party_cap"), "no party-cap rules on the Daily")
	GameState.rifts_sealed = 2
	check(not GameState.daily_available(), "locked before the third seal")
	GameState.rifts_sealed = 3
	check(GameState.daily_available(), "open after three seals")
	GameState.start_daily("E", ids, null)
	check(int(GameState.run.get("daily", -1)) == today and GameState.run["boons"] == [a["boon"]] and str(GameState.run["rift_rank"]) == "E", "the twist rides a ladder rift, with its boon")
	var layers1: Array = (GameState.run["layers"] as Array).duplicate(true)
	check(not GameState.daily_available(), "one attempt a day")
	var d := GameState._diff()
	for k in a["rule"].get("diff", {}):
		if not (k in ["hp_mult", "dmg_mult"]):
			check(d.has(k), "the Daily's rule reaches the fight (%s)" % k)
	GameState.save()
	GameState.load_save()
	check(int(GameState.run.get("daily", -1)) == today, "Daily run survives a reload")
	var cr0 := GameState.crystals
	GameState.seal_rift()
	check(GameState.daily_clears == 1 and GameState.daily_streak == 1 and GameState.crystals > cr0 and not (GameState.run["sealed"].get("daily", {}) as Dictionary).is_empty(), "sealing the Daily pays a bonus and starts a streak")
	GameState.finish_run()
	check(GameState.run_history.size() == 1 and GameState.run_history[0]["result"] == "Sealed" and str(GameState.run_history[0]["kind"]).ends_with("daily twist"), "run history records the sealed twist")
	# Once a day: a second try is a plain ladder rift.
	GameState.start_daily("E", ids, null)
	check(not GameState.run.has("daily") and str(GameState.run["rift_rank"]) == "E", "after today's try, the ladder runs plain")
	GameState.retreat_now()
	# Same layout again (a second guild on the same day, same rank).
	GameState.daily_attempt_day = -1
	GameState.start_daily("E", ids, null)
	check((GameState.run["layers"] as Array) == layers1, "the same rift layout for the same day")
	GameState.run["daily"] = today + 1
	GameState.daily_last_clear = today
	GameState.seal_rift()
	check(GameState.daily_streak == 2, "consecutive days grow the streak")
	GameState.finish_run()

	# Run history: a retreat, and the cap.
	GameState.coins = 100000   # forty days of wages
	GameState.start_run("lesser", ids, null)
	GameState.retreat_now()
	check(GameState.run_history[0]["result"] == "Retreated", "a retreat is recorded")
	for i in 40:
		for hh in GameState.heroes:
			hh.morale = 80   # forty idle weeks and unanswered requests would drive them off
		GameState.start_run("lesser", ids, null)
		GameState.retreat_now()
	check(GameState.run_history.size() == GameData.RUN_HISTORY_MAX, "history is capped")

	# Memorial.
	var h := GameState.find_hero(ids[0])
	GameState.start_run("lesser", ids, null)
	GameState.run["left_behind"] = [h.id]
	GameState.finish_run()
	check(GameState.find_hero(ids[0]) == null and GameState.fallen.size() == 1 and str(GameState.fallen[0]["name"]) == h.name and GameState.heroes_lost_total == 1, "a hero left behind goes on the memorial")

	# Achievements: every type has a progress value and ids are unique.
	var seen := {}
	for m in GameData.MILESTONES:
		seen[m["id"]] = true
	check(seen.size() == GameData.MILESTONES.size() and GameData.MILESTONES.size() >= 24, "24 unique achievements")
	GameState.tower_best = 30
	check(GameState.milestone_progress(GameData.MILESTONES.filter(func(m): return m["id"] == "climber")[0]) == 30, "Tower achievement tracks the best floor")
	GameState.save()
	GameState.load_save()
	check(GameState.fallen.size() == 1 and GameState.daily_clears == 2 and not GameState.run_history.is_empty(), "records survive a reload")
