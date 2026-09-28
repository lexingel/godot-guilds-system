extends Node
## Static data tables — a near-mechanical port of the `const` tables in
## guild-system.html. No behavior lives here, only data, mirroring the
## HTML prototype's data/logic split. Keys use snake_case per GDScript
## convention; the JS camelCase originals are named in comments where it
## helps cross-reference the source.

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
## Features open up as the guild grows instead of all at once. Each entry:
## what unlocks it (checked by GameState.feature_unlocked) and the toast that
## announces it. Roster, Recruits, Rift Hall and the Codex are always open.
const FEATURE_UNLOCKS := {
	"inventory": {"name": "Inventory", "hint": "Opens once you find your first item or relic", "news": "Loot you find is kept here — equip items on the Roster's Hero tab."},
	"medical": {"name": "Medical Bay", "hint": "Opens after your first rift run", "news": "Wounded and downed heroes recover faster in a bed."},
	"bestiary": {"name": "Bestiary", "hint": "Opens after your first fight", "news": "Every foe you meet is recorded here."},
	"crafting": {"name": "Crafting", "hint": "Opens after you seal your first rift", "news": "Combine 3 spare items or relics into a better one."},
	"quests": {"name": "Quests", "hint": "Opens after you seal your first rift", "news": "Take on quests for Gold, Essence and Renown."},
	"management": {"name": "Management", "hint": "Opens after you seal your first rift", "news": "Spend Essence on lasting guild upgrades."},
	"tower": {"name": "Tower of Trials", "hint": "Opens when you complete Act I", "news": "100 fixed floors in the Rift Hall. Each floor is always the same fight, and pays the first time you clear it."},
}

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
	# Synthesized by tools/gen_sfx.py.
	"windup": "res://assets/audio/sfx/gen_windup.wav",
	"stun": "res://assets/audio/sfx/gen_stun.wav",
	"burn": "res://assets/audio/sfx/gen_burn.wav",
	"chill": "res://assets/audio/sfx/gen_chill.wav",
	"shield": "res://assets/audio/sfx/gen_shield.wav",
	"heal": "res://assets/audio/sfx/gen_heal.wav",
	"ability": "res://assets/audio/sfx/gen_ability.wav",
	"relic": "res://assets/audio/sfx/gen_relic.wav",
	"level_up": "res://assets/audio/sfx/gen_level_up.wav",
	"unlock": "res://assets/audio/sfx/gen_unlock.wav",
	"story": "res://assets/audio/sfx/gen_story.wav",
	"defeat": "res://assets/audio/sfx/gen_defeat.wav",
	"boss": "res://assets/audio/sfx/gen_boss.wav",
}

## The tester build: what changed lately and what to try, shown on the title
## screen (newest first, a few lines each).
const WHATS_NEW := [
	"Endless Rift: waves every minute, elite packs with chests, archers, a Rift Warden at 20:00 to beat, evolutions, rift relics, terrain and braziers.",
	"Fights: the main actions fit one row (More holds the rest); hover to preview Momentum; winning by hand with no one down pays +30% Gold.",
	"Guild: a This-week strip in camp, hero requests to answer, a rival with a face and a monthly contest.",
	"New music, larger text, and rank rules shown in the rift.",
]
const WHATS_NEW_TRY := "Try: take a party into the Endless Rift and see how far you get, then tell us where it got too hard or too dull."
const FEEDBACK_ISSUES_URL := "https://github.com/lexingel/godot-guilds-system/issues/new"

## Looping background music (AudioManager.play_music loops it).
## The pools the game picks from: a new camp track each time you come home,
## a combat track per rift or Endless run (not the last one's).
const COMBAT_MUSIC := ["res://assets/audio/music/combat.ogg", "res://assets/audio/music/metal_deep.ogg", "res://assets/audio/music/iron_deep_2.ogg"]
const CAMP_MUSIC := ["res://assets/audio/music/camp.ogg", "res://assets/audio/music/nocturnal_dread.ogg", "res://assets/audio/music/nocturnal_dread_2.ogg"]


## A track from `pool`, not `last` when there's another to choose.
static func pick_track(pool: Array, last: String = "") -> String:
	var options: Array = pool.filter(func(p): return p != last)
	return str((options if not options.is_empty() else pool)[randi() % (options if not options.is_empty() else pool).size()])

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
const MANAGEMENT_BG := "res://assets/screens/management_bg.png"
const BED_ICON := "res://assets/screens/bed_icon.png"
const RIFTHALL_BG := "res://assets/screens/rifthall_bg.png"
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
	"hedge_warden": "res://assets/monsters/hedge_warden.png",
	"carrion_crier": "res://assets/monsters/carrion_crier.png",
	"rootbound_thrall": "res://assets/monsters/rootbound_thrall.png",
	"leech_priest": "res://assets/monsters/leech_priest.png",
	"mire_sniper": "res://assets/monsters/mire_sniper.png",
	"drowned_bellringer": "res://assets/monsters/drowned_bellringer.png",
	"slag_golem": "res://assets/monsters/slag_golem.png",
	"ember_oracle": "res://assets/monsters/ember_oracle.png",
	"ash_harrier": "res://assets/monsters/ash_harrier.png",
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
	"Hedge Warden": "hedge_warden", "Carrion Crier": "carrion_crier", "Rootbound Thrall": "rootbound_thrall",
	"Leech Priest": "leech_priest", "Mire Sniper": "mire_sniper", "Drowned Bellringer": "drowned_bellringer",
	"Slag Golem": "slag_golem", "Ember Oracle": "ember_oracle", "Ash Harrier": "ash_harrier",
	# Tower of Trials guardians reuse elite/boss art.
	"The Gatekeeper": "iron_revenant", "Mirelord Oskan": "deep_anchorite", "Cindermaw": "ashen_broodlord",
	"The Hollow Choir": "hollow_reaver", "Tidewarden Selk": "blightfang_elite", "The Ember Regent": "drevok",
	"Gravewright Mourn": "korrath", "The Drowned Oracle": "nyxara", "Ashfather": "rift_touched_colossus",
	"The Summit Keeper": "sythrane",
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
