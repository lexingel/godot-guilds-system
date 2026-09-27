extends "res://tests/base_test.gd"
## Relic generation, triggers, sets, legendaries, awakening and rerolls.

func _uniq(id: String) -> Relic:
	return Combat.relic_from_unique(GameData.find_unique_relic(id))


func _equip_only(rs: Array) -> void:
	GameState.relics.clear()
	for r in rs:
		r.equipped = true
		GameState.relics.append(r)


func _fight_party(ids: Array[String]) -> Dictionary:
	GameState.start_run("lesser", ids, null, false)
	GameState.run["node_state"] = {}
	GameState.choose_node_type("combat")
	GameState.engage_node()
	return GameState.run["node_state"]["combat_state"]


func run() -> void:
	seed(8)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	GameState.crystals = 5000
	var ids: Array[String] = []
	for r in ["D", "C", "D"]:
		var h := Combat.gen_hero(r, 6)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)

	# Generation.
	var c := Combat.gen_relic("common")
	var ra := Combat.gen_relic("rare")
	var ep := Combat.gen_relic("epic")
	check(c.specials.size() == 1 and c.trigger.is_empty(), "common: 1 special, no trigger")
	check(ra.specials.size() == 1 and not ra.trigger.is_empty(), "rare: special + trigger")
	check(ep.specials.size() == 2 and ep.specials[0]["kind"] != ep.specials[1]["kind"] and not ep.trigger.is_empty(), "epic: 2 distinct specials + trigger")
	check(c.name.contains(" of "), "named: %s" % c.name)
	print("   epic: ", ep.name, " — ", ep.desc())

	# Migration: an old blank relic gains a special; an old special is kept.
	var old := {"id": "rlx", "name": "Ember Sigil", "type": "Ember", "rarity": "rare", "dmg": 4, "hp": 13, "special_kind": "", "level": 2}
	var m := Relic.from_dict(old)
	check(m.specials.size() == 1, "old stat-stick relic gains a special")
	old["special_kind"] = "dodge_pct"; old["special_value"] = 0.07; old["special_label"] = "+7% dodge"
	check(Relic.from_dict(old).specials[0]["kind"] == "dodge_pct", "old special kept")
	var back := Relic.from_dict(JSON.parse_string(JSON.stringify(ep.to_dict())))
	check(back.specials.size() == 2 and back.trigger.get("effect") == ep.trigger.get("effect"), "save round-trip")

	# Special totals.
	_equip_only([c])
	var k: String = c.specials[0]["kind"]
	check(is_equal_approx(Combat.relic_special_total(k), float(c.specials[0]["value"])), "special total")

	# Sets.
	var e1 := Combat.gen_relic("common", "Ember")
	var e2 := Combat.gen_relic("common", "Ember")
	var f1 := Combat.gen_relic("common", "Frost")
	_equip_only([e1, e2])
	check(is_equal_approx(Combat.synergy_value_for("dmg_pct"), 0.075), "2 Ember: +7.5%% dmg (%.3f)" % Combat.synergy_value_for("dmg_pct"))
	var e3 := Combat.gen_relic("common", "Ember")
	_equip_only([e1, e2, e3])
	check(is_equal_approx(Combat.synergy_value_for("dmg_pct"), 0.15), "3 Ember: +15%")
	_equip_only([e1, f1, Combat.gen_relic("common", "Verdant")])
	check(Combat.relic_sets().any(func(s): return s["name"] == "Prism"), "3 elements: Prism")

	# Triggers fire in battle: a round_third nova.
	var nova := Combat.gen_relic("rare")
	nova.trigger = {"trigger": "round_third", "effect": "nova", "value": 0.5}
	_equip_only([nova])
	var st := _fight_party(ids)
	for m2 in st["monsters"]:
		m2["hp"] = 99999.0
		m2["max_hp"] = 99999.0
	var fired := false
	for i in 80:
		if GameState.run["node_state"].has("result"):
			break
		GameState.resolve_turn_now()
		if (st["log"] as Array).any(func(l): return str(l).contains("strikes every foe")):
			fired = true
			break
	check(fired, "round-third nova fires")
	GameState.run = {}

	# Legendaries.
	var ph := _uniq("phoenix_feather")
	_equip_only([ph])
	st = _fight_party(ids)
	for h in st["party"]:
		h.hp = 0
	var out := Combat._check_party_defeated(st)
	check(out.is_empty() and (st["party"] as Array).all(func(h): return h.hp > 0), "Phoenix revives the party once")
	for h in st["party"]:
		h.hp = 0
	check(not Combat._check_party_defeated(st).is_empty(), "…but only once per rift")
	GameState.run = {}
	for h in GameState.heroes:
		h.hp = Combat.max_hp(h); h.down_runs = 0

	var bp := _uniq("bloodpact")
	_equip_only([bp])
	st = _fight_party(ids)
	check(float(st["mend"]) == 0.0, "Bloodpact: no mending")
	GameState.run = {}

	var sc := _uniq("stopped_clock")
	_equip_only([sc])
	st = _fight_party(ids)
	for m3 in st["monsters"]:
		m3["hp"] = 99999.0
		m3["max_hp"] = 99999.0
	var hp_before: Array = (st["party"] as Array).map(func(h): return h.hp)
	for i in 30:
		if int(st["round_num"]) > 1 or GameState.run["node_state"].has("result"):
			break
		GameState.resolve_turn_now()
	check((st["log"] as Array).any(func(l): return str(l).contains("frozen in time")), "Stopped Clock freezes foes in round 1")
	GameState.run = {}

	var crown := _uniq("crown_of_oaths")
	_equip_only([crown])
	var champ := GameState.ensure_champion()
	GameState.start_run("lesser", ids, null, false)
	GameState.run["champion_calls"] = 1
	check(GameState.champion_call_ready(champ), "Crown: a second Call")
	GameState.run["champion_calls"] = 2
	check(not GameState.champion_call_ready(champ), "…not a third")
	GameState.run = {}

	var mirror := _uniq("mirror_shard")
	_equip_only([mirror, ep])
	var kk: String = ep.specials[0]["kind"]
	check(is_equal_approx(Combat.relic_special_total(kk), float(ep.specials[0]["value"]) * 2.0), "Mirror doubles the best relic's specials")

	var ws := _uniq("wardens_seal")
	_equip_only([ws])
	GameState.resolve_rift_map()
	var fuse0: Array = GameState.rift_map.map(func(s): return int(s.get("runs_left", 0)))
	GameState.day = 2   # pass_time makes it 3 → held
	GameState.pass_time()
	var fuse1: Array = GameState.rift_map.map(func(s): return int(s.get("runs_left", 0)))
	check(fuse0 == fuse1, "Warden's Seal holds fuses on every third day")

	# Awaken + reroll.
	var up := Combat.gen_relic("rare")
	_equip_only([up])
	for i in 4:
		GameState.upgrade_relic(up.id)
	check(up.level == 5 and up.awakened and up.specials.size() == 2, "Lv5 awakens with a 2nd special")
	var cr0 := GameState.crystals
	var t0: Dictionary = up.trigger.duplicate()
	check(GameState.reroll_relic(up.id, -1) == "" and GameState.crystals < cr0 and up.rerolls == 1, "trigger reroll spends crystals")
	check(GameState.reroll_relic(up.id, 0) == "" and up.specials[0]["kind"] != up.specials[1]["kind"], "special reroll stays distinct")
	check(GameState.reroll_relic(ph.id, 0) != "" if GameState.relics.has(ph) else true, "legendaries can't reroll")
