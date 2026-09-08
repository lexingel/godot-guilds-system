class_name Item
extends RefCounted
## Hero-bound gear — mirrors genItem()'s output shape in guild-system.html.

var id: String
var name: String
var category: String      # weapon/armor/focus
var rarity: String        # common/rare/epic/legendary
var kind: String          # dmg_pct/hp_pct/... (BUILD_KINDS)
var value: float
var equipped_to: String = ""    # hero id, "" = unequipped
var equipped_idx: int = -1      # index within that hero's weapon/gear slots
var socketed_kind: String = ""     # "" = no runestone socketed
var socketed_value: float = 0.0
var unique_id: String = ""      # "" = normal generated item; else a GameData.UNIQUE_ITEMS id
var drawback_kind: String = ""  # "" = no drawback; a Legendary's cost, same BUILD_KINDS vocabulary
var drawback_value: float = 0.0 # stored negative
var locked_role: String = ""    # "" = fits any role; else only that role's heroes can equip
var locked_subclasses: Array[String] = []   # empty = no subclass restriction


func slot_type() -> String:
	return "weapon" if category == "weapon" else "gear"


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "category": category, "rarity": rarity, "kind": kind,
		"value": value, "equipped_to": equipped_to, "equipped_idx": equipped_idx,
		"socketed_kind": socketed_kind, "socketed_value": socketed_value,
		"unique_id": unique_id, "drawback_kind": drawback_kind, "drawback_value": drawback_value,
		"locked_role": locked_role, "locked_subclasses": locked_subclasses,
	}


static func from_dict(d: Dictionary) -> Item:
	var it := Item.new()
	it.id = d.get("id", "")
	it.name = d.get("name", "")
	it.category = d.get("category", "weapon")
	it.rarity = d.get("rarity", "common")
	it.kind = d.get("kind", "")
	it.value = d.get("value", 0.0)
	it.equipped_to = d.get("equipped_to", "")
	it.equipped_idx = d.get("equipped_idx", -1)
	it.socketed_kind = d.get("socketed_kind", "")
	it.socketed_value = d.get("socketed_value", 0.0)
	it.unique_id = d.get("unique_id", "")
	it.drawback_kind = d.get("drawback_kind", "")
	it.drawback_value = d.get("drawback_value", 0.0)
	it.locked_role = d.get("locked_role", "")
	var subs: Array = d.get("locked_subclasses", [])
	it.locked_subclasses.assign(subs)
	return it
