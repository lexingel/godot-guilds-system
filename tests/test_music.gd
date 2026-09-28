extends "res://tests/base_test.gd"
## Music pools: every track loads, and a new pick avoids the last one.


func run() -> void:
	for p in GameData.COMBAT_MUSIC + GameData.CAMP_MUSIC:
		check(ResourceLoader.exists(p) and load(p) is AudioStream, "%s loads" % p)
	check(GameData.COMBAT_MUSIC.size() >= 3 and GameData.CAMP_MUSIC.size() >= 3, "three combat tracks, three camp tracks")
	var last := str(GameData.CAMP_MUSIC[0])
	var repeats := 0
	for k in 30:
		var t := GameData.pick_track(GameData.CAMP_MUSIC, last)
		if t == last:
			repeats += 1
		last = t
	check(repeats == 0, "coming home never replays the same camp track")
	check(GameData.pick_track(["only"], "only") == "only", "a single-track pool still plays")
