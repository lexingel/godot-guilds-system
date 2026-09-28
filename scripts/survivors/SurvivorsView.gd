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
const TIER_SCALE := {"combat": 1.0, "elite": 2.0, "boss": 3.0}   # whole multiples keep pixels square
const CHEST_TEX := preload("res://assets/dungeon/chest_icon.png")
const PILLAR_TEX := preload("res://assets/survivors/pillar.png")
const BRAZIER_TEX := preload("res://assets/survivors/brazier.png")
const PICKUP_ICON := {"heal": preload("res://assets/skills/potion_red.png"), "magnet": preload("res://assets/skills/gem_blue_big.png"), "bomb": preload("res://assets/skills/star.png")}

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
var _floor: Sprite2D   # a patch of floor that follows the camera
var _decals := {}      # chunk -> its _Decals, for the chunks around the party
var _banner_queue: Array = []   # [text, color, sub] waiting their turn
var _banner_busy := false
var _world: Node2D
var _fx: Node2D
var _overlay: Node2D
var _top: Node2D
var _arrows: Control
var _hud: CanvasLayer
var _hud_time: Label
var _hud_kills: Label
var _hud_level: Label
var _xp_bar: ProgressBar
var _boss_bar: ProgressBar
var _boss_label: Label
var _timeline: Label
var _tray: HFlowContainer
var _tray_sig := ""
var _hero_bars := {}
var _panel: Control          # level-up / pause / results overlay, or null
var _hero_nodes := {}
var _foe_nodes := {}
var _prop_nodes := {}   # pillar / brazier id -> Sprite2D
var _frames_cache := {}
var _drag_from := Vector2.INF
var _drag_to := Vector2.INF
var _summary := {}


func setup(p_party: Array, p_biome: String) -> void:
	party = p_party
	biome = p_biome
	run = SurvivorsRun.new(party, biome)


func _ready() -> void:
	# Sprites sort themselves by height on screen (lower in front); the
	# floor, its clutter and the shadows sit on fixed layers underneath.
	_world = Node2D.new()
	_world.y_sort_enabled = true
	add_child(_world)
	var floor_tex: Texture2D = load(FLOOR_PATH % biome) if ResourceLoader.exists(FLOOR_PATH % biome) else null
	if floor_tex:
		_floor = Sprite2D.new()
		_floor.texture = floor_tex
		_floor.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_floor.region_enabled = true
		_floor.region_rect = Rect2(-4096, -4096, 8192, 8192)
		_floor.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_floor.z_index = -3
		_world.add_child(_floor)
	_overlay = _Overlay.new()
	_overlay.view = self
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_overlay.z_index = -1
	_world.add_child(_overlay)
	# Health bars and cooldowns float above every sprite.
	_top = _TopOverlay.new()
	_top.view = self
	_top.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_top.z_index = 3000
	_world.add_child(_top)
	_fx = Node2D.new()
	_fx.z_index = 20
	_world.add_child(_fx)
	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()
	for h in run.heroes:
		# The hero's own walk cycle (their subclass look), else their role's.
		var own := "sub_" + str(h["hero"].pool_id)
		var n := _make_sprite(own if ResourceLoader.exists(WALK_DIR + own + "_0.png") else str(h["role"]), 1.0)
		n.material = UiKit.look_material(GameState.look_for(h["hero"]))
		_world.add_child(n)
		_hero_nodes[h["hero"].id] = n
	_build_hud()
	AudioManager.play_music(GameData.pick_track(GameData.COMBAT_MUSIC))


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
		while run.pending_chests > 0:
			var c := run.chest_offer()
			run.take_relic(c[0] if not c.is_empty() else "")
	if run.pending_levels > 0:
		_show_level_up()
	elif run.pending_chests > 0:
		_show_chest()
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
	for dev in Input.get_connected_joypads():
		var stick := Vector2(Input.get_joy_axis(dev, JOY_AXIS_LEFT_X), Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y))
		if stick.length() > 0.25:
			d += stick
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT):
			d.x -= 1
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT):
			d.x += 1
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_UP):
			d.y -= 1
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_DOWN):
			d.y += 1
	if d == Vector2.ZERO and _drag_from != Vector2.INF and _drag_to != Vector2.INF:
		var v := _drag_to - _drag_from
		if v.length() > 12.0:
			d = v
	return d.normalized()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START and not run.over and run.pending_levels == 0 and run.pending_chests == 0:
		_toggle_pause()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode in [KEY_ESCAPE, KEY_P] and not run.over and run.pending_levels == 0 and run.pending_chests == 0:
			_toggle_pause()
		elif _panel != null and (run.pending_levels > 0 or run.pending_chests > 0) and event.physical_keycode in [KEY_1, KEY_2, KEY_3]:
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


## Ground clutter (grass, stones, reeds, cracks...) for the chunks around
## the camera, each drawn once when it comes near and dropped when far.
func _refresh_decals() -> void:
	var cc := Vector2i(floori(_cam.position.x / SurvivorsRun.CHUNK), floori(_cam.position.y / SurvivorsRun.CHUNK))
	var want := {}
	for dx in range(-2, 3):
		for dy in range(-1, 2):
			want[cc + Vector2i(dx, dy)] = true
	for c in _decals.keys():
		if not want.has(c):
			_decals[c].queue_free()
			_decals.erase(c)
	for c in want:
		if not _decals.has(c):
			var d := _Decals.new()
			d.chunk = c
			d.biome = biome
			d.run_seed = run._seed
			d.z_index = -2
			_world.add_child(d)
			_decals[c] = d


func _sync() -> void:
	# Eases after the lead once per physics tick (a fixed step). Godot's own
	# smoothing scales with frame time and overshoots on a long frame; a few
	# of those ran the view off to NaN and the whole field went grey.
	var lead_pos: Vector2 = run.lead()["pos"]
	var eased := _cam.position.lerp(lead_pos, 0.13)
	_cam.position = eased if is_finite(eased.x) and is_finite(eased.y) else lead_pos
	if _floor:
		# Snapped to whole tiles so the pattern never shifts: the party can
		# walk as far as it likes and there's always floor under it.
		var tile := _floor.texture.get_size()
		_floor.position = (_cam.position / tile).floor() * tile
		_refresh_decals()
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
	for id in _foe_nodes.keys():
		if not seen.has(id):
			_foe_nodes[id].queue_free()
			_foe_nodes.erase(id)
	# Pillars and braziers are sprites so they sort with the crowd.
	var props := {}
	for f in run.terrain:
		if f["kind"] == "pillar":
			props[f["id"]] = [f["pos"], PILLAR_TEX]
	for b in run.braziers:
		props[b["id"]] = [b["pos"], BRAZIER_TEX]
	for id in props:
		if not _prop_nodes.has(id):
			var sp := Sprite2D.new()
			sp.texture = props[id][1]
			sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sp.centered = false
			sp.offset = Vector2(-sp.texture.get_width() * 0.5, -sp.texture.get_height() + 8.0)
			sp.position = props[id][0]
			_world.add_child(sp)
			_prop_nodes[id] = sp
	for id in _prop_nodes.keys():
		if not props.has(id):
			_prop_nodes[id].queue_free()
			_prop_nodes.erase(id)
	_overlay.queue_redraw()
	_top.queue_redraw()
	_arrows.queue_redraw()
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
					AudioManager.cue("victory" if e["tier"] == "boss" else "hit_heavy", "[The warden falls]" if e["tier"] == "boss" else "[An elite falls]")
			"hurt", "dodge":
				pass
			"ability":
				if str(e.get("name", "")) != "":
					_pop_text(str(e["name"]), e["pos"] + Vector2(0, -70), Palette.EMBER_BRIGHT)
			"heal":
				var hn: Node2D = _hero_nodes.get(e["hero"])
				if hn:
					Fx.sparkles(_fx, hn.position + Vector2(0, -20), Palette.RANK_E, 10, 30.0)
			"level":
				AudioManager.play_sfx(GameData.SFX_PATH["level_up"])
			"boss":
				if e.get("final", false):
					_banner("The Rift Warden: %s!" % str(e["name"]), Palette.HAZARD, "Bring it down to seal the rift")
				else:
					_banner("%s emerges!" % str(e["name"]), Palette.EMBER_BRIGHT)
				AudioManager.cue("boss", "[%s roars]" % str(e["name"]).split(",")[0], Palette.HAZARD)
			"wave":
				if run.time > 1.0 and str(e["wave"]) != "horde":
					_banner(str(e["name"]), Palette.TEXT, str(e["hint"]))
			"chest":
				AudioManager.cue("relic", "[A chest drops]")
			"lightning":
				Fx.line(_fx, e["pos"] + Vector2(randf_range(-30, 30), -260), e["pos"], Color(0.8, 0.9, 1.0), 0.25)
				Fx.burst(_fx, "explosion", e["pos"], 60.0, Color(0.7, 0.85, 1.0), 26.0)
			"brazier":
				Fx.burst(_fx, "explosion", e["pos"] + Vector2(0, -20), 70.0, Color(1.0, 0.7, 0.3), 24.0)
			"pickup":
				var what: String = {"heal": "Healed!", "magnet": "Shards come to you", "bomb": "Boom!"}[e["kind"]]
				_pop_text(what, e["pos"] + Vector2(0, -70), Palette.RANK_S)
				if e["kind"] == "bomb":
					Fx.ring(_fx, e["pos"], 700.0, Color(1, 0.8, 0.4), 0.5)
					AudioManager.play_sfx(GameData.SFX_PATH["hit_heavy"])
				else:
					AudioManager.play_sfx(GameData.SFX_PATH["heal" if e["kind"] == "heal" else "coin"])
			"slam":
				Fx.ring(_fx, e["pos"], e["r"], Color(1, 0.5, 0.3), 0.35)
				if e.get("hit", false):
					AudioManager.cue("hit_heavy", "[A slam hits the party]", Palette.HAZARD)
				else:
					AudioManager.cue("hit_heavy", "[Ground slam]")
			"won":
				_banner("The rift is sealed!", Palette.RANK_S)
				AudioManager.play_sfx(GameData.SFX_PATH["victory"])
			"phase":
				_banner("%s calls the horde!" % str(e["name"]), Palette.HAZARD)
			"down":
				AudioManager.cue("knockout", "[%s is down]" % _hero_name(str(e["hero"])), Palette.HAZARD)
			"revive":
				var rn: Node2D = _hero_nodes.get(e["hero"])
				if rn:
					Fx.burst(_fx, "holy", rn.position + Vector2(0, -24), 90.0, Color(1, 1, 0.85), 18.0)
	run.events.clear()


func _hero_name(hero_id: String) -> String:
	for h in run.heroes:
		if h["hero"].id == hero_id:
			return str(h["hero"].name).split(" the ")[0]
	return "A hero"


## A short name floating up over the field (an Ability going off).
func _pop_text(text: String, at: Vector2, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.position = at - Vector2(60, 0)
	l.size = Vector2(120, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fx.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 30.0, 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tw.tween_callback(l.queue_free)


# ---------------- HUD ----------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	# The field darkens toward the screen's edges, so the party in the middle
	# stands out from the crowd, and a shade under the top readouts keeps the
	# timer legible over a horde.
	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	vg.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.08), Color(0.02, 0.01, 0.04, 0.6)])
	var vt := GradientTexture2D.new()
	vt.gradient = vg
	vt.fill = GradientTexture2D.FILL_RADIAL
	vt.fill_from = Vector2(0.5, 0.5)
	vt.fill_to = Vector2(1.05, 0.5)
	vt.width = 128
	vt.height = 128
	var sg := Gradient.new()
	sg.colors = PackedColorArray([Color(0.02, 0.01, 0.04, 0.7), Color(0.02, 0.01, 0.04, 0.0)])
	var st := GradientTexture2D.new()
	st.gradient = sg
	st.fill_from = Vector2(0.5, 0.0)
	st.fill_to = Vector2(0.5, 1.0)
	st.width = 4
	st.height = 64
	for spec in [[vt, Control.PRESET_FULL_RECT, 0.0], [st, Control.PRESET_TOP_WIDE, 118.0]]:
		var shade := TextureRect.new()
		shade.texture = spec[0]
		shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shade.stretch_mode = TextureRect.STRETCH_SCALE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hud.add_child(shade)
		shade.set_anchors_and_offsets_preset(spec[1])
		if spec[2] > 0.0:
			shade.offset_bottom = spec[2]
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
	_timeline = _hud_label(top, 15)
	_timeline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timeline.modulate = Color(1, 1, 1, 0.85)
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
	_arrows = _Arrows.new()
	_arrows.view = self
	_arrows.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_arrows)
	_tray = HFlowContainer.new()
	_tray.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_tray.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tray.offset_right = -16
	_tray.offset_bottom = -34
	_tray.custom_minimum_size.x = 330
	_tray.alignment = FlowContainer.ALIGNMENT_END
	_tray.add_theme_constant_override("h_separation", 4)
	_tray.add_theme_constant_override("v_separation", 4)
	root.add_child(_tray)
	var hint := _hud_label(root, 14)
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
	var up: Array = run.upcoming()
	_timeline.text = "  ·  ".join(up.map(func(u): return "%s %d:%02d" % [u["label"], int(u["in"]) / 60, int(u["in"]) % 60]))
	var tray: Array = run.tray()
	var sig := str(tray.map(func(t): return [t["name"], t["count"]]))
	if sig != _tray_sig:
		_tray_sig = sig
		_rebuild_tray(tray)
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


## Your picks as icons, with stack counts; hover for the name.
func _rebuild_tray(tray: Array) -> void:
	for c in _tray.get_children():
		c.queue_free()
	for t in tray:
		var slot := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.55)
		sb.set_border_width_all(1)
		sb.border_color = Palette.RANK_S if t["special"] else Palette.LINE
		sb.set_corner_radius_all(3)
		slot.add_theme_stylebox_override("panel", sb)
		slot.tooltip_text = str(t["name"])
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		var ic := TextureRect.new()
		ic.texture = load(str(t["icon"]))
		ic.custom_minimum_size = Vector2(26, 26)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(ic)
		if int(t["count"]) > 1:
			var n := Label.new()
			n.text = str(t["count"])
			n.add_theme_font_size_override("font_size", 11)
			n.add_theme_color_override("font_outline_color", Color.BLACK)
			n.add_theme_constant_override("outline_size", 4)
			n.size_flags_horizontal = Control.SIZE_SHRINK_END
			n.size_flags_vertical = Control.SIZE_SHRINK_END
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(n)
		_tray.add_child(slot)


## A headline across the top (a wave, a boss, the rift sealed). They queue:
## one shows at a time, sooner gone when another is waiting.
func _banner(text: String, color: Color, sub: String = "") -> void:
	_banner_queue.append([text, color, sub])
	if not _banner_busy:
		_next_banner()


func _next_banner() -> void:
	if _banner_queue.is_empty() or not is_inside_tree():
		_banner_busy = false
		return
	_banner_busy = true
	var b: Array = _banner_queue.pop_front()
	var box := VBoxContainer.new()
	box.theme = THEME
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = str(b[0])
	l.add_theme_font_override("font", DISPLAY_FONT)
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_color_override("font_color", b[1])
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	if str(b[2]) != "":
		var s := Label.new()
		s.text = str(b[2])
		s.add_theme_font_size_override("font_size", 18)
		s.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		s.add_theme_constant_override("outline_size", 5)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(s)
	_hud.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_left = 40
	box.offset_right = -40
	box.offset_top = 104
	box.offset_bottom = 104
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.15)
	tw.tween_interval(2.2 if _banner_queue.is_empty() else 1.2)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(box.queue_free)
	tw.tween_callback(_next_banner)


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
	_pick_cards(_modal("Level %d" % run.level), run.offer(), run.pick, "Everything is maxed — carry on")


## A chest: one rift relic of three, for the rest of the run.
func _show_chest() -> void:
	var v := _modal("A rift chest")
	var sub := Label.new()
	sub.text = "Take one relic for the rest of this run"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var offer: Array = run.chest_offer().map(func(id): return "relic:" + str(id))
	_pick_cards(v, offer, func(id: String): run.take_relic(id.trim_prefix("relic:")), "Every relic found: take 60 gold")


func _pick_cards(v: VBoxContainer, offer: Array, choose: Callable, empty_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	for i in offer.size():
		var id: String = offer[i]
		var u: Dictionary = run.upgrade_info(id)
		var b := Button.new()
		b.custom_minimum_size = Vector2(200, 150)
		b.focus_mode = Control.FOCUS_ALL if not Input.get_connected_joypads().is_empty() else Control.FOCUS_NONE
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
		var have := int(u["have"])
		nm.text = "%d. %s%s" % [i + 1, u["name"], "  (%d/%d)" % [have + 1, u["max"]] if have > 0 else ""]
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_color_override("font_color", Palette.RANK_S if u.get("special", false) else Palette.EMBER_BRIGHT)
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
			choose.call(id)
			_close_panel())
		row.add_child(b)
		if i == 0 and b.focus_mode == Control.FOCUS_ALL:
			b.grab_focus.call_deferred()
	if offer.is_empty():
		var ok := Button.new()
		ok.text = empty_text
		ok.pressed.connect(func():
			choose.call("")
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
	var owned: Array = run.owned_lines()
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
		print("[bench] t=%d foes=%d shots=%d gems=%d fps=%d step=%.2fms physics=%.1fms process=%.1fms draws=%d prims=%d" % [int(run.time), run.foes.size(), run.shots.size(), run.gems.size(),
			Engine.get_frames_per_second(), _bench_us / 1000.0 / maxi(1, _bench_steps),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
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
	var v := _modal("The rift is sealed!" if run.won else "The rift closes")
	var lines := [
		("Sealed at %d:%02d" if run.won else "Survived %d:%02d") % [t / 60, t % 60] + ("  — a new best!" if _summary.get("best", false) else ""),
		"%d kills · %d elites · %d wardens · reached level %d" % [run.kills, run.elites_killed, run.bosses_killed, run.level],
		"+%d gold · +%d essence · +%d XP for every hero" % [_summary["coins"], _summary["crystals"], _summary["xp"]],
	]
	for name in _summary.get("loot", []):
		lines.append("Found: %s" % name)
	for m in _summary.get("milestones", []):
		lines.append("Milestone! " + str(m))
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
# ---------------- Shapes ----------------
## Every circle, shard, shadow and bar on the field comes out of one small
## texture: a disc, a diamond and a solid block. Drawn as textured squares
## from it, the renderer batches them into a few draw calls; drawn with
## draw_circle and polygons, each was a call of its own (about 1,500 a frame
## at 6:00, which is what made the Endless Rift crawl in a browser).
const SHAPE_DISC := Rect2(0, 0, 64, 64)
const SHAPE_DIAMOND := Rect2(64, 0, 32, 32)
const SHAPE_SOLID := Rect2(76, 12, 8, 8)
static var _shape_tex: ImageTexture


static func shape_tex() -> ImageTexture:
	if _shape_tex == null:
		var img := Image.create(96, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				img.set_pixel(x, y, Color(1, 1, 1, clampf(32.0 - Vector2(x + 0.5 - 32.0, y + 0.5 - 32.0).length(), 0.0, 1.0)))
		for y in 32:
			for x in 32:
				img.set_pixel(64 + x, y, Color(1, 1, 1, clampf(16.0 - absf(x + 0.5 - 16.0) - absf(y + 0.5 - 16.0), 0.0, 1.0)))
		_shape_tex = ImageTexture.create_from_image(img)
	return _shape_tex


## Draws shapes from the shape texture onto one canvas item and gathers its
## lines, drawn together by flush() (call it last, inside that _draw).
class _Pen:
	var ci: CanvasItem
	var tex: Texture2D
	var width := 2.5
	var pts := PackedVector2Array()
	var cols := PackedColorArray()

	func _init(p_ci: CanvasItem, p_width: float = 2.5) -> void:
		ci = p_ci
		tex = SurvivorsView.shape_tex()
		width = p_width

	## A filled circle; `squash` flattens it into a ground ellipse.
	func disc(c: Vector2, r: float, col: Color, squash: float = 1.0) -> void:
		var half := Vector2(r, r * squash)
		ci.draw_texture_rect_region(tex, Rect2(c - half, half * 2.0), SurvivorsView.SHAPE_DISC, col)

	func diamond(c: Vector2, half: Vector2, col: Color) -> void:
		ci.draw_texture_rect_region(tex, Rect2(c - half, half * 2.0), SurvivorsView.SHAPE_DIAMOND, col)

	func box(r: Rect2, col: Color) -> void:
		ci.draw_texture_rect_region(tex, r, SurvivorsView.SHAPE_SOLID, col)

	func line(a: Vector2, b: Vector2, col: Color) -> void:
		pts.append(a)
		pts.append(b)
		cols.append(col)

	func arc(c: Vector2, r: float, a0: float, a1: float, n: int, col: Color, squash: float = 1.0) -> void:
		var prev := c + Vector2(cos(a0) * r, sin(a0) * r * squash)
		for k in range(1, n + 1):
			var a := lerpf(a0, a1, float(k) / n)
			var p := c + Vector2(cos(a) * r, sin(a) * r * squash)
			line(prev, p, col)
			prev = p

	func flush() -> void:
		if not pts.is_empty():
			ci.draw_multiline_colors(pts, cols, width)


class _Overlay:
	extends Node2D
	var view: SurvivorsView

	func _draw() -> void:
		var run: SurvivorsRun = view.run
		var pen := SurvivorsView._Pen.new(self)
		for f in run.terrain:
			var p: Vector2 = f["pos"]
			var r: float = f["r"]
			match str(f["kind"]):
				"pool":
					pen.disc(p, r + 3.0, Color(0.3, 0.36, 0.3, 0.8))
					pen.disc(p, r, Color(0.24, 0.33, 0.36, 0.85))
					pen.arc(p + Vector2(-r * 0.2, -r * 0.2), r * 0.5, PI * 1.1, PI * 1.5, 10, Color(0.55, 0.66, 0.68, 0.45))
				"lava":
					# A crust of dark rock split by glowing cracks.
					pen.disc(p, r + 4.0, Color(0.14, 0.1, 0.09, 0.9))
					pen.disc(p, r, Color(0.24, 0.13, 0.1, 0.95))
					var glow := 0.55 + 0.25 * sin(run.time * 3.0 + p.x)
					pen.disc(p, r * 0.35, Color(0.8, 0.3, 0.08, glow))
					for k in 6:
						var a := TAU * k / 6.0 + p.y
						var mid := p + Vector2.RIGHT.rotated(a + 0.25) * r * 0.6
						pen.line(p + Vector2.RIGHT.rotated(a) * r * 0.25, mid, Color(1.0, 0.55, 0.15, glow))
						pen.line(mid, p + Vector2.RIGHT.rotated(a - 0.1) * r * 0.95, Color(1.0, 0.55, 0.15, glow))
		# Slam warnings fill up until the blow lands.
		for sl in run.slams:
			var fill := 1.0 - clampf(float(sl["t"]) / SurvivorsRun.SLAM_WARN, 0.0, 1.0)
			pen.disc(sl["pos"], sl["r"], Color(0.9, 0.15, 0.1, 0.18))
			pen.disc(sl["pos"], sl["r"] * fill, Color(0.9, 0.2, 0.1, 0.28))
			pen.arc(sl["pos"], sl["r"], 0.0, TAU, 40, Color(1.0, 0.35, 0.2, 0.9))
		# A shadow under every foe splits the crowd into bodies; elites and
		# wardens stand on a colored ring.
		for f in run.foes:
			var r: float = f["r"]
			pen.disc(f["pos"] + Vector2(0, 2), r * 1.05, Color(0, 0, 0, 0.35), 0.38)
			if f["tier"] != "combat":
				pen.arc(f["pos"] + Vector2(0, 2), r * 1.25, 0.0, TAU, 32, Palette.ELITE if f["tier"] == "elite" else Palette.HAZARD, 0.38)
		for h in run.heroes:
			if h["alive"]:
				pen.disc(h["pos"] + Vector2(0, 2), 16.0, Color(0, 0, 0, 0.35), 0.38)
		# Shards: a dark edge and a bright core so they read on any floor.
		for g in run.gems:
			var c := Palette.CRYSTALS if int(g["xp"]) <= 1 else (Palette.TOKENS if int(g["xp"]) < 50 else Palette.RANK_S)
			var p: Vector2 = g["pos"]
			pen.diamond(p, Vector2(6, 8), Color(0.05, 0.05, 0.1, 0.9))
			pen.diamond(p, Vector2(4, 6), c)
			pen.box(Rect2(p + Vector2(-1, -3), Vector2(2, 2)), Color(1, 1, 1, 0.9))
		for sh in run.shots:
			if sh["kind"] == "shot":
				var dir: Vector2 = sh["vel"].normalized()
				pen.line(sh["pos"] - dir * 14.0, sh["pos"], Color(1, 0.95, 0.8))
			else:
				pen.disc(sh["pos"], 7.0, Color(0.75, 0.55, 1.0))
				pen.disc(sh["pos"], 4.0, Color(1, 1, 1))
		for h in run.heroes:
			if not h["alive"]:
				continue
			var p: Vector2 = h["pos"] + Vector2(-18, 8)
			pen.box(Rect2(p, Vector2(36, 4)), Color(0, 0, 0, 0.7))
			pen.box(Rect2(p, Vector2(36.0 * h["hp"] / h["max_hp"], 4)), Palette.good() if h["hp"] > h["max_hp"] * 0.35 else Palette.HAZARD)
		pen.arc(run.lead()["pos"] + Vector2(0, 2), 18.0, 0.0, TAU, 24, Color(1, 0.8, 0.4, 0.5))
		pen.flush()


## Above every sprite: elite and warden health bars.
class _TopOverlay:
	extends Node2D
	var view: SurvivorsView

	func _draw() -> void:
		var run: SurvivorsRun = view.run
		var pen := SurvivorsView._Pen.new(self)
		# Foe bolts: a dark rim and a red core.
		for bo in run.foe_shots:
			pen.disc(bo["pos"], 7.0, Color(0.1, 0.02, 0.02, 0.9))
			pen.disc(bo["pos"], 5.0, Palette.HAZARD)
			pen.disc(bo["pos"], 2.0, Color(1, 0.85, 0.7))
		# Each hero's Ability: a ring above their head that fills as it recharges.
		for h in run.heroes:
			if not h["alive"] or not h["has_ability"]:
				continue
			var at: Vector2 = h["pos"] + Vector2(0, -70)
			var full: float = run.ability_cd_max(h)
			var ready := clampf(1.0 - float(h["ab_cd"]) / full, 0.0, 1.0)
			pen.disc(at, 6.0, Color(0, 0, 0, 0.6))
			pen.arc(at, 6.0, -PI * 0.5, -PI * 0.5 + TAU * ready, 20, Palette.EMBER_BRIGHT if ready >= 0.97 else Palette.MUTED)
		for f in run.foes:
			if f["tier"] != "elite":
				continue
			var w := 52.0
			var p: Vector2 = f["pos"] + Vector2(-w * 0.5, -60.0 * SurvivorsView.TIER_SCALE["elite"] - 4.0)
			pen.box(Rect2(p - Vector2(1, 1), Vector2(w + 2, 7)), Color(0, 0, 0, 0.8))
			pen.box(Rect2(p, Vector2(w * clampf(f["hp"] / f["max_hp"], 0.0, 1.0), 5)), Palette.ELITE)
		for pk in run.pickups:
			pen.disc(pk["pos"] + Vector2(0, -8 + sin(run.time * 5.0 + pk["pos"].x) * 2.0), 13.0, Color(0, 0, 0, 0.55))
		pen.flush()
		# Icons last (their own textures), so the shapes above stay one batch.
		for pk in run.pickups:
			var bob2 := sin(run.time * 5.0 + pk["pos"].x) * 2.0
			draw_texture_rect(SurvivorsView.PICKUP_ICON[pk["kind"]], Rect2(pk["pos"] + Vector2(-10, -18 + bob2), Vector2(20, 20)), false)
		# Chests bob gently where they lie.
		for c in run.chests:
			var bob := sin(run.time * 4.0) * 3.0
			draw_texture_rect(SurvivorsView.CHEST_TEX, Rect2(c["pos"] + Vector2(-17, -30 + bob), Vector2(34, 34)), false)


## HUD edge arrows toward elites and wardens that are off screen.
class _Arrows:
	extends Control
	var view: SurvivorsView

	func _draw() -> void:
		var vp := get_viewport_rect().size
		var center: Vector2 = view._cam.get_screen_center_position()
		var inner := Rect2(Vector2(28, 145), vp - Vector2(56, 185))   # below the boss bar
		var marks: Array = []
		for f in view.run.foes:
			if f["tier"] != "combat":
				marks.append([f["pos"], Palette.HAZARD if f["tier"] == "boss" else Palette.ELITE, 16.0 if f["tier"] == "boss" else 11.0])
		for c in view.run.chests:
			marks.append([c["pos"], Palette.RANK_S, 11.0])
		for m in marks:
			var sp: Vector2 = m[0] - center + vp * 0.5
			if Rect2(Vector2.ZERO, vp).has_point(sp):
				continue
			var dir := (sp - vp * 0.5).normalized()
			# Walk from the middle toward the foe until the inner rect's edge.
			var t := INF
			for axis in 2:
				if absf(dir[axis]) > 0.001:
					var edge: float = (inner.end[axis] if dir[axis] > 0.0 else inner.position[axis]) - vp[axis] * 0.5
					t = minf(t, edge / dir[axis])
			var at := vp * 0.5 + dir * t
			var col: Color = m[1]
			var sz: float = m[2]
			var tri := PackedVector2Array([at + dir * sz, at + dir.rotated(2.4) * sz, at + dir.rotated(-2.4) * sz])
			draw_colored_polygon(tri, col)
			draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0, 0, 0, 0.9), 2.0)


## One chunk's ground clutter, painted once in 2px "pixels" in the region's
## own colors: tufts, stones and flowers in the vale; reeds, lily pads and
## mud in the marsh; cracks, embers, bones and ash in the ashen lands. Big
## faint patches first, so the floor stops reading as one repeated tile.
class _Decals:
	extends Node2D
	var chunk: Vector2i
	var biome := "vale"
	var run_seed := 0
	const P := 2.0

	var _pen: SurvivorsView._Pen

	func _px(x: float, y: float, w: float, h: float, c: Color) -> void:
		_pen.box(Rect2(Vector2(x, y).snapped(Vector2(P, P)), Vector2(w, h) * P), c)

	func _draw() -> void:
		_pen = SurvivorsView._Pen.new(self, P)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([run_seed, biome, chunk.x, chunk.y, "decals"])
		var size := SurvivorsRun.CHUNK
		var o := Vector2(chunk) * size
		var at := func() -> Vector2: return o + Vector2(rng.randf_range(0.0, size), rng.randf_range(0.0, size))
		var pal: Dictionary = {
			"vale": {"patch": [Color(0.3, 0.38, 0.2, 0.22), Color(0.5, 0.46, 0.32, 0.18)], "a": Color(0.27, 0.36, 0.2), "b": Color(0.4, 0.5, 0.26), "stone": Color(0.52, 0.5, 0.44), "dot": [Color(0.86, 0.78, 0.35), Color(0.9, 0.88, 0.82), Color(0.7, 0.5, 0.75)]},
			"marsh": {"patch": [Color(0.2, 0.26, 0.24, 0.3), Color(0.3, 0.4, 0.3, 0.2)], "a": Color(0.2, 0.3, 0.2), "b": Color(0.47, 0.38, 0.24), "stone": Color(0.42, 0.45, 0.42), "dot": [Color(0.24, 0.38, 0.24), Color(0.8, 0.8, 0.6)]},
			"ashen": {"patch": [Color(0.16, 0.12, 0.11, 0.3), Color(0.45, 0.42, 0.4, 0.16)], "a": Color(0.16, 0.13, 0.12), "b": Color(0.35, 0.3, 0.28), "stone": Color(0.3, 0.27, 0.26), "dot": [Color(0.95, 0.5, 0.15), Color(0.8, 0.78, 0.72)]},
		}.get(biome, {})
		if pal.is_empty():
			return
		# Faint patches of other ground, a few overlapping blobs each.
		for i in 5:
			var c: Vector2 = at.call()
			var col: Color = pal["patch"][rng.randi() % 2]
			for k in 4:
				_pen.disc(c + Vector2(rng.randf_range(-40, 40), rng.randf_range(-24, 24)), rng.randf_range(26, 56), col)
		for i in 26:
			var p: Vector2 = at.call()
			match biome:
				"vale":
					# A tuft of blades, two greens.
					for k in rng.randi_range(3, 5):
						var hgt := rng.randi_range(2, 4)
						_px(p.x + k * P, p.y - hgt * P, 1, hgt, pal["a"] if k % 2 == 0 else pal["b"])
				"marsh":
					# A reed clump with brown heads.
					for k in rng.randi_range(2, 4):
						var hgt := rng.randi_range(4, 7)
						_px(p.x + k * P * 1.5, p.y - hgt * P, 1, hgt, pal["a"])
						_px(p.x + k * P * 1.5, p.y - (hgt + 2) * P, 1, 2, pal["b"])
				"ashen":
					# A crack in the crust.
					var pts := PackedVector2Array([p])
					var dir := Vector2.RIGHT.rotated(rng.randf() * TAU)
					for k in 4:
						dir = dir.rotated(rng.randf_range(-0.7, 0.7))
						pts.append(pts[pts.size() - 1] + dir * rng.randf_range(6, 14))
					for k in pts.size() - 1:
						_pen.line(pts[k], pts[k + 1], pal["a"])
		for i in 9:
			# Stones with a lit top and a shadow.
			var p: Vector2 = at.call()
			var w := rng.randi_range(2, 4)
			var st: Color = pal["stone"]
			_px(p.x, p.y + P, w, 1, st.darkened(0.45))
			_px(p.x, p.y - P, w, 2, st)
			_px(p.x + P, p.y - P, 1, 1, st.lightened(0.3))
		for i in 10:
			# Small bright bits: flowers, lily pads, embers or bones.
			var p: Vector2 = at.call()
			var dots: Array = pal["dot"]
			var col: Color = dots[rng.randi() % dots.size()]
			match biome:
				"vale":
					_px(p.x, p.y + P, 1, 1, pal["a"])
					_px(p.x, p.y, 1, 1, col)
					_px(p.x + P * 2, p.y + P, 1, 1, col)
				"marsh":
					if col == dots[0]:
						_pen.disc(p, 6.0, col)
						_pen.line(p, p + Vector2(6, -2), pal["patch"][0].darkened(0.4))
					else:
						_px(p.x, p.y, 1, 1, col)
				"ashen":
					if col == dots[0]:
						_pen.disc(p, 5.0, Color(col, 0.18))
						_px(p.x, p.y, 1, 1, col)
					else:
						_px(p.x, p.y, 3, 1, col)
						_px(p.x + P, p.y - P, 1, 3, col)
		_pen.flush()
