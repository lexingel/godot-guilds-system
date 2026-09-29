extends "res://scripts/autoload/game_data/GameDataChampions.gd"
## GameData, part 6c: Riftbreaks (docs/design/riftbreak.md). From Act II a
## rift swells every so often: a ladder rank, a region (the camp itself from
## BREACH_CAMP_RANK up) and a countdown in days. Seal a rift of that rank or
## higher first to prevent it; otherwise it breaks, rift runs wait, and the
## guild defends in a tower-defense fight.

const BREACH_UNLOCK_ACT := 2       # campaign_act from which rifts swell (Act I done)
const BREACH_FIRST_DELAY := 3      # days after that until the first one
const BREACH_EVERY_MIN := 8        # days between one breach being dealt with and the next
const BREACH_EVERY_MAX := 12
const BREACH_WARN := 6             # days from swelling to breaking
const BREACH_UP_CHANCE := 0.35     # the breach is a rank above your best seal (when that rank is open)
const BREACH_CAMP_RANK := "S"      # this rank and up break at the camp
## Rewards scale with the rank: 1 + BREACH_RANK_SCALE per ladder step.
const BREACH_RANK_SCALE := 0.35
const BREACH_PREVENT_ESSENCE := 15
const BREACH_HELD_GOLD := 80
const BREACH_HELD_ESSENCE := 30
const BREACH_LOSS_SHARE := 0.2     # of stored Gold and Essence, when a defense is lost
const BREACH_REPAIR_BASE := 40     # Gold to repair a damaged building: base + step x its level
const BREACH_REPAIR_STEP := 30

# ---------------- The defense (DefenseRun) ----------------

## Defense maps (a 1280x720 field): paths foes walk (each ends at the goal,
## or joins another path), tower pads, hero posts beside the road, and the
## goal they must not reach. Laid out so every pad covers a stretch of road.
const DEFENSE_MAPS := {
	"vale": {
		"paths": [[Vector2(-40, 170), Vector2(260, 170), Vector2(340, 400), Vector2(640, 440), Vector2(720, 230), Vector2(980, 220), Vector2(1060, 420), Vector2(1200, 470)]],
		"pads": [Vector2(560, 530), Vector2(1140, 350), Vector2(300, 110), Vector2(780, 130), Vector2(200, 310), Vector2(1060, 510), Vector2(600, 330), Vector2(760, 330)],
		"posts": [Vector2(660, 470), Vector2(1000, 190), Vector2(1080, 390), Vector2(300, 190), Vector2(60, 210)],
		"goal": Vector2(1200, 470)},
	"marsh": {
		"paths": [[Vector2(-40, 120), Vector2(300, 140), Vector2(460, 330), Vector2(760, 330), Vector2(900, 500), Vector2(1200, 520)], [Vector2(-40, 620), Vector2(250, 590), Vector2(460, 330)]],
		"pads": [Vector2(1000, 610), Vector2(240, 230), Vector2(720, 230), Vector2(1100, 430), Vector2(80, 530), Vector2(340, 50), Vector2(620, 410), Vector2(240, 430)],
		"posts": [Vector2(520, 290), Vector2(220, 630), Vector2(360, 150), Vector2(720, 370), Vector2(880, 530)],
		"goal": Vector2(1200, 520)},
	"ashen": {
		"paths": [[Vector2(200, -40), Vector2(230, 220), Vector2(520, 300), Vector2(600, 560), Vector2(920, 590), Vector2(1200, 380)], [Vector2(1000, -40), Vector2(900, 200), Vector2(600, 240), Vector2(520, 300)]],
		"pads": [Vector2(980, 650), Vector2(680, 310), Vector2(520, 610), Vector2(300, 110), Vector2(780, 130), Vector2(200, 310), Vector2(1180, 290), Vector2(1060, 390)],
		"posts": [Vector2(960, 130), Vector2(560, 330), Vector2(780, 610), Vector2(240, 50), Vector2(380, 230)],
		"goal": Vector2(1200, 380)},
	"camp": {
		"paths": [[Vector2(-40, 140), Vector2(240, 120), Vector2(360, 300), Vector2(620, 250), Vector2(800, 360)], [Vector2(-40, 620), Vector2(260, 650), Vector2(420, 470), Vector2(640, 480), Vector2(800, 360)], [Vector2(460, -40), Vector2(430, 110), Vector2(620, 250)], [Vector2(800, 360), Vector2(960, 250), Vector2(1180, 330)]],
		"pads": [Vector2(540, 570), Vector2(80, 530), Vector2(220, 270), Vector2(640, 390), Vector2(340, 50), Vector2(1110, 190), Vector2(740, 210), Vector2(1100, 410), Vector2(400, 650), Vector2(700, 530), Vector2(400, 190), Vector2(900, 170)],
		"posts": [Vector2(1060, 250), Vector2(220, 610), Vector2(400, 110), Vector2(620, 450), Vector2(460, 310), Vector2(200, 90)],
		"goal": Vector2(1180, 330)},
}

## Scenery off the road: the camp's own buildings (as built, so a damaged one
## shows it), stone pillars out in the regions. [hamlet building id or "pillar", position]
const DEFENSE_DECOR := {
	"camp": [["barracks", Vector2(240, 380)], ["infirmary", Vector2(1000, 560)], ["market", Vector2(1200, 480)],
		["lab", Vector2(800, 480)], ["scouts", Vector2(640, 640)], ["campfire", Vector2(980, 360)]],
	"vale": [["pillar", Vector2(440, 250)], ["pillar", Vector2(900, 360)], ["pillar", Vector2(120, 470)], ["pillar", Vector2(900, 600)]],
	"marsh": [["pillar", Vector2(580, 120)], ["pillar", Vector2(1000, 250)], ["pillar", Vector2(420, 600)], ["pillar", Vector2(760, 640)]],
	"ashen": [["pillar", Vector2(420, 460)], ["pillar", Vector2(80, 520)], ["pillar", Vector2(760, 420)], ["pillar", Vector2(1150, 620)]],
}

## Towers, by tier (index 0-2). Built on pads with supplies earned in the
## fight; damage grows with the breach's rank (DEFENSE_TOWER_RANK_SCALE).
## kind: bolt (one foe), fire (splash + burn), aura (chills every foe in
## reach), ward (heroes in reach take less), heal (heroes in reach mend).
const DEFENSE_TOWERS := {
	"ballista": {"name": "Ballista", "desc": "Long-range bolts at the foe furthest along the road", "icon": "res://assets/skills/sword_a.png", "kind": "bolt",
		"cost": [60, 90, 140], "range": [240.0, 270.0, 300.0], "cd": [1.4, 1.2, 1.0], "dmg": [22.0, 40.0, 70.0]},
	"brazier": {"name": "Fire Brazier", "desc": "Hurls fire that splashes and burns", "icon": "res://assets/skills/shield_orange.png", "kind": "fire",
		"cost": [80, 110, 160], "range": [170.0, 185.0, 200.0], "cd": [2.0, 1.8, 1.6], "dmg": [14.0, 24.0, 40.0], "splash": 70.0, "burn": 0.5},
	"frost": {"name": "Frost Totem", "desc": "Chills every foe in reach: they walk slower", "icon": "res://assets/skills/gem_blue_a.png", "kind": "aura",
		"cost": [70, 100, 150], "range": [150.0, 165.0, 180.0], "cd": [1.0, 1.0, 1.0], "dmg": [4.0, 8.0, 14.0], "slow": [0.35, 0.45, 0.55]},
	"ward": {"name": "Ward Stone", "desc": "Heroes in reach take less damage", "icon": "res://assets/skills/armor_chest.png", "kind": "ward",
		"cost": [70, 100, 140], "range": [170.0, 180.0, 190.0], "cd": [1.0, 1.0, 1.0], "dmg": [0.0, 0.0, 0.0], "guard": [0.25, 0.35, 0.45]},
	"chapel": {"name": "Wayside Chapel", "desc": "Heroes in reach mend every second", "icon": "res://assets/skills/heart.png", "kind": "heal",
		"cost": [90, 120, 170], "range": [180.0, 190.0, 200.0], "cd": [1.0, 1.0, 1.0], "dmg": [0.0, 0.0, 0.0], "heal": [0.03, 0.045, 0.06]},
}
const DEFENSE_TOWER_RANK_SCALE := 0.6   # keeps pace with foe HP (DEFENSE_HP_PER_RANK)
const DEFENSE_SELL_BACK := 0.6        # share of what a tower cost, when sold
const DEFENSE_SUPPLIES := 180         # at the start
const DEFENSE_KILL_SUPPLIES := {"combat": 5, "elite": 30, "boss": 120}
const DEFENSE_INTEGRITY := 20
const DEFENSE_LEAK := {"combat": 1, "elite": 3, "boss": 10}   # integrity a foe costs if it gets through
const DEFENSE_WAVES := 8              # the camp faces DEFENSE_CAMP_WAVES more
const DEFENSE_CAMP_WAVES := 1
const DEFENSE_FIRST_BUILD := 30.0     # seconds to build before the first wave
const DEFENSE_BUILD_TIME := 20.0      # and between waves ("Call early" skips it for supplies)
const DEFENSE_EARLY_SUPPLIES := 1.5   # per second skipped
## Foes: HP and damage at wave 0 of a rank-0 breach, then growth per rank and per wave.
const DEFENSE_HP0 := 50.0
const DEFENSE_DMG0 := 4.0
const DEFENSE_HP_PER_RANK := 0.6
const DEFENSE_DMG_PER_RANK := 0.45
const DEFENSE_HP_PER_WAVE := 0.18
const DEFENSE_TIER_HP := {"combat": 1.0, "elite": 8.0, "boss": 40.0}
const DEFENSE_TIER_DMG := {"combat": 1.0, "elite": 2.0, "boss": 3.0}
const DEFENSE_TIER_SPEED := {"combat": 48.0, "elite": 34.0, "boss": 26.0}
## Heroes at posts: melee roles hold foes (this many at once); ranged ones shoot.
const DEFENSE_BLOCK := {"warrior": 3, "rogue": 2, "cleric": 1, "ranger": 0, "mage": 0}
const DEFENSE_HERO_RANGE := {"warrior": 60.0, "rogue": 60.0, "cleric": 120.0, "ranger": 260.0, "mage": 240.0}
const DEFENSE_CHAMP_SPEED := 150.0
const DEFENSE_CHAMP_RESPAWN := 15.0
const DEFENSE_SIGNATURE_CD := 12.0
