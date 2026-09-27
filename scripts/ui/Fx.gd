class_name Fx
extends RefCounted
## Visual effects that play at a point on any Control: frame-animated sprites
## (assets/vfx/<id>_<n>.png, PixelLab), plus code-driven projectiles, rings,
## domes, sigils, lines and particles. Battle playback uses them today; they
## take only a parent and positions in its space, so a real-time mode can
## reuse them as they are. Everything is fire-and-forget: calls that take
## time return the Tween so a caller can await it (bounded) if it wants to.

## Frame-animated effects and their frame counts (frame 0 = the keyframe).
const FRAMES := {"slash": 5, "impact": 5, "explosion": 9, "claw": 7, "holy": 9, "flame": 7}
## Single-image effects moved/scaled by tweens.
const STATIC := ["bolt", "arrow", "shield", "shockwave", "sigil"]
## The arrow sprite points up-right; rotate by this to point along +x.
const ARROW_BASE_ANGLE := deg_to_rad(45.0)


static func frame_path(id: String, i: int) -> String:
	return "res://assets/vfx/%s_%d.png" % [id, i]


static func static_path(id: String) -> String:
	return "res://assets/vfx/%s.png" % id


static func _sprite(parent: Node, tex: Texture2D, center: Vector2, size: float, tint: Color) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = Vector2(size, size)
	r.pivot_offset = r.size * 0.5
	r.position = center - r.size * 0.5
	r.modulate = tint
	parent.add_child(r)
	return r


## Plays a frame-animated effect once, centred at `center`, then frees it.
static func burst(parent: Node, id: String, center: Vector2, size: float, tint: Color = Color.WHITE, fps: float = 20.0, rot: float = 0.0, flip: bool = false) -> Tween:
	var n: int = FRAMES.get(id, 1)
	var r := _sprite(parent, load(frame_path(id, 0)), center, size, tint)
	r.rotation = rot
	r.flip_h = flip
	var tw := r.create_tween()
	for i in range(1, n):
		tw.tween_interval(1.0 / fps)
		tw.tween_callback(func(k=i): r.texture = load(frame_path(id, k)))
	tw.tween_interval(1.0 / fps)
	tw.tween_callback(r.queue_free)
	return tw


## A looping frame animation (e.g. a burning hero's flame) that lives as long
## as its parent. Returns the node.
static func loop(parent: Node, id: String, center: Vector2, size: float, tint: Color = Color.WHITE, fps: float = 10.0) -> TextureRect:
	var at := AnimatedTexture.new()
	var n: int = FRAMES.get(id, 1)
	at.frames = n
	for i in n:
		at.set_frame_texture(i, load(frame_path(id, i)))
		at.set_frame_duration(i, 1.0 / fps)
	return _sprite(parent, at, center, size, tint)


## Flies a sprite from `from` to `to` (a faint trail behind), then frees it.
static func projectile(parent: Node, id: String, from: Vector2, to: Vector2, size: float, tint: Color = Color.WHITE, duration: float = 0.28) -> Tween:
	var r := _sprite(parent, load(static_path(id)), from, size, tint)
	var dir := to - from
	r.rotation = dir.angle() + (ARROW_BASE_ANGLE if id == "arrow" else 0.0)
	var trail := CPUParticles2D.new()
	trail.position = r.size * 0.5
	trail.amount = 16
	trail.lifetime = 0.25
	trail.local_coords = false
	trail.spread = 10.0
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 0.0
	trail.initial_velocity_max = 8.0
	trail.scale_amount_min = 1.5
	trail.scale_amount_max = 3.0
	trail.color = Color(tint, 0.7)
	r.add_child(trail)
	var tw := r.create_tween()
	tw.tween_property(r, "position", to - r.size * 0.5, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if id == "bolt":
		tw.parallel().tween_property(r, "scale", Vector2(1.25, 1.25), duration)
	tw.tween_callback(r.queue_free)
	return tw


## A ground shockwave: a flattened ring that expands and fades.
static func ring(parent: Node, center: Vector2, radius: float, tint: Color = Color.WHITE, duration: float = 0.4) -> Tween:
	var r := _sprite(parent, load(static_path("shockwave")), center, radius * 2.0, tint)
	r.scale = Vector2(0.2, 0.08)
	var tw := r.create_tween()
	tw.tween_property(r, "scale", Vector2(1.0, 0.4), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(r, "modulate:a", 0.0, duration).set_delay(duration * 0.3)
	tw.tween_callback(r.queue_free)
	return tw


## A shield bubble that pops in over a unit, shimmers, then fades.
static func dome(parent: Node, center: Vector2, size: float, tint: Color = Color(0.7, 0.9, 1.0), hold: float = 0.45) -> Tween:
	var r := _sprite(parent, load(static_path("shield")), center, size, Color(tint, 0.0))
	r.scale = Vector2(0.6, 0.6)
	var tw := r.create_tween()
	tw.tween_property(r, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(r, "modulate:a", 0.6, 0.18)
	tw.tween_property(r, "modulate", Color(tint.r * 1.4, tint.g * 1.4, tint.b * 1.4, 0.75), hold * 0.5)
	tw.tween_property(r, "modulate", Color(tint, 0.0), hold * 0.5 + 0.2)
	tw.tween_callback(r.queue_free)
	return tw


## A rune circle that spins in, holds, and fades (debuffs, curses, chill).
static func sigil(parent: Node, center: Vector2, size: float, tint: Color, duration: float = 0.6) -> Tween:
	var r := _sprite(parent, load(static_path("sigil")), center, size, Color(tint, 0.0))
	r.scale = Vector2(0.5, 0.5)
	var tw := r.create_tween()
	tw.tween_property(r, "modulate:a", 0.9, 0.15)
	tw.parallel().tween_property(r, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(r, "rotation", PI, duration)
	tw.tween_property(r, "modulate:a", 0.0, 0.2)
	tw.tween_callback(r.queue_free)
	return tw


## Particles: rising sparkles (heals, buffs) or, with `converge`, motes
## pulled inward (charging up an ability or a wind-up).
static func sparkles(parent: Node, center: Vector2, color: Color, amount: int = 18, spread_w: float = 40.0, converge: bool = false, duration: float = 0.6) -> void:
	var p := CPUParticles2D.new()
	p.position = center
	p.one_shot = true
	p.amount = amount
	p.lifetime = duration
	p.explosiveness = 0.6 if not converge else 0.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE if not converge else CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_rect_extents = Vector2(spread_w * 0.5, 6.0)
	p.emission_sphere_radius = spread_w
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(0, -40) if not converge else Vector2.ZERO
	p.initial_velocity_min = 20.0 if not converge else 0.0
	p.initial_velocity_max = 50.0 if not converge else 0.0
	p.radial_accel_min = -140.0 if converge else 0.0
	p.radial_accel_max = -90.0 if converge else 0.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = color
	parent.add_child(p)
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(duration + 0.2)
	tw.tween_callback(p.queue_free)


## A thin line from attacker to target that flashes and fades.
static func line(parent: Node, from: Vector2, to: Vector2, color: Color, duration: float = 0.4) -> Tween:
	var l := Line2D.new()
	l.points = PackedVector2Array([from, to])
	l.width = 2.0
	l.default_color = Color(color, 0.0)
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "default_color", Color(color, 0.8), duration * 0.3)
	tw.tween_property(l, "default_color", Color(color, 0.0), duration * 0.7)
	tw.tween_callback(l.queue_free)
	return tw


## The tint an element's effects use.
static func element_color(type: String) -> Color:
	return Palette.ELEMENT_PARTICLE_COLOR.get(type, Color(1, 1, 1))
