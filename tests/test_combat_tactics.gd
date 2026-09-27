extends "res://tests/base_test.gd"
## Manual tactics: Momentum, role skills, rows, and telegraphed enemy moves.


func _hero(role: String, level: int, row: String) -> Hero:
	var h := Combat.gen_hero("C", level)
	h.cls_id = role
	h.id = "h%d" % GameState.next_id
	GameState.next_id += 1
	h.formation = row
	h.hp = Combat.max_hp(h)
	GameState.heroes.append(h)
	return h


## A fight against one plain foe with no special moves, turn order cleared.
func _state(party: Array[Hero]) -> Dictionary:
	var st := Combat.start_combat(party, "combat", GameData.DIFFICULTIES[0], 1)
	var m: Dictionary = st["monsters"][0]
	st["monsters"] = [m]
	m["hp"] = 500.0
	m["max_hp"] = 500.0
	m["armor"] = 0.0
	m["kit"] = []
	m["_winding"] = false
	m["_charged"] = false
	m["ability"] = {}
	m["status"] = ""
	st["monster_shields"] = {}
	st["intents"] = {0: {"kind": "attack", "target": party[0].id}}
	st["turn_order"] = []
	st["turn_idx"] = 0
	st["dodge"] = 0.0
	st["escort"] = {}
	return st


func run() -> void:
	seed(7)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	var war := _hero("warrior", 6, "front")
	var ran := _hero("ranger", 6, "back")
	var cle := _hero("cleric", 6, "back")
	var party: Array[Hero] = [war, ran, cle]

	# Momentum: starts at 3, a basic attack adds 1, a skill spends its cost.
	var st := _state(party)
	check(int(st["momentum"]) == GameData.MOMENTUM_START, "a fight starts with %d Momentum" % GameData.MOMENTUM_START)
	st["pending_actions"][war.id] = {"action": "attack", "target": 0}
	Combat._resolve_hero_action(st, war)
	check(int(st["momentum"]) == GameData.MOMENTUM_START + 1, "an attack builds 1 Momentum")
	check(GameData.hero_role_skills(war).size() == 2 and GameData.hero_role_skills(Combat.gen_hero("F", 1)).size() == 1, "two role skills by Lv6, one at Lv1")

	# Rows: skills need their row; melee hits at half strength from the back.
	check(Combat.action_block(st, war, "skill:shield_bash") == "", "Shield Bash usable from the front with Momentum")
	check(Combat.action_block(st, ran, "skill:shield_bash") != "", "a ranger can't Shield Bash")
	war.formation = "back"
	check(Combat.action_block(st, war, "skill:shield_bash").contains("Front"), "Shield Bash is front row only")
	var m: Dictionary = st["monsters"][0]
	var hp0 := float(m["hp"])
	Combat._resolve_hero_action(st, war)
	var back_hit := hp0 - float(m["hp"])
	war.formation = "front"
	hp0 = float(m["hp"])
	Combat._resolve_hero_action(st, war)
	var front_hit := hp0 - float(m["hp"])
	check(back_hit > 0.0 and absf(back_hit - front_hit * GameData.BACK_ROW_MELEE_MULT) <= 1.0, "a warrior hits at half strength from the back (%d vs %d)" % [back_hit, front_hit])
	st["momentum"] = 1
	check(Combat.action_block(st, war, "skill:shield_bash").contains("Momentum"), "a skill needs its Momentum")

	# Shield Bash: stuns and breaks a wind-up; the stunned foe loses its action.
	st["momentum"] = 5
	m["_winding"] = true
	st["pending_actions"][war.id] = {"action": "skill:shield_bash", "target": 0}
	Combat._resolve_hero_action(st, war)
	check(int(st["momentum"]) == 3 and not m["_winding"] and st["_m_stunned"].has(0), "Shield Bash costs 2, breaks the wind-up and stuns")
	var whp := war.hp
	Combat._resolve_monster_action(st, 0)
	check(war.hp == whp and not st["_m_stunned"].has(0), "the stunned foe loses its action")

	# An unaffordable skill falls back to an attack.
	st["momentum"] = 0
	st["pending_actions"][ran.id] = {"action": "skill:volley", "target": 0}
	Combat._resolve_hero_action(st, ran)
	check(int(st["momentum"]) == 1, "no Momentum: the skill becomes an attack")

	# Heal and the Ability's cost.
	st["momentum"] = 6
	ran.hp = 1
	st["pending_actions"][cle.id] = {"action": "skill:heal", "target": 0}
	Combat._resolve_hero_action(st, cle)
	check(ran.hp > 1 and int(st["momentum"]) == 4, "Heal mends the most-hurt ally for 2 Momentum")
	if Combat.qualifies_for_ability(cle):
		st["pending_actions"][cle.id] = {"action": "ability", "target": 0}
		Combat._resolve_hero_action(st, cle)
		check(int(st["momentum"]) <= 4 - GameData.ABILITY_MOMENTUM_COST + 4, "the Ability spends %d Momentum" % GameData.ABILITY_MOMENTUM_COST)

	# Defending against a hit builds Momentum.
	st = _state(party)
	m = st["monsters"][0]
	st["_defending"] = {war.id: true}
	st["momentum"] = 0
	Combat._resolve_monster_action(st, 0)
	check(int(st["momentum"]) == 1, "a hit taken while Defending gives 1 Momentum")

	# Taunt pulls the attack.
	st = _state(party)
	m = st["monsters"][0]
	st["intents"] = {0: {"kind": "attack", "target": cle.id}}
	st["pending_actions"][war.id] = {"action": "skill:taunt", "target": 0}
	Combat._resolve_hero_action(st, war)
	check(Combat.monster_intent(st, 0)["target"] == war, "Taunt: the intent turns to the warrior")
	var chp := cle.hp
	whp = war.hp
	Combat._resolve_monster_action(st, 0)
	check(cle.hp == chp and war.hp < whp, "Taunt: the warrior takes the hit")

	# Telegraphed moves.
	for h in party:
		h.hp = Combat.max_hp(h)
	st = _state(party)
	m = st["monsters"][0]
	st["intents"] = {0: {"kind": "sweep", "target": ""}}
	check(Combat.monster_intent(st, 0)["kind"] == "sweep" and Combat.monster_intent(st, 0)["targets"].size() == 3, "a sweep shows every hero as a target")
	Combat._resolve_monster_action(st, 0)
	check(party.all(func(h): return h.hp < Combat.max_hp(h)), "a sweep hits the whole party")
	st["intents"] = {0: {"kind": "curse", "target": ran.id}}
	Combat._resolve_monster_action(st, 0)
	check(st["_weakened"].has(ran.id), "a curse weakens its target")
	var mhp := float(m["hp"])
	st["pending_actions"][ran.id] = {"action": "attack", "target": 0}
	Combat._resolve_hero_action(st, ran)
	var cursed_hit := mhp - float(m["hp"])
	st["_weakened"] = {}
	mhp = float(m["hp"])
	Combat._resolve_hero_action(st, ran)
	check(cursed_hit < mhp - float(m["hp"]), "a cursed hero hits softer")
	var add := m.duplicate(true)
	add["hp"] = 50.0
	add["max_hp"] = 100.0
	st["monsters"].append(add)
	st["intents"] = {0: {"kind": "mend", "target": ""}}
	Combat._resolve_monster_action(st, 0)
	check(float(add["hp"]) > 50.0, "Mend heals the most-hurt foe")
	st["intents"] = {0: {"kind": "ward", "target": ""}}
	Combat._resolve_monster_action(st, 0)
	check(float(st["monster_shields"].get(1, 0.0)) > 0.0, "Ward shields the most-hurt foe")
	var dmg0 := float(m["dmg"])
	st["intents"] = {0: {"kind": "roar", "target": ""}}
	Combat._resolve_monster_action(st, 0)
	check(float(m["dmg"]) > dmg0, "Roar makes foes hit harder")

	# Kits: bosses sweep and roar; the auto-player spends Momentum sensibly.
	check(Combat.monster_kit({"name": "X", "tier": "boss"}) == ["sweep", "roar"], "bosses sweep and roar")
	check(Combat.monster_kit({"name": "Rift Wisp", "tier": "combat", "ability": {"kind": "healer"}}).has("mend"), "healers mend")
	st = _state(party)
	st["momentum"] = 5
	ran.hp = 1
	check(str(Combat.auto_action(st, cle)["action"]) == "skill:heal", "auto heals a badly hurt ally")
	ran.hp = Combat.max_hp(ran)
	st["monsters"][0]["_winding"] = true
	check(str(Combat.auto_action(st, war)["action"]) == "skill:shield_bash", "auto breaks a wind-up with Shield Bash")

	# Tonics: Iron wards an ally, Focus gives Momentum; each uses up one.
	st = _state(party)
	GameState.tonics = {"iron": 1, "focus": 1}
	st["pending_actions"][war.id] = {"action": "tonic:iron", "target": 0, "ally": cle.id}
	Combat._resolve_hero_action(st, war)
	check(float(st["hero_shields"].get(cle.id, 0.0)) > 0.0 and GameState.tonic_count("iron") == 0, "an Iron Tonic wards the ally")
	var mom0 := int(st["momentum"])
	st["pending_actions"][war.id] = {"action": "tonic:focus", "target": 0}
	Combat._resolve_hero_action(st, war)
	check(int(st["momentum"]) == mini(GameData.MOMENTUM_MAX, mom0 + GameData.TONIC_FOCUS) and GameState.tonic_count() == 0, "a Focus Tonic adds Momentum")
