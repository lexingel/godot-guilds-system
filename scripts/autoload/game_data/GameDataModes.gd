extends "res://scripts/autoload/game_data/GameDataSkills.gd"
## GameData, part 6: run boons, Tower of Trials, difficulties, rift events, rift ranks, Guild Management and Orders, the hamlet, features, campaign, quests, milestones, the Daily Rift.

## ---------------- Run boons ----------------
## Picked after an elite win (1 of 3), kept for the rest of that rift only.
## Each is a stat ("kind"/"value", read through Combat.boon_total) or a relic-
## style trigger (fired with the party's relic triggers). Owning 2 / 4 of a
## family adds its set bonus.
const BOON_FAMILIES := {
	"ember": {"name": "Ember", "icon": "res://assets/relics/escalate_pct.png", "color": Color(1.0, 0.55, 0.25)},
	"frost": {"name": "Frost", "icon": "res://assets/skills/shard_blue.png", "color": Color(0.55, 0.85, 1.0)},
	"blood": {"name": "Blood", "icon": "res://assets/skills/potion_red.png", "color": Color(0.9, 0.25, 0.3)},
	"steel": {"name": "Steel", "icon": "res://assets/skills/shield_basic.png", "color": Color(0.75, 0.78, 0.85)},
	"storm": {"name": "Storm", "icon": "res://assets/skills/wing.png", "color": Color(0.7, 0.6, 1.0)},
	"shadow": {"name": "Shadow", "icon": "res://assets/skills/dagger_red.png", "color": Color(0.6, 0.4, 0.75)},
	"holy": {"name": "Holy", "icon": "res://assets/skills/star.png", "color": Color(1.0, 0.9, 0.5)},
}
const BOONS := [
	{"id": "kindling", "family": "ember", "name": "Kindling", "desc": "+3% party damage every round (stacking).", "kind": "escalate_pct", "value": 0.03},
	{"id": "blaze", "family": "ember", "name": "Blaze", "desc": "+12% party damage.", "kind": "dmg_pct", "value": 0.12},
	{"id": "pyre", "family": "ember", "name": "Pyre Burst", "desc": "Every third round, fire strikes every foe for 35% of party damage.", "trigger": {"trigger": "round_third", "effect": "nova", "value": 0.35}},
	{"id": "rime", "family": "frost", "name": "Rime Coat", "desc": "+8% dodge.", "kind": "dodge_pct", "value": 0.08},
	{"id": "frostbite", "family": "frost", "name": "Frostbite", "desc": "Evading or taking a heavy hit weakens the attacker.", "trigger": {"trigger": "evade_or_heavy", "effect": "weaken_attacker", "value": 0.12}},
	{"id": "ice_ward", "family": "frost", "name": "Ice Ward", "desc": "Every third round, shield the party for 8% of max HP.", "trigger": {"trigger": "round_third", "effect": "shield_party", "value": 0.08}},
	{"id": "leech", "family": "blood", "name": "Leech", "desc": "Hits heal the attacker for 8% of the damage.", "trigger": {"trigger": "after_hit", "effect": "lifesteal", "value": 0.08}},
	{"id": "frenzy", "family": "blood", "name": "Frenzy", "desc": "+10% party damage.", "kind": "dmg_pct", "value": 0.10},
	{"id": "feast", "family": "blood", "name": "Feast", "desc": "Each kill mends the party for 6% of max HP.", "trigger": {"trigger": "on_kill", "effect": "mend_party", "value": 0.06}},
	{"id": "riposte", "family": "steel", "name": "Riposte", "desc": "+20% chance to counter when evading or hit hard.", "kind": "counter_pct", "value": 0.20},
	{"id": "bulwark", "family": "steel", "name": "Bulwark", "desc": "20% chance to take a hit meant for a wounded ally.", "trigger": {"trigger": "ally_targeted", "effect": "intercept", "value": 0.20}},
	{"id": "tempered", "family": "steel", "name": "Tempered", "desc": "Once a fight, survive a wipe at 25% HP.", "kind": "wipe_guard", "value": 0.25},
	{"id": "surge", "family": "storm", "name": "Surge", "desc": "+30% first-strike damage.", "kind": "first_round_pct", "value": 0.30},
	{"id": "static", "family": "storm", "name": "Static", "desc": "+30% chance to cool abilities when evading or hit hard.", "kind": "cooldown_shave_pct", "value": 0.30},
	{"id": "chain", "family": "storm", "name": "Chain Lightning", "desc": "Each kill arcs lightning into every foe for 30% of party damage.", "trigger": {"trigger": "on_kill", "effect": "nova", "value": 0.30}},
	{"id": "reaper", "family": "shadow", "name": "Reaper", "desc": "Hits finish off foes left below 12% HP.", "trigger": {"trigger": "before_hit", "effect": "execute_below", "value": 0.12}},
	{"id": "ambush", "family": "shadow", "name": "Ambush", "desc": "+40% opening volley against bosses.", "kind": "boss_alpha_strike", "value": 0.40},
	{"id": "veil", "family": "shadow", "name": "Veil", "desc": "+6% dodge and +6% party damage.", "kind": "dodge_pct", "value": 0.06, "kind2": "dmg_pct", "value2": 0.06},
	{"id": "grace", "family": "holy", "name": "Grace", "desc": "Mends 3% HP every round.", "kind": "mend_pct", "value": 0.03},
	{"id": "aegis", "family": "holy", "name": "Aegis", "desc": "Each kill shields the weakest ally for 12% of max HP.", "kind": "kill_shield_pct", "value": 0.12},
	{"id": "hymn", "family": "holy", "name": "Hymn", "desc": "Every third round, mend the party for 5% of max HP.", "trigger": {"trigger": "round_third", "effect": "mend_party", "value": 0.05}},
]

## Set bonuses: [pieces, bonus] per family, same shape as a boon.
const BOON_SETS := {
	"ember": [[2, {"name": "Ember ×2", "desc": "+8% party damage.", "kind": "dmg_pct", "value": 0.08}], [4, {"name": "Inferno", "desc": "Every third round, fire hits every foe for 60% of party damage.", "trigger": {"trigger": "round_third", "effect": "nova", "value": 0.6}}]],
	"frost": [[2, {"name": "Frost ×2", "desc": "+6% dodge.", "kind": "dodge_pct", "value": 0.06}], [4, {"name": "Glacier", "desc": "Every third round, shield the party for 15%.", "trigger": {"trigger": "round_third", "effect": "shield_party", "value": 0.15}}]],
	"blood": [[2, {"name": "Blood ×2", "desc": "Mends 2% HP every round.", "kind": "mend_pct", "value": 0.02}], [4, {"name": "Crimson Pact", "desc": "Hits heal for 15% of the damage.", "trigger": {"trigger": "after_hit", "effect": "lifesteal", "value": 0.15}}]],
	"steel": [[2, {"name": "Steel ×2", "desc": "+10% counter chance.", "kind": "counter_pct", "value": 0.10}], [4, {"name": "Iron Wall", "desc": "Each kill shields the weakest ally for 20%.", "kind": "kill_shield_pct", "value": 0.20}]],
	"storm": [[2, {"name": "Storm ×2", "desc": "+15% first-strike damage.", "kind": "first_round_pct", "value": 0.15}], [4, {"name": "Tempest", "desc": "Evading or taking a heavy hit can grant an extra turn.", "trigger": {"trigger": "evade_or_heavy", "effect": "extra_turn", "value": 0.25}}]],
	"shadow": [[2, {"name": "Shadow ×2", "desc": "+6% party damage.", "kind": "dmg_pct", "value": 0.06}], [4, {"name": "Deathmark", "desc": "Hits finish off foes below 20% HP.", "trigger": {"trigger": "before_hit", "effect": "execute_below", "value": 0.20}}]],
	"holy": [[2, {"name": "Holy ×2", "desc": "Mends 2% HP every round.", "kind": "mend_pct", "value": 0.02}], [4, {"name": "Sanctuary", "desc": "Once a fight, survive a wipe at 30% HP.", "kind": "wipe_guard", "value": 0.30}]],
}
const BOON_OFFER_SIZE := 3


static func find_boon(id: String) -> Dictionary:
	for b in BOONS:
		if b["id"] == id:
			return b
	return {}

## ---------------- Tower of Trials ----------------
## 100 fixed floors, one fight each (GameState.tower_floor_info). Every floor
## is always the same fight, so a loss is something to plan around rather
## than reroll. Heroes fight at full HP and leave as they came (no downing, no
## injuries, no time passing); only the first clear of a floor pays.
const TOWER_FLOORS := 100
const TOWER_WEEKLY_FROM := 91   # floors 91-100: rules reshuffle weekly, re-clearable each week
const TOWER_HP_GROWTH := 0.027  # foes' HP/damage grow this much per floor (compounding)
const TOWER_DMG_GROWTH := 0.0255
const TOWER_BASE := {"monster_hp": 118, "monster_dmg": 13}
const TOWER_FIGHT_DEPTH := 2    # gen_monster's floor_idx for every tower fight

## Floor rules: each is a diff key read by Combat (gen_monster/gen_monsters/
## _start_round), or a party cap read by Party Assembly.
const TOWER_RULES := [
	{"id": "ironclad", "name": "Ironclad", "desc": "Every foe is armored (at least 30% of basic attacks shrugged off). Abilities ignore armor.", "diff": {"tower_armor": 0.3}},
	{"id": "scorching", "name": "Scorching", "desc": "Every foe's hits can set a hero ablaze.", "diff": {"tower_status": "burn"}},
	{"id": "frostbound", "name": "Frostbound", "desc": "Every foe's hits can chill a hero (acts late).", "diff": {"tower_status": "chill"}},
	{"id": "swarm", "name": "Swarm", "desc": "Extra foes join the fight.", "diff": {"tower_swarm": true}},
	{"id": "brutal", "name": "Brutal", "desc": "Every foe winds up heavy blows far more often. Defend!", "diff": {"windup_bonus": 0.35}},
	{"id": "colossus", "name": "Colossus", "desc": "A single foe with double health.", "diff": {"tower_single": true}},
	{"id": "glass", "name": "Glass Cannon", "desc": "Foes hit 40% harder but have 30% less health.", "diff": {"hp_mult": 0.7, "dmg_mult": 1.4}},
	{"id": "bulwark", "name": "Bulwark", "desc": "Foes have 50% more health but hit 20% softer.", "diff": {"hp_mult": 1.5, "dmg_mult": 0.8}},
	{"id": "trio", "name": "Trio", "desc": "At most 3 heroes (plus the Champion).", "party_cap": 3},
	{"id": "duo", "name": "Duo", "desc": "At most 2 heroes (plus the Champion).", "party_cap": 2},
]

## Every 10th floor: a named guardian with fixed mechanics and a Tower relic.
const TOWER_BOSSES := {
	10: {"name": "The Gatekeeper", "biome": "vale", "mechanics": ["warded"], "line": "An iron sentinel bars the first gate."},
	20: {"name": "Mirelord Oskan", "biome": "marsh", "mechanics": ["regen"], "line": "The flooded stair has a keeper, and it does not tire."},
	30: {"name": "Cindermaw", "biome": "ashen", "mechanics": ["frenzied"], "line": "Heat pours down from the thirtieth landing."},
	40: {"name": "The Hollow Choir", "biome": "vale", "mechanics": ["enrage"], "line": "Voices echo from every wall, louder by the moment."},
	50: {"name": "Tidewarden Selk", "biome": "marsh", "mechanics": ["warded", "regen"], "line": "Halfway up, the tower tests your patience."},
	60: {"name": "The Ember Regent", "biome": "ashen", "mechanics": ["frenzied", "enrage"], "line": "A crowned flame waits on its throne."},
	70: {"name": "Gravewright Mourn", "biome": "vale", "mechanics": ["regen", "enrage"], "line": "Whatever falls here, it stitches back together."},
	80: {"name": "The Drowned Oracle", "biome": "marsh", "mechanics": ["warded", "frenzied"], "line": "It has already seen how this fight ends."},
	90: {"name": "Ashfather", "biome": "ashen", "mechanics": ["frenzied", "regen"], "line": "The oldest fire in the tower."},
	100: {"name": "The Summit Keeper", "biome": "ashen", "mechanics": ["warded", "enrage"], "line": "The top of the tower. No one has stood here in an age."},
}

## Guild titles for reaching a floor (the highest shows beside the guild name).
const TOWER_TITLES := [[10, "Tower Initiate"], [25, "Trial Climber"], [50, "Spire Walker"], [75, "Stormbreaker"], [100, "Summit Keeper"]]

# Lesser and Greater Rift are the two selectable DIFFICULTIES tiers (the
# Endless Rift is a survival mode, scripts/survivors).
const DIFFICULTIES := [
	{"id": "lesser", "name": "Lesser Rift", "floors": 7, "monster_hp": 20, "monster_dmg": 2.6, "coin": [18, 34], "crystal": [5, 11], "seal_essence": 10, "cache_chance": 0.08, "power": "Low", "rec_power": 48},
	# Unlocked by GameState.greater_rift_unlocked() (seal 3 rifts) rather than
	# Guild Management currency — sits between Lesser and the Ascendant-
	# First-draft numbers, tunable after playing.
	{"id": "greater", "name": "Greater Rift", "floors": 8, "monster_hp": 80, "monster_dmg": 8.6, "coin": [40, 70], "crystal": [11, 20], "seal_essence": 18, "cache_chance": 0.14, "power": "Medium", "rec_power": 118},
]

## The power the Rift Hall compares against for the Endless Rift (survivors).
const ENDLESS_REC_POWER := 280

## Rift Map ranks — reuses the hero-rank vocabulary (F-S) extended with two
## rarer tiers (SS/SSS) for the map's random rift rolls. Weights preserve the
## exact same relative odds as hero RANKS for F-S (just rescaled ×10 for the
## finer granularity SS/SSS need); fuse_runs is how many rift runs (or rests)
## a rift stays open before an unaddressed one Riftbreaks — shorter at higher
## rank, so a rare S/SS/SSS sighting is genuinely fleeting.
## Recovery in rift runs rather than real time: a downed hero sits out this
## many runs (Medical upgrades shorten it, a bed takes one off), and a wounded
## hero regains this share of max HP each time a run ends (all of it in a bed).
## Rift events: a short scene with 2-3 choices, each stating its outcome up
## front (odds included). Effect keys, applied by GameState.resolve_event:
## coins/crystals/reputation (int, or [min, max]), xp_all, heal_pct / hurt_pct
## (of each living hero's max HP; events never knock anyone out), ready (all
## abilities off cooldown), loot (minimum rarity). "cost" is paid first and
## must be affordable; "gamble" = {chance, win: effect, lose: effect}.
const RIFT_EVENTS := [
	{"id": "traveler", "name": "A Wounded Traveler", "text": "A scout from another guild lies bleeding against the wall, clutching a torn map.",
		"choices": [
			{"label": "Patch them up", "desc": "Costs 15 Gold · +3 Renown", "cost": {"coins": 15}, "effect": {"reputation": 3}},
			{"label": "Ask for the map", "desc": "+6-12 Essence", "effect": {"crystals": [6, 12]}},
			{"label": "Move on", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "altar", "name": "Blood Altar", "text": "An altar hums with rift-light. It wants something from you.",
		"choices": [
			{"label": "Offer blood", "desc": "Every hero loses 15% HP (never below 1) · gain a Rare-or-better item or relic", "effect": {"hurt_pct": 0.15, "loot": "rare"}},
			{"label": "Walk away", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "cache", "name": "Abandoned Cache", "text": "Supplies left behind by a party that didn't make it out.",
		"choices": [
			{"label": "Search it all", "desc": "70%: 20-35 Gold · 30%: a trap hits everyone for 10% HP", "gamble": {"chance": 0.7, "win": {"coins": [20, 35]}, "lose": {"hurt_pct": 0.10}}},
			{"label": "Take what's on top", "desc": "+8 Gold", "effect": {"coins": 8}},
		]},
	{"id": "echo", "name": "Rift Echo", "text": "Shimmering memories of old battles replay in the air around you.",
		"choices": [
			{"label": "Study the fighting", "desc": "Every hero in the party gains 20 XP", "effect": {"xp_all": 20}},
			{"label": "Absorb its energy", "desc": "All abilities ready · +5 Essence", "effect": {"ready": true, "crystals": 5}},
		]},
	{"id": "gambler", "name": "The Gambler", "text": "A cloaked figure shuffles cards on an upturned crate and grins at you.",
		"choices": [
			{"label": "Bet 20 Gold", "desc": "50%: win 45 Gold (net +25) · 50%: lose the bet", "cost": {"coins": 20}, "gamble": {"chance": 0.5, "win": {"coins": 45}, "lose": {}}},
			{"label": "Decline", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "shrine", "name": "Quiet Shrine", "text": "A small shrine the rift somehow left untouched. The air is calm here.",
		"choices": [
			{"label": "Pray", "desc": "Every hero heals 20% HP", "effect": {"heal_pct": 0.20}},
			{"label": "Take the offerings", "desc": "+6-12 Essence · -1 Renown", "effect": {"crystals": [6, 12], "reputation": -1}},
		]},
	{"id": "armory", "name": "Collapsed Armory", "text": "A rack of weapons lies pinned under fallen stone. Something good might still be under there.",
		"choices": [
			{"label": "Lift the rubble", "desc": "Might check · pass: a Rare-or-better item · fail: everyone loses 10% HP", "check": {"attr": "might", "target": 9, "win": {"item": "rare"}, "lose": {"hurt_pct": 0.10}}},
			{"label": "Leave it", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "tome", "name": "Whispering Tome", "text": "A book floats open in the dark, murmuring techniques in a language almost like yours.",
		"choices": [
			{"label": "Read it", "desc": "Focus check · pass: every hero gains 40 XP · fail: everyone loses 10% HP", "check": {"attr": "focus", "target": 9, "win": {"xp_all": 40}, "lose": {"hurt_pct": 0.10}}},
			{"label": "Burn it", "desc": "+6 Essence", "effect": {"crystals": 6}},
		]},
	{"id": "bridge", "name": "Frayed Rope Bridge", "text": "A rope bridge sways over a chasm. On the far side, a dead scout's pack.",
		"choices": [
			{"label": "Cross quickly", "desc": "Agility check · pass: +20-35 Gold · fail: everyone loses 15% HP", "check": {"attr": "agility", "target": 8, "win": {"coins": [20, 35]}, "lose": {"hurt_pct": 0.15}}},
			{"label": "Go around", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "ember_pit", "name": "Ember Pit", "text": "Something glints at the bottom of a pit of still-glowing coals.",
		"choices": [
			{"label": "Reach in", "desc": "Everyone loses 15% HP · a Rare-or-better relic", "effect": {"hurt_pct": 0.15, "relic": "rare"}},
			{"label": "Leave it", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "frozen_knight", "name": "Frozen Knight", "text": "A knight from another guild, frozen mid-stride in rift-ice. Still breathing.",
		"choices": [
			{"label": "Thaw them out", "desc": "Costs 15 Gold · +3 Renown · every ability ready", "cost": {"coins": 15}, "effect": {"reputation": 3, "ready": true}},
			{"label": "Take their shield", "desc": "A Rare-or-better item · -2 Renown", "effect": {"item": "rare", "reputation": -2}},
			{"label": "Move on", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "blood_pool", "name": "Crimson Pool", "text": "A pool of something thick and red. Drinking it would teach you things. Painful things.",
		"choices": [
			{"label": "Drink", "desc": "Everyone loses 20% HP · every hero gains 40 XP", "effect": {"hurt_pct": 0.20, "xp_all": 40}},
			{"label": "Bottle some", "desc": "+1 Field Tonic", "effect": {"tonic": 1}},
		]},
	{"id": "anvil", "name": "Singing Anvil", "text": "An anvil that rings on its own. A smith's ghost offers to work it, for a price.",
		"choices": [
			{"label": "Pay the smith", "desc": "Costs 25 Gold · an Epic item", "cost": {"coins": 25}, "effect": {"item": "epic"}},
			{"label": "Sell the scrap", "desc": "+12 Gold", "effect": {"coins": 12}},
		]},
	{"id": "storm_totem", "name": "Storm Totem", "text": "A totem crackles with trapped lightning. Channelled right, it could charge your party.",
		"choices": [
			{"label": "Channel it", "desc": "Focus check · pass: +12-20 Essence, every ability ready · fail: everyone loses 10% HP", "check": {"attr": "focus", "target": 10, "win": {"crystals": [12, 20], "ready": true}, "lose": {"hurt_pct": 0.10}}},
			{"label": "Leave it", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "shade", "name": "A Hungry Shade", "text": "A shade drifts toward you, hungry for anything bright: gold, light, warmth.",
		"choices": [
			{"label": "Feed it gold", "desc": "Costs 20 Gold · +3 Essence", "cost": {"coins": 20}, "effect": {"crystals": 3}},
			{"label": "Drive it off", "desc": "Everyone loses 10% HP · +10 Essence", "effect": {"hurt_pct": 0.10, "crystals": 10}},
			{"label": "Flee", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "chapel", "name": "Ruined Chapel", "text": "Half a chapel, the other half somewhere in the rift. The altar still holds warmth.",
		"choices": [
			{"label": "Restore the altar", "desc": "Costs 20 Gold · every hero heals 50% HP · +2 Renown", "cost": {"coins": 20}, "effect": {"heal_pct": 0.5, "reputation": 2}},
			{"label": "Rest a while", "desc": "Every hero heals 20% HP", "effect": {"heal_pct": 0.20}},
		]},
	{"id": "peddler", "name": "Ghostly Peddler", "text": "A translucent merchant lays out wares that flicker in and out of existence.",
		"choices": [
			{"label": "Buy a curiosity", "desc": "Costs 30 Gold · an Epic item or relic", "cost": {"coins": 30}, "effect": {"loot": "epic"}},
			{"label": "Trade stories", "desc": "Every hero gains 12 XP", "effect": {"xp_all": 12}},
		]},
	{"id": "caged_beast", "name": "Caged Beast", "text": "A rift beast in a cage of runes, whimpering. The rune-lock is simple enough.",
		"choices": [
			{"label": "Free it", "desc": "55%: it bounds off grateful · +4 Renown, +2 Essence · 45%: it lashes out, everyone loses 15% HP", "gamble": {"chance": 0.55, "win": {"reputation": 4, "crystals": 2}, "lose": {"hurt_pct": 0.15}}},
			{"label": "Leave it", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "mirror", "name": "Rift Mirror", "text": "Your reflection moves a moment after you do. It seems to be showing you something.",
		"choices": [
			{"label": "Study it", "desc": "Focus check · pass: every ability ready, +25 XP each · fail: everyone loses 10% HP", "check": {"attr": "focus", "target": 9, "win": {"ready": true, "xp_all": 25}, "lose": {"hurt_pct": 0.10}}},
			{"label": "Smash it", "desc": "+8 Essence", "effect": {"crystals": 8}},
		]},
	{"id": "golem", "name": "Sleeping Golem", "text": "A stone golem dozes on top of a treasure chest. Its snores shake the floor.",
		"choices": [
			{"label": "Sneak the chest out", "desc": "Agility check · pass: +30-45 Gold and a Rare-or-better item or relic · fail: everyone loses 20% HP", "check": {"attr": "agility", "target": 10, "win": {"coins": [30, 45], "loot": "rare"}, "lose": {"hurt_pct": 0.20}}},
			{"label": "Let it sleep", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "lost_recruit", "name": "Lost Recruit", "text": "A young recruit from a village guild, lost and terrified, clutching a rusted sword.",
		"choices": [
			{"label": "Escort them out", "desc": "Every hero loses 5% HP · +4 Renown, +1 Essence", "effect": {"hurt_pct": 0.05, "reputation": 4, "crystals": 1}},
			{"label": "Point the way", "desc": "+1 Renown", "effect": {"reputation": 1}},
		]},
	{"id": "fungus", "name": "Glowing Fungus", "text": "Pale mushrooms pulse with soft light. They smell faintly of mint and ozone.",
		"choices": [
			{"label": "Eat some", "desc": "60%: every hero heals 30% HP and gains 15 XP · 40%: everyone loses 10% HP", "gamble": {"chance": 0.6, "win": {"heal_pct": 0.3, "xp_all": 15}, "lose": {"hurt_pct": 0.10}}},
			{"label": "Harvest them", "desc": "+6 Essence", "effect": {"crystals": 6}},
		]},
	{"id": "crossroads", "name": "Rift Crossroads", "text": "Two paths: one dives deeper into raw rift energy, one leads to a quiet alcove.",
		"choices": [
			{"label": "Push deeper", "desc": "Everyone loses 8% HP · +10-16 Essence", "effect": {"hurt_pct": 0.08, "crystals": [10, 16]}},
			{"label": "Regroup", "desc": "Every hero heals 15% HP · every ability ready", "effect": {"heal_pct": 0.15, "ready": true}},
		]},
	{"id": "banner", "name": "Fallen Banner", "text": "A guild banner lies in the dust, its bearer long gone. The cloth is still good.",
		"choices": [
			{"label": "Raise it", "desc": "+3 Renown · a 20-point shield against the next hazard", "effect": {"reputation": 3, "shield": 20}},
			{"label": "Salvage it", "desc": "+10 Gold", "effect": {"coins": 10}},
		]},
]

## Attribute checks in events: the party's best score in the attribute vs
## the target (+3 outside Lesser rifts) sets the chance to pass.
const EVENT_CHECK_BASE := 0.5
const EVENT_CHECK_PER_POINT := 0.1
const EVENT_CHECK_PER_LEVEL := 1.4   # target rises with the party's average level

## Campfire: heal share for Rest, XP for Train.
const CAMPFIRE_HEAL_PCT := 0.25
const CAMPFIRE_TRAIN_XP := 15
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

# Every kind that can appear on a hero build (skills/items/relics/traits/innate).
const BUILD_KINDS := ["dmg_pct", "hp_pct", "speed_pct", "first_round_pct", "escalate_pct", "mend_pct", "hazard_guard_pct", "dodge_pct", "ability_power", "wipe_guard", "boss_alpha_strike"]

# Guild Management: 4 branches, 9 upgrades of 5 levels. Every level adds the
# node's "every" effect (numbers from Combat.describe_node_effect); the
# "perks" levels unlock something new (Lv2 perks marked "Order:" are Guild
# Orders, used once per rift). Costs: cost_base + cost_step * current level.
const BRANCHES := [
	{"id": "ops", "name": "Operations Branch", "sub": "Heroes & Combat", "nodes": [
		{"id": "barracks", "name": "Barracks", "max": 5, "cost_base": 50, "cost_step": 50, "every": "+2 hero slots",
			"perks": {3: "Mentors: new recruits join 1 level higher", 5: "Veteran instructors: heroes earn +20% XP"}},
		{"id": "infirmary", "name": "Infirmary", "max": 5, "cost_base": 50, "cost_step": 50, "every": "-15% recovery time; a bed at Lv1/3/5",
			"perks": {2: "Order: Supply Drop — heal the party 35% between fights", 3: "Field Triage: once per rift, get a downed hero back up", 5: "Wounded heroes heal fully after every run"}},
		{"id": "drill", "name": "Drill Yard", "max": 5, "cost_base": 50, "cost_step": 50, "every": "+4% party damage and +4% max HP",
			"perks": {2: "Order: Rally — the party acts first this round and hits 30% harder", 3: "Vanguard: a fight's first strike deals +25% damage", 5: "Abilities are ready at the start of every fight"}},
	]},
	{"id": "infra", "name": "Infrastructure Branch", "sub": "Rift Yield & Safety", "nodes": [
		{"id": "amplifiers", "name": "Essence Amplifiers", "max": 5, "cost_base": 50, "cost_step": 50, "every": "+8% Essence from fights",
			"perks": {3: "Energy extraction: elites often drop bonus Essence", 5: "Resonance: bosses drop an Essence cache"}},
		{"id": "wardstones", "name": "Wardstones", "max": 5, "cost_base": 50, "cost_step": 50, "every": "-12% hazard damage, +10% Essence for sealing",
			"perks": {3: "Anchor: the first hazard of each rift is negated", 5: "Hazards can't knock a hero out"}},
	]},
	{"id": "log", "name": "Logistics Branch", "sub": "Trade & Recruiting", "nodes": [
		{"id": "trade", "name": "Trade Network", "max": 5, "cost_base": 50, "cost_step": 50, "every": "-6% shop prices, -2% auction fees, +5% Rift Cache chance",
			"perks": {2: "Order: Requisition — reroll a fight's loot choices", 3: "Black Market: Rift Caches hold 30% more Gold", 5: "Every rift shop stocks an Epic relic"}},
		{"id": "scouts", "name": "Scouts' Lodge", "max": 5, "cost_base": 50, "cost_step": 50, "every": "Recruit board: +1 offer at Lv1 and Lv4",
			"perks": {2: "Order: Scout Ahead — reroll the next fork's paths", 3: "Headhunter: every recruit refresh has a Rank C+ hero", 5: "Recruit rerolls cost half"}},
	]},
	{"id": "res", "name": "Research Branch", "sub": "Relics & Theory", "nodes": [
		{"id": "vault", "name": "Relic Vault", "max": 5, "cost_base": 50, "cost_step": 50, "every": "Starting relic choices (2 at Lv1, 3 at Lv2, 4 at Lv4)",
			"perks": {3: "+1 equipped relic slot", 5: "+1 more relic slot, and starting relics are Rare or better"}},
		{"id": "lab", "name": "Arcane Lab", "max": 5, "cost_base": 50, "cost_step": 50, "every": "+10% relic element-set bonuses; Lv1 unlocks relic scrapping and trait/scar removal",
			"perks": {3: "Skill respecs and quirk treatments cost 30% less", 5: "Relic upgrades cost 25% fewer Essence"}},
	]},
]

## What each Guild Order does and which node level unlocks it.
const GUILD_ORDERS := {
	"supply": {"name": "Supply Drop", "node": "ops.infirmary", "icon": "res://assets/skills/potion_red.png", "desc": "Heal every standing hero 35% of their max HP."},
	"rally": {"name": "Rally", "node": "ops.drill", "icon": "res://assets/skills/sword_slash.png", "desc": "This round the party acts before every foe and hits 30% harder."},
	"requisition": {"name": "Requisition", "node": "log.trade", "icon": "res://assets/skills/ingot_gold.png", "desc": "Reroll this fight's loot choices."},
	"scout": {"name": "Scout Ahead", "node": "log.scouts", "icon": "res://assets/skills/eye_gem.png", "desc": "Reroll the paths on the next fork."},
}
const ORDER_UNLOCK_LEVEL := 2

## Old tree (before save version 3): [cost_base, cost_step] per node and
## capstone costs — only used to refund a migrated save.
const OLD_MGMT_COSTS := {
	"ops.roster": [30, 20], "ops.medical": [25, 18], "ops.drill": [35, 22], "ops.trait": [40, 30],
	"infra.crystal": [30, 20], "infra.stab": [28, 18], "infra.seal": [45, 30], "infra.energy": [26, 16],
	"log.broker": [30, 20], "log.scout": [35, 25], "log.merchant": [24, 14], "log.cache": [32, 20],
	"res.relic": [30, 22], "res.theory": [28, 20], "res.recycle": [22, 14], "res.cart": [26, 16], "res.vault": [50, 40],
}
const OLD_MGMT_CAP_COSTS := {"ops.roster": 400, "ops.medical": 350, "ops.drill": 450, "infra.crystal": 400, "infra.stab": 380,
	"log.broker": 420, "log.scout": 400, "res.relic": 380, "res.theory": 400}
const GUILD_TIERS := [
	{"min": 0, "name": "Founding Guild"},
	{"min": 10, "name": "Established Guild"},
	{"min": 25, "name": "Renowned Guild"},
	{"min": 40, "name": "Legendary Guild"},
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
	"ops.barracks": "res://assets/skills/shield_basic.png",
	"ops.infirmary": "res://assets/skills/heart.png",
	"ops.drill": "res://assets/skills/sword_slash.png",
	"infra.amplifiers": "res://assets/skills/gem_blue_big.png",
	"infra.wardstones": "res://assets/skills/shield_blue.png",
	"log.trade": "res://assets/skills/ingot_gold.png",
	"log.scouts": "res://assets/skills/eye_gem.png",
	"res.vault": "res://assets/skills/shield_orange.png",
	"res.lab": "res://assets/skills/potion_blue.png",
}

## The camp hamlet: one building per system on a 400x180 native backdrop,
## back row first so the front row draws over it. "pos" is the bottom-centre.
## "tier" picks the art (assets/hamlet/<art>_t1..3.png): "node" = a Guild
## Management upgrade (T2 at Lv3, T3 at Lv5), "guild" = guild tier, "act" =
## campaign act, "" = one fixed image (<art>.png).
const HAMLET_BG := "res://assets/hamlet/backdrop.png"
const HAMLET_SIZE := Vector2(400, 180)
const HAMLET_BUILDINGS := [
	{"id": "scouts", "name": "Scouts' Lodge", "tier": "node", "node": "log.scouts", "pos": Vector2(62, 150), "row": "back"},
	{"id": "hall", "name": "Guild Hall", "tier": "guild", "pos": Vector2(200, 152), "row": "back"},
	{"id": "lab", "name": "Arcane Lab", "tier": "node", "node": "res.lab", "pos": Vector2(338, 150), "row": "back"},
	{"id": "barracks", "name": "Barracks", "tier": "node", "node": "ops.barracks", "pos": Vector2(32, 177), "row": "front"},
	{"id": "infirmary", "name": "Infirmary", "tier": "node", "node": "ops.infirmary", "pos": Vector2(96, 177), "row": "front"},
	{"id": "drill", "name": "Drill Yard", "tier": "node", "node": "ops.drill", "pos": Vector2(152, 177), "row": "front"},
	{"id": "campfire", "name": "", "tier": "", "pos": Vector2(200, 178), "row": "front"},
	{"id": "board", "name": "Quest Board", "tier": "", "pos": Vector2(234, 176), "row": "front"},
	{"id": "gate", "name": "Rift Gate", "tier": "act", "pos": Vector2(270, 177), "row": "front"},
	{"id": "market", "name": "Market", "tier": "node", "node": "log.trade", "pos": Vector2(322, 177), "row": "front"},
	{"id": "vault", "name": "Relic Vault", "tier": "node", "node": "res.vault", "pos": Vector2(374, 177), "row": "front"},
]
## Gold in a Rift Cache (a chance on sealing, DIFFICULTIES "cache_chance").
const RIFT_CACHE_GOLD := {"lesser": 70, "greater": 170}

## The very first rift is a shorter, gentler training rift.
## The campaign: three acts, each a region with a named foe. Meet an act's
## objectives (GameState.campaign_objective_progress) to open its finale — a
## harder rift whose boss is the act's foe. Sealing it completes the act,
## pays its reward and opens the next tier (Act I: Greater Rifts, Act II:
## Endless). After Act III the campaign is over and the rest is post-game.
const CAMPAIGN := [
	{"act": 1, "name": "The Shattered Vale", "foe": "Vaelith", "boss": "Vaelith, the Vale-Render",
	 "finale": "Vaelith's Breach", "tier": "lesser", "mult": 1.15, "opens": "Greater Rifts",
	 "intro": "The Vale split open in a single night. Rifts bleed monsters into the farmland, and the old guilds are gone. Yours is all that stands between the villages and whatever Vaelith is pouring through the largest breach.",
	 "outro": "Vaelith falls back through the Breach, and it seals behind her. The Vale breathes again — but the rifts beyond it only grow deeper. Greater Rifts are open to your guild.",
	 "objectives": [{"type": "rifts_sealed", "target": 2, "label": "Seal 2 rifts"}, {"type": "heroes", "target": 3, "label": "Have 3 heroes in the guild"}],
	 "reward": {"crystals": 80}},
	{"act": 2, "name": "The Drowned Marches", "foe": "Nyxara", "boss": "Nyxara, Queen of the Drowned",
	 "finale": "The Drowned Spire", "tier": "greater", "mult": 1.2, "opens": "the Endless Rift",
	 "intro": "South of the Vale the marshes have risen, and Nyxara's spire rises with them. The Greater Rifts here are older and hungrier. The villages will only trust a guild that has proven itself.",
	 "outro": "The Spire crumbles into the black water, and Nyxara with it. Beneath it, something vast stirs: a rift with no bottom. The Endless Rift is open to your guild.",
	 "objectives": [{"type": "greater_seals", "target": 2, "label": "Seal 2 Greater Rifts"}, {"type": "reputation", "target": 20, "label": "Reach 20 Renown"}, {"type": "map_rank", "target": 3, "label": "Seal a Rank C or higher Rift Map rift"}],
	 "reward": {"crystals": 160}},
	{"act": 3, "name": "The Ashen Crown", "foe": "Sythrane", "boss": "Sythrane, the Ashen Crown",
	 "finale": "The Heart of the Rift", "tier": "greater", "mult": 1.45, "opens": "",
	 "intro": "Every rift you've sealed led here. Sythrane wears a crown of ash at the heart of the rift network, and every breach in the world feeds her. Her wardens Korrath and Drevok guard the way.",
	 "outro": "The Ashen Crown shatters. One by one the rifts across the land fall quiet, and for the first time in years the sky is only sky. Your guild's name will be told for generations. (The rifts never fully close — Endless, the Rift Map and the Guild Board carry on.)",
	 "objectives": [{"type": "map_rank", "target": 4, "label": "Seal a Rank B or higher Rift Map rift"}, {"type": "boss:Korrath", "target": 1, "label": "Defeat Korrath"}, {"type": "boss:Drevok", "target": 1, "label": "Defeat Drevok"}, {"type": "quests_done", "target": 3, "label": "Complete 3 Guild Board quests"}],
	 "reward": {"crystals": 280}},
]
const TRAINING_RIFT := {"floors": 4, "monster_hp_mult": 0.8, "monster_dmg_mult": 0.85}
const QUEST_POSTED := 6
const QUEST_BOARD_BG := "res://assets/screens/quest_board.png"
const QUEST_ACTIVE_MAX := 3
const QUEST_REFRESH_DAYS := 3
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
	{"id": "act_one", "label": "The Vale Holds — complete Act I", "type": "campaign_act", "target": 2, "reward": {"crystals": 25}},
	{"id": "act_two", "label": "Out of the Marshes — complete Act II", "type": "campaign_act", "target": 3, "reward": {"crystals": 40}},
	{"id": "act_three", "label": "Crownbreaker — complete the campaign", "type": "campaign_act", "target": 4, "reward": {"crystals": 70}},
	{"id": "veteran_sealer", "label": "Rift Warden — seal 25 rifts", "type": "rifts_sealed", "target": 25, "reward": {"crystals": 40}},
	{"id": "centurion", "label": "Centurion — defeat 250 monsters", "type": "total_kills", "target": 250, "reward": {"coins": 150}},
	{"id": "kingslayer", "label": "Kingslayer — defeat 20 Bosses", "type": "bosses_won", "target": 20, "reward": {"reputation": 10}},
	{"id": "untouched", "label": "Untouched — seal 5 rifts with no one knocked out", "type": "flawless_rifts", "target": 5, "reward": {"crystals": 30}},
	{"id": "climber", "label": "Climber — reach floor 25 of the Tower", "type": "tower_best", "target": 25, "reward": {"crystals": 30}},
	{"id": "summit", "label": "Summit — clear floor 100 of the Tower", "type": "tower_best", "target": 100, "reward": {"crystals": 120}},
	{"id": "endless_five", "label": "Beyond the Edge — survive 10 minutes in the Endless Rift", "type": "endless_time", "target": 600, "reward": {"crystals": 50}},
	{"id": "daily_first", "label": "Daily Duty — clear a Daily Rift", "type": "daily_clears", "target": 1, "reward": {"crystals": 15}},
	{"id": "daily_streak", "label": "Dedicated — clear Daily Rifts 7 days in a row", "type": "daily_streak", "target": 7, "reward": {"crystals": 65}},
	{"id": "full_set", "label": "Build Complete — own a 4-piece boon set", "type": "boon_set4", "target": 1, "reward": {"crystals": 20}},
	{"id": "legendary_guild", "label": "Legendary Guild — reach Legendary Guild tier", "type": "guild_tier_legendary", "target": 1, "reward": {"reputation": 25}},
	{"id": "max_level", "label": "Paragon — raise a hero to Level 10", "type": "max_level", "target": 1, "reward": {"crystals": 25}},
	{"id": "big_guild", "label": "Great Hall — have 10 heroes on the roster", "type": "roster_size", "target": 10, "reward": {"reputation": 10}},
]

## The Daily Rift: one attempt per day; its rule and starting boon come from
## the date, so the fight layout is the same for every guild that day.
const DAILY_CLEAR_CRYSTALS := 35
const DAILY_CLEAR_CRYSTALS_PER_ACT := 10
const RUN_HISTORY_MAX := 30
