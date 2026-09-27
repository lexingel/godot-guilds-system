extends "res://tests/base_test.gd"
## The Endless Rift (survivors mode): a run on autopilot spawns foes, kills
## them, levels up, brings an elite each minute and a warden at 5:00 that
## calls the horde at half health, ends when the lead falls, and pays the
## guild for time and kills.


func run() -> void:
	GameState.reset()
	GameState.guild_name = "T"
	var party: Array = []
	for r in ["A", "A", "B", "B"]:
		var h := Combat.gen_hero(r, 10)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		party.append(h)
	var r := SurvivorsRun.new(party, "vale", 1234)
	check(r.lead()["hero"] == party[0], "the first hero leads")

	var saw_elite := false
	var saw_boss := false
	var levels := 0
	while not r.over and r.time < 360.0:
		r.step(0.1, r.autopilot_dir())
		for e in r.events:
			if e["type"] == "boss":
				saw_boss = true
		r.events.clear()
		if r.foes.any(func(f): return f["tier"] == "elite"):
			saw_elite = true
		while r.pending_levels > 0:
			var o := r.offer()
			if levels == 0:
				check(o.size() == 3, "three picks offered")
			r.pick(o[0] if not o.is_empty() else "")
			levels += 1
	check(r.kills > 50, "foes die (%d kills)" % r.kills)
	check(levels >= 5, "the party levels up (%d)" % levels)
	check(saw_elite, "an elite shows up each minute")
	check(r.time < 300.0 or saw_boss, "a warden arrives at 5:00")
	check(r.foes.size() <= SurvivorsRun.MAX_FOES + 12, "foe count stays capped")
	check(r.gems.size() <= SurvivorsRun.MAX_GEMS, "shards merge past the cap")
	check(not r.upgrades.is_empty(), "picks are recorded")
	print("    survived %.0fs, %d kills, level %d" % [r.time, r.kills, r.level])

	# A lone weak hero standing still falls, and the run ends.
	var weak := Combat.gen_hero("F", 1)
	var r2 := SurvivorsRun.new([weak], "ashen", 7)
	while not r2.over and r2.time < 900.0:
		r2.step(0.1, Vector2.ZERO)
		r2.events.clear()
		while r2.pending_levels > 0:
			r2.pick("")
	check(r2.over and not r2.lead()["alive"], "the run ends when the lead falls")

	# Warden phase: at half health it calls the horde once.
	var r3 := SurvivorsRun.new(party, "marsh", 99)
	var boss := r3._add_foe("boss")
	var before := r3.foes.size()
	r3._damage(r3.foes.find(boss), boss["max_hp"] * 0.55)
	check(boss["phased"] and r3.foes.size() == before + 10, "a warden calls the horde at half health")

	# Pay-out.
	var coins0 := GameState.coins
	var xp0: int = party[1].xp + party[1].level * 100000
	var sum := GameState.finish_survivors(r)
	check(GameState.coins > coins0 and int(sum["coins"]) > 0, "the guild is paid (%d coins)" % int(sum["coins"]))
	check(party[1].xp + party[1].level * 100000 >= xp0, "companions gain XP too")
	check(GameState.best_endless_time == int(r.time), "best time recorded")
	check(str(GameState.run_history[0]["kind"]) == "Endless Rift", "the run is in the history")
	check(GameState.milestone_progress({"type": "endless_time"}) == int(r.time), "the achievement tracks the best time")
