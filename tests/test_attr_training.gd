extends "res://tests/base_test.gd"
## Attribute training for Coins, reset unequipping, new-guild recovery.

func run() -> void:
	seed(5)
	GameState.active_slot = 9
	GameState.reset()
	var h := Combat.gen_hero("D", 6)
	h.id = "h1"
	GameState.active_slot = 9
	GameState.guild_name = "T"
	GameState.heroes.clear()
	GameState.heroes.append(h)
	GameState.coins = 120
	check(GameState.train_attr("h1") == "" and h.attr_points == 1 and GameState.coins == 70, "train costs 50, gives 1 point")
	check(GameState.train_attr("h1") == "Not enough Gold" and h.attr_trained == 1, "second costs 100")
	GameState.coins = 10000
	for i in GameData.ATTR_TRAIN_CAP + 2:
		GameState.train_attr("h1")
	check(h.attr_trained == GameData.ATTR_TRAIN_CAP and h.attr_points == GameData.ATTR_TRAIN_CAP, "capped at %d trained" % GameData.ATTR_TRAIN_CAP)
	var back := Hero.from_dict(JSON.parse_string(JSON.stringify(h.to_dict())))
	check(back.attr_trained == GameData.ATTR_TRAIN_CAP, "attr_trained saved")
	# Reset unequips gear that no longer qualifies.
	GameState.auto_assign_attrs("h1")
	var it := Combat.gen_item("epic", "weapon")
	it.id = "i1"
	GameState.items.append(it)
	h.attrs[it.attr] = 20
	GameState.equip_item("h1", "weapon", 0, "i1")
	check(it.equipped_to == "h1", "epic equipped at 20 %s" % it.attr)
	GameState.crystals = 200
	GameState.respec_attrs("h1")
	check(it.equipped_to == "", "reset takes off gear the hero no longer qualifies for")
	check(GameState.recovery_runs() == 1, "new guild recovers in 1 run")
	GameState.rifts_sealed = 3
	check(GameState.recovery_runs() == GameData.DOWNED_RECOVERY_RUNS, "after 3 seals: normal recovery")
	GameState.coins = 300
