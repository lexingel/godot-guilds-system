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
var confirm_reset: bool = false
var _combat_animating: bool = false


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


## Pixel-art icon at a fixed size, nearest-neighbor filtered to stay crisp
## (matches the HTML's image-rendering:pixelated).
func _icon(path: String, size: int = 24) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	t.custom_minimum_size = Vector2(size, size)
	# Containers apply custom_minimum_size as actual size automatically, but a
	# plain Control parent (the combat arena's freely-positioned sprites) does
	# not — without this the TextureRect renders at its native texture
	# resolution instead of the intended icon size.
	t.size = Vector2(size, size)
	# Godot 4's default expand_mode (KEEP_SIZE) treats the texture's native
	# resolution as a floor on the control's effective minimum size — harmless
	# for small square sprites (monsters, 48x48) but silently re-inflates any
	# source image taller/wider than the requested box (hero portraits are
	# 92x200 natively) back toward its native size, ignoring the size set
	# above. IGNORE_SIZE lets our explicit size win regardless of source res.
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


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


func _log_richtext(lines: Array, party: Array[Hero], monsters: Array) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
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
func _render_rift_hall(v: VBoxContainer) -> void:
	_topbar(v)
	v.add_child(_label("Rift Hall", 20))
	for d in GameData.DIFFICULTIES:
		var card := PanelContainer.new()
		var cv := _vbox(4)
		var did: String = d["id"]
		cv.add_child(_label("%s — Floors %d · Rec. Power %d" % [d["name"], d["floors"], d["rec_power"]], 16))
		cv.add_child(_primary_button("Assemble Party", func(diff_id=did):
			pending_party.clear()
			screen = "party_assembly"
			_pending_diff_id = diff_id
			_pending_endless = false
			render()
		))
		card.add_child(cv)
		v.add_child(card)

	var endless_card := PanelContainer.new()
	var ecv := _vbox(4)
	ecv.add_child(_label("Endless Rift — scales forever. Best cycle: %d" % GameState.best_endless_cycle, 16))
	ecv.add_child(_primary_button("Assemble Party", func():
		pending_party.clear()
		screen = "party_assembly"
		_pending_diff_id = "endless"
		_pending_endless = true
		render()
	))
	endless_card.add_child(ecv)
	v.add_child(endless_card)

	v.add_child(_label("Greater Rift / Ascendant Rift — coming in a later pass.", 12))
	v.add_child(_button("Back to Terminal", func():
		screen = "terminal"
		render()
	))


var _pending_diff_id: String = "lesser"
var _pending_endless: bool = false
var _pending_hardcore: bool = false


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
			for i in choice_count:
				var rarity := "rare" if (GameState.inherited_power() and Combat.weighted_rarity() == "common") else Combat.weighted_rarity()
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

	v.add_child(_hsep())
	var hc_toggle := CheckButton.new()
	hc_toggle.text = "Hardcore Mode — ×1.5 rewards, a loss removes your heroes for good"
	hc_toggle.button_pressed = _pending_hardcore
	hc_toggle.toggled.connect(func(on: bool):
		_pending_hardcore = on
		render()
	)
	v.add_child(hc_toggle)

	v.add_child(_hsep())
	v.add_child(_primary_button("Enter the Rift", func():
		if pending_party.is_empty():
			return
		var chosen: Relic = pending_relic_options[pending_relic_choice] if pending_relic_choice >= 0 else null
		var ids: Array[String] = []
		ids.assign(pending_party)
		GameState.start_run(_pending_diff_id, ids, chosen, _pending_hardcore, _pending_endless)
		pending_relic_options.clear()
		pending_relic_choice = -1
		_pending_hardcore = false
		screen = "rift_run"
		render()
	))
	v.add_child(_button("Back", func():
		screen = "rift_hall"
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
	var diff := GameState._diff()
	var pos: int = int(GameState.run["pos"])
	var total_layers: int = (GameState.run["layers"] as Array).size()
	var cycle_label := (" (cycle %d)" % (int(GameState.run["cycle"]) + 1)) if GameState.run.get("endless", false) else ""
	v.add_child(_label("%s%s — Node %d/%d" % [diff["name"], cycle_label, pos + 1, total_layers], 18))
	if GameState.run.get("hardcore", false):
		v.add_child(_label("Hardcore Mode active", 12))
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
			v.add_child(_button("Return to Terminal", func():
				GameState.finish_run()
				screen = "terminal"
				render()
			))
		return

	v.add_child(_hsep())
	for h in GameState.current_party():
		v.add_child(_label("%s%s — %d/%d HP%s" % [h.name, " (Champion)" if h.is_champion else "", h.hp, Combat.max_hp(h), " (downed)" if h.is_downed() else ""]))
	v.add_child(_hsep())

	var options := GameState.current_layer_options()
	var kind := GameState.current_node_kind()
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

	v.add_child(_hsep())
	v.add_child(_button("Retreat (keep loot, no Seal Tokens)", func():
		GameState.retreat_now()
		screen = "terminal"
		render()
	))


## Frame-swaps `rect.texture` through `frames` once, a short delay between each.
## No explicit reset to the resting pose needed — the render() call right after
## _play_round always rebuilds portraits from the static portrait path anyway.
func _play_frames(rect: TextureRect, frames: Array[String], frame_time: float = 0.08) -> void:
	for path in frames:
		rect.texture = load(path)
		await get_tree().create_timer(frame_time).timeout


## Fallback for the two combos with no usable AI-generated motion (Warrior's
## hurt, Ranger's attack): a quick lunge tween on the existing static portrait.
## Animates position:x specifically (not the whole position) so it doesn't
## fight the idle sway's position:y loop running on the same wrapper.
func _tween_lunge(wrapper: Control) -> void:
	var start_x: float = wrapper.position.x
	var tween := create_tween()
	tween.tween_property(wrapper, "position:x", start_x + 12.0, 0.12)
	tween.tween_property(wrapper, "position:x", start_x, 0.12)
	await tween.finished


func _tween_hurt(wrapper: Control) -> void:
	var start_x: float = wrapper.position.x
	var tween := create_tween()
	tween.tween_property(wrapper, "modulate", Color(1, 0.4, 0.4), 0.08)
	tween.parallel().tween_property(wrapper, "position:x", start_x - 6.0, 0.08)
	tween.chain().tween_property(wrapper, "position:x", start_x + 6.0, 0.08)
	tween.chain().tween_property(wrapper, "position:x", start_x, 0.08)
	tween.parallel().tween_property(wrapper, "modulate", Color(1, 1, 1), 0.24)
	await tween.finished


func _flash_white(wrapper: Control) -> void:
	var tween := create_tween()
	tween.tween_property(wrapper, "modulate", Color(2, 2, 2), 0.06)
	tween.tween_property(wrapper, "modulate", Color(1, 1, 1), 0.18)
	await tween.finished


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
	await tween.finished
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

	await get_tree().create_timer(0.15).timeout

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

		const ARENA_SIZE := Vector2(420, 460)
		var arena := Control.new()
		arena.custom_minimum_size = ARENA_SIZE

		# Two stacked zones (monsters up top, heroes below) rather than one
		# continuous scene — each gets its own copy of the same background
		# image, scaled independently to its own band, with a visible divider
		# between them. Tried a single unified background first; monsters
		# there kept reading as floating regardless of position/shadows, so
		# this gives each side its own clearly-grounded little stage instead.
		var bg_path: String = GameData.BATTLE_BACKGROUNDS[int(state["background_idx"]) % GameData.BATTLE_BACKGROUNDS.size()]
		var divider_h := 9.0
		var monster_zone_h := (ARENA_SIZE.y - divider_h) / 2.0
		var hero_zone_h := monster_zone_h
		var hero_zone_y := monster_zone_h + divider_h

		var monster_bg := TextureRect.new()
		monster_bg.texture = load(bg_path)
		monster_bg.custom_minimum_size = Vector2(ARENA_SIZE.x, monster_zone_h)
		monster_bg.size = Vector2(ARENA_SIZE.x, monster_zone_h)
		monster_bg.stretch_mode = TextureRect.STRETCH_SCALE
		monster_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		arena.add_child(monster_bg)

		var divider := ColorRect.new()
		divider.color = Color(Palette.RIFT.r, Palette.RIFT.g, Palette.RIFT.b, 0.45)
		divider.position = Vector2(0, monster_zone_h)
		divider.size = Vector2(ARENA_SIZE.x, divider_h)
		arena.add_child(divider)

		var hero_bg := TextureRect.new()
		hero_bg.texture = load(bg_path)
		hero_bg.custom_minimum_size = Vector2(ARENA_SIZE.x, hero_zone_h)
		hero_bg.size = Vector2(ARENA_SIZE.x, hero_zone_h)
		hero_bg.position = Vector2(0, hero_zone_y)
		hero_bg.stretch_mode = TextureRect.STRETCH_SCALE
		hero_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		arena.add_child(hero_bg)

		# Monster sprites in a row across the top zone, mirroring the hero row
		# in the bottom zone — one per living or fallen monster (fallen ones
		# stay visible, dimmed). Every monster sprite has real attack/hurt
		# animation frames (GameData.monster_anim_frames), played by
		# _play_round the same way hero frames are. Every wrapper still gets
		# the idle sway so the arena isn't static between rounds. Horizontal
		# spacing is computed from the actual monster count (1-3 here) rather
		# than a fixed step, so it doesn't crowd/overlap regardless of how many
		# showed up this fight. Size scales with the monster's own max HP
		# (clamped) so a boss/elite main unit reads as a bigger threat than a
		# weak add or a divided-stats regular mob, rather than every monster
		# being a uniform size.
		var monster_wrappers: Dictionary = {}
		var monster_rects: Dictionary = {}
		var monster_left := 24.0
		var monster_band := ARENA_SIZE.x - 48.0
		var monster_step: float = monster_band / max(1, monsters.size())
		var monster_top := monster_zone_h * 0.35
		for i in monsters.size():
			var m: Dictionary = monsters[i]
			var m_x: float = monster_left + i * monster_step
			var m_size: int = clampi(56 + int(float(m["max_hp"]) / 2.5), 60, 100)
			var m_rect := _icon(GameData.sprite_for_monster(str(m["name"])), m_size)
			var m_wrapper := _wrap_icon(m_rect)
			m_wrapper.position = Vector2(m_x, monster_top)
			_add_ground_shadow(arena, m_wrapper.position, float(m_size))
			if float(m["hp"]) <= 0:
				m_wrapper.modulate = Color(0.35, 0.35, 0.35, 0.7)
			else:
				_start_idle_sway(m_wrapper)
			arena.add_child(m_wrapper)
			monster_wrappers[i] = m_wrapper
			monster_rects[i] = m_rect
			var m_name_label := _label(str(m["name"]), 11, true)
			m_name_label.position = Vector2(m_x - 10, monster_top + m_size + 4)
			arena.add_child(m_name_label)
			var m_bar := _hp_bar(max(0, int(m["hp"])), int(m["max_hp"]), 70.0)
			m_bar.position = Vector2(m_x - 5, monster_top + m_size + 20)
			arena.add_child(m_bar)

		# Hero portraits in a row along the bottom, living heroes only, spaced
		# from the actual living count for the same reason as the monsters above.
		var hero_wrappers: Dictionary = {}
		var hero_rects: Dictionary = {}
		var living_heroes: Array[Hero] = []
		living_heroes.assign(party.filter(func(h): return h.hp > 0))
		var hero_left := 24.0
		var hero_band := ARENA_SIZE.x - 48.0
		var hero_step: float = hero_band / max(1, living_heroes.size())
		var hero_size := 84.0
		# Name + HP bar sit above the head as a nameplate rather than below
		# the feet -- a below-sprite placement overlapped the body, since the
		# portrait's visible content doesn't end at a predictable fixed offset
		# the way the normalized monster sprites do.
		var hero_top: float = hero_zone_y + hero_zone_h * 0.2
		var row_i := 0
		for h in party:
			if h.hp <= 0:
				continue
			var portrait_path := GameData.portrait_for_hero(h.cls_id, h.pool_id)
			if portrait_path == "":
				continue
			var h_x: float = hero_left + row_i * hero_step
			var h_rect := _icon(portrait_path, int(hero_size))
			var h_wrapper := _wrap_icon(h_rect)
			h_wrapper.position = Vector2(h_x, hero_top)
			_add_ground_shadow(arena, h_wrapper.position, hero_size)
			arena.add_child(h_wrapper)
			_start_idle_sway(h_wrapper)
			hero_wrappers[h.id] = h_wrapper
			hero_rects[h.id] = h_rect
			var h_name_label := _label(h.name, 11, true)
			h_name_label.position = Vector2(h_x - 10, hero_top - 32)
			arena.add_child(h_name_label)
			var h_bar := _hp_bar(h.hp, Combat.max_hp(h), 70.0)
			h_bar.position = Vector2(h_x - 5, hero_top - 16)
			arena.add_child(h_bar)
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

		var left := _vbox(8)
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var incoming := Combat.describe_incoming(state)
		if incoming != "":
			left.add_child(_label(incoming, 12, true))
		left.add_child(_log_richtext(state["log"], party, monsters))

		# The action controls live in their own bordered panel (reusing the
		# Theme's existing PanelContainer style, same as every card elsewhere
		# in the game) so it reads as a compact battle menu rather than more
		# loose page content, with smaller text/buttons than the rest of the
		# UI to fit 1-4 heroes' worth of controls without sprawling.
		var menu_panel := PanelContainer.new()
		# Explicit flat style rather than the shared Theme's texture-based
		# panel — that StyleBoxTexture is tuned for the fixed-size cards it's
		# used on elsewhere and rendered as a wrong, over-bright color at this
		# panel's size (variable height depending on party size).
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
		var cooldowns: Dictionary = state["ability_cooldowns"]
		for h in party:
			var hero_block := _vbox(2)
			if h.hp <= 0:
				hero_block.add_child(_label("%s — down for the count" % h.name, 11, true))
				menu.add_child(hero_block)
				continue
			var hero_top_row := HBoxContainer.new()
			hero_top_row.add_child(_label(h.name, 12))
			hero_top_row.add_child(_hp_bar(h.hp, Combat.max_hp(h), 80.0))
			hero_top_row.add_child(_label("%d/%d" % [h.hp, Combat.max_hp(h)], 10, true))
			hero_block.add_child(hero_top_row)
			var act: Dictionary = pending.get(h.id, {"action": "attack", "target": 0})
			var current_action: String = str(act.get("action", "attack"))
			var current_target: int = int(act.get("target", 0))

			var action_row := HBoxContainer.new()
			action_row.add_theme_constant_override("separation", 4)
			for i in monsters.size():
				if float(monsters[i]["hp"]) <= 0:
					continue
				var atk_btn := _button(str(monsters[i]["name"]), func(hid=h.id, ti=i):
					GameState.set_hero_action(hid, "attack", ti)
					render()
				)
				atk_btn.add_theme_font_size_override("font_size", 11)
				atk_btn.toggle_mode = true
				atk_btn.button_pressed = current_action == "attack" and current_target == i
				action_row.add_child(atk_btn)

			if cooldowns.has(h.id):
				var cd: int = int(cooldowns[h.id])
				var ab: Dictionary = GameData.ABILITIES[h.cls_id]
				var ab_label := "%s (%d)" % [str(ab["name"]), cd] if cd > 0 else str(ab["name"])
				var ab_btn := _button(ab_label, func(hid=h.id):
					GameState.set_hero_action(hid, "ability")
					render()
				)
				ab_btn.add_theme_font_size_override("font_size", 11)
				ab_btn.toggle_mode = true
				ab_btn.button_pressed = current_action == "ability"
				ab_btn.disabled = cd > 0
				action_row.add_child(ab_btn)

			var defend_btn := _button("Defend", func(hid=h.id):
				GameState.set_hero_action(hid, "defend")
				render()
			)
			defend_btn.add_theme_font_size_override("font_size", 11)
			defend_btn.toggle_mode = true
			defend_btn.button_pressed = current_action == "defend"
			action_row.add_child(defend_btn)

			hero_block.add_child(action_row)
			menu.add_child(hero_block)
			if h != party[party.size() - 1]:
				menu.add_child(_hsep())

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
			GameState.combat_retreat()
			render()
		))
		menu.add_child(bottom_row)
		left.add_child(menu_panel)

		var split := HBoxContainer.new()
		split.add_theme_constant_override("separation", 12)
		split.add_child(left)
		split.add_child(arena)
		v.add_child(split)
		return

	var result: Dictionary = ns["result"]
	var monster_row := HBoxContainer.new()
	monster_row.add_child(_icon(GameData.sprite_for_monster(str(result["monster_name"])), 28))
	monster_row.add_child(_label(str(result["monster_name"]), 14))
	v.add_child(monster_row)
	var log_party: Array[Hero] = GameState.current_party()
	v.add_child(_log_richtext(result["log"], log_party, [{"name": result["monster_name"]}]))

	if result["won"]:
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
				var desc: String = obj.desc() if is_relic else Combat.describe_skill(obj.kind, obj.value)
				var icon_path: String = GameData.RELIC_TYPE_ICON_PATH[obj.type] if is_relic else GameData.ITEM_CATEGORY_ICON_PATH[obj.category]
				var btn := _button("%s — %s" % [obj.name, desc], func(idx=i):
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
	else:
		var defeat_text := "You withdraw from the fight." if result.get("retreated", false) else "Defeat — the party is downed and recovering."
		v.add_child(_label(defeat_text))
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
		var desc: String = obj.desc() if off["loot_type"] == "relic" else Combat.describe_skill(obj.kind, obj.value)
		var bought: bool = off.get("bought", false)
		var is_relic: bool = off["loot_type"] == "relic"
		var icon_path: String = GameData.RELIC_TYPE_ICON_PATH[obj.type] if is_relic else GameData.ITEM_CATEGORY_ICON_PATH[obj.category]
		var row := HBoxContainer.new()
		row.add_child(_icon(icon_path, 20))
		row.add_child(_label("%s — %s (%dc)%s" % [obj.name, desc, off["price"], " [bought]" if bought else ""]))
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


func _render_hazard_node(v: VBoxContainer) -> void:
	GameState.ensure_hazard()
	var ns: Dictionary = GameState.run["node_state"]
	var hz: Dictionary = ns["hazard"]
	v.add_child(_label(hz["name"]))
	if not ns.get("resolved", false):
		v.add_child(_button("Push Through", func():
			GameState.push_through_hazard()
			render()
		))
	else:
		for line in ns.get("log", []):
			v.add_child(_label(str(line), 12))
		v.add_child(_button("Continue", func():
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
	v.add_child(_label(tier_line, 12, true))

	if term_tab == "camp":
		_render_camp(v)
		return

	v.add_child(_button("< Back to Camp", func(): term_tab = "camp"; render()))
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
	var area_entries := [
		["Medical Bay", Rect2(14, 132, 171, 98), func(): term_tab = "medical"; render()],
		["Roster", Rect2(182, 99, 132, 60), func(): term_tab = "roster"; render()],
		["Inventory", Rect2(376, 111, 62, 42), func(): term_tab = "inventory"; render()],
		["Hero Recruits", Rect2(314, 193, 94, 79), func(): term_tab = "recruits"; render()],
		["Guild Management", Rect2(459, 105, 117, 76), func(): term_tab = "management"; render()],
	]
	for entry in area_entries:
		var label_text: String = entry[0]
		var rect: Rect2 = entry[1]
		var cb: Callable = entry[2]
		var hotspot := _camp_area_hotspot(rect.size, label_text, cb)
		hotspot.position = rect.position
		camp.add_child(hotspot)

	var rift_icon := _camp_hotspot(GameData.CAMP_HUB_ICON_PATH["rift"], 56.0, "Rift Hall", func(): screen = "rift_hall"; render())
	rift_icon.position = Vector2(565, 220) - Vector2(28, 28)
	camp.add_child(rift_icon)

	v.add_child(camp)


## An invisible clickable region over a prop already drawn in the background
## art — no icon texture of its own, just a faint highlight on hover for
## affordance and a caption underneath, so the scene's own art reads as the
## button instead of a graphic layered on top of it.
func _camp_area_hotspot(size: Vector2, label_text: String, cb: Callable) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(size.x, size.y + 16)
	wrap.size = Vector2(size.x, size.y + 16)

	var glow := ColorRect.new()
	glow.color = Color(1, 1, 1, 0.16)
	glow.size = size
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.visible = false

	# A flat Button with every stylebox cleared to transparent, rather than a
	# TextureButton with no texture assigned — proven reliable input handling
	# (every other button in the game already is this class) instead of
	# relying on an untextured TextureButton's hit-testing.
	var btn := Button.new()
	btn.flat = true
	btn.text = ""
	btn.custom_minimum_size = size
	btn.size = size
	var clear_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style_name, clear_style)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(cb)
	btn.mouse_entered.connect(func(): glow.visible = true)
	btn.mouse_exited.connect(func(): glow.visible = false)
	wrap.add_child(btn)
	wrap.add_child(glow)

	var caption := _label(label_text, 11, true)
	caption.position = Vector2(0, size.y + 1)
	caption.custom_minimum_size = Vector2(size.x, 0)
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
	tb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tb.pressed.connect(cb)
	tb.mouse_entered.connect(func(): tb.modulate = Color(1.25, 1.25, 1.25))
	tb.mouse_exited.connect(func(): tb.modulate = Color(1, 1, 1))
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
		var row := HBoxContainer.new()
		row.add_child(_label("%s — Rank %s %s (%dc)" % [h.name, h.rank, h.cls_id.capitalize(), int(rank["cost"])]))
		row.add_child(_primary_button("Recruit", func(id=h.id):
			var err := GameState.recruit_hero(id)
			if err != "":
				push_warning(err)
			render()
		))
		v.add_child(row)


func _render_medical_bay(v: VBoxContainer) -> void:
	v.add_child(_label("Medical Bay — %d/%d beds occupied" % [GameState.occupied_beds(), GameState.medical_bed_cap()], 16))
	if GameState.field_triage_available():
		v.add_child(_button("Field Triage (heal whole roster, once per rift cycle)%s" % ("" if not GameState.triage_used_this_cycle else " [used]"), func():
			var err := GameState.field_triage_action()
			if err != "":
				push_warning(err)
			render()
		))
	var wounded: Array[Hero] = []
	wounded.assign(GameState.heroes.filter(func(h): return h.hp < Combat.max_hp(h)))
	if wounded.is_empty():
		v.add_child(_label("No wounded heroes.", 12))
	for h in wounded:
		var row := HBoxContainer.new()
		var status := "Bedded, healing fast" if (h.bedded and h.is_downed()) else ("Downed — recovering" if h.is_downed() else "Wounded")
		row.add_child(_label("%s — %d/%d HP (%s)" % [h.name, h.hp, Combat.max_hp(h), status]))
		if h.is_downed() and not h.bedded:
			row.add_child(_button("Assign to Bed", func(id=h.id):
				GameState.assign_to_bed(id)
				render()
			))
		v.add_child(row)


func _render_management(v: VBoxContainer) -> void:
	for b in GameData.BRANCHES:
		v.add_child(_label("%s — %s" % [b["name"], b["sub"]], 16))
		for n in b["nodes"]:
			var key := "%s.%s" % [b["id"], n["id"]]
			var cur := GameState.lvl(key)
			var maxed := cur >= int(n["max"])
			var row := _vbox(2)
			var cur_desc := Combat.describe_node_effect(n["id"], cur)
			var line := "%s (Lvl %d/%d) — %s" % [n["name"], cur, n["max"], cur_desc]
			if not maxed:
				line += " → %s" % Combat.describe_node_effect(n["id"], cur + 1)
			row.add_child(_label(line, 12))
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
			row.add_child(brow)
			v.add_child(row)
		v.add_child(_hsep())

	var reset_btn := _button("Click again to confirm reset" if confirm_reset else "Reset Guild", func():
		if not confirm_reset:
			confirm_reset = true
			render()
			get_tree().create_timer(3.0).timeout.connect(func():
				confirm_reset = false
				if screen == "terminal" and term_tab == "management":
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


func _render_roster(v: VBoxContainer) -> void:
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes recruited yet."))
		return
	for h in GameState.heroes:
		var card := PanelContainer.new()
		var cv := _vbox(4)
		cv.add_child(_title_strip(h.name))
		cv.add_child(_label("Lv%d %s (%s) · %d/%d HP" % [h.level, h.cls_id.capitalize(), h.rank, h.hp, Combat.max_hp(h)]))
		cv.add_child(_label("Trait: %s" % (h.trait_name if h.trait_name != "" else "Steadfast"), 12, true))
		cv.add_child(_label("Power %d" % Combat.power_of(h), 12, true))

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
			cv.add_child(_label("Skill Points: %d" % h.skill_points, 12))
			var tree: Array = GameData.CLASS_SKILLS.get(h.cls_id, [])
			for n in tree:
				var skill_id: String = n["id"]
				var learned: bool = h.skills.get(skill_id, false)
				var srow := HBoxContainer.new()
				srow.add_child(_label("%s — %s (Lv%d, %d SP)%s" % [n["name"], Combat.describe_skill(n["kind"], n["value"]), n["req_level"], n["cost"], " [learned]" if learned else ""], 12))
				if not learned:
					srow.add_child(_button("Learn", func(hid=h.id, sid=skill_id):
						var err := GameState.learn_skill(hid, sid)
						if err != "":
							push_warning(err)
						render()
					))
				cv.add_child(srow)
			var spent: int = h.skills.values().count(true)
			if spent > 0:
				cv.add_child(_button("Respec (%dc)" % GameState.respec_cost(spent), func(id=h.id):
					var err := GameState.respec_hero(id)
					if err != "":
						push_warning(err)
					render()
				))

		var equipped_items: Array[Item] = []
		equipped_items.assign(GameState.items.filter(func(it): return it.equipped_to == h.id))
		if not equipped_items.is_empty():
			var erow := HBoxContainer.new()
			for it in equipped_items:
				erow.add_child(_button("%s (%s) — unequip" % [it.name, GameData.ITEM_CATEGORY_LABEL[it.category]], func(id=it.id):
					var target: Item = null
					for x in GameState.items:
						if x.id == id:
							target = x
							break
					if target:
						GameState.equip_item(h.id, target.slot_type(), target.equipped_idx, "")
					render()
				))
			cv.add_child(erow)

		var hero_row := HBoxContainer.new()
		var portrait_path := GameData.portrait_for_hero(h.cls_id, h.pool_id)
		if portrait_path != "":
			hero_row.add_child(_icon(portrait_path, 64))
		hero_row.add_child(cv)
		card.add_child(hero_row)
		v.add_child(card)


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


func _render_inventory(v: VBoxContainer) -> void:
	v.add_child(_label("Inventory", 16))
	var unequipped_items: Array[Item] = []
	unequipped_items.assign(GameState.items.filter(func(it): return it.equipped_to == ""))
	if unequipped_items.is_empty():
		v.add_child(_label("No unequipped items.", 12))
	for it in unequipped_items:
		var row := HBoxContainer.new()
		row.add_child(_icon(GameData.ITEM_CATEGORY_ICON_PATH[it.category], 20))
		row.add_child(_label("%s (%s) — %s" % [it.name, GameData.ITEM_CATEGORY_LABEL[it.category], Combat.describe_skill(it.kind, it.value)], 12))
		for h2 in GameState.heroes:
			var slot := it.slot_type()
			var free_idx := _first_free_slot(h2, slot)
			if free_idx >= 0:
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
	v.add_child(_label("Relics — %d/%d slots equipped" % [Combat.equipped_relics().size(), GameState.relic_slot_cap()], 16))
	for r in GameState.relics:
		var rrow := HBoxContainer.new()
		rrow.add_child(_icon(GameData.RELIC_TYPE_ICON_PATH[r.type], 20))
		rrow.add_child(_label("%s (%s, Lv%d) — %s" % [r.name, r.type, r.level, r.desc()], 12))
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

	v.add_child(_hsep())
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
