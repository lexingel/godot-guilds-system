extends Node
## Pure stat/combat functions — ported from guild-system.html's heroSkillTotal/
## maxHp/dmgOf/engageCombat family. Reads GameState's relics/items directly
## (autoloads can reference each other by name), same as the JS version reads
## the shared `state` global, but every function here still takes its actual
## subject (hero/party) as a parameter rather than reaching for ambient state.
##
## Guild Management bonuses (tactical_bonus, crystal_yield_bonus, has_cap
## gates, etc.) are read straight from GameState rather than duplicated here.
## Elite encounters, Hardcore Mode, and the Champion system are all live —
## `kind` is "combat"/"elite"/"boss".

const RARITY_NOUNS := ["Sigil", "Charm", "Shard", "Idol", "Emblem"]


func hero_skill_total(h: Hero, kind: String) -> float:
	var s := 0.0
	for n in GameData.tier1_for_role(h.cls_id):
		if n["kind"] == kind and h.skills.get(n["id"], false):
			s += n["value"]
	for summary in GameData.hero_tree_summaries(h):
		var tree_kind: String = summary["kind"]
		for n in GameData.KIND_SKILL_PACKAGE.get(tree_kind, []):
			if n["kind"] == kind and h.skills.get(GameData.skill_storage_key(tree_kind, n["id"]), false):
				s += n["value"]
				if n.has("combo_kind") and GameState.party_has_other_kind_capstone(h.id, str(n["combo_kind"])):
					s += float(n.get("combo_bonus", 0.0))
		# A learned keystone's drawback is a plain flat stat.
		var ks := GameData.keystone_node(tree_kind)
		if not ks.is_empty() and ks["kind"] == kind and h.skills.get(GameData.skill_storage_key(tree_kind, "keystone"), false):
			s += float(ks["value"])
	s += GameState.party_resonance_bonus(kind)
	s += GameState.party_eclectic_bonus()
	if h.innate_kind == kind:
		s += h.innate_value
	# Same one-stage-back retention as the tree above — the innate bonus
	# from the class a hero just evolved out of doesn't just vanish either.
	if h.prior_innate_kind == kind:
		s += h.prior_innate_value
	s += hero_item_total(h, kind)
	if GameData.TRAIT_TABLE.has(h.trait_name):
		s += GameData.TRAIT_TABLE[h.trait_name].get(kind, 0.0)
	for scar in h.scars:
		if GameData.SCAR_TABLE.has(scar):
			s += GameData.SCAR_TABLE[scar].get(kind, 0.0)
	for tid in h.earned_traits:
		var t := GameData.find_earned_trait(tid)
		if t.get("kind", "") == kind:
			s += float(t["value"])
	if GameState.active_incense.get("kind", "") == kind:
		s += float(GameState.active_incense["value"])
	return s


func max_hp(h: Hero) -> int:
	return round(h.base_hp * (1.0 + hero_skill_total(h, "hp_pct")))


func dmg_of(h: Hero) -> int:
	return round(h.base_dmg * (1.0 + hero_skill_total(h, "dmg_pct")))


## Turn-order speed — determines where a hero falls in a round's turn order
## (see _compute_turn_order). base_spd is fixed at generation by role/rank and
## never scales with level, unlike max_hp/dmg_of — only skills/items/traits
## that grant speed_pct move it, so it stays a build choice rather than
## something that just goes up automatically.
func spd_of(h: Hero) -> float:
	return h.base_spd * (1.0 + hero_skill_total(h, "speed_pct"))


func power_of(h: Hero) -> int:
	return dmg_of(h) * 2 + round(max_hp(h) / 3.0)


## The power a party should bring to a rift: its difficulty's rec_power
## (Endless = cycle 0), nudged up by a mapped rift's rank modifiers. The
## difficulty curve was tuned against this ratio — see MONSTER_FLOOR_SCALE.
func recommended_power(diff_id: String, endless: bool, rift_rank: String = "") -> int:
	var diff: Dictionary = endless_diff_for_cycle(0) if endless else GameData.DIFFICULTIES[0]
	if not endless:
		for d in GameData.DIFFICULTIES:
			if d["id"] == diff_id:
				diff = d
	var mods: Dictionary = GameData.RIFT_RANK_MODIFIERS.get(rift_rank, {})
	return int(round(float(diff["rec_power"]) * sqrt(float(mods.get("monster_hp_mult", 1.0)) * float(mods.get("monster_dmg_mult", 1.0)))))


## Summed power_of for a party (the Champion included by the caller).
func party_power(party: Array) -> int:
	var total := 0
	for h in party:
		total += power_of(h)
	return total


func xp_to_next(level: int) -> int:
	return 40 + (level - 1) * 25


func gain_xp(h: Hero, amount: int) -> void:
	h.xp += amount
	while h.level < 10 and h.xp >= xp_to_next(h.level):
		h.xp -= xp_to_next(h.level)
		h.level += 1
		h.base_hp = round(h.base_hp * 1.08)
		h.base_dmg = round(h.base_dmg * 1.08)
		h.skill_points += 1


## Negative values (traits like Frail, scars, drawbacks) read as a penalty —
## "-15% HP", "+8% hazard severity" — never "+-15%".
func describe_skill(kind: String, value: float) -> String:
	var pct: float = round(absf(value) * 100)
	var up := "+" if value >= 0.0 else "-"
	var down := "-" if value >= 0.0 else "+"
	match kind:
		"dmg_pct": return "%s%d%% damage" % [up, pct]
		"hp_pct": return "%s%d%% HP" % [up, pct]
		"first_round_pct": return "%s%d%% first-strike damage" % [up, pct]
		"escalate_pct": return "%s%d%% damage per round (stacking)" % [up, pct]
		"mend_pct": return ("Mends %d%% of the party's HP pool each round" if value >= 0.0 else "-%d%% party mending per round") % pct
		"hazard_guard_pct": return "%s%d%% hazard severity" % [down, pct]
		"dodge_pct": return ("%d%% chance to block a retaliation" if value >= 0.0 else "-%d%% chance to block a retaliation") % pct
		"speed_pct": return "%s%d%% turn speed" % [up, pct]
		"wipe_guard": return ("Once per rift, survive a wipe at %d%% HP" if value >= 0.0 else "-%d%% HP on a survived wipe") % pct
		"boss_alpha_strike": return "Opens every Boss fight with a free strike"
		_: return ""


func party_skill_total(party: Array[Hero], kind: String) -> float:
	var s := 0.0
	for h in party:
		s += hero_skill_total(h, kind)
	return s


func affinity_bonus(party: Array[Hero]) -> float:
	var equipped_types := {}
	for r in equipped_relics():
		equipped_types[r.type] = true
	var matched := {}
	for h in party:
		if h.type != "" and equipped_types.has(h.type):
			matched[h.type] = true
	return matched.size() * 0.03


func domain_for_type(type: String) -> String:
	var home: String = GameData.TYPE_DOMAIN[type]
	if randf() < 0.6:
		return home
	var others: Array = GameData.TYPE_DOMAIN.values().filter(func(d): return d != home)
	return others[randi() % others.size()]


## Attack-only elemental multiplier: 1.3 if attacker_type is strong_vs
## defender_type, 0.8 if weak_vs, 1.0 otherwise (including either side being
## untyped/"" — combat kinds with no type, e.g. no hero picked yet, just no-op).
func type_matchup_mult(attacker_type: String, defender_type: String) -> float:
	if attacker_type == "" or defender_type == "" or not GameData.TYPE_MATCHUPS.has(attacker_type):
		return 1.0
	var matchup: Dictionary = GameData.TYPE_MATCHUPS[attacker_type]
	if matchup["strong_vs"].has(defender_type):
		return 1.3
	if matchup["weak_vs"].has(defender_type):
		return 0.8
	return 1.0


## Weighted retaliation-target pick: front row weight 3, back row weight 1
## (a bias, not a hard block — an all-back-row candidates array just reduces
## to a uniform roll among them, no special-casing needed).
func weighted_formation_target(candidates: Array[Hero]) -> Hero:
	var total := 0.0
	for h in candidates:
		total += 3.0 if h.formation != "back" else 1.0
	var roll := randf() * total
	for h in candidates:
		var w: float = 3.0 if h.formation != "back" else 1.0
		if roll < w:
			return h
		roll -= w
	return candidates[candidates.size() - 1]


func weighted_rarity() -> String:
	var bonus := drop_rate_bonus()
	var weights: Array[float] = []
	var total := 0.0
	for r in GameData.RARITIES:
		var w: float = r["weight"] if r["id"] == "common" else r["weight"] * (1.0 + bonus * 4.0)
		weights.append(w)
		total += w
	var roll := randf() * total
	for i in GameData.RARITIES.size():
		if roll < weights[i]:
			return GameData.RARITIES[i]["id"]
		roll -= weights[i]
	return "common"


func weighted_rank() -> String:
	var total := 0
	for r in GameData.RANKS:
		total += r["weight"]
	var roll := randi() % total
	for r in GameData.RANKS:
		if roll < r["weight"]:
			return r["id"]
		roll -= r["weight"]
	return "F"


func weighted_rift_rank() -> String:
	var total := 0
	for r in GameData.RIFT_RANKS:
		total += int(r["weight"])
	var roll := randi() % total
	for r in GameData.RIFT_RANKS:
		if roll < int(r["weight"]):
			return r["id"]
		roll -= int(r["weight"])
	return "F"


func pick_trait_name(role: String) -> String:
	var r := randf()
	if r < 0.22:
		return GameData.NEG_TRAITS[randi() % GameData.NEG_TRAITS.size()]
	if r < 0.50:
		return GameData.POS_TRAITS[randi() % GameData.POS_TRAITS.size()]
	if r < 0.62:
		return GameData.ROLE_TRAITS[role]
	return ""


## Uniform pick from SCAR_POOL excluding whatever the hero already has —
## returns "" if every entry is already held (can't happen at the cap of 2
## against a 5-entry pool, but keeps this safe regardless).
func pick_scar_name(existing: Array[String]) -> String:
	var choices: Array = GameData.SCAR_POOL.filter(func(s): return not existing.has(s))
	if choices.is_empty():
		return ""
	return str(choices[randi() % choices.size()])


const HERO_INNATE_MULT := 0.6


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
	h.name = "%s the %s" % [GameData.FIRST_NAMES[randi() % GameData.FIRST_NAMES.size()], cls["name"]]
	h.cls_id = cls["role"]
	h.pool_id = cls["id"]
	h.type = cls["type"]
	h.flavor = cls["flavor"]
	h.rank = rank["id"]
	h.innate_kind = cls["kind"]
	h.innate_value = hero_innate_value(cls, rank_idx)
	h.level = level_hint
	var s := 1.0 + 0.08 * (level_hint - 1)
	h.base_hp = round(role_cls["base_hp"] * cls["hp_ratio"] * rank["mult"] * s)
	h.base_dmg = round(role_cls["base_dmg"] * cls["dmg_ratio"] * rank["mult"] * s)
	h.base_spd = round(float(role_cls["base_spd"]) * float(rank["mult"]))
	h.trait_name = pick_trait_name(cls["role"])
	h.formation = str(GameData.ROLE_POSITION.get(cls["role"], {}).get("row", "front"))
	h.hp = max_hp(h)
	return h


## A Champion is a one-run guest fighter at full innate strength (no
## HERO_INNATE_MULT discount, unlike a recruited hero) and no skill tree —
## it has no `cls_id`, so `hero_skill_total`'s CLASS_SKILLS lookup naturally
## contributes nothing for it, matching the HTML version's clsId-less champ.
func generate_champion() -> Hero:
	var rank_id := weighted_rank()
	var rank := GameData.find_rank(rank_id)
	var rank_idx := GameData.rank_index(rank_id)
	var pool: Array = GameData.CLASS_POOL.filter(func(c): return c["rank"] == rank_id)
	var cls: Dictionary = pool[randi() % pool.size()]
	var champ := Hero.new()
	champ.id = "champ" + str(GameState.next_id)
	GameState.next_id += 1
	champ.name = cls["name"]
	champ.is_champion = true
	champ.pool_id = cls["id"]
	champ.rank = rank_id
	champ.type = cls["type"]
	champ.innate_kind = cls["kind"]
	champ.innate_value = innate_value_for(cls, rank_idx)
	champ.flavor = cls["flavor"]
	champ.level = 1
	champ.base_hp = int(round(30.0 * float(cls["hp_ratio"]) * float(rank["mult"])))
	champ.base_dmg = int(round(8.0 * float(cls["dmg_ratio"]) * float(rank["mult"])))
	var champ_role_cls := GameData.find_role(str(cls["role"]))
	champ.base_spd = int(round(float(champ_role_cls["base_spd"]) * float(rank["mult"])))
	champ.formation = str(GameData.ROLE_POSITION.get(str(cls["role"]), {}).get("row", "front"))
	champ.hp = max_hp(champ)
	return champ


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
	var has_special := randf() < 0.4
	var r := Relic.new()
	r.id = "rl" + str(GameState.next_id)
	GameState.next_id += 1
	r.name = "%s %s" % [type, noun]
	r.type = type
	r.rarity = rarity["id"]
	r.dmg = round((2.0 if has_special else 3.0) * rarity["mult"])
	r.hp = round((6.0 if has_special else 9.0) * rarity["mult"])
	if has_special:
		var domain := domain_for_type(type)
		var pool: Array = GameData.RELIC_SPECIALS.filter(func(x): return x["domain"] == domain)
		var s: Dictionary = pool[randi() % pool.size()]
		r.special_kind = s["kind"]
		r.special_value = snappedf(s["value"] * rarity["mult"], 0.001)
		r.special_label = s["label"]
	return r


## A fixed pick from GameData.UNIQUE_RELICS — no rarity-mult scaling, the
## effect/value/drawback are exactly as authored. "Twin Embers" is the one
## entry whose own effect is a normal rollable-style special (escalate_pct)
## rather than a bespoke mechanic, so it reuses special_kind/special_value
## instead of `effect` — Combat.resolve_round only dispatches on unique_id
## for the entries that actually need bespoke behavior.
func gen_unique_relic() -> Relic:
	var def: Dictionary = GameData.UNIQUE_RELICS[randi() % GameData.UNIQUE_RELICS.size()]
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
		r.special_kind = str(def["special_kind"])
		r.special_value = float(def["special_value"])
		r.special_label = str(def["desc"])
	if str(def.get("drawback_kind", "")) != "":
		r.drawback_kind = str(def["drawback_kind"])
		r.drawback_value = float(def["drawback_value"])
		r.drawback_label = str(def["drawback_label"])
	return r


## `category_override` — see gen_relic's type_override for why: Crafting Hall
## recipes keep a player's chosen equip-slot category intact across a craft.
## `rank` is the item's rift rank (see GameData.ITEM_RANK_MULT); "" means
## "wherever the party is right now" (GameState.loot_rank).
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
	var implicit: Dictionary = GameData.ITEM_BASE_IMPLICIT[noun]
	it.implicit_kind = str(implicit["kind"])
	it.implicit_value = snappedf(float(implicit["value"]) * rank_mult, 0.001)
	if rarity_id == "epic":
		var affix: Dictionary = GameData.ITEM_COND_AFFIXES[randi() % GameData.ITEM_COND_AFFIXES.size()].duplicate(true)
		affix["value"] = snappedf(float(affix["value"]) * roll.call(), 0.001)
		it.effects = [affix]

	var prefixes: Array = GameData.ITEM_AFFIX_PREFIX[it.kind]
	var name := "%s %s" % [str(prefixes[randi() % prefixes.size()]), noun]
	if it.secondary_kind != "":
		var suffixes: Array = GameData.ITEM_AFFIX_SUFFIX[it.secondary_kind]
		name += " %s" % str(suffixes[randi() % suffixes.size()])
	it.name = name
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
	return it


## Returns {"loot_type": "item"|"relic", "obj": Item|Relic}
func gen_loot(rarity_id: String) -> Dictionary:
	if randf() < 0.5:
		return {"loot_type": "item", "obj": gen_item(rarity_id)}
	return {"loot_type": "relic", "obj": gen_relic(rarity_id)}


func endless_diff_for_cycle(cycle: int) -> Dictionary:
	var mult := 1.0 + cycle * ENDLESS_CYCLE_GROWTH
	var base := GameData.ENDLESS_BASE
	return {
		"id": "endless", "name": "Endless Rift", "floors": 6, "power": "Extreme",
		"monster_hp": int(round(base["monster_hp"] * mult)), "monster_dmg": int(round(base["monster_dmg"] * mult)),
		"coin": [int(round(base["coin"][0] * mult)), int(round(base["coin"][1] * mult))],
		"crystal": [int(round(base["crystal"][0] * mult)), int(round(base["crystal"][1] * mult))],
		"token_base": int(round(base["token_base"] * mult)), "detector_chance": base["detector_chance"],
		"rec_power": int(round(base["rec_power"] * mult)),
	}


## Branching rift path: first layer forced combat, last forced boss, middle
## layers each offer 2 different node-type options (a fork the player picks
## between), with a guarantee at least one middle layer includes "elite".
func build_layers(diff: Dictionary) -> Array:
	var layers: Array = [{"options": ["combat"]}]
	var mid_count: int = int(diff["floors"]) - 2
	var pool := ["combat", "combat", "shop", "hazard", "elite"]
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
const ENDLESS_CYCLE_GROWTH := 0.5


func gen_monster(diff: Dictionary, floor_idx: int, kind: String) -> Dictionary:
	var scale := 1.0 + floor_idx * MONSTER_FLOOR_SCALE
	var hp_mult := BOSS_HP_MULT if kind == "boss" else (ELITE_HP_MULT if kind == "elite" else 1.0)
	var dmg_mult := BOSS_DMG_MULT if kind == "boss" else (ELITE_DMG_MULT if kind == "elite" else 1.0)
	var hp: int = round(diff["monster_hp"] * scale * hp_mult)
	var dmg: int = round(diff["monster_dmg"] * scale * dmg_mult)
	var name: String
	if kind == "boss":
		name = "%s, %s Warden" % [GameData.BOSS_NAMES[randi() % GameData.BOSS_NAMES.size()], diff["name"].split(" ")[0]]
	elif kind == "elite":
		name = GameData.ELITE_NAMES[randi() % GameData.ELITE_NAMES.size()]
	else:
		name = GameData.MONSTER_NAMES[randi() % GameData.MONSTER_NAMES.size()]
	return {"name": name, "hp": hp, "dmg": dmg, "spd": 9 + randi() % 4}


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
	if kind == "combat":
		var count := 1 + randi() % 3
		for i in count:
			var m := gen_monster(diff, floor_idx, "combat")
			m["hp"] = max(1, int(round(float(m["hp"]) / float(count))))
			m["dmg"] = max(1, int(round(float(m["dmg"]) / float(count))))
			m["max_hp"] = m["hp"]
			m["mechanic"] = {}
			m["ability"] = GameData.MONSTER_ABILITIES.get(str(m["name"]), {})
			m["is_main"] = i == 0
			m["type"] = GameData.RELIC_TYPES[randi() % GameData.RELIC_TYPES.size()]
			monsters.append(m)
		return monsters

	var main := gen_monster(diff, floor_idx, kind)
	main["is_main"] = true
	main["ability"] = {}
	if kind == "boss":
		var mechanic: Dictionary = GameData.BOSS_MECHANICS[randi() % GameData.BOSS_MECHANICS.size()]
		if mechanic["id"] == "frenzied":
			main["dmg"] = int(round(main["dmg"] * 1.25))
		main["mechanic"] = mechanic
		# SS-rank-and-above mapped rifts roll a second, distinct mechanic
		# alongside the first — every consumption site below (fight-start log,
		# describe_incoming, the regen/retaliation loops, Main.gd's badge) reads
		# "mechanic2" via .get() with an empty-dict default, so this is additive
		# and doesn't touch the normal single-mechanic path at all.
		if bool(diff.get("boss_double_mechanic", false)):
			var pool: Array = GameData.BOSS_MECHANICS.filter(func(bm): return bm["id"] != mechanic["id"])
			var mechanic2: Dictionary = pool[randi() % pool.size()]
			if mechanic2["id"] == "frenzied":
				main["dmg"] = int(round(main["dmg"] * 1.25))
			main["mechanic2"] = mechanic2
	else:
		main["mechanic"] = {}
	main["max_hp"] = main["hp"]
	main["type"] = GameData.RELIC_TYPES[randi() % GameData.RELIC_TYPES.size()]
	monsters.append(main)

	if randf() < 0.35:
		var add_count := 1 + randi() % 2
		for i in add_count:
			var add := gen_monster(diff, floor_idx, "combat")
			add["hp"] = max(1, int(round(add["hp"] * 0.6)))
			add["dmg"] = max(1, int(round(add["dmg"] * 0.6)))
			add["max_hp"] = add["hp"]
			add["mechanic"] = {}
			add["ability"] = GameData.MONSTER_ABILITIES.get(str(add["name"]), {})
			add["is_main"] = false
			add["type"] = GameData.RELIC_TYPES[randi() % GameData.RELIC_TYPES.size()]
			monsters.append(add)
	return monsters


## Guild Management node display strings — a match on node id since the HTML
## version used a per-node JS closure that doesn't translate to static data.
func describe_node_effect(node_id: String, level: int) -> String:
	match node_id:
		"roster": return "+%d hero slots" % (level * 2)
		"medical": return "-%d%% recovery time" % (level * 10)
		"drill": return "+%d%% HP/DMG in Rifts" % (level * 3)
		"trait": return ("Scrub traits · -%d%% skill respec cost" % (level * 10)) if level > 0 else "Locked"
		"crystal": return "+%d%% Crystal yield" % (level * 5)
		"stab": return "-%d%% hazard severity" % (level * 8)
		"seal": return "+%d%% Seal Tokens on a fast clear" % (level * 10)
		"energy": return "%d%% elite bonus-Crystal chance" % (level * 5)
		"broker": return "-%d%% Auction fees" % (level * 3)
		"scout": return ("HR filters unlocked (Lvl %d)" % level) if level > 0 else "Locked"
		"merchant": return "-%d%% shop prices" % (level * 5)
		"detector": return "+%d%% Rift Detector drops" % (level * 5)
		"relic":
			if level <= 0: return "Locked"
			return "%d starting Relic choices" % (4 if level >= 3 else (3 if level == 2 else 2))
		"theory": return "Damage dummy & synergy highlights unlocked" if level > 0 else "Locked"
		"recycle": return "Scrap unwanted Relics for Crystals" if level > 0 else "Locked"
		"cart": return "Reveals the rift path on entry" if level > 0 else "Locked"
		"vault": return "+%d equipped Relic slot" % level
		_: return ""


func guild_tier_info() -> Dictionary:
	var total := 0
	for v in GameState.upgrades.values():
		total += int(v)
	var idx := 0
	for i in GameData.GUILD_TIERS.size():
		if total >= int(GameData.GUILD_TIERS[i]["min"]):
			idx = i
	var next: Dictionary = GameData.GUILD_TIERS[idx + 1] if idx + 1 < GameData.GUILD_TIERS.size() else {}
	return {"name": GameData.GUILD_TIERS[idx]["name"], "total": total, "next": next}


func equipped_relics() -> Array[Relic]:
	var out: Array[Relic] = []
	for r in GameState.relics:
		if r.equipped:
			out.append(r)
	return out


func relic_dmg_bonus() -> int:
	var s := 0
	for r in equipped_relics():
		s += r.dmg
	return s


func relic_special_total(kind: String) -> float:
	var s := 0.0
	for r in equipped_relics():
		if r.special_kind == kind:
			s += r.special_value
	return s


## Mirrors relic_special_total but for a Legendary relic's drawback — only
## ever called for kinds relics already aggregate elsewhere (see
## GameData.UNIQUE_RELICS's own doc comment on that restriction).
func relic_drawback_total(kind: String) -> float:
	var s := 0.0
	for r in equipped_relics():
		if r.drawback_kind == kind:
			s += r.drawback_value
	return s


## True if an equipped relic's unique_id matches — used both to gate a
## unique relic's own bespoke effect and to check a combo partner.
func party_has_unique_relic(unique_id: String) -> bool:
	for r in equipped_relics():
		if r.unique_id == unique_id:
			return true
	return false


func hero_item_total(h: Hero, kind: String) -> float:
	var s := 0.0
	for it in GameState.items:
		if it.equipped_to == h.id:
			if it.kind == kind:
				s += it.value
			if it.secondary_kind == kind:
				s += it.secondary_value
			if it.tertiary_kind == kind:
				s += it.tertiary_value
			if it.implicit_kind == kind:
				s += it.implicit_value
			if it.socketed_kind == kind:
				s += it.socketed_value
			if it.drawback_kind == kind:
				s += it.drawback_value
	return s


## Every conditional-stat and trigger effect `h` carries, from any source.
## Flat always-on stats never live here — they stay in hero_skill_total. This
## is the one function new sources (subclass passives, keystones, earned
## traits, rolled item affixes) append to; combat never asks "does this hero
## own item X" again. Two entry shapes, both optionally gated by "cond" (see
## _cond_ok for the vocabulary):
##   stat:    {"kind": "dmg_pct"|"dodge_pct", "value": f, "scale"?: "missing_hp"}
##            — read per action by hero_cond_stat. Only those two kinds are read
##            anywhere yet (attack damage, dodge when targeted).
##   trigger: {"trigger": <_fire point>, "effect": <_apply_effect name>, "value": f}
## Each returned entry is tagged with "source" (a display name for log lines).
func hero_effects(h: Hero) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var passive := GameData.subclass_passive(h.pool_id)
	for e in passive.get("effects", []):
		out.append(_tagged(e, str(passive["name"]), str(passive["arch"])))
	var pos: Dictionary = GameData.ROLE_POSITION.get(GameData.hero_role(h), {})
	if not pos.is_empty() and h.formation == pos["row"]:
		for e in pos["effects"]:
			out.append(_tagged(e, str(pos["name"]), str(pos["arch"])))
	var learned_nodes: Array = []
	if h.skills.get("signature", false):
		learned_nodes.append(GameData.signature_node(h.cls_id))
	for summary in GameData.hero_tree_summaries(h):
		if h.skills.get(GameData.skill_storage_key(str(summary["kind"]), "keystone"), false):
			learned_nodes.append(GameData.keystone_node(str(summary["kind"])))
	for n in learned_nodes:
		for e in n["effects"]:
			out.append(_tagged(e, str(n["name"]), str(n["arch"])))
	for scar in h.scars:
		for e in GameData.SCAR_UPSIDES.get(scar, []):
			out.append(_tagged(e, scar))
	for tid in h.earned_traits:
		var t := GameData.find_earned_trait(tid)
		for e in t.get("effects", []):
			out.append(_tagged(e, str(t["name"]), str(t["arch"])))
	for it in GameState.items:
		if it.equipped_to != h.id:
			continue
		if it.unique_id != "":
			var udef := GameData.find_unique_item(it.unique_id)
			for e in udef.get("effects", []):
				out.append(_tagged(e, it.name, str(udef.get("arch", ""))))
		else:
			for e in it.effects:
				out.append(_tagged(e, it.name))
	return out


## `arch` only fills in an archetype the entry doesn't already carry itself.
func _tagged(e: Dictionary, source: String, arch: String = "") -> Dictionary:
	var tagged: Dictionary = e.duplicate()
	tagged["source"] = source
	if not tagged.has("arch") and arch != "":
		tagged["arch"] = arch
	return tagged


## Archetype -> count across everything shaping `h`'s build: their innate
## kind plus every hero_effects entry (passive, gear, keystones, earned
## traits). Display-only — the Roster's "Build" line.
func hero_archetype_counts(h: Hero) -> Dictionary:
	var counts := {}
	var innate_arch: String = GameData.KIND_ARCHETYPE.get(h.innate_kind, "")
	if innate_arch != "":
		counts[innate_arch] = 1
	for e in hero_effects(h):
		var a: String = str(e.get("arch", ""))
		if a != "":
			counts[a] = int(counts.get(a, 0)) + 1
	for tid in h.earned_traits:
		var t := GameData.find_earned_trait(tid)
		if t.has("kind"):
			counts[t["arch"]] = int(counts.get(t["arch"], 0)) + 1
	return counts


## Sum of `h`'s conditional stat effects of `kind` whose condition holds right
## now — layered on top of the flat hero_skill_total value at the moment of an
## action (attack/being targeted), never folded into max_hp/dmg_of/spd_of.
func hero_cond_stat(h: Hero, kind: String, state: Dictionary, ctx: Dictionary = {}) -> float:
	var s := 0.0
	for e in hero_effects(h):
		if e.get("kind", "") == kind and _cond_ok(e.get("cond", {}), h, state, ctx):
			var v := float(e["value"])
			match e.get("scale", ""):
				"missing_hp": v *= 1.0 - float(h.hp) / float(max_hp(h))
				"speed_above_10": v *= max(0.0, spd_of(h) - 10.0)
			s += v
	return s


## Every key in `cond` must hold. An unknown key fails closed (and errors) so a
## typo'd condition in data can't silently turn into an always-on bonus.
func _cond_ok(cond: Dictionary, h: Hero, state: Dictionary, ctx: Dictionary) -> bool:
	var round_num := int(state.get("round_num", 0))
	var hp_frac := float(h.hp) / float(max(1, max_hp(h)))
	for key in cond:
		var v = cond[key]
		var ok := false
		match key:
			"round_max": ok = round_num <= int(v)
			"round_min": ok = round_num >= int(v)
			"hp_above": ok = hp_frac > float(v)
			"hp_below": ok = hp_frac < float(v)
			"vs_boss": ok = bool(state.get("is_boss", false)) == bool(v)
			"formation": ok = h.formation == str(v)
			"target_below":
				var t: Dictionary = ctx.get("target", {})
				ok = not t.is_empty() and float(t["hp"]) / float(t["max_hp"]) < float(v)
			"ally_below":
				for a in state.get("party", []):
					if a != h and a.hp > 0 and float(a.hp) / float(max_hp(a)) < float(v):
						ok = true
			"acting_first":
				var order: Array = state.get("turn_order", [])
				ok = (not order.is_empty() and order[0]["type"] == "hero" and str(order[0]["id"]) == h.id) == bool(v)
			"acting_last":
				var order2: Array = state.get("turn_order", [])
				ok = (not order2.is_empty() and order2[-1]["type"] == "hero" and str(order2[-1]["id"]) == h.id) == bool(v)
			_:
				push_error("Unknown effect condition '%s'" % key)
		if not ok:
			return false
	return true


## Party-wide trigger effects whose strength lives on combat state (relic
## specials, surged mid-fight by abilities like counter_surge) — fired through
## the same _fire points as a hero's own effects, just with no condition.
func _party_effects(state: Dictionary) -> Array[Dictionary]:
	return [
		{"trigger": "evade_or_heavy", "effect": "counter_attack", "value": float(state["counter"]), "source": "counter"},
		{"trigger": "evade_or_heavy", "effect": "shave_cooldowns", "value": float(state["cooldown_shave"]), "source": "Chronometer"},
		{"trigger": "on_kill", "effect": "shield_lowest", "value": float(state["kill_shield"]), "source": "Lantern"},
	]


## Fires trigger point `trigger` for hero `h`: their own effects first, then the
## party-wide ones. Points: before_hit (ctx: target, dealt — may rewrite dealt),
## after_hit (ctx: target, dealt), on_kill, evade_or_heavy (ctx: attacker),
## party_mend, ally_targeted (fired on each OTHER living hero when a monster
## picks a target; ctx: target, attacker — may rewrite target). Add a point
## with one _fire call where content first needs it.
func _fire(trigger: String, state: Dictionary, h: Hero, ctx: Dictionary = {}) -> void:
	for e in hero_effects(h) + _party_effects(state):
		if e.get("trigger", "") == trigger and float(e["value"]) > 0.0 and _cond_ok(e.get("cond", {}), h, state, ctx):
			_apply_effect(str(e["effect"]), float(e["value"]), str(e["source"]), state, h, ctx)


func _apply_effect(effect: String, value: float, source: String, state: Dictionary, h: Hero, ctx: Dictionary) -> void:
	var log: Array[String] = state["log"]
	match effect:
		"execute_below":
			var t: Dictionary = ctx["target"]
			var after_hp: float = float(t["hp"]) - float(ctx["dealt"])
			if after_hp > 0.0 and float(t["max_hp"]) > 0.0 and after_hp / float(t["max_hp"]) < value:
				ctx["dealt"] = float(t["hp"])
				log.append("%s's %s finds the killing blow!" % [h.name, source])
				_proc(state, h, source)
		"lifesteal":
			var healed: int = max(1, int(round(float(ctx["dealt"]) * value)))
			h.hp = min(max_hp(h), h.hp + healed)
			log.append("%s drains %d HP from the strike." % [h.name, healed])
			_proc(state, h, "+%d HP" % healed)
		"shield_lowest":
			var shielded := _shield_lowest(state, value)
			if not shielded.is_empty():
				log.append("The %s shields %s for %d." % [source, shielded[0].name, int(round(shielded[1]))])
				_proc(state, shielded[0], "Shield +%d" % int(round(shielded[1])))
		"counter_attack":
			if randf() < value:
				var m: Dictionary = ctx["attacker"]
				var counter_dmg: int = max(1, int(round(float(state["team_dmg_base"]) * 0.3)))
				m["hp"] = max(0.0, float(m["hp"]) - counter_dmg)
				log.append("%s counters, striking %s for %d!" % [h.name, m["name"], counter_dmg])
				_proc(state, h, "Counter!")
		"shave_cooldowns":
			if randf() < value:
				for h2 in state["party"]:
					if h2.ability_cooldown > 0:
						h2.ability_cooldown -= 1
				log.append("The %s hums — abilities cool faster!" % source)
				_proc(state, h, "Cooldowns -1")
		"extra_turn":
			var used: Dictionary = state.get("_extra_turned", {})
			if not used.has(h.id) and h.hp > 0:
				used[h.id] = true
				state["_extra_turned"] = used
				state["turn_order"].insert(int(state["turn_idx"]), {"type": "hero", "id": h.id, "_spd": 0.0})
				log.append("%s's %s — they act again!" % [h.name, source])
				_proc(state, h, "Act again!")
		"intercept":
			var aimed: Hero = ctx["target"]
			if aimed != h and float(aimed.hp) / float(max_hp(aimed)) < 0.5 and randf() < value:
				ctx["target"] = h
				log.append("%s steps in front of the blow meant for %s!" % [h.name, aimed.name])
				_proc(state, h, "Intercept!")
		"weaken_attacker":
			var m2: Dictionary = ctx["attacker"]
			m2["dmg"] = float(m2["dmg"]) * (1.0 - value)
			log.append("%s's %s blunts %s's strength." % [h.name, source, m2["name"]])
			_proc(state, h, source)
		"mend_party":
			for a in state["party"]:
				if a.hp > 0:
					a.hp = min(max_hp(a), a.hp + max(1, int(round(max_hp(a) * value))))
			log.append("%s's %s mends the party." % [h.name, source])
			_proc(state, h, source)
		_:
			push_error("Unknown effect '%s'" % effect)


## Queues a floating label over `h` for the combat screen (state["_procs"],
## reset every turn by resolve_turn) — the log alone made builds invisible.
func _proc(state: Dictionary, h: Hero, text: String) -> void:
	state.get_or_add("_procs", []).append({"hero": h.id, "text": text})


## One effect entry (hero_effects shape) as a player-facing sentence, e.g.
## "+25% damage in round 1" or "On a kill: act again (once per round)".
func describe_effect(e: Dictionary) -> String:
	var pct := func(x) -> String: return "%d%%" % int(round(float(x) * 100.0))
	var v: float = float(e.get("value", 0.0))
	var text := ""
	if e.has("kind"):
		text = describe_skill(str(e["kind"]), v)
		match e.get("scale", ""):
			"missing_hp": text = "Up to %s as HP drops" % text.trim_prefix("+")
			"speed_above_10": text = "%s per Speed above 10" % text
	else:
		var what := ""
		match str(e.get("effect", "")):
			"execute_below": what = "finish foes left below %s HP" % pct.call(v)
			"lifesteal": what = "heal for %s of damage dealt" % pct.call(v)
			"shield_lowest": what = "shield the lowest-HP ally for %s of their max HP" % pct.call(v)
			"counter_attack": what = "%s chance to counter-attack" % pct.call(v)
			"shave_cooldowns": what = "%s chance to cool every Ability by 1 round" % pct.call(v)
			"extra_turn": what = "act again (once per round)"
			"intercept": what = "%s chance to take the hit for an ally below half HP" % pct.call(v)
			"weaken_attacker": what = "cut the attacker's damage by %s" % pct.call(v)
			"mend_party": what = "mend every ally for %s of their max HP" % pct.call(v)
		var when := ""
		match str(e.get("trigger", "")):
			"after_hit", "before_hit": when = "On hit"
			"on_kill": when = "On a kill"
			"evade_or_heavy": when = "When dodging or hit hard"
			"party_mend": when = "Whenever the party mends"
			"ally_targeted": when = "When an ally is attacked"
		text = "%s: %s" % [when, what]
	var conds: Array[String] = []
	for key in e.get("cond", {}):
		var c = e["cond"][key]
		match key:
			"round_max": conds.append("in round 1" if int(c) == 1 else "in the first %d rounds" % int(c))
			"round_min": conds.append("from round %d on" % int(c))
			"hp_above": conds.append("while above %s HP" % pct.call(c))
			"hp_below": conds.append("while below %s HP" % pct.call(c))
			"vs_boss": conds.append("against bosses" if bool(c) else "outside boss fights")
			"formation": conds.append("in the %s row" % str(c))
			"target_below": conds.append("vs foes below %s HP" % pct.call(c))
			"ally_below": conds.append("while an ally is below %s HP" % pct.call(c))
			"acting_first": conds.append("when acting first in the round")
			"acting_last": conds.append("when acting last in the round")
	if not conds.is_empty():
		text += " " + ", ".join(conds)
	return text


## Shields the lowest-HP living hero for `frac` of their max HP. Returns
## [hero, amount], or [] if nobody is standing.
func _shield_lowest(state: Dictionary, frac: float) -> Array:
	var lowest: Hero = null
	for hh in state["party"]:
		if hh.hp > 0 and (lowest == null or hh.hp < lowest.hp):
			lowest = hh
	if lowest == null:
		return []
	var shields: Dictionary = state["hero_shields"]
	var amt: float = max_hp(lowest) * frac
	shields[lowest.id] = float(shields.get(lowest.id, 0.0)) + amt
	return [lowest, amt]


func synergy_bonus() -> Dictionary:
	if not GameState.synergy_unlocked():
		return {}
	var counts := {}
	for r in equipped_relics():
		counts[r.type] = counts.get(r.type, 0) + 1
	for type in counts:
		if counts[type] >= 3:
			var s: Dictionary = GameData.SYNERGY_BONUS[type]
			return {"type": type, "kind": s["kind"], "value": s["value"], "label": s["label"]}
	return {}


func synergy_value_for(kind: String) -> float:
	var s := synergy_bonus()
	if s.has("kind") and s["kind"] == kind:
		return s["value"]
	return 0.0


func drop_rate_bonus() -> float:
	return relic_special_total("loot_rarity_pct") + synergy_value_for("loot_rarity_pct")


## Sums every HERO_BONDS entry of this `kind` whose both pool_ids are present
## among *living* party members — "living" matches the same standard
## sable_standard's mono_role_dmg already uses (not just "in the roster").
func bond_bonus_for(party: Array[Hero], kind: String) -> float:
	var living_pool_ids := {}
	for h in party:
		if h.hp > 0:
			living_pool_ids[h.pool_id] = true
	var total := 0.0
	for bond in GameData.HERO_BONDS:
		if bond["kind"] == kind and living_pool_ids.has(bond["a"]) and living_pool_ids.has(bond["b"]):
			total += float(bond["value"])
	# Grown bonds between specific heroes (GameState.bonds) — damage only.
	if kind == "dmg_pct":
		var grown := 0.0
		for i in party.size():
			for j in range(i + 1, party.size()):
				if party[i].hp > 0 and party[j].hp > 0:
					grown += GameData.BOND_DMG_PER_LEVEL * GameData.bond_level(GameState.bond_rifts(party[i].id, party[j].id))
		total += min(grown, GameData.BOND_DMG_CAP)
	return total


## Turn-based combat, per-hero and per-monster: a fight starts with
## start_combat() (one-time setup: monster roll via gen_monsters(), all
## party-wide bonus totals) and then advances one round per resolve_round()
## call. Each living hero has their own pending action (state["pending_actions"],
## hero_id -> {"action": "attack"/"ability"/"defend", "target": monster index,
## meaningful only for "attack"}, mutated between renders by
## GameState.set_hero_action without resolving anything) and, if their
## subclass qualifies, their own Ability cooldown (Hero.ability_cooldown,
## persistent on the hero — not reset per fight, ticks down once per node via
## GameState.tick_ability_cooldowns so it carries across shop/hazard nodes
## too). HP lives directly on each Hero throughout (no pooling), so win/
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
	var hardcore: bool = GameState.run.get("hardcore", false)
	var monsters := gen_monsters(diff, floor_idx, kind)

	var raw_sum := 0.0
	for h in party:
		raw_sum += dmg_of(h)
	var team_dmg_base: float = (raw_sum * GameState.tactical_bonus() + relic_dmg_bonus()) * (1.0 + synergy_value_for("dmg_pct") + affinity_bonus(party) + bond_bonus_for(party, "dmg_pct"))

	var first_round_bonus: float = (0.25 if GameState.has_cap("ops.drill") else 0.0) + party_skill_total(party, "first_round_pct") + relic_special_total("first_round_pct") + relic_drawback_total("first_round_pct") + synergy_value_for("first_round_pct") + bond_bonus_for(party, "first_round_pct")
	var escalate: float = party_skill_total(party, "escalate_pct") + relic_special_total("escalate_pct") + relic_drawback_total("escalate_pct") + synergy_value_for("escalate_pct")
	var mend: float = min(0.4, party_skill_total(party, "mend_pct") + relic_special_total("mend_pct") + relic_drawback_total("mend_pct") + synergy_value_for("mend_pct") + bond_bonus_for(party, "mend_pct"))
	var dodge: float = min(0.6, party_skill_total(party, "dodge_pct") + relic_special_total("dodge_pct") + relic_drawback_total("dodge_pct") + synergy_value_for("dodge_pct") + bond_bonus_for(party, "dodge_pct"))
	var wipe_guard: float = min(0.9, party_skill_total(party, "wipe_guard") + relic_special_total("wipe_guard") + relic_drawback_total("wipe_guard") + bond_bonus_for(party, "wipe_guard"))
	var counter: float = min(0.6, relic_special_total("counter_pct"))
	var cooldown_shave: float = min(0.75, relic_special_total("cooldown_shave_pct"))
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

	# An escort NPC quest, folded onto an ordinary "combat" node rather than a
	# whole new node kind — a chance for a fragile ally to tag along who
	# monster retaliation can occasionally hit instead of a hero (see
	# resolve_round's retaliation loop). {} = no escort this fight, the same
	# "empty dict = not present" contract mechanic/mechanic2 already use.
	var escort: Dictionary = {}
	if kind == "combat" and not GameState.run.get("is_riftbreak", false) and randf() < 0.25:
		var avg_hp := 0.0
		for h in party:
			avg_hp += max_hp(h)
		avg_hp /= float(max(1, party.size()))
		var ehp: int = max(15, int(round(avg_hp * 0.4)))
		var ename: String = GameData.ESCORT_NAMES[randi() % GameData.ESCORT_NAMES.size()]
		escort = {"name": ename, "hp": ehp, "max_hp": ehp}
		log.append("A %s tags along, hoping to survive the crossing." % ename)

	var state := {
		"party": party, "kind": kind, "diff": diff, "floor_idx": floor_idx, "hardcore": hardcore,
		"is_boss": is_boss, "is_elite": is_elite,
		"monsters": monsters, "background_idx": randi() % GameData.BATTLE_BACKGROUNDS.size(),
		"team_dmg_base": team_dmg_base, "raw_sum": raw_sum,
		"first_round_bonus": first_round_bonus, "escalate": escalate,
		"mend": mend, "dodge": dodge, "wipe_guard": wipe_guard, "wipe_guard_used": false, "counter": counter,
		"cooldown_shave": cooldown_shave, "kill_shield": kill_shield, "hero_shields": {},
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


const ABILITY_COOLDOWN_ROUNDS := 3


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
func monster_intent(state: Dictionary, i: int) -> Dictionary:
	var m: Dictionary = state["monsters"][i]
	if float(m["hp"]) <= 0:
		return {}
	var t := _find_party_hero(state["party"], str(state.get("intents", {}).get(i, "")))
	if t == null or t.hp <= 0:
		return {}
	var dmg := _monster_hit(m, int(state.get("round_num", 0)))
	return {"target": t, "dmg": int(dmg), "heavy": dmg >= float(max_hp(t)) * 0.25}


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
	for h in state["party"]:
		if h.hp > 0:
			entries.append({"type": "hero", "id": h.id, "_spd": spd_of(h) + randf() * 0.01})
	var monsters: Array = state["monsters"]
	for i in monsters.size():
		if float(monsters[i]["hp"]) > 0:
			entries.append({"type": "monster", "id": i, "_spd": float(monsters[i].get("spd", 10)) + randf() * 0.01})
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
			log.append("The Gambler's Coin shines bright — damage is doubled this round!")
		else:
			attack_mult *= 0.5
			log.append("The Gambler's Coin shows its dark face — damage is halved this round.")
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
	if party_has_unique_relic("sable_standard"):
		var roles_seen := {}
		for h3 in living:
			roles_seen[h3.cls_id] = true
		if roles_seen.size() == 1:
			attack_mult *= 1.25

	state["_attack_mult"] = attack_mult
	state["_escalate_mult"] = escalate_mult
	state["_defending"] = {}
	state["_extra_turned"] = {}

	for h in party:
		if h.ability_cooldown > 0:
			h.ability_cooldown -= 1

	var pending: Dictionary = state["pending_actions"]
	for h in living:
		var prev: Dictionary = pending.get(h.id, {})
		var target_idx: int = int(prev.get("target", 0))
		if target_idx < 0 or target_idx >= monsters.size() or float(monsters[target_idx]["hp"]) <= 0:
			target_idx = max(0, _first_living_monster_idx(monsters))
		pending[h.id] = {"action": str(prev.get("action", "attack")), "target": target_idx}

	state["turn_order"] = _compute_turn_order(state)
	var intents := {}
	if not living.is_empty():
		for mi in monsters.size():
			if float(monsters[mi]["hp"]) > 0:
				intents[mi] = weighted_formation_target(living).id
	state["intents"] = intents
	state["turn_idx"] = 0


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
	if action == "attack":
		var target_idx: int = int(act.get("target", 0))
		if target_idx < 0 or target_idx >= monsters.size() or float(monsters[target_idx]["hp"]) <= 0:
			target_idx = _first_living_monster_idx(monsters)
		if target_idx >= 0:
			var team_dmg_base: float = float(state["team_dmg_base"])
			var type_mult := type_matchup_mult(h.type, str(monsters[target_idx].get("type", "")))
			var formation_mult := 1.0 if bool(monsters[target_idx].get("is_main", true)) else 0.75
			var hit := {"target": monsters[target_idx]}
			hit["dealt"] = dmg_of(h) / raw_sum * team_dmg_base * attack_mult * type_mult * formation_mult * (1.0 + hero_cond_stat(h, "dmg_pct", state, hit))
			_fire("before_hit", state, h, hit)
			var dealt: float = hit["dealt"]
			var m_shields: Dictionary = state["monster_shields"]
			if dealt > 0.0 and float(m_shields.get(target_idx, 0.0)) > 0.0:
				var m_have: float = float(m_shields[target_idx])
				var m_absorbed: float = min(m_have, dealt)
				m_shields[target_idx] = m_have - m_absorbed
				dealt -= m_absorbed
				log.append("%s's ward absorbs %d damage." % [monsters[target_idx]["name"], int(round(m_absorbed))])
			monsters[target_idx]["hp"] = float(monsters[target_idx]["hp"]) - round(dealt)
			log.append("%s strikes %s for %d." % [h.name, monsters[target_idx]["name"], round(dealt)])
			var target_ability: Dictionary = monsters[target_idx].get("ability", {})
			if target_ability.get("kind") == "reflect" and dealt > 0.0:
				var reflected: int = max(1, int(round(dealt * float(target_ability["value"]))))
				h.hp = max(0, h.hp - reflected)
				log.append("%s's surface reflects %d damage back at %s." % [monsters[target_idx]["name"], reflected, h.name])
			hit["dealt"] = dealt
			_fire("after_hit", state, h, hit)
	elif action == "defend":
		state["_defending"][h.id] = true
	elif action == "ability" and h.ability_cooldown == 0:
		var team_dmg_base: float = float(state["team_dmg_base"])
		h.ability_cooldown = ABILITY_COOLDOWN_ROUNDS
		var ab: Dictionary = GameData.SUBCLASS_ABILITIES[h.pool_id]
		var eff: String = ab["effect"]
		var val: float = float(ab["value"])
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
				# Everyone but the caster — resetting its own cooldown too let
				# it recast every turn, keeping every Ability permanently ready.
				for h2 in party:
					if h2 != h:
						h2.ability_cooldown = 0
				log.append("Every ability is ready again.")
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
					h.ability_cooldown = max(0, h.ability_cooldown - GameData.ABILITY_AWAKENING_COOLDOWN_REDUCTION)
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
		_fire("on_kill", state, h)


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

	var escort: Dictionary = state.get("escort", {})
	if not escort.is_empty() and float(escort["hp"]) > 0.0 and randf() < 0.2:
		var escort_dmg: int = max(1, int(round(float(m["dmg"]) * 0.6)))
		escort["hp"] = max(0.0, float(escort["hp"]) - escort_dmg)
		log.append("The %s strikes %s for %d!" % [m["name"], str(escort["name"]), escort_dmg])
		if float(escort["hp"]) <= 0.0:
			log.append("%s doesn't survive the fight." % str(escort["name"]))
		return

	var alive_now: Array[Hero] = []
	alive_now.assign(party.filter(func(h): return h.hp > 0))
	if alive_now.is_empty():
		return
	# The target was rolled at round start (state["intents"]) so the combat
	# screen can show it; re-roll only if that hero has since dropped.
	var target: Hero = _find_party_hero(party, str(state.get("intents", {}).get(i, "")))
	if target == null or target.hp <= 0:
		target = weighted_formation_target(alive_now)
	var aim := {"target": target, "attacker": m}
	for ally in alive_now:
		if ally != target:
			_fire("ally_targeted", state, ally, aim)
			if aim["target"] != target:
				break
	target = aim["target"]
	var mech: Dictionary = m.get("mechanic", {})
	var mech2: Dictionary = m.get("mechanic2", {})
	var ability: Dictionary = m.get("ability", {})
	var back: float = _monster_hit(m, round_num)
	var warded: bool = (mech.get("id") == "warded" or mech2.get("id") == "warded") and round_num <= 2
	if state["_defending"].has(target.id):
		back *= 0.5
	var effective_dodge: float = float(state["dodge"]) + hero_cond_stat(target, "dodge_pct", state, {"attacker": m})
	var evaded := false
	if not warded and effective_dodge > 0.0 and randf() < effective_dodge:
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
			target.hp = max(0, target.hp - dealt_back)
			log.append("The %s hits %s for %d." % [m["name"], target.name, dealt_back])
			if ability.get("kind") == "poison" and target.hp > 0:
				state["hero_poison"][target.id] = {"rounds": 2, "value": float(ability["value"])}
				log.append("%s is poisoned!" % target.name)
			if ability.get("kind") == "drain" and dealt_back > 0:
				var drained: int = max(1, int(round(dealt_back * float(ability["value"]))))
				m["hp"] = min(float(m["max_hp"]), float(m["hp"]) + drained)
				log.append("%s drains %d HP from the blow." % [m["name"], drained])
			if target.hp <= 0:
				log.append("%s is knocked out!" % target.name)


## Passive round-cadence effects (monster regen/healer-heal, hero poison tick,
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

	for m in monsters:
		if float(m["hp"]) <= 0 or m.get("ability", {}).get("kind") != "healer":
			continue
		var lowest_idx := -1
		var lowest_ratio := 1.0
		for j in monsters.size():
			if monsters[j] == m or float(monsters[j]["hp"]) <= 0:
				continue
			var ratio: float = float(monsters[j]["hp"]) / float(monsters[j]["max_hp"])
			if ratio < 1.0 and ratio < lowest_ratio:
				lowest_ratio = ratio
				lowest_idx = j
		if lowest_idx >= 0:
			var heal_amt: float = round(float(monsters[lowest_idx]["max_hp"]) * float(m["ability"]["value"]))
			monsters[lowest_idx]["hp"] = min(float(monsters[lowest_idx]["max_hp"]), float(monsters[lowest_idx]["hp"]) + heal_amt)
			log.append("%s mends %s for %d." % [m["name"], monsters[lowest_idx]["name"], heal_amt])

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
	return _finish_combat(state, false, false)


## Ensures state["turn_order"]/state["turn_idx"] point at a valid upcoming
## turn — rolling a fresh round via _start_round if the previous one is
## exhausted — and returns that turn descriptor without resolving it. Lets a
## caller (Main.gd's _run_combat_turns) find out what's coming next, and
## whether it needs player input, before committing to resolve_turn. Has the
## same round-rollover side effects _start_round always has, so — like
## resolve_turn — only call this from an actual game action, never from a
## read-only render() pass (see Main.gd's own comment on this).
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
	var turn: Dictionary = peek_next_turn(state)
	var turn_idx: int = int(state["turn_idx"])
	state["turn_idx"] = turn_idx + 1

	if turn["type"] == "hero":
		var h := _find_party_hero(state["party"], str(turn["id"]))
		if h and h.hp > 0:
			_resolve_hero_action(state, h)
	else:
		var i: int = int(turn["id"])
		var monsters: Array = state["monsters"]
		if i < monsters.size() and float(monsters[i]["hp"]) > 0:
			_resolve_monster_action(state, i)

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
	var hardcore: bool = state["hardcore"]
	var full_loss := not won and not retreated
	if full_loss and hardcore:
		log.append("Your party is overwhelmed... and lost for good.")
	else:
		if full_loss:
			log.append("Your party is overwhelmed...")
		# Any hero knocked out mid-fight (hp hit 0 while the party kept
		# fighting and ultimately won, or before a retreat) still needs a
		# recovery timer — not just the whole-party-wiped case above, or
		# they'd sit at 0 HP forever, invisible to needs_recovery()/Medical Bay.
		var now := int(Time.get_unix_time_from_system() * 1000)
		for h in party:
			if h.hp <= 0 and h.downed_until <= 0:
				h.downed_until = now + GameState.recovery_ms()
				h.history["knockouts"] = int(h.history.get("knockouts", 0)) + 1
				# A freshly-knocked-out roster hero has a chance to pick up a
				# lasting scar, capped at 2 — champions are regenerated fresh
				# every seal_rift() and carry no persistent state worth scarring.
				if not h.is_champion and h.scars.size() < 2 and randf() < 0.5:
					var scar := pick_scar_name(h.scars)
					if scar != "":
						h.scars.append(scar)
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
		var reward_mult: float = (1.4 if is_elite else 1.0) * (1.5 if hardcore else 1.0)
		var depth_mult: float = 1.0 + floor_idx * 0.05
		result["coin"] = round(randf_range(diff["coin"][0], diff["coin"][1]) * reward_mult * depth_mult)
		result["crystal"] = round(randf_range(diff["crystal"][0], diff["crystal"][1]) * GameState.crystal_yield_bonus() * reward_mult * depth_mult)
		if is_elite:
			var bonus_crystal := 0
			for h in party:
				if randf() < GameState.energy_extract_chance():
					bonus_crystal += randi() % 4 + 2
			result["bonus_crystal"] = bonus_crystal
		var xp_gain: int = 30 if is_boss else (20 if is_elite else 12)
		for h in party:
			gain_xp(h, xp_gain)
		if not is_boss:
			var options := [gen_loot(weighted_rarity()), gen_loot(weighted_rarity())]
			if randf() < min(0.5, drop_rate_bonus() * 2.0):
				options.append(gen_loot(weighted_rarity()))
			result["reward_options"] = options
	return {"done": true, "result": result}
