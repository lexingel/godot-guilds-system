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
		for n in GameData.rift_nodes(tree_kind):
			if n["kind"] == kind and h.skills.get(GameData.skill_storage_key(tree_kind, n["id"]), false):
				s += float(n["value"])
		# A learned keystone's drawback is a plain flat stat.
		var ks := GameData.keystone_node(tree_kind)
		if not ks.is_empty() and ks["kind"] == kind and h.skills.get(GameData.skill_storage_key(tree_kind, "keystone"), false):
			s += float(ks["value"])
	s += GameState.party_resonance_bonus(kind)
	s += GameState.party_eclectic_bonus()
	s += GameState.champion_boon(kind)
	if h.battered and kind == "hp_pct":
		s -= GameData.BATTERED_HP_PCT
	if h.innate_kind == kind:
		s += h.innate_value
	# Same one-stage-back retention as the tree above — the innate bonus
	# from the class a hero just evolved out of doesn't just vanish either.
	if h.prior_innate_kind == kind:
		s += h.prior_innate_value
	s += hero_item_total(h, kind)
	s += attr_kind_total(h, kind)
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


## Where hero_skill_total(h, kind) comes from, term by term, as
## [label, value] pairs — the Roster's stat-breakdown tooltip. Mirrors
## hero_skill_total exactly (same terms, same order); a check keeps the two
## in sync. Display only: combat always reads hero_skill_total.
func hero_skill_sources(h: Hero, kind: String) -> Array:
	var out: Array = []
	var add := func(label: String, v: float) -> void:
		if absf(v) > 0.0005:
			out.append([label, v])
	for n in GameData.tier1_for_role(h.cls_id):
		if n["kind"] == kind and h.skills.get(n["id"], false):
			add.call("Skill: %s" % n["name"], float(n["value"]))
	for summary in GameData.hero_tree_summaries(h):
		var tree_kind: String = summary["kind"]
		for n in GameData.KIND_SKILL_PACKAGE.get(tree_kind, []):
			if n["kind"] == kind and h.skills.get(GameData.skill_storage_key(tree_kind, n["id"]), false):
				add.call("Skill: %s" % n["name"], float(n["value"]))
				if n.has("combo_kind") and GameState.party_has_other_kind_capstone(h.id, str(n["combo_kind"])):
					add.call("Combo: %s" % n["name"], float(n.get("combo_bonus", 0.0)))
		for n in GameData.rift_nodes(tree_kind):
			if n["kind"] == kind and h.skills.get(GameData.skill_storage_key(tree_kind, n["id"]), false):
				add.call("Skill: %s" % n["name"], float(n["value"]))
		var ks := GameData.keystone_node(tree_kind)
		if not ks.is_empty() and ks["kind"] == kind and h.skills.get(GameData.skill_storage_key(tree_kind, "keystone"), false):
			add.call("Keystone drawback: %s" % ks["name"], float(ks["value"]))
	add.call("Party Resonance", GameState.party_resonance_bonus(kind))
	add.call("Party Eclectic", GameState.party_eclectic_bonus())
	add.call("Champion Boon", GameState.champion_boon(kind))
	if h.battered and kind == "hp_pct":
		add.call("Battered (patched up mid-rift)", -GameData.BATTERED_HP_PCT)
	if h.innate_kind == kind:
		add.call("Innate (%s)" % GameData.find_class(h.pool_id).get("name", "class"), h.innate_value)
	if h.prior_innate_kind == kind:
		add.call("Innate (former class)", h.prior_innate_value)
	for it in GameState.items:
		if it.equipped_to == h.id:
			var v := 0.0
			for pair in [[it.kind, it.value], [it.secondary_kind, it.secondary_value], [it.tertiary_kind, it.tertiary_value],
					[it.implicit_kind, it.implicit_value], [it.socketed_kind, it.socketed_value], [it.drawback_kind, it.drawback_value]]:
				if pair[0] == kind:
					v += float(pair[1])
			add.call(it.name, v)
	for a in GameData.ATTRIBUTES:
		var per: float = float(GameData.ATTR_EFFECTS[a].get(kind, 0.0))
		if per != 0.0:
			add.call("%s %d" % [GameData.ATTR_LABEL[a], hero_attr(h, a)], (hero_attr(h, a) - GameData.ATTR_BASELINE) * per)
	if GameData.TRAIT_TABLE.has(h.trait_name):
		add.call("Trait: %s" % h.trait_name, float(GameData.TRAIT_TABLE[h.trait_name].get(kind, 0.0)))
	for scar in h.scars:
		if GameData.SCAR_TABLE.has(scar):
			add.call("Scar: %s" % scar, float(GameData.SCAR_TABLE[scar].get(kind, 0.0)))
	for tid in h.earned_traits:
		var t := GameData.find_earned_trait(tid)
		if t.get("kind", "") == kind:
			add.call("Earned: %s" % t["name"], float(t["value"]))
	if GameState.active_incense.get("kind", "") == kind:
		add.call("Incense: %s" % GameState.active_incense.get("name", "active"), float(GameState.active_incense["value"]))
	return out


## A hero's attribute: their own points plus what their equipped items add.
func hero_attr(h: Hero, a: String) -> int:
	var v: int = int(h.attrs.get(a, GameData.ATTR_BASELINE))
	for it in GameState.items:
		if it.equipped_to == h.id and it.attr == a:
			v += it.attr_bonus
	return v


## What a hero's attributes add to one stat kind (see GameData.ATTR_EFFECTS).
func attr_kind_total(h: Hero, kind: String) -> float:
	var s := 0.0
	for a in GameData.ATTRIBUTES:
		var per: float = float(GameData.ATTR_EFFECTS[a].get(kind, 0.0))
		if per != 0.0:
			s += (hero_attr(h, a) - GameData.ATTR_BASELINE) * per
	return s


## Spends a hero's unspent points the way their role would (recruits, the
## Champion, simulations).
func auto_spend_attrs(h: Hero) -> void:
	var spread: Array = GameData.ROLE_ATTR_SPREAD.get(GameData.hero_role(h), ["might", "agility", "focus"])
	var i := 0
	while h.attr_points > 0:
		var a := str(spread[i % spread.size()])
		h.attrs[a] = int(h.attrs.get(a, GameData.ATTR_BASELINE)) + 1
		h.attr_points -= 1
		i += 1


func max_hp(h: Hero) -> int:
	return round(h.base_hp * (1.0 + hero_skill_total(h, "hp_pct")) * GameState.tactical_bonus())


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
	h.xp += int(round(amount * GameState.xp_mult()))
	while h.level < 10 and h.xp >= xp_to_next(h.level):
		h.xp -= xp_to_next(h.level)
		h.level += 1
		h.base_hp = round(h.base_hp * (1.0 + GameData.LEVEL_GROWTH))
		h.base_dmg = round(h.base_dmg * (1.0 + GameData.LEVEL_GROWTH))
		h.skill_points += 1
		h.attr_points += GameData.ATTR_POINTS_PER_LEVEL
		if h.is_champion:
			auto_spend_attrs(h)


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
		"ability_power": return "%s%d%% ability power" % [up, pct]
		"wipe_guard": return ("Once per rift, survive a wipe at %d%% HP" if value >= 0.0 else "-%d%% HP on a survived wipe") % pct
		"boss_alpha_strike": return "Opens every Boss fight with a free strike"
		_: return ""


func party_skill_total(party: Array[Hero], kind: String) -> float:
	var s := 0.0
	for h in party:
		s += hero_skill_total(h, kind)
	return s


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


func endless_diff_for_cycle(cycle: int) -> Dictionary:
	var mult := 1.0 + cycle * ENDLESS_CYCLE_GROWTH
	# Rewards grow slower than the foes (docs/economy.md): at the foes' rate
	# one Endless attempt paid as much as ~20 Greater runs.
	var reward_mult := 1.0 + cycle * ENDLESS_REWARD_GROWTH
	var base := GameData.ENDLESS_BASE
	return {
		"id": "endless", "name": "Endless Rift", "floors": 6, "power": "Extreme",
		"monster_hp": int(round(base["monster_hp"] * mult)), "monster_dmg": int(round(base["monster_dmg"] * mult)),
		"coin": [int(round(base["coin"][0] * reward_mult)), int(round(base["coin"][1] * reward_mult))],
		"crystal": [int(round(base["crystal"][0] * reward_mult)), int(round(base["crystal"][1] * reward_mult))],
		"token_base": int(round(base["token_base"] * reward_mult)), "detector_chance": base["detector_chance"],
		"rec_power": int(round(base["rec_power"] * mult)),
	}
const ENDLESS_CYCLE_GROWTH := 0.5
const ENDLESS_REWARD_GROWTH := 0.2


func equipped_relics() -> Array[Relic]:
	var out: Array[Relic] = []
	for r in GameState.relics:
		if r.equipped:
			out.append(r)
	return out


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
