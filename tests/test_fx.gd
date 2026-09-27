extends "res://tests/base_test.gd"
## Battle effects: every frame/static image Fx plays exists, and the ability
## buckets the signatures switch on are all known.


func run() -> void:
	for id in Fx.FRAMES:
		for i in int(Fx.FRAMES[id]):
			check(ResourceLoader.exists(Fx.frame_path(id, i)), "vfx frame %s" % Fx.frame_path(id, i))
	for id in Fx.STATIC:
		check(ResourceLoader.exists(Fx.static_path(id)), "vfx image %s" % Fx.static_path(id))
	var buckets := {}
	for pool in GameData.SUBCLASS_ABILITIES:
		buckets[str(GameData.ABILITY_AWAKENING_BUCKET.get(str(GameData.SUBCLASS_ABILITIES[pool].get("effect", "")), "buff"))] = true
	for b in buckets:
		check(b in ["single_dmg", "aoe_dmg", "support", "buff", "utility"], "ability bucket %s has a signature" % b)
	for t in GameData.RELIC_TYPES:
		check(Fx.element_color(t) != Color(1, 1, 1), "element %s has a colour" % t)
