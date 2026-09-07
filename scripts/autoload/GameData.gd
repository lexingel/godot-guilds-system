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
	{"kind": "counter_pct", "value": 0.15, "domain": "chance", "label": "+15% chance to counter-attack when evading or taking a heavy hit"},
	{"kind": "cooldown_shave_pct", "value": 0.25, "domain": "chance", "label": "+25% chance to shave 1 round off every ability cooldown when evading or taking a heavy hit"},
	{"kind": "kill_shield_pct", "value": 0.2, "domain": "defense", "label": "On a kill, shields the lowest-HP ally for 20% of their max HP"},
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

## Field Incense: a one-shot consumable bought with Coins (not looted, not
## hero-bound) and used at Party Assembly — its bonus applies party-wide for
## every fight in the run about to start, cleared when that run ends. Reuses
## the same BUILD_KINDS vocabulary as skills/items/relics rather than
## inventing a new stat, so it flows through hero_skill_total for free.
const INCENSE_TYPES := [
	{"id": "vigor", "name": "Vigor Incense", "kind": "hp_pct", "value": 0.15, "cost": 40, "desc": "+15% party Max HP for the whole rift"},
	{"id": "warding", "name": "Warding Incense", "kind": "hazard_guard_pct", "value": 0.10, "cost": 40, "desc": "-10% hazard severity for the whole rift"},
]

static func find_incense(incense_id: String) -> Dictionary:
	for i in INCENSE_TYPES:
		if i["id"] == incense_id:
			return i
	return {}

## Runestones: bought with Coins like Incense, but socketed permanently into
## one equipped Item instead of consumed at Party Assembly — the bonus stacks
## on top of that item's own stat for as long as it stays equipped. "category"
## matches Item.slot_type() ("weapon"/"gear") so a runestone only fits the
## matching socket.
const RUNESTONE_TYPES := [
	{"id": "impact", "name": "Runestone of Impact", "category": "weapon", "kind": "dmg_pct", "value": 0.08, "cost": 60, "desc": "Weapon socket: +8% damage"},
	{"id": "aegis", "name": "Runestone of Aegis", "category": "gear", "kind": "hazard_guard_pct", "value": 0.08, "cost": 60, "desc": "Gear socket: -8% hazard severity"},
]

static func find_runestone(runestone_id: String) -> Dictionary:
	for r in RUNESTONE_TYPES:
		if r["id"] == runestone_id:
			return r
	return {}

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

## Per-subclass identity, not per-role: each of the 50 CLASS_POOL entries gets
## its own active ability and its own skill-tree specialization instead of the
## 5 shared role abilities/trees this used to be. Abilities are data-driven —
## one generic effect dispatcher in Combat.resolve_round reads {effect,value}
## from SUBCLASS_ABILITIES, so adding/tuning an ability never touches game
## logic. Skill trees stay 2 universal Tier-1 nodes (SUBCLASS_TIER1, unchanged
## from the old per-role trees) + a 4-node "signature package" keyed by the
## subclass's own CLASS_POOL `kind` (KIND_SKILL_PACKAGE) — subclasses sharing
## a kind already play similarly (same innate stat), so their trees
## reinforcing that same kind is a feature, not a shortcut.
const SUBCLASS_ABILITIES := {
	# -- Warrior --
	"squire": {"name": "Reckless Swing", "desc": "An all-in burst against the weakest foe.", "effect": "burst_lowest", "value": 0.8},
	"footman": {"name": "Shield Brace", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.15},
	"duelist": {"name": "Riposte", "desc": "+chance to counter-attack for the rest of this fight.", "effect": "counter_surge", "value": 0.25},
	"bulwark": {"name": "Unyielding Wall", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.25},
	"berserker": {"name": "Blood Frenzy", "desc": "Sacrifices own HP for a heavy burst on the weakest foe.", "effect": "self_sac_burst", "value": 1.4},
	"iron-guard": {"name": "Fortify", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.3},
	"bloodletter": {"name": "Open Wound", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.04},
	"runeblade": {"name": "Inscribed Strike", "desc": "A heavy burst against the weakest foe.", "effect": "burst_lowest", "value": 1.3},
	"ashen-templar": {"name": "Undying Vow", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.5},
	"rift-sovereign": {"name": "Sovereign's Wrath", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.1},
	# -- Ranger --
	"trapper": {"name": "Snare Volley", "desc": "Weakens every foe's damage for the rest of this fight.", "effect": "monster_dmg_mult", "value": 0.85},
	"slinger": {"name": "Improvised Shot", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.75},
	"pathfinder": {"name": "Sure Footing", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.1},
	"longshot": {"name": "One Arrow", "desc": "A finishing blow against the weakest foe, stronger the lower they are.", "effect": "execute_burst", "value": 0.9},
	"blade-dancer": {"name": "Opening Performance", "desc": "A heavy burst against the weakest foe.", "effect": "burst_lowest", "value": 1.2},
	"warden": {"name": "Walked Worse Halls", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.25},
	"stormtracker": {"name": "Chase the Lightning", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.035},
	"rift-ranger": {"name": "Read the Room", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.15},
	"deadfall-hunter": {"name": "Reversed Trap", "desc": "Weakens every foe's damage for the rest of this fight.", "effect": "monster_dmg_mult", "value": 0.75},
	"voidwalker": {"name": "Half-Step Out", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.22},
	# -- Mage --
	"apprentice": {"name": "Unsteady Spark", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.7},
	"cinderling": {"name": "First Spark", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.85},
	"fledgling-seer": {"name": "Half-Second Warning", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.08},
	"cinder-adept": {"name": "Warming Cast", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.03},
	"frost-scholar": {"name": "Cold Study", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.2},
	"wardweaver": {"name": "Faster Ward", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.3},
	"stormcaller": {"name": "Building Storm", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.045},
	"pyromancer": {"name": "The Rift Leans Away", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.2},
	"archon-of-storms": {"name": "Thunder's Door", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.0},
	"the-unbound": {"name": "No Name Holds It", "desc": "A heavy burst against the weakest foe.", "effect": "burst_lowest", "value": 1.6},
	# -- Cleric --
	"peddler": {"name": "Quick Bandage", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.3},
	"acolyte": {"name": "Quiet Prayer", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.35},
	"herbalist": {"name": "Field Kit", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.4},
	"lay-brother": {"name": "Censer Swing", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.7},
	"battle-chaplain": {"name": "Keep Moving", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.12},
	"zealot": {"name": "Faith and Blade", "desc": "A heavy burst against the weakest foe.", "effect": "burst_lowest", "value": 1.0},
	"rift-medic": {"name": "Faster Than the Wounds", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.55},
	"dawnkeeper": {"name": "First Light", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.35},
	"sanctified-shield": {"name": "Not Today", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.4},
	"alchemist": {"name": "Faster Brew", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.04},
	# -- Rogue --
	"scavenger": {"name": "Know the Puddles", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.08},
	"runaway": {"name": "Never Fought Fair", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.1},
	"cutpurse": {"name": "Leaves With More", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.8},
	"skirmisher": {"name": "Never Where You Struck", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.13},
	"footpad": {"name": "Nobody Heard Them", "desc": "+chance to counter-attack for the rest of this fight.", "effect": "counter_surge", "value": 0.2},
	"shadowfoot": {"name": "Barely Noticed", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.18},
	"fleetblade": {"name": "Getting Faster", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.04},
	"nightblade": {"name": "Strikes From the Dark", "desc": "A heavy burst against the weakest foe.", "effect": "burst_lowest", "value": 1.2},
	"wraithstep": {"name": "Two Footprints", "desc": "A finishing blow against the weakest foe, stronger the lower they are.", "effect": "execute_burst", "value": 1.0},
	"duskrunner": {"name": "Between Heartbeats", "desc": "A heavy burst against the weakest foe.", "effect": "burst_lowest", "value": 1.4},
}

## Every node's "icon" points at a bespoke pixel-art icon under
## assets/skills/ (extracted from a free CraftPix icon sheet) — 38 distinct
## icons across the 2 universal Tier-1 nodes + 9 packages x 4 nodes, no two
## nodes sharing an icon.
const SUBCLASS_TIER1 := [
	{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Honed Edge", "requires": [], "icon": "res://assets/skills/sword_a.png"},
	{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "hp_pct", "value": 0.08, "name": "Thick Hide", "requires": [], "icon": "res://assets/skills/heart.png"},
]

const KIND_SKILL_PACKAGE := {
	"dmg_pct": [
		{"id": "mastery", "tier": 2, "req_level": 4, "cost": 1, "kind": "dmg_pct", "value": 0.10, "name": "Weapon Mastery", "requires": ["edge"], "icon": "res://assets/skills/sword_silver.png"},
		{"id": "killer_instinct", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Killing Instinct", "requires": ["hide"], "icon": "res://assets/skills/gem_red.png"},
		{"id": "opening_fury", "tier": 2, "req_level": 5, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Opening Fury", "requires": [], "icon": "res://assets/skills/sword_slash.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "dmg_pct", "value": 0.22, "name": "Executioner's Edge", "requires": ["mastery", "killer_instinct"], "icon": "res://assets/skills/sword_big.png"},
	],
	"hp_pct": [
		{"id": "iron_skin", "tier": 2, "req_level": 4, "cost": 1, "kind": "hp_pct", "value": 0.10, "name": "Iron Skin", "requires": ["hide"], "icon": "res://assets/skills/shield_blue.png"},
		{"id": "steady_guard", "tier": 2, "req_level": 4, "cost": 1, "kind": "hazard_guard_pct", "value": 0.10, "name": "Steady Guard", "requires": ["edge"], "icon": "res://assets/skills/shield_basic.png"},
		{"id": "second_wind", "tier": 2, "req_level": 5, "cost": 1, "kind": "mend_pct", "value": 0.05, "name": "Second Wind", "requires": [], "icon": "res://assets/skills/potion_red_sm.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "hp_pct", "value": 0.25, "name": "Unbreakable", "requires": ["iron_skin", "steady_guard"], "icon": "res://assets/skills/shield_split.png"},
	],
	"first_round_pct": [
		{"id": "focus", "tier": 2, "req_level": 4, "cost": 1, "kind": "first_round_pct", "value": 0.12, "name": "Focused Opening", "requires": ["edge"], "icon": "res://assets/skills/dagger_blue.png"},
		{"id": "lightfoot", "tier": 2, "req_level": 4, "cost": 1, "kind": "dodge_pct", "value": 0.10, "name": "Light on Feet", "requires": ["hide"], "icon": "res://assets/skills/boots.png"},
		{"id": "precise_read", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.08, "name": "Precise Read", "requires": [], "icon": "res://assets/skills/eye_gem.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "first_round_pct", "value": 0.35, "name": "Perfect Opening", "requires": ["focus", "lightfoot"], "icon": "res://assets/skills/helm.png"},
	],
	"escalate_pct": [
		{"id": "buildup", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Building Momentum", "requires": ["edge"], "icon": "res://assets/skills/gear.png"},
		{"id": "adrenaline", "tier": 2, "req_level": 4, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Adrenaline", "requires": ["hide"], "icon": "res://assets/skills/dagger_red.png"},
		{"id": "second_breath", "tier": 2, "req_level": 5, "cost": 1, "kind": "mend_pct", "value": 0.04, "name": "Second Breath", "requires": [], "icon": "res://assets/skills/potion_blue_sm.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "escalate_pct", "value": 0.06, "name": "Unstoppable Momentum", "requires": ["buildup", "adrenaline"], "icon": "res://assets/skills/leaf_big.png"},
	],
	"mend_pct": [
		{"id": "smite", "tier": 2, "req_level": 4, "cost": 1, "kind": "dmg_pct", "value": 0.10, "name": "Smite", "requires": ["edge"], "icon": "res://assets/skills/sword_dual.png"},
		{"id": "mending", "tier": 2, "req_level": 4, "cost": 1, "kind": "mend_pct", "value": 0.05, "name": "Mending Chant", "requires": ["hide"], "icon": "res://assets/skills/potion_blue.png"},
		{"id": "ward2", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.08, "name": "Ward of Mercy", "requires": [], "icon": "res://assets/skills/shield_orange.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "mend_pct", "value": 0.10, "name": "Guardian Angel", "requires": ["smite", "mending"], "icon": "res://assets/skills/potion_red.png"},
	],
	"hazard_guard_pct": [
		{"id": "danger_sense", "tier": 2, "req_level": 4, "cost": 1, "kind": "hazard_guard_pct", "value": 0.10, "name": "Danger Sense", "requires": ["hide"], "icon": "res://assets/skills/ring.png"},
		{"id": "preempt", "tier": 2, "req_level": 4, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Preemptive Strike", "requires": ["edge"], "icon": "res://assets/skills/gem_blue_a.png"},
		{"id": "steady_hand", "tier": 2, "req_level": 5, "cost": 1, "kind": "dodge_pct", "value": 0.08, "name": "Steady Hand", "requires": [], "icon": "res://assets/skills/boots_brown.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "hazard_guard_pct", "value": 0.20, "name": "Unshakeable", "requires": ["danger_sense", "preempt"], "icon": "res://assets/skills/armor_chest.png"},
	],
	"dodge_pct": [
		{"id": "evasion", "tier": 2, "req_level": 4, "cost": 1, "kind": "dodge_pct", "value": 0.12, "name": "Evasive Training", "requires": ["hide"], "icon": "res://assets/skills/face_hood.png"},
		{"id": "momentum", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Fleeting Strike", "requires": ["edge"], "icon": "res://assets/skills/wing.png"},
		{"id": "gambit", "tier": 2, "req_level": 5, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Opening Gambit", "requires": [], "icon": "res://assets/skills/gem_blue_b.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "dmg_pct", "value": 0.20, "name": "Shadow Strike", "requires": ["evasion", "momentum"], "icon": "res://assets/skills/shard_blue.png"},
	],
	"wipe_guard": [
		{"id": "shieldwall", "tier": 2, "req_level": 4, "cost": 1, "kind": "dodge_pct", "value": 0.10, "name": "Shield Wall", "requires": ["hide"], "icon": "res://assets/skills/armor_shoulder.png"},
		{"id": "vanguard", "tier": 2, "req_level": 4, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Vanguard Strike", "requires": ["edge"], "icon": "res://assets/skills/gem_cluster.png"},
		{"id": "instinct", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.08, "name": "Battle Instinct", "requires": [], "icon": "res://assets/skills/cloak_a.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "wipe_guard", "value": 0.25, "name": "Last Stand", "requires": ["shieldwall", "vanguard"], "icon": "res://assets/skills/trophy.png"},
	],
	"boss_alpha_strike": [
		{"id": "buildup2", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Arcane Buildup", "requires": ["edge"], "icon": "res://assets/skills/star.png"},
		{"id": "ward", "tier": 2, "req_level": 4, "cost": 1, "kind": "hazard_guard_pct", "value": 0.10, "name": "Ward Sigil", "requires": ["hide"], "icon": "res://assets/skills/gem_blue_big.png"},
		{"id": "slip", "tier": 2, "req_level": 5, "cost": 1, "kind": "dodge_pct", "value": 0.08, "name": "Arcane Slip", "requires": [], "icon": "res://assets/skills/shard_green.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 3, "kind": "boss_alpha_strike", "value": 1.0, "name": "Cataclysm", "requires": ["buildup2", "ward"], "icon": "res://assets/skills/ingot_gold.png"},
	],
}


## A subclass's full skill tree: the 2 universal Tier-1 nodes plus the
## 4-node package matching its own CLASS_POOL `kind` (falls back to the
## dmg_pct package for anything not in CLASS_POOL, e.g. a Champion's
## non-subclass pool_id — harmless since Champions never learn skills).
static func subclass_skill_tree(pool_id: String) -> Array:
	var cls := find_class(pool_id)
	var kind: String = cls.get("kind", "dmg_pct")
	return SUBCLASS_TIER1 + KIND_SKILL_PACKAGE.get(kind, KIND_SKILL_PACKAGE["dmg_pct"])

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

# 50 classes across the 5 roles, 10 per role. `role` picks the Ability/anim
# assets; `kind` picks the skill-tree package (subclass_skill_tree) and the
# id itself picks the unique Ability (SUBCLASS_ABILITIES); rank/flavor are the
# same F-S vocabulary the Champion pool uses.
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
## AI-generated battle backdrops — one picked at random per encounter (stored
## on the combat state at start_combat so it doesn't change across renders of
## the same fight), not tied to monster type, matching "different rifts are
## different worlds" — the backdrop varies independent of what you're fighting.
const BATTLE_BACKGROUNDS: Array[String] = [
	"res://assets/battle/bg_dungeon.png",
	"res://assets/battle/bg_forest.png",
	"res://assets/battle/bg_cavern.png",
	"res://assets/battle/bg_ruins.png",
	"res://assets/battle/bg_volcanic.png",
]
const CURRENCY_ICON_PATH := {
	"coins": "res://assets/ui/icon_coins.png",
	"crystals": "res://assets/ui/icon_crystals.png",
	"tokens": "res://assets/ui/icon_tokens.png",
}
const CREST_PATH: Array[String] = [
	"res://assets/camp/crest_1.png", "res://assets/camp/crest_2.png",
	"res://assets/camp/crest_3.png", "res://assets/camp/crest_4.png",
	"res://assets/camp/crest_5.png", "res://assets/camp/crest_6.png",
	"res://assets/camp/crest_7.png", "res://assets/camp/crest_8.png",
]
const CAMP_BG := "res://assets/camp/camp_bg.png"
const MEDICAL_BG := "res://assets/screens/medical_bg.png"
const ROSTER_BG := "res://assets/screens/roster_bg.png"
const MANAGEMENT_BG := "res://assets/screens/management_bg.png"
const BED_ICON := "res://assets/screens/bed_icon.png"
const RIFTHALL_BG := "res://assets/screens/rifthall_bg.png"
const INVENTORY_BG := "res://assets/screens/inventory_bg.png"
const OPS_BANNER := "res://assets/screens/ops_banner.png"
const INFRA_BANNER := "res://assets/screens/infra_banner.png"
const LOGISTICS_BANNER := "res://assets/screens/logistics_banner.png"
const RESEARCH_BANNER := "res://assets/screens/research_banner.png"
const BRANCH_BANNER := {
	"ops": OPS_BANNER, "infra": INFRA_BANNER, "log": LOGISTICS_BANNER, "res": RESEARCH_BANNER,
}
const CAMP_HUB_ICON_PATH := {
	"roster": "res://assets/camp/icon_roster.png",
	"inventory": "res://assets/camp/icon_inventory.png",
	"recruits": "res://assets/camp/icon_recruits.png",
	"medical": "res://assets/camp/icon_medical.png",
	"management": "res://assets/camp/icon_management.png",
	"rift": "res://assets/camp/icon_rift.png",
}
const HERO_PORTRAIT_PATH := {
	"warrior": "res://assets/heroes/warrior.png",
	"ranger": "res://assets/heroes/ranger.png",
	"mage": "res://assets/heroes/mage.png",
	"cleric": "res://assets/heroes/cleric.png",
	"rogue": "res://assets/heroes/rogue.png",
}
## One bespoke portrait per subclass (hand-picked and background-removed from
## the free Batareya character pack, same pipeline as the 5 HERO_PORTRAIT_PATH
## renders) — gives all 50 CLASS_POOL entries a distinct look instead of
## sharing their role's single portrait.
const SUBCLASS_PORTRAIT_PATH := {
	"squire": "res://assets/heroes/subclass/squire.png",
	"footman": "res://assets/heroes/subclass/footman.png",
	"duelist": "res://assets/heroes/subclass/duelist.png",
	"bulwark": "res://assets/heroes/subclass/bulwark.png",
	"berserker": "res://assets/heroes/subclass/berserker.png",
	"iron-guard": "res://assets/heroes/subclass/iron-guard.png",
	"bloodletter": "res://assets/heroes/subclass/bloodletter.png",
	"runeblade": "res://assets/heroes/subclass/runeblade.png",
	"ashen-templar": "res://assets/heroes/subclass/ashen-templar.png",
	"rift-sovereign": "res://assets/heroes/subclass/rift-sovereign.png",
	"trapper": "res://assets/heroes/subclass/trapper.png",
	"slinger": "res://assets/heroes/subclass/slinger.png",
	"pathfinder": "res://assets/heroes/subclass/pathfinder.png",
	"longshot": "res://assets/heroes/subclass/longshot.png",
	"blade-dancer": "res://assets/heroes/subclass/blade-dancer.png",
	"warden": "res://assets/heroes/subclass/warden.png",
	"stormtracker": "res://assets/heroes/subclass/stormtracker.png",
	"rift-ranger": "res://assets/heroes/subclass/rift-ranger.png",
	"deadfall-hunter": "res://assets/heroes/subclass/deadfall-hunter.png",
	"voidwalker": "res://assets/heroes/subclass/voidwalker.png",
	"apprentice": "res://assets/heroes/subclass/apprentice.png",
	"cinderling": "res://assets/heroes/subclass/cinderling.png",
	"fledgling-seer": "res://assets/heroes/subclass/fledgling-seer.png",
	"cinder-adept": "res://assets/heroes/subclass/cinder-adept.png",
	"frost-scholar": "res://assets/heroes/subclass/frost-scholar.png",
	"wardweaver": "res://assets/heroes/subclass/wardweaver.png",
	"stormcaller": "res://assets/heroes/subclass/stormcaller.png",
	"pyromancer": "res://assets/heroes/subclass/pyromancer.png",
	"archon-of-storms": "res://assets/heroes/subclass/archon-of-storms.png",
	"the-unbound": "res://assets/heroes/subclass/the-unbound.png",
	"peddler": "res://assets/heroes/subclass/peddler.png",
	"acolyte": "res://assets/heroes/subclass/acolyte.png",
	"herbalist": "res://assets/heroes/subclass/herbalist.png",
	"lay-brother": "res://assets/heroes/subclass/lay-brother.png",
	"battle-chaplain": "res://assets/heroes/subclass/battle-chaplain.png",
	"zealot": "res://assets/heroes/subclass/zealot.png",
	"rift-medic": "res://assets/heroes/subclass/rift-medic.png",
	"dawnkeeper": "res://assets/heroes/subclass/dawnkeeper.png",
	"sanctified-shield": "res://assets/heroes/subclass/sanctified-shield.png",
	"alchemist": "res://assets/heroes/subclass/alchemist.png",
	"scavenger": "res://assets/heroes/subclass/scavenger.png",
	"runaway": "res://assets/heroes/subclass/runaway.png",
	"cutpurse": "res://assets/heroes/subclass/cutpurse.png",
	"skirmisher": "res://assets/heroes/subclass/skirmisher.png",
	"footpad": "res://assets/heroes/subclass/footpad.png",
	"shadowfoot": "res://assets/heroes/subclass/shadowfoot.png",
	"fleetblade": "res://assets/heroes/subclass/fleetblade.png",
	"nightblade": "res://assets/heroes/subclass/nightblade.png",
	"wraithstep": "res://assets/heroes/subclass/wraithstep.png",
	"duskrunner": "res://assets/heroes/subclass/duskrunner.png",
}
## AI-generated combat animation frames (5 each: frame 0 is the static portrait,
## 1-4 are the motion). Only combos that actually produced usable motion exist —
## Warrior/hurt and Ranger/attack never did after 3 rounds of prompt iteration,
## so those two intentionally have no frames; callers fall back to tweening the
## static portrait instead of frame-swapping when this returns [].
const HERO_ANIM_COMBOS := {
	"warrior": ["attack"],
	"ranger": ["hurt"],
	"mage": ["attack", "hurt"],
	"cleric": ["attack", "hurt"],
	"rogue": ["attack", "hurt"],
}


static func hero_anim_frames(role: String, action: String) -> Array[String]:
	var frames: Array[String] = []
	if not HERO_ANIM_COMBOS.get(role, []).has(action):
		return frames
	for i in 5:
		frames.append("res://assets/heroes/anim/%s_%s_%d.png" % [role, action, i])
	return frames
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


## Any monster name resolves to a sprite key: direct name match first, else a
## stable hash-based fallback across all 8 sprites — matches the HTML's
## spriteForMonster, so even Boss names (never in MONSTER_NAME_SPRITE) get a
## deterministic sprite instead of no icon at all.
static func monster_sprite_key(monster_name: String) -> String:
	if MONSTER_NAME_SPRITE.has(monster_name):
		return MONSTER_NAME_SPRITE[monster_name]
	var keys: Array = MONSTER_SPRITE_PATH.keys()
	var hash_sum := 0
	for c in monster_name:
		hash_sum += c.unicode_at(0)
	return keys[hash_sum % keys.size()]


static func sprite_for_monster(monster_name: String) -> String:
	return MONSTER_SPRITE_PATH[monster_sprite_key(monster_name)]


## Combat animation frames for a monster (5 each, same shape as
## hero_anim_frames) — all 8 monster sprites got usable attack/hurt motion on
## the first PixelLab pass (unlike heroes, no gaps here), so this always
## returns a populated array for any of the 8 known sprite keys.
static func monster_anim_frames(monster_name: String, action: String) -> Array[String]:
	var key := monster_sprite_key(monster_name)
	var frames: Array[String] = []
	for i in 5:
		frames.append("res://assets/monsters/anim/%s_%s_%d.png" % [key, action, i])
	return frames


static func find_class(pool_id: String) -> Dictionary:
	for c in CLASS_POOL:
		if c["id"] == pool_id:
			return c
	return {}


## Prefers a subclass-specific portrait (SUBCLASS_PORTRAIT_PATH, one of the 50
## CLASS_POOL entries) so recruited heroes look visually distinct beyond their
## role. Falls back to the 5 shared role portraits for anything not in that
## map — a Champion's pool_id is never a real subclass id, so this covers
## Champions the same way it always has.
static func portrait_for_hero(cls_id: String, pool_id: String) -> String:
	if SUBCLASS_PORTRAIT_PATH.has(pool_id):
		return SUBCLASS_PORTRAIT_PATH[pool_id]
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


static func find_skill_node(pool_id: String, skill_id: String) -> Dictionary:
	for n in subclass_skill_tree(pool_id):
		if n["id"] == skill_id:
			return n
	return {}


static func weapon_slots(pool_id: String) -> int:
	return 2 if DUAL_WIELD_CLASSES.has(pool_id) else 1


static func gear_slots(rank_id: String) -> int:
	return 1 + int(floor(rank_index(rank_id) / 2.0))
