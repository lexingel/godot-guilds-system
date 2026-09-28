extends "res://tests/base_test.gd"
## Champions: each guild rolls 12 of the pool; the story frees three, the
## Endless Rift hides the rest (hold their light to free them). One oversees
## rift runs (Boon, Call), Echoes level them up, and in the Endless Rift they
## are the party. Old saves keep their gold-hired champions as heroes.


func run() -> void:
	seed(31)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	var roll := GameState.champion_roll.duplicate()
	check(roll.size() == GameData.CHAMPION_ROLL and roll.all(func(i): return GameData.CHAMPIONS.has(i)), "a new guild rolls %d champions from the pool" % GameData.CHAMPION_ROLL)
	var uniq := {}
	for i in roll:
		uniq[i] = true
	check(uniq.size() == roll.size(), "no champion twice")
	GameState.reset()
	GameState.guild_name = "T"
	check(GameState.champion_roll != roll, "the next guild meets a different set")
	check(GameState.champions.is_empty() and GameState.overseer == "", "nobody is freed at the start")

	# Every champion in the pool is complete: art, a Boon the stat code
	# knows, and a Call both combat and the Endless Rift can play.
	var bad: Array = []
	for id in GameData.CHAMPIONS:
		var d: Dictionary = GameData.CHAMPIONS[id]
		if not ResourceLoader.exists("res://assets/champions/%s.png" % id):
			bad.append(id + ": portrait")
		if Combat.describe_skill(str(d["boon"]["kind"]), float(d["boon"]["value"])) == "":
			bad.append(id + ": boon")
		if not SurvivorsRun.ABILITY_STYLE.has(str(d["call"]["effect"])) or not GameData.ABILITY_EFFECT_ICON.has(str(d["call"]["effect"])):
			bad.append(id + ": call")
		if GameData.find_role(str(d["role"])).is_empty():
			bad.append(id + ": role")
	check(bad.is_empty(), "every champion has art, a Boon and a Call %s" % [bad])
	check(GameData.CHAMPIONS.size() >= 20, "a pool of %d" % GameData.CHAMPIONS.size())

	var ids: Array[String] = []
	for r in ["D", "C"]:
		var h := Combat.gen_hero(r, 6)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)

	# The story frees the first three.
	var first := GameState.story_champion(1)
	GameState.pending_stories.clear()
	GameState._complete_act(1)
	check(GameState.champion_unlocked(first) and GameState.overseer == first, "Act I frees %s, who takes up overseeing" % first)
	check(GameState.pending_stories.any(func(c): return str(c.get("subtitle", "")) == GameData.champion_full_name(first)), "with a story card")
	check(GameState.lost_champions().size() == GameData.CHAMPION_ROLL - GameData.CHAMPION_STORY_ACTS, "the rest are lost in the Endless Rift")

	# Overseeing: the Boon during a run, the Call for any hero.
	var b: Dictionary = GameData.champion_def(first)["boon"]
	check(GameState.champion_boon(str(b["kind"])) == 0.0, "no Boon outside a run")
	GameState.start_run("lesser", ids, null)
	check(GameState.run_overseer() == first, "the run remembers its overseer")
	check(is_equal_approx(GameState.champion_boon(str(b["kind"])), float(b["value"])), "the Boon applies at level 1")
	var h0: Hero = GameState.find_hero(ids[0])
	check(Combat.hero_skill_sources(h0, str(b["kind"])).any(func(p): return p[0] == "Champion Boon"), "the Boon shows in the stat breakdown")
	check(GameState.champion_call_ready(h0) and GameState.champion_calls_left() == 1, "any hero can use the Call, once a rift at level 1")
	GameState.run["node_state"] = {}
	GameState.choose_node_type("combat")
	GameState.engage_node()
	var state: Dictionary = GameState.run["node_state"]["combat_state"]
	for m in state["monsters"]:
		m["hp"] = 9999.0
		m["max_hp"] = 9999.0
		m["dmg"] = 1.0
	var used := false
	for step in 30:
		if GameState.run["node_state"].has("result") or used:
			break
		var nxt := Combat.peek_next_turn(state)
		if str(nxt["type"]) == "hero":
			var log0 := (state["log"] as Array).size()
			GameState.set_hero_action(str(nxt["id"]), "call")
			GameState.resolve_turn_now()
			var call_name := str(GameState.champion_call()["name"])
			used = (state["log"] as Array).slice(log0).any(func(l): return str(l).contains(call_name))
			continue
		GameState.resolve_turn_now()
	check(used and not GameState.champion_call_ready(), "the Call fires and is spent")
	GameState.save()
	GameState.load_save()
	check(GameState.run_overseer() == first and not GameState.champion_call_ready(), "overseer and spent Call survive a reload")
	GameState.run = {}

	# Echoes level a champion: stronger Boon and Call, a second Call at 3.
	check(GameState.level_champion(first) != "", "no Echoes, no level")
	GameState.echoes = 1000
	check(GameState.level_champion(first) == "" and GameState.champion_level(first) == 2, "Echoes buy a level")
	check(GameState.echoes == 1000 - int(GameData.CHAMPION_LEVEL_COST[1]), "for %d Echoes" % GameData.CHAMPION_LEVEL_COST[1])
	GameState.level_champion(first)
	GameState.start_run("lesser", ids, null)
	check(is_equal_approx(GameState.champion_boon(str(b["kind"])), float(b["value"]) * GameData.champion_power(3)), "the Boon grows with level")
	check(GameState.champion_calls_left() == 2, "two Calls a rift from level 3")
	GameState.run = {}
	for i in 5:
		GameState.level_champion(first)
	check(GameState.champion_level(first) == GameData.CHAMPION_LEVEL_MAX and GameState.champion_level_cost(first) == -1, "levels stop at %d" % GameData.CHAMPION_LEVEL_MAX)

	# The Endless Rift: champions as fighters, a lost one's light, the pay-out.
	var fighter := GameState.champion_hero(first)
	check(fighter.is_champion and GameData.portrait_for_hero(fighter.cls_id, fighter.pool_id) == GameData.champion_portrait(first), "a champion fights under their own portrait")
	var lost_id := str(GameState.lost_champions()[0][0])
	var r := SurvivorsRun.new([fighter], "vale", 7)
	check(bool(r.heroes[0]["has_ability"]) and str(r.heroes[0]["ability_name"]) == str(GameState.champion_call_of(first)["name"]), "their Call is their signature move")
	r.lost = [[lost_id, 5]]
	r.step(0.1, Vector2.ZERO)
	check(r.beacon.is_empty(), "no light before its depth")
	r.time = 5.0
	r.step(0.1, Vector2.ZERO)
	check(not r.beacon.is_empty() and str(r.beacon["id"]) == lost_id, "a lost champion's light appears")
	r.foes.clear()
	for k in 200:
		r.heroes[0]["pos"] = r.beacon["pos"]
		r.heroes[0]["hp"] = r.heroes[0]["max_hp"]
		r.foes.clear()
		r._tick_beacon(0.1)
		if r.beacon.is_empty():
			break
	check(r.rescued == [lost_id], "standing in it for %d s frees them" % int(GameData.BEACON_HOLD))
	var day0 := GameState.day
	var e0 := GameState.echoes
	var sum := GameState.finish_survivors(r)
	check(GameState.champion_unlocked(lost_id) and (sum["freed"] as Array).size() == 1, "a freed champion joins after the run")
	check(GameState.echoes > e0 and int(sum["echoes"]) > 0, "the run pays Echoes")
	check(GameState.day == day0 + 1, "an Endless run costs the guild a day")

	# Saves: the roll and the champions persist; an old save's hired
	# champion stays on as a hero.
	var roll_now := GameState.champion_roll.duplicate()
	GameState.save()
	GameState.load_save()
	check(GameState.champion_roll == roll_now and GameState.champion_unlocked(lost_id) and GameState.champion_level(first) == GameData.CHAMPION_LEVEL_MAX, "champions survive a save")
	var old: Dictionary = JSON.parse_string(GameState.export_save_text())
	old.erase("champion_roll")
	old.erase("champions")
	var hd: Dictionary = (old["heroes"] as Array)[0]
	hd["is_champion"] = true
	check(GameState.import_save_text(JSON.stringify(old), 9) == "" and GameState.load_save(), "an old save loads")
	check(GameState.heroes.all(func(x): return not x.is_champion) and GameState.champion_roll.size() == GameData.CHAMPION_ROLL, "hired champions stay as heroes; the guild gets a roll")
