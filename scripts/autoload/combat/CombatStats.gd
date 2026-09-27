extends Node
## Pure stat/combat functions — ported from guild-system.html's heroSkillTotal/
## maxHp/dmgOf/engageCombat family. Reads GameState's relics/items directly
## (autoloads can reference each other by name), same as the JS version reads
## the shared `state` global, but every function here still takes its actual
## subject (hero/party) as a parameter rather than reaching for ambient state.
##
## Guild Management bonuses (tactical_bonus, crystal_yield_bonus, has_cap
## gates, etc.) are read straight from GameState rather than duplicated here.
## Elite encounters and the Champion system are all live —
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
	if kind == "dmg_pct":
		s += float(GameData.morale_tier(h.morale)[2])
	for q in h.quirks:
		s += float(GameData.quirk(q).get("stats", {}).get(kind, 0.0))
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
					[it.implicit_kind, it.implicit_value], [it.drawback_kind, it.drawback_value]]:
				if pair[0] == kind:
					v += float(pair[1])
			add.call(it.name, v)
	for a in GameData.ATTRIBUTES:
		var per: float = float(GameData.ATTR_EFFECTS[a].get(kind, 0.0))
		if per != 0.0:
			add.call("%s %d" % [GameData.ATTR_LABEL[a], hero_attr(h, a)], (hero_attr(h, a) - GameData.ATTR_BASELINE) * per)
	if kind == "dmg_pct":
		var mt: Array = GameData.morale_tier(h.morale)
		add.call("Morale: %s" % mt[1], float(mt[2]))
	for q in h.quirks:
		add.call("Quirk: %s" % q, float(GameData.quirk(q).get("stats", {}).get(kind, 0.0)))
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


## The party power that clears a rift about 65% of the time: a ladder
## rank's own "rec", else the difficulty's rec_power (both measured with
## balance_sim -- calibrate).
func recommended_power(diff_id: String, rift_rank: String = "") -> int:
	if diff_id == "endless":
		return GameData.ENDLESS_REC_POWER
	if rift_rank != "":
		return int(GameData.find_rift_rank(rift_rank)["rec"])
	var diff: Dictionary = GameData.DIFFICULTIES[0]
	for d in GameData.DIFFICULTIES:
		if d["id"] == diff_id:
			diff = d
	return int(diff["rec_power"])


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


## A recruit's born quirk: 22% a bad one, 28% a good one, 12% their role's
## double-edged one, otherwise none.
func roll_born_quirk(role: String) -> String:
	var born := GameData.quirks_from("born")
	var r := randf()
	if r < 0.22:
		return str(born.filter(func(q): return GameData.QUIRKS[q].get("treatable", false) and not GameData.QUIRKS[q].has("role")).pick_random())
	if r < 0.50:
		return str(born.filter(func(q): return not GameData.QUIRKS[q].get("treatable", false)).pick_random())
	if r < 0.62:
		var own: Array = born.filter(func(q): return GameData.QUIRKS[q].get("role", "") == role)
		return str(own[0]) if not own.is_empty() else ""
	return ""


## A scar the hero doesn't have yet, or "" at the cap.
func roll_scar(h: Hero) -> String:
	var have: Array = h.quirks.filter(func(q): return GameData.quirk(q).get("origin", "") == "scar")
	if have.size() >= GameData.SCARS_MAX:
		return ""
	var choices: Array = GameData.quirks_from("scar").filter(func(q): return not h.quirks.has(q))
	return str(choices.pick_random()) if not choices.is_empty() else ""


const HERO_INNATE_MULT := 0.6




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
			if it.drawback_kind == kind:
				s += it.drawback_value
	return s
