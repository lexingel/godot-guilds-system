extends "res://tests/base_test.gd"
## Riftbreaks: a rift swells from Act II, counts down in days, closes when a
## rift of its rank is sealed in time, and otherwise breaks, blocks rift runs
## until defended, and pays out or takes its toll.


func _days(n: int) -> void:
	for i in n:
		GameState.pass_time()


func run() -> void:
	seed(5)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	var h := Combat.gen_hero("D", 5)
	h.id = "h%d" % GameState.next_id
	GameState.next_id += 1
	GameState.heroes.append(h)

	_days(20)
	check(not GameState.breach_active() and GameState.breach_next_day < 0, "no rifts swell in Act I")

	# Act II: the first one swells after BREACH_FIRST_DELAY days.
	GameState.campaign_act = GameData.BREACH_UNLOCK_ACT
	GameState.best_rift_rank_sealed = 2
	GameState.pending_toasts.clear()
	_days(1)
	check(GameState.breach_next_day == GameState.day + GameData.BREACH_FIRST_DELAY, "the first rift swells %d days into Act II" % GameData.BREACH_FIRST_DELAY)
	_days(GameData.BREACH_FIRST_DELAY)
	check(GameState.breach_active() and not GameState.breach_broken(), "a rift swells")
	check(int(GameState.breach["rank"]) in [2, 3] and str(GameState.breach["region"]) != "camp", "at your best seal or one above, out in a region (%s)" % GameState.breach_rank_id())
	check(GameState.breach_days_left() == GameData.BREACH_WARN, "%d days to act" % GameData.BREACH_WARN)
	check(GameState.pending_toasts.any(func(t): return str(t["title"]) == "A rift is swelling"), "with a warning")
	check(not GameState.breach_blocks_runs(), "rift runs go on while it swells")

	# Sealing a lower rank doesn't close it; its rank or higher does.
	var rank := int(GameState.breach["rank"])
	var ess0 := GameState.crystals
	GameState._on_rift_sealed(rank - 1)
	check(GameState.breach_active(), "a lower seal doesn't close it")
	GameState._on_rift_sealed(rank)
	check(not GameState.breach_active() and GameState.crystals > ess0, "sealing its rank closes it, for Essence")
	check(GameState.breach_next_day >= GameState.day + GameData.BREACH_EVERY_MIN and GameState.breach_next_day <= GameState.day + GameData.BREACH_EVERY_MAX, "and the next one is %d-%d days off" % [GameData.BREACH_EVERY_MIN, GameData.BREACH_EVERY_MAX])

	# Left alone, it breaks and blocks rift runs.
	GameState.breach_next_day = GameState.day + 1
	_days(1)
	check(GameState.breach_active(), "another swells")
	_days(GameData.BREACH_WARN)
	check(GameState.breach_broken() and GameState.breach_blocks_runs(), "left alone, it breaks and blocks rift runs")
	GameState._on_rift_sealed(8)
	check(GameState.breach_broken(), "a broken rift can only be defended")

	# Held: paid by rank and integrity kept; a fallen defender is wounded.
	var c0 := GameState.coins
	var day0 := GameState.day
	var won := GameState.resolve_breach({"held": true, "integrity": 1.0, "fallen": [h.id]})
	check(won["held"] and GameState.coins == c0 + int(won["coins"]) and int(won["coins"]) > 0, "holding pays Gold (%d)" % int(won["coins"]))
	check(h.down_runs > 0 and (won["wounded"] as Array).has(h.name), "a defender who fell comes back wounded")
	check(not GameState.breach_active() and GameState.day == day0 + 1, "the breach is over, and it took the day")

	# Lost: Gold and Essence, and a damaged building until repaired.
	GameState.upgrades["ops.drill"] = 3
	GameState.coins = 1000
	GameState.crystals = 500
	GameState.breach = {"rank": 3, "region": "marsh", "started": GameState.day, "breaks_on": GameState.day, "broken": true}
	var lost := GameState.resolve_breach({"held": false, "integrity": 0.0, "fallen": []})
	check(int(lost["lost_coins"]) == 200 and int(lost["lost_crystals"]) == 100, "losing costs %d%% of Gold and Essence" % int(GameData.BREACH_LOSS_SHARE * 100))
	check(lost["damaged"] == ["Drill Yard"] and GameState.lvl("ops.drill") == 2 and int(GameState.upgrades["ops.drill"]) == 3, "a building is damaged: it works a level lower")
	GameState.save()
	GameState.load_save()
	check(GameState.lvl("ops.drill") == 2 and GameState.breach_next_day > 0, "damage and the schedule survive a save")
	GameState.coins = 0
	check(GameState.repair_building("ops.drill") != "", "repairs cost Gold")
	GameState.coins = 500
	check(GameState.repair_building("ops.drill") == "" and GameState.lvl("ops.drill") == 3 and GameState.coins == 500 - GameState.repair_cost("ops.drill"), "and restore the level")

	# The camp breaks from rank S up (two buildings on a loss there).
	GameState.best_rift_rank_sealed = GameData.rift_rank_index(GameData.BREACH_CAMP_RANK)
	GameState.breach = {}
	GameState._swell_breach()
	check(str(GameState.breach["region"]) == "camp" and GameState.breach_place() == "your camp", "Rank %s and up break at the camp" % GameData.BREACH_CAMP_RANK)
