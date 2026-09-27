extends Node
## Full-run balance sim: real rift layouts, HP carries between nodes, knocked-out
## heroes sit out, the Champion joins (levelled, Boon, Call on the boss), and
## loot/XP/attribute gains inside a run are modelled. Never saves. ~1 min:
##   godot --headless --path . res://tests/sim/balance_sim.tscn
## (`-- ranks`: only the ladder-rank profiles; `-- calibrate`: power at a
## 65% clear per rank; `-- tower`, `-- survivors`)

const N := 120
var GAINS := true   # model loot/XP/attribute gains inside a run
var CHAMP_V2 := true
var BOONS := true   # a random boon after each elite win
# Income tallies (reset per profile): what one run earns on average.
var _coins := 0.0
var _crystals := 0.0
var _loot_value := 0.0   # champion levels with the party, Boon in runs, Call on the boss
const PROFILES := {
	# name: [difficulty, hero ranks, level, skill depth, gear rarity ("" = none), relics, relic rarity]
	"Lesser  | newcomer": ["lesser", ["F", "F", "F"], 1, 0, "", 0, "common"],
	"Lesser  | invested": ["lesser", ["E", "D", "D"], 4, 1, "common", 1, "common"],
	"Greater | underleveled": ["greater", ["E", "D", "D"], 4, 1, "common", 1, "common"],
	"Greater | invested": ["greater", ["D", "C", "C", "C"], 7, 2, "rare", 2, "rare"],
	"Endless | endgame": ["endless", ["C", "B", "B", "A"], 10, 3, "epic", 3, "epic"],
	# Ladder ranks (a rank id instead of a difficulty): a party roughly where
	# a player reaches that rank.
	"Rank E  | invested": ["E", ["E", "D", "D"], 4, 1, "common", 1, "common"],
	"Rank D  | invested": ["D", ["E", "D", "D", "D"], 6, 2, "rare", 1, "rare"],
	"Rank B  | invested": ["B", ["D", "C", "C", "C"], 8, 2, "rare", 2, "rare"],
	"Rank A  | endgame": ["A", ["C", "B", "B", "A"], 10, 3, "epic", 3, "epic"],
	"Rank S  | endgame": ["S", ["C", "B", "B", "A"], 10, 3, "epic", 3, "epic"],
	"Rank SS | endgame": ["SS", ["C", "B", "B", "A"], 10, 3, "epic", 3, "epic"],
	"Rank SSS| endgame": ["SSS", ["C", "B", "B", "A"], 10, 3, "epic", 3, "epic"],
}

const MODES := ["lesser", "greater", "endless"]


var TOWER_ONLY := false   # `-- tower` on the command line: skip the rift profiles


func _ready() -> void:
	GameState.active_slot = 9
	TOWER_ONLY = OS.get_cmdline_user_args().has("tower")
	if OS.get_cmdline_user_args().has("calibrate"):
		_calibrate()
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("survivors"):
		for name in PROFILES:
			if PROFILES[name][0] in ["greater", "endless"]:   # Endless opens in Act III
				_survivors(name, PROFILES[name])
		get_tree().quit()
		return
	if not TOWER_ONLY:
		for name in PROFILES:
			if PROFILES[name][0] != "endless" and (not OS.get_cmdline_user_args().has("ranks") or not PROFILES[name][0] in MODES):   # Endless is a survival run: `-- survivors`
				_profile(name, PROFILES[name])
	for name in PROFILES:
		if PROFILES[name][0] in MODES:
			_tower(name, PROFILES[name])
	get_tree().quit()


## Endless Rift (survivors): how long each profile lasts on autopilot (the
## Champion stays home; first upgrade offered is taken).
const SURV_RUNS := 12


## A sensible player's level-up pick: Ability ranks, then damage and health,
## then damage-dealing skills, else whatever is offered.
func _best_pick(o: Array) -> String:
	if o.is_empty():
		return ""
	for pref in ["ability:", "might", "vigor", "skill:", "haste", "area"]:
		for id in o:
			if str(id).begins_with(pref) and not (pref == "skill:" and str(id).split(":")[2] in ["heal", "sanctuary", "taunt", "smoke_bomb"]):
				return str(id)
	return str(o[randi() % o.size()])


func _survivors(name: String, p: Array) -> void:
	var times: Array = []
	var kills := 0
	var levels := 0
	for i in SURV_RUNS:
		var party: Array = _build_party(p)
		var r := SurvivorsRun.new(party, ["vale", "marsh", "ashen"][i % 3], 1000 + i)
		while not r.over and r.time < 1200.0:
			r.step(0.2, r.autopilot_dir())
			r.events.clear()
			while r.pending_levels > 0:
				var o := r.offer()
				r.pick(_best_pick(o))
		times.append(int(r.time))
		kills += r.kills
		levels += r.level
	times.sort()
	print("%-24s survivors: median %d:%02d (min %d:%02d, max %d:%02d) · %d kills · level %d" % [name, times[SURV_RUNS / 2] / 60, times[SURV_RUNS / 2] % 60,
		times[0] / 60, times[0] % 60, times[-1] / 60, times[-1] % 60, kills / SURV_RUNS, levels / SURV_RUNS])


## Tower of Trials: how high each profile climbs (3 tries a floor, full HP
## each try, XP from wins kept, no loot).
func _tower(name: String, p: Array) -> void:
	var tops: Array[int] = []
	for s in 20:
		seed(30000 + s)
		var party := _build_party(p)
		var top := 0
		for f in range(1, GameData.TOWER_FLOORS + 1):
			var info := GameState.tower_floor_info(f)
			var fighters: Array[Hero] = [party[0]]
			fighters.append_array(party.slice(1, 1 + int(info["party_cap"])))
			var cleared := false
			for attempt in 3:
				for h in fighters:
					h.hp = Combat.max_hp(h)
				GameState.run = {"sim": true, "tower": f}
				seed(hash([int(info["seed"]), 0, 0]))
				if _fight(fighters, str(info["kind"]), GameState._tower_diff(info), GameData.TOWER_FIGHT_DEPTH):
					cleared = true
					break
			if not cleared:
				break
			top = f
		tops.append(top)
	tops.sort()
	print("%-24s tower: median floor %d (min %d, max %d)" % [name, tops[tops.size() / 2], tops[0], tops[-1]])


func _profile(name: String, p: Array) -> void:
	_coins = 0.0; _crystals = 0.0; _loot_value = 0.0
	var clears := 0
	var ko_total := 0
	var boss_hp := 0.0
	var boss_reached := 0
	var power_sum := 0.0
	var fail_at := {}
	for s in N:
		seed(20000 + s)
		var party := _build_party(p)
		power_sum += Combat.party_power(party)
		var diff: Dictionary = _diff_for(str(p[0])).duplicate()
		diff["biome"] = ["vale", "marsh", "ashen"][s % 3]   # regions set the foes and designed encounters
		var res := _run_rift(party, diff)
		if res["cleared"]:
			clears += 1
			_crystals += float(diff["seal_essence"])
		else:
			fail_at[res["fail_kind"]] = int(fail_at.get(res["fail_kind"], 0)) + 1
		if res["boss_hp"] >= 0.0:
			boss_reached += 1
			boss_hp += res["boss_hp"]
		for h in party:
			if h.hp <= 0:
				ko_total += 1
	print("   %s avg party power %.0f" % [name, power_sum / N])
	var runs := float(N)
	print("   %s income per run: %.0f gold, %.0f essence, loot worth %.0f gold" % [name, _coins / runs, _crystals / runs, _loot_value / runs])
	print("%-24s clear %5.1f%%  party HP entering boss %3.0f%%  heroes down at end %.2f  failed at: %s" % [
		name, 100.0 * clears / N, 100.0 * boss_hp / max(1, boss_reached), float(ko_total) / N, fail_at])


## Party templates from a fresh guild to a maxed one, for `-- calibrate`:
## [hero ranks, level, skill depth, gear rarity, relics, relic rarity].
const TEMPLATES := [
	[["F", "F", "F"], 1, 0, "", 0, "common"],
	[["F", "E", "E"], 2, 0, "common", 0, "common"],
	[["E", "E", "D"], 3, 1, "common", 1, "common"],
	[["E", "D", "D"], 4, 1, "common", 1, "common"],
	[["E", "D", "D", "D"], 5, 1, "rare", 1, "common"],
	[["D", "D", "C", "C"], 6, 2, "rare", 2, "rare"],
	[["D", "C", "C", "C"], 7, 2, "rare", 2, "rare"],
	[["C", "C", "B", "B"], 8, 2, "epic", 2, "rare"],
	[["C", "B", "B", "A"], 10, 3, "epic", 3, "epic"],
	[["B", "A", "A", "S"], 10, 3, "legendary", 3, "legendary"],
]


## Party power at which each ladder rank clears ~65% of the time — what its
## "Recommended" should say. Sweeps TEMPLATES upward until one clears 95%.
func _calibrate() -> void:
	for r in GameData.RIFT_RANKS:
		var id := str(r["id"])
		var diff := _diff_for(id).duplicate()
		diff["biome"] = ["vale", "marsh", "ashen"][GameData.rift_rank_index(id) % 3]
		var pts: Array = []
		for t in TEMPLATES:
			var p: Array = [id]
			p.append_array(t)
			var clears := 0
			var power := 0.0
			for s in 30:
				seed(30000 + s)
				var party := _build_party(p)
				power += Combat.party_power(party)
				if _run_rift(party, diff)["cleared"]:
					clears += 1
			pts.append([power / 30.0, clears / 30.0])
			if clears >= 29:
				break
		var at := -1.0
		for i in range(1, pts.size()):
			if pts[i - 1][1] < 0.65 and pts[i][1] >= 0.65:
				var f: float = (0.65 - pts[i - 1][1]) / maxf(0.01, pts[i][1] - pts[i - 1][1])
				at = lerpf(pts[i - 1][0], pts[i][0], f)
				break
		print("%-4s recommended %4d  power at 65%% clear %4.0f   %s" % [id, Combat.recommended_power("", id), at, ", ".join(pts.map(func(x): return "%.0f:%d%%" % [x[0], int(x[1] * 100)]))])
	# Tower: median floor each template reaches, and Endless: median survival.
	for t in TEMPLATES:
		var p: Array = ["tower"]
		p.append_array(t)
		var party := _build_party(p)
		var power := Combat.party_power(party)
		var tops: Array[int] = []
		for s in 6:
			seed(30000 + s)
			party = _build_party(p)
			var top := 0
			for f in range(1, GameData.TOWER_FLOORS + 1):
				var info := GameState.tower_floor_info(f)
				var fighters: Array[Hero] = [party[0]]
				fighters.append_array(party.slice(1, 1 + int(info["party_cap"])))
				var cleared := false
				for attempt in 3:
					for h in fighters:
						h.hp = Combat.max_hp(h)
						GameState.run = {"sim": true, "tower": f}
					seed(hash([int(info["seed"]), 0, 0]))
					if _fight(fighters, str(info["kind"]), GameState._tower_diff(info), GameData.TOWER_FIGHT_DEPTH):
						cleared = true
						break
				if not cleared:
					break
				top = f
			tops.append(top)
		tops.sort()
		var times: Array = []
		for i in 3:
			party = _build_party(p)
			var r := SurvivorsRun.new(party, ["vale", "marsh", "ashen"][i % 3], 1000 + i)
			while not r.over and r.time < 900.0:
				r.step(0.25, r.autopilot_dir())
				r.events.clear()
				while r.pending_levels > 0:
					var o := r.offer()
					r.pick(_best_pick(o))
			times.append(int(r.time))
		times.sort()
		print("power %4d  tower median floor %3d (rec there %d)  endless median %d:%02d" % [power, tops[3], GameState.tower_recommended_power(maxi(1, tops[3])), times[1] / 60, times[1] % 60])


func _diff_for(id: String) -> Dictionary:
	if id in MODES:
		return GameData.DIFFICULTIES[0 if id == "lesser" else 1]
	var base: Dictionary = GameData.DIFFICULTIES[0 if str(GameData.find_rift_rank(id)["base"]) == "lesser" else 1]
	return GameState._apply_rift_rank_modifiers(base, id)


## A fresh party for a profile (Champion first), gear and relics equipped.
func _build_party(p: Array) -> Array[Hero]:
	GameState.items.clear()
	GameState.relics.clear()
	GameState.heroes.clear()
	GameState.run = {}
	var party: Array[Hero] = []
	for r in p[1]:
		var h := Combat.gen_hero(r, p[2])
		_learn(h, p[3])
		GameState.heroes.append(h)
		party.append(h)
	for i in party.size():
		party[i].formation = "front" if i < 2 else "back"
		if p[4] != "":
			_gear(party[i], p[4])
		party[i].hp = Combat.max_hp(party[i])
	for i in p[5]:
		var rl := Combat.gen_relic(p[6])
		rl.equipped = true
		GameState.relics.append(rl)
	return party


## One rift: walk its layers, fight/hazard/shop, HP carries. Returns
## {cleared, fail_kind, boss_hp (party HP fraction entering boss, -1 if never)}
func _run_rift(party: Array[Hero], diff: Dictionary) -> Dictionary:
	GameState.run = {"sim": true} if CHAMP_V2 else {}
	var layers := Combat.build_layers(diff)
	var boss_hp := -1.0
	for pos in layers.size():
		var opts: Array = layers[pos]["options"]
		var kind: String = opts[0]
		var cur_f := 0.0
		var mx_f := 0.0
		for h in party:
			cur_f += max(0, h.hp)
			mx_f += Combat.max_hp(h)
		var prefs := ["combat", "shop", "elite", "hazard", "treasure", "event", "campfire"]
		if cur_f / mx_f < 0.6:
			prefs.push_front("campfire")
		for pref in prefs:
			if opts.has(pref):
				kind = pref
				break
		if opts.has("boss"):
			kind = "boss"
		var living: Array[Hero] = []
		living.assign(party.filter(func(h): return h.hp > 0))
		if living.is_empty():
			return {"cleared": false, "fail_kind": "wiped", "boss_hp": boss_hp}
		if kind == "boss":
			var cur := 0.0
			var mx := 0.0
			for h in party:
				cur += h.hp
				mx += Combat.max_hp(h)
			boss_hp = cur / mx
		match kind:
			"shop", "event":
				_tick(party)
			"treasure":
				_tick(party)
				_take_loot(living, Combat.gen_loot(Combat.weighted_rarity()))
			"campfire":
				_tick(party)
				if cur_f / mx_f < 0.8:
					for h in living:
						h.hp = min(Combat.max_hp(h), h.hp + int(ceil(Combat.max_hp(h) * 0.25)))
				else:
					for h in living:
						Combat.gain_xp(h, GameData.CAMPFIRE_TRAIN_XP)
						Combat.auto_spend_attrs(h)
			"hazard":
				_tick(party)
				var guard: float = min(0.9, Combat.party_skill_total(living, "hazard_guard_pct") + Combat.relic_special_total("hazard_guard_pct"))
				var dmg: float = (6.0 + int(diff["floors"]) * 2.0) * 1.05 * (1.0 - guard)
				for h in living:
					h.hp = max(0, int(round(h.hp - dmg / living.size())))
			_:
				if not _fight(living, kind, diff, pos):
					return {"cleared": false, "fail_kind": kind, "boss_hp": boss_hp}
	return {"cleared": true, "fail_kind": "", "boss_hp": boss_hp}


func _tick(_party: Array[Hero]) -> void:
	pass


func _fight(living: Array[Hero], kind: String, diff: Dictionary, pos: int) -> bool:
	var state := Combat.start_combat(living, kind, diff, pos)
	for t in 400:
		var nxt := Combat.peek_next_turn(state)
		if nxt["type"] == "hero":
			var h: Hero = living.filter(func(x): return x.id == str(nxt["id"]))[0]
			state["pending_actions"][h.id] = Combat.auto_action(state, h)
		var out := Combat.resolve_turn(state)
		if out["done"]:
			var won := bool(out["result"]["won"])
			if won:
				_coins += float(out["result"].get("coin", 0))
				_crystals += float(out["result"].get("crystal", 0)) + float(out["result"].get("bonus_crystal", 0))
				for o in out["result"].get("reward_options", []).slice(0, 1):
					_loot_value += 15.0 * float(GameData.find_rarity(str(o["obj"].rarity))["mult"]) * 0.85
			if won and kind == "elite" and BOONS:
				var offer: Array = GameState.roll_boon_offer()
				if not offer.is_empty():
					var bs: Array = GameState.run.get("boons", [])
					bs.append(offer[randi() % offer.size()])
					GameState.run["boons"] = bs
			if won and GAINS:
				for h in living:
					Combat.auto_spend_attrs(h)
				var opts: Array = out["result"].get("reward_options", [])
				if not opts.is_empty():
					_take_loot(living, opts[0])
			return won
	return false


## Mid-run loot: an item goes on whoever has a free matching slot and meets
## its requirement; relics equip while there's a slot.
func _take_loot(living: Array[Hero], loot: Dictionary) -> void:
	if not GAINS:
		return
	if loot["loot_type"] == "relic":
		if Combat.equipped_relics().size() < 3:
			loot["obj"].equipped = true
			GameState.relics.append(loot["obj"])
		return
	var it: Item = loot["obj"]
	it.id = "sim%d" % GameState.items.size()
	GameState.items.append(it)
	for h in living:
		if h.is_champion or not GameState.attr_req_met(it, h):
			continue
		var cap := GameData.weapon_slots(h.pool_id) if it.slot_type() == "weapon" else GameData.gear_slots(h.rank)
		var used := GameState.items.filter(func(x): return x.equipped_to == h.id and x.slot_type() == it.slot_type()).map(func(x): return x.equipped_idx)
		for idx in cap:
			if not used.has(idx):
				it.equipped_to = h.id
				it.equipped_idx = idx
				return


func _learn(h: Hero, depth: int) -> void:
	if depth <= 0:
		return
	var kind: String = h.innate_kind
	var keys := ["edge"]
	var pkg: Array = GameData.KIND_SKILL_PACKAGE[kind]
	if depth >= 2:
		keys.append("hide")
		for n in pkg.filter(func(n): return int(n["tier"]) == 2).slice(0, 2):
			keys.append(n["id"])
	if depth >= 3:
		var cap: Dictionary = pkg.filter(func(n): return n["id"] == "cap")[0]
		for r in cap["requires"]:
			if not keys.has(r):
				keys.append(r)
		keys.append("cap")
		for n in pkg.filter(func(n): return int(n["tier"]) == 2):
			if not keys.has(n["id"]) and keys.size() < 9:
				keys.append(n["id"])
	for k in keys:
		h.skills[GameData.skill_storage_key(kind, k)] = true


func _gear(h: Hero, rarity: String) -> void:
	var w := Combat.gen_item(rarity, "weapon")
	w.equipped_to = h.id
	w.equipped_idx = 0
	GameState.items.append(w)
	for i in GameData.gear_slots(h.rank):
		var g := Combat.gen_item(rarity, ["armor", "focus"][i % 2])
		g.equipped_to = h.id
		g.equipped_idx = i
		GameState.items.append(g)


func _lowest(monsters: Array) -> int:
	var best := -1
	for i in monsters.size():
		if float(monsters[i]["hp"]) > 0 and (best < 0 or float(monsters[i]["hp"]) < float(monsters[best]["hp"])):
			best = i
	return max(best, 0)
