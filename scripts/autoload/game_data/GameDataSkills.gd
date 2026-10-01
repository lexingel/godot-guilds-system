extends "res://scripts/autoload/game_data/GameDataMonsters.gd"
## GameData, part 5: abilities, skill trees and keystones, evolution, awakening, the Champion, recruiting odds.

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
	"duelist": {"name": "Riposte", "desc": "Stands ready: the next 3 hits on this hero are answered with a counter-strike.", "effect": "riposte", "value": 0.35},
	"bulwark": {"name": "Unyielding Wall", "desc": "Draws every foe's attacks this round (30% less from them) and wards themself for 30% of max HP.", "effect": "taunt_ward", "value": 0.3},
	"berserker": {"name": "Blood Frenzy", "desc": "Sacrifices own HP for a heavy burst on the weakest foe.", "effect": "self_sac_burst", "value": 1.4},
	"iron-guard": {"name": "Fortify", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.3},
	"bloodletter": {"name": "Open Wound", "desc": "For the rest of the fight, the party's hits heal the attacker for 20% of the damage.", "effect": "lifesteal_surge", "value": 0.2},
	"runeblade": {"name": "Inscribed Strike", "desc": "Inscribes every blade in the party — damage surges for the rest of this fight.", "effect": "team_dmg_mult", "value": 1.18},
	"ashen-templar": {"name": "Undying Vow", "desc": "This round the hero takes half damage and can't fall below 1 HP.", "effect": "undying", "value": 0.5},
	"rift-sovereign": {"name": "Sovereign's Wrath", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.1},
	# -- Warrior (content-pass additions) --
	"fieldmender": {"name": "Battlefield Patch", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.3},
	"featherguard": {"name": "Light Feet", "desc": "+35% dodge for the whole party until the round ends.", "effect": "evasion_round", "value": 0.35},
	"trailblazer": {"name": "First Through", "desc": "Two quick strikes at the target.", "effect": "double_strike", "value": 0.9},
	"frostguard": {"name": "Unbothered", "desc": "Wards every hero in the front row for 30% of their max HP.", "effect": "shield_wall_front", "value": 0.3},
	"warbrand": {"name": "Growing Anger", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.04},
	"aegis-bearer": {"name": "On Principle", "desc": "Cripples the greatest threat's damage output for the rest of this fight.", "effect": "debuff_lowest", "value": 0.6},
	"stormguard": {"name": "Meet the Charge", "desc": "A heavy blow at the target that stuns it (bosses only lose their wind-up).", "effect": "stun_strike", "value": 1.0},
	"rift-breaker": {"name": "First Crack", "desc": "Shatters the target's armor and ward; it takes 15% more damage for the rest of the fight.", "effect": "armor_break", "value": 0.8},
	# -- Ranger --
	"trapper": {"name": "Snare Volley", "desc": "Sets a snare: the next foe to attack is hit hard and loses that attack.", "effect": "trap", "value": 1.2},
	"slinger": {"name": "Improvised Shot", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.75},
	"pathfinder": {"name": "Sure Footing", "desc": "Shields the whole party lightly.", "effect": "team_shield_burst", "value": 0.12},
	"longshot": {"name": "One Arrow", "desc": "A finishing blow against the weakest foe, stronger the lower they are.", "effect": "execute_burst", "value": 0.9},
	"blade-dancer": {"name": "Opening Performance", "desc": "A finishing sweep against every wounded foe.", "effect": "execute_all_low", "value": 0.55},
	"warden": {"name": "Walked Worse Halls", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.25},
	"stormtracker": {"name": "Chase the Lightning", "desc": "Lightning strikes three times, jumping between foes.", "effect": "chain_lightning", "value": 0.6},
	"rift-ranger": {"name": "Read the Room", "desc": "+7 Momentum for the party (it costs 4).", "effect": "reset_cooldowns", "value": 0.0},
	"deadfall-hunter": {"name": "Reversed Trap", "desc": "Sets a heavy snare: the next foe to attack is hit hard and loses that attack.", "effect": "trap", "value": 1.5},
	"voidwalker": {"name": "Half-Step Out", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.22},
	# -- Ranger (content-pass additions) --
	"shadowtracker": {"name": "Scent in the Dark", "desc": "Weakens every foe's damage for the rest of this fight.", "effect": "monster_dmg_mult", "value": 0.85},
	"fieldscout": {"name": "Exact Shot", "desc": "Finds the gap: breaks the target's armor and ward; it takes 15% more damage for the rest of the fight.", "effect": "armor_break", "value": 0.9},
	"nightwarden": {"name": "Watching the Dark", "desc": "Marks the target: it takes 30% more damage from every hero for the rest of the fight.", "effect": "mark_target", "value": 0.3},
	"sapling-keeper": {"name": "Field Dressing", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.35},
	"duskstalker": {"name": "Gone Before the Echo", "desc": "+40% dodge for the whole party until the round ends.", "effect": "evasion_round", "value": 0.4},
	"gale-marksman": {"name": "True on the Wind", "desc": "A finishing sweep against every wounded foe.", "effect": "execute_all_low", "value": 0.55},
	"rift-piercer": {"name": "The One Seam", "desc": "Tears every foe's armor and ward away and hits each of them.", "effect": "ward_break", "value": 0.7},
	"wintertide-archer": {"name": "Colder Every Shot", "desc": "Freezes the target: it loses its next two actions (a boss, one).", "effect": "freeze_target", "value": 0.6},
	"rift-eclipsed-warden": {"name": "Eclipse Volley", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.15},
	# -- Mage --
	"apprentice": {"name": "Unsteady Spark", "desc": "A burst against the weakest foe.", "effect": "burst_lowest", "value": 0.7},
	"cinderling": {"name": "First Spark", "desc": "Sets every foe burning for three rounds.", "effect": "burn_all", "value": 0.4},
	"fledgling-seer": {"name": "Half-Second Warning", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.08},
	"cinder-adept": {"name": "Warming Cast", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.03},
	"frost-scholar": {"name": "Cold Study", "desc": "Freezes the target: it loses its next two actions (a boss, one).", "effect": "freeze_target", "value": 0.5},
	"wardweaver": {"name": "Faster Ward", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.3},
	"stormcaller": {"name": "Building Storm", "desc": "Lightning strikes three times, jumping between foes.", "effect": "chain_lightning", "value": 0.8},
	"pyromancer": {"name": "Wildfire", "desc": "Sets every foe burning for three rounds.", "effect": "burn_all", "value": 0.6},
	"archon-of-storms": {"name": "Thunder's Door", "desc": "Thunder strikes three times, jumping between foes.", "effect": "chain_lightning", "value": 1.0},
	"the-unbound": {"name": "No Name Holds It", "desc": "A heavy burst against the weakest foe.", "effect": "burst_lowest", "value": 1.6},
	# -- Mage (content-pass additions) --
	"thornweaver": {"name": "Grown of Will", "desc": "For the rest of the fight, the party's hits heal the attacker for 20% of the damage.", "effect": "lifesteal_surge", "value": 0.2},
	"shade-adept": {"name": "The Quiet Spell", "desc": "Marks the target: it takes 30% more damage from every hero for the rest of the fight.", "effect": "mark_target", "value": 0.3},
	"stoneward-mystic": {"name": "Bark and Stone", "desc": "Wards every hero in the front row for 30% of their max HP.", "effect": "shield_wall_front", "value": 0.3},
	"grim-conjurer": {"name": "One More Round", "desc": "Raises a fallen ally at 40% HP (or heals the most-hurt ally).", "effect": "revive", "value": 0.4},
	"verdant-oracle": {"name": "Root and Leaf", "desc": "Heals the whole party 35% and cleanses burn, poison, chill, stun and curses.", "effect": "cleanse_heal", "value": 0.35},
	"duskglass-seer": {"name": "Sees It Land First", "desc": "+7 Momentum for the party (it costs 4).", "effect": "reset_cooldowns", "value": 0.0},
	"ashbound-theorist": {"name": "Ends in Fire", "desc": "Sets every foe burning for three rounds.", "effect": "burn_all", "value": 0.6},
	"rift-warden-magus": {"name": "Warded Before It Forms", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.35},
	# -- Cleric --
	"peddler": {"name": "Quick Bandage", "desc": "Mends and shields the lowest-HP ally at once.", "effect": "mend_shield_hybrid", "value": 0.15},
	"acolyte": {"name": "Quiet Prayer", "desc": "Heals the whole party 30% and cleanses burn, poison, chill, stun and curses.", "effect": "cleanse_heal", "value": 0.3},
	"herbalist": {"name": "Field Kit", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.4},
	"lay-brother": {"name": "Censer Swing", "desc": "A swing at the target that stuns it (bosses only lose their wind-up).", "effect": "stun_strike", "value": 0.8},
	"battle-chaplain": {"name": "Keep Moving", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.12},
	"zealot": {"name": "Faith and Blade", "desc": "Pays 20% of their own HP: +3 Momentum and +15% party damage for the rest of the fight.", "effect": "blood_price", "value": 0.15},
	"rift-medic": {"name": "Faster Than the Wounds", "desc": "Raises a fallen ally at 50% HP (or heals the most-hurt ally).", "effect": "revive", "value": 0.5},
	"dawnkeeper": {"name": "First Light", "desc": "Heals the whole party 30% and cleanses burn, poison, chill, stun and curses.", "effect": "cleanse_heal", "value": 0.3},
	"sanctified-shield": {"name": "Not Today", "desc": "Shields the lowest-HP ally.", "effect": "shield_lowest", "value": 0.4},
	"alchemist": {"name": "Faster Brew", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.04},
	"last-light-martyr": {"name": "Last Light", "desc": "Braces the party against a wipe for the rest of this fight.", "effect": "wipe_guard_surge", "value": 0.6},
	# -- Cleric (content-pass additions) --
	"emberblessed-acolyte": {"name": "Lit Candle", "desc": "Lights every blade with sacred fire — damage surges for the rest of this fight.", "effect": "team_dmg_mult", "value": 1.10},
	"frostward-sister": {"name": "Keeps the Chill Out", "desc": "Wards every hero in the front row for 30% of their max HP.", "effect": "shield_wall_front", "value": 0.3},
	"vanguard-chaplain": {"name": "Blessed Blade", "desc": "A finishing sweep against every wounded foe.", "effect": "execute_all_low", "value": 0.5},
	"hearth-warden": {"name": "Fire in the Cold", "desc": "Wards every hero in the front row for 35% of their max HP.", "effect": "shield_wall_front", "value": 0.35},
	"ember-confessor": {"name": "Brief Absolution", "desc": "Finishes the target outright if it's below 35% HP (not a boss); otherwise a heavy blow.", "effect": "execute_threshold", "value": 0.95},
	"frost-anchorite": {"name": "Fasting Vigil", "desc": "Heals the whole party 40% and cleanses burn, poison, chill, stun and curses.", "effect": "cleanse_heal", "value": 0.4},
	"radiant-vanguard": {"name": "Leads With Light", "desc": "A finishing blow against the weakest foe, stronger the lower they are.", "effect": "execute_burst", "value": 1.0},
	"sainted-ember": {"name": "First Word", "desc": "A wave of damage sweeps every foe.", "effect": "cleave_burst", "value": 1.05},
	# -- Rogue --
	"scavenger": {"name": "Know the Puddles", "desc": "+30% dodge for the whole party until the round ends.", "effect": "evasion_round", "value": 0.3},
	"runaway": {"name": "Never Fought Fair", "desc": "Shields the whole party lightly.", "effect": "team_shield_burst", "value": 0.10},
	"cutpurse": {"name": "Leaves With More", "desc": "A burst against the weakest foe, healing the caster for a share of the damage.", "effect": "hp_drain_burst", "value": 0.75},
	"skirmisher": {"name": "Never Where You Struck", "desc": "Shields the whole party lightly.", "effect": "team_shield_burst", "value": 0.13},
	"footpad": {"name": "Nobody Heard Them", "desc": "+chance to counter-attack for the rest of this fight.", "effect": "counter_surge", "value": 0.2},
	"shadowfoot": {"name": "Barely Noticed", "desc": "+dodge chance for the rest of this fight.", "effect": "dodge_surge", "value": 0.18},
	"fleetblade": {"name": "Getting Faster", "desc": "Two quick strikes at the target.", "effect": "double_strike", "value": 0.9},
	"nightblade": {"name": "Strikes From the Dark", "desc": "A heavy burst against the weakest foe, healing the caster for a share of the damage.", "effect": "hp_drain_burst", "value": 1.1},
	"wraithstep": {"name": "Two Footprints", "desc": "A finishing blow against the weakest foe, stronger the lower they are.", "effect": "execute_burst", "value": 1.0},
	"duskrunner": {"name": "Between Heartbeats", "desc": "A heavy burst against the weakest foe, healing the caster for a share of the damage.", "effect": "hp_drain_burst", "value": 1.3},
	# -- Rogue (content-pass additions) --
	"herbrunner": {"name": "Unpoisoned Plants", "desc": "Mends the whole party.", "effect": "mend_burst", "value": 0.35},
	"arcane-pilferer": {"name": "Warded Vault", "desc": "Picks every foe's armor and ward apart and hits each of them.", "effect": "ward_break", "value": 0.6},
	"ironhide-footpad": {"name": "Tougher Than It Looks", "desc": "This round the hero takes half damage and can't fall below 1 HP.", "effect": "undying", "value": 0.5},
	"glyphhand": {"name": "Reads the Seams", "desc": "Reads every seam: strips each foe's armor and ward and hits them.", "effect": "ward_break", "value": 0.6},
	"bramblefoot": {"name": "The Undergrowth Hides More", "desc": "Mends and shields the lowest-HP ally at once.", "effect": "mend_shield_hybrid", "value": 0.15},
	"rift-slipper": {"name": "Half Out of Reality", "desc": "+35% dodge for the whole party until the round ends.", "effect": "evasion_round", "value": 0.35},
	"wraithblade-adept": {"name": "Thinner and Faster", "desc": "Damage escalates faster for the rest of this fight.", "effect": "escalate_surge", "value": 0.045},
	"the-unseen-hand": {"name": "Already Struck", "desc": "Finishes the target outright if it's below 35% HP (not a boss); otherwise a heavy blow.", "effect": "execute_threshold", "value": 1.1},
	"the-final-cut": {"name": "The Final Cut", "desc": "Finishes the target outright if it's below 35% HP (not a boss); otherwise a heavy blow.", "effect": "execute_threshold", "value": 1.2},
}

## One icon per ability *effect* (37 shapes, not ~90 abilities) reusing the
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
	"stun_strike": "res://assets/skills/shield_orange.png",
	"riposte": "res://assets/skills/sword_silver.png",
	"taunt_ward": "res://assets/skills/helm.png",
	"undying": "res://assets/skills/heart.png",
	"revive": "res://assets/skills/star.png",
	"burn_all": "res://assets/relics/escalate_pct.png",
	"chain_lightning": "res://assets/skills/gem_blue_b.png",
	"mark_target": "res://assets/skills/eye_gem.png",
	"execute_threshold": "res://assets/skills/dagger_blue.png",
	"armor_break": "res://assets/skills/armor_shoulder.png",
	"double_strike": "res://assets/skills/sword_dual.png",
	"evasion_round": "res://assets/skills/cloak_a.png",
	"shield_wall_front": "res://assets/skills/shield_split.png",
	"trap": "res://assets/skills/ring.png",
	"ward_break": "res://assets/skills/shard_blue.png",
	"freeze_target": "res://assets/skills/gem_blue_a.png",
	"cleanse_heal": "res://assets/skills/potion_blue.png",
	"lifesteal_surge": "res://assets/skills/potion_red_sm.png",
	"blood_price": "res://assets/skills/gem_red.png",
}


## An Ability's description with its numbers: most descriptions were only
## flavour ("Mends the whole party."). The numbers follow Combat's ability
## match exactly; "the party's damage" is the party's combined attack.
static func ability_desc(pool_id: String) -> String:
	var ab: Dictionary = SUBCLASS_ABILITIES.get(pool_id, {})
	var v: float = float(ab.get("value", 0.0))
	var p := func(x: float) -> int: return int(round(x * 100.0))
	var n := ""
	match str(ab.get("effect", "")):
		"mend_burst": n = TranslationServer.translate("Heals every ally for %d%% of their max HP.") % p.call(v)
		"monster_dmg_mult": n = TranslationServer.translate("Every foe deals %d%% less damage for the rest of the fight.") % p.call(1.0 - v)
		"team_dmg_mult": n = TranslationServer.translate("+%d%% party damage for the rest of the fight.") % p.call(v - 1.0)
		"burst_lowest": n = TranslationServer.translate("Hits the weakest foe for %d%% of the party's damage.") % p.call(v)
		"cleave_burst": n = TranslationServer.translate("Hits every foe for %d%% of the party's damage.") % p.call(v)
		"execute_burst": n = TranslationServer.translate("Hits the weakest foe for %d%% of the party's damage, up to double against one near death.") % p.call(v)
		"shield_lowest": n = TranslationServer.translate("Shields the lowest-HP ally for %d%% of their max HP.") % p.call(v)
		"reset_cooldowns": n = TranslationServer.translate("+7 Momentum.")
		"dodge_surge": n = TranslationServer.translate("+%d%% party dodge for the rest of the fight (60%% at most).") % p.call(v)
		"escalate_surge": n = TranslationServer.translate("The party's damage grows %d%% more each round for the rest of the fight.") % p.call(v)
		"counter_surge": n = TranslationServer.translate("+%d%% chance to counter-attack for the rest of the fight (60%% at most).") % p.call(v)
		"wipe_guard_surge": n = TranslationServer.translate("+%d%% chance the last hero standing survives a killing blow, once this fight (90%% at most).") % p.call(v)
		"self_sac_burst": n = TranslationServer.translate("Costs 15%% of this hero's max HP; hits the weakest foe for %d%% of the party's damage.") % p.call(v)
		"debuff_lowest": n = TranslationServer.translate("The weakest foe deals %d%% less damage for the rest of the fight.") % p.call(1.0 - v)
		"team_shield_burst": n = TranslationServer.translate("Shields every ally for %d%% of their max HP.") % p.call(v)
		"execute_all_low": n = TranslationServer.translate("Hits every foe below half health for %d-%d%% of the party's damage.") % [p.call(v * 1.5), p.call(v * 2.0)]
		"stun_strike": n = TranslationServer.translate("Hits the target for %d%% of the party's damage and stuns it (a boss only loses a wind-up).") % p.call(v)
		"freeze_target": n = TranslationServer.translate("The target loses its next 2 actions and any wind-up (a boss: 1 action).")
		"execute_threshold": n = TranslationServer.translate("Finishes off a foe below 35%% HP (not a boss); otherwise hits it for %d%% of the party's damage.") % p.call(v)
		"armor_break": n = TranslationServer.translate("Strips the target's armor and wards; it takes +15%% damage for the fight, and is hit for %d%% of the party's damage.") % p.call(v * 0.5)
		"mark_target": n = TranslationServer.translate("The target takes +%d%% damage for the rest of the fight.") % p.call(v)
		"double_strike": n = TranslationServer.translate("Two hits on the target, each %d%% of this hero's attack.") % p.call(v)
		"burn_all": n = TranslationServer.translate("Every foe burns for %d rounds, each round for %d%% of the party's damage.") % [MONSTER_BURN_ROUNDS, p.call(v * 0.5)]
		"chain_lightning": n = TranslationServer.translate("3 strikes on random foes, each %d%% of the party's damage.") % p.call(v)
		"ward_break": n = TranslationServer.translate("Strips every foe's armor and wards and hits each for %d%% of the party's damage.") % p.call(v * 0.5)
		"riposte": n = TranslationServer.translate("This hero answers the next 3 blows with %d%% of the party's damage.") % p.call(v)
		"taunt_ward": n = TranslationServer.translate("Every foe attacks this hero this round, for 30%% less; they gain a shield of %d%% of their max HP.") % p.call(v)
		"undying": n = TranslationServer.translate("This hero can't fall this round.")
		"revive": n = TranslationServer.translate("Raises a fallen ally with %d%% of their max HP.") % p.call(v)
		"hp_drain_burst": n = TranslationServer.translate("Hits the weakest foe for %d%% of the party's damage and heals this hero for 40%% of it.") % p.call(v)
		"trap": n = TranslationServer.translate("The next foe to attack loses that attack and takes %d%% of the party's damage.") % p.call(v)
		"mend_shield_hybrid": n = TranslationServer.translate("Heals the lowest-HP ally for %d%% of max HP and shields them for %d%%.") % [p.call(v), p.call(v * 0.6)]
		"cleanse_heal": n = TranslationServer.translate("Heals every ally for %d%% of max HP and clears their burns, poisons and curses.") % p.call(v)
		"shield_wall_front": n = TranslationServer.translate("Shields every front-row ally for %d%% of their max HP.") % p.call(v)
	var d := TranslationServer.translate(str(ab.get("desc", "")))
	return d if n == "" else "%s %s" % [d, n]


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
		"effects": [{"trigger": "on_kill", "effect": "gain_momentum", "value": 1.0}]},
	"cleric": {"name": "Beacon", "arch": "sustain", "icon": "res://assets/skills/potion_blue.png",
		"effects": [{"trigger": "on_kill", "effect": "mend_party", "value": 0.05}]},
	"rogue": {"name": "Opportunist", "arch": "executioner", "icon": "res://assets/skills/dagger_blue.png",
		"effects": [{"trigger": "on_kill", "effect": "extra_turn", "value": 1.0}]},
}

## The keystone for `kind`'s tree as a full skill node, or {}.
## Two more Tier-5 nodes in every tree, earned outside SP alone:
## "stonebound" also costs Crystals (STONEBOUND_CRYSTALS) and makes the hero's Active
## Ability hit harder; "riftborn" needs the guild to have sealed a ranked
## rift of RIFTBORN_MIN_RANK or higher, and adds 40% of the tree's capstone
## stat. (A skill respec refunds the SP, never the stone.)
const RIFTBORN_MIN_RANK := "C"


static func rift_nodes(kind: String) -> Array:
	var cap_val := 0.0
	for n in KIND_SKILL_PACKAGE.get(kind, []):
		if n["id"] == "cap":
			cap_val = float(n["value"])
	return [
		{"id": "stonebound", "tier": 5, "req_level": 6, "cost": 1, "kind": "ability_power", "value": 0.25,
			"name": "Stonebound Ability", "requires": [], "requires_any": KEYSTONE_REQUIRES_ANY, "stone": true,
			"icon": "res://assets/skills/gem_red.png"},
		{"id": "riftborn", "tier": 5, "req_level": 5, "cost": 1, "kind": kind, "value": snappedf(cap_val * 0.4, 0.01),
			"name": "Riftborn", "requires": [], "rift_rank": RIFTBORN_MIN_RANK,
			"icon": "res://assets/skills/eye_gem.png"},
	]


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

## The "stonebound" skill node costs this many Crystals on top of its SP.
const STONEBOUND_CRYSTALS := 40

# Ability Awakening — a second SP sink (GameState.awaken_ability) alongside
# the skill tree: spend SP once to make a hero's existing Active Ability do
# something extra, instead of only ever making the tree's numbers bigger.
# The bonus is bucketed by effect *category*, not the tree's usual "bigger
# number" — 5 buckets covering all 18 SUBCLASS_ABILITIES effect ids, so
# awakened abilities genuinely diverge from their un-awakened siblings
# without needing 18 fully bespoke riders (Combat.resolve_round applies each
# bucket's rider once, right after the primary effect resolves).
const ABILITY_AWAKENING_COST := 3
const ABILITY_AWAKENING_MOMENTUM := 2  # "buff" bucket's rider: Momentum refunded
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
	# The signature effects.
	"stun_strike": "single_dmg", "execute_threshold": "single_dmg", "armor_break": "single_dmg", "double_strike": "single_dmg",
	"burn_all": "aoe_dmg", "chain_lightning": "aoe_dmg", "ward_break": "aoe_dmg",
	"taunt_ward": "support", "undying": "support", "revive": "support", "shield_wall_front": "support", "cleanse_heal": "support",
	"riposte": "buff", "evasion_round": "buff", "lifesteal_surge": "buff", "blood_price": "buff",
	"mark_target": "utility", "trap": "utility", "freeze_target": "utility",
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


# Recruitment-screen reroll fee. Flat rather than rank-scaled, so a bad
# opening pull is always cheap to retry (below even the F-rank recruit cost).
const RECRUIT_REROLL_COST := 20


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
const CHAMP_KIND_BASE := {
	"dmg_pct": 0.06, "hp_pct": 0.06, "first_round_pct": 0.15, "escalate_pct": 0.02,
	"mend_pct": 0.03, "dodge_pct": 0.08, "hazard_guard_pct": 0.10, "wipe_guard": 0.2, "boss_alpha_strike": 1.0,
}


# ---------------- Momentum and role skills ----------------
## Momentum: the party's shared pool for skills in a fight. Basic attacks,
## kills and taking hits while Defending or Guarding build it; role skills
## and subclass Abilities spend it.
const MOMENTUM_MAX := 10
const MOMENTUM_START := 3
const ABILITY_MOMENTUM_COST := 4
## Melee roles hit at half strength with a basic attack from the back row.
const MELEE_ROLES := ["warrior", "rogue"]
const BACK_ROW_MELEE_MULT := 0.5

## Two skills per role (the first at Lv1, the second at Lv6), on top of the
## subclass Ability at Lv3. "row": where the hero must stand ("any" = either).
## "target": "foe" skills hit the picked foe; "none" need no pick. Damage
## values are multiples of the hero's own basic attack.
const ROLE_SKILLS := {
	"warrior": [
		{"id": "shield_bash", "name": "Shield Bash", "level": 1, "cost": 2, "row": "front", "target": "foe", "effect": "bash", "value": 1.1,
			"icon": "res://assets/skills/shield_orange.png", "desc": "Hits the target for 110% and stuns it: it loses its next action and any wind-up. Bosses only lose a wind-up, and a foe stunned this round or last shakes it off."},
		{"id": "taunt", "name": "Taunt", "level": 6, "cost": 3, "row": "front", "target": "none", "effect": "taunt", "value": 0.3,
			"icon": "res://assets/skills/helm.png", "desc": "Every foe aims its attacks at this hero until the round ends, and this hero takes 30% less from them."},
	],
	"ranger": [
		{"id": "aimed_shot", "name": "Aimed Shot", "level": 1, "cost": 2, "row": "back", "target": "foe", "effect": "pierce", "value": 1.8,
			"icon": "res://assets/skills/eye_gem.png", "desc": "A 180% shot at the target that ignores armor and wards."},
		{"id": "volley", "name": "Volley", "level": 6, "cost": 3, "row": "back", "target": "none", "effect": "volley", "value": 0.7,
			"icon": "res://assets/skills/shard_green.png", "desc": "Hits every foe for 70%."},
	],
	"mage": [
		{"id": "arcane_bolt", "name": "Arcane Bolt", "level": 1, "cost": 2, "row": "any", "target": "foe", "effect": "strike", "value": 1.7,
			"icon": "res://assets/skills/gem_blue_a.png", "desc": "A 170% bolt at the target."},
		{"id": "frost_nova", "name": "Frost Nova", "level": 6, "cost": 4, "row": "any", "target": "none", "effect": "nova", "value": 0.6,
			"icon": "res://assets/skills/shard_blue.png", "desc": "Hits every foe for 60% and breaks every wind-up."},
	],
	"cleric": [
		{"id": "heal", "name": "Heal", "level": 1, "cost": 2, "row": "any", "target": "none", "effect": "heal", "value": 0.3,
			"icon": "res://assets/skills/potion_red.png", "desc": "Heals the most-hurt ally for 30% of their max HP."},
		{"id": "sanctuary", "name": "Sanctuary", "level": 6, "cost": 3, "row": "any", "target": "none", "effect": "sanctuary", "value": 0.15,
			"icon": "res://assets/skills/heart.png", "desc": "Wards every ally for 15% of their max HP and cleanses burn, poison, chill, stun and curses."},
	],
	"rogue": [
		{"id": "backstab", "name": "Backstab", "level": 1, "cost": 2, "row": "front", "target": "foe", "effect": "backstab", "value": 1.5,
			"icon": "res://assets/skills/dagger_red.png", "desc": "Hits the target for 150%, or 250% if it is winding up or below half health."},
		{"id": "smoke_bomb", "name": "Smoke Bomb", "level": 6, "cost": 3, "row": "any", "target": "none", "effect": "smoke", "value": 0.3,
			"icon": "res://assets/skills/cloak_a.png", "desc": "+30% dodge for the whole party until the round ends."},
	],
}


## The role skills `h` has learned by level.
static func hero_role_skills(h: Hero) -> Array:
	return (ROLE_SKILLS.get(h.cls_id, []) as Array).filter(func(sk): return h.level >= int(sk["level"]))


static func find_role_skill(id: String) -> Dictionary:
	for role in ROLE_SKILLS:
		for sk in ROLE_SKILLS[role]:
			if sk["id"] == id:
				return sk
	return {}


## Archetype twists: a hero's main archetype (Combat.hero_main_arch) adds a
## rider to every role skill they use.
const ARCH_TWIST := {
	"guardian": "also wards the most-hurt ally for 10% of their max HP",
	"sustain": "also heals this hero 10% of their max HP",
	"evasion": "and this hero dodges the next hit aimed at them",
	"attrition": "and the target burns for two rounds",
	"opener": "the first skill each fight hits 50% harder",
	"executioner": "+50% damage against foes below 40% HP",
}
const TWIST_WARD := 0.10
const TWIST_HEAL := 0.10
const TWIST_BURN := 0.3      # of the hero's hit, per round, two rounds
const TWIST_OPENER := 0.5
const TWIST_EXECUTE := 0.5
const TWIST_EXECUTE_BELOW := 0.4
const MONSTER_BURN_ROUNDS := 3

