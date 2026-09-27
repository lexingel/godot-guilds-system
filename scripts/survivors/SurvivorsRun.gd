class_name SurvivorsRun
extends RefCounted
## The Endless Rift: a survivors-style run. Pure simulation (no nodes) so it
## can be stepped headless — SurvivorsView draws it, tests and the balance sim
## drive it directly. Call step(dt, move_dir) every frame; read `events` for
## what to animate, `pending_levels` for level-up picks.

const ARENA_SPAWN_R := 820.0      # foes appear on a ring this far from the lead
const MAX_FOES := 260
const MAX_GEMS := 120             # past this the oldest shards merge (no XP lost)
const HERO_R := 14.0
const CONTACT_CD := 0.6           # a foe touching a hero hits this often
const LEAD_SPEED := 120.0         # px/s at speed 10
const PICKUP_R := 100.0
const MON_HP0 := 30.0             # a regular foe at minute 0 (before scaling)
const MON_DMG0 := 3.2
const ELITE_EVERY := 60.0
const RING_EVERY := 45.0          # a closing ring of foes surrounds the party
const BOSS_EVERY := 300.0
const GRID := 48.0
const REVIVE_AFTER := 15.0        # a downed companion gets back up (the lead's fall ends the run)

## Auto-attacks per role. kind: "arc" (hits everything around the hero),
## "stab" (nearest foe in reach), "shot" (projectile at the nearest foe),
## "bolt" (projectile that bursts), "pulse" (ring around the hero + heals).
const WEAPONS := {
	"warrior": {"kind": "arc", "cd": 1.1, "mult": 1.5, "range": 70.0},
	"rogue": {"kind": "stab", "cd": 0.45, "mult": 1.1, "range": 75.0},
	"ranger": {"kind": "shot", "cd": 0.7, "mult": 1.0, "range": 360.0, "pierce": 1},
	"mage": {"kind": "bolt", "cd": 1.3, "mult": 1.2, "range": 320.0, "burst": 55.0},
	"cleric": {"kind": "pulse", "cd": 1.6, "mult": 0.6, "range": 95.0},
}
## Every 8s a hero with an Ability unleashes a bigger version of its attack.
const ABILITY_CD := 8.0

## Level-up picks: id -> {name, desc, icon, max}. Effects read in _stat().
const UPGRADES := {
	"might": {"name": "Sharpened Steel", "desc": "+15% damage for the whole party", "icon": "res://assets/skills/sword_a.png", "max": 6},
	"haste": {"name": "Battle Rhythm", "desc": "Attacks come 10% faster", "icon": "res://assets/skills/wing.png", "max": 5},
	"area": {"name": "Wide Arcs", "desc": "+20% attack area and burst size", "icon": "res://assets/skills/gem_red.png", "max": 4},
	"multishot": {"name": "Split Shot", "desc": "Rangers and Mages fire one more projectile", "icon": "res://assets/skills/sword_dual.png", "max": 3},
	"vigor": {"name": "Vigor", "desc": "+20% max HP, and heal 30% now", "icon": "res://assets/skills/heart.png", "max": 5},
	"regen": {"name": "Second Wind", "desc": "Heroes regain 1% HP every second", "icon": "res://assets/skills/potion_red.png", "max": 3},
	"armor": {"name": "Tempered Plate", "desc": "Take 12% less damage from foes", "icon": "res://assets/skills/armor_chest.png", "max": 4},
	"speed": {"name": "Fleet Foot", "desc": "+12% move speed", "icon": "res://assets/skills/boots.png", "max": 4},
	"magnet": {"name": "Shard Lure", "desc": "+50% pickup range", "icon": "res://assets/skills/gem_blue_a.png", "max": 3},
	"focus": {"name": "Focused Mind", "desc": "Abilities come back 20% sooner", "icon": "res://assets/skills/eye_gem.png", "max": 3},
	"thorns": {"name": "Barbed Guard", "desc": "Foes that hit a hero take 40% of your damage back", "icon": "res://assets/skills/shield_orange.png", "max": 3},
}

var rng := RandomNumberGenerator.new()
var biome := "vale"
var time := 0.0
var kills := 0
var elites_killed := 0
var kill_counts := {}       # foe name -> kills (feeds the Bestiary / Records)
var bosses_killed := 0
var level := 1
var xp := 0
var pending_levels := 0
var upgrades := {}          # id -> stacks
var heroes: Array = []      # {hero, role, pos, hp, max_hp, alive, lead, cd, ab_cd, facing, has_ability}
var foes: Array = []        # {id, name, tier, pos, hp, max_hp, dmg, speed, r, hit_cd, xp, alive, phased}
var gems: Array = []        # {pos, xp}
var shots: Array = []       # {pos, vel, dmg, r, life, pierce, burst, hit}
var events: Array = []      # drained by the view each frame
var over := false
var _next_id := 0
var _spawn_acc := 0.0
var _next_elite := ELITE_EVERY
var _next_ring := 120.0
var _next_boss := BOSS_EVERY


func _init(party: Array, biome_id: String = "vale", seed_val: int = 0) -> void:
	rng.seed = seed_val if seed_val != 0 else randi()
	biome = biome_id
	for i in party.size():
		var h: Hero = party[i]
		var mhp := float(Combat.max_hp(h))
		heroes.append({"hero": h, "role": GameData.hero_role(h), "pos": Vector2(-40.0 * i, 30.0 * (i % 2)), "hp": mhp, "max_hp": mhp,
			"alive": true, "lead": i == 0, "cd": rng.randf() * 0.5, "ab_cd": ABILITY_CD * 0.5, "facing": 1.0,
			"has_ability": Combat.qualifies_for_ability(h)})


func lead() -> Dictionary:
	return heroes[0]


func xp_next() -> int:
	return 5 + 4 * (level - 1) + int(pow(level - 1, 1.5))


func minutes() -> float:
	return time / 60.0


func _stat(id: String) -> int:
	return int(upgrades.get(id, 0))


func dmg_mult() -> float:
	return 1.0 + 0.15 * _stat("might")


## Foe strength grows with time: HP faster than damage.
func foe_hp_mult() -> float:
	var m := minutes()
	return 1.0 + 0.3 * m + 0.055 * m * m


func foe_dmg_mult() -> float:
	return 1.0 + 0.22 * minutes()


# ---------------- Step ----------------

func step(dt: float, move_dir: Vector2) -> void:
	if over or pending_levels > 0:
		return
	time += dt
	_move_heroes(dt, move_dir)
	_spawn(dt)
	_move_foes(dt)
	_attacks(dt)
	_move_shots(dt)
	_contact(dt)
	_pickups(dt)
	if _stat("regen") > 0:
		for h in heroes:
			if h["alive"]:
				h["hp"] = minf(h["max_hp"], h["hp"] + h["max_hp"] * 0.01 * _stat("regen") * dt)
	for h in heroes:
		if not h["alive"] and not h["lead"]:
			h["down_t"] = float(h.get("down_t", 0.0)) + dt
			if h["down_t"] >= REVIVE_AFTER:
				h["alive"] = true
				h["down_t"] = 0.0
				h["hp"] = h["max_hp"] * 0.5
				h["pos"] = lead()["pos"]
				events.append({"type": "revive", "hero": h["hero"].id})
	if not lead()["alive"]:
		over = true
		events.append({"type": "over"})


func _move_heroes(dt: float, move_dir: Vector2) -> void:
	var ld: Dictionary = lead()
	var spd := LEAD_SPEED * clampf(Combat.spd_of(ld["hero"]) / 10.0, 0.8, 1.4) * (1.0 + 0.12 * _stat("speed"))
	if move_dir.length() > 0.01:
		ld["pos"] += move_dir.normalized() * spd * dt
		ld["facing"] = signf(move_dir.x) if absf(move_dir.x) > 0.1 else ld["facing"]
		ld["moving"] = true
	else:
		ld["moving"] = false
	# Companions trail the lead in a loose arc.
	var n := 0
	for h in heroes:
		if h["lead"] or not h["alive"]:
			continue
		var ang := PI + (n - 1) * 0.9
		var slot: Vector2 = ld["pos"] + Vector2(cos(ang) * -ld["facing"], sin(ang)) * 60.0
		var to: Vector2 = slot - h["pos"]
		h["moving"] = to.length() > 8.0
		if h["moving"]:
			h["pos"] += to.normalized() * minf(to.length(), spd * 1.15 * dt)
			if absf(to.x) > 2.0:
				h["facing"] = signf(to.x)
		n += 1


func _spawn(dt: float) -> void:
	var m := minutes()
	_spawn_acc += dt * (1.2 + 1.1 * m)
	var alive := foes.size()
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if alive < MAX_FOES:
			_add_foe("combat")
			alive += 1
	if time >= _next_elite:
		_next_elite += ELITE_EVERY
		_add_foe("elite")
	if time >= _next_ring:
		_next_ring += RING_EVERY
		var n := 8 + int(3.0 * m)
		for k in n:
			if alive < MAX_FOES:
				_add_foe("combat", lead()["pos"] + Vector2.RIGHT.rotated(TAU * k / n) * 460.0)
				alive += 1
		events.append({"type": "ring"})
	if time >= _next_boss:
		_next_boss += BOSS_EVERY
		_add_foe("boss")
		events.append({"type": "boss", "name": foes.back()["name"]})


func _add_foe(tier: String, at: Vector2 = Vector2.INF) -> Dictionary:
	var b: Dictionary = GameData.BIOMES.get(biome, GameData.BIOMES["vale"])
	var name: String
	if tier == "boss":
		name = str(GameData.BOSS_NAMES[rng.randi() % GameData.BOSS_NAMES.size()])
	elif tier == "elite":
		name = str(b["elites"][rng.randi() % b["elites"].size()])
	else:
		name = str(b["monsters"][rng.randi() % b["monsters"].size()])
	var mult: float = {"combat": 1.0, "elite": 14.0, "boss": 90.0}[tier]
	var dmult: float = {"combat": 1.0, "elite": 2.0, "boss": 3.0}[tier]
	var hp: float = MON_HP0 * foe_hp_mult() * mult * rng.randf_range(0.85, 1.15)
	if at == Vector2.INF:
		at = lead()["pos"] + Vector2.RIGHT.rotated(rng.randf() * TAU) * ARENA_SPAWN_R
	_next_id += 1
	var f := {"id": _next_id, "name": name, "tier": tier, "pos": at, "hp": hp, "max_hp": hp,
		"dmg": MON_DMG0 * foe_dmg_mult() * dmult, "speed": float({"combat": rng.randf_range(48.0, 72.0), "elite": 52.0, "boss": 40.0}[tier]) * (1.0 + 0.05 * minutes()),
		"r": {"combat": 16.0, "elite": 26.0, "boss": 44.0}[tier], "hit_cd": 0.0,
		"xp": {"combat": 1, "elite": 12, "boss": 60}[tier], "phased": false, "facing": -1.0, "flash": 0.0}
	foes.append(f)
	return f


func _nearest_hero(p: Vector2) -> Dictionary:
	var best := {}
	var bd := INF
	for h in heroes:
		if h["alive"]:
			var d: float = p.distance_squared_to(h["pos"])
			if d < bd:
				bd = d
				best = h
	return best


func _move_foes(dt: float) -> void:
	# Spatial hash for separation, so crowds spread instead of stacking.
	var grid := {}
	for i in foes.size():
		var c := Vector2i(floori(foes[i]["pos"].x / GRID), floori(foes[i]["pos"].y / GRID))
		grid.get_or_add(c, []).append(i)
	var lp: Vector2 = lead()["pos"]
	for i in foes.size():
		var f: Dictionary = foes[i]
		f["flash"] = maxf(0.0, f["flash"] - dt)
		var t := _nearest_hero(f["pos"])
		if t.is_empty():
			continue
		var dir: Vector2 = (t["pos"] - f["pos"]).normalized()
		var push := Vector2.ZERO
		var c := Vector2i(floori(f["pos"].x / GRID), floori(f["pos"].y / GRID))
		for ox in [-1, 0, 1]:
			for oy in [-1, 0, 1]:
				for j in grid.get(c + Vector2i(ox, oy), []):
					if j == i:
						continue
					var d: Vector2 = f["pos"] - foes[j]["pos"]
					var min_d: float = f["r"] + foes[j]["r"]
					var l := d.length()
					if l < min_d and l > 0.01:
						push += d / l * (min_d - l)
		f["pos"] += dir * f["speed"] * dt + push * 0.5
		if absf(dir.x) > 0.2:
			f["facing"] = signf(dir.x)
		# Stragglers far behind are pulled back in front of the party.
		if f["tier"] == "combat" and f["pos"].distance_squared_to(lp) > 1400.0 * 1400.0:
			f["pos"] = lp + (lp - f["pos"]).normalized() * ARENA_SPAWN_R


func _nearest_foe(p: Vector2, reach: float) -> int:
	var best := -1
	var bd := reach * reach
	for i in foes.size():
		var d: float = p.distance_squared_to(foes[i]["pos"])
		if d < bd:
			bd = d
			best = i
	return best


func _hero_dmg(h: Dictionary, mult: float) -> float:
	return float(Combat.dmg_of(h["hero"])) * mult * dmg_mult() * rng.randf_range(0.9, 1.1)


func _attacks(dt: float) -> void:
	var cd_mult := pow(0.9, _stat("haste"))
	var area := 1.0 + 0.2 * _stat("area")
	for h in heroes:
		if not h["alive"]:
			continue
		var w: Dictionary = WEAPONS.get(h["role"], WEAPONS["warrior"])
		h["cd"] -= dt
		if h["cd"] <= 0.0:
			if _fire(h, w, area, 1.0):
				h["cd"] = float(w["cd"]) * cd_mult
			else:
				h["cd"] = 0.15   # nothing in reach, check again soon
		if h["has_ability"]:
			h["ab_cd"] -= dt
			if h["ab_cd"] <= 0.0 and _nearest_foe(h["pos"], 400.0) >= 0:
				h["ab_cd"] = ABILITY_CD * pow(0.8, _stat("focus"))
				_ability(h, w, area)
		if w["kind"] == "pulse":
			h["heal_cd"] = float(h.get("heal_cd", 4.0)) - dt
			if h["heal_cd"] <= 0.0:
				h["heal_cd"] = 4.0
				_heal_lowest(0.08)


## One auto-attack; false if nothing was in reach.
func _fire(h: Dictionary, w: Dictionary, area: float, power: float) -> bool:
	var reach := float(w["range"]) * (area if w["kind"] in ["arc", "pulse"] else 1.0)
	var t := _nearest_foe(h["pos"], reach)
	if t < 0:
		return false
	var dmg := _hero_dmg(h, float(w["mult"]) * power)
	var tpos: Vector2 = foes[t]["pos"]
	match w["kind"]:
		"arc", "pulse":
			events.append({"type": w["kind"], "pos": h["pos"], "r": reach, "role": h["role"]})
			_hit_area(h["pos"], reach, dmg)
		"stab":
			events.append({"type": "stab", "from": h["pos"], "to": tpos})
			_damage(t, dmg)
		"shot", "bolt":
			var n := 1 + _stat("multishot")
			var base_dir: Vector2 = (tpos - h["pos"]).normalized()
			for k in n:
				var dir := base_dir.rotated((k - (n - 1) * 0.5) * 0.18)
				shots.append({"pos": h["pos"], "vel": dir * (520.0 if w["kind"] == "shot" else 380.0), "dmg": dmg, "r": 10.0,
					"life": 1.0, "pierce": int(w.get("pierce", 0)), "burst": float(w.get("burst", 0.0)) * area, "hit": [], "kind": w["kind"]})
	if h["pos"].x != tpos.x and not (h["lead"] and h.get("moving", false)):
		h["facing"] = signf(tpos.x - h["pos"].x)
	return true


func _ability(h: Dictionary, w: Dictionary, area: float) -> void:
	events.append({"type": "ability", "pos": h["pos"], "role": h["role"]})
	match w["kind"]:
		"arc":
			_hit_area(h["pos"], 170.0 * area, _hero_dmg(h, 3.0))
			events.append({"type": "shockwave", "pos": h["pos"], "r": 170.0 * area})
		"stab":
			for k in 6:
				var t := _nearest_foe(h["pos"], 160.0)
				if t < 0:
					break
				events.append({"type": "stab", "from": h["pos"], "to": foes[t]["pos"]})
				_damage(t, _hero_dmg(h, 1.6))
		"shot":
			for k in 12:
				shots.append({"pos": h["pos"], "vel": Vector2.RIGHT.rotated(TAU * k / 12.0) * 520.0, "dmg": _hero_dmg(h, 1.4), "r": 10.0,
					"life": 1.0, "pierce": 2, "burst": 0.0, "hit": [], "kind": "shot"})
		"bolt":
			var t := _densest_point(h["pos"], 320.0)
			_hit_area(t, 120.0 * area, _hero_dmg(h, 3.5))
			events.append({"type": "meteor", "pos": t, "r": 120.0 * area})
		"pulse":
			_heal_all(0.25)
			_hit_area(h["pos"], 200.0 * area, _hero_dmg(h, 1.8))
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 200.0 * area})


func _densest_point(p: Vector2, reach: float) -> Vector2:
	var best := p
	var best_n := -1
	for i in mini(foes.size(), 40):
		var f: Dictionary = foes[rng.randi() % foes.size()]
		if f["pos"].distance_to(p) > reach:
			continue
		var n := 0
		for g in foes:
			if g["pos"].distance_squared_to(f["pos"]) < 110.0 * 110.0:
				n += 1
		if n > best_n:
			best_n = n
			best = f["pos"]
	return best


func _hit_area(center: Vector2, r: float, dmg: float) -> void:
	for i in range(foes.size() - 1, -1, -1):
		if foes[i]["pos"].distance_squared_to(center) <= (r + foes[i]["r"]) * (r + foes[i]["r"]):
			_damage(i, dmg)


func _damage(i: int, dmg: float) -> void:
	var f: Dictionary = foes[i]
	f["hp"] -= dmg
	f["flash"] = 0.12
	if f["tier"] == "boss" and not f["phased"] and f["hp"] <= f["max_hp"] * 0.5 and f["hp"] > 0.0:
		f["phased"] = true
		events.append({"type": "phase", "name": f["name"]})
		for k in 10:
			_add_foe("combat", f["pos"] + Vector2.RIGHT.rotated(TAU * k / 10.0) * 120.0)
	if f["hp"] > 0.0:
		return
	kills += 1
	var base_name := str(f["name"])
	kill_counts[base_name] = int(kill_counts.get(base_name, 0)) + 1
	if f["tier"] == "elite":
		elites_killed += 1
	elif f["tier"] == "boss":
		bosses_killed += 1
	events.append({"type": "kill", "pos": f["pos"], "tier": f["tier"], "name": f["name"]})
	gems.append({"pos": f["pos"], "xp": int(f["xp"])})
	if gems.size() > MAX_GEMS:
		var old: Dictionary = gems.pop_front()
		gems[0]["xp"] = int(gems[0]["xp"]) + int(old["xp"])
	foes.remove_at(i)


func _move_shots(dt: float) -> void:
	for s in range(shots.size() - 1, -1, -1):
		var sh: Dictionary = shots[s]
		sh["pos"] += sh["vel"] * dt
		sh["life"] -= dt
		var done: bool = sh["life"] <= 0.0
		if not done:
			for i in range(foes.size() - 1, -1, -1):
				var f: Dictionary = foes[i]
				if sh["hit"].has(f["id"]):
					continue
				if sh["pos"].distance_squared_to(f["pos"]) <= (sh["r"] + f["r"]) * (sh["r"] + f["r"]):
					if sh["burst"] > 0.0:
						events.append({"type": "burst", "pos": sh["pos"], "r": sh["burst"]})
						_hit_area(sh["pos"], sh["burst"], sh["dmg"])
						done = true
						break
					sh["hit"].append(f["id"])
					_damage(i, sh["dmg"])
					if sh["pierce"] <= 0:
						done = true
						break
					sh["pierce"] -= 1
		if done:
			shots.remove_at(s)


func _contact(dt: float) -> void:
	var guard := pow(0.88, _stat("armor"))
	for i in range(foes.size() - 1, -1, -1):
		if i >= foes.size():
			continue
		var f: Dictionary = foes[i]
		f["hit_cd"] -= dt
		if f["hit_cd"] > 0.0:
			continue
		for h in heroes:
			if not h["alive"]:
				continue
			if f["pos"].distance_squared_to(h["pos"]) <= (f["r"] + HERO_R + 4.0) * (f["r"] + HERO_R + 4.0):
				f["hit_cd"] = CONTACT_CD
				h["hp"] -= f["dmg"] * guard
				events.append({"type": "hurt", "hero": h["hero"].id, "dmg": f["dmg"] * guard})
				if _stat("thorns") > 0:
					_damage(i, float(Combat.dmg_of(h["hero"])) * 0.4 * _stat("thorns") * dmg_mult())
				if h["hp"] <= 0.0:
					h["hp"] = 0.0
					h["alive"] = false
					events.append({"type": "down", "hero": h["hero"].id})
				break


func _pickups(dt: float) -> void:
	var lp: Vector2 = lead()["pos"]
	var reach := PICKUP_R * (1.0 + 0.5 * _stat("magnet"))
	for g in range(gems.size() - 1, -1, -1):
		var gem: Dictionary = gems[g]
		var d: float = gem["pos"].distance_to(lp)
		if not gem.get("pulled", false):
			for h in heroes:
				if h["alive"] and gem["pos"].distance_squared_to(h["pos"]) < reach * reach:
					gem["pulled"] = true
					break
		if gem.get("pulled", false):
			gem["pos"] = gem["pos"].move_toward(lp, 480.0 * dt)
			if d < 16.0:
				xp += int(gem["xp"])
				gems.remove_at(g)
	while xp >= xp_next():
		xp -= xp_next()
		level += 1
		pending_levels += 1
		events.append({"type": "level"})


func _heal_lowest(frac: float) -> void:
	var low := {}
	for h in heroes:
		if h["alive"] and (low.is_empty() or h["hp"] / h["max_hp"] < low["hp"] / low["max_hp"]):
			low = h
	if not low.is_empty() and low["hp"] < low["max_hp"]:
		low["hp"] = minf(low["max_hp"], low["hp"] + low["max_hp"] * frac)
		events.append({"type": "heal", "hero": low["hero"].id})


func _heal_all(frac: float) -> void:
	for h in heroes:
		if h["alive"]:
			h["hp"] = minf(h["max_hp"], h["hp"] + h["max_hp"] * frac)
			events.append({"type": "heal", "hero": h["hero"].id})


# ---------------- Level-ups ----------------

## Three upgrade ids that aren't maxed yet.
func offer() -> Array:
	var pool: Array = UPGRADES.keys().filter(func(id): return _stat(id) < int(UPGRADES[id]["max"]))
	var out: Array = []
	while out.size() < 3 and not pool.is_empty():
		out.append(pool.pop_at(rng.randi() % pool.size()))
	return out


func pick(id: String) -> void:
	if pending_levels <= 0:
		return
	pending_levels -= 1
	if id == "":
		return
	upgrades[id] = _stat(id) + 1
	if id == "vigor":
		for h in heroes:
			h["max_hp"] *= 1.2
			if h["alive"]:
				h["hp"] = minf(h["max_hp"], h["hp"] + h["max_hp"] * 0.3)


## Auto-pilot for tests and the balance sim, playing like a careful player:
## step away from foes that get close, otherwise go and collect shards.
func autopilot_dir() -> Vector2:
	var lp: Vector2 = lead()["pos"]
	var away := Vector2.ZERO
	var close := false
	for f in foes:
		var d: Vector2 = lp - f["pos"]
		var l2 := d.length_squared()
		if l2 < 110.0 * 110.0:
			away += d / maxf(l2, 1.0) * (4.0 if f["tier"] != "combat" else 1.0)
			close = true
	if close:
		return away.normalized()
	var best := Vector2.INF
	for g in gems:
		if g["pos"].distance_squared_to(lp) < best.distance_squared_to(lp):
			best = g["pos"]
	if best != Vector2.INF:
		return (best - lp).normalized()
	return Vector2.RIGHT.rotated(time * 0.3)


# ---------------- Rewards ----------------

## What the guild earns for this run (time survived and kills).
func rewards() -> Dictionary:
	var m := minutes()
	return {"coins": int(round(45.0 * m + 0.15 * kills)), "crystals": int(round(7.0 * m + 3.0 * elites_killed + 20.0 * bosses_killed)),
		"xp": int(round(12.0 * m)), "loot": elites_killed / 4 + bosses_killed}
