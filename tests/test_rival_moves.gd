extends "res://tests/base_test.gd"
## The rival's weekly moves: courting a hero, a dare, going for a contract.


func _hero(rank: String, level: int) -> Hero:
	var h := Combat.gen_hero(rank, level)
	h.id = "h%d" % GameState.next_id
	GameState.next_id += 1
	GameState.heroes.append(h)
	return h


func run() -> void:
	seed(5)
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	GameState.coins = 5000
	var hs: Array[Hero] = []
	for r in ["F", "F", "E", "C"]:
		hs.append(_hero(r, 3))
	GameState.resolve_guild_board()
	GameState.day = GameData.RIVAL_MOVE_DAY
	for i in 20:
		GameState.maybe_rival_move()
	check(GameState.rival_event.is_empty(), "no moves before the third seal")
	GameState.rifts_sealed = 3

	# A move comes only on its day of the week.
	GameState.day = GameData.RIVAL_MOVE_DAY + 1
	for i in 20:
		GameState.maybe_rival_move()
	check(GameState.rival_event.is_empty(), "no move off the rival's day")
	GameState.day = GameData.RIVAL_MOVE_DAY
	for i in 20:
		GameState.maybe_rival_move()
	check(not GameState.rival_event.is_empty() and GameState.rival_event_title() != "" and GameState.rival_event_text() != "", "on its day, the rival makes a move")

	# Poach: courts the strongest hero; a counter-offer keeps them.
	GameState.rival_event = {}
	check(GameState._poach_target() == hs[3], "it courts your strongest hero")
	GameState.rival_event = {"type": "poach", "hero": hs[3].id, "day": GameState.day}
	var cost := GameState.poach_counter_cost(hs[3])
	var c0 := GameState.coins
	var m0 := hs[3].morale
	check(GameState.rival_event_options().size() == 2 and GameState.answer_rival(true) == "", "a counter-offer can be made")
	check(GameState.coins == c0 - cost and hs[3].morale == m0 + GameData.POACH_COUNTER_MORALE and GameState.find_hero(hs[3].id) != null and GameState.rival_event.is_empty(), "the counter-offer costs Gold, lifts morale, and they stay")
	# Left to choose: high morale stays, low morale leaves.
	hs[3].morale = GameData.POACH_STAY_MORALE
	GameState.rival_event = {"type": "poach", "hero": hs[3].id, "day": GameState.day}
	GameState.answer_rival(false)
	check(GameState.find_hero(hs[3].id) != null, "a content hero turns the rival down")
	hs[3].morale = GameData.POACH_STAY_MORALE - 1
	GameState.rival_event = {"type": "poach", "hero": hs[3].id, "day": GameState.day}
	GameState.answer_rival(false)
	check(GameState.find_hero(hs[3].id) == null, "an unhappy hero leaves for the rival")
	check(GameState._poach_target() == null, "a guild under %d heroes isn't courted" % GameData.POACH_MIN_ROSTER)

	# Dare: accept, then win by sealing that rank.
	GameState.rival_event = {"type": "challenge", "rank": "E", "day": GameState.day}
	var rep0 := GameState.reputation
	GameState.rival_renown = 20
	GameState.answer_rival(true)
	check(GameState.rival_event.get("accepted", false) and GameState.rival_event_options().is_empty(), "an accepted dare waits for a seal")
	GameState._check_challenge(GameData.rift_rank_index("F"))
	check(not GameState.rival_event.is_empty(), "a lower-rank seal doesn't count")
	GameState._check_challenge(GameData.rift_rank_index("D"))
	check(GameState.rival_event.is_empty() and GameState.reputation == rep0 + GameData.CHALLENGE_WIN_RENOWN and GameState.rival_renown == 20 - GameData.CHALLENGE_WIN_TAKE, "sealing that rank or higher wins the dare")
	# Accepted and missed: payday hands the rival Renown.
	GameState.rival_event = {"type": "challenge", "rank": "E", "day": GameState.day, "accepted": true}
	var rr0 := GameState.rival_renown
	GameState._close_rival_event()
	check(GameState.rival_event.is_empty() and GameState.rival_renown == rr0 + GameData.CHALLENGE_FAIL_RENOWN, "a missed dare costs you at payday")
	# Unanswered: counts as declining.
	GameState.rival_event = {"type": "challenge", "rank": "E", "day": GameState.day}
	rr0 = GameState.rival_renown
	GameState._close_rival_event()
	check(GameState.rival_event.is_empty() and GameState.rival_renown == rr0 + GameData.CHALLENGE_DECLINE_RENOWN, "an unanswered dare counts as declined")

	# Contract grab: take it on, or lose it.
	var posted: Array = GameState.guild_board.filter(func(q): return str(q["status"]) == "posted")
	check(posted.size() >= 2, "the board has postings")
	GameState.rival_event = {"type": "snatch", "quest": str(posted[0]["id"]), "day": GameState.day}
	check(GameState.answer_rival(true) == "" and str(posted[0]["status"]) == "active", "taking it on makes the contract yours")
	GameState.rival_event = {"type": "snatch", "quest": str(posted[1]["id"]), "day": GameState.day}
	var n0 := GameState.guild_board.size()
	GameState._close_rival_event()
	check(GameState.guild_board.size() == n0 - 1 and GameState.rival_event.is_empty(), "left unanswered, the rival takes it")

	# The board refreshes before you answer: the rival takes the posting.
	posted = GameState.guild_board.filter(func(q): return str(q["status"]) == "posted")
	GameState.rival_event = {"type": "snatch", "quest": str(posted[0]["id"]), "day": GameState.day}
	GameState.board_refresh_day = GameState.day
	GameState.resolve_guild_board()
	check(GameState.rival_event.is_empty() and not GameState.guild_board.any(func(q): return str(q["id"]) == str(posted[0]["id"])), "a refreshed board ends the grab (the rival took it)")
	# Taking the contract from the board yourself ends it too.
	posted = GameState.guild_board.filter(func(q): return str(q["status"]) == "posted")
	for q in GameState.active_quests():
		GameState.abandon_quest(str(q["id"]))
	GameState.rival_event = {"type": "snatch", "quest": str(posted[0]["id"]), "day": GameState.day}
	GameState.accept_quest(str(posted[0]["id"]))
	check(GameState.rival_event.is_empty(), "accepting the contract yourself ends the grab")

	# Saved with the guild.
	GameState.rival_event = {"type": "challenge", "rank": "E", "day": GameState.day, "accepted": true}
	GameState.save()
	GameState.load_save()
	check(GameState.rival_event.get("accepted", false) and str(GameState.rival_event["rank"]) == "E", "the rival's move survives a reload")
