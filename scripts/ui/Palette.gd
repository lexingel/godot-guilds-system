class_name Palette
extends RefCounted
## Color constants for the violet/ember material system (Godot Phase 16) — a
## near-black violet-tinted base with two domain accents assigned by meaning,
## not by a fixed primary/secondary hierarchy: Violet for arcane/progression
## content, Ember for economy/danger/combat content, Gunmetal for anything in
## neither domain. Replaces the muted purple/teal identity from Phases 3-15.

# Base ramp (violet-tinted near-black)
const INK := Color(0.047, 0.039, 0.078, 1.0)      # #0c0a14
const SURFACE := Color(0.090, 0.071, 0.137, 1.0)  # #171223
const SURFACE2 := Color(0.129, 0.102, 0.200, 1.0) # #211a33
const SURFACE3 := Color(0.180, 0.145, 0.278, 1.0) # #2e2547
const LINE := Color(0.239, 0.200, 0.341, 1.0)     # #3d3357

# Text
const TEXT := Color(0.914, 0.886, 0.961, 1.0)     # #e9e2f5
const MUTED := Color(0.659, 0.608, 0.788, 1.0)    # #a89bc9
const MUTED2 := Color(0.478, 0.427, 0.600, 1.0)   # #7a6d99

# Domain accents — the two colors every trimmed component is assigned from,
# plus a neutral Gunmetal for anything in neither domain. Each accent carries
# a bright (bevel-light/glow) and deep (bevel-dark) pair for the pixel-bevel
# texture generator in Task 3.
const VIOLET := Color(0.545, 0.361, 0.965, 1.0)       # #8b5cf6
const VIOLET_BRIGHT := Color(0.788, 0.702, 1.0, 1.0)  # #c9b3ff
const VIOLET_DEEP := Color(0.290, 0.165, 0.600, 1.0)  # #4a2a99
const EMBER := Color(0.910, 0.392, 0.184, 1.0)        # #e8642f
const EMBER_BRIGHT := Color(1.0, 0.690, 0.400, 1.0)   # #ffb066
const EMBER_DEEP := Color(0.541, 0.169, 0.071, 1.0)   # #8a2b12
const EMBER_DANGER := Color(0.780, 0.243, 0.114, 1.0) # #c73e1d — a redder ember for damage/hazard, distinct from the warmer economy ember
const GUNMETAL := Color(0.357, 0.333, 0.439, 1.0)         # #5b5570
const GUNMETAL_BRIGHT := Color(0.478, 0.451, 0.565, 1.0)  # #7a7390
const GUNMETAL_DEEP := Color(0.204, 0.188, 0.290, 1.0)    # #34304a

# Currency (resaturated, kept mutually distinct from each other and from the domain accents)
const COINS := Color(0.949, 0.663, 0.227, 1.0)    # #f2a93a
const CRYSTALS := Color(0.435, 0.847, 0.949, 1.0) # #6fd8f2
const TOKENS := Color(0.820, 0.557, 0.949, 1.0)   # #d18ef2

# Rank colors — F/E/D/S/SS/SSS unchanged in hue family; C/B/A now point at the
# domain accents directly (see rank_color() below) instead of standalone consts.
const RANK_F := Color(0.514, 0.478, 0.600, 1.0)   # #837a99
const RANK_E := Color(0.435, 0.749, 0.451, 1.0)   # #6fbf73 (unchanged — also reused as the general "favorable/healthy" traffic-light color, see Main.gd's _hp_color/_hazard_severity_color)
const RANK_D := Color(0.373, 0.722, 0.910, 1.0)   # #5fb8e8
const RANK_S := Color(0.949, 0.761, 0.298, 1.0)   # #f2c24c
const RANK_SS := Color(0.949, 0.400, 0.831, 1.0)  # #f266d4 (unchanged)
const RANK_SSS := Color(0.980, 0.980, 0.941, 1.0) # #fafaf0 (unchanged)

const ELITE := Color(0.949, 0.573, 0.290, 1.0)    # #f2924a (was #e0954a, warmed toward the ember family)
const HAZARD := EMBER_DANGER                       # alias — hazard/damage indicators reuse the danger-ember tone directly

static func rank_color(rank: String) -> Color:
	match rank:
		"F": return RANK_F
		"E": return RANK_E
		"D": return RANK_D
		"C": return VIOLET
		"B": return TOKENS
		"A": return ELITE
		"S": return RANK_S
		"SS": return RANK_SS
		"SSS": return RANK_SSS
		_: return MUTED
