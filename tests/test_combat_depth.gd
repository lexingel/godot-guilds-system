extends "res://tests/base_test.gd"
## Boss phases (once, at half health) and elite affixes.


func run() -> void:
	var diff: Dictionary = GameData.DIFFICULTIES[1].duplicate()
	var party: Array[Hero] = [Combat.gen_hero("A", 10), Combat.gen_hero("A", 10)]

	# Every boss rolls a phase; every elite rolls affixes (1, or 2 on B-rank+).
	var boss: Dictionary = Combat.gen_monsters(diff, 3, "boss")[0]
	check(GameData.BOSS_PHASES.has(str(boss.get("phase", ""))), "a boss rolls a phase (%s)" % boss.get("phase", ""))
	var elite: Dictionary = Combat.gen_monsters(diff, 3, "elite")[0]
	check((elite.get("affixes", []) as Array).size() == 1, "an elite has one affix")
	var hard := diff.duplicate()
	hard["elite_chance_up"] = true
	for k in 30:
		var e2: Dictionary = Combat.gen_monsters(hard, 3, "elite")[0]
		var affs: Array = e2["affixes"]
		var abil := affs.filter(func(a): return GameData.ELITE_AFFIXES[a].has("ability"))
		if affs.size() != 2 or abil.size() > 1:
			check(false, "B-rank elites get two affixes, at most one ability (%s)" % [affs])
			break
	check(Combat.gen_monsters(diff, 3, "combat")[0].get("affixes", []).is_empty(), "regular foes have no affixes")

	# Each phase fires once when the boss drops to half health.
	for ph in GameData.BOSS_PHASES:
		var st := Combat.start_combat(party, "boss", diff, 3)
		var b: Dictionary = st["monsters"][0]
		b["phase"] = ph
		var count_before: int = (st["monsters"] as Array).size()
		var dmg_before := int(b["dmg"])
		Combat._check_phases(st)
		check(not b.get("_phased", false), "%s: nothing above half health" % ph)
		b["hp"] = float(b["max_hp"]) * 0.45
		Combat._check_phases(st)
		check(b.get("_phased", false) and st.has("_phase_banner"), "%s: fires at half health" % ph)
		match ph:
			"summon": check((st["monsters"] as Array).size() == count_before + 2, "summon adds two foes")
			"fury": check(int(b["dmg"]) > dmg_before, "fury hits harder")
			"barrier": check(float(st["monster_shields"].get(0, 0.0)) >= float(b["max_hp"]) * 0.11, "barrier raises a ward")
		var n: int = (st["monsters"] as Array).size()
		Combat._check_phases(st)
		check((st["monsters"] as Array).size() == n, "%s: only once" % ph)

	# Affix channels.
	for id in ["juggernaut", "blazing", "hasted", "vampiric"]:
		var e4 := {}
		for t in 60:
			e4 = {"name": "X", "hp": 100, "dmg": 100, "armor": 0.0, "status": "", "ability": {}}
			Combat._roll_affixes(e4, 1)
			if e4["affixes"][0] == id:
				break
		match id:
			"juggernaut": check(float(e4["armor"]) >= 0.35, "Juggernaut is armored")
			"blazing": check(e4["status"] == "burn", "Blazing burns")
			"hasted": check(int(e4["dmg"]) < 100, "Hasted hits a little weaker")
			"vampiric": check(e4["ability"].get("kind") == "drain", "Vampiric drains")

	# Hasted acts twice a round.
	var st2 := Combat.start_combat(party, "elite", diff, 3)
	var em: Dictionary = st2["monsters"][0]
	em["affixes"] = ["hasted"]
	var order := Combat._compute_turn_order(st2)
	check(order.filter(func(t): return t["type"] == "monster" and int(t["id"]) == 0).size() == 2, "a Hasted elite gets two turns")

	# A full fight with phases and affixes runs clean to the end.
	for kind in ["boss", "elite"]:
		var st3 := Combat.start_combat([Combat.gen_hero("S", 20), Combat.gen_hero("S", 20)], kind, diff, 3)
		var out := {}
		for t in 400:
			out = Combat.resolve_turn(st3)
			if out.get("done", false):
				break
		check(out.get("done", false), "%s fight with phase/affixes finishes" % kind)
