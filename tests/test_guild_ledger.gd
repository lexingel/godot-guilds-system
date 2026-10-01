extends "res://tests/base_test.gd"
## Running the guild: wages and payday, morale, contract deadlines, the rival.


func _hero(rank: String, level: int) -> Hero:
	var h := Combat.gen_hero(rank, level)
	h.id = "h%d" % GameState.next_id
	GameState.next_id += 1
	GameState.heroes.append(h)
	return h


## A payday that leaves a guild of one broke brings volunteers; most checks
## here are about the one hero, so send them home.
func _only(keep: Hero) -> void:
	for vh in GameState.heroes.duplicate():
		if vh != keep:
			GameState._release(vh)


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
	check(GameState.heroes.size() == GameData.VOLUNTEER_FLOOR, "broke and down to one: volunteers join")
	_only(a)

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
	_only(a)
	GameState.reputation = 10
	GameState.coins = GameState.weekly_wages()
	GameState.day = 31 * GameData.PAYDAY_DAYS - 1
	GameState.pass_time()
	check(not bool(GameState.payday_report["upkeep_paid"]) and GameState.reputation == 10 - GameData.UPKEEP_UNPAID_RENOWN, "unpaid upkeep costs Renown")
	GameState.upgrades = {}
	_only(a)

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
	GameState.reputation = GameState.rival_renown + 20
	var offers0 := GameState.recruit_offer_count() - GameState.rival_ahead
	GameState.coins = 999
	GameState.day = 10 * GameData.PAYDAY_DAYS - 1
	GameState.pass_time()
	check(GameState.rival_ahead == 1 and GameState.recruit_offer_count() == offers0 + 1, "leading the rival at payday: one more recruit offer")
	GameState.save()
	GameState.load_save()
	check(GameState.rival_ahead == 1 and GameState.find_hero(a.id).morale == a.morale, "rival and morale survive a reload")

	# Guild Standings: five guilds, best Renown first, you among them.
	GameState.day = 40
	var rows := GameState.guild_standings()
	check(rows.size() == 5 and rows.filter(func(r): return r["you"]).size() == 1, "five guilds in the standings, yours among them")
	check(rows[0]["renown"] >= rows[-1]["renown"], "sorted by Renown")
	GameState.reputation = 9999
	check(GameState.guild_standings()[0]["you"] and GameState.milestone_progress({"type": "standings_top"}) == 1, "topping the Renown column counts for the achievement")

	# This week at a glance.
	GameState.coins = 10
	var fc := GameState.payday_forecast()
	check(int(fc["bill"]) == GameState.weekly_wages() + GameState.upkeep() and int(fc["short"]) == maxi(0, int(fc["bill"]) - 10), "the forecast adds wages and upkeep against the treasury")
	GameState.run_history.push_front({"coins": 100})
	fc = GameState.payday_forecast()
	check(int(fc["short"]) == 0 or int(fc["runs"]) >= 1, "a shortfall is priced in rifts at recent pay")

	# Hero requests: one mid-week, answered with a trade-off.
	GameState.hero_request = {}
	GameState.day = GameData.REQUEST_DAY
	GameState.maybe_hero_request()
	check(not GameState.hero_request.is_empty() and GameState.request_title() != "" and GameState.request_options().size() == 2, "a hero request comes in mid-week")
	var hqq := GameState.heroes[0]
	GameState.hero_request = {"type": "raise", "ids": [hqq.id], "day": GameState.day}
	var wq0 := GameState.wage_of(hqq)
	var mq0 := hqq.morale
	check(GameState.answer_request(true) == "" and GameState.wage_of(hqq) > wq0 and hqq.morale > mq0 and GameState.hero_request.is_empty(), "a granted raise raises the wage and morale")
	GameState.hero_request = {"type": "week_off", "ids": [hqq.id], "day": GameState.day}
	GameState.answer_request(true)
	check(hqq.busy_runs >= GameData.REQUEST_LEAVE_DAYS, "time off keeps the hero home a few days")
	GameState.hero_request = {"type": "gear", "ids": [hqq.id], "day": GameState.day}
	GameState.coins = 0
	check(GameState.answer_request(true) != "" and not GameState.hero_request.is_empty(), "can't pay for kit without the Gold")
	var mq1 := hqq.morale
	GameState.answer_request(false)
	check(hqq.morale < mq1, "refusing costs morale")
	if GameState.heroes.size() >= 2:
		var hbq := GameState.heroes[1]
		hqq.morale = 50
		hbq.morale = 50
		GameState.hero_request = {"type": "feud", "ids": [hqq.id, hbq.id], "day": GameState.day}
		GameState.answer_request(false)
		check(hbq.morale > 50 and hqq.morale < 50, "siding in a feud pleases one and stings the other")
	GameState.hero_request = {"type": "gear", "ids": [hqq.id], "day": GameState.day}
	GameState.day = GameData.PAYDAY_DAYS * 10 - 1
	GameState.run_payday()
	check(GameState.hero_request.is_empty(), "an unanswered request lapses at payday")

	# The rival: a leader with a face, and a monthly contest.
	var rlead := GameState.rival_leader()
	check(str(rlead["leader"]) != "" and ResourceLoader.exists(str(rlead["portrait"])) and ResourceLoader.exists(str(rlead["crest"])), "the rival has a leader, a portrait and a crest")
	GameState.contest_start = {"ours": GameState.reputation, "theirs": GameState.rival_renown}
	GameState.add_reputation(5)
	GameState.rival_renown += 2
	var cq0 := GameState.coins
	GameState._end_contest()
	check(GameState.coins == cq0 + int(GameData.CONTEST_PRIZE["coins"]) and GameState.contest_status()["ours"] == 0 and GameState.contest_status()["theirs"] == 0, "gaining more Renown in the month wins the prize, and a new month starts")
