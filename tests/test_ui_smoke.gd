extends "res://tests/base_test.gd"
## Draws every screen once, headless, so a script error in UI code fails the
## suite (the runner and CI fail on any SCRIPT ERROR): each camp tab and
## sub-tab, the Rift Hall and party screen, settings and the title with
## Feedback open, a ranked fight (More, the Guard picker, the victory
## screen), and an Endless Rift (level-up, chest and result panels).


## Waits on physics frames: the Endless Rift view shows its panels there,
## and a headless process frame can outrun the fixed physics tick.
func _frames(n: int = 3) -> void:
	for i in n:
		await get_tree().physics_frame


func _show(main: Node, scr: String, tab: String = "") -> void:
	main.screen = scr
	if tab != "":
		main.term_tab = tab
	main.render()
	await _frames()


func run() -> void:
	var main: Control = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await _frames()
	# Main loads the real save on boot; the test works in slot 9 instead.
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "Smoke"
	GameState.campaign_act = 3
	GameState.rifts_sealed = 5
	GameState.best_rift_rank_sealed = 5
	GameState.day = 12
	GameState.coins = 900
	GameState.crystals = 300
	var ids: Array[String] = []
	var party: Array = []
	for r in ["B", "B", "A", "B"]:
		var h := Combat.gen_hero(r, 22)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
		party.append(h)
	for i in 6:
		var it := Combat.gen_item(["common", "rare", "epic", "legendary"][i % 4])
		it.id = "i%d" % GameState.next_id
		GameState.next_id += 1
		GameState.items.append(it)
	GameState.relics.append(Combat.gen_relic("rare"))
	GameState.add_tonic("healing")
	GameState.refresh_recruit_pool()
	GameState.hero_request = {"type": "feud", "ids": [ids[0], ids[1]], "day": 10}
	GameState.pending_stories.clear()
	main.selected_hero_id = ids[0]

	var drawn := 0
	for tab in ["camp", "roster", "recruits", "medical", "inventory", "management", "ledger", "quests", "records", "memorial", "bestiary", "compendium"]:
		await _show(main, "camp", tab)
		drawn += 1
	for rt in ["skills", "history", "hero"]:
		main.roster_tab = rt
		await _show(main, "camp", "roster")
	for cat in ["items", "relics", "supplies", ""]:
		main.inv_category = cat
		await _show(main, "camp", "inventory")
	for rec in ["stats", "history", "achievements"]:
		main.records_tab = rec
		await _show(main, "camp", "records")
	for cl in ["guild_hall", "arcane_lab", ""]:
		main.hub_cluster = cl
		await _show(main, "camp", "camp")
	# Full-window scenes: the camp's buildings sit on the art layer and the UI
	# above lets clicks through; other screens keep a normal UI over a backdrop.
	await _show(main, "camp", "camp")
	check(main._scene_ui.get_child_count() > 0 and main.root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the camp fills the window and its buildings take clicks")
	await _show(main, "camp", "roster")
	check(main._scene_ui.get_child_count() == 0 and main._ambient_layer.get_child_count() > 0 and main.root.mouse_filter != Control.MOUSE_FILTER_IGNORE, "a camp tab gets a drifting backdrop and a normal UI")
	main._feedback_open = true
	for scr in ["rift_hall", "tower", "crafting_hall", "settings", "title", "load_game", "credits"]:
		await _show(main, scr)
		drawn += 1
	main._feedback_open = false
	main._pending_endless = true
	main.pending_party.assign(ids)
	await _show(main, "party_assembly")
	main._pending_endless = false
	check(drawn >= 19, "every camp tab and front-end screen draws (%d)" % drawn)

	# A ranked fight: the command bar, More, the Guard picker, a gamepad button.
	GameState.start_ladder_rift("A", ids, null)
	GameState.pending_stories.clear()
	await _show(main, "rift_run")
	GameState.engage_node()
	await _frames(5)
	main._more_open = false
	main.render()
	await _frames()
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_START
	pad.pressed = true
	main._unhandled_input(pad)
	await _frames()
	check(main._more_open, "Start on a gamepad opens More in a fight")
	main._ally_pick = "guard"
	main.render()
	await _frames()
	main._ally_pick = ""
	# Win it and draw the victory screen.
	var st: Dictionary = GameState.run["node_state"].get("combat_state", {})
	for m in st.get("monsters", []):
		m["hp"] = 1.0
	for k in 60:
		if GameState.run["node_state"].has("result"):
			break
		GameState.resolve_turn_now()
	main._combat_animating = false
	main.render()
	await _frames()
	check(GameState.run["node_state"].has("result"), "the fight ends and its result screen draws")
	GameState.retreat_now()
	await _show(main, "camp", "camp")

	# The Endless Rift: a level-up, a chest, and the sealed result.
	var v := SurvivorsView.new()
	v.setup(party, "ashen")
	add_child(v)
	await _frames()
	var r: SurvivorsRun = v.run
	while r.time < 130.0 and not r.over:
		r.step(0.1, r.autopilot_dir())
		r.settle_picks()
	r.pending_levels = 1
	await _frames(3)
	check(v._panel != null, "a level-up shows its picks")
	v._close_panel()
	r.pending_levels = 0
	r.pending_chests = 1
	await _frames(3)
	check(v._panel != null, "a chest shows its relics")
	v._close_panel()
	r.pending_chests = 0
	r.won = true
	r.over = true
	await _frames(3)
	check(v._panel != null and not v._summary.is_empty(), "the sealed-rift result draws")
	v.queue_free()
	main.queue_free()
	await _frames()
