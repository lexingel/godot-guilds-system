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
	check(GameData.MONSTER_NAMES.size() >= 31, "at least 31 regular monsters")
	for b in GameData.BIOMES:
		check((GameData.BIOMES[b]["monsters"] as Array).size() >= 11, "%s has 11+ regular monsters" % b)
	for n in ["Blight Hound", "Lantern Wight", "Tide Caller", "Mudscale Brute", "Cinder Hound", "Obsidian Sentinel"]:
		check(GameData.monster_anim_frames(n, "attack").size() == 5 and GameData.monster_anim_frames(n, "hurt").size() == 5, "%s is animated" % n)

	# Encounters: known members, shares about 1, every region has several.
	for b in GameData.BIOMES:
		var encs: Array = GameData.ENCOUNTERS.get(b, [])
		check(encs.size() >= 7, "%s has 7+ designed encounters" % b)
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

	# An elite's escorts come from its region's retinue.
	var ediff: Dictionary = GameData.DIFFICULTIES[1].duplicate()
	ediff["biome"] = "marsh"
	var seen_adds := {}
	for t in 80:
		var ms := Combat.gen_monsters(ediff, 3, "elite")
		for k in range(1, ms.size()):
			seen_adds[ms[k]["name"]] = true
	check(not seen_adds.is_empty() and seen_adds.keys().all(func(n): return (GameData.BIOMES["marsh"]["retinue"] as Array).has(n)), "marsh elites bring marsh supports %s" % [seen_adds.keys()])

	# Designed bosses: a fixed identity each.
	var bdiff: Dictionary = GameData.DIFFICULTIES[0].duplicate()
	bdiff["biome"] = "vale"
	bdiff["boss_name"] = "Vaelith, the Vale-Render"
	var bms := Combat.gen_monsters(bdiff, 6, "boss")
	var vb: Dictionary = bms[0]
	check(vb["mechanic"]["id"] == "regen" and vb["phase"] == "summon" and str(vb.get("encounter", {}).get("hint", "")).contains("Harvest"), "Vaelith: regenerates, summons at half health, and opens with her hint")
	check(Combat.monster_kit(vb) == ["harvest", "curse"], "Vaelith's moves include her Harvest")
	bdiff["boss_name"] = "Sythrane, the Ashen Crown"
	var sb: Dictionary = Combat.gen_monsters(bdiff, 6, "boss")[0]
	check(sb["mechanic"]["id"] == "enrage" and sb.get("mechanic2", {}).get("id", "") == "regen", "Sythrane: enrage and regenerate")
	var rdiff: Dictionary = GameData.DIFFICULTIES[0].duplicate()
	rdiff["biome"] = "ashen"
	var any_profiled := false
	for t in 20:
		var rb: Dictionary = Combat.gen_monsters(rdiff, 6, "boss")[0]
		if GameData.BOSS_PROFILES.has(str(rb["name"]).split(",")[0]) and rb.has("encounter"):
			any_profiled = true
	check(any_profiled, "rift bosses use their profiles too")

	# The signature moves.
	var hA := Combat.gen_hero("C", 6)
	hA.id = "bA"
	hA.formation = "front"
	var hB := Combat.gen_hero("C", 6)
	hB.id = "bB"
	hB.formation = "back"
	var bparty: Array[Hero] = [hA, hB]
	bdiff["boss_name"] = "Vaelith, the Vale-Render"
	var bst := Combat.start_combat(bparty, "boss", bdiff, 6)
	var boss: Dictionary = bst["monsters"][0]
	bst["monsters"] = [boss]
	bst["turn_order"] = []
	bst["dodge"] = 0.0
	bst["escort"] = {}
	boss["hp"] = float(boss["max_hp"]) * 0.8
	boss["_winding"] = false
	boss["_charged"] = false
	var hp_b := float(boss["hp"])
	bst["intents"] = {0: {"kind": "harvest", "target": ""}}
	check(Combat.monster_intent(bst, 0)["targets"].size() == 2, "Harvest shows every hero as a target")
	Combat._resolve_monster_action(bst, 0)
	check(float(boss["hp"]) > hp_b and hA.hp < Combat.max_hp(hA) and hB.hp < Combat.max_hp(hB), "Harvest hits everyone and heals the boss")
	hA.hp = Combat.max_hp(hA)
	hB.hp = Combat.max_hp(hB)
	bst["hero_shields"] = {hA.id: 5.0}
	bst["intents"] = {0: {"kind": "sunder", "target": ""}}
	Combat._resolve_monster_action(bst, 0)
	check(hB.hp == Combat.max_hp(hB) and hA.hp < Combat.max_hp(hA) and not bst["hero_shields"].has(hA.id), "Sunder hits only the front row and tears off its wards")
	bst["intents"] = {0: {"kind": "brand", "target": hB.id}}
	Combat._resolve_monster_action(bst, 0)
	check(bst["_branded"].has(hB.id), "Brand marks a hero")
	bst["intents"] = {0: {"kind": "immolate", "target": ""}}
	Combat._resolve_monster_action(bst, 0)
	check(bst["hero_burn"].has(hB.id), "Immolate sets the party burning")
	bst["intents"] = {0: {"kind": "drown", "target": ""}}
	Combat._resolve_monster_action(bst, 0)
	check(bst["_chilled"].has(hB.id) and bst["_weakened"].has(hB.id), "the Drowning Tide chills and weakens")
	boss["hp"] = float(boss["max_hp"]) * 0.45
	var n0: int = (bst["monsters"] as Array).size()
	Combat._check_phases(bst)
	var called: Array = (bst["monsters"] as Array).slice(n0).map(func(x): return x["name"])
	check(called == ["Carrion Crier", "Hedge Warden"], "Vaelith calls a Crier and a Warden %s" % [called])
