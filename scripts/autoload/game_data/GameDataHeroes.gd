extends "res://scripts/autoload/game_data/GameDataArt.gd"
## GameData, part 2: heroes — classes and the class pool, ranks, rarities, traits, scars, bonds, relic types, synergies, narrative lines, item bases, keywords, archetypes, passives, attributes, supplies.
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
## ---------------- Quirks ----------------
## Everything personal about a hero beyond class, skills and gear, in one list
## (Hero.quirks, by name):
## - "born": rolled at recruitment (at most one; sets their voice),
## - "scar": left by being knocked out (up to 2; a net wound with an upside),
## - "earned": unlocked by what they've done (Hero.history `stat` >= `need`).
## `stats` {kind: value} add to the hero like skills and gear; `effects` are
## Combat.hero_effects entries. `treatable` quirks can be treated for Gold at
## the Arcane Lab.
const QUIRKS := {
	"Battle-Hardened": {"origin": "born", "stats": {"dmg_pct": 0.1}, "voice": "bold"},
	"Swift": {"origin": "born", "stats": {"dmg_pct": 0.05, "speed_pct": 0.12}, "voice": "swift"},
	"Iron Skin": {"origin": "born", "stats": {"hp_pct": 0.15}, "voice": "stoic"},
	"Frail": {"origin": "born", "treatable": true, "stats": {"hp_pct": -0.15}, "voice": "wary"},
	"Reckless": {"origin": "born", "treatable": true, "stats": {"dmg_pct": -0.05, "hp_pct": -0.05}, "voice": "bold"},
	"Slothful": {"origin": "born", "treatable": true, "stats": {"dmg_pct": -0.1, "speed_pct": -0.12}, "voice": "wary"},
	# Double-edged, one per role.
	"Juggernaut": {"origin": "born", "role": "warrior", "treatable": true, "stats": {"hazard_guard_pct": 0.10, "dodge_pct": -0.08}, "voice": "bold"},
	"Deadeye": {"origin": "born", "role": "ranger", "treatable": true, "stats": {"first_round_pct": 0.15, "hp_pct": -0.08}, "voice": "swift"},
	"Overtuned": {"origin": "born", "role": "mage", "treatable": true, "stats": {"escalate_pct": 0.03, "hp_pct": -0.10}, "voice": "arcane"},
	"Zealous Mercy": {"origin": "born", "role": "cleric", "treatable": true, "stats": {"mend_pct": 0.04, "dmg_pct": -0.06}, "voice": "devout"},
	"Glass Dagger": {"origin": "born", "role": "rogue", "treatable": true, "stats": {"dodge_pct": 0.10, "hazard_guard_pct": -0.08}, "voice": "swift"},
	# Scars: a wound, and what it changes about how they fight.
	"Shell-Shocked": {"origin": "scar", "treatable": true, "stats": {"dodge_pct": -0.08}, "effects": [{"kind": "dmg_pct", "value": 0.15, "cond": {"ally_below": 0.5}}]},
	"Trembling Hands": {"origin": "scar", "treatable": true, "stats": {"dmg_pct": -0.06}, "effects": [{"trigger": "evade_or_heavy", "effect": "counter_attack", "value": 0.15}]},
	"Battle Fatigue": {"origin": "scar", "treatable": true, "stats": {"hp_pct": -0.08}, "effects": [{"kind": "dmg_pct", "value": 0.12, "cond": {"round_min": 4}}]},
	"Haunted": {"origin": "scar", "treatable": true, "stats": {"mend_pct": -0.03}, "effects": [{"kind": "dmg_pct", "value": 0.15, "cond": {"hp_below": 0.5}}]},
	"Flinching": {"origin": "scar", "treatable": true, "stats": {"first_round_pct": -0.10}, "effects": [{"kind": "dodge_pct", "value": 0.15, "cond": {"hp_below": 0.4}}]},
	# Earned through play.
	"Bosskiller": {"origin": "earned", "id": "bosskiller", "stat": "boss_kills", "need": 3, "arch": "executioner",
		"effects": [{"kind": "dmg_pct", "value": 0.15, "cond": {"vs_boss": true}}]},
	"Elite Hunter": {"origin": "earned", "id": "elite_hunter", "stat": "elite_kills", "need": 5, "arch": "opener", "stats": {"first_round_pct": 0.10}},
	"Reaper": {"origin": "earned", "id": "reaper", "stat": "kills", "need": 40, "arch": "executioner",
		"effects": [{"kind": "dmg_pct", "value": 0.12, "cond": {"target_below": 0.3}}]},
	"Seasoned": {"origin": "earned", "id": "seasoned", "stat": "kills", "need": 100, "arch": "executioner", "stats": {"dmg_pct": 0.06}},
	"Survivor": {"origin": "earned", "id": "survivor", "stat": "knockouts", "need": 3, "arch": "evasion",
		"effects": [{"kind": "dodge_pct", "value": 0.20, "cond": {"hp_below": 0.3}}]},
	"Veteran": {"origin": "earned", "id": "veteran", "stat": "rifts_cleared", "need": 5, "arch": "guardian", "stats": {"hp_pct": 0.08}},
	"Old Guard": {"origin": "earned", "id": "old_guard", "stat": "rifts_cleared", "need": 15, "arch": "guardian", "stats": {"wipe_guard": 0.05}},
}
const SCARS_MAX := 2
const QUIRK_TREAT_COST := 30
const HISTORY_LABEL := {"kills": "kills", "boss_kills": "bosses", "elite_kills": "elites", "rifts_cleared": "rifts", "knockouts": "knockouts"}


static func quirk(name: String) -> Dictionary:
	return QUIRKS.get(name, {})


## The names of every quirk from `origin` ("born"/"scar"/"earned").
static func quirks_from(origin: String) -> Array:
	return QUIRKS.keys().filter(func(q): return QUIRKS[q]["origin"] == origin)


## How the hero talks (VOICE lines): their born quirk's voice, else stoic.
static func hero_voice(h: Hero) -> String:
	for q in h.quirks:
		if QUIRKS.get(q, {}).has("voice"):
			return str(QUIRKS[q]["voice"])
	return "stoic"


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
	{"kind": "momentum_pct", "value": 0.25, "domain": "chance", "label": "+25% chance to gain 1 Momentum when evading or hit hard"},
	{"kind": "kill_shield_pct", "value": 0.2, "domain": "defense", "label": "On a kill, shields the lowest-HP ally for 20% of their max HP"},
]

## Relic names: "<Type> <Noun> <suffix>", the suffix from its first special.
const RELIC_SPECIAL_SUFFIX := {
	"mend_pct": "of Renewal", "dodge_pct": "of the Wind", "escalate_pct": "of the Pyre", "hazard_guard_pct": "of Warding",
	"first_round_pct": "of First Light", "wipe_guard": "of the Last Stand", "boss_alpha_strike": "of the Warhorn",
	"loot_rarity_pct": "of Fortune", "counter_pct": "of Thorns", "momentum_pct": "of Haste", "kill_shield_pct": "of the Bulwark",
}

## Relic triggers (rare+): effects in Combat's hero-effect shape that fire in
## battle for the whole party. `value` is the common-rarity base, scaled by
## rarity mult. round_third fires at the start of every 3rd round; ally_down
## when a hero is knocked out.
const RELIC_TRIGGERS := [
	{"trigger": "on_kill", "effect": "mend_party", "value": 0.04},
	{"trigger": "after_hit", "effect": "lifesteal", "value": 0.06},
	{"trigger": "before_hit", "effect": "execute_below", "value": 0.08},
	{"trigger": "evade_or_heavy", "effect": "weaken_attacker", "value": 0.08},
	{"trigger": "ally_targeted", "effect": "intercept", "value": 0.15},
	{"trigger": "on_kill", "effect": "shield_lowest", "value": 0.10},
	{"trigger": "round_third", "effect": "nova", "value": 0.25},
	{"trigger": "round_third", "effect": "shield_party", "value": 0.08},
	{"trigger": "ally_down", "effect": "shield_party", "value": 0.15},
	{"trigger": "ally_down", "effect": "mend_party", "value": 0.10},
]

const RELIC_REROLL_CRYSTALS := 10
const TYPE_DOMAIN := {
	"Ember": "damage", "Verdant": "heal", "Frost": "chance",
	"Umbral": "defense", "Arcane": "droprate",
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
	"guild_founded": {
		"openers": ["A name, a crest, and nothing else yet.", "Every guild starts as an empty ledger.", "The banner goes up before anyone's earned it.", "No history yet. Just intent."],
		"closers": ["That's how it always starts.", "The Rift doesn't care how you began, only how you end.", "Everything after this gets written the hard way.", "Whatever comes next, it starts here."],
	},
	"scar_gained": {
		"openers": ["The rift left its mark.", "Some wounds don't close all the way.", "Not every scar shows on the skin.", "The fight is over. The fear isn't."],
		"closers": ["Quiet about how it happened.", "A price paid for coming back at all.", "The rift takes more than HP sometimes.", "Not every cost gets fully repaid."],
	},
	"greater_rift_unlocked": {
		"openers": ["The Rift Hall's third gate finally answers.", "Three rifts sealed, and the chains on the old gateway snap loose.", "The rubble in the doorway stops mattering.", "Something the guild wasn't ready for, until now it is."],
		"closers": ["It was always waiting.", "Whatever's behind it, the guild has earned the right to find out.", "Not every gate opens with a key. Some just need proof.", "The easy floors are behind you now."],
	},
	"guild_tier_reached": {
		"openers": ["Word spreads.", "Other guilds have started asking who you are.", "The name on the banner starts to mean something.", "Renown is its own kind of currency."],
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
## The stats a generated item rolls, two per category: weapons hit, armor
## holds, focus items keep the party going. (Older items may carry first-strike,
## escalating or wipe-guard stats; those are effects now, see ITEM_EFFECTS.)
const ITEM_CATEGORY_KINDS := {
	"weapon": ["dmg_pct", "speed_pct"],
	"armor": ["hp_pct", "hazard_guard_pct"],
	"focus": ["mend_pct", "dodge_pct"],
}
const ITEM_NOUNS := {
	"weapon": ["Blade", "Bow", "Staff", "Mace", "Dagger", "Axe", "Spear", "Wand"],
	"armor": ["Plate", "Guard", "Bracer", "Greaves", "Mail", "Robe", "Helm"],
	"focus": ["Ring", "Amulet", "Charm", "Band", "Talisman", "Tome", "Orb"],
}
## A Rank-F Common's value per stat. The six rolled kinds carry what the old
## base-type stat added on top; the rest are only for older items (reforging).
const ITEM_KIND_BASE := {
	"dmg_pct": 0.16, "hp_pct": 0.17, "first_round_pct": 0.15, "escalate_pct": 0.04,
	"mend_pct": 0.075, "hazard_guard_pct": 0.16, "dodge_pct": 0.12, "speed_pct": 0.14,
}

## How many distinct stats a generated (non-Legendary) item rolls — the actual
## "build-around" lever: a Common is a single clean number, an Epic is a real
## multi-stat piece worth building toward, same shape as a hero's rank ladder.
const ITEM_AFFIX_COUNT_BY_RARITY := {"common": 1, "rare": 1, "epic": 2}   # stats; Rare and Epic also roll an ITEM_EFFECTS effect

## Each slot past the first rolls at a reduced share of ITEM_KIND_BASE so the
## primary stat stays the item's clear identity instead of 3 equally-loud
## numbers — 100% / 55% / 35% for primary/secondary/tertiary.
const ITEM_AFFIX_VALUE_SHARE := [1.0, 0.5, 0.35]

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
static var _keyword_locale := ""

## [title, definition, RegEx] for every KEYWORDS entry (compiled once per
## language). A translated pattern (tr.po) matches alongside the English one;
## (*UCP) makes word boundaries treat Turkish letters (ş, ı, ç) as letters.
static func keyword_regexes() -> Array:
	var loc := TranslationServer.get_locale()
	if _keyword_res.is_empty() or loc != _keyword_locale:
		_keyword_locale = loc
		_keyword_res = []
		for k in KEYWORDS:
			var pat := str(k[0])
			var local := String(TranslationServer.translate(pat))
			if local != pat:
				pat += "|" + local
			var re := RegEx.new()
			re.compile("(*UCP)(?i)\\b(" + pat + ")\\b")
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
	"Axe": {"kind": "dmg_pct", "value": 0.05},
	"Spear": {"kind": "first_round_pct", "value": 0.08},
	"Wand": {"kind": "mend_pct", "value": 0.02},
	"Robe": {"kind": "mend_pct", "value": 0.02},
	"Helm": {"kind": "hp_pct", "value": 0.06},
	"Tome": {"kind": "escalate_pct", "value": 0.015},
	"Orb": {"kind": "dodge_pct", "value": 0.04},
}


## Every base type and Legendary has its own icon (assets/items/).
static func item_base(it) -> String:
	if it.unique_id != "":
		return ""
	for word in str(it.name).split(" "):
		if ITEM_BASE_IMPLICIT.has(word):
			return word
	return ""


static func item_icon(it) -> String:
	var path := "res://assets/items/%s.png" % (("u_" + str(it.unique_id)) if it.unique_id != "" else item_base(it).to_lower())
	return path if ResourceLoader.exists(path) else ITEM_CATEGORY_ICON_PATH.get(str(it.category), ITEM_CATEGORY_ICON_PATH["weapon"])

# ---------------- Attributes ----------------
## Three hero attributes. Every point above the baseline adds the stats
## below (a point under it costs them); heroes start with a role spread and
## get ATTR_POINTS_PER_LEVEL to spend at each level-up, on top of a smaller
## automatic growth (LEVEL_GROWTH). Items roll a bonus to their base type's
## attribute and, from Rare up, need some of it to equip.
const ATTRIBUTES := ["might", "agility", "focus"]
const ATTR_LABEL := {"might": "Might", "agility": "Agility", "focus": "Focus"}
const ATTR_BASELINE := 5
const ATTR_POINTS_PER_LEVEL := 3
const LEVEL_GROWTH := 0.05   # base HP and damage per level (was 8% with no attributes)
const ATTR_EFFECTS := {
	"might": {"dmg_pct": 0.02, "hp_pct": 0.015},
	"agility": {"speed_pct": 0.02, "dodge_pct": 0.015, "first_round_pct": 0.02},   # dodge was 0.8%: agility trailed might and focus (campaign_sim -- attr=)
	"focus": {"ability_power": 0.04, "mend_pct": 0.002},
}
const ATTR_DESC := {
	"might": "+2% damage and +1.5% HP per point above 5",
	"agility": "+2% speed, +1.5% dodge and +2% first-strike per point above 5",
	"focus": "+4% ability power and +0.2% mend per point above 5",
}

## Starting attributes per role [might, agility, focus] and how an automatic
## level-up spends its points (recruits, the Champion and old saves).
const ROLE_ATTRS := {
	"warrior": [8, 5, 3], "rogue": [5, 8, 3], "ranger": [4, 8, 4],
	"mage": [3, 4, 9], "cleric": [4, 3, 9],
}
const ROLE_ATTR_SPREAD := {
	"warrior": ["might", "might", "agility"], "rogue": ["agility", "agility", "might"],
	"ranger": ["agility", "agility", "focus"], "mage": ["focus", "focus", "agility"],
	"cleric": ["focus", "focus", "might"],
}
const ITEM_BASE_ATTR := {
	"Blade": "might", "Mace": "might", "Axe": "might", "Plate": "might", "Mail": "might", "Helm": "might", "Guard": "might",
	"Bow": "agility", "Dagger": "agility", "Spear": "agility", "Bracer": "agility", "Greaves": "agility", "Band": "agility", "Charm": "agility",
	"Staff": "focus", "Wand": "focus", "Robe": "focus", "Ring": "focus", "Amulet": "focus", "Talisman": "focus", "Tome": "focus", "Orb": "focus",
}
const UNIQUE_ARCH_ATTR := {"executioner": "might", "attrition": "might", "guardian": "might", "opener": "agility", "evasion": "agility", "sustain": "focus"}
const ITEM_ATTR_BONUS := {"common": 1, "rare": 2, "epic": 3, "legendary": 4}
const ITEM_ATTR_REQ := {"common": 0, "rare": 7, "epic": 10, "legendary": 13}

## Resetting a hero's attributes costs this many Crystals per hero level.
const RESPEC_CRYSTALS_PER_LEVEL := 10

## Field Tonic: a battle consumable (Inventory → Supplies). Using one takes the
## hero's turn and heals one ally.
## Tonics: the one consumable line. Bought at Supplies, carried on a belt of
## TONIC_CAP, and used in a fight on a hero's turn.
const TONIC_CAP := 5
const TONIC_HEAL_PCT := 0.35
const TONIC_WARD_PCT := 0.3
const TONIC_FOCUS := 3
const TONIC_TYPES := [
	{"id": "healing", "name": "Healing Tonic", "cost": 25, "target": "ally", "icon": "res://assets/ui/icon_tonic.png",
		"desc": "Heals an ally 35% of max HP and cleanses burn, poison, chill, stun and curses."},
	{"id": "iron", "name": "Iron Tonic", "cost": 30, "target": "ally", "icon": "res://assets/skills/shield_blue.png",
		"desc": "Wards an ally for 30% of their max HP."},
	{"id": "focus", "name": "Focus Tonic", "cost": 35, "target": "none", "icon": "res://assets/skills/gem_blue_big.png",
		"desc": "+3 Momentum for the party."},
]


static func find_tonic(id: String) -> Dictionary:
	for t in TONIC_TYPES:
		if t["id"] == id:
			return t
	return {}

## Downed mid-rift (after a regular/elite fight or a hazard) the player picks:
## carry them out (+1 day), send idle heroes to fetch them (busy 1-2 runs),
## heal them back up (once per rift), or leave them in the rift — rescued if
## the rift is sealed, lost for good if the run ends any other way.
const INJURY_REINFORCEMENTS := {"wounded": 1, "critical": 2}
const INJURY_BUSY_RUNS := {"wounded": 1, "critical": 2}
const FIELD_HEAL_HP_PCT := 0.30
const BATTERED_HP_PCT := 0.15
const FIELD_HEALER_MIN_RANK := "B"

## Item upkeep: rerolling one stat line costs REFORGE_CRYSTALS x rarity mult,
## more each time; salvage returns SALVAGE_CRYSTALS x rarity mult.
const REFORGE_CRYSTALS := 8
const SALVAGE_CRYSTALS := 6

## Attunement: gear grows with its hero — every ATTUNE_WINS won fights while
## equipped raise its rolled stats by ATTUNE_STEP, up to ATTUNE_MAX times.
const ATTUNE_WINS := 8
const ATTUNE_STEP := 0.04
const ATTUNE_MAX := 5

## Camp training: buy up to ATTR_TRAIN_CAP extra attribute points per hero,
## each costing ATTR_TRAIN_COST more Coins than the last.
const ATTR_TRAIN_CAP := 8
const ATTR_TRAIN_COST := 50


static func role_attrs(role: String) -> Dictionary:
	var v: Array = ROLE_ATTRS.get(role, [ATTR_BASELINE, ATTR_BASELINE, ATTR_BASELINE])
	return {"might": int(v[0]), "agility": int(v[1]), "focus": int(v[2])}

## Item rank = the rank of the rift it dropped in (GameState.loot_rank), and
## scales every rolled number on it — so higher-rank rifts are worth the risk
## and early gear eventually gets replaced. Indexed like RIFT_RANKS (F..SSS).
const ITEM_RANK_MULT := [1.0, 1.04, 1.08, 1.12, 1.16, 1.22, 1.28, 1.35, 1.42]

## Each rolled affix lands somewhere in this band of its base value.
const ITEM_ROLL_RANGE := [0.8, 1.2]

## A Rare or Epic item's defining effect, by category: a named Combat.
## hero_effects entry (a conditional stat, or a trigger and what it does),
## whose `suffix` names the item ("Brutal Blade of the Ambush"). Values are a
## Rare's; an Epic's are ITEM_EFFECT_EPIC_MULT stronger. `epic` ones only
## roll on Epics. `arch` is the build archetype it counts toward.
const ITEM_EFFECTS := {
	"weapon": [
		{"id": "ambush", "name": "Ambush", "suffix": "of the Ambush", "arch": "opener", "kind": "dmg_pct", "value": 0.35, "cond": {"round_max": 1}},
		{"id": "executioner", "name": "Executioner", "suffix": "of the Headsman", "arch": "executioner", "trigger": "after_hit", "effect": "execute_below", "value": 0.12},
		{"id": "bloodthirst", "name": "Bloodthirst", "suffix": "of Thirst", "arch": "sustain", "trigger": "after_hit", "effect": "lifesteal", "value": 0.15},
		{"id": "surge", "name": "Surge", "suffix": "of the Surge", "arch": "opener", "trigger": "on_kill", "effect": "gain_momentum", "value": 0.8},
		{"id": "thunder", "name": "Thunderclap", "suffix": "of Thunder", "arch": "attrition", "trigger": "round_third", "effect": "nova", "value": 0.35},
		{"id": "relentless", "name": "Relentless", "suffix": "of the Long Fight", "arch": "attrition", "kind": "dmg_pct", "value": 0.25, "cond": {"round_min": 4}},
		{"id": "onslaught", "name": "Onslaught", "suffix": "of Onslaught", "arch": "executioner", "trigger": "on_kill", "effect": "extra_turn", "value": 1.0, "epic": true},
	],
	"armor": [
		{"id": "riposte", "name": "Riposte", "suffix": "of Riposte", "arch": "evasion", "trigger": "evade_or_heavy", "effect": "counter_attack", "value": 0.4},
		{"id": "bulwark", "name": "Shield-Bearer", "suffix": "of the Shield-Bearer", "arch": "guardian", "trigger": "ally_targeted", "effect": "intercept", "value": 0.3},
		{"id": "blunting", "name": "Blunting", "suffix": "of Blunting", "arch": "guardian", "trigger": "evade_or_heavy", "effect": "weaken_attacker", "value": 0.1},
		{"id": "laststand", "name": "Last Stand", "suffix": "of the Last Stand", "arch": "executioner", "kind": "dmg_pct", "value": 0.3, "cond": {"hp_below": 0.4}},
		{"id": "aegis", "name": "Aegis", "suffix": "of the Aegis", "arch": "guardian", "trigger": "round_third", "effect": "shield_party", "value": 0.06, "epic": true},
	],
	"focus": [
		{"id": "renewal", "name": "Renewal", "suffix": "of Renewal", "arch": "sustain", "trigger": "round_third", "effect": "mend_party", "value": 0.06},
		{"id": "grace", "name": "Grace", "suffix": "of Grace", "arch": "sustain", "trigger": "party_mend", "effect": "shield_lowest", "value": 0.08},
		{"id": "blur", "name": "Blur", "suffix": "of the Blur", "arch": "evasion", "kind": "dodge_pct", "value": 0.15, "cond": {"hp_above": 0.75}},
		{"id": "slayer", "name": "Giant-Slayer", "suffix": "of Giants", "arch": "executioner", "kind": "dmg_pct", "value": 0.2, "cond": {"vs_boss": true}},
		{"id": "focus", "name": "Focus", "suffix": "of Focus", "arch": "opener", "trigger": "evade_or_heavy", "effect": "gain_momentum", "value": 0.5},
	],
}
const ITEM_EFFECT_EPIC_MULT := 1.35


## An older Epic's extra, situational affix (before ITEM_EFFECTS) — the Combat.hero_effects entry shape
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


static func find_class(pool_id: String) -> Dictionary:
	for c in CLASS_POOL:
		if c["id"] == pool_id:
			return c
	return {}


static func rank_index(rank_id: String) -> int:
	for i in RANKS.size():
		if RANKS[i]["id"] == rank_id:
			return i
	return 0
