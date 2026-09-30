extends GuildViews
## Root UI controller — mirrors guild-system.html's render() function: one
## place that clears and rebuilds the current screen's Controls from
## GameState, rather than a scene per screen. Uses the Cinzel/Overpass font
## pairing and a themed panel hierarchy (CardPanelViolet/CardPanelEmber/
## StatTileViolet/StatTileEmber) via guild_theme.tres.
##
## Top of the UI chain: boot, the render() router, top bar, title/onboarding,
## settings/save slots, Rift Hall and Party Assembly. Screen bodies live in
## the parent classes (see UiKit's header for the chain).

func _ready() -> void:
	GameState.load_settings()
	GameState.apply_language()
	GameState.load_active_slot()
	AudioManager.set_music_volume(GameState.music_volume)
	AudioManager.set_sfx_volume(GameState.sfx_volume)
	_apply_resolution(GameState.resolution_idx)
	get_tree().root.content_scale_factor = GameState.ui_scale
	_fit_to_window()
	get_tree().root.size_changed.connect(func():
		if _fit_to_window():
			render()
	)
	# Deliberately doesn't load_save()/reset() or route past "title" here —
	# every boot lands on the title screen now (New Game/Load Game/Credits/
	# Quit) regardless of whether the active slot has a guild in it, matching
	# the reference title screen rather than auto-resuming. New Game and Load
	# Game both route through _switch_slot(), which is what actually loads
	# (or resets) a slot's state once the player picks one.
	GameState.state_changed.connect(_on_state_changed)
	if OS.has_feature("web"):
		# Ask the browser not to evict the saves when it runs low on space.
		JavaScriptBridge.eval("navigator.storage && navigator.storage.persist && navigator.storage.persist();", true)
	if OS.get_cmdline_user_args().has("bench-survivors") or (OS.has_feature("web") and str(JavaScriptBridge.eval("location.search", true)).contains("bench=survivors")):
		_start_bench.call_deferred()
	# Portrait pop-ups live on their own CanvasLayer so render()'s
	# _clear_root() never wipes one mid-fade.
	var toast_layer := CanvasLayer.new()
	toast_layer.layer = 50
	# Main switches itself off while the Endless Rift runs; notices (and the
	# transition veil below) keep fading out on their own even then, or
	# they'd freeze on top of the run.
	toast_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(toast_layer)
	_toast_box = VBoxContainer.new()
	_toast_box.add_theme_constant_override("separation", 6)
	# Top right, under the currencies, stacking down: a narrow corner rather
	# than the middle of the page, where it sat on headings and cards.
	_toast_box.anchor_left = 1.0
	_toast_box.anchor_right = 1.0
	_toast_box.offset_left = -TOAST_W - 20.0
	_toast_box.offset_right = -20.0
	_toast_box.offset_top = 78
	_toast_box.offset_bottom = 400
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(_toast_box)
	# Full-window art under the UI (see UiKit's scene layers): the ambient
	# backdrop and the art under the vignette, the art's props just under Root.
	_root_filter = root.mouse_filter
	_ambient_layer = _new_layer(1)
	_scene_art = _new_layer(2)
	_scene_ui = _new_layer(root.get_index())
	var veil_layer := CanvasLayer.new()
	veil_layer.layer = 40
	veil_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(veil_layer)
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var veil_mat := ShaderMaterial.new()
	veil_mat.shader = preload("res://theme/transition.gdshader")
	_veil.material = veil_mat
	_veil.visible = false
	veil_layer.add_child(_veil)
	render()


var _root_filter := Control.MOUSE_FILTER_PASS
var _veil: ColorRect
var _veil_tw: Tween
var _was_bleed := false
var _navigated := false   # this render moved to another screen or tab


func _new_layer(index: int) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	move_child(c, index)
	return c


## Uncovers the new screen: a quick fade from dark, or an iris opening with a
## violet rim when stepping into a rift. Runs in real time (a rift's speed
## setting doesn't touch it).
func _play_transition(iris: bool) -> void:
	if _veil == null:
		return
	var mat := _veil.material as ShaderMaterial
	var win := get_viewport().get_visible_rect().size
	mat.set_shader_parameter("iris", iris)
	mat.set_shader_parameter("aspect", win.x / maxf(1.0, win.y))
	mat.set_shader_parameter("progress", 0.0)
	_veil.visible = true
	if _veil_tw != null:
		_veil_tw.kill()
	_veil_tw = _veil.create_tween()
	_veil_tw.set_ignore_time_scale(true)
	_veil_tw.tween_interval(0.15 if iris else 0.04)
	_veil_tw.tween_method(func(p: float): mat.set_shader_parameter("progress", p), 0.0, 1.0, 0.75 if iris else 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_veil_tw.tween_callback(func(): _veil.visible = false)


## The art behind each screen that has no full-window scene of its own,
## shown dim and drifting (see _set_ambient).
func _ambient_path() -> String:
	match screen:
		"camp":
			match term_tab:
				"inventory": return GameData.INVENTORY_BG
				"medical": return GameData.MEDICAL_BG
				"management": return GameData.MANAGEMENT_BG
				"quests": return GameData.QUEST_BOARD_BG
				"roster", "recruits", "champions": return "res://assets/screens/roster_bg.png"
			return GameData.HAMLET_BG
		"crafting_hall": return GameData.CRAFTING_BG
		"rift_hall", "party_assembly", "tower": return GameData.RIFTHALL_BG
		"rift_run": return "res://assets/screens/riftpath_bg.png"
	return GameData.TITLE_BG


## Desktop-only: on a Web export the browser/canvas already owns sizing (via
## project.godot's stretch/mode="canvas_items" + aspect="expand", which fits
## the canvas to its container correctly on its own) — forcing an internal
## window resize there fights that and desyncs the visual layout from where
## clicks actually land (confirmed: it's what caused the click-position bug
## reported after this feature first shipped). Real OS window resizing only
## makes sense where the game owns a real OS window, i.e. never on web.
func _apply_resolution(idx: int) -> void:
	if OS.has_feature("web"):
		return
	var opts: Array = GameData.RESOLUTION_OPTIONS
	var opt: Dictionary = opts[idx] if idx >= 0 and idx < opts.size() else opts[0]
	# A maximized/fullscreen OS window silently ignores a `.size` assignment
	# (Godot doesn't auto-restore it), which is why picking a resolution here
	# previously had no visible effect once the window had been maximized.
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(int(opt["w"]), int(opt["h"]))


## The canvas the UI is laid out on, by the window's shape:
## - 1280x800 on a desktop or tablet.
## - 800x450 on a short landscape window (a phone on its side, see
##   COMPACT_MAX_H): everything is drawn nearly twice as large, and screens
##   use the stacked layouts (_narrow) and scroll (_compact).
## - 760x800 on a portrait window; a phone held upright is asked to turn
##   (_rotate_prompt), since a fight doesn't fit across it.
## Sizes are compared in CSS pixels (the window's, over the screen's scale).
## Returns whether anything changed.
func _fit_to_window() -> bool:
	var win := get_tree().root
	var css := Vector2(win.size) / maxf(1.0, DisplayServer.screen_get_scale())
	var portrait := win.size.x < win.size.y * 0.9
	var want := Vector2i(1280, 800)
	if portrait:
		want = Vector2i(760, 800)
	elif css.y < COMPACT_MAX_H:
		want = COMPACT_CANVAS
	var rotate := portrait and css.x < COMPACT_MAX_H
	if win.content_scale_size == want and rotate == _rotate_prompt:
		return false
	win.content_scale_size = want
	_rotate_prompt = rotate
	return true


var _toast_box: VBoxContainer
const TOAST_W := 330.0
const TOAST_MAX := 2   # at once; the rest wait their turn


## Shows every queued GameState toast as a portrait card at the top right,
## each fading out on its own after a few seconds (real time — unaffected by
## the combat speed setting).
func _drain_toasts() -> void:
	if _toast_box == null:
		return
	# A story card is up: the pills wait for it (they'd sit on its title).
	if _rotate_prompt:
		return
	if not GameState.pending_stories.is_empty() and GameState.guild_name != "" and screen not in ["title", "load_game", "credits", "onboard"]:
		return
	# Mid-fight they'd sit on the arena: they wait for the fight to end.
	var ns: Dictionary = GameState.run.get("node_state", {}) if screen == "rift_run" else {}
	if ns.has("combat_state") and not ns.has("result"):
		return
	# The phone canvas: one at a time, narrower, right under its shorter header.
	var compact := _compact()
	var toast_w := 270.0 if compact else TOAST_W
	_toast_box.offset_left = -toast_w - (10.0 if compact else 20.0)
	_toast_box.offset_right = -10.0 if compact else -20.0
	_toast_box.offset_top = 50.0 if compact else 78.0
	_toast_box.offset_bottom = 300.0 if compact else 400.0
	while not GameState.pending_toasts.is_empty() and _toast_box.get_children().filter(func(c): return not c.is_queued_for_deletion()).size() < (1 if compact else TOAST_MAX):
		var t: Dictionary = GameState.pending_toasts.pop_front()
		# A card in the corner: the title over its text. Click to dismiss.
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.size_flags_horizontal = Control.SIZE_SHRINK_END
		card.tooltip_text = tr("Click to dismiss")
		var style := StyleBoxFlat.new()
		style.bg_color = Color(Palette.SURFACE2, 0.94)
		style.border_color = Palette.EMBER_BRIGHT
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(9)
		card.add_theme_stylebox_override("panel", style)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var portrait := GameData.portrait_for_hero(str(t["cls_id"]), str(t["pool_id"]))
		if portrait != "":
			row.add_child(_icon_trimmed(portrait, 28))
		var tcol := _vbox(1)
		tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tcol)
		if str(t["title"]) != "":
			var title := _label(str(t["title"]), 13)
			title.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
			tcol.add_child(title)
		var body := _label(str(t["text"]), 13)
		# Wraps only past the card's widest.
		var font := body.get_theme_font("font")
		if font.get_string_size(body.text, HORIZONTAL_ALIGNMENT_LEFT, -1, body.get_theme_font_size("font_size")).x > toast_w - 80.0:
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.custom_minimum_size.x = toast_w - 80.0
		tcol.add_child(body)
		card.add_child(row)
		_toast_box.add_child(card)
		AudioManager.play_sfx(GameData.SFX_PATH["ui_confirm"])
		var gone := func():
			if is_instance_valid(card) and not card.is_queued_for_deletion():
				card.queue_free()
				_drain_toasts.call_deferred()   # the next one waiting takes its place
		card.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed:
				gone.call())
		var tw := card.create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_interval(5.0)
		tw.tween_property(card, "modulate:a", 0.0, 0.6)
		tw.tween_callback(gone)


func render() -> void:
	# A fight is playing out: rebuilding now would free the arena under its
	# animation. The fight re-renders itself when the turn is done.
	if _combat_animating and screen == "rift_run":
		return
	_coached_this_render = false
	GameState.session_live = screen not in ["title", "load_game", "credits", "onboard"]
	var was_focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if was_focused is Button:
		_pad_focus_text = (was_focused as Button).text
	_combat_hotkeys.clear()
	if _pad_mode:
		_pad_focus.call_deferred()
	# Combat speed only ever applies inside a rift — camp animations (embers,
	# day/night drift) always run at normal speed.
	Engine.time_scale = minf(GameState.combat_speed, 3.0) if screen == "rift_run" else 1.0
	GameState.resolve_recovery()
	GameState.resolve_guild_board()
	GameState.refresh_looks()
	if GameState.guild_name != "":
		if not GameState.check_feature_unlocks().is_empty():
			AudioManager.play_sfx(GameData.SFX_PATH["unlock"])
	var newly_claimed := GameState.check_milestones()
	if newly_claimed.size() == 1:
		var m = GameData.MILESTONES.filter(func(x): return str(x["id"]) == newly_claimed[0])[0]
		GameState.pending_toasts.append({"cls_id": "", "pool_id": "", "title": tr("Achievement earned"), "text": str(m["label"])})
	elif newly_claimed.size() > 1:
		GameState.pending_toasts.append({"cls_id": "", "pool_id": "", "title": tr("%d achievements earned") % newly_claimed.size(), "text": tr("See Records in the Guild Hall.")})
	# Once, on the web, after a guild has something worth losing.
	if OS.has_feature("web") and GameState.guild_name != "" and GameState.last_export_day < 0 and GameState.rifts_sealed >= 3 and not GameState.hints_seen.has("backup_nudge"):
		GameState.hints_seen.append("backup_nudge")
		GameState.pending_toasts.append({"cls_id": "", "pool_id": "", "title": tr("Back up your guild"),
			"text": tr("It lives in this browser only. Settings > Backup > Export save keeps a copy.")})
	if _flavor_toast != "":
		GameState.pending_toasts.append({"cls_id": "", "pool_id": "", "title": "", "text": _flavor_toast})
		_flavor_toast = ""
	_drain_toasts()
	if not GameState.pending_s_rank_reveal.is_empty() and _s_rank_celebration.is_empty():
		_s_rank_celebration = GameState.pending_s_rank_reveal
		GameState.pending_s_rank_reveal = {}
		AudioManager.play_sfx(GameData.SFX_PATH["victory"])
		get_tree().create_timer(2.5).timeout.connect(func():
			_s_rank_celebration = {}
			render()
		)
	# Toggling something in place (Skills, an equip slot, a Guild Management
	# branch, ...) rebuilds the whole screen via _clear_root() below, which
	# would otherwise silently snap the scroll position back to the top every
	# time — jarring on a long screen. Carry it over whenever we're rebuilding
	# the SAME screen/tab; only a real navigation resets to the top.
	var render_key := "%s|%s|%s" % [screen, term_tab, hub_cluster]
	var is_navigation := render_key != _last_render_key
	var prev_screen := _last_render_key.get_slice("|", 0)
	_navigated = is_navigation
	if not is_navigation:
		for c in root.get_children():
			if c is VBoxContainer:
				for cc in c.get_children():
					if cc is ScrollContainer:
						_last_scroll_y = cc.scroll_vertical
	else:
		_last_scroll_y = 0.0
	_last_render_key = render_key

	_clear_root()
	# On a full-window scene the UI lets clicks through to the art's props.
	var bleed := _bleed_ui()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE if bleed else _root_filter
	_set_ambient("" if bleed or screen == "title" else _ambient_path())
	var outer := _vbox(4 if _compact() else 10)
	if bleed:
		outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(outer)
	if screen not in ["title", "load_game", "credits", "onboard"]:
		# The tabs first: on the phone canvas their buttons go in the top bar (_nav_bar).
		_nav_bar = null
		var nav: Control = _quick_nav() if screen in ["camp", "crafting_hall", "rift_hall"] else null
		_topbar(outer, _breadcrumb_for_screen())
		var back := _header_back()
		if not back.is_empty():
			_combat_hotkeys["Escape"] = back[0]
		if nav:
			outer.add_child(nav)
	if not _s_rank_celebration.is_empty():
		outer.add_child(_render_s_rank_celebration(_s_rank_celebration))

	var v := _vbox(14)
	if bleed:
		# The screen's panels sit straight on the art, no scrolling.
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.size_flags_vertical = Control.SIZE_EXPAND_FILL
		outer.add_child(v)
	else:
		var scroll := ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		outer.add_child(scroll)
		scroll.set_deferred("scroll_vertical", _last_scroll_y)
		v.custom_minimum_size = Vector2(_column_width(), 0)
		# Centered in the window instead of hugging the left edge.
		var center := CenterContainer.new()
		center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(center)
		center.add_child(v)

	match screen:
		"title": _render_title(v)
		"load_game": _render_load_game(v)
		"credits": _render_credits(v)
		"onboard": _render_onboard(v)
		"rift_hall": _render_rift_hall(v)
		"party_assembly": _render_party_assembly(v)
		"defense": _render_defense_setup(v)
		"tower":
			if GameState.feature_unlocked("tower"):
				_render_tower(v)
			else:
				_locked_feature(v, "tower")
		"rift_run": _render_rift_run(v)
		"crafting_hall":
			if GameState.feature_unlocked("crafting"):
				_render_crafting_hall(v)
			else:
				_locked_feature(v, "crafting")
		"settings": _render_settings(v)
		"camp": _render_camp_screen(v)
	_update_screen_music()

	# A real navigation (not an in-place data refresh — see is_navigation
	# above) fades the new screen in from transparent instead of just
	# snapping into place, so moving between hubs reads as one continuous
	# world instead of a slideshow of unrelated pages.
	# Not before the guild is founded: the Act I intro waits for the camp, even
	# when Settings is opened from the naming screen.
	if _rotate_prompt:
		_rotate_overlay()
	elif not GameState.pending_stories.is_empty() and GameState.guild_name != "" and screen not in ["title", "load_game", "credits", "onboard"]:
		var card_key := "story:" + str(GameState.pending_stories[0].get("title", ""))
		if not _sfx_seen.has(card_key):
			_sfx_seen[card_key] = true
			AudioManager.play_sfx(GameData.SFX_PATH["story"])
		_story_overlay(GameState.pending_stories[0])
	elif screen in ["camp", "rift_hall"] and GameState.guild_name != "" and _unseen_matter() != "":
		_matter_overlay(_unseen_matter())
	# A new screen (or a switch to or from a full-window scene) uncovers
	# from dark, stepping into a rift opens like one; a new tab within a
	# screen just fades its panels in.
	var bleed_now := bleed or screen == "title"
	if is_navigation and (screen != prev_screen or bleed_now != _was_bleed):
		_play_transition(screen == "rift_run" and prev_screen not in ["", "rift_run"])
	elif is_navigation:
		root.modulate = Color(1, 1, 1, 0)
		var fade_tw := create_tween()
		fade_tw.tween_property(root, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
	_was_bleed = bleed_now


## A phone held upright: the game needs the long side across (a fight is six
## figures in a row), so it asks, over whatever screen is up.
func _rotate_overlay() -> void:
	var cover := ColorRect.new()
	cover.color = Color(0.06, 0.05, 0.1)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := _vbox(14)
	var t := _label("Turn your phone sideways", 30)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 600
	t.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	col.add_child(t)
	var sub := _wrap_label("Guildhold plays in landscape.", 22, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	center.add_child(col)
	cover.add_child(center)
	root.add_child(cover)


## A campaign story card over the screen (act intros, finale outros, the
## ending). Continue shows the next queued card or returns to the game.
func _story_overlay(card_data: Dictionary) -> void:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP]:
		dim.set_offset(side, -80)
	for side in [SIDE_RIGHT, SIDE_BOTTOM]:
		dim.set_offset(side, 80)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelEmber"
	card.custom_minimum_size.x = minf(560.0, get_viewport().get_visible_rect().size.x - 40.0)
	var cv := _vbox(10)
	var title := _label(str(card_data.get("title", "")), 24)
	title.add_theme_color_override("font_color", Palette.RANK_S)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(title)
	if str(card_data.get("subtitle", "")) != "":
		var sub := _wrap_label(str(card_data["subtitle"]), 13, true)
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(sub)
	cv.add_child(_hsep())
	var body := _wrap_label(str(card_data.get("text", "")), 15)
	cv.add_child(body)
	var cont := _icon_domain_button("ember", GameData.BUTTON_ICON_PATH["confirm"], "Continue", func():
		GameState.pending_stories.pop_front()
		GameState.save()
		render()
	)
	cont.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cv.add_child(cont)
	_combat_hotkeys = {"Space": cont.pressed.emit, "Escape": cont.pressed.emit}
	card.add_child(cv)
	center.add_child(card)
	root.add_child(overlay)


## A hero's request or the rival's move, popped up over the camp the first
## time you're home after it arrives.
func _matter_overlay(kind: String) -> void:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := _matter_card(kind, true)
	card.custom_minimum_size.x = minf(600.0, get_viewport().get_visible_rect().size.x - 40.0)
	center.add_child(card)
	root.add_child(overlay)


## Camp-side screens play a camp track (a new one each time you come home);
## a rift's fights play one combat track for the whole run. Screens between
## (a rift's map, events) keep whatever is playing. AudioManager.play_music
## no-ops on a repeat of the same path, so this is safe on every render.
var _camp_track := ""     # this stay at camp's track ("" = pick one on arrival)
var _combat_track := ""   # this run's combat track
var _last_camp_track := ""
var _last_combat_track := ""


func _update_screen_music() -> void:
	if screen in ["camp", "rift_hall", "party_assembly", "tower", "crafting_hall", "settings", "title", "load_game", "credits", "onboard"]:
		if _camp_track == "":
			_camp_track = GameData.pick_track(GameData.CAMP_MUSIC, _last_camp_track)
			_last_camp_track = _camp_track
		_combat_track = ""   # the next run picks its own
		AudioManager.play_music(_camp_track)
	elif screen == "rift_run":
		var kind := GameState.current_node_kind()
		var ns: Dictionary = GameState.run.get("node_state", {})
		if kind in ["combat", "boss", "elite"] and ns.has("combat_state"):
			if _combat_track == "":
				_combat_track = GameData.pick_track(GameData.COMBAT_MUSIC, _last_combat_track)
				_last_combat_track = _combat_track
			_camp_track = ""   # coming home picks a new one
			AudioManager.play_music(_combat_track)


## Pinned HUD stays outside the ScrollContainer, so the guild identity,
## currencies, and "where am I" breadcrumb never scroll out of view.
const TAB_TITLE := {"roster": "Heroes", "management": "Management", "quests": "Quests", "compendium": "Codex", "medical": "Medical Bay", "inventory": "Items"}


func _breadcrumb_for_screen() -> String:
	match screen:
		"rift_hall": return "Rift Hall"
		"tower": return "Tower of Trials"
		"party_assembly": return "Party Assembly"
		"defense": return "Riftbreak"
		"rift_run" when GameState.run.has("tower"): return tr("Tower of Trials — Floor %d") % int(GameState.run["tower"])
		"rift_run": return tr("Rift Run — Floor %d/%d") % [int(GameState.run.get("pos", 0)) + 1, GameState.run.get("layers", []).size()]
		"crafting_hall": return "Crafting"
		"settings": return "Settings"
		"camp": return tr("Camp") if term_tab == "camp" else tr("Camp — %s") % tr(str(TAB_TITLE.get(term_tab, term_tab.capitalize())))
		_: return ""


## The Rank-S celebration banner shown pinned above the scroll area (outside
## the ScrollContainer, like the HUD) for the ~2.5s render() holds it. A
## pop-in scale/fade plus a looping glow pulse on the portrait ring — no
## full-viewport flash, since this Container-based layout isn't built for
## free-floating overlays and a contained "the banner itself glows" reads
## just as celebratory without fighting that. Tweens are bound to `banner`
## itself so they're auto-killed the moment the next render() frees it,
## rather than lingering bound to Main (which never gets freed).
func _render_s_rank_celebration(data: Dictionary) -> Control:
	var banner := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.RANK_S.r, Palette.RANK_S.g, Palette.RANK_S.b, 0.18)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Palette.RANK_S
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 14
	style.content_margin_top = 10
	style.content_margin_right = 14
	style.content_margin_bottom = 10
	banner.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var portrait_wrap := PanelContainer.new()
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(Palette.RANK_S.r, Palette.RANK_S.g, Palette.RANK_S.b, 0.4)
	glow_style.corner_radius_top_left = 30
	glow_style.corner_radius_top_right = 30
	glow_style.corner_radius_bottom_right = 30
	glow_style.corner_radius_bottom_left = 30
	glow_style.shadow_color = Color(Palette.RANK_S.r, Palette.RANK_S.g, Palette.RANK_S.b, 0.8)
	glow_style.shadow_size = 16
	portrait_wrap.add_theme_stylebox_override("panel", glow_style)
	portrait_wrap.add_child(_framed_portrait(str(data["cls_id"]), str(data["pool_id"]), 56.0))
	row.add_child(portrait_wrap)

	var mid := _vbox(2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var headline := _label("★ RANK S ★", 18)
	headline.add_theme_color_override("font_color", Palette.RANK_S)
	mid.add_child(headline)
	var source_text := tr("is offered as a Champion!") if str(data["source"]) == "champion" else tr("is available to recruit!")
	mid.add_child(_label("%s %s" % [tr(str(data["name"])), tr(str(source_text))], 13))
	row.add_child(mid)

	banner.add_child(row)

	banner.scale = Vector2(0.85, 0.85)
	banner.modulate.a = 0.0
	var pop_tw := banner.create_tween()
	pop_tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop_tw.tween_property(banner, "scale", Vector2.ONE, 0.25)
	pop_tw.parallel().tween_property(banner, "modulate:a", 1.0, 0.2)

	var glow_tw := banner.create_tween()
	glow_tw.set_loops()
	glow_tw.tween_property(portrait_wrap, "modulate", Color(1.3, 1.3, 1.0), 0.5)
	glow_tw.tween_property(portrait_wrap, "modulate", Color(1.0, 1.0, 1.0), 0.5)

	return banner


## The header bar — previously just a bare HBoxContainer floating directly on
## the screen background with a plain hairline under it, so the currency
## tiles' own borders were the only bordered thing up there. Wrapped in one
## bordered bar so the whole header reads as a single designed piece instead
## of loose elements, matching the bordered-card language the rest of the UI
## already uses (CardPanelEmber/StatTileEmber).
## What each header currency is for (keyed by its icon path).
var CURRENCY_TIPS := {
	GameData.CURRENCY_ICON_PATH["coins"]: "Gold — recruit and train heroes, buy from rift shops and supplies, reroll offers.",
	GameData.CURRENCY_ICON_PATH["crystals"]: "Essence — earned by fighting and sealing rifts. Evolves heroes, upgrades relics and the guild, reforges gear, resets attributes.",
	}


var _shown_counts: Dictionary = {}   # currency icon path -> value the header last showed


## A number label that counts up (or down) from the value it showed last
## time, so a currency change reads as a change instead of a silent swap.
func _count_label(key: String, value: int, size: int) -> Label:
	var l := _label(str(value), size)
	var from: int = int(_shown_counts.get(key, value))
	_shown_counts[key] = value
	if from != value:
		l.text = str(from)
		var tw := l.create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_method(func(x: float): l.text = str(int(round(x))), float(from), float(value), 0.6).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(l, "modulate", Palette.RANK_S if value > from else Palette.HAZARD, 0.1)
		tw.tween_property(l, "modulate", Color.WHITE, 0.4)
	return l


## The five camp tabs, reachable from any camp-side screen in one click or
## one key (1-5). Each groups screens that belong together; a group with more
## than one shows them as sub-tabs underneath.
## [label, icon id, [[screen id, sub-tab label, camp building whose attention badge it shares], ...]]
const NAV_GROUPS := [
	["Roster", "roster", [["roster", "Heroes"], ["recruits", "Recruits"], ["medical", "Medical Bay"], ["champions", "Champions"]]],
	["Inventory", "inventory", [["inventory", "Items"], ["crafting", "Crafting"]]],
	["Rift Hall", "rift", [["rift", "Rift Hall"]]],
	["Guild", "management", [["management", "Management"], ["ledger", "Ledger"], ["quests", "Quests"], ["records", "Records"], ["memorial", "Memorial"]]],
	["Library", "bestiary", [["bestiary", "Bestiary"], ["compendium", "Codex"]]],
]
const NAV_FEATURE := {"champions": "champions", "crafting": "crafting", "quests": "quests", "management": "management", "inventory": "inventory", "medical": "medical", "bestiary": "bestiary"}


func _quick_nav_current() -> String:
	match screen:
		"crafting_hall": return "crafting"
		"rift_hall": return "rift"
		"camp": return "" if term_tab == "camp" else term_tab
	return ""


func _nav_locked(id: String) -> bool:
	return NAV_FEATURE.has(id) and not GameState.feature_unlocked(NAV_FEATURE[id])


## Camp tabs by gamepad shoulder button: the next (or previous) open tab.
func _pad_cycle_tab(step: int) -> void:
	var cur := _quick_nav_current()
	var gi := 0
	for i in NAV_GROUPS.size():
		if (NAV_GROUPS[i][2] as Array).any(func(m): return str(m[0]) == cur):
			gi = i
	for k in NAV_GROUPS.size():
		gi = (gi + step + NAV_GROUPS.size()) % NAV_GROUPS.size()
		var open: Array = (NAV_GROUPS[gi][2] as Array).filter(func(m): return not _nav_locked(str(m[0])))
		if not open.is_empty():
			_quick_go(str(open[0][0]))
			return


func _quick_go(id: String) -> void:
	hub_cluster = ""
	inv_category = ""
	mgmt_branch = ""
	medical_picker_bed = -1
	match id:
		"crafting": screen = "crafting_hall"
		"rift": screen = "rift_hall"
		_:
			screen = "camp"
			term_tab = id
	render()


var _nav_bar: Control = null   # the phone canvas: the tab buttons, for the top bar


func _quick_nav() -> Control:
	var col := _vbox(6)
	var compact := _compact()
	# Wraps to two rows on the narrow (portrait) canvas; a plain row in the phone's top bar.
	var bar: Container
	if compact:
		bar = HBoxContainer.new()
		bar.add_theme_constant_override("separation", 4)
	else:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		bar = flow
	if compact:
		_nav_bar = bar   # icons only, in the top bar; only the sub-tabs stay below
	else:
		col.add_child(bar)
	var badges := _camp_badges()
	var current := _quick_nav_current()
	for i in NAV_GROUPS.size():
		var g: Array = NAV_GROUPS[i]
		var members: Array = g[2]
		var ids: Array = members.map(func(m): return str(m[0]))
		var open: Array = ids.filter(func(id): return not _nav_locked(id))
		var key := str(i + 1)
		var locked := open.is_empty()
		var go := _quick_go.bind(str(open[0]) if not locked else "")
		var b := _button("", go)
		b.custom_minimum_size = Vector2(48, 38) if compact else Vector2(88, 54)
		b.toggle_mode = true
		b.button_pressed = ids.has(current)
		b.tooltip_text = tr("%s  (key %s)") % [tr(str(g[0])), tr(str(key))]
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if locked:
			b.disabled = true
			b.modulate = Color(1, 1, 1, 0.45)
			b.tooltip_text = "%s — %s" % [tr(str(g[0])), tr(str(GameData.FEATURE_UNLOCKS[NAV_FEATURE[ids[0]]]["hint"]))]
		var tile := VBoxContainer.new()
		tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tile.alignment = BoxContainer.ALIGNMENT_CENTER
		tile.add_theme_constant_override("separation", 1)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := _icon(GameData.CAMP_HUB_ICON_PATH[str(g[1])], 26)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(ic)
		if not compact:
			var nl := _label(str(g[0]), 12)
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tile.add_child(nl)
		b.add_child(tile)
		if not locked:
			_combat_hotkeys[key] = go
		if not compact:
			var kl := _label(key, 12)
			kl.add_theme_color_override("font_color", Palette.MUTED)
			kl.position = Vector2(3, 0)
			b.add_child(kl)
		for m in members:
			var badge: Array = badges.get(str(m[0]), [])
			if not badge.is_empty() and not _nav_locked(str(m[0])):
				var chip := _count_badge(str(badge[0]), str(badge[1]))
				chip.position = Vector2(32 if compact else 70, -6)
				b.add_child(chip)
				break
		bar.add_child(b)
		# Sub-tabs for the open group.
		if ids.has(current) and members.size() > 1:
			var sub := HFlowContainer.new()
			sub.add_theme_constant_override("h_separation", 4)
			sub.alignment = FlowContainer.ALIGNMENT_CENTER
			for m in members:
				var sid := str(m[0])
				var sb := _button(str(m[1]), _quick_go.bind(sid))
				sb.toggle_mode = true
				sb.button_pressed = sid == current
				sb.custom_minimum_size = Vector2(92, 32)
				var badge: Array = badges.get(str(m[0]), [])
				if _nav_locked(sid):
					sb.disabled = true
					sb.modulate = Color(1, 1, 1, 0.45)
					sb.tooltip_text = GameData.FEATURE_UNLOCKS[NAV_FEATURE[sid]]["hint"]
				elif not badge.is_empty():
					sb.text = "%s  %s" % [tr(str(m[1])), tr(str(badge[0]))]
					sb.tooltip_text = str(badge[1])
				sub.add_child(sb)
			col.add_child(sub)
	return col


## The header's back button for this screen: [callback, destination name],
## or [] for none. Every screen's "back" lives here, so it's always in the
## same place instead of at the bottom of a long page.
func _header_back() -> Array:
	var to_camp := func():
		screen = "camp"
		term_tab = "camp"
		hub_cluster = ""
		medical_picker_bed = -1
		mgmt_branch = ""
		inv_category = ""
		render()
	match screen:
		"camp":
			if term_tab == "inventory" and inv_category != "":
				return [func(): inv_category = ""; render(), "Inventory"]
			if term_tab == "management" and mgmt_branch != "":
				return [func(): mgmt_branch = ""; render(), "Management"]
			if term_tab != "camp" or hub_cluster != "":
				return [to_camp, "Camp"]
		"rift_hall", "crafting_hall":
			return [to_camp, "Camp"]
		"defense":
			return [func(): screen = "rift_hall"; render(), "Rift Hall"]
		"tower":
			return [func(): screen = "rift_hall"; render(), "Rift Hall"]
		"party_assembly":
			if _pending_tower:
				return [func(): _pending_tower = false; screen = "tower"; render(), "Tower"]
			if _pending_daily:
				return [func(): _pending_daily = false; screen = "rift_hall"; render(), "Rift Hall"]
			return [func():
				screen = "rift_hall"
				_pending_rift_rank = ""
				render()
			, "Rift Hall"]
		"settings":
			const NAMES := {"camp": "Camp", "rift_run": "Rift", "rift_hall": "Rift Hall", "tower": "Tower",
				"party_assembly": "Party Assembly", "crafting_hall": "Crafting"}
			return [func(): screen = _pre_settings_screen; render(), NAMES.get(_pre_settings_screen, tr("Back"))]
	return []


## Content column width: combat, the camp scene and the two-pane screens
## use the window's width; text-heavy screens stay at a readable measure.
func _column_width() -> float:
	var avail: float = get_viewport().get_visible_rect().size.x - 64.0
	if screen == "rift_run":
		return _battle_width()
	if screen == "title":
		return avail
	if screen == "camp" and ((term_tab == "camp" and hub_cluster == "") or term_tab in ["roster", "inventory", "bestiary"]):
		return clampf(avail, minf(760.0, avail), 1180.0)
	return clampf(avail, minf(700.0, avail), 860.0)


func _topbar(container: Control, breadcrumb: String = "") -> void:
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Palette.SURFACE2
	bar_style.border_width_bottom = 2
	bar_style.border_color = Palette.EMBER_DEEP
	bar_style.content_margin_left = 12.0
	bar_style.content_margin_right = 12.0
	bar_style.content_margin_top = 3.0 if _compact() else 8.0
	bar_style.content_margin_bottom = 3.0 if _compact() else 8.0
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", bar_style)
	var bar_v := _vbox(4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var back := _header_back()
	if not back.is_empty():
		var bb := _button("" if _compact() else str(back[1]), back[0])
		bb.icon = load(GameData.BUTTON_ICON_PATH["back"])
		bb.tooltip_text = tr("Back to %s") % tr(str(back[1]))
		bb.custom_minimum_size = Vector2(40, 36)
		row.add_child(bb)
	if _nav_bar != null:
		row.add_child(_nav_bar)
	elif not _compact() or screen == "camp":
		row.add_child(_icon(GameData.CREST_PATH[GameState.guild_crest - 1], 24))
		var name_lbl := _label(GameState.guild_name, 16)
		name_lbl.add_theme_font_override("font", DISPLAY_FONT)
		name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(name_lbl)
	elif breadcrumb != "":
		# No room for the guild's name: say where you are instead.
		var here := _label(tr(breadcrumb), 15)
		here.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		here.clip_text = true
		here.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(here)
	var titles: Array = [GameState.tower_title(), GameState.endless_title()].filter(func(x): return x != "")
	if not titles.is_empty() and not _narrow():
		var title_lbl := _label(" · ".join(titles), 12)
		title_lbl.add_theme_color_override("font_color", Palette.RANK_S)
		title_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_lbl.tooltip_text = tr("Guild titles — Tower of Trials (best floor %d) and the Endless Rift (best %d:%02d)") % [GameState.tower_best, GameState.best_endless_time / 60, GameState.best_endless_time % 60]
		title_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(title_lbl)
	if breadcrumb != "" and not _narrow():
		var crumb := _label("›  " + tr(breadcrumb), 16)
		crumb.add_theme_color_override("font_color", Palette.MUTED)
		crumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(crumb)
	var stat_spacer := Control.new()
	stat_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(stat_spacer)
	for entry in [
		[GameData.CURRENCY_ICON_PATH["coins"], GameState.coins],
		[GameData.CURRENCY_ICON_PATH["crystals"], GameState.crystals],
		[GameData.CURRENCY_ICON_PATH["reputation"], GameState.reputation],
	]:
		var stat_row := HBoxContainer.new()
		stat_row.add_child(_icon(entry[0], 18))
		var count := _count_label(str(entry[0]), int(entry[1]), 16)
		stat_row.add_child(count)
		var tile := PanelContainer.new()
		tile.theme_type_variation = &"StatTileEmber"
		tile.tooltip_text = CURRENCY_TIPS.get(str(entry[0]), "")
		if entry[0] == GameData.CURRENCY_ICON_PATH["reputation"]:
			# Renown is the race with the rival: the tile shows where you stand.
			var lead := GameState.reputation - GameState.rival_renown
			count.add_theme_color_override("font_color", Palette.good() if lead > 0 else (Palette.HAZARD if lead < 0 else Palette.TEXT))
			tile.tooltip_text = tr("Renown %d — %s %s (%d). The leader at payday gets the better recruits; every 20 arms an Epic at your next rift shop. See Guild > Ledger.") % [GameState.reputation,
				tr("you lead") if lead > 0 else (tr("you trail") if lead < 0 else tr("level with")), tr(str(GameState.rival_name)), GameState.rival_renown]
		tile.mouse_filter = Control.MOUSE_FILTER_STOP
		tile.add_child(stat_row)
		row.add_child(tile)
	var settings_btn := TextureButton.new()
	settings_btn.texture_normal = load(GameData.CAMP_HUB_ICON_PATH["settings"])
	settings_btn.ignore_texture_size = true
	settings_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	settings_btn.custom_minimum_size = Vector2(32, 32)
	settings_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	settings_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	settings_btn.tooltip_text = "Settings"
	settings_btn.pressed.connect(func():
		AudioManager.play_sfx(GameData.SFX_PATH["ui_click"])
		_pre_settings_screen = screen
		screen = "settings"
		render()
	)
	row.add_child(settings_btn)
	bar_v.add_child(row)
	bar.add_child(bar_v)
	container.add_child(bar)


# ---------------- Title ----------------
## The very first thing every boot shows now (see _ready()) — New Game finds
## the first empty save slot and jumps straight into founding a guild there,
## or falls back to the slot list if all 3 are full so the player picks one
## to overwrite. Load Game and Credits are their own screens; Quit is hidden
## on Web (a browser tab can't close itself, and Godot's own quit() there
## just does nothing visible — see _apply_resolution's identical OS.has_feature
## gate for the same "web owns this, not us" reasoning).
func _render_title(v: VBoxContainer) -> void:
	_title_scene()
	var narrow := _narrow()
	# The name and menu on the left, what's new on the right (stacked on a
	# portrait window), over the full-window art.
	v.custom_minimum_size.y = get_viewport().get_visible_rect().size.y - 48.0
	var cols: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	var left := _vbox(10)
	left.custom_minimum_size.x = 320
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cols.add_child(left)

	var title_lbl := _on_art(_label("Guildhold", 60), 12)
	title_lbl.add_theme_font_override("font", DISPLAY_FONT)
	title_lbl.language = "en"   # the name keeps its dotless I whatever the game's language
	title_lbl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.87, 0.62))
	title_lbl.add_theme_color_override("font_shadow_color", Color(1.0, 0.5, 0.15, 0.35))
	title_lbl.add_theme_constant_override("shadow_outline_size", 22)
	left.add_child(title_lbl)
	left.add_child(_on_art(_label("A guild-management roguelite", 15)))
	var ver := _on_art(_label(tr("Test build %s · what's new is %s") % [tr(str(_version())), tr("below") if narrow else tr("on the right")], 12, true))
	left.add_child(ver)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	left.add_child(gap)

	var menu := _vbox(8)
	menu.custom_minimum_size.x = 300
	menu.add_child(_icon_domain_button("violet", "", "New Game", func():
		for i in GameState.SLOT_COUNT:
			if GameState.slot_summary(i).get("empty", true):
				_switch_slot(i)
				return
		screen = "load_game"
		render()
	))
	menu.add_child(_button("Load Game", func():
		screen = "load_game"
		render()
	))
	menu.add_child(_button("Credits", func():
		screen = "credits"
		render()
	))
	menu.add_child(_language_row())
	menu.add_child(_button("Feedback", func():
		_feedback_open = not _feedback_open
		render()
	))
	if OS.has_feature("web"):
		menu.add_child(_fullscreen_button())
	if not OS.has_feature("web"):
		menu.add_child(_button("Quit", func():
			get_tree().quit()
		))
	left.add_child(menu)
	if OS.has_feature("web_android") or OS.has_feature("web_ios"):
		var ph := _on_art(_wrap_label("This test build is made for a computer with a keyboard and mouse (or a gamepad). It runs on a phone, but small screens are cramped.", 12))
		ph.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		left.add_child(ph)
	if not narrow:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(spacer)
	var right: Control = _feedback_panel() if _feedback_open else _whats_new_card()
	right.custom_minimum_size.x = 0.0 if narrow else 420.0
	right.size_flags_vertical = Control.SIZE_SHRINK_END
	cols.add_child(right)
	if _navigated:
		# Coming to the title: the name fades up first, then the menu, then the card.
		var parts: Array[CanvasItem] = [title_lbl, menu, right]
		for i in parts.size():
			parts[i].modulate.a = 0.0
			var tw := parts[i].create_tween()
			tw.tween_interval(0.25 + 0.3 * i)
			tw.tween_property(parts[i], "modulate:a", 1.0, 0.6)


## The title art filling the window: its torches flicker, the portal in the
## arch breathes, stars twinkle past it and dust drifts in the torchlight;
## the left side darkens under the menu.
func _title_scene() -> void:
	var native := Vector2(380, 160)
	var win := get_viewport().get_visible_rect().size
	var r := _cover_rect(native)
	var s := r.size.x / native.x
	var at := func(p: Vector2) -> Vector2: return r.position + p * s
	_art_rect(GameData.TITLE_BG, r, _scene_art)
	_motes(_scene_art, Rect2(at.call(Vector2(150, 30)), Vector2(80, 45) * s), Color(1, 1, 1, 0.9), 12, Vector2.ZERO, 2.6, Vector2(3, 4))
	for p in [Vector2(102, 62), Vector2(278, 62)]:
		_glow(_scene_art, at.call(p), 34.0 * s, Color(1.0, 0.6, 0.25, 0.35), "flicker")
	_glow(_scene_art, at.call(Vector2(189, 100)), 24.0 * s, Color(0.8, 0.3, 1.0, 0.4), "pulse")
	_motes(_scene_art, Rect2(Vector2.ZERO, win), Color(1.0, 0.8, 0.55, 0.45), 36, Vector2(9, -6), 8.0, Vector2(2, 4))
	if not _narrow():
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(0.03, 0.02, 0.06, 0.85), Color(0.03, 0.02, 0.06, 0.0)])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 64
		gt.height = 4
		var shade := TextureRect.new()
		shade.texture = gt
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.size = Vector2(win.x * 0.5, win.y)
		_scene_art.add_child(shade)


## One button per language, each named in its own language (so it's found
## whichever one is showing); the current one is lit.
func _language_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for lang in GameData.LANGUAGES:
		var code := str(lang[0])
		var b := _button(str(lang[1]), func():
			GameState.language = code
			GameState.apply_language()
			GameState.save_settings()
			render())
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.toggle_mode = true
		b.button_pressed = GameState.language == code
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	return row


## The build's version, e.g. "0.9.0" (project setting application/config/version).
func _version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


## What changed in this test build, what to try, and where saves live.
func _whats_new_card() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"CardPanelViolet"
	var col := _vbox(4)
	var head := _label(tr("What's new in %s") % tr(str(_version())), 15)
	head.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	col.add_child(head)
	col.add_child(_wrap_label(tr(str(GameData.WHATS_NEW[0])), 12))   # the latest note only: a new player shouldn't open on a changelog
	if OS.has_feature("web"):
		col.add_child(_wrap_label("Your save lives in this browser. Clearing site data erases it, so back it up under Load Game > Backup now and then.", 12, true))
	p.add_child(col)
	return p


var _feedback_open := false
var _feedback_note := ""


## What a tester's report carries: the build, where they're playing, and how
## far along the guild is, then a few prompts to fill in.
func _feedback_report() -> String:
	var bits: Array[String] = [tr("Version %s (%s)") % [tr(str(_version())), tr(str("web" if OS.has_feature("web") else OS.get_name()))]]
	if GameState.guild_name != "":
		bits.append(tr("Day %d, Act %d, %d heroes, %d rifts sealed, best rank %s, Endless best %d:%02d, Tower floor %d") % [GameState.day, GameState.campaign_act, GameState.heroes.size(),
			GameState.rifts_sealed, GameData.RIFT_RANKS[clampi(GameState.best_rift_rank_sealed, 0, GameData.RIFT_RANKS.size() - 1)]["id"] if GameState.best_rift_rank_sealed >= 0 else "none",
			GameState.best_endless_time / 60, GameState.best_endless_time % 60, GameState.tower_best])
		bits.append_array(_session_lines())
	return "\n".join(bits) + tr("\n\nWhat happened:\n\nWhat you expected:\n\nAnything confusing, too hard or too easy:\n")


## How the guild has been played, for the Feedback report: time in the game,
## fights by hand and on Auto, recent runs by result, and what sits unspent.
func _session_lines() -> Array[String]:
	var s: Dictionary = GameState.session
	var secs := int(s.get("secs", 0.0))
	var out: Array[String] = [tr("Played %dh %02dm") % [secs / 3600, (secs % 3600) / 60]]
	out.append(tr("Fights: %d by hand (%d won), %d on Auto (%d won)") % [int(s.get("hand_w", 0)) + int(s.get("hand_l", 0)), int(s.get("hand_w", 0)), int(s.get("auto_w", 0)) + int(s.get("auto_l", 0)), int(s.get("auto_w", 0))])
	var runs := {}
	for r in GameState.run_history:
		var k := "%s %s" % [str(r["kind"]), str(r["result"]).to_lower()]
		runs[k] = int(runs.get(k, 0)) + 1
	if not runs.is_empty():
		out.append(tr("Last %d runs: %s") % [GameState.run_history.size(), ", ".join(runs.keys().map(func(k): return "%s x%d" % [k, runs[k]]))])
	var sp := 0
	var ap := 0
	for h in GameState.heroes:
		sp += h.skill_points
		ap += h.attr_points
	out.append(tr("Unspent: %d Gold, %d Essence, %d skill points, %d attribute points") % [GameState.coins, GameState.crystals, sp, ap])
	out.append(tr("Renown %d vs rival %d; heroes lost %d") % [GameState.reputation, GameState.rival_renown, GameState.heroes_lost_total])
	return out


## Copy the report, or copy it and open the playtest Discord.
func _feedback_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"CardPanelEmber"
	var col := _vbox(6)
	col.add_child(_label("Send feedback", 15))
	col.add_child(_wrap_label("Found a bug, or something felt off? Tell us on Discord. This report already says which build you're on and how far your guild is: copy it, then paste it into your message.", 12, true))
	var pre := _wrap_label(_feedback_report(), 12)
	pre.add_theme_color_override("font_color", Palette.MUTED)
	col.add_child(pre)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_button("Copy report", func():
		DisplayServer.clipboard_set(_feedback_report())
		_feedback_note = "Copied. Paste it into a message on the Discord."
		render()))
	row.add_child(_button("Copy and open Discord", func():
		DisplayServer.clipboard_set(_feedback_report())
		_feedback_note = "Copied. Paste it into a message on the Discord."
		OS.shell_open(GameData.FEEDBACK_DISCORD_URL)
		render()))
	col.add_child(row)
	if _feedback_note != "":
		var n := _label(_feedback_note, 12)
		n.add_theme_color_override("font_color", Palette.RANK_E)
		col.add_child(n)
	p.add_child(col)
	return p


## Web: fill the screen (a browser only allows it from a click).
func _fullscreen_button() -> Button:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	return _button(tr("Leave fullscreen") if full else tr("Fullscreen"), func():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		if not full and OS.has_feature("web"):
			# A phone that allows it (Android) stays on its side while fullscreen.
			JavaScriptBridge.eval("setTimeout(function(){ try { screen.orientation.lock('landscape').catch(function(){}); } catch (e) {} }, 400);", true)
		render.call_deferred())


func _render_load_game(v: VBoxContainer) -> void:
	v.add_child(_label("Load Game", 20))
	_render_slot_list(v)
	_render_save_backup(v)
	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back", func():
		screen = "title"
		render()
	))


func _render_credits(v: VBoxContainer) -> void:
	v.add_child(_label("Credits", 20))
	v.add_child(_label("Guildhold", 18))
	v.add_child(_wrap_label("A roguelite guild-management game — recruit heroes, evolve their subclasses, and send them through the Rifts.", 13, true))
	v.add_child(_hsep())
	v.add_child(_label(tr("Version %s") % tr(str(_version())), 13))
	v.add_child(_label("Built with Godot Engine 4.7", 13))
	v.add_child(_label("Pixel art generated with PixelLab", 13))
	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back", func():
		screen = "title"
		render()
	))


# ---------------- Onboard ----------------
const GUILD_NAME_A := ["Ashen", "Silver", "Iron", "Storm", "Ember", "Dawn", "Hollow", "Raven", "Gilded", "Last"]
const GUILD_NAME_B := ["Lantern", "Crows", "Wardens", "Blades", "Oath", "Company", "Watch", "Hearth", "Banner", "Vigil"]


func _render_onboard(v: VBoxContainer) -> void:
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	var slot_lbl := _label(tr("Save Slot %d") % (GameState.active_slot + 1), 12, true)
	slot_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(slot_lbl)
	top_row.add_child(_icon_button(GameData.CAMP_HUB_ICON_PATH["settings"], "Settings", func():
		_pre_settings_screen = "onboard"
		screen = "settings"
		render()
	))
	v.add_child(top_row)

	v.add_child(_label("Name Your Guild", 22))
	var edit := LineEdit.new()
	edit.placeholder_text = "Guild name"
	edit.text = pending_guild_name
	edit.text_changed.connect(func(t: String): pending_guild_name = t)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(edit)
	# A name without typing (a phone's keyboard can be awkward in a browser).
	name_row.add_child(_icon_button(GameData.BUTTON_ICON_PATH["dice"], "Random name", func():
		pending_guild_name = "The %s %s" % [GUILD_NAME_A[randi() % GUILD_NAME_A.size()], GUILD_NAME_B[randi() % GUILD_NAME_B.size()]]
		render()))
	v.add_child(name_row)

	v.add_child(_label("Choose a Crest", 16))
	var crest_row := HBoxContainer.new()
	crest_row.add_theme_constant_override("separation", 12)
	crest_row.add_child(_icon(GameData.CREST_PATH[pending_crest - 1], 64))
	crest_row.add_child(_icon_button(GameData.BUTTON_ICON_PATH["dice"], "Randomize", func():
		pending_crest = 1 + randi() % GameData.CREST_PATH.size()
		render()
	))
	v.add_child(crest_row)

	var found := _icon_domain_button("violet", GameData.BUTTON_ICON_PATH["confirm"], "Found the Guild", func():
		var n := edit.text.strip_edges()
		if n == "":
			# Say what's missing instead of doing nothing.
			edit.placeholder_text = tr("Name your guild first")
			edit.add_theme_color_override("font_placeholder_color", Palette.HAZARD)
			edit.grab_focus()
			return
		GameState.guild_name = n
		GameState.guild_crest = pending_crest
		GameState.hire_starters()
		GameState.refresh_recruit_pool()
		GameState.save()
		pending_guild_name = ""
		pending_crest = 1
		_flavor_toast = GameData.narrative_line("guild_founded")
		screen = "camp"
		render()
	)
	v.add_child(found)
	edit.text_submitted.connect(func(_t): found.pressed.emit())   # Enter founds it too


# ---------------- Rift Hall ----------------
## Lesser and Endless Rift are each a gate on the rift chamber's background
## art, clickable straight into Party Assembly — no intermediate detail view
## since there's nothing else to decide here, unlike Guild Management/
## Inventory's hubs. The chained third gateway in the art gets a hotspot too
## once GameState.greater_rift_unlocked() — inert (no hotspot at all) before that.
## The current act: its foe, objectives with progress, and the finale — open
## once every objective is met.
func _render_campaign_panel(v: Container) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanelEmber"
	var cv := _vbox(6)
	if GameState.campaign_done():
		cv.add_child(_label("The campaign is complete", 16))
		cv.add_child(_wrap_label("The Ashen Crown is shattered. Rifts still open — push the Endless Rift, climb the rift ladder to SSS, and take on quests.", 12, true))
		panel.add_child(cv)
		v.add_child(panel)
		return
	var act := GameState.current_act()
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var foe_icon := _icon(GameData.sprite_for_monster(str(act["boss"])), 44)
	head.add_child(foe_icon)
	var hv := _vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := _label(tr("Act %s — %s") % [tr(str(GameState._roman(int(act["act"])))), tr(str(act["name"]))], 17)
	t.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	hv.add_child(t)
	hv.add_child(_label(tr("Foe: %s") % tr(str(act["foe"])), 12, true))
	head.add_child(hv)
	cv.add_child(head)
	for o in act["objectives"]:
		var met := GameState.campaign_objective_met(o)
		var prog := "" if str(o["type"]) == "map_rank" else " (%d/%d)" % [min(GameState.campaign_objective_progress(o), int(o["target"])), int(o["target"])]
		var ol := _label("%s %s%s" % [tr(str("✓" if met else "○")), tr(str(o["label"])), tr(str(prog))], 13)
		ol.add_theme_color_override("font_color", Palette.RANK_E if met else Palette.TEXT)
		cv.add_child(ol)
	var ready := GameState.finale_ready()
	var fb := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], tr("Face the finale: %s") % tr(str(act["finale"])), func():
		pending_party.clear()
		screen = "party_assembly"
		_pending_diff_id = str(act["tier"])
		_pending_rift_rank = ""
		_pending_endless = false
		_pending_finale = true
		render()
	)
	fb.disabled = not ready
	fb.tooltip_text = tr("Recommended power %d") % GameState.finale_recommended_power() if ready else tr("Complete every objective above first")
	fb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cv.add_child(fb)
	panel.add_child(cv)
	v.add_child(panel)


func _render_rift_hall(v: VBoxContainer) -> void:
	var wide := _bleed_ui()
	if not wide:
		v.add_child(_label("Rift Hall", 20))
	if not GameState.heroes.is_empty():
		var f := GameState.payday_forecast()
		var msg := tr("Payday in %d day%s: %d Gold due, you have %d — ") % [int(f["days"]), tr(str(_pl(int(f["days"])))), int(f["bill"]), int(f["have"])]
		if int(f["short"]) == 0:
			msg += tr("covered.")
		elif int(f["runs"]) > 0:
			msg += tr("short %d; about %d rift%s at your recent pay (%d each) covers it.") % [int(f["short"]), int(f["runs"]), tr(str(_pl(int(f["runs"])))), int(f["per_run"])]
		else:
			msg += tr("short %d.") % int(f["short"])
		var pay_col: Color = Palette.COINS if int(f["short"]) == 0 else Palette.HAZARD
		if wide:
			# On the hall's stone it needs a dark backing to read.
			var chip := _rule_chip(msg, "", pay_col)
			(chip.get_child(0) as Label).add_theme_color_override("font_color", pay_col)
			chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			v.add_child(chip)
		else:
			var fl := _wrap_label(msg, 12)
			fl.add_theme_color_override("font_color", pay_col)
			v.add_child(fl)
	if GameState.breach_active():
		v.add_child(_breach_card())
	_coach(v, "rift_hall", "Choosing a rift", "Rifts come in ranks, F to SSS. Seal a rank to open the next. The readout compares your best party's power with what the rift expects — Deadly, Risky, Even or Favored. Your very first rift is a shorter training run.")
	if _ladder_pick == "" or GameState.ladder_rank_lock(_ladder_pick) != "":
		_ladder_pick = GameState.highest_open_rank()

	var unlocked := GameState.greater_rift_unlocked()
	var go := func(rank_id: String, endless: bool):
		pending_party.clear()
		pending_relic_options.clear()
		pending_relic_choice = -1
		_pending_tower = false
		_pending_daily = not endless and _ladder_twist and GameState.daily_available()
		screen = "party_assembly"
		_pending_rift_rank = rank_id
		_pending_diff_id = "endless" if endless else str(GameData.find_rift_rank(rank_id)["base"])
		_pending_endless = endless
		_pending_finale = false
		render()
	# The two rift gates in the art: the Lesser ranks (F-D) on the left, the
	# Greater ranks (C-SSS) on the chained archway once Act II opens them.
	var best_of := func(base: String) -> String:
		var out := ""
		for r in GameData.RIFT_RANKS:
			if str(r["base"]) == base and GameState.ladder_rank_lock(str(r["id"])) == "":
				out = str(r["id"])
		return out
	var lesser_pick: String = _ladder_pick if str(GameData.find_rift_rank(_ladder_pick)["base"]) == "lesser" else best_of.call("lesser")
	var endless_open := GameState.endless_unlocked()
	var greater_pick: String = _ladder_pick if str(GameData.find_rift_rank(_ladder_pick)["base"]) == "greater" else best_of.call("greater")
	var greater_open: bool = unlocked and greater_pick != ""
	# Each gate: [its name, its area on the old 700x340 stage, the gate in the
	# 320x200 art, where it leads (an empty Callable while it's locked)].
	var gates := [
		[tr("Rank %s Rift") % tr(str(lesser_pick)), Rect2(0, 0, 230, 340), Rect2(18, 65, 68, 98), go.bind(lesser_pick, false)],
		["Endless Rift" if endless_open else tr("Endless Rift — locked"), Rect2(230, 0, 240, 340), Rect2(110, 20, 97, 130),
			go.bind("", true) if endless_open else Callable()],
		[tr("Rank %s Rift") % tr(str(greater_pick)) if greater_open else (tr("Ranks C-SSS — locked") if not unlocked else tr("Rank C — %s") % tr(str(GameState.ladder_rank_lock("C")))),
			Rect2(470, 0, 230, 340), Rect2(230, 30, 78, 140), go.bind(greater_pick, false) if greater_open else Callable()],
	]
	var best := _best_party_power()
	if wide:
		_rift_hall_wide(v, gates, best, go)
		return
	if _compact():
		# The phone canvas: no gate art to scroll past; the act and the ladder side by side, the other modes under them.
		var cols := HBoxContainer.new()
		cols.add_theme_constant_override("separation", 8)
		_render_campaign_panel(cols)
		(cols.get_child(cols.get_child_count() - 1) as Control).custom_minimum_size.x = 250
		var ladder := _ladder_card(best, go)
		ladder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(ladder)
		v.add_child(cols)
		v.add_child(_rift_mode_rows(best, go))
		return

	var scene := Control.new()
	scene.custom_minimum_size = HUB_SCENE
	scene.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bg := TextureRect.new()
	bg.texture = load(GameData.RIFTHALL_BG)
	bg.custom_minimum_size = HUB_SCENE
	bg.size = HUB_SCENE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)
	for g in gates:
		var area := _hub_rect(g[1])
		var cb: Callable = g[3]
		if cb.is_valid():
			var native_rect: Rect2 = g[2]
			var hotspot := _camp_area_hotspot(area, Rect2(native_rect.position * HUB_ART_SCALE, native_rect.size * HUB_ART_SCALE), str(g[0]), cb)
			hotspot.position = area.position
			scene.add_child(hotspot)
		else:
			var lock_plaque := _camp_plaque(str(g[0]))
			lock_plaque.position = Vector2(area.position.x + (area.size.x - lock_plaque.size.x) * 0.5, area.end.y - lock_plaque.size.y - 6)
			scene.add_child(lock_plaque)
	v.add_child(scene)
	_render_campaign_panel(v)
	v.add_child(_ladder_card(best, go))
	v.add_child(_rift_mode_cards(best, go))


## Height of the Rift Hall's bottom row of cards on a landscape window.
const RIFT_DOCK_H := 236.0
## The hall's floor, continued below the art on a tall window.
const RIFTHALL_FLOOR := Color(0.34, 0.32, 0.26)


## The Rift Hall on a landscape window: the hall fills it (torches flicker,
## the portal breathes and sheds motes), its gates are the way in, and the
## campaign, the rift ladder and the other modes sit along the bottom.
func _rift_hall_wide(v: VBoxContainer, gates: Array, best: int, go: Callable) -> void:
	var native := Vector2(320, 200)
	var win := get_viewport().get_visible_rect().size
	# Always the hall's full width: the side gates are the way in, so they
	# must never be cropped. A window taller than the art (a square browser
	# window) carries the floor on below it, where the cards sit anyway.
	var s := win.x / native.x
	var h := roundf(native.y * s)
	var r := Rect2(Vector2(0.0, minf(0.0, roundf((win.y - h) * 0.3))), Vector2(win.x, h))
	var at := func(p: Vector2) -> Vector2: return r.position + p * s
	if r.end.y < win.y:
		var fg := Gradient.new()
		fg.colors = PackedColorArray([RIFTHALL_FLOOR, RIFTHALL_FLOOR.darkened(0.6)])
		var ft := GradientTexture2D.new()
		ft.gradient = fg
		ft.fill_from = Vector2(0.5, 0.0)
		ft.fill_to = Vector2(0.5, 1.0)
		ft.width = 4
		ft.height = 64
		var floor_fill := TextureRect.new()
		floor_fill.texture = ft
		floor_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		floor_fill.stretch_mode = TextureRect.STRETCH_SCALE
		floor_fill.position = Vector2(0.0, r.end.y - 2.0)
		floor_fill.size = Vector2(win.x, win.y - r.end.y + 2.0)
		floor_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scene_art.add_child(floor_fill)
	_art_rect(GameData.RIFTHALL_BG, r, _scene_art)
	for p in [Vector2(13, 70), Vector2(100, 78), Vector2(219, 77), Vector2(308, 70)]:
		_glow(_scene_art, at.call(p), 18.0 * s, Color(1.0, 0.6, 0.25, 0.4), "flicker")
	_glow(_scene_art, at.call(Vector2(160, 88)), 58.0 * s, Color(0.6, 0.3, 1.0, 0.3), "pulse")
	_glow(_scene_art, at.call(Vector2(52, 118)), 26.0 * s, Color(0.3, 0.8, 1.0, 0.22), "pulse")
	_motes(_scene_art, Rect2(at.call(Vector2(125, 50)), Vector2(70, 95) * s), Color(0.8, 0.6, 1.0, 0.8), 26, Vector2(0, -16), 3.5, Vector2(2, 4), 25.0)
	_motes(_scene_art, Rect2(at.call(Vector2(0, 140)), Vector2(320, 60) * s), Color(1.0, 0.8, 0.6, 0.35), 18, Vector2(6, -3), 8.0, Vector2(2, 3))
	# Name plaques stand at each gate's foot, or just above the cards.
	var plaque_floor := win.y - 20.0 - RIFT_DOCK_H - 10.0
	for g in gates:
		var nr: Rect2 = g[2]
		var gr := Rect2(at.call(nr.position), nr.size * s)
		var cb: Callable = g[3]
		if cb.is_valid():
			var hotspot := _camp_area_hotspot(gr, gr, str(g[0]), cb, false)
			hotspot.position = gr.position
			_scene_ui.add_child(hotspot)
		var plaque := _camp_plaque(str(g[0]))
		plaque.position = Vector2(roundf(gr.get_center().x - plaque.size.x * 0.5), roundf(minf(gr.end.y, plaque_floor) - plaque.size.y - 4.0))
		_scene_ui.add_child(plaque)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(spacer)
	var dock := ScrollContainer.new()
	dock.custom_minimum_size.y = RIFT_DOCK_H
	dock.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_render_campaign_panel(row)
	(row.get_child(row.get_child_count() - 1) as Control).custom_minimum_size.x = 280
	var ladder := _ladder_card(best, go)
	ladder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ladder)
	var modes := _rift_mode_rows(best, go)
	modes.custom_minimum_size.x = 330
	row.add_child(modes)
	dock.add_child(row)
	v.add_child(dock)


## The modes besides the ladder: [name, what it is, recommended power,
## where it leads, why it's locked ("" when open), button text].
func _rift_mode_defs(go: Callable) -> Array:
	return [
		["Endless Rift", tr("Steer your party through endless waves · best %d:%02d") % [GameState.best_endless_time / 60, GameState.best_endless_time % 60], Combat.recommended_power("endless"), go.bind("", true),
			"" if GameState.endless_unlocked() else tr("Opens when you complete Act II"), "Assemble party"],
		["Tower of Trials", tr("100 fixed floors · best floor %d") % GameState.tower_best, GameState.tower_recommended_power(maxi(1, GameState.tower_next_floor())),
			func(): screen = "tower"; render(), "" if GameState.feature_unlocked("tower") else tr("Opens when you complete Act I"), "Enter the Tower"],
	]


## The other modes as cards: what each is, how your strongest party measures
## up, and the button to go.
func _rift_mode_cards(best: int, go: Callable) -> HFlowContainer:
	var cards := HFlowContainer.new()
	cards.alignment = FlowContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("h_separation", 10)
	cards.add_theme_constant_override("v_separation", 10)
	for cd in _rift_mode_defs(go):
		var card := PanelContainer.new()
		card.custom_minimum_size.x = 270
		var cv := _vbox(6)
		cv.add_child(_label(str(cd[0]), 16))
		cv.add_child(_label(str(cd[1]), 12, true))
		if str(cd[4]) != "":
			cv.add_child(_wrap_label(str(cd[4]), 12, true))
			card.modulate = Color(1, 1, 1, 0.6)
		else:
			var pr := _power_readout(best, int(cd[2]), "Your best party")
			pr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cv.add_child(pr)
			var b := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], str(cd[5]), cd[3])
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			cv.add_child(b)
		card.add_child(cv)
		cards.add_child(card)
	return cards


## The other modes as compact rows, for the Rift Hall's bottom row of cards.
func _rift_mode_rows(best: int, go: Callable) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"CardPanelViolet"
	var col := _vbox(8)
	for cd in _rift_mode_defs(go):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var tv := _vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Two short lines each (what it is is the name's tooltip) so all three fit.
		var name_l := _label(str(cd[0]), 15)
		name_l.tooltip_text = str(cd[1])
		name_l.mouse_filter = Control.MOUSE_FILTER_STOP
		tv.add_child(name_l)
		var locked := str(cd[4]) != ""
		if locked:
			var why := _label(str(cd[4]), 12, true)
			why.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			why.clip_text = true
			why.tooltip_text = why.text
			why.mouse_filter = Control.MOUSE_FILTER_STOP
			tv.add_child(why)
		else:
			tv.add_child(_power_readout(best, int(cd[2]), "Your best"))
		row.add_child(tv)
		if locked:
			row.modulate = Color(1, 1, 1, 0.6)
		else:
			var b := _button("Go", cd[3])
			b.tooltip_text = str(cd[5])
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(b)
		col.add_child(row)
	p.add_child(col)
	return p


## The rift ladder: one button per rank (locked ones say why), and the picked
## rank's floors, foes, rewards, extra rules and power readout.
func _ladder_card(best: int, go: Callable) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelEmber"
	var cv := _vbox(8)
	cv.add_child(_label("Rift Ladder", 17))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	var next_locked := ""
	for r in GameData.RIFT_RANKS:
		var rid := str(r["id"])
		var lock := GameState.ladder_rank_lock(rid)
		if lock != "" and next_locked == "":
			next_locked = tr("Next: Rank %s — %s") % [tr(str(rid)), tr(str(lock))]
		var b := _button(rid, func(): _ladder_pick = rid; render())
		b.custom_minimum_size = Vector2(46, 40)
		b.toggle_mode = true
		b.button_pressed = rid == _ladder_pick
		b.add_theme_color_override("font_color", Palette.rank_color(rid))
		if lock != "":
			# Still in its rank's colour, just softer, so the whole ladder
			# ahead reads at a glance.
			b.disabled = true
			b.add_theme_color_override("font_disabled_color", Color(Palette.rank_color(rid), 0.6))
			b.tooltip_text = tr("Rank %s — %s") % [tr(str(rid)), tr(str(lock))]
		elif GameState.best_rift_rank_sealed >= GameData.rift_rank_index(rid):
			b.tooltip_text = tr("Rank %s — sealed") % tr(str(rid))
		row.add_child(b)
	cv.add_child(row)
	var rank: Dictionary = GameData.find_rift_rank(_ladder_pick)
	var base: Dictionary = GameData.DIFFICULTIES[0]
	for d in GameData.DIFFICULTIES:
		if d["id"] == rank["base"]:
			base = d
	var rules: Array[String] = []
	for k in GameData.RIFT_RANK_RULE_TEXT:
		if rank.get(k, false):
			rules.append(tr(str(GameData.RIFT_RANK_RULE_TEXT[k])))
	var t := _label(tr("Rank %s · %d floors") % [tr(str(_ladder_pick)), int(base["floors"])], 15)
	t.add_theme_color_override("font_color", Palette.rank_color(_ladder_pick))
	var go_row := HBoxContainer.new()
	go_row.add_theme_constant_override("separation", 10)
	var pick_col := _vbox(2)
	pick_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick_col.add_child(t)
	var pr := _power_readout(best, Combat.recommended_power("", _ladder_pick), "Your best party")
	pr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pick_col.add_child(pr)
	go_row.add_child(pick_col)
	var b := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], "Assemble party", go.bind(_ladder_pick, false))
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go_row.add_child(b)
	cv.add_child(go_row)
	var foes := tr("Foes: base") if float(rank["hp"]) == 1.0 else tr("Foes: ×%s health, ×%s damage") % [tr(str(rank["hp"])), tr(str(rank["dmg"]))]
	cv.add_child(_wrap_label(tr("%s%s · Rewards ×%s%s") % [tr(str(base["name"])) + " · ", tr(str(foes)), tr(str(rank["reward"])), tr(str((" · " + ", ".join(rules)) if not rules.is_empty() else ""))], 12, true))
	if GameState.rifts_sealed >= 1:
		cv.add_child(_daily_twist_row())
	if next_locked != "":
		cv.add_child(_label(next_locked, 12, true))
	card.add_child(cv)
	return card


# ---------------- Tower of Trials ----------------
## The next floor (its fight, rules, reward and the party's odds), the climb
## around it, and the ten guardians with their relics.
func _render_tower(v: VBoxContainer) -> void:
	v.add_child(_label("Tower of Trials", 20))
	var title := GameState.tower_title()
	v.add_child(_label(tr("Best floor %d / %d%s") % [GameState.tower_best, GameData.TOWER_FLOORS, ("  ·  " + tr(title)) if title != "" else ""], 13, true))
	_coach(v, "tower", "The Tower", "Every floor is always the same fight — if you lose, study it, change your party and come back. Heroes fight at full HP and leave exactly as they came, so a loss costs nothing. Each floor pays the first time you clear it; every 10th floor is a guardian with its own relic.")
	var f := GameState.tower_next_floor()
	if f == 0:
		var days_left := 7 - int(fmod(Time.get_unix_time_from_system(), 604800.0) / 86400.0)
		var done := _wrap_label(tr("You've cleared this week's ladder. Floors %d–%d reshuffle their rules in %d day%s.") % [GameData.TOWER_WEEKLY_FROM, GameData.TOWER_FLOORS, days_left, tr(str(_pl(days_left)))], 14)
		done.add_theme_color_override("font_color", Palette.RANK_E)
		v.add_child(done)
	else:
		v.add_child(_tower_floor_card(GameState.tower_floor_info(f)))
		v.add_child(_tower_strip(f))
	v.add_child(_hsep())
	v.add_child(_label("Guardians", 16))
	for gf in GameData.TOWER_BOSSES:
		var boss: Dictionary = GameData.TOWER_BOSSES[gf]
		var rdef: Dictionary = GameData.TOWER_RELICS[gf]
		var done_g := GameState.tower_best >= int(gf)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var ic := _icon(GameData.sprite_for_monster(str(boss["name"])), 32)
		if not done_g:
			ic.modulate = Color(1, 1, 1, 0.45)
		row.add_child(ic)
		var fl := _label(tr("Floor %d") % int(gf), 13, true)
		fl.custom_minimum_size.x = 64
		row.add_child(fl)
		var nm := _label(str(boss["name"]), 13)
		nm.custom_minimum_size.x = 170
		row.add_child(nm)
		var rl := _label(("✓ " if done_g else "") + tr(str(rdef["name"])), 13)
		rl.add_theme_color_override("font_color", Palette.RANK_E if done_g else Palette.RANK_S)
		rl.tooltip_text = str(rdef["desc"])
		rl.mouse_filter = Control.MOUSE_FILTER_STOP
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(rl)
		v.add_child(row)
	var titles := GameData.TOWER_TITLES.map(func(e): return ("✓ " if GameState.tower_best >= int(e[0]) else "") + tr("%s (floor %d)") % [tr(str(e[1])), int(e[0])])
	v.add_child(_wrap_label(tr("Titles: ") + ", ".join(titles), 12, true))


func _tower_floor_card(info: Dictionary) -> Control:
	var f := int(info["floor"])
	var boss: Dictionary = info["boss"]
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanelEmber" if not boss.is_empty() else &"CardPanelViolet"
	var cv := _vbox(6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	if not boss.is_empty():
		head.add_child(_icon(GameData.sprite_for_monster(str(boss["name"])), 48))
	var hv := _vbox(2)
	var t := _label(tr("Floor %d") % f, 22)
	t.add_theme_font_override("font", DISPLAY_FONT)
	t.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if not boss.is_empty() else Palette.TEXT)
	hv.add_child(t)
	var kind_name: String = {"boss": tr("Guardian: ") + str(boss.get("name", "")), "elite": "Elite fight", "combat": "Fight"}[str(info["kind"])]
	hv.add_child(_label("%s  ·  %s%s" % [tr(str(kind_name)), tr(str(GameData.BIOMES[str(info["biome"])]["name"])), tr(str(tr("  ·  weekly ladder") if info["weekly"] else ""))], 12, true))
	head.add_child(hv)
	cv.add_child(head)
	if not boss.is_empty():
		cv.add_child(_wrap_label(str(boss["line"]), 12, true))
		for mid in boss["mechanics"]:
			var bm: Dictionary = GameData.BOSS_MECHANICS.filter(func(x): return x["id"] == mid)[0]
			cv.add_child(_wrap_label("%s — %s" % [tr(str(bm["name"])), tr(str(bm["desc"]))], 13))
	for r in info["rules"]:
		var rl := _wrap_label(tr("Rule · %s — %s") % [tr(str(r["name"])), tr(str(r["desc"]))], 13)
		rl.add_theme_color_override("font_color", Palette.HAZARD)
		cv.add_child(rl)
	if info["rules"].is_empty() and boss.is_empty():
		cv.add_child(_label("No special rules on this floor.", 12, true))
	var cap := int(info["party_cap"])
	var pr := _power_readout(_best_party_power(cap), GameState.tower_recommended_power(f), "Your best party")
	pr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(pr)
	cv.add_child(_tower_reward_line(info))
	var b := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], tr("Assemble party (up to %d)") % cap, func():
		pending_party.clear()
		_pending_tower = true
		screen = "party_assembly"
		render()
	)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cv.add_child(b)
	panel.add_child(cv)
	return panel


func _tower_reward_line(info: Dictionary) -> Control:
	var f := int(info["floor"])
	var rw: Dictionary = info["reward"]
	var first := f > GameState.tower_best
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label(tr("First clear:") if first else tr("This week's re-clear:"), 13))
	row.add_child(_icon(GameData.CURRENCY_ICON_PATH["coins"], 16))
	row.add_child(_label("+%d" % (int(rw["coins"]) if first else int(rw["coins"]) / 2), 13))
	row.add_child(_icon(GameData.CURRENCY_ICON_PATH["crystals"], 16))
	row.add_child(_label("+%d" % (int(rw["crystals"]) if first else int(rw["crystals"]) / 2), 13))
	var rdef: Dictionary = rw["relic"]
	if first and not rdef.is_empty():
		var rl := _label("+ %s" % tr(str(rdef["name"])), 13)
		rl.add_theme_color_override("font_color", Palette.RANK_S)
		rl.tooltip_text = str(rdef["desc"])
		rl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(rl)
	return row


## A strip of floor chips around the next one: cleared, next, and a few ahead
## (guardians in ember, rules in the tooltip).
func _tower_strip(next_f: int) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for f in range(maxi(1, next_f - 3), mini(GameData.TOWER_FLOORS, next_f + 8) + 1):
		var info := GameState.tower_floor_info(f)
		var chip := PanelContainer.new()
		var st := StyleBoxFlat.new()
		var guardian: bool = not (info["boss"] as Dictionary).is_empty()
		st.bg_color = Palette.SURFACE3 if f == next_f else Palette.SURFACE2
		st.border_color = Palette.EMBER_BRIGHT if f == next_f else (Palette.EMBER if guardian else Palette.LINE)
		st.set_border_width_all(2 if f == next_f or guardian else 1)
		st.set_corner_radius_all(6)
		st.set_content_margin_all(6)
		chip.add_theme_stylebox_override("panel", st)
		chip.custom_minimum_size = Vector2(52, 44)
		var cleared := f < next_f
		var l := _label(("✓ " if cleared else "") + str(f), 14, cleared)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_child(l)
		var tip := tr("Floor %d — %s") % [f, tr(str(info["boss"]["name"]) if guardian else (tr("Elite fight") if info["kind"] == "elite" else tr("Fight")))]
		for r in info["rules"]:
			tip += "\n%s: %s" % [tr(str(r["name"])), tr(str(r["desc"]))]
		chip.tooltip_text = tip
		flow.add_child(chip)
	return flow


## The ladder's daily twist: a box to take today's rule and starting boon
## on the next ladder rift, or where the streak stands once it's done.
func _daily_twist_row() -> Control:
	var info := GameState.daily_info()
	var boon: Dictionary = GameData.find_boon(str(info["boon"]))
	var bonus := GameData.DAILY_CLEAR_CRYSTALS + GameData.DAILY_CLEAR_CRYSTALS_PER_ACT * mini(GameState.campaign_act, 3)
	var streak := (tr(" · streak %d") % GameState.daily_streak) if GameState.daily_streak > 0 else ""
	if not GameState.daily_available():
		return _label(tr("Today's twist is done%s. A new one tomorrow.") % streak, 12, true)
	var cb := CheckBox.new()
	cb.text = tr("Today's twist: %s, start with %s · +%d Essence%s") % [tr(str(info["rule"]["name"])), tr(str(boon["name"])), bonus, streak]
	cb.button_pressed = _ladder_twist
	cb.add_theme_font_size_override("font_size", ui_size(12))
	cb.add_theme_color_override("font_color", Palette.RANK_S)
	cb.add_theme_color_override("font_pressed_color", Palette.RANK_S)
	cb.tooltip_text = tr("Rule: %s\nStarting boon: %s (%s)\nOne try a day, any rank. Every guild faces the same twist today; seal it for +%d Essence and a longer streak.") % [tr(str(info["rule"]["desc"])), tr(str(boon["name"])), tr(str(boon["desc"])), bonus]
	cb.toggled.connect(func(on: bool): _ladder_twist = on)
	return cb


# ---------------- Party Assembly ----------------
func _render_party_assembly(v: VBoxContainer) -> void:
	if GameState.breach_blocks_runs():
		screen = "defense"   # a broken rift comes first
		_render_defense_setup(v)
		return
	if _pending_endless and _pending_rift_rank == "":
		_render_endless_assembly(v)
		return
	var tower_info := GameState.tower_floor_info(GameState.tower_next_floor()) if _pending_tower else {}
	if _pending_daily:
		var dinfo := GameState.daily_info()
		v.add_child(_label(tr("Rank %s Rift — today's twist: %s") % [tr(str(_pending_rift_rank)), tr(str(dinfo["rule"]["name"]))], 20))
		v.add_child(_wrap_label(tr("Rule: %s Starting boon: %s (%s). Sealing it pays +%d Essence. Up to 4 heroes.") % [tr(str(dinfo["rule"]["desc"])), tr(str(GameData.find_boon(str(dinfo["boon"]))["name"])), tr(str(GameData.find_boon(str(dinfo["boon"]))["desc"])), GameData.DAILY_CLEAR_CRYSTALS + GameData.DAILY_CLEAR_CRYSTALS_PER_ACT * mini(GameState.campaign_act, 3)], 12, true))
	elif _pending_tower:
		v.add_child(_label(tr("Tower of Trials — Floor %d") % int(tower_info["floor"]), 20))
		var rules: Array = tower_info["rules"]
		v.add_child(_wrap_label(tr("Up to %d heroes. Everyone fights at full HP and leaves as they came.%s") % [_party_cap(), tr(str((tr(" Rules: ") + ", ".join(rules.map(func(r): return "%s (%s)" % [tr(str(r["name"])), tr(str(r["desc"]))]))) if not rules.is_empty() else ""))], 12, true))
	elif _pending_finale and not GameState.current_act().is_empty():
		v.add_child(_label(tr("Finale — %s") % tr(str(GameState.current_act()["finale"])), 20))
		v.add_child(_wrap_label(tr("A harder %s Rift that ends in %s. Up to 4 heroes.") % [tr(str(GameState.current_act()["tier"]).capitalize()), tr(str(GameState.current_act()["boss"]))], 12, true))
	else:
		v.add_child(_label("Assemble Party (up to 4)", 20))
	_coach(v, "party", "Pick your party", "Add heroes, then Enter the Rift. The front row takes most of the hits; the back row is attacked far less.")
	# Formation slots (Darkest Dungeon style): the party sits in a Front and a
	# Back row. Drag a portrait into a row (from the roster below, or between
	# rows), or use Add/Move/Remove. The front row draws ~3x the attacks; each
	# role has a natural row with its own bonus (GameData.ROLE_POSITION).
	var lineup: Array[Hero] = []
	for hid in pending_party:
		var ph := GameState.find_hero(hid)
		if ph:
			lineup.append(ph)
	for row_id in ["front", "back"]:
		var zone := DropZone.new()
		var zone_style := StyleBoxFlat.new()
		zone_style.bg_color = Palette.SURFACE2
		zone_style.border_color = Palette.EMBER if row_id == "front" else Palette.VIOLET
		zone_style.set_border_width_all(1)
		zone_style.set_corner_radius_all(8)
		zone_style.set_content_margin_all(8)
		zone.add_theme_stylebox_override("panel", zone_style)
		zone.can_accept = func(data) -> bool:
			if typeof(data) != TYPE_DICTIONARY or data.get("kind", "") != "party_hero":
				return false
			var hid2: String = str(data.get("hero_id", ""))
			return pending_party.has(hid2) or pending_party.size() < _party_cap()
		zone.on_drop = func(data, r=row_id) -> void:
			var hid2: String = str(data.get("hero_id", ""))
			if not pending_party.has(hid2):
				pending_party.append(hid2)
			GameState.set_hero_formation(hid2, r)
			render()
		var zv := _vbox(6)
		zv.mouse_filter = Control.MOUSE_FILTER_PASS
		var in_row: Array = lineup.filter(func(x): return x.formation == row_id)
		zv.add_child(_label(tr("%s row (%d) — %s") % [tr(row_id).capitalize(), in_row.size(),
			tr("takes most of the enemy's attacks") if row_id == "front" else tr("attacked far less often")], 13))
		var cards := HFlowContainer.new()
		cards.add_theme_constant_override("h_separation", 8)
		cards.add_theme_constant_override("v_separation", 8)
		cards.mouse_filter = Control.MOUSE_FILTER_PASS
		for ph in in_row:
			cards.add_child(_party_card(ph, ph.is_champion, true))
		if in_row.is_empty():
			cards.add_child(_label("Drag a hero here", 11, true))
		zv.add_child(cards)
		zone.add_child(zv)
		v.add_child(zone)

	var bench: Array = GameState.heroes.filter(func(x): return not pending_party.has(x.id))
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes yet — recruit some under Roster > Recruits first."))
	elif not bench.is_empty():
		var bench_head := HBoxContainer.new()
		bench_head.add_theme_constant_override("separation", 10)
		var bl := _label("Roster — drag into a row, or Add (joins their natural row)", 12, true)
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bench_head.add_child(bl)
		# One click to a full party: the strongest ready heroes, each in their natural row.
		var ready: Array = bench.filter(func(x): return not x.is_champion and not x.is_downed() and x.busy_runs <= 0)
		ready.sort_custom(func(a, b): return Combat.power_of(a) > Combat.power_of(b))
		var fill := _button("Add strongest", func():
			for x in ready:
				if pending_party.size() >= _party_cap():
					break
				pending_party.append(x.id)
				GameState.set_hero_formation(x.id, str(GameData.ROLE_POSITION.get(GameData.hero_role(x), {}).get("row", x.formation)))
			render())
		fill.tooltip_text = tr("Fill the party with your strongest ready heroes, each in their natural row.")
		fill.disabled = ready.is_empty() or pending_party.size() >= _party_cap()
		bench_head.add_child(fill)
		v.add_child(bench_head)
		var bench_flow := HFlowContainer.new()
		bench_flow.add_theme_constant_override("h_separation", 8)
		bench_flow.add_theme_constant_override("v_separation", 8)
		for bh in bench:
			bench_flow.add_child(_party_card(bh, bh.is_champion, false))
		v.add_child(bench_flow)

	if not GameState.champions.is_empty():
		v.add_child(_hsep())
		_coach(v, "overseer", "Your overseer", "A champion never fights in a rift run. They oversee it: their Boon lifts the whole party, and any hero can spend a turn on their Call. (In the Endless Rift champions are the party; in a defense you steer one.)")
		v.add_child(_overseer_picker())
	v.add_child(_hsep())
	var choice_count := 0 if _pending_tower else GameState.relic_choice_count()
	if choice_count > 0:
		v.add_child(_label("Starting Relic (pick one, optional)"))
		if pending_relic_options.is_empty():
			# S-rank+ mapped rifts carry a "relic_rarity_floor_down" modifier —
			# it suppresses Guild Management's inherited_power() floor-raise
			# (which normally bumps a rolled Common up to Rare) for this
			# starting-relic roll specifically, so an S+ rift's starting pick
			# can't lean on that safety net the way a normal run's can.
			var floor_suppressed: bool = _pending_rift_rank != "" and bool(GameData.find_rift_rank(_pending_rift_rank).get("relic_rarity_floor_down", false))
			for i in choice_count:
				var rarity := "rare" if (GameState.inherited_power() and not floor_suppressed and Combat.weighted_rarity() == "common") else Combat.weighted_rarity()
				pending_relic_options.append(Combat.gen_relic(rarity))
	for i in pending_relic_options.size():
		var r: Relic = pending_relic_options[i]
		var rb := CheckButton.new()
		rb.button_pressed = pending_relic_choice == i
		rb.toggled.connect(func(on: bool):
			pending_relic_choice = i if on else -1
			render()
		)
		v.add_child(_info_row("%s (%s) — %s" % [tr(str(r.name)), tr(str(r.type)), tr(str(r.desc()))], 14, [], rb))


	var launch := _party_launch_bar()
	v.add_child(launch)
	v.move_child(launch, 1)


## Who oversees this run: a champion's Boon for the whole party and their
## Call (any hero can spend a turn on it), or none.
func _overseer_picker() -> Control:
	var box := _vbox(6)
	var cur := GameState.overseer
	box.add_child(_label(tr("Overseer: %s") % (GameData.champion_full_name(cur) if cur != "" else tr("none")), 14))
	if cur != "":
		var call := GameState.champion_call_of(cur)
		box.add_child(_wrap_label(tr("Boon: %s  ·  Call: %s — %s") % [GameState.champion_boon_text(cur), tr(str(call["name"])), tr(str(call["desc"]))], 12, true))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	row.add_theme_constant_override("v_separation", 6)
	for id in GameState.champion_roll:
		if not GameState.champion_unlocked(id):
			continue
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = id == cur
		b.text = str(GameData.champion_def(id)["name"])
		b.tooltip_text = GameState.champion_boon_text(id)
		b.pressed.connect(func(i=id): GameState.set_overseer(i); render())
		row.add_child(b)
	var none := Button.new()
	none.toggle_mode = true
	none.button_pressed = cur == ""
	none.text = tr("None")
	none.pressed.connect(func(): GameState.set_overseer(""); render())
	row.add_child(none)
	box.add_child(row)
	return box


## The Endless Rift's party: your champions (up to 4), the first one steered.
func _render_endless_assembly(v: VBoxContainer) -> void:
	var picked: Array = pending_party.filter(func(i): return str(i).begins_with("champ:") and GameState.champion_unlocked(str(i).trim_prefix("champ:")))
	pending_party.assign(picked)
	v.add_child(_label("Endless Rift — your champions (up to 4)", 20))
	_coach(v, "endless_champs", "Champions only", "Only champions go into the Endless Rift. You steer the first one you pick; the others follow and fight on their own, each with their Call as a signature move. Somewhere in the rift, lost champions wait in pillars of light: stand in one to free them. A run costs the guild a day.")
	var bar := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Palette.SURFACE2
	st.border_color = Palette.VIOLET_DEEP
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(10)
	bar.add_theme_stylebox_override("panel", st)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 12)
	var info := _vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var typed: Array[Hero] = []
	for i in pending_party:
		typed.append(GameState.champion_hero(str(i).trim_prefix("champ:")))
	info.add_child(_label(tr("Party power %d") % Combat.party_power(typed), 13))
	info.add_child(_endless_region_picker())
	var lost_left := GameState.lost_champions().filter(func(e): return not GameState.champion_unlocked(str(e[0]))).size()
	info.add_child(_wrap_label(tr("%d lost champions still wait in the rift.") % lost_left if lost_left > 0 else tr("Every lost champion has been found."), 12, true))
	info.add_child(_wrap_label(tr("Rift strength %d%% — it grows with every champion you free and every act you pass.") % int(round(GameState.endless_threat() * 100.0)), 12, true))
	brow.add_child(info)
	var enter := _icon_domain_button("violet", GameData.CAMP_HUB_ICON_PATH["rift"], tr("Enter the Rift"), func():
		if pending_party.is_empty():
			return
		var ids: Array[String] = []
		ids.assign(pending_party)
		_start_survivors(ids)
	)
	enter.disabled = pending_party.is_empty()
	enter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brow.add_child(enter)
	bar.add_child(brow)
	v.add_child(bar)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var any := false
	for id in GameState.champion_roll:
		if not GameState.champion_unlocked(id):
			continue
		any = true
		var key := "champ:" + id
		var slot := pending_party.find(key)
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanelEmber" if slot >= 0 else &"CardPanel"
		card.custom_minimum_size.x = 230
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_icon_trimmed(GameData.champion_portrait(id), 64))
		var col := _vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_label(GameData.champion_full_name(id), 13))
		col.add_child(_label(tr("%s · Level %d") % [tr(str(GameData.champion_def(id)["role"]).capitalize()), GameState.champion_level(id)], 11, true))
		col.add_child(_wrap_label(tr("Signature: %s") % tr(str(GameState.champion_call_of(id)["name"])), 11, true))
		if slot == 0:
			col.add_child(_label("You steer this one", 11))
		var btn := _button(tr("Remove") if slot >= 0 else tr("Add"), func(k=key):
			if pending_party.has(k):
				pending_party.erase(k)
			elif pending_party.size() < 4:
				pending_party.append(k)
			render()
		)
		btn.disabled = slot < 0 and pending_party.size() >= 4
		col.add_child(btn)
		row.add_child(col)
		card.add_child(row)
		grid.add_child(card)
	if not any:
		v.add_child(_wrap_label("You have no champions yet. The first is freed at the end of Act I.", 13, true))
	v.add_child(grid)


## The top of Party Assembly: party power against the recommendation, any
## wounded members, and Enter the Rift — up where it's seen, not below the
## roster and options.
func _party_launch_bar() -> Control:
	var bar := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Palette.SURFACE2
	st.border_color = Palette.VIOLET_DEEP
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(10)
	bar.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var info := _vbox(4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var going: Array = []
	for h in GameState.heroes:
		if pending_party.has(h.id):
			going.append(h)
	var rec_power: int = GameState.tower_recommended_power(GameState.tower_next_floor()) if _pending_tower else GameState.finale_recommended_power() if _pending_finale else Combat.recommended_power(_pending_diff_id, _pending_rift_rank)
	var pr := _power_readout(Combat.party_power(going), rec_power)
	pr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(pr)
	var hurt: Array = going.filter(func(h): return h.hp < Combat.max_hp(h) * 0.5)
	if pending_party.is_empty():
		info.add_child(_label("Add at least one hero to the party.", 12, true))
	elif not hurt.is_empty() and not _pending_tower:
		var hl := _wrap_label(tr("Wounded: %s — they start the rift hurt.") % tr(str(", ".join(hurt.map(func(h): return "%s (%d/%d)" % [tr(str(h.name.split(" the ")[0])), h.hp, Combat.max_hp(h)])))), 12)
		hl.add_theme_color_override("font_color", Palette.HAZARD)
		info.add_child(hl)
	if _pending_endless and _pending_rift_rank == "":
		info.add_child(_endless_region_picker())
	if _pending_endless and not pending_party.is_empty():
		var lead := GameState.find_hero(pending_party[0])
		if lead:
			info.add_child(_wrap_label(tr("Endless Rift: you steer %s (the first hero you picked); the others follow and fight on their own. Your build comes along: gear, skills, equipped relics, dodge and mending, and each hero's Ability. Survive the waves, and beat the Rift Warden at 20:00 to seal the rift.") % tr(str(lead.name.split(" the ")[0])), 12, true))
	row.add_child(info)
	var enter := _icon_domain_button("violet", GameData.CAMP_HUB_ICON_PATH["rift"], tr("Begin the trial") if _pending_tower else tr("Enter the Rift"), func():
		if pending_party.is_empty():
			return
		var chosen: Relic = pending_relic_options[pending_relic_choice] if pending_relic_choice >= 0 else null
		var ids: Array[String] = []
		ids.assign(pending_party)
		if _pending_endless and _pending_rift_rank == "":
			_start_survivors(ids)
			return
		if _pending_tower:
			GameState.start_tower(ids)
		elif _pending_daily:
			GameState.start_daily(_pending_rift_rank, ids, chosen)
		elif _pending_finale:
			GameState.start_finale(ids, chosen)
		elif _pending_rift_rank != "":
			GameState.start_ladder_rift(_pending_rift_rank, ids, chosen)
		else:
			GameState.start_run(_pending_diff_id, ids, chosen)
		_pending_finale = false
		_pending_tower = false
		_pending_daily = false
		pending_relic_options.clear()
		pending_relic_choice = -1
		_pending_rift_rank = ""
		screen = "rift_run"
		render()
		_play_rift_entry_flash()
	)
	enter.disabled = pending_party.is_empty()
	enter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(enter)
	bar.add_child(row)
	return bar


## Performance check (`?bench=survivors` on the web build, or `-- bench-survivors`):
## a self-steering Endless run fast-forwarded to 6:00 that logs FPS. Uses
## throwaway heroes and never saves.
func _start_bench() -> void:
	var party: Array = []
	for r in ["A", "A", "B", "B", "C"]:
		party.append(Combat.gen_hero(r, 10))
	var view := SurvivorsView.new()
	view.setup(party, "ashen")
	view.bench = true
	view.autopilot = true
	var t0 := Time.get_ticks_msec()
	while view.run.time < 360.0 and not view.run.over:
		view.run.step(0.1, view.run.autopilot_dir())
		view.run.events.clear()
		view.run.settle_picks()
	print("[bench] fast-forward to 6:00 took %d ms" % (Time.get_ticks_msec() - t0))
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(view)


## The Endless Rift's region, with the guild's best time in each and the
## next milestone.
func _endless_region_picker() -> Control:
	var box := _vbox(4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_label("Region:", 12, true))
	if _endless_biome == "":
		_endless_biome = "vale"
	for b in ["vale", "marsh", "ashen"]:
		var best := int(GameState.endless_best.get(b, 0))
		var btn := Button.new()
		btn.text = "%s  %s" % [tr(str(GameData.BIOMES[b]["name"]).trim_prefix("The ")), tr(str("%d:%02d" % [best / 60, best % 60] if best > 0 else "—"))]
		btn.toggle_mode = true
		btn.button_pressed = b == _endless_biome
		btn.tooltip_text = tr("Your best time in %s. It sets the foes you'll meet and the Rift Warden at 20:00 (%s).") % [tr(str(GameData.BIOMES[b]["name"])), tr(str(SurvivorsRun.FINAL_WARDEN[b]))]
		btn.pressed.connect(func(): _endless_biome = b; render())
		row.add_child(btn)
	box.add_child(row)
	var next: Dictionary = {}
	for m in GameData.ENDLESS_MILESTONES:
		if not GameState.endless_milestones.has(int(m["at"])):
			next = m
			break
	if not next.is_empty():
		var bits: Array = []
		if int(next["coins"]) > 0:
			bits.append(tr("%d gold") % int(next["coins"]))
		bits.append(tr("%d essence") % int(next["crystals"]))
		if next.has("relic"):
			bits.append(tr("the relic %s") % tr(str(GameData.ENDLESS_RELICS[next["relic"]]["name"])))
		if next.has("title"):
			bits.append(tr("the title \"%s\"") % tr(str(next["title"])))
		var goal := tr("Beat the Rift Warden at 20:00") if next.get("sealed", false) else tr("Survive %d:00") % (int(next["at"]) / 60)
		box.add_child(_wrap_label(tr("Next milestone: %s for %s.") % [tr(str(goal)), tr(str(", ".join(bits)))], 12, true))
	return box


## The Endless Rift is a real-time survivors run in its own node; Main steps
## aside (hidden and paused) until the player leaves it.
# ---------------- Riftbreaks ----------------
var _defense_posted: Array[String] = []   # hero ids for the posts, in order
var _defense_champ := ""                   # the champion to steer ("" = none)
var _defense_ready := false                # the picks above were filled in for this breach


## The swelling or broken rift, at the top of the Rift Hall: a one-line
## strip while it swells, a card with Defend once it breaks.
func _breach_card() -> PanelContainer:
	var broken := GameState.breach_broken()
	if not broken:
		var days := GameState.breach_days_left()
		var r := tr(GameState.breach_rank_id())
		var chip := _rule_chip(tr("⚠ A Rank %s rift near %s breaks in %d day%s — seal a Rank %s rift or higher to close it") % [r, GameState.breach_place(), days, tr(str(_pl(days))), r],
			tr("Or let it break and defend: build towers, post idle heroes, steer a champion (Guild > Manage > Defenses researches towers)."), Palette.EMBER_BRIGHT)
		(chip.get_child(0) as Label).add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		return chip
	var card := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.16, 0.05, 0.06, 0.95) if broken else Color(0.12, 0.08, 0.16, 0.95)
	st.border_color = Palette.HAZARD if broken else Palette.EMBER_BRIGHT
	st.set_border_width_all(2)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var col := _vbox(4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var rank := tr(GameState.breach_rank_id())
	if broken:
		var t := _label(tr("The rift has broken! Rank %s near %s") % [rank, GameState.breach_place()], 17)
		t.add_theme_color_override("font_color", Palette.HAZARD)
		col.add_child(t)
		col.add_child(_wrap_label(tr("Monsters are pouring out. Rift runs wait until your guild defends."), 13))
		var b := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], tr("Defend"), func(): screen = "defense"; render())
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
	return card


## Before a defense: who stands at the posts, which champion goes, and what's at stake.
func _render_defense_setup(v: VBoxContainer) -> void:
	if not GameState.breach_broken():
		screen = "rift_hall"
		_render_rift_hall(v)
		return
	var region := str(GameState.breach["region"])
	var posts: int = (GameData.DEFENSE_MAPS[region]["posts"] as Array).size()
	var cands := GameState.defense_candidates()
	if not _defense_ready:
		_defense_ready = true
		_defense_posted.clear()
		for h in cands.slice(0, posts):
			_defense_posted.append(h.id)
		_defense_champ = GameState.overseer
	_defense_posted.assign(_defense_posted.filter(func(id): return cands.any(func(h): return h.id == id)))
	v.add_child(_label(tr("Riftbreak — Rank %s near %s") % [tr(GameState.breach_rank_id()), GameState.breach_place()], 20))
	_coach(v, "defense", "Defending", "Foes walk the roads toward your outpost. Build towers on the round pads with supplies: you start with some and earn more for every kill. Tap a built tower to upgrade or sell it. Heroes at posts stand by the road: warriors and rogues hold foes in place, rangers and mages shoot. Tap the ground to send your champion. Every foe that gets through costs integrity; at 0 the defense is lost.")
	var opts := GameState.defense_opts()
	var names: Array = (opts["towers"] as Array).map(func(t): return tr(str(GameData.DEFENSE_TOWERS[t]["name"])))
	var waves := GameData.DEFENSE_WAVES + (GameData.DEFENSE_CAMP_WAVES if region == "camp" else 0)
	var info := _vbox(3)
	info.add_child(_wrap_label(tr("%d waves · integrity %d · %d starting supplies") % [waves, GameData.DEFENSE_INTEGRITY + int(opts["integrity"]), GameData.DEFENSE_SUPPLIES + int(opts["supplies"])], 13))
	info.add_child(_wrap_label(tr("Towers: %s · up to tier %d") % [", ".join(names), int(opts["max_tier"])], 13))
	var dmg_n := 2 if region == "camp" else 1
	info.add_child(_wrap_label(tr("Holding pays Gold and Essence. If it falls, you lose %d%% of your spare Gold and your Essence, %d building%s is damaged, and posted heroes who fell come back wounded.") % [int(GameData.BREACH_LOSS_SHARE * 100), dmg_n, tr(str(_pl(dmg_n)))], 12, true))
	v.add_child(info)
	v.add_child(_label(tr("Posts (%d/%d)") % [_defense_posted.size(), posts], 15))
	if cands.is_empty():
		v.add_child(_wrap_label(tr("No idle heroes can stand guard: towers and your champion will have to hold."), 12, true))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for h in cands:
		var on := _defense_posted.has(h.id)
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanelEmber" if on else &"CardPanel"
		card.custom_minimum_size.x = 220
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(_icon_trimmed(GameData.portrait_for_hero(h.cls_id, h.pool_id), 48))
		var col := _vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_label(h.name, 13))
		col.add_child(_label(tr("%s · Lv%d · Power %d") % [tr(GameData.hero_role(h).capitalize()), h.level, Combat.power_of(h)], 11, true))
		var btn := _button(tr("Stand down") if on else tr("Post"), func(id=h.id):
			if _defense_posted.has(id):
				_defense_posted.erase(id)
			elif _defense_posted.size() < posts:
				_defense_posted.append(id)
			render())
		btn.disabled = not on and _defense_posted.size() >= posts
		col.add_child(btn)
		row.add_child(col)
		card.add_child(row)
		grid.add_child(card)
	v.add_child(grid)
	v.add_child(_label(tr("Champion: %s") % (GameData.champion_full_name(_defense_champ) if _defense_champ != "" else tr("none")), 15))
	var crow := HFlowContainer.new()
	crow.add_theme_constant_override("h_separation", 6)
	for id in GameState.champion_roll:
		if not GameState.champion_unlocked(id):
			continue
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = id == _defense_champ
		b.text = str(GameData.champion_def(id)["name"])
		b.pressed.connect(func(i=id): _defense_champ = i; render())
		crow.add_child(b)
	var none := Button.new()
	none.toggle_mode = true
	none.button_pressed = _defense_champ == ""
	none.text = tr("None")
	none.pressed.connect(func(): _defense_champ = ""; render())
	crow.add_child(none)
	v.add_child(crow)
	var go := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], tr("Defend"), _start_defense)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(go)


func _start_defense() -> void:
	if not GameState.breach_broken():
		return
	var posted: Array = []
	for id in _defense_posted:
		var h := GameState.find_hero(id)
		if h:
			posted.append(h)
	var champ: Hero = GameState.champion_hero(_defense_champ) if _defense_champ != "" and GameState.champion_unlocked(_defense_champ) else null
	var view := DefenseView.new()
	view.setup(str(GameState.breach["region"]), int(GameState.breach["rank"]), posted, champ, GameState.defense_opts())
	_camp_track = ""
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(view)
	view.finished.connect(func(_summary):
		view.queue_free()
		visible = true
		process_mode = Node.PROCESS_MODE_INHERIT
		_defense_ready = false
		screen = "rift_hall"
		render())


func _start_survivors(ids: Array[String]) -> void:
	var party: Array = []
	for id in ids:
		var h := GameState.champion_hero(id.trim_prefix("champ:")) if id.begins_with("champ:") else GameState.find_hero(id)
		if h:
			party.append(h)
	if party.is_empty():
		return
	var view := SurvivorsView.new()
	view.setup(party, _endless_biome if _endless_biome != "" else GameState.pick_biome())
	_camp_track = ""   # home again afterwards: a fresh camp track
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(view)
	view.finished.connect(func(_summary):
		view.queue_free()
		visible = true
		process_mode = Node.PROCESS_MODE_INHERIT
		_pending_endless = false
		pending_party.clear()
		screen = "rift_hall"
		render())


# ---------------- Settings ----------------
func _volume_row(label_text: String, value: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := _label(label_text, 14)
	lbl.custom_minimum_size = Vector2(120, 0)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = round(value * 100)
	slider.custom_minimum_size = Vector2(180, 0)
	row.add_child(slider)
	var pct := _label("%d%%" % int(round(value * 100)), 12, true)
	pct.custom_minimum_size = Vector2(40, 0)
	row.add_child(pct)
	# Deliberately not wired through render() — rebuilding the whole tree on
	# every drag tick would tear the slider out from under an in-progress
	# drag. The percent label updates directly instead.
	slider.value_changed.connect(func(new_value: float):
		pct.text = "%d%%" % int(new_value)
		on_change.call(new_value / 100.0)
	)
	return row


func _switch_slot(slot: int) -> void:
	GameState.set_active_slot(slot)
	term_tab = "camp"
	mgmt_branch = ""
	inv_category = ""
	confirm_reset = false
	confirm_delete_slot = -1
	if not GameState.load_save():
		GameState.reset()
	if GameState.guild_name != "":
		screen = "camp" if GameState.run.is_empty() else "rift_run"
	else:
		pending_crest = 1 + randi() % GameData.CREST_PATH.size()
		screen = "onboard"
	render()


func _render_settings(v: VBoxContainer) -> void:
	v.add_child(_label("Settings", 20))
	v.add_child(_language_row())
	var fb := _button(tr("Send feedback") if not _feedback_open else tr("Hide feedback"), func():
		_feedback_open = not _feedback_open
		render())
	fb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(fb)
	if _feedback_open:
		v.add_child(_feedback_panel())

	v.add_child(_label("Audio", 15))
	v.add_child(_volume_row("Music", GameState.music_volume, func(val: float):
		GameState.music_volume = val
		AudioManager.set_music_volume(val)
		GameState.save_settings()
	))
	v.add_child(_volume_row("SFX", GameState.sfx_volume, func(val: float):
		GameState.sfx_volume = val
		AudioManager.set_sfx_volume(val)
		GameState.save_settings()
	))

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	speed_row.add_child(_label("Battle speed", 13))
	for spd in [1.0, 2.0, 3.0, INSTANT_SPEED]:
		var spb := _button(tr("Instant") if spd >= INSTANT_SPEED else "×%d" % int(spd), func(val=spd):
			GameState.combat_speed = val
			GameState.save_settings()
			render()
		)
		spb.toggle_mode = true
		spb.button_pressed = is_equal_approx(GameState.combat_speed, spd)
		spb.tooltip_text = tr("Fights resolve with no animation; the screen updates when it's your turn") if spd >= INSTANT_SPEED else tr("Battle animations at %d× speed") % int(spd)
		speed_row.add_child(spb)
	v.add_child(speed_row)

	v.add_child(_hsep())
	v.add_child(_label("Display", 15))
	# Scales every piece of UI (text, buttons, art) together — the game's
	# fixed-size layouts stay intact, just bigger or smaller.
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 6)
	scale_row.add_child(_label("Text & UI size", 13))
	for sc in [0.9, 1.0, 1.15, 1.3, 1.5]:
		var sb := _button("%d%%" % int(round(sc * 100)), func(val=sc):
			GameState.ui_scale = val
			get_tree().root.content_scale_factor = val
			GameState.save_settings()
			render()
		)
		sb.toggle_mode = true
		sb.button_pressed = is_equal_approx(GameState.ui_scale, sc)
		scale_row.add_child(sb)
	v.add_child(scale_row)
	if OS.has_feature("web"):
		# Resolution switching is a desktop-only concept — on Web the browser
		# tab/window already sizes the canvas correctly on its own.
		v.add_child(_wrap_label("The game fits your browser window automatically.", 12, true))
		v.add_child(_fullscreen_button())
	else:
		var res_opts: Array = GameData.RESOLUTION_OPTIONS
		var res_idx := GameState.resolution_idx
		v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["sort"], tr("Resolution: %s") % tr(str(res_opts[res_idx]["label"])), func():
			var next_idx: int = (res_idx + 1) % res_opts.size()
			GameState.resolution_idx = next_idx
			GameState.save_settings()
			_apply_resolution(next_idx)
			render()
		))

	v.add_child(_hsep())
	v.add_child(_label("Accessibility", 15))
	var acc_row := HFlowContainer.new()
	acc_row.add_theme_constant_override("h_separation", 8)
	var rm := _button(tr("Reduce motion: %s") % tr(str((tr("on") if GameState.reduce_motion else tr("off")))), func():
		GameState.reduce_motion = not GameState.reduce_motion
		GameState.save_settings()
		render())
	rm.tooltip_text = "No screen shake, zooms, knockbacks, idle sway or flashing in fights"
	acc_row.add_child(rm)
	var cb := _button(tr("Colour-blind mode: %s") % tr(str((tr("on") if GameState.colorblind else tr("off")))), func():
		GameState.colorblind = not GameState.colorblind
		GameState.save_settings()
		render())
	cb.tooltip_text = "Blue instead of green wherever it sits against red (HP, fight readouts, stat changes), and a rarity letter on every item"
	acc_row.add_child(cb)
	var ha := _button(tr("Hearing aid: %s") % tr(str((tr("on") if GameState.hearing_aid else tr("off")))), func():
		GameState.hearing_aid = not GameState.hearing_aid
		GameState.save_settings()
		render())
	ha.tooltip_text = "Sounds that tell you something also show as captions at the bottom of the screen (a boss arriving, a heavy blow, a hero going down, a wind-up, a chest dropping), and the biggest ones pulse the screen's edges"
	acc_row.add_child(ha)
	v.add_child(acc_row)

	v.add_child(_hsep())
	v.add_child(_label("Tips", 15))
	var tips_row := HBoxContainer.new()
	tips_row.add_theme_constant_override("separation", 8)
	tips_row.add_child(_button(tr("Tips: %s") % tr(str((tr("off") if GameState.tips_off else tr("on")))), func():
		GameState.tips_off = not GameState.tips_off
		GameState.save()
		render()
	))
	tips_row.add_child(_button("Show all tips again", func():
		GameState.hints_seen = []
		GameState.tips_off = false
		GameState.save()
		render()
	))
	v.add_child(tips_row)

	v.add_child(_hsep())
	v.add_child(_label("Save Slots", 15))
	_render_slot_list(v)
	_render_save_backup(v)


var _backup_msg := ""
var _import_open := false
var _import_text := ""
var _js_file_cb   # keeps the browser file-picker callback alive


## Export the active save (clipboard, plus a download on the web) or import
## one — pasted, or picked from a file on the web — into the active slot.
## Browser storage can be wiped by clearing site data; this is the backup.
func _render_save_backup(v: VBoxContainer) -> void:
	v.add_child(_hsep())
	v.add_child(_label("Backup", 15))
	v.add_child(_wrap_label("Saves live in this browser/device only; clearing site data erases them. Export one to keep a copy or move it to another device. The previous save is also kept automatically in case one gets damaged.", 12, true))
	if GameState.guild_name != "":
		var le := _label(tr("Last exported: %s") % tr(str(("never" if GameState.last_export_day < 0 else tr("day %d (today is day %d)") % [GameState.last_export_day, GameState.day]))), 12)
		le.add_theme_color_override("font_color", Palette.HAZARD if GameState.last_export_day < 0 and GameState.rifts_sealed >= 3 else Palette.MUTED)
		v.add_child(le)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var exp := _icon_button(GameData.BUTTON_ICON_PATH["confirm"], "Export save", func():
		var text := GameState.export_save_text()
		if text == "":
			_backup_msg = "Nothing to export in this slot yet."
		else:
			DisplayServer.clipboard_set(text)
			if OS.has_feature("web"):
				JavaScriptBridge.download_buffer(text.to_utf8_buffer(), "guild_save_%s.json" % GameState.guild_name.to_snake_case(), "application/json")
				_backup_msg = "Downloaded, and copied to the clipboard."
			else:
				_backup_msg = "Copied to the clipboard — paste it somewhere safe."
		render()
	)
	exp.disabled = GameState.guild_name == ""
	row.add_child(exp)
	row.add_child(_icon_button(GameData.BUTTON_ICON_PATH["sort"], tr("Import save…") if not _import_open else tr("Cancel import"), func():
		_import_open = not _import_open
		_import_text = ""
		_backup_msg = ""
		render()
	))
	v.add_child(row)
	if _import_open:
		var slot := GameState.active_slot
		v.add_child(_wrap_label(tr("Paste an exported save below%s. It replaces Slot %d%s.") % [tr(str(tr(" or pick the file") if OS.has_feature("web") else "")), slot + 1, tr(str(" (%s)" % tr(str(GameState.guild_name)) if GameState.guild_name != "" else ""))], 12))
		if OS.has_feature("web"):
			v.add_child(_button("Choose file…", func(): _web_pick_save_file()))
		var te := TextEdit.new()
		te.custom_minimum_size = Vector2(0, 90)
		te.placeholder_text = "{\"guild_name\": ...}"
		te.text = _import_text
		te.text_changed.connect(func(): _import_text = te.text)
		v.add_child(te)
		var go := _icon_domain_button("ember", GameData.BUTTON_ICON_PATH["confirm"], tr("Replace Slot %d with this save") % (slot + 1), func():
			var err := GameState.import_save_text(_import_text, slot)
			if err != "":
				_backup_msg = err
				render()
				return
			_import_open = false
			_import_text = ""
			_backup_msg = "Save imported."
			_switch_slot(slot)
		)
		go.disabled = _import_text.strip_edges() == ""
		v.add_child(go)
	if _backup_msg != "":
		v.add_child(_label(_backup_msg, 12, true))


func _web_pick_save_file() -> void:
	if not OS.has_feature("web"):
		return
	_js_file_cb = JavaScriptBridge.create_callback(func(args):
		_import_text = str(args[0])
		render()
	)
	JavaScriptBridge.get_interface("window").godotSaveImportCb = _js_file_cb
	JavaScriptBridge.eval("""(function(){var i=document.createElement('input');i.type='file';i.accept='.json,application/json';
		i.onchange=function(e){var f=e.target.files[0];if(!f)return;var r=new FileReader();r.onload=function(){window.godotSaveImportCb(r.result);};r.readAsText(f);};i.click();})();""", true)


## Shared by Settings' "Save Slots" section and the title screen's Load Game
## list — same slot rows (Play/Delete), just embedded in two different
## screens, so the delayed delete-confirm timeout's render() gate has to
## check "whichever of them is still showing", not one hardcoded screen name.
func _render_slot_list(v: VBoxContainer) -> void:
	for slot in GameState.SLOT_COUNT:
		var summary := GameState.slot_summary(slot)
		var is_active := slot == GameState.active_slot
		var is_empty: bool = summary.get("empty", true)
		var text := tr("Slot %d — Empty") % (slot + 1)
		if not is_empty:
			var sealed := int(summary.get("rifts_sealed", 0))
			text = tr("Slot %d — %s (%d rift%s sealed)") % [slot + 1, tr(str(summary.get("guild_name", ""))), sealed, tr(str(_pl(sealed)))]
		if is_active:
			text += tr("  (Active)")
		var actions: Array[Control] = []
		# From the title's Load Game, the active slot still needs a way back in.
		if is_active and not is_empty and screen == "load_game":
			actions.append(_icon_button(GameData.BUTTON_ICON_PATH["confirm"], "Continue", func(s=slot):
				_switch_slot(s)
			))
		if not is_active:
			actions.append(_icon_button(GameData.BUTTON_ICON_PATH["confirm"], "Play", func(s=slot):
				_switch_slot(s)
			))
			if not is_empty:
				actions.append(_icon_button("res://assets/skills/shard_green.png", "Click again to confirm delete" if confirm_delete_slot == slot else "Delete", func(s=slot):
					if confirm_delete_slot != s:
						confirm_delete_slot = s
						render()
						get_tree().create_timer(3.0).timeout.connect(func():
							if confirm_delete_slot == s:
								confirm_delete_slot = -1
								if screen == "settings" or screen == "load_game":
									render()
						)
						return
					GameState.delete_slot(s)
					confirm_delete_slot = -1
					render()
				))
		v.add_child(_info_row(text, 13, actions))

## One hero as a Party Assembly card: a draggable portrait (drop it on a
## Front/Back row), name, level/role/HP, and their position bonus. `in_party`
## cards get Move/Remove (the Champion can't be removed); bench cards get Add,
## which drops the hero into their role's natural row.
func _party_card(h: Hero, is_champ: bool, in_party: bool) -> Control:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.SURFACE3 if in_party else Palette.SURFACE
	style.border_color = Palette.LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	card.add_theme_stylebox_override("panel", style)
	var cv := _vbox(2)
	cv.custom_minimum_size.x = 150
	cv.mouse_filter = Control.MOUSE_FILTER_PASS
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	var downed := h.is_downed() or h.busy_runs > 0
	var portrait := GameData.portrait_for_hero(h.cls_id, h.pool_id)
	if portrait != "":
		var icon := DragIcon.new()
		var tex: Texture2D = _icon_trimmed(portrait, 44).texture
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(44, 44)
		_hero_look(icon, h)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if not downed:
			icon.drag_payload = {"kind": "party_hero", "hero_id": h.id}
			icon.mouse_default_cursor_shape = Control.CURSOR_MOVE
			icon.tooltip_text = "Drag onto the Front or Back row"
		else:
			icon.modulate = Color(1, 1, 1, 0.4)
		top.add_child(icon)
	var names := _vbox(0)
	names.mouse_filter = Control.MOUSE_FILTER_PASS
	names.add_child(_label(h.name.split(" the ")[0], 12))
	names.add_child(_label(tr("Lv%d %s · %d/%d HP%s") % [h.level, tr(str(GameData.hero_role(h).capitalize())), h.hp, Combat.max_hp(h), tr(str((tr(" · out %d run%s") % [h.down_runs, tr(str(_pl(h.down_runs)))] if h.down_runs > 0 else tr(" · away %d run%s") % [h.busy_runs, tr(str(_pl(h.busy_runs)))]) if downed else ""))], 10, true))
	if not downed and h.hp < Combat.max_hp(h) * 0.5:
		var wl := _label(tr("Wounded — %d%% HP") % int(100.0 * h.hp / max(1, Combat.max_hp(h))), 12)
		wl.add_theme_color_override("font_color", Palette.HAZARD)
		wl.tooltip_text = "Starts the rift at this HP. A Medical Bay bed or a rest heals them."
		names.add_child(wl)
	var power_line := tr("Power %d") % Combat.power_of(h)
	var arch := _main_arch(h)
	names.add_child(_rich_line(power_line + ("  " + _arch_chip(arch) if arch != "" else ""), 10, true))
	top.add_child(names)
	cv.add_child(top)
	var pos_text := _position_text(h) if in_party else ""
	if pos_text != "":
		cv.add_child(_wrap_label(pos_text, 10, true))
	var actions := HBoxContainer.new()
	if in_party:
		var other := "back" if h.formation == "front" else "front"
		actions.add_child(_button(tr("Move %s") % tr(other), func(id=h.id, r=other):
			GameState.set_hero_formation(id, r)
			render()
		))
		actions.add_child(_button("Remove", func(id=h.id):
			pending_party.erase(id)
			render()
		))
	elif not downed:
		var add_btn := _button("Add", func(id=h.id, hero=h):
			if pending_party.size() >= _party_cap():
				return
			pending_party.append(id)
			GameState.set_hero_formation(id, str(GameData.ROLE_POSITION.get(GameData.hero_role(hero), {}).get("row", hero.formation)))
			render()
		)
		add_btn.disabled = pending_party.size() >= _party_cap()
		actions.add_child(add_btn)
	cv.add_child(actions)
	card.add_child(cv)
	return card
