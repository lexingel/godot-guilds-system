class_name Hero
extends RefCounted
## Typed hero model — mirrors the hero object shape from guild-system.html's
## genHero()/state.heroes entries, but as a real class instead of a duck-typed
## dictionary, so fields get autocomplete/type-checking in the editor.

var id: String
var name: String
var cls_id: String       # role: warrior/ranger/mage/cleric/rogue
var pool_id: String       # CLASS_POOL entry id
var type: String          # elemental type (Ember/Frost/Verdant/Umbral/Arcane)
var flavor: String
var rank: String          # F..S
var innate_kind: String
var innate_value: float
var level: int = 1
var xp: int = 0
var skill_points: int = 0
var skills: Dictionary = {}      # skill_id -> true. Keys are "<kind>:<node_id>" for KIND_SKILL_PACKAGE nodes (every kind package reuses the same node ids — "cap", "mastery", etc. — so this avoids collisions once a hero can hold more than one tree) or the bare id for the universal Tier-1 roots ("edge"/"hide"), which are shared/learned once across every tree.
# Evolving keeps exactly the ONE most recent past stage reachable — not an
# unbounded chain back to the hero's original class. A single field rather
# than a growing list: an unlimited history would let one hero accumulate
# a tree (and an innate bonus) per rank ever passed through, which turns
# "evolve" into a strictly-better move than ever recruiting/pulling a hero
# directly at that final rank, and rewards chain-evolving through every
# intermediate rank in one sitting purely to stack breadth. Capping at one
# prior stage keeps the "your last investment isn't wasted" promise intact
# without that snowball.
var prior_pool_id: String = ""            # "" = never evolved (or evolved once already superseded by a second evolution)
var prior_innate_kind: String = ""        # the innate bonus from prior_pool_id's class — same one-stage cap as the tree above
var prior_innate_value: float = 0.0
var base_hp: int
var base_dmg: int
var trait_name: String = ""      # "" means no trait ("Steadfast")
var scars: Array[String] = []    # earned from being knocked out in combat, capped at 2
var downed_until: int = 0        # msec timestamp, 0 = not downed
var heal_until: int = 0          # msec timestamp, 0 = not scheduled (full HP, or downed instead)
var bedded: bool = false
var hp: int = 0
var is_champion: bool = false
var ability_cooldown: int = 0    # rounds until Ability is usable again; ticks down once per node, not per fight
var formation: String = "front"  # "front" or "back" — biases monster retaliation targeting


func is_downed() -> bool:
	return downed_until > 0 and downed_until > Time.get_unix_time_from_system() * 1000


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "cls_id": cls_id, "pool_id": pool_id, "type": type,
		"flavor": flavor, "rank": rank, "innate_kind": innate_kind, "innate_value": innate_value,
		"level": level, "xp": xp, "skill_points": skill_points, "skills": skills,
		"base_hp": base_hp, "base_dmg": base_dmg, "trait_name": trait_name, "scars": scars,
		"downed_until": downed_until, "heal_until": heal_until, "bedded": bedded, "hp": hp, "is_champion": is_champion,
		"ability_cooldown": ability_cooldown, "formation": formation, "prior_pool_id": prior_pool_id,
		"prior_innate_kind": prior_innate_kind, "prior_innate_value": prior_innate_value,
	}


static func from_dict(d: Dictionary) -> Hero:
	var h := Hero.new()
	h.id = d.get("id", "")
	h.name = d.get("name", "")
	h.cls_id = d.get("cls_id", "")
	h.pool_id = d.get("pool_id", "")
	h.type = d.get("type", "")
	h.flavor = d.get("flavor", "")
	h.rank = d.get("rank", "F")
	h.innate_kind = d.get("innate_kind", "")
	h.innate_value = d.get("innate_value", 0.0)
	h.level = d.get("level", 1)
	h.xp = d.get("xp", 0)
	h.skill_points = d.get("skill_points", 0)
	if d.has("prior_pool_id"):
		h.prior_pool_id = d.get("prior_pool_id", "")
		h.prior_innate_kind = d.get("prior_innate_kind", "")
		h.prior_innate_value = d.get("prior_innate_value", 0.0)
	else:
		# One-release-old format: an unbounded evolved_pool_ids list instead
		# of a single prior_pool_id. Best-effort — take the most recent
		# entry; the innate bonus for it can't be recovered (that field
		# didn't exist yet), so it's lost for anyone on this exact save
		# version. Self-correcting: the next evolution overwrites it anyway.
		var old_list: Array = d.get("evolved_pool_ids", [])
		if not old_list.is_empty():
			h.prior_pool_id = str(old_list[-1])
	# Raw pass-through — skill-key migration for saves predating the
	# kind-namespaced format lives in GameState.migrate_hero_skill_keys()
	# instead of here, since it needs GameData (Hero.gd stays a plain
	# RefCounted model with no autoload dependencies).
	h.skills = d.get("skills", {})
	h.base_hp = d.get("base_hp", 10)
	h.base_dmg = d.get("base_dmg", 1)
	h.trait_name = d.get("trait_name", "")
	h.scars.assign(d.get("scars", []))
	h.downed_until = d.get("downed_until", 0)
	h.heal_until = d.get("heal_until", 0)
	h.bedded = d.get("bedded", false)
	h.hp = d.get("hp", 0)
	h.is_champion = d.get("is_champion", false)
	h.ability_cooldown = d.get("ability_cooldown", 0)
	h.formation = d.get("formation", "front")
	return h
