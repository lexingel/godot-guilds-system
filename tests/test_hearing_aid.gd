extends "res://tests/base_test.gd"
## Hearing aid: meaningful sounds show a caption (repeats counted, not
## stacked) and the big ones pulse the screen edges; off, nothing shows.


func _frames(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame


func run() -> void:
	var was := GameState.hearing_aid
	var box: VBoxContainer = AudioManager._captions
	for c in box.get_children():
		c.free()
	GameState.hearing_aid = false
	AudioManager.cue("boss", "[A boss roars]", Palette.HAZARD)
	check(box.get_child_count() == 0, "off: a cue only plays its sound")
	GameState.hearing_aid = true
	AudioManager._pulse_at = -10.0
	AudioManager.cue("boss", "[A boss roars]", Palette.HAZARD)
	check(box.get_child_count() == 1 and str((box.get_child(0).get_child(0) as Label).text) == "[A boss roars]", "on: the cue shows its caption")
	AudioManager.cue("boss", "[A boss roars]")
	check(box.get_child_count() == 1 and str((box.get_child(0).get_child(0) as Label).text).ends_with("×2"), "the same sound again is counted, not stacked")
	for k in 6:
		AudioManager.cue("hit_heavy", "[Heavy blow %d]" % k)
	check(box.get_child_count() <= AudioManager.CAPTIONS_MAX, "at most %d captions at once" % AudioManager.CAPTIONS_MAX)
	await _frames()
	check(AudioManager._pulse.modulate.a > 0.0 or AudioManager._pulse_at > 0.0, "a big moment pulses the edges")
	var at := AudioManager._pulse_at
	AudioManager.cue("knockout", "[Down]", Palette.HAZARD)
	check(AudioManager._pulse_at == at, "pulses are spaced out (no strobing)")
	AudioManager.cue("hit", "")
	GameState.hearing_aid = was
	for c in box.get_children():
		c.free()
