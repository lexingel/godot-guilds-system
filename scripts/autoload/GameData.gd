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

## Legendary items: fixed (never rolled) hero-bound gear, each with one
## effect outside the normal BUILD_KINDS vocabulary (dispatched by `effect` in
## Combat.resolve_round via Combat.hero_has_unique_item) plus, on most, a real
## drawback in the *existing* kind vocabulary so it still flows through
## hero_item_total/hero_skill_total for free. "locked_role"/"locked_subclasses"
## restrict who can equip it - "" / [] means no restriction.
const UNIQUE_ITEMS := [
	{"id": "bloodthirst_fang", "name": "Bloodthirst Fang", "category": "weapon",
	 "effect": "lifesteal_pct", "value": 0.25,
	 "drawback_kind": "hazard_guard_pct", "drawback_value": -0.15,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "Heals the wielder for 25% of the damage they deal each round they attack. -15% hazard severity guard."},
	{"id": "widows_edge", "name": "Widow's Edge", "category": "weapon",
	 "effect": "execute_below_pct", "value": 0.15,
	 "drawback_kind": "dmg_pct", "drawback_value": -0.10,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "Instantly finishes a foe this hero's attack would drop below 15% HP. -10% damage otherwise."},
	{"id": "last_stand_plate", "name": "Last Stand Plate", "category": "armor",
	 "effect": "desperate_dodge", "value": 0.30,
	 "drawback_kind": "dodge_pct", "drawback_value": -0.10,
	 "locked_role": "", "locked_subclasses": [],
	 "desc": "The lower this hero's HP, up to +30% dodge chance near death. -10% dodge chance at full HP."},
	{"id": "oathbound_talisman", "name": "Oathbound Talisman", "category": "focus",
	 "effect": "mend_shield_proc", "value": 0.15,
	 "drawback_kind": "dmg_pct", "drawback_value": -0.15,
	 "locked_role": "cleric", "locked_subclasses": [],
	 "desc": "Whenever the party mends, also shields the lowest-HP ally for 15% of their max HP. -15% damage. Cleric only."},
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
	{"id": "lesser", "name": "Lesser Rift", "floors": 7, "monster_hp": 38, "monster_dmg": 5, "coin": [18, 34], "crystal": [5, 11], "token_base": 10, "detector_chance": 0.08, "power": "Low", "rec_power": 70},
	# Unlocked by GameState.greater_rift_unlocked() (seal 3 rifts) rather than
	# Guild Management currency — sits between Lesser and the Ascendant-
	# equivalent ENDLESS_BASE below. First-draft numbers, tunable after playing.
	{"id": "greater", "name": "Greater Rift", "floors": 8, "monster_hp": 70, "monster_dmg": 9, "coin": [40, 70], "crystal": [11, 20], "token_base": 18, "detector_chance": 0.14, "power": "Medium", "rec_power": 150},
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
	# -- Warrior (content-pass additions) --
	"fieldmender": {"name": "Battlefield Patch", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.3},
	"featherguard": {"name": "Light Feet", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.12},
	"trailblazer": {"name": "First Through", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.75},
	"frostguard": {"name": "Unbothered", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.3},
	"warbrand": {"name": "Growing Anger", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.04},
	"aegis-bearer": {"name": "On Principle", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.35},
	"stormguard": {"name": "Meet the Charge", "desc": "A heavy burst against the weakest foe.", "effect": "burst_lowest", "value": 1.1},
	"rift-breaker": {"name": "First Crack", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.0},
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
	# -- Ranger (content-pass additions) --
	"shadowtracker": {"name": "Scent in the Dark", "desc": "Weakens every foe's damage for the rest of this fight.", "effect": "monster_dmg_mult", "value": 0.85},
	"fieldscout": {"name": "Exact Shot", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.75},
	"nightwarden": {"name": "Watching the Dark", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.2},
	"sapling-keeper": {"name": "Field Dressing", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.35},
	"duskstalker": {"name": "Gone Before the Echo", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.15},
	"gale-marksman": {"name": "True on the Wind", "desc": "A heavy burst against the weakest foe.", "effect": "burst_lowest", "value": 1.1},
	"rift-piercer": {"name": "The One Seam", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.0},
	"wintertide-archer": {"name": "Colder Every Shot", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.045},
	"rift-eclipsed-warden": {"name": "Eclipse Volley", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.15},
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
	# -- Mage (content-pass additions) --
	"thornweaver": {"name": "Grown of Will", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.3},
	"shade-adept": {"name": "The Quiet Spell", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.7},
	"stoneward-mystic": {"name": "Bark and Stone", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.3},
	"grim-conjurer": {"name": "One More Round", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.25},
	"verdant-oracle": {"name": "Root and Leaf", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.45},
	"duskglass-seer": {"name": "Sees It Land First", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.18},
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
	"emberblessed-acolyte": {"name": "Lit Candle", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.75},
	"frostward-sister": {"name": "Keeps the Chill Out", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.3},
	"vanguard-chaplain": {"name": "Blessed Blade", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 1.0},
	"hearth-warden": {"name": "Fire in the Cold", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.25},
	"ember-confessor": {"name": "Brief Absolution", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.95},
	"frost-anchorite": {"name": "Fasting Vigil", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.5},
	"radiant-vanguard": {"name": "Leads With Light", "desc": "A finishing blow against the weakest foe, stronger the lower they are.", "effect": "execute_burst", "value": 1.0},
	"sainted-ember": {"name": "First Word", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.05},
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
	# -- Rogue (content-pass additions) --
	"herbrunner": {"name": "Unpoisoned Plants", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.35},
	"arcane-pilferer": {"name": "Warded Vault", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.85},
	"ironhide-footpad": {"name": "Tougher Than It Looks", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.3},
	"glyphhand": {"name": "Reads the Seams", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.16},
	"bramblefoot": {"name": "The Undergrowth Hides More", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.2},
	"rift-slipper": {"name": "Half Out of Reality", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.3},
	"wraithblade-adept": {"name": "Thinner and Faster", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.045},
	"the-unseen-hand": {"name": "Already Struck", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.1},
	"the-final-cut": {"name": "Uncatchable", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.28},
}

## One icon per ability *effect* (13 shapes, not 50 abilities) reusing the
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
}

static func ability_icon(pool_id: String) -> String:
	var ab: Dictionary = SUBCLASS_ABILITIES.get(pool_id, {})
	return ABILITY_EFFECT_ICON.get(str(ab.get("effect", "")), "res://assets/skills/sword_a.png")

## Every node's "icon" points at a bespoke pixel-art icon under
## assets/skills/ (extracted from a free CraftPix icon sheet) — 38 distinct
## icons across the 2 universal Tier-1 nodes + 9 packages x 4 nodes, no two
## nodes sharing an icon.
const SUBCLASS_TIER1 := [
	{"id": "edge", "tier": 1, "req_level": 2, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Honed Edge", "requires": [], "icon": "res://assets/skills/sword_a.png"},
	{"id": "hide", "tier": 1, "req_level": 2, "cost": 1, "kind": "hp_pct", "value": 0.08, "name": "Thick Hide", "requires": [], "icon": "res://assets/skills/heart.png"},
]

## Each package's shape: the original 3 Tier-2 nodes (2 gated by a Tier-1
## root, 1 free) are unchanged, plus a 4th Tier-2 node requiring BOTH roots.
## Tier 3 is a hard-exclusive fork — "cap" (the original capstone, kept
## as-is so any hero who already learned it under the old 1-capstone shape
## stays valid) vs "cap_alt" (a new alternate direction); each `excludes`
## the other, so learning one permanently locks out the other regardless of
## level/SP. Tier 4 is a single finisher per fork, only reachable through
## that fork's own capstone — the "how far does this path go" payoff.
const KIND_SKILL_PACKAGE := {
	"dmg_pct": [
		{"id": "mastery", "tier": 2, "req_level": 4, "cost": 1, "kind": "dmg_pct", "value": 0.10, "name": "Weapon Mastery", "requires": ["edge"], "icon": "res://assets/skills/sword_silver.png"},
		{"id": "killer_instinct", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Killing Instinct", "requires": ["hide"], "icon": "res://assets/skills/gem_red.png"},
		{"id": "opening_fury", "tier": 2, "req_level": 5, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Opening Fury", "requires": [], "icon": "res://assets/skills/sword_slash.png"},
		{"id": "battle_fury", "tier": 2, "req_level": 5, "cost": 1, "kind": "dmg_pct", "value": 0.06, "name": "Battle Fury", "requires": ["edge", "hide"], "icon": "res://assets/skills/sword_dual.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "dmg_pct", "value": 0.22, "name": "Executioner's Edge", "requires": ["mastery", "killer_instinct"], "excludes": ["cap_alt"], "icon": "res://assets/skills/sword_big.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "escalate_pct", "value": 0.05, "name": "Bloodletter's Patience", "requires": ["mastery", "killer_instinct"], "excludes": ["cap"], "icon": "res://assets/skills/shard_blue.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "dmg_pct", "value": 0.15, "name": "Killing Blow", "requires": ["cap"], "icon": "res://assets/skills/sword_big.png"},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "escalate_pct", "value": 0.04, "name": "Endless Fury", "requires": ["cap_alt"], "icon": "res://assets/skills/leaf_big.png"},
	],
	"hp_pct": [
		{"id": "iron_skin", "tier": 2, "req_level": 4, "cost": 1, "kind": "hp_pct", "value": 0.10, "name": "Iron Skin", "requires": ["hide"], "icon": "res://assets/skills/shield_blue.png"},
		{"id": "steady_guard", "tier": 2, "req_level": 4, "cost": 1, "kind": "hazard_guard_pct", "value": 0.10, "name": "Steady Guard", "requires": ["edge"], "icon": "res://assets/skills/shield_basic.png"},
		{"id": "second_wind", "tier": 2, "req_level": 5, "cost": 1, "kind": "mend_pct", "value": 0.05, "name": "Second Wind", "requires": [], "icon": "res://assets/skills/potion_red_sm.png"},
		{"id": "fortified_stance", "tier": 2, "req_level": 5, "cost": 1, "kind": "hp_pct", "value": 0.06, "name": "Fortified Stance", "requires": ["edge", "hide"], "icon": "res://assets/skills/armor_chest.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "hp_pct", "value": 0.25, "name": "Unbreakable", "requires": ["iron_skin", "steady_guard"], "excludes": ["cap_alt"], "icon": "res://assets/skills/shield_split.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "hazard_guard_pct", "value": 0.18, "name": "Stone Sentinel", "requires": ["iron_skin", "steady_guard"], "excludes": ["cap"], "icon": "res://assets/skills/shield_orange.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "hp_pct", "value": 0.15, "name": "Immovable", "requires": ["cap"], "icon": "res://assets/skills/shield_split.png"},
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
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "escalate_pct", "value": 0.04, "name": "Boundless Fury", "requires": ["cap"], "icon": "res://assets/skills/leaf_big.png"},
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
	"dodge_pct": [
		{"id": "evasion", "tier": 2, "req_level": 4, "cost": 1, "kind": "dodge_pct", "value": 0.12, "name": "Evasive Training", "requires": ["hide"], "icon": "res://assets/skills/face_hood.png"},
		{"id": "momentum", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Fleeting Strike", "requires": ["edge"], "icon": "res://assets/skills/wing.png"},
		{"id": "gambit", "tier": 2, "req_level": 5, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Opening Gambit", "requires": [], "icon": "res://assets/skills/gem_blue_b.png"},
		{"id": "phantom_step", "tier": 2, "req_level": 5, "cost": 1, "kind": "dodge_pct", "value": 0.06, "name": "Phantom Step", "requires": ["edge", "hide"], "icon": "res://assets/skills/wing.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "dmg_pct", "value": 0.20, "name": "Shadow Strike", "requires": ["evasion", "momentum"], "excludes": ["cap_alt"], "icon": "res://assets/skills/shard_blue.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "dodge_pct", "value": 0.16, "name": "Untouchable Form", "requires": ["evasion", "momentum"], "excludes": ["cap"], "icon": "res://assets/skills/face_hood.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "dmg_pct", "value": 0.15, "name": "Killer's Shadow", "requires": ["cap"], "icon": "res://assets/skills/shard_blue.png"},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "dodge_pct", "value": 0.14, "name": "Ghost Step", "requires": ["cap_alt"], "icon": "res://assets/skills/boots.png"},
	],
	"wipe_guard": [
		{"id": "shieldwall", "tier": 2, "req_level": 4, "cost": 1, "kind": "dodge_pct", "value": 0.10, "name": "Shield Wall", "requires": ["hide"], "icon": "res://assets/skills/armor_shoulder.png"},
		{"id": "vanguard", "tier": 2, "req_level": 4, "cost": 1, "kind": "first_round_pct", "value": 0.10, "name": "Vanguard Strike", "requires": ["edge"], "icon": "res://assets/skills/gem_cluster.png"},
		{"id": "instinct", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.08, "name": "Battle Instinct", "requires": [], "icon": "res://assets/skills/cloak_a.png"},
		{"id": "guardians_resolve", "tier": 2, "req_level": 5, "cost": 1, "kind": "hazard_guard_pct", "value": 0.06, "name": "Guardian's Resolve", "requires": ["edge", "hide"], "icon": "res://assets/skills/cloak_a.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "wipe_guard", "value": 0.25, "name": "Last Stand", "requires": ["shieldwall", "vanguard"], "excludes": ["cap_alt"], "icon": "res://assets/skills/trophy.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "hp_pct", "value": 0.20, "name": "Undying Vanguard", "requires": ["shieldwall", "vanguard"], "excludes": ["cap"], "icon": "res://assets/skills/shield_split.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "wipe_guard", "value": 0.15, "name": "Defiant to the End", "requires": ["cap"], "icon": "res://assets/skills/trophy.png"},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "hp_pct", "value": 0.15, "name": "Iron Will", "requires": ["cap_alt"], "icon": "res://assets/skills/armor_shoulder.png"},
	],
	"boss_alpha_strike": [
		{"id": "buildup2", "tier": 2, "req_level": 4, "cost": 1, "kind": "escalate_pct", "value": 0.03, "name": "Arcane Buildup", "requires": ["edge"], "icon": "res://assets/skills/star.png"},
		{"id": "ward", "tier": 2, "req_level": 4, "cost": 1, "kind": "hazard_guard_pct", "value": 0.10, "name": "Ward Sigil", "requires": ["hide"], "icon": "res://assets/skills/gem_blue_big.png"},
		{"id": "slip", "tier": 2, "req_level": 5, "cost": 1, "kind": "dodge_pct", "value": 0.08, "name": "Arcane Slip", "requires": [], "icon": "res://assets/skills/shard_green.png"},
		{"id": "arcane_convergence", "tier": 2, "req_level": 5, "cost": 1, "kind": "dmg_pct", "value": 0.08, "name": "Arcane Convergence", "requires": ["edge", "hide"], "icon": "res://assets/skills/gem_blue_big.png"},
		{"id": "cap", "tier": 3, "req_level": 7, "cost": 2, "kind": "boss_alpha_strike", "value": 1.0, "name": "Cataclysm", "requires": ["buildup2", "ward"], "excludes": ["cap_alt"], "icon": "res://assets/skills/ingot_gold.png"},
		{"id": "cap_alt", "tier": 3, "req_level": 7, "cost": 2, "kind": "escalate_pct", "value": 0.05, "name": "Sustained Onslaught", "requires": ["buildup2", "ward"], "excludes": ["cap"], "icon": "res://assets/skills/star.png"},
		{"id": "cap_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "dmg_pct", "value": 0.25, "name": "World Ender", "requires": ["cap"], "icon": "res://assets/skills/ingot_gold.png"},
		{"id": "cap_alt_finisher", "tier": 4, "req_level": 9, "cost": 2, "kind": "escalate_pct", "value": 0.04, "name": "Relentless Tide", "requires": ["cap_alt"], "icon": "res://assets/skills/leaf_big.png"},
	],
}


## The storage key a skill uses in Hero.skills. Every KIND_SKILL_PACKAGE
## reuses the same node ids ("cap", "mastery", ...), which was harmless when
## a hero only ever had one active tree — evolving keeping the old tree
## reachable (see hero_tree_summaries) means two of a hero's trees can now
## both have a node called "cap", so anything but the universal Tier-1
## roots ("edge"/"hide" — shared, learned once, apply to every tree) needs
## its owning kind folded into the key.
static func skill_storage_key(kind: String, node_id: String) -> String:
	return node_id if node_id in ["edge", "hide"] else "%s:%s" % [kind, node_id]


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
## (CLASS_POOL's array order shouldn't matter). GameState.evolve_hero() picks
## among these with an aptitude-weighted random roll, not a player choice or
## a deterministic first-match — see the Evolution Stone constants below.
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
## finer granularity SS/SSS need); fuse_minutes is the real-time countdown
## before an unaddressed rift Riftbreaks — shorter at higher rank, so a rare
## S/SS/SSS sighting is genuinely fleeting. First-draft numbers, tunable after
## the map is playable.
const RIFT_RANKS := [
	{"id": "F", "weight": 1000, "fuse_minutes": 45},
	{"id": "E", "weight": 600, "fuse_minutes": 40},
	{"id": "D", "weight": 350, "fuse_minutes": 35},
	{"id": "C", "weight": 200, "fuse_minutes": 30},
	{"id": "B", "weight": 100, "fuse_minutes": 25},
	{"id": "A", "weight": 40, "fuse_minutes": 20},
	{"id": "S", "weight": 10, "fuse_minutes": 15},
	{"id": "SS", "weight": 3, "fuse_minutes": 10},
	{"id": "SSS", "weight": 1, "fuse_minutes": 6},
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
const MEDICAL_BG := "res://assets/screens/medical_bg.png"
const ROSTER_BG := "res://assets/screens/roster_bg.png"
const MANAGEMENT_BG := "res://assets/screens/management_bg.png"
const BED_ICON := "res://assets/screens/bed_icon.png"
const RIFTHALL_BG := "res://assets/screens/rifthall_bg.png"
const RIFTMAP_BG := "res://assets/screens/riftmap_bg.png"
const INVENTORY_BG := "res://assets/screens/inventory_bg.png"
const CRAFTING_BG := "res://assets/screens/crafting_bg.png"
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
	"goblin": "res://assets/monsters/goblin.png",
	"orc": "res://assets/monsters/orc.png",
	"skelly": "res://assets/monsters/skelly.png",
	"mummy": "res://assets/monsters/mummy.png",
	"zombie": "res://assets/monsters/zombie.png",
	"slime": "res://assets/monsters/slime.png",
	"wraith": "res://assets/monsters/wraith.png",
	"fire_skull": "res://assets/monsters/fire_skull.png",
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
	"Gloom Stalker": "wraith", "Rift Wisp": "fire_skull", "Husk Brute": "zombie",
	"Sable Fang": "orc", "Ember Whelp": "goblin", "Marrow Crawler": "skelly",
	"Hollow Reaver": "mummy", "Cinder Moth": "slime",
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
## hero_anim_frames) — the original 8 monster sprites all got usable
## attack/hurt motion on the first PixelLab pass. The content-pass batch of
## 19 more (Phase 19) got their static sprites generated but ran out of
## PixelLab credits before their animations — checking frame 0 actually
## exists (rather than assuming every known sprite key has animations, like
## this used to) means those 19 gracefully fall back to a tween instead of
## erroring on a missing resource every time they're hit, the same contract
## hero_anim_frames already has for its own gaps.
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


## Looks up a bare node id within a specific kind's package (or the
## universal Tier-1 roots, for "edge"/"hide" — `kind` is ignored then, since
## those are shared across every tree).
static func find_skill_node(kind: String, skill_id: String) -> Dictionary:
	if skill_id == "edge" or skill_id == "hide":
		for n in SUBCLASS_TIER1:
			if n["id"] == skill_id:
				return n
		return {}
	for n in KIND_SKILL_PACKAGE.get(kind, []):
		if n["id"] == skill_id:
			return n
	return {}


static func weapon_slots(pool_id: String) -> int:
	return 2 if DUAL_WIELD_CLASSES.has(pool_id) else 1


static func gear_slots(rank_id: String) -> int:
	return 1 + int(floor(rank_index(rank_id) / 2.0))
