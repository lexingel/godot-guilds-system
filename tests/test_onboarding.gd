extends "res://tests/base_test.gd"
## Staged unlocks, coach tips and the training rift.


func run() -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	check(not GameState.feature_unlocked("quests") and not GameState.feature_unlocked("rift_map") and not GameState.feature_unlocked("inventory"), "a new guild starts with features locked")
	check(GameState.feature_unlocked("roster") and GameState.feature_unlocked("recruits"), "core screens always open")
	# The Rift Map stays empty and doesn't tick before it unlocks.
	GameState.resolve_rift_map()
	check(GameState.rift_map.all(func(s): return not s.has("rank")), "no ranked rifts before the map unlocks")
	GameState.pass_time()
	check(GameState.pending_riftbreak_ranks.is_empty(), "no Riftbreaks for a brand-new guild")
	# Training rift: only the first run.
	var ids: Array[String] = []
	for r in ["E", "E"]:
		var h := Combat.gen_hero(r, 1)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	GameState.start_run("lesser", ids, null, false, false)
	check(GameState.run.get("training", false) and GameState.run["layers"].size() == GameData.TRAINING_RIFT["floors"], "first run is a %d-floor training rift" % GameData.TRAINING_RIFT["floors"])
	check(GameState.run["layers"].all(func(l): return not (l["options"] as Array).has("elite")), "no elites in the training rift")
	check(int(GameState._diff()["monster_hp"]) < int(GameData.DIFFICULTIES[0]["monster_hp"]), "training foes are weaker")
	GameState.finish_run()
	GameState.start_run("lesser", ids, null, false, false)
	check(not GameState.run.get("training", false), "second run is a normal rift")
	GameState.finish_run()
	# Unlock announcements.
	GameState.pending_toasts.clear()
	GameState.rifts_sealed = 1
	var fresh := GameState.check_feature_unlocks()
	check(fresh.has("quests") and fresh.has("crafting") and fresh.has("management") and not fresh.has("rift_map"), "first seal unlocks quests/crafting/management %s" % [fresh])
	check(GameState.pending_toasts.size() == 1 and str(GameState.pending_toasts[0]["text"]).contains("Guild Board"), "one combined unlock toast")
	check(GameState.check_feature_unlocks().is_empty(), "announced only once")
	GameState.rifts_sealed = 2
	check(GameState.check_feature_unlocks().has("rift_map"), "second seal unlocks the Rift Map")
	GameState.resolve_rift_map()
	check(GameState.rift_map.any(func(s): return s.has("rank")), "map fills once unlocked")
	# Tips.
	check(GameState.hint_pending("battle"), "tip pending")
	GameState.dismiss_hint("battle")
	check(not GameState.hint_pending("battle"), "dismissed tip stays gone")
	GameState.tips_off = true
	check(not GameState.hint_pending("party"), "tips off hides every tip")
	# Save round-trip + old-save seeding.
	GameState.save()
	GameState.load_save()
	check(GameState.hints_seen.has("battle") and GameState.tips_off and GameState.runs_started == 2, "tips and run count saved")
	var d: Dictionary = JSON.parse_string(GameState.export_save_text())
	d.erase("features_seen")
	d.erase("runs_started")
	GameState.import_save_text(JSON.stringify(d), 9)
	GameState.load_save()
	GameState.pending_toasts.clear()
	check(GameState.check_feature_unlocks().is_empty(), "an old guild isn't spammed with unlock toasts")
	check(GameState.runs_started >= 1, "an old guild doesn't get a training rift")
