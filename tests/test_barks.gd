extends "res://tests/base_test.gd"
## Hero voices: every trait has a voice with lines for every moment; heroes
## speak at most once a turn and twice a fight; a win carries one quote.


func run() -> void:
	for q in GameData.quirks_from("born"):
		check(GameData.BARKS.has(str(GameData.QUIRKS[q].get("voice", ""))), "born quirk '%s' has a voice" % q)
	for v in GameData.BARKS:
		for moment in ["kill", "low_hp", "ally_down", "victory", "level_up"]:
			if (GameData.BARKS[v].get(moment, []) as Array).is_empty():
				check(false, "%s has %s lines" % [v, moment])

	var party: Array[Hero] = [Combat.gen_hero("A", 6), Combat.gen_hero("A", 6)]
	party[0].id = "a"
	party[1].id = "b"
	var st := Combat.start_combat(party, "combat", GameData.DIFFICULTIES[0], 1)
	st["_barks"] = []
	Combat._bark(st, party[0], "kill", 1.0)
	Combat._bark(st, party[1], "kill", 1.0)
	check((st["_barks"] as Array).size() == 1, "one line per turn")
	check(str(st["log"].back()).contains("\""), "the line is logged")
	st["_barks"] = []
	Combat._bark(st, party[0], "kill", 1.0)
	st["_barks"] = []
	Combat._bark(st, party[0], "kill", 1.0)
	check((st["_barks"] as Array).is_empty(), "at most twice a fight per hero")

	# A won fight ends with someone's quote.
	var strong: Array[Hero] = [Combat.gen_hero("S", 20), Combat.gen_hero("S", 20)]
	var st2 := Combat.start_combat(strong, "combat", GameData.DIFFICULTIES[0], 1)
	var out := {}
	for i in 300:
		out = Combat.resolve_turn(st2)
		if out.get("done", false):
			break
	check(out.get("result", {}).get("won", false), "the strong party wins")
	check(not str(out["result"].get("bark", {}).get("text", "")).is_empty(), "the win carries a quote")
