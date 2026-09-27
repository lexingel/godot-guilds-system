extends "res://scripts/autoload/game_data/GameDataItems.gd"
## GameData, part 4: foes — boss mechanics, monster abilities, hazards, names, biomes, armor/statuses/wind-ups, hero voices, boss phases and elite affixes.

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
	# Content depth: foes built around the telegraphed moves (MONSTER_KIT).
	"Hedge Warden": {"kind": "shielded", "name": "Thorn Bulwark", "value": 0.25},
	"Leech Priest": {"kind": "healer", "name": "Leech Blessing", "value": 0.12},
	"Ember Oracle": {"kind": "shielded", "name": "Ash Veil", "value": 0.2},
	"Ash Harrier": {"kind": "frenzy", "name": "Cornered Fury", "value": 0.4},
	"Rootbound Thrall": {"kind": "drain", "name": "Root Grasp", "value": 0.25},
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
const MONSTER_NAMES := ["Gloom Stalker", "Rift Wisp", "Husk Brute", "Sable Fang", "Ember Whelp", "Marrow Crawler", "Hollow Reaver", "Cinder Moth", "Bog Wretch", "Silt Crawler", "Glass Wisp", "Mirror Fiend", "Frost Stalker", "Ashclad Ghoul", "Deep Anchorite", "Voidling Sprite",
	"Hedge Warden", "Carrion Crier", "Rootbound Thrall", "Leech Priest", "Mire Sniper", "Drowned Bellringer", "Slag Golem", "Ember Oracle", "Ash Harrier"]
const ELITE_NAMES := ["Warbound Elite", "Blightfang Elite", "Rift-Touched Colossus", "Iron Revenant", "Storm-Called Elite", "Ashen Broodlord"]
const BOSS_NAMES := ["Vaelith", "Korrath", "Nyxara", "Drevok", "Sythrane"]

## Biomes: each rift is in one, which sets its foes and arenas (indices into
## BATTLE_BACKGROUNDS). A finale fights in its act's biome; other rifts pick
## from the biomes the campaign has reached (GameState.pick_biome).
const BIOMES := {
	"vale": {"name": "The Shattered Vale", "monsters": ["Gloom Stalker", "Sable Fang", "Husk Brute", "Rift Wisp", "Marrow Crawler", "Hollow Reaver", "Hedge Warden", "Carrion Crier", "Rootbound Thrall"],
		"elites": ["Warbound Elite", "Iron Revenant"], "retinue": ["Hedge Warden", "Carrion Crier", "Rift Wisp"], "backgrounds": [1, 3, 0]},
	"marsh": {"name": "The Drowned Marches", "monsters": ["Bog Wretch", "Silt Crawler", "Frost Stalker", "Glass Wisp", "Mirror Fiend", "Deep Anchorite", "Leech Priest", "Mire Sniper", "Drowned Bellringer"],
		"elites": ["Blightfang Elite", "Storm-Called Elite"], "retinue": ["Leech Priest", "Mire Sniper", "Drowned Bellringer"], "backgrounds": [5, 6, 2]},
	"ashen": {"name": "The Ashen Wastes", "monsters": ["Ember Whelp", "Cinder Moth", "Ashclad Ghoul", "Voidling Sprite", "Hollow Reaver", "Mirror Fiend", "Slag Golem", "Ember Oracle", "Ash Harrier"],
		"elites": ["Ashen Broodlord", "Rift-Touched Colossus"], "retinue": ["Ember Oracle", "Ash Harrier", "Cinder Moth"], "backgrounds": [4, 8, 7, 9]},
}
const ACT_BIOME := {1: "vale", 2: "marsh", 3: "ashen"}

## Armor: the share of every basic attack an armored foe shrugs off. Each hit
## that lands chips it by ARMOR_SUNDER; abilities, relic strikes and counters
## ignore it.
const MONSTER_ARMOR := {"Hedge Warden": 0.3, "Slag Golem": 0.4, "Husk Brute": 0.35, "Hollow Reaver": 0.3, "Deep Anchorite": 0.35, "Iron Revenant": 0.4,
	"Warbound Elite": 0.3, "Rift-Touched Colossus": 0.35, "Korrath": 0.3, "Drevok": 0.25}
const ARMOR_SUNDER := 0.05

## Statuses foes inflict on a hit (chance per hit): burn deals `value` of max
## HP per round for `rounds`; chill makes the hero act late next round. A
## heavy blow stuns (the hero loses their next turn) unless they Defended.
const MONSTER_STATUS := {"Ember Oracle": "burn", "Slag Golem": "burn", "Ash Harrier": "burn", "Drowned Bellringer": "chill", "Ember Whelp": "burn", "Cinder Moth": "burn", "Ashclad Ghoul": "burn", "Ashen Broodlord": "burn",
	"Frost Stalker": "chill", "Glass Wisp": "chill", "Storm-Called Elite": "chill", "Nyxara": "chill", "Sythrane": "burn"}
const STATUS_INFO := {"burn": {"chance": 0.5, "rounds": 3, "value": 0.05}, "chill": {"chance": 0.5, "rounds": 1}}

## Wind-ups: some foes spend a turn gathering strength, then land a heavy
## blow (HEAVY_BLOW_MULT damage + stun). The intent tag warns a turn ahead.
const WINDUP_CHANCE := {"boss": 0.35, "elite": 0.3, "brute": 0.25}
const WINDUP_BRUTES := ["Husk Brute", "Deep Anchorite", "Hollow Reaver", "Rootbound Thrall", "Slag Golem"]
const HEAVY_BLOW_MULT := 3.0

## ---------------- Hero voices ----------------
## A hero's born quirk sets how they talk (GameData.hero_voice); they speak up at a few fight moments
## (Combat._bark) and on the victory screen.
const VOICE_NAME := {"bold": "Bold", "swift": "Quick", "stoic": "Stoic", "wary": "Nervous", "devout": "Devout", "arcane": "Scholarly"}
const BARKS := {
	"bold": {
		"kill": ["Next!", "Too easy.", "Who's next in line?"],
		"low_hp": ["Just a scratch!", "That all you've got?", "I've had worse at breakfast."],
		"ally_down": ["You'll pay for that!", "Hold on, I'll finish this!", "Stay down, I've got it!"],
		"victory": ["Ha! Another one for the wall.", "Is that the best the Rift can do?", "Point me at the next one."],
		"level_up": ["Stronger. Good.", "Now we're talking.", "Bring on something bigger."],
	},
	"swift": {
		"kill": ["Blink and you missed it.", "Clean.", "Right where I aimed."],
		"low_hp": ["Too slow on that one...", "Need to keep moving!", "Close. Too close."],
		"ally_down": ["Man down! Covering!", "I'll draw them off!", "Get up, get up!"],
		"victory": ["Fast work.", "Home before supper.", "They never saw us coming."],
		"level_up": ["Quicker every day.", "Feeling light on my feet.", "Watch this."],
	},
	"stoic": {
		"kill": ["It's done.", "One less.", "Stay down."],
		"low_hp": ["I can still stand.", "Not yet.", "I hold."],
		"ally_down": ["I'll hold the line.", "Rest. I'll carry this.", "Steady. We finish it."],
		"victory": ["The line held.", "We endure.", "Another day."],
		"level_up": ["Steady progress.", "I feel it. Good.", "The work pays off."],
	},
	"wary": {
		"kill": ["Did... did I do that?", "Oh, thank the stars.", "Is it dead? It's dead."],
		"low_hp": ["I don't want to die here!", "Help! Anyone?", "This was a terrible idea."],
		"ally_down": ["No, no, no, get up!", "Should we run? We should run.", "They got them!"],
		"victory": ["We lived! We actually lived!", "Can we go home now?", "Never again. Probably."],
		"level_up": ["Huh. I'm getting better at this.", "Maybe I'm not so bad after all.", "Did I just get stronger?"],
	},
	"devout": {
		"kill": ["Rest now.", "The light judges you.", "Forgiven, and gone."],
		"low_hp": ["Grant me strength...", "My faith holds, if my body won't.", "Not while they need me."],
		"ally_down": ["I'm coming, hold on!", "Light, keep them!", "Don't you dare give up!"],
		"victory": ["Light guide us home.", "We were spared. Give thanks.", "Let's tend the wounded."],
		"level_up": ["A blessing.", "I am given more to give.", "My purpose grows clearer."],
	},
	"arcane": {
		"kill": ["Unmade.", "Just as I calculated.", "Fascinating. Was."],
		"low_hp": ["Variables... unfavorable.", "The weave is fraying. So am I.", "I need a moment to recompute!"],
		"ally_down": ["That was not in the plan!", "Recalculating!", "Someone get them up!"],
		"victory": ["A tidy result.", "Worth a page in my notes.", "The Rift has patterns. I see them now."],
		"level_up": ["The equations open up.", "More power. Excellent.", "I understand more now."],
	},
}

## ---------------- Boss phases & elite affixes ----------------
## Every boss turns once, at half health: one of these, rolled at fight start
## and shown on its plate so the player can plan for it.
const BOSS_PHASE_AT := 0.5
const BOSS_PHASES := {
	"summon": {"name": "Call the Horde", "desc": "At half health, two foes answer its call.", "line": "%s howls, and the rift answers with reinforcements!", "icon": "res://assets/skills/icon_boss_skull.png"},
	"fury": {"name": "Fury", "desc": "At half health it hits 20% harder and winds up heavy blows more often.", "line": "%s roars in fury!", "icon": "res://assets/skills/sword_dual.png"},
	"barrier": {"name": "Last Bastion", "desc": "At half health it raises a ward worth 12% of its health.", "line": "%s raises a shimmering barrier!", "icon": "res://assets/skills/shield_basic.png"},
}

## Elites roll one affix (two in Endless and B-rank+ mapped rifts), each
## costing them 15% HP. Each rides an existing channel: a monster ability,
## armor, a status, or extra adds.
const ELITE_AFFIXES := {
	"vampiric": {"name": "Vampiric", "desc": "Heals for 25% of the damage it deals.", "icon": "res://assets/skills/dagger_red.png", "ability": {"kind": "drain", "name": "Vampiric", "value": 0.25}},
	"thorned": {"name": "Thorned", "desc": "Reflects 15% of the damage it takes back at the attacker.", "icon": "res://assets/skills/shield_blue.png", "ability": {"kind": "reflect", "name": "Thorned", "value": 0.15}},
	"shielded": {"name": "Shielded", "desc": "Starts behind a ward worth 20% of its health.", "icon": "res://assets/skills/shield_orange.png", "ability": {"kind": "shielded", "name": "Shielded", "value": 0.2}},
	"venomous": {"name": "Venomous", "desc": "Its hits poison.", "icon": "res://assets/skills/shard_green.png", "ability": {"kind": "poison", "name": "Venomous", "value": 0.06}},
	"juggernaut": {"name": "Juggernaut", "desc": "Heavily armored: shrugs off 35% of basic attacks.", "icon": "res://assets/skills/armor_chest.png", "armor": 0.35},
	"blazing": {"name": "Blazing", "desc": "Its hits can set heroes ablaze.", "icon": "res://assets/relics/escalate_pct.png", "status": "burn"},
	"hasted": {"name": "Hasted", "desc": "Acts twice each round (each hit a little weaker) and never winds up.", "icon": "res://assets/skills/boots.png", "hasted": true},
	"commander": {"name": "Commander", "desc": "Always brings two (weaker) escorts.", "icon": "res://assets/skills/helm.png", "adds": 2},
}


# ---------------- Enemy intents ----------------
## Foes whose names read as ranged (they snipe the back row).
const RANGED_FOE_WORDS := ["Wisp", "Moth", "Sprite", "Oracle", "Choir", "Sniper", "Crier", "Harrier", "Bellringer", "Priest"]
## Besides attacking, a foe can telegraph one of its kit's moves a round
## ahead (Combat.monster_kit / monster_intent). Numbers used by Combat.
const INTENT_SPECIAL_CHANCE := 0.3
const SWEEP_MULT := 0.55      # hits every hero for this share of a normal hit
const SNIPE_MULT := 1.25      # a heavier hit on the most-hurt back-row hero
const CURSE_WEAKEN := 0.4     # a cursed hero deals this much less damage...
const CURSE_ROUNDS := 2       # ...for this many rounds
const WARD_PCT := 0.2         # of the warded foe's max HP
const MEND_PCT := 0.15        # of the mended foe's max HP (a healer's own value if it has one)
const ROAR_MULT := 1.2        # every foe hits this much harder, up to twice a fight
const INTENT_INFO := {
	"sweep": {"name": "Sweep", "icon": "res://assets/skills/sword_slash.png", "desc": "Hits every hero for %d%% of a normal hit. Defend halves it for whoever Defends."},
	"snipe": {"name": "Snipe", "icon": "res://assets/skills/dagger_blue.png", "desc": "A heavier shot at the most-hurt hero in the back row. Guard can take it for them."},
	"curse": {"name": "Curse", "icon": "res://assets/skills/face_hood.png", "desc": "No damage, but the target deals 40%% less for 2 rounds. Sanctuary cleanses it."},
	"ward": {"name": "Ward", "icon": "res://assets/skills/shield_blue.png", "desc": "Shields its most-hurt ally for 20%% of their max HP. Aimed Shot ignores wards."},
	"mend": {"name": "Mend", "icon": "res://assets/skills/potion_red_sm.png", "desc": "Heals its most-hurt ally. Kill or stun it first."},
	"roar": {"name": "Roar", "icon": "res://assets/skills/gem_red.png", "desc": "Every foe hits 20%% harder for the rest of the fight (up to twice). Stun it to stop it."},
	"stunned": {"name": "Stunned", "icon": "res://assets/skills/star.png", "desc": "Loses its next action."},
}


## The moves a species telegraphs besides attacking (see Combat.monster_kit);
## species not listed get one by ability, range and name.
const MONSTER_KIT := {
	"Hedge Warden": ["ward"], "Carrion Crier": ["curse", "roar"], "Rootbound Thrall": ["sweep"],
	"Leech Priest": ["mend"], "Mire Sniper": ["snipe"], "Drowned Bellringer": ["curse"],
	"Slag Golem": ["sweep"], "Ember Oracle": ["ward", "curse"], "Ash Harrier": ["snipe"],
}

## Hand-designed fights per region: a named group whose members play off each
## other, with a hint shown at the start. Members: [name, share of the fight's
## health, share of its damage] — shares sum to about 1, so a designed fight
## is no harder overall than a random one. The first member leads (front).
## min_floor keeps the nastier ones out of a rift's first floors.
const ENCOUNTERS := {
	"vale": [
		{"name": "Scarecrow Line", "min_floor": 0, "hint": "The Warden wards its friends and the Wisp mends them. Take the Wisp first, or strip the wards.",
			"members": [["Hedge Warden", 0.45, 0.25], ["Husk Brute", 0.35, 0.45], ["Rift Wisp", 0.2, 0.3]]},
		{"name": "Murder of Crows", "min_floor": 1, "hint": "Criers curse and roar from the back. Silence them before the roars stack.",
			"members": [["Gloom Stalker", 0.4, 0.3], ["Carrion Crier", 0.3, 0.35], ["Carrion Crier", 0.3, 0.35]]},
		{"name": "Rootbound Ambush", "min_floor": 0, "hint": "The Thrall's sweeps hit the whole party. Defend, or stun its wind-up.",
			"members": [["Rootbound Thrall", 0.5, 0.5], ["Sable Fang", 0.25, 0.25], ["Sable Fang", 0.25, 0.25]]},
		{"name": "Graveyard Shift", "min_floor": 2, "hint": "The Crawler mends the Reaver while the Crier curses. Break the healer, then the brute.",
			"members": [["Hollow Reaver", 0.45, 0.45], ["Marrow Crawler", 0.25, 0.25], ["Carrion Crier", 0.3, 0.3]]},
		{"name": "Stalker Pack", "min_floor": 0, "hint": "Poison stacks fast. A Healing Tonic or Sanctuary washes it out.",
			"members": [["Gloom Stalker", 0.34, 0.34], ["Gloom Stalker", 0.33, 0.33], ["Gloom Stalker", 0.33, 0.33]]},
	],
	"marsh": [
		{"name": "The Leech Mass", "min_floor": 0, "hint": "The Priest keeps the Wretches fed. Kill it first.",
			"members": [["Bog Wretch", 0.35, 0.4], ["Bog Wretch", 0.35, 0.4], ["Leech Priest", 0.3, 0.2]]},
		{"name": "Reed Snipers", "min_floor": 1, "hint": "Snipers hunt the back row behind their Anchorite. Guard your healer, or Taunt.",
			"members": [["Deep Anchorite", 0.5, 0.3], ["Mire Sniper", 0.25, 0.35], ["Mire Sniper", 0.25, 0.35]]},
		{"name": "Bell and Mirror", "min_floor": 1, "hint": "The Fiend reflects basic hits and the Bell curses. Skills and Aimed Shot go around the mirror.",
			"members": [["Mirror Fiend", 0.4, 0.4], ["Drowned Bellringer", 0.3, 0.3], ["Glass Wisp", 0.3, 0.3]]},
		{"name": "Silt Swarm", "min_floor": 0, "hint": "Three drainers heal off every hit. Volley and Frost Nova hit them all.",
			"members": [["Silt Crawler", 0.34, 0.34], ["Silt Crawler", 0.33, 0.33], ["Silt Crawler", 0.33, 0.33]]},
		{"name": "Frozen Watch", "min_floor": 2, "hint": "Chills slow your turns and the Priest mends. Burst the Priest down.",
			"members": [["Frost Stalker", 0.35, 0.4], ["Frost Stalker", 0.35, 0.4], ["Leech Priest", 0.3, 0.2]]},
	],
	"ashen": [
		{"name": "Forge Guard", "min_floor": 1, "hint": "The Oracle wards the Golem, and the Golem's sweeps burn. Take the Oracle first.",
			"members": [["Slag Golem", 0.6, 0.5], ["Ember Oracle", 0.4, 0.5]]},
		{"name": "Ash Flock", "min_floor": 0, "hint": "Harriers snipe and hit harder when hurt. Finish each one quickly.",
			"members": [["Cinder Moth", 0.4, 0.3], ["Ash Harrier", 0.3, 0.35], ["Ash Harrier", 0.3, 0.35]]},
		{"name": "Cinder Cult", "min_floor": 0, "hint": "Everything here burns. Keep a cleanse ready.",
			"members": [["Ashclad Ghoul", 0.35, 0.35], ["Ashclad Ghoul", 0.35, 0.35], ["Ember Oracle", 0.3, 0.3]]},
		{"name": "Void Tear", "min_floor": 1, "hint": "The Reaver winds up while the Sprites harry. Break the wind-up.",
			"members": [["Hollow Reaver", 0.5, 0.4], ["Voidling Sprite", 0.25, 0.3], ["Voidling Sprite", 0.25, 0.3]]},
		{"name": "Molten Wall", "min_floor": 2, "hint": "Two armored brutes. Armor breakers and stuns shine here.",
			"members": [["Slag Golem", 0.5, 0.5], ["Slag Golem", 0.5, 0.5]]},
	],
}
const ENCOUNTER_CHANCE := 0.6

