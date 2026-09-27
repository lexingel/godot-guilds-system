extends "res://scripts/autoload/game_state/GameStateItems.gd"
## GameState, part 4: the Guild Board, reputation and milestones.


# ---------------- Quests: Guild Board (Contracts + Dailies) & Milestones ----------------
## Every Reputation gain routes through here so crossing a 20-point tier can
## auto-arm a Shop Boost (an Epic at the next rift shop) —
## Reputation losses (none exist yet, but kept symmetrical) skip the roll.
func add_reputation(amount: int) -> void:
	if amount <= 0:
		reputation += amount
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
	if rift_map.any(func(sl): return sl.has("rank") and sl.has("uid")):
		types.append_array(["seal_map", "seal_map"])
	if greater_rift_unlocked():
		types.append("seal_greater")
	if rifts_sealed >= 1:
		types.append("trial_hardcore")
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
		"seal_map":
			var slots := rift_map.filter(func(sl): return sl.has("rank") and sl.has("uid"))
			var sl: Dictionary = slots[randi() % slots.size()]
			q["param"] = str(sl["uid"])
			q["rank"] = str(sl["rank"])
			var ri := GameData.rift_rank_index(q["rank"])
			q["diff"] = 1 if ri <= 1 else (2 if ri <= 3 else 3)
		"seal_rank":
			var r: int = clampi(max(best_rift_rank_sealed, 0) + randi() % 2, 1, 5)
			q["param"] = str(GameData.RIFT_RANKS[r]["id"])
			q["diff"] = 2 if r <= 3 else 3
		"seal_greater":
			q["diff"] = 3
		"trial_small":
			q["diff"] = 2
		"trial_flawless", "trial_hardcore":
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
		"seal_map": return _tally("map:" + str(q["param"]))
		"seal_rank":
			var n := 0
			for i in range(GameData.rift_rank_index(str(q["param"])), GameData.RIFT_RANKS.size()):
				n += _tally("rank_seals:%d" % i)
			return n
		"seal_greater": return _tally("greater_seals")
		"trial_small": return _tally("small_seals")
		"trial_flawless": return _tally("flawless_rifts")
		"trial_hardcore": return _tally("hardcore_seals")
		"craft": return crafts_performed
		"flawless_win": return flawless_wins
	return 0


func quest_progress(q: Dictionary) -> int:
	if str(q.get("status", "")) != "active":
		return 0
	return min(int(q["target"]), max(0, _quest_current(q) - int(q.get("baseline", 0))))


## Seeds a fresh board (new guild, or a save from the old contract/daily
## board), refreshes postings when their days are up, and fails any quest
## whose Rift Map rift broke open before it was sealed.
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
	for q in guild_board:
		if str(q["type"]) == "seal_map" and str(q["status"]) != "failed" and _tally("map:" + str(q["param"])) == 0 \
				and not rift_map.any(func(sl): return str(sl.get("uid", "")) == str(q["param"])) \
				and not (not run.is_empty() and str(run.get("map_uid", "")) == str(q["param"])):
			q["status"] = "failed"
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
		"seal_map": return "Seal: close the Rank %s rift on the Rift Map before it breaks" % q.get("rank", "?")
		"seal_rank": return "Seal: seal a Rank %s+ Rift Map rift" % q["param"]
		"seal_greater": return "Seal: seal a Greater Rift"
		"trial_small": return "Trial: seal a rift with 2 heroes or fewer (plus the Champion)"
		"trial_flawless": return "Trial: seal a rift without any hero going down"
		"trial_hardcore": return "Trial: seal a rift in Hardcore Mode"
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
