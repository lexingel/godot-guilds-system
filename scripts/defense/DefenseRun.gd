class_name DefenseRun
extends RefCounted
## A Riftbreak defense (docs/design/riftbreak.md): a pure simulation like
## SurvivorsRun, so tests and the balance sim can step it headless. Foes walk
## the map's routes to the goal; towers on pads, heroes at posts and one
## steered champion stop them. Call step(dt) every frame and read `events`
## for what to draw. Numbers live in GameDataBreach.

const FIELD := Rect2(0, 0, 1280, 720)
const JOIN_R := 30.0       # a path ending this close to another joins it
const FOE_R := {"combat": 14.0, "elite": 22.0, "boss": 36.0}

var rng := RandomNumberGenerator.new()
var region := "vale"
var rank := 0
var foe_mult := 1.0
var map: Dictionary = {}
var routes: Array = []     # entry to goal: {pts: Array[Vector2], cum: Array[float], len}
var pads: Array = []       # {pos, tower ("" = empty), tier, cd, spent, cover}
var heroes: Array = []     # {hero, role, pos, home, alive, hp, max_hp, dmg, cd, block, champion, target, respawn_t, sig_cd, style}
var foes: Array = []       # {id, name, tier, route, d, pos, hp, max_hp, dmg, speed, slow_t, slow, stun_t, burn_t, burn_dps, held_by, hit_cd, facing, dead}
var events: Array = []     # drained by the view each frame
var supplies := 0
var integrity := 0
var max_integrity := 0
var wave := 0              # waves started so far
var waves_total := 0
var build_t := 0.0         # seconds until the next wave (> 0: a build phase)
var spawning: Array = []   # this wave's foes still to come: {t, tier, route}
var time := 0.0
var over := false
var held := false
var kills := 0
var fallen: Array = []     # ids of stationed heroes who fell (they come back wounded)
var tower_types: Array = []   # tower ids this guild can build
var max_tier := 2          # how many tiers this guild can build (research raises it to 3)
var tower_dmg := 1.0       # research: Armory
var cost_mult := 1.0       # research: Engineering
var sell_back := GameData.DEFENSE_SELL_BACK
var _next_id := 0
var _wave_t := 0.0


## defenders: roster heroes for the posts (in post order); champion: a
## champion Hero to steer, or null. opts: {supplies, integrity, towers, max_tier}.
func _init(region_id: String, rank_idx: int, defenders: Array, champion: Hero = null, seed_val: int = 0, opts: Dictionary = {}) -> void:
	rng.seed = seed_val if seed_val != 0 else randi()
	region = region_id
	rank = rank_idx
	map = GameData.DEFENSE_MAPS.get(region, GameData.DEFENSE_MAPS["vale"])
	supplies = GameData.DEFENSE_SUPPLIES + int(opts.get("supplies", 0))
	max_integrity = GameData.DEFENSE_INTEGRITY + int(opts.get("integrity", 0))
	integrity = max_integrity
	tower_types = opts.get("towers", ["ballista", "brazier"])
	max_tier = int(opts.get("max_tier", 2))
	tower_dmg = float(opts.get("tower_dmg", 1.0))
	cost_mult = float(opts.get("cost", 1.0))
	sell_back = float(opts.get("sell_back", GameData.DEFENSE_SELL_BACK))
	var hero_hp := float(opts.get("hero_hp", 1.0))
	foe_mult = float(opts.get("foe_mult", 1.0))   # a tide of the Open Hollow
	waves_total = GameData.DEFENSE_WAVES + (GameData.DEFENSE_CAMP_WAVES if region == "camp" else 0)
	build_t = GameData.DEFENSE_FIRST_BUILD
	_build_routes()
	for p in map["pads"]:
		pads.append({"pos": p, "tower": "", "tier": 0, "cd": 0.0, "spent": 0, "cover": _cover(p, 220.0)})
	var posts: Array = map["posts"]
	for i in mini(defenders.size(), posts.size()):
		_add_hero(defenders[i], posts[i], false)
		heroes[-1]["max_hp"] = float(heroes[-1]["max_hp"]) * hero_hp
		heroes[-1]["hp"] = heroes[-1]["max_hp"]
	if champion:
		_add_hero(champion, map["goal"] + Vector2(-70, 0), true)


func _add_hero(h: Hero, at: Vector2, champ: bool) -> void:
	var role := GameData.hero_role(h)
	var mhp := float(Combat.max_hp(h))
	var call: Dictionary = GameState.champion_call_of(h.id.trim_prefix("champ:")) if champ else {}
	heroes.append({"hero": h, "role": role, "pos": at, "home": at, "alive": true, "hp": mhp, "max_hp": mhp,
		"dmg": float(Combat.dmg_of(h)), "cd": rng.randf() * 0.5, "block": int(GameData.DEFENSE_BLOCK.get(role, 0)),
		"champion": champ, "target": at, "respawn_t": 0.0, "sig_cd": GameData.DEFENSE_SIGNATURE_CD * 0.5,
		"style": str(SurvivorsRun.ABILITY_STYLE.get(str(call.get("effect", "")), "")), "sig_name": str(call.get("name", "")), "facing": 1.0})


## Every path that enters from off the field, followed through its joins to the goal.
func _build_routes() -> void:
	var paths: Array = map["paths"]
	for p in paths:
		if FIELD.has_point(p[0]):
			continue
		var pts: Array = (p as Array).duplicate()
		for guard in 6:
			var last: Vector2 = pts[-1]
			if last.distance_to(map["goal"]) < 5.0:
				break
			var joined := false
			for q in paths:
				if q == p:
					continue
				for j in (q as Array).size():
					if (q[j] as Vector2).distance_to(last) <= JOIN_R and j < (q as Array).size() - 1:
						pts.append_array((q as Array).slice(j + 1))
						joined = true
						break
				if joined:
					break
			if not joined:
				break
		var cum: Array = [0.0]
		for k in range(1, pts.size()):
			cum.append(float(cum[-1]) + (pts[k] as Vector2).distance_to(pts[k - 1]))
		routes.append({"pts": pts, "cum": cum, "len": float(cum[-1])})


## Where a foe is, `d` along route r.
func route_pos(r: int, d: float) -> Vector2:
	var rt: Dictionary = routes[r]
	var cum: Array = rt["cum"]
	var pts: Array = rt["pts"]
	for k in range(1, pts.size()):
		if d <= float(cum[k]):
			var seg := float(cum[k]) - float(cum[k - 1])
			return (pts[k - 1] as Vector2).lerp(pts[k], (d - float(cum[k - 1])) / maxf(seg, 0.001))
	return pts[-1]


## How much road (sampled) lies within `r` of p: ranks pads for the autoplayer.
func _cover(p: Vector2, r: float) -> float:
	var n := 0.0
	for ri in routes.size():
		var d := 0.0
		while d < float(routes[ri]["len"]):
			if route_pos(ri, d).distance_to(p) <= r:
				n += 20.0
			d += 20.0
	return n


# ---------------- Step ----------------

func step(dt: float) -> void:
	if over:
		return
	time += dt
	if build_t > 0.0:
		build_t -= dt
		if build_t <= 0.0:
			_start_wave()
	_spawn(dt)
	_towers(dt)
	_heroes(dt)
	_move_foes(dt)
	_statuses(dt)
	foes = foes.filter(func(f): return not f["dead"])
	if integrity <= 0:
		integrity = 0
		over = true
		held = false
		events.append({"type": "lost"})
	elif wave >= waves_total and spawning.is_empty() and foes.is_empty():
		over = true
		held = true
		events.append({"type": "held"})
	elif build_t <= 0.0 and spawning.is_empty() and foes.is_empty():
		build_t = GameData.DEFENSE_BUILD_TIME
		events.append({"type": "wave_clear", "wave": wave})


## Skip the rest of a build phase for supplies.
func call_early() -> void:
	if build_t <= 0.0 or over:
		return
	var bonus := int(build_t * GameData.DEFENSE_EARLY_SUPPLIES)
	supplies += bonus
	build_t = 0.0
	events.append({"type": "early", "supplies": bonus})
	_start_wave()


func _start_wave() -> void:
	build_t = 0.0
	wave += 1
	_wave_t = 0.0
	var k := wave - 1
	var n := 6 + 2 * k
	for i in n:
		spawning.append({"t": i * 1.1, "tier": "combat", "route": i % routes.size()})
	for i in ((k + 1) / 3 if k >= 2 else 0):   # elites: 1 from wave 3, 2 from wave 6, 3 from wave 9
		spawning.append({"t": 3.0 + i * 4.0, "tier": "elite", "route": rng.randi() % routes.size()})
	if wave == waves_total:
		spawning.append({"t": n * 1.1 + 2.0, "tier": "boss", "route": rng.randi() % routes.size()})
	events.append({"type": "wave", "wave": wave, "total": waves_total, "boss": wave == waves_total})


func _spawn(dt: float) -> void:
	if spawning.is_empty():
		return
	_wave_t += dt
	for s in spawning.duplicate():
		if _wave_t >= float(s["t"]):
			spawning.erase(s)
			_add_foe(str(s["tier"]), int(s["route"]))


func _add_foe(tier: String, r: int) -> Dictionary:
	var b: Dictionary = GameData.BIOMES.get(region, GameData.BIOMES[["vale", "marsh", "ashen"][rng.randi() % 3]])
	var name := str(GameData.BOSS_NAMES[rng.randi() % GameData.BOSS_NAMES.size()]) if tier == "boss" else str((b["elites"] if tier == "elite" else b["monsters"])[rng.randi() % (b["elites"] if tier == "elite" else b["monsters"]).size()])
	var hp := foe_mult * GameData.DEFENSE_HP0 * (1.0 + GameData.DEFENSE_HP_PER_RANK * rank) * (1.0 + GameData.DEFENSE_HP_PER_WAVE * (wave - 1)) * float(GameData.DEFENSE_TIER_HP[tier]) * rng.randf_range(0.9, 1.1)
	_next_id += 1
	var f := {"id": _next_id, "name": name, "tier": tier, "route": r, "d": 0.0, "pos": route_pos(r, 0.0), "hp": hp, "max_hp": hp,
		"dmg": foe_mult * GameData.DEFENSE_DMG0 * (1.0 + GameData.DEFENSE_DMG_PER_RANK * rank) * float(GameData.DEFENSE_TIER_DMG[tier]),
		"speed": float(GameData.DEFENSE_TIER_SPEED[tier]) * rng.randf_range(0.9, 1.15), "r": float(FOE_R[tier]),
		"slow_t": 0.0, "slow": 0.0, "stun_t": 0.0, "burn_t": 0.0, "burn_dps": 0.0, "held_by": -1, "hit_cd": 0.5, "facing": 1.0, "dead": false, "flash": 0.0}
	foes.append(f)
	events.append({"type": "spawn", "id": f["id"], "tier": tier})
	return f


## How far along its road a foe is (0-1): towers aim at the one closest to the goal.
func progress(f: Dictionary) -> float:
	return float(f["d"]) / maxf(1.0, float(routes[int(f["route"])]["len"]))


func _move_foes(dt: float) -> void:
	for f in foes:
		if f["dead"]:
			continue
		f["flash"] = maxf(0.0, float(f["flash"]) - dt)
		f["stun_t"] = maxf(0.0, float(f["stun_t"]) - dt)
		var hi := int(f["held_by"])
		if hi >= 0 and not heroes[hi]["alive"]:
			f["held_by"] = -1
			hi = -1
		if hi >= 0:
			# Held: trade blows with the hero holding it.
			f["hit_cd"] = float(f["hit_cd"]) - dt
			if float(f["hit_cd"]) <= 0.0 and float(f["stun_t"]) <= 0.0:
				f["hit_cd"] = 1.0
				_hurt_hero(hi, float(f["dmg"]))
			continue
		if float(f["stun_t"]) > 0.0:
			continue
		var slow := float(f["slow"]) if float(f["slow_t"]) > 0.0 else 0.0
		var before: Vector2 = f["pos"]
		f["d"] = float(f["d"]) + float(f["speed"]) * (1.0 - slow) * dt
		var rt: Dictionary = routes[int(f["route"])]
		if float(f["d"]) >= float(rt["len"]):
			f["dead"] = true
			integrity -= int(GameData.DEFENSE_LEAK[f["tier"]])
			events.append({"type": "leak", "id": f["id"], "tier": f["tier"], "pos": map["goal"]})
			continue
		f["pos"] = route_pos(int(f["route"]), float(f["d"]))
		if (f["pos"] as Vector2).x != before.x:
			f["facing"] = signf((f["pos"] as Vector2).x - before.x)


func _statuses(dt: float) -> void:
	for f in foes:
		f["slow_t"] = maxf(0.0, float(f["slow_t"]) - dt)
		if float(f["burn_t"]) > 0.0 and not f["dead"]:
			f["burn_t"] = float(f["burn_t"]) - dt
			_damage(f, float(f["burn_dps"]) * dt, false)


func _damage(f: Dictionary, dmg: float, flash: bool = true) -> void:
	if f["dead"]:
		return
	f["hp"] = float(f["hp"]) - dmg
	if flash:
		f["flash"] = 0.12
	if float(f["hp"]) > 0.0:
		return
	f["dead"] = true
	kills += 1
	supplies += int(GameData.DEFENSE_KILL_SUPPLIES[f["tier"]])
	events.append({"type": "kill", "id": f["id"], "pos": f["pos"], "tier": f["tier"], "name": f["name"]})


func _foes_near(p: Vector2, r: float) -> Array:
	return foes.filter(func(f): return not f["dead"] and (f["pos"] as Vector2).distance_to(p) <= r + float(f["r"]))


## The foe in reach closest to the goal.
func _lead_foe(p: Vector2, r: float) -> Dictionary:
	var best: Dictionary = {}
	for f in _foes_near(p, r):
		if best.is_empty() or progress(f) > progress(best):
			best = f
	return best


# ---------------- Towers ----------------

func tower_stat(pad: Dictionary, key: String) -> float:
	return float(GameData.DEFENSE_TOWERS[pad["tower"]][key][int(pad["tier"])])


func _tower_power() -> float:
	return (1.0 + GameData.DEFENSE_TOWER_RANK_SCALE * rank) * tower_dmg


func _towers(dt: float) -> void:
	for pad in pads:
		if pad["tower"] == "":
			continue
		pad["cd"] = float(pad["cd"]) - dt
		if float(pad["cd"]) > 0.0:
			continue
		var def: Dictionary = GameData.DEFENSE_TOWERS[pad["tower"]]
		var reach := tower_stat(pad, "range")
		var fired := false
		match str(def["kind"]):
			"bolt":
				var t := _lead_foe(pad["pos"], reach)
				if not t.is_empty():
					events.append({"type": "shot", "kind": "bolt", "from": pad["pos"], "to": t["pos"]})
					_damage(t, tower_stat(pad, "dmg") * _tower_power())
					fired = true
			"fire":
				var t := _lead_foe(pad["pos"], reach)
				if not t.is_empty():
					var at: Vector2 = t["pos"]
					events.append({"type": "shot", "kind": "fire", "from": pad["pos"], "to": at, "r": float(def["splash"])})
					for f in _foes_near(at, float(def["splash"])):
						_damage(f, tower_stat(pad, "dmg") * _tower_power())
						f["burn_t"] = 3.0
						f["burn_dps"] = maxf(float(f["burn_dps"]), tower_stat(pad, "dmg") * _tower_power() * float(def["burn"]))
					fired = true
			"aura":
				var near := _foes_near(pad["pos"], reach)
				for f in near:
					f["slow_t"] = 1.2
					f["slow"] = maxf(float(f["slow"]) if float(f["slow_t"]) > 0.0 else 0.0, tower_stat(pad, "slow"))
					_damage(f, tower_stat(pad, "dmg") * _tower_power(), false)
				if not near.is_empty():
					events.append({"type": "pulse", "kind": "frost", "pos": pad["pos"], "r": reach})
				fired = true
			"heal":
				for h in heroes:
					if h["alive"] and (h["pos"] as Vector2).distance_to(pad["pos"]) <= reach and float(h["hp"]) < float(h["max_hp"]):
						h["hp"] = minf(float(h["max_hp"]), float(h["hp"]) + float(h["max_hp"]) * tower_stat(pad, "heal"))
						events.append({"type": "heal", "pos": h["pos"]})
				fired = true
			"ward":
				fired = true
		pad["cd"] = tower_stat(pad, "cd") if fired else 0.2


## The best Ward Stone guard over a spot (0-1).
func _guard_at(p: Vector2) -> float:
	var g := 0.0
	for pad in pads:
		if pad["tower"] != "" and str(GameData.DEFENSE_TOWERS[pad["tower"]]["kind"]) == "ward" and (pad["pos"] as Vector2).distance_to(p) <= tower_stat(pad, "range"):
			g = maxf(g, tower_stat(pad, "guard"))
	return g


func tower_cost(type: String, tier: int) -> int:
	return int(round(int(GameData.DEFENSE_TOWERS[type]["cost"][tier]) * cost_mult))


## "" if a tower of `type` can go on empty pad i, else why not.
func can_build(i: int, type: String) -> String:
	if not tower_types.has(type):
		return tr("Not researched yet")
	if pads[i]["tower"] != "":
		return tr("Something is built here")
	if supplies < tower_cost(type, 0):
		return tr("Not enough supplies")
	return ""


func build(i: int, type: String) -> String:
	var why := can_build(i, type)
	if why != "":
		return why
	var cost := tower_cost(type, 0)
	supplies -= cost
	pads[i]["tower"] = type
	pads[i]["tier"] = 0
	pads[i]["cd"] = 0.3
	pads[i]["spent"] = cost
	events.append({"type": "build", "pad": i})
	return ""


func can_upgrade(i: int) -> String:
	var pad: Dictionary = pads[i]
	if pad["tower"] == "":
		return tr("Nothing built here")
	if int(pad["tier"]) + 1 >= mini(max_tier, 3):
		return tr("Research raises the tier cap") if int(pad["tier"]) + 1 < 3 else tr("Fully upgraded")
	if supplies < tower_cost(pad["tower"], int(pad["tier"]) + 1):
		return tr("Not enough supplies")
	return ""


func upgrade(i: int) -> String:
	var why := can_upgrade(i)
	if why != "":
		return why
	var cost := tower_cost(pads[i]["tower"], int(pads[i]["tier"]) + 1)
	supplies -= cost
	pads[i]["tier"] = int(pads[i]["tier"]) + 1
	pads[i]["spent"] = int(pads[i]["spent"]) + cost
	events.append({"type": "build", "pad": i})
	return ""


func sell(i: int) -> int:
	if pads[i]["tower"] == "":
		return 0
	var back := int(int(pads[i]["spent"]) * sell_back)
	supplies += back
	pads[i]["tower"] = ""
	pads[i]["tier"] = 0
	pads[i]["spent"] = 0
	return back


# ---------------- Heroes and the champion ----------------

func champion() -> Dictionary:
	for h in heroes:
		if h["champion"]:
			return h
	return {}


## Sends the champion toward a spot on the field.
func move_champion(to: Vector2) -> void:
	var c := champion()
	if not c.is_empty():
		c["target"] = Vector2(clampf(to.x, 20.0, FIELD.size.x - 20.0), clampf(to.y, 20.0, FIELD.size.y - 20.0))
		_release(heroes.find(c))


func _release(hi: int) -> void:
	for f in foes:
		if int(f["held_by"]) == hi:
			f["held_by"] = -1


func _heroes(dt: float) -> void:
	for hi in heroes.size():
		var h: Dictionary = heroes[hi]
		if not h["alive"]:
			if h["champion"]:
				h["respawn_t"] = float(h["respawn_t"]) - dt
				if float(h["respawn_t"]) <= 0.0:
					h["alive"] = true
					h["hp"] = h["max_hp"]
					h["pos"] = map["goal"] + Vector2(-70, 0)
					h["target"] = h["pos"]
					events.append({"type": "respawn", "hero": h["hero"].id})
			continue
		var w: Dictionary = SurvivorsRun.WEAPONS.get(h["role"], SurvivorsRun.WEAPONS["warrior"])
		var reach := float(GameData.DEFENSE_HERO_RANGE.get(h["role"], 60.0))
		# The champion walks where it was sent (and holds nothing on the way).
		if h["champion"]:
			var to: Vector2 = h["target"]
			var off: Vector2 = to - (h["pos"] as Vector2)
			if off.length() > 4.0:
				h["pos"] = (h["pos"] as Vector2) + off.normalized() * minf(off.length(), GameData.DEFENSE_CHAMP_SPEED * dt)
				h["facing"] = signf(off.x) if absf(off.x) > 1.0 else float(h["facing"])
				continue
			h["sig_cd"] = float(h["sig_cd"]) - dt
			if float(h["sig_cd"]) <= 0.0 and not _foes_near(h["pos"], 250.0).is_empty():
				h["sig_cd"] = GameData.DEFENSE_SIGNATURE_CD
				_signature(h)
		# Melee heroes hold foes that reach them.
		if int(h["block"]) > 0:
			var holding := foes.filter(func(f): return not f["dead"] and int(f["held_by"]) == hi).size()
			for f in _foes_near(h["pos"], reach):
				if holding >= int(h["block"]):
					break
				if int(f["held_by"]) < 0:
					f["held_by"] = hi
					holding += 1
		h["cd"] = float(h["cd"]) - dt
		if float(h["cd"]) > 0.0:
			continue
		if h["role"] == "cleric":
			var low: Dictionary = {}
			for o in heroes:
				if o["alive"] and (o["pos"] as Vector2).distance_to(h["pos"]) <= 170.0 and float(o["hp"]) < float(o["max_hp"]) and (low.is_empty() or float(o["hp"]) / float(o["max_hp"]) < float(low["hp"]) / float(low["max_hp"])):
					low = o
			if not low.is_empty():
				low["hp"] = minf(float(low["max_hp"]), float(low["hp"]) + float(low["max_hp"]) * 0.06)
				events.append({"type": "heal", "pos": low["pos"]})
		var held_foes := foes.filter(func(f): return not f["dead"] and int(f["held_by"]) == hi)
		var t: Dictionary = held_foes[0] if not held_foes.is_empty() else _lead_foe(h["pos"], reach)
		if t.is_empty():
			h["cd"] = 0.15
			continue
		h["cd"] = float(w["cd"])
		h["facing"] = signf((t["pos"] as Vector2).x - (h["pos"] as Vector2).x) if absf((t["pos"] as Vector2).x - (h["pos"] as Vector2).x) > 1.0 else float(h["facing"])
		var dmg := float(h["dmg"]) * float(w["mult"])
		events.append({"type": "hero_hit", "hero": h["hero"].id, "from": h["pos"], "to": t["pos"], "role": h["role"]})
		if h["role"] == "mage":
			for f in _foes_near(t["pos"], 55.0):
				_damage(f, dmg)
		else:
			_damage(t, dmg)


## The champion's signature: area damage, a stun, or mending, by its style.
func _signature(h: Dictionary) -> void:
	var style := str(h["style"])
	var p: Vector2 = h["pos"]
	events.append({"type": "ability", "hero": h["hero"].id, "name": h["sig_name"], "pos": p})
	if style in ["freeze", "stun", "slow"]:
		for f in _foes_near(p, 170.0):
			f["stun_t"] = 2.5
			if style == "stun":
				_damage(f, float(h["dmg"]) * 2.0)
		events.append({"type": "pulse", "kind": "frost", "pos": p, "r": 170.0})
	elif style in ["mend", "revive", "wall", "rally", "evasion", "lifesteal", "undying", "blood"]:
		for o in heroes:
			if o["alive"] and (o["pos"] as Vector2).distance_to(p) <= 240.0:
				o["hp"] = minf(float(o["max_hp"]), float(o["hp"]) + float(o["max_hp"]) * 0.3)
				events.append({"type": "heal", "pos": o["pos"]})
		for f in _foes_near(p, 150.0):
			_damage(f, float(h["dmg"]) * 1.5)
	else:
		for f in _foes_near(p, 160.0):
			_damage(f, float(h["dmg"]) * 3.5)
			if style == "burn":
				f["burn_t"] = 4.0
				f["burn_dps"] = maxf(float(f["burn_dps"]), float(h["dmg"]) * 0.8)
		events.append({"type": "pulse", "kind": "blast", "pos": p, "r": 160.0})


func _hurt_hero(hi: int, dmg: float) -> void:
	var h: Dictionary = heroes[hi]
	if not h["alive"]:
		return
	h["hp"] = float(h["hp"]) - dmg * (1.0 - _guard_at(h["pos"]))
	events.append({"type": "hurt", "hero": h["hero"].id})
	if float(h["hp"]) > 0.0:
		return
	h["alive"] = false
	h["hp"] = 0.0
	_release(hi)
	events.append({"type": "down", "hero": h["hero"].id, "pos": h["pos"]})
	if h["champion"]:
		h["respawn_t"] = GameData.DEFENSE_CHAMP_RESPAWN
	else:
		fallen.append(h["hero"].id)


# ---------------- Result, autoplay ----------------

## For GameState.resolve_breach.
func result() -> Dictionary:
	return {"held": held, "integrity": float(integrity) / float(max_integrity), "fallen": fallen.duplicate()}


## Tests and the balance sim: builds like a sensible player. Fills the pads
## that cover the most road first (mostly damage towers, a frost totem
## early, a ward and a chapel later), then upgrades the cheapest.
func autoplay() -> void:
	var order: Array = range(pads.size())
	order.sort_custom(func(a, b): return float(pads[a]["cover"]) > float(pads[b]["cover"]))
	var cycle: Array = ["ballista", "brazier", "frost", "ballista", "brazier", "ballista", "ward", "brazier", "chapel", "ballista"].filter(func(t): return tower_types.has(t))
	var built := pads.filter(func(p): return p["tower"] != "").size()
	for i in order:
		if pads[i]["tower"] == "" and not cycle.is_empty():
			var type: String = cycle[built % cycle.size()]
			if build(i, type) == "":
				built += 1
			else:
				break
	var best := -1
	for i in pads.size():
		if can_upgrade(i) == "" and (best < 0 or tower_cost(pads[i]["tower"], int(pads[i]["tier"]) + 1) < tower_cost(pads[best]["tower"], int(pads[best]["tier"]) + 1)):
			best = i
	if best >= 0:
		upgrade(best)
