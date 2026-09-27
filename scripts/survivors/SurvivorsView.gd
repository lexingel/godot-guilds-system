class_name SurvivorsView
extends Node2D
## The Endless Rift on screen: draws a SurvivorsRun, feeds it input
## (WASD/arrows, or drag anywhere on touch/mouse), shows the HUD, level-up
## picks and the result. Main hides itself while this runs and gets
## `finished` with the guild payout when the player leaves.

signal finished(summary: Dictionary)

const WALK_DIR := "res://assets/survivors/walk/"
const FLOOR_PATH := "res://assets/survivors/floor_%s.png"
const THEME := preload("res://theme/guild_theme.tres")
const DISPLAY_FONT := preload("res://assets/fonts/Cinzel-Bold.ttf")
const TIER_SCALE := {"combat": 1.0, "elite": 1.45, "boss": 2.3}

var run: SurvivorsRun
var party: Array = []
var biome := "vale"
var paused := false
var autopilot := false   # screenshots / attract: the run steers itself
var bench := false       # performance check: logs FPS and step time, never pays out
var _bench_acc := 0.0
var _bench_us := 0
var _bench_steps := 0

var _cam: Camera2D
var _world: Node2D
var _fx: Node2D
var _overlay: Node2D
var _hud: CanvasLayer
var _hud_time: Label
var _hud_kills: Label
var _hud_level: Label
var _xp_bar: ProgressBar
var _boss_bar: ProgressBar
var _boss_label: Label
var _hero_bars := {}
var _panel: Control          # level-up / pause / results overlay, or null
var _hero_nodes := {}
var _foe_nodes := {}
var _frames_cache := {}
var _drag_from := Vector2.INF
var _drag_to := Vector2.INF
var _summary := {}


func setup(p_party: Array, p_biome: String) -> void:
	party = p_party
	biome = p_biome
	run = SurvivorsRun.new(party, biome)


func _ready() -> void:
	_world = Node2D.new()
	add_child(_world)
	var floor_tex: Texture2D = load(FLOOR_PATH % biome) if ResourceLoader.exists(FLOOR_PATH % biome) else null
	if floor_tex:
		var fl := Sprite2D.new()
		fl.texture = floor_tex
		fl.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		fl.region_enabled = true
		fl.region_rect = Rect2(-20000, -20000, 40000, 40000)
		fl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fl.modulate = Color(0.75, 0.75, 0.8)
		_world.add_child(fl)
	_overlay = _Overlay.new()
	_overlay.view = self
	_world.add_child(_overlay)
	_fx = Node2D.new()
	_fx.z_index = 20
	_world.add_child(_fx)
	_cam = Camera2D.new()
	_cam.position_smoothing_enabled = true
	_cam.position_smoothing_speed = 8.0
	add_child(_cam)
	_cam.make_current()
	for h in run.heroes:
		# The hero's own walk cycle (their subclass look), else their role's.
		var own := "sub_" + str(h["hero"].pool_id)
		var n := _make_sprite(own if ResourceLoader.exists(WALK_DIR + own + "_0.png") else str(h["role"]), 1.0)
		_world.add_child(n)
		_hero_nodes[h["hero"].id] = n
	_build_hud()
	AudioManager.play_music(GameData.MUSIC_PATH["combat"])


# ---------------- Sprites ----------------

func _frames_for(key: String) -> SpriteFrames:
	if _frames_cache.has(key):
		return _frames_cache[key]
	var sf := SpriteFrames.new()
	sf.set_animation_speed("default", 10.0)
	for i in 8:
		var p := WALK_DIR + "%s_%d.png" % [key, i]
		if ResourceLoader.exists(p):
			sf.add_frame("default", load(p))
	if sf.get_frame_count("default") == 0:
		# No walk cycle yet: the static battle sprite, scaled down.
		var still := str(GameData.MONSTER_SPRITE_PATH.get(key, GameData.HERO_PORTRAIT_PATH.get(key, "")))
		if still != "":
			sf.add_frame("default", load(still))
	_frames_cache[key] = sf
	return sf


func _make_sprite(key: String, scale_mult: float) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = _frames_for(key)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.offset = Vector2(0, -28)
	var tex := s.sprite_frames.get_frame_texture("default", 0)
	var h := float(tex.get_height()) if tex else 64.0
	s.scale = Vector2.ONE * scale_mult * (64.0 / h if h > 64.0 else 1.0)
	s.play()
	return s


func _foe_key(name: String) -> String:
	return GameData.monster_sprite_key(name)


# ---------------- Frame ----------------

func _physics_process(delta: float) -> void:
	if paused or _panel != null:
		return
	var t0 := Time.get_ticks_usec()
	run.step(delta, run.autopilot_dir() if autopilot else _input_dir())
	_sync()
	_play_events()
	if bench:
		_bench_log(delta, Time.get_ticks_usec() - t0)
	if autopilot:
		while run.pending_levels > 0:
			var o := run.offer()
			run.pick(o[0] if not o.is_empty() else "")
	if run.pending_levels > 0:
		_show_level_up()
	elif run.over:
		_show_results()


func _input_dir() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		d.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		d.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		d.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		d.y += 1
	if d == Vector2.ZERO and _drag_from != Vector2.INF and _drag_to != Vector2.INF:
		var v := _drag_to - _drag_from
		if v.length() > 12.0:
			d = v
	return d.normalized()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_ESCAPE, KEY_P] and not run.over and run.pending_levels == 0:
			_toggle_pause()
		elif _panel != null and run.pending_levels > 0 and event.physical_keycode in [KEY_1, KEY_2, KEY_3]:
			var btns := _panel.find_children("*", "Button", true, false)
			var k: int = event.physical_keycode - KEY_1
			if k < btns.size():
				(btns[k] as Button).pressed.emit()
	elif event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		if event.pressed:
			_drag_from = event.position
			_drag_to = event.position
		else:
			_drag_from = Vector2.INF
			_drag_to = Vector2.INF
	elif event is InputEventScreenDrag or (event is InputEventMouseMotion and _drag_from != Vector2.INF):
		_drag_to = event.position


func _sync() -> void:
	for h in run.heroes:
		var n: AnimatedSprite2D = _hero_nodes[h["hero"].id]
		n.position = h["pos"]
		n.flip_h = h["facing"] < 0.0
		n.modulate = Color(1, 1, 1) if h["alive"] else Color(0.4, 0.4, 0.45, 0.6)
		if h["alive"] and h.get("moving", false):
			if not n.is_playing():
				n.play()
		else:
			n.stop()
			n.frame = 0
		n.z_index = int(h["pos"].y / 10.0) + 1000
	_cam.position = run.lead()["pos"]
	var seen := {}
	for f in run.foes:
		var id: int = f["id"]
		seen[id] = true
		var n: AnimatedSprite2D = _foe_nodes.get(id)
		if n == null:
			n = _make_sprite(_foe_key(str(f["name"])), TIER_SCALE[f["tier"]])
			n.frame = randi() % maxi(1, n.sprite_frames.get_frame_count("default"))
			_world.add_child(n)
			_foe_nodes[id] = n
		n.position = f["pos"]
		n.flip_h = f["facing"] > 0.0
		n.modulate = Color(3, 3, 3) if f["flash"] > 0.0 else Color.WHITE
		n.z_index = int(f["pos"].y / 10.0) + 1000
	for id in _foe_nodes.keys():
		if not seen.has(id):
			_foe_nodes[id].queue_free()
			_foe_nodes.erase(id)
	_overlay.queue_redraw()
	_update_hud()


func _play_events() -> void:
	for e in run.events:
		match e["type"]:
			"arc":
				Fx.burst(_fx, "slash", e["pos"], e["r"] * 1.6, Color(1, 0.9, 0.8), 30.0)
				AudioManager.play_sfx(GameData.SFX_PATH["attack"])
			"pulse":
				Fx.ring(_fx, e["pos"], e["r"], Color(1.0, 0.95, 0.6), 0.35)
			"stab":
				Fx.burst(_fx, "claw", e["to"], 46.0, Color(0.9, 0.95, 1.0), 34.0)
			"burst":
				Fx.burst(_fx, "explosion", e["pos"], e["r"] * 2.2, Color(0.8, 0.6, 1.0), 26.0)
			"shockwave":
				Fx.ring(_fx, e["pos"], e["r"], Color(1, 0.8, 0.5), 0.5)
				AudioManager.play_sfx(GameData.SFX_PATH["hit_heavy"])
			"meteor":
				Fx.burst(_fx, "explosion", e["pos"], e["r"] * 2.4, Color(1.0, 0.6, 0.3), 20.0)
				AudioManager.play_sfx(GameData.SFX_PATH["hit_heavy"])
			"sanctuary":
				Fx.burst(_fx, "holy", e["pos"], e["r"] * 1.4, Color(1, 1, 0.8), 18.0)
			"kill":
				if e["tier"] != "combat":
					Fx.burst(_fx, "explosion", e["pos"], 120.0 if e["tier"] == "elite" else 220.0, Color(0.8, 0.75, 0.9), 18.0)
					AudioManager.play_sfx(GameData.SFX_PATH["victory" if e["tier"] == "boss" else "hit_heavy"])
			"hurt":
				pass
			"heal":
				var hn: Node2D = _hero_nodes.get(e["hero"])
				if hn:
					Fx.sparkles(_fx, hn.position + Vector2(0, -20), Palette.RANK_E, 10, 30.0)
			"level":
				AudioManager.play_sfx(GameData.SFX_PATH["victory"])
			"boss":
				_banner("%s emerges!" % str(e["name"]), Palette.EMBER_BRIGHT)
				AudioManager.play_sfx(GameData.SFX_PATH["boss"])
			"phase":
				_banner("%s calls the horde!" % str(e["name"]), Palette.HAZARD)
			"down":
				AudioManager.play_sfx(GameData.SFX_PATH["knockout"])
			"revive":
				var rn: Node2D = _hero_nodes.get(e["hero"])
				if rn:
					Fx.burst(_fx, "holy", rn.position + Vector2(0, -24), 90.0, Color(1, 1, 0.85), 18.0)
	run.events.clear()


# ---------------- HUD ----------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	var root := Control.new()
	root.theme = THEME
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(root)
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_xp_bar = _bar(Palette.CRYSTALS, 10)
	top.add_child(_xp_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)
	_hud_level = _hud_label(row, 18)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	_hud_time = _hud_label(row, 28)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp2)
	_hud_kills = _hud_label(row, 18)
	var pause := Button.new()
	pause.text = "Pause"
	pause.focus_mode = Control.FOCUS_NONE
	pause.pressed.connect(_toggle_pause)
	row.add_child(pause)
	_boss_label = _hud_label(top, 16)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_bar = _bar(Palette.HAZARD, 12)
	top.add_child(_boss_bar)
	# Party health, bottom-left.
	var party_box := VBoxContainer.new()
	party_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	party_box.offset_left = 16
	party_box.offset_bottom = -16
	party_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	party_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(party_box)
	for h in run.heroes:
		var hr := HBoxContainer.new()
		hr.add_theme_constant_override("separation", 8)
		hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nl := _hud_label(hr, 14)
		nl.text = ("★ " if h["lead"] else "") + h["hero"].name.split(" the ")[0]
		nl.custom_minimum_size.x = 120
		var bar := _bar(Color.WHITE, 10)
		bar.custom_minimum_size.x = 160
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hr.add_child(bar)
		party_box.add_child(hr)
		_hero_bars[h["hero"].id] = bar
	var hint := _hud_label(root, 13)
	hint.text = "Move: WASD / arrows, or drag  ·  Pause: Esc"
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	hint.modulate = Color(1, 1, 1, 0.6)


func _bar(color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _hud_label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size >= 20:
		l.add_theme_font_override("font", DISPLAY_FONT)
	parent.add_child(l)
	return l


func _update_hud() -> void:
	var t := int(run.time)
	_hud_time.text = "%d:%02d" % [t / 60, t % 60]
	_hud_kills.text = "%d kills" % run.kills
	_hud_level.text = "Level %d" % run.level
	_xp_bar.max_value = run.xp_next()
	_xp_bar.value = run.xp
	var boss := {}
	for f in run.foes:
		if f["tier"] == "boss":
			boss = f
			break
	_boss_bar.visible = not boss.is_empty()
	_boss_label.visible = not boss.is_empty()
	if not boss.is_empty():
		_boss_label.text = str(boss["name"])
		_boss_bar.max_value = boss["max_hp"]
		_boss_bar.value = maxf(0.0, boss["hp"])
	for h in run.heroes:
		var bar: ProgressBar = _hero_bars[h["hero"].id]
		bar.max_value = h["max_hp"]
		bar.value = h["hp"]
		(bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Palette.good() if h["hp"] > h["max_hp"] * 0.35 else Palette.HAZARD
		bar.modulate.a = 1.0 if h["alive"] else 0.4


func _banner(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.theme = THEME
	l.add_theme_font_override("font", DISPLAY_FONT)
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 8)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.offset_top = 110
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


# ---------------- Panels ----------------

func _modal(title: String) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.theme = THEME
	_hud.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(cc)
	var panel := PanelContainer.new()
	cc.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	m.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", DISPLAY_FONT)
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	_panel = dim
	return v


func _close_panel() -> void:
	if _panel:
		_panel.queue_free()
	_panel = null


func _show_level_up() -> void:
	var v := _modal("Level %d" % run.level)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var offer := run.offer()
	for i in offer.size():
		var id: String = offer[i]
		var u: Dictionary = SurvivorsRun.UPGRADES[id]
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 150)
		b.focus_mode = Control.FOCUS_NONE
		var col := VBoxContainer.new()
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 6)
		var ic := TextureRect.new()
		ic.texture = load(str(u["icon"]))
		ic.custom_minimum_size = Vector2(36, 36)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(ic)
		var nm := Label.new()
		var have := int(run.upgrades.get(id, 0))
		nm.text = "%d. %s%s" % [i + 1, u["name"], "  (%d/%d)" % [have + 1, u["max"]] if have > 0 else ""]
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(nm)
		var d := Label.new()
		d.text = str(u["desc"])
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.custom_minimum_size.x = 180
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(d)
		b.add_child(col)
		b.pressed.connect(func():
			run.pick(id)
			_close_panel())
		row.add_child(b)
	if offer.is_empty():
		var ok := Button.new()
		ok.text = "Everything is maxed — carry on"
		ok.pressed.connect(func():
			run.pick("")
			_close_panel())
		v.add_child(ok)


func _toggle_pause() -> void:
	if _panel != null:
		if paused:
			paused = false
			_close_panel()
		return
	paused = true
	var v := _modal("Paused")
	var owned: Array = run.upgrades.keys().map(func(id): return "%s ×%d" % [SurvivorsRun.UPGRADES[id]["name"], run.upgrades[id]])
	var l := Label.new()
	l.text = "Upgrades: " + (", ".join(owned) if not owned.is_empty() else "none yet")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 420
	v.add_child(l)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(_toggle_pause)
	v.add_child(resume)
	var leave := Button.new()
	leave.text = "Leave the rift (keep what you've earned)"
	leave.pressed.connect(func():
		paused = false
		_close_panel()
		run.over = true
		_show_results())
	v.add_child(leave)


## Every 5 s: frames per second, and how long one simulation + draw sync takes.
func _bench_log(delta: float, us: int) -> void:
	_bench_acc += delta
	_bench_us += us
	_bench_steps += 1
	if _bench_acc >= 5.0:
		print("[bench] t=%d foes=%d shots=%d gems=%d fps=%d step=%.2fms" % [int(run.time), run.foes.size(), run.shots.size(), run.gems.size(),
			Engine.get_frames_per_second(), _bench_us / 1000.0 / maxi(1, _bench_steps)])
		_bench_acc = 0.0
		_bench_us = 0
		_bench_steps = 0


func _show_results() -> void:
	if bench:
		print("[bench] run over at %d s" % int(run.time))
		paused = true
		return
	if not _summary.is_empty():
		return
	_summary = GameState.finish_survivors(run)
	var t := int(run.time)
	var v := _modal("The rift closes")
	var lines := [
		"Survived %d:%02d%s" % [t / 60, t % 60, "  — a new best!" if _summary.get("best", false) else ""],
		"%d kills · %d elites · %d wardens · reached level %d" % [run.kills, run.elites_killed, run.bosses_killed, run.level],
		"+%d gold · +%d essence · +%d XP for every hero" % [_summary["coins"], _summary["crystals"], _summary["xp"]],
	]
	for name in _summary.get("loot", []):
		lines.append("Found: %s" % name)
	for s in lines:
		var l := Label.new()
		l.text = s
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var back := Button.new()
	back.text = "Return to the guild"
	back.pressed.connect(func(): finished.emit(_summary))
	v.add_child(back)


## Gems, projectiles and hero health, drawn in one pass.
class _Overlay:
	extends Node2D
	var view: SurvivorsView

	func _draw() -> void:
		var run: SurvivorsRun = view.run
		for g in run.gems:
			var c := Palette.CRYSTALS if int(g["xp"]) <= 1 else (Palette.TOKENS if int(g["xp"]) < 50 else Palette.RANK_S)
			draw_colored_polygon(PackedVector2Array([g["pos"] + Vector2(0, -6), g["pos"] + Vector2(4, 0), g["pos"] + Vector2(0, 6), g["pos"] + Vector2(-4, 0)]), c)
		for s in run.shots:
			if s["kind"] == "shot":
				var dir: Vector2 = s["vel"].normalized()
				draw_line(s["pos"] - dir * 14.0, s["pos"], Color(1, 0.95, 0.8), 3.0)
			else:
				draw_circle(s["pos"], 7.0, Color(0.75, 0.55, 1.0))
				draw_circle(s["pos"], 4.0, Color(1, 1, 1))
		for h in run.heroes:
			if not h["alive"]:
				continue
			var p: Vector2 = h["pos"] + Vector2(-18, 8)
			draw_rect(Rect2(p, Vector2(36, 4)), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(p, Vector2(36.0 * h["hp"] / h["max_hp"], 4)), Palette.good() if h["hp"] > h["max_hp"] * 0.35 else Palette.HAZARD)
		var lp: Vector2 = run.lead()["pos"]
		draw_arc(lp + Vector2(0, 2), 18.0, 0.0, TAU, 24, Color(1, 0.8, 0.4, 0.5), 2.0)
