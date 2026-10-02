extends "res://scripts/autoload/game_state/GameStateQuests.gd"
## GameState, part 5: rift difficulty and the modes built on runs — campaign, the daily twist, Tower hooks, boons, records.


## Folds a ladder rank (GameData.RIFT_RANKS) into a copy of its base `diff`:
## foe multipliers, reward multiplier and extra rules. Shared by start_run()
## (the first build_layers() call) and _diff() (every later lookup).
func _apply_rift_rank_modifiers(diff: Dictionary, rift_rank: String) -> Dictionary:
	if rift_rank == "":
		return diff
	var mods: Dictionary = GameData.find_rift_rank(rift_rank)
	var out := diff.duplicate(true)
	var above_f := rift_rank != "F"
	out["monster_hp"] = float(out["monster_hp"]) * float(mods["hp"]) * (GameData.RANK_THREAT_HP if above_f else 1.0)
	out["monster_dmg"] = float(out["monster_dmg"]) * float(mods["dmg"]) * (GameData.RANK_THREAT_DMG if above_f else 1.0)
	var rw := float(mods["reward"])
	out["coin"] = [int(round(float(out["coin"][0]) * rw)), int(round(float(out["coin"][1]) * rw))]
	out["crystal"] = [int(round(float(out["crystal"][0]) * rw)), int(round(float(out["crystal"][1]) * rw))]
	out["seal_essence"] = int(round(float(out["seal_essence"]) * rw))
	out["rec_power"] = int(mods["rec"])
	out["hazard_severity_up"] = int(mods.get("hazard_severity_up", 0))
	out["elite_chance_up"] = bool(mods.get("elite_chance_up", false))
	out["shop_chance_down"] = bool(mods.get("shop_chance_down", false))
	out["boss_double_mechanic"] = bool(mods.get("boss_double_mechanic", false))
	return out


func _diff() -> Dictionary:
	if run.has("tower"):
		return _tower_diff(tower_floor_info(int(run["tower"])))
	var diff: Dictionary = GameData.DIFFICULTIES[0]
	for d in GameData.DIFFICULTIES:
		if d["id"] == run["diff_id"]:
			diff = d
	diff = _apply_rift_rank_modifiers(diff, str(run.get("rift_rank", "")))
	if not run.is_empty():
		diff = diff.duplicate()
		diff["biome"] = run_biome()
	if run.has("daily"):
		diff = _apply_daily(diff)
	if int(run.get("finale", 0)) > 0:
		return _apply_finale(diff)
	if run.get("morrow", false):   # the Charter War: Morrow is this rift's boss
		diff = diff.duplicate()
		diff["boss_name"] = GameData.MORROW_BOSS
	return _apply_training(diff) if run.get("training", false) else diff


func _apply_training(diff: Dictionary) -> Dictionary:
	var out := diff.duplicate(true)
	var t: Dictionary = GameData.TRAINING_RIFT
	out["floors"] = int(t["floors"])
	out["monster_hp"] = int(round(float(out["monster_hp"]) * float(t["monster_hp_mult"])))
	out["monster_dmg"] = int(round(float(out["monster_dmg"]) * float(t["monster_dmg_mult"])))
	return out


# ---------------- Campaign ----------------

func campaign_done() -> bool:
	return campaign_act > GameData.CAMPAIGN.size()


func current_act() -> Dictionary:
	return {} if campaign_done() else GameData.CAMPAIGN[campaign_act - 1]


func campaign_objective_progress(o: Dictionary) -> int:
	var t := str(o["type"])
	if t.begins_with("boss:"):
		return int(quest_tally.get(t, 0))
	match t:
		"rifts_sealed": return rifts_sealed
		"heroes": return heroes.size()
		"greater_seals": return int(quest_tally.get("greater_seals", 0))
		"reputation": return reputation
		"map_rank": return best_rift_rank_sealed + 1 if best_rift_rank_sealed >= int(o["target"]) else 0
		"quests_done": return int(quest_tally.get("quests_done", 0))
		"ledger_pages": return accord_pages
		"posts_freed": return posts_freed()
	return 0


## Lost champions freed in the Endless Rift: the posts the guild has emptied.
func posts_freed() -> int:
	return lost_champions().filter(func(e): return champion_unlocked(str(e[0]))).size()


func campaign_objective_met(o: Dictionary) -> bool:
	if str(o["type"]) == "map_rank":
		return best_rift_rank_sealed >= int(o["target"])
	return campaign_objective_progress(o) >= int(o["target"])


func finale_ready() -> bool:
	var act := current_act()
	return not act.is_empty() and (act["objectives"] as Array).all(func(o): return campaign_objective_met(o))


func finale_recommended_power() -> int:
	var act := current_act()
	if act.is_empty():
		return 0
	return int(round(Combat.recommended_power(str(act["tier"]), str(act.get("rank", ""))) * float(act["mult"])))


## A biome for a new rift: the Vale in Act I, the Vale or the Marshes in Act
## II, any of the three after that.
func pick_biome() -> String:
	var open := ["vale"] if campaign_act <= 1 else (["vale", "marsh", "marsh"] if campaign_act == 2 else ["vale", "marsh", "ashen"])
	return str(open[randi() % open.size()])


## The run's biome.
func run_biome() -> String:
	return str(run.get("biome", "vale"))


## A finale is its act's gate rank (the one you seal to open it) and then
## some: it was the bare tier x1.15-1.45, weaker than the rank before it, and
## a quarter of finale fights ended in round 1 (campaign_sim).
func _apply_finale(diff: Dictionary) -> Dictionary:
	var act: Dictionary = GameData.CAMPAIGN[int(run["finale"]) - 1]
	var out := _apply_rift_rank_modifiers(diff, str(act.get("rank", ""))).duplicate(true)
	out["monster_hp"] = int(round(float(out["monster_hp"]) * float(act["mult"])))
	out["monster_dmg"] = int(round(float(out["monster_dmg"]) * float(act["mult"])))
	if int(act["act"]) == 4:   # the Terms grow with every empty post
		var grow := 1.0 + GameData.TERMS_PER_POST * posts_freed()
		out["monster_hp"] = int(round(float(out["monster_hp"]) * grow))
		out["monster_dmg"] = int(round(float(out["monster_dmg"]) * grow))
	out["boss_name"] = str(act["boss"])
	out["boss_double_mechanic"] = int(act["act"]) >= 3
	return out


## Sealing a finale: the act's reward, a Legendary relic, the next act.
func _complete_act(act_num: int) -> void:
	var act: Dictionary = GameData.CAMPAIGN[act_num - 1]
	var reward: Dictionary = act["reward"]
	crystals += int(reward.get("crystals", 0))
	var relic := Combat.gen_unique_relic()
	relics.append(relic)
	campaign_act = act_num + 1
	var subtitle := tr("Act %s complete — +%d Essence, %s") % [tr(str(_roman(act_num))), int(reward.get("crystals", 0)), tr(str(relic.name))]
	if str(act["opens"]) != "":
		subtitle += tr(" · %s unlocked") % tr(str(act["opens"]))
	pending_stories.append({"title": tr(str(act["finale"])) + tr(" — sealed"), "subtitle": subtitle, "text": str(act["outro"])})
	var freed := story_champion(act_num)
	if freed != "" and not champions.has(freed):
		unlock_champion(freed)
		var d := GameData.champion_def(freed)
		pending_stories.append({"title": tr("A champion is freed"), "subtitle": GameData.champion_full_name(freed),
			"text": tr("Deep in %s, held in a pillar of light, your guild finds %s. %s\n\n%s\n\nChampions oversee your rift runs (their Boon, and their Call) and fight in the Endless Rift. See Roster > Champions.") % [tr(str(act["finale"])), GameData.champion_full_name(freed), tr(str(d.get("lore", ""))), champion_memory_line(freed)]})
	if act_num == 3 and feature_unlocked("rival"):
		pending_stories.append(_charter_hearing())
	if act_num == 2 and feature_unlocked("rival") and charter_choice == "":
		pending_stories.append(GameData.CHARTER_TURN.duplicate(true))   # after Act III's intro (below)
	if act_num == 4:
		pending_stories.append(GameData.ACCORD_CHOICE.duplicate(true))   # the ending, then The End
	elif campaign_done():
		pending_stories.append(_the_end_card())
	else:
		pending_stories.append(_act_intro_card(campaign_act))
		# The Charter War's turn waits until after Act III's intro.
		var turn := pending_stories.filter(func(c): return str(c.get("kind", "")) == "charter")
		for c in turn:
			pending_stories.erase(c)
			pending_stories.append(c)


## "<Name> remembers: ..." (the Broken Accord), or "" for a champion without one.
func champion_memory_line(id: String) -> String:
	var m := str(GameData.CHAMPION_MEMORY.get(id, GameData.champion_def(id).get("memory", "")))
	return "" if m == "" else tr("%s remembers: %s") % [tr(str(GameData.champion_def(id)["name"])), tr(m)]


## A sealed rift may turn up the next page of the Grandmaster's ledger (a
## finale always does), once the campaign has reached that page's act.
func maybe_find_ledger_page(finale: bool) -> void:
	if accord_pages >= GameData.LEDGER_PAGES.size():
		return
	var page: Dictionary = GameData.LEDGER_PAGES[accord_pages]
	if campaign_act < int(page["act"]) or (not finale and randf() >= GameData.LEDGER_PAGE_CHANCE):
		return
	accord_pages += 1
	pending_toasts.append({"cls_id": "", "pool_id": "", "title": tr("A page of the Grandmaster's ledger"),
		"text": tr("Page %d of %d, found in the rift. Read it in Library > Codex > Chronicle.") % [accord_pages, GameData.LEDGER_PAGES.size()]})


## What the Rifts Take: from Act II a sealed rift sometimes leaves an echo
## (GameData.ECHOES, each once), a choice card: give it back or keep it.
func maybe_echo() -> void:
	if campaign_act < 2 or pending_stories.any(func(c): return str(c.get("kind", "")) == "echo") or randf() >= GameData.ECHO_CHANCE:
		return
	var left: Array = GameData.ECHOES.filter(func(e): return not echoes_seen.has(str(e["id"])))
	if left.is_empty():
		return
	var e: Dictionary = left[randi() % left.size()]
	echoes_seen.append(str(e["id"]))
	pending_stories.append({"kind": "echo", "echo": str(e["id"]), "title": str(e["title"]), "subtitle": tr("An echo, from the last rift"),
		"text": str(e["text"]), "choices": ["return", "keep"], "essence": echo_essence()})


func echo_essence() -> int:
	return 25 + 15 * mini(campaign_act, 4)


## Answers the echo on top of the story queue: "return" (Renown, and a scene)
## or "keep" (its Essence).
func answer_echo(choice: String) -> void:
	if pending_stories.is_empty() or str(pending_stories[0].get("kind", "")) != "echo":
		return
	var card: Dictionary = pending_stories.pop_front()
	var e: Array = GameData.ECHOES.filter(func(x): return str(x["id"]) == str(card["echo"]))
	if choice == "return":
		add_reputation(GameData.ECHO_RENOWN)
		echoes_returned += 1
		if not e.is_empty():
			pending_stories.push_front({"title": tr(str(e[0]["title"])), "subtitle": tr("Given back · +%d Renown") % GameData.ECHO_RENOWN, "text": str(e[0]["returned"])})
		_news(tr("An echo was given back to the village: %s.") % tr(str(card["title"])))
	else:
		crystals += int(card.get("essence", echo_essence()))
		_news(tr("An echo was kept: %s (+%d Essence).") % [tr(str(card["title"])), int(card.get("essence", 0))])
		_echo_touch(str(card["echo"]))
	if echoes_seen.size() == 3:   # the third echo brings Ezra
		var ez: Dictionary = GameData.EZRA_VISIT["gave" if echoes_returned * 2 >= echoes_seen.size() else "kept"]
		pending_stories.append({"title": tr(str(ez["title"])), "subtitle": tr(str(ez["subtitle"])), "text": tr(str(ez["text"]))})
	save()
	state_changed.emit()


## A kept echo may touch a hero who recognises what's in it (Echo-Touched).
func _echo_touch(echo_id: String) -> void:
	var pool: Array = heroes.filter(func(h): return not h.is_champion and not h.quirks.has("Echo-Touched"))
	if pool.is_empty() or randf() >= GameData.ECHO_TOUCH_CHANCE:
		return
	var h: Hero = pool[randi() % pool.size()]
	h.history["echoes"] = 1
	check_earned_quirks(h)
	var n := tr(str(h.name.split(" the ")[0]))
	var t: Dictionary = GameData.ECHO_TOUCH
	pending_stories.append({"title": tr(str(t["title"])) % n, "subtitle": tr(str(t["subtitle"])),
		"text": tr(str(t["text"])) % [n, tr(str(GameData.ECHO_HOLDS.get(echo_id, "something"))), n, n]})


## What the Vale remembers (the campaign's end, after three echoes or more).
func _vale_remembers() -> Dictionary:
	var v: Dictionary = GameData.VALE_REMEMBERS["gave" if echoes_returned * 2 >= echoes_seen.size() else "kept"]
	return {"title": tr(str(v["title"])), "subtitle": tr(str(v["subtitle"])), "text": tr(str(v["text"]))}


## The Charter War's turn: "expose" the Hollow Crown Company or keep "quiet"
## (the choice card that opens Act III).
func choose_charter(choice: String) -> void:
	if charter_choice != "" or not GameData.CHARTER_RESULT.has(choice):
		return
	charter_choice = choice
	if choice == "expose":
		add_reputation(GameData.CHARTER_EXPOSE_RENOWN)
		if rival_name == "The Hollow Crown Company":
			rival_renown = maxi(0, rival_renown - GameData.CHARTER_EXPOSE_RENOWN)   # the Crown fines them
		if campaign_act >= GameData.BREACH_UNLOCK_ACT and breach.is_empty():
			breach_next_day = day + 2   # the Company opens one on your road
	var r: Dictionary = GameData.CHARTER_RESULT[choice]
	if not pending_stories.is_empty() and str(pending_stories[0].get("kind", "")) == "charter":
		pending_stories.pop_front()
	pending_stories.push_front({"title": tr(str(r["title"])), "subtitle": tr(str(r["subtitle"])), "text": tr(str(r["text"]))})
	_news(tr(str(r["title"])) + ".")
	save()
	state_changed.emit()


## The Crown's hearing (Act III's end): the Royal Charter to the Renown leader.
func _charter_hearing() -> Dictionary:
	charter_result = "won" if reputation >= rival_renown else "lost"
	var h: Dictionary = GameData.CHARTER_HEARING[charter_result]
	var rn := tr(str(rival_name))
	var card := {"title": tr(str(h["title"])), "subtitle": tr(str(h["subtitle"])), "text": tr(str(h["text"]))}
	if charter_result == "lost":
		card["subtitle"] = card["subtitle"] % rn
		card["text"] = card["text"] % rn
	_news(card["subtitle"] + ".")
	return card


## Wen's line for the Memorial (by voice, a steady pick per name).
func memorial_line(h: Hero) -> String:
	var lines: Array = GameData.MEMORIAL_LINES.get(GameData.hero_voice(h), GameData.MEMORIAL_LINES["stoic"])
	var first := str(h.name.split(" the ")[0])
	return tr(str(lines[abs(first.hash()) % lines.size()])) % tr(first)


func _the_end_card() -> Dictionary:
	return {"title": tr("The End"), "subtitle": tr("The campaign is complete"), "text": tr("Thank you for playing. Your guild endures: push the Endless Rift, climb the rift ladder, and take on quests for as long as rifts keep opening.")}


## The Broken Accord's ending (the choice card after Act IV). "renew" needs
## the hero who takes the forty-first post; "break" frees every champion of
## this guild. Returns "" or why not.
func choose_accord_ending(choice: String, hero_id: String = "") -> String:
	if accord_ending != "" or not GameData.ACCORD_ENDING.has(choice):
		return ""
	var end: Dictionary = GameData.ACCORD_ENDING[choice]
	var card := {"title": tr(str(end["title"])), "subtitle": tr(str(end["subtitle"])), "text": tr(str(end["text"]))}
	if choice == "renew":
		var h := find_hero(hero_id)
		if h == null or h.is_champion:
			return tr("Choose a hero to take the post.")
		if heroes.size() <= 1:
			return tr("The guild needs at least one hero.")
		var first := tr(str(h.name.split(" the ")[0]))
		card["subtitle"] = card["subtitle"] % first
		card["text"] = card["text"] % first
		accord_hero = first
		_memorialize(h, tr("Took the forty-first post"))
		_release(h)
		breach = {}
		breach_next_day = -1
	else:
		for id in champion_roll:
			unlock_champion(str(id))
	accord_ending = choice
	if not pending_stories.is_empty() and pending_stories[0].has("choices"):
		pending_stories.pop_front()
	pending_stories.push_front(_the_end_card())
	if echoes_seen.size() >= 3:
		pending_stories.push_front(_vale_remembers())
	pending_stories.push_front(card)
	_news(card["title"] + ".")
	save()
	state_changed.emit()
	return ""


func _act_intro_card(act_num: int) -> Dictionary:
	var act: Dictionary = GameData.CAMPAIGN[act_num - 1]
	return {"title": tr("Act %s — %s") % [tr(str(_roman(act_num))), tr(str(act["name"]))], "subtitle": tr("Foe: %s") % tr(str(act["foe"])), "text": str(act["intro"])}


static func _roman(n: int) -> String:
	return ["I", String(TranslationServer.translate("II")), String(TranslationServer.translate("III")), "IV"][clampi(n - 1, 0, 3)]


# ---------------- The daily twist on the ladder ----------------

static func daily_id() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


## Today's twist: rule, starting boon, region and seed.
func daily_info(day: int = -1) -> Dictionary:
	if day < 0:
		day = daily_id()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["daily", day])
	var rules: Array = GameData.TOWER_RULES.filter(func(r): return not r.has("party_cap"))
	var rule: Dictionary = rules[rng.randi() % rules.size()]
	var boon: Dictionary = GameData.BOONS[rng.randi() % GameData.BOONS.size()]
	var biomes := ["vale", "marsh", "ashen"]
	return {"day": day, "rule": rule, "boon": str(boon["id"]),
		"biome": biomes[rng.randi() % biomes.size()], "seed": rng.randi()}


func daily_available() -> bool:
	return feature_unlocked("daily") and daily_attempt_day != daily_id()


func _apply_daily(diff: Dictionary) -> Dictionary:
	var rule: Dictionary = daily_info(int(run["daily"]))["rule"]
	var d := diff.duplicate(true)
	d.merge(rule.get("diff", {}), true)
	var hp := float(d["monster_hp"]) * float(d.get("hp_mult", 1.0)) * (2.0 if d.get("tower_single", false) else 1.0)
	d["monster_hp"] = int(round(hp))
	d["monster_dmg"] = int(round(float(d["monster_dmg"]) * float(d.get("dmg_mult", 1.0))))
	return d


## Sealing a rift with today's twist: the bonus, and the streak.
func _complete_daily() -> Dictionary:
	var day := int(run["daily"])
	daily_clears += 1
	daily_streak = daily_streak + 1 if daily_last_clear == day - 1 else 1
	daily_last_clear = day
	var cr := GameData.DAILY_CLEAR_CRYSTALS + GameData.DAILY_CLEAR_CRYSTALS_PER_ACT * mini(campaign_act, 3)
	crystals += cr
	return {"crystals": cr, "streak": daily_streak}


# ---------------- Records: run history, memorial ----------------

func _run_label() -> String:
	if str(run.get("rift_rank", "")) != "":
		return tr("Rank %s rift") % tr(str(run["rift_rank"])) + (tr(" · daily twist") if run.has("daily") else "")
	if int(run.get("finale", 0)) > 0:
		return tr("Act %s finale") % tr(str(_roman(int(run["finale"]))))
	return str(_diff().get("name", tr("Rift")))


## Appends the run that's ending to run_history (newest first).
func _record_run(outcome: String) -> void:
	if run.is_empty() or run.has("tower"):
		return
	var names: Array = []
	for h in current_party():
		names.append(h.name.split(" the ")[0])
	var entry := {"day": day, "kind": _run_label(), "result": outcome,
		"floor": "%d/%d" % [mini(int(run.get("pos", 0)) + 1, (run.get("layers", []) as Array).size()), (run.get("layers", []) as Array).size()],
		"heroes": names, "boons": run.get("boons", []),
		"coins": coins - int(run.get("start_coins", coins)), "crystals": crystals - int(run.get("start_crystals", crystals))}
	run_history.push_front(entry)
	if run_history.size() > GameData.RUN_HISTORY_MAX:
		run_history.resize(GameData.RUN_HISTORY_MAX)
	runs_finished += 1


## A key (English): compared, and kept in run history; shown translated.
func _run_outcome() -> String:
	if run.get("sealed") != null:
		return "Sealed"
	var res: Dictionary = run.get("node_state", {}).get("result", {})
	if bool(res.get("retreated", false)):
		return "Retreated"
	if not res.is_empty() and not bool(res.get("won", true)):
		return "Defeated"
	return "Left"


## Remembers a hero lost for good (left behind in a rift).
func _memorialize(h: Hero, cause: String) -> void:
	fallen.push_front({"name": h.name, "cls_id": h.cls_id, "pool_id": h.pool_id, "rank": h.rank, "level": h.level,
		"day": day, "cause": cause, "rifts": int(h.history.get("rifts_cleared", 0)), "kills": int(h.history.get("kills", 0)),
		"line": memorial_line(h)})
	heroes_lost_total += 1


# ---------------- Run boons ----------------

func boon_family_counts() -> Dictionary:
	var counts := {}
	for id in run.get("boons", []):
		var fam := str(GameData.find_boon(str(id)).get("family", ""))
		if fam != "":
			counts[fam] = int(counts.get(fam, 0)) + 1
	return counts


## Three boons not yet owned; when you already lean into a family, one slot
## favours it so a build can come together.
func roll_boon_offer() -> Array:
	var owned: Array = run.get("boons", [])
	var pool: Array = GameData.BOONS.filter(func(b): return not owned.has(b["id"])).map(func(b): return str(b["id"]))
	pool.shuffle()
	var offer: Array = []
	var counts := boon_family_counts()
	if not counts.is_empty():
		var fams := counts.keys()
		var fav := str(fams[randi() % fams.size()])
		for id in pool:
			if GameData.find_boon(id)["family"] == fav:
				offer.append(id)
				break
	for id in pool:
		if offer.size() >= GameData.BOON_OFFER_SIZE:
			break
		if not offer.has(id):
			offer.append(id)
	return offer


## Takes offered boon `idx` (or -1 to skip) from the current fight's result.
func pick_boon(idx: int) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var res: Dictionary = ns.get("result", {})
	var offer: Array = res.get("boon_offer", [])
	if ns.get("boon_chosen", false) or offer.is_empty():
		return
	if idx >= 0 and idx < offer.size():
		var boons: Array = run.get("boons", [])
		boons.append(str(offer[idx]))
		run["boons"] = boons
		if boon_family_counts().values().any(func(n): return int(n) >= 4):
			boon_set4_reached = true
	ns["boon_chosen"] = true
	run["node_state"] = ns
	save()
	state_changed.emit()


func boon_pending() -> bool:
	var ns: Dictionary = run.get("node_state", {})
	return not (ns.get("result", {}).get("boon_offer", []) as Array).is_empty() and not ns.get("boon_chosen", false)


# ---------------- Tower of Trials ----------------

static func tower_week_id() -> int:
	return int(Time.get_unix_time_from_system() / 604800.0)


func _tower_roll_week() -> void:
	if tower_week != tower_week_id():
		tower_week = tower_week_id()
		tower_week_cleared = 0


## The floor a new attempt fights: the next uncleared one, or, once floor 90
## is cleared, this week's next ladder floor (91-100). 0 = nothing left this week.
func tower_next_floor() -> int:
	_tower_roll_week()
	var from := GameData.TOWER_WEEKLY_FROM
	if tower_best < from - 1:
		return tower_best + 1
	var f := from + tower_week_cleared
	return f if f <= GameData.TOWER_FLOORS else 0


## Everything fixed about a floor: its fight kind, region, guardian, rules
## (seeded by the floor; floors 91+ also by the week) and first-clear reward.
func tower_floor_info(f: int) -> Dictionary:
	var boss: Dictionary = GameData.TOWER_BOSSES.get(f, {})
	var weekly := f >= GameData.TOWER_WEEKLY_FROM
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["tower", f, tower_week_id() if weekly else 0])
	var rules: Array = []
	if boss.is_empty() and f > 5:
		var pool: Array = GameData.TOWER_RULES.duplicate()
		for i in (2 if weekly else 1):
			rules.append(pool.pop_at(rng.randi() % pool.size()))
	var cap := 4
	for r in rules:
		cap = mini(cap, int(r.get("party_cap", 4)))
	return {"floor": f, "kind": "boss" if not boss.is_empty() else ("elite" if f % 5 == 0 else "combat"),
		"biome": str(boss.get("biome", ["vale", "marsh", "ashen"][((f - 1) / 10) % 3])),
		"boss": boss, "rules": rules, "weekly": weekly, "party_cap": cap, "seed": rng.randi(), "reward": tower_reward(f)}


## First-clear reward for a floor (every 5th floor pays extra Crystals). A
## weekly re-clear pays half the Coins and Crystals and nothing else.
func tower_reward(f: int) -> Dictionary:
	return {"coins": 20 + 4 * f, "crystals": 8 + int(1.5 * f) + ((2 + f / 10) if f % 5 == 0 else 0),
		"relic": GameData.TOWER_RELICS.get(f, {})}


## Fit to the balance sim: a party of this power clears about half its tries.
## Party power whose climb typically ends around floor f (balance_sim
## -- calibrate), interpolated between measured points.
const TOWER_REC := [[1, 60], [5, 140], [10, 250], [20, 650], [45, 1000], [70, 1500], [85, 2200], [100, 2600]]


func tower_recommended_power(f: int) -> int:
	for i in range(1, TOWER_REC.size()):
		if f <= int(TOWER_REC[i][0]):
			var a: Array = TOWER_REC[i - 1]
			var b: Array = TOWER_REC[i]
			return int(round(lerpf(float(a[1]), float(b[1]), clampf(float(f - int(a[0])) / float(int(b[0]) - int(a[0])), 0.0, 1.0))))
	return int(TOWER_REC[-1][1])


func _tower_diff(info: Dictionary) -> Dictionary:
	var f := int(info["floor"])
	var d := {"id": "tower", "name": "Tower of Trials", "floors": 1, "power": "Trial",
		"coin": [0, 0], "crystal": [0, 0], "seal_essence": 0, "cache_chance": 0.0,
		"rec_power": tower_recommended_power(f), "biome": info["biome"]}
	for r in info["rules"]:
		d.merge(r.get("diff", {}), true)
	var hp := float(GameData.TOWER_BASE["monster_hp"]) * pow(1.0 + GameData.TOWER_HP_GROWTH, f - 1) * float(d.get("hp_mult", 1.0))
	if d.get("tower_single", false):
		hp *= 2.0
	d["monster_hp"] = int(round(hp))
	d["monster_dmg"] = int(round(float(GameData.TOWER_BASE["monster_dmg"]) * pow(1.0 + GameData.TOWER_DMG_GROWTH, f - 1) * float(d.get("dmg_mult", 1.0))))
	var boss: Dictionary = info["boss"]
	if not boss.is_empty():
		d["boss_name"] = str(boss["name"])
		d["boss_mechanics"] = boss["mechanics"]
	return d


func tower_title() -> String:
	var t := ""
	for e in GameData.TOWER_TITLES:
		if tower_best >= int(e[0]):
			t = str(e[1])
	return t


## Pays a cleared floor (from _apply_combat_outcome, once) and returns what
## it paid for the result screen.
func _complete_tower_floor(f: int) -> Dictionary:
	var first := f > tower_best
	var rw := tower_reward(f)
	var got := {"floor": f, "first": first, "coins": int(rw["coins"]), "crystals": int(rw["crystals"]), "relic": "", "title": ""}
	if first:
		var rdef: Dictionary = rw["relic"]
		if not rdef.is_empty():
			var r := Combat.relic_from_unique(rdef)
			r.equipped = Combat.equipped_relics().size() < relic_slot_cap()
			relics.append(r)
			got["relic"] = r.name
		var old_title := tower_title()
		tower_best = f
		if tower_title() != old_title:
			got["title"] = tower_title()
	else:
		got["coins"] = int(got["coins"]) / 2
		got["crystals"] = int(got["crystals"]) / 2
	if f >= GameData.TOWER_WEEKLY_FROM:
		_tower_roll_week()
		tower_week_cleared = maxi(tower_week_cleared, f - GameData.TOWER_WEEKLY_FROM + 1)
	coins += int(got["coins"])
	crystals += int(got["crystals"])
	return got


func _end_tower() -> void:
	var snap: Dictionary = run.get("tower_snap", {})
	for h in current_party():
		if snap.has(h.id):
			var s: Array = snap[h.id]
			h.hp = int(s[0])
			h.down_runs = int(s[1])
			h.bedded = bool(s[2])
	run = {}
	_clamp_hp_to_max()
	save()
	state_changed.emit()


# ---------------- Legacy ----------------
## The Laurels this guild leaves the next ones (GameData.LAURELS).
func laurels_earned() -> int:
	var L: Dictionary = GameData.LAURELS
	var n := clampi(campaign_act - 1, 0, GameData.CAMPAIGN.size()) * int(L["act"])
	n += int(L["ending"]) if accord_ending != "" else 0
	n += posts_freed() * int(L["freed"])
	n += int(L["charter"]) if charter_result == "won" else 0
	n += int(L["morrow"]) if morrow_defeated else 0
	n += echoes_returned * int(L["echo"])
	return n


## Heroes the Vale can remember: Rank C or higher, or 25 rifts sealed.
func legacy_candidates() -> Array:
	return heroes.filter(func(h): return not h.is_champion and (GameData.rank_index(h.rank) >= GameData.rank_index(GameData.LEGACY_MIN_RANK)
		or int(h.history.get("rifts_cleared", 0)) >= GameData.LEGACY_MIN_RIFTS))


## The Accord's ending is chosen and the guild's legacy isn't written yet.
func legacy_due() -> bool:
	return guild_name != "" and accord_ending != "" and not legacy_written


## A guild can retire once Act II is done (and not after its legacy is written).
func can_retire() -> bool:
	return guild_name != "" and campaign_act >= 3 and not legacy_written


## Writes this guild into the Vale's history: its record in the Hall of
## Guilds, up to LEGACY_HEROES remembered heroes as champions for later
## guilds (plus whoever took the forty-first post), and its Laurels.
## Returns the Laurels earned.
func write_legacy(hero_ids: Array, retired: bool = false) -> int:
	if legacy_written or guild_name == "":
		return 0
	if legacy.is_empty():
		load_legacy()
	var names: Array = []
	var ok := legacy_candidates()
	for hid in hero_ids.slice(0, GameData.LEGACY_HEROES):
		var h := find_hero(str(hid))
		if h and ok.has(h):
			_legacy_champion({"name": h.name, "cls_id": h.cls_id, "pool_id": h.pool_id, "rank": h.rank,
				"rifts": int(h.history.get("rifts_cleared", 0)), "kills": int(h.history.get("kills", 0))}, false)
			names.append(h.name.split(" the ")[0])
	if accord_ending == "renew":
		for f in fallen:
			if str(f.get("name", "")).split(" the ")[0] == accord_hero:
				_legacy_champion(f, true)
				names.append(accord_hero)
				break
	# Only the most recent remembered heroes stay in the pool.
	var keys: Array = (legacy["champions"] as Dictionary).keys()
	keys.sort_custom(func(a, b): return int(legacy["champions"][a].get("at", 0)) > int(legacy["champions"][b].get("at", 0)))
	for k in keys.slice(GameData.LEGACY_POOL):
		(legacy["champions"] as Dictionary).erase(k)
	var earned := laurels_earned()
	legacy["laurels"] = int(legacy["laurels"]) + earned
	(legacy["guilds"] as Array).append({"id": "g%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 100000],
		"name": guild_name, "crest": guild_crest, "ending": accord_ending, "retired": retired, "day": day, "act": campaign_act,
		"rifts": rifts_sealed, "laurels": earned, "remembered": names, "fallen": fallen.size(), "charter": charter_result})
	legacy_written = true
	save_legacy()
	save()
	state_changed.emit()
	return earned


## A remembered hero as a champion: their name, class and portrait, a Boon,
## Call and mods borrowed from a champion of the same role, and a lore and
## memory line from their history.
func _legacy_champion(src: Dictionary, post: bool) -> String:
	var role := str(src.get("cls_id", "warrior"))
	var same: Array = GameData.CHAMPIONS.keys().filter(func(k): return str(GameData.CHAMPIONS[k]["role"]) == role)
	if same.is_empty():
		same = GameData.CHAMPIONS.keys()
	same.sort()
	var first := str(src.get("name", "")).split(" the ")[0]
	var tpl: Dictionary = GameData.CHAMPIONS[same[absi(hash(first + guild_name)) % same.size()]]
	var rifts := int(src.get("rifts", 0))
	var id := "legacy_%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 100000]
	var memory := tr(GameData.LEGACY_POST_MEMORY) % guild_name if post else ""
	if not post:
		var m := str(GameData.LEGACY_MEMORY[absi(hash(first)) % GameData.LEGACY_MEMORY.size()])
		memory = tr(m) % ([guild_name, rifts] if m.find("%s") < m.find("%d") else [rifts, guild_name])
	legacy["champions"][id] = {"name": first, "guild": guild_name, "role": role, "post": post, "at": int(Time.get_unix_time_from_system()),
		"boon": (tpl["boon"] as Dictionary).duplicate(), "call": (tpl["call"] as Dictionary).duplicate(), "mods": (tpl["mods"] as Array).duplicate(),
		"portrait": GameData.portrait_for_hero(role, str(src.get("pool_id", ""))),
		"lore": tr(GameData.LEGACY_POST_LORE) % guild_name if post else tr(GameData.LEGACY_LORE) % [tr(str(src.get("rank", "F"))), guild_name, rifts, int(src.get("kills", 0))],
		"memory": memory}
	return id


## Spends Laurels on founding gifts for this new guild (GameData.LEGACY_GIFTS
## ids); a gift it can't afford is skipped. Returns the ones applied.
func apply_legacy_gifts(ids: Array) -> Array:
	var applied: Array = []
	for g in GameData.LEGACY_GIFTS:
		if not ids.has(g["id"]) or int(legacy.get("laurels", 0)) < int(g["cost"]):
			continue
		legacy["laurels"] = int(legacy["laurels"]) - int(g["cost"])
		match str(g["id"]):
			"gold":
				coins += 300
			"hero":
				heroes.append(Combat.gen_hero("D", 1))
			"relic":
				var r := Combat.gen_relic("rare")
				r.id = "rl" + str(next_id)
				next_id += 1
				r.equipped = true
				relics.append(r)
			"barracks":
				upgrades["ops.barracks"] = maxi(1, int(upgrades.get("ops.barracks", 0)))
		applied.append(g["id"])
	if not applied.is_empty():
		save_legacy()
		save()
	return applied
