extends "res://scripts/autoload/combat/CombatStats.gd"
## Combat, part 2: relics, item/hero effects and triggers, synergies, boons and bonds — what the party brings to a fight — and the loot-rarity rolls they tilt.


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


## Guild Management node display strings — a match on node id since the HTML
## version used a per-node JS closure that doesn't translate to static data.
func describe_node_effect(node_id: String, level: int) -> String:
	if level <= 0:
		return "Not built yet"
	match node_id:
		"barracks": return "+%d hero slots" % (level * 2)
		"infirmary": return "-%d%% recovery time · %d bed%s" % [level * 15, 1 + int(ceil(level / 2.0)), "" if level == 0 else "s"]
		"drill": return "+%d%% party damage and max HP" % (level * 4)
		"amplifiers": return "+%d%% Essence from fights" % (level * 8)
		"wardstones": return "-%d%% hazard damage · +%d%% Essence for sealing" % [level * 12, level * 10]
		"trade": return "-%d%% shop prices · -%d%% auction fees · +%d%% Rift Cache chance" % [level * 6, level * 2, level * 5]
		"scouts": return "%d recruit offers" % (4 + (1 if level >= 1 else 0) + (1 if level >= 4 else 0))
		"vault":
			var choices := 4 if level >= 4 else (3 if level >= 2 else 2)
			return "%d starting relic choices · %d relic slots" % [choices, 3 + (1 if level >= 3 else 0) + (1 if level >= 5 else 0)]
		"lab": return "+%d%% element-set bonuses" % (level * 10)
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


func relic_dmg_bonus() -> int:
	var s := 0
	for r in equipped_relics():
		s += r.dmg
	return s


func relic_special_total(kind: String) -> float:
	var s := 0.0
	for r in equipped_relics():
		for sp in r.specials:
			if str(sp["kind"]) == kind:
				s += float(sp["value"])
	# Mirror Shard: the best other equipped relic's specials count twice.
	if party_has_unique_relic("mirror_shard"):
		var best: Relic = null
		for r in equipped_relics():
			if r.unique_id != "mirror_shard" and (best == null or GameData.find_rarity(r.rarity)["mult"] > GameData.find_rarity(best.rarity)["mult"] or (r.rarity == best.rarity and r.level > best.level)):
				best = r
		if best:
			for sp in best.specials:
				if str(sp["kind"]) == kind:
					s += float(sp["value"])
	return s * GameState.relic_power_mult() + (boon_total(kind) if BOON_VIA_RELIC.has(kind) else 0.0)


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
	for q in h.quirks:
		var qd := GameData.quirk(q)
		for e in qd.get("effects", []):
			out.append(_tagged(e, q, str(qd.get("arch", ""))))
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
	for q in h.quirks:
		var qd := GameData.quirk(q)
		if qd.has("stats") and qd.has("arch"):
			counts[qd["arch"]] = int(counts.get(qd["arch"], 0)) + 1
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
	var out: Array[Dictionary] = [
		{"trigger": "evade_or_heavy", "effect": "counter_attack", "value": float(state["counter"]), "source": "counter"},
		{"trigger": "evade_or_heavy", "effect": "gain_momentum", "value": float(state["momentum_proc"]), "source": "Chronometer"},
		{"trigger": "on_kill", "effect": "shield_lowest", "value": float(state["kill_shield"]), "source": "Lantern"},
	]
	# Every equipped relic's trigger fires for the whole party, and so does
	# every run boon's.
	for r in equipped_relics():
		if not r.trigger.is_empty():
			var t: Dictionary = r.trigger.duplicate()
			t["source"] = r.name
			out.append(t)
	for b in boon_effects():
		if b.has("trigger"):
			var bt: Dictionary = (b["trigger"] as Dictionary).duplicate()
			bt["source"] = str(b["name"])
			out.append(bt)
	return out


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
		"gain_momentum":
			if randf() < value:
				state["momentum"] = mini(GameData.MOMENTUM_MAX, int(state.get("momentum", 0)) + 1)
				log.append("The %s hums — +1 Momentum!" % source)
				_proc(state, h, "Momentum +1")
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
			log.append("The %s mends the party." % source)
			_proc(state, h, source)
		"nova":
			var nova: int = max(1, int(round(float(state["team_dmg_base"]) * value)))
			for mm in state["monsters"]:
				if float(mm["hp"]) > 0:
					mm["hp"] = float(mm["hp"]) - nova
			log.append("The %s strikes every foe for %d!" % [source, nova])
			_proc(state, h, source)
		"shield_party":
			var sh: Dictionary = state["hero_shields"]
			for a in state["party"]:
				if a.hp > 0:
					sh[a.id] = float(sh.get(a.id, 0.0)) + max_hp(a) * value
			log.append("The %s shields the party." % source)
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
			"gain_momentum": what = "%s chance to gain 1 Momentum" % pct.call(v)
			"extra_turn": what = "act again (once per round)"
			"intercept": what = "%s chance to take the hit for an ally below half HP" % pct.call(v)
			"weaken_attacker": what = "cut the attacker's damage by %s" % pct.call(v)
			"mend_party": what = "mend every ally for %s of their max HP" % pct.call(v)
			"nova": what = "strike every foe for %s of the party's damage" % pct.call(v)
			"shield_party": what = "shield every ally for %s of their max HP" % pct.call(v)
		var when := ""
		match str(e.get("trigger", "")):
			"after_hit", "before_hit": when = "On hit"
			"on_kill": when = "On a kill"
			"round_third": when = "Every third round"
			"ally_down": when = "When an ally falls"
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


## The run's boons for a stat kind (kinds in BOON_VIA_RELIC come through
## relic_special_total instead).
func synergy_value_for(kind: String) -> float:
	return 0.0 if BOON_VIA_RELIC.has(kind) else boon_total(kind)

## Kinds read through relic_special_total rather than synergy_value_for;
## boons join whichever channel a kind already flows through (never both).
const BOON_VIA_RELIC := ["counter_pct", "momentum_pct", "kill_shield_pct", "wipe_guard", "boss_alpha_strike"]


## Every stat entry and trigger the current run's boons (and their family
## set bonuses) give: [{kind, value} | {trigger, effect, value}, source].
func boon_effects() -> Array:
	var out: Array = []
	var counts := {}
	for id in GameState.run.get("boons", []):
		var b := GameData.find_boon(str(id))
		if b.is_empty():
			continue
		counts[b["family"]] = int(counts.get(b["family"], 0)) + 1
		out.append(b)
	for fam in counts:
		for step in GameData.BOON_SETS.get(fam, []):
			if int(counts[fam]) >= int(step[0]):
				out.append(step[1])
	return out


func boon_total(kind: String) -> float:
	var s := 0.0
	for e in boon_effects():
		if str(e.get("kind", "")) == kind:
			s += float(e["value"])
		if str(e.get("kind2", "")) == kind:
			s += float(e["value2"])
	return s


func drop_rate_bonus() -> float:
	return relic_special_total("loot_rarity_pct") + synergy_value_for("loot_rarity_pct")


## Party damage from grown bonds (heroes who have sealed rifts together),
## counted while both stand.
func bond_bonus_for(party: Array[Hero], kind: String) -> float:
	var total := 0.0
	# Grown bonds between specific heroes (GameState.bonds) — damage only.
	if kind == "dmg_pct":
		var grown := 0.0
		for i in party.size():
			for j in range(i + 1, party.size()):
				if party[i].hp > 0 and party[j].hp > 0:
					grown += GameData.BOND_DMG_PER_LEVEL * GameData.bond_level(GameState.bond_rifts(party[i].id, party[j].id))
		total += min(grown, GameData.BOND_DMG_CAP)
	return total


## Power: what heroes bring to a fight in one number — damage (ability power
## and ramp folded in) x2 plus effective health (dodge, mending, relic ward)
## /3. Mirrors start_combat's party-wide numbers, so it moves with everything
## that actually changes a fight. A hero's own power leaves out the party-
## wide terms (relics, synergy, bonds); party_power counts them once.
func party_power(party: Array) -> int:
	return _power(party, true)


func power_of(h: Hero) -> int:
	return _power([h], false)


func _power(heroes: Array, party_terms: bool) -> int:
	if heroes.is_empty():
		return 0
	var party: Array[Hero] = []
	party.assign(heroes)
	var dmg := 0.0
	var hp := 0.0
	for h in party:
		dmg += dmg_of(h) * (1.0 + 0.3 * hero_skill_total(h, "ability_power"))
		hp += max_hp(h)
	dmg *= GameState.tactical_bonus()
	var dodge := party_skill_total(party, "dodge_pct")
	var mend := party_skill_total(party, "mend_pct")
	var ramp := party_skill_total(party, "escalate_pct") * 4.0 + party_skill_total(party, "first_round_pct") * 0.15
	if party_terms:
		dmg += relic_dmg_bonus()
		dmg *= 1.0 + synergy_value_for("dmg_pct") + bond_bonus_for(party, "dmg_pct")
		dodge += relic_special_total("dodge_pct") + relic_drawback_total("dodge_pct") + synergy_value_for("dodge_pct") + bond_bonus_for(party, "dodge_pct")
		mend += relic_special_total("mend_pct") + relic_drawback_total("mend_pct") + synergy_value_for("mend_pct") + bond_bonus_for(party, "mend_pct")
		ramp += (relic_special_total("escalate_pct") + relic_drawback_total("escalate_pct")) * 4.0 + (relic_special_total("first_round_pct") + relic_drawback_total("first_round_pct")) * 0.15
		if party_has_unique_relic("bloodpact"):
			mend = 0.0
		for r in equipped_relics():
			hp += r.hp
	dmg *= 1.0 + maxf(ramp, -0.5)
	hp = hp / (1.0 - clampf(dodge, 0.0, 0.6)) * (1.0 + 6.0 * clampf(mend, 0.0, 0.4))
	return int(round(dmg * 2.0 + hp / 3.0))

