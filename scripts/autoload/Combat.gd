extends Node
## Pure stat/combat functions — ported from guild-system.html's heroSkillTotal/
## maxHp/dmgOf/engageCombat family. Reads GameState's relics/items directly
## (autoloads can reference each other by name), same as the JS version reads
## the shared `state` global, but every function here still takes its actual
## subject (hero/party) as a parameter rather than reaching for ambient state.
##
## Vertical-slice simplification: every bonus that in the HTML version comes
## from the Guild Management upgrade tree (tacticalBonus, Vanguard Order,
## Crystal Amplifiers, Energy Extraction, Optimal Synergy's unlock gate,
## Hardcore Mode) is dropped or treated as its zero/default value — that
## whole system is explicitly deferred past this slice. Elite encounters and
## the Champion system are also deferred, so `kind` is just "combat"/"boss".

const RARITY_NOUNS := ["Sigil", "Charm", "Shard", "Idol", "Emblem"]


func hero_skill_total(h: Hero, kind: String) -> float:
	var s := 0.0
	var tree: Array = GameData.subclass_skill_tree(h.pool_id)
	for n in tree:
		if n["kind"] == kind and h.skills.get(n["id"], false):
			s += n["value"]
	if h.innate_kind == kind:
		s += h.innate_value
	s += hero_item_total(h, kind)
	if GameData.TRAIT_TABLE.has(h.trait_name):
		s += GameData.TRAIT_TABLE[h.trait_name].get(kind, 0.0)
	for scar in h.scars:
		if GameData.SCAR_TABLE.has(scar):
			s += GameData.SCAR_TABLE[scar].get(kind, 0.0)
	if GameState.active_incense.get("kind", "") == kind:
		s += float(GameState.active_incense["value"])
	return s


func max_hp(h: Hero) -> int:
	return round(h.base_hp * (1.0 + hero_skill_total(h, "hp_pct")))


func dmg_of(h: Hero) -> int:
	return round(h.base_dmg * (1.0 + hero_skill_total(h, "dmg_pct")))


func power_of(h: Hero) -> int:
	return dmg_of(h) * 2 + round(max_hp(h) / 3.0)


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


func describe_skill(kind: String, value: float) -> String:
	var pct: float = round(value * 100)
	match kind:
		"dmg_pct": return "+%d%% damage" % pct
		"hp_pct": return "+%d%% HP" % pct
		"first_round_pct": return "+%d%% first-strike damage" % pct
		"escalate_pct": return "+%d%% damage per round (stacking)" % pct
		"mend_pct": return "Mends %d%% of the party's HP pool each round" % pct
		"hazard_guard_pct": return "-%d%% hazard severity" % pct
		"dodge_pct": return "%d%% chance to block a retaliation" % pct
		"wipe_guard": return "Once per rift, survive a wipe at %d%% HP" % pct
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
	h.trait_name = pick_trait_name(cls["role"])
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
	champ.hp = max_hp(champ)
	return champ


func gen_relic(rarity_id: String) -> Relic:
	if rarity_id == "legendary":
		return gen_unique_relic()
	var type: String = GameData.RELIC_TYPES[randi() % GameData.RELIC_TYPES.size()]
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


func gen_item(rarity_id: String) -> Item:
	if rarity_id == "legendary":
		return gen_unique_item()
	var rarity := GameData.find_rarity(rarity_id)
	var category: String = GameData.ITEM_CATEGORIES[randi() % GameData.ITEM_CATEGORIES.size()]
	var kinds: Array = GameData.ITEM_CATEGORY_KINDS[category]
	var kind: String = kinds[randi() % kinds.size()]
	var value: float = snappedf(GameData.ITEM_KIND_BASE[kind] * rarity["mult"], 0.001)
	var nouns: Array = GameData.ITEM_NOUNS[category]
	var noun: String = nouns[randi() % nouns.size()]
	var it := Item.new()
	it.id = "it" + str(GameState.next_id)
	GameState.next_id += 1
	it.name = "%s %s" % [rarity["name"], noun]
	it.category = category
	it.rarity = rarity["id"]
	it.kind = kind
	it.value = value
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
	it.kind = ""
	it.value = 0.0
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
	var mult := 1.0 + cycle * 0.35
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


func gen_monster(diff: Dictionary, floor_idx: int, kind: String) -> Dictionary:
	var scale := 1.0 + floor_idx * 0.12
	var hp_mult := 1.8 if kind == "boss" else (1.45 if kind == "elite" else 1.0)
	var dmg_mult := 1.5 if kind == "boss" else (1.3 if kind == "elite" else 1.0)
	var hp: int = round(diff["monster_hp"] * scale * hp_mult)
	var dmg: int = round(diff["monster_dmg"] * scale * dmg_mult)
	var name: String
	if kind == "boss":
		name = "%s, %s Warden" % [GameData.BOSS_NAMES[randi() % GameData.BOSS_NAMES.size()], diff["name"].split(" ")[0]]
	elif kind == "elite":
		name = GameData.ELITE_NAMES[randi() % GameData.ELITE_NAMES.size()]
	else:
		name = GameData.MONSTER_NAMES[randi() % GameData.MONSTER_NAMES.size()]
	return {"name": name, "hp": hp, "dmg": dmg}


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
			if it.socketed_kind == kind:
				s += it.socketed_value
			if it.drawback_kind == kind:
				s += it.drawback_value
	return s


## True if `h` has the named Legendary item (by unique_id) equipped.
func hero_has_unique_item(h: Hero, unique_id: String) -> bool:
	for it in GameState.items:
		if it.equipped_to == h.id and it.unique_id == unique_id:
			return true
	return false


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
		monsters[0]["hp"] = float(monsters[0]["hp"]) - alpha
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

	return {
		"party": party, "kind": kind, "diff": diff, "floor_idx": floor_idx, "hardcore": hardcore,
		"is_boss": is_boss, "is_elite": is_elite,
		"monsters": monsters, "background_idx": randi() % GameData.BATTLE_BACKGROUNDS.size(),
		"team_dmg_base": team_dmg_base, "raw_sum": raw_sum,
		"first_round_bonus": first_round_bonus, "escalate": escalate,
		"mend": mend, "dodge": dodge, "wipe_guard": wipe_guard, "wipe_guard_used": false, "counter": counter,
		"cooldown_shave": cooldown_shave, "kill_shield": kill_shield, "hero_shields": {},
		"monster_shields": monster_shields, "hero_poison": {},
		"round_num": 0, "log": log,
		"pending_actions": pending_actions,
	}


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
	var next_round: int = int(state.get("round_num", 0)) + 1
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


## One round of an in-progress fight: applies every living hero's pending
## action from state["pending_actions"], then rolls each living monster's
## retaliation independently against a random living hero. Mutates `state` in
## place and returns {"done": bool, "result": Dictionary} — result is only
## populated once the fight ends (win/loss/retreat).
func resolve_round(state: Dictionary) -> Dictionary:
	var log: Array[String] = state["log"]
	var party: Array[Hero] = state["party"]
	var pending: Dictionary = state["pending_actions"]
	var monsters: Array = state["monsters"]

	var living: Array[Hero] = []
	living.assign(party.filter(func(h): return h.hp > 0))
	var monsters_hp_before: Array[float] = []
	for m in monsters:
		monsters_hp_before.append(float(m["hp"]))

	state["round_num"] = int(state["round_num"]) + 1
	var round_num: int = state["round_num"]
	var team_dmg_base: float = state["team_dmg_base"]
	var raw_sum: float = state["raw_sum"]
	var attack_mult: float = (1.0 + float(state["first_round_bonus"]) if round_num == 1 else 1.0) * (1.0 + float(state["escalate"]) * (round_num - 1))
	var escalate_mult: float = 1.0 + float(state["escalate"]) * (round_num - 1)

	# Legendary relic round-wide multipliers — rolled/computed fresh each
	# round (unlike team_dmg_base, these aren't meant to be permanent), then
	# folded into this round's attack_mult only.
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

	for h in party:
		if h.ability_cooldown > 0:
			h.ability_cooldown -= 1

	var defending := {}   # hero_id -> true, checked against each retaliation below
	for h in living:
		var act: Dictionary = pending.get(h.id, {"action": "attack", "target": 0})
		var action: String = str(act.get("action", "attack"))
		if action == "attack":
			var target_idx: int = int(act.get("target", 0))
			if target_idx < 0 or target_idx >= monsters.size() or float(monsters[target_idx]["hp"]) <= 0:
				target_idx = _first_living_monster_idx(monsters)
			if target_idx < 0:
				continue
			var type_mult := type_matchup_mult(h.type, str(monsters[target_idx].get("type", "")))
			var formation_mult := 1.0 if bool(monsters[target_idx].get("is_main", true)) else 0.75
			var dealt: float = dmg_of(h) / raw_sum * team_dmg_base * attack_mult * type_mult * formation_mult
			if hero_has_unique_item(h, "widows_edge"):
				var edge_def := GameData.find_unique_item("widows_edge")
				var after_hp: float = float(monsters[target_idx]["hp"]) - dealt
				var target_max: float = float(monsters[target_idx]["max_hp"])
				if after_hp > 0.0 and target_max > 0.0 and after_hp / target_max < float(edge_def["value"]):
					dealt = float(monsters[target_idx]["hp"])
					log.append("%s's Widow's Edge finds the killing blow!" % h.name)
			var m_shields: Dictionary = state["monster_shields"]
			if dealt > 0.0 and float(m_shields.get(target_idx, 0.0)) > 0.0:
				var m_have: float = float(m_shields[target_idx])
				var m_absorbed: float = min(m_have, dealt)
				m_shields[target_idx] = m_have - m_absorbed
				dealt -= m_absorbed
				log.append("%s's ward absorbs %d damage." % [monsters[target_idx]["name"], int(round(m_absorbed))])
			monsters[target_idx]["hp"] = float(monsters[target_idx]["hp"]) - dealt
			log.append("%s strikes %s for %d." % [h.name, monsters[target_idx]["name"], round(dealt)])
			if hero_has_unique_item(h, "bloodthirst_fang"):
				var fang_def := GameData.find_unique_item("bloodthirst_fang")
				var healed: int = max(1, int(round(dealt * float(fang_def["value"]))))
				h.hp = min(max_hp(h), h.hp + healed)
				log.append("%s drains %d HP from the strike." % [h.name, healed])
		elif action == "defend":
			defending[h.id] = true
		elif action == "ability" and h.ability_cooldown == 0:
			h.ability_cooldown = ABILITY_COOLDOWN_ROUNDS
			var ab: Dictionary = GameData.SUBCLASS_ABILITIES[h.pool_id]
			var eff: String = ab["effect"]
			var val: float = float(ab["value"])
			log.append("%s uses %s!" % [h.name, ab["name"]])
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
						monsters[idx]["hp"] = float(monsters[idx]["hp"]) - burst
						log.append("A burst lands on %s for %d!" % [monsters[idx]["name"], round(burst)])
				"cleave_burst":
					for m in monsters:
						if float(m["hp"]) > 0:
							var dealt2: float = team_dmg_base * escalate_mult * val
							m["hp"] = float(m["hp"]) - dealt2
					log.append("A wave of damage sweeps every foe.")
				"execute_burst":
					var idx2 := _lowest_hp_living_monster_idx(monsters)
					if idx2 >= 0:
						var missing_frac: float = 1.0 - float(monsters[idx2]["hp"]) / float(monsters[idx2]["max_hp"])
						var dealt3: float = team_dmg_base * val * (1.0 + missing_frac)
						monsters[idx2]["hp"] = float(monsters[idx2]["hp"]) - dealt3
						log.append("A finishing blow strikes %s for %d!" % [monsters[idx2]["name"], round(dealt3)])
				"shield_lowest":
					var alive_for_ability: Array[Hero] = living.filter(func(hh): return hh.hp > 0)
					if not alive_for_ability.is_empty():
						var lowest: Hero = alive_for_ability[0]
						for hh2 in alive_for_ability:
							if hh2.hp < lowest.hp:
								lowest = hh2
						var shields: Dictionary = state["hero_shields"]
						var amt: float = max_hp(lowest) * val
						shields[lowest.id] = float(shields.get(lowest.id, 0.0)) + amt
						log.append("%s is shielded for %d." % [lowest.name, int(round(amt))])
				"reset_cooldowns":
					for h2 in party:
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
						monsters[idx3]["hp"] = float(monsters[idx3]["hp"]) - burst2
						log.append("%s sacrifices %d HP for a burst on %s for %d!" % [h.name, self_cost, monsters[idx3]["name"], round(burst2)])

	if float(state["kill_shield"]) > 0.0:
		var got_kill := false
		for i in monsters.size():
			if monsters_hp_before[i] > 0.0 and float(monsters[i]["hp"]) <= 0.0:
				got_kill = true
		if got_kill:
			var alive_for_shield: Array[Hero] = living.filter(func(h): return h.hp > 0)
			if not alive_for_shield.is_empty():
				var lowest: Hero = alive_for_shield[0]
				for h2 in alive_for_shield:
					if h2.hp < lowest.hp:
						lowest = h2
				var shields: Dictionary = state["hero_shields"]
				var amt: float = max_hp(lowest) * float(state["kill_shield"])
				shields[lowest.id] = float(shields.get(lowest.id, 0.0)) + amt
				log.append("The Lantern grants %s a %d-point shield." % [lowest.name, int(round(amt))])

	var any_alive := false
	for m in monsters:
		if float(m["hp"]) > 0:
			any_alive = true
			break
	if not any_alive:
		log.append(("The %s falls!" % monsters[0]["name"]) if monsters.size() == 1 else "All foes defeated!")
		return _finish_combat(state, true, false)

	for m in monsters:
		var is_regen: bool = m.get("mechanic", {}).get("id") == "regen" or m.get("mechanic2", {}).get("id") == "regen"
		if float(m["hp"]) > 0 and is_regen:
			var regen_heal: float = round(float(m["max_hp"]) * 0.08)
			m["hp"] = min(float(m["max_hp"]), float(m["hp"]) + regen_heal)
			log.append("%s regenerates %d HP." % [m["name"], regen_heal])

	# "healer"-ability monsters mend the lowest-HP *other* living monster each
	# round they survive — same shape as the regen loop just above, but
	# targeting an ally instead of healing self.
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

	# Poison ticks on any hero still carrying it — refreshed (not stacked) by
	# a poison-ability monster's hit, see the retaliation loop above.
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

	if float(state["mend"]) > 0.0:
		var mended := false
		for h in living:
			if h.hp > 0 and h.hp < max_hp(h):
				var heal: int = max(1, int(round(max_hp(h) * float(state["mend"]))))
				h.hp = min(max_hp(h), h.hp + heal)
				mended = true
		if mended:
			log.append("The party mends its wounds.")
			var talisman_wearer: Hero = null
			for h4 in living:
				if hero_has_unique_item(h4, "oathbound_talisman"):
					talisman_wearer = h4
					break
			if talisman_wearer:
				var still_alive: Array[Hero] = living.filter(func(hh): return hh.hp > 0)
				if not still_alive.is_empty():
					var lowest_h: Hero = still_alive[0]
					for hh3 in still_alive:
						if hh3.hp < lowest_h.hp:
							lowest_h = hh3
					var talisman_def := GameData.find_unique_item("oathbound_talisman")
					var shields2: Dictionary = state["hero_shields"]
					var shield_amt: float = max_hp(lowest_h) * float(talisman_def["value"])
					shields2[lowest_h.id] = float(shields2.get(lowest_h.id, 0.0)) + shield_amt
					log.append("The Oathbound Talisman shields %s for %d." % [lowest_h.name, int(round(shield_amt))])

	if living.filter(func(h): return h.hp > 0).is_empty():
		return _finish_combat(state, false, false)

	for m in monsters:
		if float(m["hp"]) <= 0:
			continue
		var alive_now: Array[Hero] = []
		alive_now.assign(party.filter(func(h): return h.hp > 0))
		if alive_now.is_empty():
			break
		var target: Hero = weighted_formation_target(alive_now)
		var mech: Dictionary = m.get("mechanic", {})
		var mech2: Dictionary = m.get("mechanic2", {})
		var ability: Dictionary = m.get("ability", {})
		var back: float = float(m["dmg"])
		var warded: bool = (mech.get("id") == "warded" or mech2.get("id") == "warded") and round_num <= 2
		if (mech.get("id") == "enrage" or mech2.get("id") == "enrage") and round_num > GameData.BOSS_ENRAGE_ROUND:
			back = round(back * (1.0 + 0.15 * (round_num - GameData.BOSS_ENRAGE_ROUND)))
		if ability.get("kind") == "frenzy" and float(m["hp"]) / float(m["max_hp"]) <= 0.3:
			back = round(back * (1.0 + float(ability["value"])))
		if defending.has(target.id):
			back *= 0.5
		var effective_dodge: float = float(state["dodge"])
		if hero_has_unique_item(target, "last_stand_plate"):
			var plate_def := GameData.find_unique_item("last_stand_plate")
			var missing_frac2: float = 1.0 - float(target.hp) / float(max_hp(target))
			effective_dodge += float(plate_def["value"]) * missing_frac2
		var evaded := false
		if not warded and effective_dodge > 0.0 and randf() < effective_dodge:
			log.append("%s evades %s's retaliation!" % [target.name, m["name"]])
			evaded = true
		var heavy_hit: bool = back >= float(max_hp(target)) * 0.25
		if evaded:
			back = 0.0
		if (evaded or heavy_hit) and float(state["counter"]) > 0.0 and randf() < float(state["counter"]):
			var counter_dmg: int = max(1, int(round(float(state["team_dmg_base"]) * 0.3)))
			m["hp"] = max(0.0, float(m["hp"]) - counter_dmg)
			log.append("%s counters, striking %s for %d!" % [target.name, m["name"], counter_dmg])
		if (evaded or heavy_hit) and float(state["cooldown_shave"]) > 0.0 and randf() < float(state["cooldown_shave"]):
			for h2 in party:
				if h2.ability_cooldown > 0:
					h2.ability_cooldown -= 1
			log.append("The Chronometer hums — abilities cool faster!")
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
				if target.hp <= 0:
					log.append("%s is knocked out!" % target.name)

	var final_living: Array[Hero] = []
	final_living.assign(party.filter(func(h): return h.hp > 0))
	if final_living.is_empty():
		return _finish_combat(state, false, false)
	if round_num >= 30:
		return _finish_combat(state, false, false)

	for h in final_living:
		var prev: Dictionary = pending.get(h.id, {})
		var target_idx: int = int(prev.get("target", 0))
		if target_idx < 0 or target_idx >= monsters.size() or float(monsters[target_idx]["hp"]) <= 0:
			target_idx = max(0, _first_living_monster_idx(monsters))
		pending[h.id] = {"action": "attack", "target": target_idx}

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
