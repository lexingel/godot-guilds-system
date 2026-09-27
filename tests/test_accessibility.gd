extends "res://tests/base_test.gd"
## Colour-blind mode swaps green for blue wherever it sits against red; both
## accessibility settings survive a settings save/load.


func run() -> void:
	var was_cb := GameState.colorblind
	var was_rm := GameState.reduce_motion
	GameState.colorblind = false
	check(Palette.good() == Palette.RANK_E, "green by default")
	GameState.colorblind = true
	check(Palette.good() == Palette.RANK_D, "blue in colour-blind mode")
	check(Palette.good() != Palette.HAZARD, "never the danger colour")

	GameState.reduce_motion = true
	GameState.save_settings()
	GameState.colorblind = false
	GameState.reduce_motion = false
	GameState.load_settings()
	check(GameState.colorblind and GameState.reduce_motion, "both settings round-trip through settings.json")
	GameState.colorblind = was_cb
	GameState.reduce_motion = was_rm
	GameState.save_settings()
