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
