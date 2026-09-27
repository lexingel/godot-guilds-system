extends "res://scripts/autoload/combat/CombatGen.gd"
## Combat, part 4 (the autoload): a fight â€” setup, turn order, hero and monster turns, round effects, defeat analysis, outcome.
## The chain, bottom up: combat/CombatStats.gd -> Effects -> Gen -> this file; each part only calls down.


## Turn-based combat, per-hero and per-monster: a fight starts with
## start_combat() (one-time setup: monster roll via gen_monsters(), all
## party-wide bonus totals) and then advances one round per resolve_round()
## call. Each living hero has their own pending action (state["pending_actions"],
## hero_id -> {"action": "attack"/"ability"/"skill:<id>"/"defend"/..., "target":
## monster index}, mutated between renders by GameState.set_hero_action
## without resolving anything). Skills and Abilities spend the party's shared
## Momentum (state["momentum"]), built by attacks, kills and taking hits
## while Defending or Guarding. Foes telegraph each round's move in
## state["intents"] (see _roll_intent / monster_intent). HP lives directly on each Hero throughout (no pooling), so win/
## retreat/loss need no redistribution step. Monsters live in state["monsters"]
## (Array of {name, hp, max_hp, dmg, mechanic, is_main} — mechanic is only ever
## non-empty on the "is_main" unit, and only for a "boss" encounter). Every
## living monster retaliates independently each round against a random living
## hero; a hero knocked out (hp reaches 0) sits out the rest of the fight but
## the party keeps fighting — a loss only happens once every hero is down, a
## win only once every monster is down. State is persisted by the caller
## (GameState.engage_node/resolve_round_now) across renders in
## run["node_state"]["combat_state"], the same per-node-cache pattern already
## used for shop/hazard nodes. `kind` is "combat"/"elite"/"boss".
func start_combat(party: Array[Hero], kind: String, diff: Dictionary, floor_idx: int) -> Dictionary:
	var is_boss := kind == "boss"
	var is_elite := kind == "elite"
	var monsters := gen_monsters(diff, floor_idx, kind)

	var raw_sum := 0.0
	for h in party:
		raw_sum += dmg_of(h)
	var team_dmg_base: float = (raw_sum * GameState.tactical_bonus() + relic_dmg_bonus()) * (1.0 + synergy_value_for("dmg_pct") + bond_bonus_for(party, "dmg_pct"))

	var first_round_bonus: float = (0.25 if GameState.vanguard() else 0.0) + party_skill_total(party, "first_round_pct") + relic_special_total("first_round_pct") + relic_drawback_total("first_round_pct") + synergy_value_for("first_round_pct") + bond_bonus_for(party, "first_round_pct")
	var escalate: float = party_skill_total(party, "escalate_pct") + relic_special_total("escalate_pct") + relic_drawback_total("escalate_pct") + synergy_value_for("escalate_pct")
	var mend: float = 0.0 if party_has_unique_relic("bloodpact") else min(0.4, party_skill_total(party, "mend_pct") + relic_special_total("mend_pct") + relic_drawback_total("mend_pct") + synergy_value_for("mend_pct") + bond_bonus_for(party, "mend_pct"))
	var dodge: float = min(0.6, party_skill_total(party, "dodge_pct") + relic_special_total("dodge_pct") + relic_drawback_total("dodge_pct") + synergy_value_for("dodge_pct") + bond_bonus_for(party, "dodge_pct"))
	var wipe_guard: float = min(0.9, party_skill_total(party, "wipe_guard") + relic_special_total("wipe_guard") + relic_drawback_total("wipe_guard") + bond_bonus_for(party, "wipe_guard"))
	var counter: float = min(0.6, relic_special_total("counter_pct"))
	var momentum_proc: float = min(0.75, relic_special_total("momentum_pct"))
	var kill_shield: float = min(0.6, relic_special_total("kill_shield_pct"))
	var alpha_strikes: float = (party_skill_total(party, "boss_alpha_strike") + relic_special_total("boss_alpha_strike")) if is_boss else 0.0

	var log: Array[String] = []
	if monsters.size() == 1:
		log.append("A %s blocks the way (%d HP)." % [monsters[0]["name"], monsters[0]["hp"]])
	else:
		var names: Array[String] = []
		for m in monsters:
			names.append(str(m["name"]))
		log.append("%d foes block the way: %s." % [monsters.size(), ", ".join(names)])
	for m in monsters:
		if not m["mechanic"].is_empty():
			log.append("%s: %s" % [m["mechanic"]["name"], m["mechanic"]["desc"]])
		var mechanic2: Dictionary = m.get("mechanic2", {})
		if not mechanic2.is_empty():
			log.append("%s: %s" % [mechanic2["name"], mechanic2["desc"]])
		if m.has("phase"):
			var ph: Dictionary = GameData.BOSS_PHASES[m["phase"]]
			log.append("%s: %s" % [ph["name"], ph["desc"]])
		for a in m.get("affixes", []):
			log.append("%s: %s" % [GameData.ELITE_AFFIXES[a]["name"], GameData.ELITE_AFFIXES[a]["desc"]])
	if alpha_strikes > 0:
		var alpha: float = team_dmg_base * alpha_strikes
		monsters[0]["hp"] = float(monsters[0]["hp"]) - round(alpha)
		log.append("An opening volley lands for %d!" % round(alpha))

	# A "shielded"-ability monster starts the fight with a one-time absorb
	# shield on incoming hero damage — pre-filled here (once, not re-rolled
	# each round) mirroring how alpha_strikes above is also a one-time
	# fight-start effect rather than a per-round one.
	var monster_shields: Dictionary = {}
	for i in monsters.size():
		var ability: Dictionary = monsters[i].get("ability", {})
		if ability.get("kind") == "shielded":
			monster_shields[i] = float(monsters[i]["max_hp"]) * float(ability["value"])
			log.append("%s: %s (shielded)" % [str(monsters[i]["name"]), str(ability["name"])])

	var pending_actions: Dictionary = {}
	for h in party:
		pending_actions[h.id] = {"action": "attack", "target": 0}
	# Drill Yard Lv5 and a campfire's Sharpen (run "momentum_bonus") add to
	# the Momentum a fight starts with.
	var momentum: int = GameData.MOMENTUM_START + (3 if GameState.abilities_ready_each_fight() else 0) + int(GameState.run.get("momentum_bonus", 0))
	GameState.run.erase("momentum_bonus")

	# An escort NPC quest, folded onto an ordinary "combat" node rather than a
	# whole new node kind — a chance for a fragile ally to tag along who
	# monster retaliation can occasionally hit instead of a hero (see
	# resolve_round's retaliation loop). {} = no escort this fight, the same
	# "empty dict = not present" contract mechanic/mechanic2 already use.
	var escort: Dictionary = {}
	if kind == "combat" and not GameState.run.has("tower") and randf() < 0.25:
		var avg_hp := 0.0
		for h in party:
			avg_hp += max_hp(h)
		avg_hp /= float(max(1, party.size()))
		var ehp: int = max(15, int(round(avg_hp * 0.4)))
		var ename: String = GameData.ESCORT_NAMES[randi() % GameData.ESCORT_NAMES.size()]
		escort = {"name": ename, "hp": ehp, "max_hp": ehp}
		log.append("A %s tags along, hoping to survive the crossing." % ename)

	var hp_now := 0.0
	var hp_max := 0.0
	for h in party:
		hp_now += max(0, h.hp)
		hp_max += max_hp(h)
	var state := {
		"_start_hp_pct": hp_now / maxf(1.0, hp_max),
		"party": party, "kind": kind, "diff": diff, "floor_idx": floor_idx,
		"is_boss": is_boss, "is_elite": is_elite,
		"monsters": monsters, "background_idx": _biome_background(diff),
		"team_dmg_base": team_dmg_base, "raw_sum": raw_sum,
		"first_round_bonus": first_round_bonus, "escalate": escalate,
		"mend": mend, "dodge": dodge, "wipe_guard": wipe_guard, "wipe_guard_used": false, "counter": counter,
		"momentum_proc": momentum_proc, "momentum": mini(momentum, GameData.MOMENTUM_MAX), "kill_shield": kill_shield, "hero_shields": {},
		"monster_shields": monster_shields, "hero_poison": {}, "escort": escort,
		"round_num": 0, "log": log,
		"pending_actions": pending_actions,
	}
	# Seed round 1's turn order immediately so the combat screen's very first
	# render already knows whose turn it is, instead of needing a resolve_turn
	# call just to find out.
	_start_round(state)
	return state


## True if `h` has an Ability at all (subclass qualifies + level 3+) — used to
## gate both the combat action-button row and the Ability's cooldown ticking.
static func qualifies_for_ability(h: Hero) -> bool:
	return GameData.SUBCLASS_ABILITIES.has(h.pool_id) and h.level >= 3


## "tonic:<id>" -> id ("tonic" alone is a Healing Tonic).
static func _tonic_id(action: String) -> String:
	return action.substr(6) if action.begins_with("tonic:") else "healing"


func gain_momentum(state: Dictionary, n: int) -> void:
	state["momentum"] = clampi(int(state.get("momentum", 0)) + n, 0, GameData.MOMENTUM_MAX)


## What `action` ("ability" or "skill:<id>") costs in Momentum and which row
## it needs: [cost, row].
func action_cost(action: String) -> Array:
	if action == "ability":
		return [GameData.ABILITY_MOMENTUM_COST, "any"]
	if action.begins_with("skill:"):
		var sk := GameData.find_role_skill(action.substr(6))
		return [int(sk.get("cost", 0)), str(sk.get("row", "any"))]
	return [0, "any"]


## "" if `h` can use `action` right now, else why not (for the command bar
## and the auto-player).
func action_block(state: Dictionary, h: Hero, action: String) -> String:
	if action == "ability" and not qualifies_for_ability(h):
		return "Unlocks at level 3"
	if action.begins_with("skill:") and not GameData.hero_role_skills(h).any(func(sk): return "skill:" + str(sk["id"]) == action):
		return "Not learned yet"
	var c := action_cost(action)
	if str(c[1]) != "any" and (str(c[1]) == "back") != (h.formation == "back"):
		return "%s row only" % str(c[1]).capitalize()
	if int(state.get("momentum", 0)) < int(c[0]):
		return "Needs %d Momentum" % int(c[0])
	return ""


## One-line hint about the round about to happen, meant to sit above the
## action rows as a warning rather than only showing up in the log after the
## fact. Boss-mechanic messages (read from the main monster unit) take
## priority; every fight (not just bosses) falls back to a general heavy-hit/
## stacking-damage heuristic so the signal isn't boss-only.
func describe_incoming(state: Dictionary) -> String:
	var monsters: Array = state["monsters"]
	var main_mechanic: Dictionary = {}
	var main_mechanic2: Dictionary = {}
	for m in monsters:
		if bool(m.get("is_main", false)):
			main_mechanic = m["mechanic"]
			main_mechanic2 = m.get("mechanic2", {})
			break
	# round_num is prepared (incremented + turn order rolled) by _start_round
	# before this round's first turn ever runs — see resolve_turn — so it
	# already names the round currently in progress, not the last completed
	# one; no +1 needed here anymore.
	var next_round: int = int(state.get("round_num", 0))
	# A double-mechanic boss (SS-rank+ mapped rift) checks both rolled
	# mechanics here, same message per id as the single-mechanic case —
	# whichever one matches first wins, same as only ever having had one.
	for mech in [main_mechanic, main_mechanic2]:
		if mech.is_empty():
			continue
		match mech.get("id"):
			"warded":
				if next_round <= 2:
					return "Warded — dodge won't help this round."
			"enrage":
				if next_round > GameData.BOSS_ENRAGE_ROUND:
					return "Enraged — retaliation is empowered this round."
			"regen":
				return "Regenerating — it will heal after this exchange."
			"frenzied":
				return "Frenzied — its blows already hit harder."
	for m in monsters:
		if m.has("phase") and not m.get("_phased", false) and float(m["hp"]) > 0.0 and float(m["hp"]) <= float(m["max_hp"]) * 0.7:
			return "%s is close to half health: %s." % [str(m["name"]).split(",")[0], str(GameData.BOSS_PHASES[m["phase"]]["desc"]).trim_prefix("At half health, ").trim_prefix("At half health ")]

	var party: Array[Hero] = state["party"]
	var living: Array[Hero] = []
	living.assign(party.filter(func(h): return h.hp > 0))
	if living.is_empty():
		return ""
	var worst_back := 0.0
	for m in monsters:
		if float(m["hp"]) <= 0:
			continue
		var back: float = float(m["dmg"])
		var is_enraging: bool = main_mechanic.get("id") == "enrage" or main_mechanic2.get("id") == "enrage"
		if bool(m.get("is_main", false)) and is_enraging and next_round > GameData.BOSS_ENRAGE_ROUND:
			back = back * (1.0 + 0.15 * (next_round - GameData.BOSS_ENRAGE_ROUND))
		worst_back = max(worst_back, back)
	var avg_max := 0.0
	for h in living:
		avg_max += max_hp(h)
	avg_max /= living.size()
	if avg_max > 0.0 and worst_back / avg_max > 0.35:
		return "A heavy blow is coming — consider Defending."
	if float(state["escalate"]) > 0.0 and next_round >= 3:
		return "Damage is stacking — every attack counts more now."
	return ""


## A monster's raw hit this round before defend/dodge/shields — enrage and
## frenzy included. Shared by the real attack and the intent preview.
func _monster_hit(m: Dictionary, round_num: int) -> float:
	var back: float = float(m["dmg"])
	var mech: Dictionary = m.get("mechanic", {})
	var mech2: Dictionary = m.get("mechanic2", {})
	var ability: Dictionary = m.get("ability", {})
	if (mech.get("id") == "enrage" or mech2.get("id") == "enrage") and round_num > GameData.BOSS_ENRAGE_ROUND:
		back = round(back * (1.0 + 0.15 * (round_num - GameData.BOSS_ENRAGE_ROUND)))
	if ability.get("kind") == "frenzy" and float(m["hp"]) / float(m["max_hp"]) <= 0.3:
		back = round(back * (1.0 + float(ability["value"])))
	return back


## What monster `i` is about to do this round, for the combat screen:
## {"target": Hero, "dmg": int, "heavy": bool} or {} if it's down / no target.
## Heavy = a quarter of the target's max HP or more (same bar as the log's
## heavy-hit reactions). Intercepts/escort hits can still change the outcome.
## What an auto-played hero does this turn (Auto toggle, Quick fight, the
## balance sim): Defend against a heavy blow aimed at them, heal a badly hurt
## ally, break a wind-up, the Champion's Call on a boss, the Ability or a
## damage skill when Momentum allows, otherwise attack the weakest foe.
func auto_action(state: Dictionary, h: Hero) -> Dictionary:
	var monsters: Array = state["monsters"]
	var tgt: int = max(0, _lowest_hp_living_monster_idx(monsters))
	for mi in monsters.size():
		var it := monster_intent(state, mi)
		if it.get("heavy_blow", false) and it["target"] == h:
			return {"action": "defend", "target": 0}
	var ok := func(a: String) -> bool: return action_block(state, h, a) == ""
	var party: Array = state["party"]
	var hurt: Array = party.filter(func(x): return x.hp > 0 and x.hp < max_hp(x) * 0.45)
	if not hurt.is_empty() and ok.call("skill:heal"):
		return {"action": "skill:heal", "target": 0}
	for mi in monsters.size():
		if float(monsters[mi]["hp"]) > 0 and monsters[mi].get("_winding", false):
			if ok.call("skill:shield_bash"):
				return {"action": "skill:shield_bash", "target": mi}
			if ok.call("skill:frost_nova"):
				return {"action": "skill:frost_nova", "target": 0}
	if bool(state.get("is_boss", false)) and GameState.champion_call_ready(h):
		return {"action": "call", "target": 0}
	if ok.call("ability"):
		var at := _ability_target(state, h)
		if at >= 0:
			return {"action": "ability", "target": at}
	# A Healing Tonic for a badly hurt ally when no heal skill is ready.
	if GameState.tonic_count("healing") > 0:
		var worst: Hero = null
		for x in party:
			if x.hp > 0 and x.hp < max_hp(x) * 0.3 and (worst == null or x.hp < worst.hp):
				worst = x
		if worst:
			return {"action": "tonic:healing", "target": 0, "ally": worst.id}
	# Spend on a damage skill only with enough left over for someone's Ability.
	if int(state.get("momentum", 0)) >= GameData.ABILITY_MOMENTUM_COST + 2:
		for sk in GameData.hero_role_skills(h):
			if str(sk["effect"]) in ["pierce", "strike", "backstab", "volley"] and ok.call("skill:" + str(sk["id"])):
				return {"action": "skill:" + str(sk["id"]), "target": tgt}
	return {"action": "attack", "target": tgt}


## Whether `h`'s Ability is worth firing now, and at which foe: the index,
## or -1 to hold it. Heals wait for someone hurt, Revive for someone down,
## defensive ones for a big hit coming; stuns go to a foe winding up, marks
## to the toughest foe, executes to the weakest. Full Momentum always fires.
func _ability_target(state: Dictionary, h: Hero) -> int:
	var monsters: Array = state["monsters"]
	var party: Array = state["party"]
	var weakest: int = max(0, _lowest_hp_living_monster_idx(monsters))
	var toughest := weakest
	for i in monsters.size():
		if float(monsters[i]["hp"]) > float(monsters[toughest]["hp"]):
			toughest = i
	var full := int(state.get("momentum", 0)) >= GameData.MOMENTUM_MAX - 1
	var eff := str(GameData.SUBCLASS_ABILITIES.get(h.pool_id, {}).get("effect", ""))
	var hurt: bool = party.any(func(x): return x.hp > 0 and x.hp < max_hp(x) * 0.6)
	var danger := false
	for mi in monsters.size():
		var it := monster_intent(state, mi)
		if it.get("kind") in ["sweep", "heavy", "windup"] or (it.get("target") != null and int(it.get("dmg", 0)) >= max_hp(it["target"]) * 0.25):
			danger = true
	match eff:
		"revive":
			return 0 if party.any(func(x): return x.hp <= 0) or party.any(func(x): return x.hp > 0 and x.hp < max_hp(x) * 0.4) or full else -1
		"mend_burst", "cleanse_heal", "mend_shield_hybrid", "shield_lowest", "team_shield_burst", "shield_wall_front":
			var ailing: bool = not (state.get("hero_burn", {}) as Dictionary).is_empty() or not (state.get("hero_poison", {}) as Dictionary).is_empty() or not (state.get("_weakened", {}) as Dictionary).is_empty()
			return 0 if hurt or (eff == "cleanse_heal" and ailing) or full else -1
		"trap", "riposte", "taunt_ward", "undying", "evasion_round", "dodge_surge", "wipe_guard_surge":
			return 0 if danger or full else -1
		"stun_strike", "freeze_target":
			for mi in monsters.size():
				if float(monsters[mi]["hp"]) > 0 and (monsters[mi].get("_winding", false) or monsters[mi].get("_charged", false)):
					return mi
			return toughest
		"mark_target", "armor_break":
			return toughest
		"execute_threshold":
			return weakest if float(monsters[weakest]["hp"]) <= float(monsters[weakest]["max_hp"]) * 0.35 or full else -1
	return weakest


## What monster `i` is about to do this round, for the combat screen and the
## auto-player: {"kind", "target" (Hero or null), "dmg", "heavy", ...} or {}
## if it's down or has already acted. Kinds: attack, windup (charging),
## heavy (the blow), sweep ("targets": every hero), snipe, curse, ward, mend,
## roar, stunned. Heavy = a quarter of the target's max HP or more.
func monster_intent(state: Dictionary, i: int) -> Dictionary:
	var m: Dictionary = state["monsters"][i]
	if float(m["hp"]) <= 0:
		return {}
	# A monster that has already acted this round has nothing left to show
	# (and Guard can't change a hit that already landed).
	var order: Array = state.get("turn_order", [])
	for k in min(int(state.get("turn_idx", 0)), order.size()):
		if str(order[k]["type"]) == "monster" and int(order[k]["id"]) == i:
			return {}
	if state.get("_m_stunned", {}).has(i):
		return {"kind": "stunned", "target": null, "dmg": 0, "heavy": false}
	var it: Dictionary = _intent_of(state, i)
	var kind := str(it.get("kind", "attack"))
	var round_num := int(state.get("round_num", 0))
	if kind in ["ward", "mend", "roar"]:
		return {"kind": kind, "target": null, "dmg": 0, "heavy": false}
	if kind == "sweep":
		var living: Array = (state["party"] as Array).filter(func(h): return h.hp > 0)
		return {"kind": "sweep", "target": null, "targets": living, "dmg": int(_monster_hit(m, round_num) * GameData.SWEEP_MULT), "heavy": false}
	var t := _find_party_hero(state["party"], str(it.get("target", "")))
	if t == null or t.hp <= 0:
		return {}
	if kind == "curse":
		return {"kind": "curse", "target": t, "dmg": 0, "heavy": false}
	if m.get("_winding", false):
		return {"kind": "windup", "target": t, "dmg": 0, "heavy": false, "guarded": false, "charging": true}
	var taunter := _find_party_hero(state["party"], str(state.get("_taunt", "")))
	if taunter and taunter.hp > 0:
		t = taunter
	var dmg := _monster_hit(m, round_num)
	var blow: bool = m.get("_charged", false)
	if blow:
		dmg *= GameData.HEAVY_BLOW_MULT
	if kind == "snipe":
		dmg *= GameData.SNIPE_MULT
	if t == taunter:
		dmg *= 1.0 - float(state.get("_taunt_cut", 0.0))
	# A guarded target shows the hit landing on its guard.
	var guard := guard_of(state, t)
	if guard:
		t = guard
		dmg *= GUARD_DAMAGE_MULT
	return {"kind": "heavy" if blow else kind, "target": t, "dmg": int(dmg), "heavy": blow or dmg >= float(max_hp(t)) * 0.25, "guarded": guard != null, "heavy_blow": blow}


## A monster's rolled intent for this round: {"kind", "target": hero id}.
func _intent_of(state: Dictionary, i: int) -> Dictionary:
	var it = state.get("intents", {}).get(i, {})
	return it if it is Dictionary else {"kind": "attack", "target": str(it)}


const GUARD_DAMAGE_MULT := 0.75


## The living hero guarding `target` this round, or null.
func guard_of(state: Dictionary, target: Hero) -> Hero:
	var gid: String = str(state.get("_guarding", {}).get(target.id, ""))
	if gid == "":
		return null
	var g := _find_party_hero(state["party"], gid)
	return g if g and g.hp > 0 and g != target else null


func _find_party_hero(party: Array[Hero], hero_id: String) -> Hero:
	for h in party:
		if h.id == hero_id:
			return h
	return null


## Living heroes + living monsters, sorted by Combat.spd_of()/monster "spd"
## descending (a small random jitter breaks exact ties so they don't always
## resolve in the same order) — this round's turn sequence.
func _compute_turn_order(state: Dictionary) -> Array:
	var entries: Array = []
	var chilled: Dictionary = state.get("_chilled", {})
	for h in state["party"]:
		if h.hp > 0:
			entries.append({"type": "hero", "id": h.id, "_spd": spd_of(h) * (0.5 if chilled.has(h.id) else 1.0) + randf() * 0.01})
	var monsters: Array = state["monsters"]
	for i in monsters.size():
		if float(monsters[i]["hp"]) > 0:
			entries.append({"type": "monster", "id": i, "_spd": float(monsters[i].get("spd", 10)) + randf() * 0.01})
			if (monsters[i].get("affixes", []) as Array).has("hasted"):
				entries.append({"type": "monster", "id": i, "_spd": float(monsters[i].get("spd", 10)) * 0.4 + randf() * 0.01})
	entries.sort_custom(func(a, b): return float(a["_spd"]) > float(b["_spd"]))
	return entries


## Everything that happens once at the start of a round, before any actor's
## turn: round_num/attack_mult/escalate_mult (cached on state for the whole
## round — an ability that raises state["escalate"] mid-round only takes
## effect starting next round, same timing the old batched resolve_round
## had), the Legendary relic round-wide rolls, ability cooldown ticks, a
## fresh turn order, and defaulting any dead-target pending actions to a
## living monster.
func _start_round(state: Dictionary) -> void:
	var log: Array[String] = state["log"]
	var party: Array[Hero] = state["party"]
	var monsters: Array = state["monsters"]
	var living: Array[Hero] = []
	living.assign(party.filter(func(h): return h.hp > 0))

	state["round_num"] = int(state["round_num"]) + 1
	var round_num: int = state["round_num"]
	var attack_mult: float = (1.0 + float(state["first_round_bonus"]) if round_num == 1 else 1.0) * (1.0 + float(state["escalate"]) * (round_num - 1))
	var escalate_mult: float = 1.0 + float(state["escalate"]) * (round_num - 1)

	if party_has_unique_relic("gamblers_coin"):
		if randf() < 0.5:
			attack_mult *= 2.0
			log.append("The Gambler's Gold shines bright — damage is doubled this round!")
		else:
			attack_mult *= 0.5
			log.append("The Gambler's Gold shows its dark face — damage is halved this round.")
	if party_has_unique_relic("ashes_of_the_fallen"):
		var desperation_cap := 0.30
		if party_has_unique_relic("twin_embers"):
			desperation_cap *= 2.0
		var total_max := 0.0
		var total_missing := 0.0
		for h3 in living:
			total_max += max_hp(h3)
			total_missing += max_hp(h3) - h3.hp
		if total_max > 0.0:
			attack_mult *= 1.0 + desperation_cap * (total_missing / total_max)
	if party_has_unique_relic("bloodpact"):
		attack_mult *= 1.35
	if party_has_unique_relic("prism_heart"):
		var elems := {}
		for h3 in living:
			if h3.type != "":
				elems[h3.type] = true
		attack_mult *= 1.0 + 0.05 * elems.size()
	if party_has_unique_relic("sable_standard"):
		var roles_seen := {}
		for h3 in living:
			roles_seen[h3.cls_id] = true
		if roles_seen.size() == 1:
			attack_mult *= 1.25

	state["_attack_mult"] = attack_mult
	state["_escalate_mult"] = escalate_mult
	state["_defending"] = {}
	state["_guarding"] = {}   # guarded hero id -> guard's id (see "guard" below)
	state["_extra_turned"] = {}
	state["_taunt"] = ""
	state["_smoke"] = 0.0
	state["_undying"] = {}
	var weakened: Dictionary = state.get("_weakened", {})
	for wid in weakened.keys().duplicate():
		weakened[wid] = int(weakened[wid]) - 1
		if int(weakened[wid]) <= 0:
			weakened.erase(wid)
	state["_weakened"] = weakened

	var pending: Dictionary = state["pending_actions"]
	for h in living:
		var prev: Dictionary = pending.get(h.id, {})
		var target_idx: int = int(prev.get("target", 0))
		if target_idx < 0 or target_idx >= monsters.size() or float(monsters[target_idx]["hp"]) <= 0:
			target_idx = max(0, _first_living_monster_idx(monsters))
		pending[h.id] = {"action": str(prev.get("action", "attack")), "target": target_idx}

	state["turn_order"] = _compute_turn_order(state)
	var chilled: Dictionary = state.get("_chilled", {})
	for hid in chilled.keys().duplicate():
		chilled[hid] = int(chilled[hid]) - 1
		if int(chilled[hid]) <= 0:
			chilled.erase(hid)
	state["_chilled"] = chilled
	for mw in monsters:
		if float(mw["hp"]) <= 0 or mw.get("_charged", false):
			continue
		if int(mw.get("_windup_cd", 0)) > 0:
			mw["_windup_cd"] = int(mw["_windup_cd"]) - 1
			continue
		if (mw.get("affixes", []) as Array).has("hasted"):
			continue
		var wtier := str(mw.get("tier", "combat"))
		if wtier == "combat" and GameData.WINDUP_BRUTES.has(str(mw["name"])):
			wtier = "brute"
		if randf() < float(GameData.WINDUP_CHANCE.get(wtier, 0.0)) + float(state.get("diff", {}).get("windup_bonus", 0.0)) + float(mw.get("windup_bonus", 0.0)):
			mw["_winding"] = true
	# The guided first fight (training rift) shows one wind-up in round 2.
	if GameState.run.get("training", false) and int(state["round_num"]) == 2 and not GameState.hints_seen.has("tut_windup"):
		for mw in monsters:
			if float(mw["hp"]) > 0 and not mw.get("_charged", false):
				mw["_winding"] = true
				break
	if int(state["round_num"]) % 3 == 0 and not living.is_empty():
		_fire("round_third", state, living[0])
	var intents := {}
	if not living.is_empty():
		for mi in monsters.size():
			if float(monsters[mi]["hp"]) > 0:
				intents[mi] = _roll_intent(state, mi, living)
	state["intents"] = intents
	state["turn_idx"] = 0


## What monster `mi` will do this round: attack (or wind up / land a heavy
## blow, rolled above), or now and then a move from its kit, never two
## rounds running. {"kind", "target": hero id or ""}.
func _roll_intent(state: Dictionary, mi: int, living: Array[Hero]) -> Dictionary:
	var m: Dictionary = state["monsters"][mi]
	if not m.has("kit"):
		m["kit"] = monster_kit(m)
	var round_num := int(state["round_num"])
	var kind := "attack"
	if not m.get("_winding", false) and not m.get("_charged", false) and int(m.get("_special_round", -9)) < round_num - 1 and not GameState.run.get("training", false):
		var kit: Array = m["kit"]
		if not kit.is_empty():
			var pick := str(kit[randi() % kit.size()])
			var chance := GameData.INTENT_SPECIAL_CHANCE
			var monsters: Array = state["monsters"]
			match pick:
				"mend":
					chance = 0.6 if monsters.any(func(o): return float(o["hp"]) > 0 and float(o["hp"]) < float(o["max_hp"]) * 0.7) else 0.0
				"roar":
					chance = chance if int(m.get("_roars", 0)) < 2 else 0.0
			if randf() < chance:
				kind = pick
				m["_special_round"] = round_num
	var target := ""
	match kind:
		"attack", "curse":
			target = weighted_formation_target(living).id
		"snipe":
			var back: Array = living.filter(func(h): return h.formation == "back")
			var pool: Array = back if not back.is_empty() else living
			var best: Hero = pool[0]
			for h in pool:
				if float(h.hp) / max_hp(h) < float(best.hp) / max_hp(best):
					best = h
			target = best.id
	return {"kind": kind, "target": target}


## One hero hit on monster `ti` at `mult` of their share of the party's
## damage (the basic attack is mult 1). Armor and wards soak it and reflect
## bites back unless `pierce`. Returns the damage dealt.
func _hero_hit(state: Dictionary, h: Hero, ti: int, mult: float, pierce: bool = false) -> float:
	var log: Array[String] = state["log"]
	var monsters: Array = state["monsters"]
	var formation_mult := 1.0 if bool(monsters[ti].get("is_main", true)) else 0.75
	var weaken := 1.0 - GameData.CURSE_WEAKEN if state.get("_weakened", {}).has(h.id) else 1.0
	var marked := 1.0 + float(monsters[ti].get("_marked", 0.0))
	match str(state.get("_twist", "")):
		"executioner":
			if float(monsters[ti]["hp"]) < float(monsters[ti]["max_hp"]) * GameData.TWIST_EXECUTE_BELOW:
				mult *= 1.0 + GameData.TWIST_EXECUTE
		"opener":
			if not state.get("_opened", {}).has(h.id):
				mult *= 1.0 + GameData.TWIST_OPENER
	var hit := {"target": monsters[ti]}
	hit["dealt"] = dmg_of(h) / float(state["raw_sum"]) * float(state["team_dmg_base"]) * float(state["_attack_mult"]) * formation_mult * mult * weaken * marked * (1.0 + hero_cond_stat(h, "dmg_pct", state, hit))
	_fire("before_hit", state, h, hit)
	var dealt: float = hit["dealt"]
	var armor := float(monsters[ti].get("armor", 0.0))
	if armor > 0.0 and dealt > 0.0 and not pierce:
		var blocked: float = dealt * armor
		dealt -= blocked
		monsters[ti]["armor"] = maxf(0.0, armor - GameData.ARMOR_SUNDER)
		log.append("%s's armor turns aside %d." % [monsters[ti]["name"], int(round(blocked))])
	var m_shields: Dictionary = state["monster_shields"]
	if dealt > 0.0 and float(m_shields.get(ti, 0.0)) > 0.0 and not pierce:
		var m_have: float = float(m_shields[ti])
		var m_absorbed: float = min(m_have, dealt)
		m_shields[ti] = m_have - m_absorbed
		dealt -= m_absorbed
		log.append("%s's ward absorbs %d damage." % [monsters[ti]["name"], int(round(m_absorbed))])
	monsters[ti]["hp"] = float(monsters[ti]["hp"]) - round(dealt)
	log.append("%s strikes %s for %d." % [h.name, monsters[ti]["name"], round(dealt)])
	var target_ability: Dictionary = monsters[ti].get("ability", {})
	if target_ability.get("kind") == "reflect" and dealt > 0.0 and not pierce:
		var reflected: int = max(1, int(round(dealt * float(target_ability["value"]))))
		h.hp = max(0, h.hp - reflected)
		log.append("%s's surface reflects %d damage back at %s." % [monsters[ti]["name"], reflected, h.name])
	hit["dealt"] = dealt
	var steal := float(state.get("_lifesteal", 0.0))
	if steal > 0.0 and dealt > 0.0 and h.hp > 0:
		h.hp = mini(max_hp(h), h.hp + int(round(dealt * steal)))
	_fire("after_hit", state, h, hit)
	return dealt


## A role skill (GameData.ROLE_SKILLS) — Momentum already paid.
func _use_role_skill(state: Dictionary, h: Hero, sk: Dictionary, target_idx: int) -> void:
	var log: Array[String] = state["log"]
	var party: Array[Hero] = state["party"]
	var monsters: Array = state["monsters"]
	var val := float(sk["value"])
	log.append("%s uses %s!" % [h.name, sk["name"]])
	_tally(state, "skills")
	if target_idx < 0 or target_idx >= monsters.size() or float(monsters[target_idx]["hp"]) <= 0:
		target_idx = _first_living_monster_idx(monsters)
	var living: Array[Hero] = []
	living.assign(party.filter(func(x): return x.hp > 0))
	var arch := hero_main_arch(h)
	state["_twist"] = arch
	_role_skill_effect(state, h, sk, target_idx, val, living)
	state["_twist"] = ""
	match arch:
		"guardian":
			if not living.is_empty():
				var low: Hero = living[0]
				for x in living:
					if float(x.hp) / max_hp(x) < float(low.hp) / max_hp(low):
						low = x
				var shields: Dictionary = state["hero_shields"]
				shields[low.id] = float(shields.get(low.id, 0.0)) + max_hp(low) * GameData.TWIST_WARD
		"sustain":
			h.hp = mini(max_hp(h), h.hp + int(round(max_hp(h) * GameData.TWIST_HEAL)))
		"evasion":
			state.get_or_add("_evade_next", {})[h.id] = true
		"attrition":
			if target_idx >= 0 and target_idx < monsters.size() and float(monsters[target_idx]["hp"]) > 0 and str(sk["target"]) == "foe":
				_burn_foe(state, target_idx, dmg_of(h) / float(state["raw_sum"]) * float(state["team_dmg_base"]) * GameData.TWIST_BURN, 2)
		"opener":
			state.get_or_add("_opened", {})[h.id] = true


## A foe burns for `per_round` damage at each round's end for `rounds` rounds
## (the stronger burn wins).
func _burn_foe(state: Dictionary, i: int, per_round: float, rounds: int) -> void:
	var burns: Dictionary = state.get_or_add("_m_burn", {})
	var old: Dictionary = burns.get(i, {})
	if old.is_empty() or float(old["dmg"]) * int(old["rounds"]) < per_round * rounds:
		burns[i] = {"dmg": per_round, "rounds": rounds}


func _role_skill_effect(state: Dictionary, h: Hero, sk: Dictionary, target_idx: int, val: float, living: Array[Hero]) -> void:
	var log: Array[String] = state["log"]
	var monsters: Array = state["monsters"]
	match str(sk["effect"]):
		"bash":
			if target_idx >= 0:
				_hero_hit(state, h, target_idx, val)
				var m: Dictionary = monsters[target_idx]
				if float(m["hp"]) > 0:
					var broke: bool = m.get("_winding", false) or m.get("_charged", false)
					m["_winding"] = false
					m["_charged"] = false
					if str(m.get("tier", "")) != "boss":
						state.get_or_add("_m_stunned", {})[target_idx] = true
						log.append("%s is stunned!" % m["name"])
					elif broke:
						log.append("%s's wind-up is broken!" % m["name"])
		"taunt":
			state["_taunt"] = h.id
			state["_taunt_cut"] = val
			log.append("Every foe turns on %s." % h.name)
		"pierce", "strike":
			if target_idx >= 0:
				_hero_hit(state, h, target_idx, val, str(sk["effect"]) == "pierce")
		"backstab":
			if target_idx >= 0:
				var m2: Dictionary = monsters[target_idx]
				var exposed: bool = m2.get("_winding", false) or m2.get("_charged", false) or float(m2["hp"]) < float(m2["max_hp"]) * 0.5
				_hero_hit(state, h, target_idx, val + (1.0 if exposed else 0.0))
		"volley", "nova":
			for i in monsters.size():
				if float(monsters[i]["hp"]) > 0:
					_hero_hit(state, h, i, val)
					if str(sk["effect"]) == "nova" and (monsters[i].get("_winding", false) or monsters[i].get("_charged", false)):
						monsters[i]["_winding"] = false
						monsters[i]["_charged"] = false
						log.append("%s's wind-up is broken!" % monsters[i]["name"])
		"heal":
			if not living.is_empty():
				var low: Hero = living[0]
				for x in living:
					if float(x.hp) / max_hp(x) < float(low.hp) / max_hp(low):
						low = x
				var healed: int = mini(max_hp(low) - low.hp, int(round(max_hp(low) * val)))
				low.hp += healed
				log.append("%s is healed for %d." % [low.name, healed])
		"sanctuary":
			var shields: Dictionary = state["hero_shields"]
			for x in living:
				shields[x.id] = float(shields.get(x.id, 0.0)) + max_hp(x) * val
				for key in ["hero_poison", "hero_burn", "_chilled", "_stunned", "_weakened"]:
					state.get(key, {}).erase(x.id)
			log.append("A sanctuary shelters the party.")
		"smoke":
			state["_smoke"] = float(state.get("_smoke", 0.0)) + val
			log.append("Smoke fills the field — the party is hard to hit.")


## One hero's pending action (attack/defend/ability) from state["pending_actions"]
## — the per-hero body of the old batched hero phase, unchanged math, just
## scoped to a single hero's turn instead of looping the whole living party.
func _resolve_hero_action(state: Dictionary, h: Hero) -> void:
	var log: Array[String] = state["log"]
	var party: Array[Hero] = state["party"]
	var monsters: Array = state["monsters"]
	var pending: Dictionary = state["pending_actions"]
	var attack_mult: float = float(state["_attack_mult"])
	var escalate_mult: float = float(state["_escalate_mult"])
	var raw_sum: float = state["raw_sum"]

	var monsters_hp_before: Array[float] = []
	for m in monsters:
		monsters_hp_before.append(float(m["hp"]))

	var act: Dictionary = pending.get(h.id, {"action": "attack", "target": 0})
	var action: String = str(act.get("action", "attack"))
	# A skill the hero can't pay for (or from the wrong row) falls back to an attack.
	if (action == "ability" or action.begins_with("skill:")) and action_block(state, h, action) != "":
		action = "attack"
	if action == "attack":
		var target_idx: int = int(act.get("target", 0))
		if target_idx < 0 or target_idx >= monsters.size() or float(monsters[target_idx]["hp"]) <= 0:
			target_idx = _first_living_monster_idx(monsters)
		if target_idx >= 0:
			var reach := GameData.BACK_ROW_MELEE_MULT if h.formation == "back" and GameData.MELEE_ROLES.has(h.cls_id) else 1.0
			_hero_hit(state, h, target_idx, reach)
			gain_momentum(state, 1)
	elif action.begins_with("skill:"):
		gain_momentum(state, -int(action_cost(action)[0]))
		_use_role_skill(state, h, GameData.find_role_skill(action.substr(6)), int(act.get("target", 0)))
	elif action == "defend":
		state["_defending"][h.id] = true
	elif action == "swap":
		h.formation = "back" if h.formation != "back" else "front"
		log.append("%s moves to the %s row." % [h.name, h.formation])
	elif action.begins_with("tonic") and GameState.tonic_count(_tonic_id(action)) > 0:
		var tid := _tonic_id(action)
		var patient := _find_party_hero(party, str(act.get("ally", "")))
		if patient == null or patient.hp <= 0:
			patient = h
		GameState.tonics[tid] = GameState.tonic_count(tid) - 1
		match tid:
			"healing":
				for key in ["hero_poison", "hero_burn", "_chilled", "_stunned", "_weakened"]:
					state.get(key, {}).erase(patient.id)
				var healed: int = min(max_hp(patient) - patient.hp, int(round(max_hp(patient) * GameData.TONIC_HEAL_PCT)))
				patient.hp += healed
				log.append("%s gives %s a Healing Tonic: +%d HP." % [h.name, patient.name, healed])
			"iron":
				var ward := max_hp(patient) * GameData.TONIC_WARD_PCT
				var shields: Dictionary = state["hero_shields"]
				shields[patient.id] = float(shields.get(patient.id, 0.0)) + ward
				log.append("%s gives %s an Iron Tonic: a %d ward." % [h.name, patient.name, int(round(ward))])
			"focus":
				gain_momentum(state, GameData.TONIC_FOCUS)
				log.append("%s drinks a Focus Tonic: +%d Momentum." % [h.name, GameData.TONIC_FOCUS])
	elif action == "guard":
		# Until the round ends, attacks aimed at the ally hit this hero
		# instead, 25% weaker (see _resolve_monster_action).
		var ally := _find_party_hero(party, str(act.get("ally", "")))
		if ally and ally != h and ally.hp > 0:
			var guards: Dictionary = state.get("_guarding", {})
			guards[ally.id] = h.id
			state["_guarding"] = guards
			log.append("%s moves to guard %s." % [h.name, ally.name])
	elif action == "ability" or (action == "call" and GameState.champion_call_ready(h)):
		_tally(state, "abilities")
		var team_dmg_base: float = float(state["team_dmg_base"])
		var ab: Dictionary
		if action == "call":
			ab = GameState.champion_call(h)
			GameState.run["champion_calls"] = int(GameState.run.get("champion_calls", 0)) + 1
			GameState.run["champion_call_used"] = true
		else:
			gain_momentum(state, -GameData.ABILITY_MOMENTUM_COST)
			ab = GameData.SUBCLASS_ABILITIES[h.pool_id]
		var eff: String = ab["effect"]
		var val: float = float(ab["value"])
		# Focus: ability power strengthens the effect — a damage-cutting
		# debuff cuts deeper, a damage multiplier grows, the rest scale up.
		var ap := hero_skill_total(h, "ability_power")
		if ap != 0.0:
			match eff:
				"monster_dmg_mult", "debuff_lowest":
					val = maxf(0.2, 1.0 - (1.0 - val) * (1.0 + ap))
				"team_dmg_mult":
					val = 1.0 + (val - 1.0) * (1.0 + ap)
				_:
					val *= 1.0 + ap
		log.append("%s uses %s%s!" % [h.name, ab["name"], " (Awakened)" if h.ability_awakened else ""])
		var living: Array[Hero] = []
		living.assign(party.filter(func(hh): return hh.hp > 0))
		match eff:
			"mend_burst":
				for h2 in party:
					if h2.hp > 0:
						h2.hp = min(max_hp(h2), h2.hp + int(round(max_hp(h2) * val)))
				log.append("The party mends.")
			"monster_dmg_mult":
				for m in monsters:
					m["dmg"] = float(m["dmg"]) * val
				log.append("The enemies' strength is sapped.")
			"team_dmg_mult":
				state["team_dmg_base"] = team_dmg_base * val
			"burst_lowest":
				var idx := _lowest_hp_living_monster_idx(monsters)
				if idx >= 0:
					var burst: float = team_dmg_base * escalate_mult * val
					monsters[idx]["hp"] = float(monsters[idx]["hp"]) - round(burst)
					log.append("A burst lands on %s for %d!" % [monsters[idx]["name"], round(burst)])
			"cleave_burst":
				for m in monsters:
					if float(m["hp"]) > 0:
						var dealt2: float = team_dmg_base * escalate_mult * val
						m["hp"] = float(m["hp"]) - round(dealt2)
				log.append("A wave of damage sweeps every foe.")
			"execute_burst":
				var idx2 := _lowest_hp_living_monster_idx(monsters)
				if idx2 >= 0:
					var missing_frac: float = 1.0 - float(monsters[idx2]["hp"]) / float(monsters[idx2]["max_hp"])
					var dealt3: float = team_dmg_base * val * (1.0 + missing_frac)
					monsters[idx2]["hp"] = float(monsters[idx2]["hp"]) - round(dealt3)
					log.append("A finishing blow strikes %s for %d!" % [monsters[idx2]["name"], round(dealt3)])
			"shield_lowest":
				var shielded := _shield_lowest(state, val)
				if not shielded.is_empty():
					log.append("%s is shielded for %d." % [shielded[0].name, int(round(shielded[1]))])
			"reset_cooldowns":
				gain_momentum(state, 7)
				log.append("+7 Momentum.")
			"dodge_surge":
				state["dodge"] = min(0.6, float(state["dodge"]) + val)
				log.append("The party moves lighter on its feet.")
			"escalate_surge":
				state["escalate"] = float(state["escalate"]) + val
				log.append("Every attack counts for more now.")
			"counter_surge":
				state["counter"] = min(0.6, float(state["counter"]) + val)
				log.append("The party stands ready to strike back.")
			"wipe_guard_surge":
				state["wipe_guard"] = min(0.9, float(state["wipe_guard"]) + val)
				log.append("The party braces against disaster.")
			"self_sac_burst":
				var idx3 := _lowest_hp_living_monster_idx(monsters)
				if idx3 >= 0:
					var self_cost: int = max(1, int(round(max_hp(h) * 0.15)))
					h.hp = max(1, h.hp - self_cost)
					var burst2: float = team_dmg_base * escalate_mult * val
					monsters[idx3]["hp"] = float(monsters[idx3]["hp"]) - round(burst2)
					log.append("%s sacrifices %d HP for a burst on %s for %d!" % [h.name, self_cost, monsters[idx3]["name"], round(burst2)])
			"debuff_lowest":
				var idx4 := _lowest_hp_living_monster_idx(monsters)
				if idx4 >= 0:
					monsters[idx4]["dmg"] = float(monsters[idx4]["dmg"]) * val
					log.append("%s is crippled, dealing far less damage." % monsters[idx4]["name"])
			"team_shield_burst":
				var shields2: Dictionary = state["hero_shields"]
				for hh3 in living:
					shields2[hh3.id] = float(shields2.get(hh3.id, 0.0)) + max_hp(hh3) * val
				log.append("The whole party is shielded.")
			"execute_all_low":
				for m2 in monsters:
					if float(m2["hp"]) > 0:
						var missing_frac2: float = 1.0 - float(m2["hp"]) / float(m2["max_hp"])
						if missing_frac2 >= 0.5:
							var dealt4: float = team_dmg_base * val * (1.0 + missing_frac2)
							m2["hp"] = float(m2["hp"]) - round(dealt4)
				log.append("Every wounded foe is finished off.")
			"stun_strike", "execute_threshold", "armor_break", "double_strike", "mark_target", "freeze_target":
				var ti := int(act.get("target", 0))
				if ti < 0 or ti >= monsters.size() or float(monsters[ti]["hp"]) <= 0:
					ti = _first_living_monster_idx(monsters)
				if ti >= 0:
					var tm: Dictionary = monsters[ti]
					var boss: bool = str(tm.get("tier", "")) == "boss"
					match eff:
						"stun_strike":
							tm["hp"] = float(tm["hp"]) - round(team_dmg_base * escalate_mult * val)
							tm["_winding"] = false
							tm["_charged"] = false
							if not boss:
								state.get_or_add("_m_stunned", {})[ti] = 1
							log.append("%s is %s!" % [tm["name"], "stunned" if not boss else "staggered — its wind-up breaks"])
						"freeze_target":
							tm["_winding"] = false
							tm["_charged"] = false
							state.get_or_add("_m_stunned", {})[ti] = 1 if boss else 2
							log.append("%s is frozen solid!" % tm["name"])
						"execute_threshold":
							if not boss and float(tm["hp"]) <= float(tm["max_hp"]) * 0.35:
								tm["hp"] = 0.0
								log.append("%s is finished off!" % tm["name"])
							else:
								tm["hp"] = float(tm["hp"]) - round(team_dmg_base * escalate_mult * val)
						"armor_break":
							tm["armor"] = 0.0
							state["monster_shields"].erase(ti)
							tm["_marked"] = float(tm.get("_marked", 0.0)) + 0.15
							tm["hp"] = float(tm["hp"]) - round(team_dmg_base * escalate_mult * val * 0.5)
							log.append("%s's defences shatter." % tm["name"])
						"mark_target":
							tm["_marked"] = float(tm.get("_marked", 0.0)) + val
							log.append("%s is marked." % tm["name"])
						"double_strike":
							_hero_hit(state, h, ti, val)
							if float(tm["hp"]) > 0:
								_hero_hit(state, h, ti, val)
			"burn_all":
				for bi in monsters.size():
					if float(monsters[bi]["hp"]) > 0:
						_burn_foe(state, bi, team_dmg_base * val * 0.5, GameData.MONSTER_BURN_ROUNDS)
				log.append("Every foe is set ablaze.")
			"chain_lightning":
				for k in 3:
					var alive_idx: Array = []
					for ci in monsters.size():
						if float(monsters[ci]["hp"]) > 0:
							alive_idx.append(ci)
					if alive_idx.is_empty():
						break
					var ci2: int = alive_idx[randi() % alive_idx.size()]
					monsters[ci2]["hp"] = float(monsters[ci2]["hp"]) - round(team_dmg_base * escalate_mult * val)
				log.append("Lightning leaps between the foes.")
			"ward_break":
				for wi in monsters.size():
					if float(monsters[wi]["hp"]) > 0:
						monsters[wi]["armor"] = 0.0
						monsters[wi]["hp"] = float(monsters[wi]["hp"]) - round(team_dmg_base * escalate_mult * val * 0.5)
				state["monster_shields"] = {}
				log.append("Every ward and plate is torn away.")
			"riposte":
				state.get_or_add("_riposte", {})[h.id] = {"left": 3, "dmg": team_dmg_base * val}
				log.append("%s stands ready to answer every blow." % h.name)
			"taunt_ward":
				state["_taunt"] = h.id
				state["_taunt_cut"] = 0.3
				var tsh: Dictionary = state["hero_shields"]
				tsh[h.id] = float(tsh.get(h.id, 0.0)) + max_hp(h) * val
				log.append("%s plants their feet — every foe turns on them." % h.name)
			"undying":
				state.get_or_add("_undying", {})[h.id] = true
				log.append("%s will not fall this round." % h.name)
			"revive":
				var fallen: Array = party.filter(func(x): return x.hp <= 0)
				if not fallen.is_empty():
					var rv: Hero = fallen[0]
					rv.hp = maxi(1, int(round(max_hp(rv) * val)))
					log.append("%s is raised back to their feet!" % rv.name)
				elif not living.is_empty():
					var low2: Hero = living[0]
					for x in living:
						if float(x.hp) / max_hp(x) < float(low2.hp) / max_hp(low2):
							low2 = x
					low2.hp = mini(max_hp(low2), low2.hp + int(round(max_hp(low2) * val)))
					log.append("%s is mended." % low2.name)
			"cleanse_heal":
				for x in living:
					x.hp = mini(max_hp(x), x.hp + int(round(max_hp(x) * val)))
					for key in ["hero_poison", "hero_burn", "_chilled", "_stunned", "_weakened"]:
						state.get(key, {}).erase(x.id)
				log.append("A cleansing light washes over the party.")
			"shield_wall_front":
				var wsh: Dictionary = state["hero_shields"]
				for x in living:
					if x.formation != "back":
						wsh[x.id] = float(wsh.get(x.id, 0.0)) + max_hp(x) * val
				log.append("The front row locks shields.")
			"evasion_round":
				state["_smoke"] = float(state.get("_smoke", 0.0)) + val
				log.append("The party slips out of reach.")
			"trap":
				state["_trap"] = float(state.get("_trap", 0.0)) + team_dmg_base * val
				log.append("A snare is set.")
			"lifesteal_surge":
				state["_lifesteal"] = float(state.get("_lifesteal", 0.0)) + val
				log.append("Every wound the party deals now feeds it.")
			"blood_price":
				h.hp = maxi(1, h.hp - int(round(max_hp(h) * 0.2)))
				gain_momentum(state, 3)
				state["team_dmg_base"] = float(state["team_dmg_base"]) * (1.0 + val)
				log.append("%s pays in blood: +3 Momentum, and the party hits harder." % h.name)
			"hp_drain_burst":
				var idx5 := _lowest_hp_living_monster_idx(monsters)
				if idx5 >= 0:
					var burst3: float = team_dmg_base * escalate_mult * val
					monsters[idx5]["hp"] = float(monsters[idx5]["hp"]) - round(burst3)
					var drained: int = max(1, int(round(burst3 * 0.4)))
					h.hp = min(max_hp(h), h.hp + drained)
					log.append("%s drains %d from %s, healing %d!" % [h.name, round(burst3), monsters[idx5]["name"], drained])
			"mend_shield_hybrid":
				if not living.is_empty():
					var lowest2: Hero = living[0]
					for hh4 in living:
						if hh4.hp < lowest2.hp:
							lowest2 = hh4
					lowest2.hp = min(max_hp(lowest2), lowest2.hp + int(round(max_hp(lowest2) * val)))
					var shields3: Dictionary = state["hero_shields"]
					var amt2: float = max_hp(lowest2) * val * 0.6
					shields3[lowest2.id] = float(shields3.get(lowest2.id, 0.0)) + amt2
					log.append("%s is mended and shielded." % lowest2.name)

		# Awakening (GameState.awaken_ability) grants a bucketed rider on top
		# of the primary effect above, keyed by GameData's ABILITY_AWAKENING_BUCKET
		# — see its doc comment for why buckets instead of one flat number or
		# 18 fully bespoke riders.
		if h.ability_awakened:
			var bucket: String = GameData.ABILITY_AWAKENING_BUCKET.get(eff, "buff")
			match bucket:
				"buff":
					gain_momentum(state, GameData.ABILITY_AWAKENING_MOMENTUM)
				"single_dmg":
					for m3 in monsters:
						m3["dmg"] = float(m3["dmg"]) * 0.97
				"aoe_dmg":
					state["dodge"] = min(0.6, float(state["dodge"]) + 0.08)
				"support":
					var shields4: Dictionary = state["hero_shields"]
					shields4[h.id] = float(shields4.get(h.id, 0.0)) + max_hp(h) * 0.15
				"utility":
					state["escalate"] = float(state["escalate"]) + 0.02

	# Checked against just this hero's own action, so on_kill effects (the
	# Lantern's shield included) trigger on any hero's kill regardless of turn
	# order. Fires once per action, however many foes that action dropped.
	var kills := 0
	for i in monsters.size():
		if monsters_hp_before[i] > 0.0 and float(monsters[i]["hp"]) <= 0.0:
			kills += 1
	if kills > 0:
		h.history["kills"] = int(h.history.get("kills", 0)) + kills
		gain_momentum(state, 1)
		_fire("on_kill", state, h)
	# Per-fight tallies for the victory screen (damage dealt, kills).
	var dealt_now := 0.0
	for i in monsters.size():
		dealt_now += maxf(0.0, monsters_hp_before[i] - maxf(0.0, float(monsters[i]["hp"])))
	var dealt_map: Dictionary = state.get("_dealt", {})
	dealt_map[h.id] = float(dealt_map.get(h.id, 0.0)) + dealt_now
	state["_dealt"] = dealt_map
	var kill_map: Dictionary = state.get("_kills", {})
	kill_map[h.id] = int(kill_map.get(h.id, 0)) + kills
	state["_kills"] = kill_map


## One living monster's retaliation — the per-monster body of the old batched
## monster phase, unchanged math, scoped to a single monster's turn. `round_num`
## still gates warded/enrage exactly as it did in the batched version (a
## round-scoped effect, not a per-turn one).
func _resolve_monster_action(state: Dictionary, i: int) -> void:
	var log: Array[String] = state["log"]
	var party: Array[Hero] = state["party"]
	var monsters: Array = state["monsters"]
	var round_num: int = int(state["round_num"])
	var m: Dictionary = monsters[i]

	if round_num == 1 and party_has_unique_relic("stopped_clock"):
		log.append("%s is frozen in time by the Stopped Clock." % m["name"])
		return
	var escort: Dictionary = state.get("escort", {})
	if not escort.is_empty() and float(escort["hp"]) > 0.0 and randf() < 0.2:
		var escort_dmg: int = max(1, int(round(float(m["dmg"]) * 0.6)))
		escort["hp"] = max(0.0, float(escort["hp"]) - escort_dmg)
		log.append("The %s strikes %s for %d!" % [m["name"], str(escort["name"]), escort_dmg])
		if float(escort["hp"]) <= 0.0:
			log.append("%s doesn't survive the fight." % str(escort["name"]))
		return

	var stunned: Dictionary = state.get("_m_stunned", {})
	if stunned.has(i):
		var left := int(stunned[i]) - 1
		if left <= 0:
			stunned.erase(i)
		else:
			stunned[i] = left
		log.append("%s is stunned and loses its action." % m["name"])
		return
	if m.get("_winding", false):
		m["_winding"] = false
		m["_charged"] = true
		log.append("%s gathers its strength — a heavy blow is coming!" % m["name"])
		return
	var alive_now: Array[Hero] = []
	alive_now.assign(party.filter(func(h): return h.hp > 0))
	if alive_now.is_empty():
		return
	var it := _intent_of(state, i)
	var kind := str(it.get("kind", "attack"))
	if m.get("_charged", false):
		kind = "attack"   # a charged blow always lands as an attack
	match kind:
		"ward", "mend":
			var low := -1
			for j in monsters.size():
				if float(monsters[j]["hp"]) > 0 and (low < 0 or float(monsters[j]["hp"]) / float(monsters[j]["max_hp"]) < float(monsters[low]["hp"]) / float(monsters[low]["max_hp"])):
					low = j
			if low >= 0:
				if kind == "ward":
					var amt: float = round(float(monsters[low]["max_hp"]) * GameData.WARD_PCT)
					var ws: Dictionary = state["monster_shields"]
					ws[low] = float(ws.get(low, 0.0)) + amt
					log.append("%s wards %s for %d." % [m["name"], monsters[low]["name"], amt])
				else:
					var pct := float(m.get("ability", {}).get("value", GameData.MEND_PCT)) if m.get("ability", {}).get("kind") == "healer" else GameData.MEND_PCT
					var heal: float = round(float(monsters[low]["max_hp"]) * pct)
					monsters[low]["hp"] = minf(float(monsters[low]["max_hp"]), float(monsters[low]["hp"]) + heal)
					log.append("%s mends %s for %d." % [m["name"], monsters[low]["name"], heal])
					_tally(state, "enemy_heal", heal)
			return
		"roar":
			for o in monsters:
				if float(o["hp"]) > 0:
					o["dmg"] = float(o["dmg"]) * GameData.ROAR_MULT
			m["_roars"] = int(m.get("_roars", 0)) + 1
			log.append("%s roars — every foe hits harder!" % m["name"])
			return
		"curse":
			var ct: Hero = _find_party_hero(party, str(it.get("target", "")))
			if ct == null or ct.hp <= 0:
				ct = alive_now[randi() % alive_now.size()]
			state.get_or_add("_weakened", {})[ct.id] = GameData.CURSE_ROUNDS
			log.append("%s curses %s: %d%% less damage for %d rounds." % [m["name"], ct.name, int(GameData.CURSE_WEAKEN * 100), GameData.CURSE_ROUNDS])
			return
		"sweep":
			log.append("%s sweeps the whole party!" % m["name"])
			for h in alive_now:
				if h.hp > 0:
					_monster_strike(state, i, h, GameData.SWEEP_MULT, false)
			return
	# The target was rolled at round start (state["intents"]) so the combat
	# screen can show it; re-roll only if that hero has since dropped.
	var target: Hero = _find_party_hero(party, str(it.get("target", "")))
	if target == null or target.hp <= 0:
		target = weighted_formation_target(alive_now)
	_monster_strike(state, i, target, GameData.SNIPE_MULT if kind == "snipe" else 1.0, true)


## Monster `i` hits `target` for `mult` of its hit. `aimed` hits can be
## redirected (Taunt, intercept effects, Guard); a sweep's can't.
func _monster_strike(state: Dictionary, i: int, target: Hero, mult: float, aimed: bool) -> void:
	var log: Array[String] = state["log"]
	var party: Array[Hero] = state["party"]
	var m: Dictionary = state["monsters"][i]
	var round_num: int = int(state["round_num"])
	var alive_now: Array[Hero] = []
	alive_now.assign(party.filter(func(h): return h.hp > 0))
	var guard: Hero = null
	var taunted := false
	if aimed and float(state.get("_trap", 0.0)) > 0.0:
		var trap_dmg := float(state["_trap"])
		state["_trap"] = 0.0
		m["hp"] = float(m["hp"]) - round(trap_dmg)
		log.append("%s springs the snare: %d damage, and its attack is lost!" % [m["name"], int(round(trap_dmg))])
		return
	if aimed:
		var taunter := _find_party_hero(party, str(state.get("_taunt", "")))
		if taunter and taunter.hp > 0:
			target = taunter
			taunted = true
		else:
			var aim := {"target": target, "attacker": m}
			for ally in alive_now:
				if ally != target:
					_fire("ally_targeted", state, ally, aim)
					if aim["target"] != target:
						break
			target = aim["target"]
			guard = guard_of(state, target)
			if guard:
				log.append("%s takes the blow meant for %s!" % [guard.name, target.name])
				_proc(state, guard, "Guard!")
				target = guard
	var mech: Dictionary = m.get("mechanic", {})
	var mech2: Dictionary = m.get("mechanic2", {})
	var ability: Dictionary = m.get("ability", {})
	var back: float = _monster_hit(m, round_num) * mult
	var heavy_blow: bool = m.get("_charged", false)
	if heavy_blow:
		m["_charged"] = false
		m["_windup_cd"] = 1
		back *= GameData.HEAVY_BLOW_MULT
	if guard:
		back *= GUARD_DAMAGE_MULT
		gain_momentum(state, 2 if heavy_blow else 1)
	if taunted:
		back *= 1.0 - float(state.get("_taunt_cut", 0.0))
	var undying: bool = state.get("_undying", {}).has(target.id)
	if undying:
		back *= 0.5
	var warded: bool = (mech.get("id") == "warded" or mech2.get("id") == "warded") and round_num <= 2
	if state["_defending"].has(target.id):
		back *= 0.5
		gain_momentum(state, 2 if heavy_blow else 1)
	var effective_dodge: float = float(state["dodge"]) + float(state.get("_smoke", 0.0)) + hero_cond_stat(target, "dodge_pct", state, {"attacker": m})
	var evaded := false
	if state.get("_evade_next", {}).has(target.id):
		state["_evade_next"].erase(target.id)
		log.append("%s saw it coming and slips the blow!" % target.name)
		evaded = true
	elif not warded and effective_dodge > 0.0 and randf() < effective_dodge:
		log.append("%s evades %s's retaliation!" % [target.name, m["name"]])
		evaded = true
	var heavy_hit: bool = back >= float(max_hp(target)) * 0.25
	if evaded:
		back = 0.0
	if evaded or heavy_hit:
		_fire("evade_or_heavy", state, target, {"attacker": m})
	var shields: Dictionary = state["hero_shields"]
	if back > 0.0 and float(shields.get(target.id, 0.0)) > 0.0:
		var have: float = float(shields[target.id])
		var absorbed: float = min(have, back)
		shields[target.id] = have - absorbed
		back -= absorbed
		log.append("%s's shield absorbs %d damage." % [target.name, int(round(absorbed))])
	if back > 0.0:
		var dealt_back: int = int(round(back))
		var is_last_hero := alive_now.size() == 1
		if dealt_back >= target.hp and is_last_hero and not state["wipe_guard_used"] and float(state["wipe_guard"]) > 0.0:
			state["wipe_guard_used"] = true
			target.hp = max(1, int(round(float(max_hp(target)) * float(state["wipe_guard"]))))
			log.append("Last Stand! %s clings to life with %d HP." % [target.name, target.hp])
		else:
			target.hp = max(1 if undying else 0, target.hp - dealt_back)
			log.append("The %s hits %s for %d." % [m["name"], target.name, dealt_back])
			_tally(state, "taken", dealt_back)
			if heavy_blow and not state["_defending"].has(target.id):
				_tally(state, "undefended_heavy")
				_tally(state, "heavy_dmg", dealt_back)
			if heavy_blow and target.hp > 0 and not state["_defending"].has(target.id):
				state.get_or_add("_stunned", {})[target.id] = true
				log.append("%s is stunned by the blow!" % target.name)
			var status := str(m.get("status", ""))
			if status != "" and target.hp > 0 and randf() < float(GameData.STATUS_INFO[status]["chance"]):
				var info: Dictionary = GameData.STATUS_INFO[status]
				if status == "burn":
					state.get_or_add("hero_burn", {})[target.id] = {"rounds": int(info["rounds"]), "value": float(info["value"])}
					log.append("%s is set ablaze!" % target.name)
				elif status == "chill":
					state.get_or_add("_chilled", {})[target.id] = int(info["rounds"]) + 1
					log.append("%s is chilled — they'll act late next round." % target.name)
			if ability.get("kind") == "poison" and target.hp > 0:
				state["hero_poison"][target.id] = {"rounds": 2, "value": float(ability["value"])}
				log.append("%s is poisoned!" % target.name)
			if ability.get("kind") == "drain" and dealt_back > 0:
				var drained: int = max(1, int(round(dealt_back * float(ability["value"]))))
				m["hp"] = min(float(m["max_hp"]), float(m["hp"]) + drained)
				log.append("%s drains %d HP from the blow." % [m["name"], drained])
			if target.hp <= 0:
				log.append("%s is knocked out!" % target.name)
				_fire("ally_down", state, target)
	var rip: Dictionary = state.get("_riposte", {}).get(target.id, {})
	if not rip.is_empty() and target.hp > 0 and float(m["hp"]) > 0:
		m["hp"] = float(m["hp"]) - round(float(rip["dmg"]))
		log.append("%s ripostes, striking %s for %d!" % [target.name, m["name"], int(round(float(rip["dmg"])))])
		rip["left"] = int(rip["left"]) - 1
		if int(rip["left"]) <= 0:
			state["_riposte"].erase(target.id)


# ---------------- Defeat analysis ----------------

## Fight tallies for the "why you lost" card (state["_stats"]).
func _tally(state: Dictionary, key: String, amount: float = 1.0) -> void:
	var st: Dictionary = state.get_or_add("_stats", {})
	st[key] = float(st.get(key, 0.0)) + amount


## The top reasons a fight was lost, each [title, tip], most important first.
func defeat_reasons(state: Dictionary) -> Array:
	var st: Dictionary = state.get("_stats", {})
	var party: Array = state["party"]
	var out: Array = []   # [weight, title, tip]
	var power := party_power(party)
	var rec := int(state.get("diff", {}).get("rec_power", 0))
	if state.get("is_boss", false):
		rec = int(round(rec * 1.1))
	if rec > 0 and power < rec * 0.9:
		out.append([3.0 + float(rec - power) / rec * 5.0, "Underpowered: party power %d vs %d recommended" % [power, rec],
			"Level heroes, train attributes and upgrade gear at camp, or pick an easier rift for now."])
	var heavy := int(st.get("undefended_heavy", 0))
	if heavy > 0:
		out.append([2.5 + heavy, "%d heavy blow%s landed undefended (%d damage)" % [heavy, "" if heavy == 1 else "s", int(st.get("heavy_dmg", 0.0))],
			"When a foe is \"Winding up\", its target should Defend (5): half damage and no stun. Guard (6) moves the hit onto a sturdier ally; Shield Bash or Frost Nova break the wind-up."])
	var taken := float(st.get("taken", 0.0))
	var dot := float(st.get("dot", 0.0))
	if taken > 0.0 and dot / taken >= 0.2:
		out.append([2.0 + dot / taken * 4.0, "Burn and poison did %d damage (%d%% of the total)" % [int(dot), int(dot / taken * 100.0)],
			"A Healing Tonic cleanses burn, poison, chill and stun. Kill the fire and poison foes first."])
	var healed := float(st.get("enemy_heal", 0.0))
	var foe_hp := 0.0
	for m in state["monsters"]:
		foe_hp += float(m["max_hp"])
	if foe_hp > 0.0 and healed / foe_hp >= 0.15:
		out.append([2.0 + healed / foe_hp * 4.0, "Your foes healed %d HP" % int(healed),
			"Focus the healer first, and save Abilities to burst a regenerating foe from low HP."])
	var start_pct := float(state.get("_start_hp_pct", 1.0))
	if start_pct < 0.6:
		out.append([2.0 + (0.6 - start_pct) * 5.0, "The party started the fight at %d%% HP" % int(start_pct * 100.0),
			"Rest at a campfire, use a Supply Drop order, or retreat and come back healed."])
	if int(state.get("round_num", 0)) >= 3 and int(st.get("abilities", 0)) == 0:
		out.append([1.8, "No Abilities were used",
			"Abilities (2) hit much harder than attacks. Use them whenever they're ready."])
	var squishy_front := party.filter(func(h): return h.formation == "front" and GameData.hero_role(h) in ["mage", "cleric", "ranger"] and h.hp <= 0)
	if not squishy_front.is_empty():
		out.append([1.5, "%s fell in the front row" % ", ".join(squishy_front.map(func(h): return h.name.split(" the ")[0])),
			"The front row takes most of the hits. Put Mages, Clerics and Rangers in the back row."])
	if not party.any(func(h): return GameData.hero_role(h) == "cleric") and int(state.get("round_num", 0)) >= 6:
		out.append([1.2, "No healer in a long fight",
			"A Cleric (or healing relics and skills) keeps the party standing through long fights."])
	out.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	return out.slice(0, 3).map(func(x): return [x[1], x[2]])


## Passive round-cadence effects (monster regen, hero poison tick,
## party mend) — fired once, after every actor in the round's turn order has
## acted, rather than at the old "after heroes, before monsters" phase
## boundary, which no longer exists once heroes and monsters are genuinely
## interleaved. Same total effect per round as before, just anchored to
## round-end instead of a mid-round phase split.
func _end_round_effects(state: Dictionary) -> void:
	var log: Array[String] = state["log"]
	var party: Array[Hero] = state["party"]
	var monsters: Array = state["monsters"]

	for m in monsters:
		var is_regen: bool = m.get("mechanic", {}).get("id") == "regen" or m.get("mechanic2", {}).get("id") == "regen"
		if float(m["hp"]) > 0 and is_regen:
			var regen_heal: float = round(float(m["max_hp"]) * 0.08)
			m["hp"] = min(float(m["max_hp"]), float(m["hp"]) + regen_heal)
			log.append("%s regenerates %d HP." % [m["name"], regen_heal])
			_tally(state, "enemy_heal", regen_heal)

	var mburn: Dictionary = state.get("_m_burn", {})
	for mi in mburn.keys().duplicate():
		var mb: Dictionary = mburn[mi]
		if int(mi) >= monsters.size() or float(monsters[int(mi)]["hp"]) <= 0:
			mburn.erase(mi)
			continue
		monsters[int(mi)]["hp"] = float(monsters[int(mi)]["hp"]) - round(float(mb["dmg"]))
		log.append("%s burns for %d." % [monsters[int(mi)]["name"], int(round(float(mb["dmg"])))])
		mb["rounds"] = int(mb["rounds"]) - 1
		if int(mb["rounds"]) <= 0:
			mburn.erase(mi)
	var burn: Dictionary = state.get("hero_burn", {})
	for bid in burn.keys().duplicate():
		var hb: Hero = _find_party_hero(party, str(bid))
		if hb == null or hb.hp <= 0:
			burn.erase(bid)
			continue
		var btick: int = max(1, int(round(max_hp(hb) * float(burn[bid]["value"]))))
		hb.hp = max(0, hb.hp - btick)
		log.append("%s burns for %d." % [hb.name, btick])
		_tally(state, "dot", btick)
		_tally(state, "taken", btick)
		if hb.hp <= 0:
			log.append("%s is knocked out!" % hb.name)
		burn[bid]["rounds"] = int(burn[bid]["rounds"]) - 1
		if int(burn[bid]["rounds"]) <= 0 or hb.hp <= 0:
			burn.erase(bid)
	var poison: Dictionary = state["hero_poison"]
	for hero_id in poison.keys().duplicate():
		var h5: Hero = null
		for hp_candidate in party:
			if hp_candidate.id == str(hero_id):
				h5 = hp_candidate
				break
		if h5 == null or h5.hp <= 0:
			poison.erase(hero_id)
			continue
		var entry: Dictionary = poison[hero_id]
		var tick: int = max(1, int(round(max_hp(h5) * float(entry["value"]))))
		h5.hp = max(0, h5.hp - tick)
		log.append("%s suffers %d poison damage." % [h5.name, tick])
		_tally(state, "dot", tick)
		_tally(state, "taken", tick)
		if h5.hp <= 0:
			log.append("%s is knocked out!" % h5.name)
		entry["rounds"] = int(entry["rounds"]) - 1
		if entry["rounds"] <= 0 or h5.hp <= 0:
			poison.erase(hero_id)
		else:
			poison[hero_id] = entry

	var living: Array[Hero] = []
	living.assign(party.filter(func(h): return h.hp > 0))
	if float(state["mend"]) > 0.0:
		var mended := false
		for h in living:
			if h.hp > 0 and h.hp < max_hp(h):
				var heal: int = max(1, int(round(max_hp(h) * float(state["mend"]))))
				h.hp = min(max_hp(h), h.hp + heal)
				mended = true
		if mended:
			log.append("The party mends its wounds.")
			for h4 in living:
				_fire("party_mend", state, h4)


## {} if the fight isn't over; otherwise the {"done":true,...} outcome from
## _finish_combat.
func _check_monsters_defeated(state: Dictionary) -> Dictionary:
	var monsters: Array = state["monsters"]
	for m in monsters:
		if float(m["hp"]) > 0:
			return {}
	state["log"].append(("The %s falls!" % monsters[0]["name"]) if monsters.size() == 1 else "All foes defeated!")
	return _finish_combat(state, true, false)


func _check_party_defeated(state: Dictionary) -> Dictionary:
	for h in state["party"]:
		if h.hp > 0:
			return {}
	if party_has_unique_relic("phoenix_feather") and not GameState.run.is_empty() and not bool(GameState.run.get("phoenix_used", false)):
		GameState.run["phoenix_used"] = true
		for h in state["party"]:
			h.hp = max(1, int(round(max_hp(h) * 0.30)))
		(state["log"] as Array).append("The Phoenix Feather flares — the party rises from the ashes!")
		return {}
	return _finish_combat(state, false, false)


## Ensures state["turn_order"]/state["turn_idx"] point at a valid upcoming
## turn — rolling a fresh round via _start_round if the previous one is
## exhausted — and returns that turn descriptor without resolving it. Lets a
## caller (Main.gd's _run_combat_turns) find out what's coming next, and
## whether it needs player input, before committing to resolve_turn. Has the
## same round-rollover side effects _start_round always has, so — like
## resolve_turn — only call this from an actual game action, never from a
## read-only render() pass (see Main.gd's own comment on this).
## Guild Order "Rally": the rest of this round, every hero acts before any
## foe and the party hits 30% harder.
func apply_rally(state: Dictionary) -> void:
	peek_next_turn(state)   # make sure a round is under way
	state["_attack_mult"] = float(state.get("_attack_mult", 1.0)) * 1.3
	var idx := int(state.get("turn_idx", 0))
	var order: Array = state["turn_order"]
	var rest: Array = order.slice(idx)
	var sorted: Array = rest.filter(func(t): return t["type"] == "hero") + rest.filter(func(t): return t["type"] != "hero")
	for k in sorted.size():
		order[idx + k] = sorted[k]
	(state["log"] as Array).append("Rally! The guild's order rings out: the party moves first and hits 30% harder this round.")


func peek_next_turn(state: Dictionary) -> Dictionary:
	if state.get("turn_order", []).is_empty() or int(state.get("turn_idx", 0)) >= state["turn_order"].size():
		_start_round(state)
	return state["turn_order"][int(state["turn_idx"])]


## One actor's turn within an in-progress fight — a living hero's chosen
## pending action, or a living monster's retaliation, whichever
## state["turn_order"] says comes next (see _compute_turn_order — heroes and
## monsters are genuinely interleaved by speed, not resolved in two batch
## phases). Advances state["turn_idx"]; once a round's turn order is fully
## spent, rolls the passive round-end effects and a fresh order for the next
## round. Mutates `state` in place and returns {"done": bool, "result":
## Dictionary} — result is only populated once the fight ends. Call once per
## turn (see Main.gd's _run_combat_turns, which drives this automatically for
## monster turns and on the player's action-bar click for a hero's turn).
func resolve_turn(state: Dictionary) -> Dictionary:
	state["_procs"] = []   # effects that fired this turn — the combat screen floats their names
	state["_barks"] = []   # what a hero said this turn (speech bubbles)
	var turn: Dictionary = peek_next_turn(state)
	var turn_idx: int = int(state["turn_idx"])
	state["turn_idx"] = turn_idx + 1

	if turn["type"] == "hero":
		var h := _find_party_hero(state["party"], str(turn["id"]))
		var stunned: Dictionary = state.get("_stunned", {})
		if h and h.hp > 0 and stunned.has(h.id):
			stunned.erase(h.id)
			(state["log"] as Array).append("%s is stunned and loses the turn." % h.name)
		elif h and h.hp > 0:
			var alive_before: Array = (state["monsters"] as Array).filter(func(m): return float(m["hp"]) > 0)
			_resolve_hero_action(state, h)
			var felled: Array = alive_before.filter(func(m): return float(m["hp"]) <= 0)
			if not felled.is_empty() and h.hp > 0:
				_bark(state, h, "kill", 1.0 if felled.any(func(m): return m["is_main"] and m["tier"] != "combat") else 0.3)
	else:
		var i: int = int(turn["id"])
		var monsters: Array = state["monsters"]
		if i < monsters.size() and float(monsters[i]["hp"]) > 0:
			var hp_before := {}
			for ph in state["party"]:
				hp_before[ph.id] = ph.hp
			_resolve_monster_action(state, i)
			var living: Array = (state["party"] as Array).filter(func(x): return x.hp > 0)
			for ph in state["party"]:
				if ph.hp >= int(hp_before[ph.id]):
					continue
				if ph.hp <= 0 and not living.is_empty():
					_bark(state, living[randi() % living.size()], "ally_down", 0.6)
				elif ph.hp > 0 and ph.hp < max_hp(ph) * 0.25:
					_bark(state, ph, "low_hp", 0.7)
	_check_phases(state)

	var outcome := _check_monsters_defeated(state)
	if not outcome.is_empty():
		return outcome
	outcome = _check_party_defeated(state)
	if not outcome.is_empty():
		return outcome

	if int(state["turn_idx"]) >= state["turn_order"].size():
		_end_round_effects(state)
		outcome = _check_monsters_defeated(state)
		if not outcome.is_empty():
			return outcome
		outcome = _check_party_defeated(state)
		if not outcome.is_empty():
			return outcome
		if int(state["round_num"]) >= 30:
			return _finish_combat(state, false, false)

	return {"done": false, "result": {}}


## Ends the fight immediately by player choice — no round processing, no
## penalty beyond forfeiting rewards; every hero keeps their current live HP.
func retreat_combat(state: Dictionary) -> Dictionary:
	var log: Array[String] = state["log"]
	log.append("The party withdraws from the fight.")
	return _finish_combat(state, false, true)


func _finish_combat(state: Dictionary, won: bool, retreated: bool) -> Dictionary:
	var party: Array[Hero] = state["party"]
	var log: Array[String] = state["log"]
	var full_loss := not won and not retreated
	if full_loss:
		log.append("Your party is overwhelmed...")
	# Any hero knocked out mid-fight (hp hit 0 while the party kept
	# fighting and ultimately won, or before a retreat) still needs a
	# recovery timer — not just the whole-party-wiped case above, or
	# they'd sit at 0 HP forever, invisible to needs_recovery()/Medical Bay.
	for h in party:
		if h.hp <= 0 and h.down_runs <= 0:
			GameState.knock_out(h)
			h.history["knockouts"] = int(h.history.get("knockouts", 0)) + 1
			# A freshly-knocked-out roster hero may pick up a scar quirk
			# (up to GameData.SCARS_MAX).
			if not GameState.run.has("tower") and randf() < 0.5:
				var scar := roll_scar(h)
				if scar != "":
					h.quirks.append(scar)
					log.append("%s is left with a lasting scar: %s." % [h.name, scar])
					log.append(GameData.narrative_line("scar_gained"))

	var result := {
		"won": won, "retreated": retreated, "log": log, "rounds": int(state["round_num"]), "monster_name": state["monsters"][0]["name"],
		"coin": 0, "crystal": 0, "bonus_crystal": 0, "reward_options": [],
	}
	if won:
		var is_boss: bool = state["is_boss"]
		var is_elite: bool = state["is_elite"]
		var diff: Dictionary = state["diff"]
		var floor_idx: int = state["floor_idx"]
		var reward_mult: float = 1.4 if is_elite else 1.0
		var depth_mult: float = 1.0 + floor_idx * 0.05
		result["coin"] = round(randf_range(diff["coin"][0], diff["coin"][1]) * reward_mult * depth_mult)
		var base_crystal: float = round(randf_range(diff["crystal"][0], diff["crystal"][1]) * reward_mult * depth_mult)
		result["crystal"] = round(base_crystal * GameState.crystal_yield_bonus())
		result["guild_crystal"] = int(result["crystal"] - base_crystal)   # Crystal Amplifiers' share, shown on the result
		if is_boss and GameState.crystal_resonance():
			var cache := int(round(float(diff["crystal"][1]) * 2.0))
			result["bonus_crystal"] = int(result.get("bonus_crystal", 0)) + cache
			result["crystal_cache"] = cache
		if is_elite:
			var bonus_crystal := 0
			for h in party:
				if randf() < GameState.energy_extract_chance():
					bonus_crystal += randi() % 4 + 2
			result["bonus_crystal"] = bonus_crystal
		var xp_gain: int = 30 if is_boss else (20 if is_elite else 12)
		var summary: Array = []
		for h in party:
			var lv0 := h.level
			var xp0 := h.xp
			gain_xp(h, xp_gain)
			summary.append({"id": h.id, "name": h.name, "cls_id": h.cls_id, "pool_id": h.pool_id, "alive": h.hp > 0,
				"lv0": lv0, "xp0": xp0, "next0": xp_to_next(lv0), "lv1": h.level, "xp1": h.xp, "next1": xp_to_next(h.level),
				"dealt": int(round(float(state.get("_dealt", {}).get(h.id, 0.0)))), "kills": int(state.get("_kills", {}).get(h.id, 0))})
		result["heroes"] = summary
		result["xp_gain"] = xp_gain
		# One hero sums it up: whoever levelled, else the top damage dealer.
		var speaker: Hero = null
		var moment := "victory"
		for k in summary.size():
			if summary[k]["alive"] and int(summary[k]["lv1"]) > int(summary[k]["lv0"]):
				speaker = party[k]
				moment = "level_up"
				break
		if speaker == null:
			for k in summary.size():
				if summary[k]["alive"] and (speaker == null or int(summary[k]["dealt"]) > int(state.get("_dealt", {}).get(speaker.id, 0.0))):
					speaker = party[k]
		if speaker:
			result["bark"] = {"id": speaker.id, "name": speaker.name.split(" the ")[0], "text": bark_line(speaker, moment)}
		if not is_boss:
			var options := [gen_loot(weighted_rarity()), gen_loot(weighted_rarity())]
			if randf() < min(0.5, drop_rate_bonus() * 2.0):
				options.append(gen_loot(weighted_rarity()))
			result["reward_options"] = options
	return {"done": true, "result": result}
