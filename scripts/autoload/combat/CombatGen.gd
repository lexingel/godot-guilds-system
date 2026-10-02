extends "res://scripts/autoload/combat/CombatEffects.gd"
## Combat, part 3: generating heroes, relics, items, loot, rift layouts and monsters (affixes, boss phases, hero voices).


func innate_value_for(cls: Dictionary, rank_idx: int) -> float:
	if cls["kind"] == "boss_alpha_strike":
		return 1.0
	var base: float = GameData.CHAMP_KIND_BASE[cls["kind"]]
	return snappedf(base * (1.0 + rank_idx * 0.18), 0.001)


func hero_innate_value(cls: Dictionary, rank_idx: int) -> float:
	return snappedf(innate_value_for(cls, rank_idx) * HERO_INNATE_MULT, 0.001)


func gen_hero(rank_id: String, level_hint: int) -> Hero:
	var rank := GameData.find_rank(rank_id)
	var rank_idx := GameData.rank_index(rank_id)
	var pool: Array = GameData.CLASS_POOL.filter(func(c): return c["rank"] == rank_id)
	var cls: Dictionary = pool[randi() % pool.size()]
	var role_cls := GameData.find_role(cls["role"])
	var h := Hero.new()
	h.id = "h" + str(GameState.next_id)
	GameState.next_id += 1
	# Avoid a first name already in the roster or on offer (two "Aldric"s
	# are hard to tell apart in the arena and party lists).
	var taken := {}
	for other in GameState.heroes + GameState.recruit_pool:
		taken[other.name.split(" the ")[0]] = true
	var free_names: Array = GameData.FIRST_NAMES.filter(func(n): return not taken.has(n))
	var names: Array = free_names if not free_names.is_empty() else GameData.FIRST_NAMES
	h.name = "%s the %s" % [names[randi() % names.size()], cls["name"]]
	h.cls_id = cls["role"]
	h.pool_id = cls["id"]
	h.type = cls["type"]
	h.flavor = cls["flavor"]
	h.rank = rank["id"]
	h.innate_kind = cls["kind"]
	h.innate_value = hero_innate_value(cls, rank_idx)
	h.level = level_hint
	var s := 1.0 + GameData.LEVEL_GROWTH * (level_hint - 1)
	h.base_hp = round(role_cls["base_hp"] * cls["hp_ratio"] * rank["mult"] * s)
	h.base_dmg = round(role_cls["base_dmg"] * cls["dmg_ratio"] * rank["mult"] * s)
	h.base_spd = round(float(role_cls["base_spd"]) * float(rank["mult"]))
	var born := roll_born_quirk(cls["role"])
	if born != "":
		h.quirks.append(born)
	h.formation = str(GameData.ROLE_POSITION.get(cls["role"], {}).get("row", "front"))
	# Recruits arrive with their levels' points already spent by role.
	h.attrs = GameData.role_attrs(cls["role"])
	h.attr_points = (level_hint - 1) * GameData.ATTR_POINTS_PER_LEVEL
	auto_spend_attrs(h)
	h.hp = max_hp(h)
	return h


## `type_override` lets Crafting Hall recipes preserve the fed-in relics'
## elemental type on the crafted result instead of rolling a fresh random one
## — a player feeding in 3 Ember commons reasonably expects an Ember rare
## back, not a coin flip across all 5 types.
func gen_relic(rarity_id: String, type_override: String = "") -> Relic:
	if rarity_id == "legendary":
		return gen_unique_relic()
	var type: String = type_override if type_override != "" else GameData.RELIC_TYPES[randi() % GameData.RELIC_TYPES.size()]
	var rarity := GameData.find_rarity(rarity_id)
	var noun: String = RARITY_NOUNS[randi() % RARITY_NOUNS.size()]
	var r := Relic.new()
	r.id = "rl" + str(GameState.next_id)
	GameState.next_id += 1
	r.type = type
	r.rarity = rarity["id"]
	r.dmg = round(2.0 * rarity["mult"])
	r.hp = round(6.0 * rarity["mult"])
	# Common: one special. Rare: a special and a trigger. Epic: two and a trigger.
	r.specials = [roll_relic_special(type, r.rarity, [])]
	if r.rarity == "epic":
		r.specials.append(roll_relic_special(type, r.rarity, r.specials.map(func(s): return s["kind"])))
	if r.rarity != "common":
		r.trigger = roll_relic_trigger(r.rarity)
	r.name = "%s %s %s" % [type, noun, GameData.RELIC_SPECIAL_SUFFIX.get(str(r.specials[0]["kind"]), "")]
	return r


## One special for a relic of `type` (60% its element's home domain), never a
## kind in `exclude`. The label is rebuilt from the scaled value.
func roll_relic_special(type: String, rarity_id: String, exclude: Array) -> Dictionary:
	var domain := domain_for_type(type)
	var pool: Array = GameData.RELIC_SPECIALS.filter(func(x): return x["domain"] == domain and not exclude.has(x["kind"]))
	if pool.is_empty():
		pool = GameData.RELIC_SPECIALS.filter(func(x): return not exclude.has(x["kind"]))
	var s: Dictionary = pool[randi() % pool.size()]
	var v := snappedf(float(s["value"]) * float(GameData.find_rarity(rarity_id)["mult"]), 0.001)
	return {"kind": s["kind"], "value": v, "label": relic_special_label(str(s["kind"]), v)}


func relic_special_label(kind: String, v: float) -> String:
	var pct := ("%.1f%%" % (v * 100.0)) if v < 0.1 else ("%d%%" % int(round(v * 100.0)))
	match kind:
		"mend_pct": return tr("Mends %s HP/round") % tr(str(pct))
		"dodge_pct": return tr("+%s dodge chance") % tr(str(pct))
		"escalate_pct": return tr("+%s dmg/round (stacking)") % tr(str(pct))
		"hazard_guard_pct": return tr("-%s hazard severity") % tr(str(pct))
		"first_round_pct": return tr("+%s first-strike damage") % tr(str(pct))
		"loot_rarity_pct": return tr("+%s odds toward Rare/Epic loot") % tr(str(pct))
		"wipe_guard": return tr("Relic ward: survive a wipe at %d%% HP") % int(round(v * 100))
		"boss_alpha_strike": return tr("+%d%% opening volley vs Bosses") % int(round(v * 100))
		"counter_pct": return tr("+%d%% chance to counter when evading or hit hard") % int(round(v * 100))
		"momentum_pct": return tr("+%d%% chance to gain 1 Momentum when evading or hit hard") % int(round(v * 100))
		"kill_shield_pct": return tr("On a kill, shield the weakest ally for %d%% of max HP") % int(round(v * 100))
	return describe_skill(kind, v)


func roll_relic_trigger(rarity_id: String) -> Dictionary:
	var t: Dictionary = GameData.RELIC_TRIGGERS[randi() % GameData.RELIC_TRIGGERS.size()].duplicate()
	# Triggers scale gentler than stats (sqrt of the rarity mult) — they fire
	# repeatedly, so a full epic multiplier made them dominate.
	t["value"] = snappedf(float(t["value"]) * sqrt(float(GameData.find_rarity(rarity_id)["mult"])), 0.001)
	return t


## A fixed pick from GameData.UNIQUE_RELICS — no rarity-mult scaling, the
## effect/value/drawback are exactly as authored. "Twin Embers" is the one
## entry whose own effect is a normal rollable-style special (escalate_pct)
## rather than a bespoke mechanic, so it reuses special_kind/special_value
## instead of `effect` — Combat.resolve_round only dispatches on unique_id
## for the entries that actually need bespoke behavior.
func gen_unique_relic() -> Relic:
	return relic_from_unique(GameData.UNIQUE_RELICS[randi() % GameData.UNIQUE_RELICS.size()])


## A Legendary relic built exactly from a UNIQUE_RELICS/TOWER_RELICS entry.
func relic_from_unique(def: Dictionary) -> Relic:
	var r := Relic.new()
	r.id = "rl" + str(GameState.next_id)
	GameState.next_id += 1
	r.name = str(def["name"])
	r.type = str(def["type"])
	r.rarity = "legendary"
	r.dmg = 0
	r.hp = 0
	r.unique_id = str(def["id"])
	r.combo_with = str(def.get("combo_with", ""))
	if def.has("special_kind"):
		r.specials = [{"kind": str(def["special_kind"]), "value": float(def["special_value"]), "label": relic_special_label(str(def["special_kind"]), float(def["special_value"]))}]
	if def.has("trigger"):
		r.trigger = (def["trigger"] as Dictionary).duplicate()
	if str(def.get("drawback_kind", "")) != "":
		r.drawback_kind = str(def["drawback_kind"])
		r.drawback_value = float(def["drawback_value"])
		r.drawback_label = str(def["drawback_label"])
	return r


## `category_override` — see gen_relic's type_override for why: Crafting Hall
## recipes keep a player's chosen equip-slot category intact across a craft.
## `rank` is the item's rift rank (see GameData.ITEM_RANK_MULT); "" means
## "wherever the party is right now" (GameState.loot_rank).
## One rolled stat line's value — gen_item's formula, for rerolls.
func item_line_value(kind: String, rarity_id: String, line: int, rank: String) -> float:
	var rank_mult: float = GameData.ITEM_RANK_MULT[GameData.rift_rank_index(rank if rank != "" else "F")]
	var roll := randf_range(GameData.ITEM_ROLL_RANGE[0], GameData.ITEM_ROLL_RANGE[1]) * rank_mult
	return snappedf(GameData.ITEM_KIND_BASE[kind] * float(GameData.find_rarity(rarity_id)["mult"]) * GameData.ITEM_AFFIX_VALUE_SHARE[line] * roll, 0.001)


func gen_item(rarity_id: String, category_override: String = "", rank: String = "") -> Item:
	if rarity_id == "legendary":
		return gen_unique_item()
	if rank == "":
		rank = GameState.loot_rank()
	var rank_mult: float = GameData.ITEM_RANK_MULT[GameData.rift_rank_index(rank)]
	var rarity := GameData.find_rarity(rarity_id)
	var category: String = category_override if category_override != "" else GameData.ITEM_CATEGORIES[randi() % GameData.ITEM_CATEGORIES.size()]
	var nouns: Array = GameData.ITEM_NOUNS[category]
	var noun: String = nouns[randi() % nouns.size()]
	var roll := func() -> float: return randf_range(GameData.ITEM_ROLL_RANGE[0], GameData.ITEM_ROLL_RANGE[1]) * rank_mult

	# Roll N distinct kinds (1/2/3 by rarity) from this category's pool —
	# shuffled-and-take-first rather than reject-sampling, so it's exact and
	# can't loop. Each slot past the first is worth less of ITEM_KIND_BASE
	# (see ITEM_AFFIX_VALUE_SHARE) so the primary stat stays the item's clear
	# identity.
	var affix_count: int = GameData.ITEM_AFFIX_COUNT_BY_RARITY.get(rarity_id, 1)
	var pool: Array = GameData.ITEM_CATEGORY_KINDS[category].duplicate()
	pool.shuffle()
	var rolled_kinds: Array = pool.slice(0, affix_count)

	var it := Item.new()
	it.id = "it" + str(GameState.next_id)
	GameState.next_id += 1
	it.category = category
	it.rarity = rarity["id"]
	it.item_rank = rank
	it.kind = str(rolled_kinds[0])
	it.value = snappedf(GameData.ITEM_KIND_BASE[it.kind] * rarity["mult"] * GameData.ITEM_AFFIX_VALUE_SHARE[0] * roll.call(), 0.001)
	if rolled_kinds.size() > 1:
		it.secondary_kind = str(rolled_kinds[1])
		it.secondary_value = snappedf(GameData.ITEM_KIND_BASE[it.secondary_kind] * rarity["mult"] * GameData.ITEM_AFFIX_VALUE_SHARE[1] * roll.call(), 0.001)
	if rolled_kinds.size() > 2:
		it.tertiary_kind = str(rolled_kinds[2])
		it.tertiary_value = snappedf(GameData.ITEM_KIND_BASE[it.tertiary_kind] * rarity["mult"] * GameData.ITEM_AFFIX_VALUE_SHARE[2] * roll.call(), 0.001)
	# Rare and Epic items carry a defining effect, which names them.
	var fx := {}
	if rarity_id in ["rare", "epic"]:
		var fx_pool: Array = (GameData.ITEM_EFFECTS[category] as Array).filter(func(e): return rarity_id == "epic" or not e.get("epic", false))
		fx = (fx_pool[randi() % fx_pool.size()] as Dictionary).duplicate(true)
		fx["value"] = snappedf(float(fx["value"]) * (GameData.ITEM_EFFECT_EPIC_MULT if rarity_id == "epic" else 1.0) * randf_range(0.9, 1.1), 0.001)
		it.effects = [fx]

	var prefixes: Array = GameData.ITEM_AFFIX_PREFIX[it.kind]
	# Stored in English (it's in the save); NameTranslation shows it translated.
	var name := "%s %s" % [prefixes[randi() % prefixes.size()], noun]
	if not fx.is_empty():
		name += " %s" % str(fx["suffix"])
	it.name = name
	it.attr = str(GameData.ITEM_BASE_ATTR.get(noun, "might"))
	it.attr_bonus = int(GameData.ITEM_ATTR_BONUS[rarity_id])
	it.attr_req = int(GameData.ITEM_ATTR_REQ[rarity_id])
	return it


## A fixed pick from GameData.UNIQUE_ITEMS — see gen_unique_relic for why
## this bypasses the normal category/kind roll entirely.
func gen_unique_item() -> Item:
	var def: Dictionary = GameData.UNIQUE_ITEMS[randi() % GameData.UNIQUE_ITEMS.size()]
	var it := Item.new()
	it.id = "it" + str(GameState.next_id)
	GameState.next_id += 1
	it.name = str(def["name"])
	it.category = str(def["category"])
	it.rarity = "legendary"
	# A Legendary also rolls one Epic-strength stat from its category (rank-
	# scaled like any drop) — with only its effect and a drawback, it used to
	# be a straight downgrade from the Epic it replaced.
	it.item_rank = GameState.loot_rank()
	var kinds: Array = GameData.ITEM_CATEGORY_KINDS[it.category]
	it.kind = str(kinds[randi() % kinds.size()])
	it.value = snappedf(GameData.ITEM_KIND_BASE[it.kind] * float(GameData.find_rarity("epic")["mult"]) * randf_range(GameData.ITEM_ROLL_RANGE[0], GameData.ITEM_ROLL_RANGE[1]) * GameData.ITEM_RANK_MULT[GameData.rift_rank_index(it.item_rank)], 0.001)
	it.unique_id = str(def["id"])
	it.drawback_kind = str(def.get("drawback_kind", ""))
	it.drawback_value = float(def.get("drawback_value", 0.0))
	it.locked_role = str(def.get("locked_role", ""))
	var subs: Array = def.get("locked_subclasses", [])
	it.locked_subclasses.assign(subs)
	it.attr = GameData.item_attr_for(it)
	it.attr_bonus = int(GameData.ITEM_ATTR_BONUS["legendary"])
	it.attr_req = int(GameData.ITEM_ATTR_REQ["legendary"])
	return it


## Returns {"loot_type": "item"|"relic", "obj": Item|Relic}
func gen_loot(rarity_id: String) -> Dictionary:
	if randf() < 0.5:
		return {"loot_type": "item", "obj": gen_item(rarity_id)}
	return {"loot_type": "relic", "obj": gen_relic(rarity_id)}

## Branching rift path: first layer forced combat, last forced boss, middle
## layers each offer 2 different node-type options (a fork the player picks
## between), with a guarantee at least one middle layer includes "elite".
## Campfire / event / treasure are one entry each, so fights stay about half
## of every fork.
const FORK_POOL := ["combat", "combat", "combat", "shop", "hazard", "elite", "campfire", "event", "treasure"]


func build_layers(diff: Dictionary) -> Array:
	var layers: Array = [{"options": ["combat"]}]
	var mid_count: int = int(diff["floors"]) - 2
	var pool: Array = FORK_POOL.duplicate()
	# A mapped rift's elite_chance_up/shop_chance_down modifiers bias the pool
	# by adding/removing one entry rather than reworking the odds formula.
	if diff.get("elite_chance_up", false):
		pool.append("elite")
	if diff.get("shop_chance_down", false):
		pool.erase("shop")
	for i in mid_count:
		var a: String = pool[randi() % pool.size()]
		var b: String = pool[randi() % pool.size()]
		var guard := 0
		while b == a and guard < 6:
			b = pool[randi() % pool.size()]
			guard += 1
		if b == a:
			var filtered: Array = pool.filter(func(x): return x != a)
			b = filtered[randi() % filtered.size()]
		layers.append({"options": [a, b]})
	if mid_count > 0:
		var has_elite := false
		for l in layers:
			var opts: Array = l["options"]
			if opts.has("elite"):
				has_elite = true
				break
		if not has_elite:
			var li := 1 + randi() % mid_count
			var oi := randi() % 2
			var opts: Array = layers[li]["options"]
			opts[oi] = "elite"
	layers.append({"options": ["boss"]})
	return layers

## Difficulty knobs, tuned with a full-run simulation (HP carrying across a
## rift's floors): the pressure sits on later floors, elites, bosses and the
## harder rifts, so a fresh Lesser run stays winnable while an invested party
## still has to make real choices. Endless growth is ENDLESS_CYCLE_GROWTH.
const MONSTER_FLOOR_SCALE := 0.14
const ELITE_HP_MULT := 2.0
const ELITE_DMG_MULT := 1.6
const BOSS_HP_MULT := 3.0
const BOSS_DMG_MULT := 2.0


func _biome_background(diff: Dictionary) -> int:
	var bgs: Array = GameData.BIOMES.get(str(diff.get("biome", "")), {}).get("backgrounds", [])
	return int(bgs[randi() % bgs.size()]) if not bgs.is_empty() else randi() % GameData.BATTLE_BACKGROUNDS.size()


func gen_monster(diff: Dictionary, floor_idx: int, kind: String) -> Dictionary:
	var scale := 1.0 + floor_idx * MONSTER_FLOOR_SCALE
	var hp_mult := BOSS_HP_MULT if kind == "boss" else (ELITE_HP_MULT if kind == "elite" else 1.0)
	var dmg_mult := BOSS_DMG_MULT if kind == "boss" else (ELITE_DMG_MULT if kind == "elite" else 1.0)
	var hp: int = round(diff["monster_hp"] * scale * hp_mult * (1.15 if GameState.sworn("hollow_touched") else 1.0))
	var dmg: int = round(diff["monster_dmg"] * scale * dmg_mult)
	var name: String
	if kind == "boss" and diff.has("boss_name"):
		name = str(diff["boss_name"])   # a campaign finale's named foe
	elif kind == "boss":
		# A region's own wardens: a new guild in the Vale never meets the Act III boss.
		var bosses: Array = GameData.BIOMES.get(str(diff.get("biome", "")), {}).get("bosses", GameData.BOSS_NAMES)
		name = "%s, %s Warden" % [bosses[randi() % bosses.size()], diff["name"].split(" ")[0]]
	elif kind == "elite":
		var elites: Array = GameData.BIOMES.get(str(diff.get("biome", "")), {}).get("elites", GameData.ELITE_NAMES)
		name = str(elites[randi() % elites.size()])
	else:
		var pool: Array = GameData.BIOMES.get(str(diff.get("biome", "")), {}).get("monsters", GameData.MONSTER_NAMES)
		name = str(pool[randi() % pool.size()])
	var base_name := name.split(",")[0]
	var armor := maxf(float(GameData.MONSTER_ARMOR.get(base_name, 0.0)), float(diff.get("tower_armor", 0.0)))
	var status := str(diff.get("tower_status", GameData.MONSTER_STATUS.get(base_name, "")))
	return {"name": name, "hp": hp, "dmg": dmg, "spd": 9 + randi() % 4, "tier": kind, "armor": armor, "status": status}


func _first_living_monster_idx(monsters: Array) -> int:
	for i in monsters.size():
		if float(monsters[i]["hp"]) > 0:
			return i
	return -1


func _lowest_hp_living_monster_idx(monsters: Array) -> int:
	var best := -1
	var best_hp := INF
	for i in monsters.size():
		var hp: float = float(monsters[i]["hp"])
		if hp > 0 and hp < best_hp:
			best_hp = hp
			best = i
	return best


## Rolls the monster(s) for one encounter. "combat" nodes get 1-3 interchangeable
## monsters with stats divided by the roll count, so total party-facing threat
## (total HP to clear, total incoming damage per round) stays comparable to a
## single monster regardless of count. "elite"/"boss" always get one full-
## strength main unit (boss still rolls its GameData.BOSS_MECHANICS entry —
## that's what makes the fight a boss fight) with a chance of 1-2 weaker
## "combat"-tier adds alongside it, not a dilution of the main unit itself.
func gen_monsters(diff: Dictionary, floor_idx: int, kind: String) -> Array[Dictionary]:
	var monsters: Array[Dictionary] = []
	if kind == "combat" and not diff.get("tower_single", false) and not diff.get("tower_swarm", false):
		var designed := _designed_encounter(diff, floor_idx)
		if not designed.is_empty():
			return designed
	if kind == "combat":
		var count := 1 + randi() % 3
		var share := float(count)
		if diff.get("tower_single", false):
			count = 1
			share = 1.0
		elif diff.get("tower_swarm", false):
			count = 4
			share = 2.5   # more foes, more total threat
		for i in count:
			var m := gen_monster(diff, floor_idx, "combat")
			m["hp"] = max(1, int(round(float(m["hp"]) / share)))
			m["dmg"] = max(1, int(round(float(m["dmg"]) / share)))
			m["max_hp"] = m["hp"]
			m["mechanic"] = {}
			m["ability"] = GameData.MONSTER_ABILITIES.get(str(m["name"]), {})
			m["is_main"] = i == 0
			monsters.append(m)
		return monsters

	var main := gen_monster(diff, floor_idx, kind)
	main["is_main"] = true
	main["ability"] = {}
	var profile: Dictionary = GameData.BOSS_PROFILES.get(str(main["name"]).split(",")[0], {}) if kind == "boss" else {}
	if kind == "boss":
		main["hp"] = int(round(float(main["hp"]) * float(profile.get("hp_mult", 1.0))))
		main["dmg"] = int(round(float(main["dmg"]) * float(profile.get("dmg_mult", 1.0))))
		var mechanic: Dictionary = GameData.BOSS_MECHANICS[randi() % GameData.BOSS_MECHANICS.size()]
		var fixed: Array = diff.get("boss_mechanics", profile.get("mechanics", []))   # a Tower guardian's own, or the boss's profile
		if not fixed.is_empty():
			mechanic = GameData.BOSS_MECHANICS.filter(func(bm): return bm["id"] == fixed[0])[0]
		if mechanic["id"] == "frenzied":
			main["dmg"] = int(round(main["dmg"] * 1.25))
		main["mechanic"] = mechanic
		# SS-rank-and-above mapped rifts roll a second, distinct mechanic
		# alongside the first — every consumption site below (fight-start log,
		# describe_incoming, the regen/retaliation loops, Main.gd's badge) reads
		# "mechanic2" via .get() with an empty-dict default, so this is additive
		# and doesn't touch the normal single-mechanic path at all.
		if bool(diff.get("boss_double_mechanic", false)) or fixed.size() > 1:
			fixed = fixed.duplicate()
			var pool: Array = GameData.BOSS_MECHANICS.filter(func(bm): return bm["id"] != mechanic["id"])
			var mechanic2: Dictionary = pool[randi() % pool.size()]
			if fixed.size() > 1:
				mechanic2 = GameData.BOSS_MECHANICS.filter(func(bm): return bm["id"] == fixed[1])[0]
			if mechanic2["id"] == "frenzied":
				main["dmg"] = int(round(main["dmg"] * 1.25))
			main["mechanic2"] = mechanic2
	else:
		main["mechanic"] = {}
	if kind == "boss":
		var phases: Array = GameData.BOSS_PHASES.keys()
		if diff.get("tower_single", false):
			phases.erase("summon")
		main["phase"] = str(phases[randi() % phases.size()])
		if not profile.is_empty() and phases.has(str(profile["phase"])):
			main["phase"] = str(profile["phase"])
			main["encounter"] = {"name": str(main["name"]), "hint": str(profile["hint"])}
	elif kind == "elite":
		_roll_affixes(main, 2 if diff.get("elite_chance_up", false) else 1)
	main["max_hp"] = main["hp"]
	monsters.append(main)

	var add_roll := randf() < 0.35
	var add_count := 1 + randi() % 2
	var add_mult := 0.6
	if (main.get("affixes", []) as Array).has("commander"):
		add_roll = true
		add_count = 2
		add_mult = 0.35
	if diff.get("tower_swarm", false):
		add_roll = true
		add_count = 2
	elif diff.get("tower_single", false):
		add_roll = false
	if add_roll:
		for i in add_count:
			monsters.append(_make_add(diff, floor_idx, add_mult, add_mult, kind == "elite"))
	return monsters


## Now and then (ENCOUNTER_CHANCE) a regular fight is one of the region's
## hand-designed groups instead of a random draw; [] when it isn't. The lead
## carries the encounter's name and hint for the fight log and arena.
func _designed_encounter(diff: Dictionary, floor_idx: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pool: Array = (GameData.ENCOUNTERS.get(str(diff.get("biome", "")), []) as Array).filter(func(e): return int(e["min_floor"]) <= floor_idx)
	var enc: Dictionary = {}
	if GameState.company_hunting() and not GameState.run.has("tower") and randf() < GameData.COMPANY_AMBUSH_CHANCE:
		enc = GameData.COMPANY_AMBUSH   # the Charter War: the exposed Company strikes back
	elif pool.is_empty() or randf() >= GameData.ENCOUNTER_CHANCE:
		return out
	else:
		enc = pool[randi() % pool.size()]
	for k in (enc["members"] as Array).size():
		var mem: Array = enc["members"][k]
		var m := gen_monster(diff, floor_idx, "combat")
		var nm := str(mem[0])
		m["name"] = nm
		m["hp"] = maxi(1, int(round(float(m["hp"]) * float(mem[1]))))
		m["dmg"] = maxi(1, int(round(float(m["dmg"]) * float(mem[2]))))
		m["max_hp"] = m["hp"]
		m["armor"] = maxf(float(GameData.MONSTER_ARMOR.get(nm, 0.0)), float(diff.get("tower_armor", 0.0)))
		m["status"] = str(diff.get("tower_status", GameData.MONSTER_STATUS.get(nm, "")))
		m["mechanic"] = {}
		m["ability"] = GameData.MONSTER_ABILITIES.get(nm, {})
		m["is_main"] = k == 0
		if k == 0:
			m["encounter"] = {"name": enc["name"], "hint": enc["hint"]}
		out.append(m)
	return out


## A weaker "combat"-tier foe fighting alongside an elite or boss.
## An elite's escorts come from its region's retinue (supports: wardens,
## healers, snipers, cursers) when there is one.
func _make_add(diff: Dictionary, floor_idx: int, hp_mult: float, dmg_mult: float, retinue: bool = false) -> Dictionary:
	var add := gen_monster(diff, floor_idx, "combat")
	var pool: Array = GameData.BIOMES.get(str(diff.get("biome", "")), {}).get("retinue", []) if retinue else []
	if not pool.is_empty():
		var nm := str(pool[randi() % pool.size()])
		add["name"] = nm
		add["armor"] = float(GameData.MONSTER_ARMOR.get(nm, 0.0))
		add["status"] = str(diff.get("tower_status", GameData.MONSTER_STATUS.get(nm, "")))
	add["hp"] = max(1, int(round(add["hp"] * hp_mult)))
	add["dmg"] = max(1, int(round(add["dmg"] * dmg_mult)))
	add["max_hp"] = add["hp"]
	add["mechanic"] = {}
	add["ability"] = GameData.MONSTER_ABILITIES.get(str(add["name"]), {})
	add["is_main"] = false
	return add
const AFFIX_HP_MULT := 0.85


## Gives an elite `count` GameData.ELITE_AFFIXES, never two that need the
## monster's one ability slot.
func _roll_affixes(m: Dictionary, count: int) -> void:
	var pool: Array = GameData.ELITE_AFFIXES.keys()
	pool.shuffle()
	var picked: Array = []
	for id in pool:
		if picked.size() >= count:
			break
		var a: Dictionary = GameData.ELITE_AFFIXES[id]
		if a.has("ability") and not (m["ability"] as Dictionary).is_empty():
			continue
		picked.append(id)
		if a.has("ability"):
			m["ability"] = a["ability"]
		if a.has("armor"):
			m["armor"] = maxf(float(m["armor"]), float(a["armor"]))
		if a.has("status"):
			m["status"] = a["status"]
		if a.get("hasted", false):
			m["dmg"] = maxi(1, int(round(float(m["dmg"]) * 0.55)))
		# The affix is the threat, not a free buff on top.
		m["hp"] = maxi(1, int(round(float(m["hp"]) * AFFIX_HP_MULT)))
	m["affixes"] = picked


## A line in this hero's voice for a moment (GameData.BARKS).
func bark_line(h: Hero, moment: String) -> String:
	var lines: Array = GameData.BARKS[GameData.hero_voice(h)][moment]
	return str(lines[randi() % lines.size()])


## A hero speaks up mid-fight (a speech bubble on the combat screen and a log
## line): at most once a turn and twice a fight per hero, `chance` of the time.
func _bark(state: Dictionary, h: Hero, moment: String, chance: float) -> void:
	var said: Dictionary = state.get_or_add("_bark_n", {})
	if not (state.get("_barks", []) as Array).is_empty() or int(said.get(h.id, 0)) >= 2 or randf() >= chance:
		return
	said[h.id] = int(said.get(h.id, 0)) + 1
	var text := bark_line(h, moment)
	state.get_or_add("_barks", []).append({"hero": h.id, "text": text})
	(state["log"] as Array).append("%s: \"%s\"" % [tr(str(h.name.split(" the ")[0])), tr(str(text))])


## A boss turns at half health (GameData.BOSS_PHASES), or at each of its
## profile's "phase_at" points.
func _check_phases(state: Dictionary) -> void:
	var monsters: Array = state["monsters"]
	for i in monsters.size():
		var m: Dictionary = monsters[i]
		var ph := str(m.get("phase", ""))
		if ph == "":
			continue
		var points := GameData.boss_phase_points(m)
		var done := int(m.get("_phases_done", 0))
		if done >= points.size() or float(m["hp"]) <= 0.0 or float(m["hp"]) > float(m["max_hp"]) * float(points[done]):
			continue
		m["_phases_done"] = done + 1
		m["_phased"] = true
		var info: Dictionary = GameData.BOSS_PHASES[ph]
		(state["log"] as Array).append(str(info["line"]) % m["name"])
		state["_phase_banner"] = [str(m["name"]), str(info["name"])]
		match ph:
			"fury":
				m["dmg"] = int(round(float(m["dmg"]) * 1.2))
				m["windup_bonus"] = 0.15
			"barrier":
				var ws: Dictionary = state["monster_shields"]
				ws[i] = float(ws.get(i, 0.0)) + round(float(m["max_hp"]) * 0.12)
			"summon":
				var calls: Array = GameData.BOSS_PROFILES.get(str(m["name"]).split(",")[0], {}).get("summons", [])
				for k in 2:
					var add := _make_add(state["diff"], int(state["floor_idx"]), 0.3, 0.3)
					if k < calls.size():
						var cn := str(calls[k])
						add["name"] = cn
						add["armor"] = float(GameData.MONSTER_ARMOR.get(cn, 0.0))
						add["status"] = str(GameData.MONSTER_STATUS.get(cn, ""))
						add["ability"] = GameData.MONSTER_ABILITIES.get(cn, {})
					monsters.append(add)


## The special moves a foe can telegraph besides attacking (see Combat's
## _start_round): bosses sweep and roar, healers mend, shielded foes ward,
## ranged foes snipe, elites and most species get one more by name.
func monster_kit(m: Dictionary) -> Array:
	var name := str(m["name"])
	var ab := str(m.get("ability", {}).get("kind", ""))
	var tier := str(m.get("tier", "combat"))
	if tier == "boss":
		return (GameData.BOSS_PROFILES.get(name.split(",")[0], {}).get("kit", ["sweep", "roar"]) as Array).duplicate()
	var kit: Array = (GameData.MONSTER_KIT.get(name, []) as Array).duplicate()
	if not kit.is_empty():
		if tier == "elite" and not kit.has("roar"):
			kit.append("roar")
		return kit
	if ab == "healer":
		kit.append("mend")
	if ab == "shielded":
		kit.append("ward")
	if GameData.RANGED_FOE_WORDS.any(func(w): return name.contains(w)):
		kit.append("snipe")
	if tier == "elite":
		kit.append(["sweep", "snipe", "curse"][absi(hash(name)) % 3])
	if (m.get("affixes", []) as Array).has("commander"):
		kit.append("roar")
	if kit.is_empty():
		var k: int = absi(hash(name)) % 4
		if k < 3:
			kit.append(["snipe", "curse", "sweep"][k])
	return kit

