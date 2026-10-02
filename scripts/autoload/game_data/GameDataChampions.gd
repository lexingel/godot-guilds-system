extends "res://scripts/autoload/game_data/GameDataModes.gd"
## GameData, part 6b: Champions. A pool of named heroes out of time; each new
## guild rolls CHAMPION_ROLL of them. The first three rolled are freed at the
## end of Acts I-III, the rest are lost in the Endless Rift and rescued there
## (hold a beacon). A champion never joins the roster: in rifts one oversees
## the party (their Boon, and their Call 1-2 times a rift); in the Endless
## Rift they are the party.
##
## boon: party-wide while overseeing, {kind, value, name}; call: an Ability-
## shaped {name, effect, value, desc}. Both grow CHAMPION_LEVEL_POWER per
## level. mods: the two SurvivorsRun.SIG_MODS their signature can learn in the
## Endless Rift. Art: assets/champions (portraits), walk and skill frames in
## assets/survivors; the prompts that made them are in docs/art_src.

const CHAMPION_ROLL := 12
const CHAMPION_STORY_ACTS := 3
## The nine lost champions surface at these times in an Endless run.
const CHAMPION_DEPTHS := [120, 180, 240, 300, 420, 540, 660, 780, 900]
const CHAMPION_LEVEL_MAX := 5
const CHAMPION_LEVEL_COST := [0, 40, 75, 135, 210]   # Essence to reach level i+1
const CHAMPION_LEVEL_POWER := 0.25   # Boon and Call strength per level past 1
const CHAMPION_LEVEL_STATS := 0.15   # HP and damage per level in the Endless Rift
const CHAMPION_RANK := "B"
const CHAMPION_EXTRA_CALL_LEVEL := 3   # from this level the Call works twice a rift
const BEACON_HOLD := 12.0   # seconds inside the light to free a lost champion
const BEACON_R := 90.0
const BEACON_DIST := 520.0
## Endless Rift threat (foe HP and damage scale): gentle when it first opens
## after Act II, stronger with every lost champion freed and every act passed
## after that, up to THREAT_MAX (four champions with two fusions are far
## stronger than the heroes the base curve was tuned for). The balance sim
## (`-- champions`) keeps each step's median run near 11 minutes.
const THREAT_BASE := 0.6
const THREAT_PER_RESCUE := 0.15
const THREAT_PER_ACT := 0.15
const THREAT_MAX := 1.6

const CHAMPIONS := {
	# Warriors
	"brannoch": {"name": "Brannoch", "title": "the Unbroken", "role": "warrior",
		"lore": "The last knight of the old guilds held a rift shut with his own body for eleven years. The chains are still on his wrists; he says they help him remember why.",
		"boon": {"kind": "hp_pct", "value": 0.08, "name": "Unbroken Line"},
		"call": {"name": "Last Stand", "effect": "team_shield_burst", "value": 0.35, "desc": "shields every ally for 35% of their max HP"},
		"mods": ["stagger", "bulwark"]},
	"grell": {"name": "Grell", "title": "Ironjaw", "role": "warrior",
		"lore": "Lost his jaw to a rift-beast and had a better one forged. He has not stopped talking since.",
		"boon": {"kind": "dmg_pct", "value": 0.08, "name": "Iron Resolve"},
		"call": {"name": "War Cry", "effect": "team_dmg_mult", "value": 1.25, "desc": "the whole party hits 25% harder for the rest of the fight"},
		"mods": ["stagger", "fervor"]},
	"mordrake": {"name": "Mordrake", "title": "the Deathless", "role": "warrior",
		"lore": "He died in the Endless Rift once. It didn't take.",
		"boon": {"kind": "escalate_pct", "value": 0.02, "name": "Grim Momentum"},
		"call": {"name": "Deathless", "effect": "wipe_guard_surge", "value": 0.6, "desc": "braces the party against a wipe for the rest of the fight"},
		"mods": ["ignite", "renewal"]},
	"sigrun": {"name": "Sigrun", "title": "Shieldmaiden", "role": "warrior",
		"lore": "Her village sank into a rift in a single night. She walked in after it and has been walking ever since.",
		"boon": {"kind": "hazard_guard_pct", "value": 0.12, "name": "Shieldwall"},
		"call": {"name": "Shield Wall", "effect": "shield_wall_front", "value": 0.5, "desc": "wards the front row for 50% of their max HP"},
		"mods": ["bulwark", "expose"]},
	"kael": {"name": "Kael", "title": "the Oathsworn", "role": "warrior",
		"lore": "Swore to guard a rift-gate until relieved. Nobody came. He is very glad to see you.",
		"boon": {"kind": "first_round_pct", "value": 0.12, "name": "Vanguard Oath"},
		"call": {"name": "Spear Wall", "effect": "cleave_burst", "value": 1.8, "desc": "a sweep of the spear hits every foe"},
		"mods": ["aftershock", "expose"]},
	# Rangers
	"kaya": {"name": "Kaya", "title": "Swiftwind", "role": "ranger",
		"lore": "She outran a rift-storm once. Now she can't stop running, so she brings the storm with her.",
		"boon": {"kind": "speed_pct", "value": 0.06, "name": "Tailwind"},
		"call": {"name": "Arrow Storm", "effect": "chain_lightning", "value": 1.0, "desc": "arrows ride the wind, jumping between foes"},
		"mods": ["shrapnel", "fervor"]},
	"hesk": {"name": "Hesk", "title": "the Beastcaller", "role": "ranger",
		"lore": "Raised by rift-wolves. Speaks their language better than ours, and prefers their company.",
		"boon": {"kind": "dmg_pct", "value": 0.08, "name": "Pack Hunter"},
		"call": {"name": "Pounce", "effect": "execute_burst", "value": 2.4, "desc": "the pack falls on the weakest foe, harder the more it's hurt"},
		"mods": ["leech", "fervor"]},
	"lyra": {"name": "Lyra", "title": "Thornwood", "role": "ranger",
		"lore": "The last warden of a forest the rifts swallowed. The forest is still in there; so is she.",
		"boon": {"kind": "dodge_pct", "value": 0.05, "name": "Leaf on the Wind"},
		"call": {"name": "Thorn Snare", "effect": "freeze_target", "value": 0.8, "desc": "thorns bind the target: it loses its next two actions (a boss, one)"},
		"mods": ["radiant", "renewal"]},
	"bram": {"name": "Bram", "title": "the Trapper", "role": "ranger",
		"lore": "Forty years of setting snares for things that come out of rifts. Some of them are still in his cellar.",
		"boon": {"kind": "hazard_guard_pct", "value": 0.12, "name": "Trail Wisdom"},
		"call": {"name": "Deadfall", "effect": "execute_all_low", "value": 0.8, "desc": "springs every trap at once on the wounded foes"},
		"mods": ["shrapnel", "stagger"]},
	"ossian": {"name": "Ossian", "title": "Greyfeather", "role": "ranger",
		"lore": "Has never missed a shot. He will tell you this before you ask.",
		"boon": {"kind": "first_round_pct", "value": 0.12, "name": "First Shot"},
		"call": {"name": "Killshot", "effect": "execute_burst", "value": 2.6, "desc": "one perfect arrow at the weakest foe, deadlier the more it's hurt"},
		"mods": ["expose", "smokescreen"]},
	# Mages
	"vesh": {"name": "Vesh", "title": "the Ashborn", "role": "mage",
		"lore": "Once the herald of an ash-queen, until he read what he was heralding. The embers under his skin never cooled.",
		"boon": {"kind": "ability_power", "value": 0.15, "name": "Cinder Tongue"},
		"call": {"name": "Crownfall", "effect": "cleave_burst", "value": 2.2, "desc": "a rain of burning ash engulfs every foe"},
		"mods": ["ignite", "aftershock"]},
	"auriel": {"name": "Auriel", "title": "the Starwright", "role": "mage",
		"lore": "Mapped every star, then noticed new ones leaking out of the rifts. She has been following them since.",
		"boon": {"kind": "escalate_pct", "value": 0.02, "name": "Star Chart"},
		"call": {"name": "Meteor", "effect": "cleave_burst", "value": 2.4, "desc": "calls down a falling star on every foe"},
		"mods": ["aftershock", "radiant"]},
	"morwen": {"name": "Morwen", "title": "of the Frost", "role": "mage",
		"lore": "Froze a rift solid to save a town. The town is fine. She has been cold for a hundred years.",
		"boon": {"kind": "hp_pct", "value": 0.08, "name": "Rime Ward"},
		"call": {"name": "Deep Freeze", "effect": "freeze_target", "value": 1.0, "desc": "freezes the target solid: it loses its next two actions (a boss, one)"},
		"mods": ["frostbite", "shrapnel"]},
	"tamsin": {"name": "Tamsin", "title": "Sparkwright", "role": "mage",
		"lore": "Built a machine to close rifts. It opened one instead. She is working on version two.",
		"boon": {"kind": "speed_pct", "value": 0.06, "name": "Overclock"},
		"call": {"name": "Chain Lightning", "effect": "chain_lightning", "value": 1.1, "desc": "lightning arcs from foe to foe"},
		"mods": ["stagger", "aftershock"]},
	"ezra": {"name": "Ezra", "title": "the Pale", "role": "mage",
		"lore": "Studies what the rifts take from people. Keeps some of it in the lantern, for safekeeping. He insists.",
		"boon": {"kind": "ability_power", "value": 0.15, "name": "Soul Tithe"},
		"call": {"name": "Harvest", "effect": "hp_drain_burst", "value": 1.2, "desc": "drains the weakest foe, healing the caster for a share of it"},
		"mods": ["leech", "frostbite"]},
	# Clerics
	"imre": {"name": "Imre", "title": "of the Tides", "role": "cleric",
		"lore": "Kept alive at the bottom of a drowned spire as a lantern for something that hated the dark. She still carries the light.",
		"boon": {"kind": "mend_pct", "value": 0.03, "name": "Tidal Grace"},
		"call": {"name": "Low Tide", "effect": "cleanse_heal", "value": 0.55, "desc": "heals the party 55% and washes away burn, poison, chill, stun and curses"},
		"mods": ["frostbite", "renewal"]},
	"odo": {"name": "Odo", "title": "the Lamplighter", "role": "cleric",
		"lore": "Lit the lamps of a city that fell into a rift. He kept lighting them. Eventually the lamps led him out.",
		"boon": {"kind": "hazard_guard_pct", "value": 0.12, "name": "Lamp in the Dark"},
		"call": {"name": "Light the Way", "effect": "revive", "value": 0.6, "desc": "raises a fallen ally at 60% HP (or heals the most hurt)"},
		"mods": ["radiant", "bulwark"]},
	"seraphine": {"name": "Seraphine", "title": "Dawnbringer", "role": "cleric",
		"lore": "Walked into the dark between rifts to find the sunrise. Came back with it.",
		"boon": {"kind": "hp_pct", "value": 0.08, "name": "Dawn's Blessing"},
		"call": {"name": "Sunrise", "effect": "mend_burst", "value": 0.65, "desc": "heals the whole party for 65% of their max HP"},
		"mods": ["radiant", "fervor"]},
	"hobb": {"name": "Hobb", "title": "the Friar", "role": "cleric",
		"lore": "Opened a tavern at the edge of a rift. Business was terrible. Blessings were excellent.",
		"boon": {"kind": "dmg_pct", "value": 0.08, "name": "Liquid Courage"},
		"call": {"name": "Round's On Me", "effect": "mend_burst", "value": 0.5, "desc": "heals the whole party for 50% of their max HP"},
		"mods": ["leech", "bulwark"]},
	"veyla": {"name": "Veyla", "title": "the Penitent", "role": "cleric",
		"lore": "Wears the mask so the rift can't see her face. It has been looking for her a long time.",
		"boon": {"kind": "dodge_pct", "value": 0.05, "name": "Incense Veil"},
		"call": {"name": "Censer Smoke", "effect": "dodge_surge", "value": 0.3, "desc": "thick smoke: +30% dodge for the rest of the fight"},
		"mods": ["ignite", "smokescreen"]},
	# Rogues
	"selune": {"name": "Selune", "title": "of the Hollow Moon", "role": "rogue",
		"lore": "An assassin who took one contract too many: on the moon. It didn't go well for either of them.",
		"boon": {"kind": "first_round_pct", "value": 0.12, "name": "New Moon"},
		"call": {"name": "Eclipse", "effect": "execute_all_low", "value": 0.9, "desc": "darkness falls, and every wounded foe with it"},
		"mods": ["smokescreen", "expose"]},
	"pip": {"name": "Pip", "title": "Quickfingers", "role": "rogue",
		"lore": "Stole a key from a rift-lord's belt. The key opened the rift. Pip would like to give it back.",
		"boon": {"kind": "dodge_pct", "value": 0.05, "name": "Slippery"},
		"call": {"name": "Smoke and Mirrors", "effect": "dodge_surge", "value": 0.35, "desc": "+35% dodge for the rest of the fight"},
		"mods": ["shrapnel", "smokescreen"]},
	"raske": {"name": "Raske", "title": "the Red", "role": "rogue",
		"lore": "Captained a ship that sailed off the edge of the world and into a rift. Kept the coat.",
		"boon": {"kind": "dmg_pct", "value": 0.08, "name": "Blood in the Water"},
		"call": {"name": "Whirlwind", "effect": "cleave_burst", "value": 1.9, "desc": "a spinning storm of cutlasses hits every foe"},
		"mods": ["leech", "renewal"]},
	"corvin": {"name": "Corvin", "title": "Ashwhisper", "role": "rogue",
		"lore": "Brews poisons from what bleeds out of rifts. Swears most of them are medicine.",
		"boon": {"kind": "escalate_pct", "value": 0.02, "name": "Slow Venom"},
		"call": {"name": "Plague Cloud", "effect": "burn_all", "value": 0.6, "desc": "a toxic cloud that eats at every foe for three rounds"},
		"mods": ["ignite", "frostbite"]},
}


## Champions from the player's own past guilds (GameState.legacy), by id
## ("legacy_..."), set when the legacy record loads: CHAMPIONS' shape plus
## "guild", "portrait", "memory" and "post" (took the forty-first post).
static var LEGACY_CHAMPIONS := {}


static func champion_def(id: String) -> Dictionary:
	return CHAMPIONS.get(id, LEGACY_CHAMPIONS.get(id, {}))


## "Brannoch the Unbroken" / "Grell Ironjaw" / "Imre of the Tides".
static func champion_full_name(id: String) -> String:
	var d := champion_def(id)
	if d.has("guild"):   # a hero from a past guild: "Oren of the Pocket Crows"
		return String(TranslationServer.translate("%s of %s")) % [str(d["name"]), str(d["guild"])]
	# A template, so a language can put the title first ("Kırılmaz Brannoch").
	return String(TranslationServer.translate("{name} {title}")).format({"name": str(d.get("name", id)), "title": String(TranslationServer.translate(str(d.get("title", ""))))})


static func champion_power(level: int) -> float:
	return 1.0 + CHAMPION_LEVEL_POWER * (clampi(level, 1, CHAMPION_LEVEL_MAX) - 1)


static func champion_portrait(id: String) -> String:
	var own := "res://assets/champions/%s.png" % id
	if ResourceLoader.exists(own):
		return own
	var d := champion_def(id)
	return str(d["portrait"]) if d.has("portrait") else HERO_PORTRAIT_PATH.get(str(d.get("role", "warrior")), "")


## What each champion remembers of the Night of Breaking (the Broken Accord):
## told when they're freed, kept in the Codex's Chronicle. Each stands alone,
## since a guild meets its champions in any order.
const CHAMPION_MEMORY := {
	"brannoch": "The Grandmaster said one night. One night, and the Hollow would be quiet for good. I counted. It was eleven years.",
	"grell": "We drew lots for the posts. I drew a deep one. I remember thinking that was lucky.",
	"mordrake": "When the light closed over me it didn't hurt. It felt like being told to wait, very firmly.",
	"sigrun": "My whole shield-company walked into the light together. I came out alone. Ask the others if they're still holding.",
	"kael": "The order was: hold until relieved. The Grandmaster said she would come back for us herself. She didn't. Why didn't she?",
	"kaya": "I ran messages between the posts that night. The last one I carried was from the Grandmaster, and it was sealed with ash.",
	"hesk": "The wolves knew before we did. They howled at the Hall for three days before the Night. Nobody listens to wolves.",
	"lyra": "Some of us didn't go into the light willingly. The Grandmaster said there wasn't time to ask.",
	"bram": "I set a snare at my post, out of habit. Caught a voice. It kept saying: the price, the price.",
	"ossian": "I had the Grandmaster in my sights that night, on her way out. I've never missed. I didn't take the shot. I'd like to know if that was right.",
	"vesh": "I read her proclamations aloud in the ash for years before I read one closely. It began: the Accord is dissolved.",
	"auriel": "The new stars leaking from the rifts are the posts, going out one by one. I have counted forty dark since the Night.",
	"morwen": "Freezing my rift was my own idea, not the Accord's. I think that's why the Hollow never got its hooks into me.",
	"tamsin": "The Accord's engineers built the bargain like a lock. I've seen the plans. Every lock has a key.",
	"ezra": "Each of us gave the Hollow something to seal the deal. I gave my colour. You can probably tell.",
	"imre": "I was kept lit to read the archive by. I read all of it. The bargain has a clause about what happens when a post is abandoned.",
	"odo": "The lamps of my city were Accord lamps, meant to lead the guilds home. The city fell before anyone came back.",
	"seraphine": "The Grandmaster said there would be no sunrise until the price was paid. She was wrong. I went and found it.",
	"hobb": "Half the Accord drank at my tavern the night before. The Grandmaster paid for every round. I thought it was generous. It was a goodbye.",
	"veyla": "I signed the bargain as a witness. The mask is so the Hollow can't match my face to my name on it.",
	"selune": "My last contract came from inside the Accord: remove a ranger who had left her post. I didn't. Vaelith owes me one.",
	"pip": "The key I stole opened a rift, yes. It was the Grandmaster's key. I'm told that matters.",
	"raske": "We were to ferry the last guild to its post across the Marches. The water rose too fast. I kept the coat. I kept the list of names too.",
	"corvin": "The Accord's healers poisoned nobody, whatever the songs say. They gave the posts something to sleep. I still have the recipe.",
}


## ---- Legacy: what a finished or retired guild leaves the next ones ----
## (design: "The Vale Remembers"). Laurels are earned once, when the legacy
## is written, and spent at founding.
const LAURELS := {"act": 5, "ending": 10, "freed": 2, "charter": 5, "morrow": 3, "echo": 1}
const LEGACY_HEROES := 2          # heroes a guild can ask the Vale to remember
const LEGACY_POOL := 12           # remembered heroes kept (the most recent)
const LEGACY_MIN_RANK := "C"      # ...or LEGACY_MIN_RIFTS sealed
const LEGACY_MIN_RIFTS := 25
const LEGACY_SHALLOW := 5         # a remembered hero waits at one of the first lost pillars
## One-guild starting gifts bought with Laurels at founding.
const LEGACY_GIFTS := [
	{"id": "gold", "cost": 5, "name": "300 more Gold"},
	{"id": "hero", "cost": 8, "name": "A fourth hero, Rank D"},
	{"id": "relic", "cost": 8, "name": "A rare relic"},
	{"id": "barracks", "cost": 10, "name": "The Barracks one level up"},
]
## A remembered hero's champion text (%s/%d filled when the legacy is written).
const LEGACY_LORE := "Once Rank %s with %s: %d rifts sealed, %d foes felled."
const LEGACY_POST_LORE := "Took the forty-first post for %s, and held it."
const LEGACY_MEMORY := [
	"Different crest on the banner. Same work. I sealed %d rifts with %s; I can manage a few more.",
	"Tell Hesper I kept count. %d rifts with %s, and every one of them stayed shut.",
	"The light was very quiet. I kept thinking about payday at %s, of all things. %d rifts, and I still miss the pay table.",
]
const LEGACY_POST_MEMORY := "Every year someone from %s climbed down to tell me how the harvest went. I'd like to hear it up close for once."
