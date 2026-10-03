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
	{"id": "static", "family": "storm", "name": "Static", "desc": "+30% chance to gain 1 Momentum when evading or hit hard.", "kind": "momentum_pct", "value": 0.30},
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
	{"id": "trio", "name": "Trio", "desc": "At most 3 heroes.", "party_cap": 3},
	{"id": "duo", "name": "Duo", "desc": "At most 2 heroes.", "party_cap": 2},
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
## Weekly hero requests: on this day of the week (day % PAYDAY_DAYS) one
## hero (two for a feud) asks for something. Each answer costs something;
## no answer by payday counts as "no". %s in the texts is the hero's name.
const REQUEST_DAY := 3
const REQUEST_RAISE := 0.25       # a granted raise: +25% wage for good
const REQUEST_GEAR_COST := 60
const REQUEST_LEAVE_DAYS := 3
const HERO_REQUESTS := {
	"week_off": {"title": "%s asks for time off", "text": "%s has been in the rifts a lot and wants a few days away from the guild.",
		"yes": "Grant it: away %d days, +15 morale" % REQUEST_LEAVE_DAYS, "no": "Refuse: -10 morale", "yes_morale": 15, "no_morale": -10},
	"raise": {"title": "%s asks for a raise", "text": "%s says the rifts are worth more than the guild pays and wants a bigger share.",
		"yes": "Raise their wage %d%%: +20 morale" % int(REQUEST_RAISE * 100), "no": "Refuse: -12 morale", "yes_morale": 20, "no_morale": -12},
	"gear": {"title": "%s wants better kit", "text": "%s says their gear is falling apart and asks for Gold for repairs.",
		"yes": "Pay %d Gold: +15 morale" % REQUEST_GEAR_COST, "no": "Refuse: -8 morale", "yes_morale": 15, "no_morale": -8},
	"train": {"title": "%s wants extra drills", "text": "%s asks for a spot in the Training Yard this week.",
		"yes": "Give them a slot: +1 attribute point, +5 morale", "no": "Not this week: -6 morale", "yes_morale": 5, "no_morale": -6},
	"feud": {"title": "%s and %s are feuding", "text": "An argument over the last rift's spoils has turned sour. Each wants you on their side.",
		"yes": "Side with %s", "no": "Side with %s", "yes_morale": 10, "no_morale": -12},
}

## A fight won by hand (Auto never on) with no hero down pays this share
## of its Gold and its Essence again, where GameState.hand_bonus_here says.
const HAND_BONUS := 0.3
## A party at this share of a rank's Recommended power ("Favored") may Quick
## fight it before sealing it: a tester way above the content couldn't.
const QUICK_FIGHT_FAVORED := 1.2

## The Endless Rift pays once for each of these, the first time the guild
## survives that long (any region); "sealed" means beating the Rift Warden.
const ENDLESS_MILESTONES := [
	{"at": 300, "name": "Five minutes in the rift", "coins": 150, "crystals": 30},
	{"at": 600, "name": "Ten minutes in the rift", "coins": 250, "crystals": 50, "relic": "e_warden_shard"},
	{"at": 900, "name": "Fifteen minutes in the rift", "coins": 400, "crystals": 80, "title": "Riftwalkers"},
	{"at": 1200, "name": "The rift sealed", "coins": 0, "crystals": 120, "relic": "e_rift_heart", "title": "Rift Sealers", "sealed": true},
]

const TOWER_TITLES := [[10, "Tower Initiate"], [25, "Trial Climber"], [50, "Spire Walker"], [75, "Stormbreaker"], [100, "Summit Keeper"]]

# Lesser and Greater Rift are the two selectable DIFFICULTIES tiers (the
# Endless Rift is a survival mode, scripts/survivors).
const DIFFICULTIES := [
	{"id": "lesser", "name": "Lesser Rift", "floors": 7, "monster_hp": 20, "monster_dmg": 2.6, "coin": [18, 34], "crystal": [5, 11], "seal_essence": 10, "cache_chance": 0.08, "power": "Low", "rec_power": 90},
	# Unlocked by GameState.greater_rift_unlocked() (seal 3 rifts) rather than
	# Guild Management currency — sits between Lesser and the Ascendant-
	# First-draft numbers, tunable after playing.
	{"id": "greater", "name": "Greater Rift", "floors": 8, "monster_hp": 80, "monster_dmg": 8.6, "coin": [40, 70], "crystal": [11, 20], "seal_essence": 18, "cache_chance": 0.14, "power": "Medium", "rec_power": 500},
]

## The power the Rift Hall compares against for the Endless Rift (survivors).
const ENDLESS_REC_POWER := 1000   # a party this strong lasts roughly 8-15 min (balance_sim -- calibrate)

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
			{"label": "Absorb its energy", "desc": "+3 Momentum next fight · +5 Essence", "effect": {"ready": true, "crystals": 5}},
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
			{"label": "Thaw them out", "desc": "Costs 15 Gold · +3 Renown · +3 Momentum next fight", "cost": {"coins": 15}, "effect": {"reputation": 3, "ready": true}},
			{"label": "Take their shield", "desc": "A Rare-or-better item · -2 Renown", "effect": {"item": "rare", "reputation": -2}},
			{"label": "Move on", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "blood_pool", "name": "Crimson Pool", "text": "A pool of something thick and red. Drinking it would teach you things. Painful things.",
		"choices": [
			{"label": "Drink", "desc": "Everyone loses 20% HP · every hero gains 40 XP", "effect": {"hurt_pct": 0.20, "xp_all": 40}},
			{"label": "Bottle some", "desc": "+1 Healing Tonic", "effect": {"tonic": 1}},
		]},
	{"id": "anvil", "name": "Singing Anvil", "text": "An anvil that rings on its own. A smith's ghost offers to work it, for a price.",
		"choices": [
			{"label": "Pay the smith", "desc": "Costs 25 Gold · an Epic item", "cost": {"coins": 25}, "effect": {"item": "epic"}},
			{"label": "Sell the scrap", "desc": "+12 Gold", "effect": {"coins": 12}},
		]},
	{"id": "storm_totem", "name": "Storm Totem", "text": "A totem crackles with trapped lightning. Channelled right, it could charge your party.",
		"choices": [
			{"label": "Channel it", "desc": "Focus check · pass: +12-20 Essence, +3 Momentum next fight · fail: everyone loses 10% HP", "check": {"attr": "focus", "target": 10, "win": {"crystals": [12, 20], "ready": true}, "lose": {"hurt_pct": 0.10}}},
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
			{"label": "Study it", "desc": "Focus check · pass: +3 Momentum next fight, +25 XP each · fail: everyone loses 10% HP", "check": {"attr": "focus", "target": 9, "win": {"ready": true, "xp_all": 25}, "lose": {"hurt_pct": 0.10}}},
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
			{"label": "Regroup", "desc": "Every hero heals 15% HP · +3 Momentum next fight", "effect": {"heal_pct": 0.15, "ready": true}},
		]},
	{"id": "banner", "name": "Fallen Banner", "text": "A guild banner lies in the dust, its bearer long gone. The cloth is still good.",
		"choices": [
			{"label": "Raise it", "desc": "+3 Renown · a 20-point shield against the next hazard", "effect": {"reputation": 3, "shield": 20}},
			{"label": "Salvage it", "desc": "+10 Gold", "effect": {"coins": 10}},
		]},
	# Content pass (0.18): more events; "biome" keeps one to its region.
	{"id": "deserter", "name": "A Deserter", "text": "A rival guild's hireling crouches in a side passage, clutching a stolen purse.",
		"choices": [
			{"label": "Turn them in", "desc": "+10 Gold · +3 Renown", "effect": {"coins": 10, "reputation": 3}},
			{"label": "Split the purse", "desc": "+20-30 Gold · -2 Renown", "effect": {"coins": [20, 30], "reputation": -2}},
		]},
	{"id": "well", "name": "Whispering Well", "text": "Coins glint at the bottom of a dry well, and something down there whispers your name.",
		"choices": [
			{"label": "Climb down", "desc": "Agility check · pass: 25-40 Gold · fail: everyone loses 10% HP", "check": {"attr": "agility", "target": 9, "win": {"coins": [25, 40]}, "lose": {"hurt_pct": 0.10}}},
			{"label": "Toss a coin in", "desc": "Costs 5 Gold · every hero heals 15% HP", "cost": {"coins": 5}, "effect": {"heal_pct": 0.15}},
		]},
	{"id": "forge", "name": "Cold Forge", "text": "An abandoned rift-forge, its coals still faintly warm.",
		"choices": [
			{"label": "Stoke it with Essence", "desc": "Costs 10 Essence · a Rare-or-better item", "cost": {"crystals": 10}, "effect": {"item": "rare"}},
			{"label": "Scavenge the scraps", "desc": "+12 Gold", "effect": {"coins": 12}},
		]},
	{"id": "sparring", "name": "Old Sparring Ring", "text": "Chalk lines and battered practice dummies. Someone trained here once, and the rift kept it.",
		"choices": [
			{"label": "Spar", "desc": "Everyone loses 10% HP · every hero gains 35 XP", "effect": {"hurt_pct": 0.10, "xp_all": 35}},
			{"label": "Rest in the ring", "desc": "Every hero heals 10% HP", "effect": {"heal_pct": 0.10}},
		]},
	{"id": "hermit", "name": "Rift Hermit", "text": "An old man lives here, somehow. He offers tea and a story.",
		"choices": [
			{"label": "Drink the tea", "desc": "Every hero heals 25% HP", "effect": {"heal_pct": 0.25}},
			{"label": "Buy his charm", "desc": "Costs 20 Gold · a 25-point shield against the next hazard", "cost": {"coins": 20}, "effect": {"shield": 25}},
		]},
	{"id": "bones", "name": "Pile of Bones", "text": "Adventurers' bones, their packs still strapped on.",
		"choices": [
			{"label": "Search the packs", "desc": "60%: a Rare-or-better find · 40%: a trap hits everyone for 10% HP", "gamble": {"chance": 0.6, "win": {"loot": "rare"}, "lose": {"hurt_pct": 0.10}}},
			{"label": "Bury them", "desc": "+2 Renown · every hero gains 10 XP", "effect": {"reputation": 2, "xp_all": 10}},
		]},
	{"id": "tollkeeper", "name": "The Tollkeeper", "text": "A masked figure blocks the path with a spear. \"Toll.\"",
		"choices": [
			{"label": "Pay the toll", "desc": "Costs 25 Gold · he points out a shortcut: +3 Momentum next fight", "cost": {"coins": 25}, "effect": {"ready": true}},
			{"label": "Push past", "desc": "Might check · pass: +30 Gold from his strongbox · fail: everyone loses 15% HP", "check": {"attr": "might", "target": 10, "win": {"coins": 30}, "lose": {"hurt_pct": 0.15}}},
		]},
	{"id": "starlight", "name": "Rift Starlight", "text": "A shaft of pale light falls through a crack in the rift. It feels like home.",
		"choices": [
			{"label": "Bask in it", "desc": "Every hero heals 15% HP · +3 Momentum next fight", "effect": {"heal_pct": 0.15, "ready": true}},
			{"label": "Bottle it", "desc": "+10 Essence", "effect": {"crystals": 10}},
		]},
	{"id": "cart", "name": "Overturned Cart", "text": "A merchant's cart lies on its side. The merchant is nowhere to be seen.",
		"choices": [
			{"label": "Take the goods", "desc": "+25 Gold · -2 Renown", "effect": {"coins": 25, "reputation": -2}},
			{"label": "Take one tonic", "desc": "+1 Healing Tonic", "effect": {"tonic": 1}},
			{"label": "Right the cart", "desc": "+4 Renown", "effect": {"reputation": 4}},
		]},
	{"id": "scarecrow", "biome": "vale", "name": "Silent Scarecrow", "text": "A scarecrow stands in the rift's wheat, its sackcloth head turning to follow you.",
		"choices": [
			{"label": "Burn it", "desc": "+8 Essence", "effect": {"crystals": 8}},
			{"label": "Search its coat", "desc": "Focus check · pass: a Rare-or-better item · fail: everyone loses 10% HP", "check": {"attr": "focus", "target": 9, "win": {"item": "rare"}, "lose": {"hurt_pct": 0.10}}},
		]},
	{"id": "orchard", "biome": "vale", "name": "Rift Orchard", "text": "Apple trees heavy with softly glowing fruit, in a field that shouldn't exist.",
		"choices": [
			{"label": "Eat the fruit", "desc": "70%: every hero heals 30% HP · 30%: bellyache, everyone loses 10% HP", "gamble": {"chance": 0.7, "win": {"heal_pct": 0.30}, "lose": {"hurt_pct": 0.10}}},
			{"label": "Fill a basket", "desc": "+1 Healing Tonic", "effect": {"tonic": 1}},
		]},
	{"id": "mill", "biome": "vale", "name": "Haunted Mill", "text": "The mill wheel turns with no water and no wind, grinding something that glows.",
		"choices": [
			{"label": "Take the rift-flour", "desc": "+12-18 Essence", "effect": {"crystals": [12, 18]}},
			{"label": "Jam the wheel", "desc": "Might check · pass: the village thanks you, +4 Renown, +15 Gold · fail: everyone loses 10% HP", "check": {"attr": "might", "target": 9, "win": {"reputation": 4, "coins": 15}, "lose": {"hurt_pct": 0.10}}},
		]},
	{"id": "wayshrine", "biome": "vale", "name": "Vale Wayshrine", "text": "A farmer's roadside shrine, its garlands somehow still fresh.",
		"choices": [
			{"label": "Leave an offering", "desc": "Costs 10 Gold · every hero heals 20% HP · +2 Renown", "cost": {"coins": 10}, "effect": {"heal_pct": 0.20, "reputation": 2}},
			{"label": "Pray for strength", "desc": "Every hero gains 20 XP", "effect": {"xp_all": 20}},
		]},
	{"id": "sunken_bell", "biome": "marsh", "name": "Sunken Bell", "text": "A bronze bell rises from the black water and tolls once, very slowly.",
		"choices": [
			{"label": "Ring it back", "desc": "50%: a Rare-or-better relic surfaces · 50%: the water lashes out, everyone loses 15% HP", "gamble": {"chance": 0.5, "win": {"relic": "rare"}, "lose": {"hurt_pct": 0.15}}},
			{"label": "Leave quietly", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "leech_pool", "biome": "marsh", "name": "Leech Pool", "text": "Fat leeches drift in a warm pool. The old marsh healers swore by them.",
		"choices": [
			{"label": "Bathe", "desc": "Every hero heals 25% HP", "effect": {"heal_pct": 0.25}},
			{"label": "Jar a few", "desc": "+1 Healing Tonic", "effect": {"tonic": 1}},
		]},
	{"id": "drowned_chest", "biome": "marsh", "name": "Drowned Chest", "text": "A chest sits chained under a foot of murky water.",
		"choices": [
			{"label": "Dive for it", "desc": "Agility check · pass: a Rare-or-better item · fail: everyone loses 12% HP", "check": {"attr": "agility", "target": 10, "win": {"item": "rare"}, "lose": {"hurt_pct": 0.12}}},
			{"label": "Hook it with a rope", "desc": "+15-25 Gold", "effect": {"coins": [15, 25]}},
		]},
	{"id": "fog_voices", "biome": "marsh", "name": "Voices in the Fog", "text": "The fog whispers the names of heroes your guild has lost.",
		"choices": [
			{"label": "Answer them", "desc": "Focus check · pass: every hero gains 40 XP · fail: everyone loses 10% HP", "check": {"attr": "focus", "target": 10, "win": {"xp_all": 40}, "lose": {"hurt_pct": 0.10}}},
			{"label": "Press on in silence", "desc": "+3 Momentum next fight", "effect": {"ready": true}},
		]},
	{"id": "ash_statue", "biome": "ashen", "name": "Ash-Buried King", "text": "The statue of a forgotten king, half swallowed by ash, still holds out its hand.",
		"choices": [
			{"label": "Dig it out", "desc": "Might check · pass: a Rare-or-better relic · fail: everyone loses 10% HP", "check": {"attr": "might", "target": 10, "win": {"relic": "rare"}, "lose": {"hurt_pct": 0.10}}},
			{"label": "Pry off its gems", "desc": "+12 Essence", "effect": {"crystals": 12}},
		]},
	{"id": "glass_bridge", "biome": "ashen", "name": "Glass Bridge", "text": "A bridge of cooled volcanic glass arcs over a river of fire.",
		"choices": [
			{"label": "Cross carefully", "desc": "Agility check · pass: +8 Essence, +3 Momentum next fight · fail: everyone loses 15% HP", "check": {"attr": "agility", "target": 9, "win": {"crystals": 8, "ready": true}, "lose": {"hurt_pct": 0.15}}},
			{"label": "Go the long way", "desc": "Everyone loses 5% HP", "effect": {"hurt_pct": 0.05}},
		]},
	{"id": "cult_altar", "biome": "ashen", "name": "Cult Offering", "text": "An abandoned fire-cult altar, piled high with offerings.",
		"choices": [
			{"label": "Take the offerings", "desc": "+30 Gold · -3 Renown", "effect": {"coins": 30, "reputation": -3}},
			{"label": "Scatter the ashes", "desc": "+4 Renown", "effect": {"reputation": 4}},
		]},
	{"id": "ember_egg", "biome": "ashen", "name": "Ember Egg", "text": "A warm egg rests in the embers, pulsing with light like a heartbeat.",
		"choices": [
			{"label": "Warm it", "desc": "40%: it hatches and leaves a gift, a Rare-or-better find, +10 Essence · 60%: it bursts, everyone loses 15% HP", "gamble": {"chance": 0.4, "win": {"loot": "rare", "crystals": 10}, "lose": {"hurt_pct": 0.15}}},
			{"label": "Take its shell", "desc": "+15 Essence", "effect": {"crystals": 15}},
		]},
	# The Sky Beneath (a side thread): strange, gentle things from the Hollow.
	# "min_act" holds an event back until that act.
	{"id": "glass_market", "name": "The Glass Market", "text": "In the middle of the rift, a stall. A thing with too many hands is selling fruit made of glass. It does not attack. It seems embarrassed to be seen. When your party comes closer it holds out a fruit and says, very clearly, in our language: please.",
		"choices": [
			{"label": "Buy a fruit", "desc": "Costs 12 Gold · every hero heals 25% HP", "cost": {"coins": 12}, "effect": {"heal_pct": 0.25}},
			{"label": "Take one (it lets you)", "desc": "+8-14 Essence · -1 Renown", "effect": {"crystals": [8, 14], "reputation": -1}},
			{"label": "Leave it in peace", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "lost_child", "min_act": 2, "name": "A Lost Child", "text": "A small creature hides behind a rock. It has the shape of the things you fight, but small, and it is crying. It flinches when your party comes near, then follows at a distance.",
		"choices": [
			{"label": "Walk it to the rift's heart", "desc": "Every hero gains 15 XP", "effect": {"xp_all": 15}},
			{"label": "Leave it your rations", "desc": "Costs 10 Gold · +3 Renown", "cost": {"coins": 10}, "effect": {"reputation": 3}},
			{"label": "Drive it off", "desc": "Nothing happens", "effect": {}},
		]},
	{"id": "rain_up", "min_act": 2, "name": "Rain That Falls Up", "text": "Here the rain falls toward the sky, slow and warm, and collects in the air above your heads like a lake seen from underneath.",
		"choices": [
			{"label": "Stand in it", "desc": "Every hero heals 15% HP · +3 Momentum next fight", "effect": {"heal_pct": 0.15, "ready": true}},
			{"label": "Bottle it", "desc": "+8-14 Essence", "effect": {"crystals": [8, 14]}},
		]},
	{"id": "dark_post", "min_act": 2, "name": "A Dark Post", "text": "A pillar of glass stands in the rift, cracked and empty. Scratched into its base: a name, and the Accord's oath. Whoever held this post let go a long time ago.",
		"choices": [
			{"label": "Read the oath aloud", "desc": "Every hero heals 10% HP · +2 Renown", "effect": {"heal_pct": 0.10, "reputation": 2}},
			{"label": "Chip out the crystal", "desc": "+10-16 Essence · -2 Renown", "effect": {"crystals": [10, 16], "reputation": -2}},
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
## The rift ladder, F to SSS. Each rank sits on a base difficulty (Lesser for
## F-D, Greater from C) scaled by its own foe multipliers and reward
## multiplier, plus the rules it adds. "rec" is the party power that clears
## it about 65% of the time (balance_sim -- calibrate). Sealing a rank opens the next; C and up
## also need the Greater Rift (Act II).
## Monster strength on top of each rank's own hp/dmg, above Rank F (which
## stays gentle for a new guild). Set from the campaign sim
## (tests/sim/campaign_sim.gd -- bold): at Recommended power a party seals
## 3 rifts in 5, near what the Party screen says (at 1.0 it was 87%). A var so
## the sim can sweep it.
var RANK_THREAT_HP := 1.3
var RANK_THREAT_DMG := 1.3
const RIFT_RANKS := [
	{"id": "F", "rec": 65, "base": "lesser", "hp": 0.8, "dmg": 0.85, "reward": 1.0},
	{"id": "E", "rec": 160, "base": "lesser", "hp": 1.8, "dmg": 1.6, "reward": 1.4},
	{"id": "D", "rec": 220, "base": "lesser", "hp": 2.4, "dmg": 2.0, "reward": 1.7},
	{"id": "C", "rec": 480, "base": "greater", "hp": 1.0, "dmg": 1.0, "reward": 1.0},
	{"id": "B", "rec": 740, "base": "greater", "hp": 1.4, "dmg": 1.3, "reward": 1.3, "elite_chance_up": true},
	{"id": "A", "rec": 850, "base": "greater", "hp": 1.9, "dmg": 1.6, "reward": 1.7, "elite_chance_up": true, "hazard_severity_up": 1, "shop_chance_down": true},
	{"id": "S", "rec": 1200, "base": "greater", "hp": 3.0, "dmg": 2.2, "reward": 2.2, "elite_chance_up": true, "hazard_severity_up": 1, "shop_chance_down": true, "relic_rarity_floor_down": true},
	{"id": "SS", "rec": 1850, "base": "greater", "hp": 4.2, "dmg": 3.0, "reward": 2.8, "elite_chance_up": true, "hazard_severity_up": 1, "shop_chance_down": true, "relic_rarity_floor_down": true, "boss_double_mechanic": true},
	{"id": "SSS", "rec": 2200, "base": "greater", "hp": 6.0, "dmg": 3.8, "reward": 3.5, "elite_chance_up": true, "hazard_severity_up": 2, "shop_chance_down": true, "relic_rarity_floor_down": true, "boss_double_mechanic": true},
]

## What each rank's extra rules read as on the Rift Hall.
const RIFT_RANK_RULE_TEXT := {
	"elite_chance_up": "more elites", "hazard_severity_up": "harsher hazards", "shop_chance_down": "fewer shops",
	"relic_rarity_floor_down": "no rarity floor on the starting relic", "boss_double_mechanic": "bosses use two mechanics",
}


## What each rule does, for its tooltip.
const RIFT_RANK_RULE_TIP := {
	"elite_chance_up": "Forks offer elite fights more often.",
	"hazard_severity_up": "The mildest hazards are skipped: every hazard is at least Moderate (at least Severe at SSS).",
	"shop_chance_down": "Forks offer a shop less often.",
	"relic_rarity_floor_down": "The starting relic can be any rarity, even Common.",
	"boss_double_mechanic": "The boss uses two of its mechanics at once.",
}


static func find_rift_rank(rank_id: String) -> Dictionary:
	for r in RIFT_RANKS:
		if r["id"] == rank_id:
			return r
	return RIFT_RANKS[0]


## 0-8 index of a rift rank (F..SSS).
static func rift_rank_index(rank_id: String) -> int:
	for i in RIFT_RANKS.size():
		if RIFT_RANKS[i]["id"] == rank_id:
			return i
	return 0

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
		{"id": "drill", "name": "Drill Yard", "max": 5, "cost_base": 50, "cost_step": 50, "every": "a Training Yard slot every 2 levels; +4% party damage and +4% max HP",
			"perks": {2: "Order: Rally — the party acts first this round and hits 30% harder", 3: "Vanguard: a fight's first strike deals +25% damage", 5: "Abilities are ready at the start of every fight"}},
	]},
	{"id": "infra", "name": "Infrastructure Branch", "sub": "Rift Yield & Safety", "nodes": [
		{"id": "amplifiers", "name": "Essence Amplifiers", "max": 5, "cost_base": 50, "cost_step": 50, "every": "+8% Essence from fights",
			"perks": {3: "Energy extraction: elites often drop bonus Essence", 5: "Resonance: bosses drop an Essence cache"}},
		{"id": "wardstones", "name": "Wardstones", "max": 5, "cost_base": 50, "cost_step": 50, "every": "-12% hazard damage, +10% Essence for sealing",
			"perks": {3: "Anchor: the first hazard of each rift is negated", 5: "Hazards can't knock a hero out"}},
	]},
	{"id": "log", "name": "Logistics Branch", "sub": "Trade & Recruiting", "nodes": [
		{"id": "trade", "name": "Trade Network", "max": 5, "cost_base": 50, "cost_step": 50, "every": "+1 feast seat; -6% shop prices, -2% auction fees, +5% Rift Cache chance",
			"perks": {2: "Order: Requisition — reroll a fight's loot choices", 3: "Black Market: Rift Caches hold 30% more Gold", 5: "Every rift shop stocks an Epic relic"}},
		{"id": "scouts", "name": "Scouts' Lodge", "max": 5, "cost_base": 50, "cost_step": 50, "every": "Recruit board: +1 offer at Lv1 and Lv4",
			"perks": {2: "Order: Scout Ahead — reroll the next fork's paths", 3: "Headhunter: every recruit refresh has a Rank C+ hero", 5: "Recruit rerolls cost half"}},
	]},
	{"id": "def", "name": "Defenses Branch", "sub": "Riftbreaks (paid in Gold)", "nodes": [
		{"id": "armory", "name": "Armory", "max": 5, "cost_base": 80, "cost_step": 80, "currency": "gold", "every": "+6% tower damage",
			"perks": {1: "Towers: Frost Totem", 2: "Towers: Ward Stone", 3: "Towers: Wayside Chapel"}},
		{"id": "engineering", "name": "Engineering", "max": 5, "cost_base": 80, "cost_step": 80, "currency": "gold", "every": "-6% tower costs",
			"perks": {3: "Towers can reach tier 3", 5: "Selling a tower refunds all of it"}},
		{"id": "palisade", "name": "Palisade", "max": 5, "cost_base": 80, "cost_step": 80, "currency": "gold", "every": "+2 integrity and +20 starting supplies",
			"perks": {}},
		{"id": "watch", "name": "Watchtower", "max": 5, "cost_base": 80, "cost_step": 80, "currency": "gold", "every": "posted heroes +6% max HP",
			"perks": {1: "+1 day of warning before a rift breaks", 3: "+1 more day of warning"}},
	]},
	{"id": "res", "name": "Research Branch", "sub": "Relics & Theory", "nodes": [
		{"id": "vault", "name": "Relic Vault", "max": 5, "cost_base": 50, "cost_step": 50, "every": "Starting relic choices (2 at Lv1, 3 at Lv2, 4 at Lv4)",
			"perks": {3: "+1 equipped relic slot", 5: "+1 more relic slot, and starting relics are Rare or better"}},
		{"id": "lab", "name": "Arcane Lab", "max": 5, "cost_base": 50, "cost_step": 50, "every": "+5% to every relic effect; Lv1 unlocks relic scrapping and trait/scar removal",
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
	"def.armory": "res://assets/skills/sword_a.png",
	"def.engineering": "res://assets/skills/gear.png",
	"def.palisade": "res://assets/skills/shield_basic.png",
	"def.watch": "res://assets/skills/eye_gem.png",
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
## The backdrop's night sky, continued above it when the village fills the window.
const HAMLET_SKY := Color(0.0902, 0.0824, 0.2275)
const HAMLET_BUILDINGS := [
	{"id": "scouts", "name": "Recruits", "building": "Scouts' Lodge", "tier": "node", "node": "log.scouts", "pos": Vector2(62, 150), "row": "back"},
	{"id": "hall", "name": "Guild Hall", "tier": "guild", "pos": Vector2(200, 152), "row": "back"},
	{"id": "lab", "name": "Arcane Lab", "tier": "node", "node": "res.lab", "pos": Vector2(338, 150), "row": "back"},
	{"id": "barracks", "name": "Heroes", "building": "Barracks", "tier": "node", "node": "ops.barracks", "pos": Vector2(32, 177), "row": "front"},
	{"id": "infirmary", "name": "Medical Bay", "building": "Infirmary", "tier": "node", "node": "ops.infirmary", "pos": Vector2(96, 177), "row": "front"},
	{"id": "drill", "name": "Skills", "building": "Drill Yard", "tier": "node", "node": "ops.drill", "pos": Vector2(152, 177), "row": "front"},
	{"id": "campfire", "name": "", "tier": "", "pos": Vector2(200, 178), "row": "front"},
	{"id": "board", "name": "Quests", "building": "Quest Board", "tier": "", "pos": Vector2(234, 176), "row": "front"},
	{"id": "gate", "name": "Rift Hall", "building": "Rift Gate", "tier": "act", "pos": Vector2(270, 177), "row": "front"},
	{"id": "market", "name": "Items", "building": "Market", "tier": "node", "node": "log.trade", "pos": Vector2(322, 177), "row": "front"},
	{"id": "vault", "name": "Relics", "building": "Relic Vault", "tier": "node", "node": "res.vault", "pos": Vector2(374, 177), "row": "front"},
]
## Past guilds' banners in the camp ("The Vale Remembers"): pole x on the
## native backdrop, in the gaps either side of the Guild Hall, oldest first.
## The cloth colour goes with the crest.
const BANNER_X := [100, 116, 132, 264, 280, 296]
const BANNER_CLOTH := [Color("7a2e2e"), Color("2e3f7a"), Color("2f6a3f"), Color("5b2e7a"),
	Color("8a6a24"), Color("24666a"), Color("6a2448"), Color("4a5260")]
## The Descent: the Endless Rift turn-based, with the guild's heroes, at its
## best sealed rank. Depths of DESCENT_FLOORS floors; each ends in a guardian
## (an elite) or, every DESCENT_PILLAR_EVERY depths while a lost champion
## waits, a pillar (its keeper fights as a rift warden; winning frees the
## champion). Each depth is DESCENT_GROWTH harder and pays DESCENT_PAY_GROWTH
## more. Climbing out keeps everything; falling loses DESCENT_DEFEAT_LOSS of
## what the Descent earned. It costs a day, like any run.
const DESCENT_FLOORS := 4
const DESCENT_PILLAR_EVERY := 2
const DESCENT_GROWTH := 0.15
const DESCENT_PAY_GROWTH := 0.10
const DESCENT_DEFEAT_LOSS := 0.5
## Pillars on the ladder: a rift of PILLAR_MIN_RANK or higher sometimes offers
## a lost champion's pillar as a fork (once the Endless Rift is open).
const PILLAR_CHANCE := 0.15
const PILLAR_MIN_RANK := "B"
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
	 "finale": "Vaelith's Breach", "tier": "lesser", "rank": "E", "mult": 1.15, "opens": "Greater Rifts",
	 "intro": "The Vale split open on the Night of Breaking, and it has not closed since. Rifts bleed monsters into the farmland. The largest breach belongs to Vaelith, and the villages say she wears the green of an Accord ranger. Seal it, and find out why.",
	 "outro": "Vaelith falls back through the Breach, and it seals behind her. Under her cloak was an Accord badge with the oath scratched out: she was one of them, and she left her post. Whatever the old guilds did that night, someone has been undoing it. Greater Rifts are open to your guild.",
	 "objectives": [{"type": "rifts_sealed", "target": 3, "label": "Seal 3 rifts"}, {"type": "map_rank", "target": 1, "label": "Seal a Rank E rift"}],
	 "reward": {"crystals": 80}},
	{"act": 2, "name": "The Drowned Marches", "foe": "Nyxara", "boss": "Nyxara, Queen of the Drowned",
	 "finale": "The Drowned Spire", "tier": "greater", "rank": "C", "mult": 1.2, "opens": "the Endless Rift",
	 "intro": "South of the Vale the marshes have risen, and Nyxara's spire rises with them. Before it drowned, the Spire was the Accord's archive: every contract, every name, every oath. Nyxara keeps it now, with a light burning at the bottom. The villages will only trust a guild that has proven itself.",
	 "outro": "The Spire crumbles into the black water, and Nyxara with it. One book survived the archive, in the Grandmaster's hand, and it says the guilds did not fall that night. They made a bargain. Beneath the Spire, something vast stirs: a rift with no bottom, lit by pillars of light. The Endless Rift is open to your guild.",
	 "objectives": [{"type": "map_rank", "target": 3, "label": "Seal a Rank C rift"}, {"type": "greater_seals", "target": 2, "label": "Seal 2 rifts of Rank C or higher"}, {"type": "quests_done", "target": 1, "label": "Complete a quest"}],
	 "reward": {"crystals": 160}},
	{"act": 3, "name": "The Ashen Crown", "foe": "Sythrane", "boss": "Sythrane, the Ashen Crown",
	 "finale": "The Heart of the Rift", "tier": "greater", "rank": "B", "mult": 1.3, "opens": "",
	 "intro": "Every rift you've sealed led here. At the heart of the rift network sits Sythrane in a crown of ash, guarded by Korrath and Drevok, once her wardens. The Grandmaster's book names her plainly: Sythrane, Grandmaster of the Accord. She made the bargain. Every breach in the world is one of her guilds letting go, and every one feeds her.",
	 "outro": "The Ashen Crown shatters. Sythrane's last words are not a threat but a warning: someone has to hold the Hollow shut, and she was tired. One by one the rifts fall quiet, and for the first time in years the sky is only sky. In the Endless Rift the pillars of light are still holding. Your guild's name will be told for generations. (The rifts never fully close: Endless, the rift ladder and the quests carry on.)",
	 "objectives": [{"type": "map_rank", "target": 4, "label": "Seal a Rank B rift"}, {"type": "boss:Korrath", "target": 1, "label": "Defeat Korrath"}, {"type": "boss:Drevok", "target": 1, "label": "Defeat Drevok"}, {"type": "quests_done", "target": 3, "label": "Complete 3 quests"}],
	 "reward": {"crystals": 280}},
	{"act": 4, "name": "The Accord Hall", "foe": "The Terms", "boss": "The Terms, in the Grandmaster's shape",
	 "finale": "The Accord Hall", "tier": "greater", "rank": "A", "mult": 1.35, "opens": "",
	 "intro": "With Sythrane gone, the Hollow has no one to bargain with, so it is bargaining with the posts directly. One by one the pillars in the Endless Rift are flickering. The Accord Hall lies below them, and in it the Terms that started all of this, wearing the Grandmaster's face. Every post that has gone dark makes them stronger. Someone will have to read them out loud.",
	 "outro": "The Terms come apart into forty-one lines of old ink, and the Hall goes quiet. The posts are listening. The bargain needs a last signature, or a fire. Your guild has to choose.",
	 "objectives": [{"type": "map_rank", "target": 5, "label": "Seal a Rank A rift"}, {"type": "posts_freed", "target": 1, "label": "Free a lost champion from a pillar"}, {"type": "ledger_pages", "target": 7, "label": "Find every page of the Grandmaster's ledger"}],
	 "reward": {"crystals": 400}},
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
## Guild Standings: besides the rival (who is real, see rival_day), three
## other guilds whose records grow with the days: [strength] scales their
## Renown pace, Tower climb and Endless survival.
const STANDING_STRENGTH := [0.7, 0.95, 1.2]

const MILESTONES := [
	{"id": "first_seal", "label": "First Blood — seal your first Rift", "type": "rifts_sealed", "target": 1, "reward": {"crystals": 10}},
	{"id": "monster_hunter", "label": "Monster Hunter — defeat 25 monsters total", "type": "total_kills", "target": 25, "reward": {"coins": 50, "reputation": 5}},
	{"id": "elite_slayer", "label": "Elite Slayer — win 3 Elite fights", "type": "elites_won", "target": 3, "reward": {"reputation": 3}},
	{"id": "boss_breaker", "label": "Boss Breaker — defeat 3 Bosses", "type": "bosses_won", "target": 3, "reward": {"reputation": 5}},
	{"id": "artisan", "label": "Artisan — craft 3 items or relics", "type": "crafts_performed", "target": 3, "reward": {"crystals": 30}},
	{"id": "full_roster", "label": "Full Roster — fill every hero slot", "type": "full_roster", "target": 1, "reward": {"reputation": 10}},
	{"id": "top_guild", "label": "Guild of the Realm — top the Guild Standings in Renown", "type": "standings_top", "target": 1, "reward": {"coins": 150, "reputation": 5}},
	{"id": "renowned", "label": "Renowned Guild — reach Renowned Guild tier", "type": "guild_tier_renowned", "target": 1, "reward": {"reputation": 15}},
	{"id": "greater_threat", "label": "Greater Threat — open the Rank C rift", "type": "greater_unlocked", "target": 1, "reward": {"crystals": 20}},
	{"id": "act_one", "label": "The Vale Holds — complete Act I", "type": "campaign_act", "target": 2, "reward": {"crystals": 25}},
	{"id": "act_two", "label": "Out of the Marshes — complete Act II", "type": "campaign_act", "target": 3, "reward": {"crystals": 40}},
	{"id": "act_three", "label": "Crownbreaker — complete Act III", "type": "campaign_act", "target": 4, "reward": {"crystals": 70}},
	{"id": "act_four", "label": "Keeper of the Accord — complete the campaign", "type": "campaign_act", "target": 5, "reward": {"crystals": 100}},
	{"id": "veteran_sealer", "label": "Rift Warden — seal 25 rifts", "type": "rifts_sealed", "target": 25, "reward": {"crystals": 40}},
	{"id": "centurion", "label": "Centurion — defeat 250 monsters", "type": "total_kills", "target": 250, "reward": {"coins": 150}},
	{"id": "kingslayer", "label": "Kingslayer — defeat 20 Bosses", "type": "bosses_won", "target": 20, "reward": {"reputation": 10}},
	{"id": "untouched", "label": "Untouched — seal 5 rifts with no one knocked out", "type": "flawless_rifts", "target": 5, "reward": {"crystals": 30}},
	{"id": "climber", "label": "Climber — reach floor 25 of the Tower", "type": "tower_best", "target": 25, "reward": {"crystals": 30}},
	{"id": "summit", "label": "Summit — clear floor 100 of the Tower", "type": "tower_best", "target": 100, "reward": {"crystals": 120}},
	{"id": "endless_five", "label": "Beyond the Edge — survive 10 minutes in the Endless Rift", "type": "endless_time", "target": 600, "reward": {"crystals": 50}},
	{"id": "daily_first", "label": "Daily Duty — seal a rift with the daily twist", "type": "daily_clears", "target": 1, "reward": {"crystals": 15}},
	{"id": "daily_streak", "label": "Dedicated — seal the daily twist 7 days in a row", "type": "daily_streak", "target": 7, "reward": {"crystals": 65}},
	{"id": "full_set", "label": "Build Complete — own a 4-piece boon set", "type": "boon_set4", "target": 1, "reward": {"crystals": 20}},
	{"id": "legendary_guild", "label": "Legendary Guild — reach Legendary Guild tier", "type": "guild_tier_legendary", "target": 1, "reward": {"reputation": 25}},
	{"id": "max_level", "label": "Paragon — raise a hero to Level 10", "type": "max_level", "target": 1, "reward": {"crystals": 25}},
	{"id": "big_guild", "label": "Great Hall — have 10 heroes on the roster", "type": "roster_size", "target": 10, "reward": {"reputation": 10}},
]

## The daily twist: once a day a ladder rift can carry a rule and a starting
## boon from the date (the same for every guild), for bonus Essence and a streak.
const DAILY_CLEAR_CRYSTALS := 35
const DAILY_CLEAR_CRYSTALS_PER_ACT := 10
const RUN_HISTORY_MAX := 30


# ---------------- Running the guild ----------------
## Payday comes every PAYDAY_DAYS days (a day = one rift run or a rest).
## A hero's weekly wage: by rank, +3% per level above 1. Tuned with the
## campaign sim (tests/sim/campaign_sim.gd) so a full roster of 16 costs a
## guild that invests about 40% of its Gold, and a casual 6 about 28%:
## a bench is worth having, a roster of stars has to pay for itself.
const PAYDAY_DAYS := 7
const WAGE_BY_RANK := {"F": 60, "E": 90, "D": 130, "C": 165, "B": 225, "A": 255, "S": 330}
const WAGE_PER_LEVEL := 0.03
## Pay rates the Ledger sets per hero: [wage multiplier, morale at payday].
## Half pay saves Gold at a morale cost (still far better than going unpaid);
## a bonus buys morale for heroes you want Inspired.
const PAY_RATES := {"half": [0.5, -10], "full": [1.0, 0], "bonus": [1.5, 10]}
## Every Guild Management level costs this much Gold a week to keep running.
## Upkeep is paid after wages; unpaid upkeep costs Renown.
const UPKEEP_PER_LEVEL := 12
const UPKEEP_UNPAID_RENOWN := 3
## The Training Yard trains this many attribute points a week (+1 per two
## Drill Yard levels).
const TRAINING_SLOTS := 2
## Unpaid twice running, or paid while at rock-bottom morale, a hero walks out.
const UNPAID_WEEKS_TO_LEAVE := 2
## A guild below this many heroes with no Gold for a Rank F recruit gets free
## volunteers at payday, back up to this many: a way to rebuild, not a lock.
const VOLUNTEER_FLOOR := 3
const MORALE_WALKOUT := 10

## Morale 0-100. Tiers by floor: [min, name, damage bonus].
const MORALE_START := 60
const MORALE_TIERS := [[80, "Inspired", 0.10], [40, "Steady", 0.0], [20, "Shaken", -0.10], [0, "Breaking", -0.20]]
const MORALE_SEAL := 8          # every hero who saw a rift sealed
const MORALE_DEFEAT := -10      # the party of a lost rift
const MORALE_KNOCKOUT := -5
const MORALE_UNPAID := -25
const MORALE_IDLE_WEEK := -5    # a week without a rift run
const MORALE_QUEST_FAILED := -5 # everyone, when a contract fails
const FEAST_MORALE := 15
const FEAST_COST_PER_HERO := 8   # Gold, once a week
const FEAST_SEATS := 6           # heroes a feast can feed (+1 per Trade Network level); lowest morale first

## Contracts come due this many days after they're taken, by difficulty;
## a missed one costs 2 Renown per difficulty level.
const QUEST_DUE_DAYS := {1: 6, 2: 8, 3: 10}

## The rival guild competing for the same contracts and recruits.
const RIVAL_NAMES := ["The Iron Chorus", "The Ashen Wolves", "The Gilded Lance", "The Last Lantern", "The Hollow Crown Company"]
const RIVAL_DAILY_RENOWN := {1: [1, 2], 2: [2, 4], 3: [3, 5]}   # [min, max] per day by campaign act (3 = Act III and after); a guild earns ~3-4 a day in Act II
const RIVAL_CATCH_UP := 10   # trailing by this much or more, the rival gains 1 more a day
## The rival's weekly move: on RIVAL_MOVE_DAY of the week, with this chance,
## it courts a hero, dares you to a challenge or goes for a posted contract,
## and you answer before payday (no answer: the "no" side).
const RIVAL_MOVE_DAY := 5
const RIVAL_MOVE_CHANCE := 0.7
const POACH_MIN_ROSTER := 4          # it never courts a hero from a guild smaller than this
const POACH_COUNTER_WEEKS := 2       # a counter-offer costs this many weeks of the hero's wage
const POACH_COUNTER_MORALE := 10
const POACH_STAY_MORALE := 50        # left to choose, a hero stays at this morale or above
const CHALLENGE_WIN_RENOWN := 6      # you gain this, and the rival loses CHALLENGE_WIN_TAKE
const CHALLENGE_WIN_TAKE := 4
const CHALLENGE_FAIL_RENOWN := 6     # the rival gains this if you fail an accepted dare
const CHALLENGE_DECLINE_RENOWN := 3  # ... or this if you decline
## Each rival guild's leader: a name, a portrait (a subclass id) and a crest.
const RIVAL_LEADERS := {
	"The Iron Chorus": {"leader": "Marshal Orla Venn", "portrait": "iron-guard", "crest": 1},
	"The Ashen Wolves": {"leader": "Kael Ashborn", "portrait": "berserker", "crest": 2},
	"The Gilded Lance": {"leader": "Ser Aldric Vane", "portrait": "radiant-vanguard", "crest": 3},
	"The Last Lantern": {"leader": "Mother Ilse", "portrait": "dawnkeeper", "crest": 4},
	"The Hollow Crown Company": {"leader": "Captain Morrow", "portrait": "nightblade", "crest": 5},
}
## What the rival's leader says about you in the guild news (%s: your guild).
const RIVAL_TAUNTS := [
	"Seal the small rifts, %s. Leave the real ones to us.",
	"%s pays its heroes in promises, I hear.",
	"Our recruits ask about %s. Then they sign with us.",
	"Tell %s the quest board isn't a charity.",
	"We'll send flowers when %s closes its doors.",
	"%s? I thought they'd disbanded.",
]
const RIVAL_TAUNT_CHANCE := 0.2
## A monthly contest: whoever gains more Renown in CONTEST_DAYS wins a prize.
const CONTEST_DAYS := 28
const CONTEST_PRIZE := {"coins": 200, "reputation": 8}
## Sealing a rift earns Renown: 1, +1 per three ladder ranks.
const SEAL_RENOWN_BASE := 1


static func morale_tier(m: int) -> Array:
	for t in MORALE_TIERS:
		if m >= int(t[0]):
			return t
	return MORALE_TIERS[-1]


## The Broken Accord (the campaign's story). The game opens on this card,
## before Act I's.
const PROLOGUE := {"title": "The Night of Breaking", "subtitle": "The end of the Accord",
	"text": "For three hundred years the guilds of the Accord kept the rifts shut. They swore one oath: close what opens, share what you find, never sell a rift. Then, in a single night, every rift in the Vale opened at once, and every Accord guild went in. None of them came back. By morning their halls stood empty.\n\nThe villages still need a guild. They have yours."}

## The Codex's Chronicle: what everyone knows (always shown), then what the
## campaign reveals ("act": shown once that act's finale is sealed).
const CHRONICLE_WORLD := [
	["The Hollow", "The world sits on a thin crust. Under it is the Hollow, where things that never got to happen pile up: unfinished storms, roads never built, beasts that almost were. A rift is a crack in the crust, and what comes through is the Hollow trying on a shape. It copies what it finds, which is why each region's monsters look like that region."],
	["Essence", "When the Hollow touches air it hardens into crystal. Essence is unfinished possibility: put it into a hero and they grow into what they might have been, into a building and it becomes its better self, into a relic and it wakes. Gold pays people. Essence changes things."],
	["The Accord", "The oath of the old guilds: close what opens, share what you find, never sell a rift. The villages paid the guilds that swore it, and for three hundred years the crust held. Renown is the villages' trust; the best recruits go where it is."],
	["The Assay", "Every hero who joins a guild is measured once on the Assay stone, by how much Essence they can hold without breaking: F to S. Rifts are measured on the same scale, so a Rank C rift is one a Rank C hero can stand in. SS and SSS were added after the Night of Breaking, by clerks who had run out of letters."],
	["The Five Paths", "The Accord trained fighters in five Paths: the Shield (warriors), the Bow (rangers), the Word (mages), the Vow (clerics) and the Knife (rogues). Below Rank B the Path is all a hero is. From Rank B there is enough Essence in them that it settles into a shape of its own, and the Path forks into a calling."],
	["The Night of Breaking", "Every rift in the Vale opened at once, deeper than the Assay could measure, and every Accord guild answered. None came back. The new companies that took charters afterward never swore the Accord. Yours can choose to keep it."],
]
const CHRONICLE_REVEALS := [
	{"act": 1, "title": "Vaelith's badge", "text": "Under Vaelith's cloak was an Accord ranger's badge with the oath scratched out. She held a post on the Night of Breaking and walked away from it. The great Breach in the Vale was the post she left."},
	{"act": 2, "title": "The bargain", "text": "The guilds did not fall. On the Night of Breaking the Grandmaster of the Accord made a bargain with the Hollow: the strongest of the guilds would stand in the cracks and let the Hollow harden around them, and the Hollow would stay below. The pillars of light in the Endless Rift are those posts, still holding."},
	{"act": 3, "title": "The forty-first post", "text": "Sythrane was the Grandmaster. The bargain asked for forty-one posts, and she would not take the last one herself. The Hollow crowned her instead, and every post that tired and let go fed her. With her gone the rifts are quiet. The posts are still holding, and someone will have to relieve them."},
]

## The Grandmaster's ledger: pages found in sealed rifts (a finale always
## turns one up). A page shows once the campaign reaches its act.
const LEDGER_PAGE_CHANCE := 0.35
const LEDGER_PAGES := [
	{"act": 1, "text": "Day 1. The Hollow is rising faster than we can close it. The Assay has no mark for what came through at Thornwood. I have called every guild to the Hall."},
	{"act": 1, "text": "Day 3. A voice answered from the deepest rift. It offered terms. I wrote them down so that I could refuse them properly."},
	{"act": 2, "text": "Day 9. Forty posts: forty of our strongest, standing in the cracks, held by the Hollow's own hardening. In return it stays below. I have not refused."},
	{"act": 2, "text": "Day 10. Lots drawn. Brannoch asked for the deepest post and I let him. I told them all I would come back for them myself."},
	{"act": 2, "text": "Day 11. Vaelith asked who holds the Grandmaster's post. I said the Grandmaster keeps the ledger. That was not an answer, and she knew it."},
	{"act": 3, "text": "The Night. Every post is taken but mine. The terms say forty-one. The Hollow can count."},
	{"act": 3, "text": "After. The Hollow came for the forty-first and found me ready to make a different bargain. It gives me a crown. I give it the posts, one at a time, as they tire. It is slower than refusing. That is all I wanted: more time."},
]


## The Charter War: the Crown will grant one Royal Charter. This notice is
## shown once, when the rival's weekly moves begin (%s: the rival, its leader).
const ROYAL_CHARTER := {"title": "By Royal Hand", "subtitle": "A notice on every guild door in the Vale",
	"text": "The Crown will return to the Vale. A single Royal Charter will go to the company that has done the most to close the rifts: every contract, for a generation. Until then, all chartered companies compete on equal terms.\n\nThe loudest of them, %s, led by %s, has noticed your guild."}

## Each rival leader's voice: a signed letter with each weekly move (poach:
## %s the hero; challenge: %s the rank) and what they say about you in the
## guild news (%s: your guild).
const RIVAL_VOICE := {
	"The Iron Chorus": {
		"poach": "%s fights like one of mine. I'd rather ask than steal, so I'm asking: let them come, or pay them what they're worth. No hard feelings either way. — O. Venn",
		"challenge": "Seal a Rank %s rift before payday. If you do, I'll say so to the herald. If you don't, I'll say that too. — O. Venn",
		"snatch": "That contract is on the board and we can do it. So can you, maybe. First to sign it keeps it. — O. Venn",
		"taunts": ["Good work this week, %s. Do better next week.", "The Chorus sings about the rifts it has closed. %s hums.", "%s keeps its word. I'll give them that. I'll give them nothing else."]},
	"The Ashen Wolves": {
		"poach": "We can't train heroes like %s; we haven't the Gold. We can pay them, though, for a few weeks at least. They'll be happy. Probably. — Kael",
		"challenge": "Rank %s by payday. We did one last week. Barely. Your turn. — Kael",
		"snatch": "We need that contract more than you do. I'm not proud of saying so. I'm saying it anyway. — Kael",
		"taunts": ["The Wolves are hungry and %s is fat. Draw your own conclusions.", "Someday the Wolves will have a hall like %s's. With a roof.", "%s had a good week. We ate."]},
	"The Gilded Lance": {
		"poach": "Your %s has a good eye and a poor wage. I have the opposite problem. I'm sure we can come to an arrangement. — Vane",
		"challenge": "A Rank %s rift by payday, if your guild can manage it. Mine could, in its sleep. It frequently does. — Vane",
		"snatch": "The Lance will be taking that contract. Do not trouble yourselves. — Ser Aldric Vane",
		"taunts": ["The Charter will hang in the Lance's hall. I have already chosen the frame.", "%s pays its heroes in promises, I hear.", "%s? I thought they'd disbanded."]},
	"The Last Lantern": {
		"poach": "%s has been unhappy, child. I notice these things. Pay them, or I will, and then we'll both know who listens. — Mother Ilse",
		"challenge": "I've told the taverns you can seal a Rank %s rift by payday. Don't make an old woman a liar. — Ilse",
		"snatch": "The Wolves will try for this one tomorrow. Take it first and I'll know you can be trusted with better news. Let it go and I'll take it, and I'll know that too. — Ilse",
		"taunts": ["Mother Ilse sends her regards to %s, and a small bill.", "Everyone owes the Lantern something. %s just doesn't know what yet.", "The Lantern hears %s is short this week. The Lantern lends."]},
	"The Hollow Crown Company": {
		"poach": "%s deserves a company that values them. Ours does: twice the wage, half the danger. I can't explain the half. Trade secret. — Capt. Morrow",
		"challenge": "Rank %s by payday? A friendly wager. There is always another rift, after all. We make sure of it. — Morrow",
		"snatch": "We'll take this one off your hands. Plenty of work for everyone; there always seems to be, near us. — Morrow",
		"taunts": ["Plenty of work for everyone, %s. There always is.", "The Company wishes %s a quiet week. Truly.", "Captain Morrow sent %s a bottle of good wine. No note."]},
}

## The Guildhold Chronicle: a short scene at the pay table every payday,
## between Wen (the Chronicler), Dobbs (the Quartermaster) and Old Hesper
## (the last of an Accord guild; she had a fever on the Night of Breaking).
## GameState._payday_scene picks one by what happened that week.
const PAYDAY_SCENES := {
	"first": [["Dobbs", "First payday. I'm Dobbs; I keep the books. The one with the ink is Wen."], ["Wen", "I write down what happens. Try to make it worth writing."], ["Hesper", "And I'm the old woman who was here before both of them. Pay your heroes and they'll stay."]],
	"walkout": [["Dobbs", "Someone walked out today."], ["Hesper", "Unpaid twice, or miserable. Usually both."], ["Wen", "I'll write that they left. I won't write why. That's yours to fix."]],
	"lost": [["Wen", "I've added a name to the Memorial."], ["Hesper", "Say it out loud once. It helps."], ["Dobbs", "I'll take them off the payroll. Quietly."]],
	"unpaid": [["Dobbs", "We're short. I want that written down, Wen."], ["Wen", "It's written down. It was written down last week, too."], ["Dobbs", "Then underline it."]],
	"feast": [["Hesper", "Good feast."], ["Dobbs", "Expensive feast."], ["Wen", "I'm writing 'good'."]],
	"we_lead": [["Wen", "The herald wrote our name first this week."], ["Dobbs", "Did the herald pay anything?"], ["Wen", "No."], ["Dobbs", "Then it's ink."]],
	"they_lead": [["Dobbs", "Our rivals bought new banners."], ["Hesper", "The Accord never had banners."], ["Dobbs", "The Accord is gone."], ["Hesper", "Yes. Well."]],
	"rich": [["Dobbs", "The vault is full. I don't trust it."], ["Hesper", "Spend it on the heroes, then. Gold never closed a rift."], ["Dobbs", "Gold paid the ones who did."]],
	"accord": [["Wen", "These ledger pages. Hesper, did you know the Grandmaster?"], ["Hesper", "Everyone knew her. Nobody knew her."], ["Wen", "That isn't an answer."], ["Hesper", "It's the only one she ever gave."]],
	"quiet1": [["Hesper", "Nobody hurt this week."], ["Wen", "That's not a story."], ["Hesper", "It's the best kind. You'll learn."]],
	"quiet2": [["Wen", "Hesper, what were the old guilds like?"], ["Hesper", "Louder. Better paid. Gone."]],
	"quiet3": [["Dobbs", "Wages, upkeep, and a bill for a broken door."], ["Wen", "Which door?"], ["Dobbs", "The one someone kicked in after the last rift. I'm not saying who."]],
	"quiet4": [["Hesper", "I sat the Assay at sixteen. The stone barely glowed."], ["Wen", "What rank?"], ["Hesper", "F. I'm still here. Most of the S's aren't."]],
	"quiet5": [["Wen", "I need another word for 'rift'. I've used it four hundred times."], ["Dobbs", "Use 'expense'."]],
	"quiet6": [["Dobbs", "The recruits ask what the Accord was."], ["Hesper", "Tell them it was a promise. Tell them we're keeping it."], ["Dobbs", "Are we?"], ["Hesper", "Ask me next payday."]],
	# A past guild from the Hall of Guilds ({guild}; {hero}: one it remembered).
	"past_paytable": [["Hesper", "{guild} paid on the seventh, too. Rain or not."], ["Wen", "You never said you knew them."], ["Hesper", "You never asked who taught you the pay table."]],
	"past_banner": [["Wen", "Someone left flowers under the {guild} banner."], ["Dobbs", "Who pays for flowers?"], ["Hesper", "Nobody. That's how you know they mean it."]],
	"past_books": [["Dobbs", "{guild} spent less on feasts than we do."], ["Hesper", "And kept fewer heroes."], ["Dobbs", "I hate it when the books agree with you."]],
	"past_hero": [["Wen", "{hero} is all over the old {guild} ledgers. Rift after rift."], ["Hesper", "{hero} carried me home from the Marches once. Don't write that down."], ["Wen", "Already have."]],
	"past_renew": [["Wen", "Who goes down to the forty-first post now that {guild} is gone?"], ["Hesper", "We do. Once a year, on the Night of Breaking."], ["Dobbs", "I'll put it in the ledger. No charge."]],
	"past_break": [["Dobbs", "The tides got worse after {guild} burned the Terms."], ["Hesper", "The tides got honest."], ["Dobbs", "Honest costs more."]],
	"past_retired": [["Wen", "{guild} just stopped. Do guilds do that?"], ["Hesper", "The good ones stop. The rest get stopped."], ["Wen", "Which were they?"], ["Hesper", "Look at their banner. It's still up."]],
}
## How often a quiet payday turns to a past guild, once the Hall of Guilds has one.
const PAST_SCENE_CHANCE := 0.4

## The Broken Accord: a champion freed from the Endless Rift leaves a post
## empty, and the next Riftbreak comes this many days sooner.
const EMPTY_POST_DAYS := 1
const EMPTY_POST := {"title": "An empty post", "subtitle": "The Endless Rift",
	"text": "The pillar is dark now. Somewhere in the Vale, a rift that has been quiet for twenty years draws breath. You did the right thing. The Hollow noticed.\n\n(Each champion freed in the Endless Rift brings the next Riftbreak a day sooner.)"}

## Act IV's finale grows with every post the guild has emptied (lost
## champions freed in the Endless Rift).
const TERMS_PER_POST := 0.05
## The Broken Accord's ending, chosen after Act IV. Renew: a hero takes the
## forty-first post and Riftbreaks end. Break: every post is released (every
## champion of this guild freed) and the Hollow rises: Riftbreaks come twice
## as often.
const ACCORD_CHOICE := {"title": "The last signature", "subtitle": "The Accord Hall",
	"text": "The Terms lie open on the floor of the Hall: forty-one lines, forty signed. Sign the last, and one of your heroes takes the forty-first post forever; the rifts close for good. Or burn it, and every post is released at once; the champions come home, and the Hollow comes up with them.",
	"choices": ["renew", "break"]}
const ACCORD_ENDING := {
	"renew": {"title": "The Accord renewed", "subtitle": "%s holds the forty-first post",
		"text": "The Hall is quiet. Up in the Vale the villagers wake to a morning without a single rift on the horizon, and do not know why. The guild knows. Every year, on the Night of Breaking, someone climbs down to the forty-first post and tells %s how the harvest went.\n\n(Riftbreaks have ended. The Endless Rift, the ladder and the quests carry on.)"},
	"break": {"title": "The Accord broken", "subtitle": "Every post released",
		"text": "The Terms burn green. Forty pillars go out at once, and forty people step into the dark and start walking home. Behind them, the Hollow rises to meet the sky. It will be a hard century. It will be an honest one.\n\n(Every champion of the old guilds is free. Riftbreaks come twice as often.)"},
}
const CHRONICLE_ENDING := {
	"renew": ["The forty-first post", "Your guild signed the Terms. %s took the forty-first post, and the Hollow stays below. The rifts that remain are old ones, and quiet."],
	"break": ["The Terms burned", "Your guild burned the Terms. Every post was released, the old guilds came home, and the Hollow came up with them. The rifts are louder now, and nobody holds them shut but the guilds."],
}


## What the Rifts Take (a side thread): from Act II, a sealed rift sometimes
## leaves an echo, Essence that holds one thing the Hollow took. Give it back
## to the village (Renown, and a scene) or keep it (Essence).
const ECHO_CHANCE := 0.12
const ECHO_RENOWN := 3
const ECHOES := [
	{"id": "name", "title": "A Child's Name", "text": "This Essence will not settle. It keeps the shape of a word. The miller's wife in Hollin heard about it and walked here in the rain: her son went into the Breach on the Night of Breaking, and she cannot remember what she called him.",
		"returned": "She holds the crystal to her ear, then says the name out loud, twice, as if checking it still fits. She does not thank you. She does not need to."},
	{"id": "street", "title": "A Street", "text": "The Essence from the last rift has a street in it: cobbles, a bakery, a blue door. A carter in the village swears it is the street he grew up on, in a town the Vale forgot.",
		"returned": "He walks the street in his head all evening, door by door. In the morning he paints his own door blue."},
	{"id": "song", "title": "A Song", "text": "This Essence hums. The old women in the village know the tune and none of the words. The words were in the rift.",
		"returned": "By nightfall the whole village is singing it, words and all, a little off-key. Wen writes them down."},
	{"id": "face", "title": "A Face", "text": "There is a face in this crystal, young and stern, in an Accord ranger's green. The village elder asks to see it and goes very quiet.",
		"returned": "'My sister,' the elder says. 'I had forgotten I had one.' The crystal goes home with them and sits in the window."},
	{"id": "bread", "title": "A Recipe", "text": "This Essence smells of bread. The innkeeper says her grandmother's loaf tasted like this, before the Night took the recipe out of everyone's heads.",
		"returned": "The inn smells of it for a week. Your heroes eat there free for the rest of the month, and nobody counts."},
	{"id": "oath", "title": "An Oath", "text": "The words in this crystal are the Accord's oath, spoken in a voice nobody living remembers. Old Hesper asks to hold it.",
		"returned": "Hesper holds it a long time. 'That was the Grandmaster,' she says, 'before.' She gives it to the village shrine and does not speak of it again."},
]

## The Guildhold Chronicle: when a hero's Path first forks into a calling
## (their Rank B evolution), a short scene by their voice (%s: the hero,
## then the calling).
const CALLING_SCENES := {
	"bold": "Hesper watches %s split the training post and keep swinging at the stump. 'The Path is choosing for you,' she says. 'You could let it.' They let it. Wen writes a new word under their name: %s.",
	"swift": "%s used to be first into every rift and first out. This week they stayed behind to walk the slowest hero home. Hesper calls that the moment a Path forks. Wen writes the new word down: %s.",
	"stoic": "%s says nothing about it at all. They turn up at the pay table one morning carrying themselves differently, and Hesper nods as if a debt has been paid. Wen asks what to write. Hesper says: %s.",
	"wary": "%s didn't want it. The Essence settled anyway, the way rain settles on a roof. Hesper sits with them until dark. 'Nobody's ready,' she says. 'The good ones are scared.' Wen writes: %s.",
	"devout": "%s prays before every rift, and this time the answer came back as a shape. Hesper says the Vow always answers in its own time. Wen writes it in the chronicle in her best hand: %s.",
	"arcane": "%s has been taking notes on their own Essence for weeks. The notes end mid-sentence on the day it settled. Wen copies the last line into the chronicle and adds the new word: %s.",
}


## The Charter War's turn (Act III opens): Mother Ilse brings proof that the
## Hollow Crown Company has been opening rifts. Expose it (Renown, and the
## Company strikes back with a Riftbreak at your door) or keep quiet (its
## contracts pay you more, against the Accord's oath).
const CHARTER_EXPOSE_RENOWN := 10
const CHARTER_QUIET_PAY := 1.25     # contract Gold, keeping quiet
const CHARTER_PAY := 1.2            # contract Gold and Essence, holding the Royal Charter
const CHARTER_TURN := {"kind": "charter", "title": "Mother Ilse's page", "subtitle": "The Charter War",
	"text": "Mother Ilse of the Last Lantern finds you after dark with a page torn from the Hollow Crown Company's books: a list of rifts, each with a date, a price, and the word opened. Captain Morrow has been opening rifts and selling the contracts to close them.\n\nShe will give it to the Crown's herald if you ask. Or the Company will pay well for a guild that keeps quiet, and its contracts would come to you.",
	"choices": ["expose", "quiet"]}
const CHARTER_RESULT := {
	"expose": {"title": "The Company exposed", "subtitle": "The Charter War",
		"text": "The herald reads Morrow's page aloud in the square. By evening the Hollow Crown Company's banners are down in three villages. By morning a rift has opened on the road to your camp, which is how you know the page was real.\n\n(+10 Renown. A Riftbreak is coming to your door.)"},
	"quiet": {"title": "A quiet arrangement", "subtitle": "The Charter War",
		"text": "Morrow's contracts start arriving on your board, generous ones. Hesper reads the first, folds it, and doesn't say anything. She doesn't have to.\n\n(Contracts pay 25% more Gold for the rest of the campaign.)"},
}
## The Crown's hearing (Act III ends): the Royal Charter goes to the guild
## that leads on Renown (%s: the rival, twice, when they win it).
const CHARTER_HEARING := {
	"won": {"title": "By Royal Hand", "subtitle": "The Royal Charter is yours",
		"text": "The herald reads one name, and it is yours. Orla Venn is the first to shake your hand; Kael Ashborn asks for a job; Mother Ilse is already gone, which is how you know she was pleased. The Charter hangs in your hall, and the villages bring their troubles to a door they know.\n\n(Contracts pay 20% more Gold and Essence.)"},
	"lost": {"title": "By Royal Hand", "subtitle": "The Charter goes to %s",
		"text": "The herald reads a name, and it isn't yours. %s hangs the Royal Charter in their hall. The rifts don't care whose name is on the wall. Neither, in the end, do the villagers, as long as somebody comes."},
}

## The Guildhold Chronicle: when a bond reaches its last level, Wen writes
## the pair down together (%s, %s: the two heroes).
const BOND_SCENES := [
	"%s and %s have stopped needing to talk in a fight. Wen noticed first. She has started writing their names in the chronicle as one entry, with an ampersand, and neither of them has complained.",
	"%s and %s sat up past the last candle arguing about a fight they won. Dobbs charged the guild for the candle. Hesper paid it herself and told him to let them be.",
	"Ten rifts together. %s still can't say %s's full name right, and %s still lets it go. Wen has written down both versions.",
	"%s took a hit meant for %s last week and has refused to talk about it since. Wen has written it down anyway. Hesper says that's how the old guilds started.",
]
## Wen's line on the Memorial, by the hero's voice (%s: their name).
const MEMORIAL_LINES := {
	"bold": ["%s went first into every rift. Somebody had to.", "%s never once asked how deep a rift went before stepping in."],
	"swift": ["%s was always first out of the rift, and always went back for whoever wasn't.", "%s never sat still at the pay table. The chair is still pushed back."],
	"stoic": ["%s said very little and meant all of it.", "%s held the line. That is the whole entry, and it is enough."],
	"wary": ["%s was afraid of every rift and walked into all of them.", "%s checked every strap twice. It wasn't the straps."],
	"devout": ["%s prayed before every rift. We hope someone answered.", "%s kept the candles lit in the hall. We have kept them lit since."],
	"arcane": ["%s left a notebook full of questions. Wen is working through them.", "%s understood the Hollow better than any of us, and went to see it anyway."],
}


## The Charter War's last move. A guild that exposed the Hollow Crown
## Company has made an enemy: from Act III its sellswords sometimes ambush
## the guild's rifts, and Captain Morrow waits at the bottom of the next
## Rank C+ rift, holding the key he opens rifts with. Beat him and the
## Company is finished.
const COMPANY_AMBUSH_CHANCE := 0.25
const COMPANY_AMBUSH := {"name": "Company Ambush", "min_floor": 0,
	"hint": "Morrow's sellswords, sent to settle a debt. The crossbowman snipes from the back; close on him first.",
	"members": [["Company Sellsword", 0.4, 0.4], ["Company Sellsword", 0.3, 0.3], ["Company Crossbowman", 0.3, 0.4]]}
const MORROW_BOSS := "Captain Morrow, of the Hollow Crown"
const MORROW_REWARD := {"coins": 300, "reputation": 10}
const MORROW_WAITS := {"title": "Morrow is waiting", "text": "Word comes as you set out: Captain Morrow is at the bottom of this rift, and he has brought friends."}
const MORROW_DOWN := {"title": "Morrow's key", "subtitle": "The Charter War",
	"text": "Morrow goes down laughing, which is somehow worse. On his belt hangs an old iron key with the Accord's sigil: the key Pip swears she stole from a rift-lord, and the one he has been opening rifts with. By the end of the week the Company's banners are gone from the Vale.\n\n(+300 Gold, +10 Renown. No more Company ambushes.)"}


## What the Rifts Take, followed up. A kept echo may touch a hero (they
## recognise what's in it; the Echo-Touched quirk). The third echo brings
## Ezra the Pale, and the campaign's end says what the Vale remembers, both
## by how much was given back.
const ECHO_TOUCH_CHANCE := 0.5
## What each echo holds, for the scene ("There was %s in it").
const ECHO_HOLDS := {"name": "a child's name", "street": "a street with a blue door", "song": "a song",
	"face": "a young ranger's face", "bread": "the smell of bread", "oath": "the Accord's oath"}
const ECHO_TOUCH := {"title": "%s remembers", "subtitle": "An echo, kept",
	"text": "%s has been quiet since you kept the echo. There was %s in it, and %s knew it, from a life they don't remember living.\n\n(%s is Echo-Touched: +6%% ability power.)"}
const EZRA_VISIT := {
	"gave": {"title": "Ezra the Pale", "subtitle": "What the Rifts Take",
		"text": "A pale man with a lantern has been following the echoes. Ezra studies what the rifts take from people, and he keeps a little of it in the lantern, for safekeeping. He asks what you did with yours. When you tell him, he bows, which nobody in the Vale has seen him do."},
	"kept": {"title": "Ezra the Pale", "subtitle": "What the Rifts Take",
		"text": "A pale man with a lantern has been following the echoes. Ezra studies what the rifts take from people. He asks to see your vault, goes very still, and asks how much of it you have spent, and on what, and whether you kept a list. 'It was yours to spend,' he says at the door. 'I hope it was worth what it cost them.'"},
}
const VALE_REMEMBERS := {
	"gave": {"title": "What the Vale remembers", "subtitle": "What the Rifts Take",
		"text": "In the weeks after, people stop in the street and say names out loud. A song nobody knew is sung at every harvest. The empty guild halls fill with flowers, and yours gets the most, from people who never met you."},
	"kept": {"title": "What the Vale remembers", "subtitle": "What the Rifts Take",
		"text": "Something leaves the Vale with the last of the rifts, quietly, and nobody can say what. Your guild is the strongest the Vale has ever had. Ezra's lantern is found on your doorstep one morning, empty, with no note."},
}
## The Guildhold Chronicle: a hero's fiftieth sealed rift (%s: the hero).
const FIFTY_RIFTS := [
	"Wen asks %s for a line for the chronicle: something learned in fifty rifts. %s thinks about it for a long time. 'Bring more bandages than you think,' they say. Wen writes it down exactly.",
	"Fifty rifts. Dobbs works out what %s has cost the guild in wages and what they have brought home, then quietly tears up the page. Wen asks why. 'Some sums you don't show anyone,' says Dobbs. %s pretends not to hear.",
	"Hesper gives %s her old Accord pin for their fiftieth rift. It is bent and tarnished and nobody has ever seen her take it off. %s wears it on the inside of their coat.",
]

## Founding charters ("The Vale Remembers", section 2): what kind of guild
## this is, picked at founding. Each rule is a multiplier read where that
## system pays out (GameState.founding_rule). Free Company is today's game;
## the others unlock with Laurels or by a deed in a past guild.
const FOUNDINGS := {
	"free": {"name": "Free Company", "desc": "As the Vale knows guilds: three heroes and 280 Gold."},
	"mercenary": {"name": "Mercenary Company", "gold": 320, "contract_gold": 1.2, "wages": 1.15, "renown": 0.8, "laurels": 25,
		"desc": "Hired swords: start with 600 Gold. Contracts pay 20% more Gold, wages are 15% higher, and Renown comes 20% slower. The Hollow Crown Company will make you an offer."},
	"temple": {"name": "Temple Order", "gold": -80, "wages": 0.8, "recover": 1, "echo_renown": 2.0, "echo_essence": 0.5, "laurels": 25,
		"desc": "Sworn to mend: start with 200 Gold. Wages are 20% lower and downed heroes are back a run sooner. An echo given back earns twice the Renown; one kept, half the Essence."},
	"smugglers": {"name": "The Lantern's Smugglers", "gold": 70, "prices": 0.25, "quiet_pay": 1.4, "laurels": 30, "deed": "quiet",
		"desc": "Mother Ilse's people: start with 350 Gold. Shop prices are 25% lower, the Last Lantern is never your rival, and keeping quiet in the Charter War pays 40% more Gold instead of 25%."},
	"accord": {"name": "Last of the Accord", "ledger": 2.0, "breach_sooner": 1, "deed": "ending",
		"desc": "Old Hesper's own guild: the Grandmaster's ledger pages turn up twice as often, but the Hollow knows you, and Riftbreaks come a day sooner."},
}
## How a charter is unlocked by a deed (a guild in the Hall of Guilds did it).
const FOUNDING_DEEDS := {"quiet": "Kept quiet in a Charter War", "ending": "Finish a campaign"}
## The Last of the Accord's own prologue (instead of PROLOGUE).
const ACCORD_PROLOGUE := {"title": "The Night of Breaking", "subtitle": "Old Hesper remembers",
	"text": "Hesper had a fever on the Night of Breaking and missed it. Every other guild of the Accord went into the rifts that night, hers too, and none came back. Twenty years on she has a hall again, three recruits, and the old oath: close what opens, share what you find, never sell a rift. She means to keep it this time."}
## A Mercenary Company's Act II: the Hollow Crown Company comes calling.
const MERCENARY_OFFER := {"title": "An offer from the Company", "subtitle": "Captain Morrow",
	"text": "Captain Morrow sends a man with a ledger and a good coat. The Hollow Crown Company would take your contracts off your hands, and your guild with them, at a fair price. He leaves the paper on the table. Nobody signs it. Dobbs reads it twice."}

## Oaths ("The Vale Remembers", section 3): optional vows sworn at founding,
## each harder in one way and worth more Laurels (+%, capped). They can't be
## dropped; the Hall of Guilds shows which a guild kept.
const OATHS := {
	"never_sell": {"name": "Never Sell a Rift", "laurels": 0.10, "desc": "The Accord's own rule: in the Charter War, keeping quiet is not an option."},
	"by_hand": {"name": "By Hand", "laurels": 0.15, "desc": "No Quick fight: every fight is played, or set to Auto."},
	"lean_purse": {"name": "Lean Purse", "laurels": 0.15, "desc": "Wages are 50% higher."},
	"no_rest": {"name": "No Rest", "laurels": 0.10, "desc": "Medical Bay beds don't speed recovery."},
	"hollow_touched": {"name": "Hollow-Touched", "laurels": 0.20, "desc": "Every foe has 15% more health."},
	"long_watch": {"name": "The Long Watch", "laurels": 0.15, "desc": "Riftbreaks come twice as often."},
}
const OATH_LAURELS_CAP := 0.6

## The ending sets the postgame ("The Vale Remembers", section 4).
## Renew: Keepers of the Vale. Seven halls of the old Accord guilds stand
## empty; restoring one costs Gold and Essence (more for each one before
## it) and gives a lasting bonus. The Grandmaster's comes last.
const ACCORD_HALLS := [
	{"id": "iron_oath", "name": "Hall of the Iron Oath", "kind": "slots", "value": 1, "bonus": "+1 hero slot",
		"text": "The Iron Oath trained shield-walls. Their drill yard is still marked out in white stones, and Hesper walks it once, end to end, before she lets the recruits in."},
	{"id": "green_hand", "name": "Hall of the Green Hand", "kind": "beds", "value": 1, "bonus": "+1 Medical Bay bed",
		"text": "The Green Hand were healers. Their shelves still smell of feverfew. Wen finds a ledger of everyone they ever patched up, and reads names out loud for an hour."},
	{"id": "quiet_coin", "name": "Hall of Quiet Coin", "kind": "gold", "value": 0.10, "bonus": "Contracts pay 10% more Gold",
		"text": "Quiet Coin kept the Accord's accounts. Dobbs is in their counting room before the dust settles, and comes out holding a pen like a holy relic."},
	{"id": "ninth_lamp", "name": "Hall of the Ninth Lamp", "kind": "essence", "value": 0.10, "bonus": "Contracts pay 10% more Essence",
		"text": "The Ninth Lamp studied Essence. Their lamps still hold a little of it, and light themselves when someone they would have liked walks in."},
	{"id": "long_roads", "name": "Hall of Long Roads", "kind": "wages", "value": 0.10, "bonus": "Wages 10% lower",
		"text": "Long Roads took in strays and taught them a trade. Word gets around: heroes ask to work for the guild that opened it again, and ask for less."},
	{"id": "open_hand", "name": "Hall of the Open Hand", "kind": "prices", "value": 0.10, "bonus": "Shop prices 10% lower",
		"text": "The Open Hand traded with every village in the Vale. The merchants remember the sign over the door, and start giving the guild their old prices."},
	{"id": "grandmaster", "name": "The Grandmaster's Hall", "kind": "title", "value": 0, "bonus": "The title Keepers of the Vale, and 20 Laurels",
		"text": "The last hall is the one the Accord was sworn in. Its doors open with the key Pip stole from Morrow. Inside is a long table, forty-one chairs, and one that someone has dusted every year. The Vale has its keepers again."},
]
## Sim (0.35.3): at 5000/2000 +3000/1500 and 25000/12000 strong guilds took
## ~110 days for all seven and sat on 47k unspent Essence; now ~45k Gold and
## ~40k Essence in all.
const HALL_COST := [3000, 2500]          # the first hall: Gold, Essence
const HALL_COST_STEP := [1000, 1000]     # each hall after it costs this much more
const GRANDMASTER_HALL_COST := [12000, 10000]
const GRANDMASTER_LAURELS := 20
## Break: the Open Hollow. Every TIDE_DAYS a tide breaks over the Vale, a
## Riftbreak of Rank A strength that grows TIDE_GROWTH with each tide held
## (a lost one doesn't make the next harder). It can't be closed early;
## holding it pays TIDE_LAURELS.
const TIDE_DAYS := 7
const TIDE_WARN := 3   # a tide swells this many days before it breaks
const TIDE_RANK := "A"
## Sim (0.35.3): a strong guild holds x2.0 and loses x2.5 by day 90 (so its
## wall is around tide 8-11); a casual one lost tide 4 (x1.3 at 10%).
var TIDE_GROWTH := 0.15   # a var so the balance sim can try others (tide_growth=)
const TIDE_LAURELS := 2
## Tidewalls: the Open Hollow's Gold sink (Break guilds sat on 50-120k idle
## Gold). Each wall makes every tide TIDEWALL_STEP weaker against the guild
## (strength / (1 + step x walls)); no cap, the cost rises with each.
const TIDEWALL_STEP := 0.06
const TIDEWALL_COST := [4000, 2000]        # the first wall: Gold, Essence
const TIDEWALL_COST_STEP := [2000, 1000]   # each wall after it costs this much more
## The Chronicle as a completion board once the legacy is written: each line
## finished afterwards adds BOARD_LAURELS to the legacy.
const BOARD_LAURELS := 2
const COMPLETION_BOARD := [
	{"id": "champions", "label": "Every champion freed"},
	{"id": "ledger", "label": "Every page of the Grandmaster's ledger"},
	{"id": "echoes", "label": "Every echo answered"},
	{"id": "morrow", "label": "Captain Morrow beaten"},
	{"id": "charter", "label": "The Royal Charter won"},
	{"id": "halls", "label": "Every Accord hall restored", "ending": "renew"},
	{"id": "tides", "label": "Five tides of the Open Hollow held", "ending": "break"},
]
