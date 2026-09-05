class_name Item
extends RefCounted
## Hero-bound gear — mirrors genItem()'s output shape in guild-system.html.

var id: String
var name: String
var category: String      # weapon/armor/focus
var rarity: String        # common/rare/epic
var kind: String          # dmg_pct/hp_pct/... (BUILD_KINDS)
var value: float
var equipped_to: String = ""    # hero id, "" = unequipped
var equipped_idx: int = -1      # index within that hero's weapon/gear slots


func slot_type() -> String:
	return "weapon" if category == "weapon" else "gear"


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "category": category, "rarity": rarity, "kind": kind,
		"value": value, "equipped_to": equipped_to, "equipped_idx": equipped_idx,
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
	return it
