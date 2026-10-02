extends "res://tests/base_test.gd"
## Legacy: what a finished or retired guild leaves the next ones (Laurels,
## the Hall of Guilds, remembered heroes as champions, founding gifts).


func _guild(name: String) -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = name
	GameState.hire_starters()


func run() -> void:
	_guild("Pocket Crows")
	var veteran: Hero = GameState.heroes[0]
	veteran.rank = "B"
	veteran.history["rifts_cleared"] = 30
	veteran.history["kills"] = 120
	var rookie: Hero = GameState.heroes[1]
	rookie.rank = "F"
	GameState.campaign_act = 5
	GameState.accord_ending = "break"
	GameState.charter_result = "won"
	GameState.morrow_defeated = true
	GameState.echoes_returned = 2
	var L: Dictionary = GameData.LAURELS
	var expect: int = 4 * int(L["act"]) + int(L["ending"]) + int(L["charter"]) + int(L["morrow"]) + 2 * int(L["echo"])
	check(GameState.laurels_earned() == expect, "Laurels: acts, the ending, the Charter, Morrow, echoes given back (%d)" % GameState.laurels_earned())
	check(GameState.legacy_due(), "a guild that chose the Accord's ending has a legacy to write")
	check(GameState.legacy_candidates().has(veteran) and not GameState.legacy_candidates().has(rookie), "a Rank B veteran can be remembered, a Rank F rookie can't")

	var earned := GameState.write_legacy([veteran.id, rookie.id])
	check(earned == expect and int(GameState.legacy["laurels"]) == expect, "writing the legacy pays the Laurels")
	check(GameState.legacy_written and not GameState.legacy_due(), "and only once")
	check(GameState.write_legacy([veteran.id]) == 0, "a second write pays nothing")
	var hall: Array = GameState.legacy["guilds"]
	check(hall.size() == 1 and str(hall[0]["name"]) == "Pocket Crows" and str(hall[0]["ending"]) == "break", "the guild joins the Hall of Guilds")
	var ids: Array = GameData.LEGACY_CHAMPIONS.keys()
	check(ids.size() == 1, "only the qualifying hero is remembered")
	var cid := str(ids[0])
	var first := veteran.name.split(" the ")[0]
	check(GameData.champion_full_name(cid).contains(first) and GameData.champion_full_name(cid).contains("Pocket Crows"), "they come back as '%s'" % GameData.champion_full_name(cid))
	check(str(GameData.champion_def(cid)["role"]) == veteran.cls_id and not (GameData.champion_def(cid)["call"] as Dictionary).is_empty(), "with their class and a Call")
	check(ResourceLoader.exists(GameData.champion_portrait(cid)), "and their own portrait")
	check(GameState.champion_memory_line(cid).contains("Pocket Crows"), "and a memory of their old guild")
	var ch := GameState.champion_hero(cid)
	check(ch.base_hp > 0 and ch.is_champion and WalkSprites.hero_key(ch, ch.cls_id) == ch.cls_id, "they fight in the Endless Rift, walking as their class")

	# A new guild: the remembered hero waits at one of the first lost pillars.
	_guild("Iron Watch")
	var at := GameState.champion_roll.find(cid)
	check(at >= GameData.CHAMPION_STORY_ACTS and at < GameData.CHAMPION_STORY_ACTS + GameData.LEGACY_SHALLOW, "a later guild's lost champions include them (slot %d)" % at)
	check(GameState.lost_champions().any(func(e): return str(e[0]) == cid), "lost in the Endless Rift, to be freed")

	# Renewing the Accord: whoever took the forty-first post is remembered too,
	# always at the deepest pillar.
	GameState.campaign_act = 5
	var keeper: Hero = GameState.heroes[0]
	check(GameState.choose_accord_ending("renew", keeper.id) == "", "the Accord renewed")
	GameState.write_legacy([])
	var post_ids: Array = GameData.LEGACY_CHAMPIONS.keys().filter(func(k): return GameData.LEGACY_CHAMPIONS[k].get("post", false))
	check(post_ids.size() == 1, "the forty-first post's hero is remembered without being picked")
	_guild("Third Light")
	check(GameState.champion_roll[-1] == str(post_ids[0]), "and waits at the deepest pillar of the next guild")

	# Founding gifts are bought with Laurels.
	var laurels := int(GameState.legacy["laurels"])
	var coins := GameState.coins
	var crew := GameState.heroes.size()
	var got := GameState.apply_legacy_gifts(["gold", "hero"])
	check(got == ["gold", "hero"] and GameState.coins == coins + 300 and GameState.heroes.size() == crew + 1, "founding gifts: 300 Gold and a fourth hero")
	check(int(GameState.legacy["laurels"]) == laurels - 13, "paid for with Laurels")
	GameState.legacy["laurels"] = 3
	check(GameState.apply_legacy_gifts(["relic"]).is_empty(), "a gift the Laurels can't cover is skipped")

	# Retiring frees the slot and keeps the record.
	_guild("Short Rest")
	GameState.campaign_act = 2
	check(not GameState.can_retire(), "not before Act II is done")
	GameState.campaign_act = 3
	GameState.save()
	check(GameState.can_retire(), "after it, a guild can retire")
	var before := (GameState.legacy["guilds"] as Array).size()
	GameState.retire_guild([])
	var last: Dictionary = GameState.legacy["guilds"][-1]
	check(GameState.guild_name == "" and not FileAccess.file_exists(GameState._slot_path(9)), "retiring frees the save slot")
	check((GameState.legacy["guilds"] as Array).size() == before + 1 and last.get("retired", false) and str(last["name"]) == "Short Rest", "and the Hall of Guilds keeps it")

	# A backup or a transfer carries the legacy; importing folds it in.
	_guild("Courier")
	var text := GameState.export_save_text()
	var hall_size := (GameState.legacy["guilds"] as Array).size()
	GameState.legacy = {"laurels": 0, "guilds": [], "champions": {}}
	GameData.LEGACY_CHAMPIONS = GameState.legacy["champions"]
	check(GameState.import_save_text(text, 9) == "", "the export imports")
	check((GameState.legacy["guilds"] as Array).size() == hall_size and not GameData.LEGACY_CHAMPIONS.is_empty(), "and brings the Hall of Guilds and the remembered heroes with it")
	GameState.delete_slot(9)

	# ---- Founding charters ----
	GameState.legacy = {"laurels": 0, "guilds": [], "champions": {}}
	check(GameState.founding_unlocked("free") and not GameState.founding_unlocked("mercenary"), "a first guild can only found a Free Company")
	check(GameState.unlock_founding("mercenary") != "", "a charter needs the Laurels")
	GameState.legacy["laurels"] = 30
	check(GameState.unlock_founding("mercenary") == "" and GameState.founding_unlocked("mercenary") and int(GameState.legacy["laurels"]) == 5, "25 Laurels buy the Mercenary Company for good")
	check(GameState.unlock_founding("accord") != "" and not GameState.founding_unlocked("accord"), "Last of the Accord can't be bought")
	(GameState.legacy["guilds"] as Array).append({"id": "gx", "name": "Old Hands", "ending": "renew", "quiet": true})
	check(GameState.founding_unlocked("accord") and GameState.founding_unlocked("smugglers"), "a finished campaign opens the Last of the Accord, a quiet Charter War the Smugglers")

	# Free Company vs each charter, from the same start.
	var base := {}
	for id in ["free", "mercenary", "temple", "smugglers", "accord"]:
		GameState.legacy["charters"] = GameData.FOUNDINGS.keys()
		GameState.reset()
		GameState.guild_name = "Charter " + id
		GameState.apply_founding(id)
		GameState.hire_starters()
		var h: Hero = GameState.heroes[0]
		var r0 := GameState.reputation
		GameState.add_reputation(10)
		h.down_runs = 2
		GameState.pass_time()
		base[id] = {"coins": GameState.coins, "wage": GameState.wage_at(h, "full"), "renown": GameState.reputation - r0,
			"gold": GameState.charter_pay(false), "prices": GameState.merchant_price_reduction(), "down": h.down_runs, "rival": GameState.rival_name,
			"story": str(GameState.pending_stories[0].get("subtitle", ""))}
	var f: Dictionary = base["free"]
	var m: Dictionary = base["mercenary"]
	check(m["coins"] > f["coins"] and m["wage"] > f["wage"] and m["renown"] < f["renown"] and m["gold"] > f["gold"], "Mercenaries: more Gold to start and from contracts, higher wages, slower Renown")
	var t: Dictionary = base["temple"]
	check(t["coins"] < f["coins"] and t["wage"] < f["wage"] and t["down"] < f["down"], "Temple Order: less Gold, lower wages, the downed back sooner")
	var sm: Dictionary = base["smugglers"]
	check(sm["prices"] > f["prices"] + 0.2 and sm["rival"] != "The Last Lantern", "Smugglers: cheaper shops, never the Lantern as rival")
	check(str(base["accord"]["story"]) == GameData.ACCORD_PROLOGUE["subtitle"], "Last of the Accord opens on Hesper's own prologue")
	GameState.founding = "smugglers"
	GameState.charter_choice = "quiet"
	check(is_equal_approx(GameState.charter_pay(false), 1.4), "Smugglers keeping quiet in the Charter War: 40% more Gold")
	GameState.founding = "free"
	check(is_equal_approx(GameState.charter_pay(false), GameData.CHARTER_QUIET_PAY), "anyone else: 25%")
	GameState.charter_choice = ""

	# ---- Oaths ----
	GameState.legacy = {"laurels": 0, "guilds": [], "champions": {}}
	_guild("Sworn")
	var hh: Hero = GameState.heroes[0]
	var wage0 := GameState.wage_at(hh, "full")
	var plain_hp := 0
	seed(5)
	plain_hp = int(Combat.gen_monster({"monster_hp": 100.0, "monster_dmg": 10.0, "name": "Lesser Rift", "biome": "vale"}, 0, "combat")["hp"])
	GameState.oaths = ["lean_purse", "by_hand", "hollow_touched", "never_sell", "no_rest", "long_watch"]
	check(GameState.wage_at(hh, "full") > wage0 * 1.4, "Lean Purse: wages 50% higher")
	check(GameState.quick_fight_lock() != "", "By Hand: no Quick fight")
	seed(5)
	check(int(Combat.gen_monster({"monster_hp": 100.0, "monster_dmg": 10.0, "name": "Lesser Rift", "biome": "vale"}, 0, "combat")["hp"]) > plain_hp, "Hollow-Touched: foes have more health")
	GameState.choose_charter("quiet")
	check(GameState.charter_choice == "", "Never Sell a Rift: keeping quiet is refused")
	GameState.campaign_act = 5
	GameState.accord_ending = "break"
	var bare := 4 * int(GameData.LAURELS["act"]) + int(GameData.LAURELS["ending"])
	check(GameState.laurels_earned() == int(round(bare * 1.6)), "six oaths: Laurels +60%% (capped), %d" % GameState.laurels_earned())
	GameState.write_legacy([])
	check((GameState.legacy["guilds"][-1]["oaths"] as Array).size() == 6, "the Hall of Guilds records the oaths kept")

	# ---- The ending sets the postgame ----
	# Renew: Keepers of the Vale.
	GameState.legacy = {"laurels": 0, "guilds": [], "champions": {}}
	_guild("Keepers")
	GameState.campaign_act = 5
	check(GameState.hall_lock("iron_oath") != "", "the old halls are only for a guild that renewed the Accord")
	GameState.accord_ending = "renew"
	GameState.write_legacy([])
	GameState.coins = 200000
	GameState.crystals = 100000
	var slots0 := GameState.hero_slot_cap()
	var c0: Array = GameState.hall_cost("iron_oath")
	check(GameState.restore_hall("iron_oath") == "" and GameState.hero_slot_cap() == slots0 + 1, "the Iron Oath's hall: one more hero slot")
	var c1: Array = GameState.hall_cost("green_hand")
	check(int(c1[0]) > int(c0[0]) and int(c1[1]) > int(c0[1]), "each hall costs more than the last")
	check(GameState.hall_lock("grandmaster") != "", "the Grandmaster's hall comes last")
	var prices0 := GameState.merchant_price_reduction()
	for id in ["green_hand", "quiet_coin", "ninth_lamp", "long_roads", "open_hand"]:
		GameState.restore_hall(id)
	check(GameState.merchant_price_reduction() > prices0 and GameState.charter_pay(false) > 1.0 and GameState.charter_pay(true) > 1.0, "the halls cut prices and raise contract Gold and Essence")
	var lau0 := int(GameState.legacy["laurels"])
	check(GameState.restore_hall("grandmaster") == "" and int(GameState.legacy["laurels"]) == lau0 + GameData.GRANDMASTER_LAURELS, "the Grandmaster's hall: +20 Laurels")
	check(str(GameState.legacy["guilds"][-1].get("title", "")) == "Keepers of the Vale", "and the title, in the Hall of Guilds")
	GameState.check_completion_board()
	check(GameState.board_claimed.has("halls") and not GameState.board_claimed.has("tides"), "the completion board pays for the halls, and has no tides for a Keeper")

	# Break: the Open Hollow's tides.
	_guild("Tidewatch")
	GameState.campaign_act = 5
	GameState.best_rift_rank_sealed = GameData.rift_rank_index("A")
	GameState.accord_ending = "break"
	GameState.write_legacy([])
	GameState._swell_breach()
	check(GameState.breach.get("tide", 0) == 1 and is_equal_approx(GameState.tide_strength(), 1.0), "tide 1 breaks at Rank A strength")
	GameState._on_rift_sealed(GameData.rift_rank_index("SSS"))
	check(not GameState.breach.is_empty(), "a tide can't be sealed away")
	var lau1 := int(GameState.legacy["laurels"])
	GameState.resolve_breach({"held": true, "integrity": 1.0, "fallen": []})
	check(GameState.tides_held == 1 and int(GameState.legacy["laurels"]) == lau1 + GameData.TIDE_LAURELS, "holding a tide pays Laurels")
	check(GameState.breach_next_day == GameState.day + GameData.TIDE_DAYS, "the next tide comes in a week")
	GameState._swell_breach()
	check(GameState.tide_strength() > 1.05 and float(GameState.defense_opts()["foe_mult"]) == GameState.tide_strength(), "tide 2 is stronger")
	GameState.breach = {}
	GameState.delete_slot(9)
