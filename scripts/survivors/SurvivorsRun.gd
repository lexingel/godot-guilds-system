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
## Every 8s a hero with an Ability unleashes it: its subclass Ability's
## effect picks the style (ABILITY_STYLE); without one, a bigger version of
## the role's attack.
const ABILITY_CD := 8.0
const ABILITY_STYLE := {
	"burst_lowest": "strike", "self_sac_burst": "strike", "hp_drain_burst": "strike",
	"cleave_burst": "nova", "execute_all_low": "nova", "ward_break": "nova",
	"mend_burst": "mend", "mend_shield_hybrid": "mend", "shield_lowest": "mend", "cleanse_heal": "mend",
	"monster_dmg_mult": "slow", "debuff_lowest": "slow",
	"team_dmg_mult": "rally", "escalate_surge": "rally", "counter_surge": "rally", "wipe_guard_surge": "rally", "reset_cooldowns": "rally",
	# Signature effects keep their identity in the Endless Rift.
	"riposte": "riposte", "revive": "revive", "trap": "trap", "freeze_target": "freeze", "stun_strike": "stun",
	"burn_all": "burn", "chain_lightning": "chain", "mark_target": "mark", "armor_break": "mark",
	"execute_threshold": "execute", "execute_burst": "execute", "lifesteal_surge": "lifesteal",
	"undying": "undying", "taunt_ward": "undying", "shield_wall_front": "wall", "team_shield_burst": "wall",
	"evasion_round": "evasion", "dodge_surge": "evasion", "blood_price": "blood", "double_strike": "double",
}
## Role skills learned at level-up become auto-moves on their own timer.
const SKILL_MOVES := {
	"shield_bash": {"cd": 5.0, "desc": "Every 5s: shoves foes around the hero, stunning them"},
	"taunt": {"cd": 10.0, "desc": "Every 10s: draws every foe to this hero for 3s, taking 40% less"},
	"aimed_shot": {"cd": 3.0, "desc": "Every 3s: a piercing shot at the toughest foe in sight"},
	"volley": {"cd": 4.0, "desc": "Every 4s: a ring of arrows"},
	"arcane_bolt": {"cd": 2.5, "desc": "Every 2.5s: a bursting bolt at the toughest foe near"},
	"frost_nova": {"cd": 7.0, "desc": "Every 7s: freezes every foe close by"},
	"heal": {"cd": 6.0, "desc": "Every 6s: heals the most-hurt hero 20%"},
	"sanctuary": {"cd": 12.0, "desc": "Every 12s: heals the whole party 12%"},
	"backstab": {"cd": 3.0, "desc": "Every 3s: a heavy stab, heavier on a wounded foe"},
	"smoke_bomb": {"cd": 10.0, "desc": "Every 10s: +40% dodge for the party for 3s"},
}
const ABILITY_RANK_MAX := 3
const ABILITY_RANK_CD := 0.8      # cooldown multiplier per rank
const ABILITY_RANK_POWER := 0.3   # extra power per rank
const TWIST_TEXT := {
	"guardian": "also heals the party 8%", "sustain": "also heals this hero 25%",
	"evasion": "and the party dodges more for 2s", "attrition": "and slows foes around the hero",
	"opener": "fires twice", "executioner": "hits 50% harder",
}
const RALLY_MULT := 1.25
const RALLY_TIME := 4.0
const SLOW_TIME := 4.0

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
# The guild's build, read once at the start (see _init): party dodge and
# mending from skills, items and relics, relic damage and wards.
var dodge := 0.0
var mend := 0.0
var rally_t := 0.0
var dodge_t := 0.0   # a Smoke Bomb or an evasion twist: extra dodge while > 0
var wall_t := 0.0    # a shield wall: the party takes half damage while > 0
var regen_t := 0.0   # lifesteal: the party regains 3% HP a second while > 0
var traps: Array = []   # {pos, r, dmg, life}: the first foe to step in springs it


func _init(party: Array, biome_id: String = "vale", seed_val: int = 0) -> void:
	rng.seed = seed_val if seed_val != 0 else randi()
	biome = biome_id
	var typed: Array[Hero] = []
	typed.assign(party)
	dodge = clampf(Combat.party_skill_total(typed, "dodge_pct") + Combat.relic_special_total("dodge_pct"), 0.0, 0.2)
	mend = clampf(Combat.party_skill_total(typed, "mend_pct") + Combat.relic_special_total("mend_pct"), 0.0, 0.4)
	var ward := 0.0
	for r in Combat.equipped_relics():
		ward += r.hp
	var n: float = maxf(1.0, party.size())
	for i in party.size():
		var h: Hero = party[i]
		var mhp := float(Combat.max_hp(h)) + ward / n
		var ab: Dictionary = GameData.SUBCLASS_ABILITIES.get(h.pool_id, {}) if Combat.qualifies_for_ability(h) else {}
		heroes.append({"hero": h, "role": GameData.hero_role(h), "pos": Vector2(-40.0 * i, 30.0 * (i % 2)), "hp": mhp, "max_hp": mhp,
			"alive": true, "lead": i == 0, "cd": rng.randf() * 0.5, "ab_cd": ABILITY_CD * 0.5, "facing": 1.0,
			"has_ability": not ab.is_empty(), "ability_name": str(ab.get("name", "")), "style": str(ABILITY_STYLE.get(str(ab.get("effect", "")), "")),
			"bonus_dmg": float(Combat.relic_dmg_bonus()) / n, "haste": 1.0 + 0.5 * maxf(0.0, Combat.hero_skill_total(h, "speed_pct")),
			"skills": {}, "ab_rank": 0, "arch": Combat.hero_main_arch(h), "taunt_t": 0.0})


func lead() -> Dictionary:
	return heroes[0]


func xp_next() -> int:
	return 5 + 4 * (level - 1) + int(pow(level - 1, 1.5))


func minutes() -> float:
	return time / 60.0


func _stat(id: String) -> int:
	return int(upgrades.get(id, 0))


func dmg_mult() -> float:
	return (1.0 + 0.15 * _stat("might")) * (RALLY_MULT if rally_t > 0.0 else 1.0)


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
	rally_t = maxf(0.0, rally_t - dt)
	dodge_t = maxf(0.0, dodge_t - dt)
	wall_t = maxf(0.0, wall_t - dt)
	regen_t = maxf(0.0, regen_t - dt)
	_tick_statuses(dt)
	# Mending: a round's worth (see Combat) spread over ~10 seconds.
	var regen := 0.01 * _stat("regen") + mend * 0.1 + (0.03 if regen_t > 0.0 else 0.0)
	if regen > 0.0:
		for h in heroes:
			if h["alive"]:
				h["hp"] = minf(h["max_hp"], h["hp"] + h["max_hp"] * regen * dt)
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
	for h in heroes:
		if h["alive"] and float(h.get("taunt_t", 0.0)) > 0.0 and p.distance_squared_to(h["pos"]) <= 500.0 * 500.0:
			return h
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
		f["stun_t"] = maxf(0.0, float(f.get("stun_t", 0.0)) - dt)
		var slow := 0.0 if float(f["stun_t"]) > 0.0 else (0.4 if float(f.get("slow_t", 0.0)) > 0.0 else 1.0)
		f["slow_t"] = maxf(0.0, float(f.get("slow_t", 0.0)) - dt)
		f["pos"] += dir * f["speed"] * slow * dt + push * 0.5
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
	return (float(Combat.dmg_of(h["hero"])) + float(h.get("bonus_dmg", 0.0))) * mult * dmg_mult() * rng.randf_range(0.9, 1.1)


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
				h["cd"] = float(w["cd"]) * cd_mult / float(h.get("haste", 1.0))
			else:
				h["cd"] = 0.15   # nothing in reach, check again soon
		if h["has_ability"]:
			h["ab_cd"] -= dt
			if h["ab_cd"] <= 0.0 and _nearest_foe(h["pos"], 400.0) >= 0:
				h["ab_cd"] = ABILITY_CD * pow(0.8, _stat("focus")) * pow(ABILITY_RANK_CD, int(h["ab_rank"]))
				_ability(h, w, area)
				if int(h["ab_rank"]) >= ABILITY_RANK_MAX:
					_twist(h, w, area)
		for tk in ["taunt_t", "riposte_t", "undying_t"]:
			h[tk] = maxf(0.0, float(h.get(tk, 0.0)) - dt)
		var skills: Dictionary = h["skills"]
		for sid in skills:
			skills[sid] = float(skills[sid]) - dt
			if float(skills[sid]) <= 0.0:
				skills[sid] = float(SKILL_MOVES[sid]["cd"]) * cd_mult if _skill_move(h, str(sid), area) else 0.3
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


## A hero's Ability at rank 3 adds their archetype's twist (TWIST_TEXT).
func _twist(h: Dictionary, w: Dictionary, area: float) -> void:
	match str(h.get("arch", "")):
		"guardian":
			_heal_all(0.08)
		"sustain":
			h["hp"] = minf(h["max_hp"], h["hp"] + h["max_hp"] * 0.25)
		"evasion":
			dodge_t = maxf(dodge_t, 2.0)
		"attrition":
			for f in foes:
				if f["pos"].distance_squared_to(h["pos"]) <= 260.0 * 260.0:
					f["slow_t"] = SLOW_TIME
		"opener":
			_ability(h, w, area)


## The power an Ability hits with: its ranks, and an executioner's rank-3 twist.
func _ability_power(h: Dictionary) -> float:
	var p := 1.0 + ABILITY_RANK_POWER * int(h.get("ab_rank", 0))
	if int(h.get("ab_rank", 0)) >= ABILITY_RANK_MAX and str(h.get("arch", "")) == "executioner":
		p *= 1.5
	return p


## A learned role skill's auto-move; false if it had nothing to hit.
func _skill_move(h: Dictionary, id: String, area: float) -> bool:
	match id:
		"shield_bash", "frost_nova":
			var r := (100.0 if id == "shield_bash" else 170.0) * area
			var hit := false
			for i in range(foes.size() - 1, -1, -1):
				if i < foes.size() and foes[i]["pos"].distance_squared_to(h["pos"]) <= r * r:
					foes[i]["stun_t"] = 1.2 if id == "shield_bash" else 2.0
					hit = true
					_damage(i, _hero_dmg(h, 1.5 if id == "shield_bash" else 1.0))
			if hit:
				events.append({"type": "shockwave", "pos": h["pos"], "r": r})
			return hit
		"taunt":
			if _nearest_foe(h["pos"], 300.0) < 0:
				return false
			h["taunt_t"] = 3.0
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 80.0})
			return true
		"aimed_shot", "arcane_bolt", "backstab":
			var reach: float = {"aimed_shot": 600.0, "arcane_bolt": 400.0, "backstab": 130.0}[id]
			var best := -1
			for i in foes.size():
				if foes[i]["pos"].distance_squared_to(h["pos"]) <= reach * reach and (best < 0 or float(foes[i]["hp"]) > float(foes[best]["hp"])):
					best = i
			if best < 0:
				return false
			var tpos: Vector2 = foes[best]["pos"]
			if id == "backstab":
				var mult := 3.0 * (1.7 if float(foes[best]["hp"]) < float(foes[best]["max_hp"]) * 0.5 else 1.0)
				events.append({"type": "stab", "from": h["pos"], "to": tpos})
				_damage(best, _hero_dmg(h, mult))
			else:
				var dir: Vector2 = (tpos - h["pos"]).normalized()
				shots.append({"pos": h["pos"], "vel": dir * (700.0 if id == "aimed_shot" else 420.0), "dmg": _hero_dmg(h, 4.0 if id == "aimed_shot" else 3.0), "r": 12.0,
					"life": 1.2, "pierce": 5 if id == "aimed_shot" else 0, "burst": 0.0 if id == "aimed_shot" else 70.0 * area, "hit": [], "kind": "shot" if id == "aimed_shot" else "bolt"})
			return true
		"volley":
			if _nearest_foe(h["pos"], 400.0) < 0:
				return false
			for k in 8:
				shots.append({"pos": h["pos"], "vel": Vector2.RIGHT.rotated(TAU * k / 8.0) * 520.0, "dmg": _hero_dmg(h, 1.2), "r": 10.0,
					"life": 1.0, "pierce": 1, "burst": 0.0, "hit": [], "kind": "shot"})
			return true
		"heal":
			_heal_lowest(0.2)
			return true
		"sanctuary":
			_heal_all(0.12)
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 140.0})
			return true
		"smoke_bomb":
			dodge_t = maxf(dodge_t, 3.0)
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 110.0})
			return true
	return false


func _ability(h: Dictionary, w: Dictionary, area: float) -> void:
	events.append({"type": "ability", "pos": h["pos"], "role": h["role"], "name": str(h.get("ability_name", ""))})
	var pw := _ability_power(h)
	match str(h.get("style", "")):
		"riposte":
			h["riposte_t"] = 6.0
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 70.0})
			return
		"revive":
			for o in heroes:
				if not o["alive"]:
					o["alive"] = true
					o["down_t"] = 0.0
					o["hp"] = o["max_hp"] * 0.5 * pw
					o["pos"] = h["pos"]
					events.append({"type": "revive", "hero": o["hero"].id})
					return
			_heal_lowest(0.25 * pw)
			return
		"trap":
			traps.append({"pos": _densest_point(h["pos"], 300.0), "r": 90.0 * area, "dmg": _hero_dmg(h, 5.0 * pw), "life": 10.0})
			events.append({"type": "pulse", "pos": traps[-1]["pos"], "r": 90.0 * area, "role": h["role"]})
			return
		"freeze", "stun":
			var fr := (220.0 if str(h["style"]) == "freeze" else 140.0) * area
			for i in range(foes.size() - 1, -1, -1):
				if i < foes.size() and foes[i]["pos"].distance_squared_to(h["pos"]) <= fr * fr:
					foes[i]["stun_t"] = 2.5
					if str(h["style"]) == "stun":
						_damage(i, _hero_dmg(h, 2.5 * pw))
			events.append({"type": "shockwave", "pos": h["pos"], "r": fr})
			return
		"burn":
			for f in foes:
				if f["pos"].distance_squared_to(h["pos"]) <= 260.0 * 260.0 * area * area:
					f["burn_t"] = 4.0
					f["burn_dps"] = maxf(float(f.get("burn_dps", 0.0)), _hero_dmg(h, 0.8 * pw))
			events.append({"type": "meteor", "pos": h["pos"], "r": 200.0 * area})
			return
		"chain":
			for k in 5:
				var near: Array = []
				for i in foes.size():
					if foes[i]["pos"].distance_squared_to(h["pos"]) <= 350.0 * 350.0:
						near.append(i)
				if near.is_empty():
					break
				var ci: int = near[rng.randi() % near.size()]
				events.append({"type": "stab", "from": h["pos"], "to": foes[ci]["pos"]})
				_damage(ci, _hero_dmg(h, 2.0 * pw))
			return
		"mark":
			for f in foes:
				if f["pos"].distance_squared_to(h["pos"]) <= 250.0 * 250.0:
					f["marked_t"] = 6.0
			events.append({"type": "pulse", "pos": h["pos"], "r": 250.0, "role": h["role"]})
			return
		"execute":
			for i in range(foes.size() - 1, -1, -1):
				if i < foes.size() and str(foes[i]["tier"]) != "boss" and foes[i]["pos"].distance_squared_to(h["pos"]) <= 250.0 * 250.0 and float(foes[i]["hp"]) <= float(foes[i]["max_hp"]) * 0.35:
					_damage(i, float(foes[i]["hp"]) + 1.0)
			var best_x := _nearest_foe(h["pos"], 300.0)
			if best_x >= 0:
				events.append({"type": "meteor", "pos": foes[best_x]["pos"], "r": 60.0})
				_damage(best_x, _hero_dmg(h, 3.0 * pw))
			return
		"lifesteal":
			regen_t = 6.0
			rally_t = maxf(rally_t, 3.0)
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 120.0})
			return
		"undying":
			h["undying_t"] = 3.0
			if h["role"] == "warrior":
				h["taunt_t"] = 3.0
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 90.0})
			return
		"wall":
			wall_t = 4.0
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 160.0})
			return
		"evasion":
			dodge_t = maxf(dodge_t, 3.0)
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 110.0})
			return
		"blood":
			h["hp"] = maxf(1.0, h["hp"] - h["max_hp"] * 0.15)
			rally_t = RALLY_TIME * 1.5
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 120.0})
			return
		"double":
			for k in 2:
				var t2 := _nearest_foe(h["pos"], 300.0)
				if t2 < 0:
					break
				events.append({"type": "stab", "from": h["pos"], "to": foes[t2]["pos"]})
				_damage(t2, _hero_dmg(h, 2.5 * pw))
			return
	match str(h.get("style", "")):
		"strike":
			var best := -1
			for i in foes.size():
				if foes[i]["pos"].distance_squared_to(h["pos"]) <= 420.0 * 420.0 and (best < 0 or float(foes[i]["hp"]) > float(foes[best]["hp"])):
					best = i
			if best >= 0:
				var at: Vector2 = foes[best]["pos"]
				events.append({"type": "meteor", "pos": at, "r": 60.0})
				_damage(best, _hero_dmg(h, 4.0 * pw))
			return
		"nova":
			_hit_area(h["pos"], 200.0 * area, _hero_dmg(h, 2.5 * pw))
			events.append({"type": "shockwave", "pos": h["pos"], "r": 200.0 * area})
			return
		"mend":
			_heal_all(0.1 * pw)
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 160.0})
			return
		"slow":
			for f in foes:
				if f["pos"].distance_squared_to(h["pos"]) <= 260.0 * 260.0:
					f["slow_t"] = SLOW_TIME
			events.append({"type": "shockwave", "pos": h["pos"], "r": 260.0})
			return
		"rally":
			rally_t = RALLY_TIME
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 120.0})
			return
	match w["kind"]:
		"arc":
			_hit_area(h["pos"], 170.0 * area, _hero_dmg(h, 3.0 * pw))
			events.append({"type": "shockwave", "pos": h["pos"], "r": 170.0 * area})
		"stab":
			for k in 6:
				var t := _nearest_foe(h["pos"], 160.0)
				if t < 0:
					break
				events.append({"type": "stab", "from": h["pos"], "to": foes[t]["pos"]})
				_damage(t, _hero_dmg(h, 1.6 * pw))
		"shot":
			for k in 12:
				shots.append({"pos": h["pos"], "vel": Vector2.RIGHT.rotated(TAU * k / 12.0) * 520.0, "dmg": _hero_dmg(h, 1.4 * pw), "r": 10.0,
					"life": 1.0, "pierce": 2, "burst": 0.0, "hit": [], "kind": "shot"})
		"bolt":
			var t := _densest_point(h["pos"], 320.0)
			_hit_area(t, 120.0 * area, _hero_dmg(h, 3.5 * pw))
			events.append({"type": "meteor", "pos": t, "r": 120.0 * area})
		"pulse":
			_heal_all(0.25)
			_hit_area(h["pos"], 200.0 * area, _hero_dmg(h, 1.8 * pw))
			events.append({"type": "sanctuary", "pos": h["pos"], "r": 200.0 * area})


## Burning and marked foes, and traps waiting to be sprung.
func _tick_statuses(dt: float) -> void:
	for i in range(foes.size() - 1, -1, -1):
		if i >= foes.size():
			continue
		var f: Dictionary = foes[i]
		f["marked_t"] = maxf(0.0, float(f.get("marked_t", 0.0)) - dt)
		if float(f.get("burn_t", 0.0)) > 0.0:
			f["burn_t"] = float(f["burn_t"]) - dt
			_damage(i, float(f.get("burn_dps", 0.0)) * dt)
	for t in traps.duplicate():
		t["life"] = float(t["life"]) - dt
		var sprung := false
		for f in foes:
			if f["pos"].distance_squared_to(t["pos"]) <= float(t["r"]) * float(t["r"]):
				sprung = true
				break
		if sprung:
			events.append({"type": "meteor", "pos": t["pos"], "r": float(t["r"])})
			for i in range(foes.size() - 1, -1, -1):
				if i < foes.size() and foes[i]["pos"].distance_squared_to(t["pos"]) <= float(t["r"]) * float(t["r"]):
					foes[i]["stun_t"] = 1.5
					_damage(i, float(t["dmg"]))
		if sprung or float(t["life"]) <= 0.0:
			traps.erase(t)


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
	f["hp"] -= dmg * (1.3 if float(f.get("marked_t", 0.0)) > 0.0 else 1.0)
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
		if f["hit_cd"] > 0.0 or float(f.get("stun_t", 0.0)) > 0.0:
			continue
		for h in heroes:
			if not h["alive"]:
				continue
			if f["pos"].distance_squared_to(h["pos"]) <= (f["r"] + HERO_R + 4.0) * (f["r"] + HERO_R + 4.0):
				f["hit_cd"] = CONTACT_CD
				if rng.randf() < dodge + (0.4 if dodge_t > 0.0 else 0.0):
					events.append({"type": "dodge", "hero": h["hero"].id})
					break
				if float(h.get("undying_t", 0.0)) > 0.0:
					break
				h["hp"] -= f["dmg"] * guard * (0.6 if float(h.get("taunt_t", 0.0)) > 0.0 else 1.0) * (0.5 if wall_t > 0.0 else 1.0)
				if float(h.get("riposte_t", 0.0)) > 0.0 and i < foes.size() and foes[i] == f:
					_damage(i, _hero_dmg(h, 2.0))
					events.append({"type": "stab", "from": h["pos"], "to": f["pos"]})
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
	for i in heroes.size():
		var h: Dictionary = heroes[i]
		for sk in GameData.ROLE_SKILLS.get(h["hero"].cls_id, []):
			if not (h["skills"] as Dictionary).has(sk["id"]) and SKILL_MOVES.has(sk["id"]):
				pool.append("skill:%d:%s" % [i, sk["id"]])
		if h["has_ability"] and int(h["ab_rank"]) < ABILITY_RANK_MAX:
			pool.append("ability:%d" % i)
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
	var parts := id.split(":")
	if parts[0] == "skill":
		(heroes[int(parts[1])]["skills"] as Dictionary)[parts[2]] = 0.5
		return
	if parts[0] == "ability":
		heroes[int(parts[1])]["ab_rank"] = int(heroes[int(parts[1])]["ab_rank"]) + 1
		return
	upgrades[id] = _stat(id) + 1
	if id == "vigor":
		for h in heroes:
			h["max_hp"] *= 1.2
			if h["alive"]:
				h["hp"] = minf(h["max_hp"], h["hp"] + h["max_hp"] * 0.3)


## What a level-up pick is, for the offer screen: {name, desc, icon, have, max}.
func upgrade_info(id: String) -> Dictionary:
	var parts := id.split(":")
	if parts[0] == "skill":
		var h: Dictionary = heroes[int(parts[1])]
		var sk := GameData.find_role_skill(parts[2])
		return {"name": "%s: %s" % [h["hero"].name.split(" the ")[0], sk["name"]], "desc": str(SKILL_MOVES[parts[2]]["desc"]), "icon": str(sk["icon"]), "have": 0, "max": 1}
	if parts[0] == "ability":
		var h2: Dictionary = heroes[int(parts[1])]
		var r := int(h2["ab_rank"])
		var d := "Fires 20% sooner and hits 30% harder"
		if r + 1 >= ABILITY_RANK_MAX and TWIST_TEXT.has(str(h2["arch"])):
			d += "; %s twist: %s" % [GameData.ARCHETYPES[h2["arch"]], TWIST_TEXT[h2["arch"]]]
		return {"name": "%s: %s" % [h2["hero"].name.split(" the ")[0], h2["ability_name"]], "desc": d, "icon": GameData.ability_icon(h2["hero"].pool_id), "have": r, "max": ABILITY_RANK_MAX}
	var u: Dictionary = UPGRADES[id]
	return {"name": u["name"], "desc": u["desc"], "icon": u["icon"], "have": _stat(id), "max": int(u["max"])}


## Everything picked so far, for the pause screen.
func owned_lines() -> Array:
	var out: Array = upgrades.keys().map(func(id): return "%s ×%d" % [UPGRADES[id]["name"], upgrades[id]])
	for h in heroes:
		var who: String = h["hero"].name.split(" the ")[0]
		for sid in h["skills"]:
			out.append("%s: %s" % [who, GameData.find_role_skill(str(sid))["name"]])
		if int(h["ab_rank"]) > 0:
			out.append("%s: %s rank %d" % [who, h["ability_name"], int(h["ab_rank"])])
	return out


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
	return {"coins": int(round(45.0 * m + 0.05 * kills)), "crystals": int(round(7.0 * m + 3.0 * elites_killed + 20.0 * bosses_killed)),
		"xp": int(round(12.0 * m)), "loot": elites_killed / 4 + bosses_killed}
