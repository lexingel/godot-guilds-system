extends "res://tests/base_test.gd"
## The campaign: objectives, finales, rewards, unlocks, story cards, migration.


func _heroes(n: int) -> Array[String]:
	var ids: Array[String] = []
	for i in n:
		var h := Combat.gen_hero("C", 8)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		ids.append(h.id)
	return ids


func run() -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	check(GameState.campaign_act == 1 and GameState.pending_stories.size() == 2 and str(GameState.pending_stories[0]["title"]) == "The Night of Breaking", "a new guild opens on the prologue, then Act I's intro")
	check(not GameState.greater_rift_unlocked() and not GameState.endless_unlocked(), "Greater and Endless start locked")
	check(not GameState.finale_ready(), "finale closed until objectives are met")
	var ids := _heroes(3)
	GameState.rifts_sealed = 3
	check(not GameState.finale_ready(), "Act I still needs a Rank E seal")
	GameState.best_rift_rank_sealed = GameData.rift_rank_index("E")
	check(GameState.finale_ready(), "Act I objectives met -> finale open")
	GameState.runs_started = 5
	GameState.start_finale(ids, null)
	check(int(GameState.run.get("finale", 0)) == 1 and not GameState.run.get("training", false), "finale run started")
	var d := GameState._diff()
	check(str(d.get("boss_name", "")) == "Vaelith, the Vale-Render", "finale boss is the act's foe")
	check(int(d["monster_hp"]) > int(GameData.DIFFICULTIES[0]["monster_hp"]), "finale foes are tougher")
	var boss := Combat.gen_monster(d, 6, "boss")
	check(str(boss["name"]).begins_with("Vaelith"), "boss generated with the foe's name")
	# Save/load mid-finale keeps the finale.
	GameState.save()
	GameState.load_save()
	check(int(GameState.run.get("finale", 0)) == 1, "finale flag survives a reload")
	var relics0 := GameState.relics.size()
	var cr0 := GameState.crystals
	GameState.pending_stories.clear()
	GameState.seal_rift()
	check(GameState.campaign_act == 2 and GameState.greater_rift_unlocked() and not GameState.endless_unlocked(), "Act I done: Greater open, Endless still closed")
	check(GameState.relics.size() == relics0 + 1 and GameState.relics[-1].rarity == "legendary" and GameState.crystals > cr0, "reward: crystals and a Legendary relic")
	check(GameState.pending_stories.size() == 3 and str(GameState.pending_stories[2]["title"]).contains("Act II"), "outro card, the freed champion, then the Act II intro")
	check(GameState.champion_unlocked(GameState.story_champion(1)), "Act I frees its champion")
	check(str(GameState.pending_stories[1]["text"]).contains("remembers"), "and the champion says what they remember of the Night")
	check(GameState.accord_pages == 1, "a finale always turns up a page of the Grandmaster's ledger")
	GameState.finish_run()
	# A normal seal doesn't complete an act.
	GameState.start_run("lesser", ids, null)
	GameState.seal_rift()
	check(GameState.campaign_act == 2, "a normal rift seal doesn't advance the campaign")
	GameState.finish_run()
	# Act II objectives.
	GameState.quest_tally["greater_seals"] = 2
	GameState.quest_tally["quests_done"] = 1
	GameState.best_rift_rank_sealed = GameData.rift_rank_index("D")
	check(not GameState.finale_ready(), "Act II still needs a Rank C+ map seal")
	GameState.best_rift_rank_sealed = GameData.rift_rank_index("C")
	check(GameState.finale_ready(), "Act II objectives met")
	GameState.start_finale(ids, null)
	check(str(GameState._diff().get("boss_name", "")).begins_with("Nyxara") and str(GameState._diff()["id"]) == "greater", "Act II finale is a Greater rift against Nyxara")
	GameState.seal_rift()
	GameState.finish_run()
	check(GameState.endless_unlocked(), "Act II done: Endless open")
	# Act III and the ending.
	GameState.best_rift_rank_sealed = GameData.rift_rank_index("B")
	GameState.quest_tally["boss:Korrath"] = 1
	GameState.quest_tally["boss:Drevok"] = 1
	GameState.quest_tally["quests_done"] = 3
	check(GameState.finale_ready(), "Act III objectives met")
	GameState.pending_stories.clear()
	GameState.start_finale(ids, null)
	check(bool(GameState._diff().get("boss_double_mechanic", false)), "the last finale boss has two mechanics")
	GameState.seal_rift()
	GameState.finish_run()
	check(GameState.campaign_done() and GameState.current_act().is_empty(), "campaign complete")
	check(GameState.pending_stories.any(func(c): return str(c["title"]) == "The End"), "the ending card is queued")
	# Quest claims feed the Act III tally.
	var q := GameState.roll_quest()
	q["type"] = "craft"; q["target"] = 1
	GameState.guild_board.append(q)
	GameState.accept_quest(str(q["id"]))
	GameState.crafts_performed += 1
	var qd := int(GameState.quest_tally.get("quests_done", 0))
	GameState.claim_quest(str(q["id"]))
	check(int(GameState.quest_tally.get("quests_done", 0)) == qd + 1, "claiming a quest counts toward Act III")
	# Old saves keep what they had.
	var data: Dictionary = JSON.parse_string(GameState.export_save_text())
	data.erase("campaign_act")
	data["rifts_sealed"] = 4
	data["best_endless_cycle"] = 0
	GameState.import_save_text(JSON.stringify(data), 9)
	GameState.load_save()
	check(GameState.campaign_act == 2 and GameState.greater_rift_unlocked(), "an old guild with Greater unlocked starts at Act II")
	data["best_endless_cycle"] = 2
	GameState.import_save_text(JSON.stringify(data), 9)
	GameState.load_save()
	check(GameState.campaign_act == 3 and GameState.endless_unlocked(), "an old guild that played Endless starts at Act III")
	# The Compendium remembers every Legendary the guild has held, even one sold since.
	var leg := Combat.gen_unique_relic()
	GameState.relics.append(leg)
	GameState.save()
	GameState.relics.assign(GameState.relics.filter(func(r): return r.unique_id != leg.unique_id))   # every copy (a finale may have given the same one)
	GameState.save()
	GameState.load_save()
	check(GameState.relics_found.has(leg.unique_id) and not GameState.relics.any(func(r): return r.unique_id == leg.unique_id), "a sold Legendary stays found")
	data.erase("relics_found")
	GameState.import_save_text(JSON.stringify(data), 9)
	GameState.load_save()
	check(GameState.relics_found is Array, "an old save loads with an empty record")

	# The Broken Accord's data: every champion remembers something, the
	# ledger pages come in act order, and a page waits for its act.
	check(GameData.CHAMPIONS.keys().all(func(id): return GameData.CHAMPION_MEMORY.has(id)), "every champion has a memory of the Night")
	var acts_in_order := true
	for i in range(1, GameData.LEDGER_PAGES.size()):
		acts_in_order = acts_in_order and int(GameData.LEDGER_PAGES[i]["act"]) >= int(GameData.LEDGER_PAGES[i - 1]["act"])
	check(acts_in_order, "ledger pages run in act order")
	GameState.campaign_act = 1
	GameState.accord_pages = 2
	GameState.maybe_find_ledger_page(true)
	check(GameState.accord_pages == 2, "an Act II page waits while the guild is in Act I")
	GameState.campaign_act = 2
	GameState.maybe_find_ledger_page(true)
	check(GameState.accord_pages == 3, "and turns up once it's Act II")
	GameState.save()
	GameState.load_save()
	check(GameState.accord_pages == 3, "found pages survive a reload")
