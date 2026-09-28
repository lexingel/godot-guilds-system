extends "res://scripts/autoload/game_data/GameDataModes.gd"
## GameData, part 7 (the autoload): lookups across all of the above.
## The chain, bottom up: game_data/GameDataArt.gd (paths, icons, sprites) -> Heroes -> Items
## -> Monsters -> Skills -> Modes -> this file; each part only uses names from below it.


## Prefers a subclass-specific portrait (SUBCLASS_PORTRAIT_PATH, one of the 50
## CLASS_POOL entries) so recruited heroes look visually distinct beyond their
## role. Falls back to the 5 shared role portraits for anything not in that
## map — a Champion's pool_id is never a real subclass id, so this covers
## Champions the same way it always has.
static func portrait_for_hero(cls_id: String, pool_id: String) -> String:
	if SUBCLASS_PORTRAIT_PATH.has(pool_id):
		return SUBCLASS_PORTRAIT_PATH[pool_id]
	var role := cls_id
	if role == "":
		role = find_class(pool_id).get("role", "")
	return HERO_PORTRAIT_PATH.get(role, "")


## An English plural ending for `n` things ("s", or "es" for hero), none in
## Turkish, where a noun after a number stays singular ("3 gün").
## ponytail: suffix-only plurals; switch call sites to tr_n() when a language
## with real plural forms (German, Russian...) is added.
static func pl(n: int, suffix: String = "s") -> String:
	return "" if n == 1 or not TranslationServer.get_locale().begins_with("en") else suffix


static func find_role(role_id: String) -> Dictionary:
	for c in CLASSES:
		if c["id"] == role_id:
			return c
	return {}


static func find_rank(rank_id: String) -> Dictionary:
	for r in RANKS:
		if r["id"] == rank_id:
			return r
	return {}


static func find_rarity(rarity_id: String) -> Dictionary:
	for r in RARITIES:
		if r["id"] == rarity_id:
			return r
	return {}


## key is "branch_id.node_id", e.g. "ops.medical".
static func find_branch_node(key: String) -> Dictionary:
	var parts := key.split(".")
	if parts.size() != 2:
		return {}
	for b in BRANCHES:
		if b["id"] == parts[0]:
			for n in b["nodes"]:
				if n["id"] == parts[1]:
					return n
	return {}


## Looks up a bare node id within a specific kind's package (or a Tier-1
## root, for "edge"/"hide" — `kind` is ignored then, since those are shared
## across every tree). `role` picks which role's Tier-1 flavor to resolve
## against; callers that don't have a hero in scope (pure SP-cost math) can
## omit it since cost/req_level/tier are identical across every role's variant.
static func find_skill_node(kind: String, skill_id: String, role: String = "warrior") -> Dictionary:
	if skill_id == "edge" or skill_id == "hide":
		for n in tier1_for_role(role):
			if n["id"] == skill_id:
				return n
		return {}
	if skill_id == "signature":
		return signature_node(role)
	if skill_id == "keystone":
		return keystone_node(kind)
	for n in rift_nodes(kind):
		if n["id"] == skill_id:
			return n
	for n in KIND_SKILL_PACKAGE.get(kind, []):
		if n["id"] == skill_id:
			return n
	return {}


static func weapon_slots(pool_id: String) -> int:
	return 2 if DUAL_WIELD_CLASSES.has(pool_id) else 1


static func gear_slots(rank_id: String) -> int:
	return 1 + int(floor(rank_index(rank_id) / 2.0))
