extends Control
## Root UI controller — mirrors guild-system.html's render() function: one
## place that clears and rebuilds the current screen's Controls from
## GameState, rather than a scene per screen. Kept as plain Controls with no
## custom Theme (visual polish is explicitly deferred past this slice).

@onready var root: MarginContainer = $Root

var screen: String = "onboard"     # onboard | rift_hall | party_assembly | rift_run | terminal
var term_tab: String = "camp"      # camp | roster | inventory | recruits | medical | management
var pending_crest: int = 1
var pending_party: Array[String] = []
var pending_relic_options: Array = []
var pending_relic_choice: int = -1
var selected_hero_id: String = ""
var expanded_skill_hero: String = ""
var expanded_slot: String = ""     # "weapon:0"/"gear:2" — which equip slot's picker is open, scoped to the selected hero
var confirm_reset: bool = false
var _combat_animating: bool = false
var medical_picker_bed: int = -1   # which empty bed slot is showing its hero picker, -1 = none
var mgmt_branch: String = ""       # "" = branch hub, else a GameData.BRANCHES id
var inv_category: String = ""      # "" = category hub, else "items" | "relics" | "detectors"
var combat_selected_hero_id: String = ""   # which hero's action bar is showing in combat; falls back to the first living hero
var roster_sort: String = "power"          # "power" | "level" | "rank" — cycled via the Roster tab's Sort button
var inv_sort: String = "rarity"            # "rarity" | "value" | "name" — cycled via the Inventory tab's Sort button


func _ready() -> void:
	if not GameState.load_save():
		GameState.reset()
	if GameState.guild_name != "":
		screen = "terminal" if GameState.run.is_empty() else "rift_run"
	else:
		pending_crest = 1 + randi() % GameData.CREST_PATH.size()
	GameState.state_changed.connect(render)
	render()


func _clear_root() -> void:
	for c in root.get_children():
		c.queue_free()


func _vbox(gap: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v


## No autowrap by default: a wrapping Label's minimum size shrinks to ~one
## word, so inside an HBoxContainer row it gets squeezed to near-zero width
## and wraps every word onto its own line. Long text (combat log lines, item
## descriptions) instead sits in a VBoxContainer stretched to the fixed-width
## content column, so it wraps at a sane width via wrap_text() below instead.
func _label(text: String, size: int = 14, muted: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if muted:
		l.add_theme_color_override("font_color", Palette.MUTED)
	return l


## Green above half HP, gold at low-but-not-critical, red once it's dire —
## a quick-scan cue on top of the exact numbers shown alongside every bar.
func _hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Palette.RIFT
	elif ratio > 0.25:
		return Palette.GOLD
	return Palette.HAZARD


func _hp_bar(current: int, max_val: int, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max(1, max_val)
	bar.value = clampi(current, 0, max_val)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 10)
	bar.size = Vector2(width, 10)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Palette.INK
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("background", bg_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = _hp_color(float(max(0, current)) / float(max(1, max_val)))
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_top_right = 4
	fill_style.corner_radius_bottom_left = 4
	fill_style.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("fill", fill_style)
	return bar


## A plain floating name + HP readout above a hero/monster in the arena — a
## name label over a colored bar with "cur/max" text, no ornate frame. Swapped
## from an earlier wooden-nameplate-prop version to match the reference battle
## screens' simple floating HP bars.
const STATUS_PLATE_HEIGHT := 34.0
func _status_plate(name_text: String, hp: int, max_hp_val: int, width: float = 160.0) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(width, STATUS_PLATE_HEIGHT)
	wrap.size = Vector2(width, STATUS_PLATE_HEIGHT)

	var name_label := _label(name_text, 11)
	name_label.size = Vector2(width, 15)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	wrap.add_child(name_label)

	var bar := _hp_bar(hp, max_hp_val, width)
	bar.position = Vector2(0, 16)
	wrap.add_child(bar)
	var hp_label := _label("%d/%d" % [hp, max_hp_val], 9, true)
	hp_label.size = Vector2(width, 12)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.position = Vector2(0, 27)
	wrap.add_child(hp_label)
	return wrap


## A hero portrait inside GameData.PORTRAIT_FRAME_PATH's ornate frame, sized
## to `size` — shared by the Roster hero card and Recruit offer cards so a
## hero's portrait always reads the same way wherever it appears. Returns an
## empty sized box if this class/pool has no portrait art (never happens for
## the 5 real classes today, but keeps callers from needing their own guard).
func _framed_portrait(cls_id: String, pool_id: String, size: float) -> Control:
	var frame_wrap := Control.new()
	frame_wrap.custom_minimum_size = Vector2(size, size)
	frame_wrap.size = Vector2(size, size)
	var portrait_path := GameData.portrait_for_hero(cls_id, pool_id)
	if portrait_path == "":
		return frame_wrap
	var pf_icon := _icon(portrait_path, int(size * 0.82))
	pf_icon.position = Vector2(size * 0.09, size * 0.09)
	frame_wrap.add_child(pf_icon)
	var pf_frame := _icon(GameData.PORTRAIT_FRAME_PATH, int(size))
	pf_frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame_wrap.add_child(pf_frame)
	return frame_wrap


## One battle-action slot: an ornate frame (GameData.RARITY_FRAME_PATH,
## "common" for every action — actions aren't loot, the frame is just the
## established slot language) with the action's icon centered inside, an
## optional cooldown-round badge in the corner, a short caption underneath so
## the action reads without guessing at an icon, and an invisible Button on
## top for input/selection state — same layered-hotspot approach as the camp
## hub's clickable props. Selected state is a filled tint (not just a thin
## border) since the border alone was too easy to miss against the wooden
## shelf background.
func _action_slot(icon_path: String, cooldown_text: String, selected: bool, disabled: bool, cb: Callable, size: float = 48.0, label_text: String = "") -> Control:
	var label_h := 14.0 if label_text != "" else 0.0
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(size, size + label_h)
	wrap.size = Vector2(size, size + label_h)

	var frame := _icon(GameData.RARITY_FRAME_PATH["common"], int(size))
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	wrap.add_child(frame)

	if selected:
		var glow := PanelContainer.new()
		var glow_style := StyleBoxFlat.new()
		glow_style.bg_color = Color(Palette.RIFT.r, Palette.RIFT.g, Palette.RIFT.b, 0.32)
		glow_style.border_width_left = 2
		glow_style.border_width_top = 2
		glow_style.border_width_right = 2
		glow_style.border_width_bottom = 2
		glow_style.border_color = Palette.RIFT
		glow_style.corner_radius_top_left = 4
		glow_style.corner_radius_top_right = 4
		glow_style.corner_radius_bottom_left = 4
		glow_style.corner_radius_bottom_right = 4
		glow.add_theme_stylebox_override("panel", glow_style)
		glow.custom_minimum_size = Vector2(size, size)
		glow.size = Vector2(size, size)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(glow)

	if icon_path != "":
		var icon_size := size * 0.6
		var icon := _icon(icon_path, int(icon_size))
		icon.position = Vector2((size - icon_size) * 0.5, (size - icon_size) * 0.5)
		if disabled:
			icon.modulate = Color(0.5, 0.5, 0.5, 0.7)
		wrap.add_child(icon)

	if cooldown_text != "":
		var badge := PanelContainer.new()
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = Palette.HAZARD
		badge_style.corner_radius_top_left = 8
		badge_style.corner_radius_top_right = 8
		badge_style.corner_radius_bottom_left = 8
		badge_style.corner_radius_bottom_right = 8
		badge_style.content_margin_left = 3
		badge_style.content_margin_right = 3
		badge.add_theme_stylebox_override("panel", badge_style)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var badge_label := _label(cooldown_text, 9)
		badge.add_child(badge_label)
		badge.position = Vector2(size * 0.62, size * 0.62)
		wrap.add_child(badge)

	if label_text != "":
		var lbl := _label(label_text, 9, disabled)
		lbl.custom_minimum_size = Vector2(size, label_h)
		lbl.size = Vector2(size, label_h)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.clip_text = true
		lbl.position = Vector2(0, size)
		wrap.add_child(lbl)

	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = wrap.custom_minimum_size
	btn.size = wrap.size
	btn.disabled = disabled
	var clear_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style_name, clear_style)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if label_text != "":
		btn.tooltip_text = label_text
	btn.pressed.connect(cb)
	wrap.add_child(btn)
	return wrap


## A row of _action_slot controls on a wooden "ability bar" shelf background
## (GameData.ABILITY_BAR_STRIP_PATH, 9-sliced via StyleBoxTexture so it
## stretches to fit however many slots a hero has this fight).
func _slot_row(children: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	# Without this, a VBoxContainer parent stretches the panel to its own
	# full width — the StyleBoxTexture then stretches its tileable middle
	# band across that whole leftover width, showing stray bits of the
	# source art (looks like unrelated furniture) to the right of the actual
	# buttons instead of the bar just hugging its own content.
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxTexture.new()
	style.texture = load(GameData.ABILITY_BAR_STRIP_PATH)
	style.texture_margin_left = 60
	style.texture_margin_right = 60
	style.texture_margin_top = 14
	style.texture_margin_bottom = 14
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for c in children:
		row.add_child(c)
	panel.add_child(row)
	return panel


## Pixel-art icon at a fixed size, nearest-neighbor filtered to stay crisp
## (matches the HTML's image-rendering:pixelated).
func _icon(path: String, size: int = 24) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	# Godot 4's default expand_mode (KEEP_SIZE) treats the texture's native
	# resolution as a floor the moment `.size` is assigned — Control.size's
	# setter clamps up to get_combined_minimum_size(), and under KEEP_SIZE that
	# minimum is the texture's own pixel size. So expand_mode has to switch to
	# IGNORE_SIZE *before* `.size`/`custom_minimum_size` are set below, or the
	# clamp bakes in a too-large size that IGNORE_SIZE can no longer shrink
	# back down (bit both a 192x192 UI frame requested at 96 and a 92x200
	# hero portrait requested at 78 before this was reordered).
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.custom_minimum_size = Vector2(size, size)
	# Containers apply custom_minimum_size as actual size automatically, but a
	# plain Control parent (the combat arena's freely-positioned sprites) does
	# not — without this the TextureRect renders at its native texture
	# resolution instead of the intended icon size.
	t.size = Vector2(size, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


## A wide atmospheric header image (stretched to fill, corners rounded to
## match the game's card language) sitting above a screen's actual content —
## purely decorative, no clickable elements on it.
func _banner(path: String, width: float, height: float) -> Control:
	var clip := Control.new()
	clip.custom_minimum_size = Vector2(width, height)
	clip.size = Vector2(width, height)
	clip.clip_contents = true
	var t := TextureRect.new()
	t.texture = load(path)
	t.custom_minimum_size = Vector2(width, height)
	t.size = Vector2(width, height)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip.add_child(t)
	return clip


## Wraps hero/monster names in the combat log in BBCode color so the wall of
## text reads as "who did what to whom" at a glance instead of one uniform
## color — heroes in the accent teal, monsters in the hazard red. [lb] escapes
## any literal '[' first so a stray bracket in a name can't be misread as a
## tag.
func _colorize_log_line(line: String, party: Array[Hero], monsters: Array) -> String:
	var out := line.replace("[", "[lb]")
	for h in party:
		if h.name != "":
			out = out.replace(h.name, "[color=#%s]%s[/color]" % [Palette.RIFT.to_html(false), h.name])
	for m in monsters:
		var mname: String = str(m.get("name", ""))
		if mname != "":
			out = out.replace(mname, "[color=#%s]%s[/color]" % [Palette.HAZARD.to_html(false), mname])
	return out


## A piece of loot's display text — a Legendary's real effect lives in
## GameData.find_unique_item/relic's authored `desc`, not in kind/value or
## the generic Relic.desc() (built for the normal rolled case), so every
## loot-listing site (reward choice, shop, inventory) routes through here
## instead of duplicating the unique/normal branch three times.
func _loot_desc(obj, is_relic: bool) -> String:
	if is_relic:
		var r: Relic = obj
		if r.unique_id != "":
			var d := str(GameData.find_unique_relic(r.unique_id).get("desc", ""))
			if r.combo_with != "" and Combat.party_has_unique_relic(r.combo_with):
				d += " [combo active!]"
			return d
		return r.desc()
	var it: Item = obj
	if it.unique_id != "":
		return str(GameData.find_unique_item(it.unique_id).get("desc", ""))
	return Combat.describe_skill(it.kind, it.value)


func _loot_display_name(obj) -> String:
	var uid: String = obj.unique_id
	return "★ %s" % obj.name if uid != "" else obj.name


## Fixed-height, internally-scrolled log — `fit_content` used to grow the
## label a line taller every round, pushing the action buttons further down
## the page each time. scroll_follow keeps the newest line in view without
## the caller needing to manage scroll position.
func _log_richtext(lines: Array, party: Array[Hero], monsters: Array, height: float = 160.0) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.custom_minimum_size = Vector2(0, height)
	rt.size = Vector2(0, height)
	rt.scroll_active = true
	rt.scroll_following = true
	rt.add_theme_font_size_override("normal_font_size", 12)
	var body := ""
	for line in lines:
		body += _colorize_log_line(str(line), party, monsters) + "\n"
	rt.text = body
	return rt


## Wraps an _icon() TextureRect in a plain Control sized to match it — plain
## Controls don't auto-layout their children the way Container nodes do, so a
## combat animation can freely tween the wrapper's position/modulate (a lunge,
## a hit-shake) and freely position a damage-number Label inside it, without
## fighting whatever Container the wrapper itself sits in.
func _wrap_icon(rect: TextureRect) -> Control:
	var c := Control.new()
	c.custom_minimum_size = rect.custom_minimum_size
	c.size = rect.custom_minimum_size
	c.add_child(rect)
	return c


## A soft dark ellipse under a hero/monster's feet so they read as standing on
## the ground rather than floating over the battle background — add this to
## `parent` (the arena) *before* the wrapper it belongs to, so it paints
## underneath (Godot draws siblings in child order).
func _add_ground_shadow(parent: Control, wrapper_pos: Vector2, wrapper_size: float) -> void:
	var shadow := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.35)
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_left = 999
	style.corner_radius_bottom_right = 999
	shadow.add_theme_stylebox_override("panel", style)
	var shadow_w: float = wrapper_size * 0.8
	var shadow_h: float = shadow_w * 0.32
	shadow.custom_minimum_size = Vector2(shadow_w, shadow_h)
	shadow.size = Vector2(shadow_w, shadow_h)
	shadow.position = Vector2(wrapper_pos.x + (wrapper_size - shadow_w) * 0.5, wrapper_pos.y + wrapper_size - shadow_h * 0.5)
	parent.add_child(shadow)


## Opt-in wrapping variant for long standalone text (combat log lines,
## descriptions) — safe to use only where the label is the sole child of its
## row (a VBoxContainer entry, not sharing an HBoxContainer with buttons).
func _wrap_label(text: String, size: int = 14) -> Label:
	var l := _label(text, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


## The single highest-intent action on a screen (Engage, Continue, Recruit,
## Start Run, Confirm Reset) — reuses the theme's own hover/pressed textures
## (already the rift-teal accent) in the button's resting state instead of
## drawing new art, so it reads as "the one to click" without a second Theme.
func _primary_button(text: String, cb: Callable) -> Button:
	var b := _button(text, cb)
	var hover_style := get_theme_stylebox("hover", "Button")
	var pressed_style := get_theme_stylebox("pressed", "Button")
	b.add_theme_stylebox_override("normal", hover_style)
	b.add_theme_stylebox_override("hover", hover_style)
	b.add_theme_stylebox_override("focus", hover_style)
	b.add_theme_stylebox_override("pressed", pressed_style)
	b.add_theme_color_override("font_color", get_theme_color("font_pressed_color", "Button"))
	b.add_theme_color_override("font_hover_color", get_theme_color("font_pressed_color", "Button"))
	return b


func _hsep() -> HSeparator:
	return HSeparator.new()


## A small colored heading strip for a card that needs a title set apart from
## its body text (e.g. a Roster hero card) — a plain StyleBoxFlat rather than
## extracting the UI pack's header-bar art, since that art comes fused to a
## specific panel body with baked-in text and isn't reusable standalone.
func _title_strip(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.SURFACE3
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	p.add_theme_stylebox_override("panel", style)
	var l := _label(text, 14)
	l.add_theme_color_override("font_color", Palette.RIFT)
	p.add_child(l)
	return p


func render() -> void:
	GameState.resolve_recovery()
	GameState.resolve_rift_map()
	if screen == "terminal" and GameState.run.is_empty() and not GameState.pending_riftbreak_ranks.is_empty():
		GameState.start_riftbreak_encounter()
		if not GameState.run.is_empty():
			screen = "rift_run"
	_clear_root()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var v := _vbox(14)
	# Rift Run gets extra width for the combat arena (background + positioned
	# sprites) sitting alongside the log/action column — every other screen
	# stays at the original column width.
	v.custom_minimum_size = Vector2(940 if screen == "rift_run" else 760, 0)
	scroll.add_child(v)

	match screen:
		"onboard": _render_onboard(v)
		"rift_hall": _render_rift_hall(v)
		"rift_map": _render_rift_map_hub(v)
		"party_assembly": _render_party_assembly(v)
		"rift_run": _render_rift_run(v)
		"terminal": _render_terminal(v)


func _topbar(v: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_icon(GameData.CREST_PATH[GameState.guild_crest - 1], 24))
	row.add_child(_label("%s —" % GameState.guild_name, 16))
	for entry in [
		[GameData.CURRENCY_ICON_PATH["coins"], GameState.coins],
		[GameData.CURRENCY_ICON_PATH["crystals"], GameState.crystals],
		[GameData.CURRENCY_ICON_PATH["tokens"], GameState.tokens],
	]:
		var stat_row := HBoxContainer.new()
		stat_row.add_child(_icon(entry[0], 18))
		stat_row.add_child(_label(str(entry[1]), 16))
		row.add_child(stat_row)
	v.add_child(row)
	v.add_child(_hsep())


# ---------------- Onboard ----------------
func _render_onboard(v: VBoxContainer) -> void:
	v.add_child(_label("Name Your Guild", 22))
	var edit := LineEdit.new()
	edit.placeholder_text = "Guild name"
	v.add_child(edit)

	v.add_child(_label("Choose a Crest", 16))
	var crest_row := HBoxContainer.new()
	crest_row.add_theme_constant_override("separation", 12)
	crest_row.add_child(_icon(GameData.CREST_PATH[pending_crest - 1], 64))
	crest_row.add_child(_button("Randomize", func():
		pending_crest = 1 + randi() % GameData.CREST_PATH.size()
		render()
	))
	v.add_child(crest_row)

	v.add_child(_primary_button("Found the Guild", func():
		var n := edit.text.strip_edges()
		if n == "":
			return
		GameState.guild_name = n
		GameState.guild_crest = pending_crest
		GameState.refresh_recruit_pool()
		GameState.save()
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
	_topbar(v)
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
	if not GameState.greater_rift_unlocked():
		v.add_child(_label("Greater Rift — Seal %d more Rift(s) to unlock (%d/3)" % [3 - GameState.rifts_sealed, GameState.rifts_sealed], 12))
	v.add_child(_button("Back to Terminal", func():
		screen = "terminal"
		render()
	))


## A plain list, not an illustrated scene — 6+ rifts shifting in and out
## doesn't earn its own background art the way Rift Hall's two fixed gates
## do. Each row shows the slot's rolled rank (colored via Palette.rank_color)
## and a live mm:ss countdown to its Riftbreak, computed fresh every render()
## the same way every other lazily-resolved timer in this project already is.
func _render_rift_map_hub(v: VBoxContainer) -> void:
	_topbar(v)
	v.add_child(_label("Rift Map", 20))
	v.add_child(_label("Rifts open at random ranks and stay for a limited time. Leave one unaddressed and its threat spills out as a forced fight next time you're back at the Terminal.", 12, true))
	v.add_child(_hsep())

	var now := int(Time.get_unix_time_from_system() * 1000)
	for i in GameState.rift_map.size():
		var slot: Dictionary = GameState.rift_map[i]
		if slot.is_empty():
			continue
		var rank := str(slot.get("rank", "F"))
		var remain_ms: int = max(0, int(slot.get("expires_at", 0)) - now)
		var remain_s := remain_ms / 1000
		var mm := remain_s / 60
		var ss := remain_s % 60

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var rank_label := _label("Rank %s" % rank, 14)
		rank_label.add_theme_color_override("font_color", Palette.rank_color(rank))
		row.add_child(rank_label)
		row.add_child(_label("%02d:%02d remaining" % [mm, ss], 12, true))
		row.add_child(_button("Enter", func(idx=i, r=rank):
			pending_party.clear()
			pending_relic_options.clear()
			pending_relic_choice = -1
			_pending_rift_rank = r
			_pending_map_slot_idx = idx
			screen = "party_assembly"
			render()
		))
		v.add_child(row)

	if not GameState.pending_riftbreak_ranks.is_empty():
		v.add_child(_hsep())
		v.add_child(_label("A Riftbreak is looming — %d unaddressed rift(s) will spill out next time you return to the Terminal." % GameState.pending_riftbreak_ranks.size(), 12, true))

	v.add_child(_hsep())
	v.add_child(_button("Back to Terminal", func():
		screen = "terminal"
		render()
	))


var _pending_diff_id: String = "lesser"
var _pending_endless: bool = false
var _pending_hardcore: bool = false
var pending_incense_id: String = ""
## Non-empty only when Party Assembly was entered from the Rift Map hub
## (rather than Rift Hall) — routes "Enter the Rift" to start_map_rift()
## instead of start_run(), hides the Hardcore toggle (retired from mapped
## rifts), and sends "Back" to the map instead of the hall.
var _pending_rift_rank: String = ""
var _pending_map_slot_idx: int = -1


# ---------------- Party Assembly ----------------
func _render_party_assembly(v: VBoxContainer) -> void:
	_topbar(v)
	v.add_child(_label("Assemble Party (pick up to 4)", 20))
	var champ := GameState.ensure_champion()
	var champ_row := HBoxContainer.new()
	var champ_portrait := GameData.portrait_for_hero(champ.cls_id, champ.pool_id)
	if champ_portrait != "":
		champ_row.add_child(_icon(champ_portrait, 48))
	champ_row.add_child(_label("Champion: %s — Rank %s (always joins) · %d/%d HP" % [champ.name, champ.rank, champ.hp, Combat.max_hp(champ)], 13))
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
			row.add_child(_icon(portrait_path, 40))
		var status := " (downed)" if h.is_downed() else ""
		row.add_child(_label("%s — Lv%d %s · %d/%d HP%s" % [h.name, h.level, h.cls_id.capitalize(), h.hp, Combat.max_hp(h), status]))
		v.add_child(row)
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes yet — recruit some from the Guild Terminal first."))

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
		var row2 := HBoxContainer.new()
		var rb := CheckButton.new()
		rb.button_pressed = pending_relic_choice == i
		rb.toggled.connect(func(on: bool):
			pending_relic_choice = i if on else -1
			render()
		)
		row2.add_child(rb)
		row2.add_child(_label("%s (%s) — %s" % [r.name, r.type, r.desc()]))
		v.add_child(row2)

	if not GameState.consumables.is_empty():
		v.add_child(_hsep())
		v.add_child(_label("Field Incense (pick one, optional) — lasts the whole rift"))
		for c in GameState.consumables:
			var cid: String = str(c["id"])
			var def := GameData.find_incense(str(c["incense_id"]))
			var irow := HBoxContainer.new()
			var ib := CheckButton.new()
			ib.button_pressed = pending_incense_id == cid
			ib.toggled.connect(func(on: bool, id=cid):
				pending_incense_id = id if on else ""
				render()
			)
			irow.add_child(ib)
			irow.add_child(_label("%s — %s" % [def["name"], def["desc"]]))
			v.add_child(irow)

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
	v.add_child(_primary_button("Enter the Rift", func():
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
	))
	v.add_child(_button("Back", func():
		screen = "rift_map" if _pending_rift_rank != "" else "rift_hall"
		_pending_rift_rank = ""
		_pending_map_slot_idx = -1
		render()
	))


const MAP_NODE_COLOR := {
	"combat": Palette.HAZARD, "elite": Palette.ELITE, "shop": Palette.GOLD,
	"hazard": Palette.CRYSTAL, "boss": Palette.TOKEN,
}
const MAP_NODE_LABEL := {"combat": "C", "elite": "E", "shop": "S", "hazard": "H", "boss": "B"}


func _map_node_marker(kind: String, is_current: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = MAP_NODE_COLOR.get(kind, Palette.LINE)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	if is_current:
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Palette.TEXT
	p.add_theme_stylebox_override("panel", style)
	var l := _label(MAP_NODE_LABEL.get(kind, "?"), 13)
	l.add_theme_color_override("font_color", Color(0, 0, 0, 1))
	p.add_child(l)
	return p


## Horizontal overview of the whole rift path — a reskin of run["layers"]/
## ["chosen"], not new state. Resolved floors show one marker; an unresolved
## fork shows both its options side by side. Purely informational: the actual
## fork-choice buttons for the current position render separately, below.
func _render_rift_map(v: VBoxContainer) -> void:
	var layers: Array = GameState.run["layers"]
	var chosen: Dictionary = GameState.run.get("chosen", {})
	var pos: int = int(GameState.run["pos"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in layers.size():
		var opts: Array = layers[i]["options"]
		var resolved: String = str(chosen[i]) if chosen.has(i) else (str(opts[0]) if opts.size() == 1 else "")
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		if resolved != "":
			cell.add_child(_map_node_marker(resolved, i == pos))
		else:
			for opt in opts:
				cell.add_child(_map_node_marker(str(opt), i == pos))
		row.add_child(cell)
		if i < layers.size() - 1:
			row.add_child(_label("-", 12, true))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 46)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(row)
	v.add_child(scroll)


# ---------------- Rift Run ----------------
func _render_rift_run(v: VBoxContainer) -> void:
	if GameState.run.is_empty():
		screen = "terminal"
		render()
		return
	_topbar(v)
	if GameState.run.get("is_riftbreak", false):
		var rb_label := _label("⚠ Riftbreak! An unaddressed rift's threat has spilled out and forced this fight.", 14)
		rb_label.add_theme_color_override("font_color", Palette.HAZARD)
		v.add_child(rb_label)
	var diff := GameState._diff()
	var pos: int = int(GameState.run["pos"])
	var total_layers: int = (GameState.run["layers"] as Array).size()
	var cycle_label := (" (cycle %d)" % (int(GameState.run["cycle"]) + 1)) if GameState.run.get("endless", false) else ""
	v.add_child(_label("%s%s — Node %d/%d" % [diff["name"], cycle_label, pos + 1, total_layers], 18))
	if GameState.run.get("hardcore", false):
		v.add_child(_label("Hardcore Mode active", 12))
	if not GameState.active_incense.is_empty():
		v.add_child(_label("%s active" % str(GameState.active_incense["name"]), 12, true))
	_render_rift_map(v)

	var sealed = GameState.run.get("sealed")
	if sealed != null:
		var sealed_dict: Dictionary = sealed
		var sealed_row := HBoxContainer.new()
		sealed_row.add_child(_icon(GameData.CHEST_ICON_PATH, 28))
		sealed_row.add_child(_label("Rift Sealed! +%d Seal Tokens%s%s" % [
			int(sealed_dict["tokens"]),
			" (fast clear)" if sealed_dict.get("fast_clear", false) else "",
			" · Rift Detector found!" if sealed_dict.get("got_detector", false) else "",
		]))
		v.add_child(sealed_row)
		if sealed_dict.get("continuing", false):
			v.add_child(_label("Endless cycle %d begins..." % int(sealed_dict["cycle"])))
			v.add_child(_button("Continue Endless Run", func():
				GameState.continue_endless()
				render()
			))
		else:
			for line in _run_summary_lines():
				v.add_child(_label(line, 12, true))
			v.add_child(_button("Return to Terminal", func():
				GameState.finish_run()
				screen = "terminal"
				render()
			))
		return

	var options := GameState.current_layer_options()
	var kind := GameState.current_node_kind()
	# The battle screen already shows every hero's HP twice over (arena
	# nameplates + the action menu) and has its own Retreat button — repeating
	# a third party-HP list and a second Retreat button above/below it just
	# forced extra scrolling to reach the actual action buttons every round.
	var is_combat_kind := kind in ["combat", "boss", "elite"]

	if not is_combat_kind:
		v.add_child(_hsep())
		for h in GameState.current_party():
			v.add_child(_label("%s%s — %d/%d HP%s" % [h.name, " (Champion)" if h.is_champion else "", h.hp, Combat.max_hp(h), " (downed)" if h.is_downed() else ""]))
		v.add_child(_hsep())

	if kind == "" and options.size() > 1:
		v.add_child(_label("Choose your path:"))
		for opt in options:
			v.add_child(_button(str(opt).capitalize(), func(picked=str(opt)):
				GameState.choose_node_type(picked)
				render()
			))
	else:
		match kind:
			"combat", "boss", "elite": _render_combat_node(v)
			"shop": _render_shop_node(v)
			"hazard": _render_hazard_node(v)

	if not is_combat_kind:
		v.add_child(_hsep())
		v.add_child(_button("Retreat (keep loot, no Seal Tokens)", func():
			GameState.retreat_now()
			screen = "terminal"
			render()
		))


## Bounds an animation wait to `timeout_sec` of real engine time instead of
## trusting `sig` alone. Reproduced twice: Resolve Round's animation chain
## (tween.finished / SceneTreeTimer.timeout) can simply never fire — once
## even on a foregrounded, unthrottled tab — which used to wedge
## _combat_animating forever behind the early-return guard on the button,
## making every further click a silent no-op until the page was reloaded.
## Polls via process_frame rather than racing a second timer against the
## first, since process_frame is the one signal that must still fire for
## anything on screen to ever change — timing out against it can't get stuck
## the same way a stalled Tween or SceneTreeTimer can.
func _await_or_timeout(sig: Signal, timeout_sec: float) -> void:
	var fired := [false]
	var mark_fired := func(): fired[0] = true
	sig.connect(mark_fired, CONNECT_ONE_SHOT)
	var elapsed := 0.0
	while not fired[0] and elapsed < timeout_sec:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if sig.is_connected(mark_fired):
		sig.disconnect(mark_fired)


## Frame-swaps `rect.texture` through `frames` once, a short delay between each.
## No explicit reset to the resting pose needed — the render() call right after
## _play_round always rebuilds portraits from the static portrait path anyway.
func _play_frames(rect: TextureRect, frames: Array[String], frame_time: float = 0.08) -> void:
	for path in frames:
		rect.texture = load(path)
		await _await_or_timeout(get_tree().create_timer(frame_time).timeout, frame_time + 1.0)


## Fallback for the two combos with no usable AI-generated motion (Warrior's
## hurt, Ranger's attack): a quick lunge tween on the existing static portrait.
## Animates position:x specifically (not the whole position) so it doesn't
## fight the idle sway's position:y loop running on the same wrapper.
func _tween_lunge(wrapper: Control) -> void:
	var start_x: float = wrapper.position.x
	var tween := create_tween()
	tween.tween_property(wrapper, "position:x", start_x + 12.0, 0.12)
	tween.tween_property(wrapper, "position:x", start_x, 0.12)
	await _await_or_timeout(tween.finished, 1.0)


func _tween_hurt(wrapper: Control) -> void:
	var start_x: float = wrapper.position.x
	var tween := create_tween()
	tween.tween_property(wrapper, "modulate", Color(1, 0.4, 0.4), 0.08)
	tween.parallel().tween_property(wrapper, "position:x", start_x - 6.0, 0.08)
	tween.chain().tween_property(wrapper, "position:x", start_x + 6.0, 0.08)
	tween.chain().tween_property(wrapper, "position:x", start_x, 0.08)
	tween.parallel().tween_property(wrapper, "modulate", Color(1, 1, 1), 0.24)
	await _await_or_timeout(tween.finished, 1.0)


func _flash_white(wrapper: Control) -> void:
	var tween := create_tween()
	tween.tween_property(wrapper, "modulate", Color(2, 2, 2), 0.06)
	tween.tween_property(wrapper, "modulate", Color(1, 1, 1), 0.18)
	await _await_or_timeout(tween.finished, 1.0)


## A gentle, endless breathing/sway loop for a hero or monster wrapper so the
## arena doesn't look frozen between rounds — a small vertical bob rather than
## a scale pulse (scaling pixel art by fractional amounts shimmers/aliases
## even with nearest-neighbor filtering, which read as distracting). Uses
## `position` offsets relative to the wrapper's own resting position, and only
## the Y axis, so it doesn't fight the lunge/hurt tweens' X-axis moves (those
## are momentary and both resolve back to the same resting spot). Self-cleans
## up: bind_node() means Godot kills the tween automatically once render()
## frees this wrapper on the next state change, no manual bookkeeping needed.
func _start_idle_sway(wrapper: Control) -> void:
	var rest := wrapper.position
	var tween := create_tween()
	tween.bind_node(wrapper)
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(wrapper, "position:y", rest.y - 3.0, 1.4)
	tween.tween_property(wrapper, "position:y", rest.y, 1.4)


func _spawn_damage_number(wrapper: Control, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)
	l.position = Vector2(wrapper.custom_minimum_size.x * 0.5 - 10, -6)
	wrapper.add_child(l)
	var tween := create_tween()
	tween.tween_property(l, "position:y", l.position.y - 24, 0.6)
	tween.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	await _await_or_timeout(tween.finished, 1.5)
	l.queue_free()


## Plays out one round's visible consequences on the *live* nodes from the
## current render() pass (portraits/wrappers built moments ago in
## _render_combat_node) before the caller calls render() again, which would
## otherwise tear all of this down mid-animation. Diffs hp before/after
## GameState.resolve_round_now() to figure out who acted and who got hit,
## since Combat.resolve_round doesn't return that directly.
func _play_round(state: Dictionary, hero_wrappers: Dictionary, hero_rects: Dictionary, monster_wrappers: Dictionary, monster_rects: Dictionary) -> void:
	var party: Array[Hero] = state["party"]
	var pending: Dictionary = state["pending_actions"].duplicate(true)
	var hp_before: Dictionary = {}
	for h in party:
		hp_before[h.id] = h.hp
	var monsters: Array = state["monsters"]
	var monster_hp_before: Array = []
	for m in monsters:
		monster_hp_before.append(float(m["hp"]))

	GameState.resolve_round_now()

	for h in party:
		if h.hp <= 0 or not hero_wrappers.has(h.id):
			continue
		var act: Dictionary = pending.get(h.id, {})
		var action: String = str(act.get("action", "attack"))
		if action == "attack" or action == "ability":
			var frames := GameData.hero_anim_frames(h.cls_id, "attack")
			if not frames.is_empty() and hero_rects.has(h.id):
				await _play_frames(hero_rects[h.id], frames)
			else:
				await _tween_lunge(hero_wrappers[h.id])

	for i in monsters.size():
		if not monster_wrappers.has(i):
			continue
		var dmg: float = float(monster_hp_before[i]) - float(monsters[i]["hp"])
		if dmg > 0:
			if monster_rects.has(i):
				await _play_frames(monster_rects[i], GameData.monster_anim_frames(str(monsters[i]["name"]), "hurt"))
			await _flash_white(monster_wrappers[i])
			await _spawn_damage_number(monster_wrappers[i], "-%d" % int(round(dmg)), Palette.HAZARD)

	await _await_or_timeout(get_tree().create_timer(0.15).timeout, 1.0)

	# Every monster still alive after the heroes' attack phase takes its
	# retaliation swing now. Whether a given swing actually landed or was
	# dodged is a per-hero log detail, not tracked per-attacking-monster here
	# — a deliberate simplification, since Combat.resolve_round doesn't return
	# which monster hit which hero. Every surviving monster just animates its
	# attack, and separately whichever hero(es) actually lost HP show their
	# own hurt reaction right after.
	for i in monsters.size():
		if float(monsters[i]["hp"]) > 0 and monster_rects.has(i):
			await _play_frames(monster_rects[i], GameData.monster_anim_frames(str(monsters[i]["name"]), "attack"))

	for h in party:
		var before: int = int(hp_before.get(h.id, h.hp))
		var dmg2: int = before - h.hp
		if dmg2 > 0 and hero_wrappers.has(h.id):
			var frames := GameData.hero_anim_frames(h.cls_id, "hurt")
			if not frames.is_empty() and hero_rects.has(h.id):
				await _play_frames(hero_rects[h.id], frames)
			else:
				await _tween_hurt(hero_wrappers[h.id])
			await _spawn_damage_number(hero_wrappers[h.id], "-%d" % dmg2, Palette.HAZARD)


## One hero's tab in the battle screen's action-bar header: portrait + HP bar
## + a small badge for whatever action they're currently set to (a monster's
## own sprite for Attack, the class ability icon for Ability, a shield for
## Defend) so the whole party's plan reads at a glance without switching
## tabs. Clicking a tab makes that hero's full action bar show below —
## reused from the reference battle screens' turn-order strip, but repurposed
## honestly: this game resolves every hero's action in the same round rather
## than one at a time, so the strip picks "whose bar am I editing," not
## "whose turn is it."
func _hero_action_tab(h: Hero, monsters: Array, pending: Dictionary, selected: bool) -> Control:
	var w := 64.0
	var ht := 84.0
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(w, ht)
	wrap.size = Vector2(w, ht)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, ht)
	panel.size = Vector2(w, ht)
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.SURFACE3 if selected else Palette.SURFACE2
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Palette.RIFT if selected else Palette.LINE
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_top = 4
	panel.add_theme_stylebox_override("panel", style)

	var downed := h.hp <= 0
	var pv := _vbox(2)
	var portrait_path := GameData.portrait_for_hero(h.cls_id, h.pool_id)
	if portrait_path != "":
		var icon_wrap := CenterContainer.new()
		var pic := _icon(portrait_path, 36)
		if downed:
			pic.modulate = Color(0.4, 0.4, 0.4, 0.7)
		icon_wrap.add_child(pic)
		pv.add_child(icon_wrap)
	pv.add_child(_label(h.name.split(" the ")[0], 9))
	if downed:
		pv.add_child(_label("Down", 8, true))
	else:
		var bar_wrap := CenterContainer.new()
		bar_wrap.add_child(_hp_bar(h.hp, Combat.max_hp(h), w - 12.0))
		pv.add_child(bar_wrap)
		var act: Dictionary = pending.get(h.id, {"action": "attack", "target": 0})
		var action: String = str(act.get("action", "attack"))
		var badge_icon := "res://assets/skills/shield_basic.png"
		if action == "attack":
			var ti := int(act.get("target", 0))
			if ti >= 0 and ti < monsters.size():
				badge_icon = GameData.sprite_for_monster(str(monsters[ti]["name"]))
		elif action == "ability":
			badge_icon = GameData.ability_icon(h.pool_id)
		var badge_wrap := CenterContainer.new()
		badge_wrap.add_child(_icon(badge_icon, 16))
		pv.add_child(badge_wrap)
	panel.add_child(pv)
	wrap.add_child(panel)

	if not downed:
		var btn := Button.new()
		btn.flat = true
		btn.custom_minimum_size = wrap.custom_minimum_size
		btn.size = wrap.size
		var clear_style := StyleBoxEmpty.new()
		for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(style_name, clear_style)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(func(hid=h.id):
			combat_selected_hero_id = hid
			render()
		)
		wrap.add_child(btn)
	return wrap


func _render_combat_node(v: VBoxContainer) -> void:
	var ns: Dictionary = GameState.run.get("node_state", {})
	var kind := GameState.current_node_kind()
	var is_boss := kind == "boss"

	if not ns.has("combat_state") and not ns.has("result"):
		var kind_label := "Boss" if is_boss else ("Elite" if kind == "elite" else "Combat")
		v.add_child(_label("A %s encounter awaits." % kind_label))
		v.add_child(_primary_button("Engage", func():
			GameState.engage_node()
			render()
		))
		return

	if ns.has("combat_state") and not ns.has("result"):
		var state: Dictionary = ns["combat_state"]
		var monsters: Array = state["monsters"]
		var party: Array[Hero] = state["party"]
		var living_heroes: Array[Hero] = []
		living_heroes.assign(party.filter(func(h): return h.hp > 0))

		# One shared battlefield — heroes on the left, monsters on the right,
		# facing each other across the same ground — rather than the previous
		# stacked monster-band/hero-band diorama. Matches every reference
		# battle screen's side-by-side confrontation instead of a top/bottom
		# split, and now spans the full content width with the action bar
		# stacked below it (also reference-matched: scene on top, commands in
		# a bottom strip) instead of sharing a row with a side menu.
		const ARENA_SIZE := Vector2(700, 300)
		var arena := Control.new()
		arena.custom_minimum_size = ARENA_SIZE

		var bg_path: String = GameData.BATTLE_BACKGROUNDS[int(state["background_idx"]) % GameData.BATTLE_BACKGROUNDS.size()]
		var bg := TextureRect.new()
		bg.texture = load(bg_path)
		bg.custom_minimum_size = ARENA_SIZE
		bg.size = ARENA_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		arena.add_child(bg)

		# Both rows share this baseline Y (bottom of the sprite) so the two
		# sides read as standing on the same ground rather than floating at
		# independent heights.
		var ground_y: float = ARENA_SIZE.y * 0.62

		# Each side's units pack into a narrow zone near ITS OWN edge of the
		# field, leaving a wide fixed no-man's-land in the middle (from 34%
		# to 66% of the width, regardless of how many units are on either
		# side) — a tight per-side spacing next to a deliberately open gap is
		# what actually reads as "two groups facing off" rather than one row
		# of evenly-spaced individuals (the previous 40%/50%+ split put too
		# little daylight between the sides relative to their own internal
		# spacing). Size still scales with the monster's own max HP (clamped)
		# so a boss/elite main unit reads as a bigger threat than a weak add.
		# A small per-position vertical offset applied within each side's row —
		# a flat single line read as too uniform/lined-up next to the
		# reference battle screens, which stagger their party into a loose
		# cluster at varied depths. Paired with DEPTH_SCALE so a unit staggered
		# "back" (negative offset, higher on screen) also shrinks and one
		# staggered "front" (positive, lower) grows — without that, moving a
		# same-size sprite up/down just reads as floating rather than standing
		# further back on the ground, since real perspective ties apparent
		# size to distance. Cycles if a side somehow has more than 4 living
		# units (never happens today, but harmless if it did).
		const DEPTH_STAGGER := [0.0, 20.0, -8.0, 28.0]
		const DEPTH_SCALE := [1.0, 1.1, 0.93, 1.15]

		var monster_wrappers: Dictionary = {}
		var monster_rects: Dictionary = {}
		var monster_zone_x: float = ARENA_SIZE.x * 0.66
		var monster_zone_w: float = ARENA_SIZE.x - monster_zone_x - 24.0
		var monster_step: float = monster_zone_w / max(1, monsters.size())
		for i in monsters.size():
			var m: Dictionary = monsters[i]
			var m_x: float = monster_zone_x + i * monster_step
			var depth_i := i % DEPTH_STAGGER.size()
			var m_ground: float = ground_y + DEPTH_STAGGER[depth_i]
			var m_size: int = clampi(int((56 + float(m["max_hp"]) / 2.5) * DEPTH_SCALE[depth_i]), 56, 110)
			var m_rect := _icon(GameData.sprite_for_monster(str(m["name"])), m_size)
			var m_wrapper := _wrap_icon(m_rect)
			m_wrapper.position = Vector2(m_x, m_ground - m_size)
			_add_ground_shadow(arena, m_wrapper.position, float(m_size))
			if float(m["hp"]) <= 0:
				m_wrapper.modulate = Color(0.35, 0.35, 0.35, 0.7)
			else:
				_start_idle_sway(m_wrapper)
			arena.add_child(m_wrapper)
			monster_wrappers[i] = m_wrapper
			monster_rects[i] = m_rect
			var m_plate_w: float = clampf(monster_step - 10.0, 70.0, 100.0)
			var m_plate := _status_plate(str(m["name"]), max(0, int(m["hp"])), int(m["max_hp"]), m_plate_w)
			var m_plate_pos := Vector2(m_x + m_size * 0.5 - m_plate_w * 0.5, m_ground - m_size - STATUS_PLATE_HEIGHT - 6.0)
			m_plate.position = m_plate_pos
			arena.add_child(m_plate)

			# A persistent badge for the boss's own mechanic(s) (Enraged/Warded/
			# Regenerating/Frenzied — an SS-rank+ mapped rift's boss can carry
			# two at once) or, for a regular monster, its MONSTER_ABILITIES
			# archetype (poison/healer/shielded/frenzy) — sitting on its status
			# plate all fight instead of only a transient text hint above the
			# action bar.
			var mechanic: Dictionary = m.get("mechanic", {})
			var mechanic2: Dictionary = m.get("mechanic2", {})
			var ability: Dictionary = m.get("ability", {})
			var badge_specs: Array[Dictionary] = []
			if not mechanic.is_empty():
				badge_specs.append({"icon": GameData.BOSS_MECHANIC_ICON.get(str(mechanic["id"]), ""), "tooltip": "%s — %s" % [str(mechanic["name"]), str(mechanic["desc"])]})
			if not mechanic2.is_empty():
				badge_specs.append({"icon": GameData.BOSS_MECHANIC_ICON.get(str(mechanic2["id"]), ""), "tooltip": "%s — %s" % [str(mechanic2["name"]), str(mechanic2["desc"])]})
			if mechanic.is_empty() and not ability.is_empty():
				badge_specs.append({"icon": GameData.MONSTER_ABILITY_ICON.get(str(ability["kind"]), ""), "tooltip": str(ability["name"])})
			for bi in badge_specs.size():
				var mech_icon_path: String = str(badge_specs[bi]["icon"])
				if mech_icon_path == "":
					continue
				var mech_badge := PanelContainer.new()
				var mech_style := StyleBoxFlat.new()
				mech_style.bg_color = Palette.SURFACE3
				mech_style.border_width_left = 1
				mech_style.border_width_top = 1
				mech_style.border_width_right = 1
				mech_style.border_width_bottom = 1
				mech_style.border_color = Palette.ELITE
				mech_style.corner_radius_top_left = 999
				mech_style.corner_radius_top_right = 999
				mech_style.corner_radius_bottom_left = 999
				mech_style.corner_radius_bottom_right = 999
				mech_badge.add_theme_stylebox_override("panel", mech_style)
				mech_badge.add_child(_icon(mech_icon_path, 14))
				mech_badge.position = m_plate_pos + Vector2(m_plate_w - 16.0 - bi * 20.0, -6.0)
				mech_badge.tooltip_text = str(badge_specs[bi]["tooltip"])
				arena.add_child(mech_badge)

		var hero_wrappers: Dictionary = {}
		var hero_rects: Dictionary = {}
		var hero_zone_x := 24.0
		var hero_zone_w: float = ARENA_SIZE.x * 0.34 - hero_zone_x
		var hero_step: float = hero_zone_w / max(1, living_heroes.size())
		var hero_base_size: float = clampf(84.0 - (living_heroes.size() - 1) * 8.0, 56.0, 84.0)
		var row_i := 0
		for h in party:
			if h.hp <= 0:
				continue
			var portrait_path := GameData.portrait_for_hero(h.cls_id, h.pool_id)
			if portrait_path == "":
				continue
			var h_x: float = hero_zone_x + row_i * hero_step
			var h_depth_i := row_i % DEPTH_STAGGER.size()
			var h_ground: float = ground_y + DEPTH_STAGGER[h_depth_i]
			var hero_size: float = hero_base_size * DEPTH_SCALE[h_depth_i]
			var h_rect := _icon(portrait_path, int(hero_size))
			var h_wrapper := _wrap_icon(h_rect)
			h_wrapper.position = Vector2(h_x, h_ground - hero_size)
			_add_ground_shadow(arena, h_wrapper.position, hero_size)
			arena.add_child(h_wrapper)
			_start_idle_sway(h_wrapper)
			hero_wrappers[h.id] = h_wrapper
			hero_rects[h.id] = h_rect
			var h_plate_w: float = clampf(hero_step - 6.0, 70.0, 100.0)
			var h_plate := _status_plate(h.name.split(" the ")[0], h.hp, Combat.max_hp(h), h_plate_w)
			h_plate.position = Vector2(h_x + hero_size * 0.5 - h_plate_w * 0.5, h_ground - hero_size - STATUS_PLATE_HEIGHT - 6.0)
			arena.add_child(h_plate)
			row_i += 1

		# A border frame overlay, drawn last so it sits on top of everything
		# else — gives the arena a clear "this is the screen" edge instead of
		# the background art just stopping with nothing marking the boundary.
		var frame := PanelContainer.new()
		var frame_style := StyleBoxFlat.new()
		frame_style.bg_color = Color(0, 0, 0, 0)
		frame_style.border_width_left = 3
		frame_style.border_width_top = 3
		frame_style.border_width_right = 3
		frame_style.border_width_bottom = 3
		frame_style.border_color = Palette.LINE
		frame.add_theme_stylebox_override("panel", frame_style)
		frame.custom_minimum_size = ARENA_SIZE
		frame.size = ARENA_SIZE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arena.add_child(frame)

		# A round counter banner across the top of the arena — the reference
		# battle screens announce "Round N" at the start of each round; ours
		# stays up the whole round instead of flashing in and fading, since
		# animating it would mean threading another tween through the already
		# carefully-sequenced _play_round animation chain for a cosmetic touch.
		var round_label := _label("Round %d" % (int(state.get("round_num", 0)) + 1), 16)
		round_label.size = Vector2(ARENA_SIZE.x, 22)
		round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		round_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		round_label.add_theme_constant_override("shadow_offset_x", 1)
		round_label.add_theme_constant_override("shadow_offset_y", 1)
		round_label.position = Vector2(0, 6)
		arena.add_child(round_label)
		v.add_child(arena)

		var incoming := Combat.describe_incoming(state)
		if incoming != "":
			v.add_child(_label(incoming, 12, true))

		if combat_selected_hero_id == "" or not living_heroes.any(func(h): return h.id == combat_selected_hero_id):
			combat_selected_hero_id = living_heroes[0].id if not living_heroes.is_empty() else ""

		# The action controls live in their own bordered panel below the
		# arena (reusing the same flat style the old side menu used — the
		# shared Theme's texture-based panel is tuned for fixed-size cards
		# and renders wrong at this panel's variable width/height).
		var menu_panel := PanelContainer.new()
		var menu_style := StyleBoxFlat.new()
		menu_style.bg_color = Palette.SURFACE2
		menu_style.border_width_left = 1
		menu_style.border_width_top = 1
		menu_style.border_width_right = 1
		menu_style.border_width_bottom = 1
		menu_style.border_color = Palette.LINE
		menu_style.corner_radius_top_left = 8
		menu_style.corner_radius_top_right = 8
		menu_style.corner_radius_bottom_right = 8
		menu_style.corner_radius_bottom_left = 8
		menu_style.content_margin_left = 10.0
		menu_style.content_margin_top = 10.0
		menu_style.content_margin_right = 10.0
		menu_style.content_margin_bottom = 10.0
		menu_panel.add_theme_stylebox_override("panel", menu_style)
		var menu := _vbox(6)
		menu_panel.add_child(menu)

		var pending: Dictionary = state["pending_actions"]

		# Hero tab row: click a tab to make that hero's full action bar show
		# below — every tab's badge icon reflects whatever action that hero
		# is currently set to, so the whole party's plan for this round is
		# visible without switching tabs (reused/repurposed from the
		# reference battle screens' turn-order strip — see _hero_action_tab).
		var tab_row := HBoxContainer.new()
		tab_row.add_theme_constant_override("separation", 8)
		for h in party:
			tab_row.add_child(_hero_action_tab(h, monsters, pending, h.id == combat_selected_hero_id))
		menu.add_child(tab_row)
		menu.add_child(_hsep())

		var sel_hero: Hero = null
		for h in living_heroes:
			if h.id == combat_selected_hero_id:
				sel_hero = h
		if sel_hero:
			var act: Dictionary = pending.get(sel_hero.id, {"action": "attack", "target": 0})
			var current_action: String = str(act.get("action", "attack"))
			var current_target: int = int(act.get("target", 0))

			var slots: Array = []
			for i in monsters.size():
				if float(monsters[i]["hp"]) <= 0:
					continue
				var target_name: String = str(monsters[i]["name"]).split(" ")[0]
				var attack_cb := func(hid=sel_hero.id, ti=i):
					GameState.set_hero_action(hid, "attack", ti)
					render()
				slots.append(_action_slot(GameData.sprite_for_monster(str(monsters[i]["name"])), "",
					current_action == "attack" and current_target == i, false,
					attack_cb, 64.0, "Atk %s" % target_name
				))
			if Combat.qualifies_for_ability(sel_hero):
				var cd: int = sel_hero.ability_cooldown
				var ability_name := str(GameData.SUBCLASS_ABILITIES.get(sel_hero.pool_id, {}).get("name", "Ability")).split(" ")[0]
				var ability_cb := func(hid=sel_hero.id):
					GameState.set_hero_action(hid, "ability")
					render()
				slots.append(_action_slot(GameData.ability_icon(sel_hero.pool_id), str(cd) if cd > 0 else "",
					current_action == "ability", cd > 0,
					ability_cb, 64.0, ability_name
				))
			var defend_cb := func(hid=sel_hero.id):
				GameState.set_hero_action(hid, "defend")
				render()
			slots.append(_action_slot("res://assets/skills/shield_basic.png", "",
				current_action == "defend", false,
				defend_cb, 64.0, "Defend"
			))
			menu.add_child(_slot_row(slots))
		else:
			menu.add_child(_label("The party is down.", 12, true))

		var bottom_row := HBoxContainer.new()
		bottom_row.add_child(_primary_button("Resolve Round", func():
			# Guard against a second click firing while the first is still
			# mid-animation — that would start a second _play_round on the same
			# state, and whichever finishes first would render() (destroying
			# the portrait nodes) out from under the other's suspended awaits.
			if _combat_animating:
				return
			_combat_animating = true
			# resolve_round_now() emits state_changed partway through, which is
			# normally connected straight to render() — that would tear down
			# the very portrait nodes _play_round is mid-animation on. Disconnect
			# for the duration and render once explicitly when it's done.
			if GameState.state_changed.is_connected(render):
				GameState.state_changed.disconnect(render)
			await _play_round(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects)
			if not GameState.state_changed.is_connected(render):
				GameState.state_changed.connect(render)
			_combat_animating = false
			render()
		))
		bottom_row.add_child(_button("Retreat", func():
			# Same guard as Resolve Round: retreating while a round's animation
			# is genuinely still in-flight would mutate the same `state` dict
			# _play_round is reading and immediately render() out from under
			# it, freeing the arena nodes its suspended awaits still reference.
			if _combat_animating:
				return
			GameState.combat_retreat()
			render()
		))
		menu.add_child(bottom_row)
		v.add_child(menu_panel)

		# The round log stays available but demoted — a strip below the action
		# bar rather than sharing equal billing with the arena, since none of
		# the reference battle screens foreground a scrolling log (damage
		# numbers/animations carry the moment-to-moment feedback now). Only
		# the most recent lines are rendered (rather than the whole fight's
		# log) and the box is tall enough for a typical round's worth of
		# lines, so reading "what just happened" doesn't actually require
		# scrolling — a fixed height still caps it so a long boss fight's full
		# log can't push the layout down the way it used to.
		var full_log: Array = state["log"]
		var recent_log: Array = full_log.slice(max(0, full_log.size() - 10))
		v.add_child(_log_richtext(recent_log, party, monsters, 130.0))
		return

	var result: Dictionary = ns["result"]
	var monster_row := HBoxContainer.new()
	monster_row.add_child(_icon(GameData.sprite_for_monster(str(result["monster_name"])), 28))
	monster_row.add_child(_label(str(result["monster_name"]), 14))
	v.add_child(monster_row)
	var log_party: Array[Hero] = GameState.current_party()
	v.add_child(_log_richtext(result["log"], log_party, [{"name": result["monster_name"]}]))

	var is_riftbreak: bool = GameState.run.get("is_riftbreak", false)
	if result["won"]:
		if is_riftbreak:
			# A Riftbreak is a consequence, not an opportunity — no loot, no
			# reward choice, straight back to the Terminal.
			v.add_child(_label("Threat repelled. The rift's spillover is contained — no loot from a fight like this."))
			v.add_child(_primary_button("Return to Terminal", func():
				GameState.finish_run()
				screen = "terminal"
				render()
			))
			return
		var bonus_crystal: int = result.get("bonus_crystal", 0)
		var victory_text := "Victory! +%d Coins, +%d Crystals" % [result["coin"], result["crystal"]]
		if bonus_crystal > 0:
			victory_text += " (+%d bonus)" % bonus_crystal
		v.add_child(_label(victory_text))
		var options: Array = result.get("reward_options", [])
		if not options.is_empty() and not ns.get("reward_chosen", false):
			v.add_child(_label("Choose a reward:"))
			for i in options.size():
				var opt: Dictionary = options[i]
				var obj = opt["obj"]
				var is_relic: bool = opt["loot_type"] == "relic"
				var desc: String = _loot_desc(obj, is_relic)
				var icon_path: String = GameData.RELIC_TYPE_ICON_PATH[obj.type] if is_relic else GameData.ITEM_CATEGORY_ICON_PATH[obj.category]
				var btn := _button("%s — %s" % [_loot_display_name(obj), desc], func(idx=i):
					GameState.pick_combat_reward(idx)
					render()
				)
				btn.icon = load(icon_path)
				v.add_child(btn)
		else:
			v.add_child(_primary_button("Continue", func():
				if is_boss:
					GameState.seal_rift()
				else:
					GameState.advance_node()
				render()
			))
	elif is_riftbreak and not result.get("retreated", false) and int(GameState.run.get("riftbreak_worst_index", 0)) >= 6:
		# Worst merged rank was S/SS/SSS — a forced game over, not a normal
		# loss. Fires immediately with no confirm step (unlike the voluntary
		# "Reset Guild" button) since this is a consequence, not a choice.
		# Excludes a retreat — walking away from the fight isn't the same as
		# losing it.
		v.add_child(_label("Due to the rift break, a large portion of the world is in struggle now. Your guild has been erased."))
		v.add_child(_primary_button("Found a New Guild", func():
			GameState.reset()
			GameState.save()
			screen = "onboard"
			render()
		))
	else:
		var defeat_text := "You withdraw from the fight." if result.get("retreated", false) else "Defeat — the party is downed and recovering."
		v.add_child(_label(defeat_text))
		if result.has("riftbreak_compensation_coins"):
			v.add_child(_label("You paid compensation to the other guilds to help close the rift. (-%d Coins, -%d Crystals)" % [int(result["riftbreak_compensation_coins"]), int(result["riftbreak_compensation_crystals"])], 12, true))
		for line in _run_summary_lines():
			v.add_child(_label(line, 12, true))
		v.add_child(_button("Return to Terminal", func():
			GameState.finish_run()
			screen = "terminal"
			render()
		))


func _render_shop_node(v: VBoxContainer) -> void:
	GameState.ensure_shop_offers()
	var ns: Dictionary = GameState.run["node_state"]
	v.add_child(_label("Rift Hallway Shop"))
	var offers: Array = ns["offers"]
	for i in offers.size():
		var off: Dictionary = offers[i]
		var obj = off["obj"]
		var is_relic: bool = off["loot_type"] == "relic"
		var desc: String = _loot_desc(obj, is_relic)
		var bought: bool = off.get("bought", false)
		var icon_path: String = GameData.RELIC_TYPE_ICON_PATH[obj.type] if is_relic else GameData.ITEM_CATEGORY_ICON_PATH[obj.category]
		var row := HBoxContainer.new()
		row.add_child(_icon(icon_path, 20))
		row.add_child(_label("%s — %s (%dc)%s" % [_loot_display_name(obj), desc, off["price"], " [bought]" if bought else ""]))
		if not bought:
			row.add_child(_button("Buy", func(idx=i):
				GameState.buy_shop_offer(idx)
				render()
			))
		v.add_child(row)
	v.add_child(_button("Continue", func():
		GameState.advance_node()
		render()
	))


## Hazard severity reads purely off dmg_mult (the one number that already
## drives how much this hazard actually hurts) — under 1.0 means the hazard
## is net-favorable to push through, up to +15% is a normal risk, anything
## higher is a real spike worth pausing on.
func _hazard_severity_color(dmg_mult: float) -> Color:
	if dmg_mult < 1.0:
		return Palette.RIFT
	elif dmg_mult <= 1.15:
		return Palette.GOLD
	return Palette.HAZARD


func _hazard_severity_label(dmg_mult: float) -> String:
	if dmg_mult < 1.0:
		return "Mild"
	elif dmg_mult <= 1.15:
		return "Moderate"
	return "Severe"


## A short recap for the two screens a run can end on (sealed or wiped/
## retreated) — floor reached, net currency change this run (coins/crystals/
## tokens can be spent as well as earned mid-run, e.g. at a shop, so "net
## change" is the honest framing, not "earned"), and heroes lost to Hardcore
## if any. Deliberately reads only numbers that already exist or are a cheap
## snapshot diff — no new combat-hot-path instrumentation.
func _run_summary_lines() -> Array[String]:
	var lines: Array[String] = []
	var layers: Array = GameState.run.get("layers", [])
	if not layers.is_empty():
		lines.append("Floor %d/%d reached" % [int(GameState.run.get("pos", 0)) + 1, layers.size()])
	var coin_delta := GameState.coins - int(GameState.run.get("start_coins", GameState.coins))
	var crystal_delta := GameState.crystals - int(GameState.run.get("start_crystals", GameState.crystals))
	var token_delta := GameState.tokens - int(GameState.run.get("start_tokens", GameState.tokens))
	lines.append("%+d Coins, %+d Crystals, %+d Tokens this run" % [coin_delta, crystal_delta, token_delta])
	var lost := int(GameState.run.get("heroes_lost", 0))
	if lost > 0:
		lines.append("%d hero%s lost" % [lost, "es" if lost > 1 else ""])
	return lines


func _render_hazard_node(v: VBoxContainer) -> void:
	GameState.ensure_hazard()
	var ns: Dictionary = GameState.run["node_state"]
	var hz: Dictionary = ns["hazard"]
	var bg_path: String = GameData.HAZARD_BG.get(str(hz["id"]), "")
	if bg_path != "":
		v.add_child(_banner(bg_path, 700, 190))

	var dmg_mult: float = float(hz["dmg_mult"])
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(_label(str(hz["name"]), 16))
	var sev_label := _label(_hazard_severity_label(dmg_mult), 12)
	sev_label.add_theme_color_override("font_color", _hazard_severity_color(dmg_mult))
	name_row.add_child(sev_label)
	v.add_child(name_row)

	if not ns.get("resolved", false):
		var choice_row := HBoxContainer.new()
		choice_row.add_theme_constant_override("separation", 8)
		choice_row.add_child(_button("Push Through", func():
			GameState.push_through_hazard()
			render()
		))
		var bypass_btn := _button("Bypass (%d Crystals)" % GameState.HAZARD_BYPASS_COST, func():
			GameState.bypass_hazard()
			render()
		)
		bypass_btn.disabled = not GameState.can_afford_hazard_bypass()
		choice_row.add_child(bypass_btn)
		choice_row.add_child(_button("Risk it for Loot", func():
			GameState.risk_hazard()
			render()
		))
		v.add_child(choice_row)
	else:
		for line in ns.get("log", []):
			v.add_child(_label(str(line), 12))
		v.add_child(_primary_button("Continue", func():
			GameState.advance_node()
			render()
		))


# ---------------- Terminal ----------------
func _render_terminal(v: VBoxContainer) -> void:
	_topbar(v)
	var tier := Combat.guild_tier_info()
	var tier_line := "%s — %d levels purchased" % [tier["name"], tier["total"]]
	if not tier["next"].is_empty():
		tier_line += " (%d to %s)" % [int(tier["next"]["min"]) - int(tier["total"]), tier["next"]["name"]]
	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 6)
	var tier_icon_path: String = GameData.GUILD_TIER_ICON.get(str(tier["name"]), "")
	if tier_icon_path != "":
		tier_row.add_child(_icon(tier_icon_path, 18))
	tier_row.add_child(_label(tier_line, 12, true))
	v.add_child(tier_row)

	if term_tab == "camp":
		_render_camp(v)
		return

	v.add_child(_button("< Back to Camp", func():
		term_tab = "camp"
		medical_picker_bed = -1
		mgmt_branch = ""
		inv_category = ""
		render()
	))
	v.add_child(_hsep())
	match term_tab:
		"inventory": _render_inventory(v)
		"recruits": _render_recruits(v)
		"medical": _render_medical_bay(v)
		"management": _render_management(v)
		_: _render_roster(v)


## The guild hub: a camp scene with one clickable icon-button per section,
## replacing the old plain row of tab buttons. Buttons are placed with
## explicit positions over the background the same way the battle arena
## places its sprites (a plain Control, not a layout Container).
func _render_camp(v: VBoxContainer) -> void:
	v.add_child(_label("Guild Name", 12, true))
	v.add_child(_label(GameState.guild_name, 20))

	var camp_size := Vector2(700, 340)
	var camp := Control.new()
	camp.custom_minimum_size = camp_size

	var bg := TextureRect.new()
	bg.texture = load(GameData.CAMP_BG)
	bg.custom_minimum_size = camp_size
	bg.size = camp_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	camp.add_child(bg)

	# 5 of the 6 sections click on a prop already drawn in the background art
	# itself (no separate icon layered on top) — rect positions hand-picked
	# against camp_bg.png: the angled green tent lower-left (Medical Bay),
	# the pointy green tent above it (Roster), the crossed swords near the
	# banners (Inventory), the campfire (Hero Recruits), and the lighter tan
	# tent on the right (Guild Management). Rift Hall has no matching prop in
	# the scene, so it keeps its own generated portal icon.
	# hit_rect is the generous, easy-to-click area; native_rect is the prop's
	# own tight bounds *in the source 320x200 camp_bg.png* — used only to
	# place the hover glow over the object's actual silhouette rather than
	# the whole padded hitbox.
	var area_entries := [
		["Medical Bay", Rect2(14, 132, 171, 98), Rect2(18, 80, 72, 46), func(): term_tab = "medical"; render()],
		["Roster", Rect2(182, 99, 132, 60), Rect2(83, 58, 61, 36), func(): term_tab = "roster"; render()],
		["Inventory", Rect2(376, 111, 62, 42), Rect2(160, 58, 35, 32), func(): term_tab = "inventory"; render()],
		["Hero Recruits", Rect2(314, 193, 94, 79), Rect2(143, 113, 45, 48), func(): term_tab = "recruits"; render()],
		["Guild Management", Rect2(459, 105, 117, 76), Rect2(210, 62, 54, 45), func(): term_tab = "management"; render()],
	]
	var camp_scale := Vector2(700.0 / 320.0, 340.0 / 200.0)
	for entry in area_entries:
		var label_text: String = entry[0]
		var rect: Rect2 = entry[1]
		var native_rect: Rect2 = entry[2]
		var cb: Callable = entry[3]
		var glow_rect := Rect2(
			native_rect.position.x * camp_scale.x, native_rect.position.y * camp_scale.y,
			native_rect.size.x * camp_scale.x, native_rect.size.y * camp_scale.y
		)
		var hotspot := _camp_area_hotspot(rect, glow_rect, label_text, cb)
		hotspot.position = rect.position
		camp.add_child(hotspot)

	# Bottom-left, in the open ground below the small griffin banner-post and
	# its nearby crates/barrels.
	var rift_icon := _camp_hotspot(GameData.CAMP_HUB_ICON_PATH["rift"], 56.0, "Rift Hall (Training Ground)", func(): screen = "rift_hall"; render())
	rift_icon.position = Vector2(150, 270) - Vector2(28, 28)
	camp.add_child(rift_icon)

	# No matching background prop for this one either — placed a bit further
	# right along the same open ground as the Rift Hall icon above.
	var rift_map_icon := _camp_hotspot(GameData.CAMP_HUB_ICON_PATH["rift_map"], 56.0, "Rift Map", func(): screen = "rift_map"; render())
	rift_map_icon.position = Vector2(230, 270) - Vector2(28, 28)
	camp.add_child(rift_map_icon)

	v.add_child(camp)


## An invisible clickable region over a prop already drawn in the background
## art — the prop itself stays untouched (no duplicated/cropped copy of it,
## which read as an awkward seam when scaled). Hovering instead fades in a
## soft blurred glow (StyleBoxFlat's built-in shadow, not a hard-edged box)
## around the prop's own silhouette bounds, like it's catching firelight.
func _camp_area_hotspot(hit_rect: Rect2, glow_rect: Rect2, label_text: String, cb: Callable) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(hit_rect.size.x, hit_rect.size.y + 16)
	wrap.size = Vector2(hit_rect.size.x, hit_rect.size.y + 16)

	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(0, 0, 0, 0)
	glow_style.shadow_color = Color(1.0, 0.85, 0.55, 0.0)
	glow_style.shadow_size = 14
	glow_style.corner_radius_top_left = 10
	glow_style.corner_radius_top_right = 10
	glow_style.corner_radius_bottom_left = 10
	glow_style.corner_radius_bottom_right = 10

	var glow := Panel.new()
	glow.add_theme_stylebox_override("panel", glow_style)
	glow.position = glow_rect.position - hit_rect.position
	glow.size = glow_rect.size
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(glow)

	var btn := Button.new()
	btn.flat = true
	btn.text = ""
	btn.custom_minimum_size = hit_rect.size
	btn.size = hit_rect.size
	var clear_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style_name, clear_style)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(cb)
	btn.mouse_entered.connect(func():
		var tw := create_tween()
		tw.tween_method(func(a): glow_style.shadow_color = Color(1.0, 0.85, 0.55, a), 0.0, 0.3, 0.15)
	)
	btn.mouse_exited.connect(func():
		var tw := create_tween()
		tw.tween_method(func(a): glow_style.shadow_color = Color(1.0, 0.85, 0.55, a), 0.3, 0.0, 0.15)
	)
	wrap.add_child(btn)

	var caption := _label(label_text, 11, true)
	caption.position = Vector2(0, hit_rect.size.y + 1)
	caption.custom_minimum_size = Vector2(hit_rect.size.x, 0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(caption)

	return wrap


## The camp's one icon-based hotspot (Rift Hall, no matching background
## prop) — a bare TextureButton (no Button chrome/box) with a caption label
## underneath and a hover brighten for click affordance.
func _camp_hotspot(icon_path: String, size: float, label_text: String, cb: Callable) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(size, size + 18)
	wrap.size = Vector2(size, size + 18)

	var tb := TextureButton.new()
	tb.texture_normal = load(icon_path)
	tb.ignore_texture_size = true
	tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	tb.custom_minimum_size = Vector2(size, size)
	tb.size = Vector2(size, size)
	tb.pivot_offset = Vector2(size, size) / 2.0
	tb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tb.pressed.connect(cb)
	tb.mouse_entered.connect(func():
		var tw := create_tween()
		tw.tween_property(tb, "scale", Vector2(1.1, 1.1), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	)
	tb.mouse_exited.connect(func():
		var tw := create_tween()
		tw.tween_property(tb, "scale", Vector2(1, 1), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	)
	wrap.add_child(tb)

	var caption := _label(label_text, 11, true)
	caption.position = Vector2(0, size + 2)
	caption.custom_minimum_size = Vector2(size, 0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(caption)

	return wrap


func _render_recruits(v: VBoxContainer) -> void:
	v.add_child(_label("Hero Recruits — %d/%d roster slots" % [GameState.heroes.size(), GameState.hero_slot_cap()]))
	for h in GameState.recruit_pool:
		var rank := GameData.find_rank(h.rank)
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Palette.SURFACE2
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Palette.LINE
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_right = 8
		style.corner_radius_bottom_left = 8
		style.content_margin_left = 8.0
		style.content_margin_top = 6.0
		style.content_margin_right = 8.0
		style.content_margin_bottom = 6.0
		card.add_theme_stylebox_override("panel", style)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_framed_portrait(h.cls_id, h.pool_id, 56.0))
		var mid := _vbox(2)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_child(_label(h.name, 13))
		mid.add_child(_label("Rank %s %s · %dc" % [h.rank, h.cls_id.capitalize(), int(rank["cost"])], 11, true))
		row.add_child(mid)
		row.add_child(_primary_button("Recruit", func(id=h.id):
			var err := GameState.recruit_hero(id)
			if err != "":
				push_warning(err)
			render()
		))
		card.add_child(row)
		v.add_child(card)


func _render_medical_bay(v: VBoxContainer) -> void:
	v.add_child(_label("Medical Bay — %d/%d beds occupied" % [GameState.occupied_beds(), GameState.medical_bed_cap()], 16))
	if GameState.field_triage_available():
		v.add_child(_button("Field Triage (heal whole roster, once per rift cycle)%s" % ("" if not GameState.triage_used_this_cycle else " [used]"), func():
			var err := GameState.field_triage_action()
			if err != "":
				push_warning(err)
			render()
		))

	var scene_size := Vector2(700, 200)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size

	var bg := TextureRect.new()
	bg.texture = load(GameData.MEDICAL_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)

	var bedded: Array[Hero] = []
	bedded.assign(GameState.heroes.filter(func(h): return GameState.needs_recovery(h) and h.bedded))
	var waiting: Array[Hero] = []
	waiting.assign(GameState.heroes.filter(func(h): return GameState.needs_recovery(h) and not h.bedded))

	var cap := GameState.medical_bed_cap()
	var bed_w := 64.0
	var bed_h := 40.0
	var gap: float = (scene_size.x - cap * bed_w) / (cap + 1)
	var now_ms := int(Time.get_unix_time_from_system() * 1000)
	for i in cap:
		var bx: float = gap + i * (bed_w + gap)
		var by := scene_size.y - bed_h - 24.0
		var bed_rect := _icon(GameData.BED_ICON, int(bed_w))
		var bed_wrap := _wrap_icon(bed_rect)
		bed_wrap.position = Vector2(bx, by)

		if i < bedded.size():
			var h: Hero = bedded[i]
			bed_rect.modulate = Color(0.8, 0.85, 1.0)
			scene.add_child(bed_wrap)
			var until: int = h.downed_until if h.is_downed() else h.heal_until
			var secs: int = max(0, int((until - now_ms) / 1000.0))
			var name_label := _label(h.name, 10, true)
			name_label.position = Vector2(bx - 10, by + bed_h + 2)
			scene.add_child(name_label)
			var time_label := _label("%ds" % secs, 10, true)
			time_label.position = Vector2(bx - 10, by + bed_h + 16)
			scene.add_child(time_label)
		else:
			scene.add_child(bed_wrap)
			var bed_btn := _button("", func(idx=i):
				medical_picker_bed = -1 if medical_picker_bed == idx else idx
				render()
			)
			bed_btn.flat = true
			bed_btn.custom_minimum_size = Vector2(bed_w, bed_h)
			bed_btn.size = Vector2(bed_w, bed_h)
			bed_btn.position = Vector2(bx, by)
			var clear_style := StyleBoxEmpty.new()
			for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
				bed_btn.add_theme_stylebox_override(style_name, clear_style)
			bed_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			scene.add_child(bed_btn)
			var empty_label := _label("Empty", 10, true)
			empty_label.position = Vector2(bx + 6, by + bed_h + 2)
			scene.add_child(empty_label)

	v.add_child(scene)

	if medical_picker_bed >= 0 and medical_picker_bed < cap:
		var picker := _vbox(4)
		if waiting.is_empty():
			picker.add_child(_label("No wounded heroes waiting for a bed.", 12, true))
		else:
			picker.add_child(_label("Assign to bed %d:" % (medical_picker_bed + 1), 12, true))
			for h in waiting:
				var status := "downed" if h.is_downed() else "wounded"
				var row := HBoxContainer.new()
				row.add_child(_label("%s — %d/%d HP (%s)" % [h.name, h.hp, Combat.max_hp(h), status]))
				row.add_child(_primary_button("Assign", func(id=h.id):
					GameState.assign_to_bed(id)
					medical_picker_bed = -1
					render()
				))
				picker.add_child(row)
		v.add_child(picker)

	if medical_picker_bed == -1 and not waiting.is_empty():
		v.add_child(_label("Recovering without a bed (slower):", 12, true))
		for h in waiting:
			v.add_child(_label("%s — %d/%d HP" % [h.name, h.hp, Combat.max_hp(h)], 12))


func _render_management(v: VBoxContainer) -> void:
	if mgmt_branch == "":
		_render_management_hub(v)
		return

	var branch: Dictionary = {}
	for b in GameData.BRANCHES:
		if b["id"] == mgmt_branch:
			branch = b
	v.add_child(_button("< Back to Branches", func(): mgmt_branch = ""; render()))
	v.add_child(_banner(GameData.BRANCH_BANNER[mgmt_branch], 700, 150))
	v.add_child(_label("%s — %s" % [branch["name"], branch["sub"]], 16))
	for n in branch["nodes"]:
		_render_management_node(v, branch, n)


## The 4 Guild Management branches as clickable stations on a war-room scene
## (a soldier's kit for Operations, gears/blueprints for Infrastructure, a
## coin pouch/ledger for Logistics, a spellbook/crystal for Research) — same
## background-prop-as-button + hover-glow pattern as the camp screen.
func _render_management_hub(v: VBoxContainer) -> void:
	var scene_size := Vector2(700, 340)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size

	var bg := TextureRect.new()
	bg.texture = load(GameData.MANAGEMENT_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)

	# hit_rect (a generous quadrant of the round table, easy to click) +
	# native_rect (the station's own tight prop bounds in the source 320x200
	# art — helmet+sword north, gears+blueprint east, coin pouch+ledger
	# south, crystal+book west — used only to place the hover glow).
	var branch_entries := [
		["ops", "Operations", Rect2(180, 0, 280, 115), Rect2(97, 7, 96, 45)],
		["infra", "Infrastructure", Rect2(460, 60, 240, 170), Rect2(223, 52, 62, 71)],
		["log", "Logistics", Rect2(180, 210, 280, 130), Rect2(102, 133, 121, 34)],
		["res", "Research", Rect2(0, 60, 220, 170), Rect2(30, 50, 57, 67)],
	]
	var camp_scale := Vector2(700.0 / 320.0, 340.0 / 200.0)
	for entry in branch_entries:
		var bid: String = entry[0]
		var label_text: String = entry[1]
		var hit_rect: Rect2 = entry[2]
		var native_rect: Rect2 = entry[3]
		var glow_rect := Rect2(
			native_rect.position.x * camp_scale.x, native_rect.position.y * camp_scale.y,
			native_rect.size.x * camp_scale.x, native_rect.size.y * camp_scale.y
		)
		var hotspot := _camp_area_hotspot(hit_rect, glow_rect, label_text, func(id=bid):
			mgmt_branch = id
			render()
		)
		hotspot.position = hit_rect.position
		scene.add_child(hotspot)

	v.add_child(scene)

	var reset_btn := _button("Click again to confirm reset" if confirm_reset else "Reset Guild", func():
		if not confirm_reset:
			confirm_reset = true
			render()
			get_tree().create_timer(3.0).timeout.connect(func():
				confirm_reset = false
				if screen == "terminal" and term_tab == "management" and mgmt_branch == "":
					render()
			)
			return
		confirm_reset = false
		GameState.reset()
		GameState.save()
		screen = "onboard"
		render()
	)
	v.add_child(reset_btn)


## One upgrade node's display line + Upgrade/capstone buttons.
func _render_management_node(v: VBoxContainer, branch: Dictionary, n: Dictionary) -> void:
	var key := "%s.%s" % [branch["id"], n["id"]]
	var cur := GameState.lvl(key)
	var maxed := cur >= int(n["max"])

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon_path: String = GameData.MANAGEMENT_NODE_ICON.get(key, "")
	if icon_path != "":
		row.add_child(_icon(icon_path, 28))

	var col := _vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cur_desc := Combat.describe_node_effect(n["id"], cur)
	var line := "%s (Lvl %d/%d) — %s" % [n["name"], cur, n["max"], cur_desc]
	if not maxed:
		line += " → %s" % Combat.describe_node_effect(n["id"], cur + 1)
	col.add_child(_label(line, 12))
	var brow := HBoxContainer.new()
	if not maxed:
		var cost: int = int(n["cost_base"]) + int(n["cost_step"]) * cur
		brow.add_child(_button("Upgrade (%dcr)" % cost, func(k=key):
			var err := GameState.upgrade_node(k)
			if err != "":
				push_warning(err)
			render()
		))
	var cap: Dictionary = n.get("cap", {})
	if not cap.is_empty() and maxed and not GameState.has_cap(key):
		brow.add_child(_button("%s (%dcr) — %s" % [cap["name"], int(cap["cost"]), cap["desc"]], func(k=key):
			var err := GameState.buy_cap(k)
			if err != "":
				push_warning(err)
			render()
		))
	elif not cap.is_empty() and GameState.has_cap(key):
		brow.add_child(_label("%s unlocked" % cap["name"], 12))
	col.add_child(brow)
	row.add_child(col)
	v.add_child(row)


## A small button that cycles through `options` (each {id, label}) and calls
## `on_change(new_id)` — shared by the Roster and Inventory tabs' Sort
## controls so both screens follow the same "click to cycle" pattern instead
## of a dropdown neither otherwise uses in this UI.
func _sort_cycle_button(current: String, options: Array, on_change: Callable) -> Button:
	var idx := 0
	for i in options.size():
		if options[i]["id"] == current:
			idx = i
	return _button("Sort: %s" % str(options[idx]["label"]), func():
		var next_idx: int = (idx + 1) % options.size()
		on_change.call(options[next_idx]["id"])
		render()
	)


func _sorted_heroes() -> Array[Hero]:
	var out: Array[Hero] = []
	out.assign(GameState.heroes)
	match roster_sort:
		"power":
			out.sort_custom(func(a, b): return Combat.power_of(a) > Combat.power_of(b))
		"level":
			out.sort_custom(func(a, b): return a.level > b.level)
		"rank":
			out.sort_custom(func(a, b): return float(GameData.find_rank(a.rank)["mult"]) > float(GameData.find_rank(b.rank)["mult"]))
	return out


func _render_roster(v: VBoxContainer) -> void:
	v.add_child(_banner(GameData.ROSTER_BG, 760, 190))
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes recruited yet."))
		return

	var still_here: Array[Hero] = []
	still_here.assign(GameState.heroes.filter(func(h): return h.id == selected_hero_id))
	if still_here.is_empty():
		selected_hero_id = ""

	v.add_child(_sort_cycle_button(roster_sort, [
		{"id": "power", "label": "Power"},
		{"id": "level", "label": "Level"},
		{"id": "rank", "label": "Rank"},
	], func(new_id): roster_sort = new_id))

	var portrait_row := HBoxContainer.new()
	portrait_row.add_theme_constant_override("separation", 12)
	for h in _sorted_heroes():
		portrait_row.add_child(_roster_portrait_button(h))
	v.add_child(portrait_row)

	if selected_hero_id == "":
		v.add_child(_label("Click a hero above for their details.", 12, true))
		return
	var h: Hero = still_here[0]

	var card := PanelContainer.new()
	var cv := _vbox(4)
	cv.add_child(_title_strip(h.name))
	cv.add_child(_label("Lv%d %s (%s) · %d/%d HP" % [h.level, h.cls_id.capitalize(), h.rank, h.hp, Combat.max_hp(h)]))
	cv.add_child(_label("Trait: %s" % (h.trait_name if h.trait_name != "" else "Steadfast"), 12, true))
	for scar_name in h.scars:
		var scar_row := HBoxContainer.new()
		scar_row.add_child(_label("Scar: %s" % scar_name, 12, true))
		scar_row.add_child(_button("Scrub (30c)", func(id=h.id, sn=scar_name):
			var err := GameState.scrub_scar(id, sn)
			if err != "":
				push_warning(err)
			render()
		))
		cv.add_child(scar_row)

	# Portrait + a live stat readout side by side, framed with the same
	# PORTRAIT_FRAME_PATH art the paper-doll design has been carrying unused
	# since it was first generated — every number here is the real derived
	# stat (Combat.power_of/max_hp/hero_skill_total), not a fantasy stat this
	# game doesn't track.
	var visual_row := HBoxContainer.new()
	visual_row.add_theme_constant_override("separation", 14)
	visual_row.add_child(_framed_portrait(h.cls_id, h.pool_id, 96.0))
	var stats_v := _vbox(2)
	stats_v.add_child(_label("Power %d" % Combat.power_of(h), 13))
	stats_v.add_child(_label("HP %d/%d" % [h.hp, Combat.max_hp(h)], 12, true))
	for kind in GameData.BUILD_KINDS:
		var total := Combat.hero_skill_total(h, kind)
		if total != 0.0:
			stats_v.add_child(_label(Combat.describe_skill(kind, total), 11, true))
	visual_row.add_child(stats_v)
	cv.add_child(visual_row)

	var actions := HBoxContainer.new()
	actions.add_child(_button("Reroll Trait (60c)", func(id=h.id):
		var err := GameState.reroll_trait(id)
		if err != "":
			push_warning(err)
		render()
	))
	if h.trait_name != "":
		actions.add_child(_button("Scrub Trait (30c)", func(id=h.id):
			var err := GameState.scrub_trait(id)
			if err != "":
				push_warning(err)
			render()
		))
	actions.add_child(_button("Skills" if expanded_skill_hero != h.id else "Hide Skills", func(id=h.id):
		expanded_skill_hero = "" if expanded_skill_hero == id else id
		render()
	))
	if h.level >= 10:
		var cur_cls := GameData.find_class(h.pool_id)
		if not cur_cls.is_empty() and not GameState.evolution_target(cur_cls).is_empty():
			var next_cls := GameState.evolution_target(cur_cls)
			var next_rank := GameData.find_rank(next_cls["rank"])
			actions.add_child(_button("Evolve → %s (%dcr)" % [next_cls["name"], int(next_rank["cost"])], func(id=h.id):
				var err := GameState.evolve_hero(id)
				if err != "":
					push_warning(err)
				render()
			))
	cv.add_child(actions)

	if expanded_skill_hero == h.id:
		cv.add_child(_hsep())
		if GameData.SUBCLASS_ABILITIES.has(h.pool_id):
			var ab: Dictionary = GameData.SUBCLASS_ABILITIES[h.pool_id]
			var ab_row := HBoxContainer.new()
			ab_row.add_theme_constant_override("separation", 8)
			ab_row.add_child(_icon(GameData.ability_icon(h.pool_id), 28))
			var ab_mid := _vbox(0)
			ab_mid.add_child(_label("Ability: %s" % str(ab["name"]), 12))
			ab_mid.add_child(_label(str(ab["desc"]), 11, true))
			ab_row.add_child(ab_mid)
			if h.level < 3:
				ab_row.add_child(_label("Unlocks at Lv3", 11, true))
			cv.add_child(ab_row)
			cv.add_child(_hsep())
		cv.add_child(_label("Skill Points: %d" % h.skill_points, 12))
		var tree: Array = GameData.subclass_skill_tree(h.pool_id)
		var tier_label := {1: "Tier 1", 2: "Tier 2", 3: "Capstone"}
		var cur_tier := -1
		for n in tree:
			var tier: int = int(n["tier"])
			if tier != cur_tier:
				cur_tier = tier
				cv.add_child(_label(str(tier_label.get(tier, "")), 11, true))
			cv.add_child(_skill_node_row(h, n))
		var spent: int = h.skills.values().count(true)
		if spent > 0:
			cv.add_child(_button("Respec (%dc)" % GameState.respec_cost(spent), func(id=h.id):
				var err := GameState.respec_hero(id)
				if err != "":
					push_warning(err)
				render()
			))

	cv.add_child(_hsep())
	cv.add_child(_label("Weapon", 12, true))
	var weapon_row := HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 8)
	for i in GameData.weapon_slots(h.pool_id):
		weapon_row.add_child(_equip_slot_frame(h, "weapon", i))
	cv.add_child(weapon_row)
	if expanded_slot.begins_with("weapon:"):
		_render_equip_picker(cv, h, "weapon", int(expanded_slot.split(":")[1]))

	cv.add_child(_label("Gear", 12, true))
	var gear_row := HBoxContainer.new()
	gear_row.add_theme_constant_override("separation", 8)
	for i in GameData.gear_slots(h.rank):
		gear_row.add_child(_equip_slot_frame(h, "gear", i))
	cv.add_child(gear_row)
	if expanded_slot.begins_with("gear:"):
		_render_equip_picker(cv, h, "gear", int(expanded_slot.split(":")[1]))

	card.add_child(cv)
	v.add_child(card)


## One skill-tree node: icon + name/effect/requirement in a bordered row,
## with a Learn button that disables itself (showing why) instead of only
## failing after the click — level/prereq/SP gating mirrors learn_skill()'s
## own checks exactly so the row never promises something a click can't do.
func _skill_node_row(h: Hero, n: Dictionary) -> PanelContainer:
	var skill_id: String = n["id"]
	var learned: bool = h.skills.get(skill_id, false)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.SURFACE2 if not learned else Palette.SURFACE3
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Palette.RIFT if learned else Palette.LINE
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 6
	style.content_margin_top = 4
	style.content_margin_right = 6
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_icon(str(n["icon"]), 28))

	var mid := _vbox(0)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(_label(str(n["name"]), 12))
	mid.add_child(_label(Combat.describe_skill(str(n["kind"]), float(n["value"])), 11, true))
	row.add_child(mid)

	if learned:
		row.add_child(_label("Learned", 11, true))
	else:
		var missing_level: bool = h.level < int(n["req_level"])
		var missing_prereq := false
		for req in n["requires"]:
			if not h.skills.get(req, false):
				missing_prereq = true
		var missing_sp: bool = h.skill_points < int(n["cost"])
		var reason := ""
		if missing_level:
			reason = "Requires Lv%d" % int(n["req_level"])
		elif missing_prereq:
			reason = "Needs prerequisite"
		elif missing_sp:
			reason = "Needs %d SP" % int(n["cost"])
		if reason != "":
			row.add_child(_label(reason, 11, true))
		else:
			var learn_btn := _button("Learn (%d SP)" % int(n["cost"]), func(hid=h.id, sid=skill_id):
				var err := GameState.learn_skill(hid, sid)
				if err != "":
					push_warning(err)
				render()
			)
			learn_btn.add_theme_font_size_override("font_size", 11)
			row.add_child(learn_btn)

	panel.add_child(row)
	return panel


## One hero's clickable portrait for the Roster row — a PanelContainer
## (bordered/highlighted when selected) with a flat invisible Button on top,
## same layered-hotspot approach as the camp/management screens.
func _roster_portrait_button(h: Hero) -> Control:
	var w := 72.0
	var ht := 100.0
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(w, ht)
	wrap.size = Vector2(w, ht)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, ht)
	panel.size = Vector2(w, ht)
	if selected_hero_id == h.id:
		var sel_style := StyleBoxFlat.new()
		sel_style.bg_color = Palette.SURFACE2
		sel_style.border_width_left = 2
		sel_style.border_width_top = 2
		sel_style.border_width_right = 2
		sel_style.border_width_bottom = 2
		sel_style.border_color = Palette.RIFT
		sel_style.corner_radius_top_left = 8
		sel_style.corner_radius_top_right = 8
		sel_style.corner_radius_bottom_left = 8
		sel_style.corner_radius_bottom_right = 8
		sel_style.content_margin_top = 4
		panel.add_theme_stylebox_override("panel", sel_style)
	var pv := _vbox(2)
	var portrait_path := GameData.portrait_for_hero(h.cls_id, h.pool_id)
	if portrait_path != "":
		var icon_wrap := CenterContainer.new()
		icon_wrap.add_child(_icon(portrait_path, 48))
		pv.add_child(icon_wrap)
	pv.add_child(_label(h.name.split(" the ")[0], 10))
	pv.add_child(_label("%d/%d HP" % [h.hp, Combat.max_hp(h)], 9, true))
	panel.add_child(pv)
	wrap.add_child(panel)

	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(w, ht)
	btn.size = Vector2(w, ht)
	var clear_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style_name, clear_style)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(func(id=h.id):
		selected_hero_id = "" if selected_hero_id == id else id
		expanded_slot = ""
		render()
	)
	wrap.add_child(btn)
	return wrap


func _first_free_slot(h: Hero, slot_type: String) -> int:
	var cap := GameData.weapon_slots(h.pool_id) if slot_type == "weapon" else GameData.gear_slots(h.rank)
	var used := {}
	for it in GameState.items:
		if it.equipped_to == h.id and it.slot_type() == slot_type:
			used[it.equipped_idx] = true
	for i in cap:
		if not used.has(i):
			return i
	return -1


func _find_equipped_at(hero_id: String, slot_type: String, idx: int) -> Item:
	for it in GameState.items:
		if it.equipped_to == hero_id and it.slot_type() == slot_type and it.equipped_idx == idx:
			return it
	return null


## One equip-slot frame for the Roster paper-doll: a rarity-tinted border
## (RARITY_FRAME_PATH — "common" when empty) with the equipped item's category
## icon centered inside (blank when empty) and a short caption underneath
## (the item's first name word, or "Weapon"/"Gear" when empty) so the slot
## reads without opening anything. Clicking toggles this slot's inline
## equip-picker below the row — same expand/collapse pattern already used for
## the Skills button and Medical Bay's bed picker.
func _equip_slot_frame(h: Hero, slot_type: String, idx: int, size: float = 56.0) -> Control:
	var equipped := _find_equipped_at(h.id, slot_type, idx)
	var slot_key := "%s:%d" % [slot_type, idx]
	var is_open := expanded_slot == slot_key
	var label_text := equipped.name.split(" ")[0] if equipped else ("Weapon" if slot_type == "weapon" else "Gear")
	var icon_path: String = GameData.ITEM_CATEGORY_ICON_PATH[equipped.category] if equipped else ""
	var cb := func():
		expanded_slot = "" if is_open else slot_key
		render()
	return _action_slot(icon_path, "", is_open, false, cb, size, label_text)


## The picker for whichever equip slot is currently expanded: shows the
## equipped item (with Unequip + matching Socket options) if any, then every
## unequipped item that fits this hero and slot with an Equip button — reuses
## GameState.equip_item/item_fits_hero exactly like the old Inventory-tab
## "Equip →" flow did, just triggered from the hero's own card instead.
func _render_equip_picker(cv: VBoxContainer, h: Hero, slot_type: String, idx: int) -> void:
	var equipped := _find_equipped_at(h.id, slot_type, idx)
	var picker := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.SURFACE3
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Palette.RIFT
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
	picker.add_theme_stylebox_override("panel", style)
	var pv := _vbox(4)

	if equipped:
		var erow := HBoxContainer.new()
		erow.add_theme_constant_override("separation", 8)
		erow.add_child(_icon(GameData.ITEM_CATEGORY_ICON_PATH[equipped.category], 18))
		erow.add_child(_label("%s (%s) — %s" % [_loot_display_name(equipped), GameData.ITEM_CATEGORY_LABEL[equipped.category], _loot_desc(equipped, false)], 12))
		pv.add_child(erow)
		var eactions := HBoxContainer.new()
		eactions.add_child(_button("Unequip", func(hid=h.id, st=slot_type, i=idx):
			GameState.equip_item(hid, st, i, "")
			render()
		))
		if equipped.socketed_kind != "":
			eactions.add_child(_label("Socketed: %s" % Combat.describe_skill(equipped.socketed_kind, equipped.socketed_value), 11, true))
		else:
			for r in GameState.runestones:
				var rdef := GameData.find_runestone(str(r["runestone_id"]))
				if rdef.get("category", "") != slot_type:
					continue
				eactions.add_child(_button("Socket %s" % str(rdef["name"]), func(rid=r["id"], iid=equipped.id):
					var err := GameState.socket_runestone(rid, iid)
					if err != "":
						push_warning(err)
					render()
				))
		pv.add_child(eactions)
		pv.add_child(_hsep())

	var candidates: Array[Item] = []
	candidates.assign(GameState.items.filter(func(it): return it.equipped_to == "" and it.slot_type() == slot_type and GameState.item_fits_hero(it, h)))
	if candidates.is_empty():
		pv.add_child(_label("No unequipped %s available." % ("weapons" if slot_type == "weapon" else "gear"), 11, true))
	for it in candidates:
		var crow := HBoxContainer.new()
		crow.add_theme_constant_override("separation", 8)
		crow.add_child(_icon(GameData.ITEM_CATEGORY_ICON_PATH[it.category], 18))
		crow.add_child(_label("%s (%s) — %s" % [_loot_display_name(it), GameData.ITEM_CATEGORY_LABEL[it.category], _loot_desc(it, false)], 12))
		crow.add_child(_button("Equip", func(hid=h.id, st=slot_type, i=idx, iid=it.id):
			GameState.equip_item(hid, st, i, iid)
			expanded_slot = ""
			render()
		))
		pv.add_child(crow)

	pv.add_child(_button("Close", func():
		expanded_slot = ""
		render()
	))
	picker.add_child(pv)
	cv.add_child(picker)


func _render_inventory(v: VBoxContainer) -> void:
	if inv_category == "":
		_render_inventory_hub(v)
		return
	v.add_child(_button("< Back to Inventory", func(): inv_category = ""; render()))
	match inv_category:
		"relics": _render_inventory_relics(v)
		"detectors": _render_inventory_detectors(v)
		_: _render_inventory_items(v)


## The 3 Inventory categories as clickable stations on a storage-vault scene
## (a chest for Items, a glowing altar for Relics, a table with a spyglass
## for Detectors) — same background-prop-as-button + hover-glow pattern as
## the camp/management screens.
func _render_inventory_hub(v: VBoxContainer) -> void:
	var scene_size := Vector2(700, 340)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size

	var bg := TextureRect.new()
	bg.texture = load(GameData.INVENTORY_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)

	# hit_rect (generous, easy-to-click) + native_rect (the station's own
	# tight bounds in the source 320x200 art, for the hover glow).
	var cat_entries := [
		["items", "Items", Rect2(0, 0, 230, 340), Rect2(3, 103, 97, 70)],
		["relics", "Relics", Rect2(230, 0, 240, 340), Rect2(133, 58, 62, 100)],
		["detectors", "Rift Detectors", Rect2(470, 0, 230, 340), Rect2(210, 65, 110, 95)],
	]
	var camp_scale := Vector2(700.0 / 320.0, 340.0 / 200.0)
	for entry in cat_entries:
		var cid: String = entry[0]
		var label_text: String = entry[1]
		var hit_rect: Rect2 = entry[2]
		var native_rect: Rect2 = entry[3]
		var glow_rect := Rect2(
			native_rect.position.x * camp_scale.x, native_rect.position.y * camp_scale.y,
			native_rect.size.x * camp_scale.x, native_rect.size.y * camp_scale.y
		)
		var hotspot := _camp_area_hotspot(hit_rect, glow_rect, label_text, func(id=cid):
			inv_category = id
			render()
		)
		hotspot.position = hit_rect.position
		scene.add_child(hotspot)

	v.add_child(scene)


func _rarity_rank(rarity_id: String) -> int:
	for i in GameData.RARITIES.size():
		if GameData.RARITIES[i]["id"] == rarity_id:
			return i
	return 0


func _render_inventory_items(v: VBoxContainer) -> void:
	v.add_child(_label("Items", 16))
	var unequipped_items: Array[Item] = []
	unequipped_items.assign(GameState.items.filter(func(it): return it.equipped_to == ""))
	v.add_child(_sort_cycle_button(inv_sort, [
		{"id": "rarity", "label": "Rarity"},
		{"id": "value", "label": "Value"},
		{"id": "name", "label": "Name"},
	], func(new_id): inv_sort = new_id))
	match inv_sort:
		"rarity":
			unequipped_items.sort_custom(func(a, b): return _rarity_rank(a.rarity) > _rarity_rank(b.rarity))
		"value":
			unequipped_items.sort_custom(func(a, b): return a.value > b.value)
		"name":
			unequipped_items.sort_custom(func(a, b): return a.name < b.name)
	if unequipped_items.is_empty():
		v.add_child(_label("No unequipped items.", 12))
	for it in unequipped_items:
		var row := HBoxContainer.new()
		row.add_child(_icon(GameData.ITEM_CATEGORY_ICON_PATH[it.category], 20))
		row.add_child(_label("%s (%s) — %s" % [_loot_display_name(it), GameData.ITEM_CATEGORY_LABEL[it.category], _loot_desc(it, false)], 12))
		for h2 in GameState.heroes:
			var slot := it.slot_type()
			var free_idx := _first_free_slot(h2, slot)
			if free_idx >= 0 and GameState.item_fits_hero(it, h2):
				row.add_child(_button("Equip → %s" % h2.name.split(" the ")[0], func(hid=h2.id, iid=it.id, s=slot, idx=free_idx):
					GameState.equip_item(hid, s, idx, iid)
					render()
				))
		row.add_child(_button("Sell", func(id=it.id):
			GameState.sell_item(id)
			render()
		))
		v.add_child(row)

	v.add_child(_hsep())
	v.add_child(_label("Field Incense — used at Party Assembly, lasts the whole rift", 16))
	if not GameState.consumables.is_empty():
		v.add_child(_label("Owned:", 12, true))
		for c in GameState.consumables:
			var def := GameData.find_incense(str(c["incense_id"]))
			v.add_child(_label("%s — %s" % [def["name"], def["desc"]], 12))
	for def in GameData.INCENSE_TYPES:
		var irow := HBoxContainer.new()
		irow.add_child(_label("%s (%dcr) — %s" % [def["name"], int(def["cost"]), def["desc"]], 12))
		irow.add_child(_button("Buy", func(iid=def["id"]):
			var err := GameState.buy_incense(iid)
			if err != "":
				push_warning(err)
			render()
		))
		v.add_child(irow)

	v.add_child(_hsep())
	v.add_child(_label("Runestones — socket into an equipped item from its Roster card", 16))
	if not GameState.runestones.is_empty():
		v.add_child(_label("Owned:", 12, true))
		for r in GameState.runestones:
			var rdef := GameData.find_runestone(str(r["runestone_id"]))
			v.add_child(_label("%s — %s" % [rdef["name"], rdef["desc"]], 12))
	for rdef in GameData.RUNESTONE_TYPES:
		var rrow := HBoxContainer.new()
		rrow.add_child(_label("%s (%dcr) — %s" % [rdef["name"], int(rdef["cost"]), rdef["desc"]], 12))
		rrow.add_child(_button("Buy", func(rid=rdef["id"]):
			var err := GameState.buy_runestone(rid)
			if err != "":
				push_warning(err)
			render()
		))
		v.add_child(rrow)


func _render_inventory_relics(v: VBoxContainer) -> void:
	v.add_child(_label("Relics — %d/%d slots equipped" % [Combat.equipped_relics().size(), GameState.relic_slot_cap()], 16))
	v.add_child(_sort_cycle_button(inv_sort, [
		{"id": "rarity", "label": "Rarity"},
		{"id": "level", "label": "Level"},
		{"id": "name", "label": "Name"},
	], func(new_id): inv_sort = new_id))
	var relics_sorted: Array[Relic] = []
	relics_sorted.assign(GameState.relics)
	match inv_sort:
		"rarity":
			relics_sorted.sort_custom(func(a, b): return _rarity_rank(a.rarity) > _rarity_rank(b.rarity))
		"level", "value":
			relics_sorted.sort_custom(func(a, b): return a.level > b.level)
		"name":
			relics_sorted.sort_custom(func(a, b): return a.name < b.name)
	for r in relics_sorted:
		var rrow := HBoxContainer.new()
		rrow.add_child(_icon(GameData.RELIC_TYPE_ICON_PATH[r.type], 20))
		rrow.add_child(_label("%s (%s, Lv%d) — %s" % [_loot_display_name(r), r.type, r.level, _loot_desc(r, true)], 12))
		rrow.add_child(_button("Unequip" if r.equipped else "Equip", func(id=r.id):
			GameState.toggle_equip_relic(id)
			render()
		))
		if r.level < GameState.RELIC_MAX_LEVEL:
			var rar := GameData.find_rarity(r.rarity)
			var cost := int(round(15.0 * float(rar["mult"]) * r.level))
			rrow.add_child(_button("Upgrade (%dcr)" % cost, func(id=r.id):
				var err := GameState.upgrade_relic(id)
				if err != "":
					push_warning(err)
				render()
			))
		if not r.equipped:
			rrow.add_child(_button("Sell", func(id=r.id):
				GameState.sell_relic(id)
				render()
			))
			if GameState.recycle_unlocked():
				rrow.add_child(_button("Scrap", func(id=r.id):
					GameState.scrap_relic(id)
					render()
				))
		v.add_child(rrow)


func _render_inventory_detectors(v: VBoxContainer) -> void:
	v.add_child(_label("Rift Detectors", 16))
	if GameState.detectors.is_empty():
		v.add_child(_label("No Detectors.", 12))
	for d in GameState.detectors:
		var drow := HBoxContainer.new()
		var det_id: String = d["id"]
		drow.add_child(_label("%s Detector" % str(d["tier"]).capitalize(), 12))
		drow.add_child(_button("Sell", func(id=det_id):
			GameState.sell_detector(id)
			render()
		))
		drow.add_child(_button("Use for Shop Boost", func(id=det_id):
			var err := GameState.use_detector_for_shop_boost(id)
			if err != "":
				push_warning(err)
			render()
		))
		v.add_child(drow)
