extends "res://tests/base_test.gd"
## Running the guild: wages and payday, morale, contract deadlines, the rival.


func _hero(rank: String, level: int) -> Hero:
	var h := Combat.gen_hero(rank, level)
	h.id = "h%d" % GameState.next_id
	GameState.next_id += 1
	GameState.heroes.append(h)
	return h


func run() -> void:
	seed(3)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	check(GameState.rival_name != "" and GameState.rival_renown == 0, "a new guild has a rival")
	var a := _hero("F", 1)
	var b := _hero("C", 5)
	check(GameState.wage_of(a) == 40 and GameState.wage_of(b) == int(round(110 * 1.12)), "wages by rank and level")
	check(GameState.weekly_wages() == GameState.wage_of(a) + GameState.wage_of(b), "weekly wages sum the roster")

	# Payday: paid in full.
	GameState.coins = 1000
	GameState.day = GameData.PAYDAY_DAYS - 1
	a.last_rift_day = GameState.day
	b.last_rift_day = GameState.day
	GameState.pass_time()
	check(GameState.coins == 1000 - GameState.weekly_wages() and int(GameState.payday_report["paid"]) == GameState.weekly_wages(), "payday pays every wage")
	check(a.unpaid_weeks == 0 and a.morale == GameData.MORALE_START, "paid heroes keep their morale")

	# Short of Gold: the unpaid lose morale; unpaid twice, they walk out.
	GameState.coins = GameState.wage_of(a)
	GameState.day = 2 * GameData.PAYDAY_DAYS - 1
	a.last_rift_day = GameState.day
	b.last_rift_day = GameState.day
	GameState.pass_time()
	check(a.unpaid_weeks == 0 and b.unpaid_weeks == 1 and b.morale == GameData.MORALE_START + GameData.MORALE_UNPAID, "the unpaid lose morale")
	GameState.coins = 0
	GameState.day = 3 * GameData.PAYDAY_DAYS - 1
	a.last_rift_day = GameState.day
	b.last_rift_day = GameState.day
	GameState.pass_time()
	check(not GameState.heroes.has(b) and GameState.heroes.has(a), "unpaid twice: they walk out (never the last hero)")
	check((GameState.payday_report["left"] as Array).size() == 1, "the payday report names who left")

	# Morale: tiers change damage; a feast lifts everyone once a week.
	a.morale = 90
	var d_hi := Combat.hero_skill_total(a, "dmg_pct")
	a.morale = 10
	var d_lo := Combat.hero_skill_total(a, "dmg_pct")
	check(is_equal_approx(d_hi - d_lo, 0.30), "Inspired +10%% vs Breaking -20%% damage")
	check(Combat.hero_skill_sources(a, "dmg_pct").any(func(p): return str(p[0]).begins_with("Morale")), "morale shows in the stat breakdown")
	GameState.coins = 500
	var m0 := a.morale
	check(GameState.hold_feast() == "" and a.morale == m0 + GameData.FEAST_MORALE, "a feast lifts morale")
	check(GameState.hold_feast() != "", "one feast a week")
	GameState.knock_out(a)
	check(a.morale == m0 + GameData.FEAST_MORALE + GameData.MORALE_KNOCKOUT, "a knockout costs morale")

	# Dismiss: never the last hero; gear returns.
	var c := _hero("E", 2)
	var it := Combat.gen_item("common", "weapon")
	it.id = "it1"
	it.equipped_to = c.id
	GameState.items.append(it)
	check(GameState.dismiss_hero(c.id) == "" and not GameState.heroes.has(c) and it.equipped_to == "", "dismissed; their gear goes back")
	check(GameState.dismiss_hero(a.id) != "", "the last hero can't be dismissed")

	# Upkeep: every Guild Management level costs Gold at payday; unpaid, Renown.
	GameState.upgrades = {"ops.drill": 2, "log.trade": 1}
	check(GameState.upkeep() == 3 * GameData.UPKEEP_PER_LEVEL and GameState.training_slots() == GameData.TRAINING_SLOTS + 1 and GameState.feast_seats() == GameData.FEAST_SEATS + 1, "upkeep, training slots and feast seats follow the upgrades")
	GameState.coins = GameState.weekly_wages() + GameState.upkeep()
	GameState.day = 30 * GameData.PAYDAY_DAYS - 1
	GameState.pass_time()
	check(GameState.coins == 0 and bool(GameState.payday_report["upkeep_paid"]), "payday pays wages and upkeep")
	GameState.reputation = 10
	GameState.coins = GameState.weekly_wages()
	GameState.day = 31 * GameData.PAYDAY_DAYS - 1
	GameState.pass_time()
	check(not bool(GameState.payday_report["upkeep_paid"]) and GameState.reputation == 10 - GameData.UPKEEP_UNPAID_RENOWN, "unpaid upkeep costs Renown")
	GameState.upgrades = {}

	# Contracts come due and fail.
	GameState.reputation = 20
	GameState.guild_board = []
	GameState.board_refresh_day = GameState.day + 99
	var q := GameState.roll_quest()
	q["type"] = "craft"
	q["target"] = 5
	q["diff"] = 2
	GameState.guild_board.append(q)
	GameState.accept_quest(str(q["id"]))
	check(int(q["due"]) == GameState.day + int(GameData.QUEST_DUE_DAYS[2]), "a taken contract gets a due day")
	GameState.day = int(q["due"]) + 1
	var mo := a.morale
	GameState.resolve_guild_board()
	check(q["status"] == "failed" and GameState.reputation == 16 and a.morale == mo + GameData.MORALE_QUEST_FAILED, "an overdue contract fails: Renown and morale drop")

	# The rival gains Renown and can take posted contracts; payday compares.
	GameState.campaign_act = 3
	var r0 := GameState.rival_renown
	for i in 20:
		GameState.rival_day()
	check(GameState.rival_renown >= r0 + 20, "the rival gains Renown every day in Act III")
	GameState.reputation = GameState.rival_renown + 5
	var offers0 := GameState.recruit_offer_count() - GameState.rival_ahead
	GameState.coins = 999
	GameState.day = 10 * GameData.PAYDAY_DAYS - 1
	GameState.pass_time()
	check(GameState.rival_ahead == 1 and GameState.recruit_offer_count() == offers0 + 1, "leading the rival at payday: one more recruit offer")
	GameState.save()
	GameState.load_save()
	check(GameState.rival_ahead == 1 and GameState.find_hero(a.id).morale == a.morale, "rival and morale survive a reload")
