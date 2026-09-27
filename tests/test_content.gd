extends "res://tests/base_test.gd"
## Monster roster and hand-designed encounters.


func run() -> void:
	seed(4)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"

	# Every monster has art, a region, and a Bestiary entry's worth of data.
	for n in GameData.MONSTER_NAMES:
		check(ResourceLoader.exists(GameData.sprite_for_monster(str(n))) and GameData.MONSTER_NAME_SPRITE.has(n), "%s has its own sprite" % n)
		var in_region := false
		for b in GameData.BIOMES:
			if (GameData.BIOMES[b]["monsters"] as Array).has(n):
				in_region = true
		check(in_region, "%s lives in a region" % n)
	check(GameData.MONSTER_NAMES.size() >= 25, "at least 25 regular monsters")

	# Encounters: known members, shares about 1, every region has several.
	for b in GameData.BIOMES:
		var encs: Array = GameData.ENCOUNTERS.get(b, [])
		check(encs.size() >= 5, "%s has 5+ designed encounters" % b)
		for e in encs:
			var hp := 0.0
			var dmg := 0.0
			for mem in e["members"]:
				check(GameData.MONSTER_NAMES.has(mem[0]), "%s: %s is a known monster" % [e["name"], mem[0]])
				hp += float(mem[1])
				dmg += float(mem[2])
			check(absf(hp - 1.0) < 0.05 and absf(dmg - 1.0) < 0.05, "%s: shares sum to 1" % e["name"])

	# A designed fight carries its name, leads with its first member, and
	# costs the same total as a random fight.
	var diff: Dictionary = GameData.DIFFICULTIES[0].duplicate()
	diff["biome"] = "vale"
	var found := false
	for t in 60:
		var ms := Combat.gen_monsters(diff, 3, "combat")
		var enc: Dictionary = ms[0].get("encounter", {})
		if enc.is_empty():
			continue
		found = true
		var def: Dictionary = (GameData.ENCOUNTERS["vale"] as Array).filter(func(e): return e["name"] == enc["name"])[0]
		check(ms.size() == (def["members"] as Array).size() and ms[0]["name"] == def["members"][0][0] and ms[0]["is_main"], "%s: members in order, lead first" % enc["name"])
		var total := 0.0
		for m in ms:
			total += float(m["hp"])
		var base := float(Combat.gen_monster(diff, 3, "combat")["hp"])
		check(absf(total - base) <= base * 0.1 + 3.0, "%s: same total health as a random fight" % enc["name"])
		break
	check(found, "regular fights sometimes use a designed encounter")
	var tower := diff.duplicate()
	tower["tower_single"] = true
	check(Combat.gen_monsters(tower, 3, "combat").size() == 1, "tower rules skip designed encounters")

	# The new species telegraph their moves.
	check(Combat.monster_kit({"name": "Hedge Warden", "tier": "combat"}) == ["ward"], "Hedge Warden wards")
	check(Combat.monster_kit({"name": "Mire Sniper", "tier": "combat"}) == ["snipe"], "Mire Sniper snipes")
	check(Combat.monster_kit({"name": "Carrion Crier", "tier": "combat"}).has("roar"), "Carrion Crier roars")
	check(Combat.monster_kit({"name": "Slag Golem", "tier": "elite"}).has("roar"), "an elite of a kitted species also roars")

	# The encounter is announced in the fight log.
	GameState.start_run("lesser", [], null)
	var st := {}
	for t in 60:
		var h := Combat.gen_hero("C", 5)
		var party: Array[Hero] = [h]
		st = Combat.start_combat(party, "combat", diff, 3)
		if not st["monsters"][0].get("encounter", {}).is_empty():
			break
	check((st["log"] as Array).any(func(l): return str(l).contains(str(st["monsters"][0].get("encounter", {}).get("name", "@@")))), "the encounter's name and hint open the fight log")
	GameState.run = {}
