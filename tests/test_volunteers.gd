extends "res://tests/base_test.gd"
## A broke guild down to its last hero is refilled by volunteers at payday,
## so a bad week means rebuilding, not a dead save.


func run() -> void:
	seed(3)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	GameState.hire_starters()
	GameState.coins = 100000
	GameState.run_payday()
	check(GameState.heroes.size() == 3, "a guild with Gold gets no volunteers")
	GameState._release(GameState.heroes[2])
	GameState._release(GameState.heroes[1])
	GameState.coins = 0
	GameState.pending_toasts.clear()
	GameState.run_payday()
	check(GameState.heroes.size() == GameData.VOLUNTEER_FLOOR, "a broke guild of one is filled back to %d" % GameData.VOLUNTEER_FLOOR)
	check(GameState.pending_toasts.any(func(t): return str(t["title"]) == "Volunteers"), "and told why, and how to rebuild")
	check(GameState.heroes.all(func(h): return str(h.id) != ""), "volunteers are real roster heroes")
	GameState._release(GameState.heroes[2])
	GameState.coins = int(GameData.find_rank("F")["cost"]) + 1000
	GameState.run_payday()
	check(GameState.heroes.size() == 2, "a guild that can afford a recruit hires its own")
