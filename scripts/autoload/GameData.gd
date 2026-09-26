extends Node
## Static data tables — a near-mechanical port of the `const` tables in
## guild-system.html. No behavior lives here, only data, mirroring the
## HTML prototype's data/logic split. Keys use snake_case per GDScript
## convention; the JS camelCase originals are named in comments where it
## helps cross-reference the source.

const CLASSES := [
	{"id": "warrior", "name": "Warrior", "base_hp": 36, "base_dmg": 6, "base_spd": 8, "badge": "W"},
	{"id": "ranger", "name": "Ranger", "base_hp": 27, "base_dmg": 8, "base_spd": 12, "badge": "R"},
	{"id": "mage", "name": "Mage", "base_hp": 19, "base_dmg": 11, "base_spd": 10, "badge": "M"},
	{"id": "cleric", "name": "Cleric", "base_hp": 31, "base_dmg": 5, "base_spd": 7, "badge": "C"},
	{"id": "rogue", "name": "Rogue", "base_hp": 23, "base_dmg": 9, "base_spd": 14, "badge": "G"},
]

# Item/relic rarity only — heroes and Champions use RANKS below.
const RARITIES := [
	{"id": "common", "name": "Common", "mult": 1.0, "cost": 40, "weight": 60},
	{"id": "rare", "name": "Rare", "mult": 1.4, "cost": 120, "weight": 32},
	{"id": "epic", "name": "Epic", "mult": 1.9, "cost": 320, "weight": 8},
	# Legendary doesn't scale a rolled stat by `mult` like the other three —
	# it's a fixed pick from UNIQUE_ITEMS/UNIQUE_RELICS instead (see
	# Combat.gen_unique_item/gen_unique_relic). `mult`/`cost` exist only so
	# find_rarity() still has something sane to return.
	{"id": "legendary", "name": "Legendary", "mult": 1.0, "cost": 800, "weight": 1},
]

const POS_TRAITS := ["Battle-Hardened", "Swift", "Iron Skin"]
const NEG_TRAITS := ["Frail", "Reckless", "Slothful"]

# Trait kind-keys use the same BUILD_KINDS vocabulary as skills/items/relics
# so they flow through Combat.hero_skill_total for free.
const TRAIT_TABLE := {
	"Battle-Hardened": {"dmg_pct": 0.1},
	"Swift": {"dmg_pct": 0.05, "speed_pct": 0.12},
	"Iron Skin": {"hp_pct": 0.15},
	"Frail": {"hp_pct": -0.15},
	"Reckless": {"dmg_pct": -0.05, "hp_pct": -0.05},
	"Slothful": {"dmg_pct": -0.1, "speed_pct": -0.12},
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


## One opener + one closer, joined — see NARRATIVE_LINES above. Returns ""
## for an unknown event id (a missing/typo'd id just silently adds nothing,
## rather than crashing whatever log line called this).
static func narrative_line(event_id: String) -> String:
	if not NARRATIVE_LINES.has(event_id):
		return ""
	var pools: Dictionary = NARRATIVE_LINES[event_id]
	var openers: Array = pools["openers"]
	var closers: Array = pools["closers"]
	return "%s %s" % [openers[randi() % openers.size()], closers[randi() % closers.size()]]

# Earned from being knocked out in combat (Combat._finish_combat), not rolled
# at recruitment like TRAIT_TABLE above — a separate, capped-at-2 pool so a
# scar reads as a distinct kind of thing from the base trait. Same kind/value
# shape (flows through Combat.hero_skill_total for free), deliberately milder
# than a full NEG_TRAITS entry since up to 2 can stack on top of the trait.
const SCAR_POOL := ["Shell-Shocked", "Trembling Hands", "Battle Fatigue", "Haunted", "Flinching"]
const SCAR_TABLE := {
	"Shell-Shocked": {"dodge_pct": -0.08},
	"Trembling Hands": {"dmg_pct": -0.06},
	"Battle Fatigue": {"hp_pct": -0.08},
	"Haunted": {"mend_pct": -0.03},
	"Flinching": {"first_round_pct": -0.10},
}

## What a scar gives back — every scar is still a net wound (SCAR_TABLE), but
## one that changes how the hero fights instead of only making them worse.
## Combat.hero_effects entry shape.
const SCAR_UPSIDES := {
	"Shell-Shocked": [{"kind": "dmg_pct", "value": 0.15, "cond": {"ally_below": 0.5}}],
	"Trembling Hands": [{"trigger": "evade_or_heavy", "effect": "counter_attack", "value": 0.15}],
	"Battle Fatigue": [{"kind": "dmg_pct", "value": 0.12, "cond": {"round_min": 4}}],
	"Haunted": [{"kind": "dmg_pct", "value": 0.15, "cond": {"hp_below": 0.5}}],
	"Flinching": [{"kind": "dodge_pct", "value": 0.15, "cond": {"hp_below": 0.4}}],
}

## Traits earned through play rather than rolled at recruitment: each unlocks
## once `stat` in Hero.history reaches `need` (checked by
## GameState.check_earned_traits after fights and rift seals). Either a flat
## `kind`/`value` (summed by hero_skill_total) or `effects` (hero_effects).
const EARNED_TRAITS := [
	{"id": "bosskiller", "name": "Bosskiller", "stat": "boss_kills", "need": 3, "arch": "executioner",
	 "effects": [{"kind": "dmg_pct", "value": 0.15, "cond": {"vs_boss": true}}]},
	{"id": "elite_hunter", "name": "Elite Hunter", "stat": "elite_kills", "need": 5, "arch": "opener",
	 "kind": "first_round_pct", "value": 0.10},
	{"id": "reaper", "name": "Reaper", "stat": "kills", "need": 40, "arch": "executioner",
	 "effects": [{"kind": "dmg_pct", "value": 0.12, "cond": {"target_below": 0.3}}]},
	{"id": "seasoned", "name": "Seasoned", "stat": "kills", "need": 100, "arch": "executioner",
	 "kind": "dmg_pct", "value": 0.06},
	{"id": "survivor", "name": "Survivor", "stat": "knockouts", "need": 3, "arch": "evasion",
	 "effects": [{"kind": "dodge_pct", "value": 0.20, "cond": {"hp_below": 0.3}}]},
	{"id": "veteran", "name": "Veteran", "stat": "rifts_cleared", "need": 5, "arch": "guardian",
	 "kind": "hp_pct", "value": 0.08},
	{"id": "old_guard", "name": "Old Guard", "stat": "rifts_cleared", "need": 15, "arch": "guardian",
	 "kind": "wipe_guard", "value": 0.05},
]
const HISTORY_LABEL := {"kills": "kills", "boss_kills": "bosses", "elite_kills": "elites", "rifts_cleared": "rifts", "knockouts": "knockouts"}

static func find_earned_trait(trait_id: String) -> Dictionary:
	for t in EARNED_TRAITS:
		if t["id"] == trait_id:
			return t
	return {}

## Bonds between two specific heroes grow by clearing rifts together
## (GameState.bonds): level N once their shared rift count reaches
## BOND_LEVEL_RIFTS[N-1]. Each level is +BOND_DMG_PER_LEVEL party damage while
## both are alive in the fight, capped in total at BOND_DMG_CAP.
const BOND_LEVEL_RIFTS := [2, 5, 10]
const BOND_DMG_PER_LEVEL := 0.02
const BOND_DMG_CAP := 0.10

static func bond_level(rifts_together: int) -> int:
	var lvl := 0
	for need in BOND_LEVEL_RIFTS:
		if rifts_together >= need:
			lvl += 1
	return lvl

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

# Hero-vs-monster elemental weakness (attack-only — doesn't affect retaliation
# taken). Deliberately asymmetric rather than a clean 5-cycle: 3 of the 10
# pairs are neutral (Ember-Arcane, Frost-Umbral, Verdant-Umbral), and Ember/
# Arcane come out net stronger than Frost/Verdant. First-draft numbers,
# tunable after playing.
const TYPE_MATCHUPS := {
	"Ember": {"strong_vs": ["Verdant", "Umbral"], "weak_vs": ["Frost"]},
	"Frost": {"strong_vs": ["Ember"], "weak_vs": ["Verdant", "Arcane"]},
	"Verdant": {"strong_vs": ["Frost"], "weak_vs": ["Ember", "Arcane"]},
	"Umbral": {"strong_vs": ["Arcane"], "weak_vs": ["Ember"]},
	"Arcane": {"strong_vs": ["Verdant", "Frost"], "weak_vs": ["Umbral"]},
}

# Mirrors UNIQUE_RELICS' existing "combo_with" named-partner pattern, as a
# standing party-composition mechanic instead of a rare-relic-gated one.
# Keyed by pool_id (subclass), not specific hero instances, so any two heroes
# of those subclasses trigger it. Checked against Combat.bond_bonus_for.
const HERO_BONDS := [
	{"name": "Dueling Rivals", "a": "duelist", "b": "blade-dancer", "kind": "first_round_pct", "value": 0.08},
	{"name": "Won't Let You Fall", "a": "sanctified-shield", "b": "ashen-templar", "kind": "wipe_guard", "value": 0.10},
	{"name": "Half-Step Ahead", "a": "runaway", "b": "voidwalker", "kind": "dodge_pct", "value": 0.08},
	{"name": "Shield and Spark", "a": "iron-guard", "b": "rift-medic", "kind": "mend_pct", "value": 0.06},
	{"name": "Twin Shadows", "a": "nightblade", "b": "wraithstep", "kind": "dmg_pct", "value": 0.08},
	{"name": "Kindled Together", "a": "berserker", "b": "pyromancer", "kind": "dmg_pct", "value": 0.08},
	{"name": "Read the Room", "a": "rift-ranger", "b": "wardweaver", "kind": "hazard_guard_pct", "value": 0.06},
]

# Equipping 3+ of one element grants that element's own bonus.
const SYNERGY_BONUS := {
	"Ember": {"kind": "dmg_pct", "value": 0.15, "label": "+15% team damage"},
	"Frost": {"kind": "dodge_pct", "value": 0.12, "label": "+12% dodge chance"},
	"Verdant": {"kind": "mend_pct", "value": 0.08, "label": "Mends 8% of the party's HP pool each round"},
	"Umbral": {"kind": "hazard_guard_pct", "value": 0.15, "label": "-15% hazard severity"},
	"Arcane": {"kind": "loot_rarity_pct", "value": 0.10, "label": "+10% odds toward Rare/Epic loot"},
}

# A small combinatorial line-generator: each event id has an "openers" and
# "closers" pool, joined at random (narrative_line below picks one of each) —
# a modest amount of writing produces many more effective combinations than
# hand-writing full lines per event. Deliberately name-free (no {hero} slots)
# so the mechanism stays a single generic join everywhere — appended as an
# extra atmospheric line alongside whatever mechanical log line already names
# the hero/rank/etc. at that event's existing call site.
const NARRATIVE_LINES := {
	"rift_sealed": {
		"openers": ["The rift closes behind you.", "Another door shuts.", "The tear in the world seals over.", "Quiet returns to the floor you just cleared."],
		"closers": ["The world holds a little longer.", "Nobody will thank you for it.", "It won't stay closed forever.", "One less wound in the Rift's hide."],
	},
	"fast_clear": {
		"openers": ["You were in and out before the rift even noticed.", "Clean work.", "No wasted swings, no wasted time.", "The Rift barely had a chance to answer."],
		"closers": ["The Rift barely had time to react.", "Efficiency the guild will remember.", "Some fights end before they really begin.", "Not every victory needs to be hard-won."],
	},
	"boss_defeated": {
		"openers": ["It fought like it knew what was coming.", "The rift's champion falls.", "Whatever it was guarding, it isn't guarding anymore.", "The floor goes quiet where it used to stand."],
		"closers": ["Didn't matter.", "The rift itself feels smaller for it.", "The guild adds one more name to the list.", "Some things don't come back from a fight like that."],
	},
	"elite_defeated": {
		"openers": ["Stronger than the rest, and still not strong enough.", "It made you work for it.", "A cut above the usual — until it wasn't.", "The Rift saves its better monsters for later. This one came early."],
		"closers": ["That's the difference between elite and dead.", "Worth the extra scars.", "The rest of the floor felt easier after that.", "It won't be the last one like it."],
	},
	"hero_evolved": {
		"openers": ["Something in them has shifted.", "The rift changes people.", "They walked out different than they walked in.", "Whatever they were before, it isn't enough anymore."],
		"closers": ["This time, for the better.", "Growth has a cost, and they just paid it.", "The guild takes notice.", "Not every change happens by choice — but this one did."],
	},
	"legendary_drop": {
		"openers": ["Something in the wreckage doesn't belong to this floor at all.", "The rift doesn't usually give things like this away.", "Buried under the ordinary, something extraordinary.", "Not every rift hides a find like this."],
		"closers": ["Luck, or the Rift wanted rid of it.", "The guild will be talking about this one.", "Worth every wound it took to find it.", "Some things are worth the risk of coming back for."],
	},
	"hardcore_hero_lost": {
		"openers": ["No recovery this time.", "The Rift doesn't give this one back.", "Some doors only open one way.", "The guild loses more than a name today."],
		"closers": ["The guild remembers the ones it couldn't bring home.", "Hardcore Mode has no mercy, and neither did this fight.", "Grief is the price of that kind of risk.", "Not every hero makes it out of the Rift's reach."],
	},
	"guild_founded": {
		"openers": ["A name, a crest, and nothing else yet.", "Every guild starts as an empty ledger.", "The banner goes up before anyone's earned it.", "No history yet. Just intent."],
		"closers": ["That's how it always starts.", "The Rift doesn't care how you began, only how you end.", "Everything after this gets written the hard way.", "Whatever comes next, it starts here."],
	},
	"scar_gained": {
		"openers": ["The rift left its mark.", "Some wounds don't close all the way.", "Not every scar shows on the skin.", "The fight is over. The fear isn't."],
		"closers": ["Quiet about how it happened.", "A price paid for coming back at all.", "The rift takes more than HP sometimes.", "Not every cost gets fully repaid."],
	},
	"riftbreak_begins": {
		"openers": ["The threat you left to fester finally comes looking for you.", "No warning this time.", "What you didn't finish, finishes coming for you.", "The rift you ignored didn't ignore you back."],
		"closers": ["The spillover is already at the gates.", "This one isn't optional.", "You don't get to choose when this bill comes due.", "Whatever's coming, it's already arrived."],
	},
	"greater_rift_unlocked": {
		"openers": ["The Rift Hall's third gate finally answers.", "Three rifts sealed, and the chains on the old gateway snap loose.", "The rubble in the doorway stops mattering.", "Something the guild wasn't ready for, until now it is."],
		"closers": ["It was always waiting.", "Whatever's behind it, the guild has earned the right to find out.", "Not every gate opens with a key. Some just need proof.", "The easy floors are behind you now."],
	},
	"guild_tier_reached": {
		"openers": ["Word spreads.", "Other guilds have started asking who you are.", "The name on the banner starts to mean something.", "Reputation is its own kind of currency."],
		"closers": ["The guild's name means something now.", "Not everyone gets to hear it and stay calm.", "Whatever you're building, people have noticed.", "Growth like this doesn't go unnoticed for long."],
	},
}

# Items: hero-bound gear distinct from party-wide Relics. 3 category umbrellas:
# Weapon (offense), Armor (survival), Focus (utility). Weapon items fill a
# hero's weapon slots; Armor/Focus items share one "gear" slot pool. Each
# category's pool is widened to 4 kinds (beyond its "home" stats) specifically
# so a multi-affix roll (see ITEM_AFFIX_COUNT_BY_RARITY) has real room to vary
# instead of just guaranteeing every stat in that category at Epic.
const ITEM_CATEGORIES := ["weapon", "armor", "focus"]
const ITEM_CATEGORY_LABEL := {"weapon": "Weapon", "armor": "Armor", "focus": "Focus"}
const ITEM_CATEGORY_KINDS := {
	"weapon": ["dmg_pct", "first_round_pct", "escalate_pct", "speed_pct"],
	"armor": ["hp_pct", "hazard_guard_pct", "mend_pct", "dodge_pct"],
	"focus": ["dodge_pct", "speed_pct", "mend_pct", "hp_pct"],
}
const ITEM_NOUNS := {
	"weapon": ["Blade", "Bow", "Staff", "Mace", "Dagger"],
	"armor": ["Plate", "Guard", "Bracer", "Greaves", "Mail"],
	"focus": ["Ring", "Amulet", "Charm", "Band", "Talisman"],
}
const ITEM_KIND_BASE := {
	"dmg_pct": 0.12, "hp_pct": 0.12, "first_round_pct": 0.15, "escalate_pct": 0.04,
	"mend_pct": 0.06, "hazard_guard_pct": 0.12, "dodge_pct": 0.10, "speed_pct": 0.12,
}
## How many distinct stats a generated (non-Legendary) item rolls — the actual
## "build-around" lever: a Common is a single clean number, an Epic is a real
## multi-stat piece worth building toward, same shape as a hero's rank ladder.
const ITEM_AFFIX_COUNT_BY_RARITY := {"common": 1, "rare": 2, "epic": 3}
## Each slot past the first rolls at a reduced share of ITEM_KIND_BASE so the
## primary stat stays the item's clear identity instead of 3 equally-loud
## numbers — 100% / 55% / 35% for primary/secondary/tertiary.
const ITEM_AFFIX_VALUE_SHARE := [1.0, 0.55, 0.35]
## Flavor vocabulary for generated item names — a prefix (from the primary
## stat) and, when there's a secondary stat, a suffix phrase, e.g. "Swift
## Blade of Ruin". A tertiary stat (Epic) is never named, only described —
## three affixes baked into a name reads as noise, not identity. Two words
## per kind/slot just for pick variety, not meant to be exhaustive.
const ITEM_AFFIX_PREFIX := {
	"dmg_pct": ["Brutal", "Savage"],
	"first_round_pct": ["Ambushing", "Sudden"],
	"escalate_pct": ["Relentless", "Rising"],
	"hp_pct": ["Stalwart", "Hardy"],
	"hazard_guard_pct": ["Warded", "Bulwark"],
	"mend_pct": ["Mending", "Restorative"],
	"dodge_pct": ["Evasive", "Nimble"],
	"speed_pct": ["Swift", "Fleet"],
}
const ITEM_AFFIX_SUFFIX := {
	"dmg_pct": ["of Ruin", "of Slaughter"],
	"first_round_pct": ["of First Blood", "of the Ambush"],
	"escalate_pct": ["of Escalation", "of the Storm"],
	"hp_pct": ["of Vitality", "of Fortitude"],
	"hazard_guard_pct": ["of Warding", "of the Bulwark"],
	"mend_pct": ["of Mending", "of Renewal"],
	"dodge_pct": ["of Evasion", "of Shadows"],
	"speed_pct": ["of Haste", "of the Wind"],
}

## Glossary for keyword tooltips: [regex (case-insensitive, word-bounded),
## title, definition]. UiKit hovers these in rich text lines ([hint]) and
## lists the ones a tooltip card mentions at its foot. Definitions must not
## contain "]" (they go inside a BBCode tag).
const KEYWORDS := [
	["first-strike", "First-strike", "bonus damage on the party's opening round of every fight"],
	["per round \\(stacking\\)|escalat\\w*", "Escalation", "damage that keeps growing every round the fight goes on"],
	["hazard severity|hazard guard", "Hazard guard", "cuts the damage rift hazards (traps, fog, lava) deal to the party"],
	["block a retaliation|dodge", "Dodge", "chance to avoid a monster's attack completely"],
	["mends?|mending", "Mend", "the party heals a share of its HP at the end of every round"],
	["survive a wipe|wipe guard", "Wipe guard", "once per rift, the last hero standing survives a killing blow"],
	["take the hit|intercept", "Intercept", "step in front of an attack aimed at a wounded ally"],
	["counter-attack|counters?", "Counter", "strike back at the attacker after dodging or taking a heavy hit"],
	["finish foes|execute", "Execute", "instantly defeats a foe your hit leaves below the threshold"],
	["act again", "Extra turn", "the hero immediately takes another turn, once per round"],
	["shields?", "Shield", "absorbs incoming damage before HP is lost"],
	["acting first|acting last", "Turn order", "everyone acts in Speed order each round; first/last means this round's order"],
	["turn speed|speed", "Speed", "sets turn order each round, faster acts earlier"],
	["front row|back row", "Formation", "the front row draws about 3x as many monster attacks as the back row"],
	["opener", "Opener", "win fast: first-strike, speed and round-one bursts"],
	["attrition", "Attrition", "win long fights: bonuses that grow with every round"],
	["guardian", "Guardian", "keep the party standing: HP, hazard/wipe guard, intercepts"],
	["evasion", "Evasion", "avoid hits: dodge and punishing counters"],
	["sustain", "Sustain", "outlast: mending, lifesteal and shields"],
	["executioner", "Executioner", "finish things: raw damage, executes, boss killing"],
]

static var _keyword_res: Array = []

## [title, definition, RegEx] for every KEYWORDS entry (compiled once).
static func keyword_regexes() -> Array:
	if _keyword_res.is_empty():
		for k in KEYWORDS:
			var re := RegEx.new()
			re.compile("(?i)\\b(" + str(k[0]) + ")\\b")
			_keyword_res.append([str(k[1]), str(k[2]), re])
	return _keyword_res

## Build archetypes — the shared vocabulary that ties a hero's innate kind,
## subclass passive, skill keystones, item affixes and Legendaries together
## into one visible "build". Purely a display/grouping layer: combat never
## reads it, only the Roster's build summary and item/passive tags do.
const ARCHETYPES := {
	"opener": "Opener", "attrition": "Attrition", "guardian": "Guardian",
	"evasion": "Evasion", "sustain": "Sustain", "executioner": "Executioner",
}
const KIND_ARCHETYPE := {
	"first_round_pct": "opener", "speed_pct": "opener",
	"escalate_pct": "attrition",
	"hp_pct": "guardian", "hazard_guard_pct": "guardian", "wipe_guard": "guardian",
	"dodge_pct": "evasion",
	"mend_pct": "sustain",
	"dmg_pct": "executioner", "boss_alpha_strike": "executioner",
}

## Subclass passives — every CLASS_POOL entry gets one, always on from Lv1,
## chosen by its innate kind: the Nth subclass of a kind (CLASS_POOL order)
## gets template N mod 3, so siblings of the same kind don't all share one.
## Values are Rank-F; subclass_passive() scales them by rank. Each passive is
## a Combat.hero_effects entry list plus the archetype it belongs to.
const PASSIVE_TEMPLATES := {
	"dmg_pct": [
		{"name": "Killer's Eye", "arch": "executioner", "effects": [{"kind": "dmg_pct", "value": 0.12, "cond": {"target_below": 0.4}}]},
		{"name": "Bloodrush", "arch": "executioner", "effects": [{"kind": "dmg_pct", "value": 0.15, "cond": {"hp_below": 0.5}}]},
		{"name": "Headhunter", "arch": "executioner", "effects": [{"kind": "dmg_pct", "value": 0.12, "cond": {"vs_boss": true}}]},
	],
	"hp_pct": [
		{"name": "Stand Firm", "arch": "guardian", "effects": [{"kind": "dmg_pct", "value": 0.10, "cond": {"formation": "front"}}]},
		{"name": "Protector", "arch": "guardian", "effects": [{"trigger": "ally_targeted", "effect": "intercept", "value": 0.20}]},
		{"name": "Unbowed", "arch": "guardian", "effects": [{"kind": "dodge_pct", "value": 0.10, "cond": {"hp_below": 0.4}}]},
	],
	"first_round_pct": [
		{"name": "Quick Draw", "arch": "opener", "effects": [{"kind": "dmg_pct", "value": 0.12, "cond": {"acting_first": true}}]},
		{"name": "Ambusher", "arch": "opener", "effects": [{"kind": "dmg_pct", "value": 0.15, "cond": {"round_max": 1}}]},
		{"name": "Opening Salvo", "arch": "opener", "effects": [{"kind": "dmg_pct", "value": 0.08, "cond": {"round_max": 2}}]},
	],
	"escalate_pct": [
		{"name": "Second Wind", "arch": "attrition", "effects": [{"kind": "dmg_pct", "value": 0.10, "cond": {"round_min": 3}}]},
		{"name": "Long Fight", "arch": "attrition", "effects": [{"kind": "dmg_pct", "value": 0.14, "cond": {"round_min": 5}}]},
		{"name": "Wear Them Down", "arch": "attrition", "effects": [{"trigger": "evade_or_heavy", "effect": "weaken_attacker", "value": 0.05}]},
	],
	"mend_pct": [
		{"name": "Field Medic", "arch": "sustain", "effects": [{"trigger": "party_mend", "effect": "shield_lowest", "value": 0.04}]},
		{"name": "Siphon", "arch": "sustain", "effects": [{"trigger": "after_hit", "effect": "lifesteal", "value": 0.08}]},
		{"name": "Rallying Word", "arch": "sustain", "effects": [{"trigger": "on_kill", "effect": "mend_party", "value": 0.03}]},
	],
	"hazard_guard_pct": [
		{"name": "Wary", "arch": "guardian", "effects": [{"kind": "dodge_pct", "value": 0.08, "cond": {"round_max": 2}}]},
		{"name": "Brace", "arch": "guardian", "effects": [{"trigger": "evade_or_heavy", "effect": "weaken_attacker", "value": 0.06}]},
		{"name": "Covering Stance", "arch": "guardian", "effects": [{"trigger": "ally_targeted", "effect": "intercept", "value": 0.15}]},
	],
	"dodge_pct": [
		{"name": "Slippery", "arch": "evasion", "effects": [{"kind": "dodge_pct", "value": 0.10, "cond": {"hp_above": 0.75}}]},
		{"name": "Riposte", "arch": "evasion", "effects": [{"trigger": "evade_or_heavy", "effect": "counter_attack", "value": 0.15}]},
		{"name": "Back-Row Shadow", "arch": "evasion", "effects": [{"kind": "dodge_pct", "value": 0.10, "cond": {"formation": "back"}}]},
	],
	"wipe_guard": [
		{"name": "Last Bastion", "arch": "guardian", "effects": [{"kind": "dodge_pct", "value": 0.12, "cond": {"hp_below": 0.3}}]},
		{"name": "Oathkeeper", "arch": "guardian", "effects": [{"trigger": "ally_targeted", "effect": "intercept", "value": 0.25}]},
		{"name": "Rally", "arch": "guardian", "effects": [{"kind": "dmg_pct", "value": 0.12, "cond": {"ally_below": 0.5}}]},
	],
	"boss_alpha_strike": [
		{"name": "Giant's Bane", "arch": "executioner", "effects": [{"kind": "dmg_pct", "value": 0.15, "cond": {"vs_boss": true}}]},
		{"name": "Crushing Blow", "arch": "executioner", "effects": [{"kind": "dmg_pct", "value": 0.15, "cond": {"target_below": 0.3}}]},
		{"name": "Apex", "arch": "executioner", "effects": [{"trigger": "on_kill", "effect": "extra_turn", "value": 1.0}]},
	],
}

## Formation (Phase 5): each role has a natural row and a role-flavored
## bonus while standing in it (Combat.hero_effects adds it only in position).
## Front row still draws ~3x the monster attacks (Combat.weighted_formation_
## target), so putting a fragile back-liner up front costs twice over.
const ROLE_POSITION := {
	"warrior": {"row": "front", "name": "Vanguard", "arch": "guardian",
		"effects": [{"trigger": "ally_targeted", "effect": "intercept", "value": 0.15}]},
	"rogue": {"row": "front", "name": "Flanker", "arch": "executioner",
		"effects": [{"kind": "dmg_pct", "value": 0.12, "cond": {"formation": "front"}}]},
	"ranger": {"row": "back", "name": "Overwatch", "arch": "opener",
		"effects": [{"kind": "dmg_pct", "value": 0.15, "cond": {"formation": "back", "round_max": 2}}]},
	"mage": {"row": "back", "name": "Safe Distance", "arch": "attrition",
		"effects": [{"kind": "dmg_pct", "value": 0.10, "cond": {"formation": "back"}}]},
	"cleric": {"row": "back", "name": "Sanctuary Line", "arch": "sustain",
		"effects": [{"trigger": "party_mend", "effect": "shield_lowest", "value": 0.04}]},
}

## A hero's role even for a Champion (whose cls_id is blank).
static func hero_role(h: Hero) -> String:
	return h.cls_id if h.cls_id != "" else str(find_class(h.pool_id).get("role", ""))

static var _passive_cache: Dictionary = {}

## {"name", "arch", "effects"} for a subclass (rank-scaled), or {} if unknown.
static func subclass_passive(pool_id: String) -> Dictionary:
	if _passive_cache.has(pool_id):
		return _passive_cache[pool_id]
	var cls := find_class(pool_id)
	var out := {}
	if not cls.is_empty() and PASSIVE_TEMPLATES.has(cls["kind"]):
		var n := 0
		for c in CLASS_POOL:
			if c["id"] == pool_id:
				break
			if c["kind"] == cls["kind"]:
				n += 1
		var templates: Array = PASSIVE_TEMPLATES[cls["kind"]]
		out = templates[n % templates.size()].duplicate(true)
		var mult := 1.0 + 0.12 * rank_index(cls["rank"])
		for e in out["effects"]:
			if str(e.get("effect", "")) != "extra_turn":
				e["value"] = snappedf(float(e["value"]) * mult, 0.001)
	_passive_cache[pool_id] = out
	return out

## A generated item's base (the noun) grants a small fixed stat — so a Dagger
## and a Mace of the same rarity and affixes still pull a build in different
## directions. Scaled by item rank (ITEM_RANK_MULT), never by the affix roll.
const ITEM_BASE_IMPLICIT := {
	"Blade": {"kind": "dmg_pct", "value": 0.05},
	"Bow": {"kind": "first_round_pct", "value": 0.08},
	"Staff": {"kind": "mend_pct", "value": 0.02},
	"Mace": {"kind": "escalate_pct", "value": 0.015},
	"Dagger": {"kind": "speed_pct", "value": 0.06},
	"Plate": {"kind": "hp_pct", "value": 0.06},
	"Guard": {"kind": "hazard_guard_pct", "value": 0.06},
	"Bracer": {"kind": "dodge_pct", "value": 0.04},
	"Greaves": {"kind": "speed_pct", "value": 0.05},
	"Mail": {"kind": "wipe_guard", "value": 0.05},
	"Ring": {"kind": "escalate_pct", "value": 0.015},
	"Amulet": {"kind": "mend_pct", "value": 0.02},
	"Charm": {"kind": "dodge_pct", "value": 0.04},
	"Band": {"kind": "first_round_pct", "value": 0.06},
	"Talisman": {"kind": "hazard_guard_pct", "value": 0.06},
}

## Item rank = the rank of the rift it dropped in (GameState.loot_rank), and
## scales every rolled number on it — so higher-rank rifts are worth the risk
## and early gear eventually gets replaced. Indexed like RIFT_RANKS (F..SSS).
const ITEM_RANK_MULT := [1.0, 1.04, 1.08, 1.12, 1.16, 1.22, 1.28, 1.35, 1.42]
## Each rolled affix lands somewhere in this band of its base value.
const ITEM_ROLL_RANGE := [0.8, 1.2]

## An Epic's extra, situational affix — the Combat.hero_effects entry shape
## (see its doc comment), rolled once and stored on the Item. "arch" is the
## build archetype it belongs to (ARCHETYPES). Values here are Rank-F, pre-roll.
const ITEM_COND_AFFIXES := [
	{"arch": "opener", "kind": "dmg_pct", "value": 0.25, "cond": {"round_max": 1}},
	{"arch": "opener", "kind": "dmg_pct", "value": 0.15, "cond": {"acting_first": true}},
	{"arch": "attrition", "kind": "dmg_pct", "value": 0.18, "cond": {"round_min": 4}},
	{"arch": "evasion", "kind": "dodge_pct", "value": 0.12, "cond": {"hp_above": 0.75}},
	{"arch": "evasion", "trigger": "evade_or_heavy", "effect": "counter_attack", "value": 0.20},
	{"arch": "guardian", "trigger": "ally_targeted", "effect": "intercept", "value": 0.20},
	{"arch": "sustain", "trigger": "party_mend", "effect": "shield_lowest", "value": 0.06},
	{"arch": "sustain", "trigger": "after_hit", "effect": "lifesteal", "value": 0.10},
	{"arch": "executioner", "kind": "dmg_pct", "value": 0.30, "cond": {"target_below": 0.35}},
	{"arch": "executioner", "kind": "dmg_pct", "value": 0.15, "cond": {"vs_boss": true}},
	{"arch": "executioner", "kind": "dmg_pct", "value": 0.25, "cond": {"hp_below": 0.4}},
	{"arch": "guardian", "kind": "dmg_pct", "value": 0.15, "cond": {"ally_below": 0.5}},
]

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
]

static func find_unique_item(unique_id: String) -> Dictionary:
	for u in UNIQUE_ITEMS:
		if u["id"] == unique_id:
			return u
	return {}


static func find_unique_relic(unique_id: String) -> Dictionary:
	for u in UNIQUE_RELICS:
		if u["id"] == unique_id:
			return u
	return {}

# Classes agile/skilled enough to dual-wield get 2 weapon slots instead of 1 —
# all 10 Rogues plus 3 hand-picked classes whose flavor fits.
const DUAL_WIELD_CLASSES := [
	"scavenger", "runaway", "cutpurse", "skirmisher", "footpad", "shadowfoot",
	"fleetblade", "nightblade", "wraithstep", "duskrunner",
	"duelist", "blade-dancer", "zealot",
	# Content-pass additions — both fit the dual-wield finisher/duelist flavor.
	"the-unseen-hand", "glyphhand",
]

const BOSS_MECHANICS := [
	{"id": "enrage", "name": "Enraged", "desc": "Strikes harder the longer the fight drags on (past round 4)."},
	{"id": "warded", "name": "Warded", "desc": "Shields and dodge cannot mitigate its first two retaliations."},
	{"id": "regen", "name": "Regenerating", "desc": "Heals a portion of its health back each round it survives."},
	{"id": "frenzied", "name": "Frenzied", "desc": "Hits harder than expected from the very first round."},
]

## A persistent badge icon per boss mechanic, shown on the boss's own status
## plate in the arena for the whole fight — previously a boss's mechanic was
## only ever mentioned via Combat.describe_incoming's transient text hint
## above the action bar, easy to miss once you stopped rereading it.
const BOSS_MECHANIC_ICON := {
	"enrage": "res://assets/skills/sword_big.png",
	"warded": "res://assets/skills/shield_split.png",
	"regen": "res://assets/skills/potion_red.png",
	"frenzied": "res://assets/skills/wing.png",
}

## One archetype ability per regular monster name (MONSTER_NAMES) — every
## fight used to run identical generic attack math regardless of which
## monster showed up. Scoped to regular "combat"-tier monsters only (standalone
## or as elite/boss adds via Combat.gen_monsters); elite mains keep their stat
## multipliers and bosses keep BOSS_MECHANICS, both untouched.
const MONSTER_ABILITIES := {
	"Gloom Stalker": {"kind": "poison", "name": "Venomous Bite", "value": 0.06},
	"Sable Fang": {"kind": "poison", "name": "Venomous Bite", "value": 0.06},
	"Rift Wisp": {"kind": "healer", "name": "Mending Pulse", "value": 0.10},
	"Marrow Crawler": {"kind": "healer", "name": "Mending Pulse", "value": 0.10},
	"Husk Brute": {"kind": "shielded", "name": "Bone Ward", "value": 0.3},
	"Hollow Reaver": {"kind": "shielded", "name": "Bone Ward", "value": 0.3},
	"Ember Whelp": {"kind": "frenzy", "name": "Death Frenzy", "value": 0.4},
	"Cinder Moth": {"kind": "frenzy", "name": "Death Frenzy", "value": 0.4},
	# Content pass: 2 new archetypes, 2 monsters each — the other 4 new
	# monsters intentionally carry no ability entry at all (pure visual
	# variety), the same already-supported "nothing special" case every
	# monster not in this dict already falls into.
	"Bog Wretch": {"kind": "drain", "name": "Leeching Mire", "value": 0.35},
	"Silt Crawler": {"kind": "drain", "name": "Leeching Mire", "value": 0.35},
	"Glass Wisp": {"kind": "reflect", "name": "Mirrored Edge", "value": 0.25},
	"Mirror Fiend": {"kind": "reflect", "name": "Mirrored Edge", "value": 0.25},
}

## Badge icons for MONSTER_ABILITIES — reuses BOSS_MECHANIC_ICON's picks where
## the concept already matches (healer/frenzy both mean the same thing a boss
## mechanic would), no new art needed.
const MONSTER_ABILITY_ICON := {
	"poison": "res://assets/skills/shard_green.png",
	"healer": "res://assets/skills/potion_red.png",
	"shielded": "res://assets/skills/shield_orange.png",
	"frenzy": "res://assets/skills/wing.png",
	"drain": "res://assets/skills/dagger_red.png",
	"reflect": "res://assets/skills/shield_blue.png",
}

const HAZARD_TYPES := [
	{"id": "poison", "name": "Poison Fog", "dmg_mult": 1.0, "bonus_chance": 0.3, "bonus_type": "crystals"},
	{"id": "lava", "name": "Cracked Lava Floor", "dmg_mult": 1.3, "bonus_chance": 0.15, "bonus_type": "crystals"},
	{"id": "collapse", "name": "Collapsing Passage", "dmg_mult": 1.1, "bonus_chance": 0.2, "bonus_type": "coins"},
	{"id": "wraith", "name": "Wailing Wraiths", "dmg_mult": 0.8, "bonus_chance": 0.4, "bonus_type": "crystals"},
	{"id": "vault", "name": "Sealed Vault Trap", "dmg_mult": 1.2, "bonus_chance": 0.5, "bonus_type": "coins"},
]

## One illustration per hazard type — the hazard node used to be a bare name
## label with no art at all. PixelLab-generated (generate-image-v2, 320x200 —
## the same native size every other scene backdrop in this project uses).
const HAZARD_BG := {
	"poison": "res://assets/screens/hazard_poison.png",
	"lava": "res://assets/screens/hazard_lava.png",
	"collapse": "res://assets/screens/hazard_collapse.png",
	"wraith": "res://assets/screens/hazard_wraith.png",
	"vault": "res://assets/screens/hazard_vault.png",
}

const FIRST_NAMES := ["Aldric", "Bryn", "Coren", "Dessa", "Elowen", "Fenwick", "Gara", "Hollis", "Ianthe", "Joric", "Kestrel", "Liora", "Maren", "Nyx", "Oren", "Petra", "Quill", "Roth", "Sable", "Tavin", "Ysolde", "Zeph"]
const MONSTER_NAMES := ["Gloom Stalker", "Rift Wisp", "Husk Brute", "Sable Fang", "Ember Whelp", "Marrow Crawler", "Hollow Reaver", "Cinder Moth", "Bog Wretch", "Silt Crawler", "Glass Wisp", "Mirror Fiend", "Frost Stalker", "Ashclad Ghoul", "Deep Anchorite", "Voidling Sprite"]
const ELITE_NAMES := ["Warbound Elite", "Blightfang Elite", "Rift-Touched Colossus", "Iron Revenant", "Storm-Called Elite", "Ashen Broodlord"]
const BOSS_NAMES := ["Vaelith", "Korrath", "Nyxara", "Drevok", "Sythrane"]

# Lesser and Greater Rift are the two selectable DIFFICULTIES tiers; Endless
# (below, via ENDLESS_BASE) is a separate infinite-scaling mode. Ascendant
# isn't its own selectable tier — ENDLESS_BASE just reuses its numbers.
const DIFFICULTIES := [
	{"id": "lesser", "name": "Lesser Rift", "floors": 7, "monster_hp": 32, "monster_dmg": 4, "coin": [18, 34], "crystal": [5, 11], "token_base": 10, "detector_chance": 0.08, "power": "Low", "rec_power": 70},
	# Unlocked by GameState.greater_rift_unlocked() (seal 3 rifts) rather than
	# Guild Management currency — sits between Lesser and the Ascendant-
	# equivalent ENDLESS_BASE below. First-draft numbers, tunable after playing.
	{"id": "greater", "name": "Greater Rift", "floors": 8, "monster_hp": 105, "monster_dmg": 11, "coin": [40, 70], "crystal": [11, 20], "token_base": 18, "detector_chance": 0.14, "power": "Medium", "rec_power": 150},
]

# Endless Rift scales forever off these base stats (matches the HTML
# version's ENDLESS_BASE, which is Ascendant Rift's numbers regardless of
# whether Ascendant itself is a selectable tier in this port).
const ENDLESS_BASE := {"monster_hp": 125, "monster_dmg": 14, "coin": [85, 140], "crystal": [20, 36], "token_base": 36, "detector_chance": 0.22, "rec_power": 280}

## Per-subclass identity, not per-role: each CLASS_POOL entry gets its own
## active ability and its own skill-tree specialization instead of the 5
## shared role abilities/trees this used to be. Abilities are data-driven —
## one generic effect dispatcher in Combat.resolve_round reads {effect,value}
## from SUBCLASS_ABILITIES, so adding/tuning an ability never touches game
## logic. Skill trees are 2 Tier-1 roots (role-flavored — see TIER1_BY_ROLE;
## the id is always "edge"/"hide" so every KIND_SKILL_PACKAGE's `requires`
## keeps working regardless of which role's flavor a hero actually has) + a
## "signature package" keyed by the subclass's own CLASS_POOL `kind`
## (KIND_SKILL_PACKAGE) — subclasses sharing a kind already play similarly
## (same innate stat), so their trees reinforcing that same kind is a
## feature, not a shortcut. Most packages are 4 Tier-2 nodes + a 2-way Tier-3
## fork + 2 Tier-4 finishers, but that shape isn't load-bearing — see
## `boss_alpha_strike` (a single linear capstone, no fork) and `dodge_pct` (a
## 3-way fork) for the deliberately asymmetric ones.
const SUBCLASS_ABILITIES := {
	# -- Warrior --
	"squire": {"name": "Reckless Swing", "desc": "An all-in burst against the weakest foe.", "effect": "burst_lowest", "value": 0.8},
	"footman": {"name": "Shield Brace", "desc": "Cripples the greatest threat's damage output for the rest of this fight.", "effect": "debuff_lowest", "value": 0.65},
	"duelist": {"name": "Riposte", "desc": "+chance to counter-attack for the rest of this fight.", "effect": "counter_surge", "value": 0.25},
	"bulwark": {"name": "Unyielding Wall", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.25},
	"berserker": {"name": "Blood Frenzy", "desc": "Sacrifices own HP for a heavy burst on the weakest foe.", "effect": "self_sac_burst", "value": 1.4},
	"iron-guard": {"name": "Fortify", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.3},
	"bloodletter": {"name": "Open Wound", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.04},
	"runeblade": {"name": "Inscribed Strike", "desc": "Inscribes every blade in the party — damage surges for the rest of this fight.", "effect": "team_dmg_mult", "value": 1.18},
	"ashen-templar": {"name": "Undying Vow", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.5},
	"rift-sovereign": {"name": "Sovereign's Wrath", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.1},
	# -- Warrior (content-pass additions) --
	"fieldmender": {"name": "Battlefield Patch", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.3},
	"featherguard": {"name": "Light Feet", "desc": "Shields the whole party lightly.", "effect": "team_shield_burst", "value": 0.12},
	"trailblazer": {"name": "First Through", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.75},
	"frostguard": {"name": "Unbothered", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.3},
	"warbrand": {"name": "Growing Anger", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.04},
	"aegis-bearer": {"name": "On Principle", "desc": "Cripples the greatest threat's damage output for the rest of this fight.", "effect": "debuff_lowest", "value": 0.6},
	"stormguard": {"name": "Meet the Charge", "desc": "A heavy burst against the weakest foe.", "effect": "burst_lowest", "value": 1.1},
	"rift-breaker": {"name": "First Crack", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.0},
	# -- Ranger --
	"trapper": {"name": "Snare Volley", "desc": "Weakens every foe's damage for the rest of this fight.", "effect": "monster_dmg_mult", "value": 0.85},
	"slinger": {"name": "Improvised Shot", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.75},
	"pathfinder": {"name": "Sure Footing", "desc": "Shields the whole party lightly.", "effect": "team_shield_burst", "value": 0.12},
	"longshot": {"name": "One Arrow", "desc": "A finishing blow against the weakest foe, stronger the lower they are.", "effect": "execute_burst", "value": 0.9},
	"blade-dancer": {"name": "Opening Performance", "desc": "A finishing sweep against every wounded foe.", "effect": "execute_all_low", "value": 0.55},
	"warden": {"name": "Walked Worse Halls", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.25},
	"stormtracker": {"name": "Chase the Lightning", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.035},
	"rift-ranger": {"name": "Read the Room", "desc": "Every ability is ready again.", "effect": "reset_cooldowns", "value": 0.0},
	"deadfall-hunter": {"name": "Reversed Trap", "desc": "Weakens every foe's damage for the rest of this fight.", "effect": "monster_dmg_mult", "value": 0.75},
	"voidwalker": {"name": "Half-Step Out", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.22},
	# -- Ranger (content-pass additions) --
	"shadowtracker": {"name": "Scent in the Dark", "desc": "Weakens every foe's damage for the rest of this fight.", "effect": "monster_dmg_mult", "value": 0.85},
	"fieldscout": {"name": "Exact Shot", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.75},
	"nightwarden": {"name": "Watching the Dark", "desc": "Cripples the greatest threat's damage output for the rest of this fight.", "effect": "debuff_lowest", "value": 0.65},
	"sapling-keeper": {"name": "Field Dressing", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.35},
	"duskstalker": {"name": "Gone Before the Echo", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.15},
	"gale-marksman": {"name": "True on the Wind", "desc": "A finishing sweep against every wounded foe.", "effect": "execute_all_low", "value": 0.55},
	"rift-piercer": {"name": "The One Seam", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.0},
	"wintertide-archer": {"name": "Colder Every Shot", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.045},
	"rift-eclipsed-warden": {"name": "Eclipse Volley", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.15},
	# -- Mage --
	"apprentice": {"name": "Unsteady Spark", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.7},
	"cinderling": {"name": "First Spark", "desc": "Ignites the whole party's resolve — damage surges for the rest of this fight.", "effect": "team_dmg_mult", "value": 1.10},
	"fledgling-seer": {"name": "Half-Second Warning", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.08},
	"cinder-adept": {"name": "Warming Cast", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.03},
	"frost-scholar": {"name": "Cold Study", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.2},
	"wardweaver": {"name": "Faster Ward", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.3},
	"stormcaller": {"name": "Building Storm", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.045},
	"pyromancer": {"name": "The Rift Leans Away", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.2},
	"archon-of-storms": {"name": "Thunder's Door", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.0},
	"the-unbound": {"name": "No Name Holds It", "desc": "A heavy burst against the weakest foe.", "effect": "burst_lowest", "value": 1.6},
	# -- Mage (content-pass additions) --
	"thornweaver": {"name": "Grown of Will", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.3},
	"shade-adept": {"name": "The Quiet Spell", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.7},
	"stoneward-mystic": {"name": "Bark and Stone", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.3},
	"grim-conjurer": {"name": "One More Round", "desc": "Mends and shields the lowest-HP ally at once.", "effect": "mend_shield_hybrid", "value": 0.18},
	"verdant-oracle": {"name": "Root and Leaf", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.45},
	"duskglass-seer": {"name": "Sees It Land First", "desc": "Every ability is ready again.", "effect": "reset_cooldowns", "value": 0.0},
	"ashbound-theorist": {"name": "Ends in Fire", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.045},
	"rift-warden-magus": {"name": "Warded Before It Forms", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.35},
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
	"last-light-martyr": {"name": "Last Light", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.6},
	# -- Cleric (content-pass additions) --
	"emberblessed-acolyte": {"name": "Lit Candle", "desc": "Lights every blade with sacred fire — damage surges for the rest of this fight.", "effect": "team_dmg_mult", "value": 1.10},
	"frostward-sister": {"name": "Keeps the Chill Out", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.3},
	"vanguard-chaplain": {"name": "Blessed Blade", "desc": "A finishing sweep against every wounded foe.", "effect": "execute_all_low", "value": 0.5},
	"hearth-warden": {"name": "Fire in the Cold", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.25},
	"ember-confessor": {"name": "Brief Absolution", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.95},
	"frost-anchorite": {"name": "Fasting Vigil", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.5},
	"radiant-vanguard": {"name": "Leads With Light", "desc": "A finishing blow against the weakest foe, stronger the lower they are.", "effect": "execute_burst", "value": 1.0},
	"sainted-ember": {"name": "First Word", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.05},
	# -- Rogue --
	"scavenger": {"name": "Know the Puddles", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.08},
	"runaway": {"name": "Never Fought Fair", "desc": "Shields the whole party lightly.", "effect": "team_shield_burst", "value": 0.10},
	"cutpurse": {"name": "Leaves With More", "desc": "A burst against the weakest foe, healing the caster for a share of the damage.", "effect": "hp_drain_burst", "value": 0.75},
	"skirmisher": {"name": "Never Where You Struck", "desc": "Shields the whole party lightly.", "effect": "team_shield_burst", "value": 0.13},
	"footpad": {"name": "Nobody Heard Them", "desc": "+chance to counter-attack for the rest of this fight.", "effect": "counter_surge", "value": 0.2},
	"shadowfoot": {"name": "Barely Noticed", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.18},
	"fleetblade": {"name": "Getting Faster", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.04},
	"nightblade": {"name": "Strikes From the Dark", "desc": "A heavy burst against the weakest foe, healing the caster for a share of the damage.", "effect": "hp_drain_burst", "value": 1.1},
	"wraithstep": {"name": "Two Footprints", "desc": "A finishing blow against the weakest foe, stronger the lower they are.", "effect": "execute_burst", "value": 1.0},
	"duskrunner": {"name": "Between Heartbeats", "desc": "A heavy burst against the weakest foe, healing the caster for a share of the damage.", "effect": "hp_drain_burst", "value": 1.3},
	# -- Rogue (content-pass additions) --
	"herbrunner": {"name": "Unpoisoned Plants", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.35},
	"arcane-pilferer": {"name": "Warded Vault", "desc": "A burst against the weakest foe, healing the caster for a share of the damage.", "effect": "hp_drain_burst", "value": 0.8},
	"ironhide-footpad": {"name": "Tougher Than It Looks", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.3},
	"glyphhand": {"name": "Reads the Seams", "desc": "Every ability is ready again.", "effect": "reset_cooldowns", "value": 0.0},
	"bramblefoot": {"name": "The Undergrowth Hides More", "desc": "Mends and shields the lowest-HP ally at once.", "effect": "mend_shield_hybrid", "value": 0.15},
	"rift-slipper": {"name": "Half Out of Reality", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.3},
	"wraithblade-adept": {"name": "Thinner and Faster", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.045},
	"the-unseen-hand": {"name": "Already Struck", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.1},
	"the-final-cut": {"name": "Uncatchable", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.28},
}

## One icon per ability *effect* (18 shapes, not ~90 abilities) reusing the
## same assets/skills/ icons skill-tree nodes already draw from — abilities
## and skill nodes never render on the same screen, so sharing icons across
## the two doesn't read as a collision.
const ABILITY_EFFECT_ICON := {
	"mend_burst": "res://assets/skills/potion_red.png",
	"monster_dmg_mult": "res://assets/skills/eye_gem.png",
	"team_dmg_mult": "res://assets/skills/sword_big.png",
	"burst_lowest": "res://assets/skills/sword_slash.png",
	"cleave_burst": "res://assets/skills/sword_dual.png",
	"execute_burst": "res://assets/skills/dagger_red.png",
	"shield_lowest": "res://assets/skills/shield_blue.png",
	"reset_cooldowns": "res://assets/skills/gear.png",
	"dodge_surge": "res://assets/skills/wing.png",
	"escalate_surge": "res://assets/skills/gem_red.png",
	"counter_surge": "res://assets/skills/shield_split.png",
	"wipe_guard_surge": "res://assets/skills/shield_basic.png",
	"self_sac_burst": "res://assets/skills/dagger_blue.png",
	"debuff_lowest": "res://assets/skills/shard_blue.png",
	"team_shield_burst": "res://assets/skills/shield_orange.png",
	"execute_all_low": "res://assets/skills/helm.png",
	"hp_drain_burst": "res://assets/skills/potion_red_sm.png",
	"mend_shield_hybrid": "res://assets/skills/potion_blue_sm.png",
}

static func ability_icon(pool_id: String) -> String:
	var ab: Dictionary = SUBCLASS_ABILITIES.get(pool_id, {})
	return ABILITY_EFFECT_ICON.get(str(ab.get("effect", "")), "res://assets/skills/sword_a.png")

## Every node's "icon" points at a bespoke pixel-art icon under
## assets/skills/ (extracted from a free CraftPix icon sheet) — 38 distinct
## icons across the 2 Tier-1 slots + 9 packages x 4-10 nodes, no two nodes
## sharing an icon.
##
## Tier 1 is 2 slots ("edge" = offense root, "hide" = defense root), but
## which concrete node fills each slot is role-flavored instead of one
## universal pair — every hero in the game no longer starts on the literal
## same two nodes. `cost`/`req_level`/`tier` stay identical across every
## role's variant (so anything that doesn't care which flavor a hero has,
## e.g. SP-cost math, stays correct without needing role context) — only
## `name`/`icon`/`kind`/`value` vary, and `value` is pinned to the same 0.08
## everywhere too, so this is pure re-flavoring, not a rebalance. The id
## stays "edge"/"hide" regardless of role so every KIND_SKILL_PACKAGE's
## `requires: ["edge"]`/`["hide"]` keeps resolving no matter which flavor is
## actually learned. See tier1_for_role().
const TIER1_BY_ROLE := {
	"warrior": [
		{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Honed Edge", "requires": [], "icon": "res://assets/skills/sword_a.png"},
		{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "hp_pct", "value": 0.08, "name": "Thick Hide", "requires": [], "icon": "res://assets/skills/heart.png"},
	],
	"ranger": [
		{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "first_round_pct", "value": 0.08, "name": "Trueshot Aim", "requires": [], "icon": "res://assets/skills/eye_gem.png"},
		{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "dodge_pct", "value": 0.08, "name": "Woodland Step", "requires": [], "icon": "res://assets/skills/boots_brown.png"},
	],
	"mage": [
		{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "escalate_pct", "value": 0.08, "name": "Arcane Focus", "requires": [], "icon": "res://assets/skills/gem_red.png"},
		{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "hazard_guard_pct", "value": 0.08, "name": "Warding Sigil", "requires": [], "icon": "res://assets/skills/shield_orange.png"},
	],
	"cleric": [
		{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "mend_pct", "value": 0.08, "name": "Devotion", "requires": [], "icon": "res://assets/skills/potion_blue.png"},
		{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "wipe_guard", "value": 0.08, "name": "Sanctuary", "requires": [], "icon": "res://assets/skills/shield_split.png"},
	],
	"rogue": [
		{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "first_round_pct", "value": 0.08, "name": "Opening Strike", "requires": [], "icon": "res://assets/skills/dagger_blue.png"},
		{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "dodge_pct", "value": 0.08, "name": "Shadow Step", "requires": [], "icon": "res://assets/skills/face_hood.png"},
	],
}

static func tier1_for_role(role: String) -> Array:
	return TIER1_BY_ROLE.get(role, TIER1_BY_ROLE["warrior"])

## Each package's shape: the original 3 Tier-2 nodes (2 gated by a Tier-1
## root, 1 free) are unchanged, plus a 4th Tier-2 node requiring BOTH roots.
## Tier 3 is a hard-exclusive fork — "cap" (the original capstone, kept
## as-is so any hero who already learned it under the old 1-capstone shape
## stays valid) vs "cap_alt" (a new alternate direction); each `excludes`
## the other, so learning one permanently locks out the other regardless of
## level/SP. Tier 4 is a single finisher per fork, only reachable through
## that fork's own capstone — the "how far does this path go" payoff.
##
## A handful of finishers also carry `combo_kind`/`combo_bonus` — a cross-kind
## party synergy (Combat.hero_skill_total): that finisher's owner gets the
## extra `combo_bonus` only while another CURRENT-RUN party member (not
## themselves) has reached `combo_kind`'s own Tier-3 capstone (cap or
## cap_alt). It's about who you bring together, not just how you build one
## hero — see GameState.party_has_other_kind_capstone().
const KIND_SKILL_PACKAGE := {
	"dmg_pct": [
		{"id": "mastery", "tier": 2, "req_level": 4, "cost": 1, "kind": "dmg_pct", "value": 0.10, "name": "Weapon Mastery", "requires": ["edge"], "icon": "res://assets/skills/sword_silver.png"},
		{"id": "killer_instinct", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Killing Instinct", "requires": ["hide"], "icon": "res://assets/skills/gem_red.png"},
		{"id": "opening_fury", "tier": 2, "req_level": 5, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Opening Fury", "requires": [], "icon": "res://assets/skills/sword_slash.png"},
		{"id": "battle_fury", "tier": 2, "req_level": 5, "cost": 1, "kind": "dmg_pct", "value": 0.06, "name": "Battle Fury", "requires": ["edge", "hide"], "icon": "res://assets/skills/sword_dual.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "dmg_pct", "value": 0.22, "name": "Executioner's Edge", "requires": ["mastery", "killer_instinct"], "excludes": ["cap_alt"], "icon": "res://assets/skills/sword_big.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "escalate_pct", "value": 0.05, "name": "Bloodletter's Patience", "requires": ["mastery", "killer_instinct"], "excludes": ["cap"], "icon": "res://assets/skills/shard_blue.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "dmg_pct", "value": 0.15, "name": "Killing Blow", "requires": ["cap"], "icon": "res://assets/skills/sword_big.png", "combo_kind": "wipe_guard", "combo_bonus": 0.08},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "escalate_pct", "value": 0.04, "name": "Endless Fury", "requires": ["cap_alt"], "icon": "res://assets/skills/leaf_big.png"},
	],
	"hp_pct": [
		{"id": "iron_skin", "tier": 2, "req_level": 4, "cost": 1, "kind": "hp_pct", "value": 0.10, "name": "Iron Skin", "requires": ["hide"], "icon": "res://assets/skills/shield_blue.png"},
		{"id": "steady_guard", "tier": 2, "req_level": 4, "cost": 1, "kind": "hazard_guard_pct", "value": 0.10, "name": "Steady Guard", "requires": ["edge"], "icon": "res://assets/skills/shield_basic.png"},
		{"id": "second_wind", "tier": 2, "req_level": 5, "cost": 1, "kind": "mend_pct", "value": 0.05, "name": "Second Wind", "requires": [], "icon": "res://assets/skills/potion_red_sm.png"},
		{"id": "fortified_stance", "tier": 2, "req_level": 5, "cost": 1, "kind": "hp_pct", "value": 0.06, "name": "Fortified Stance", "requires": ["edge", "hide"], "icon": "res://assets/skills/armor_chest.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "hp_pct", "value": 0.25, "name": "Unbreakable", "requires": ["iron_skin", "steady_guard"], "excludes": ["cap_alt"], "icon": "res://assets/skills/shield_split.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "hazard_guard_pct", "value": 0.18, "name": "Stone Sentinel", "requires": ["iron_skin", "steady_guard"], "excludes": ["cap"], "icon": "res://assets/skills/shield_orange.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "hp_pct", "value": 0.15, "name": "Immovable", "requires": ["cap"], "icon": "res://assets/skills/shield_split.png", "combo_kind": "mend_pct", "combo_bonus": 0.10},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "hazard_guard_pct", "value": 0.12, "name": "Bulwark's Ward", "requires": ["cap_alt"], "icon": "res://assets/skills/armor_shoulder.png"},
	],
	"first_round_pct": [
		{"id": "focus", "tier": 2, "req_level": 4, "cost": 1, "kind": "first_round_pct", "value": 0.12, "name": "Focused Opening", "requires": ["edge"], "icon": "res://assets/skills/dagger_blue.png"},
		{"id": "lightfoot", "tier": 2, "req_level": 4, "cost": 1, "kind": "dodge_pct", "value": 0.10, "name": "Light on Feet", "requires": ["hide"], "icon": "res://assets/skills/boots.png"},
		{"id": "precise_read", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.08, "name": "Precise Read", "requires": [], "icon": "res://assets/skills/eye_gem.png"},
		{"id": "predators_focus", "tier": 2, "req_level": 5, "cost": 1, "kind": "first_round_pct", "value": 0.08, "name": "Predator's Focus", "requires": ["edge", "hide"], "icon": "res://assets/skills/eye_gem.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "first_round_pct", "value": 0.35, "name": "Perfect Opening", "requires": ["focus", "lightfoot"], "excludes": ["cap_alt"], "icon": "res://assets/skills/helm.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "dmg_pct", "value": 0.18, "name": "Assassin's Gambit", "requires": ["focus", "lightfoot"], "excludes": ["cap"], "icon": "res://assets/skills/dagger_blue.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "first_round_pct", "value": 0.20, "name": "Flawless Strike", "requires": ["cap"], "icon": "res://assets/skills/sword_slash.png"},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "dmg_pct", "value": 0.12, "name": "Silent Kill", "requires": ["cap_alt"], "icon": "res://assets/skills/dagger_red.png"},
	],
	"escalate_pct": [
		{"id": "buildup", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Building Momentum", "requires": ["edge"], "icon": "res://assets/skills/gear.png"},
		{"id": "adrenaline", "tier": 2, "req_level": 4, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Adrenaline", "requires": ["hide"], "icon": "res://assets/skills/dagger_red.png"},
		{"id": "second_breath", "tier": 2, "req_level": 5, "cost": 1, "kind": "mend_pct", "value": 0.04, "name": "Second Breath", "requires": [], "icon": "res://assets/skills/potion_blue_sm.png"},
		{"id": "rising_tide", "tier": 2, "req_level": 5, "cost": 1, "kind": "escalate_pct", "value": 0.02, "name": "Rising Tide", "requires": ["edge", "hide"], "icon": "res://assets/skills/gear.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "escalate_pct", "value": 0.06, "name": "Unstoppable Momentum", "requires": ["buildup", "adrenaline"], "excludes": ["cap_alt"], "icon": "res://assets/skills/leaf_big.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "dmg_pct", "value": 0.20, "name": "Berserker's Peak", "requires": ["buildup", "adrenaline"], "excludes": ["cap"], "icon": "res://assets/skills/star.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "escalate_pct", "value": 0.04, "name": "Boundless Fury", "requires": ["cap"], "icon": "res://assets/skills/leaf_big.png", "combo_kind": "dmg_pct", "combo_bonus": 0.03},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "dmg_pct", "value": 0.15, "name": "Overwhelming Force", "requires": ["cap_alt"], "icon": "res://assets/skills/sword_big.png"},
	],
	"mend_pct": [
		{"id": "smite", "tier": 2, "req_level": 4, "cost": 1, "kind": "dmg_pct", "value": 0.10, "name": "Smite", "requires": ["edge"], "icon": "res://assets/skills/sword_dual.png"},
		{"id": "mending", "tier": 2, "req_level": 4, "cost": 1, "kind": "mend_pct", "value": 0.05, "name": "Mending Chant", "requires": ["hide"], "icon": "res://assets/skills/potion_blue.png"},
		{"id": "ward2", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.08, "name": "Ward of Mercy", "requires": [], "icon": "res://assets/skills/shield_orange.png"},
		{"id": "clerics_vow", "tier": 2, "req_level": 5, "cost": 1, "kind": "mend_pct", "value": 0.03, "name": "Battle Cleric's Vow", "requires": ["edge", "hide"], "icon": "res://assets/skills/potion_blue.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "mend_pct", "value": 0.10, "name": "Guardian Angel", "requires": ["smite", "mending"], "excludes": ["cap_alt"], "icon": "res://assets/skills/potion_red.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "dmg_pct", "value": 0.16, "name": "Vengeful Light", "requires": ["smite", "mending"], "excludes": ["cap"], "icon": "res://assets/skills/sword_dual.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "mend_pct", "value": 0.08, "name": "Divine Grace", "requires": ["cap"], "icon": "res://assets/skills/potion_red.png"},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "dmg_pct", "value": 0.12, "name": "Smiting Wrath", "requires": ["cap_alt"], "icon": "res://assets/skills/sword_big.png"},
	],
	"hazard_guard_pct": [
		{"id": "danger_sense", "tier": 2, "req_level": 4, "cost": 1, "kind": "hazard_guard_pct", "value": 0.10, "name": "Danger Sense", "requires": ["hide"], "icon": "res://assets/skills/ring.png"},
		{"id": "preempt", "tier": 2, "req_level": 4, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Preemptive Strike", "requires": ["edge"], "icon": "res://assets/skills/gem_blue_a.png"},
		{"id": "steady_hand", "tier": 2, "req_level": 5, "cost": 1, "kind": "dodge_pct", "value": 0.08, "name": "Steady Hand", "requires": [], "icon": "res://assets/skills/boots_brown.png"},
		{"id": "vigilant_heart", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.05, "name": "Vigilant Heart", "requires": ["edge", "hide"], "icon": "res://assets/skills/ring.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "hazard_guard_pct", "value": 0.20, "name": "Unshakeable", "requires": ["danger_sense", "preempt"], "excludes": ["cap_alt"], "icon": "res://assets/skills/armor_chest.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "first_round_pct", "value": 0.22, "name": "Riposte Mastery", "requires": ["danger_sense", "preempt"], "excludes": ["cap"], "icon": "res://assets/skills/gem_blue_a.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "hazard_guard_pct", "value": 0.15, "name": "Untouchable", "requires": ["cap"], "icon": "res://assets/skills/armor_chest.png"},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "first_round_pct", "value": 0.18, "name": "Perfect Riposte", "requires": ["cap_alt"], "icon": "res://assets/skills/sword_slash.png"},
	],
	# dodge_pct is deliberately asymmetric — a 3-way Tier-3 fork instead of
	# the usual 2 (see the topology-variety doc comment above
	# KIND_SKILL_PACKAGE), so a rogue-flavored kind gets a real third
	# philosophy (offense / pure evasion / counter-punish) instead of a
	# binary choice.
	"dodge_pct": [
		{"id": "evasion", "tier": 2, "req_level": 4, "cost": 1, "kind": "dodge_pct", "value": 0.12, "name": "Evasive Training", "requires": ["hide"], "icon": "res://assets/skills/face_hood.png"},
		{"id": "momentum", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Fleeting Strike", "requires": ["edge"], "icon": "res://assets/skills/wing.png"},
		{"id": "gambit", "tier": 2, "req_level": 5, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Opening Gambit", "requires": [], "icon": "res://assets/skills/gem_blue_b.png"},
		{"id": "phantom_step", "tier": 2, "req_level": 5, "cost": 1, "kind": "dodge_pct", "value": 0.06, "name": "Phantom Step", "requires": ["edge", "hide"], "icon": "res://assets/skills/wing.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "dmg_pct", "value": 0.20, "name": "Shadow Strike", "requires": ["evasion", "momentum"], "excludes": ["cap_alt", "cap_third"], "icon": "res://assets/skills/shard_blue.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "dodge_pct", "value": 0.16, "name": "Untouchable Form", "requires": ["evasion", "momentum"], "excludes": ["cap", "cap_third"], "icon": "res://assets/skills/face_hood.png"},
		{"id": "cap_third", "tier": 3, "req_level": 7, "cost": 2, "kind": "first_round_pct", "value": 0.18, "name": "Riposte Flow", "requires": ["evasion", "momentum"], "excludes": ["cap", "cap_alt"], "icon": "res://assets/skills/gem_blue_b.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "dmg_pct", "value": 0.15, "name": "Killer's Shadow", "requires": ["cap"], "icon": "res://assets/skills/shard_blue.png"},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "dodge_pct", "value": 0.14, "name": "Ghost Step", "requires": ["cap_alt"], "icon": "res://assets/skills/boots.png"},
		{"id": "cap_third_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "first_round_pct", "value": 0.12, "name": "Counterflow Mastery", "requires": ["cap_third"], "icon": "res://assets/skills/gem_blue_b.png"},
	],
	"wipe_guard": [
		{"id": "shieldwall", "tier": 2, "req_level": 4, "cost": 1, "kind": "dodge_pct", "value": 0.10, "name": "Shield Wall", "requires": ["hide"], "icon": "res://assets/skills/armor_shoulder.png"},
		{"id": "vanguard", "tier": 2, "req_level": 4, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Vanguard Strike", "requires": ["edge"], "icon": "res://assets/skills/gem_cluster.png"},
		{"id": "instinct", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.08, "name": "Battle Instinct", "requires": [], "icon": "res://assets/skills/cloak_a.png"},
		{"id": "guardians_resolve", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.06, "name": "Guardian's Resolve", "requires": ["edge", "hide"], "icon": "res://assets/skills/cloak_a.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "wipe_guard", "value": 0.25, "name": "Last Stand", "requires": ["shieldwall", "vanguard"], "excludes": ["cap_alt"], "icon": "res://assets/skills/trophy.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "hp_pct", "value": 0.20, "name": "Undying Vanguard", "requires": ["shieldwall", "vanguard"], "excludes": ["cap"], "icon": "res://assets/skills/shield_split.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "wipe_guard", "value": 0.15, "name": "Defiant to the End", "requires": ["cap"], "icon": "res://assets/skills/trophy.png", "combo_kind": "hazard_guard_pct", "combo_bonus": 0.10},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "hp_pct", "value": 0.15, "name": "Iron Will", "requires": ["cap_alt"], "icon": "res://assets/skills/armor_shoulder.png"},
	],
	# boss_alpha_strike is deliberately asymmetric the other direction — a
	# single linear capstone, no fork at all (see the topology-variety doc
	# comment above KIND_SKILL_PACKAGE). It's the rarest kind (every carrier
	# is B rank or higher already), so "total commitment, one undivided
	# payoff" fits better than a branching choice: the capstone requires ALL
	# FOUR Tier-2 nodes instead of the usual 2.
	"boss_alpha_strike": [
		{"id": "buildup2", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Arcane Buildup", "requires": ["edge"], "icon": "res://assets/skills/star.png"},
		{"id": "ward", "tier": 2, "req_level": 4, "cost": 1, "kind": "hazard_guard_pct", "value": 0.10, "name": "Ward Sigil", "requires": ["hide"], "icon": "res://assets/skills/gem_blue_big.png"},
		{"id": "slip", "tier": 2, "req_level": 5, "cost": 1, "kind": "dodge_pct", "value": 0.08, "name": "Arcane Slip", "requires": [], "icon": "res://assets/skills/shard_green.png"},
		{"id": "arcane_convergence", "tier": 2, "req_level": 5, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Arcane Convergence", "requires": ["edge", "hide"], "icon": "res://assets/skills/gem_blue_big.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "boss_alpha_strike", "value": 1.15, "name": "Cataclysm", "requires": ["buildup2", "ward", "slip", "arcane_convergence"], "icon": "res://assets/skills/ingot_gold.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "dmg_pct", "value": 0.25, "name": "World Ender", "requires": ["cap"], "icon": "res://assets/skills/ingot_gold.png"},
	],
}


## Tier 5, one per tree: a keystone changes HOW a hero plays rather than
## scaling a number — its upside is `effects` (Combat.hero_effects shape), its
## cost a real flat drawback in `kind`/`value`. Reached from ANY of the tree's
## Tier-3 Path nodes (`requires_any`), so whichever fork you took leads here —
## and at 3 SP against the 9 a Lv10 hero earns, it competes with that path's
## own Mastery finisher (and Awakening/the role signature) for the same points.
const KEYSTONE_REQUIRES_ANY := ["cap", "cap_alt", "cap_third"]
const KEYSTONES := {
	"dmg_pct": {"name": "Headsman's Creed", "arch": "executioner", "icon": "res://assets/skills/sword_big.png",
		"effects": [{"kind": "dmg_pct", "value": 0.35, "cond": {"target_below": 0.4}}], "kind": "hp_pct", "value": -0.08},
	"hp_pct": {"name": "Bulwark Oath", "arch": "guardian", "icon": "res://assets/skills/shield_split.png",
		"effects": [{"trigger": "ally_targeted", "effect": "intercept", "value": 0.5}], "kind": "dmg_pct", "value": -0.08},
	"first_round_pct": {"name": "Ambush Doctrine", "arch": "opener", "icon": "res://assets/skills/dagger_red.png",
		"effects": [{"kind": "dmg_pct", "value": 0.40, "cond": {"round_max": 1}}, {"kind": "dmg_pct", "value": 0.15, "cond": {"acting_first": true}}], "kind": "escalate_pct", "value": -0.02},
	"escalate_pct": {"name": "Slow Burn", "arch": "attrition", "icon": "res://assets/skills/leaf_big.png",
		"effects": [{"kind": "dmg_pct", "value": 0.30, "cond": {"round_min": 4}}], "kind": "first_round_pct", "value": -0.15},
	"mend_pct": {"name": "Martyr's Grace", "arch": "sustain", "icon": "res://assets/skills/potion_red.png",
		"effects": [{"trigger": "party_mend", "effect": "shield_lowest", "value": 0.10}], "kind": "dmg_pct", "value": -0.10},
	"hazard_guard_pct": {"name": "Iron Discipline", "arch": "guardian", "icon": "res://assets/skills/armor_chest.png",
		"effects": [{"trigger": "evade_or_heavy", "effect": "weaken_attacker", "value": 0.12}], "kind": "speed_pct", "value": -0.10},
	"dodge_pct": {"name": "Phantom Riposte", "arch": "evasion", "icon": "res://assets/skills/face_hood.png",
		"effects": [{"trigger": "evade_or_heavy", "effect": "counter_attack", "value": 0.40}], "kind": "hp_pct", "value": -0.10},
	"wipe_guard": {"name": "Undying", "arch": "guardian", "icon": "res://assets/skills/trophy.png",
		"effects": [{"kind": "dodge_pct", "value": 0.25, "cond": {"hp_below": 0.3}}, {"kind": "dmg_pct", "value": 0.20, "cond": {"hp_below": 0.3}}], "kind": "hp_pct", "value": -0.05},
	"boss_alpha_strike": {"name": "Giantslayer", "arch": "executioner", "icon": "res://assets/skills/ingot_gold.png",
		"effects": [{"kind": "dmg_pct", "value": 0.35, "cond": {"vs_boss": true}}], "kind": "first_round_pct", "value": -0.10},
}

## One per role, shared across every tree the hero holds (stored bare like
## "edge"/"hide"): the role's signature trick, no drawback. Level 8, needs
## both Tier-1 roots.
const ROLE_SIGNATURES := {
	"warrior": {"name": "Shieldbearer", "arch": "guardian", "icon": "res://assets/skills/helm.png",
		"effects": [{"trigger": "ally_targeted", "effect": "intercept", "value": 0.30, "cond": {"formation": "front"}}]},
	"ranger": {"name": "Hunter's Mark", "arch": "executioner", "icon": "res://assets/skills/eye_gem.png",
		"effects": [{"kind": "dmg_pct", "value": 0.20, "cond": {"target_below": 0.5}}]},
	"mage": {"name": "Arcane Surge", "arch": "attrition", "icon": "res://assets/skills/gem_blue_big.png",
		"effects": [{"trigger": "on_kill", "effect": "shave_cooldowns", "value": 1.0}]},
	"cleric": {"name": "Beacon", "arch": "sustain", "icon": "res://assets/skills/potion_blue.png",
		"effects": [{"trigger": "on_kill", "effect": "mend_party", "value": 0.05}]},
	"rogue": {"name": "Opportunist", "arch": "executioner", "icon": "res://assets/skills/dagger_blue.png",
		"effects": [{"trigger": "on_kill", "effect": "extra_turn", "value": 1.0}]},
}

## The keystone for `kind`'s tree as a full skill node, or {}.
static func keystone_node(kind: String) -> Dictionary:
	if not KEYSTONES.has(kind):
		return {}
	var n: Dictionary = KEYSTONES[kind].duplicate(true)
	n.merge({"id": "keystone", "tier": 5, "req_level": 10, "cost": 3, "requires": [], "requires_any": KEYSTONE_REQUIRES_ANY})
	return n

## `role`'s signature as a full skill node (Tier 5 column, shared/bare key).
static func signature_node(role: String) -> Dictionary:
	var n: Dictionary = ROLE_SIGNATURES.get(role, ROLE_SIGNATURES["warrior"]).duplicate(true)
	n.merge({"id": "signature", "tier": 5, "req_level": 8, "cost": 2, "kind": "", "value": 0.0, "requires": ["edge", "hide"]})
	return n

## The storage key a skill uses in Hero.skills. Every KIND_SKILL_PACKAGE
## reuses the same node ids ("cap", "mastery", ...), which was harmless when
## a hero only ever had one active tree — evolving keeping the old tree
## reachable (see hero_tree_summaries) means two of a hero's trees can now
## both have a node called "cap", so anything but the universal Tier-1
## roots ("edge"/"hide" — shared, learned once, apply to every tree) needs
## its owning kind folded into the key.
static func skill_storage_key(kind: String, node_id: String) -> String:
	return node_id if node_id in ["edge", "hide", "signature"] else "%s:%s" % [kind, node_id]


## Every distinct tree a hero currently has access to: their current class's
## kind plus their one retained prior stage's kind (Hero.prior_pool_id) —
## de-duplicated, since evolving into a same-kind class would otherwise show
## the identical tree twice. Each entry
## is {"kind": kind, "label": the subclass name that tree came from}.
static func hero_tree_summaries(h: Hero) -> Array:
	var history: Array = [h.pool_id]
	if h.prior_pool_id != "":
		history.append(h.prior_pool_id)
	var seen: Array = []
	var out: Array = []
	for pid in history:
		var cls := find_class(pid)
		if cls.is_empty():
			continue
		var kind: String = cls.get("kind", "dmg_pct")
		if seen.has(kind):
			continue
		seen.append(kind)
		out.append({"kind": kind, "label": cls["name"]})
	return out


## Every subclass a hero at `cls`'s rank could evolve into — every CLASS_POOL
## entry sharing `cls`'s role at the next rank up, not just the first match
## (CLASS_POOL's array order shouldn't matter). The player picks one of these
## in the Roster's evolution picker; GameState.evolve_hero() validates it.
static func evolution_choices(cls: Dictionary) -> Array:
	var rank_idx := rank_index(cls["rank"])
	for i in range(rank_idx + 1, RANKS.size()):
		var matches: Array = CLASS_POOL.filter(func(c): return c["role"] == cls["role"] and c["rank"] == RANKS[i]["id"])
		if not matches.is_empty():
			return matches
	return []

# Rank ladder shared by recruited heroes and the Champion (see GameState's
# recruit_hero/reroll_champion). Rank sets weight (pull odds), stat
# multiplier, and hero rank progression via evolution.
const RANKS := [
	{"id": "F", "weight": 100, "mult": 0.9, "cost": 25},
	{"id": "E", "weight": 60, "mult": 1.0, "cost": 45},
	{"id": "D", "weight": 35, "mult": 1.15, "cost": 75},
	{"id": "C", "weight": 20, "mult": 1.35, "cost": 130},
	{"id": "B", "weight": 10, "mult": 1.6, "cost": 220},
	{"id": "A", "weight": 4, "mult": 2.0, "cost": 380},
	{"id": "S", "weight": 1, "mult": 2.6, "cost": 650},
]

# Evolution Stones — a rank-tiered consumable dropped by clearing a Rift Map
# rift of that rank (GameState.seal_rift), spent by GameState.evolve_hero()
# to unlock the E/D/C/B/A/S jump. Nothing evolves into F, so there's no
# F-tier stone. First-draft numbers, tunable after the loop is playable.
const EVOLUTION_STONE_DROP_CHANCE := 0.15
const EVOLUTION_STONE_BONUS_SP_CAP := 3

## Rift Map ranks run past S (SS/SSS) but hero rank tops out at S, so a stone
## from one of those rarer mapped rifts still clamps down to the one hero
## tier that can use it — it doesn't just get wasted.
static func stone_tier_for_rift_rank(rift_rank: String) -> String:
	if rift_rank == "" or rift_rank == "F":
		return ""
	if rift_rank == "SS" or rift_rank == "SSS":
		return "S"
	return rift_rank

## Compact "E×1 · C×2 · B×1" line for whatever Evolution Stones are actually
## held — RANKS order, zero counts skipped, "" if the player is holding none.
static func evolution_stones_text(stones: Dictionary) -> String:
	var parts: Array[String] = []
	for r in RANKS:
		var n := int(stones.get(r["id"], 0))
		if n > 0:
			parts.append("%s×%d" % [r["id"], n])
	return " · ".join(parts)

# Ability Awakening — a second SP sink (GameState.awaken_ability) alongside
# the skill tree: spend SP once to make a hero's existing Active Ability do
# something extra, instead of only ever making the tree's numbers bigger.
# The bonus is bucketed by effect *category*, not the tree's usual "bigger
# number" — 5 buckets covering all 18 SUBCLASS_ABILITIES effect ids, so
# awakened abilities genuinely diverge from their un-awakened siblings
# without needing 18 fully bespoke riders (Combat.resolve_round applies each
# bucket's rider once, right after the primary effect resolves).
const ABILITY_AWAKENING_COST := 3
const ABILITY_AWAKENING_COOLDOWN_REDUCTION := 1  # "buff" bucket's rider

const ABILITY_AWAKENING_BUCKET := {
	# Party-wide buffs/utility — rider: -1 round off the Ability's own cooldown.
	"dodge_surge": "buff", "escalate_surge": "buff", "counter_surge": "buff",
	"wipe_guard_surge": "buff", "team_shield_burst": "buff", "team_dmg_mult": "buff",
	# Single-target damage — rider: every foe's damage output dips slightly.
	"burst_lowest": "single_dmg", "execute_burst": "single_dmg",
	"hp_drain_burst": "single_dmg", "self_sac_burst": "single_dmg",
	# AoE damage — rider: the party gets a small dodge bump.
	"cleave_burst": "aoe_dmg", "execute_all_low": "aoe_dmg",
	# Healing/shielding — rider: the caster shields themselves too.
	"mend_burst": "support", "shield_lowest": "support", "mend_shield_hybrid": "support",
	# Debuff/utility — rider: a small permanent damage stack for the fight.
	"monster_dmg_mult": "utility", "reset_cooldowns": "utility", "debuff_lowest": "utility",
}

const ABILITY_AWAKENING_BUCKET_DESC := {
	"buff": "-1 round Ability cooldown",
	"single_dmg": "also weakens every foe's damage slightly",
	"aoe_dmg": "also grants the party a dodge boost",
	"support": "also shields the caster",
	"utility": "also stacks a small permanent damage boost",
}

static func awakening_bonus_text(pool_id: String) -> String:
	var ab: Dictionary = SUBCLASS_ABILITIES.get(pool_id, {})
	var bucket: String = ABILITY_AWAKENING_BUCKET.get(str(ab.get("effect", "")), "buff")
	return ABILITY_AWAKENING_BUCKET_DESC.get(bucket, "")

# Party-kind synergy (GameState.party_resonance_bonus/party_eclectic_bonus,
# read by Combat.hero_skill_total) — computed live from the active run's
# roster, never cached, so it can't go stale if the party ever changes.
# Resonance rewards bringing 2+ heroes who currently share a kind (their
# builds reinforce each other); Eclectic rewards the opposite, a genuinely
# varied 3+ party with no repeats. Never both at once for the same party.
const PARTY_RESONANCE_BONUS := 0.05
const PARTY_ECLECTIC_BONUS := 0.03

# Recruitment-screen reroll fees. Flat rather than rank-scaled, so a bad
# opening pull is always cheap to retry (below even the F-rank recruit cost)
# and a Champion reroll — free and automatic on every rift seal already —
# just costs a mid-tier hero's worth of Coins to trigger on demand instead.
const RECRUIT_REROLL_COST := 20
const CHAMPION_REROLL_COST := 150

## Compact "F 43% · E 26% · ..." odds line for the recruit/Champion rank
## table, so the pull weights aren't just implicit in RANKS.
static func rank_odds_text() -> String:
	var total := 0
	for r in RANKS:
		total += int(r["weight"])
	var parts: Array[String] = []
	for r in RANKS:
		var pct := 100.0 * float(r["weight"]) / float(total)
		parts.append("%s %s" % [r["id"], (str(snappedf(pct, 0.1)) + "%") if pct < 1.0 else (str(int(round(pct))) + "%")])
	return " · ".join(parts)

## Rift Map ranks — reuses the hero-rank vocabulary (F-S) extended with two
## rarer tiers (SS/SSS) for the map's random rift rolls. Weights preserve the
## exact same relative odds as hero RANKS for F-S (just rescaled ×10 for the
## finer granularity SS/SSS need); fuse_runs is how many rift runs (or rests)
## a rift stays open before an unaddressed one Riftbreaks — shorter at higher
## rank, so a rare S/SS/SSS sighting is genuinely fleeting.
## Recovery in rift runs rather than real time: a downed hero sits out this
## many runs (Medical upgrades shorten it, a bed takes one off), and a wounded
## hero regains this share of max HP each time a run ends (all of it in a bed).
const DOWNED_RECOVERY_RUNS := 2
const WOUND_HEAL_PER_RUN := 0.5

const RIFT_RANKS := [
	{"id": "F", "weight": 1000, "fuse_runs": 5},
	{"id": "E", "weight": 600, "fuse_runs": 4},
	{"id": "D", "weight": 350, "fuse_runs": 4},
	{"id": "C", "weight": 200, "fuse_runs": 3},
	{"id": "B", "weight": 100, "fuse_runs": 3},
	{"id": "A", "weight": 40, "fuse_runs": 2},
	{"id": "S", "weight": 10, "fuse_runs": 2},
	{"id": "SS", "weight": 3, "fuse_runs": 1},
	{"id": "SSS", "weight": 1, "fuse_runs": 1},
]

static func find_rift_rank(rank_id: String) -> Dictionary:
	for r in RIFT_RANKS:
		if r["id"] == rank_id:
			return r
	return RIFT_RANKS[0]


## 0-8 severity index for a Rift Rank id — used both to scale a Riftbreak
## encounter's difficulty (summed across every merged pending rank) and to
## decide the loss-consequence branch (index >= 6, i.e. S/SS/SSS, is the
## game-ending branch; below that is the Coin/Crystal compensation branch).
static func rift_rank_index(rank_id: String) -> int:
	for i in RIFT_RANKS.size():
		if RIFT_RANKS[i]["id"] == rank_id:
			return i
	return 0


## Cumulative modifiers a mapped rift's rank folds into the fight/run — each
## rank includes every modifier below it plus its own. Applied by
## GameState.start_map_rift() to a copy of DIFFICULTIES[0], not by mutating
## the base difficulty table itself. First-draft values, tunable later.
const RIFT_RANK_MODIFIERS := {
	"F": {},
	"E": {"monster_hp_mult": 1.10},
	"D": {"monster_hp_mult": 1.10, "monster_dmg_mult": 1.10},
	"C": {"monster_hp_mult": 1.10, "monster_dmg_mult": 1.10, "hazard_severity_up": 1},
	"B": {"monster_hp_mult": 1.10, "monster_dmg_mult": 1.10, "hazard_severity_up": 1, "elite_chance_up": true},
	"A": {"monster_hp_mult": 1.10, "monster_dmg_mult": 1.10, "hazard_severity_up": 1, "elite_chance_up": true, "shop_chance_down": true},
	"S": {"monster_hp_mult": 1.10, "monster_dmg_mult": 1.10, "hazard_severity_up": 1, "elite_chance_up": true, "shop_chance_down": true, "relic_rarity_floor_down": 1},
	"SS": {"monster_hp_mult": 1.10, "monster_dmg_mult": 1.10, "hazard_severity_up": 1, "elite_chance_up": true, "shop_chance_down": true, "relic_rarity_floor_down": 1, "boss_double_mechanic": true},
	"SSS": {"monster_hp_mult": 1.35, "monster_dmg_mult": 1.35, "hazard_severity_up": 2, "elite_chance_up": true, "shop_chance_down": true, "relic_rarity_floor_down": 1, "boss_double_mechanic": true},
}

const CHAMP_KIND_BASE := {
	"dmg_pct": 0.06, "hp_pct": 0.06, "first_round_pct": 0.15, "escalate_pct": 0.02,
	"mend_pct": 0.03, "dodge_pct": 0.08, "hazard_guard_pct": 0.10, "wipe_guard": 0.2, "boss_alpha_strike": 1.0,
}

# Classes across the 5 roles. Ranks F-C are a shared, un-named identity per
# role (`name` is just "Warrior"/"Ranger"/etc — no subclass to speak of yet);
# a real named subclass only forks off starting at rank B, then again at A
# and S — see evolve_hero()/GameData.evolution_choices() and the Evolution
# Stone constants below. `role` picks the Ability/anim assets; `kind` picks
# the skill-tree package (KIND_SKILL_PACKAGE, reached via hero_tree_summaries)
# and the id itself picks the unique Ability (SUBCLASS_ABILITIES); rank/flavor
# are the same F-S vocabulary the Champion pool uses.
const CLASS_POOL := [
	# -- Warrior (melee bruisers & tanks) --
	# F-C rows below share the un-named "Warrior" identity (see the doc
	# comment above CLASS_POOL) — only `name` changed from the original
	# per-row titles; kind/type/flavor/ratios are untouched so existing saves
	# and skill-tree investment aren't disturbed.
	{"id": "squire", "name": "Warrior", "role": "warrior", "rank": "F", "type": "Ember", "hp_ratio": 1.0, "dmg_ratio": 1.0, "kind": "dmg_pct", "flavor": "A guild recruit swinging a borrowed blade."},
	{"id": "footman", "name": "Warrior", "role": "warrior", "rank": "F", "type": "Umbral", "hp_ratio": 1.2, "dmg_ratio": 0.8, "kind": "hazard_guard_pct", "flavor": "Slow, sturdy, and hard to put down."},
	{"id": "duelist", "name": "Warrior", "role": "warrior", "rank": "E", "type": "Ember", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "first_round_pct", "flavor": "Wins the exchange before it starts."},
	{"id": "bulwark", "name": "Warrior", "role": "warrior", "rank": "E", "type": "Umbral", "hp_ratio": 1.3, "dmg_ratio": 0.7, "kind": "hp_pct", "flavor": "A wall with opinions."},
	{"id": "berserker", "name": "Warrior", "role": "warrior", "rank": "D", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 1.3, "kind": "dmg_pct", "flavor": "Considers armor a personal insult."},
	{"id": "iron-guard", "name": "Warrior", "role": "warrior", "rank": "C", "type": "Umbral", "hp_ratio": 1.4, "dmg_ratio": 0.8, "kind": "hp_pct", "flavor": "Rift-forged plate, dented and unbothered."},
	{"id": "bloodletter", "name": "Warrior", "role": "warrior", "rank": "C", "type": "Ember", "hp_ratio": 0.9, "dmg_ratio": 1.3, "kind": "escalate_pct", "flavor": "Trades wounds and wins the trade."},
	{"id": "runeblade", "name": "Runeblade", "role": "warrior", "rank": "B", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 1.2, "kind": "first_round_pct", "flavor": "Every strike is already inscribed."},
	{"id": "ashen-templar", "name": "Ashen Templar", "role": "warrior", "rank": "A", "type": "Umbral", "hp_ratio": 1.3, "dmg_ratio": 1.0, "kind": "wipe_guard", "flavor": "Has died before. Didn't care for it."},
	{"id": "rift-sovereign", "name": "Rift Sovereign", "role": "warrior", "rank": "S", "type": "Arcane", "hp_ratio": 1.1, "dmg_ratio": 1.4, "kind": "boss_alpha_strike", "flavor": "The Rift answers to almost nothing. Almost."},
	# -- Warrior (content-pass additions — fills the role's missing mend_pct/
	# dodge_pct kinds and Verdant/Frost types) --
	{"id": "fieldmender", "name": "Warrior", "role": "warrior", "rank": "F", "type": "Verdant", "hp_ratio": 1.0, "dmg_ratio": 0.8, "kind": "mend_pct", "flavor": "Patches the party between swings."},
	{"id": "featherguard", "name": "Warrior", "role": "warrior", "rank": "E", "type": "Frost", "hp_ratio": 0.9, "dmg_ratio": 1.0, "kind": "dodge_pct", "flavor": "Heavy armor, light feet."},
	{"id": "trailblazer", "name": "Warrior", "role": "warrior", "rank": "F", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "dmg_pct", "flavor": "First through the door, first to swing."},
	{"id": "frostguard", "name": "Warrior", "role": "warrior", "rank": "E", "type": "Frost", "hp_ratio": 1.3, "dmg_ratio": 0.7, "kind": "hp_pct", "flavor": "The cold never bothered the plate much."},
	{"id": "warbrand", "name": "Warrior", "role": "warrior", "rank": "D", "type": "Ember", "hp_ratio": 0.9, "dmg_ratio": 1.2, "kind": "escalate_pct", "flavor": "Gets angrier, not slower."},
	{"id": "aegis-bearer", "name": "Warrior", "role": "warrior", "rank": "C", "type": "Frost", "hp_ratio": 1.3, "dmg_ratio": 0.8, "kind": "wipe_guard", "flavor": "The last thing standing, on principle."},
	{"id": "stormguard", "name": "Stormguard", "role": "warrior", "rank": "B", "type": "Frost", "hp_ratio": 1.0, "dmg_ratio": 1.1, "kind": "first_round_pct", "flavor": "Meets the charge before it lands."},
	{"id": "rift-breaker", "name": "Rift-Breaker", "role": "warrior", "rank": "A", "type": "Verdant", "hp_ratio": 1.2, "dmg_ratio": 1.1, "kind": "boss_alpha_strike", "flavor": "Puts the first crack in anything."},
	# -- Ranger (precision & terrain reading) --
	{"id": "trapper", "name": "Ranger", "role": "ranger", "rank": "F", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Sets more snares than the Rift can spring."},
	{"id": "slinger", "name": "Ranger", "role": "ranger", "rank": "F", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 1.0, "kind": "dmg_pct", "flavor": "Improvises a weapon out of whatever's at hand."},
	{"id": "pathfinder", "name": "Ranger", "role": "ranger", "rank": "E", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Already knows where the floor gives way."},
	{"id": "longshot", "name": "Ranger", "role": "ranger", "rank": "E", "type": "Frost", "hp_ratio": 0.8, "dmg_ratio": 1.1, "kind": "first_round_pct", "flavor": "One arrow. Rarely needs a second."},
	{"id": "blade-dancer", "name": "Ranger", "role": "ranger", "rank": "D", "type": "Ember", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "first_round_pct", "flavor": "The opening strike is the whole performance."},
	{"id": "warden", "name": "Ranger", "role": "ranger", "rank": "D", "type": "Verdant", "hp_ratio": 1.1, "dmg_ratio": 0.9, "kind": "hp_pct", "flavor": "Has walked through worse hallways than this."},
	{"id": "stormtracker", "name": "Ranger", "role": "ranger", "rank": "D", "type": "Frost", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "escalate_pct", "flavor": "Follows the lightning instead of waiting for thunder."},
	{"id": "rift-ranger", "name": "Ranger", "role": "ranger", "rank": "C", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 1.1, "kind": "dodge_pct", "flavor": "Reads a hallway before it reads back."},
	{"id": "deadfall-hunter", "name": "Ranger", "role": "ranger", "rank": "C", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 1.0, "kind": "hazard_guard_pct", "flavor": "Sets the trap the Rift walks into instead."},
	{"id": "voidwalker", "name": "Voidwalker", "role": "ranger", "rank": "A", "type": "Arcane", "hp_ratio": 0.9, "dmg_ratio": 1.2, "kind": "dodge_pct", "flavor": "Half-stepped out of the fight before it began."},
	# -- Ranger (content-pass additions — fills the role's missing mend_pct/
	# wipe_guard/boss_alpha_strike kinds and Umbral type) --
	{"id": "shadowtracker", "name": "Ranger", "role": "ranger", "rank": "F", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Tracks by scent when the light gives out."},
	{"id": "fieldscout", "name": "Ranger", "role": "ranger", "rank": "F", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 1.0, "kind": "dmg_pct", "flavor": "Knows exactly where to put an arrow."},
	{"id": "nightwarden", "name": "Ranger", "role": "ranger", "rank": "E", "type": "Umbral", "hp_ratio": 1.0, "dmg_ratio": 0.9, "kind": "wipe_guard", "flavor": "Watches the dark so the party doesn't have to."},
	{"id": "sapling-keeper", "name": "Ranger", "role": "ranger", "rank": "E", "type": "Verdant", "hp_ratio": 1.0, "dmg_ratio": 0.8, "kind": "mend_pct", "flavor": "Field dressings from whatever's growing nearby."},
	{"id": "duskstalker", "name": "Ranger", "role": "ranger", "rank": "D", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "dodge_pct", "flavor": "Gone before the echo catches up."},
	{"id": "gale-marksman", "name": "Ranger", "role": "ranger", "rank": "C", "type": "Frost", "hp_ratio": 0.8, "dmg_ratio": 1.2, "kind": "first_round_pct", "flavor": "The wind carries the first shot true."},
	{"id": "rift-piercer", "name": "Rift-Piercer", "role": "ranger", "rank": "B", "type": "Arcane", "hp_ratio": 0.9, "dmg_ratio": 1.2, "kind": "boss_alpha_strike", "flavor": "Finds the one seam every ward has."},
	{"id": "wintertide-archer", "name": "Wintertide Archer", "role": "ranger", "rank": "A", "type": "Frost", "hp_ratio": 1.0, "dmg_ratio": 1.2, "kind": "escalate_pct", "flavor": "Colder with every arrow loosed."},
	{"id": "rift-eclipsed-warden", "name": "Rift-Eclipsed Warden", "role": "ranger", "rank": "S", "type": "Umbral", "hp_ratio": 1.0, "dmg_ratio": 1.3, "kind": "boss_alpha_strike", "flavor": "Every shadow in the Rift owes her an arrow."},
	# -- Mage (escalating & warding casters) --
	{"id": "apprentice", "name": "Mage", "role": "mage", "rank": "F", "type": "Arcane", "hp_ratio": 0.8, "dmg_ratio": 0.9, "kind": "escalate_pct", "flavor": "Still learning to hold a spark steady."},
	{"id": "cinderling", "name": "Mage", "role": "mage", "rank": "F", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 0.9, "kind": "dmg_pct", "flavor": "Sparks first, thinks second."},
	{"id": "fledgling-seer", "name": "Mage", "role": "mage", "rank": "F", "type": "Arcane", "hp_ratio": 0.9, "dmg_ratio": 0.8, "kind": "hazard_guard_pct", "flavor": "Sees the trap a half-second before it triggers."},
	{"id": "cinder-adept", "name": "Mage", "role": "mage", "rank": "E", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 1.0, "kind": "escalate_pct", "flavor": "Every spell warms up the next."},
	{"id": "frost-scholar", "name": "Mage", "role": "mage", "rank": "E", "type": "Frost", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Studies the Rift's cold so it can't study back."},
	{"id": "wardweaver", "name": "Mage", "role": "mage", "rank": "D", "type": "Arcane", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Weaves a ward faster than the Rift can break it."},
	{"id": "stormcaller", "name": "Mage", "role": "mage", "rank": "C", "type": "Frost", "hp_ratio": 0.8, "dmg_ratio": 1.1, "kind": "escalate_pct", "flavor": "Calls down more with every passing second."},
	{"id": "pyromancer", "name": "Pyromancer", "role": "mage", "rank": "B", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 1.2, "kind": "dodge_pct", "flavor": "The Rift itself seems to lean away."},
	{"id": "archon-of-storms", "name": "Archon of Storms", "role": "mage", "rank": "A", "type": "Frost", "hp_ratio": 1.0, "dmg_ratio": 1.2, "kind": "boss_alpha_strike", "flavor": "Opens every Warden's door with thunder."},
	{"id": "the-unbound", "name": "The Unbound", "role": "mage", "rank": "S", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 1.3, "kind": "escalate_pct", "flavor": "No name holds it. No floor stops it."},
	# -- Mage (content-pass additions — fills the role's missing hp_pct/
	# first_round_pct/mend_pct/wipe_guard kinds and Verdant/Umbral types) --
	{"id": "thornweaver", "name": "Mage", "role": "mage", "rank": "F", "type": "Verdant", "hp_ratio": 1.0, "dmg_ratio": 0.8, "kind": "mend_pct", "flavor": "Grows a ward out of nothing but will."},
	{"id": "shade-adept", "name": "Mage", "role": "mage", "rank": "F", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "first_round_pct", "flavor": "The first spell is always the quiet one."},
	{"id": "stoneward-mystic", "name": "Mage", "role": "mage", "rank": "E", "type": "Verdant", "hp_ratio": 1.2, "dmg_ratio": 0.7, "kind": "hp_pct", "flavor": "Turns skin to something closer to bark."},
	{"id": "grim-conjurer", "name": "Mage", "role": "mage", "rank": "E", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.0, "kind": "wipe_guard", "flavor": "Bargains with the dark for one more round."},
	{"id": "verdant-oracle", "name": "Mage", "role": "mage", "rank": "D", "type": "Verdant", "hp_ratio": 1.0, "dmg_ratio": 0.9, "kind": "mend_pct", "flavor": "Reads the future in root and leaf."},
	{"id": "duskglass-seer", "name": "Mage", "role": "mage", "rank": "C", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "dodge_pct", "flavor": "Sees the strike land before it's thrown."},
	{"id": "ashbound-theorist", "name": "Ashbound Theorist", "role": "mage", "rank": "B", "type": "Ember", "hp_ratio": 0.9, "dmg_ratio": 1.2, "kind": "escalate_pct", "flavor": "Every equation ends in fire."},
	{"id": "rift-warden-magus", "name": "Rift-Warden Magus", "role": "mage", "rank": "A", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 1.2, "kind": "hazard_guard_pct", "flavor": "Wards the floor before the Rift finishes forming it."},
	# -- Cleric (sustain & support) --
	{"id": "peddler", "name": "Cleric", "role": "cleric", "rank": "F", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 0.8, "kind": "mend_pct", "flavor": "Sells bandages. Uses them too."},
	{"id": "acolyte", "name": "Cleric", "role": "cleric", "rank": "F", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 0.8, "kind": "mend_pct", "flavor": "Prays quietly, heals quietly."},
	{"id": "herbalist", "name": "Cleric", "role": "cleric", "rank": "E", "type": "Verdant", "hp_ratio": 1.0, "dmg_ratio": 0.8, "kind": "mend_pct", "flavor": "Carries a field kit for every wound."},
	{"id": "lay-brother", "name": "Cleric", "role": "cleric", "rank": "E", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 0.9, "kind": "dmg_pct", "flavor": "Swings a censer like it owes him money."},
	{"id": "battle-chaplain", "name": "Cleric", "role": "cleric", "rank": "D", "type": "Arcane", "hp_ratio": 1.0, "dmg_ratio": 0.9, "kind": "dodge_pct", "flavor": "Prays loudly enough to keep the party moving."},
	{"id": "zealot", "name": "Cleric", "role": "cleric", "rank": "D", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "dmg_pct", "flavor": "Faith, mostly. A blade, occasionally."},
	{"id": "rift-medic", "name": "Cleric", "role": "cleric", "rank": "C", "type": "Verdant", "hp_ratio": 1.0, "dmg_ratio": 0.9, "kind": "mend_pct", "flavor": "Faster hands than the Rift has wounds to give."},
	{"id": "dawnkeeper", "name": "Dawnkeeper", "role": "cleric", "rank": "B", "type": "Arcane", "hp_ratio": 1.1, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Carries first light into the deepest floor."},
	{"id": "sanctified-shield", "name": "Sanctified Shield", "role": "cleric", "rank": "B", "type": "Arcane", "hp_ratio": 1.3, "dmg_ratio": 0.9, "kind": "wipe_guard", "flavor": "Swears the party will not fall today."},
	{"id": "alchemist", "name": "Alchemist", "role": "cleric", "rank": "B", "type": "Verdant", "hp_ratio": 1.0, "dmg_ratio": 1.0, "kind": "escalate_pct", "flavor": "Brews faster than the Rift can wound."},
	# -- Cleric (content-pass additions — fills the role's missing hp_pct/
	# first_round_pct/boss_alpha_strike kinds and Ember/Frost types) --
	{"id": "emberblessed-acolyte", "name": "Cleric", "role": "cleric", "rank": "F", "type": "Ember", "hp_ratio": 1.0, "dmg_ratio": 0.8, "kind": "dmg_pct", "flavor": "Prays with a lit candle, not a cold one."},
	{"id": "frostward-sister", "name": "Cleric", "role": "cleric", "rank": "F", "type": "Frost", "hp_ratio": 1.1, "dmg_ratio": 0.7, "kind": "hp_pct", "flavor": "Keeps the chill out of everyone but herself."},
	{"id": "vanguard-chaplain", "name": "Cleric", "role": "cleric", "rank": "E", "type": "Ember", "hp_ratio": 1.0, "dmg_ratio": 0.9, "kind": "first_round_pct", "flavor": "Blesses the blade before it's needed."},
	{"id": "hearth-warden", "name": "Cleric", "role": "cleric", "rank": "E", "type": "Frost", "hp_ratio": 1.1, "dmg_ratio": 0.8, "kind": "hp_pct", "flavor": "A fire that doesn't go out in the cold."},
	{"id": "ember-confessor", "name": "Cleric", "role": "cleric", "rank": "D", "type": "Ember", "hp_ratio": 0.9, "dmg_ratio": 1.0, "kind": "dmg_pct", "flavor": "Absolves the Rift of its sins, briefly."},
	{"id": "frost-anchorite", "name": "Cleric", "role": "cleric", "rank": "C", "type": "Frost", "hp_ratio": 1.0, "dmg_ratio": 0.9, "kind": "mend_pct", "flavor": "Fasts, prays, and somehow still heals faster."},
	{"id": "radiant-vanguard", "name": "Radiant Vanguard", "role": "cleric", "rank": "B", "type": "Ember", "hp_ratio": 1.1, "dmg_ratio": 1.0, "kind": "first_round_pct", "flavor": "Leads with light, not caution."},
	{"id": "sainted-ember", "name": "Sainted Ember", "role": "cleric", "rank": "A", "type": "Ember", "hp_ratio": 1.1, "dmg_ratio": 1.0, "kind": "boss_alpha_strike", "flavor": "The Rift's worst still flinches from her first word."},
	{"id": "last-light-martyr", "name": "Last-Light Martyr", "role": "cleric", "rank": "S", "type": "Arcane", "hp_ratio": 1.2, "dmg_ratio": 0.9, "kind": "wipe_guard", "flavor": "The party has never seen the floor she stood between them and."},
	# -- Rogue (evasion & burst) --
	{"id": "scavenger", "name": "Rogue", "role": "rogue", "rank": "F", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "hazard_guard_pct", "flavor": "Knows which puddles not to step in."},
	{"id": "runaway", "name": "Rogue", "role": "rogue", "rank": "F", "type": "Umbral", "hp_ratio": 0.8, "dmg_ratio": 0.9, "kind": "dodge_pct", "flavor": "Has never once stood and fought fair."},
	{"id": "cutpurse", "name": "Rogue", "role": "rogue", "rank": "F", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 1.0, "kind": "dmg_pct", "flavor": "Leaves with more than they came with."},
	{"id": "skirmisher", "name": "Rogue", "role": "rogue", "rank": "E", "type": "Ember", "hp_ratio": 0.9, "dmg_ratio": 1.0, "kind": "dodge_pct", "flavor": "Never where the last swing landed."},
	{"id": "footpad", "name": "Rogue", "role": "rogue", "rank": "E", "type": "Frost", "hp_ratio": 0.8, "dmg_ratio": 1.0, "kind": "hazard_guard_pct", "flavor": "Nobody's ever heard them arrive."},
	{"id": "shadowfoot", "name": "Rogue", "role": "rogue", "rank": "D", "type": "Umbral", "hp_ratio": 0.8, "dmg_ratio": 1.1, "kind": "dodge_pct", "flavor": "The Rift barely notices it was there."},
	{"id": "fleetblade", "name": "Rogue", "role": "rogue", "rank": "D", "type": "Ember", "hp_ratio": 0.8, "dmg_ratio": 1.0, "kind": "escalate_pct", "flavor": "Gets faster the longer no one catches them."},
	{"id": "nightblade", "name": "Rogue", "role": "rogue", "rank": "C", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "dmg_pct", "flavor": "Strikes from the dark and returns to it."},
	{"id": "wraithstep", "name": "Rogue", "role": "rogue", "rank": "C", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "first_round_pct", "flavor": "Leaves two footprints and no explanation."},
	{"id": "duskrunner", "name": "Duskrunner", "role": "rogue", "rank": "B", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.2, "kind": "first_round_pct", "flavor": "Moves like the space between two heartbeats."},
	# -- Rogue (content-pass additions — fills the role's missing hp_pct/
	# mend_pct/wipe_guard/boss_alpha_strike kinds and Verdant/Arcane types) --
	{"id": "herbrunner", "name": "Rogue", "role": "rogue", "rank": "F", "type": "Verdant", "hp_ratio": 0.9, "dmg_ratio": 0.9, "kind": "mend_pct", "flavor": "Knows every plant the Rift hasn't poisoned yet."},
	{"id": "arcane-pilferer", "name": "Rogue", "role": "rogue", "rank": "F", "type": "Arcane", "hp_ratio": 0.8, "dmg_ratio": 1.0, "kind": "dmg_pct", "flavor": "Steals more than coin from a warded vault."},
	{"id": "ironhide-footpad", "name": "Rogue", "role": "rogue", "rank": "E", "type": "Verdant", "hp_ratio": 1.1, "dmg_ratio": 0.8, "kind": "hp_pct", "flavor": "Tougher than a rogue has any right to be."},
	{"id": "glyphhand", "name": "Rogue", "role": "rogue", "rank": "E", "type": "Arcane", "hp_ratio": 0.8, "dmg_ratio": 1.0, "kind": "dodge_pct", "flavor": "Reads a ward's seams like a lockpick reads a door."},
	{"id": "bramblefoot", "name": "Rogue", "role": "rogue", "rank": "D", "type": "Verdant", "hp_ratio": 1.0, "dmg_ratio": 0.9, "kind": "hp_pct", "flavor": "The undergrowth hides more than it seems to."},
	{"id": "rift-slipper", "name": "Rogue", "role": "rogue", "rank": "C", "type": "Arcane", "hp_ratio": 0.9, "dmg_ratio": 1.1, "kind": "wipe_guard", "flavor": "Steps half out of reality when it matters."},
	{"id": "wraithblade-adept", "name": "Wraithblade Adept", "role": "rogue", "rank": "B", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.2, "kind": "escalate_pct", "flavor": "Every strike thinner than the last, and faster."},
	{"id": "the-unseen-hand", "name": "The Unseen Hand", "role": "rogue", "rank": "A", "type": "Arcane", "hp_ratio": 0.9, "dmg_ratio": 1.3, "kind": "boss_alpha_strike", "flavor": "Already struck before the boss noticed it arrive."},
	{"id": "the-final-cut", "name": "The Final Cut", "role": "rogue", "rank": "S", "type": "Umbral", "hp_ratio": 0.9, "dmg_ratio": 1.2, "kind": "dodge_pct", "flavor": "Nothing has landed a hit since the Rift learned her name."},
]

# Every kind that can appear on a hero build (skills/items/relics/traits/innate).
const BUILD_KINDS := ["dmg_pct", "hp_pct", "speed_pct", "first_round_pct", "escalate_pct", "mend_pct", "hazard_guard_pct", "dodge_pct", "wipe_guard", "boss_alpha_strike"]

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

## One badge per Guild Tier, reusing existing assets/skills/ icons (no new
## generation) so the guild's growth reads as more than a text line — a
## visibly bigger/richer badge the more Guild Management levels are bought.
const GUILD_TIER_ICON := {
	"Founding Guild": "res://assets/skills/shield_basic.png",
	"Established Guild": "res://assets/skills/star.png",
	"Renowned Guild": "res://assets/skills/gem_blue_big.png",
	"Legendary Guild": "res://assets/skills/ingot_gold.png",
}

## One icon per Guild Management upgrade node, keyed "branch.node" — all
## reused from the existing assets/skills/ set (no new generation needed;
## every concept here already had a decent visual match sitting unused).
## Previously these nodes were a bare text line with no icon at all.
const MANAGEMENT_NODE_ICON := {
	"ops.roster": "res://assets/skills/shield_basic.png",
	"ops.medical": "res://assets/skills/heart.png",
	"ops.drill": "res://assets/skills/sword_slash.png",
	"ops.trait": "res://assets/skills/star.png",
	"infra.crystal": "res://assets/skills/gem_blue_big.png",
	"infra.stab": "res://assets/skills/shield_blue.png",
	"infra.seal": "res://assets/skills/trophy.png",
	"infra.energy": "res://assets/skills/gem_red.png",
	"log.broker": "res://assets/skills/ingot_gold.png",
	"log.scout": "res://assets/skills/eye_gem.png",
	"log.merchant": "res://assets/skills/gem_blue_a.png",
	"log.detector": "res://assets/skills/gem_cluster.png",
	"res.relic": "res://assets/skills/shard_blue.png",
	"res.theory": "res://assets/skills/potion_blue.png",
	"res.recycle": "res://assets/skills/shard_green.png",
	"res.cart": "res://assets/skills/ring.png",
	"res.vault": "res://assets/skills/shield_orange.png",
}

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
	"res://assets/battle/bg_swamp.png",
	"res://assets/battle/bg_tundra.png",
	"res://assets/battle/bg_skyfallen_ruins.png",
	"res://assets/battle/bg_abyssal_chasm.png",
	"res://assets/battle/bg_arcane_observatory.png",
]
const CURRENCY_ICON_PATH := {
	"coins": "res://assets/ui/icon_coins.png",
	"crystals": "res://assets/ui/icon_crystals.png",
	"tokens": "res://assets/ui/icon_tokens.png",
	"reputation": "res://assets/skills/trophy.png",
}
## Escort quests: a fragile NPC that occasionally tags along on a "combat"
## node (Combat.start_combat), which monster retaliation can hit instead of
## a hero. Purely flavor text — reused across every escort roll, no per-name
## mechanical difference.
const ESCORT_NAMES := ["Wounded Survivor", "Lost Scout", "Stranded Merchant", "Frightened Pilgrim"]
## Guild Board: a rotating pool of "contract" (small, quick) and "daily"
## (bigger target, bigger reward including Reputation) quests. `type` is
## looked up against GameState.quest_progress()'s match — kept here only as
## the id/label pairing so a new type is a one-line add in both places.
const QUEST_TYPE_LABEL := {
	"kill_monster": "Defeat %d %s",
	"seal_rift": "Seal %d Rift%s",
	"win_elite": "Win %d Elite fight%s",
	"win_boss": "Defeat a Boss",
	"craft": "Craft %d item%s or relic%s",
	"flawless_win": "Win %d fight%s without a hero going down",
}
## A static checklist, each auto-granted the moment its condition becomes
## true (GameState.check_milestones, called once per render) — distinct from
## Bestiary, which tracks encounters with no reward attached.
const MILESTONES := [
	{"id": "first_seal", "label": "First Blood — seal your first Rift", "type": "rifts_sealed", "target": 1, "reward": {"crystals": 10}},
	{"id": "monster_hunter", "label": "Monster Hunter — defeat 25 monsters total", "type": "total_kills", "target": 25, "reward": {"coins": 50, "reputation": 5}},
	{"id": "elite_slayer", "label": "Elite Slayer — win 3 Elite fights", "type": "elites_won", "target": 3, "reward": {"reputation": 3}},
	{"id": "boss_breaker", "label": "Boss Breaker — defeat 3 Bosses", "type": "bosses_won", "target": 3, "reward": {"reputation": 5}},
	{"id": "artisan", "label": "Artisan — craft 3 items or relics", "type": "crafts_performed", "target": 3, "reward": {"crystals": 30}},
	{"id": "full_roster", "label": "Full Roster — fill every hero slot", "type": "full_roster", "target": 1, "reward": {"reputation": 10}},
	{"id": "renowned", "label": "Renowned Guild — reach Renowned Guild tier", "type": "guild_tier_renowned", "target": 1, "reward": {"reputation": 15}},
	{"id": "greater_threat", "label": "Greater Threat — unlock the Greater Rift", "type": "greater_unlocked", "target": 1, "reward": {"crystals": 20}},
]
## One-shot SFX, all CC0 (Kenney.nl — Interface Sounds/RPG Audio/Impact
## Sounds packs, see assets/audio/sfx/KENNEY_LICENSE.txt). Every key here is
## safe to reference from any call site regardless of whether the file
## exists yet — AudioManager.play_sfx no-ops gracefully on a missing path,
## the same contract GameData.monster_anim_frames uses for its own gaps.
const SFX_PATH := {
	"ui_click": "res://assets/audio/sfx/ui_click.ogg",
	"ui_back": "res://assets/audio/sfx/ui_back.ogg",
	"ui_confirm": "res://assets/audio/sfx/ui_confirm.ogg",
	"ui_error": "res://assets/audio/sfx/ui_error.ogg",
	"coin": "res://assets/audio/sfx/coin.ogg",
	"attack": "res://assets/audio/sfx/attack.ogg",
	"hit": "res://assets/audio/sfx/hit.ogg",
	"hit_heavy": "res://assets/audio/sfx/hit_heavy.ogg",
	"knockout": "res://assets/audio/sfx/knockout.ogg",
	"victory": "res://assets/audio/sfx/victory.ogg",
	"craft": "res://assets/audio/sfx/craft.ogg",
}
## Looping background music — none of these exist yet (a future session
## generates them via Suno, per the plan doc), but every combat/camp screen
## call site can reference these keys now; AudioManager.play_music no-ops
## until a real file lands at the path.
const MUSIC_PATH := {
	"combat": "res://assets/audio/music/combat.ogg",
	"camp": "res://assets/audio/music/camp.ogg",
}
## The 4 new generic action icons Phase 14 needed on top of the existing
## assets/skills/ set (which already covered swords/shields/potions/gems/a
## star/a trophy/a heart/boots/rings/armor — enough for most button actions
## without new art at all).
const BUTTON_ICON_PATH := {
	"confirm": "res://assets/skills/icon_confirm.png",
	"back": "res://assets/skills/icon_back.png",
	"dice": "res://assets/skills/icon_dice.png",
	"sort": "res://assets/skills/icon_sort.png",
}
const CREST_PATH: Array[String] = [
	"res://assets/camp/crest_1.png", "res://assets/camp/crest_2.png",
	"res://assets/camp/crest_3.png", "res://assets/camp/crest_4.png",
	"res://assets/camp/crest_5.png", "res://assets/camp/crest_6.png",
	"res://assets/camp/crest_7.png", "res://assets/camp/crest_8.png",
]
const CAMP_BG := "res://assets/camp/camp_bg.png"
const TITLE_BG := "res://assets/screens/title_bg.png"
const MEDICAL_BG := "res://assets/screens/medical_bg.png"
const ROSTER_BG := "res://assets/screens/roster_bg.png"
const MANAGEMENT_BG := "res://assets/screens/management_bg.png"
const BED_ICON := "res://assets/screens/bed_icon.png"
const RIFTHALL_BG := "res://assets/screens/rifthall_bg.png"
const RIFTMAP_BG := "res://assets/screens/riftmap_bg.png"
const INVENTORY_BG := "res://assets/screens/inventory_bg.png"
const CRAFTING_BG := "res://assets/screens/crafting_bg.png"
const SHOP_BG := "res://assets/screens/shop_bg.png"
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
	"rift_map": "res://assets/camp/icon_rift_map.png",
	"bestiary": "res://assets/camp/icon_bestiary.png",
	"crafting": "res://assets/camp/icon_crafting.png",
	"settings": "res://assets/skills/gear.png",
	"compendium": "res://assets/camp/icon_compendium.png",
	"quests": "res://assets/camp/icon_quests.png",
}
## Window sizes offered by the Settings screen — Godot's existing
## stretch/mode="canvas_items" + aspect="expand" (project.godot) already
## scales the UI to whatever size the window ends up, so switching entries
## here is just get_window().size = Vector2i(w, h), no stretch-system change.
const RESOLUTION_OPTIONS := [
	{"label": "1280×800 (Default)", "w": 1280, "h": 800},
	{"label": "1200×800", "w": 1200, "h": 800},
	{"label": "1600×900", "w": 1600, "h": 900},
	{"label": "1920×1080", "w": 1920, "h": 1080},
]
## Ornate slot-frame borders, one per rarity tier — reused everywhere a
## rarity needs to read at a glance: equip slots on the paper-doll Roster
## screen and the battle screen's action-bar slots (which always use the
## "common" frame, since actions aren't items). AI-generated (PixelLab),
## same pipeline as every other UI asset this project uses.
const RARITY_FRAME_PATH := {
	"common": "res://assets/ui/frame_common.png",
	"rare": "res://assets/ui/frame_rare.png",
	"epic": "res://assets/ui/frame_epic.png",
	"legendary": "res://assets/ui/frame_legendary.png",
}
const SKILL_NODE_FRAME_PATH := "res://assets/ui/skill_node_hex.png"
const STATUS_PLATE_PATH := "res://assets/ui/status_plate.png"
const PORTRAIT_FRAME_PATH := "res://assets/ui/portrait_frame.png"
const ABILITY_BAR_STRIP_PATH := "res://assets/ui/ability_bar_strip.png"
const HERO_DETAIL_BG := "res://assets/screens/hero_detail_bg.png"

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
	"rift-eclipsed-warden": "res://assets/heroes/subclass/rift-eclipsed-warden.png",
	"last-light-martyr": "res://assets/heroes/subclass/last-light-martyr.png",
	"the-final-cut": "res://assets/heroes/subclass/the-final-cut.png",
	# The 40 "content-pass" subclasses (added in an earlier session) never got
	# portrait art at all — PixelLab-generated, matching the hand-picked set's
	# proportions/style, to close that gap the same way the 3 new S-ranks were.
	"fieldmender": "res://assets/heroes/subclass/fieldmender.png",
	"featherguard": "res://assets/heroes/subclass/featherguard.png",
	"trailblazer": "res://assets/heroes/subclass/trailblazer.png",
	"frostguard": "res://assets/heroes/subclass/frostguard.png",
	"warbrand": "res://assets/heroes/subclass/warbrand.png",
	"aegis-bearer": "res://assets/heroes/subclass/aegis-bearer.png",
	"stormguard": "res://assets/heroes/subclass/stormguard.png",
	"rift-breaker": "res://assets/heroes/subclass/rift-breaker.png",
	"shadowtracker": "res://assets/heroes/subclass/shadowtracker.png",
	"fieldscout": "res://assets/heroes/subclass/fieldscout.png",
	"nightwarden": "res://assets/heroes/subclass/nightwarden.png",
	"sapling-keeper": "res://assets/heroes/subclass/sapling-keeper.png",
	"duskstalker": "res://assets/heroes/subclass/duskstalker.png",
	"gale-marksman": "res://assets/heroes/subclass/gale-marksman.png",
	"rift-piercer": "res://assets/heroes/subclass/rift-piercer.png",
	"wintertide-archer": "res://assets/heroes/subclass/wintertide-archer.png",
	"thornweaver": "res://assets/heroes/subclass/thornweaver.png",
	"shade-adept": "res://assets/heroes/subclass/shade-adept.png",
	"stoneward-mystic": "res://assets/heroes/subclass/stoneward-mystic.png",
	"grim-conjurer": "res://assets/heroes/subclass/grim-conjurer.png",
	"verdant-oracle": "res://assets/heroes/subclass/verdant-oracle.png",
	"duskglass-seer": "res://assets/heroes/subclass/duskglass-seer.png",
	"ashbound-theorist": "res://assets/heroes/subclass/ashbound-theorist.png",
	"rift-warden-magus": "res://assets/heroes/subclass/rift-warden-magus.png",
	"emberblessed-acolyte": "res://assets/heroes/subclass/emberblessed-acolyte.png",
	"frostward-sister": "res://assets/heroes/subclass/frostward-sister.png",
	"vanguard-chaplain": "res://assets/heroes/subclass/vanguard-chaplain.png",
	"hearth-warden": "res://assets/heroes/subclass/hearth-warden.png",
	"ember-confessor": "res://assets/heroes/subclass/ember-confessor.png",
	"frost-anchorite": "res://assets/heroes/subclass/frost-anchorite.png",
	"radiant-vanguard": "res://assets/heroes/subclass/radiant-vanguard.png",
	"sainted-ember": "res://assets/heroes/subclass/sainted-ember.png",
	"herbrunner": "res://assets/heroes/subclass/herbrunner.png",
	"arcane-pilferer": "res://assets/heroes/subclass/arcane-pilferer.png",
	"ironhide-footpad": "res://assets/heroes/subclass/ironhide-footpad.png",
	"glyphhand": "res://assets/heroes/subclass/glyphhand.png",
	"bramblefoot": "res://assets/heroes/subclass/bramblefoot.png",
	"rift-slipper": "res://assets/heroes/subclass/rift-slipper.png",
	"wraithblade-adept": "res://assets/heroes/subclass/wraithblade-adept.png",
	"the-unseen-hand": "res://assets/heroes/subclass/the-unseen-hand.png",
}
## AI-generated combat animation frames (5 each: frame 0 is the static portrait,
## 1-4 are the motion). Only combos that actually produced usable motion exist —
## Warrior/hurt and Ranger/attack never did after 3 rounds of prompt iteration,
## and Ranger/skill didn't either on the first attempt despite using the
## limb-specific wording that lesson taught — so those three intentionally
## have no frames; callers fall back to tweening the static portrait instead
## of frame-swapping when this returns [].
const HERO_ANIM_COMBOS := {
	"warrior": ["attack", "skill"],
	"ranger": ["hurt"],
	"mage": ["attack", "hurt", "skill"],
	"cleric": ["attack", "hurt", "skill"],
	"rogue": ["attack", "hurt", "skill"],
}


static func hero_anim_frames(role: String, action: String) -> Array[String]:
	var frames: Array[String] = []
	if not HERO_ANIM_COMBOS.get(role, []).has(action):
		return frames
	for i in 5:
		frames.append("res://assets/heroes/anim/%s_%s_%d.png" % [role, action, i])
	return frames


## Subclass-specific combat frames (same 5-frame shape as hero_anim_frames,
## generated the same way — frame 0 duplicates the static portrait). Checked
## via ResourceLoader.exists rather than a static combo table since these were
## generated per-subclass after the fact and coverage varies by role (see
## hero_combat_frames).
static func subclass_anim_frames(pool_id: String, action: String) -> Array[String]:
	var frames: Array[String] = []
	for i in 5:
		frames.append("res://assets/heroes/subclass_anim/%s_%s_%d.png" % [pool_id, action, i])
	if not ResourceLoader.exists(frames[1]):
		return []
	return frames


## The single entry point _play_round should use to decide what to
## frame-animate. A hero with a subclass-specific portrait (SUBCLASS_PORTRAIT_
## PATH) must never play the generic role's frames — those are a different-
## looking character and that mismatch is exactly what caused heroes to
## visibly "change look" mid-hit. So subclassed heroes only ever get their own
## subclass_anim_frames (or no frames at all, falling back to a tween on their
## correct portrait); only Champions and other non-subclassed heroes fall back
## to the generic role animation, since portrait_for_hero shows them that same
## generic art at rest.
static func hero_combat_frames(cls_id: String, pool_id: String, action: String) -> Array[String]:
	if SUBCLASS_PORTRAIT_PATH.has(pool_id):
		return subclass_anim_frames(pool_id, action)
	return hero_anim_frames(cls_id, action)
const MONSTER_SPRITE_PATH := {
	"ember_whelp": "res://assets/monsters/ember_whelp.png",
	"sable_fang": "res://assets/monsters/sable_fang.png",
	"marrow_crawler": "res://assets/monsters/marrow_crawler.png",
	"hollow_reaver": "res://assets/monsters/hollow_reaver.png",
	"husk_brute": "res://assets/monsters/husk_brute.png",
	"cinder_moth": "res://assets/monsters/cinder_moth.png",
	"gloom_stalker": "res://assets/monsters/gloom_stalker.png",
	"rift_wisp": "res://assets/monsters/rift_wisp.png",
	# Content pass: 8 new regular monsters, plus dedicated art for every
	# elite/boss name that previously fell through to a hash-picked sprite
	# from the pool above (a boss used to be able to look identical to a
	# common goblin).
	"bog_wretch": "res://assets/monsters/bog_wretch.png",
	"silt_crawler": "res://assets/monsters/silt_crawler.png",
	"glass_wisp": "res://assets/monsters/glass_wisp.png",
	"mirror_fiend": "res://assets/monsters/mirror_fiend.png",
	"frost_stalker": "res://assets/monsters/frost_stalker.png",
	"ashclad_ghoul": "res://assets/monsters/ashclad_ghoul.png",
	"deep_anchorite": "res://assets/monsters/deep_anchorite.png",
	"voidling_sprite": "res://assets/monsters/voidling_sprite.png",
	"warbound_elite": "res://assets/monsters/warbound_elite.png",
	"blightfang_elite": "res://assets/monsters/blightfang_elite.png",
	"rift_touched_colossus": "res://assets/monsters/rift_touched_colossus.png",
	"iron_revenant": "res://assets/monsters/iron_revenant.png",
	"storm_called_elite": "res://assets/monsters/storm_called_elite.png",
	"ashen_broodlord": "res://assets/monsters/ashen_broodlord.png",
	"vaelith": "res://assets/monsters/vaelith.png",
	"korrath": "res://assets/monsters/korrath.png",
	"nyxara": "res://assets/monsters/nyxara.png",
	"drevok": "res://assets/monsters/drevok.png",
	"sythrane": "res://assets/monsters/sythrane.png",
}
const MONSTER_NAME_SPRITE := {
	"Gloom Stalker": "gloom_stalker", "Rift Wisp": "rift_wisp", "Husk Brute": "husk_brute",
	"Sable Fang": "sable_fang", "Ember Whelp": "ember_whelp", "Marrow Crawler": "marrow_crawler",
	"Hollow Reaver": "hollow_reaver", "Cinder Moth": "cinder_moth",
	"Bog Wretch": "bog_wretch", "Silt Crawler": "silt_crawler",
	"Glass Wisp": "glass_wisp", "Mirror Fiend": "mirror_fiend",
	"Frost Stalker": "frost_stalker", "Ashclad Ghoul": "ashclad_ghoul",
	"Deep Anchorite": "deep_anchorite", "Voidling Sprite": "voidling_sprite",
	"Warbound Elite": "warbound_elite", "Blightfang Elite": "blightfang_elite",
	"Rift-Touched Colossus": "rift_touched_colossus", "Iron Revenant": "iron_revenant",
	"Storm-Called Elite": "storm_called_elite", "Ashen Broodlord": "ashen_broodlord",
	"Vaelith": "vaelith", "Korrath": "korrath", "Nyxara": "nyxara",
	"Drevok": "drevok", "Sythrane": "sythrane",
}


## Any monster name resolves to a sprite key: a name match first (bosses by
## the part before the comma), else a stable hash-based pick so an unknown
## name still gets a deterministic sprite.
static func monster_sprite_key(monster_name: String) -> String:
	# Bosses are named "Korrath, Lesser Warden" — their art is keyed by the
	# name before the comma.
	var base_name := monster_name.split(",")[0]
	if MONSTER_NAME_SPRITE.has(base_name):
		return MONSTER_NAME_SPRITE[base_name]
	var keys: Array = MONSTER_SPRITE_PATH.keys()
	var hash_sum := 0
	for c in monster_name:
		hash_sum += c.unicode_at(0)
	return keys[hash_sum % keys.size()]


static func sprite_for_monster(monster_name: String) -> String:
	return MONSTER_SPRITE_PATH[monster_sprite_key(monster_name)]


## Combat animation frames for a monster (5 each, same shape as
## hero_anim_frames). Every monster's base sprite and frames share one crop
## box, so swapping frames never shifts the sprite. A monster with no frames
## falls back to a tween, the same contract hero_anim_frames has.
static func monster_anim_frames(monster_name: String, action: String) -> Array[String]:
	var key := monster_sprite_key(monster_name)
	var frames: Array[String] = []
	for i in 5:
		frames.append("res://assets/monsters/anim/%s_%s_%d.png" % [key, action, i])
	if not ResourceLoader.exists(frames[0]):
		return []
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


## Looks up a bare node id within a specific kind's package (or a Tier-1
## root, for "edge"/"hide" — `kind` is ignored then, since those are shared
## across every tree). `role` picks which role's Tier-1 flavor to resolve
## against; callers that don't have a hero in scope (pure SP-cost math) can
## omit it since cost/req_level/tier are identical across every role's variant.
static func find_skill_node(kind: String, skill_id: String, role: String = "warrior") -> Dictionary:
	if skill_id == "edge" or skill_id == "hide":
		for n in tier1_for_role(role):
			if n["id"] == skill_id:
				return n
		return {}
	if skill_id == "signature":
		return signature_node(role)
	if skill_id == "keystone":
		return keystone_node(kind)
	for n in KIND_SKILL_PACKAGE.get(kind, []):
		if n["id"] == skill_id:
			return n
	return {}


static func weapon_slots(pool_id: String) -> int:
	return 2 if DUAL_WIELD_CLASSES.has(pool_id) else 1


static func gear_slots(rank_id: String) -> int:
	return 1 + int(floor(rank_index(rank_id) / 2.0))
