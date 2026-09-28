extends "res://scripts/autoload/game_state/GameStateItems.gd"
## GameState, part 4: the Guild Board, reputation and milestones.


# ---------------- Quests: Guild Board (Contracts + Dailies) & Milestones ----------------
## Every Reputation gain routes through here so crossing a 20-point tier can
## auto-arm a Shop Boost (an Epic at the next rift shop) —
## Reputation losses (none exist yet, but kept symmetrical) skip the roll.
func add_reputation(amount: int) -> void:
	if amount <= 0:
		reputation = maxi(0, reputation + amount)
		return
	var before := reputation / 20
	reputation += amount
	if reputation / 20 > before:
		pending_shop_boost = true


## ---------------- Guild Board ----------------
## QUEST_POSTED quests are posted at a time; accept up to QUEST_ACTIVE_MAX.
## Every QUEST_REFRESH_DAYS days (a day = one rift run or rest) the unaccepted
## postings are replaced; accepted ones stay until claimed or abandoned.
## Progress is read off quest_tally / the all-time counters minus a baseline
## taken when the quest is accepted, so only work done after accepting counts.

func _quest_reward(diff: int) -> Dictionary:
	match diff:
		3:
			return {"coins": 110 + randi() % 50, "crystals": 30 + randi() % 12, "reputation": 5}
		2:
			return {"coins": 70 + randi() % 40, "crystals": 14 + randi() % 9, "reputation": 2}
	return {"coins": 40 + randi() % 30, "crystals": 5 + randi() % 6, "reputation": 1}


func _tally(key: String) -> int:
	return int(quest_tally.get(key, 0))


func _bump(key: String, n: int = 1) -> void:
	quest_tally[key] = _tally(key) + n


## Rolls one posting of a random type the guild can actually attempt now.
func roll_quest() -> Dictionary:
	var types := ["hunt", "hunt", "elite", "bounty", "seal_rank", "trial_small", "trial_flawless", "craft", "flawless_win"]
	if greater_rift_unlocked():
		types.append("seal_greater")
	var type: String = types[randi() % types.size()]
	var q := {"id": "quest%d" % next_id, "type": type, "param": "", "target": 1, "diff": 1, "status": "posted", "baseline": 0}
	next_id += 1
	match type:
		"hunt":
			var pool: Array = monsters_seen.filter(func(n): return GameData.MONSTER_NAMES.has(n))
			if pool.size() < 3:
				pool = GameData.MONSTER_NAMES
			q["param"] = str(pool[randi() % pool.size()])
			q["target"] = 4 + randi() % 4
		"elite":
			q["target"] = 1 + randi() % 2
			q["diff"] = q["target"]
		"bounty":
			q["param"] = str(GameData.BOSS_NAMES[randi() % GameData.BOSS_NAMES.size()])
			q["diff"] = 2
		"seal_rank":
			var r: int = clampi(max(best_rift_rank_sealed, 0) + randi() % 2, 1, 5)
			q["param"] = str(GameData.RIFT_RANKS[r]["id"])
			q["diff"] = 2 if r <= 3 else 3
		"seal_greater":
			q["diff"] = 3
		"trial_small":
			q["diff"] = 2
		"trial_flawless":
			q["diff"] = 3
		"craft":
			q["target"] = 1 + randi() % 2
		"flawless_win":
			q["target"] = 1 + randi() % 2
	q["reward"] = _quest_reward(int(q["diff"]))
	return q


## The all-time count a quest's progress is measured against.
func _quest_current(q: Dictionary) -> int:
	match str(q["type"]):
		"hunt": return int(monster_kill_counts.get(str(q["param"]), 0))
		"elite": return elites_won
		"bounty": return _tally("boss:" + str(q["param"]))
		"seal_rank":
			var n := 0
			for i in range(GameData.rift_rank_index(str(q["param"])), GameData.RIFT_RANKS.size()):
				n += _tally("rank_seals:%d" % i)
			return n
		"seal_greater": return _tally("greater_seals")
		"trial_small": return _tally("small_seals")
		"trial_flawless": return _tally("flawless_rifts")
		"craft": return crafts_performed
		"flawless_win": return flawless_wins
	return 0


func quest_progress(q: Dictionary) -> int:
	if str(q.get("status", "")) != "active":
		return 0
	return min(int(q["target"]), max(0, _quest_current(q) - int(q.get("baseline", 0))))


## Seeds a fresh board (new guild, or a save from the old contract/daily
## board) and refreshes postings when their days are up.
func resolve_guild_board() -> void:
	var changed := false
	if guild_board.is_empty() or guild_board.any(func(q): return not q.has("status")):
		guild_board = []
		board_refresh_day = day
		changed = true
	if day >= board_refresh_day:
		guild_board.assign(guild_board.filter(func(q): return str(q["status"]) == "active"))
		while guild_board.filter(func(q): return str(q["status"]) == "posted").size() < GameData.QUEST_POSTED:
			guild_board.append(roll_quest())
		board_refresh_day = day + GameData.QUEST_REFRESH_DAYS
		changed = true
	# Contracts past their due day fail: Renown and everyone's morale drop.
	for q in guild_board:
		if str(q["status"]) == "active" and day > int(q.get("due", 1 << 30)) and quest_progress(q) < int(q["target"]):
			q["status"] = "failed"
			add_reputation(-2 * int(q.get("diff", 1)))
			for h in heroes:
				h.morale = clampi(h.morale + GameData.MORALE_QUEST_FAILED, 0, 100)
			_news("Contract failed: %s (-%d Renown)." % [quest_desc(q), 2 * int(q.get("diff", 1))])
			pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Contract failed", "text": "%s ran out of time. -%d Renown, and the guild's morale dips." % [quest_desc(q), 2 * int(q.get("diff", 1))]})
			changed = true
	if changed:
		save()


func active_quests() -> Array:
	return guild_board.filter(func(q): return str(q["status"]) == "active")


func accept_quest(quest_id: String) -> String:
	if active_quests().size() >= GameData.QUEST_ACTIVE_MAX:
		return "You can only take %d at a time" % GameData.QUEST_ACTIVE_MAX
	for q in guild_board:
		if str(q["id"]) == quest_id and str(q["status"]) == "posted":
			q["status"] = "active"
			q["baseline"] = _quest_current(q)
			q["due"] = day + int(GameData.QUEST_DUE_DAYS.get(int(q.get("diff", 1)), 6))
			save()
			state_changed.emit()
			return ""
	return ""


func abandon_quest(quest_id: String) -> void:
	guild_board.assign(guild_board.filter(func(q): return str(q["id"]) != quest_id))
	save()
	state_changed.emit()


func quest_desc(q: Dictionary) -> String:
	var t := int(q["target"])
	var s := "" if t == 1 else "s"
	match str(q["type"]):
		"hunt": return "Hunt: defeat %s ×%d" % [q["param"], t]
		"elite": return "Hunt: win %d Elite fight%s" % [t, s]
		"bounty": return "Bounty: defeat %s" % q["param"]
		"seal_rank": return "Seal: seal a Rank %s+ rift" % q["param"]
		"seal_greater": return "Seal: seal a Rank C+ rift"
		"trial_small": return "Trial: seal a rift with 2 heroes or fewer (plus the Champion)"
		"trial_flawless": return "Trial: seal a rift without any hero going down"
		"craft": return "Supply: craft %d item%s or relic%s" % [t, s, s]
		"flawless_win": return "Trial: win %d fight%s without a hero going down" % [t, s]
	return "?"


func quest_reward_desc(reward: Dictionary) -> String:
	var parts: Array[String] = []
	if int(reward.get("coins", 0)) > 0:
		parts.append("%d Gold" % int(reward["coins"]))
	if int(reward.get("crystals", 0)) > 0:
		parts.append("%d Essence" % int(reward["crystals"]))
	if int(reward.get("reputation", 0)) > 0:
		parts.append("%d Renown" % int(reward["reputation"]))
	return ", ".join(parts)


func claim_quest(quest_id: String) -> void:
	for q in guild_board:
		if str(q["id"]) != quest_id or quest_progress(q) < int(q["target"]):
			continue
		var reward: Dictionary = q["reward"]
		var ledger := 1.5 if Combat.party_has_unique_relic("quartermasters_ledger") else 1.0
		coins += int(round(int(reward.get("coins", 0)) * ledger))
		crystals += int(round(int(reward.get("crystals", 0)) * ledger))
		add_reputation(int(reward.get("reputation", 0)))
		guild_board.erase(q)
		_bump("quests_done")
		save()
		state_changed.emit()
		return


func milestone_progress(m: Dictionary) -> int:
	match str(m["type"]):
		"rifts_sealed": return rifts_sealed
		"total_kills":
			var s := 0
			for v in monster_kill_counts.values():
				s += int(v)
			return s
		"elites_won": return elites_won
		"bosses_won": return bosses_won
		"crafts_performed": return crafts_performed
		"full_roster": return 1 if heroes.size() >= hero_slot_cap() else 0
		"guild_tier_renowned":
			var tname := str(Combat.guild_tier_info()["name"])
			return 1 if tname == "Renowned Guild" or tname == "Legendary Guild" else 0
		"greater_unlocked": return 1 if greater_rift_unlocked() else 0
		"campaign_act": return campaign_act
		"flawless_rifts": return int(quest_tally.get("flawless_rifts", 0))
		"tower_best": return tower_best
		"endless_time": return best_endless_time
		"daily_clears": return daily_clears
		"daily_streak": return daily_streak
		"boon_set4": return 1 if boon_set4_reached else 0
		"guild_tier_legendary": return 1 if str(Combat.guild_tier_info()["name"]) == "Legendary Guild" else 0
		"standings_top": return 1 if day > 0 and str(guild_standings()[0]["name"]) == guild_name else 0
		"max_level": return 1 if heroes.any(func(h): return h.level >= 10) else 0
		"roster_size": return heroes.size()
		_: return 0


## Called once per render() — cheap (8-item loop) — grants any not-yet-claimed
## milestone the instant its condition becomes true. Returns the ids newly
## granted this call (usually 0 or 1) so the caller can show a flavor toast.
func check_milestones() -> Array[String]:
	var newly: Array[String] = []
	for m in GameData.MILESTONES:
		var mid := str(m["id"])
		if milestones_claimed.has(mid):
			continue
		if milestone_progress(m) >= int(m["target"]):
			milestones_claimed.append(mid)
			var reward: Dictionary = m["reward"]
			coins += int(reward.get("coins", 0))
			crystals += int(reward.get("crystals", 0))
			add_reputation(int(reward.get("reputation", 0)))
			newly.append(mid)
	if not newly.is_empty():
		save()
		state_changed.emit()
	return newly


# ---------------- Running the guild: wages, morale, the rival ----------------

func _news(line: String) -> void:
	guild_news.push_front("Day %d: %s" % [day, line])
	if guild_news.size() > 12:
		guild_news.resize(12)


func wage_of(h: Hero) -> int:
	return int(round(float(GameData.WAGE_BY_RANK.get(h.rank, 15)) * (1.0 + GameData.WAGE_PER_LEVEL * (h.level - 1)) * (1.0 + float(wage_raise.get(h.id, 0.0)))))


func weekly_wages() -> int:
	var total := 0
	for h in heroes:
		total += wage_of(h)
	return total


func days_to_payday() -> int:
	return GameData.PAYDAY_DAYS - (day % GameData.PAYDAY_DAYS)


## The coming payday at a glance: {days, wages, upkeep, bill, have, short,
## since (Gold gained since the last payday), per_run (average pay of the
## last few rifts, 0 if none), runs (rifts at that pay to cover the gap)}.
func payday_forecast() -> Dictionary:
	var w := weekly_wages()
	var up := upkeep()
	var bill := w + up
	var pays: Array = run_history.slice(0, 5).map(func(e): return int(e.get("coins", 0))).filter(func(c): return c > 0)
	var per_run := 0
	if not pays.is_empty():
		per_run = int(pays.reduce(func(a, b): return a + b, 0) / pays.size())
	var short := maxi(0, bill - coins)
	return {"days": days_to_payday(), "wages": w, "upkeep": up, "bill": bill, "have": coins, "short": short,
		"since": coins - (week_start_coins if week_start_coins >= 0 else coins), "per_run": per_run,
		"runs": (int(ceil(float(short) / per_run)) if per_run > 0 else -1) if short > 0 else 0}


# ---------------- Hero requests ----------------

## Mid-week, maybe a hero asks for something (see HERO_REQUESTS).
func maybe_hero_request() -> void:
	if not hero_request.is_empty() or day % GameData.PAYDAY_DAYS != GameData.REQUEST_DAY:
		return
	var in_rift: Array = run.get("hero_ids", []) if not run.is_empty() else []
	var pool: Array = heroes.filter(func(h): return not h.is_champion and not in_rift.has(h.id) and not h.is_downed())
	if pool.is_empty():
		return
	pool.shuffle()
	var types: Array = ["week_off", "raise", "gear"]
	if training_left() > 0:
		types.append("train")
	if pool.size() >= 2:
		types.append("feud")
	var t: String = types[randi() % types.size()]
	var ids: Array = [pool[0].id] if t != "feud" else [pool[0].id, pool[1].id]
	hero_request = {"type": t, "ids": ids, "day": day}
	_news(request_title() + ".")
	pending_toasts.append({"cls_id": "", "pool_id": "", "title": "A request", "text": request_title() + ". Answer it in the Ledger before payday."})


func _request_names() -> Array:
	var out: Array = []
	for id in hero_request.get("ids", []):
		var h := find_hero(str(id))
		out.append(h.name.split(" the ")[0] if h else "someone")
	return out


func request_title() -> String:
	if hero_request.is_empty():
		return ""
	var def: Dictionary = GameData.HERO_REQUESTS[hero_request["type"]]
	var n := _request_names()
	return str(def["title"]) % (n if hero_request["type"] == "feud" else [n[0]])


## The two answers' button texts.
func request_options() -> Array:
	var def: Dictionary = GameData.HERO_REQUESTS[hero_request["type"]]
	var n := _request_names()
	if hero_request["type"] == "feud":
		return [str(def["yes"]) % n[0], str(def["no"]) % n[1]]
	return [str(def["yes"]), str(def["no"])]


## Answers this week's request. For a feud, "yes" sides with the first hero,
## "no" with the second. Returns "" or why it can't be done.
func answer_request(yes: bool) -> String:
	if hero_request.is_empty():
		return "No request is waiting."
	var t := str(hero_request["type"])
	var def: Dictionary = GameData.HERO_REQUESTS[t]
	var hs: Array = (hero_request["ids"] as Array).map(func(id): return find_hero(str(id))).filter(func(h): return h != null)
	if hs.is_empty():
		hero_request = {}
		return ""
	var h: Hero = hs[0]
	if t == "feud":
		if hs.size() >= 2:
			var winner: Hero = hs[0] if yes else hs[1]
			var loser: Hero = hs[1] if yes else hs[0]
			change_morale(winner, int(def["yes_morale"]))
			change_morale(loser, int(def["no_morale"]))
	elif yes:
		match t:
			"week_off":
				h.busy_runs = maxi(h.busy_runs, GameData.REQUEST_LEAVE_DAYS)
			"raise":
				wage_raise[h.id] = float(wage_raise.get(h.id, 0.0)) + GameData.REQUEST_RAISE
			"gear":
				if coins < GameData.REQUEST_GEAR_COST:
					return "Not enough Gold."
				coins -= GameData.REQUEST_GEAR_COST
			"train":
				if training_left() <= 0:
					return "The Training Yard is full this week."
				if training_week != day / GameData.PAYDAY_DAYS:
					training_week = day / GameData.PAYDAY_DAYS
					trained_this_week = 0
				trained_this_week += 1
				h.attr_points += 1
		change_morale(h, int(def["yes_morale"]))
	else:
		change_morale(h, int(def["no_morale"]))
	hero_request = {}
	save()
	state_changed.emit()
	return ""


func change_morale(h: Hero, delta: int) -> void:
	h.morale = clampi(h.morale + delta, 0, 100)


## Every PAYDAY_DAYS days: wages go out (as many heroes as Gold covers, in
## roster order), the unpaid lose morale, idle heroes grow restless, and a
## hero unpaid twice running or at rock-bottom morale walks out (never one
## on a rift right now). Then the guild is compared with its rival.
func run_payday() -> void:
	if not hero_request.is_empty():
		_news("%s — no answer by payday, taken as a no." % request_title())
		answer_request(false)
	var in_rift: Array = run.get("hero_ids", []) if not run.is_empty() else []
	var paid := 0
	var unpaid: Array[String] = []
	for h in heroes:
		var w := wage_of(h)
		if coins >= w:
			coins -= w
			paid += w
			h.unpaid_weeks = 0
		else:
			h.unpaid_weeks += 1
			change_morale(h, GameData.MORALE_UNPAID)
			unpaid.append(h.name.split(" the ")[0])
		if day - h.last_rift_day >= GameData.PAYDAY_DAYS and not in_rift.has(h.id):
			change_morale(h, GameData.MORALE_IDLE_WEEK)
	# Then the facilities: unpaid upkeep costs Renown.
	var up := upkeep()
	var upkeep_paid := up <= coins
	if upkeep_paid:
		coins -= up
	elif up > 0:
		add_reputation(-GameData.UPKEEP_UNPAID_RENOWN)
	var left: Array[String] = []
	for h in heroes.duplicate():
		if in_rift.has(h.id) or heroes.size() <= 1:
			continue
		if h.unpaid_weeks >= GameData.UNPAID_WEEKS_TO_LEAVE or h.morale <= GameData.MORALE_WALKOUT:
			left.append(h.name.split(" the ")[0])
			_release(h)
	rival_ahead = 1 if reputation > rival_renown else (-1 if reputation < rival_renown else 0)
	payday_report = {"day": day, "due": paid + unpaid.size(), "paid": paid, "unpaid": unpaid, "left": left, "ahead": rival_ahead, "upkeep": up, "upkeep_paid": upkeep_paid}
	var line := "Payday: %d Gold in wages, %s." % [paid, ("%d in upkeep" % up) if upkeep_paid else "upkeep unpaid (-%d Renown)" % GameData.UPKEEP_UNPAID_RENOWN]
	if not unpaid.is_empty():
		line += " Unpaid: %s." % ", ".join(unpaid)
	if not left.is_empty():
		line += " Walked out: %s." % ", ".join(left)
	_news(line)
	_news("%s the %s (Renown %d vs %d)." % ["Your guild leads" if rival_ahead > 0 else ("The guild trails" if rival_ahead < 0 else "Your guild is level with"), rival_name, reputation, rival_renown] + (" Recruits favor you this week: +1 offer." if rival_ahead > 0 else (" Recruits favor them this week: -1 offer." if rival_ahead < 0 else "")))
	refresh_recruit_pool()
	var text := "%d Gold in wages, %s" % [paid, ("%d upkeep" % up) if upkeep_paid else "upkeep unpaid (-%d Renown)" % GameData.UPKEEP_UNPAID_RENOWN]
	if not unpaid.is_empty():
		text += " · couldn't pay %s" % ", ".join(unpaid)
	if not left.is_empty():
		text += " · %s walked out" % ", ".join(left)
	pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Payday", "text": text + "."})
	week_start_coins = coins


## A hero leaves the guild (dismissed or walked out): their gear returns to
## the stockpile.
func _release(h: Hero) -> void:
	for it in items:
		if it.equipped_to == h.id:
			it.equipped_to = ""
			it.equipped_idx = -1
	heroes.erase(h)


## Let a hero go. Not while they're on a rift, and never the last one.
func dismiss_hero(hero_id: String) -> String:
	var h := find_hero(hero_id)
	if h == null:
		return ""
	if not run.is_empty() and (run.get("hero_ids", []) as Array).has(hero_id):
		return "They're on a rift right now"
	if heroes.size() <= 1:
		return "The guild needs at least one hero"
	_release(h)
	_news("%s left the guild." % h.name.split(" the ")[0])
	save()
	state_changed.emit()
	return ""


func feast_cost() -> int:
	return GameData.FEAST_COST_PER_HERO * mini(heroes.size(), feast_seats())


func feast_ready() -> bool:
	return feast_week != day / GameData.PAYDAY_DAYS


## Once a week: Gold for +FEAST_MORALE morale for every hero.
func hold_feast() -> String:
	if not feast_ready():
		return "Already feasted this week"
	if coins < feast_cost():
		return "Not enough Gold"
	coins -= feast_cost()
	feast_week = day / GameData.PAYDAY_DAYS
	var guests: Array = heroes.duplicate()
	guests.sort_custom(func(a, b): return a.morale < b.morale)
	guests = guests.slice(0, feast_seats())
	for h in guests:
		change_morale(h, GameData.FEAST_MORALE)
	_news("A feast in the hall: +%d morale for %d hero%s%s." % [GameData.FEAST_MORALE, guests.size(), "" if guests.size() == 1 else "es", "" if guests.size() == heroes.size() else " (no seats for %d)" % (heroes.size() - guests.size())])
	save()
	state_changed.emit()
	return ""


## The rival's day: it gains Renown (more each act) and now and then takes a
## posted contract off the board before you can.
func rival_day() -> void:
	var span: Array = GameData.RIVAL_DAILY_RENOWN[mini(3, campaign_act)]
	rival_renown += int(span[0]) + randi() % (int(span[1]) - int(span[0]) + 1)
	if randf() < GameData.RIVAL_SNATCH_CHANCE:
		var posted: Array = guild_board.filter(func(q): return str(q["status"]) == "posted")
		if not posted.is_empty():
			var q: Dictionary = posted[randi() % posted.size()]
			guild_board.erase(q)
			_news("%s took the contract: %s." % [rival_name, quest_desc(q)])
	if randf() < GameData.RIVAL_TAUNT_CHANCE:
		_news("%s of %s: \"%s\"" % [rival_leader()["leader"], rival_name, str(GameData.RIVAL_TAUNTS[randi() % GameData.RIVAL_TAUNTS.size()]) % guild_name])
	# This month's contest.
	if contest_seals_start < 0:
		contest_seals_start = rifts_sealed
		rival_contest_seals = 0
	if randf() < float(GameData.RIVAL_SEAL_CHANCE[clampi(campaign_act, 1, 3)]):
		rival_contest_seals += 1
	if day % GameData.CONTEST_DAYS == 0:
		_end_contest()


## The rival's leader: {leader, portrait (path), crest (path)}.
func rival_leader() -> Dictionary:
	var d: Dictionary = GameData.RIVAL_LEADERS.get(rival_name, {"leader": "Their captain", "portrait": "footman", "crest": 1})
	return {"leader": d["leader"], "portrait": GameData.portrait_for_hero("", str(d["portrait"])), "crest": GameData.CREST_PATH[int(d["crest"]) % GameData.CREST_PATH.size()]}


## This month's contest: {ours, theirs, days_left}.
func contest_status() -> Dictionary:
	var ours := rifts_sealed - contest_seals_start if contest_seals_start >= 0 else 0
	return {"ours": ours, "theirs": rival_contest_seals, "days_left": GameData.CONTEST_DAYS - (day % GameData.CONTEST_DAYS)}


## The month is up: whoever sealed more rifts takes the prize (a tie, nobody).
func _end_contest() -> void:
	var c := contest_status()
	var ours: int = c["ours"]
	var theirs: int = c["theirs"]
	if ours > theirs:
		coins += int(GameData.CONTEST_PRIZE["coins"])
		add_reputation(int(GameData.CONTEST_PRIZE["reputation"]))
		_news("You won the month's contest, %d rifts to %d: +%d Gold, +%d Renown." % [ours, theirs, GameData.CONTEST_PRIZE["coins"], GameData.CONTEST_PRIZE["reputation"]])
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Contest won", "text": "%d rifts sealed to %s's %d. +%d Gold, +%d Renown." % [ours, rival_name, theirs, GameData.CONTEST_PRIZE["coins"], GameData.CONTEST_PRIZE["reputation"]]})
	elif theirs > ours:
		rival_renown += int(GameData.CONTEST_PRIZE["reputation"])
		_news("%s won the month's contest, %d rifts to your %d." % [rival_name, theirs, ours])
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Contest lost", "text": "%s sealed %d rifts to your %d and takes the prize." % [rival_name, theirs, ours]})
	else:
		_news("The month's contest ends level at %d rifts each." % ours)
	contest_seals_start = rifts_sealed
	rival_contest_seals = 0


## The Guild Standings, best Renown first: your guild, the rival, and three
## more guilds whose Renown, Tower floor and Endless time grow each day
## (deterministic, so they don't jump around between looks).
## [{name, renown, tower, endless, you}].
func guild_standings() -> Array:
	var rows: Array = [{"name": guild_name, "renown": reputation, "tower": tower_best, "endless": best_endless_time, "you": true},
		{"name": rival_name, "renown": rival_renown, "tower": mini(100, int(day * 0.55)), "endless": mini(1500, day * 11), "you": false}]
	var others: Array = GameData.RIVAL_NAMES.filter(func(n): return n != rival_name).slice(0, GameData.STANDING_STRENGTH.size())
	for k in others.size():
		var st: float = GameData.STANDING_STRENGTH[k]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(["standings", others[k]])
		var pace := st * (0.8 + 0.4 * rng.randf())
		rows.append({"name": others[k], "renown": int(day * 0.9 * pace), "tower": mini(100, int(day * 0.5 * pace)), "endless": mini(1500, int(day * 10.0 * pace)), "you": false})
	rows.sort_custom(func(a, b): return int(a["renown"]) > int(b["renown"]) or (int(a["renown"]) == int(b["renown"]) and a["you"]))
	return rows

