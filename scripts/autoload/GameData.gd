extends Node
## Static data tables — a near-mechanical port of the `const` tables in
## guild-system.html. No behavior lives here, only data, mirroring the
## HTML prototype's data/logic split. Keys use snake_case per GDScript
## convention; the JS camelCase originals are named in comments where it
## helps cross-reference the source.

const CLASSES := [
	{"id": "warrior", "name": "Warrior", "base_hp": 36, "base_dmg": 6, "badge": "W"},
	{"id": "ranger", "name": "Ranger", "base_hp": 27, "base_dmg": 8, "badge": "R"},
	{"id": "mage", "name": "Mage", "base_hp": 19, "base_dmg": 11, "badge": "M"},
	{"id": "cleric", "name": "Cleric", "base_hp": 31, "base_dmg": 5, "badge": "C"},
	{"id": "rogue", "name": "Rogue", "base_hp": 23, "base_dmg": 9, "badge": "G"},
]

# Item/relic rarity only — heroes and Champions use RANKS below.
const RARITIES := [
	{"id": "common", "name": "Common", "mult": 1.0, "cost": 40, "weight": 60},
	{"id": "rare", "name": "Rare", "mult": 1.4, "cost": 120, "weight": 32},
	{"id": "epic", "name": "Epic", "mult": 1.9, "cost": 320, "weight": 8},
]

const POS_TRAITS := ["Battle-Hardened", "Swift", "Iron Skin"]
const NEG_TRAITS := ["Frail", "Reckless", "Slothful"]

# Trait kind-keys use the same BUILD_KINDS vocabulary as skills/items/relics
# so they flow through Combat.hero_skill_total for free.
const TRAIT_TABLE := {
	"Battle-Hardened": {"dmg_pct": 0.1},
	"Swift": {"dmg_pct": 0.05},
	"Iron Skin": {"hp_pct": 0.15},
	"Frail": {"hp_pct": -0.15},
	"Reckless": {"dmg_pct": -0.05, "hp_pct": -0.05},
	"Slothful": {"dmg_pct": -0.1},
	# Role-exclusive double-edged traits (see ROLE_TRAITS below).
	"Juggernaut": {"hazard_guard_pct": 0.10, "dodge_pct": -0.08},
	"Deadeye": {"first_round_pct": 0.15, "hp_pct": -0.08},
	"Overtuned": {"escalate_pct": 0.03, "hp_pct": -0.10},
	"Zealous Mercy": {"mend_pct": 0.04, "dmg_pct": -0.06},
	"Glass Dagger": {"dodge_pct": 0.10, "hazard_guard_pct": -0.08},
}

# One per role, rolled only for that role — on top of the universal pool above.
const ROLE_TRAITS := {
	"warrior": "Juggernaut",
	"ranger": "Deadeye",
	"mage": "Overtuned",
	"cleric": "Zealous Mercy",
	"rogue": "Glass Dagger",
}

static func is_role_trait(trait_name: String) -> bool:
	return ROLE_TRAITS.values().has(trait_name)

const RELIC_TYPES := ["Ember", "Frost", "Verdant", "Umbral", "Arcane"]

# Each type nudges (doesn't lock) which power domain a relic's special favors —
# see Combat.domain_for_type. Domains map 1:1 onto the 5 types.
const RELIC_SPECIALS := [
	{"kind": "mend_pct", "value": 0.02, "domain": "heal", "label": "Mends 2% HP/round"},
	{"kind": "dodge_pct", "value": 0.05, "domain": "chance", "label": "+5% dodge chance"},
	{"kind": "escalate_pct", "value": 0.015, "domain": "damage", "label": "+1.5% dmg/round (stacking)"},
	{"kind": "hazard_guard_pct", "value": 0.06, "domain": "defense", "label": "-6% hazard severity"},
	{"kind": "first_round_pct", "value": 0.06, "domain": "damage", "label": "+6% first-strike damage"},
	{"kind": "wipe_guard", "value": 0.08, "domain": "defense", "label": "Relic ward: survive a wipe at 8% HP"},
	{"kind": "boss_alpha_strike", "value": 0.3, "domain": "damage", "label": "+30% opening volley vs Bosses"},
	{"kind": "loot_rarity_pct", "value": 0.06, "domain": "droprate", "label": "+6% odds toward Rare/Epic loot"},
]

const TYPE_DOMAIN := {
	"Ember": "damage", "Verdant": "heal", "Frost": "chance",
	"Umbral": "defense", "Arcane": "droprate",
}

# Equipping 3+ of one element grants that element's own bonus.
const SYNERGY_BONUS := {
	"Ember": {"kind": "dmg_pct", "value": 0.15, "label": "+15% team damage"},
	"Frost": {"kind": "dodge_pct", "value": 0.12, "label": "+12% dodge chance"},
	"Verdant": {"kind": "mend_pct", "value": 0.08, "label": "Mends 8% of the party's HP pool each round"},
	"Umbral": {"kind": "hazard_guard_pct", "value": 0.15, "label": "-15% hazard severity"},
	"Arcane": {"kind": "loot_rarity_pct", "value": 0.10, "label": "+10% odds toward Rare/Epic loot"},
}

# Items: hero-bound gear distinct from party-wide Relics. 3 category umbrellas:
# Weapon (offense), Armor (survival), Focus (utility). Weapon items fill a
# hero's weapon slots; Armor/Focus items share one "gear" slot pool.
const ITEM_CATEGORIES := ["weapon", "armor", "focus"]
const ITEM_CATEGORY_LABEL := {"weapon": "Weapon", "armor": "Armor", "focus": "Focus"}
const ITEM_CATEGORY_KINDS := {
	"weapon": ["dmg_pct", "first_round_pct", "escalate_pct"],
	"armor": ["hp_pct", "hazard_guard_pct", "mend_pct"],
	"focus": ["dodge_pct"],
}
const ITEM_NOUNS := {
	"weapon": ["Blade", "Bow", "Staff", "Mace", "Dagger"],
	"armor": ["Plate", "Guard", "Bracer", "Greaves", "Mail"],
	"focus": ["Ring", "Amulet", "Charm", "Band", "Talisman"],
}
const ITEM_KIND_BASE := {
	"dmg_pct": 0.12, "hp_pct": 0.12, "first_round_pct": 0.15, "escalate_pct": 0.04,
	"mend_pct": 0.06, "hazard_guard_pct": 0.12, "dodge_pct": 0.10,
}

# Classes agile/skilled enough to dual-wield get 2 weapon slots instead of 1 —
# all 10 Rogues plus 3 hand-picked classes whose flavor fits.
const DUAL_WIELD_CLASSES := [
	"scavenger", "runaway", "cutpurse", "skirmisher", "footpad", "shadowfoot",
	"fleetblade", "nightblade", "wraithstep", "duskrunner",
	"duelist", "blade-dancer", "zealot",
]

const BOSS_MECHANICS := [
	{"id": "enrage", "name": "Enraged", "desc": "Strikes harder the longer the fight drags on (past round 4)."},
	{"id": "warded", "name": "Warded", "desc": "Shields and dodge cannot mitigate its first two retaliations."},
	{"id": "regen", "name": "Regenerating", "desc": "Heals a portion of its health back each round it survives."},
	{"id": "frenzied", "name": "Frenzied", "desc": "Hits harder than expected from the very first round."},
]

const HAZARD_TYPES := [
	{"id": "poison", "name": "Poison Fog", "dmg_mult": 1.0, "bonus_chance": 0.3, "bonus_type": "crystals"},
	{"id": "lava", "name": "Cracked Lava Floor", "dmg_mult": 1.3, "bonus_chance": 0.15, "bonus_type": "crystals"},
	{"id": "collapse", "name": "Collapsing Passage", "dmg_mult": 1.1, "bonus_chance": 0.2, "bonus_type": "coins"},
	{"id": "wraith", "name": "Wailing Wraiths", "dmg_mult": 0.8, "bonus_chance": 0.4, "bonus_type": "crystals"},
	{"id": "vault", "name": "Sealed Vault Trap", "dmg_mult": 1.2, "bonus_chance": 0.5, "bonus_type": "coins"},
]

const FIRST_NAMES := ["Aldric", "Bryn", "Coren", "Dessa", "Elowen", "Fenwick", "Gara", "Hollis", "Ianthe", "Joric", "Kestrel", "Liora", "Maren", "Nyx", "Oren", "Petra", "Quill", "Roth", "Sable", "Tavin", "Ysolde", "Zeph"]
const MONSTER_NAMES := ["Gloom Stalker", "Rift Wisp", "Husk Brute", "Sable Fang", "Ember Whelp", "Marrow Crawler", "Hollow Reaver", "Cinder Moth"]
const ELITE_NAMES := ["Warbound Elite", "Blightfang Elite", "Rift-Touched Colossus", "Iron Revenant", "Storm-Called Elite", "Ashen Broodlord"]
const BOSS_NAMES := ["Vaelith", "Korrath", "Nyxara", "Drevok", "Sythrane"]

# Vertical slice: only Lesser Rift is active. Greater/Ascendant/Endless are
# deferred — see the plan's "explicitly deferred" list.
const DIFFICULTIES := [
	{"id": "lesser", "name": "Lesser Rift", "floors": 7, "monster_hp": 38, "monster_dmg": 5, "coin": [18, 34], "crystal": [5, 11], "token_base": 10, "detector_chance": 0.08, "power": "Low", "rec_power": 70},
]

# Endless Rift scales forever off these base stats (matches the HTML
# version's ENDLESS_BASE, which is Ascendant Rift's numbers regardless of
# whether Ascendant itself is a selectable tier in this port).
const ENDLESS_BASE := {"monster_hp": 125, "monster_dmg": 14, "coin": [85, 140], "crystal": [20, 36], "token_base": 36, "detector_chance": 0.22, "rec_power": 280}

const ABILITIES := {
	"warrior": {"name": "Rally", "desc": "+30% team damage for the rest of this fight."},
	"ranger": {"name": "Piercing Volley", "desc": "-40% the monster's damage for the rest of this fight."},
	"mage": {"name": "Overcharge", "desc": "An immediate burst of damage against the monster."},
	"cleric": {"name": "Blessing", "desc": "Fully heals the party immediately."},
	"rogue": {"name": "Ambush", "desc": "This round's attack deals +90% damage."},
}

# Every class tree shares the same shape: 2 generic Tier-1 nodes, 3
# class-flavored Tier-2 nodes (only 2 gate the capstone), one capstone.
const CLASS_SKILLS := {
	"warrior": [
		{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Honed Edge", "requires": []},
		{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "hp_pct", "value": 0.08, "name": "Thick Hide", "requires": []},
		{"id": "vanguard", "tier": 2, "req_level": 4, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Vanguard Strike", "requires": ["edge"]},
		{"id": "shieldwall", "tier": 2, "req_level": 4, "cost": 1, "kind": "dodge_pct", "value": 0.10, "name": "Shield Wall", "requires": ["hide"]},
		{"id": "instinct", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.08, "name": "Battle Instinct", "requires": []},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "wipe_guard", "value": 0.25, "name": "Last Stand", "requires": ["vanguard", "shieldwall"]},
	],
	"ranger": [
		{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Honed Edge", "requires": []},
		{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "hp_pct", "value": 0.08, "name": "Thick Hide", "requires": []},
		{"id": "focus", "tier": 2, "req_level": 4, "cost": 1, "kind": "first_round_pct", "value": 0.12, "name": "Focused Shot", "requires": ["edge"]},
		{"id": "lightfoot", "tier": 2, "req_level": 4, "cost": 1, "kind": "hazard_guard_pct", "value": 0.10, "name": "Light-Footed", "requires": ["hide"]},
		{"id": "sustain", "tier": 2, "req_level": 5, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Sustained Aim", "requires": []},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "first_round_pct", "value": 0.35, "name": "Dead Eye", "requires": ["focus", "lightfoot"]},
	],
	"mage": [
		{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Honed Edge", "requires": []},
		{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "hp_pct", "value": 0.08, "name": "Thick Hide", "requires": []},
		{"id": "buildup", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Arcane Buildup", "requires": ["edge"]},
		{"id": "ward", "tier": 2, "req_level": 4, "cost": 1, "kind": "hazard_guard_pct", "value": 0.10, "name": "Ward Sigil", "requires": ["hide"]},
		{"id": "slip", "tier": 2, "req_level": 5, "cost": 1, "kind": "dodge_pct", "value": 0.08, "name": "Arcane Slip", "requires": []},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "boss_alpha_strike", "value": 1.0, "name": "Cataclysm", "requires": ["buildup", "ward"]},
	],
	"cleric": [
		{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Honed Edge", "requires": []},
		{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "hp_pct", "value": 0.08, "name": "Thick Hide", "requires": []},
		{"id": "smite", "tier": 2, "req_level": 4, "cost": 1, "kind": "dmg_pct", "value": 0.10, "name": "Smite", "requires": ["edge"]},
		{"id": "mending", "tier": 2, "req_level": 4, "cost": 1, "kind": "mend_pct", "value": 0.05, "name": "Mending Chant", "requires": ["hide"]},
		{"id": "ward2", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.08, "name": "Ward of Mercy", "requires": []},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "mend_pct", "value": 0.10, "name": "Guardian Angel", "requires": ["smite", "mending"]},
	],
	"rogue": [
		{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Honed Edge", "requires": []},
		{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "hp_pct", "value": 0.08, "name": "Thick Hide", "requires": []},
		{"id": "momentum", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Momentum", "requires": ["edge"]},
		{"id": "evasion", "tier": 2, "req_level": 4, "cost": 1, "kind": "dodge_pct", "value": 0.12, "name": "Evasion", "requires": ["hide"]},
		{"id": "gambit", "tier": 2, "req_level": 5, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Opening Gambit", "requires": []},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "dmg_pct", "value": 0.20, "name": "Shadow Strike", "requires": ["momentum", "evasion"]},
	],
}

# Champion system (deferred beyond this slice, but the rank ladder is shared
# with recruited heroes, so it's ported now). Rank sets weight (pull odds),
# stat multiplier, and hero rank progression via evolution.
const RANKS := [
	{"id": "F", "weight": 100, "mult": 0.9, "cost": 25},
	{"id": "E", "weight": 60, "mult": 1.0, "cost": 45},
	{"id": "D", "weight": 35, "mult": 1.15, "cost": 75},
	{"id": "C", "weight": 20, "mult": 1.35, "cost": 130},
	{"id": "B", "weight": 10, "mult": 1.6, "cost": 220},
	{"id": "A", "weight": 4, "mult": 2.0, "cost": 380},
	{"id": "S", "weight": 1, "mult": 2.6, "cost": 650},
]

const CHAMP_KIND_BASE := {
	"dmg_pct": 0.06, "hp_pct": 0.06, "first_round_pct": 0.15, "escalate_pct": 0.02,
	"mend_pct": 0.03, "dodge_pct": 0.08, "hazard_guard_pct": 0.10, "wipe_guard": 0.2, "boss_alpha_strike": 1.0,
}

# 50 classes across the 5 roles, 10 per role. `role` picks the CLASS_SKILLS
# tree; rank/kind/flavor are the same F-S vocabulary the Champion pool uses.
const CLASS_POOL := [
	# -- Warrior (melee bruisers & tanks) --
	{"id": "squire", "name": "Squire", "role": "warrior", "rank": "F", "type": "Ember", "hp_ratio": 1.0, "dmg_ratio": 1.0, "kind": "dmg_pct", "flavor": "A guild recruit swinging a borrowed blade."},
	{"id": "footman", "name": "Footman", "role": "warrior", "rank": "F", "type": "Umbral", "hp_ratio": 1.2, "dmg_ratio": 0.8, "kind": "hazard_guard_pct", "flavor": "Slow, sturdy, and hard to put down."},
	{"id": "duelist", "name": "Duelist", "role": "warrior", "rank": "E", "type": "Ember", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "first_round_pct", "flavor": "Wins the exchange before it starts."},
	{"id": "bulwark", "name": "Bulwark", "role": "warrior", "rank": "E", "type": "Umbral", "hp_ratio": 1.3, "dmg_ratio": 0.7, "kind": "hp_pct", "flavor": "A wall with opinions."},
	{"id": "berserker", "name": "Berserker", "role": "warrior", "rank": "D", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 1.3, "kind": "dmg_pct", "flavor": "Considers armor a personal insult."},
	{"id": "iron-guard", "name": "Iron Guard", "role": "warrior", "rank": "C", "type": "Umbral", "hp_ratio": 1.4, "dmg_ratio": 0.8, "kind": "hp_pct", "flavor": "Rift-forged plate, dented and unbothered."},
	{"id": "bloodletter", "name": "Bloodletter", "role": "warrior", "rank": "C", "type": "Ember", "hp_ratio": 0.9, "dmg_ratio": 1.3, "kind": "escalate_pct", "flavor": "Trades wounds and wins the trade."},
	{"id": "runeblade", "name": "Runeblade", "role": "warrior", "rank": "B", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 1.2, "kind": "first_round_pct", "flavor": "Every strike is already inscribed."},
	{"id": "ashen-templar", "name": "Ashen Templar", "role": "warrior", "rank": "A", "type": "Umbral", "hp_ratio": 1.3, "dmg_ratio": 1.0, "kind": "wipe_guard", "flavor": "Has died before. Didn't care for it."},
	{"id": "rift-sovereign", "name": "Rift Sovereign", "role": "warrior", "rank": "S", "type": "Arcane", "hp_ratio": 1.1, "dmg_ratio": 1.4, "kind": "boss_alpha_strike", "flavor": "The Rift answers to almost nothing. Almost."},
	# -- Ranger (precision & terrain reading) --
	{"id": "trapper", "name": "Trapper", "role": "ranger", "rank": "F", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Sets more snares than the Rift can spring."},
	{"id": "slinger", "name": "Slinger", "role": "ranger", "rank": "F", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 1.0, "kind": "dmg_pct", "flavor": "Improvises a weapon out of whatever's at hand."},
	{"id": "pathfinder", "name": "Pathfinder", "role": "ranger", "rank": "E", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Already knows where the floor gives way."},
	{"id": "longshot", "name": "Longshot", "role": "ranger", "rank": "E", "type": "Frost", "hp_ratio": 0.8, "dmg_ratio": 1.1, "kind": "first_round_pct", "flavor": "One arrow. Rarely needs a second."},
	{"id": "blade-dancer", "name": "Blade Dancer", "role": "ranger", "rank": "D", "type": "Ember", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "first_round_pct", "flavor": "The opening strike is the whole performance."},
	{"id": "warden", "name": "Warden", "role": "ranger", "rank": "D", "type": "Verdant", "hp_ratio": 1.1, "dmg_ratio": 0.9, "kind": "hp_pct", "flavor": "Has walked through worse hallways than this."},
	{"id": "stormtracker", "name": "Stormtracker", "role": "ranger", "rank": "D", "type": "Frost", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "escalate_pct", "flavor": "Follows the lightning instead of waiting for thunder."},
	{"id": "rift-ranger", "name": "Rift Ranger", "role": "ranger", "rank": "C", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 1.1, "kind": "dodge_pct", "flavor": "Reads a hallway before it reads back."},
	{"id": "deadfall-hunter", "name": "Deadfall Hunter", "role": "ranger", "rank": "C", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 1.0, "kind": "hazard_guard_pct", "flavor": "Sets the trap the Rift walks into instead."},
	{"id": "voidwalker", "name": "Voidwalker", "role": "ranger", "rank": "A", "type": "Arcane", "hp_ratio": 0.9, "dmg_ratio": 1.2, "kind": "dodge_pct", "flavor": "Half-stepped out of the fight before it began."},
	# -- Mage (escalating & warding casters) --
	{"id": "apprentice", "name": "Apprentice", "role": "mage", "rank": "F", "type": "Arcane", "hp_ratio": 0.8, "dmg_ratio": 0.9, "kind": "escalate_pct", "flavor": "Still learning to hold a spark steady."},
	{"id": "cinderling", "name": "Cinderling", "role": "mage", "rank": "F", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 0.9, "kind": "dmg_pct", "flavor": "Sparks first, thinks second."},
	{"id": "fledgling-seer", "name": "Fledgling Seer", "role": "mage", "rank": "F", "type": "Arcane", "hp_ratio": 0.9, "dmg_ratio": 0.8, "kind": "hazard_guard_pct", "flavor": "Sees the trap a half-second before it triggers."},
	{"id": "cinder-adept", "name": "Cinder Adept", "role": "mage", "rank": "E", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 1.0, "kind": "escalate_pct", "flavor": "Every spell warms up the next."},
	{"id": "frost-scholar", "name": "Frost Scholar", "role": "mage", "rank": "E", "type": "Frost", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Studies the Rift's cold so it can't study back."},
	{"id": "wardweaver", "name": "Wardweaver", "role": "mage", "rank": "D", "type": "Arcane", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Weaves a ward faster than the Rift can break it."},
	{"id": "stormcaller", "name": "Stormcaller", "role": "mage", "rank": "C", "type": "Frost", "hp_ratio": 0.8, "dmg_ratio": 1.1, "kind": "escalate_pct", "flavor": "Calls down more with every passing second."},
	{"id": "pyromancer", "name": "Pyromancer", "role": "mage", "rank": "B", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 1.2, "kind": "dodge_pct", "flavor": "The Rift itself seems to lean away."},
	{"id": "archon-of-storms", "name": "Archon of Storms", "role": "mage", "rank": "A", "type": "Frost", "hp_ratio": 1.0, "dmg_ratio": 1.2, "kind": "boss_alpha_strike", "flavor": "Opens every Warden's door with thunder."},
	{"id": "the-unbound", "name": "The Unbound", "role": "mage", "rank": "S", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 1.3, "kind": "escalate_pct", "flavor": "No name holds it. No floor stops it."},
	# -- Cleric (sustain & support) --
	{"id": "peddler", "name": "Peddler", "role": "cleric", "rank": "F", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 0.8, "kind": "mend_pct", "flavor": "Sells bandages. Uses them too."},
	{"id": "acolyte", "name": "Acolyte", "role": "cleric", "rank": "F", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 0.8, "kind": "mend_pct", "flavor": "Prays quietly, heals quietly."},
	{"id": "herbalist", "name": "Herbalist", "role": "cleric", "rank": "E", "type": "Verdant", "hp_ratio": 1.0, "dmg_ratio": 0.8, "kind": "mend_pct", "flavor": "Carries a field kit for every wound."},
	{"id": "lay-brother", "name": "Lay Brother", "role": "cleric", "rank": "E", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 0.9, "kind": "dmg_pct", "flavor": "Swings a censer like it owes him money."},
	{"id": "battle-chaplain", "name": "Battle Chaplain", "role": "cleric", "rank": "D", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 0.9, "kind": "dodge_pct", "flavor": "Prays loudly enough to keep the party moving."},
	{"id": "zealot", "name": "Zealot", "role": "cleric", "rank": "D", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "dmg_pct", "flavor": "Faith, mostly. A blade, occasionally."},
	{"id": "rift-medic", "name": "Rift Medic", "role": "cleric", "rank": "C", "type": "Verdant", "hp_ratio": 1.0, "dmg_ratio": 0.9, "kind": "mend_pct", "flavor": "Faster hands than the Rift has wounds to give."},
	{"id": "dawnkeeper", "name": "Dawnkeeper", "role": "cleric", "rank": "B", "type": "Arcane", "hp_ratio": 1.1, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Carries first light into the deepest floor."},
	{"id": "sanctified-shield", "name": "Sanctified Shield", "role": "cleric", "rank": "B", "type": "Arcane", "hp_ratio": 1.3, "dmg_ratio": 0.9, "kind": "wipe_guard", "flavor": "Swears the party will not fall today."},
	{"id": "alchemist", "name": "Alchemist", "role": "cleric", "rank": "B", "type": "Verdant", "hp_ratio": 1.0, "dmg_ratio": 1.0, "kind": "escalate_pct", "flavor": "Brews faster than the Rift can wound."},
	# -- Rogue (evasion & burst) --
	{"id": "scavenger", "name": "Scavenger", "role": "rogue", "rank": "F", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Knows which puddles not to step in."},
	{"id": "runaway", "name": "Runaway", "role": "rogue", "rank": "F", "type": "Umbral", "hp_ratio": 0.8, "dmg_ratio": 0.9, "kind": "dodge_pct", "flavor": "Has never once stood and fought fair."},
	{"id": "cutpurse", "name": "Cutpurse", "role": "rogue", "rank": "F", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 1.0, "kind": "dmg_pct", "flavor": "Leaves with more than they came with."},
	{"id": "skirmisher", "name": "Skirmisher", "role": "rogue", "rank": "E", "type": "Ember", "hp_ratio": 0.9, "dmg_ratio": 1.0, "kind": "dodge_pct", "flavor": "Never where the last swing landed."},
	{"id": "footpad", "name": "Footpad", "role": "rogue", "rank": "E", "type": "Frost", "hp_ratio": 0.8, "dmg_ratio": 1.0, "kind": "hazard_guard_pct", "flavor": "Nobody's ever heard them arrive."},
	{"id": "shadowfoot", "name": "Shadowfoot", "role": "rogue", "rank": "D", "type": "Umbral", "hp_ratio": 0.8, "dmg_ratio": 1.1, "kind": "dodge_pct", "flavor": "The Rift barely notices it was there."},
	{"id": "fleetblade", "name": "Fleetblade", "role": "rogue", "rank": "D", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 1.0, "kind": "escalate_pct", "flavor": "Gets faster the longer no one catches them."},
	{"id": "nightblade", "name": "Nightblade", "role": "rogue", "rank": "C", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "dmg_pct", "flavor": "Strikes from the dark and returns to it."},
	{"id": "wraithstep", "name": "Wraithstep", "role": "rogue", "rank": "C", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "first_round_pct", "flavor": "Leaves two footprints and no explanation."},
	{"id": "duskrunner", "name": "Duskrunner", "role": "rogue", "rank": "B", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.2, "kind": "first_round_pct", "flavor": "Moves like the space between two heartbeats."},
]

# Every kind that can appear on a hero build (skills/items/relics/traits/innate).
const BUILD_KINDS := ["dmg_pct", "hp_pct", "first_round_pct", "escalate_pct", "mend_pct", "hazard_guard_pct", "dodge_pct", "wipe_guard", "boss_alpha_strike"]

# Guild Management: 4 branches x 4-5 nodes each. Each node's display effect
# string is computed by Combat.describe_node_effect(node_id, level) — a
# match on node id, since the HTML version used a per-node JS closure that
# doesn't translate directly to static GDScript data. "cap" is {} when a node
# has no capstone.
const BRANCHES := [
	{"id": "ops", "name": "Operations Branch", "sub": "Hero Roster & Combat Management", "nodes": [
		{"id": "roster", "name": "Roster Expansion", "max": 5, "cost_base": 30, "cost_step": 20, "cap": {"name": "Elite Barracks", "cost": 400, "desc": "Set a Guild Mentor — new recruits join one level higher."}},
		{"id": "medical", "name": "Medical Bay", "max": 5, "cost_base": 25, "cost_step": 18, "cap": {"name": "Field Triage", "cost": 350, "desc": "Once per rift cycle, instantly heal the whole team."}},
		{"id": "drill", "name": "Tactical Drilling", "max": 5, "cost_base": 35, "cost_step": 22, "cap": {"name": "Vanguard Order", "cost": 450, "desc": "A fight's first strike deals +25% bonus damage."}},
		{"id": "trait", "name": "Trait Management Office", "max": 3, "cost_base": 40, "cost_step": 30, "cap": {}},
	]},
	{"id": "infra", "name": "Infrastructure Branch", "sub": "Rift Efficiency & Yield", "nodes": [
		{"id": "crystal", "name": "Crystal Amplifiers", "max": 5, "cost_base": 30, "cost_step": 20, "cap": {"name": "Crystal Resonance", "cost": 400, "desc": "Rift Bosses drop a bonus Pure Crystal cache."}},
		{"id": "stab", "name": "Rift Stabilization", "max": 5, "cost_base": 28, "cost_step": 18, "cap": {"name": "Anchor Artifact", "cost": 380, "desc": "Negates each floor's first hazard entirely."}},
		{"id": "seal", "name": "Seal Maximizer", "max": 3, "cost_base": 45, "cost_step": 30, "cap": {}},
		{"id": "energy", "name": "Energy Extraction", "max": 5, "cost_base": 26, "cost_step": 16, "cap": {}},
	]},
	{"id": "log", "name": "Logistics Branch", "sub": "Economy & Market", "nodes": [
		{"id": "broker", "name": "Broker Network", "max": 5, "cost_base": 30, "cost_step": 20, "cap": {"name": "Black Market Clearance", "cost": 420, "desc": "Unlocks premium bids on ultra-rare Rift Detectors."}},
		{"id": "scout", "name": "Targeted Scouting", "max": 3, "cost_base": 35, "cost_step": 25, "cap": {"name": "Headhunter", "cost": 400, "desc": "Guarantees a Rank C+ hero in every HR refresh."}},
		{"id": "merchant", "name": "Merchant Contract", "max": 5, "cost_base": 24, "cost_step": 14, "cap": {}},
		{"id": "detector", "name": "Detector Tuning", "max": 4, "cost_base": 32, "cost_step": 20, "cap": {}},
	]},
	{"id": "res", "name": "Research Branch", "sub": "Run Mechanics & Analytics", "nodes": [
		{"id": "relic", "name": "Relic Storage", "max": 3, "cost_base": 30, "cost_step": 22, "cap": {"name": "Inherited Power", "cost": 380, "desc": "Start every Rift with a Rare Relic instead of Common."}},
		{"id": "theory", "name": "Theorycrafting Lab", "max": 3, "cost_base": 28, "cost_step": 20, "cap": {"name": "Optimal Synergy", "cost": 400, "desc": "3 equipped Relics of one type grant +15% damage."}},
		{"id": "recycle", "name": "Relic Recycling", "max": 3, "cost_base": 22, "cost_step": 14, "cap": {}},
		{"id": "cart", "name": "Arcane Cartography", "max": 3, "cost_base": 26, "cost_step": 16, "cap": {}},
		{"id": "vault", "name": "Relic Vault", "max": 2, "cost_base": 50, "cost_step": 40, "cap": {}},
	]},
]

const GUILD_TIERS := [
	{"min": 0, "name": "Founding Guild"},
	{"min": 10, "name": "Established Guild"},
	{"min": 25, "name": "Renowned Guild"},
	{"min": 45, "name": "Legendary Guild"},
]

const DETECTOR_BASE_SALE := {"lesser": 80, "greater": 200, "ascendant": 450}

const BOSS_ENRAGE_ROUND := 4

# Icon paths — relic-type gems and item-category icons were extracted
# pixel-identical from guild-system.html's embedded base64 (RELIC_TYPE_ICON/
# ITEM_CATEGORY_ICON) into assets/icons/; monster sprites and the chest icon
# were already individually-named files from the earlier asset-slicing pass.
const RELIC_TYPE_ICON_PATH := {
	"Ember": "res://assets/icons/relic_ember.png",
	"Frost": "res://assets/icons/relic_frost.png",
	"Verdant": "res://assets/icons/relic_verdant.png",
	"Umbral": "res://assets/icons/relic_umbral.png",
	"Arcane": "res://assets/icons/relic_arcane.png",
}
const ITEM_CATEGORY_ICON_PATH := {
	"weapon": "res://assets/icons/item_weapon.png",
	"armor": "res://assets/icons/item_armor.png",
	"focus": "res://assets/icons/item_focus.png",
}
const CHEST_ICON_PATH := "res://assets/dungeon/chest_icon.png"
const HERO_PORTRAIT_PATH := {
	"warrior": "res://assets/heroes/warrior.png",
	"ranger": "res://assets/heroes/ranger.png",
	"mage": "res://assets/heroes/mage.png",
	"cleric": "res://assets/heroes/cleric.png",
	"rogue": "res://assets/heroes/rogue.png",
}
const MONSTER_SPRITE_PATH := {
	"goblin": "res://assets/monsters/goblin.png",
	"orc": "res://assets/monsters/orc.png",
	"skelly": "res://assets/monsters/skelly.png",
	"mummy": "res://assets/monsters/mummy.png",
	"zombie": "res://assets/monsters/zombie.png",
	"slime": "res://assets/monsters/slime.png",
	"wraith": "res://assets/monsters/wraith.png",
	"fire_skull": "res://assets/monsters/fire_skull.png",
}
const MONSTER_NAME_SPRITE := {
	"Gloom Stalker": "wraith", "Rift Wisp": "fire_skull", "Husk Brute": "zombie",
	"Sable Fang": "orc", "Ember Whelp": "goblin", "Marrow Crawler": "skelly",
	"Hollow Reaver": "mummy", "Cinder Moth": "slime",
}


## Any monster name gets a sprite: direct name match first, else a stable
## hash-based fallback across all 8 sprites — matches the HTML's
## spriteForMonster, so even Boss names (never in MONSTER_NAME_SPRITE) get a
## deterministic sprite instead of no icon at all.
static func sprite_for_monster(monster_name: String) -> String:
	if MONSTER_NAME_SPRITE.has(monster_name):
		var key: String = MONSTER_NAME_SPRITE[monster_name]
		return MONSTER_SPRITE_PATH[key]
	var keys: Array = MONSTER_SPRITE_PATH.keys()
	var hash_sum := 0
	for c in monster_name:
		hash_sum += c.unicode_at(0)
	var key: String = keys[hash_sum % keys.size()]
	return MONSTER_SPRITE_PATH[key]


static func find_class(pool_id: String) -> Dictionary:
	for c in CLASS_POOL:
		if c["id"] == pool_id:
			return c
	return {}


## Champions have no cls_id (no skill tree), so their role has to come from
## their pool_id's CLASS_POOL entry instead — this covers both.
static func portrait_for_hero(cls_id: String, pool_id: String) -> String:
	var role := cls_id
	if role == "":
		role = find_class(pool_id).get("role", "")
	return HERO_PORTRAIT_PATH.get(role, "")


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


static func rank_index(rank_id: String) -> int:
	for i in RANKS.size():
		if RANKS[i]["id"] == rank_id:
			return i
	return 0


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


static func find_skill_node(role: String, skill_id: String) -> Dictionary:
	for n in CLASS_SKILLS.get(role, []):
		if n["id"] == skill_id:
			return n
	return {}


static func weapon_slots(pool_id: String) -> int:
	return 2 if DUAL_WIELD_CLASSES.has(pool_id) else 1


static func gear_slots(rank_id: String) -> int:
	return 1 + int(floor(rank_index(rank_id) / 2.0))
