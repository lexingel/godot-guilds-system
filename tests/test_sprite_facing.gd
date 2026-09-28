extends "res://tests/base_test.gd"
## Heroes face right and foes face left: art drawn the other way is mirrored
## in the arena and the Endless Rift. And the Act I intro waits until the
## guild is founded (Settings opened from the naming screen used to show it).


func _frames(n: int = 3) -> void:
	for i in n:
		await get_tree().physics_frame


func run() -> void:
	check(GameData.faces_away("res://assets/monsters/mire_sniper.png") and GameData.faces_away("carrion_crier"), "wrong-way foes are listed (by path or key)")
	check(GameData.faces_away("sub_acolyte") and GameData.faces_away("res://assets/heroes/cleric.png"), "wrong-way heroes too, including Endless walk keys")
	check(not GameData.faces_away("ash_harrier") and not GameData.faces_away("sub_duskstalker"), "art that already faces the right way is left alone")
	for key in GameData.SPRITE_FACES_AWAY:
		var known := GameData.MONSTER_SPRITE_PATH.has(key) or GameData.SUBCLASS_PORTRAIT_PATH.has(key) or ResourceLoader.exists("res://assets/heroes/%s.png" % key)
		check(known, "%s is a real sprite" % key)

	var main: Control = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await _frames()
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = ""
	GameState.pending_stories.clear()
	GameState.pending_stories.append({"title": "Test Intro", "subtitle": "", "text": "..."})
	main._pre_settings_screen = "onboard"
	main.screen = "settings"
	main.render()
	await _frames()
	var shown := func() -> bool:
		return main.find_children("*", "Label", true, false).any(func(l): return str(l.text) == "Test Intro")
	check(not shown.call(), "no story over Settings before the guild is founded")
	GameState.guild_name = "Facing"
	main.screen = "camp"
	main.render()
	await _frames()
	check(shown.call(), "the intro shows once the guild exists")
	GameState.pending_stories.clear()

	# The turn-order strip mirrors the same art the arena does.
	var party: Array[Hero] = []
	var strip: Control = main._turn_order_strip({"party": party, "turn_idx": 0,
		"monsters": [{"name": "Mire Sniper", "hp": 10.0}, {"name": "Ash Harrier", "hp": 10.0}],
		"turn_order": [{"type": "monster", "id": 0}, {"type": "monster", "id": 1}]})
	var icons := strip.find_children("*", "TextureRect", true, false)
	check(icons.size() == 2 and icons[0].flip_h and not icons[1].flip_h, "turn-order icons: Mire Sniper mirrored, Ash Harrier not")
	strip.free()
	main.queue_free()
	await _frames()
