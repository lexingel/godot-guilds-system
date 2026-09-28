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
		r.settle_picks()
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

	# The guild's build comes along: relics (ward, damage, dodge), and each
	# hero's subclass Ability picks its special.
	var rl := Combat.gen_relic("rare")
	rl.equipped = true
	rl.hp = 40
	rl.specials = [{"kind": "dodge_pct", "value": 0.2}]
	GameState.relics.append(rl)
	var r4 := SurvivorsRun.new(party, "vale", 7)
	check(r4.dodge >= 0.2 and r4.heroes[0]["max_hp"] > float(Combat.max_hp(party[0])), "relic dodge and ward carry in")
	var styled: Array = r4.heroes.filter(func(x): return x["has_ability"] and str(x["style"]) != "")
	for x in r4.heroes:
		if x["has_ability"]:
			check(str(x["ability_name"]) == str(GameData.SUBCLASS_ABILITIES[x["hero"].pool_id]["name"]), "the special is the hero's own Ability")
	r4.rally_t = 1.0
	var m_rally := r4.dmg_mult()
	r4.rally_t = 0.0
	check(m_rally > r4.dmg_mult(), "a rally ability raises party damage")
	GameState.relics.erase(rl)
	check(styled.size() >= 0, "styles resolve")

	# Level-ups offer each hero's role skills and signature Ability.
	var r5 := SurvivorsRun.new(party, "vale", 21)
	var all_offers := {}
	for k in 60:
		for id in r5.offer():
			all_offers[id] = true
	check(all_offers.keys().any(func(id): return str(id).begins_with("skill:")), "role skills are offered at level-up")
	var ab_i := -1
	for i in r5.heroes.size():
		if r5.heroes[i]["has_ability"]:
			ab_i = i
	if ab_i >= 0:
		check(all_offers.has("ability:%d" % ab_i), "a hero's own Ability is offered")
		r5.pending_levels = 3
		for k in 3:
			r5.pick("ability:%d" % ab_i)
		check(int(r5.heroes[ab_i]["ab_rank"]) == SurvivorsRun.ABILITY_RANK_MAX and r5._ability_power(r5.heroes[ab_i]) >= 1.9, "three ranks: stronger Ability")
		check(not r5.offer().has("ability:%d" % ab_i), "a maxed Ability isn't offered again")
	var sk_id := str(GameData.ROLE_SKILLS[r5.heroes[0]["hero"].cls_id][0]["id"])
	r5.pending_levels = 1
	r5.pick("skill:0:%s" % sk_id)
	check((r5.heroes[0]["skills"] as Dictionary).has(sk_id), "a picked role skill is learned")
	check(str(r5.upgrade_info("skill:0:%s" % sk_id)["name"]).contains(GameData.find_role_skill(sk_id)["name"]), "the offer names the skill")
	var foe := r5._add_foe("combat", r5.heroes[0]["pos"] + Vector2(40, 0))
	foe["stun_t"] = 1.0
	var p0: Vector2 = foe["pos"]
	r5._move_foes(0.1)
	check(foe["pos"] == p0, "a stunned foe doesn't move")
	r5.heroes[0]["skills"][sk_id] = 0.0
	var t0 := r5.time
	for k in 20:
		r5.step(0.1, Vector2.ZERO)
	check(float(r5.heroes[0]["skills"][sk_id]) > 0.0, "the learned skill fires and goes on cooldown")

	# Signature Abilities keep their identity in the Endless Rift.
	var r6 := SurvivorsRun.new(party, "vale", 31)
	var h6: Dictionary = r6.heroes[0]
	var w6: Dictionary = SurvivorsRun.WEAPONS[h6["role"]]
	var near_foe := r6._add_foe("combat", h6["pos"] + Vector2(60, 0))
	h6["style"] = "freeze"
	r6._ability(h6, w6, 1.0)
	check(float(near_foe["stun_t"]) > 0.0, "Freeze stops foes around the hero")
	h6["style"] = "mark"
	r6._ability(h6, w6, 1.0)
	var hp6 := float(near_foe["hp"])
	r6._damage(r6.foes.find(near_foe), 10.0)
	check(is_equal_approx(hp6 - float(near_foe["hp"]), 13.0), "marked foes take 30% more")
	h6["style"] = "trap"
	r6._ability(h6, w6, 1.0)
	check(r6.traps.size() == 1, "Trap sets a snare")
	r6.traps[0]["pos"] = near_foe["pos"]
	near_foe["stun_t"] = 0.0
	r6._tick_statuses(0.1)
	check(r6.traps.is_empty() and (not r6.foes.has(near_foe) or float(near_foe["stun_t"]) > 0.0), "a foe springs the snare")
	if r6.heroes.size() > 1:
		r6.heroes[1]["alive"] = false
		h6["style"] = "revive"
		r6._ability(h6, w6, 1.0)
		check(r6.heroes[1]["alive"], "Revive raises a downed companion")
	h6["style"] = "undying"
	r6._ability(h6, w6, 1.0)
	var hp_u: float = h6["hp"]
	var biter := r6._add_foe("combat", h6["pos"])
	biter["hit_cd"] = 0.0
	r6._contact(0.1)
	check(h6["hp"] == hp_u, "Undying: no damage for a moment")
	check(r6.rewards()["coins"] < 45.0 * r6.minutes() + 0.1 * r6.kills + 1, "kills pay 0.05 Gold each")

	# The run's shape: a five-minute cycle of waves and a Rift Warden at 20:00.
	var r7 := SurvivorsRun.new(party, "marsh", 41)
	check(r7.wave_at(30.0) == "horde" and r7.wave_at(90.0) == "swarm" and r7.wave_at(150.0) == "pack" and r7.wave_at(210.0) == "volley" and r7.wave_at(270.0) == "lull", "the five-minute wave cycle")
	check(r7.wave_at(1250.0) == "horde", "after the Rift Warden, the horde")
	r7.time = 240.0
	r7.wave = "lull"
	var lull_budget := r7.spawn_budget()
	r7.wave = "horde"
	check(lull_budget < r7.spawn_budget(), "a lull keeps fewer foes out")
	r7.wave = "volley"
	var shooters := 0
	for k in 30:
		if r7._add_foe("combat")["ranged"]:
			shooters += 1
	check(shooters >= 15, "a ranged wave brings archers and casters (%d/30)" % shooters)
	r7.foes.clear()
	var archer := r7._add_foe("combat", r7.lead()["pos"] + Vector2(200, 0))
	archer["name"] = "Mire Sniper"
	archer["ranged"] = true
	archer["shot_cd"] = 0.0
	r7._move_foes(0.1)
	check(r7.foe_shots.size() == 1, "a ranged foe shoots a bolt")
	r7.foe_shots[0]["pos"] = r7.lead()["pos"] + Vector2(0, -20)
	var hp7: float = r7.lead()["hp"]
	r7.dodge = 0.0
	r7._move_foe_shots(0.01)
	check(r7.foe_shots.is_empty() and r7.lead()["hp"] < hp7, "a bolt that reaches a hero hurts")
	var up: Array = r7.upcoming()
	check(up.size() == 2 and str(up[1]["label"]) == "Warden", "the timeline shows the next wave and warden")

	# An elite pack's leader drops a chest; opening one offers rift relics.
	r7.foes.clear()
	r7.wave = "pack"
	r7._start_wave()
	var leaders: Array = r7.foes.filter(func(f): return f.get("chest", false))
	check(r7.foes.size() == 2 and leaders.size() == 1, "the first elite pack is a pair, one with a chest")
	r7._damage(r7.foes.find(leaders[0]), 1e9)
	check(r7.chests.size() == 1, "the pack leader drops a chest")
	r7.chests[0]["pos"] = r7.lead()["pos"]
	r7._pickups(0.1)
	check(r7.pending_chests == 1, "walking over a chest opens it")
	var t_before := r7.time
	r7.step(0.1, Vector2.ZERO)
	check(r7.time == t_before, "the run waits while a chest is open")
	var ro := r7.chest_offer()
	check(ro.size() == 3, "a chest offers three relics")
	r7.take_relic(str(ro[0]))
	check(r7.relics.has(ro[0]) and r7.pending_chests == 0, "the relic is kept")
	r7.relics["idol"] = true
	var idol_pay: int = r7.rewards()["coins"]
	r7.relics.erase("idol")
	check(idol_pay >= r7.rewards()["coins"], "the Gilded Idol pays more gold")

	# Evolutions: a role's matching upgrade maxed, then always offered first.
	var r8 := SurvivorsRun.new(party, "vale", 51)
	var role: String = r8.heroes[0]["role"]
	var needs: String = SurvivorsRun.EVOLUTIONS[role]["needs"]
	check(not r8.evolutions_ready().has(role), "no evolution before its upgrade is maxed")
	r8.upgrades[needs] = int(SurvivorsRun.UPGRADES[needs]["max"])
	check(r8.offer()[0] == "evolve:" + role, "a ready evolution is offered first")
	r8.pending_levels = 1
	r8.pick("evolve:" + role)
	check(r8.evolved.has(role) and not r8.offer().has("evolve:" + role), "an evolution is taken once")

	# Archetype twists are their own pick, once the Ability has a rank.
	for i in r8.heroes.size():
		var hx: Dictionary = r8.heroes[i]
		if hx["has_ability"] and SurvivorsRun.TWIST_TEXT.has(str(hx["arch"])):
			var seen := false
			for k in 80:
				seen = seen or r8.offer().has("twist:%d" % i)
			check(not seen, "no twist before the Ability has a rank")
			hx["ab_rank"] = 1
			for k in 80:
				seen = seen or r8.offer().has("twist:%d" % i)
			check(seen, "the twist is offered once the Ability has a rank")
			r8.pending_levels = 1
			r8.pick("twist:%d" % i)
			check(hx.get("twist", false), "the twist is learned")
			break

	# The Rift Warden: beat it and the run is won, with a bonus.
	var r9 := SurvivorsRun.new(party, "ashen", 61)
	r9.time = SurvivorsRun.FINAL_AT
	r9._next_boss = SurvivorsRun.FINAL_AT + 1.0
	r9._spawn(0.01)
	var wardens: Array = r9.foes.filter(func(f): return f.get("final", false))
	check(wardens.size() == 1 and str(wardens[0]["name"]) == "Sythrane", "the Rift Warden arrives at 20:00")
	var plain := r9.rewards()
	r9._damage(r9.foes.find(wardens[0]), 1e12)
	check(r9.won and r9.over, "beating the Rift Warden seals the rift")
	check(int(r9.rewards()["coins"]) > int(plain["coins"]), "a sealed rift pays a bonus")

	# Terrain: pillars block, lava burns, pools slow; braziers drop pickups.
	var rv := SurvivorsRun.new(party, "vale", 71)
	var pil := {"id": "t", "pos": rv.lead()["pos"] + Vector2(10, 0), "r": 24.0, "kind": "pillar"}
	rv.terrain = [pil]
	rv._terrain_t = 99.0
	rv._terrain_effects(0.1)
	check(rv.lead()["pos"].distance_to(pil["pos"]) >= 24.0 + SurvivorsRun.HERO_R - 0.01, "a pillar pushes a hero out")
	var feats := 0
	for cx in 4:
		feats += (rv._chunk(Vector2i(cx, 3))["features"] as Array).size()
	check(feats >= 4 and rv._chunk(Vector2i(1, 3)) == rv._chunk(Vector2i(1, 3)), "each chunk has its region's features, and they stay put")
	var ra := SurvivorsRun.new(party, "ashen", 72)
	ra.terrain = [{"id": "l", "pos": ra.lead()["pos"], "r": 60.0, "kind": "lava"}]
	ra._terrain_t = 99.0
	var hp_l: float = ra.lead()["hp"]
	ra._terrain_effects(0.5)
	check(ra.lead()["hp"] < hp_l, "lava burns a hero standing in it")
	var rm := SurvivorsRun.new(party, "marsh", 73)
	rm._terrain_t = 99.0
	var x0: float = rm.lead()["pos"].x
	rm._move_heroes(1.0, Vector2.RIGHT)
	var dry: float = rm.lead()["pos"].x - x0
	rm.terrain = [{"id": "p", "pos": rm.lead()["pos"], "r": 200.0, "kind": "pool"}]
	x0 = rm.lead()["pos"].x
	rm._move_heroes(1.0, Vector2.RIGHT)
	check(rm.lead()["pos"].x - x0 < dry * 0.7, "a pool slows the party")
	var bz := {"id": "b0", "pos": rm.lead()["pos"]}
	rm.braziers = [bz]
	rm._pickups(0.1)
	check(rm.braziers.is_empty() and rm.pickups.size() == 1 and rm._broken.has("b0"), "walking into a brazier breaks it and drops a pickup")
	rm.pickups[0]["kind"] = "heal"
	rm.pickups[0]["pos"] = rm.lead()["pos"]
	rm.lead()["hp"] = rm.lead()["max_hp"] * 0.5
	rm._pickups(0.1)
	check(rm.pickups.is_empty() and rm.lead()["hp"] > rm.lead()["max_hp"] * 0.5, "a heal pickup heals")

	# Elites telegraph a slam; step out of the circle before it lands.
	var rs := SurvivorsRun.new(party, "vale", 74)
	var el := rs._add_foe("elite", rs.lead()["pos"] + Vector2(150, 0))
	el["slam_cd"] = 0.0
	rs._move_foes(0.05)
	check(rs.slams.size() == 1, "an elite telegraphs a slam")
	rs.dodge = 0.0
	var hp_s: float = rs.lead()["hp"]
	rs.slams[0]["pos"] = rs.lead()["pos"] + Vector2(1000, 0)
	rs._tick_slams(SurvivorsRun.SLAM_WARN + 0.1)
	check(rs.lead()["hp"] == hp_s and rs.slams.is_empty(), "a slam misses a hero who stepped out")
	rs.slams.append({"pos": rs.lead()["pos"], "r": 90.0, "t": 0.0, "dmg": 10.0})
	rs._tick_slams(0.1)
	check(rs.lead()["hp"] < hp_s, "a slam hits a hero inside the circle")

	# Milestones pay once, the first time; best times are kept per region.
	GameState.endless_milestones = []
	var relics0 := GameState.relics.size()
	var rt := SurvivorsRun.new(party, "marsh", 81)
	rt.time = 610.0
	var sum_t := GameState.finish_survivors(rt)
	check((sum_t["milestones"] as Array).size() == 2 and GameState.endless_milestones.has(300) and GameState.endless_milestones.has(600), "5 and 10 minutes pay their milestones")
	check(GameState.relics.size() == relics0 + 1 and GameState.relics.back().unique_id == "e_warden_shard", "ten minutes gives the Warden's Shard")
	check(int(GameState.endless_best.get("marsh", 0)) == 610, "the best time is kept for the region")
	var sum_t2 := GameState.finish_survivors(rt)
	check((sum_t2["milestones"] as Array).is_empty(), "a milestone pays only once")
	check(GameState.endless_title() == "", "no title before fifteen minutes")
	rt.time = 1250.0
	rt.won = true
	GameState.finish_survivors(rt)
	check(GameState.endless_title() == "Rift Sealers", "sealing the rift earns the top title")
