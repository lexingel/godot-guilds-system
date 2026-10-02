class_name Cinematic
extends CanvasLayer
## The opening cinematic: the Night of Breaking told in a few illustrated
## shots (slow pans, fades, captions, a little weather), ending on the new
## guild's name and crest. Space, Enter or a click moves to the next shot;
## Esc (or Skip) ends it. Respects Reduce motion (no pans or shaking).

const SHOT_FADE := 0.6
## Shot lengths follow the opening's track (opening.ogg, 60s): the Night's
## flash lands on its hit at ~13.8s and the last shot ends in its fade.
## Narration: line N of the opening for the game's language, if recorded
## (shots 1-7 speak lines 1-7; the guild's name brings line 8). A language
## without files plays with captions only.
const VOICE_PATH := "res://assets/audio/vo/%s/opening_%d.ogg"
## Its music: a dedicated track if one is ever added, else a camp track.
const MUSIC := ["res://assets/audio/music/opening.ogg", "res://assets/audio/music/nocturnal_dread.ogg"]
## [image, seconds, zoom from, zoom to, pan from, pan to (fractions of the
## overflow), caption, effect]
const SHOTS := [
	["res://assets/cinematic/hall.png", 6.5, 1.12, 1.0, Vector2(-0.4, 0.2), Vector2(0.3, -0.1), "For three hundred years, the guilds of the Accord kept the rifts shut.", "glow_warm"],
	["res://assets/cinematic/oath.png", 6.5, 1.0, 1.15, Vector2.ZERO, Vector2(0.0, -0.3), "They swore one oath: close what opens, share what you find, never sell a rift.", "glow"],
	["res://assets/cinematic/night.png", 7.5, 1.0, 1.1, Vector2(0.3, 0.0), Vector2(-0.3, 0.0), "Then, in a single night, every rift in the Vale opened at once.", "night"],
	["res://assets/cinematic/march.png", 7.5, 1.15, 1.0, Vector2(0.0, 0.3), Vector2(0.0, 0.0), "Every guild of the Accord went in.", "embers"],
	["res://assets/cinematic/pillars.png", 8.0, 1.0, 1.18, Vector2(-0.3, 0.0), Vector2(0.35, -0.1), "What they found there, no one living remembers.", "glow"],
	["res://assets/cinematic/empty.png", 7.5, 1.1, 1.0, Vector2(0.3, 0.2), Vector2(-0.2, 0.0), "By morning, their halls stood empty.", "dust"],
	["res://assets/hamlet/backdrop.png", 14.0, 1.05, 1.0, Vector2(0.0, 0.2), Vector2.ZERO, "The villages still need a guild.", "finale"],
]

var guild_name := ""
var crest_path := ""
var on_done: Callable          # called with true if the player skipped it all
var _shot := -1
var _busy := false
var _tweens: Array[Tween] = []
var _ground: ColorRect
var _pic: TextureRect
var _fx: Control
var _black: ColorRect
var _caption: Label
var _skip: Button


func _ready() -> void:
	layer = 60
	var vp := get_viewport().get_visible_rect().size
	_ground = ColorRect.new()
	_ground.color = Color.BLACK
	_ground.size = vp
	_ground.mouse_filter = Control.MOUSE_FILTER_STOP
	_ground.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_next())
	add_child(_ground)
	_pic = TextureRect.new()
	_pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pic.stretch_mode = TextureRect.STRETCH_SCALE
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.add_child(_pic)
	_fx = Control.new()
	_fx.size = vp
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.add_child(_fx)
	# A soft dark band under the captions, so they read over busy art.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.8)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var band := TextureRect.new()
	band.texture = gt
	band.stretch_mode = TextureRect.STRETCH_SCALE
	band.size = Vector2(vp.x, vp.y * 0.4)
	band.position = Vector2(0, vp.y * 0.6)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.add_child(band)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.size = vp
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.add_child(_black)
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_override("font", UiKit.DISPLAY_FONT)
	_caption.add_theme_font_size_override("font_size", int(clampf(vp.y / 26.0, 16.0, 30.0)))
	_caption.add_theme_color_override("font_color", Color(0.95, 0.92, 1.0))
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_caption.add_theme_constant_override("outline_size", 6)
	_caption.size = Vector2(minf(vp.x - 48.0, 900.0), vp.y * 0.2)
	_caption.position = Vector2((vp.x - _caption.size.x) * 0.5, vp.y * 0.76)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	_ground.add_child(_caption)
	_skip = Button.new()
	_skip.text = tr("Skip")
	_skip.tooltip_text = tr("Esc skips the opening; Space or a click goes to the next scene.")
	_skip.flat = true
	_skip.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_skip.position = Vector2(vp.x - 130.0, vp.y - 48.0)
	_skip.pressed.connect(func(): _finish(true))
	_ground.add_child(_skip)
	for m in MUSIC:
		if ResourceLoader.exists(m):
			AudioManager.play_music(m, 0.5, false)
			break
	_next()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_finish(true)
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_next()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_B:
			_finish(true)
		elif event.button_index == JOY_BUTTON_A:
			_next()
		get_viewport().set_input_as_handled()


func _kill_tweens() -> void:
	for t in _tweens:
		if is_instance_valid(t):
			t.kill()
	_tweens.clear()


func _tw() -> Tween:
	var t := create_tween()
	_tweens.append(t)
	return t


## Fades to black, then the next shot (or the end).
func _next() -> void:
	if _busy:
		return
	_busy = true
	_kill_tweens()
	var out := _tw()
	out.tween_property(_black, "color:a", 1.0, SHOT_FADE if _shot >= 0 else 0.0)
	out.parallel().tween_property(_caption, "modulate:a", 0.0, SHOT_FADE * 0.6)
	out.tween_callback(func():
		_shot += 1
		if _shot >= SHOTS.size():
			_finish(false)
			return
		_play(_shot))


func _play(i: int) -> void:
	var s: Array = SHOTS[i]
	for c in _fx.get_children():
		c.queue_free()
	var vp := get_viewport().get_visible_rect().size
	var tex: Texture2D = load(str(s[0]))
	_pic.texture = tex
	var base := maxf(vp.x / tex.get_width(), vp.y / tex.get_height())
	var still := GameState.reduce_motion
	var z0: float = 1.0 if still else float(s[2])
	var z1: float = 1.0 if still else float(s[3])
	var p0: Vector2 = Vector2.ZERO if still else s[4]
	var p1: Vector2 = Vector2.ZERO if still else s[5]
	var place := func(z: float, p: Vector2) -> void:
		var sz: Vector2 = tex.get_size() * base * z
		_pic.size = sz
		var spare := sz - vp   # how far the picture overhangs the screen
		_pic.position = -spare * 0.5 + Vector2(spare.x * 0.5 * p.x, spare.y * 0.5 * p.y)
	place.call(z0, p0)
	_pic.modulate = Color.WHITE
	AudioManager.stop_voice()
	var spoken := AudioManager.play_voice(_voice_path(i + 1))
	var dur := maxf(float(s[1]), spoken + 2.2)   # the shot waits for its line
	var cam := _tw()
	cam.tween_method(func(k: float): place.call(lerpf(z0, z1, k), p0.lerp(p1, k)), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_effect(str(s[7]), vp, dur, still)
	_caption.text = tr(str(s[6]))
	var show := _tw()
	show.tween_property(_black, "color:a", 0.0, SHOT_FADE)
	show.tween_callback(func(): _busy = false)
	show.tween_property(_caption, "modulate:a", 1.0, 0.8).set_delay(0.3)
	if str(s[7]) == "finale":
		var last := ResourceLoader.exists(_voice_path(i + 2))
		show.tween_interval(maxf(2.4, spoken - 0.6))
		show.tween_property(_caption, "modulate:a", 0.0, 0.5)
		show.tween_callback(func(): _title_card(vp))
		show.tween_property(_caption, "modulate:a", 1.0, 0.8)
		var tail := maxf(4.0, dur - 5.4)   # the rest of the shot (fades in, caption, name)
		if last:
			var stream: AudioStream = load(_voice_path(i + 2))
			tail = maxf(tail, stream.get_length() + 2.5)
		show.tween_interval(tail)
	else:
		show.tween_interval(maxf(1.0, dur - SHOT_FADE - 1.1 - SHOT_FADE))
	show.tween_callback(_next)


## The last shot: the guild's crest and name, then "They have yours."
func _title_card(vp: Vector2) -> void:
	_caption.text = tr("They have yours.")
	AudioManager.play_voice(_voice_path(SHOTS.size() + 1))
	if guild_name == "":   # watched from the title screen, before any guild
		return
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	if crest_path != "" and ResourceLoader.exists(crest_path):
		var crest := TextureRect.new()
		crest.texture = load(crest_path)
		crest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		crest.custom_minimum_size = Vector2.ONE * clampf(vp.y / 6.0, 56.0, 120.0)
		crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(crest)
	var name_l := Label.new()
	name_l.text = guild_name
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_override("font", UiKit.DISPLAY_FONT)
	name_l.add_theme_font_size_override("font_size", int(clampf(vp.y / 12.0, 28.0, 64.0)))
	name_l.add_theme_color_override("font_color", Color(0.95, 0.76, 0.3))
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_l.add_theme_constant_override("outline_size", 8)
	box.add_child(name_l)
	box.size = Vector2(vp.x, vp.y * 0.5)
	box.position = Vector2(0, vp.y * 0.18)
	box.modulate.a = 0.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(box)
	_tw().tween_property(box, "modulate:a", 1.0, 1.2)


func _effect(kind: String, vp: Vector2, dur: float, still: bool) -> void:
	match kind:
		"glow", "glow_warm":
			var t := _tw().set_loops(maxi(1, int(dur / 2.4)))
			var hi := Color(1.12, 1.02, 0.9) if kind == "glow_warm" else Color(1.05, 0.98, 1.18)
			t.tween_property(_pic, "modulate", hi, 1.2).set_trans(Tween.TRANS_SINE)
			t.tween_property(_pic, "modulate", Color.WHITE, 1.2).set_trans(Tween.TRANS_SINE)
		"night":
			# The rifts tear open: a flash of rift light, the ground shakes, embers.
			var flash := ColorRect.new()
			flash.color = Color(0.7, 0.5, 1.0, 0.0)
			flash.size = vp
			flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_fx.add_child(flash)
			var f := _tw()
			f.tween_interval(0.8)
			f.tween_property(flash, "color:a", 0.55, 0.08)
			f.tween_property(flash, "color:a", 0.0, 0.9)
			if not still:
				var sh := _tw()
				sh.tween_interval(0.8)
				for k in 10:
					sh.tween_property(_fx, "position", Vector2(randf_range(-6, 6), randf_range(-4, 4)), 0.05)
				sh.tween_property(_fx, "position", Vector2.ZERO, 0.05)
			_particles(vp, Color(1.0, 0.55, 0.25), 60, Vector2(0, -40), 2.5)
		"embers":
			_particles(vp, Color(0.75, 0.55, 1.0), 40, Vector2(0, -25), 3.0)
		"dust":
			_particles(vp, Color(1.0, 0.95, 0.8, 0.5), 30, Vector2(6, 4), 6.0, true)
		"finale":
			_particles(vp, Color(1.0, 0.6, 0.25), 45, Vector2(0, -30), 3.0)


## Drifting motes over the shot (embers rise; dust floats anywhere).
func _particles(vp: Vector2, col: Color, n: int, vel: Vector2, life: float, anywhere: bool = false) -> void:
	var p := CPUParticles2D.new()
	p.amount = n
	p.lifetime = life
	p.preprocess = life
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(vp.x * 0.5, vp.y * (0.5 if anywhere else 0.1))
	p.position = Vector2(vp.x * 0.5, vp.y * (0.5 if anywhere else 0.95))
	p.direction = vel.normalized() if vel != Vector2.ZERO else Vector2.UP
	p.spread = 25.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = vel.length() * 0.6
	p.initial_velocity_max = vel.length() * 1.4
	p.scale_amount_min = maxf(2.0, vp.y / 320.0)
	p.scale_amount_max = maxf(4.0, vp.y / 180.0)
	p.color = col
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(col, 0.0), col, Color(col, 0.0)])
	p.color_ramp = ramp
	_fx.add_child(p)


func _voice_path(line: int) -> String:
	return VOICE_PATH % [str(GameState.language).substr(0, 2), line]


func _finish(skipped: bool) -> void:
	if not is_inside_tree():
		return
	_kill_tweens()
	AudioManager.stop_voice()
	var cb := on_done
	queue_free()
	if cb.is_valid():
		cb.call(skipped and _shot < SHOTS.size() - 1)
