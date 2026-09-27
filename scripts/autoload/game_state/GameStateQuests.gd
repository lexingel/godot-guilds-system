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
	return int(round(float(GameData.WAGE_BY_RANK.get(h.rank, 15)) * (1.0 + GameData.WAGE_PER_LEVEL * (h.level - 1))))


func weekly_wages() -> int:
	var total := 0
	for h in heroes:
		total += wage_of(h)
	return total


func days_to_payday() -> int:
	return GameData.PAYDAY_DAYS - (day % GameData.PAYDAY_DAYS)


func change_morale(h: Hero, delta: int) -> void:
	h.morale = clampi(h.morale + delta, 0, 100)


## Every PAYDAY_DAYS days: wages go out (as many heroes as Gold covers, in
## roster order), the unpaid lose morale, idle heroes grow restless, and a
## hero unpaid twice running or at rock-bottom morale walks out (never one
## on a rift right now). Then the guild is compared with its rival.
func run_payday() -> void:
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
	var left: Array[String] = []
	for h in heroes.duplicate():
		if in_rift.has(h.id) or heroes.size() <= 1:
			continue
		if h.unpaid_weeks >= GameData.UNPAID_WEEKS_TO_LEAVE or h.morale <= GameData.MORALE_WALKOUT:
			left.append(h.name.split(" the ")[0])
			_release(h)
	rival_ahead = 1 if reputation > rival_renown else (-1 if reputation < rival_renown else 0)
	payday_report = {"day": day, "due": paid + unpaid.size(), "paid": paid, "unpaid": unpaid, "left": left, "ahead": rival_ahead}
	var line := "Payday: %d Gold in wages." % paid
	if not unpaid.is_empty():
		line += " Unpaid: %s." % ", ".join(unpaid)
	if not left.is_empty():
		line += " Walked out: %s." % ", ".join(left)
	_news(line)
	_news("%s the %s (Renown %d vs %d)." % ["Your guild leads" if rival_ahead > 0 else ("The guild trails" if rival_ahead < 0 else "Your guild is level with"), rival_name, reputation, rival_renown] + (" Recruits favor you this week: +1 offer." if rival_ahead > 0 else (" Recruits favor them this week: -1 offer." if rival_ahead < 0 else "")))
	refresh_recruit_pool()
	var text := "%d Gold in wages" % paid
	if not unpaid.is_empty():
		text += " · couldn't pay %s" % ", ".join(unpaid)
	if not left.is_empty():
		text += " · %s walked out" % ", ".join(left)
	pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Payday", "text": text + "."})


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
	return GameData.FEAST_COST_PER_HERO * heroes.size()


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
	for h in heroes:
		change_morale(h, GameData.FEAST_MORALE)
	_news("A feast in the hall: +%d morale for everyone." % GameData.FEAST_MORALE)
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

