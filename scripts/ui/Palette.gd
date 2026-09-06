class_name Palette
extends RefCounted
## Color constants ported directly from guild-system.html's :root CSS custom
## properties, for the few places code needs to color something per-data
## (rank badges, resource dots) rather than via the Theme resource.

const INK := Color(0.082, 0.075, 0.109, 1.0)         # #15131c
const SURFACE := Color(0.118, 0.102, 0.153, 1.0)      # #1e1a27
const SURFACE2 := Color(0.157, 0.137, 0.196, 1.0)     # #282232
const SURFACE3 := Color(0.2, 0.169, 0.251, 1.0)       # #332b40
const LINE := Color(0.227, 0.2, 0.275, 1.0)           # #3a3346
const TEXT := Color(0.925, 0.906, 0.957, 1.0)         # #ece7f4
const MUTED := Color(0.604, 0.565, 0.678, 1.0)        # #9a90ad
const MUTED2 := Color(0.471, 0.431, 0.557, 1.0)       # #786e8e
const RIFT := Color(0.247, 0.878, 0.659, 1.0)         # #3fe0a8 (accent)
const GOLD := Color(0.859, 0.651, 0.247, 1.0)         # #dba63f
const CRYSTAL := Color(0.373, 0.780, 0.910, 1.0)      # #5fc7e8
const TOKEN := Color(0.725, 0.557, 0.878, 1.0)        # #b98ee0
const HAZARD := Color(0.878, 0.396, 0.290, 1.0)       # #e0654a
const ELITE := Color(0.878, 0.584, 0.290, 1.0)        # #e0954a
const RANK_F := Color(0.545, 0.518, 0.588, 1.0)       # #8b8496
const RANK_E := Color(0.435, 0.749, 0.451, 1.0)       # #6fbf73
const RANK_D := Color(0.373, 0.659, 0.910, 1.0)       # #5fa8e8
const RANK_S := Color(0.949, 0.788, 0.298, 1.0)       # #f2c94c

static func rank_color(rank: String) -> Color:
	match rank:
		"F": return RANK_F
		"E": return RANK_E
		"D": return RANK_D
		"C": return RIFT
		"B": return TOKEN
		"A": return ELITE
		"S": return RANK_S
		_: return MUTED
