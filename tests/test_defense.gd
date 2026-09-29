extends "res://tests/base_test.gd"
## Riftbreak defense (DefenseRun): maps that lead to the goal, towers and
## supplies, foes that leak, heroes that hold the road, the champion, and a
## whole defense played out by the autoplayer.


func _heroes(ranks: Array, level: int) -> Array:
	var out: Array = []
	for r in ranks:
		var h := Combat.gen_hero(r, level)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		out.append(h)
	return out


func _play(r: DefenseRun) -> void:
	for k in 20000:
		if r.over:
			break
		if k % 25 == 0:
			r.autoplay()
			if r.build_t > 0.0 and r.wave > 0:
				r.call_early()
		r.step(0.1)
		r.events.clear()


func run() -> void:
	seed(12)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"

	# Every map: routes from off the field to the goal; pads and posts off the road.
	for id in GameData.DEFENSE_MAPS:
		var r := DefenseRun.new(id, 0, [], null, 1)
		var bad: Array = []
		for rt in r.routes:
			if (rt["pts"][-1] as Vector2).distance_to(r.map["goal"]) > 5.0:
				bad.append("a route stops short")
		for p in r.map["pads"] + r.map["posts"]:
			for ri in r.routes.size():
				var d := 0.0
				while d < float(r.routes[ri]["len"]):
					if r.route_pos(ri, d).distance_to(p) < 24.0:
						bad.append("%s sits on the road" % p)
						break
					d += 10.0
		check(not r.routes.is_empty() and bad.is_empty(), "%s: %d routes reach the goal, pads and posts beside the road %s" % [id, r.routes.size(), bad])
	check(DefenseRun.new("camp", 0, [], null, 1).routes.size() == 3, "the camp is attacked from three sides")

	# Building: supplies, research gates, tiers, selling.
	var r := DefenseRun.new("vale", 0, [], null, 2)
	var s0 := r.supplies
	check(r.build(0, "frost") != "", "unresearched towers can't be built")
	check(r.build(0, "ballista") == "" and r.supplies == s0 - r.tower_cost("ballista", 0), "a ballista costs %d supplies" % r.tower_cost("ballista", 0))
	check(r.build(0, "brazier") != "", "one tower a pad")
	r.supplies = 1000
	check(r.upgrade(0) == "" and int(r.pads[0]["tier"]) == 1, "upgrades to tier 2")
	check(r.upgrade(0) != "", "tier 3 needs research")
	var back := r.sell(0)
	check(back == int((r.tower_cost("ballista", 0) + r.tower_cost("ballista", 1)) * GameData.DEFENSE_SELL_BACK) and r.pads[0]["tower"] == "", "selling returns %d%%" % int(GameData.DEFENSE_SELL_BACK * 100))

	# Waves: a build phase, then the wave; an unopposed foe leaks integrity.
	check(r.build_t > 0.0 and r.wave == 0, "a build phase before the first wave")
	var sup := r.supplies
	r.call_early()
	check(r.wave == 1 and r.supplies > sup, "calling a wave early pays supplies")
	var f := r._add_foe("elite", 0)
	f["d"] = float(r.routes[0]["len"]) - 1.0
	var i0 := r.integrity
	r.step(0.1)
	check(r.integrity == i0 - int(GameData.DEFENSE_LEAK["elite"]) and not r.foes.has(f), "a foe that gets through costs integrity")

	# Heroes hold the road; frost slows; the champion goes where it's sent.
	var war: Hero = null
	for k in 60:
		var h := Combat.gen_hero("C", 5)
		if GameData.hero_role(h) == "warrior":
			war = h
			break
	war.id = "hw"
	GameState.heroes.append(war)
	var r2 := DefenseRun.new("vale", 0, [war], null, 3)
	var post: Vector2 = r2.heroes[0]["pos"]
	var nearest_d := 0.0
	for d in range(0, int(r2.routes[0]["len"]), 5):
		if r2.route_pos(0, d).distance_to(post) < r2.route_pos(0, nearest_d).distance_to(post):
			nearest_d = d
	var g := r2._add_foe("combat", 0)
	g["d"] = nearest_d - 30.0
	g["hp"] = 1e9
	for k in 40:
		r2.step(0.1)
	check(int(g["held_by"]) == 0 and float(g["d"]) < nearest_d + 40.0, "a warrior at a post holds a foe")
	var r3 := DefenseRun.new("vale", 0, [], null, 4, {"towers": ["frost"]})
	r3.build(0, "frost")
	var near_d := 0.0
	for d in range(0, int(r3.routes[0]["len"]), 5):
		if r3.route_pos(0, d).distance_to(r3.pads[0]["pos"]) < r3.route_pos(0, near_d).distance_to(r3.pads[0]["pos"]):
			near_d = d
	var a := r3._add_foe("combat", 0)
	a["d"] = near_d
	a["hp"] = 1e9
	a["speed"] = 50.0
	r3.step(0.1)
	var d0 := float(a["d"])
	r3.step(1.0)
	check(float(a["d"]) - d0 < 50.0 * 0.8, "a Frost Totem slows foes in reach")
	GameState.champions["brannoch"] = 1
	var r4 := DefenseRun.new("vale", 0, [], GameState.champion_hero("brannoch"), 5)
	r4.move_champion(Vector2(400, 300))
	for k in 60:
		r4.step(0.1)
	check((r4.champion()["pos"] as Vector2).distance_to(Vector2(400, 300)) < 5.0, "the champion walks where it's sent")

	# Whole defenses on autoplay: a steady guild holds a low rank; nothing
	# built and nobody posted, a high rank breaks through.
	var guards := _heroes(["C", "C", "B", "C", "B"], 8)
	var easy := DefenseRun.new("vale", 1, guards, GameState.champion_hero("brannoch"), 6)
	_play(easy)
	check(easy.over and easy.held and easy.kills > 50, "a steady guild holds a Rank E breach (%d/%d integrity, %d kills)" % [easy.integrity, easy.max_integrity, easy.kills])
	var hard := DefenseRun.new("camp", 7, [], null, 7)
	for k in 20000:
		if hard.over:
			break
		if hard.build_t > 0.0:
			hard.call_early()
		hard.step(0.1)
		hard.events.clear()
	check(hard.over and not hard.held and hard.integrity == 0, "undefended, the camp falls")
	var res := easy.result()
	check(res["held"] and float(res["integrity"]) > 0.0 and res["fallen"] is Array, "the result feeds resolve_breach")
