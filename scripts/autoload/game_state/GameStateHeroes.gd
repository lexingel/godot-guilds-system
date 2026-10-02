extends "res://scripts/autoload/game_state/GameStateCore.gd"
## GameState, part 2: heroes — recruiting, the Champion, bonds, skills, traits, attributes.


## Queues a portrait pop-up (Main drains these on its next render).
func push_toast(h: Hero, title: String, text: String) -> void:
	pending_toasts.append({"cls_id": h.cls_id, "pool_id": h.pool_id, "title": title, "text": text})


func _bond_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


func bond_rifts(a: String, b: String) -> int:
	return int(bonds.get(_bond_key(a, b), 0))


## Gives `h` every earned quirk (GameData.QUIRKS, origin "earned") their
## history now qualifies for; returns "X earned Bosskiller!" lines.
func check_earned_quirks(h: Hero) -> Array[String]:
	var gained: Array[String] = []
	for q in GameData.quirks_from("earned"):
		var t := GameData.quirk(q)
		if not h.quirks.has(q) and int(h.history.get(t["stat"], 0)) >= int(t["need"]):
			h.quirks.append(q)
			gained.append(tr("%s earned %s!") % [tr(str(h.name)), tr(str(q))])
			push_toast(h, tr("Quirk earned: %s") % tr(str(q)), "%s — %s" % [tr(str(h.name.split(" the ")[0])), tr(str(quirk_text(q)))])
	return gained


## "+10% damage; +15% dodge while below 40% HP" for a quirk.
func quirk_text(q: String) -> String:
	var t := GameData.quirk(q)
	var parts: Array[String] = []
	var stats: Dictionary = t.get("stats", {})
	for kind in stats:
		parts.append(Combat.describe_skill(kind, float(stats[kind])))
	for e in t.get("effects", []):
		parts.append(Combat.describe_effect(e))
	return "; ".join(parts)


## Treats a treatable quirk (a bad born quirk or a scar) at the Arcane Lab.
func treat_quirk(hero_id: String, q: String) -> String:
	if lvl("res.lab") < 1:
		return tr("Build the Arcane Lab first")
	var h := find_hero(hero_id)
	if not h or not h.quirks.has(q) or not GameData.quirk(q).get("treatable", false):
		return ""
	var cost := quirk_treat_cost()
	if coins < cost:
		return tr("Need %d Gold") % cost
	coins -= cost
	h.quirks.erase(q)
	h.hp = mini(h.hp, Combat.max_hp(h))
	save()
	state_changed.emit()
	return ""


func quirk_treat_cost() -> int:
	return int(round(GameData.QUIRK_TREAT_COST * (1.0 - respec_fee_reduction())))


## Heroes who'd look identical (the same portrait: the same subclass, or
## Champions of one role) get different colour variants. The earliest in the
## roster keeps the art as drawn, the next the first free variant, and so on;
## a hero keeps theirs until an evolution changes their portrait.
func refresh_looks() -> void:
	var taken := {}   # portrait -> {look: true}
	for h in heroes:
		var art := GameData.portrait_for_hero(h.cls_id, h.pool_id)
		var t: Dictionary = taken.get(art, {})
		if h.look_of != art or t.has(h.look):
			h.look = _free_look(t)
			h.look_of = art
		t[h.look] = true
		taken[art] = t


## The variant a hero would wear on joining (a recruit offer's preview).
func look_for(h: Hero) -> int:
	if heroes.has(h):
		return h.look
	var art := GameData.portrait_for_hero(h.cls_id, h.pool_id)
	var t := {}
	for o in heroes:
		if o.look_of == art:
			t[o.look] = true
	return _free_look(t)


func _free_look(taken: Dictionary) -> int:
	var k := 0
	while taken.has(k):
		k += 1
	return k


func find_hero(hero_id: String) -> Hero:
	for h in heroes:
		if h.id == hero_id:
			return h
	return null


## Saved loadouts (party_presets): a party with each hero's row, to load in
## one click on any party screen.
func save_party_preset(i: int, hero_ids: Array) -> void:
	if i < 0 or i >= party_presets.size():
		return
	var out: Array = []
	for id in hero_ids:
		var h := find_hero(str(id))
		if h and not h.is_champion:
			out.append([h.id, h.formation])
	party_presets[i] = out
	save()


## A loadout's heroes who can go now, set in their saved rows, up to `cap`:
## {ids, missing (first names of the ones who can't)}.
func load_party_preset(i: int, cap: int) -> Dictionary:
	var ids: Array[String] = []
	var missing: Array[String] = []
	if i < 0 or i >= party_presets.size():
		return {"ids": ids, "missing": missing}
	for entry in party_presets[i]:
		var h := find_hero(str(entry[0]))
		if h == null:
			continue
		if h.is_downed() or h.busy_runs > 0 or ids.size() >= cap:
			missing.append(h.name.split(" the ")[0])
			continue
		h.formation = str(entry[1])
		ids.append(h.id)
	return {"ids": ids, "missing": missing}


func gen_recruit_offer(force_rank: String = "") -> Hero:
	return Combat.gen_hero(force_rank if force_rank != "" else Combat.weighted_rank(), 1)


## Flags pending_s_rank_reveal whenever a blind roll (recruit offer, Champion
## reroll/init) lands Rank S — Main.render() consumes it once, the same way
## it already consumes _flavor_toast, so the celebration shows up wherever
## the player is instead of only on the Recruits screen.
func _maybe_flag_s_rank(h: Hero, source: String) -> void:
	if h.rank == "S":
		pending_s_rank_reveal = {"name": h.name, "cls_id": h.cls_id, "pool_id": h.pool_id, "source": source}


## A full board (a new guild, or an old save without one).
func refresh_recruit_pool() -> void:
	recruit_pool = []
	recruit_until = {}
	recruit_top_up()


## Puts a recruit on the board for a few days (`stay` -1 = the usual roll).
func _post_offer(h: Hero, stay: int = -1, at: int = -1) -> void:
	if stay < 0:
		stay = randi_range(int(GameData.RECRUIT_STAY[0]), int(GameData.RECRUIT_STAY[1]))
	if at < 0:
		recruit_pool.append(h)
	else:
		recruit_pool.insert(at, h)
	recruit_until[h.id] = day + stay
	_maybe_flag_s_rank(h, "recruit")


func _drop_offer(h: Hero) -> void:
	recruit_pool.erase(h)
	recruit_until.erase(h.id)


## Days an offer still waits: 0 = its last day.
func offer_days_left(h: Hero) -> int:
	return int(recruit_until.get(h.id, day)) - day


## Payday: the week's new faces fill the board (the Scouts' Lodge assures a
## C+ among them) and rerolls are back to their first price.
func recruit_top_up() -> void:
	while recruit_pool.size() < recruit_offer_count():
		_post_offer(gen_recruit_offer())
	if headhunter_guarantee() and not recruit_pool.is_empty() and not recruit_pool.any(func(h): return GameData.rank_index(h.rank) >= GameData.rank_index("C")):
		var good_ranks := ["C", "B", "A", "S"]
		_drop_offer(recruit_pool[recruit_pool.size() - 1])
		_post_offer(gen_recruit_offer(good_ranks[randi() % good_ranks.size()]))
	recruit_rerolls = 0


## A day on the recruit board: offers whose time is up move on, the rival may
## sign the best one, and a new face arrives (two on a thin board). The board
## used to refill whole after every seal, so rerolling was the only choice.
func recruit_day() -> void:
	for h in recruit_pool.duplicate():
		if offer_days_left(h) < 0:
			_drop_offer(h)
	if not recruit_pool.is_empty() and feature_unlocked("rival") and randf() < GameData.RIVAL_SIGN_CHANCE:
		var best: Hero = recruit_pool[0]
		for h in recruit_pool:
			if GameData.rank_index(h.rank) > GameData.rank_index(best.rank):
				best = h
		_drop_offer(best)
		_news(tr("%s signed %s (Rank %s) off your recruit board.") % [tr(str(rival_name)), tr(str(best.name.split(" the ")[0])), tr(str(best.rank))])
	var arrivals := 2 if recruit_pool.size() * 2 < recruit_offer_count() else 1
	for i in arrivals:
		if recruit_pool.size() < recruit_offer_count():
			_post_offer(gen_recruit_offer())


## A recruit of the role you ask for, at the usual rank odds, for
## COMMISSION_COST_MULT x the reroll fee. Rerolling the board until a cleric
## turned up was the only way to look for one ("spamming Gold"). The new
## offer goes first; the last one leaves, so the board keeps its size.
func commission_recruit(role: String) -> String:
	var cost := commission_cost()
	if coins < cost:
		return tr("Not enough Gold.")
	var rank := Combat.weighted_rank()
	var h: Hero = null
	for i in 200:
		var c := Combat.gen_hero(rank, 1)
		if GameData.hero_role(c) == role:
			h = c
			break
	if h == null:
		return tr("No %s answered; try another role") % tr(role)
	coins -= cost
	recruit_rerolls += 1
	_post_offer(h, -1, 0)
	if recruit_pool.size() > recruit_offer_count():
		_drop_offer(recruit_pool[recruit_pool.size() - 1])
	save()
	state_changed.emit()
	return ""


func commission_cost() -> int:
	return recruit_reroll_cost() * GameData.COMMISSION_COST_MULT


func recruit_hero(offer_id: String) -> String:
	var idx := -1
	for i in recruit_pool.size():
		if recruit_pool[i].id == offer_id:
			idx = i
			break
	if idx < 0:
		return ""
	if heroes.size() >= hero_slot_cap():
		return tr("Roster is full.")
	var offer := recruit_pool[idx]
	var rank := GameData.find_rank(offer.rank)
	if coins < int(rank["cost"]):
		return tr("Not enough Gold.")
	coins -= int(rank["cost"])
	var is_dupe := heroes.any(func(h): return h.pool_id == offer.pool_id)
	if guild_mentor():
		offer.level = 2
		offer.skill_points += 1
		offer.base_hp = int(round(offer.base_hp * 1.08))
		offer.base_dmg = int(round(offer.base_dmg * 1.08))
		offer.hp = Combat.max_hp(offer)
	heroes.append(offer)
	_drop_offer(offer)   # the next face arrives tomorrow (it used to be replaced on the spot)
	if is_dupe:
		var refund := int(round(float(rank["cost"]) * 0.5))
		coins += refund
	save()
	state_changed.emit()
	return ""


## Champions for hire: fills the offers if there are none.
func reroll_recruit_offer(offer_id: String) -> String:
	var idx := -1
	for i in recruit_pool.size():
		if recruit_pool[i].id == offer_id:
			idx = i
			break
	if idx < 0:
		return ""
	if coins < recruit_reroll_cost():
		return tr("Not enough Gold.")
	coins -= recruit_reroll_cost()
	recruit_rerolls += 1
	_drop_offer(recruit_pool[idx])
	_post_offer(gen_recruit_offer(), -1, idx)
	save()
	state_changed.emit()
	return ""


# ---------------- Champions ----------------
## This guild's champions: GameData.CHAMPION_ROLL drawn from the pool. The
## first CHAMPION_STORY_ACTS are freed at the end of Acts I-III, the rest are
## lost in the Endless Rift (see lost_champions).
func roll_champions() -> void:
	var ids: Array = GameData.CHAMPIONS.keys()
	ids.shuffle()
	champion_roll.assign(ids.slice(0, GameData.CHAMPION_ROLL))


## The champion freed at the end of Act `act`, or "".
func story_champion(act: int) -> String:
	return champion_roll[act - 1] if act >= 1 and act <= mini(GameData.CHAMPION_STORY_ACTS, champion_roll.size()) else ""


## How strong the Endless Rift's foes are for this guild (see THREAT_BASE).
func endless_threat() -> float:
	var freed := lost_champions().filter(func(e): return champion_unlocked(str(e[0]))).size()
	var acts_after := maxi(0, campaign_act - 3)   # the rift opens once Act II is done
	return minf(GameData.THREAT_MAX, GameData.THREAT_BASE + GameData.THREAT_PER_RESCUE * freed + GameData.THREAT_PER_ACT * acts_after)


## [[id, depth seconds], ...]: this guild's champions lost in the Endless Rift.
func lost_champions() -> Array:
	var out: Array = []
	for i in range(GameData.CHAMPION_STORY_ACTS, champion_roll.size()):
		out.append([champion_roll[i], int(GameData.CHAMPION_DEPTHS[mini(i - GameData.CHAMPION_STORY_ACTS, GameData.CHAMPION_DEPTHS.size() - 1)])])
	return out


func champion_unlocked(id: String) -> bool:
	return champions.has(id)


func champion_level(id: String) -> int:
	return int(champions.get(id, 0))


## Frees a champion (the first one freed also takes up overseeing).
func unlock_champion(id: String) -> void:
	if id == "" or champions.has(id):
		return
	champions[id] = 1
	if overseer == "":
		overseer = id


## Essence to raise `id` one level, or -1 at the top.
func champion_level_cost(id: String) -> int:
	var lv := champion_level(id)
	return int(GameData.CHAMPION_LEVEL_COST[lv]) if lv >= 1 and lv < GameData.CHAMPION_LEVEL_MAX else -1


func level_champion(id: String) -> String:
	var cost := champion_level_cost(id)
	if cost < 0:
		return tr("Already at the top level.")
	if crystals < cost:
		return tr("Not enough Essence.")
	crystals -= cost
	champions[id] = champion_level(id) + 1
	save()
	state_changed.emit()
	return ""


func set_overseer(id: String) -> void:
	if id != "" and not champions.has(id):
		return
	overseer = id
	save()
	state_changed.emit()


## The champion overseeing this run ("" outside a run or with none).
func run_overseer() -> String:
	return str(run.get("overseer", "")) if not run.is_empty() else ""


## The overseer's party-wide Boon for `kind` during a run.
func champion_boon(kind: String) -> float:
	var id := run_overseer()
	var b: Dictionary = GameData.champion_def(id).get("boon", {})
	if b.is_empty() or str(b["kind"]) != kind:
		return 0.0
	return float(b["value"]) * GameData.champion_power(champion_level(id))


func champion_boon_text(id: String) -> String:
	var b: Dictionary = GameData.champion_def(id).get("boon", {})
	if b.is_empty():
		return ""
	return tr("%s — party %s") % [tr(str(b["name"])), tr(str(Combat.describe_skill(str(b["kind"]), float(b["value"]) * GameData.champion_power(maxi(1, champion_level(id))))))]


## `id`'s Call at their level, Ability-shaped {name, effect, value, desc}.
## A multiplier (x1.25) grows on its bonus, anything else on its value.
func champion_call_of(id: String) -> Dictionary:
	var c: Dictionary = (GameData.champion_def(id).get("call", {}) as Dictionary).duplicate()
	if c.is_empty():
		return c
	var k := GameData.champion_power(maxi(1, champion_level(id)))
	var v := float(c["value"])
	c["value"] = 1.0 + (v - 1.0) * k if v > 1.0 and str(c["effect"]).ends_with("_mult") else v * k
	return c


## The overseer's Call (any hero can spend their turn on it). `_h` is kept
## for the combat code's call sites.
func champion_call(_h: Hero = null) -> Dictionary:
	return champion_call_of(run_overseer())


func champion_calls_allowed() -> int:
	var id := run_overseer()
	if id == "":
		return 0
	var n := 2 if champion_level(id) >= GameData.CHAMPION_EXTRA_CALL_LEVEL else 1
	return n + (1 if Combat.party_has_unique_relic("crown_of_oaths") else 0)


func champion_calls_left() -> int:
	return maxi(0, champion_calls_allowed() - int(run.get("champion_calls", 0)))


func champion_call_ready(_h: Hero = null) -> bool:
	return not run.is_empty() and champion_calls_left() > 0


## A champion as a fighter for the Endless Rift: rank CHAMPION_RANK, as
## experienced as the guild's best hero, stronger with their own level.
func champion_hero(id: String) -> Hero:
	var d := GameData.champion_def(id)
	var role := str(d.get("role", "warrior"))
	var template: Dictionary = {}
	for c in GameData.CLASS_POOL:
		if str(c["role"]) == role and str(c["rank"]) == GameData.CHAMPION_RANK:
			template = c
			break
	if template.is_empty():
		template = GameData.CLASS_POOL.filter(func(c): return str(c["role"]) == role)[0]
	var rank := GameData.find_rank(GameData.CHAMPION_RANK)
	var h := Hero.new()
	h.id = "champ:" + id
	h.name = str(d.get("name", id))
	h.is_champion = true
	h.cls_id = role
	h.pool_id = "champ_" + id
	h.rank = GameData.CHAMPION_RANK
	h.type = str(template.get("type", ""))
	var boon: Dictionary = d.get("boon", {})
	h.innate_kind = str(boon.get("kind", template.get("kind", "dmg_pct")))
	h.innate_value = Combat.innate_value_for(template, GameData.rank_index(GameData.CHAMPION_RANK))
	h.flavor = str(d.get("lore", ""))
	var lv := 1
	for o in heroes:
		lv = maxi(lv, o.level)
	h.level = lv
	var grow := pow(1.0 + GameData.LEVEL_GROWTH, lv - 1) * (1.0 + GameData.CHAMPION_LEVEL_STATS * (maxi(1, champion_level(id)) - 1))
	h.base_hp = int(round(30.0 * float(template["hp_ratio"]) * float(rank["mult"]) * grow))
	h.base_dmg = int(round(8.0 * float(template["dmg_ratio"]) * float(rank["mult"]) * grow))
	h.base_spd = int(round(float(GameData.find_role(role)["base_spd"]) * float(rank["mult"])))
	h.formation = str(GameData.ROLE_POSITION.get(role, {}).get("row", "front"))
	h.attrs = GameData.role_attrs(role)
	h.attr_points = (lv - 1) * GameData.ATTR_POINTS_PER_LEVEL
	Combat.auto_spend_attrs(h)
	h.hp = Combat.max_hp(h)
	return h

func current_party() -> Array[Hero]:
	var out: Array[Hero] = []
	for id in run.get("hero_ids", []):
		var h := find_hero(id)
		if h:
			out.append(h)
	return out


## The B/A/S jump (a real named subclass forking off — see the CLASS_POOL doc
## comment) additionally needs a sealed rift of that rank; the earlier
## F-E-D-C climb (still the same un-named identity throughout) doesn't need
## one, same as before this system existed. The player picks which candidate
## (`target_pool_id`, one of GameData.evolution_choices) — the biggest build
## decision a hero gets, so it's a choice, not a roll.
func evolve_hero(hero_id: String, target_pool_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	if h.level < 10:
		return tr("Must be Level 10 to evolve")
	var cur_cls := GameData.find_class(h.pool_id)
	if cur_cls.is_empty():
		return tr("This hero predates the evolution system")
	var choices := GameData.evolution_choices(cur_cls)
	if choices.is_empty():
		return tr("No further evolution available")
	var next_rank_id: String = choices[0]["rank"]
	var next_rank := GameData.find_rank(next_rank_id)
	if crystals < int(next_rank["cost"]):
		return tr("Not enough Essence")
	var gate := evolve_rank_gate(next_rank_id)
	if gate != "":
		return gate
	var picked: Array = choices.filter(func(c): return c["id"] == target_pool_id)
	if picked.is_empty():
		return tr("Pick an evolution path")
	var next: Dictionary = picked[0]
	var cur_rank := GameData.find_rank(cur_cls["rank"])
	crystals -= int(next_rank["cost"])
	# Keeps exactly the one stage being left behind reachable — see the doc
	# comment on Hero.prior_pool_id for why this isn't an unbounded history.
	h.prior_pool_id = h.pool_id
	h.prior_innate_kind = h.innate_kind
	h.prior_innate_value = h.innate_value
	var ratio_mult: float = (float(next["hp_ratio"]) / float(cur_cls["hp_ratio"])) * (float(next_rank["mult"]) / float(cur_rank["mult"]))
	var dmg_ratio_mult: float = (float(next["dmg_ratio"]) / float(cur_cls["dmg_ratio"])) * (float(next_rank["mult"]) / float(cur_rank["mult"]))
	h.base_hp = int(round(h.base_hp * ratio_mult))
	h.base_dmg = int(round(h.base_dmg * dmg_ratio_mult))
	h.pool_id = next["id"]
	h.rank = next["rank"]
	h.type = next["type"]
	h.flavor = next["flavor"]
	h.innate_kind = next["kind"]
	var rank_idx := GameData.rank_index(next["rank"])
	h.innate_value = Combat.hero_innate_value(next, rank_idx)
	h.name = "%s the %s" % [h.name.split(" the ")[0], next["name"]]
	h.hp = Combat.max_hp(h)
	var passive := GameData.subclass_passive(h.pool_id)
	push_toast(h, tr("Evolved — Rank %s") % tr(str(h.rank)), tr("%s · new passive: %s") % [tr(str(h.name)), tr(str(passive.get("name", "none")))])
	if h.rank == "B":   # the Path's first fork into a calling: a scene (the Guildhold Chronicle)
		var scene := str(GameData.CALLING_SCENES.get(GameData.hero_voice(h), GameData.CALLING_SCENES["stoic"]))
		pending_stories.append({"title": tr("A calling: %s") % tr(str(next["name"])), "subtitle": tr(str(h.name)),
			"text": tr(scene) % [tr(str(h.name.split(" the ")[0])), tr(str(next["name"]))]})
	save()
	state_changed.emit()
	return ""


## B/A/S evolutions need a rift of that rank sealed once; "" if met.
func evolve_rank_gate(rank_id: String) -> String:
	if rank_id in ["B", "A", "S"] and best_rift_rank_sealed < GameData.rift_rank_index(rank_id):
		return tr("Seal a Rank %s rift first") % tr(str(rank_id))
	return ""


## A hero topped up to a buffed max_hp during a run (a boon's +hp_pct, say)
## would otherwise be left with hp above their real max back at camp.
func _clamp_hp_to_max() -> void:
	for h in heroes:
		h.battered = false   # back at camp, the field patch-up no longer holds them back
		h.hp = min(h.hp, Combat.max_hp(h))


## `kind` identifies which of the hero's unlocked trees `skill_id` belongs
## to (a bare node id — "cap", "mastery", ...) — ignored for the universal
## Tier-1 roots ("edge"/"hide"), which are shared across every tree.
func learn_skill(hero_id: String, kind: String, skill_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	var n := GameData.find_skill_node(kind, skill_id, h.cls_id)
	var key := GameData.skill_storage_key(kind, skill_id)
	if n.is_empty() or h.skills.get(key, false):
		return ""
	if h.level < int(n["req_level"]):
		return tr("Requires Level %d") % n["req_level"]
	for req in n["requires"]:
		if not h.skills.get(GameData.skill_storage_key(kind, req), false):
			return tr("Learn the prerequisite skill(s) first")
	if not n.get("requires_any", []).is_empty() and not n["requires_any"].any(func(r): return h.skills.get(GameData.skill_storage_key(kind, r), false)):
		return tr("Master one of this tree's paths first")
	for excl in n.get("excludes", []):
		if h.skills.get(GameData.skill_storage_key(kind, excl), false):
			return tr("Locked out — you already chose the other path")
	if n.has("rift_rank") and best_rift_rank_sealed < GameData.rift_rank_index(str(n["rift_rank"])):
		return tr("Seal a Rank %s or higher rift first") % tr(str(n["rift_rank"]))
	if n.get("stone", false) and crystals < GameData.STONEBOUND_CRYSTALS:
		return tr("Needs %d Essence") % GameData.STONEBOUND_CRYSTALS
	var cost := skill_node_cost(h, kind, n)
	if h.skill_points < cost:
		return tr("Not enough Skill Points")
	h.skill_points -= cost
	if n.get("stone", false):
		crystals -= GameData.STONEBOUND_CRYSTALS
	h.skills[key] = true
	save()
	state_changed.emit()
	return ""


## Spends SP once to make a hero's existing Active Ability trigger more
## often (see GameData's Ability Awakening doc comment) — a second SP sink
## next to the skill tree, not a replacement for it. One-time per hero:
## already-awakened is a no-op refusal, not a stacking cooldown reduction.
## A Tier-3 fork costs 1 SP less (never below 1) for a hero whose trait
## already leans into its stat, or whose scar the fork would shore up.
func skill_node_cost(h: Hero, kind: String, n: Dictionary) -> int:
	var cost := int(n.get("cost", 0))
	if int(n.get("tier", 0)) == 3 and fork_discounted(h, str(n.get("kind", ""))):
		cost = max(1, cost - 1)
	return cost


## A quirk that leans into `stat` (a boost, or a scar that wounds it) makes
## that fork's tier-3 node cheaper.
func fork_discounted(h: Hero, stat: String) -> bool:
	for q in h.quirks:
		var t := GameData.quirk(q)
		var v := float(t.get("stats", {}).get(stat, 0.0))
		if (v > 0.0 and t["origin"] != "scar") or (v < 0.0 and t["origin"] == "scar"):
			return true
	return false


func awaken_ability(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	if not Combat.qualifies_for_ability(h):
		return tr("This hero has no Active Ability yet")
	if h.ability_awakened:
		return tr("Already awakened")
	if h.skill_points < GameData.ABILITY_AWAKENING_COST:
		return tr("Not enough Skill Points")
	h.skill_points -= GameData.ABILITY_AWAKENING_COST
	h.ability_awakened = true
	save()
	state_changed.emit()
	return ""


## For a KIND_SKILL_PACKAGE finisher's `combo_kind` field (GameData doc
## comment above KIND_SKILL_PACKAGE) — true if some OTHER current-run party
## member has reached `kind`'s own Tier-3 capstone (cap or cap_alt; the
## asymmetric kinds' cap_third/no-fork shapes still resolve through "cap").
func party_has_other_kind_capstone(exclude_hero_id: String, kind: String) -> bool:
	if run.is_empty():
		return false
	for hid in run.get("hero_ids", []):
		if str(hid) == exclude_hero_id:
			continue
		var h2 := find_hero(str(hid))
		if not h2:
			continue
		if h2.skills.get(GameData.skill_storage_key(kind, "cap"), false) or h2.skills.get(GameData.skill_storage_key(kind, "cap_alt"), false):
			return true
	return false


## Real SP cost of a set of learned skill keys — sums each node's actual
## `cost`, not just a count of learned nodes (those differ, since Tier-3/4
## nodes cost more SP than Tier-1/2 ones — counting nodes instead of summing
## cost under-refunded a hero who'd learned any higher-tier node).
func _skill_keys_sp_cost(keys: Array, h: Hero = null) -> int:
	var total := 0
	for key in keys:
		var key_str := str(key)
		if not key_str.contains(":"):
			total += int(GameData.find_skill_node("", key_str).get("cost", 0))
		else:
			var parts := key_str.split(":", true, 1)
			if parts.size() == 2:
				var n := GameData.find_skill_node(parts[0], parts[1])
				total += skill_node_cost(h, parts[0], n) if h else int(n.get("cost", 0))
	return total


func respec_cost(spent_sp: int) -> int:
	return int(round(float(20 + 10 * spent_sp) * (1.0 - respec_fee_reduction())))


## Coin cost to respec a hero's `kind` tree right now (or every tree, if
## `kind` is empty) — same accounting respec_hero() itself uses, exposed so
## the UI can show the real price on the button instead of guessing.
func tree_respec_cost(h: Hero, kind: String = "") -> int:
	var target_keys: Array = []
	for key in h.skills.keys():
		if h.skills[key] and (kind == "" or str(key).begins_with("%s:" % tr(str(kind)))):
			target_keys.append(key)
	return respec_cost(_skill_keys_sp_cost(target_keys, h))


## `kind` empty respecs every tree at once (and the universal Tier-1 roots);
## given, only that one tree's own nodes clear — the universal roots and any
## other tree's progress are untouched. A hero holds at most 2 trees at once
## (see Hero.prior_pool_id), so "just this one" is a real, much cheaper
## option next to nuking everything to fix one fork choice.
func respec_hero(hero_id: String, kind: String = "") -> String:
	var h := find_hero(hero_id)
	if not h:
		return ""
	var target_keys: Array = []
	for key in h.skills.keys():
		if not h.skills[key]:
			continue
		if kind == "" or str(key).begins_with("%s:" % tr(str(kind))):
			target_keys.append(key)
	if target_keys.is_empty():
		return ""
	var spent_sp := _skill_keys_sp_cost(target_keys, h)
	var cost := respec_cost(spent_sp)
	if coins < cost:
		return tr("Need %d Gold") % cost
	coins -= cost
	h.skill_points += spent_sp
	for key in target_keys:
		h.skills.erase(key)
	save()
	state_changed.emit()
	return ""


## A Legendary item's locked_role/locked_subclasses restricts who can equip
## it — empty on both means no restriction (every normal item, and most
## Legendaries).
## Has this hero enough of the item's attribute to equip it?
func attr_req_met(it: Item, h: Hero) -> bool:
	return it.attr_req <= 0 or Combat.hero_attr(h, it.attr) - (it.attr_bonus if it.equipped_to == h.id else 0) >= it.attr_req


func auto_assign_attrs(hero_id: String) -> void:
	var h := find_hero(hero_id)
	if not h or h.attr_points <= 0:
		return
	Combat.auto_spend_attrs(h)
	save()
	state_changed.emit()


## Points a hero has put into attributes beyond their role's starting spread.
func attr_points_spent(h: Hero) -> int:
	var base := GameData.role_attrs(GameData.hero_role(h))
	var n := 0
	for a in GameData.ATTRIBUTES:
		n += int(h.attrs.get(a, GameData.ATTR_BASELINE)) - int(base[a])
	return max(n, 0)


func attr_respec_cost(h: Hero) -> int:
	return h.level * GameData.RESPEC_CRYSTALS_PER_LEVEL


## Refunds every spent attribute point for Crystals. Gear whose requirement
## the hero no longer meets comes off (otherwise a reset could keep gear on
## that the new build couldn't equip).
func respec_attrs(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return tr("Can't reset this hero")
	var refund := attr_points_spent(h)
	if refund <= 0:
		return tr("Nothing to reset")
	var cost := attr_respec_cost(h)
	if crystals < cost:
		return tr("Not enough Essence")
	crystals -= cost
	h.attrs = GameData.role_attrs(GameData.hero_role(h))
	h.attr_points += refund
	for it in items:
		if it.equipped_to == h.id and not attr_req_met(it, h):
			it.equipped_to = ""
			it.equipped_idx = -1
	save()
	state_changed.emit()
	return ""


func attr_train_cost(h: Hero) -> int:
	return GameData.ATTR_TRAIN_COST * (h.attr_trained + 1)


## Buys one attribute point with Coins (see ATTR_TRAIN_CAP).
func train_attr(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if not h:
		return tr("Can't train this hero")
	if h.attr_trained >= GameData.ATTR_TRAIN_CAP:
		return tr("Fully trained")
	if training_left() <= 0:
		return tr("The Training Yard is full this week")
	var cost := attr_train_cost(h)
	if coins < cost:
		return tr("Not enough Gold")
	coins -= cost
	var week := day / GameData.PAYDAY_DAYS
	if training_week != week:
		training_week = week
		trained_this_week = 0
	trained_this_week += 1
	h.attr_trained += 1
	h.attr_points += 1
	save()
	state_changed.emit()
	return ""


func spend_attr_point(hero_id: String, a: String) -> void:
	var h := find_hero(hero_id)
	if not h or h.attr_points <= 0 or not GameData.ATTRIBUTES.has(a):
		return
	h.attrs[a] = int(h.attrs.get(a, GameData.ATTR_BASELINE)) + 1
	h.attr_points -= 1
	save()
	state_changed.emit()


func item_fits_hero(it: Item, h: Hero) -> bool:
	if it.locked_role != "" and h.cls_id != it.locked_role:
		return false
	if not it.locked_subclasses.is_empty() and not it.locked_subclasses.has(h.pool_id):
		return false
	return true
