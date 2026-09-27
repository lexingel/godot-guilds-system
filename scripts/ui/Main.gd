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
	GameState.state_changed.connect(render)
	if OS.has_feature("web"):
		# Ask the browser not to evict the saves when it runs low on space.
		JavaScriptBridge.eval("navigator.storage && navigator.storage.persist && navigator.storage.persist();", true)
	if OS.get_cmdline_user_args().has("bench-survivors") or (OS.has_feature("web") and str(JavaScriptBridge.eval("location.search", true)).contains("bench=survivors")):
		_start_bench.call_deferred()
	# Portrait pop-ups live on their own CanvasLayer so render()'s
	# _clear_root() never wipes one mid-fade.
	var toast_layer := CanvasLayer.new()
	toast_layer.layer = 50
	add_child(toast_layer)
	_toast_box = VBoxContainer.new()
	_toast_box.add_theme_constant_override("separation", 6)
	# Bottom-right, stacking upward — clear of the header and the quick-travel bar.
	_toast_box.anchor_left = 1.0
	_toast_box.anchor_right = 1.0
	_toast_box.anchor_top = 1.0
	_toast_box.anchor_bottom = 1.0
	_toast_box.offset_left = -300
	_toast_box.offset_right = -12
	_toast_box.offset_top = -400
	_toast_box.offset_bottom = -12
	_toast_box.alignment = BoxContainer.ALIGNMENT_END
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


## A portrait window (a phone held upright) lays the UI out on a 760-wide
## canvas instead of 1280, so it scales up ~1.7x instead of shrinking to a
## third; screens that sit side by side on desktop stack there (see _narrow).
## Returns whether the canvas size changed.
func _fit_to_window() -> bool:
	var win := get_tree().root
	var want := Vector2i(760, 800) if win.size.x < win.size.y * 0.9 else Vector2i(1280, 800)
	if win.content_scale_size == want:
		return false
	win.content_scale_size = want
	return true


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
	Engine.time_scale = minf(GameState.combat_speed, 3.0) if screen == "rift_run" else 1.0
	GameState.resolve_recovery()
	GameState.resolve_guild_board()
	if GameState.guild_name != "":
		if not GameState.check_feature_unlocks().is_empty():
			AudioManager.play_sfx(GameData.SFX_PATH["unlock"])
	var newly_claimed := GameState.check_milestones()
	if newly_claimed.size() == 1:
		var m = GameData.MILESTONES.filter(func(x): return str(x["id"]) == newly_claimed[0])[0]
		GameState.pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Achievement earned", "text": str(m["label"])})
	elif newly_claimed.size() > 1:
		GameState.pending_toasts.append({"cls_id": "", "pool_id": "", "title": "%d achievements earned" % newly_claimed.size(), "text": "See Records in the Guild Hall."})
	# Once, on the web, after a guild has something worth losing.
	if OS.has_feature("web") and GameState.guild_name != "" and GameState.last_export_day < 0 and GameState.rifts_sealed >= 3 and not GameState.hints_seen.has("backup_nudge"):
		GameState.hints_seen.append("backup_nudge")
		GameState.pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Back up your guild",
			"text": "It lives in this browser only. Settings > Backup > Export save keeps a copy."})
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
		if screen in ["terminal", "crafting_hall", "rift_hall"]:
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
		"party_assembly": _render_party_assembly(v)
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
		"terminal": _render_terminal(v)
	_update_screen_music()

	# A real navigation (not an in-place data refresh — see is_navigation
	# above) fades the new screen in from transparent instead of just
	# snapping into place, so moving between hubs reads as one continuous
	# world instead of a slideshow of unrelated pages.
	if not GameState.pending_stories.is_empty() and screen not in ["title", "load_game", "credits", "onboard"]:
		var card_key := "story:" + str(GameState.pending_stories[0].get("title", ""))
		if not _sfx_seen.has(card_key):
			_sfx_seen[card_key] = true
			AudioManager.play_sfx(GameData.SFX_PATH["story"])
		_story_overlay(GameState.pending_stories[0])
	if is_navigation:
		root.modulate = Color(1, 1, 1, 0)
		var fade_tw := create_tween()
		fade_tw.tween_property(root, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)


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
const TAB_TITLE := {"roster": "Heroes", "management": "Guild Management", "quests": "Guild Board", "compendium": "Codex"}


func _breadcrumb_for_screen() -> String:
	match screen:
		"rift_hall": return "Rift Hall"
		"tower": return "Tower of Trials"
		"party_assembly": return "Party Assembly"
		"rift_run" when GameState.run.has("tower"): return "Tower of Trials — Floor %d" % int(GameState.run["tower"])
		"rift_run": return "Rift Run — Floor %d/%d" % [int(GameState.run.get("pos", 0)) + 1, GameState.run.get("layers", []).size()]
		"crafting_hall": return "Crafting Hall"
		"settings": return "Settings"
		"terminal": return "Camp" if term_tab == "camp" else "Camp — %s" % TAB_TITLE.get(term_tab, term_tab.capitalize())
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
	var source_text := "is offered as a Champion!" if str(data["source"]) == "champion" else "is available to recruit!"
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
## What each header currency is for (keyed by its icon path).
var CURRENCY_TIPS := {
	GameData.CURRENCY_ICON_PATH["coins"]: "Gold — recruit and train heroes, buy from rift shops and supplies, reroll offers.",
	GameData.CURRENCY_ICON_PATH["crystals"]: "Essence — earned by fighting and sealing rifts. Evolves heroes, upgrades relics and the guild, reforges gear, resets attributes.",
	GameData.CURRENCY_ICON_PATH["reputation"]: "Renown — from rift bounties and quests. Every 20 guarantees an Epic at your next rift shop.",
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
	["Roster", "roster", [["roster", "Heroes", "Command Tent"], ["recruits", "Recruits", "Hero Recruits"], ["medical", "Medical", "Medical Tent"]]],
	["Inventory", "inventory", [["inventory", "Items", "Inventory"], ["crafting", "Crafting", "Trading Post"]]],
	["Rift Hall", "rift", [["rift", "Rift Hall", "Rift Gate"]]],
	["Guild", "management", [["management", "Manage", ""], ["ledger", "Ledger", ""], ["quests", "Quests", "Scholar's Lodge"], ["records", "Records", ""], ["memorial", "Memorial", ""]]],
	["Library", "bestiary", [["bestiary", "Bestiary", ""], ["compendium", "Codex", ""]]],
]
const NAV_FEATURE := {"crafting": "crafting", "quests": "quests", "management": "management", "inventory": "inventory", "medical": "medical", "bestiary": "bestiary"}


func _quick_nav_current() -> String:
	match screen:
		"crafting_hall": return "crafting"
		"rift_hall": return "rift"
		"terminal": return "" if term_tab == "camp" else term_tab
	return ""


func _nav_locked(id: String) -> bool:
	return NAV_FEATURE.has(id) and not GameState.feature_unlocked(NAV_FEATURE[id])


func _quick_go(id: String) -> void:
	hub_cluster = ""
	inv_category = ""
	mgmt_branch = ""
	medical_picker_bed = -1
	match id:
		"crafting": screen = "crafting_hall"
		"rift": screen = "rift_hall"
		_:
			screen = "terminal"
			term_tab = id
	render()


func _quick_nav() -> Control:
	var col := _vbox(6)
	# Wraps to two rows on the narrow (portrait) canvas.
	var bar := HFlowContainer.new()
	bar.add_theme_constant_override("h_separation", 6)
	bar.add_theme_constant_override("v_separation", 6)
	bar.alignment = FlowContainer.ALIGNMENT_CENTER
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
		b.custom_minimum_size = Vector2(88, 54)
		b.toggle_mode = true
		b.button_pressed = ids.has(current)
		b.tooltip_text = "%s  (key %s)" % [g[0], key]
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if locked:
			b.disabled = true
			b.modulate = Color(1, 1, 1, 0.45)
			b.tooltip_text = "%s — %s" % [g[0], GameData.FEATURE_UNLOCKS[NAV_FEATURE[ids[0]]]["hint"]]
		var tile := VBoxContainer.new()
		tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tile.alignment = BoxContainer.ALIGNMENT_CENTER
		tile.add_theme_constant_override("separation", 1)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := _icon(GameData.CAMP_HUB_ICON_PATH[str(g[1])], 26)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(ic)
		var nl := _label(str(g[0]), 12)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tile.add_child(nl)
		b.add_child(tile)
		if not locked:
			_combat_hotkeys[key] = go
		var kl := _label(key, 12)
		kl.add_theme_color_override("font_color", Palette.MUTED)
		kl.position = Vector2(3, 0)
		b.add_child(kl)
		for m in members:
			var badge: Array = badges.get(str(m[2]), [])
			if not badge.is_empty() and not _nav_locked(str(m[0])):
				var chip := _count_badge(str(badge[0]), str(badge[1]))
				chip.position = Vector2(70, -6)
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
				var badge: Array = badges.get(str(m[2]), [])
				if _nav_locked(sid):
					sb.disabled = true
					sb.modulate = Color(1, 1, 1, 0.45)
					sb.tooltip_text = GameData.FEATURE_UNLOCKS[NAV_FEATURE[sid]]["hint"]
				elif not badge.is_empty():
					sb.text = "%s  %s" % [m[1], badge[0]]
					sb.tooltip_text = str(badge[1])
				sub.add_child(sb)
			col.add_child(sub)
	return col


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
		"rift_hall", "crafting_hall":
			return [to_camp, "Camp"]
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
			const NAMES := {"terminal": "Camp", "rift_run": "Rift", "rift_hall": "Rift Hall", "tower": "Tower",
				"party_assembly": "Party Assembly", "crafting_hall": "Crafting Hall"}
			return [func(): screen = _pre_settings_screen; render(), NAMES.get(_pre_settings_screen, "Back")]
	return []


## Content column width: combat, the camp scene and the two-pane screens
## use the window's width; text-heavy screens stay at a readable measure.
func _column_width() -> float:
	var avail: float = get_viewport().get_visible_rect().size.x - 64.0
	if screen == "rift_run":
		return _battle_width()
	if screen == "terminal" and ((term_tab == "camp" and hub_cluster == "") or term_tab in ["roster", "inventory", "bestiary"]):
		return clampf(avail, minf(760.0, avail), 1180.0)
	return clampf(avail, minf(700.0, avail), 860.0)


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
	if GameState.tower_title() != "" and not _narrow():
		var title_lbl := _label(GameState.tower_title(), 12)
		title_lbl.add_theme_color_override("font_color", Palette.RANK_S)
		title_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title_lbl.tooltip_text = "Guild title — Tower of Trials, best floor %d" % GameState.tower_best
		title_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(title_lbl)
	if breadcrumb != "" and not _narrow():
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
		[GameData.CURRENCY_ICON_PATH["reputation"], GameState.reputation],
	]:
		var stat_row := HBoxContainer.new()
		stat_row.add_child(_icon(entry[0], 18))
		stat_row.add_child(_count_label(str(entry[0]), int(entry[1]), 16))
		var tile := PanelContainer.new()
		tile.theme_type_variation = &"StatTileEmber"
		tile.tooltip_text = CURRENCY_TIPS.get(str(entry[0]), "")
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
	_render_save_backup(v)
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
## The current act: its foe, objectives with progress, and the finale — open
## once every objective is met.
func _render_campaign_panel(v: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanelEmber"
	var cv := _vbox(6)
	if GameState.campaign_done():
		cv.add_child(_label("The campaign is complete", 16))
		cv.add_child(_wrap_label("The Ashen Crown is shattered. Rifts still open — push the Endless Rift, climb the rift ladder to SSS, and take on the Guild Board.", 12, true))
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
	var t := _label("Act %s — %s" % [GameState._roman(int(act["act"])), act["name"]], 17)
	t.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	hv.add_child(t)
	hv.add_child(_label("Foe: %s" % act["foe"], 12, true))
	head.add_child(hv)
	cv.add_child(head)
	for o in act["objectives"]:
		var met := GameState.campaign_objective_met(o)
		var prog := "" if str(o["type"]) == "map_rank" else " (%d/%d)" % [min(GameState.campaign_objective_progress(o), int(o["target"])), int(o["target"])]
		var ol := _label("%s %s%s" % ["✓" if met else "○", o["label"], prog], 13)
		ol.add_theme_color_override("font_color", Palette.RANK_E if met else Palette.TEXT)
		cv.add_child(ol)
	var ready := GameState.finale_ready()
	var fb := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], "Face the finale: %s" % act["finale"], func():
		pending_party.clear()
		screen = "party_assembly"
		_pending_diff_id = str(act["tier"])
		_pending_rift_rank = ""
		_pending_endless = false
		_pending_finale = true
		render()
	)
	fb.disabled = not ready
	fb.tooltip_text = "Recommended power %d" % GameState.finale_recommended_power() if ready else "Complete every objective above first"
	fb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cv.add_child(fb)
	panel.add_child(cv)
	v.add_child(panel)


func _render_rift_hall(v: VBoxContainer) -> void:
	v.add_child(_label("Rift Hall", 20))
	_coach(v, "rift_hall", "Choosing a rift", "Rifts come in ranks, F to SSS. Seal a rank to open the next. The readout compares your best party's power with what the rift expects — Deadly, Risky, Even or Favored. Your very first rift is a shorter training run.")
	if _ladder_pick == "" or GameState.ladder_rank_lock(_ladder_pick) != "":
		_ladder_pick = GameState.highest_open_rank()

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
	var unlocked := GameState.greater_rift_unlocked()
	var go := func(rank_id: String, endless: bool):
		pending_party.clear()
		pending_relic_options.clear()
		pending_relic_choice = -1
		_pending_tower = false
		_pending_daily = false
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
	var gate_entries := [
		["Rank %s Rift" % lesser_pick, Rect2(0, 0, 230, 340), Rect2(18, 65, 68, 98), go.bind(lesser_pick, false)],
	]
	if endless_open:
		gate_entries.append(["Endless Rift", Rect2(230, 0, 240, 340), Rect2(110, 20, 97, 130), go.bind("", true)])
	if unlocked:
		var greater_pick: String = _ladder_pick if str(GameData.find_rift_rank(_ladder_pick)["base"]) == "greater" else best_of.call("greater")
		gate_entries.append(["Rank %s Rift" % greater_pick, Rect2(470, 0, 230, 340), Rect2(230, 30, 78, 140), go.bind(greater_pick, false)])
	for entry in gate_entries:
		var native_rect: Rect2 = entry[2]
		var glow_rect := Rect2(native_rect.position * camp_scale, native_rect.size * camp_scale)
		var hotspot := _camp_area_hotspot(entry[1], glow_rect, str(entry[0]), entry[3])
		hotspot.position = (entry[1] as Rect2).position
		scene.add_child(hotspot)
	if not unlocked:
		var lock_plaque := _camp_plaque("Ranks C-SSS — locked")
		lock_plaque.position = Vector2(470 + (230 - lock_plaque.size.x) * 0.5, 340 - lock_plaque.size.y - 6)
		scene.add_child(lock_plaque)
	if not endless_open:
		var endless_plaque := _camp_plaque("Endless Rift — locked")
		endless_plaque.position = Vector2(230 + (240 - endless_plaque.size.x) * 0.5, 340 - endless_plaque.size.y - 6)
		scene.add_child(endless_plaque)
	v.add_child(scene)

	_render_campaign_panel(v)

	var best := _best_party_power()
	v.add_child(_ladder_card(best, go))

	# The other modes: what each is, how your strongest party measures up,
	# and the button to go.
	var cards := HFlowContainer.new()
	cards.alignment = FlowContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("h_separation", 10)
	cards.add_theme_constant_override("v_separation", 10)
	var card_defs := [
		["Endless Rift", "Steer your party through endless waves · best %d:%02d" % [GameState.best_endless_time / 60, GameState.best_endless_time % 60], Combat.recommended_power("endless"), go.bind("", true),
			"" if endless_open else "Opens when you complete Act II"],
		["Tower of Trials", "100 fixed floors · best floor %d" % GameState.tower_best, GameState.tower_recommended_power(maxi(1, GameState.tower_next_floor())),
			func(): screen = "tower"; render(), "" if GameState.feature_unlocked("tower") else "Opens when you complete Act I", "Enter the Tower"],
		_daily_card_def(),
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
			var b := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], str(cd[5]) if cd.size() > 5 else "Assemble party", cd[3])
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			cv.add_child(b)
		card.add_child(cv)
		cards.add_child(card)
	v.add_child(cards)


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
	for r in GameData.RIFT_RANKS:
		var rid := str(r["id"])
		var lock := GameState.ladder_rank_lock(rid)
		var b := _button(rid, func(): _ladder_pick = rid; render())
		b.custom_minimum_size = Vector2(52, 40)
		b.toggle_mode = true
		b.button_pressed = rid == _ladder_pick
		b.add_theme_color_override("font_color", Palette.rank_color(rid))
		if lock != "":
			b.disabled = true
			b.modulate = Color(1, 1, 1, 0.45)
			b.tooltip_text = "Rank %s — %s" % [rid, lock]
		elif GameState.best_rift_rank_sealed >= GameData.rift_rank_index(rid):
			b.tooltip_text = "Rank %s — sealed" % rid
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
			rules.append(str(GameData.RIFT_RANK_RULE_TEXT[k]))
	var t := _label("Rank %s · %d floors" % [_ladder_pick, int(base["floors"])], 15)
	t.add_theme_color_override("font_color", Palette.rank_color(_ladder_pick))
	cv.add_child(t)
	var foes := "Foes: base" if float(rank["hp"]) == 1.0 else "Foes: ×%s health, ×%s damage" % [str(rank["hp"]), str(rank["dmg"])]
	cv.add_child(_wrap_label("%s%s · Rewards ×%s%s" % [base["name"] + " · ", foes, str(rank["reward"]), (" · " + ", ".join(rules)) if not rules.is_empty() else ""], 12, true))
	var pr := _power_readout(best, Combat.recommended_power("", _ladder_pick), "Your best party")
	pr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(pr)
	var b := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], "Assemble party", go.bind(_ladder_pick, false))
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cv.add_child(b)
	card.add_child(cv)
	return card


# ---------------- Tower of Trials ----------------
## The next floor (its fight, rules, reward and the party's odds), the climb
## around it, and the ten guardians with their relics.
func _render_tower(v: VBoxContainer) -> void:
	v.add_child(_label("Tower of Trials", 20))
	var title := GameState.tower_title()
	v.add_child(_label("Best floor %d / %d%s" % [GameState.tower_best, GameData.TOWER_FLOORS, ("  ·  " + title) if title != "" else ""], 13, true))
	_coach(v, "tower", "The Tower", "Every floor is always the same fight — if you lose, study it, change your party and come back. Heroes fight at full HP and leave exactly as they came, so a loss costs nothing. Each floor pays the first time you clear it; every 10th floor is a guardian with its own relic.")
	var f := GameState.tower_next_floor()
	if f == 0:
		var days_left := 7 - int(fmod(Time.get_unix_time_from_system(), 604800.0) / 86400.0)
		var done := _wrap_label("You've cleared this week's ladder. Floors %d–%d reshuffle their rules in %d day%s." % [GameData.TOWER_WEEKLY_FROM, GameData.TOWER_FLOORS, days_left, "" if days_left == 1 else "s"], 14)
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
		var fl := _label("Floor %d" % int(gf), 13, true)
		fl.custom_minimum_size.x = 64
		row.add_child(fl)
		var nm := _label(str(boss["name"]), 13)
		nm.custom_minimum_size.x = 170
		row.add_child(nm)
		var rl := _label(("✓ " if done_g else "") + str(rdef["name"]), 13)
		rl.add_theme_color_override("font_color", Palette.RANK_E if done_g else Palette.RANK_S)
		rl.tooltip_text = str(rdef["desc"])
		rl.mouse_filter = Control.MOUSE_FILTER_STOP
		rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(rl)
		v.add_child(row)
	var titles := GameData.TOWER_TITLES.map(func(e): return ("✓ " if GameState.tower_best >= int(e[0]) else "") + "%s (floor %d)" % [e[1], int(e[0])])
	v.add_child(_wrap_label("Titles: " + ", ".join(titles), 12, true))


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
	var t := _label("Floor %d" % f, 22)
	t.add_theme_font_override("font", DISPLAY_FONT)
	t.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if not boss.is_empty() else Palette.TEXT)
	hv.add_child(t)
	var kind_name: String = {"boss": "Guardian: " + str(boss.get("name", "")), "elite": "Elite fight", "combat": "Fight"}[str(info["kind"])]
	hv.add_child(_label("%s  ·  %s%s" % [kind_name, GameData.BIOMES[str(info["biome"])]["name"], "  ·  weekly ladder" if info["weekly"] else ""], 12, true))
	head.add_child(hv)
	cv.add_child(head)
	if not boss.is_empty():
		cv.add_child(_wrap_label(str(boss["line"]), 12, true))
		for mid in boss["mechanics"]:
			var bm: Dictionary = GameData.BOSS_MECHANICS.filter(func(x): return x["id"] == mid)[0]
			cv.add_child(_wrap_label("%s — %s" % [bm["name"], bm["desc"]], 13))
	for r in info["rules"]:
		var rl := _wrap_label("Rule · %s — %s" % [r["name"], r["desc"]], 13)
		rl.add_theme_color_override("font_color", Palette.HAZARD)
		cv.add_child(rl)
	if info["rules"].is_empty() and boss.is_empty():
		cv.add_child(_label("No special rules on this floor.", 12, true))
	var cap := int(info["party_cap"])
	var pr := _power_readout(_best_party_power(cap), GameState.tower_recommended_power(f), "Your best party")
	pr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cv.add_child(pr)
	cv.add_child(_tower_reward_line(info))
	var b := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["rift"], "Assemble party (up to %d + the Champion)" % cap, func():
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
	row.add_child(_label("First clear:" if first else "This week's re-clear:", 13))
	row.add_child(_icon(GameData.CURRENCY_ICON_PATH["coins"], 16))
	row.add_child(_label("+%d" % (int(rw["coins"]) if first else int(rw["coins"]) / 2), 13))
	row.add_child(_icon(GameData.CURRENCY_ICON_PATH["crystals"], 16))
	row.add_child(_label("+%d" % (int(rw["crystals"]) if first else int(rw["crystals"]) / 2), 13))
	var rdef: Dictionary = rw["relic"]
	if first and not rdef.is_empty():
		var rl := _label("+ %s" % rdef["name"], 13)
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
		var tip := "Floor %d — %s" % [f, str(info["boss"]["name"]) if guardian else ("Elite fight" if info["kind"] == "elite" else "Fight")]
		for r in info["rules"]:
			tip += "\n%s: %s" % [r["name"], r["desc"]]
		chip.tooltip_text = tip
		flow.add_child(chip)
	return flow


## The Daily Rift's Rift Hall card (same shape as the other card_defs rows).
func _daily_card_def() -> Array:
	var info := GameState.daily_info()
	var sub := "Today: %s · starts with %s" % [info["rule"]["name"], GameData.find_boon(str(info["boon"]))["name"]]
	if GameState.daily_streak > 0:
		sub += " · streak %d" % GameState.daily_streak
	var lock := ""
	if GameState.rifts_sealed < 1:
		lock = "Opens after you seal your first rift"
	elif not GameState.daily_available():
		lock = "Done for today. A new Daily Rift opens tomorrow (%s)." % sub.split(" · ")[0]
	return ["Daily Rift", sub, Combat.recommended_power(str(info["diff_id"])), func():
		pending_party.clear()
		_pending_daily = true
		_pending_tower = false
		_pending_finale = false
		_pending_diff_id = str(info["diff_id"])
		_pending_rift_rank = ""
		_pending_endless = false
		screen = "party_assembly"
		render(), lock, "Assemble party"]


# ---------------- Party Assembly ----------------
func _render_party_assembly(v: VBoxContainer) -> void:
	var tower_info := GameState.tower_floor_info(GameState.tower_next_floor()) if _pending_tower else {}
	if _pending_daily:
		var dinfo := GameState.daily_info()
		v.add_child(_label("Daily Rift — %s" % dinfo["rule"]["name"], 20))
		v.add_child(_wrap_label("One attempt today; every guild faces the same rift. Rule: %s Starting boon: %s (%s). Sealing it pays +%d Essence." % [dinfo["rule"]["desc"], GameData.find_boon(str(dinfo["boon"]))["name"], GameData.find_boon(str(dinfo["boon"]))["desc"], GameData.DAILY_CLEAR_CRYSTALS + GameData.DAILY_CLEAR_CRYSTALS_PER_ACT * mini(GameState.campaign_act, 3)], 12, true))
	elif _pending_tower:
		v.add_child(_label("Tower of Trials — Floor %d" % int(tower_info["floor"]), 20))
		var rules: Array = tower_info["rules"]
		v.add_child(_wrap_label("Up to %d heroes and the Champion. Everyone fights at full HP and leaves as they came.%s" % [_party_cap(), (" Rules: " + ", ".join(rules.map(func(r): return "%s (%s)" % [r["name"], r["desc"]]))) if not rules.is_empty() else ""], 12, true))
	elif _pending_finale and not GameState.current_act().is_empty():
		v.add_child(_label("Finale — %s" % GameState.current_act()["finale"], 20))
		v.add_child(_wrap_label("A harder %s Rift that ends in %s. Up to 4 heroes." % [str(GameState.current_act()["tier"]).capitalize(), GameState.current_act()["boss"]], 12, true))
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
		zv.add_child(_label("%s row (%d) — %s" % [row_id.capitalize(), in_row.size(),
			"takes most of the enemy's attacks" if row_id == "front" else "attacked far less often"], 13))
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
		v.add_child(_label("Roster — drag into a row, or Add (joins their natural row)", 12, true))
		var bench_flow := HFlowContainer.new()
		bench_flow.add_theme_constant_override("h_separation", 8)
		bench_flow.add_theme_constant_override("v_separation", 8)
		for bh in bench:
			bench_flow.add_child(_party_card(bh, bh.is_champion, false))
		v.add_child(bench_flow)

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
		v.add_child(_info_row("%s (%s) — %s" % [r.name, r.type, r.desc()], 14, [], rb))


	var launch := _party_launch_bar()
	v.add_child(launch)
	v.move_child(launch, 1)


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
		var hl := _wrap_label("Wounded: %s — they start the rift hurt." % ", ".join(hurt.map(func(h): return "%s (%d/%d)" % [h.name.split(" the ")[0], h.hp, Combat.max_hp(h)])), 12)
		hl.add_theme_color_override("font_color", Palette.HAZARD)
		info.add_child(hl)
	if _pending_endless and not pending_party.is_empty():
		var lead := GameState.find_hero(pending_party[0])
		if lead:
			info.add_child(_wrap_label("Endless Rift: you steer %s (the first hero you picked); the others follow and fight on their own. Your build comes along: gear, skills, equipped relics, dodge and mending, and each hero's Ability. Survive as long as you can." % lead.name.split(" the ")[0], 12, true))
	row.add_child(info)
	var enter := _icon_domain_button("violet", GameData.CAMP_HUB_ICON_PATH["rift"], "Begin the trial" if _pending_tower else "Enter the Rift", func():
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
			GameState.start_daily(ids)
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
		while view.run.pending_levels > 0:
			view.run.pick(view.run.offer()[0])
	print("[bench] fast-forward to 6:00 took %d ms" % (Time.get_ticks_msec() - t0))
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().root.add_child(view)


## The Endless Rift is a real-time survivors run in its own node; Main steps
## aside (hidden and paused) until the player leaves it.
func _start_survivors(ids: Array[String]) -> void:
	var party: Array = []
	for id in ids:
		var h := GameState.find_hero(id)
		if h:
			party.append(h)
	if party.is_empty():
		return
	var view := SurvivorsView.new()
	view.setup(party, GameState.pick_biome())
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

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	speed_row.add_child(_label("Battle speed", 13))
	for spd in [1.0, 2.0, 3.0, INSTANT_SPEED]:
		var spb := _button("Instant" if spd >= INSTANT_SPEED else "×%d" % int(spd), func(val=spd):
			GameState.combat_speed = val
			GameState.save_settings()
			render()
		)
		spb.toggle_mode = true
		spb.button_pressed = is_equal_approx(GameState.combat_speed, spd)
		spb.tooltip_text = "Fights resolve with no animation; the screen updates when it's your turn" if spd >= INSTANT_SPEED else "Battle animations at %d× speed" % int(spd)
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
	v.add_child(_label("Accessibility", 15))
	var acc_row := HFlowContainer.new()
	acc_row.add_theme_constant_override("h_separation", 8)
	var rm := _button("Reduce motion: %s" % ("on" if GameState.reduce_motion else "off"), func():
		GameState.reduce_motion = not GameState.reduce_motion
		GameState.save_settings()
		render())
	rm.tooltip_text = "No screen shake, zooms, knockbacks, idle sway or flashing in fights"
	acc_row.add_child(rm)
	var cb := _button("Colour-blind mode: %s" % ("on" if GameState.colorblind else "off"), func():
		GameState.colorblind = not GameState.colorblind
		GameState.save_settings()
		render())
	cb.tooltip_text = "Blue instead of green wherever it sits against red (HP, fight readouts, stat changes), and a rarity letter on every item"
	acc_row.add_child(cb)
	v.add_child(acc_row)

	v.add_child(_hsep())
	v.add_child(_label("Tips", 15))
	var tips_row := HBoxContainer.new()
	tips_row.add_theme_constant_override("separation", 8)
	tips_row.add_child(_button("Tips: %s" % ("off" if GameState.tips_off else "on"), func():
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
		var le := _label("Last exported: %s" % ("never" if GameState.last_export_day < 0 else "day %d (today is day %d)" % [GameState.last_export_day, GameState.day]), 12)
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
	row.add_child(_icon_button(GameData.BUTTON_ICON_PATH["sort"], "Import save…" if not _import_open else "Cancel import", func():
		_import_open = not _import_open
		_import_text = ""
		_backup_msg = ""
		render()
	))
	v.add_child(row)
	if _import_open:
		var slot := GameState.active_slot
		v.add_child(_wrap_label("Paste an exported save below%s. It replaces Slot %d%s." % [" or pick the file" if OS.has_feature("web") else "", slot + 1, " (%s)" % GameState.guild_name if GameState.guild_name != "" else ""], 12))
		if OS.has_feature("web"):
			v.add_child(_button("Choose file…", func(): _web_pick_save_file()))
		var te := TextEdit.new()
		te.custom_minimum_size = Vector2(0, 90)
		te.placeholder_text = "{\"guild_name\": ...}"
		te.text = _import_text
		te.text_changed.connect(func(): _import_text = te.text)
		v.add_child(te)
		var go := _icon_domain_button("ember", GameData.BUTTON_ICON_PATH["confirm"], "Replace Slot %d with this save" % (slot + 1), func():
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
		var text := "Slot %d — Empty" % (slot + 1)
		if not is_empty:
			var sealed := int(summary.get("rifts_sealed", 0))
			text = "Slot %d — %s (%d rift%s sealed)" % [slot + 1, str(summary.get("guild_name", "")), sealed, "" if sealed == 1 else "s"]
		if is_active:
			text += "  (Active)"
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
	if is_champ:
		var boon := _wrap_label(GameState.champion_boon_text(h), 12, true)
		boon.add_theme_color_override("font_color", Palette.RANK_E)
		names.add_child(boon)
	names.add_child(_label("Lv%d %s · %d/%d HP%s" % [h.level, GameData.hero_role(h).capitalize(), h.hp, Combat.max_hp(h), (" · out %d run%s" % [h.down_runs, "" if h.down_runs == 1 else "s"] if h.down_runs > 0 else " · away %d run%s" % [h.busy_runs, "" if h.busy_runs == 1 else "s"]) if downed else ""], 10, true))
	if not downed and h.hp < Combat.max_hp(h) * 0.5:
		var wl := _label("Wounded — %d%% HP" % int(100.0 * h.hp / max(1, Combat.max_hp(h))), 12)
		wl.add_theme_color_override("font_color", Palette.HAZARD)
		wl.tooltip_text = "Starts the rift at this HP. A Medical Bay bed or a rest heals them."
		names.add_child(wl)
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
