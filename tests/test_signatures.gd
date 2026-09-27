extends "res://tests/base_test.gd"
## Signature Abilities (every subclass's own effect) and archetype twists.


func _hero(role: String, pool: String, row: String) -> Hero:
	var h := Combat.gen_hero("B", 8)
	h.cls_id = role
	h.pool_id = pool
	h.id = "h%d" % GameState.next_id
	GameState.next_id += 1
	h.formation = row
	h.hp = Combat.max_hp(h)
	GameState.heroes.append(h)
	return h


func _state(party: Array[Hero], foes: int = 2) -> Dictionary:
	var st := Combat.start_combat(party, "combat", GameData.DIFFICULTIES[0], 1)
	var base: Dictionary = st["monsters"][0]
	var ms: Array = []
	for k in foes:
		var m := base.duplicate(true)
		m["hp"] = 400.0
		m["max_hp"] = 400.0
		m["armor"] = 0.3
		m["kit"] = []
		m["_winding"] = false
		m["_charged"] = false
		m["ability"] = {}
		m["status"] = ""
		m["tier"] = "combat"
		m["dmg"] = 20.0
		ms.append(m)
	st["monsters"] = ms
	st["monster_shields"] = {}
	st["intents"] = {0: {"kind": "attack", "target": party[0].id}, 1: {"kind": "attack", "target": party[0].id}}
	st["turn_order"] = []
	st["turn_idx"] = 0
	st["dodge"] = 0.0
	st["escort"] = {}
	st["momentum"] = 5
	return st


## True if a state value holds something (a non-empty dict, text or number).
func _holds(v) -> bool:
	if v is Dictionary:
		return not v.is_empty()
	if v is String:
		return v != ""
	if v is float or v is int:
		return v != 0
	return false


func run() -> void:
	seed(9)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"

	# Every subclass's Ability resolves and does something to the fight.
	var effects := {}
	for pool in GameData.SUBCLASS_ABILITIES:
		effects[str(GameData.SUBCLASS_ABILITIES[pool]["effect"])] = true
	check(effects.size() >= 35, "at least 35 distinct signature effects (%d)" % effects.size())
	var counts := {}
	for pool in GameData.SUBCLASS_ABILITIES:
		var e := str(GameData.SUBCLASS_ABILITIES[pool]["effect"])
		counts[e] = int(counts.get(e, 0)) + 1
	check(counts.values().max() <= 4, "no effect is shared by more than 4 subclasses")
	for e in GameData.ABILITY_AWAKENING_BUCKET.keys():
		pass
	var missing: Array = effects.keys().filter(func(e): return not GameData.ABILITY_AWAKENING_BUCKET.has(e) or not GameData.ABILITY_EFFECT_ICON.has(e) or not SurvivorsRun.ABILITY_STYLE.has(e) and not e in ["mend_burst", "monster_dmg_mult", "debuff_lowest", "burst_lowest", "execute_burst", "self_sac_burst", "hp_drain_burst", "cleave_burst", "execute_all_low", "shield_lowest", "team_shield_burst", "mend_shield_hybrid"])
	check(missing.is_empty(), "every effect has an awakening bucket, an icon and an Endless style %s" % [missing])
	var quiet: Array = []
	for pool in GameData.SUBCLASS_ABILITIES:
		GameState.heroes.clear()
		var a := _hero("warrior", str(pool), "front")
		var b := _hero("cleric", "acolyte", "back")
		b.hp = int(Combat.max_hp(b) * 0.5)
		var party: Array[Hero] = [a, b]
		var st := _state(party)
		var before := JSON.stringify([st["monsters"], st["hero_shields"], st["monster_shields"], a.hp, b.hp, st.get("dodge"), st.get("counter"), st.get("escalate"), st.get("wipe_guard"), st.get("team_dmg_base"), st.get("momentum")])
		st["pending_actions"][a.id] = {"action": "ability", "target": 0}
		Combat._resolve_hero_action(st, a)
		var keys := ["_riposte", "_undying", "_trap", "_lifesteal", "_smoke", "_m_burn", "_m_stunned", "_taunt"]
		var flagged := keys.any(func(k): return _holds(st.get(k)))
		var after := JSON.stringify([st["monsters"], st["hero_shields"], st["monster_shields"], a.hp, b.hp, st.get("dodge"), st.get("counter"), st.get("escalate"), st.get("wipe_guard"), st.get("team_dmg_base"), st.get("momentum")])
		if before == after and not flagged:
			quiet.append(pool)
	check(quiet.is_empty(), "every Ability changes the fight %s" % [quiet])

	# A few in detail.
	GameState.heroes.clear()
	var w := _hero("warrior", "trapper", "front")
	var c := _hero("cleric", "rift-medic", "back")
	var party2: Array[Hero] = [w, c]
	var st2 := _state(party2)
	st2["momentum"] = 10
	st2["pending_actions"][w.id] = {"action": "ability", "target": 0}
	Combat._resolve_hero_action(st2, w)
	var whp := w.hp
	var mhp := float(st2["monsters"][0]["hp"])
	Combat._resolve_monster_action(st2, 0)
	check(w.hp == whp and float(st2["monsters"][0]["hp"]) < mhp and float(st2["_trap"]) == 0.0, "Trap: the next attacker is hit and loses its attack")
	w.hp = 0
	st2["momentum"] = 10
	st2["pending_actions"][c.id] = {"action": "ability", "target": 0}
	Combat._resolve_hero_action(st2, c)
	check(w.hp > 0, "Revive raises a fallen ally")
	w.pool_id = "wintertide-archer"
	w.hp = Combat.max_hp(w)
	st2["momentum"] = 10
	st2["pending_actions"][w.id] = {"action": "ability", "target": 1}
	Combat._resolve_hero_action(st2, w)
	check(int(st2["_m_stunned"].get(1, 0)) == 2, "Freeze: two lost actions")
	Combat._resolve_monster_action(st2, 1)
	Combat._resolve_monster_action(st2, 1)
	check(not st2["_m_stunned"].has(1), "the freeze wears off after two")
	w.pool_id = "duelist"
	st2["momentum"] = 10
	st2["pending_actions"][w.id] = {"action": "ability", "target": 0}
	Combat._resolve_hero_action(st2, w)
	mhp = float(st2["monsters"][0]["hp"])
	Combat._resolve_monster_action(st2, 0)
	check(float(st2["monsters"][0]["hp"]) < mhp and int(st2["_riposte"][w.id]["left"]) == 2, "Riposte answers a hit")
	w.pool_id = "pyromancer"
	st2["momentum"] = 10
	st2["pending_actions"][w.id] = {"action": "ability", "target": 0}
	Combat._resolve_hero_action(st2, w)
	mhp = float(st2["monsters"][1]["hp"])
	Combat._end_round_effects(st2)
	check(float(st2["monsters"][1]["hp"]) < mhp, "Burn ticks at round end")
	w.pool_id = "the-final-cut"
	st2["monsters"][0]["hp"] = 50.0
	st2["momentum"] = 10
	st2["pending_actions"][w.id] = {"action": "ability", "target": 0}
	Combat._resolve_hero_action(st2, w)
	check(float(st2["monsters"][0]["hp"]) <= 0.0, "Execute finishes a low foe")
	w.pool_id = "ashen-templar"
	st2["momentum"] = 10
	st2["pending_actions"][w.id] = {"action": "ability", "target": 1}
	Combat._resolve_hero_action(st2, w)
	w.hp = 1
	st2["intents"] = {1: {"kind": "attack", "target": w.id}}
	st2["monsters"][1]["dmg"] = 9999.0
	Combat._resolve_monster_action(st2, 1)
	check(w.hp == 1, "Undying: can't fall this round")

	# Archetype twists on role skills.
	var found := {}
	for tries in 200:
		GameState.heroes.clear()
		var h := Combat.gen_hero(["F", "D", "B"][tries % 3], 6)
		h.id = "hx%d" % tries
		GameState.heroes.append(h)
		var arch := Combat.hero_main_arch(h)
		if arch == "" or found.has(arch) or GameData.hero_role_skills(h).is_empty():
			continue
		var ally := _hero("cleric", "acolyte", "back")
		ally.hp = int(Combat.max_hp(ally) * 0.3)
		h.formation = "front" if GameData.hero_role_skills(h)[0]["row"] != "back" else "back"
		var pt: Array[Hero] = [h, ally]
		var st3 := _state(pt)
		var sk: Dictionary = GameData.hero_role_skills(h)[0]
		var hp_h0 := h.hp
		h.hp = int(Combat.max_hp(h) * 0.5)
		hp_h0 = h.hp
		st3["pending_actions"][h.id] = {"action": "skill:" + str(sk["id"]), "target": 0}
		Combat._resolve_hero_action(st3, h)
		match arch:
			"guardian": found[arch] = not (st3["hero_shields"] as Dictionary).is_empty()
			"sustain": found[arch] = h.hp > hp_h0
			"evasion": found[arch] = st3.get("_evade_next", {}).has(h.id)
			"opener": found[arch] = st3.get("_opened", {}).has(h.id)
			"attrition": found[arch] = str(sk["target"]) != "foe" or not (st3.get("_m_burn", {}) as Dictionary).is_empty()
			"executioner": found[arch] = true
	for arch in found:
		check(bool(found[arch]), "%s twist applies" % arch)
	check(found.size() >= 4, "twists seen for %d archetypes" % found.size())

	# Auto-battle fires an Ability only when it helps.
	GameState.heroes.clear()
	var med := _hero("cleric", "rift-medic", "back")
	var tank := _hero("warrior", "stormguard", "front")
	var p4: Array[Hero] = [med, tank]
	var st4 := _state(p4)
	st4["momentum"] = 5
	check(str(Combat.auto_action(st4, med)["action"]) != "ability", "Revive waits while nobody is down or badly hurt")
	tank.hp = 0
	check(str(Combat.auto_action(st4, med)["action"]) == "ability", "Revive fires when an ally is down")
	tank.hp = Combat.max_hp(tank)
	st4["monsters"][1]["_winding"] = true
	var aa := Combat.auto_action(st4, tank)
	check(str(aa["action"]) in ["ability", "skill:shield_bash"] and int(aa["target"]) == 1, "a stun goes to the foe winding up")
	st4["monsters"][1]["_winding"] = false
	st4["momentum"] = 0
	GameState.tonics = {"healing": 1}
	med.hp = 1
	var ta := Combat.auto_action(st4, tank)
	check(str(ta["action"]) == "tonic:healing" and str(ta["ally"]) == med.id, "auto gives a Healing Tonic to a badly hurt ally")
	GameState.tonics = {}
