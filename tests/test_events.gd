extends "res://tests/base_test.gd"
## Rift events: all 24 are well-formed, every choice resolves, attribute
## checks scale with the party, and a run doesn't repeat an event.

const KEYS := ["coins", "crystals", "reputation", "xp_all", "heal_pct", "hurt_pct", "ready", "loot", "item", "relic", "tokens", "tonic", "shield"]


func _keys_ok(e: Dictionary) -> bool:
	return e.keys().all(func(k): return KEYS.has(k))


func run() -> void:
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "T"
	check(GameData.RIFT_EVENTS.size() == 24, "24 events (%d)" % GameData.RIFT_EVENTS.size())
	var ids := {}
	for ev in GameData.RIFT_EVENTS:
		ids[ev["id"]] = true
		for c in ev["choices"]:
			var ok := true
			if c.has("check"):
				ok = GameData.ATTR_LABEL.has(c["check"]["attr"]) and _keys_ok(c["check"]["win"]) and _keys_ok(c["check"]["lose"])
			elif c.has("gamble"):
				ok = _keys_ok(c["gamble"]["win"]) and _keys_ok(c["gamble"]["lose"])
			else:
				ok = _keys_ok(c.get("effect", {}))
			check(ok, "%s / %s uses known effects" % [ev["id"], c["label"]])
	check(ids.size() == 24, "event ids are unique")

	var hids: Array[String] = []
	for i in 3:
		var h := Combat.gen_hero("C", 8)
		h.id = "h%d" % GameState.next_id
		GameState.next_id += 1
		GameState.heroes.append(h)
		hids.append(h.id)
	GameState.runs_started = 3
	GameState.coins = 1000
	GameState.start_run("lesser", hids, null, false, false)
	# Every choice of every event resolves without error.
	for ev in GameData.RIFT_EVENTS:
		for ci in (ev["choices"] as Array).size():
			GameState.run["node_state"] = {"type": "event", "event": ev, "resolved": false}
			GameState.resolve_event(ci)
			check(bool(GameState.run["node_state"].get("resolved", false)) and not (GameState.run["node_state"].get("log", []) as Array).is_empty(), "%s choice %d resolves" % [ev["id"], ci])
	# Checks: a strong attribute raises the chance; Greater rifts are harder.
	var chk := {"attr": "might", "target": 9, "win": {}, "lose": {}}
	for hid in hids:
		GameState.find_hero(hid).attrs["might"] = 5
	GameState.current_champion.attrs["might"] = 5
	var c0 := float(GameState.event_check(chk)["chance"])
	GameState.find_hero(hids[0]).attrs["might"] = 30
	check(float(GameState.event_check(chk)["chance"]) > c0 and float(GameState.event_check(chk)["chance"]) <= 0.95, "a strong hero raises the check chance (capped)")
	var t_lesser := int(GameState.event_check(chk)["target"])
	GameState.run["diff_id"] = "greater"
	GameState.find_hero(hids[0]).attrs["might"] = 5
	check(int(GameState.event_check(chk)["target"]) == t_lesser + 3, "Greater rifts raise the target")
	GameState.run["diff_id"] = "lesser"
	var lv0 := int(GameState.event_check(chk)["target"])
	for h in GameState.current_party():
		h.level += 4
	check(int(GameState.event_check(chk)["target"]) > lv0, "the target rises with party level")
	# No repeats within a run.
	GameState.run["events_seen"] = []
	var seen := {}
	for i in 24:
		GameState.run["node_state"] = {}
		GameState.ensure_event()
		seen[str(GameState.run["node_state"]["event"]["id"])] = true
	check(seen.size() == 24, "24 events in a row never repeat within a run")
	GameState.finish_run()
