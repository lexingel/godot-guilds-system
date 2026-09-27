extends "res://tests/base_test.gd"
## Attribute reset for Essence (Crystals).

func run() -> void:
	seed(5)
	GameState.active_slot = 9
	GameState.reset()
	var h := Combat.gen_hero("D", 6)
	h.id = "h1"
	GameState.heroes.append(h)
	GameState.active_slot = 9
	GameState.guild_name = "T"
	GameState.heroes.clear()
	GameState.heroes.append(h)
	var spent: int = GameState.attr_points_spent(h)
	check(spent == 15, "L6 recruit has 15 spent points (%d)" % spent)
	GameState.crystals = 20
	check(GameState.respec_attrs("h1") == "Not enough Essence" and h.attr_points == 0, "can't afford: nothing changes")
	GameState.crystals = 80
	check(GameState.respec_attrs("h1") == "" and GameState.crystals == 20 and h.attr_points == 15, "reset refunds 15 points for 60 Essence")
	check(h.attrs == GameData.role_attrs(GameData.hero_role(h)), "attrs back to the role spread")
	check(GameState.respec_attrs("h1") == "Nothing to reset", "second reset refused (nothing spent)")
	GameState.auto_assign_attrs("h1")
	GameState.crystals = 80
