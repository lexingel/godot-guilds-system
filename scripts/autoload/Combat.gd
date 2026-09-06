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


func hero_item_total(h: Hero, kind: String) -> float:
	var s := 0.0
	for it in GameState.items:
		if it.equipped_to == h.id and it.kind == kind:
			s += it.value
	return s


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


## Turn-based combat, per-hero: a fight starts with start_combat() (one-time
## setup: monster roll, boss mechanic, all party-wide bonus totals) and then
## advances one round per resolve_round() call. Each living hero has their own
## pending action (state["pending_actions"], hero_id -> "attack"/"ability"/
## "defend", mutated between renders by GameState.set_hero_action without
## resolving anything) and, if their role qualifies, their own Ability
## cooldown (state["ability_cooldowns"], hero_id -> int) — no more single
## shared party-wide action or Ability use. HP lives directly on each Hero
## throughout (no pooling), so win/retreat/loss need no redistribution step:
## whatever a hero's live `hp` is when the fight ends is correct as-is. The
## monster's retaliation each round targets one random living hero; a hero
## knocked out (hp reaches 0) sits out the rest of the fight but the party
## keeps fighting — a loss only happens once every hero is down. State is
## persisted by the caller (GameState.engage_node/resolve_round_now) across
## renders in run["node_state"]["combat_state"], the same per-node-cache
## pattern already used for shop/hazard nodes. `kind` is "combat"/"elite"/
## "boss". Boss mechanics are rolled fresh each call (not pre-rolled/
## previewed — a minor simplification vs. the HTML version's
## ensureBossPreview, since this port has no pre-engage preview UI).
func start_combat(party: Array[Hero], kind: String, diff: Dictionary, floor_idx: int) -> Dictionary:
	var is_boss := kind == "boss"
	var is_elite := kind == "elite"
	var hardcore: bool = GameState.run.get("hardcore", false)
	var monster := gen_monster(diff, floor_idx, kind)
	var mechanic: Dictionary = {}
	if is_boss:
		mechanic = GameData.BOSS_MECHANICS[randi() % GameData.BOSS_MECHANICS.size()]
		if mechanic["id"] == "frenzied":
			monster["dmg"] = int(round(monster["dmg"] * 1.25))

	var raw_sum := 0.0
	for h in party:
		raw_sum += dmg_of(h)
	var team_dmg_base: float = (raw_sum * GameState.tactical_bonus() + relic_dmg_bonus()) * (1.0 + synergy_value_for("dmg_pct") + affinity_bonus(party))

	var first_round_bonus: float = (0.25 if GameState.has_cap("ops.drill") else 0.0) + party_skill_total(party, "first_round_pct") + relic_special_total("first_round_pct") + synergy_value_for("first_round_pct")
	var escalate: float = party_skill_total(party, "escalate_pct") + relic_special_total("escalate_pct") + synergy_value_for("escalate_pct")
	var mend: float = min(0.4, party_skill_total(party, "mend_pct") + relic_special_total("mend_pct") + synergy_value_for("mend_pct"))
	var dodge: float = min(0.6, party_skill_total(party, "dodge_pct") + relic_special_total("dodge_pct") + synergy_value_for("dodge_pct"))
	var wipe_guard: float = min(0.9, party_skill_total(party, "wipe_guard") + relic_special_total("wipe_guard"))
	var alpha_strikes: float = (party_skill_total(party, "boss_alpha_strike") + relic_special_total("boss_alpha_strike")) if is_boss else 0.0

	var monster_max_hp: float = monster["hp"]
	var m_hp: float = monster_max_hp

	var log: Array[String] = []
	log.append("A %s blocks the way (%d HP)." % [monster["name"], monster["hp"]])
	if not mechanic.is_empty():
		log.append("%s: %s" % [mechanic["name"], mechanic["desc"]])
	if alpha_strikes > 0:
		var alpha: float = team_dmg_base * alpha_strikes
		m_hp -= alpha
		log.append("An opening volley lands for %d!" % round(alpha))

	var ability_cooldowns: Dictionary = {}
	var pending_actions: Dictionary = {}
	for h in party:
		if GameData.ABILITIES.has(h.cls_id) and h.level >= 3:
			ability_cooldowns[h.id] = 0
		pending_actions[h.id] = "attack"

	return {
		"party": party, "kind": kind, "diff": diff, "floor_idx": floor_idx, "hardcore": hardcore,
		"is_boss": is_boss, "is_elite": is_elite,
		"monster_name": monster["name"], "monster_hp": m_hp, "monster_max_hp": monster_max_hp,
		"monster_dmg": float(monster["dmg"]), "mechanic": mechanic, "team_dmg_base": team_dmg_base,
		"raw_sum": raw_sum, "first_round_bonus": first_round_bonus, "escalate": escalate,
		"mend": mend, "dodge": dodge, "wipe_guard": wipe_guard, "wipe_guard_used": false,
		"round_num": 0, "log": log, "ability_cooldowns": ability_cooldowns,
		"pending_actions": pending_actions,
	}


const ABILITY_COOLDOWN_ROUNDS := 3


## One-line hint about the round about to happen, meant to sit above the
## action rows as a warning rather than only showing up in the log after the
## fact. Boss-mechanic messages take priority; every fight (not just bosses)
## falls back to a general heavy-hit/stacking-damage heuristic so the signal
## isn't boss-only.
func describe_incoming(state: Dictionary) -> String:
	var mechanic: Dictionary = state.get("mechanic", {})
	var next_round: int = int(state.get("round_num", 0)) + 1
	if not mechanic.is_empty():
		match mechanic.get("id"):
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
	var back: float = float(state["monster_dmg"])
	if mechanic.get("id") == "enrage" and next_round > GameData.BOSS_ENRAGE_ROUND:
		back = back * (1.0 + 0.15 * (next_round - GameData.BOSS_ENRAGE_ROUND))
	var avg_max := 0.0
	for h in living:
		avg_max += max_hp(h)
	avg_max /= living.size()
	if avg_max > 0.0 and back / avg_max > 0.35:
		return "A heavy blow is coming — consider Defending."
	if float(state["escalate"]) > 0.0 and next_round >= 3:
		return "Damage is stacking — every attack counts more now."
	return ""


## One round of an in-progress fight: applies every living hero's pending
## action from state["pending_actions"] simultaneously, then rolls one random
## living hero as the monster's retaliation target. Mutates `state` in place
## and returns {"done": bool, "result": Dictionary} — result is only populated
## once the fight ends (win/loss/retreat).
func resolve_round(state: Dictionary) -> Dictionary:
	var log: Array[String] = state["log"]
	var monster_name: String = state["monster_name"]
	var party: Array[Hero] = state["party"]
	var pending: Dictionary = state["pending_actions"]
	var cooldowns: Dictionary = state["ability_cooldowns"]

	var living: Array[Hero] = []
	living.assign(party.filter(func(h): return h.hp > 0))

	state["round_num"] = int(state["round_num"]) + 1
	var round_num: int = state["round_num"]
	var team_dmg_base: float = state["team_dmg_base"]
	var raw_sum: float = state["raw_sum"]
	var m_hp: float = state["monster_hp"]
	var attack_mult: float = (1.0 + float(state["first_round_bonus"]) if round_num == 1 else 1.0) * (1.0 + float(state["escalate"]) * (round_num - 1))
	var escalate_mult: float = 1.0 + float(state["escalate"]) * (round_num - 1)

	for hid in cooldowns.keys():
		if int(cooldowns[hid]) > 0:
			cooldowns[hid] = int(cooldowns[hid]) - 1

	var attack_dmg := 0.0
	var defending := {}   # hero_id -> true, checked against the retaliation target below
	for h in living:
		var action: String = pending.get(h.id, "attack")
		if action == "attack":
			attack_dmg += dmg_of(h) / raw_sum * team_dmg_base * attack_mult
		elif action == "defend":
			defending[h.id] = true
		elif action == "ability" and int(cooldowns.get(h.id, 999)) == 0:
			cooldowns[h.id] = ABILITY_COOLDOWN_ROUNDS
			var ability_id: String = h.cls_id
			log.append("%s uses %s!" % [h.name, GameData.ABILITIES[ability_id]["name"]])
			match ability_id:
				"cleric":
					for h2 in party:
						h2.hp = max_hp(h2)
					log.append("The party is fully mended.")
				"ranger":
					state["monster_dmg"] = float(state["monster_dmg"]) * 0.6
					log.append("The monster's strength is sapped.")
				"warrior":
					state["team_dmg_base"] = team_dmg_base * 1.3
				"mage":
					var burst: float = team_dmg_base
					m_hp -= burst
					log.append("Overcharge unleashes a burst for %d!" % round(burst))
				"rogue":
					var dealt: float = team_dmg_base * escalate_mult * 1.9
					m_hp -= dealt
					log.append("Ambush lands for %d!" % round(dealt))

	if attack_dmg > 0.0:
		m_hp -= attack_dmg
		log.append("Round %d — the Guild strikes for %d." % [round_num, round(attack_dmg)])
	state["monster_hp"] = m_hp

	if m_hp <= 0:
		log.append("The %s falls!" % monster_name)
		return _finish_combat(state, true, false)

	if state["mechanic"].get("id") == "regen":
		var regen_heal: float = round(float(state["monster_max_hp"]) * 0.08)
		state["monster_hp"] = min(float(state["monster_max_hp"]), m_hp + regen_heal)
		log.append("%s regenerates %d HP." % [monster_name, regen_heal])

	if float(state["mend"]) > 0.0:
		var mended := false
		for h in living:
			if h.hp > 0 and h.hp < max_hp(h):
				var heal: int = max(1, int(round(max_hp(h) * float(state["mend"]))))
				h.hp = min(max_hp(h), h.hp + heal)
				mended = true
		if mended:
			log.append("The party mends its wounds.")

	var still_living: Array[Hero] = []
	still_living.assign(party.filter(func(h): return h.hp > 0))
	if still_living.is_empty():
		return _finish_combat(state, false, false)
	var target: Hero = still_living[randi() % still_living.size()]

	var back: float = float(state["monster_dmg"])
	var warded: bool = state["mechanic"].get("id") == "warded" and round_num <= 2
	if state["mechanic"].get("id") == "enrage" and round_num > GameData.BOSS_ENRAGE_ROUND:
		back = round(back * (1.0 + 0.15 * (round_num - GameData.BOSS_ENRAGE_ROUND)))
	if defending.has(target.id):
		back *= 0.5
	if not warded and float(state["dodge"]) > 0.0 and randf() < float(state["dodge"]):
		log.append("%s evades the %s's retaliation!" % [target.name, monster_name])
		back = 0.0
	if back > 0.0:
		var dealt_back: int = int(round(back))
		if dealt_back >= target.hp and still_living.size() == 1 and not state["wipe_guard_used"] and float(state["wipe_guard"]) > 0.0:
			state["wipe_guard_used"] = true
			target.hp = max(1, int(round(float(max_hp(target)) * float(state["wipe_guard"]))))
			log.append("Last Stand! %s clings to life with %d HP." % [target.name, target.hp])
		else:
			target.hp = max(0, target.hp - dealt_back)
			log.append("The %s hits %s for %d." % [monster_name, target.name, dealt_back])
			if target.hp <= 0:
				log.append("%s is knocked out!" % target.name)

	var final_living: Array[Hero] = []
	final_living.assign(party.filter(func(h): return h.hp > 0))
	if final_living.is_empty():
		return _finish_combat(state, false, false)
	if round_num >= 30:
		return _finish_combat(state, false, false)

	for h in final_living:
		pending[h.id] = "attack"

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
	if not won and not retreated:
		if hardcore:
			log.append("Your party is overwhelmed... and lost for good.")
		else:
			for h in party:
				h.downed_until = int(Time.get_unix_time_from_system() * 1000) + GameState.recovery_ms()
			log.append("Your party is overwhelmed...")

	var result := {
		"won": won, "retreated": retreated, "log": log, "rounds": int(state["round_num"]), "monster_name": state["monster_name"],
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
