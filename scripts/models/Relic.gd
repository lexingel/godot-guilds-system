class_name Relic
extends RefCounted
## Party-wide gear — mirrors genRelic()'s output shape in guild-system.html.

var id: String
var name: String
var type: String          # Ember/Frost/Verdant/Umbral/Arcane
var rarity: String        # common/rare/epic/legendary
var dmg: int
var hp: int
var special_kind: String = ""   # "" means no special rolled
var special_value: float = 0.0
var special_label: String = ""
var level: int = 1
var equipped: bool = false
var unique_id: String = ""       # "" = normal generated relic; else a GameData.UNIQUE_RELICS id
var drawback_kind: String = ""   # "" = no drawback; must be a kind relics already aggregate
var drawback_value: float = 0.0  # stored negative
var drawback_label: String = ""
var combo_with: String = ""      # another unique_id that doubles this relic's effect when both are equipped


func has_special() -> bool:
	return special_kind != ""


func desc() -> String:
	var s := "+%d DMG · +%d Shield" % [dmg, hp]
	if has_special():
		s += " · " + special_label
	if drawback_kind != "":
		s += " · " + drawback_label
	return s


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "type": type, "rarity": rarity, "dmg": dmg, "hp": hp,
		"special_kind": special_kind, "special_value": special_value, "special_label": special_label,
		"level": level, "equipped": equipped,
		"unique_id": unique_id, "drawback_kind": drawback_kind, "drawback_value": drawback_value,
		"drawback_label": drawback_label, "combo_with": combo_with,
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
	r.unique_id = d.get("unique_id", "")
	r.drawback_kind = d.get("drawback_kind", "")
	r.drawback_value = d.get("drawback_value", 0.0)
	r.drawback_label = d.get("drawback_label", "")
	r.combo_with = d.get("combo_with", "")
	return r
