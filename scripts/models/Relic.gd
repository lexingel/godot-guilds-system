class_name Relic
extends RefCounted
## Party-wide gear — mirrors genRelic()'s output shape in guild-system.html.

var id: String
var name: String
var type: String          # Ember/Frost/Verdant/Umbral/Arcane
var rarity: String        # common/rare/epic
var dmg: int
var hp: int
var special_kind: String = ""   # "" means no special rolled
var special_value: float = 0.0
var special_label: String = ""
var level: int = 1
var equipped: bool = false


func has_special() -> bool:
	return special_kind != ""


func desc() -> String:
	var s := "+%d DMG · +%d Shield" % [dmg, hp]
	if has_special():
		s += " · " + special_label
	return s


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "type": type, "rarity": rarity, "dmg": dmg, "hp": hp,
		"special_kind": special_kind, "special_value": special_value, "special_label": special_label,
		"level": level, "equipped": equipped,
	}


static func from_dict(d: Dictionary) -> Relic:
	var r := Relic.new()
	r.id = d.get("id", "")
	r.name = d.get("name", "")
	r.type = d.get("type", "")
	r.rarity = d.get("rarity", "common")
	r.dmg = d.get("dmg", 0)
	r.hp = d.get("hp", 0)
	r.special_kind = d.get("special_kind", "")
	r.special_value = d.get("special_value", 0.0)
	r.special_label = d.get("special_label", "")
	r.level = d.get("level", 1)
	r.equipped = d.get("equipped", false)
	return r
