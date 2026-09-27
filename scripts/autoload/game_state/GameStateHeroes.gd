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
			gained.append("%s earned %s!" % [h.name, q])
			push_toast(h, "Quirk earned: %s" % q, "%s — %s" % [h.name.split(" the ")[0], quirk_text(q)])
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
		return "Build the Arcane Lab first"
	var h := find_hero(hero_id)
	if not h or not h.quirks.has(q) or not GameData.quirk(q).get("treatable", false):
		return ""
	var cost := quirk_treat_cost()
	if coins < cost:
		return "Need %d Gold" % cost
	coins -= cost
	h.quirks.erase(q)
	h.hp = mini(h.hp, Combat.max_hp(h))
	save()
	state_changed.emit()
	return ""


func quirk_treat_cost() -> int:
	return int(round(GameData.QUIRK_TREAT_COST * (1.0 - respec_fee_reduction())))


func find_hero(hero_id: String) -> Hero:
	for h in heroes:
		if h.id == hero_id:
			return h
	return null


func gen_recruit_offer(force_rank: String = "") -> Hero:
	return Combat.gen_hero(force_rank if force_rank != "" else Combat.weighted_rank(), 1)


## Flags pending_s_rank_reveal whenever a blind roll (recruit offer, Champion
## reroll/init) lands Rank S — Main.render() consumes it once, the same way
## it already consumes _flavor_toast, so the celebration shows up wherever
## the player is instead of only on the Recruits screen.
func _maybe_flag_s_rank(h: Hero, source: String) -> void:
	if h.rank == "S":
		pending_s_rank_reveal = {"name": h.name, "cls_id": h.cls_id, "pool_id": h.pool_id, "source": source}


func refresh_recruit_pool() -> void:
	recruit_pool = []
	for i in recruit_offer_count():
		recruit_pool.append(gen_recruit_offer())
	if headhunter_guarantee():
		var order: Array[String] = []
		for r in GameData.RANKS:
			order.append(r["id"])
		var has_good := recruit_pool.any(func(h): return order.find(h.rank) >= 3)
		if not has_good:
			var good_ranks := ["C", "B", "A", "S"]
			recruit_pool[0] = gen_recruit_offer(good_ranks[randi() % good_ranks.size()])
	for h in recruit_pool:
		_maybe_flag_s_rank(h, "recruit")


func recruit_hero(offer_id: String) -> String:
	var idx := -1
	for i in recruit_pool.size():
		if recruit_pool[i].id == offer_id:
			idx = i
			break
	if idx < 0:
		return ""
	if heroes.size() >= hero_slot_cap():
		return "Roster is full."
	var offer := recruit_pool[idx]
	var rank := GameData.find_rank(offer.rank)
	if coins < int(rank["cost"]):
		return "Not enough Gold."
	coins -= int(rank["cost"])
	var is_dupe := heroes.any(func(h): return h.pool_id == offer.pool_id)
	if guild_mentor():
		offer.level = 2
		offer.skill_points += 1
		offer.base_hp = int(round(offer.base_hp * 1.08))
		offer.base_dmg = int(round(offer.base_dmg * 1.08))
		offer.hp = Combat.max_hp(offer)
	heroes.append(offer)
	recruit_pool[idx] = gen_recruit_offer()
	if is_dupe:
		var refund := int(round(float(rank["cost"]) * 0.5))
		coins += refund
	save()
	state_changed.emit()
	return ""


## Champions for hire: fills the offers if there are none.
func ensure_champion_offers() -> void:
	if champion_offers.is_empty():
		refresh_champion_offers()


func reroll_recruit_offer(offer_id: String) -> String:
	var idx := -1
	for i in recruit_pool.size():
		if recruit_pool[i].id == offer_id:
			idx = i
			break
	if idx < 0:
		return ""
	if coins < recruit_reroll_cost():
		return "Not enough Gold."
	coins -= recruit_reroll_cost()
	recruit_pool[idx] = gen_recruit_offer()
	_maybe_flag_s_rank(recruit_pool[idx], "recruit")
	save()
	state_changed.emit()
	return ""


## A fresh set of Champion offers for Coins (a free set arrives every seal).
func reroll_champion() -> String:
	if coins < GameData.CHAMPION_REROLL_COST:
		return "Not enough Gold."
	coins -= GameData.CHAMPION_REROLL_COST
	refresh_champion_offers()
	save()
	state_changed.emit()
	return ""


func refresh_champion_offers() -> void:
	champion_offers.clear()
	var roles := {}
	for i in GameData.CHAMPION_OFFER_COUNT:
		# Different roles where the dice allow, so it's a real choice of Boon/Call.
		var c := Combat.generate_champion()
		for attempt in 12:
			if not roles.has(champion_role(c)):
				break
			c = Combat.generate_champion()
		roles[champion_role(c)] = true
		_maybe_flag_s_rank(c, "champion")
		_sync_level(c)
		c.hp = Combat.max_hp(c)
		champion_offers.append(c)


func _sync_level(c: Hero) -> void:
	var target := 1
	for h in heroes:
		target = max(target, h.level)
	while c.level < target:
		c.level += 1
		c.base_hp = int(round(c.base_hp * (1.0 + GameData.LEVEL_GROWTH)))
		c.base_dmg = int(round(c.base_dmg * (1.0 + GameData.LEVEL_GROWTH)))
		c.attr_points += GameData.ATTR_POINTS_PER_LEVEL
	Combat.auto_spend_attrs(c)


func champion_role(c: Hero) -> String:
	return str(GameData.find_class(c.pool_id).get("role", "warrior"))


## The party-wide Boon while the Champion is standing in a run.
func champion_boon(kind: String) -> float:
	if run.is_empty():
		return 0.0
	var total := 0.0
	for c in current_party():
		if not c.is_champion or c.hp <= 0:
			continue
		var b: Dictionary = GameData.CHAMPION_BOONS.get(champion_role(c), {})
		if b.get("kind", "") == kind:
			total += float(b["value"]) * float(GameData.find_rank(c.rank)["mult"])
	return total


func champion_boon_text(c: Hero) -> String:
	var b: Dictionary = GameData.CHAMPION_BOONS.get(champion_role(c), {})
	if b.is_empty():
		return ""
	return "%s — party %s" % [b["name"], Combat.describe_skill(str(b["kind"]), float(b["value"]) * float(GameData.find_rank(c.rank)["mult"]))]


## The Champion's Call as an Active-Ability-shaped dict {name, effect, value}.
func champion_call(c: Hero) -> Dictionary:
	return GameData.CHAMPION_CALLS.get(champion_role(c), GameData.CHAMPION_CALLS["warrior"])


func champion_call_ready(h: Hero) -> bool:
	if not h.is_champion or run.is_empty():
		return false
	var allowed := 2 if Combat.party_has_unique_relic("crown_of_oaths") else 1
	return int(run.get("champion_calls", 0)) < allowed


func champion_hire_cost(c: Hero) -> int:
	return int(GameData.find_rank(c.rank)["cost"]) * GameData.CHAMPION_HIRE_MULT


## Hires Champion offer `idx` for Gold: a seasoned hero (as experienced as
## your best) who keeps their party Boon and Champion's Call.
func hire_champion(idx: int) -> String:
	if idx < 0 or idx >= champion_offers.size():
		return ""
	if heroes.size() >= hero_slot_cap():
		return "Roster is full."
	var c := champion_offers[idx]
	var cost := champion_hire_cost(c)
	if coins < cost:
		return "Not enough Gold."
	coins -= cost
	var cls := GameData.find_class(c.pool_id)
	c.cls_id = str(cls.get("role", "warrior"))
	c.innate_value = Combat.hero_innate_value(cls, GameData.rank_index(c.rank))
	var born := Combat.roll_born_quirk(c.cls_id)
	c.quirks.assign([born] if born != "" else [])
	c.skill_points = c.level - 1
	c.hp = Combat.max_hp(c)
	heroes.append(c)
	champion_offers.remove_at(idx)
	push_toast(c, "Champion hired", "%s joins your roster" % c.name.split(" the ")[0])
	save()
	state_changed.emit()
	return ""


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
		return "Must be Level 10 to evolve"
	var cur_cls := GameData.find_class(h.pool_id)
	if cur_cls.is_empty():
		return "This hero predates the evolution system"
	var choices := GameData.evolution_choices(cur_cls)
	if choices.is_empty():
		return "No further evolution available"
	var next_rank_id: String = choices[0]["rank"]
	var next_rank := GameData.find_rank(next_rank_id)
	if crystals < int(next_rank["cost"]):
		return "Not enough Essence"
	var gate := evolve_rank_gate(next_rank_id)
	if gate != "":
		return gate
	var picked: Array = choices.filter(func(c): return c["id"] == target_pool_id)
	if picked.is_empty():
		return "Pick an evolution path"
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
	push_toast(h, "Evolved — Rank %s" % h.rank, "%s · new passive: %s" % [h.name, str(passive.get("name", "none"))])
	save()
	state_changed.emit()
	return ""


## B/A/S evolutions need a rift of that rank sealed once; "" if met.
func evolve_rank_gate(rank_id: String) -> String:
	if rank_id in ["B", "A", "S"] and best_rift_rank_sealed < GameData.rift_rank_index(rank_id):
		return "Seal a Rank %s rift first" % rank_id
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
		return "Requires Level %d" % n["req_level"]
	for req in n["requires"]:
		if not h.skills.get(GameData.skill_storage_key(kind, req), false):
			return "Learn the prerequisite skill(s) first"
	if not n.get("requires_any", []).is_empty() and not n["requires_any"].any(func(r): return h.skills.get(GameData.skill_storage_key(kind, r), false)):
		return "Master one of this tree's paths first"
	for excl in n.get("excludes", []):
		if h.skills.get(GameData.skill_storage_key(kind, excl), false):
			return "Locked out — you already chose the other path"
	if n.has("rift_rank") and best_rift_rank_sealed < GameData.rift_rank_index(str(n["rift_rank"])):
		return "Seal a Rank %s or higher rift first" % n["rift_rank"]
	if n.get("stone", false) and crystals < GameData.STONEBOUND_CRYSTALS:
		return "Needs %d Essence" % GameData.STONEBOUND_CRYSTALS
	var cost := skill_node_cost(h, kind, n)
	if h.skill_points < cost:
		return "Not enough Skill Points"
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
		return "This hero has no Active Ability yet"
	if h.ability_awakened:
		return "Already awakened"
	if h.skill_points < GameData.ABILITY_AWAKENING_COST:
		return "Not enough Skill Points"
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
		if h.skills[key] and (kind == "" or str(key).begins_with("%s:" % kind)):
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
		if kind == "" or str(key).begins_with("%s:" % kind):
			target_keys.append(key)
	if target_keys.is_empty():
		return ""
	var spent_sp := _skill_keys_sp_cost(target_keys, h)
	var cost := respec_cost(spent_sp)
	if coins < cost:
		return "Need %d Gold" % cost
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
		return "Can't reset this hero"
	var refund := attr_points_spent(h)
	if refund <= 0:
		return "Nothing to reset"
	var cost := attr_respec_cost(h)
	if crystals < cost:
		return "Not enough Essence"
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
		return "Can't train this hero"
	if h.attr_trained >= GameData.ATTR_TRAIN_CAP:
		return "Fully trained"
	var cost := attr_train_cost(h)
	if coins < cost:
		return "Not enough Gold"
	coins -= cost
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
