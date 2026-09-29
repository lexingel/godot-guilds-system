class_name WalkSprites
extends RefCounted
## Walk-cycle sprites shared by the Endless Rift and Riftbreak defenses: a
## key's 8 walk frames (assets/survivors/walk), its signature move if it has
## one (assets/survivors/skill), else its static battle sprite. Cached per key.

const WALK_DIR := "res://assets/survivors/walk/"
const SKILL_DIR := "res://assets/survivors/skill/"   # a champion's signature move (frames 0-7)

static var _cache := {}


static func frames(key: String) -> SpriteFrames:
	if _cache.has(key):
		return _cache[key]
	var sf := SpriteFrames.new()
	sf.set_animation_speed("default", 10.0)
	for i in 8:
		var p := WALK_DIR + "%s_%d.png" % [key, i]
		if ResourceLoader.exists(p):
			sf.add_frame("default", load(p))
	for i in 8:
		var sp := SKILL_DIR + "%s_%d.png" % [key, i]
		if ResourceLoader.exists(sp):
			if not sf.has_animation("skill"):
				sf.add_animation("skill")
				sf.set_animation_speed("skill", 12.0)
				sf.set_animation_loop("skill", false)
			sf.add_frame("skill", load(sp))
	if sf.get_frame_count("default") == 0:
		# No walk cycle yet: the static battle sprite, scaled down.
		var still := str(GameData.MONSTER_SPRITE_PATH.get(key, GameData.HERO_PORTRAIT_PATH.get(key, "")))
		if key.begins_with("sub_champ_"):
			still = GameData.champion_portrait(key.trim_prefix("sub_champ_"))
		if still != "":
			sf.add_frame("default", load(still))
	_cache[key] = sf
	return sf


static func make(key: String, scale_mult: float) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames(key)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex := s.sprite_frames.get_frame_texture("default", 0)
	var h := float(tex.get_height()) if tex else 64.0
	s.offset = Vector2(0, 4.0 - h * 0.5)   # feet on the spot (-28 for a 64px walk frame)
	s.scale = Vector2.ONE * scale_mult * (64.0 / h if h > 64.0 else 1.0)
	s.play()
	return s


## A hero's sprite key: their own walk cycle, else their role's (a champion
## without one still looks like themself).
static func hero_key(h: Hero, role: String) -> String:
	var own := "sub_" + str(h.pool_id)
	return own if ResourceLoader.exists(WALK_DIR + own + "_0.png") or own.begins_with("sub_champ_") else role
