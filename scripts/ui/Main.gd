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
	GameState.load_active_slot()
	AudioManager.set_music_volume(GameState.music_volume)
	AudioManager.set_sfx_volume(GameState.sfx_volume)
	_apply_resolution(GameState.resolution_idx)
	get_tree().root.content_scale_factor = GameState.ui_scale
	# Deliberately doesn't load_save()/reset() or route past "title" here —
	# every boot lands on the title screen now (New Game/Load Game/Credits/
	# Quit) regardless of whether the active slot has a guild in it, matching
	# the reference title screen rather than auto-resuming. New Game and Load
	# Game both route through _switch_slot(), which is what actually loads
	# (or resets) a slot's state once the player picks one.
	GameState.state_changed.connect(render)
	# Portrait pop-ups live on their own CanvasLayer so render()'s
	# _clear_root() never wipes one mid-fade.
	var toast_layer := CanvasLayer.new()
	toast_layer.layer = 50
	add_child(toast_layer)
	_toast_box = VBoxContainer.new()
	_toast_box.add_theme_constant_override("separation", 6)
	_toast_box.anchor_left = 1.0
	_toast_box.anchor_right = 1.0
	_toast_box.offset_left = -300
	_toast_box.offset_right = -12
	_toast_box.offset_top = 84
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_layer.add_child(_toast_box)
	render()


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


var _toast_box: VBoxContainer


## Shows every queued GameState toast as a portrait card at the top right,
## each fading out on its own after a few seconds (real time — unaffected by
## the combat speed setting).
func _drain_toasts() -> void:
	if _toast_box == null:
		return
	for t in GameState.pending_toasts:
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style := StyleBoxFlat.new()
		style.bg_color = Palette.SURFACE2
		style.border_color = Palette.EMBER_BRIGHT
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(8)
		card.add_theme_stylebox_override("panel", style)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var portrait := GameData.portrait_for_hero(str(t["cls_id"]), str(t["pool_id"]))
		if portrait != "":
			row.add_child(_icon_trimmed(portrait, 44))
		var col := _vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if str(t["title"]) != "":
			var title := _label(str(t["title"]), 14)
			title.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
			col.add_child(title)
		col.add_child(_wrap_label(str(t["text"]), 12, true))
		row.add_child(col)
		card.add_child(row)
		_toast_box.add_child(card)
		AudioManager.play_sfx(GameData.SFX_PATH["ui_confirm"])
		var tw := card.create_tween()
		tw.set_ignore_time_scale(true)
		tw.tween_interval(4.5)
		tw.tween_property(card, "modulate:a", 0.0, 0.6)
		tw.tween_callback(card.queue_free)
	GameState.pending_toasts.clear()


func render() -> void:
	_combat_hotkeys.clear()
	# Combat speed only ever applies inside a rift — camp animations (embers,
	# day/night drift) always run at normal speed.
	Engine.time_scale = GameState.combat_speed if screen == "rift_run" else 1.0
	GameState.resolve_recovery()
	GameState.resolve_rift_map()
	GameState.resolve_guild_board()
	var newly_claimed := GameState.check_milestones()
	if not newly_claimed.is_empty():
		var m = GameData.MILESTONES.filter(func(x): return str(x["id"]) == newly_claimed[0])[0]
		GameState.pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Milestone reached", "text": str(m["label"])})
	if _flavor_toast != "":
		GameState.pending_toasts.append({"cls_id": "", "pool_id": "", "title": "", "text": _flavor_toast})
		_flavor_toast = ""
	_drain_toasts()
	if screen == "terminal" and GameState.run.is_empty() and not GameState.pending_riftbreak_ranks.is_empty():
		GameState.start_riftbreak_encounter()
		if not GameState.run.is_empty():
			screen = "rift_run"
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
	var render_key := "%s|%s" % [screen, term_tab]
	var is_navigation := render_key != _last_render_key
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
	var outer := _vbox(10)
	root.add_child(outer)
	if screen not in ["title", "load_game", "credits", "onboard"]:
		_topbar(outer, _breadcrumb_for_screen())
		var back := _header_back()
		if not back.is_empty():
			_combat_hotkeys["Escape"] = back[0]
		if screen in ["terminal", "crafting_hall", "rift_hall", "rift_map"]:
			outer.add_child(_quick_nav())
	if not _s_rank_celebration.is_empty():
		outer.add_child(_render_s_rank_celebration(_s_rank_celebration))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	scroll.set_deferred("scroll_vertical", _last_scroll_y)
	var v := _vbox(14)
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
		"rift_map": _render_rift_map_hub(v)
		"party_assembly": _render_party_assembly(v)
		"rift_run": _render_rift_run(v)
		"crafting_hall": _render_crafting_hall(v)
		"settings": _render_settings(v)
		"terminal": _render_terminal(v)
	_update_screen_music()

	# A real navigation (not an in-place data refresh — see is_navigation
	# above) fades the new screen in from transparent instead of just
	# snapping into place, so moving between hubs reads as one continuous
	# world instead of a slideshow of unrelated pages.
	if is_navigation:
		root.modulate = Color(1, 1, 1, 0)
		var fade_tw := create_tween()
		fade_tw.tween_property(root, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)


## Only 2 music tracks are planned for now (combat, camp — see the Suno plan
## in the project doc), so this only ever switches between those two states
## and otherwise leaves whatever's already playing alone, rather than
## stopping/restarting on every screen that doesn't have a track assigned
## yet. Both AudioManager.play_music calls are safe to make unconditionally
## (they already no-op on a repeat of the same path, or a missing file).
func _update_screen_music() -> void:
	if screen == "terminal":
		AudioManager.play_music(GameData.MUSIC_PATH["camp"])
	elif screen == "rift_run":
		var kind := GameState.current_node_kind()
		var ns: Dictionary = GameState.run.get("node_state", {})
		if kind in ["combat", "boss", "elite"] and ns.has("combat_state"):
			AudioManager.play_music(GameData.MUSIC_PATH["combat"])


## Pinned HUD stays outside the ScrollContainer, so the guild identity,
## currencies, and "where am I" breadcrumb never scroll out of view.
func _breadcrumb_for_screen() -> String:
	match screen:
		"rift_hall": return "Rift Hall"
		"rift_map": return "Rift Map"
		"party_assembly": return "Party Assembly"
		"rift_run": return "Rift Run — Floor %d/%d" % [int(GameState.run.get("pos", 0)) + 1, GameState.run.get("layers", []).size()]
		"crafting_hall": return "Crafting Hall"
		"settings": return "Settings"
		"terminal": return "Terminal" if term_tab == "camp" else "Terminal — %s" % term_tab.capitalize()
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
	var source_text := "joins as Champion!" if str(data["source"]) == "champion" else "is available to recruit!"
	mid.add_child(_label("%s %s" % [str(data["name"]), source_text], 13))
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


## Every camp destination, reachable from any camp-side screen in one click
## or one key (1-9, 0), instead of Camp -> building -> picker -> screen.
## [id, label, camp building whose attention badge it shares]
const QUICK_NAV := [
	["roster", "Roster", "Command Tent"],
	["recruits", "Recruits", "Hero Recruits"],
	["medical", "Medical", "Medical Tent"],
	["inventory", "Inventory", ""],
	["crafting", "Crafting", "Trading Post"],
	["quests", "Quests", "Scholar's Lodge"],
	["rift", "Rift Hall", "Rift Gate"],
	["rift_map", "Rift Map", ""],
	["management", "Manage", ""],
	["bestiary", "Bestiary", ""],
	["compendium", "Codex", ""],
]


func _quick_nav_current() -> String:
	match screen:
		"crafting_hall": return "crafting"
		"rift_hall": return "rift"
		"rift_map": return "rift_map"
		"terminal": return "" if term_tab == "camp" else term_tab
	return ""


func _quick_go(id: String) -> void:
	hub_cluster = ""
	inv_category = ""
	mgmt_branch = ""
	medical_picker_bed = -1
	match id:
		"crafting": screen = "crafting_hall"
		"rift": screen = "rift_hall"
		"rift_map": screen = "rift_map"
		_:
			screen = "terminal"
			term_tab = id
	render()


func _quick_nav() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	var badges := _camp_badges()
	var current := _quick_nav_current()
	for i in QUICK_NAV.size():
		var e: Array = QUICK_NAV[i]
		var id: String = e[0]
		var key := str((i + 1) % 10) if i < 10 else ""
		var go := _quick_go.bind(id)
		var b := _button("", go)
		b.custom_minimum_size = Vector2(76, 54)
		b.toggle_mode = true
		b.button_pressed = id == current
		b.tooltip_text = "%s%s" % [e[1], "  (key %s)" % key if key != "" else ""]
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var tile := VBoxContainer.new()
		tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tile.alignment = BoxContainer.ALIGNMENT_CENTER
		tile.add_theme_constant_override("separation", 1)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := _icon(GameData.CAMP_HUB_ICON_PATH[id], 26)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(ic)
		var nl := _label(str(e[1]), 12)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(nl)
		b.add_child(tile)
		if key != "":
			_combat_hotkeys[key] = go
			var kl := _label(key, 12)
			kl.add_theme_color_override("font_color", Palette.MUTED)
			kl.position = Vector2(3, 0)
			b.add_child(kl)
		var badge: Array = badges.get(str(e[2]), [])
		if not badge.is_empty():
			var chip := _count_badge(str(badge[0]), str(badge[1]))
			chip.position = Vector2(58, -6)
			b.add_child(chip)
		bar.add_child(b)
	return bar


## The header's back button for this screen: [callback, destination name],
## or [] for none. Every screen's "back" lives here, so it's always in the
## same place instead of at the bottom of a long page.
func _header_back() -> Array:
	var to_camp := func():
		screen = "terminal"
		term_tab = "camp"
		hub_cluster = ""
		medical_picker_bed = -1
		mgmt_branch = ""
		inv_category = ""
		render()
	match screen:
		"terminal":
			if term_tab == "inventory" and inv_category != "":
				return [func(): inv_category = ""; render(), "Inventory"]
			if term_tab == "management" and mgmt_branch != "":
				return [func(): mgmt_branch = ""; render(), "Management"]
			if term_tab != "camp" or hub_cluster != "":
				return [to_camp, "Camp"]
		"rift_hall", "rift_map", "crafting_hall":
			return [to_camp, "Camp"]
		"party_assembly":
			var from_map := _pending_rift_rank != ""
			return [func():
				screen = "rift_map" if _pending_rift_rank != "" else "rift_hall"
				_pending_rift_rank = ""
				_pending_map_slot_idx = -1
				render()
			, "Rift Map" if from_map else "Rift Hall"]
		"settings":
			const NAMES := {"terminal": "Camp", "rift_run": "Rift", "rift_hall": "Rift Hall", "rift_map": "Rift Map",
				"party_assembly": "Party Assembly", "crafting_hall": "Crafting Hall"}
			return [func(): screen = _pre_settings_screen; render(), NAMES.get(_pre_settings_screen, "Back")]
	return []


## Content column width: combat, the camp scene and the two-pane screens
## use the window's width; text-heavy screens stay at a readable measure.
func _column_width() -> float:
	var avail: float = get_viewport().get_visible_rect().size.x - 64.0
	if screen == "rift_run":
		return _battle_width()
	if screen == "terminal" and ((term_tab == "camp" and hub_cluster == "") or term_tab in ["roster", "inventory"]):
		return clampf(avail, 760.0, 1180.0)
	return clampf(avail, 700.0, 860.0)


func _topbar(container: Control, breadcrumb: String = "") -> void:
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Palette.SURFACE2
	bar_style.border_width_bottom = 2
	bar_style.border_color = Palette.EMBER_DEEP
	bar_style.content_margin_left = 12.0
	bar_style.content_margin_right = 12.0
	bar_style.content_margin_top = 8.0
	bar_style.content_margin_bottom = 8.0
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", bar_style)
	var bar_v := _vbox(4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var back := _header_back()
	if not back.is_empty():
		var bb := _button(str(back[1]), back[0])
		bb.icon = load(GameData.BUTTON_ICON_PATH["back"])
		bb.tooltip_text = "Back to %s" % str(back[1])
		bb.custom_minimum_size = Vector2(40, 36)
		row.add_child(bb)
	row.add_child(_icon(GameData.CREST_PATH[GameState.guild_crest - 1], 24))
	var name_lbl := _label(GameState.guild_name, 16)
	name_lbl.add_theme_font_override("font", DISPLAY_FONT)
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_lbl)
	if breadcrumb != "":
		var crumb := _label("›  " + breadcrumb, 16)
		crumb.add_theme_color_override("font_color", Palette.MUTED)
		crumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(crumb)
	var stat_spacer := Control.new()
	stat_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(stat_spacer)
	for entry in [
		[GameData.CURRENCY_ICON_PATH["coins"], GameState.coins],
		[GameData.CURRENCY_ICON_PATH["crystals"], GameState.crystals],
		[GameData.CURRENCY_ICON_PATH["tokens"], GameState.tokens],
		[GameData.CURRENCY_ICON_PATH["reputation"], GameState.reputation],
	]:
		var stat_row := HBoxContainer.new()
		stat_row.add_child(_icon(entry[0], 18))
		stat_row.add_child(_count_label(str(entry[0]), int(entry[1]), 16))
		var tile := PanelContainer.new()
		tile.theme_type_variation = &"StatTileEmber"
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
	v.add_child(_banner(GameData.TITLE_BG, 760, 320))

	var title_lbl := _label("Guild System", 30)
	title_lbl.add_theme_font_override("font", DISPLAY_FONT)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(title_lbl)
	v.add_child(_hsep())

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var menu := _vbox(8)
	menu.custom_minimum_size.x = 280
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
	if not OS.has_feature("web"):
		menu.add_child(_button("Quit", func():
			get_tree().quit()
		))
	center.add_child(menu)
	v.add_child(center)


func _render_load_game(v: VBoxContainer) -> void:
	v.add_child(_label("Load Game", 20))
	_render_slot_list(v)
	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back", func():
		screen = "title"
		render()
	))


func _render_credits(v: VBoxContainer) -> void:
	v.add_child(_label("Credits", 20))
	v.add_child(_label("Guild System", 18))
	v.add_child(_wrap_label("A roguelite guild-management game — recruit heroes, evolve their subclasses, and send them through the Rifts.", 13, true))
	v.add_child(_hsep())
	v.add_child(_label("Built with Godot Engine 4.7", 13))
	v.add_child(_label("Pixel art generated with PixelLab", 13))
	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back", func():
		screen = "title"
		render()
	))


# ---------------- Onboard ----------------
func _render_onboard(v: VBoxContainer) -> void:
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	var slot_lbl := _label("Save Slot %d" % (GameState.active_slot + 1), 12, true)
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
	v.add_child(edit)

	v.add_child(_label("Choose a Crest", 16))
	var crest_row := HBoxContainer.new()
	crest_row.add_theme_constant_override("separation", 12)
	crest_row.add_child(_icon(GameData.CREST_PATH[pending_crest - 1], 64))
	crest_row.add_child(_icon_button(GameData.BUTTON_ICON_PATH["dice"], "Randomize", func():
		pending_crest = 1 + randi() % GameData.CREST_PATH.size()
		render()
	))
	v.add_child(crest_row)

	v.add_child(_icon_domain_button("violet", GameData.BUTTON_ICON_PATH["confirm"], "Found the Guild", func():
		var n := edit.text.strip_edges()
		if n == "":
			return
		GameState.guild_name = n
		GameState.guild_crest = pending_crest
		GameState.refresh_recruit_pool()
		GameState.save()
		pending_guild_name = ""
		pending_crest = 1
		_flavor_toast = GameData.narrative_line("guild_founded")
		screen = "terminal"
		render()
	))


# ---------------- Rift Hall ----------------
## Lesser and Endless Rift are each a gate on the rift chamber's background
## art, clickable straight into Party Assembly — no intermediate detail view
## since there's nothing else to decide here, unlike Guild Management/
## Inventory's hubs. The chained third gateway in the art gets a hotspot too
## once GameState.greater_rift_unlocked() — inert (no hotspot at all) before that.
func _render_rift_hall(v: VBoxContainer) -> void:
	v.add_child(_label("Rift Hall", 20))

	var scene_size := Vector2(700, 340)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size
	scene.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var bg := TextureRect.new()
	bg.texture = load(GameData.RIFTHALL_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)

	var camp_scale := Vector2(700.0 / 320.0, 340.0 / 200.0)
	var lesser: Dictionary = GameData.DIFFICULTIES[0]
	var greater: Dictionary = GameData.DIFFICULTIES[1]
	var unlocked := GameState.greater_rift_unlocked()
	var go := func(diff_id: String, endless: bool):
		pending_party.clear()
		screen = "party_assembly"
		_pending_diff_id = diff_id
		_pending_endless = endless
		render()
	var gate_entries := [
		["Lesser Rift", Rect2(0, 0, 230, 340), Rect2(18, 65, 68, 98), go.bind(str(lesser["id"]), false)],
		["Endless Rift", Rect2(230, 0, 240, 340), Rect2(110, 20, 97, 130), go.bind("endless", true)],
	]
	# The chained, rubble-blocked archway stays inert until
	# GameState.greater_rift_unlocked() (earned by sealing rifts).
	if unlocked:
		gate_entries.append(["Greater Rift", Rect2(470, 0, 230, 340), Rect2(230, 30, 78, 140), go.bind(str(greater["id"]), false)])
	for entry in gate_entries:
		var native_rect: Rect2 = entry[2]
		var glow_rect := Rect2(native_rect.position * camp_scale, native_rect.size * camp_scale)
		var hotspot := _camp_area_hotspot(entry[1], glow_rect, str(entry[0]), entry[3])
		hotspot.position = (entry[1] as Rect2).position
		scene.add_child(hotspot)
	if not unlocked:
		var lock_plaque := _camp_plaque("Greater Rift — locked")
		lock_plaque.position = Vector2(470 + (230 - lock_plaque.size.x) * 0.5, 340 - lock_plaque.size.y - 6)
		scene.add_child(lock_plaque)
	v.add_child(scene)

	# One card per rift: what it is, how your strongest party measures up,
	# and the button to go.
	var best := _best_party_power()
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 10)
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	var card_defs := [
		["Lesser Rift", "%d floors" % int(lesser["floors"]), Combat.recommended_power("lesser", false), go.bind(str(lesser["id"]), false), ""],
		["Greater Rift", "%d floors" % int(greater["floors"]), Combat.recommended_power("greater", false), go.bind(str(greater["id"]), false),
			"" if unlocked else "Seal %d more rift(s) to unlock (%d/3)" % [3 - GameState.rifts_sealed, GameState.rifts_sealed]],
		["Endless Rift", "Scales every cycle · best cycle %d" % GameState.best_endless_cycle, Combat.recommended_power("endless", true), go.bind("endless", true), ""],
	]
	for cd in card_defs:
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
			var b := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], "Assemble party", cd[3])
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			cv.add_child(b)
		card.add_child(cv)
		cards.add_child(card)
	v.add_child(cards)


func _render_rift_map_hub(v: VBoxContainer) -> void:
	v.add_child(_label("Rift Map", 20))
	v.add_child(_wrap_label("Rifts open at random ranks and stay for a limited time. Leave one unaddressed and its threat spills out as a forced fight next time you're back at the Terminal.", 12, true))

	var scene_size := Vector2(700, 200)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size
	scene.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var bg := TextureRect.new()
	bg.texture = load(GameData.RIFTMAP_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)

	var map_scale := Vector2(scene_size.x / 320.0, scene_size.y / 200.0)
	var now := int(Time.get_unix_time_from_system() * 1000)
	var icon_size := 32.0
	var best := _best_party_power()
	# The map only carries a numbered marker per rift (captions here used to
	# pile on top of each other); the details live in the list below it.
	var rows := _vbox(6)
	var n := 0
	for i in GameState.rift_map.size():
		var slot: Dictionary = GameState.rift_map[i]
		if slot.is_empty():
			continue
		n += 1
		var rank := str(slot.get("rank", "F"))
		var remain_s: int = max(0, int(slot.get("expires_at", 0)) - now) / 1000
		var enter := func(idx=i, r=rank):
			pending_party.clear()
			pending_relic_options.clear()
			pending_relic_choice = -1
			_pending_rift_rank = r
			_pending_map_slot_idx = idx
			screen = "party_assembly"
			render()
		var hotspot := _camp_hotspot(GameData.CAMP_HUB_ICON_PATH["rift"], icon_size, "", enter)
		var marker: Vector2 = RIFT_MAP_MARKER_POS[i % RIFT_MAP_MARKER_POS.size()]
		hotspot.position = Vector2(marker.x * map_scale.x, marker.y * map_scale.y) - Vector2(icon_size, icon_size) / 2.0
		(hotspot.get_child(0) as Control).tooltip_text = "Rank %s rift" % rank
		scene.add_child(hotspot)
		var num := _count_badge(str(n), "Rank %s rift" % rank)
		num.position = hotspot.position + Vector2(icon_size - 10, -8)
		scene.add_child(num)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var row_badge := _count_badge(str(n), "")
		row_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row_badge.custom_minimum_size.x = 24
		row.add_child(row_badge)
		var rl := _label("Rank %s" % rank, 15)
		rl.add_theme_color_override("font_color", Palette.rank_color(rank))
		rl.custom_minimum_size.x = 76
		row.add_child(rl)
		var tl := _label("closes in %d:%02d" % [remain_s / 60, remain_s % 60], 13, true)
		tl.custom_minimum_size.x = 120
		tl.tooltip_text = "Real time. An unaddressed rift spills out as a forced fight."
		row.add_child(tl)
		var bounty: Dictionary = slot.get("bounty", {})
		var bl := _label("Bounty +%dc, +%d Rep" % [int(bounty.get("coins", 0)), int(bounty.get("reputation", 0))] if not bounty.is_empty() else "", 13)
		bl.add_theme_color_override("font_color", Palette.COINS)
		bl.custom_minimum_size.x = 160
		row.add_child(bl)
		var pr := _power_readout(best, Combat.recommended_power("lesser", false, rank), "Your best")
		pr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(pr)
		row.add_child(_icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], "Enter", enter))
		rows.add_child(row)

	v.add_child(scene)
	if n == 0:
		v.add_child(_label("No rifts are open right now — new ones appear over time.", 13, true))
	v.add_child(rows)

	if not GameState.pending_riftbreak_ranks.is_empty():
		v.add_child(_hsep())
		v.add_child(_label("A Riftbreak is looming — %d unaddressed rift(s) will spill out next time you return to the Terminal." % GameState.pending_riftbreak_ranks.size(), 12, true))


# ---------------- Party Assembly ----------------
func _render_party_assembly(v: VBoxContainer) -> void:
	v.add_child(_label("Assemble Party (up to 4 + the Champion)", 20))
	var champ := GameState.ensure_champion()
	# Formation slots (Darkest Dungeon style): the party sits in a Front and a
	# Back row. Drag a portrait into a row (from the roster below, or between
	# rows), or use Add/Move/Remove. The front row draws ~3x the attacks; each
	# role has a natural row with its own bonus (GameData.ROLE_POSITION).
	var lineup: Array[Hero] = [champ]
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
			return hid2 == champ.id or pending_party.has(hid2) or pending_party.size() < 4
		zone.on_drop = func(data, r=row_id) -> void:
			var hid2: String = str(data.get("hero_id", ""))
			if hid2 != champ.id and not pending_party.has(hid2):
				pending_party.append(hid2)
			GameState.set_hero_formation(hid2, r)
			render()
		var zv := _vbox(6)
		zv.mouse_filter = Control.MOUSE_FILTER_PASS
		var in_row: Array = lineup.filter(func(x): return x.formation == row_id)
		zv.add_child(_label("%s row (%d) — %s" % [row_id.capitalize(), in_row.size(),
			"takes most of the enemy's attacks" if row_id == "front" else "attacked far less often"], 13))
		var cards := HFlowContainer.new()
		cards.add_theme_constant_override("h_separation", 8)
		cards.add_theme_constant_override("v_separation", 8)
		cards.mouse_filter = Control.MOUSE_FILTER_PASS
		for ph in in_row:
			cards.add_child(_party_card(ph, ph == champ, true))
		if in_row.is_empty():
			cards.add_child(_label("Drag a hero here", 11, true))
		zv.add_child(cards)
		zone.add_child(zv)
		v.add_child(zone)

	var bench: Array = GameState.heroes.filter(func(x): return not pending_party.has(x.id))
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes yet — recruit some from the Guild Terminal first."))
	elif not bench.is_empty():
		v.add_child(_label("Roster — drag into a row, or Add (joins their natural row)", 12, true))
		var bench_flow := HFlowContainer.new()
		bench_flow.add_theme_constant_override("h_separation", 8)
		bench_flow.add_theme_constant_override("v_separation", 8)
		for bh in bench:
			bench_flow.add_child(_party_card(bh, false, false))
		v.add_child(bench_flow)

	# Surface any Hero Bond among the currently-picked heroes (+ the Champion,
	# who always joins) so it's discoverable while assembling a party, not
	# just a silent combat bonus.
	var picked_pool_ids := {champ.pool_id: true}
	for h in GameState.heroes:
		if pending_party.has(h.id):
			picked_pool_ids[h.pool_id] = true
	var active_bonds: Array[String] = []
	for bond in GameData.HERO_BONDS:
		if picked_pool_ids.has(bond["a"]) and picked_pool_ids.has(bond["b"]):
			active_bonds.append(str(bond["name"]))
	if not active_bonds.is_empty():
		v.add_child(_label("Bond active: %s" % ", ".join(active_bonds), 12, true))

	# Party-kind synergy preview (Resonance/Eclectic) — computed here from
	# pending_party rather than GameState.party_resonance_bonus(), since that
	# reads the already-started run and this screen runs BEFORE the run
	# exists. Same rule, just previewed off the picks-in-progress.
	var picked_kind_counts := {}
	for h2 in GameState.heroes:
		if pending_party.has(h2.id):
			var cls2 := GameData.find_class(h2.pool_id)
			if not cls2.is_empty():
				var k2: String = cls2.get("kind", "")
				picked_kind_counts[k2] = int(picked_kind_counts.get(k2, 0)) + 1
	var resonant_kinds: Array[String] = []
	for k2 in picked_kind_counts:
		if int(picked_kind_counts[k2]) >= 2:
			resonant_kinds.append(k2)
	if not resonant_kinds.is_empty():
		var kind_bonuses: Array[String] = []
		for rk in resonant_kinds:
			kind_bonuses.append(Combat.describe_skill(rk, GameData.PARTY_RESONANCE_BONUS))
		v.add_child(_label("Resonance active - shared builds reinforce each other (%s)" % ", ".join(kind_bonuses), 12, true))
	elif picked_kind_counts.size() >= 3:
		v.add_child(_label("Eclectic active - a fully varied party (+%s to everything)" % Combat.describe_skill("dmg_pct", GameData.PARTY_ECLECTIC_BONUS), 12, true))

	v.add_child(_hsep())
	var choice_count := GameState.relic_choice_count()
	if choice_count > 0:
		v.add_child(_label("Starting Relic (pick one, optional)"))
		if pending_relic_options.is_empty():
			# S-rank+ mapped rifts carry a "relic_rarity_floor_down" modifier —
			# it suppresses Guild Management's inherited_power() floor-raise
			# (which normally bumps a rolled Common up to Rare) for this
			# starting-relic roll specifically, so an S+ rift's starting pick
			# can't lean on that safety net the way a normal run's can.
			var floor_suppressed: bool = _pending_rift_rank != "" and bool(GameData.RIFT_RANK_MODIFIERS.get(_pending_rift_rank, {}).get("relic_rarity_floor_down", 0))
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
		v.add_child(_info_row("%s (%s) — %s" % [r.name, r.type, r.desc()], 14, [], rb))

	if not GameState.consumables.is_empty():
		v.add_child(_hsep())
		v.add_child(_label("Field Incense (pick one, optional) — lasts the whole rift"))
		for c in GameState.consumables:
			var cid: String = str(c["id"])
			var def := GameData.find_incense(str(c["incense_id"]))
			var ib := CheckButton.new()
			ib.button_pressed = pending_incense_id == cid
			ib.toggled.connect(func(on: bool, id=cid):
				pending_incense_id = id if on else ""
				render()
			)
			v.add_child(_info_row("%s — %s" % [def["name"], def["desc"]], 14, [], ib))

	v.add_child(_hsep())
	if _pending_rift_rank == "":
		var hc_toggle := CheckButton.new()
		hc_toggle.text = "Hardcore Mode — ×1.5 rewards, a loss removes your heroes for good"
		hc_toggle.button_pressed = _pending_hardcore
		hc_toggle.toggled.connect(func(on: bool):
			_pending_hardcore = on
			render()
		)
		v.add_child(hc_toggle)
	else:
		v.add_child(_label("Rift Rank %s — Hardcore Mode is retired from mapped rifts." % _pending_rift_rank, 12, true))

	v.add_child(_hsep())
	var going: Array = [champ]
	for h in GameState.heroes:
		if pending_party.has(h.id):
			going.append(h)
	var map_run := _pending_map_slot_idx >= 0
	v.add_child(_power_readout(Combat.party_power(going),
		Combat.recommended_power("lesser" if map_run else _pending_diff_id, _pending_endless and not map_run, _pending_rift_rank)))
	v.add_child(_icon_domain_button("violet", GameData.CAMP_HUB_ICON_PATH["rift"], "Enter the Rift", func():
		if pending_party.is_empty():
			return
		var chosen: Relic = pending_relic_options[pending_relic_choice] if pending_relic_choice >= 0 else null
		var ids: Array[String] = []
		ids.assign(pending_party)
		if pending_incense_id != "":
			GameState.use_incense(pending_incense_id)
			pending_incense_id = ""
		if _pending_rift_rank != "":
			GameState.start_map_rift(_pending_map_slot_idx, ids, chosen)
		else:
			GameState.start_run(_pending_diff_id, ids, chosen, _pending_hardcore, _pending_endless)
		pending_relic_options.clear()
		pending_relic_choice = -1
		_pending_hardcore = false
		_pending_rift_rank = ""
		_pending_map_slot_idx = -1
		screen = "rift_run"
		render()
		_play_rift_entry_flash()
	))


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
		screen = "terminal" if GameState.run.is_empty() else "rift_run"
	else:
		pending_crest = 1 + randi() % GameData.CREST_PATH.size()
		screen = "onboard"
	render()


func _render_settings(v: VBoxContainer) -> void:
	v.add_child(_label("Settings", 20))

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

	v.add_child(_hsep())
	v.add_child(_label("Display", 15))
	# Scales every piece of UI (text, buttons, art) together — the game's
	# fixed-size layouts stay intact, just bigger or smaller.
	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 6)
	scale_row.add_child(_label("Text & UI size", 13))
	for sc in [0.9, 1.0, 1.15, 1.3]:
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
	else:
		var res_opts: Array = GameData.RESOLUTION_OPTIONS
		var res_idx := GameState.resolution_idx
		v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["sort"], "Resolution: %s" % str(res_opts[res_idx]["label"]), func():
			var next_idx: int = (res_idx + 1) % res_opts.size()
			GameState.resolution_idx = next_idx
			GameState.save_settings()
			_apply_resolution(next_idx)
			render()
		))

	v.add_child(_hsep())
	v.add_child(_label("Save Slots", 15))
	_render_slot_list(v)


## Shared by Settings' "Save Slots" section and the title screen's Load Game
## list — same slot rows (Play/Delete), just embedded in two different
## screens, so the delayed delete-confirm timeout's render() gate has to
## check "whichever of them is still showing", not one hardcoded screen name.
func _render_slot_list(v: VBoxContainer) -> void:
	for slot in GameState.SLOT_COUNT:
		var summary := GameState.slot_summary(slot)
		var is_active := slot == GameState.active_slot
		var is_empty: bool = summary.get("empty", true)
		var text := "Slot %d — Empty" % (slot + 1)
		if not is_empty:
			var sealed := int(summary.get("rifts_sealed", 0))
			text = "Slot %d — %s (%d rift%s sealed)" % [slot + 1, str(summary.get("guild_name", "")), sealed, "" if sealed == 1 else "s"]
		if is_active:
			text += "  (Active)"
		var actions: Array[Control] = []
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
	var downed := h.is_downed()
	var portrait := GameData.portrait_for_hero(h.cls_id, h.pool_id)
	if portrait != "":
		var icon := DragIcon.new()
		var tex: Texture2D = _icon_trimmed(portrait, 44).texture
		icon.texture = tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(44, 44)
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
	names.add_child(_label(("Champion: " if is_champ else "") + h.name.split(" the ")[0], 12))
	names.add_child(_label("Lv%d %s · %d/%d HP%s" % [h.level, GameData.hero_role(h).capitalize(), h.hp, Combat.max_hp(h), " · downed" if downed else ""], 10, true))
	var power_line := "Power %d" % Combat.power_of(h)
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
		actions.add_child(_button("Move %s" % other, func(id=h.id, r=other):
			GameState.set_hero_formation(id, r)
			render()
		))
		if not is_champ:
			actions.add_child(_button("Remove", func(id=h.id):
				pending_party.erase(id)
				render()
			))
	elif not downed:
		var add_btn := _button("Add", func(id=h.id, hero=h):
			if pending_party.size() >= 4:
				return
			pending_party.append(id)
			GameState.set_hero_formation(id, str(GameData.ROLE_POSITION.get(GameData.hero_role(hero), {}).get("row", hero.formation)))
			render()
		)
		add_btn.disabled = pending_party.size() >= 4
		actions.add_child(add_btn)
	cv.add_child(actions)
	card.add_child(cv)
	return card
