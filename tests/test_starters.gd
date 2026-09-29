extends "res://tests/base_test.gd"
## A new guild starts with a balanced trio, so the first step is a rift.


func run() -> void:
	for s in 5:
		seed(100 + s)
		GameState.active_slot = 9
		GameState.reset()
		GameState.hire_starters()
		var roles: Array = GameState.heroes.map(func(h): return GameData.hero_role(h))
		check(GameState.heroes.size() == 3 and GameState.heroes.all(func(h): return h.rank == "F"), "three Rank F starters (seed %d)" % s)
		check(roles.has("warrior") and roles.has("cleric") and (roles.has("ranger") or roles.has("mage")), "a warrior, a cleric and a ranged hero %s" % [roles])
		var ids := {}
		for h in GameState.heroes:
			ids[h.id] = true
		check(ids.size() == 3, "each with their own id")
		check(GameState.coins >= int(GameState.payday_forecast()["bill"]), "and the first payday is covered (%d Gold for a %d bill)" % [GameState.coins, int(GameState.payday_forecast()["bill"])])
