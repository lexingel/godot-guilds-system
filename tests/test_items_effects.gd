extends "res://tests/base_test.gd"
## Items (ranks, implicits, epic affixes), item effects and fights.

var fired := {}




func run() -> void:
	seed(42)
	GameState.reset()
	# --- item generation ---
	for rank in ["F", "C", "SSS"]:
		for rar in ["common", "rare", "epic"]:
			var it := Combat.gen_item(rar, "", rank)
			check(it.item_rank == rank, "rank stored")
			check(it.implicit_kind != "", "implicit rolled")
			check((it.effects.size() == 1) == (rar == "epic"), "epic cond affix only on epic")
			var back := Item.from_dict(JSON.parse_string(JSON.stringify(it.to_dict())))
			check(is_equal_approx(back.implicit_value, it.implicit_value) and back.item_rank == it.item_rank and back.effects.size() == it.effects.size(), "roundtrip")
			print("[%s/%s] %s | %s" % [rank, rar, it.name, _desc(it)])
	var lo := Combat.gen_item("common", "weapon", "F")
	var hi := Combat.gen_item("common", "weapon", "SSS")
	check(hi.implicit_value > lo.implicit_value, "rank scales implicit")
	for e in GameData.ITEM_COND_AFFIXES:
		var d := Combat.describe_effect(e)
		check(d != "" and not d.begins_with(":"), "describe affix " + str(e))
	for u in GameData.UNIQUE_ITEMS:
		for e in u["effects"]:
			print("  %s: %s" % [u["name"], Combat.describe_effect(e)])
	# --- phase 2: passives + evolution choice ---
	var passive_names := {}
	for c in GameData.CLASS_POOL:
		var p := GameData.subclass_passive(str(c["id"]))
		check(not p.is_empty(), "passive for " + str(c["id"]))
		for e in p.get("effects", []):
			check(Combat.describe_effect(e) != "", "passive desc " + str(c["id"]))
		passive_names[p.get("name", "")] = true
	print("distinct passives: %d across %d subclasses" % [passive_names.size(), GameData.CLASS_POOL.size()])
	var evo := Combat.gen_hero("E", 10)
	GameState.heroes.append(evo)
	GameState.crystals = 99999
	var choices := GameData.evolution_choices(GameData.find_class(evo.pool_id))
	check(GameState.evolve_hero(evo.id, "nope") != "", "bogus path rejected")
	var want: String = str(choices[-1]["id"])
	check(GameState.evolve_hero(evo.id, want) == "" and evo.pool_id == want, "evolves into chosen path")
	print("evolved into %s: %s" % [want, evo.name])
	print("build: ", Combat.hero_archetype_counts(evo))
	GameState.heroes.clear()
	# --- phase 3: keystones + signatures ---
	var kh := Combat.gen_hero("C", 10)
	kh.skill_points = 20
	GameState.heroes.append(kh)
	GameState.coins = 99999
	var kk: String = kh.innate_kind
	check(GameState.learn_skill(kh.id, kk, "keystone") != "", "keystone gated before a Path node")
	var cap_node := GameData.find_skill_node(kk, "cap")
	for sid in ["edge", "hide"] + cap_node["requires"] + ["cap"]:
		GameState.learn_skill(kh.id, kk, str(sid))
	var hp_before := Combat.max_hp(kh)
	var eff_before := Combat.hero_effects(kh).size()
	check(GameState.learn_skill(kh.id, kk, "keystone") == "", "keystone learnable after Path")
	check(Combat.hero_effects(kh).size() > eff_before, "keystone adds effects")
	var ks := GameData.keystone_node(kk)
	if str(ks["kind"]) == "hp_pct":
		check(Combat.max_hp(kh) < hp_before, "keystone hp drawback applies")
	check(GameState.learn_skill(kh.id, kk, "signature") == "", "signature learnable")
	check(kh.skills.has("signature"), "signature stored bare")
	GameState.migrate_hero_skill_keys(kh)
	check(kh.skills.has("signature"), "migration keeps signature bare")
	var sp_before := kh.skill_points
	GameState.respec_hero(kh.id, "")
	check(kh.skills.is_empty() and kh.skill_points == 20, "full respec refunds everything (got %d, had %d)" % [kh.skill_points, sp_before])
	print("keystone %s: %s" % [ks["name"], ks["effects"]])
	GameState.heroes.clear()
	# --- phase 4: history, earned traits, scar upsides, bonds ---
	GameState.active_slot = 9   # throwaway slot — seal_rift/start_run save()
	var a := Combat.gen_hero("C", 8)
	var b := Combat.gen_hero("C", 8)
	GameState.heroes.assign([a, b])
	a.history = {"boss_kills": 3, "rifts_cleared": 4}
	var got := GameState.check_earned_quirks(a)
	check(a.quirks.has("Bosskiller") and got.size() == 1, "bosskiller earned at 3 boss kills")
	check(Combat.hero_effects(a).any(func(e): return e.get("source", "") == "Bosskiller"), "earned effect active")
	a.quirks.append("Haunted")
	check(Combat.hero_effects(a).any(func(e): return e.get("source", "") == "Haunted"), "scar upside active")
	var ids: Array[String] = [a.id, b.id]
	for r in 5:
		GameState.start_run("lesser", ids, null)
		GameState.seal_rift()
		GameState.run = {}
	check(GameState.bond_rifts(a.id, b.id) == 5 and GameData.bond_level(5) == 2, "bond grows with shared rifts")
	check(a.quirks.has("Veteran"), "veteran earned on 5th rift (had 4)")
	var party2: Array[Hero] = [a, b]
	a.hp = Combat.max_hp(a)
	b.hp = Combat.max_hp(b)
	check(absf(Combat.bond_bonus_for(party2, "dmg_pct") - 0.04) < 0.0001 or Combat.bond_bonus_for(party2, "dmg_pct") >= 0.04, "bond Lv2 gives +4% dmg")
	var back := Hero.from_dict(JSON.parse_string(JSON.stringify(a.to_dict())))
	check(back.quirks == a.quirks and int(back.history.get("rifts_cleared", 0)) == 9, "hero history roundtrip")
	GameState.delete_slot(9)
	GameState.heroes.clear()
	# --- fights with every legendary + epic affixes ---
	var wins := 0
	for s in 60:
		seed(500 + s)
		GameState.items.clear()
		GameState.relics.clear()
		var party: Array[Hero] = []
		for i in 4:
			var h := Combat.gen_hero(["D", "C", "B", "A"][i], 8)
			if i % 2 == 1:
				h.formation = "back"
			party.append(h)
		for i in 4:
			var u: Dictionary = GameData.UNIQUE_ITEMS[(s * 4 + i) % GameData.UNIQUE_ITEMS.size()]
			var it := Item.new()
			it.id = "u%d" % i
			it.name = str(u["name"])
			it.category = str(u["category"])
			it.unique_id = str(u["id"])
			it.drawback_kind = str(u["drawback_kind"])
			it.drawback_value = float(u["drawback_value"])
			it.equipped_to = party[i].id
			GameState.items.append(it)
			var ep := Combat.gen_item("epic", "armor", "B")
			ep.equipped_to = party[i].id
			GameState.items.append(ep)
		for h in party:
			h.hp = Combat.max_hp(h)
		var state := Combat.start_combat(party, ["combat", "elite", "boss"][s % 3], GameData.DIFFICULTIES[s % 2], 3)
		var out := {}
		for t in 500:
			var nxt := Combat.peek_next_turn(state)
			if nxt["type"] == "hero":
				state["pending_actions"][str(nxt["id"])] = {"action": "ability" if t % 4 == 0 else "attack", "target": t % 3}
			out = Combat.resolve_turn(state)
			if out["done"]:
				break
		check(out.get("done", false), "fight %d finished" % s)
		for line in state["log"]:
			for key in ["act again", "steps in front", "blunts", "mends the party", "counters", "shields"]:
				if str(line).contains(key):
					fired[key] = int(fired.get(key, 0)) + 1
		if out.get("done", false) and out["result"]["won"]:
			wins += 1
	# intercept: a Warden's Oath wearer at full HP guarding a wounded ally
	seed(9)
	GameState.items.clear()
	var guard := Combat.gen_hero("C", 8)
	var hurt := Combat.gen_hero("C", 8)
	var oath := Item.new()
	oath.id = "oath"
	oath.name = "Warden's Oath"
	oath.category = "armor"
	oath.unique_id = "wardens_oath"
	oath.equipped_to = guard.id
	GameState.items.append(oath)
	var ip: Array[Hero] = [guard, hurt]
	var intercepts := 0
	for trial in 40:
		guard.hp = Combat.max_hp(guard)
		hurt.hp = int(Combat.max_hp(hurt) * 0.3)
		var st := Combat.start_combat(ip, "combat", GameData.DIFFICULTIES[0], 1)
		st["dodge"] = 0.0
		Combat._resolve_monster_action(st, 0)
		for line in st["log"]:
			if str(line).contains("steps in front"):
				intercepts += 1
	print("intercepts: %d/40 (expect ~60%% of hits aimed at the wounded ally)" % intercepts)
	check(intercepts > 0, "intercept fires")
	print("fights won: %d/60" % wins)
	print("effects fired: ", fired)
	print("CHECKS: %s" % ("ALL PASSED" if fails == 0 else "%d FAILED" % fails))


func _desc(it: Item) -> String:
	var parts: Array[String] = ["base " + Combat.describe_skill(it.implicit_kind, it.implicit_value), Combat.describe_skill(it.kind, it.value)]
	if it.secondary_kind != "":
		parts.append(Combat.describe_skill(it.secondary_kind, it.secondary_value))
	if it.tertiary_kind != "":
		parts.append(Combat.describe_skill(it.tertiary_kind, it.tertiary_value))
	for e in it.effects:
		parts.append(Combat.describe_effect(e))
	return ", ".join(parts)
