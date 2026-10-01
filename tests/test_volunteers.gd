extends "res://tests/base_test.gd"
## A broke guild down to its last hero is refilled by volunteers at payday,
## so a bad week means rebuilding, not a dead save.


func run() -> void:
	seed(3)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	GameState.hire_starters()
	GameState.coins = 100000
	GameState.run_payday()
	check(GameState.heroes.size() == 3, "a guild with Gold gets no volunteers")
	GameState._release(GameState.heroes[2])
	GameState._release(GameState.heroes[1])
	GameState.coins = 0
	GameState.pending_toasts.clear()
	GameState.run_payday()
	check(GameState.heroes.size() == GameData.VOLUNTEER_FLOOR, "a broke guild of one is filled back to %d" % GameData.VOLUNTEER_FLOOR)
	check(GameState.pending_toasts.any(func(t): return str(t["title"]) == "Volunteers"), "and told why, and how to rebuild")
	check(GameState.heroes.all(func(h): return str(h.id) != ""), "volunteers are real roster heroes")
	GameState._release(GameState.heroes[2])
	GameState.coins = int(GameData.find_rank("F")["cost"]) + 1000
	GameState.run_payday()
	check(GameState.heroes.size() == 2, "a guild that can afford a recruit hires its own")

	# Commissioning a recruit: the role you ask for, for 3 rerolls' Gold.
	GameState.refresh_recruit_pool()
	var n := GameState.recruit_pool.size()
	GameState.coins = 1000
	var c0 := GameState.commission_cost()
	check(GameState.commission_recruit("cleric") == "" and GameData.hero_role(GameState.recruit_pool[0]) == "cleric", "a commissioned cleric heads the offers")
	check(GameState.recruit_pool.size() == n and GameState.coins == 1000 - c0, "the board keeps its size; it cost %d Gold" % c0)
	check(GameState.commission_cost() == c0 * 2, "and the next one costs double")

	# The recruit board: offers wait a few days, new faces arrive daily,
	# rerolls double until payday, a hire leaves a gap until tomorrow.
	GameState.refresh_recruit_pool()
	check(GameState.recruit_pool.size() == GameState.recruit_offer_count() and GameState.recruit_rerolls == 0, "a full board, rerolls at their first price")
	check(GameState.recruit_pool.all(func(h): var d := GameState.offer_days_left(h); return d >= int(GameData.RECRUIT_STAY[0]) and d <= int(GameData.RECRUIT_STAY[1])), "every offer waits 3-6 days")
	var r0 := GameState.recruit_reroll_cost()
	GameState.coins = 1000
	GameState.reroll_recruit_offer(GameState.recruit_pool[0].id)
	GameState.reroll_recruit_offer(GameState.recruit_pool[0].id)
	check(GameState.coins == 1000 - r0 - 2 * r0 and GameState.recruit_reroll_cost() == 4 * r0, "rerolls double: %d, %d, then %d" % [r0, 2 * r0, 4 * r0])
	for i in 10:
		GameState.reroll_recruit_offer(GameState.recruit_pool[0].id)
	check(GameState.recruit_reroll_cost() == r0 * (1 << GameData.RECRUIT_REROLL_DOUBLINGS), "up to a cap")
	var gone: Hero = GameState.recruit_pool[1]
	GameState.recruit_until[gone.id] = GameState.day - 1
	var size_before := GameState.recruit_pool.size()
	GameState.recruit_day()
	check(not GameState.recruit_pool.has(gone), "an offer whose time is up moves on")
	check(GameState.recruit_pool.size() == size_before, "and a new face takes the place")
	while GameState.heroes.size() >= GameState.hero_slot_cap():
		GameState._release(GameState.heroes[GameState.heroes.size() - 1])
	var hire: Hero = GameState.recruit_pool[0]
	GameState.coins = 100000
	var before_hire := GameState.recruit_pool.size()
	check(GameState.recruit_hero(hire.id) == "" and GameState.recruit_pool.size() == before_hire - 1, "a hire leaves a gap (no instant replacement)")
	GameState.recruit_top_up()
	check(GameState.recruit_pool.size() == GameState.recruit_offer_count() and GameState.recruit_rerolls == 0, "payday fills the board and resets rerolls")

	# The rival signs your best offer (once its moves have begun).
	GameState.features_seen.append("rival")
	GameState.rifts_sealed = 3
	var signed := false
	for i in 60:
		GameState.guild_news.clear()
		GameState.recruit_day()
		if GameState.guild_news.any(func(l): return str(l).contains("signed")):
			signed = true
			break
	check(signed, "the rival signs an offer now and then")

	# Loadouts: a saved party with rows; loading leaves out who can't go.
	var a: Hero = GameState.heroes[0]
	a.formation = "back"
	GameState.save_party_preset(0, [a.id])
	a.formation = "front"
	var res := GameState.load_party_preset(0, 4)
	check(res["ids"] == [a.id] and a.formation == "back", "a loadout loads its party in their saved rows")
	a.down_runs = 2
	res = GameState.load_party_preset(0, 4)
	check((res["ids"] as Array).is_empty() and (res["missing"] as Array).size() == 1, "a recovering hero is left out and named")
	a.down_runs = 0
	GameState._release(a)
	check((GameState.party_presets[0] as Array).is_empty(), "a hero who leaves drops out of every loadout")
	GameState.coins = 0
	check(GameState.commission_recruit("mage") != "", "not without the Gold")
