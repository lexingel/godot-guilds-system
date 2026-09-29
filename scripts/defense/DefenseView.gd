class_name DefenseView
extends Node2D
## A Riftbreak defense on screen: draws a DefenseRun on its fixed field and
## takes the player's orders. Tap a pad to build, upgrade or sell; tap the
## ground to send the champion; Space calls the next wave early. On the end
## it settles the breach (GameState.resolve_breach) and emits `finished`.

signal finished(summary: Dictionary)

const THEME := preload("res://theme/guild_theme.tres")
const DISPLAY_FONT := preload("res://assets/fonts/Cinzel-Bold.ttf")
const FLOOR_PATH := "res://assets/survivors/floor_%s.png"
const ROAD_ART := "res://assets/defense/road_%s.png"   # a road strip, tiled along each path
const ROAD_W := 62.0
const TOWER_ART := "res://assets/defense/%s_%d.png"   # tower sprites by tier (0-2); the icon stands in until then
const TIER_SCALE := {"combat": 1.0, "elite": 2.0, "boss": 3.0}
const HUD_H := 56.0
const PAD_R := 26.0

var run: DefenseRun
var paused := false
var fast := false          # double speed
var autopilot := false     # screenshots: the autoplayer builds
var bench := false         # checks: never settles the breach
var _world: Node2D
var _fx: Node2D
var _board: _Board
var _top: _Top
var _cam: Camera2D
var _hud: CanvasLayer
var _root: Control
var _wave_l: Label
var _integ_l: Label
var _integ_bar: ProgressBar
var _supplies_l: Label
var _next_l: Label
var _early_btn: Button
var _speed_btn: Button
var _menu: PanelContainer
var _panel: Control
var selected_pad := -1
var _hero_nodes := {}
var _foe_nodes := {}
var _tower_nodes := {}   # pad index -> Sprite2D
var _summary := {}
var _banner_queue: Array = []
var _banner_busy := false


func setup(region: String, rank_idx: int, defenders: Array, champion: Hero, opts: Dictionary = {}) -> void:
	run = DefenseRun.new(region, rank_idx, defenders, champion, 0, opts)


func _ready() -> void:
	_world = Node2D.new()
	_world.y_sort_enabled = true
	add_child(_world)
	var floor_id := "vale" if run.region == "camp" else run.region
	if ResourceLoader.exists(FLOOR_PATH % floor_id):
		var fl := Sprite2D.new()
		fl.texture = load(FLOOR_PATH % floor_id)
		fl.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		fl.region_enabled = true
		fl.region_rect = Rect2(0, -HUD_H - 200, DefenseRun.FIELD.size.x, DefenseRun.FIELD.size.y + HUD_H + 400)
		fl.centered = false
		fl.position = Vector2(0, -HUD_H - 200)
		fl.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fl.z_index = -3
		_world.add_child(fl)
	for path in run.map["paths"]:
		var road := Line2D.new()
		road.points = PackedVector2Array(path)
		road.width = ROAD_W
		road.texture = load(ROAD_ART % run.region)
		road.texture_mode = Line2D.LINE_TEXTURE_TILE
		road.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		road.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		road.joint_mode = Line2D.LINE_JOINT_ROUND
		road.begin_cap_mode = Line2D.LINE_CAP_ROUND
		road.end_cap_mode = Line2D.LINE_CAP_ROUND
		road.z_index = -2
		_world.add_child(road)
	_board = _Board.new()
	_board.view = self
	_board.z_index = -2
	_world.add_child(_board)
	var goal := Sprite2D.new()
	# The Guild Hall itself at the camp (as grand as the guild), else a field camp.
	goal.texture = load(GameState.hamlet_texture({"id": "hall", "tier": "guild"}) if run.region == "camp" else "res://assets/hamlet/barracks_t1.png")
	goal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	goal.scale = Vector2(2, 2)
	goal.offset = Vector2(0, -goal.texture.get_height() * 0.5 + 6)
	goal.position = run.map["goal"] + Vector2(24, 0)
	_world.add_child(goal)
	for d in GameData.DEFENSE_DECOR.get(run.region, []):
		var prop := Sprite2D.new()
		var hb: Array = GameData.HAMLET_BUILDINGS.filter(func(b): return str(b["id"]) == str(d[0]))
		prop.texture = load("res://assets/survivors/pillar.png" if d[0] == "pillar" else GameState.hamlet_texture(hb[0]))
		prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		prop.scale = Vector2.ONE * (1.0 if d[0] == "pillar" else 1.6)
		prop.offset = Vector2(0, -prop.texture.get_height() * 0.5 + 4)
		prop.position = d[1]
		_world.add_child(prop)
	for h in run.heroes:
		var n := WalkSprites.make(WalkSprites.hero_key(h["hero"], str(h["role"])), 1.0)
		n.set_meta("away", GameData.faces_away(WalkSprites.hero_key(h["hero"], str(h["role"]))))
		n.material = UiKit.look_material(GameState.look_for(h["hero"]))
		_world.add_child(n)
		_hero_nodes[h["hero"].id] = n
	_top = _Top.new()
	_top.view = self
	_top.z_index = 3000
	_world.add_child(_top)
	_fx = Node2D.new()
	_fx.z_index = 20
	_world.add_child(_fx)
	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()
	_build_hud()
	AudioManager.play_music(GameData.pick_track(GameData.COMBAT_MUSIC))
	_banner(tr("The rift has broken!"), Palette.HAZARD, tr("Build towers on the pads, then call the first wave"))


## The whole field in view, under the HUD strip.
func _fit_camera() -> void:
	var vs := get_viewport_rect().size
	var z := minf(vs.x / DefenseRun.FIELD.size.x, (vs.y - HUD_H) / DefenseRun.FIELD.size.y)
	_cam.zoom = Vector2(z, z)
	_cam.position = DefenseRun.FIELD.get_center() - Vector2(0, HUD_H * 0.5 / z)


# ---------------- Frame ----------------

func _physics_process(delta: float) -> void:
	if paused or _panel != null:
		return
	for k in (2 if fast else 1):
		run.step(delta)
	if autopilot:
		run.autoplay()
	_sync()
	_play_events()
	_update_hud()
	if run.over and _panel == null:
		_show_results()


func _sync() -> void:
	for h in run.heroes:
		var n: AnimatedSprite2D = _hero_nodes[h["hero"].id]
		n.position = h["pos"]
		n.flip_h = (float(h["facing"]) < 0.0) != bool(n.get_meta("away", false))
		n.visible = h["alive"] or not h["champion"]
		n.modulate = Color(1, 1, 1) if h["alive"] else Color(0.4, 0.4, 0.45, 0.6)
		var moving: bool = h["champion"] and h["alive"] and (h["pos"] as Vector2).distance_to(h["target"]) > 4.0
		if n.animation == &"skill" and n.is_playing():
			pass
		elif moving:
			if not n.is_playing():
				n.play()
		else:
			n.stop()
			n.frame = 0
	var seen := {}
	for f in run.foes:
		seen[f["id"]] = true
		var n: AnimatedSprite2D = _foe_nodes.get(f["id"])
		if n == null:
			var key := GameData.monster_sprite_key(str(f["name"]))
			n = WalkSprites.make(key, TIER_SCALE[f["tier"]])
			n.set_meta("away", GameData.faces_away(key))
			_world.add_child(n)
			_foe_nodes[f["id"]] = n
		n.position = f["pos"]
		n.flip_h = (float(f["facing"]) < 0.0) != bool(n.get_meta("away", false))
		n.modulate = Color(2, 2, 2) if float(f["flash"]) > 0.0 else (Color(0.7, 0.85, 1.2) if float(f["slow_t"]) > 0.0 else Color(1, 1, 1))
		var still := int(f["held_by"]) >= 0 or float(f["stun_t"]) > 0.0
		if still and n.is_playing():
			n.pause()
		elif not still and not n.is_playing():
			n.play()
	for id in _foe_nodes.keys():
		if not seen.has(id):
			_foe_nodes[id].queue_free()
			_foe_nodes.erase(id)
	for i in run.pads.size():
		var pad: Dictionary = run.pads[i]
		var key := "%s:%d" % [pad["tower"], pad["tier"]]
		var t: Sprite2D = _tower_nodes.get(i)
		if pad["tower"] == "":
			if t:
				t.queue_free()
				_tower_nodes.erase(i)
			continue
		if t and t.get_meta("key") == key:
			continue
		if t:
			t.queue_free()
		t = Sprite2D.new()
		var art := TOWER_ART % [pad["tower"], int(pad["tier"])]
		t.texture = load(art) if ResourceLoader.exists(art) else load(str(GameData.DEFENSE_TOWERS[pad["tower"]]["icon"]))
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var th := float(t.texture.get_height())
		# The 96px art has its own stone base (about 12px of margin under it): seat it on the pad.
		t.scale = Vector2.ONE * ((1.0 + 0.1 * int(pad["tier"])) if ResourceLoader.exists(art) else 1.4 + 0.2 * int(pad["tier"]))
		t.offset = Vector2(0, -th * 0.5 + (26.0 if ResourceLoader.exists(art) else 8.0))
		t.position = pad["pos"]
		t.set_meta("key", key)
		_world.add_child(t)
		_tower_nodes[i] = t
	_board.queue_redraw()
	_top.queue_redraw()


func _play_events() -> void:
	for e in run.events:
		match str(e["type"]):
			"shot":
				if e["kind"] == "bolt":
					Fx.projectile(_fx, "arrow", e["from"] + Vector2(0, -40), e["to"] + Vector2(0, -16), 34.0, Color(1, 0.95, 0.8), 0.2)
				else:
					Fx.projectile(_fx, "bolt", e["from"] + Vector2(0, -40), e["to"], 30.0, Color(1.0, 0.55, 0.2), 0.3)
					Fx.burst(_fx, "explosion", e["to"], float(e["r"]) * 2.0, Color(1.0, 0.6, 0.3), 24.0)
			"pulse":
				if e["kind"] == "frost":
					Fx.ring(_fx, e["pos"], float(e["r"]), Color(0.6, 0.85, 1.0, 0.7), 0.5)
				else:
					Fx.burst(_fx, "explosion", e["pos"], float(e["r"]) * 2.0, Color(1.0, 0.85, 0.5), 20.0)
			"heal":
				Fx.sparkles(_fx, e["pos"] + Vector2(0, -24), Palette.RANK_E, 6, 20.0)
			"hero_hit":
				match str(e["role"]):
					"ranger":
						Fx.projectile(_fx, "arrow", e["from"] + Vector2(0, -24), e["to"] + Vector2(0, -16), 26.0, Color.WHITE, 0.18)
					"mage":
						Fx.projectile(_fx, "bolt", e["from"] + Vector2(0, -24), e["to"], 24.0, Color(0.6, 0.7, 1.0), 0.22)
					_:
						Fx.burst(_fx, "slash", e["to"] + Vector2(0, -16), 44.0, Color.WHITE, 28.0)
			"kill":
				Fx.burst(_fx, "impact", e["pos"] + Vector2(0, -16), 48.0 if e["tier"] == "combat" else 110.0, Color(1, 0.9, 0.7), 24.0)
				_pop_text("+%d" % int(GameData.DEFENSE_KILL_SUPPLIES[e["tier"]]), e["pos"] + Vector2(0, -44), Palette.COINS)
			"leak":
				Fx.burst(_fx, "explosion", e["pos"], 90.0, Color(1.0, 0.3, 0.25), 20.0)
				AudioManager.cue("hit_heavy", tr("[A foe breaks through]"), Palette.HAZARD)
				_pop_text("-%d" % int(GameData.DEFENSE_LEAK[e["tier"]]), e["pos"] + Vector2(0, -70), Palette.HAZARD)
			"wave":
				if e["boss"]:
					_banner(tr("The last wave!"), Palette.HAZARD, tr("A warden leads it"))
					AudioManager.cue("relic", tr("[A warden approaches]"), Palette.HAZARD)
				else:
					_banner(tr("Wave %d of %d") % [int(e["wave"]), int(e["total"])], Palette.EMBER_BRIGHT)
			"wave_clear":
				_banner(tr("Wave cleared"), Palette.RANK_E, tr("Build and upgrade before the next one"))
			"early":
				_pop_text(tr("+%d supplies") % int(e["supplies"]), run.map["goal"] + Vector2(-60, -90), Palette.COINS)
			"build":
				Fx.burst(_fx, "holy", run.pads[int(e["pad"])]["pos"] + Vector2(0, -20), 70.0, Color(1, 0.95, 0.7), 24.0)
				AudioManager.play_sfx(GameData.SFX_PATH["ui_confirm"])
			"down":
				AudioManager.cue("hit_heavy", tr("[%s falls]") % _hero_name(str(e["hero"])), Palette.HAZARD)
			"respawn":
				_pop_text(tr("%s is back") % _hero_name(str(e["hero"])), run.map["goal"] + Vector2(-70, -80), Palette.RANK_S)
			"ability":
				_pop_text(tr(str(e["name"])), e["pos"] + Vector2(0, -80), Palette.EMBER_BRIGHT)
				var an: AnimatedSprite2D = _hero_nodes.get(str(e["hero"]))
				if an and an.sprite_frames.has_animation("skill"):
					an.play("skill")
					if not an.animation_finished.is_connected(_skill_done.bind(an)):
						an.animation_finished.connect(_skill_done.bind(an))
	run.events.clear()


func _skill_done(n: AnimatedSprite2D) -> void:
	if is_instance_valid(n) and n.animation == &"skill":
		n.play("default")


func _hero_name(hero_id: String) -> String:
	for h in run.heroes:
		if h["hero"].id == hero_id:
			return str(h["hero"].name).split(" the ")[0]
	return ""


func _pop_text(text: String, at: Vector2, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.position = at - Vector2(40, 0)
	l.size = Vector2(80, 20)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fx.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", at.y - 30.0, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.tween_callback(l.queue_free)


# ---------------- Input ----------------

func _unhandled_input(event: InputEvent) -> void:
	if _panel != null:
		return
	if event.is_action_pressed("ui_cancel"):
		if _menu:
			_close_menu()
		else:
			_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		run.call_early()
		get_viewport().set_input_as_handled()
		return
	var tap: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed)
	if not tap:
		return
	var at: Vector2 = get_global_mouse_position() if event is InputEventMouseButton else get_canvas_transform().affine_inverse() * (event as InputEventScreenTouch).position
	get_viewport().set_input_as_handled()
	for i in run.pads.size():
		if (run.pads[i]["pos"] as Vector2).distance_to(at) <= PAD_R + 6.0:
			_open_menu(i)
			return
	_close_menu()
	if not run.champion().is_empty():
		run.move_champion(at)
		Fx.ring(_fx, at, 30.0, Palette.RANK_S, 0.35)


## The build menu for pad i: towers to build, or the tower's upgrade and sale.
func _open_menu(i: int) -> void:
	_close_menu()
	selected_pad = i
	var pad: Dictionary = run.pads[i]
	_menu = PanelContainer.new()
	_menu.theme = THEME
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	_menu.add_child(v)
	if pad["tower"] == "":
		var t := Label.new()
		t.text = tr("Build a tower")
		t.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		v.add_child(t)
		for type in GameData.DEFENSE_TOWERS:
			var d: Dictionary = GameData.DEFENSE_TOWERS[type]
			var b := Button.new()
			b.icon = load(str(d["icon"]))
			b.expand_icon = false
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.text = "%s — %d" % [tr(str(d["name"])), run.tower_cost(type, 0)]
			var why := run.can_build(i, type)
			b.disabled = why != ""
			b.tooltip_text = "%s%s" % [tr(str(d["desc"])), ("\n" + why) if why != "" else ""]
			b.pressed.connect(func(): run.build(i, type); _close_menu())
			v.add_child(b)
	else:
		var d: Dictionary = GameData.DEFENSE_TOWERS[pad["tower"]]
		var t := Label.new()
		t.text = tr("%s (tier %d)") % [tr(str(d["name"])), int(pad["tier"]) + 1]
		t.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		v.add_child(t)
		var desc := Label.new()
		desc.text = tr(str(d["desc"]))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 220
		desc.add_theme_font_size_override("font_size", 13)
		v.add_child(desc)
		var up := Button.new()
		var why := run.can_upgrade(i)
		up.text = tr("Upgrade — %d") % run.tower_cost(pad["tower"], int(pad["tier"]) + 1) if int(pad["tier"]) < 2 else tr("Fully upgraded")
		up.disabled = why != ""
		up.tooltip_text = why
		up.pressed.connect(func(): run.upgrade(i); _close_menu())
		v.add_child(up)
		var sell := Button.new()
		sell.text = tr("Sell — +%d") % int(int(pad["spent"]) * run.sell_back)
		sell.pressed.connect(func(): run.sell(i); _close_menu())
		v.add_child(sell)
	var close := Button.new()
	close.text = tr("Close")
	close.pressed.connect(_close_menu)
	v.add_child(close)
	_hud.add_child(_menu)
	var sp: Vector2 = get_canvas_transform() * (pad["pos"] as Vector2)
	_menu.reset_size()
	var vs := get_viewport_rect().size
	_menu.position = Vector2(clampf(sp.x + 34.0, 8.0, vs.x - _menu.size.x - 8.0), clampf(sp.y - _menu.size.y * 0.5, HUD_H, vs.y - _menu.size.y - 8.0))


func _close_menu() -> void:
	selected_pad = -1
	if _menu:
		_menu.queue_free()
		_menu = null


# ---------------- HUD ----------------

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	_root = Control.new()
	_root.theme = THEME
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_root)
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = HUD_H
	_root.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	bar.add_child(row)
	_wave_l = _hud_label(row, 18)
	var ib := VBoxContainer.new()
	ib.add_theme_constant_override("separation", 0)
	row.add_child(ib)
	_integ_l = _hud_label(ib, 13)
	_integ_bar = ProgressBar.new()
	_integ_bar.show_percentage = false
	_integ_bar.custom_minimum_size = Vector2(160, 10)
	_integ_bar.max_value = run.max_integrity
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.RANK_E
	_integ_bar.add_theme_stylebox_override("fill", fill)
	ib.add_child(_integ_bar)
	_supplies_l = _hud_label(row, 18)
	_supplies_l.add_theme_color_override("font_color", Palette.COINS)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_next_l = _hud_label(row, 15)
	_early_btn = Button.new()
	_early_btn.pressed.connect(run.call_early)
	row.add_child(_early_btn)
	_speed_btn = Button.new()
	_speed_btn.text = "x1"
	_speed_btn.tooltip_text = tr("Game speed")
	_speed_btn.pressed.connect(func():
		fast = not fast
		_speed_btn.text = "x2" if fast else "x1")
	row.add_child(_speed_btn)
	var pause := Button.new()
	pause.text = tr("Pause")
	pause.pressed.connect(_toggle_pause)
	row.add_child(pause)
	var hint := Label.new()
	hint.text = tr("Tap a pad to build · tap the ground to send your champion · Space: next wave")
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 4)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_right = -12
	hint.offset_bottom = -6
	_update_hud()


func _hud_label(parent: Control, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _update_hud() -> void:
	_wave_l.text = tr("Wave %d / %d") % [run.wave, run.waves_total]
	_integ_l.text = tr("Integrity %d / %d") % [run.integrity, run.max_integrity]
	_integ_bar.value = run.integrity
	_supplies_l.text = tr("Supplies %d") % run.supplies
	var building := run.build_t > 0.0
	_next_l.text = tr("Next wave in %ds") % int(ceil(run.build_t)) if building else (tr("Wave in progress") if not run.over else "")
	_early_btn.visible = building
	_early_btn.text = tr("Call it now (+%d)") % int(run.build_t * GameData.DEFENSE_EARLY_SUPPLIES)


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
	var l := Label.new()
	l.text = str(b[0])
	l.add_theme_font_override("font", DISPLAY_FONT)
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", b[1])
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	if str(b[2]) != "":
		var s := Label.new()
		s.text = str(b[2])
		s.add_theme_font_size_override("font_size", 16)
		s.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		s.add_theme_constant_override("outline_size", 5)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(s)
	_hud.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	box.offset_top = HUD_H + 24.0
	box.offset_bottom = HUD_H + 24.0
	box.modulate.a = 0.0
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.8 if _banner_queue.is_empty() else 1.0)
	tw.tween_property(box, "modulate:a", 0.0, 0.4)
	tw.tween_callback(box.queue_free)
	tw.tween_callback(_next_banner)


# ---------------- Panels ----------------

func _modal(title: String) -> VBoxContainer:
	_close_menu()
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
	v.add_theme_constant_override("separation", 10)
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


func _toggle_pause() -> void:
	if _panel != null:
		_close_panel()
		return
	var v := _modal(tr("Paused"))
	var resume := Button.new()
	resume.text = tr("Resume")
	resume.pressed.connect(_close_panel)
	v.add_child(resume)
	var quit := Button.new()
	quit.text = tr("Abandon the defense (counts as lost)")
	quit.pressed.connect(func():
		_close_panel()
		run.integrity = 0
		run.over = true
		run.held = false
		_show_results())
	v.add_child(quit)


func _show_results() -> void:
	if not _summary.is_empty() or _panel != null:
		return
	_summary = {"held": run.held} if bench else GameState.resolve_breach(run.result())
	AudioManager.play_sfx(GameData.SFX_PATH["victory" if run.held else "defeat"])
	var v := _modal(tr("The breach is held!") if run.held else tr("The defenders are overrun"))
	var lines: Array = [tr("Integrity %d / %d · %d foes slain") % [run.integrity, run.max_integrity, run.kills]]
	if int(_summary.get("coins", 0)) > 0:
		lines.append(tr("+%d gold · +%d essence") % [int(_summary["coins"]), int(_summary["crystals"])])
	if int(_summary.get("lost_coins", 0)) > 0 or int(_summary.get("lost_crystals", 0)) > 0:
		lines.append(tr("Lost from the stores: %d gold · %d essence") % [int(_summary["lost_coins"]), int(_summary["lost_crystals"])])
	for name in _summary.get("damaged", []):
		lines.append(tr("Damaged: %s — it works a level lower until repaired (Guild > Manage)") % str(name))
	for name in _summary.get("wounded", []):
		lines.append(tr("Wounded: %s") % str(name))
	for s in lines:
		var l := Label.new()
		l.text = s
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
	var back := Button.new()
	back.text = tr("Return to the guild")
	back.pressed.connect(func(): finished.emit(_summary))
	v.add_child(back)


# ---------------- Drawing ----------------

## Pads, posts and the reach of the selected tower, over the roads and under the sprites.
class _Board:
	extends Node2D
	var view: DefenseView

	func _draw() -> void:
		var run := view.run
		for i in run.pads.size():
			var pad: Dictionary = run.pads[i]
			var p: Vector2 = pad["pos"]
			if pad["tower"] != "":
				draw_set_transform(p + Vector2(0, 6), 0.0, Vector2(1.0, 0.45))
				draw_circle(Vector2.ZERO, PAD_R + 8.0, Color(0, 0, 0, 0.35))
				draw_set_transform(Vector2.ZERO)
			else:
				draw_circle(p + Vector2(0, 4), PAD_R, Color(0, 0, 0, 0.35))
				draw_circle(p, PAD_R, Color(0.36, 0.34, 0.33))
				draw_arc(p, PAD_R, 0, TAU, 32, Color(0.55, 0.52, 0.5), 3.0)
			if pad["tower"] == "":
				draw_line(p + Vector2(-8, 0), p + Vector2(8, 0), Color(0.85, 0.8, 0.7), 3.0)
				draw_line(p + Vector2(0, -8), p + Vector2(0, 8), Color(0.85, 0.8, 0.7), 3.0)
			if i == view.selected_pad:
				draw_arc(p, PAD_R + 4.0, 0, TAU, 32, Palette.EMBER_BRIGHT, 3.0)
				if pad["tower"] != "":
					draw_arc(p, run.tower_stat(pad, "range"), 0, TAU, 64, Color(Palette.EMBER_BRIGHT, 0.6), 2.0)
		for p in run.map["posts"]:
			draw_line(p + Vector2(18, 0), p + Vector2(18, -30), Color(0.3, 0.22, 0.15), 3.0)
			draw_colored_polygon(PackedVector2Array([p + Vector2(18, -30), p + Vector2(34, -25), p + Vector2(18, -20)]), Palette.EMBER_BRIGHT)
		var c := run.champion()
		if not c.is_empty() and c["alive"] and (c["pos"] as Vector2).distance_to(c["target"]) > 4.0:
			draw_arc(c["target"], 14.0, 0, TAU, 24, Palette.RANK_S, 2.0)


## Health bars over foes and heroes.
class _Top:
	extends Node2D
	var view: DefenseView

	func _draw() -> void:
		var run := view.run
		for f in run.foes:
			if float(f["hp"]) >= float(f["max_hp"]) and f["tier"] == "combat":
				continue
			var w := 30.0 * float(TIER_SCALE[f["tier"]])
			var at: Vector2 = (f["pos"] as Vector2) + Vector2(-w * 0.5, -60.0 * float(TIER_SCALE[f["tier"]]) - 4.0)
			draw_rect(Rect2(at, Vector2(w, 4)), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(at, Vector2(w * clampf(float(f["hp"]) / float(f["max_hp"]), 0.0, 1.0), 4)), Palette.HAZARD)
		for h in run.heroes:
			if not h["alive"]:
				continue
			var at: Vector2 = (h["pos"] as Vector2) + Vector2(-16, -66)
			draw_rect(Rect2(at, Vector2(32, 4)), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(at, Vector2(32 * clampf(float(h["hp"]) / float(h["max_hp"]), 0.0, 1.0), 4)), Palette.RANK_S if h["champion"] else Palette.RANK_E)
