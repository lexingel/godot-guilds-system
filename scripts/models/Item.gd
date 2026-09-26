class_name Item
extends RefCounted
## Hero-bound gear — mirrors genItem()'s output shape in guild-system.html.

var id: String
var name: String
var category: String      # weapon/armor/focus
var rarity: String        # common/rare/epic/legendary
var kind: String          # dmg_pct/hp_pct/... (BUILD_KINDS) — the item's primary/only stat
var value: float
# A rolled item's 2nd and 3rd stats (Rare rolls secondary, Epic rolls both) —
# "" kind means that slot is unused. Same flat accumulator shape as
# socketed_kind/drawback_kind below rather than an array, so every existing
# kind->value summing site only needs one more `if` instead of a rewrite.
var secondary_kind: String = ""
var secondary_value: float = 0.0
var tertiary_kind: String = ""
var tertiary_value: float = 0.0
var implicit_kind: String = ""   # fixed stat from the item's base noun (GameData.ITEM_BASE_IMPLICIT)
var implicit_value: float = 0.0
var item_rank: String = ""       # rift rank it dropped at (GameData.RIFT_RANKS id); "" = pre-rank legacy item
var effects: Array = []          # rolled conditional/trigger affixes — Combat.hero_effects entry shape
var equipped_to: String = ""    # hero id, "" = unequipped
var equipped_idx: int = -1      # index within that hero's weapon/gear slots
var socketed_kind: String = ""     # "" = no runestone socketed
var socketed_value: float = 0.0
var unique_id: String = ""      # "" = normal generated item; else a GameData.UNIQUE_ITEMS id
var drawback_kind: String = ""  # "" = no drawback; a Legendary's cost, same BUILD_KINDS vocabulary
var drawback_value: float = 0.0 # stored negative
var locked_role: String = ""    # "" = fits any role; else only that role's heroes can equip
var locked_subclasses: Array[String] = []   # empty = no subclass restriction
var attr: String = ""           # the attribute it trains / needs (GameData.ITEM_BASE_ATTR)
var attr_bonus: int = 0         # + that attribute while equipped
var attr_req: int = 0           # that attribute needed to equip (0 = none)


func slot_type() -> String:
	return "weapon" if category == "weapon" else "gear"


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "category": category, "rarity": rarity, "kind": kind,
		"value": value, "secondary_kind": secondary_kind, "secondary_value": secondary_value,
		"tertiary_kind": tertiary_kind, "tertiary_value": tertiary_value,
		"implicit_kind": implicit_kind, "implicit_value": implicit_value,
		"item_rank": item_rank, "effects": effects,
		"equipped_to": equipped_to, "equipped_idx": equipped_idx,
		"socketed_kind": socketed_kind, "socketed_value": socketed_value,
		"unique_id": unique_id, "drawback_kind": drawback_kind, "drawback_value": drawback_value,
		"locked_role": locked_role, "locked_subclasses": locked_subclasses,
		"attr": attr, "attr_bonus": attr_bonus, "attr_req": attr_req,
	}


static func from_dict(d: Dictionary) -> Item:
	var it := Item.new()
	it.id = d.get("id", "")
	it.name = d.get("name", "")
	it.category = d.get("category", "weapon")
	it.rarity = d.get("rarity", "common")
	it.kind = d.get("kind", "")
	it.value = d.get("value", 0.0)
	it.secondary_kind = d.get("secondary_kind", "")
	it.secondary_value = d.get("secondary_value", 0.0)
	it.tertiary_kind = d.get("tertiary_kind", "")
	it.tertiary_value = d.get("tertiary_value", 0.0)
	it.implicit_kind = d.get("implicit_kind", "")
	it.implicit_value = d.get("implicit_value", 0.0)
	it.item_rank = d.get("item_rank", "")
	it.effects = d.get("effects", [])
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
	if d.has("attr"):
		it.attr = str(d["attr"])
		it.attr_bonus = int(d.get("attr_bonus", 0))
		it.attr_req = int(d.get("attr_req", 0))
	else:
		# Items from before attributes: they get their bonus, but no
		# requirement, so nothing already equipped falls off.
		it.attr = GameData.item_attr_for(it)
		it.attr_bonus = int(GameData.ITEM_ATTR_BONUS.get(it.rarity, 1))
	return it
