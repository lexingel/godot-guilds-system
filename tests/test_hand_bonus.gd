extends "res://tests/base_test.gd"
## Playing by hand: a fight won with no Auto and no hero down pays extra Gold.


func _fight(auto: bool, kind: String = "combat") -> Dictionary:
	GameState.run["node_state"] = {}
	GameState.choose_node_type(kind)
	GameState.engage_node()
	var state: Dictionary = GameState.run["node_state"]["combat_state"]
	if auto:
		state["auto_used"] = true
	for step in 200:
		if GameState.run["node_state"].has("result"):
			break
		GameState.resolve_turn_now()
	return GameState.run["node_state"].get("result", {})


func run() -> void:
	seed(4321)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	var ids: Array[String] = []
	for r in ["A", "A", "A"]:
		var h := Combat.gen_hero(r, 30)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	GameState.runs_started = 3   # past the training rift
	GameState.start_ladder_rift("F", ids, null)   # nothing sealed yet: the frontier
	var res := _fight(false, "elite")   # (this party is Favored on F, so its regular fights don't pay it)
	check(res.get("won", false), "the strong party wins")
	var coins_before := GameState.coins
	check(int(res.get("hand_bonus", 0)) > 0, "a flawless fight played by hand pays a bonus (%d)" % int(res.get("hand_bonus", 0)))
	check(int(res.get("hand_bonus_ess", 0)) > 0, "and the same share of its Essence (%d)" % int(res.get("hand_bonus_ess", 0)))
	for h in GameState.heroes:
		h.hp = Combat.max_hp(h)
	var res2 := _fight(true, "elite")
	check(res2.get("won", false) and int(res2.get("hand_bonus", 0)) == 0, "no bonus once Auto played a turn")
	check(GameState.coins >= coins_before, "gold only goes up")
	for h in GameState.heroes:
		h.hp = Combat.max_hp(h)
	GameState.run["node_state"] = {}
	GameState.choose_node_type("combat")
	GameState.quick_fight()
	var res3: Dictionary = GameState.run["node_state"].get("result", {})
	check(res3.get("won", false) and int(res3.get("hand_bonus", 0)) == 0, "Quick fight is auto play: no hand bonus")
	# Once the rank is sealed, only its elites and bosses pay the bonus.
	GameState.best_rift_rank_sealed = 0
	for h in GameState.heroes:
		h.hp = Combat.max_hp(h)
	var res4 := _fight(false)
	check(res4.get("won", false) and int(res4.get("hand_bonus", 0)) == 0, "no bonus for a regular fight on a sealed rank")
	for h in GameState.heroes:
		h.hp = Combat.max_hp(h)
	var res5 := _fight(false, "elite")
	check(res5.get("won", false) and int(res5.get("hand_bonus", 0)) > 0, "an elite still pays it")

	# Quick fight is earned per rank: open on a sealed rank, not on a new one
	# (unless the party is Favored there) or a finale.
	GameState.finish_run()
	var weak := Combat.gen_hero("F", 1)
	weak.id = "weak"
	GameState.heroes.append(weak)
	var weak_ids: Array[String] = ["weak"]
	GameState.best_rift_rank_sealed = GameData.rift_rank_index("D")
	GameState.start_ladder_rift("D", weak_ids, null)
	check(GameState.quick_fight_lock() == "", "Quick fight on a rank you've sealed")
	GameState.finish_run()
	GameState.start_ladder_rift("C", weak_ids, null)
	check(GameState.quick_fight_lock() != "", "not on a rank you haven't sealed yet")
	GameState.finish_run()
	GameState.start_ladder_rift("C", ids, null)
	check(GameState.quick_fight_lock() == "", "unless the party is Favored there")
	GameState.finish_run()
	GameState.run = {"finale": 1, "rift_rank": ""}
	check(GameState.quick_fight_lock() != "", "nor in a finale")
	GameState.run = {}

	# Auto stops for a hero about to fall.
	GameState.start_run("lesser", ids, null)
	GameState.run["node_state"] = {}
	GameState.choose_node_type("combat")
	GameState.engage_node()
	var st: Dictionary = GameState.run["node_state"]["combat_state"]
	# A known round: every foe alive, none has acted, each aims a plain attack
	# at the first hero (an opening volley or a rolled Ward made this flaky).
	st["turn_idx"] = 0
	st["_m_stunned"] = {}
	var aim: Hero = st["party"][0]
	for mi in (st["monsters"] as Array).size():
		var m: Dictionary = st["monsters"][mi]
		m["hp"] = 999.0
		m["max_hp"] = 999.0
		m["dmg"] = 1.0
		m["_winding"] = false
		m["_charged"] = false
		st["intents"][mi] = {"kind": "attack", "target": aim.id}
	check(Combat.hero_about_to_fall(st) == null, "no pause while nobody is in danger")
	check(not Combat.incoming_hits(st).is_empty(), "the foes' intents show who they're hitting")
	for x in st["party"]:
		x.hp = 1
	check(Combat.hero_about_to_fall(st) != null, "a hit that would drop a hero is spotted")
	GameState.finish_run()

	# A foe can't be stunned round after round; a boss shrugs off a stun.
	var sst := {"round_num": 3, "log": [] as Array[String], "monsters": [{"name": "Wolf", "hp": 10.0, "tier": "combat"}]}
	check(Combat.stun_monster(sst, 0, 1), "a stun takes")
	check(not Combat.stun_monster(sst, 0, 1), "not twice in a round")
	sst["round_num"] = 4
	check(not Combat.stun_monster(sst, 0, 1), "nor the next round")
	sst["round_num"] = 5
	check(Combat.stun_monster(sst, 0, 1), "but again a round later")

	# Fixed Legendary relics don't take Essence for a level; old levels are refunded.
	var coin := Combat.relic_from_unique(GameData.UNIQUE_RELICS.filter(func(d): return d["id"] == "gamblers_coin")[0])
	GameState.relics.append(coin)
	GameState.crystals = 1000
	check(not GameState.relic_levels_up(coin) and GameState.upgrade_relic(coin.id) != "" and GameState.crystals == 1000, "a fixed Legendary relic can't be levelled")
	coin.level = 3
	GameState.save()
	GameState.load_save()
	var back: Relic = GameState.relics.filter(func(r): return r.unique_id == "gamblers_coin")[0]
	check(back.level == 1 and GameState.crystals > 1000, "levels already bought on one are refunded (%d Essence)" % (GameState.crystals - 1000))
