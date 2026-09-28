class_name SurvivorsRun
extends RefCounted
## The Endless Rift: a survivors-style run. Pure simulation (no nodes) so it
## can be stepped headless — SurvivorsView draws it, tests and the balance sim
## drive it directly. Call step(dt, move_dir) every frame; read `events` for
## what to animate, `pending_levels` for level-up picks.

const ARENA_SPAWN_R := 820.0      # foes appear on a ring this far from the lead
const MAX_FOES := 260             # a hard cap for performance; the spawn budget stays under it
const MAX_GEMS := 120             # past this the oldest shards merge (no XP lost)
const HERO_R := 14.0
const CONTACT_CD := 0.6           # a foe touching a hero hits this often
const LEAD_SPEED := 120.0         # px/s at speed 10
const PICKUP_R := 100.0
const MON_HP0 := 30.0             # a regular foe at minute 0 (before scaling)
const MON_DMG0 := 3.2
const ELITE_EVERY := 60.0         # a lone elite at :30 of every minute (not in a pack or lull minute)
const RING_EVERY := 45.0          # a closing ring of foes surrounds the party
const BOSS_EVERY := 300.0
const FINAL_AT := 1200.0          # the Rift Warden: beat it and the rift is sealed (a win)
const FINAL_WARDEN := {"vale": "Vaelith", "marsh": "Nyxara", "ashen": "Sythrane"}
## How many foes may be out at once (elites count as ELITE_WEIGHT), before a
## wave's own budget multiplier. The rest of the difficulty is foe strength.
const BUDGET0 := 40.0
const BUDGET_PER_MIN := 11.0
const ELITE_WEIGHT := 6
## Every region runs the same five-minute cycle of waves; a warden closes each.
const WAVE_PLAN := ["horde", "swarm", "pack", "volley", "lull"]
const WAVES := {
	"horde": {"name": "The horde", "hint": "", "rate": 1.0, "budget": 1.0},
	"swarm": {"name": "A swarm", "hint": "Weak but many, and fast", "rate": 2.2, "budget": 1.6},
	"pack": {"name": "An elite pack", "hint": "Its leader carries a chest", "rate": 0.8, "budget": 0.8},
	"volley": {"name": "Archers and casters", "hint": "Step aside from their bolts", "rate": 1.0, "budget": 1.0},
	"lull": {"name": "A lull", "hint": "A chest lies nearby", "rate": 0.3, "budget": 0.4},
}
const SWARM_HP := 0.45
const RANGED_KEEP := 240.0        # ranged foes hold at this distance and shoot
const RANGED_CD := 3.2
const RANGED_SHARE := 0.35        # outside a ranged wave, this share of archers and casters shoot (the rest close in)
const MAX_BOLTS := 45
const BOLT_SPEED := 170.0
const BOLT_MULT := 0.5            # a bolt hits for this share of the foe's contact hit
const CHEST_R := 34.0
## Terrain: the arena is cut into CHUNK-sized squares, each with a few of its
## region's features (made from the run's seed, so they stay put) and maybe a
## brazier. Pillars block, pools slow, lava burns heroes and foes alike.
const CHUNK := 640.0
const TERRAIN_KIND := {"vale": "pillar", "marsh": "pool", "ashen": "lava"}
const POOL_SLOW := 0.55
const LAVA_HERO_PCT := 0.05       # of max HP per second
const BRAZIER_CHANCE := 0.6
const PICKUP_KINDS := ["heal", "heal", "magnet", "magnet", "bomb"]
## Elites and wardens telegraph a slam: a circle on the ground, then the blow.
const SLAM_WARN := 1.4
const SLAM_CD := {"elite": 6.0, "boss": 7.0}
const SLAM_R := {"elite": 85.0, "boss": 130.0}
const SLAM_MULT := 2.0
const GRID := 48.0
const _NEIGHBOUR_CELLS: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
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
## A role's auto-attack evolves once its matching upgrade is maxed: the pick
## is then always offered first.
const EVOLUTIONS := {
	"warrior": {"name": "Whirlwind", "needs": "area", "desc": "Warriors' sweeps reach 40% farther and strike twice", "icon": "res://assets/skills/sword_a.png"},
	"rogue": {"name": "Thousand Cuts", "needs": "haste", "desc": "Rogues' stabs hit the three nearest foes", "icon": "res://assets/skills/sword_dual.png"},
	"ranger": {"name": "Arrow Storm", "needs": "multishot", "desc": "Rangers' arrows pierce every foe in their path", "icon": "res://assets/skills/wing.png"},
	"mage": {"name": "Starfall", "needs": "focus", "desc": "Mages' bolts burst twice as wide and set foes alight", "icon": "res://assets/skills/gem_red.png"},
	"cleric": {"name": "Sanctum", "needs": "regen", "desc": "Clerics' pulses reach 40% farther and heal the party 3%", "icon": "res://assets/skills/heart.png"},
}
## Rift relics: found in chests (elite pack leaders, lulls), last for the run.
const RIFT_RELICS := {
	"fang": {"name": "Bloodfang", "desc": "Every kill heals the party 0.2%", "icon": "res://assets/skills/potion_red.png"},
	"idol": {"name": "Gilded Idol", "desc": "+40% gold from this run", "icon": "res://assets/skills/gem_blue_a.png"},
	"echo": {"name": "Echo Stone", "desc": "Every Ability fires twice", "icon": "res://assets/skills/eye_gem.png"},
	"phoenix": {"name": "Phoenix Feather", "desc": "The first time your lead falls, they rise at half health", "icon": "res://assets/skills/wing.png"},
	"storm": {"name": "Storm Crown", "desc": "Lightning strikes a foe near the party every 1.5s", "icon": "res://assets/skills/gem_red.png"},
	"lodestone": {"name": "Lodestone", "desc": "+60% pickup range, and every 30s every shard flies to you", "icon": "res://assets/skills/gem_blue_a.png"},
	"hourglass": {"name": "Sandglass", "desc": "Foes move 15% slower", "icon": "res://assets/skills/boots.png"},
	"ember": {"name": "Ember Heart", "desc": "Foes that strike a hero catch fire", "icon": "res://assets/skills/shield_orange.png"},
	"aegis": {"name": "Rift Aegis", "desc": "Every 20s the party takes half damage for 3s", "icon": "res://assets/skills/armor_chest.png"},
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
var pending_chests := 0     # chests walked over, waiting for a relic pick
var upgrades := {}          # id -> stacks
var evolved := {}           # role -> true
var relics := {}            # rift relic id -> true
var chests: Array = []      # {pos}: walk over one to open it
var foe_shots: Array = []   # {pos, vel, dmg, life}: ranged foes' bolts
var won := false            # the Rift Warden fell: the rift is sealed
var wave := "horde"
var bonus_coins := 0        # a chest opened with every relic already found
var terrain: Array = []     # features near the party: {id, pos, r, kind}
var braziers: Array = []    # standing braziers near the party: {id, pos}
var pickups: Array = []     # {pos, kind}: heal, magnet or bomb, from braziers
var slams: Array = []       # {pos, r, t, dmg}: a telegraphed blow landing when t runs out
var _chunks := {}           # Vector2i -> {features, brazier}
var _broken := {}           # brazier id -> true
var _terrain_t := 0.0
var _seed := 0
var _sep_half := 0   # which half of the crowd checks its neighbours this tick
var heroes: Array = []      # {hero, role, pos, hp, max_hp, alive, lead, cd, ab_cd, facing, has_ability}
var foes: Array = []        # {id, name, tier, pos, hp, max_hp, dmg, speed, r, hit_cd, xp, alive, phased}
var gems: Array = []        # {pos, xp}
var shots: Array = []       # {pos, vel, dmg, r, life, pierce, burst, hit}
var events: Array = []      # drained by the view each frame
var over := false
var _next_id := 0
var _spawn_acc := 0.0
var _next_elite := ELITE_EVERY * 0.5
var _next_ring := 120.0
var _next_boss := BOSS_EVERY
var _wave_min := -1
var _final_spawned := false
var _phoenix_used := false
var _storm_t := 1.5
var _lode_t := 30.0
var _aegis_t := 20.0
# The guild's build, read once at the start (see _init): party dodge and
# mending from skills, items and relics, relic damage and wards.
var dodge := 0.0
var mend := 0.0
var rally_t := 0.0
var dodge_t := 0.0   # a Smoke Bomb or an evasion twist: extra dodge while > 0
var wall_t := 0.0    # a shield wall: the party takes half damage while > 0
var regen_t := 0.0   # lifesteal: the party regains 3% HP a second while > 0
var traps: Array = []   # {pos, r, dmg, life}: the first foe to step in springs it
var lost: Array = []       # [[champion id, depth seconds]]: champions lost in this rift (set by the caller)
var beacon: Dictionary = {}   # {id, pos, held}: a lost champion's light; stand in it to free them
var rescued: Array = []    # champion ids freed this run
var threat := 1.0          # foe strength scale (GameState.endless_threat): gentle when the rift first opens


func _init(party: Array, biome_id: String = "vale", seed_val: int = 0) -> void:
	rng.seed = seed_val if seed_val != 0 else randi()
	_seed = int(rng.seed)
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
		# A champion's signature is their Call; a hero's, their subclass Ability.
		var ab: Dictionary = GameState.champion_call_of(h.id.trim_prefix("champ:")) if h.is_champion else (GameData.SUBCLASS_ABILITIES.get(h.pool_id, {}) if Combat.qualifies_for_ability(h) else {})
		heroes.append({"hero": h, "role": GameData.hero_role(h), "pos": Vector2(-40.0 * i, 30.0 * (i % 2)), "hp": mhp, "max_hp": mhp,
			"alive": true, "lead": i == 0, "cd": rng.randf() * 0.5, "ab_cd": ABILITY_CD * (0.5 + 0.2 * i), "facing": 1.0,
			"has_ability": not ab.is_empty(), "ability_name": str(ab.get("name", "")), "style": str(ABILITY_STYLE.get(str(ab.get("effect", "")), "")),
			"bonus_dmg": float(Combat.relic_dmg_bonus()) / n, "haste": 1.0 + 0.5 * maxf(0.0, Combat.hero_skill_total(h, "speed_pct")),
			"skills": {}, "ab_rank": 0, "arch": Combat.hero_main_arch(h), "taunt_t": 0.0,
			"ab_icon": str(GameData.ABILITY_EFFECT_ICON.get(str(ab.get("effect", "")), "res://assets/skills/sword_a.png"))})


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
	return (1.0 + 0.3 * m + 0.055 * m * m) * threat


func foe_dmg_mult() -> float:
	return (1.0 + 0.22 * minutes()) * threat


# ---------------- Step ----------------

func step(dt: float, move_dir: Vector2) -> void:
	if over or pending_levels > 0 or pending_chests > 0:
		return
	time += dt
	_move_heroes(dt, move_dir)
	_spawn(dt)
	_move_foes(dt)
	_terrain_effects(dt)
	_attacks(dt)
	_move_shots(dt)
	_move_foe_shots(dt)
	_contact(dt)
	_pickups(dt)
	_tick_relics(dt)
	_tick_slams(dt)
	_tick_beacon(dt)
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
	if not lead()["alive"] and relics.has("phoenix") and not _phoenix_used:
		_phoenix_used = true
		var ld: Dictionary = lead()
		ld["alive"] = true
		ld["hp"] = ld["max_hp"] * 0.5
		events.append({"type": "revive", "hero": ld["hero"].id})
	if not lead()["alive"]:
		over = true
		events.append({"type": "over"})


func _move_heroes(dt: float, move_dir: Vector2) -> void:
	var ld: Dictionary = lead()
	var spd := LEAD_SPEED * clampf(Combat.spd_of(ld["hero"]) / 10.0, 0.8, 1.4) * (1.0 + 0.12 * _stat("speed")) * (POOL_SLOW if _in_terrain(ld["pos"], "pool") else 1.0)
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


## The wave this minute of the run follows (WAVE_PLAN); after the Rift Warden
## arrives, the horde.
func wave_at(t: float) -> String:
	return "horde" if t >= FINAL_AT else str(WAVE_PLAN[int(t / 60.0) % WAVE_PLAN.size()])


## How many foes (elites weigh more) the rift keeps out at once right now.
func spawn_budget() -> float:
	return minf(MAX_FOES, (BUDGET0 + BUDGET_PER_MIN * minutes()) * float(WAVES[wave]["budget"]))


func _spawn(dt: float) -> void:
	var m := minutes()
	var minute := int(time / 60.0)
	if minute != _wave_min:
		_wave_min = minute
		wave = wave_at(time)
		_start_wave()
	var info: Dictionary = WAVES[wave]
	_spawn_acc += dt * (1.2 + 1.1 * m) * float(info["rate"])
	var crowd := 0
	for f in foes:
		crowd += ELITE_WEIGHT if f["tier"] == "elite" else (1 if f["tier"] == "combat" else 0)
	var budget := spawn_budget()
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		if crowd < budget and foes.size() < MAX_FOES:
			_add_foe("combat")
			crowd += 1
	if time >= _next_elite:
		_next_elite += ELITE_EVERY
		if not wave in ["pack", "lull"]:
			_add_foe("elite")
	if time >= _next_ring:
		_next_ring += RING_EVERY
		if wave != "lull":
			var n := 8 + int(3.0 * m)
			for k in n:
				if foes.size() < MAX_FOES:
					_add_foe("combat", lead()["pos"] + Vector2.RIGHT.rotated(TAU * k / n) * 460.0)
			events.append({"type": "ring"})
	if time >= _next_boss and _next_boss < FINAL_AT:
		_next_boss += BOSS_EVERY
		_add_foe("boss")
		events.append({"type": "boss", "name": foes.back()["name"]})
	if time >= FINAL_AT and not _final_spawned:
		_final_spawned = true
		var fw := _add_foe("boss")
		fw["name"] = str(FINAL_WARDEN.get(biome, "Sythrane"))
		fw["final"] = true
		fw["max_hp"] *= 1.6
		fw["hp"] = fw["max_hp"]
		fw["dmg"] *= 1.3
		events.append({"type": "boss", "name": fw["name"], "final": true})


## A new minute: its wave's opening (an elite pack, a lull's chest).
func _start_wave() -> void:
	events.append({"type": "wave", "wave": wave, "name": str(WAVES[wave]["name"]), "hint": str(WAVES[wave]["hint"])})
	var lp: Vector2 = lead()["pos"]
	match wave:
		"pack":
			var a := rng.randf() * TAU
			for k in (2 if time < BOSS_EVERY else 3):   # the first pack is a pair
				var e := _add_foe("elite", lp + Vector2.RIGHT.rotated(a + k * 0.35) * 620.0)
				if k == 1:
					e["chest"] = true
		"lull":
			chests.append({"pos": lp + Vector2.RIGHT.rotated(rng.randf() * TAU) * 280.0})


## What's coming, for the HUD timeline: [{label, in}] soonest first.
func upcoming() -> Array:
	var out: Array = []
	var next_min := (floorf(time / 60.0) + 1.0) * 60.0
	if next_min < FINAL_AT:
		out.append({"label": str(WAVES[wave_at(next_min)]["name"]), "in": next_min - time})
	if not _final_spawned:
		if _next_boss < FINAL_AT:
			out.append({"label": tr("Warden"), "in": _next_boss - time})
		else:
			out.append({"label": tr("Rift Warden"), "in": FINAL_AT - time})
	return out.filter(func(u): return float(u["in"]) > 0.0)


func _add_foe(tier: String, at: Vector2 = Vector2.INF) -> Dictionary:
	var b: Dictionary = GameData.BIOMES.get(biome, GameData.BIOMES["vale"])
	var name: String
	if tier == "boss":
		name = str(GameData.BOSS_NAMES[rng.randi() % GameData.BOSS_NAMES.size()])
	elif tier == "elite":
		name = str(b["elites"][rng.randi() % b["elites"].size()])
	else:
		name = str(b["monsters"][rng.randi() % b["monsters"].size()])
		# A ranged wave: mostly the region's archers and casters.
		if wave == "volley" and rng.randf() < 0.7:
			var ranged: Array = (b["monsters"] as Array).filter(func(n): return _is_ranged(str(n)))
			if not ranged.is_empty():
				name = str(ranged[rng.randi() % ranged.size()])
	var mult: float = {"combat": 1.0, "elite": 14.0, "boss": 90.0}[tier]
	if tier == "combat" and wave == "swarm":
		mult *= SWARM_HP
	var dmult: float = {"combat": 1.0, "elite": 2.0, "boss": 2.5}[tier]
	var hp: float = MON_HP0 * foe_hp_mult() * mult * rng.randf_range(0.85, 1.15)
	if at == Vector2.INF:
		at = lead()["pos"] + Vector2.RIGHT.rotated(rng.randf() * TAU) * ARENA_SPAWN_R
	_next_id += 1
	var f := {"id": _next_id, "name": name, "tier": tier, "pos": at, "hp": hp, "max_hp": hp,
		"dmg": MON_DMG0 * foe_dmg_mult() * dmult, "speed": float({"combat": rng.randf_range(48.0, 72.0), "elite": 52.0, "boss": 40.0}[tier]) * (1.0 + 0.05 * minutes()),
		"r": {"combat": 16.0, "elite": 26.0, "boss": 44.0}[tier], "hit_cd": 0.0,
		"xp": {"combat": 1, "elite": 12, "boss": 60}[tier], "phased": false, "facing": -1.0, "flash": 0.0,
		"ranged": tier == "combat" and _is_ranged(name) and (wave == "volley" or rng.randf() < RANGED_SHARE), "shot_cd": rng.randf_range(1.0, RANGED_CD)}
	if tier == "combat" and wave == "swarm":
		f["speed"] *= 1.15
	foes.append(f)
	return f


## The indices of up to n foes nearest to p within reach, nearest first.
func _nearest_foes(p: Vector2, reach: float, n: int) -> Array:
	var near: Array = []
	for i in foes.size():
		if foes[i]["pos"].distance_squared_to(p) <= reach * reach:
			near.append(i)
	near.sort_custom(func(a, b): return foes[a]["pos"].distance_squared_to(p) < foes[b]["pos"].distance_squared_to(p))
	return near.slice(0, n)


func _is_ranged(name: String) -> bool:
	return GameData.RANGED_FOE_WORDS.any(func(w): return name.contains(w))


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
	# Positions and radii are copied into packed arrays first (reading them
	# out of each foe's Dictionary in the inner loop was most of the cost),
	# and each tick only half the crowd checks its neighbours, pushing twice
	# as hard: the crowd spreads the same for half the work.
	var n := foes.size()
	var pos := PackedVector2Array()
	pos.resize(n)
	var rad := PackedFloat32Array()
	rad.resize(n)
	var grid := {}
	for i in n:
		var fp: Vector2 = foes[i]["pos"]
		pos[i] = fp
		rad[i] = foes[i]["r"]
		grid.get_or_add(Vector2i(floori(fp.x / GRID), floori(fp.y / GRID)), []).append(i)
	_sep_half = 1 - _sep_half
	var lp: Vector2 = lead()["pos"]
	for i in n:
		var f: Dictionary = foes[i]
		f["flash"] = maxf(0.0, f["flash"] - dt)
		var t := _nearest_hero(pos[i])
		if t.is_empty():
			continue
		var dir: Vector2 = (t["pos"] - pos[i]).normalized()
		var push := Vector2.ZERO
		if i % 2 == _sep_half:
			var p := pos[i]
			var c := Vector2i(floori(p.x / GRID), floori(p.y / GRID))
			for o in _NEIGHBOUR_CELLS:
				var cell = grid.get(c + o)
				if cell == null:
					continue
				for j in cell:
					if j == i:
						continue
					var d: Vector2 = p - pos[j]
					var min_d: float = rad[i] + rad[j]
					var l2 := d.length_squared()
					if l2 < min_d * min_d and l2 > 0.0001:
						var l := sqrt(l2)
						push += d / l * (min_d - l)
		f["stun_t"] = maxf(0.0, float(f.get("stun_t", 0.0)) - dt)
		var slow := 0.0 if float(f["stun_t"]) > 0.0 else (0.4 if float(f.get("slow_t", 0.0)) > 0.0 else 1.0)
		f["slow_t"] = maxf(0.0, float(f.get("slow_t", 0.0)) - dt)
		if relics.has("hourglass"):
			slow *= 0.85
		var move := dir
		if f["ranged"]:
			# Archers and casters hold their distance and shoot.
			var dist: float = f["pos"].distance_to(t["pos"])
			move = -dir * 0.6 if dist < RANGED_KEEP - 40.0 else (dir if dist > RANGED_KEEP + 40.0 else Vector2.ZERO)
			f["shot_cd"] = float(f["shot_cd"]) - dt
			if f["shot_cd"] <= 0.0 and dist < RANGED_KEEP + 120.0 and float(f["stun_t"]) <= 0.0 and foe_shots.size() < MAX_BOLTS:
				f["shot_cd"] = RANGED_CD
				foe_shots.append({"pos": f["pos"] + Vector2(0, -24), "vel": dir * BOLT_SPEED, "dmg": float(f["dmg"]) * BOLT_MULT, "life": 3.0})
		if f["tier"] != "combat" and float(f["stun_t"]) <= 0.0:
			f["slam_cd"] = float(f.get("slam_cd", SLAM_CD[f["tier"]] * 0.5)) - dt
			# Slams aim at the hero you steer: dodging them is your job.
			if f["slam_cd"] <= 0.0 and f["pos"].distance_squared_to(lp) < 280.0 * 280.0:
				f["slam_cd"] = SLAM_CD[f["tier"]]
				slams.append({"pos": lp, "r": SLAM_R[f["tier"]], "t": SLAM_WARN, "dmg": float(f["dmg"]) * SLAM_MULT})
		f["pos"] += move * f["speed"] * slow * dt + push
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
				h["ab_cd"] = ability_cd_max(h)
				_ability(h, w, area)
				if relics.has("echo"):
					_ability(h, w, area)
				if h.get("twist", false):
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
	var evo: bool = evolved.has(h["role"])
	var reach := float(w["range"]) * (area if w["kind"] in ["arc", "pulse"] else 1.0) * (1.4 if evo and w["kind"] in ["arc", "pulse"] else 1.0)
	var t := _nearest_foe(h["pos"], reach)
	if t < 0:
		return false
	var dmg := _hero_dmg(h, float(w["mult"]) * power)
	var tpos: Vector2 = foes[t]["pos"]
	match w["kind"]:
		"arc", "pulse":
			events.append({"type": w["kind"], "pos": h["pos"], "r": reach, "role": h["role"]})
			_hit_area(h["pos"], reach, dmg)
			if evo and w["kind"] == "arc":
				_hit_area(h["pos"], reach, dmg)
			elif evo:
				_heal_all(0.03)
		"stab":
			var targets: Array = [t]
			if evo:
				targets = _nearest_foes(h["pos"], reach, 3)
			targets.sort()
			targets.reverse()   # highest index first, so a kill doesn't shift the rest
			for ti in targets:
				events.append({"type": "stab", "from": h["pos"], "to": foes[ti]["pos"]})
				_damage(ti, dmg)
		"shot", "bolt":
			var n := 1 + _stat("multishot")
			var base_dir: Vector2 = (tpos - h["pos"]).normalized()
			for k in n:
				var dir := base_dir.rotated((k - (n - 1) * 0.5) * 0.18)
				shots.append({"pos": h["pos"], "vel": dir * (520.0 if w["kind"] == "shot" else 380.0), "dmg": dmg, "r": 10.0,
					"life": 1.0, "pierce": 999 if evo and w["kind"] == "shot" else int(w.get("pierce", 0)),
					"burst": float(w.get("burst", 0.0)) * area * (2.0 if evo else 1.0), "hit": [], "kind": w["kind"], "burn": evo and w["kind"] == "bolt"})
	if h["pos"].x != tpos.x and not (h["lead"] and h.get("moving", false)):
		h["facing"] = signf(tpos.x - h["pos"].x)
	return true


## A hero's archetype twist (TWIST_TEXT), picked at level-up, rides on every Ability.
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
	if h.get("twist", false) and str(h.get("arch", "")) == "executioner":
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
	events.append({"type": "ability", "pos": h["pos"], "role": h["role"], "name": str(h.get("ability_name", "")), "hero": h["hero"].id})
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
	for b in braziers.duplicate():
		if b["pos"].distance_squared_to(center) <= (r + 12.0) * (r + 12.0):
			_break_brazier(b)
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
	if f.get("chest", false):
		chests.append({"pos": f["pos"]})
	if f.get("final", false):
		won = true
		over = true
		events.append({"type": "won", "name": f["name"]})
	if relics.has("fang"):
		for h in heroes:
			if h["alive"]:
				h["hp"] = minf(h["max_hp"], h["hp"] + h["max_hp"] * 0.002)
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
						if sh.get("burn", false):
							for g in foes:
								if g["pos"].distance_squared_to(sh["pos"]) <= sh["burst"] * sh["burst"]:
									g["burn_t"] = 3.0
									g["burn_dps"] = maxf(float(g.get("burn_dps", 0.0)), sh["dmg"] * 0.3)
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
				if not _hurt_hero(h, f["dmg"]):
					break
				if relics.has("ember"):
					f["burn_t"] = 3.0
					f["burn_dps"] = maxf(float(f.get("burn_dps", 0.0)), float(Combat.dmg_of(h["hero"])) * 0.5 * dmg_mult())
				if float(h.get("riposte_t", 0.0)) > 0.0 and i < foes.size() and foes[i] == f:
					_damage(i, _hero_dmg(h, 2.0))
					events.append({"type": "stab", "from": h["pos"], "to": f["pos"]})
				if _stat("thorns") > 0 and i < foes.size() and foes[i] == f:
					_damage(i, float(Combat.dmg_of(h["hero"])) * 0.4 * _stat("thorns") * dmg_mult())
				break


## A foe's blow or bolt lands on a hero (dodge, Undying, Tempered Plate,
## Taunt and a shield wall first). False if it didn't land.
func _hurt_hero(h: Dictionary, dmg: float) -> bool:
	if rng.randf() < dodge + (0.4 if dodge_t > 0.0 else 0.0):
		events.append({"type": "dodge", "hero": h["hero"].id})
		return false
	if float(h.get("undying_t", 0.0)) > 0.0:
		return false
	var taken := dmg * pow(0.88, _stat("armor")) * (0.6 if float(h.get("taunt_t", 0.0)) > 0.0 else 1.0) * (0.5 if wall_t > 0.0 else 1.0)
	h["hp"] -= taken
	events.append({"type": "hurt", "hero": h["hero"].id, "dmg": taken})
	if h["hp"] <= 0.0:
		h["hp"] = 0.0
		h["alive"] = false
		events.append({"type": "down", "hero": h["hero"].id})
	return true


func _move_foe_shots(dt: float) -> void:
	for s in range(foe_shots.size() - 1, -1, -1):
		var b: Dictionary = foe_shots[s]
		b["pos"] += b["vel"] * dt
		b["life"] -= dt
		var done: bool = b["life"] <= 0.0
		for h in heroes:
			if not done and h["alive"] and b["pos"].distance_squared_to(h["pos"] + Vector2(0, -20)) <= (HERO_R + 6.0) * (HERO_R + 6.0):
				_hurt_hero(h, b["dmg"])
				done = true
		if done:
			foe_shots.remove_at(s)


# ---------------- Terrain ----------------

## A chunk's features and brazier, made once from the run's seed.
func _chunk(c: Vector2i) -> Dictionary:
	if _chunks.has(c):
		return _chunks[c]
	var cr := RandomNumberGenerator.new()
	cr.seed = hash([_seed, biome, c.x, c.y])
	var kind: String = TERRAIN_KIND.get(biome, "pillar")
	var feats: Array = []
	var n := cr.randi_range(1, 3) if kind == "pillar" else cr.randi_range(1, 2)
	for k in n:
		var r: float = {"pillar": cr.randf_range(20.0, 28.0), "pool": cr.randf_range(55.0, 90.0), "lava": cr.randf_range(40.0, 65.0)}[kind]
		var p := Vector2(c) * CHUNK + Vector2(cr.randf_range(r, CHUNK - r), cr.randf_range(r, CHUNK - r))
		if p.length() > 220.0:   # the party starts on open ground
			feats.append({"id": "%d_%d_%d" % [c.x, c.y, k], "pos": p, "r": r, "kind": kind})
	var ch := {"features": feats, "brazier": {}}
	if cr.randf() < BRAZIER_CHANCE:
		var bp := Vector2(c) * CHUNK + Vector2(cr.randf_range(60.0, CHUNK - 60.0), cr.randf_range(60.0, CHUNK - 60.0))
		if not feats.any(func(f): return f["pos"].distance_to(bp) < float(f["r"]) + 40.0):
			ch["brazier"] = {"id": "b%d_%d" % [c.x, c.y], "pos": bp}
	_chunks[c] = ch
	return ch


## Every half second: the features and braziers within two chunks of the lead.
func _refresh_terrain() -> void:
	var lc := Vector2i(floori(lead()["pos"].x / CHUNK), floori(lead()["pos"].y / CHUNK))
	terrain.clear()
	braziers.clear()
	for ox in range(-2, 3):
		for oy in range(-2, 3):
			var ch := _chunk(lc + Vector2i(ox, oy))
			terrain.append_array(ch["features"])
			var b: Dictionary = ch["brazier"]
			if not b.is_empty() and not _broken.has(b["id"]):
				braziers.append(b)


func _in_terrain(p: Vector2, kind: String) -> bool:
	for f in terrain:
		if f["kind"] == kind and p.distance_squared_to(f["pos"]) < float(f["r"]) * float(f["r"]):
			return true
	return false


## Pillars push bodies out; pools slow foes (heroes: _move_heroes); lava burns
## foes and the lead.
func _terrain_effects(dt: float) -> void:
	_terrain_t -= dt
	if _terrain_t <= 0.0:
		_terrain_t = 0.5
		_refresh_terrain()
	if terrain.is_empty():
		return
	var lp: Vector2 = lead()["pos"]
	var close: Array = terrain.filter(func(f): return f["pos"].distance_squared_to(lp) < 1000.0 * 1000.0)
	for f in close:
		var fr: float = f["r"]
		for h in heroes:
			if not h["alive"]:
				continue
			var d: Vector2 = h["pos"] - f["pos"]
			match str(f["kind"]):
				"pillar":
					if d.length() < fr + HERO_R:
						h["pos"] = f["pos"] + (d.normalized() if d.length() > 0.01 else Vector2.RIGHT) * (fr + HERO_R)
				"lava":
					# Only the hero you steer: companions can't choose where they walk.
					if h["lead"] and d.length() < fr:
						h["hp"] -= h["max_hp"] * LAVA_HERO_PCT * dt
						if h["hp"] <= 0.0:
							h["hp"] = 0.0
							h["alive"] = false
							events.append({"type": "down", "hero": h["hero"].id})
		var reach := fr + 50.0
		for g in foes:
			var d2: Vector2 = g["pos"] - f["pos"]
			if absf(d2.x) > reach or absf(d2.y) > reach:
				continue
			match str(f["kind"]):
				"pillar":
					if d2.length() < fr + float(g["r"]):
						g["pos"] = f["pos"] + (d2.normalized() if d2.length() > 0.01 else Vector2.RIGHT) * (fr + float(g["r"]))
				"pool":
					if d2.length() < fr:
						g["pos"] -= (lead()["pos"] - g["pos"]).normalized() * float(g["speed"]) * (1.0 - POOL_SLOW) * dt
				"lava":
					if d2.length() < fr and g["tier"] == "combat":
						g["burn_t"] = maxf(float(g.get("burn_t", 0.0)), 1.0)
						g["burn_dps"] = maxf(float(g.get("burn_dps", 0.0)), MON_HP0 * foe_hp_mult() * 0.2)


func _break_brazier(b: Dictionary) -> void:
	_broken[b["id"]] = true
	braziers.erase(b)
	var kind: String = PICKUP_KINDS[rng.randi() % PICKUP_KINDS.size()]
	# It rolls a step past the brazier, so it's seen before it's taken.
	var away: Vector2 = b["pos"] - lead()["pos"]
	pickups.append({"pos": b["pos"] + (away.normalized() if away.length() > 1.0 else Vector2.DOWN) * 44.0, "kind": kind})
	events.append({"type": "brazier", "pos": b["pos"]})


func _use_pickup(kind: String) -> void:
	events.append({"type": "pickup", "kind": kind, "pos": lead()["pos"]})
	match kind:
		"heal":
			_heal_all(0.25)
		"magnet":
			for g in gems:
				g["pulled"] = true
		"bomb":
			var dmg := _hero_dmg(lead(), 6.0)
			for i in range(foes.size() - 1, -1, -1):
				if i < foes.size() and foes[i]["pos"].distance_squared_to(lead()["pos"]) <= 700.0 * 700.0:
					_damage(i, dmg)


## Telegraphed slams land when their warning runs out.
func _tick_slams(dt: float) -> void:
	for k in range(slams.size() - 1, -1, -1):
		var s: Dictionary = slams[k]
		s["t"] = float(s["t"]) - dt
		if s["t"] > 0.0:
			continue
		var hit := false
		for h in heroes:
			if h["alive"] and h["pos"].distance_squared_to(s["pos"]) <= float(s["r"]) * float(s["r"]):
				_hurt_hero(h, float(s["dmg"]))
				hit = true
		events.append({"type": "slam", "pos": s["pos"], "r": s["r"], "hit": hit})
		slams.remove_at(k)


## Rift relics that act on a timer.
func _tick_relics(dt: float) -> void:
	if relics.has("storm"):
		_storm_t -= dt
		if _storm_t <= 0.0:
			_storm_t = 1.5
			var near: Array = []
			for i in foes.size():
				if foes[i]["pos"].distance_squared_to(lead()["pos"]) <= 420.0 * 420.0:
					near.append(i)
			if not near.is_empty():
				var i: int = near[rng.randi() % near.size()]
				events.append({"type": "lightning", "pos": foes[i]["pos"]})
				_damage(i, _hero_dmg(lead(), 3.0))
	if relics.has("lodestone"):
		_lode_t -= dt
		if _lode_t <= 0.0:
			_lode_t = 30.0
			for g in gems:
				g["pulled"] = true
	if relics.has("aegis"):
		_aegis_t -= dt
		if _aegis_t <= 0.0:
			_aegis_t = 20.0
			wall_t = maxf(wall_t, 3.0)
			events.append({"type": "sanctuary", "pos": lead()["pos"], "r": 160.0})


func _pickups(dt: float) -> void:
	var lp: Vector2 = lead()["pos"]
	for b in braziers.duplicate():
		if b["pos"].distance_squared_to(lp) <= 36.0 * 36.0:
			_break_brazier(b)
	for k in range(pickups.size() - 1, -1, -1):
		if pickups[k]["pos"].distance_squared_to(lp) <= 30.0 * 30.0:
			_use_pickup(str(pickups[k]["kind"]))
			pickups.remove_at(k)
	for c in range(chests.size() - 1, -1, -1):
		if chests[c]["pos"].distance_squared_to(lp) <= CHEST_R * CHEST_R:
			chests.remove_at(c)
			pending_chests += 1
			events.append({"type": "chest"})
	var reach := PICKUP_R * (1.0 + 0.5 * _stat("magnet")) * (1.6 if relics.has("lodestone") else 1.0)
	for g in range(gems.size() - 1, -1, -1):
		var gem: Dictionary = gems[g]
		var d: float = gem["pos"].distance_to(lp)
		if not gem.get("pulled", false):
			for h in heroes:
				if h["alive"] and gem["pos"].distance_squared_to(h["pos"]) < reach * reach:
					gem["pulled"] = true
					break
		if gem.get("pulled", false):
			gem["pos"] = gem["pos"].move_toward(lp, maxf(480.0, d * 2.0) * dt)
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
	var evos: Array = evolutions_ready()
	for i in heroes.size():
		var h: Dictionary = heroes[i]
		for sk in GameData.ROLE_SKILLS.get(h["hero"].cls_id, []):
			if not (h["skills"] as Dictionary).has(sk["id"]) and SKILL_MOVES.has(sk["id"]):
				pool.append("skill:%d:%s" % [i, sk["id"]])
		if h["has_ability"] and int(h["ab_rank"]) < ABILITY_RANK_MAX:
			pool.append("ability:%d" % i)
		if h["has_ability"] and int(h["ab_rank"]) >= 1 and not h.get("twist", false) and TWIST_TEXT.has(str(h["arch"])):
			pool.append("twist:%d" % i)
	# A ready evolution is always offered, first.
	var out: Array = evos.slice(0, 1).map(func(r): return "evolve:" + str(r))
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
	if parts[0] == "evolve":
		evolved[parts[1]] = true
		return
	if parts[0] == "twist":
		heroes[int(parts[1])]["twist"] = true
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


## A hero's Ability cooldown with Focused Mind and its ranks.
func ability_cd_max(h: Dictionary) -> float:
	return ABILITY_CD * pow(0.8, _stat("focus")) * pow(ABILITY_RANK_CD, int(h["ab_rank"]))


## The HUD's pick tray: [{icon, name, count, special}] in the order picked.
func tray() -> Array:
	var out: Array = []
	for id in upgrades:
		out.append({"icon": UPGRADES[id]["icon"], "name": "%s (%d/%d)" % [tr(str(UPGRADES[id]["name"])), upgrades[id], UPGRADES[id]["max"]], "count": int(upgrades[id]), "special": false})
	for role in evolved:
		out.append({"icon": EVOLUTIONS[role]["icon"], "name": "%s: %s" % [tr(str(EVOLUTIONS[role]["name"])), tr(str(EVOLUTIONS[role]["desc"]))], "count": 0, "special": true})
	for id in relics:
		out.append({"icon": RIFT_RELICS[id]["icon"], "name": "%s: %s" % [tr(str(RIFT_RELICS[id]["name"])), tr(str(RIFT_RELICS[id]["desc"]))], "count": 0, "special": true})
	for h in heroes:
		for sid in h["skills"]:
			var sk := GameData.find_role_skill(str(sid))
			out.append({"icon": sk["icon"], "name": "%s: %s" % [tr(str(h["hero"].name.split(" the ")[0])), tr(str(sk["name"]))], "count": 0, "special": false})
	return out


## Roles in the party whose auto-attack can evolve now (matching upgrade maxed).
func evolutions_ready() -> Array:
	var out: Array = []
	for role in EVOLUTIONS:
		if not evolved.has(role) and _stat(EVOLUTIONS[role]["needs"]) >= int(UPGRADES[EVOLUTIONS[role]["needs"]]["max"]) and heroes.any(func(h): return h["role"] == role):
			out.append(role)
	return out


## Up to three rift relics not found yet, for a chest.
func chest_offer() -> Array:
	var pool: Array = RIFT_RELICS.keys().filter(func(id): return not relics.has(id))
	var out: Array = []
	while out.size() < 3 and not pool.is_empty():
		out.append(pool.pop_at(rng.randi() % pool.size()))
	return out


## Opens the waiting chest with this relic ("" when every relic is found: gold instead).
func take_relic(id: String) -> void:
	if pending_chests <= 0:
		return
	pending_chests -= 1
	if id == "":
		bonus_coins += 60
		return
	relics[id] = true


## What a level-up pick is, for the offer screen: {name, desc, icon, have, max}.
func upgrade_info(id: String) -> Dictionary:
	var parts := id.split(":")
	if parts[0] == "evolve":
		var ev: Dictionary = EVOLUTIONS[parts[1]]
		return {"name": tr("Evolve: ") + tr(str(ev["name"])), "desc": ev["desc"], "icon": ev["icon"], "have": 0, "max": 1, "special": true}
	if parts[0] == "twist":
		var ht: Dictionary = heroes[int(parts[1])]
		return {"name": tr("%s: %s twist") % [tr(str(ht["hero"].name.split(" the ")[0])), tr(str(GameData.ARCHETYPES[ht["arch"]]))], "desc": "%s %s" % [tr(str(ht["ability_name"])), tr(str(TWIST_TEXT[ht["arch"]]))],
			"icon": ht["ab_icon"], "have": 0, "max": 1}
	if parts[0] == "relic":
		var rl: Dictionary = RIFT_RELICS[parts[1]]
		return {"name": rl["name"], "desc": rl["desc"], "icon": rl["icon"], "have": 0, "max": 1, "special": true}
	if parts[0] == "skill":
		var h: Dictionary = heroes[int(parts[1])]
		var sk := GameData.find_role_skill(parts[2])
		return {"name": "%s: %s" % [tr(str(h["hero"].name.split(" the ")[0])), tr(str(sk["name"]))], "desc": str(SKILL_MOVES[parts[2]]["desc"]), "icon": str(sk["icon"]), "have": 0, "max": 1}
	if parts[0] == "ability":
		var h2: Dictionary = heroes[int(parts[1])]
		var r := int(h2["ab_rank"])
		var d := tr("Fires 20% sooner and hits 30% harder")
		return {"name": "%s: %s" % [tr(str(h2["hero"].name.split(" the ")[0])), tr(str(h2["ability_name"]))], "desc": d, "icon": h2["ab_icon"], "have": r, "max": ABILITY_RANK_MAX}
	var u: Dictionary = UPGRADES[id]
	return {"name": u["name"], "desc": u["desc"], "icon": u["icon"], "have": _stat(id), "max": int(u["max"])}


## Everything picked so far, for the pause screen.
func owned_lines() -> Array:
	var out: Array = upgrades.keys().map(func(id): return "%s ×%d" % [tr(str(UPGRADES[id]["name"])), upgrades[id]])
	for h in heroes:
		var who: String = h["hero"].name.split(" the ")[0]
		for sid in h["skills"]:
			out.append("%s: %s" % [tr(str(who)), tr(str(GameData.find_role_skill(str(sid))["name"]))])
		if int(h["ab_rank"]) > 0:
			out.append(tr("%s: %s rank %d") % [tr(str(who)), tr(str(h["ability_name"])), int(h["ab_rank"])])
		if h.get("twist", false):
			out.append(tr("%s: %s twist") % [tr(str(who)), tr(str(GameData.ARCHETYPES[h["arch"]]))])
	for role in evolved:
		out.append(str(EVOLUTIONS[role]["name"]))
	for id in relics:
		out.append(str(RIFT_RELICS[id]["name"]))
	return out


## Tests, the sim and fast-forwards: settles every waiting level-up (the first
## offer, or choose(offer)'s pick) and chest (the first relic).
func settle_picks(choose: Callable = Callable()) -> void:
	while pending_levels > 0:
		var o := offer()
		pick(str(choose.call(o)) if choose.is_valid() else (o[0] if not o.is_empty() else ""))
	while pending_chests > 0:
		var c := chest_offer()
		take_relic(c[0] if not c.is_empty() else "")


## Auto-pilot for tests and the balance sim, playing like a careful player:
## step away from foes that get close, otherwise go and collect shards.
func autopilot_dir() -> Vector2:
	var lp: Vector2 = lead()["pos"]
	var away := Vector2.ZERO
	var close := false
	# In a lost champion's light and healthy: hold it (step out of slams only).
	var holding := not beacon.is_empty() and lp.distance_to(beacon["pos"]) < GameData.BEACON_R * 0.7 and float(lead()["hp"]) > float(lead()["max_hp"]) * 0.35
	for s in slams:
		var out: Vector2 = lp - s["pos"]
		if out.length() < float(s["r"]) + 20.0:
			return (out if out.length() > 1.0 else Vector2.RIGHT).normalized()
	for f in terrain:
		if f["kind"] == "lava" and lp.distance_to(f["pos"]) < float(f["r"]) + 10.0:
			return (lp - f["pos"]).normalized()
	for b in foe_shots:
		var to_me: Vector2 = lp - b["pos"]
		if to_me.length_squared() < 120.0 * 120.0 and to_me.dot(b["vel"]) > 0.0:
			away += b["vel"].orthogonal().normalized() * signf(b["vel"].orthogonal().dot(to_me) + 0.001) * 0.2
			close = true
	for f in foes:
		var d: Vector2 = lp - f["pos"]
		var l2 := d.length_squared()
		if l2 < 110.0 * 110.0:
			away += d / maxf(l2, 1.0) * (4.0 if f["tier"] != "combat" else 1.0)
			close = true
	if holding:
		return Vector2.ZERO
	if close:
		return away.normalized()
	if not beacon.is_empty():
		var to_b: Vector2 = beacon["pos"] - lp
		return Vector2.ZERO if to_b.length() < GameData.BEACON_R * 0.5 else to_b.normalized()
	var best := Vector2.INF
	for c in chests:
		if c["pos"].distance_squared_to(lp) < 600.0 * 600.0:
			return (c["pos"] - lp).normalized()
	for g in gems:
		if g["pos"].distance_squared_to(lp) < best.distance_squared_to(lp):
			best = g["pos"]
	if best != Vector2.INF:
		return (best - lp).normalized()
	return Vector2.RIGHT.rotated(time * 0.3)


# ---------------- Rewards ----------------

## What the guild earns for this run (time survived and kills).
## Gold is light here (the champions don't draw wages, and a run costs the
## guild a day); Echoes level the champions.
func rewards() -> Dictionary:
	var m := minutes()
	var coins := (15.0 * m + 0.02 * kills + (100.0 if won else 0.0)) * (1.4 if relics.has("idol") else 1.0) + bonus_coins
	return {"coins": int(round(coins)), "crystals": int(round(7.0 * m + 3.0 * elites_killed + 20.0 * bosses_killed + (50.0 if won else 0.0))),
		"echoes": int(round(2.0 * m + 1.0 * elites_killed + 5.0 * bosses_killed + (20.0 if won else 0.0) + 10.0 * rescued.size())),
		"loot": elites_killed / 4 + bosses_killed + (2 if won else 0)}


# ---------------- Lost champions ----------------

## A lost champion's light appears once the run is deep enough (one at a
## time, in depth order); standing in it for BEACON_HOLD seconds frees them.
func _tick_beacon(dt: float) -> void:
	if beacon.is_empty():
		for e in lost:
			var id := str(e[0])
			if time >= float(e[1]) and not rescued.has(id):
				var ang := rng.randf() * TAU
				beacon = {"id": id, "pos": lead()["pos"] + Vector2.RIGHT.rotated(ang) * GameData.BEACON_DIST, "held": 0.0}
				events.append({"type": "beacon", "id": id, "pos": beacon["pos"]})
				return
		return
	var inside := false
	for h in heroes:
		if h["alive"] and (h["pos"] as Vector2).distance_to(beacon["pos"]) <= GameData.BEACON_R:
			inside = true
			break
	if not inside:
		return
	beacon["held"] = float(beacon["held"]) + dt
	if float(beacon["held"]) >= GameData.BEACON_HOLD:
		rescued.append(beacon["id"])
		events.append({"type": "rescue", "id": beacon["id"], "pos": beacon["pos"]})
		_heal_all(0.25)
		beacon = {}
