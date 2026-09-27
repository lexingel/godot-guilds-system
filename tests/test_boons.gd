extends "res://tests/base_test.gd"
## Run boons: offers after elites, picks, stacking set bonuses, the combat
## channels they feed, and that they end with the rift.


func run() -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	check(GameData.BOONS.size() == 21, "21 boons")
	for b in GameData.BOONS:
		check(GameData.BOON_FAMILIES.has(b["family"]) and (b.has("kind") or b.has("trigger")), "boon %s is well-formed" % b["id"])
	for fam in GameData.BOON_FAMILIES:
		check(GameData.BOONS.filter(func(x): return x["family"] == fam).size() == 3 and GameData.BOON_SETS[fam].size() == 2, "family %s has 3 boons and 2 sets" % fam)
		check(ResourceLoader.exists(str(GameData.BOON_FAMILIES[fam]["icon"])), "family %s icon" % fam)

	var ids: Array[String] = []
	for i in 3:
		var h := Combat.gen_hero("C", 8)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	GameState.runs_started = 3
	GameState.start_run("lesser", ids, null, false)
	var offer := GameState.roll_boon_offer()
	check(offer.size() == 3 and offer.all(func(x): return not GameData.find_boon(str(x)).is_empty()), "an offer is 3 real boons")

	# Stats flow through: Blaze adds party damage via synergy_value_for.
	var d0 := Combat.synergy_value_for("dmg_pct")
	GameState.run["boons"] = ["blaze"]
	check(is_equal_approx(Combat.synergy_value_for("dmg_pct"), d0 + 0.12), "Blaze adds 12% damage")
	GameState.run["boons"] = ["blaze", "kindling"]
	check(is_equal_approx(Combat.synergy_value_for("dmg_pct"), d0 + 0.20), "Ember ×2 set adds 8% more")
	check(Combat.boon_total("escalate_pct") > 0.0, "Kindling escalates")
	# Relic-channel kinds, and never both channels.
	GameState.run["boons"] = ["riposte"]
	check(is_equal_approx(Combat.relic_special_total("counter_pct"), 0.2) and is_equal_approx(Combat.synergy_value_for("counter_pct"), 0.0), "Riposte counts once, via the relic channel")
	# Triggers join the party's relic triggers.
	GameState.run["boons"] = ["pyre", "blaze", "kindling", "leech"]
	var st := Combat.start_combat(GameState.current_party(), "combat", GameData.DIFFICULTIES[0], 1)
	var eff := Combat._party_effects(st)
	check(eff.any(func(e): return e.get("source", "") == "Pyre Burst") and eff.any(func(e): return e.get("source", "") == "Leech"), "boon triggers fire with the party")
	GameState.run["boons"] = ["pyre", "blaze", "kindling", "leech", "frenzy"]
	check(not Combat._party_effects(st).any(func(e): return e.get("source", "") == "Inferno"), "Inferno needs 4 Ember")
	GameState.run["boons"] = ["pyre", "blaze"]
	var roll2 := GameState.roll_boon_offer()
	check(not roll2.has("pyre") and not roll2.has("blaze"), "owned boons aren't offered again")
	check(roll2.any(func(x): return GameData.find_boon(str(x))["family"] == "ember"), "an owned family is favoured")

	# The pick after an elite.
	GameState.run["boons"] = []
	GameState.run["node_state"] = {"type": "combat", "result": {"won": true, "boon_offer": ["surge", "grace", "veil"], "reward_options": []}, "reward_chosen": true}
	check(GameState.boon_pending(), "boon pending after an elite")
	GameState.pick_boon(1)
	check(GameState.run["boons"] == ["grace"] and not GameState.boon_pending(), "picking takes the boon")
	GameState.save()
	GameState.load_save()
	check(GameState.run.get("boons", []) == ["grace"], "boons survive a reload")
	GameState.finish_run()
	check(Combat.boon_total("mend_pct") == 0.0, "boons end with the rift")

	# A real elite win rolls an offer; a Tower elite doesn't.
	GameState.start_run("lesser", ids, null, false)
	GameState.run["layers"][0]["options"] = ["elite"]
	GameState.run["chosen"] = {}
	GameState.choose_node_type("elite")
	GameState.quick_fight()
	var res: Dictionary = GameState.run["node_state"].get("result", {})
	if bool(res.get("won", false)):
		check((res.get("boon_offer", []) as Array).size() == 3, "winning an elite offers boons")
	GameState.finish_run()
