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
var skills: Dictionary = {}      # skill_id -> true
var base_hp: int
var base_dmg: int
var trait_name: String = ""      # "" means no trait ("Steadfast")
var downed_until: int = 0        # msec timestamp, 0 = not downed
var bedded: bool = false
var hp: int = 0
var is_champion: bool = false


func is_downed() -> bool:
	return downed_until > 0 and downed_until > Time.get_unix_time_from_system() * 1000


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "cls_id": cls_id, "pool_id": pool_id, "type": type,
		"flavor": flavor, "rank": rank, "innate_kind": innate_kind, "innate_value": innate_value,
		"level": level, "xp": xp, "skill_points": skill_points, "skills": skills,
		"base_hp": base_hp, "base_dmg": base_dmg, "trait_name": trait_name,
		"downed_until": downed_until, "bedded": bedded, "hp": hp, "is_champion": is_champion,
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
	h.skills = d.get("skills", {})
	h.base_hp = d.get("base_hp", 10)
	h.base_dmg = d.get("base_dmg", 1)
	h.trait_name = d.get("trait_name", "")
	h.downed_until = d.get("downed_until", 0)
	h.bedded = d.get("bedded", false)
	h.hp = d.get("hp", 0)
	h.is_champion = d.get("is_champion", false)
	return h
