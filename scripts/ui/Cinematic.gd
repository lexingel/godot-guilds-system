class_name Cinematic
extends CanvasLayer
## The opening cinematic: the Night of Breaking told in illustrated shots
## (slow pans, fades, captions, a little weather) over its own narrated
## track, ending on the new guild's name and crest. Esc, B or Skip ends it;
## the shots follow the narration, so nothing skips ahead within it.
## Respects Reduce motion (no pans or shaking).

const SHOT_FADE := 0.6
## Captions: Alegreya Bold (OFL, assets/fonts/Alegreya-OFL.txt) on a dark
## plate, so they read over any shot; Cinzel's small caps broke up over busy
## art in small windows.
const CAPTION_FONT := preload("res://assets/fonts/Alegreya-Variable.ttf")
## The narrated track (made with Suno, 69.7s). Each shot is cut in the pause
## before its line and its caption appears as the line begins: the times
## below come from a speech-recognition pass over the track (word starts),
## so a new track means new numbers.
const MUSIC := ["res://assets/audio/music/opening.ogg", "res://assets/audio/music/nocturnal_dread.ogg"]
## The rifts' flash lands on "opened" (28.2s), this long after the Night's cut.
const NIGHT_HIT := 7.4
## [image, seconds, zoom from, zoom to, pan from, pan to (fractions of the
## overflow), caption, effect, caption after (seconds into the shot)]
const SHOTS := [
	["res://assets/cinematic/hall.png", 8.0, 1.12, 1.0, Vector2(-0.4, 0.2), Vector2(0.3, -0.1), "For three hundred years, the guilds of the Accord kept the rifts shut.", "glow_warm", 1.4],
	["res://assets/cinematic/oath.png", 5.9, 1.0, 1.15, Vector2.ZERO, Vector2(0.0, -0.3), "They swore one oath: close what opens,", "glow", 1.1],
	["res://assets/cinematic/seal.png", 6.9, 1.0, 1.12, Vector2(0.0, 0.2), Vector2(0.0, -0.2), "share what you find, never sell a rift.", "glow", 0.6],
	["res://assets/cinematic/night.png", 10.6, 1.0, 1.1, Vector2(0.3, 0.0), Vector2(-0.3, 0.0), "Then, in a single night, every rift in the Vale opened at once.", "night", 2.0],
	["res://assets/cinematic/march.png", 5.8, 1.15, 1.0, Vector2(0.0, 0.3), Vector2(0.0, 0.0), "Every guild of the Accord went in.", "embers", 1.3],
	["res://assets/cinematic/pillars.png", 8.2, 1.0, 1.18, Vector2(-0.3, 0.0), Vector2(0.35, -0.1), "What they found there, no one living remembers.", "glow", 1.2],
	["res://assets/cinematic/empty.png", 7.4, 1.1, 1.0, Vector2(0.3, 0.2), Vector2(-0.2, 0.0), "By morning, their halls stood empty.", "dust", 1.1],
	["res://assets/cinematic/villagers.png", 5.2, 1.1, 1.0, Vector2(0.0, 0.3), Vector2.ZERO, "The villagers still need a guild.", "glow_warm", 1.1],
	["res://assets/hamlet/backdrop.png", 10.8, 1.05, 1.0, Vector2(0.0, 0.2), Vector2.ZERO, "They have yours.", "finale", 1.3],
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
var _track := ""          # the opening track playing, followed for timing
var _clock := 0.0         # seconds since the start, when there's no track
var _cuts: Array[float] = []     # when each shot starts, from SHOTS
var _cap_shown := false
var _cap_max_w := 900.0


func _ready() -> void:
	layer = 60
	var vp := get_viewport().get_visible_rect().size
	_ground = ColorRect.new()
	_ground.color = Color.BLACK
	_ground.size = vp
	_ground.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind it takes clicks
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
	var bold := FontVariation.new()
	bold.base_font = CAPTION_FONT
	bold.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	_caption.add_theme_font_override("font", bold)
	_caption.add_theme_font_size_override("font_size", int(clampf(vp.y / 23.0, 18.0, 34.0)))
	_caption.add_theme_color_override("font_color", Color(0.97, 0.94, 1.0))
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	_caption.add_theme_constant_override("shadow_offset_x", 0)
	_caption.add_theme_constant_override("shadow_offset_y", 3)
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.04, 0.03, 0.07, 0.8)
	plate.set_corner_radius_all(6)
	plate.content_margin_left = 22
	plate.content_margin_right = 22
	plate.content_margin_top = 6
	plate.content_margin_bottom = 8
	_caption.add_theme_stylebox_override("normal", plate)
	_cap_max_w = minf(vp.x - 48.0, 1100.0)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	_ground.add_child(_caption)
	_skip = Button.new()
	_skip.text = tr("Skip")
	_skip.tooltip_text = tr("Esc skips the opening.")
	_skip.flat = true
	_skip.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	_skip.position = Vector2(vp.x - 130.0, vp.y - 48.0)
	_skip.pressed.connect(func(): _finish(true))
	_ground.add_child(_skip)
	var t := 0.0
	for sh in SHOTS:
		_cuts.append(t)
		t += float(sh[1])
	_cuts.append(t)   # the end
	for m in MUSIC:
		if ResourceLoader.exists(m):
			AudioManager.play_music(m, 0.05, false)
			_track = m
			break
	_next()


## Seconds into the opening: the narrated track's own position (so pictures
## and captions can't drift from the voice), else the clock.
func _now() -> float:
	var p := AudioManager.music_position(_track) if _track != "" else -1.0
	return p if p >= 0.0 else _clock


func _process(delta: float) -> void:
	_clock += delta
	if _shot < 0 or _shot >= SHOTS.size():
		return
	var t := _now()
	if not _cap_shown and t >= _cuts[_shot] + float(SHOTS[_shot][8]):
		_cap_shown = true
		_tw().tween_property(_caption, "modulate:a", 1.0, 0.4)
	if not _busy and t >= _cuts[_shot + 1] - SHOT_FADE:
		_next()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_finish(true)
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_B:
			_finish(true)
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
	var dur := float(s[1])
	var cam := _tw()
	cam.tween_method(func(k: float): place.call(lerpf(z0, z1, k), p0.lerp(p1, k)), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_effect(str(s[7]), vp, dur, still)
	_set_caption(tr(str(s[6])), vp)
	# In from black; _process brings the caption in as its line begins and
	# cuts to the next shot, both by the track's position.
	_cap_shown = false
	var show := _tw()
	show.tween_property(_black, "color:a", 0.0, SHOT_FADE)
	show.tween_callback(func(): _busy = false)
	if str(s[7]) == "finale":
		show.tween_callback(func(): _title_card(vp))


## The plate hugs the line: one line when it fits, else wrapped into lines
## of even length (no lone last word).
func _set_caption(text: String, vp: Vector2) -> void:
	_caption.text = text
	_caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	_caption.size = Vector2.ZERO
	var w := _caption.get_minimum_size().x
	if w > _cap_max_w:
		_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w = minf(_cap_max_w, w / ceilf(w / _cap_max_w) + 60.0)
		_caption.size = Vector2(w, 0)
	_caption.size = Vector2(w, _caption.get_minimum_size().y)
	_caption.position = Vector2((vp.x - w) * 0.5, vp.y * 0.78)


## The last shot: the guild's crest and name, just before "They have yours."
func _title_card(vp: Vector2) -> void:
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
			f.tween_interval(NIGHT_HIT)
			f.tween_property(flash, "color:a", 0.55, 0.08)
			f.tween_property(flash, "color:a", 0.0, 0.9)
			if not still:
				var sh := _tw()
				sh.tween_interval(NIGHT_HIT)
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


func _finish(skipped: bool) -> void:
	if not is_inside_tree():
		return
	_kill_tweens()
	var cb := on_done
	queue_free()
	if cb.is_valid():
		cb.call(skipped and _shot < SHOTS.size() - 1)
