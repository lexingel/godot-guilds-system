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
	# Deliberately doesn't load_save()/reset() or route past "title" here —
	# every boot lands on the title screen now (New Game/Load Game/Credits/
	# Quit) regardless of whether the active slot has a guild in it, matching
	# the reference title screen rather than auto-resuming. New Game and Load
	# Game both route through _switch_slot(), which is what actually loads
	# (or resets) a slot's state once the player picks one.
	GameState.state_changed.connect(render)
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


func render() -> void:
	GameState.resolve_recovery()
	GameState.resolve_rift_map()
	GameState.resolve_guild_board()
	var newly_claimed := GameState.check_milestones()
	if not newly_claimed.is_empty():
		var m = GameData.MILESTONES.filter(func(x): return str(x["id"]) == newly_claimed[0])[0]
		_flavor_toast = "Milestone reached: %s" % str(m["label"])
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
	if not _s_rank_celebration.is_empty():
		outer.add_child(_render_s_rank_celebration(_s_rank_celebration))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	scroll.set_deferred("scroll_vertical", _last_scroll_y)
	var v := _vbox(14)
	# Rift Run gets extra width for the combat arena (background + positioned
	# sprites) sitting alongside the log/action column, and the camp hub
	# needs room for its 6-building scene — every other screen stays at the
	# original column width.
	var is_camp_scene := screen == "terminal" and term_tab == "camp" and hub_cluster == ""
	v.custom_minimum_size = Vector2(940 if screen == "rift_run" else (800 if is_camp_scene else 760), 0)
	scroll.add_child(v)

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
	row.add_theme_constant_override("separation", 16)
	row.add_child(_icon(GameData.CREST_PATH[GameState.guild_crest - 1], 24))
	var name_lbl := _label(GameState.guild_name, 16)
	name_lbl.add_theme_font_override("font", DISPLAY_FONT)
	row.add_child(name_lbl)
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
		stat_row.add_child(_label(str(entry[1]), 16))
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
	if breadcrumb != "":
		bar_v.add_child(_label(breadcrumb, 12, true))
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

	var bg := TextureRect.new()
	bg.texture = load(GameData.RIFTHALL_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)

	var camp_scale := Vector2(700.0 / 320.0, 340.0 / 200.0)
	var lesser: Dictionary = GameData.DIFFICULTIES[0]
	var gate_entries := [
		["%s — Floors %d · Rec. Power %d" % [lesser["name"], lesser["floors"], lesser["rec_power"]],
			Rect2(0, 0, 230, 340), Rect2(18, 65, 68, 98),
			func(): pending_party.clear(); screen = "party_assembly"; _pending_diff_id = str(lesser["id"]); _pending_endless = false; render()],
		["Endless Rift — scales forever. Best cycle: %d" % GameState.best_endless_cycle,
			Rect2(230, 0, 240, 340), Rect2(110, 20, 97, 130),
			func(): pending_party.clear(); screen = "party_assembly"; _pending_diff_id = "endless"; _pending_endless = true; render()],
	]
	# The chained, rubble-blocked archway to the right stays inert until
	# GameState.greater_rift_unlocked() (earned by sealing rifts, not bought
	# with Guild Management currency) — no hotspot at all while locked, same
	# as this gate's behavior before Greater Rift existed.
	if GameState.greater_rift_unlocked():
		var greater: Dictionary = GameData.DIFFICULTIES[1]
		gate_entries.append(["%s — Floors %d · Rec. Power %d" % [greater["name"], greater["floors"], greater["rec_power"]],
			Rect2(470, 0, 230, 340), Rect2(230, 30, 78, 140),
			func(): pending_party.clear(); screen = "party_assembly"; _pending_diff_id = str(greater["id"]); _pending_endless = false; render()])
	for entry in gate_entries:
		var label_text: String = entry[0]
		var hit_rect: Rect2 = entry[1]
		var native_rect: Rect2 = entry[2]
		var cb: Callable = entry[3]
		var glow_rect := Rect2(
			native_rect.position.x * camp_scale.x, native_rect.position.y * camp_scale.y,
			native_rect.size.x * camp_scale.x, native_rect.size.y * camp_scale.y
		)
		var hotspot := _camp_area_hotspot(hit_rect, glow_rect, label_text, cb)
		hotspot.position = hit_rect.position
		scene.add_child(hotspot)

	v.add_child(scene)
	var best := _best_party_power()
	v.add_child(_power_readout(best, Combat.recommended_power("lesser", false), "Lesser Rift — your strongest party"))
	if GameState.greater_rift_unlocked():
		v.add_child(_power_readout(best, Combat.recommended_power("greater", false), "Greater Rift — your strongest party"))
	v.add_child(_power_readout(best, Combat.recommended_power("endless", true), "Endless Rift (cycle 1) — your strongest party"))
	if not GameState.greater_rift_unlocked():
		v.add_child(_label("Greater Rift — Seal %d more Rift(s) to unlock (%d/3)" % [3 - GameState.rifts_sealed, GameState.rifts_sealed], 12))
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back to Terminal", func():
		screen = "terminal"
		render()
	))


func _render_rift_map_hub(v: VBoxContainer) -> void:
	v.add_child(_label("Rift Map", 20))
	v.add_child(_label("Rifts open at random ranks and stay for a limited time. Leave one unaddressed and its threat spills out as a forced fight next time you're back at the Terminal.", 12, true))

	var scene_size := Vector2(700, 200)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size

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
	for i in GameState.rift_map.size():
		var slot: Dictionary = GameState.rift_map[i]
		if slot.is_empty():
			continue
		var rank := str(slot.get("rank", "F"))
		var remain_ms: int = max(0, int(slot.get("expires_at", 0)) - now)
		var remain_s := remain_ms / 1000
		var mm := remain_s / 60
		var ss := remain_s % 60
		var caption := "Rank %s — %02d:%02d" % [rank, mm, ss]
		var bounty: Dictionary = slot.get("bounty", {})
		if not bounty.is_empty():
			caption += "\n+%dc, +%d Rep" % [int(bounty.get("coins", 0)), int(bounty.get("reputation", 0))]

		var hotspot := _camp_hotspot(GameData.CAMP_HUB_ICON_PATH["rift"], icon_size, caption, func(idx=i, r=rank):
			pending_party.clear()
			pending_relic_options.clear()
			pending_relic_choice = -1
			_pending_rift_rank = r
			_pending_map_slot_idx = idx
			screen = "party_assembly"
			render()
		)
		var marker: Vector2 = RIFT_MAP_MARKER_POS[i % RIFT_MAP_MARKER_POS.size()]
		hotspot.position = Vector2(marker.x * map_scale.x, marker.y * map_scale.y) - Vector2(icon_size, icon_size) / 2.0
		var rank_label := hotspot.get_child(1) as Label
		rank_label.add_theme_color_override("font_color", Palette.rank_color(rank))
		scene.add_child(hotspot)

	v.add_child(scene)

	if not GameState.pending_riftbreak_ranks.is_empty():
		v.add_child(_hsep())
		v.add_child(_label("A Riftbreak is looming — %d unaddressed rift(s) will spill out next time you return to the Terminal." % GameState.pending_riftbreak_ranks.size(), 12, true))

	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back to Terminal", func():
		screen = "terminal"
		render()
	))


# ---------------- Party Assembly ----------------
func _render_party_assembly(v: VBoxContainer) -> void:
	v.add_child(_label("Assemble Party (pick up to 4)", 20))
	var champ := GameState.ensure_champion()
	var champ_row := HBoxContainer.new()
	var champ_portrait := GameData.portrait_for_hero(champ.cls_id, champ.pool_id)
	if champ_portrait != "":
		champ_row.add_child(_icon(champ_portrait, 48))
	champ_row.add_child(_label("Champion: %s — Rank %s (always joins) · %d/%d HP" % [champ.name, champ.rank, champ.hp, Combat.max_hp(champ)], 13))
	champ_row.add_child(_icon_button("res://assets/skills/shield_orange.png" if champ.formation != "back" else "res://assets/skills/shield_basic.png", "Back" if champ.formation != "back" else "Front", func(id=champ.id, f=champ.formation):
		GameState.set_hero_formation(id, "back" if f != "back" else "front")
		render()
	))
	champ_row.add_child(_label(_position_text(champ), 11, true))
	v.add_child(champ_row)
	for h in GameState.heroes:
		var row := HBoxContainer.new()
		var picked := pending_party.has(h.id)
		var cb := CheckBox.new()
		cb.button_pressed = picked
		cb.disabled = h.is_downed()
		cb.toggled.connect(func(on: bool):
			if on and pending_party.size() < 4:
				pending_party.append(h.id)
			else:
				pending_party.erase(h.id)
			render()
		)
		row.add_child(cb)
		var portrait_path := GameData.portrait_for_hero(h.cls_id, h.pool_id)
		if portrait_path != "":
			row.add_child(_icon_trimmed(portrait_path, 40))
		var status := " (downed)" if h.is_downed() else ""
		row.add_child(_label("%s — Lv%d %s · %d/%d HP%s" % [h.name, h.level, h.cls_id.capitalize(), h.hp, Combat.max_hp(h), status]))
		row.add_child(_icon_button("res://assets/skills/shield_orange.png" if h.formation != "back" else "res://assets/skills/shield_basic.png", "Back" if h.formation != "back" else "Front", func(id=h.id, f=h.formation):
			GameState.set_hero_formation(id, "back" if f != "back" else "front")
			render()
		))
		row.add_child(_label(_position_text(h), 11, true))
		v.add_child(row)
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes yet — recruit some from the Guild Terminal first."))

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
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back", func():
		screen = "rift_map" if _pending_rift_rank != "" else "rift_hall"
		_pending_rift_rank = ""
		_pending_map_slot_idx = -1
		render()
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

	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back", func():
		screen = _pre_settings_screen
		render()
	))


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
