class_name Relic
extends RefCounted
## Party-wide gear. Every relic carries at least one special (a party-wide
## stat, see GameData.RELIC_SPECIALS); rare and epic ones also carry a
## trigger (an effect that fires in battle, GameData.RELIC_TRIGGERS), and a
## level-5 relic awakens with one more special. Legendaries are fixed picks
## from GameData.UNIQUE_RELICS with a bespoke effect.

var id: String
var name: String
var type: String          # Ember/Frost/Verdant/Umbral/Arcane
var rarity: String        # common/rare/epic/legendary
var dmg: int
var hp: int
var specials: Array = []         # [{kind, value, label}]
var trigger: Dictionary = {}     # {trigger, effect, value} in Combat's effect shape, or {}
var level: int = 1
var awakened: bool = false
var rerolls: int = 0
var equipped: bool = false
var unique_id: String = ""       # "" = normal generated relic; else a GameData.UNIQUE_RELICS id
var drawback_kind: String = ""   # "" = no drawback; must be a kind relics already aggregate
var drawback_value: float = 0.0  # stored negative
var drawback_label: String = ""
var combo_with: String = ""      # another unique_id that doubles this relic's effect when both are equipped


func has_special() -> bool:
	return not specials.is_empty()


func desc() -> String:
	var parts: Array[String] = [tr("+%d DMG · +%d Shield") % [dmg, hp]]
	for s in specials:
		parts.append(str(s["label"]))
	if not trigger.is_empty():
		parts.append(Combat.describe_effect(trigger, true))
	if drawback_kind != "":
		parts.append(drawback_label)
	return " · ".join(parts)


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "type": type, "rarity": rarity, "dmg": dmg, "hp": hp,
		"specials": specials, "trigger": trigger, "awakened": awakened, "rerolls": rerolls,
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
	r.level = d.get("level", 1)
	r.equipped = d.get("equipped", false)
	r.unique_id = d.get("unique_id", "")
	r.drawback_kind = d.get("drawback_kind", "")
	r.drawback_value = d.get("drawback_value", 0.0)
	r.drawback_label = d.get("drawback_label", "")
	r.combo_with = d.get("combo_with", "")
	r.awakened = bool(d.get("awakened", false))
	r.rerolls = int(d.get("rerolls", 0))
	r.trigger = d.get("trigger", {})
	if d.has("specials"):
		r.specials = d["specials"]
	else:
		# From before every relic had an effect: keep the old special, and a
		# plain stat-stick relic gains one now.
		if str(d.get("special_kind", "")) != "":
			r.specials = [{"kind": str(d["special_kind"]), "value": float(d.get("special_value", 0.0)), "label": str(d.get("special_label", ""))}]
		elif r.unique_id == "":
			r.specials = [Combat.roll_relic_special(r.type, r.rarity, [])]
	return r
