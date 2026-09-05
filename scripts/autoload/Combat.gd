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
	var tree: Array = GameData.CLASS_SKILLS.get(h.cls_id, [])
	for n in tree:
		if n["kind"] == kind and h.skills.get(n["id"], false):
			s += n["value"]
	if h.innate_kind == kind:
		s += h.innate_value
	s += hero_item_total(h, kind)
	if GameData.TRAIT_TABLE.has(h.trait_name):
		s += GameData.TRAIT_TABLE[h.trait_name].get(kind, 0.0)
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
	var pct := round(value * 100)
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


func pick_trait_name(role: String) -> String:
	var r := randf()
	if r < 0.22:
		return GameData.NEG_TRAITS[randi() % GameData.NEG_TRAITS.size()]
	if r < 0.50:
		return GameData.POS_TRAITS[randi() % GameData.POS_TRAITS.size()]
	if r < 0.62:
		return GameData.ROLE_TRAITS[role]
	return ""


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


func gen_relic(rarity_id: String) -> Relic:
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


func gen_item(rarity_id: String) -> Item:
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


## Returns {"loot_type": "item"|"relic", "obj": Item|Relic}
func gen_loot(rarity_id: String) -> Dictionary:
	if randf() < 0.5:
		return {"loot_type": "item", "obj": gen_item(rarity_id)}
	return {"loot_type": "relic", "obj": gen_relic(rarity_id)}


func gen_monster(diff: Dictionary, floor_idx: int, kind: String) -> Dictionary:
	var scale := 1.0 + floor_idx * 0.12
	var hp_mult := 1.8 if kind == "boss" else 1.0
	var dmg_mult := 1.5 if kind == "boss" else 1.0
	var hp: int = round(diff["monster_hp"] * scale * hp_mult)
	var dmg: int = round(diff["monster_dmg"] * scale * dmg_mult)
	var name: String
	if kind == "boss":
		name = "%s, %s Warden" % [GameData.BOSS_NAMES[randi() % GameData.BOSS_NAMES.size()], diff["name"].split(" ")[0]]
	else:
		name = GameData.MONSTER_NAMES[randi() % GameData.MONSTER_NAMES.size()]
	return {"name": name, "hp": hp, "dmg": dmg}


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


func hero_item_total(h: Hero, kind: String) -> float:
	var s := 0.0
	for it in GameState.items:
		if it.equipped_to == h.id and it.kind == kind:
			s += it.value
	return s


## Optimal Synergy has no Guild-Management unlock gate in this slice — it's
## always active (that upgrade tree is explicitly deferred).
func synergy_bonus() -> Dictionary:
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


## Simplified combat resolver: one fight, pooled party HP, round-by-round
## exchange. Drops Guild-Management-gated bonuses (tactical drilling, Vanguard
## Order, Hardcore Mode) since that whole tree is deferred past this slice.
## `ability_used` is one of "" / warrior / ranger / mage / cleric / rogue.
func resolve_combat(party: Array[Hero], kind: String, diff: Dictionary, floor_idx: int, ability_used: String) -> Dictionary:
	var is_boss := kind == "boss"
	var monster := gen_monster(diff, floor_idx, kind)
	if ability_used == "cleric":
		for h in party:
			h.hp = max_hp(h)
	var monster_dmg: float = monster["dmg"] * 0.6 if ability_used == "ranger" else float(monster["dmg"])

	var raw_sum := 0.0
	for h in party:
		raw_sum += dmg_of(h)
	var team_dmg_base := (raw_sum + relic_dmg_bonus()) * (1.0 + synergy_value_for("dmg_pct") + affinity_bonus(party))
	if ability_used == "warrior":
		team_dmg_base *= 1.3

	var first_round_bonus := party_skill_total(party, "first_round_pct") + relic_special_total("first_round_pct") + synergy_value_for("first_round_pct")
	if ability_used == "rogue":
		first_round_bonus += 0.9
	var escalate := party_skill_total(party, "escalate_pct") + relic_special_total("escalate_pct") + synergy_value_for("escalate_pct")
	var mend: float = min(0.4, party_skill_total(party, "mend_pct") + relic_special_total("mend_pct") + synergy_value_for("mend_pct"))
	var dodge: float = min(0.6, party_skill_total(party, "dodge_pct") + relic_special_total("dodge_pct") + synergy_value_for("dodge_pct"))
	var wipe_guard: float = min(0.9, party_skill_total(party, "wipe_guard") + relic_special_total("wipe_guard"))
	var alpha_strikes := (party_skill_total(party, "boss_alpha_strike") + relic_special_total("boss_alpha_strike")) if is_boss else 0.0

	var m_hp: float = monster["hp"]
	var total_max_at_start := 0
	for h in party:
		total_max_at_start += max_hp(h)
	total_max_at_start = max(1, total_max_at_start)
	var hp_pool := 0
	for h in party:
		hp_pool += h.hp

	var log: Array[String] = []
	log.append("A %s blocks the way (%d HP)." % [monster["name"], monster["hp"]])
	if ability_used != "":
		log.append("%s activated!" % GameData.ABILITIES[ability_used]["name"])
	if alpha_strikes > 0:
		var alpha := team_dmg_base * alpha_strikes
		m_hp -= alpha
		log.append("An opening volley lands for %d!" % round(alpha))
	if ability_used == "mage":
		var burst := team_dmg_base
		m_hp -= burst
		log.append("Overcharge unleashes a burst for %d!" % round(burst))

	var round_num := 0
	var wipe_guard_used := false
	while m_hp > 0 and hp_pool > 0 and round_num < 30:
		round_num += 1
		var mult := (1.0 + first_round_bonus if round_num == 1 else 1.0) * (1.0 + escalate * (round_num - 1))
		var dealt := team_dmg_base * mult
		m_hp -= dealt
		log.append("Round %d — the Guild strikes for %d." % [round_num, round(dealt)])
		if m_hp <= 0:
			log.append("The %s falls!" % monster["name"])
			break
		if mend > 0:
			var heal := round(hp_pool * mend)
			if heal > 0:
				hp_pool = min(total_max_at_start, hp_pool + heal)
				log.append("The party mends %d HP." % heal)
		var back: float = monster_dmg
		if dodge > 0 and randf() < dodge:
			log.append("The party evades the %s's retaliation!" % monster["name"])
			back = 0
		if back > 0:
			hp_pool = max(0, hp_pool - int(round(back)))
			log.append("The %s hits back for %d." % [monster["name"], round(back)])
			if hp_pool <= 0 and not wipe_guard_used and wipe_guard > 0:
				wipe_guard_used = true
				hp_pool = max(1, round(total_max_at_start * wipe_guard))
				log.append("Last Stand! The party clings to life with %d HP." % hp_pool)

	var won := m_hp <= 0
	if not won:
		for h in party:
			h.hp = 0
			h.downed_until = int(Time.get_unix_time_from_system() * 1000) + GameState.recovery_ms()
		log.append("Your party is overwhelmed...")
	else:
		for h in party:
			var share := float(max_hp(h)) / float(total_max_at_start)
			h.hp = clampi(round(hp_pool * share), 1, max_hp(h))

	var result := {
		"won": won, "log": log, "rounds": round_num, "monster_name": monster["name"],
		"coin": 0, "crystal": 0, "reward_options": [],
	}
	if won:
		var depth_mult := 1.0 + floor_idx * 0.05
		result["coin"] = round(randf_range(diff["coin"][0], diff["coin"][1]) * depth_mult)
		result["crystal"] = round(randf_range(diff["crystal"][0], diff["crystal"][1]) * depth_mult)
		var xp_gain := 30 if is_boss else 12
		for h in party:
			gain_xp(h, xp_gain)
		if not is_boss:
			var options := [gen_loot(weighted_rarity()), gen_loot(weighted_rarity())]
			if randf() < min(0.5, drop_rate_bonus() * 2.0):
				options.append(gen_loot(weighted_rarity()))
			result["reward_options"] = options
	return result
