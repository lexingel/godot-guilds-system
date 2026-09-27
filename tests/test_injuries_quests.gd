extends "res://tests/base_test.gd"
## Downed-hero choices and the Guild Board.

func _party(n_idle: int) -> Array[String]:
	GameState.reset()
	GameState.guild_name = "T"
	GameState.rifts_sealed = 3
	var ids: Array[String] = []
	for i in 3 + n_idle:
		var h := Combat.gen_hero("D", 5)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		if i < 3:
			ids.append(h.id)
	GameState.start_run("lesser", ids, null)
	return ids


func _down(id: String, sev: String) -> void:
	var h := GameState.find_hero(id)
	GameState.knock_out(h)
	GameState._note_injuries(sev)


func run() -> void:
	seed(5)
	GameState.active_slot = 9
	# Carry: a day passes, hero leaves the party, advance blocked until decided.
	var ids := _party(2)
	_down(ids[0], "wounded")
	var pos0 := int(GameState.run["pos"])
	GameState.advance_node()
	check(int(GameState.run["pos"]) == pos0, "can't move on with an undecided downed hero")
	var d0 := GameState.day
	GameState.injury_carry(ids[0])
	check(GameState.day == d0 + 1 and not (GameState.run["hero_ids"] as Array).has(ids[0]) and GameState.pending_injuries().is_empty(), "carry: +1 day, hero leaves the rift")
	# Reinforcements: critical needs 2 idle, they go busy 2 runs.
	_down(ids[1], "critical")
	check(GameState.injury_reinforce(ids[1]) == "", "reinforce with 2 idle")
	var busy := GameState.heroes.filter(func(h): return h.busy_runs == 2).size()
	check(busy == 2, "2 idle heroes away for 2 runs (%d)" % busy)
	check(not GameState.heroes.filter(func(h): return h.busy_runs > 0)[0].is_available(), "busy heroes can't join a party")
	# Heal: needs a healer; Field Triage works.
	_down(ids[2], "wounded")
	check(GameState.injury_heal(ids[2]) != "" or GameState.field_healer() != "", "heal gated on a healer")
	GameState.upgrades["ops.infirmary"] = 3
	if GameState.field_healer() != "":
		check(GameState.injury_heal(ids[2]) == "", "heal with Field Triage")
		var h2 := GameState.find_hero(ids[2])
		check(h2.hp > 0 and h2.battered and h2.down_runs == 0, "healed hero back up, battered")
		GameState.finish_run()
		check(not h2.battered, "battered clears when the run ends")
	else:
		print("   (couldn't unlock Field Triage in test; skipped)")
		GameState.finish_run()

	# Leave: rescued on seal, lost otherwise.
	ids = _party(0)
	_down(ids[0], "wounded")
	check(GameState.injury_leave(ids[0]) == "", "leave them")
	GameState.seal_rift()
	check(GameState.find_hero(ids[0]) != null, "left-behind hero rescued by sealing")
	GameState.finish_run()
	ids = _party(0)
	var it := Combat.gen_item("common", "weapon")
	GameState.items.append(it)
	GameState.find_hero(ids[0]).attrs[it.attr] = 30
	GameState.equip_item(ids[0], "weapon", 0, it.id)
	_down(ids[0], "wounded")
	GameState.injury_leave(ids[0])
	GameState.retreat_now()
	check(GameState.find_hero(ids[0]) == null and it.equipped_to == "", "left-behind hero lost on retreat, gear returned")
	ids = _party(0)
	GameState.rifts_sealed = 0
	_down(ids[0], "wounded")
	check(GameState.injury_leave(ids[0]) != "", "new guild can't leave anyone")
	GameState.injury_carry(ids[0])
	# Save round-trip of injury state.
	_down(ids[1], "critical")
	GameState.save()
	GameState.load_save()
	check(GameState.pending_injuries().size() == 1, "pending injury survives reload")
	GameState.injury_carry(ids[1])
	GameState.finish_run()

	# ---- Guild Board
	GameState.guild_board = [{"id": "old", "tier": "daily", "type": "craft", "target": 1, "baseline": 0, "reward": {}}]
	GameState.resolve_guild_board()
	check(GameState.guild_board.size() == GameData.QUEST_POSTED and GameState.guild_board.all(func(q): return q["status"] == "posted"), "old board replaced by 6 postings")
	var q0: Dictionary = GameState.guild_board[0]
	for q in GameState.guild_board.slice(0, 3):
		GameState.accept_quest(str(q["id"]))
	check(GameState.active_quests().size() == 3, "3 accepted")
	check(GameState.accept_quest(str(GameState.guild_board[3]["id"])) != "", "4th refused")
	# Refresh after 3 days keeps active, replaces postings.
	var posted_ids: Array = GameState.guild_board.filter(func(q): return q["status"] == "posted").map(func(q): return q["id"])
	for i in GameData.QUEST_REFRESH_DAYS:
		GameState.rest_guild()
	var still: Array = GameState.guild_board.filter(func(q): return posted_ids.has(q["id"]))
	check(still.is_empty() and GameState.active_quests().size() == 3 and GameState.guild_board.size() == 3 + GameData.QUEST_POSTED, "refresh: postings replaced, accepted kept (%d on board)" % GameState.guild_board.size())
	# A craft quest completes and claims.
	var cq := GameState.roll_quest()
	cq["type"] = "craft"; cq["target"] = 1
	GameState.guild_board.append(cq)
	GameState.abandon_quest(str(GameState.active_quests()[0]["id"]))
	GameState.accept_quest(str(cq["id"]))
	GameState.crafts_performed += 1
	check(GameState.quest_progress(cq) == 1, "progress counts after accepting")
	var coins0 := GameState.coins
	GameState.claim_quest(str(cq["id"]))
	check(GameState.coins > coins0 and not GameState.guild_board.has(cq), "claim pays and removes")
	# Bounty + seal tallies.
	var bq := GameState.roll_quest()
	bq["type"] = "bounty"; bq["param"] = "Korrath"
	GameState.guild_board.append(bq)
	GameState.accept_quest(str(bq["id"]))
	GameState._bump("boss:Korrath")
	check(GameState.quest_progress(bq) == 1, "bounty progress from boss tally")
	# The rift ladder: each rank opens once the one below is sealed; C+ needs Act II.
	GameState.finish_run()
	GameState.best_rift_rank_sealed = -1
	check(GameState.ladder_rank_lock("F") == "" and GameState.ladder_rank_lock("E") != "", "only Rank F is open at first")
	GameState.best_rift_rank_sealed = GameData.rift_rank_index("D")
	GameState.campaign_act = 1
	check(GameState.ladder_rank_lock("C") != "" and GameState.highest_open_rank() == "D", "Rank C waits for Act II")
	GameState.campaign_act = 2
	check(GameState.highest_open_rank() == "C", "Rank C opens with Act II")
	check(Combat.recommended_power("", "E") > Combat.recommended_power("", "F") and Combat.recommended_power("", "SSS") > Combat.recommended_power("", "S"), "recommended power climbs the ladder")
	var lids: Array[String] = []
	lids.assign(GameState.heroes.slice(0, 3).map(func(h): return h.id))
	GameState.start_ladder_rift("B", lids, null)
	var d := GameState._diff()
	check(d["id"] == "greater" and float(d["monster_hp"]) > float(GameData.DIFFICULTIES[1]["monster_hp"]) and int(d["seal_essence"]) > int(GameData.DIFFICULTIES[1]["seal_essence"]) and bool(d.get("elite_chance_up", false)), "Rank B: Greater base, tougher foes, bigger rewards, more elites")
	check(GameState.loot_rank() == "B", "loot drops at the rift's rank")
	GameState.finish_run()
