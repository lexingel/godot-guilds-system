extends "res://tests/base_test.gd"
## Biomes, armor, wind-ups/heavy blows/stun, burn and chill.


func _party(n: int) -> Array[String]:
	var ids: Array[String] = []
	for i in n:
		var h := Combat.gen_hero("C", 6)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	return ids


func _fight(ids: Array[String]) -> Dictionary:
	GameState.run["node_state"] = {}
	GameState.choose_node_type("combat")
	GameState.engage_node()
	return GameState.run["node_state"]["combat_state"]


func run() -> void:
	seed(12)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	GameState.runs_started = 3
	var ids := _party(3)
	# Biomes follow the campaign.
	check(GameState.pick_biome() == "vale", "Act I rifts are in the Vale")
	GameState.campaign_act = 3
	var seen := {}
	for i in 40:
		seen[GameState.pick_biome()] = true
	check(seen.size() == 3, "Act III rifts roll every biome")
	GameState.start_run("lesser", ids, null)
	GameState.run["biome"] = "ashen"
	var d := GameState._diff()
	var pool: Array = GameData.BIOMES["ashen"]["monsters"]
	var all_in := true
	for i in 30:
		if not pool.has(Combat.gen_monster(d, 1, "combat")["name"]):
			all_in = false
	check(all_in, "foes come from the run's biome")
	check(GameData.BIOMES["ashen"]["elites"].has(Combat.gen_monster(d, 1, "elite")["name"]), "elites from the biome too")
	GameState.run["node_state"] = {}
	GameState.ensure_combat_bg()
	check(GameData.BIOMES["ashen"]["backgrounds"].has(int(GameState.run["node_state"]["bg_idx"])), "arena from the biome")

	# Armor: basic attacks lose a share, and each hit sunders it.
	var st := _fight(ids)
	var m: Dictionary = st["monsters"][0]
	m["hp"] = 99999.0; m["max_hp"] = 99999.0; m["armor"] = 0.4
	st["escort"] = {}   # an escort can soak a foe's turn; keep these checks exact
	for other in (st["monsters"] as Array).slice(1):
		other["hp"] = 0.0
	var h0: Hero = (st["party"] as Array).filter(func(h): return not h.is_champion)[0]
	st["pending_actions"][h0.id] = {"action": "attack", "target": 0}
	var before: float = m["hp"]
	Combat._resolve_hero_action(st, h0)
	check((st["log"] as Array).any(func(l): return str(l).contains("armor turns aside")), "armor blocks part of a basic attack")
	check(is_equal_approx(float(m["armor"]), 0.4 - GameData.ARMOR_SUNDER), "the hit chips the armor")
	check(float(m["hp"]) < before, "the rest still lands")

	# Wind-up: the intent warns, the next hit is heavy and stuns.
	m["_winding"] = true
	st["intents"] = {0: h0.id}
	var it := Combat.monster_intent(st, 0)
	check(it.get("charging", false) and int(it["dmg"]) == 0, "winding foe's intent shows it charging")
	var hp0 := h0.hp
	Combat._resolve_monster_action(st, 0)
	check(h0.hp == hp0 and m.get("_charged", false), "the wind-up turn deals nothing, charges the blow")
	it = Combat.monster_intent(st, 0)
	check(it.get("heavy_blow", false) and int(it["dmg"]) >= int(Combat._monster_hit(m, 1) * 2.0), "next intent is a heavy blow")
	for ph in st["party"]:
		ph.hp = Combat.max_hp(ph) * 10   # whoever takes it survives it
	st["_defending"] = {}
	st["dodge"] = 0.0
	# A dodge avoids the blow entirely, so retry until one lands.
	for attempt in 12:
		Combat._resolve_monster_action(st, 0)
		if not st.get("_stunned", {}).is_empty():
			break
		m["_charged"] = true
	# (An ally's intercept effect may take the blow instead — whoever is hit is stunned.)
	var stunned_ids: Array = st.get("_stunned", {}).keys()
	check(stunned_ids.size() == 1, "an undefended heavy blow stuns whoever it hits")
	var victim: Hero = Combat._find_party_hero(st["party"], str(stunned_ids[0])) if not stunned_ids.is_empty() else h0
	check(not m.get("_charged", false) and int(m.get("_windup_cd", 0)) == 1, "blow spent, a round before the next wind-up")
	# A stunned hero loses the turn.
	st["turn_order"] = [{"type": "hero", "id": victim.id, "_spd": 10.0}]
	st["turn_idx"] = 0
	st["pending_actions"][victim.id] = {"action": "attack", "target": 0}
	var mhp: float = m["hp"]
	Combat.resolve_turn(st)
	check(float(m["hp"]) == mhp and not st["_stunned"].has(victim.id), "stunned hero skips a turn, then recovers")
	# Defending blocks the stun.
	m["_charged"] = true
	var everyone := {}
	for ph in st["party"]:
		everyone[ph.id] = true
	st["_defending"] = everyone
	Combat._resolve_monster_action(st, 0)
	check(st.get("_stunned", {}).is_empty(), "Defending prevents the stun")
	st["_defending"] = {}

	# Burn ticks at round end; a tonic cleanses it.
	h0.hp = Combat.max_hp(h0)
	st["hero_burn"] = {h0.id: {"rounds": 2, "value": 0.1}}
	st["mend"] = 0.0   # no mending over the tick
	var hb := h0.hp
	Combat._end_round_effects(st)
	check(h0.hp < hb and int(st["hero_burn"][h0.id]["rounds"]) == 1, "burn ticks")
	GameState.tonics = {"healing": 1}
	st["pending_actions"][h0.id] = {"action": "tonic", "target": 0, "ally": h0.id}
	Combat._resolve_hero_action(st, h0)
	check(not st["hero_burn"].has(h0.id), "a tonic puts out the burn")
	# Chill makes a hero act late.
	var fast: Hero = h0
	st["_chilled"] = {fast.id: 2}
	var order := Combat._compute_turn_order(st)
	var plain := Combat.spd_of(fast)
	var entry: Dictionary = order.filter(func(e): return str(e["id"]) == fast.id)[0]
	check(float(entry["_spd"]) < plain * 0.6, "chilled hero's speed is halved in the turn order")
	GameState.run = {}

	# A finale fights in its act's biome.
	GameState.campaign_act = 2
	GameState.quest_tally["greater_seals"] = 2
	GameState.reputation = 20
	GameState.best_rift_rank_sealed = 3
	GameState.start_finale(ids, null)
	check(GameState.run_biome() == "marsh", "the Act II finale is in the Marshes")
	GameState.run = {}

	# Auto policy and Quick fight.
	GameState.campaign_act = 1
	GameState.start_run("lesser", ids, null)
	var st2 := _fight(ids)
	var ha: Hero = (st2["party"] as Array).filter(func(h): return not h.is_champion)[0]
	st2["monsters"][0]["_charged"] = true
	st2["monsters"][0]["_winding"] = false   # a random wind-up roll would mask the blow
	st2["intents"] = {0: ha.id}
	st2["turn_order"] = []
	st2["turn_idx"] = 0
	check(str(Combat.auto_action(st2, ha)["action"]) == "defend", "auto Defends against a heavy blow aimed at it")
	st2["monsters"][0]["_charged"] = false
	st2["momentum"] = 0   # nothing to spend
	check(str(Combat.auto_action(st2, ha)["action"]) == "attack", "auto attacks otherwise")
	GameState.run["node_state"] = {}
	GameState.choose_node_type("combat")
	GameState.quick_fight()
	check(GameState.run["node_state"].has("result"), "Quick fight plays the whole fight out")
	GameState.run = {}
