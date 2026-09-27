extends "res://scripts/autoload/game_data/GameDataHeroes.gd"
## GameData, part 3: unique (Legendary) items and relics, Tower relics included.


## The attribute an item trains / needs.
static func item_attr_for(it) -> String:
	if it.unique_id != "":
		return str(UNIQUE_ARCH_ATTR.get(str(find_unique_item(it.unique_id).get("arch", "")), "might"))
	return str(ITEM_BASE_ATTR.get(item_base(it), "might"))

## Legendary items: fixed (never rolled) hero-bound gear. Their mechanic is
## plain data in "effects" — the shared EFFECT vocabulary Combat.hero_effects
## reads (see the doc comment above Combat.hero_effects for the entry shape) —
## plus, on most, a real drawback in the flat kind vocabulary so it still flows
## through hero_item_total/hero_skill_total for free. "locked_role"/
## "locked_subclasses" restrict who can equip it - "" / [] means no restriction.
const UNIQUE_ITEMS := [
	{"id": "bloodthirst_fang", "name": "Bloodthirst Fang", "category": "weapon", "arch": "sustain",
	 "effects": [{"trigger": "after_hit", "effect": "lifesteal", "value": 0.25}],
	 "drawback_kind": "hazard_guard_pct", "drawback_value": -0.15,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "Heals the wielder for 25% of the damage they deal each round they attack. -15% hazard severity guard."},
	{"id": "widows_edge", "name": "Widow's Edge", "category": "weapon", "arch": "executioner",
	 "effects": [{"trigger": "before_hit", "effect": "execute_below", "value": 0.15}],
	 "drawback_kind": "dmg_pct", "drawback_value": -0.10,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "Instantly finishes a foe this hero's attack would drop below 15% HP. -10% damage otherwise."},
	{"id": "last_stand_plate", "name": "Last Stand Plate", "category": "armor", "arch": "evasion",
	 "effects": [{"kind": "dodge_pct", "value": 0.30, "scale": "missing_hp"}],
	 "drawback_kind": "dodge_pct", "drawback_value": -0.10,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "The lower this hero's HP, up to +30% dodge chance near death. -10% dodge chance at full HP."},
	{"id": "oathbound_talisman", "name": "Oathbound Talisman", "category": "focus", "arch": "sustain",
	 "effects": [{"trigger": "party_mend", "effect": "shield_lowest", "value": 0.15}],
	 "drawback_kind": "dmg_pct", "drawback_value": -0.15,
	 "locked_role": "cleric", "locked_subclasses": [],
	 "desc": "Whenever the party mends, also shields the lowest-HP ally for 15% of their max HP. -15% damage. Cleric only."},
	# -- Build-defining additions, one or more per archetype, several built
	# around the speed/turn-order system specifically. --
	{"id": "reapers_due", "name": "Reaper's Due", "category": "weapon", "arch": "executioner",
	 "effects": [{"trigger": "on_kill", "effect": "extra_turn", "value": 1.0}],
	 "drawback_kind": "hp_pct", "drawback_value": -0.10,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "On a kill, this hero immediately acts again (once per round). -10% HP."},
	{"id": "quickening_band", "name": "Quickening Band", "category": "focus", "arch": "opener",
	 "effects": [{"kind": "dmg_pct", "value": 0.02, "scale": "speed_above_10"}],
	 "drawback_kind": "hp_pct", "drawback_value": -0.08,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "+2% damage for every point of Speed above 10. -8% HP."},
	{"id": "millstone_maul", "name": "Millstone Maul", "category": "weapon", "arch": "attrition",
	 "effects": [{"kind": "dmg_pct", "value": 0.50, "cond": {"acting_last": true}}],
	 "drawback_kind": "speed_pct", "drawback_value": -0.40,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "+50% damage when this hero is the last in the round to act. -40% Speed."},
	{"id": "hourglass_of_first_light", "name": "Hourglass of First Light", "category": "focus", "arch": "opener",
	 "effects": [{"kind": "dmg_pct", "value": 0.40, "cond": {"acting_first": true}}],
	 "drawback_kind": "hp_pct", "drawback_value": -0.08,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "+40% damage when this hero acts first in the round. -8% HP."},
	{"id": "wardens_oath", "name": "Warden's Oath", "category": "armor", "arch": "guardian",
	 "effects": [{"trigger": "ally_targeted", "effect": "intercept", "value": 0.60}],
	 "drawback_kind": "dodge_pct", "drawback_value": -0.10,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "60% chance to step in front of a blow aimed at an ally below half HP. -10% dodge chance."},
	{"id": "ember_of_the_last_hour", "name": "Ember of the Last Hour", "category": "focus", "arch": "executioner",
	 "effects": [{"kind": "dmg_pct", "value": 0.45, "cond": {"hp_below": 0.35}}],
	 "drawback_kind": "hp_pct", "drawback_value": -0.10,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "+45% damage while this hero is below 35% HP. -10% HP."},
	{"id": "chronoblade", "name": "Chronoblade", "category": "weapon", "arch": "evasion",
	 "effects": [{"trigger": "evade_or_heavy", "effect": "shave_cooldowns", "value": 0.60}],
	 "drawback_kind": "dmg_pct", "drawback_value": -0.08,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "60% chance to cool every Ability by 1 round when this hero dodges or takes a heavy hit. -8% damage."},
	{"id": "bossbane_spear", "name": "Bossbane Spear", "category": "weapon", "arch": "executioner",
	 "effects": [{"kind": "dmg_pct", "value": 0.40, "cond": {"vs_boss": true}}],
	 "drawback_kind": "first_round_pct", "drawback_value": -0.10,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "+40% damage in Boss fights. -10% first-strike damage."},
]

## Legendary relics: same idea as UNIQUE_ITEMS but party-wide. `effect`/`value`
## dispatch via Combat.party_has_unique_relic; drawback kinds are restricted
## to ones relic specials already aggregate into (mend/dodge/escalate/
## hazard_guard/first_round/wipe_guard - never dmg_pct/hp_pct, which relics
## have no path into). "combo_with" is another unique_id that, when also
## equipped, doubles this relic's own effect (checked by combo_partner_id).
const UNIQUE_RELICS := [
	{"id": "gamblers_coin", "name": "The Gambler's Coin", "type": "Ember",
	 "effect": "coinflip_dmg", "value": 0.0,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "",
	 "combo_with": "",
	 "desc": "Each round: 50% chance the party's damage is doubled, 50% chance it's halved."},
	{"id": "ashes_of_the_fallen", "name": "Ashes of the Fallen", "type": "Umbral",
	 "effect": "desperation_dmg", "value": 0.30,
	 "drawback_kind": "hazard_guard_pct", "drawback_value": -0.10, "drawback_label": "-10% hazard severity guard",
	 "combo_with": "twin_embers",
	 "desc": "+damage the more wounded the party collectively is, up to +30% at the brink of death. -10% hazard severity guard."},
	{"id": "sable_standard", "name": "Sable Standard", "type": "Arcane",
	 "effect": "mono_role_dmg", "value": 0.25,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "",
	 "combo_with": "",
	 "desc": "+25% team damage, but only while every living hero shares the same role."},
	{"id": "twin_embers", "name": "Twin Embers", "type": "Ember",
	 "effect": "", "value": 0.0,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "",
	 "combo_with": "ashes_of_the_fallen",
	 "special_kind": "escalate_pct", "special_value": 0.02,
	 "desc": "+2% dmg/round (stacking) on its own. Paired with Ashes of the Fallen, that relic's desperation bonus doubles."},
	{"id": "phoenix_feather", "name": "Phoenix Feather", "type": "Ember", "effect": "phoenix", "value": 0.30,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "", "combo_with": "",
	 "desc": "Once per rift, when the whole party falls, everyone rises again at 30% HP."},
	{"id": "wardens_seal", "name": "Warden's Seal", "type": "Umbral", "effect": "slow_fuses", "value": 0.0,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "", "combo_with": "",
	 "special_kind": "hazard_guard_pct", "special_value": 0.08,
	 "desc": "Rift Map rifts skip every third day of their countdown. -8% hazard severity."},
	{"id": "crown_of_oaths", "name": "Crown of Oaths", "type": "Arcane", "effect": "double_call", "value": 0.0,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "", "combo_with": "",
	 "desc": "The Champion's Call can be used twice per rift."},
	{"id": "bloodpact", "name": "Bloodpact Dagger", "type": "Umbral", "effect": "bloodpact", "value": 0.35,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "", "combo_with": "",
	 "desc": "+35% team damage, but the party never mends between rounds."},
	{"id": "quartermasters_ledger", "name": "Quartermaster's Ledger", "type": "Arcane", "effect": "quest_bonus", "value": 0.5,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "", "combo_with": "",
	 "special_kind": "loot_rarity_pct", "special_value": 0.05,
	 "desc": "Guild Board quests pay 50% more Coins and Crystals. +5% odds toward Rare/Epic loot."},
	{"id": "lantern_of_the_lost", "name": "Lantern of the Lost", "type": "Verdant", "effect": "free_carry", "value": 0.0,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "", "combo_with": "",
	 "special_kind": "mend_pct", "special_value": 0.02,
	 "desc": "Carrying a downed hero out of a rift costs no day. Mends 2% HP/round."},
	{"id": "stopped_clock", "name": "The Stopped Clock", "type": "Frost", "effect": "frozen_round", "value": 0.0,
	 "drawback_kind": "first_round_pct", "drawback_value": -0.15, "drawback_label": "-15% first-strike damage", "combo_with": "",
	 "desc": "Foes can't act in the first round of a fight. -15% first-strike damage."},
	{"id": "mirror_shard", "name": "Mirror Shard", "type": "Frost", "effect": "mirror", "value": 0.0,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "", "combo_with": "",
	 "desc": "Copies every special of your best other equipped relic."},
	{"id": "stormcaller_idol", "name": "Stormcaller Idol", "type": "Ember", "effect": "", "value": 0.0,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "", "combo_with": "",
	 "trigger": {"trigger": "round_third", "effect": "nova", "value": 0.6},
	 "desc": "Every third round, lightning strikes every foe for 60% of the party's damage."},
	{"id": "prism_heart", "name": "Prism Heart", "type": "Arcane", "effect": "prism_heart", "value": 0.05,
	 "drawback_kind": "", "drawback_value": 0.0, "drawback_label": "", "combo_with": "",
	 "desc": "+5% team damage for each different element among your standing heroes."},
]


static func find_unique_item(unique_id: String) -> Dictionary:
	for u in UNIQUE_ITEMS:
		if u["id"] == unique_id:
			return u
	return {}


## A relic's icon: a Legendary's own, else its first special's, else its type gem.
static func relic_icon(r) -> String:
	var path := ""
	if r.unique_id != "":
		path = "res://assets/relics/u_%s.png" % r.unique_id
	elif not r.specials.is_empty():
		path = "res://assets/relics/%s.png" % str(r.specials[0]["kind"])
	if path != "" and ResourceLoader.exists(path):
		return path
	return RELIC_TYPE_ICON_PATH.get(r.type, CHEST_ICON_PATH)


static func find_unique_relic(unique_id: String) -> Dictionary:
	for u in UNIQUE_RELICS + TOWER_RELICS.values():
		if u["id"] == unique_id:
			return u
	return {}

## Relics only the Tower's guardians give (first clear of that floor). Same
## schema as UNIQUE_RELICS; only special_kind/trigger, no bespoke effects.
const TOWER_RELICS := {
	10: {"id": "t_gate_key", "name": "Gatekeeper's Key", "type": "Arcane", "special_kind": "first_round_pct", "special_value": 0.3,
		"desc": "+30% first-strike damage."},
	20: {"id": "t_mire_lantern", "name": "Mire Lantern", "type": "Verdant", "special_kind": "mend_pct", "special_value": 0.04,
		"desc": "Mends 4% HP every round."},
	30: {"id": "t_cinder_brand", "name": "Cinder Brand", "type": "Ember", "special_kind": "escalate_pct", "special_value": 0.04,
		"desc": "+4% damage every round (stacking)."},
	40: {"id": "t_choir_bell", "name": "Choir Bell", "type": "Arcane", "trigger": {"trigger": "round_third", "effect": "shield_party", "value": 0.15},
		"desc": "Every third round, shields the whole party for 15% of max HP."},
	50: {"id": "t_tide_mirror", "name": "Tide Mirror", "type": "Frost", "special_kind": "dodge_pct", "special_value": 0.12,
		"desc": "+12% dodge chance."},
	60: {"id": "t_regent_crown", "name": "Regent's Crown", "type": "Ember", "special_kind": "boss_alpha_strike", "special_value": 0.6,
		"desc": "+60% opening volley against bosses."},
	70: {"id": "t_grave_thread", "name": "Gravewright's Thread", "type": "Umbral", "special_kind": "wipe_guard", "special_value": 0.35,
		"desc": "Relic ward: once a fight, survive a wipe at 35% HP."},
	80: {"id": "t_oracle_eye", "name": "Oracle's Eye", "type": "Frost", "special_kind": "counter_pct", "special_value": 0.3,
		"desc": "+30% chance to counter when evading or hit hard."},
	90: {"id": "t_ashfather_coal", "name": "Ashfather's Coal", "type": "Ember", "trigger": {"trigger": "round_third", "effect": "nova", "value": 0.8},
		"desc": "Every third round, fire strikes every foe for 80% of the party's damage."},
	100: {"id": "t_summit_star", "name": "Summit Star", "type": "Arcane", "special_kind": "escalate_pct", "special_value": 0.05,
		"trigger": {"trigger": "round_third", "effect": "nova", "value": 1.0},
		"desc": "+5% damage every round (stacking), and every third round a starfall hits every foe for 100% of the party's damage."},
}
