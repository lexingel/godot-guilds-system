extends "res://scripts/autoload/game_state/GameStateModes.gd"
## GameState, part 6: rift runs — nodes, fights, events, shops, hazards, sealing, recovery, the Endless Rift payout.


## `rift_rank` is a ladder rank (start_ladder_rift) or "" for unranked runs
## (daily, finale). relic_rarity_floor_down is read by Party Assembly's
## starting-relic roll, which happens before the run exists.
func start_run(diff_id: String, hero_ids: Array[String], starting_relic: Relic, rift_rank: String = "") -> void:
	var shield := 0
	for r in Combat.equipped_relics():
		shield += r.hp
	if starting_relic:
		shield += starting_relic.hp
		starting_relic.id = "rl" + str(next_id)
		next_id += 1
		starting_relic.equipped = false
		relics.append(starting_relic)
	var diff: Dictionary = GameData.DIFFICULTIES[0]
	for d in GameData.DIFFICULTIES:
		if d["id"] == diff_id:
			diff = d
	diff = _apply_rift_rank_modifiers(diff, rift_rank)
	var training := runs_started == 0 and rift_rank in ["", "F"]
	if training:
		diff = _apply_training(diff)
	runs_started += 1
	run = {
		"diff_id": diff_id,
		"layers": Combat.build_layers(diff), "pos": 0, "chosen": {},
		"hero_ids": hero_ids, "shield": shield, "boss_rounds": 0,
		"node_kind": "", "node_state": {}, "sealed": null, "anchor_used": false,
		"start_coins": coins, "start_crystals": crystals, "heroes_lost": 0,
		"rift_rank": rift_rank, "seed": randi(), "training": training, "biome": pick_biome(),
		"overseer": overseer if champions.has(overseer) else "",
	}
	if training:
		# No elites in the training rift — a campfire takes their place.
		for layer in run["layers"]:
			layer["options"] = (layer["options"] as Array).map(func(o): return "campfire" if o == "elite" else o)
	auto_resolve_single_option()
	save()
	state_changed.emit()


## The rift rank newly generated items drop at (GameData.ITEM_RANK_MULT): a
## ladder rift's own rank; an unranked Greater run reads as C; Lesser and
## anything outside a run (shop restock etc.) is F.
func loot_rank() -> String:
	if run.is_empty():
		return "F"
	var mapped: String = str(run.get("rift_rank", ""))
	if mapped != "":
		return mapped
	if run.get("diff_id", "") == "greater":
		return "C"
	return "F"


## Announces each feature the first time it unlocks (once per render, like
## check_milestones). Returns the ids newly announced.
func check_feature_unlocks() -> Array:
	var fresh: Array = []
	for f in GameData.FEATURE_UNLOCKS:
		if not features_seen.has(f) and feature_unlocked(f):
			features_seen.append(f)
			fresh.append(f)
	if fresh.size() == 1:
		var def: Dictionary = GameData.FEATURE_UNLOCKS[fresh[0]]
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": tr("New: %s") % tr(str(def["name"])), "text": str(def["news"])})
	elif fresh.size() > 1:
		# Several at once (e.g. the first seal): one toast, not a stack.
		pending_toasts.append({"cls_id": "", "pool_id": "", "title": tr("New at camp"), "text": ", ".join(fresh.map(func(f): return tr(str(GameData.FEATURE_UNLOCKS[f]["name"])))) + tr(" — check the tabs above.")})
	if not fresh.is_empty():
		save()
	return fresh


func hint_pending(id: String) -> bool:
	return not tips_off and not hints_seen.has(id)


func _see_hint(id: String) -> void:
	if not hints_seen.has(id):
		hints_seen.append(id)


func dismiss_hint(id: String) -> void:
	if not hints_seen.has(id):
		hints_seen.append(id)
	save()


func current_layer_options() -> Array:
	var layers: Array = run["layers"]
	return layers[int(run["pos"])]["options"]


func auto_resolve_single_option() -> void:
	var options := current_layer_options()
	var chosen: Dictionary = run["chosen"]
	if options.size() == 1 and not chosen.has(int(run["pos"])):
		choose_node_type(options[0])


func choose_node_type(kind: String) -> void:
	var chosen: Dictionary = run["chosen"]
	chosen[int(run["pos"])] = kind
	run["chosen"] = chosen
	run["node_kind"] = kind
	run["node_state"] = {}
	save()
	state_changed.emit()


func current_node_kind() -> String:
	var chosen: Dictionary = run.get("chosen", {})
	return chosen.get(int(run.get("pos", 0)), "")


## Rolls the battle backdrop the moment a fresh combat node is stood on
## (called from the pre-engage screen), rather than leaving it to
## Combat.start_combat() at Engage time — so the "encounter awaits" screen
## and the arena you fight in are the same room instead of a jarring swap.
func ensure_combat_bg() -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.has("bg_idx") or ns.has("combat_state"):
		return
	var bgs: Array = GameData.BIOMES.get(run_biome(), {}).get("backgrounds", [])
	ns["bg_idx"] = int(bgs[randi() % bgs.size()]) if not bgs.is_empty() else randi() % GameData.BATTLE_BACKGROUNDS.size()
	run["node_state"] = ns


func engage_node() -> void:
	var diff := _diff()
	var party: Array[Hero] = []
	party.assign(current_party().filter(func(h): return not h.is_downed() and h.hp > 0))
	if party.is_empty():
		return
	var kind := current_node_kind()
	if run.has("tower"):
		for h in party:
			h.hp = Combat.max_hp(h)
	seed(hash([int(run.get("seed", 0)), int(run["pos"])]))
	var state := Combat.start_combat(party, kind, diff, int(run["pos"]))
	randomize()
	var prior_bg_idx := int(run["node_state"].get("bg_idx", -1))
	if prior_bg_idx >= 0:
		state["background_idx"] = prior_bg_idx
	for m in state["monsters"]:
		# Boss names are generated as "Vaelith, Lesser Warden" — split off the
		# difficulty suffix so the same boss counts as seen regardless of tier.
		var mname := str(m["name"]).split(",")[0]
		if not monsters_seen.has(mname):
			monsters_seen.append(mname)
	# bg_idx stays alongside so a reload mid-fight (which drops combat_state)
	# brings back the same arena.
	run["node_state"] = {"type": "combat", "combat_state": state, "reward_chosen": false, "bg_idx": int(state.get("background_idx", prior_bg_idx))}
	save()
	state_changed.emit()


## Quick fight: engages the node and plays it out instantly with the auto
## policy (Combat.auto_action), landing straight on the result screen.
func quick_fight() -> void:
	engage_node()
	var st: Dictionary = run.get("node_state", {}).get("combat_state", {})
	if not st.is_empty():
		st["auto_used"] = true   # played by the auto policy: no hand-played bonus
	for i in 600:
		if st.is_empty() or run.get("node_state", {}).has("result"):
			break
		var nxt := Combat.peek_next_turn(st)
		if str(nxt["type"]) == "hero":
			var h := Combat._find_party_hero(st["party"], str(nxt["id"]))
			if h and h.hp > 0:
				st["pending_actions"][h.id] = Combat.auto_action(st, h)
		resolve_turn_now()


## Sets one hero's pending action for the round about to resolve — a pure
## "what will they do" toggle, no combat math, mirrors how e.g.
## choose_node_type() just records a choice.
## `target` is a monster index into state["monsters"], meaningful only for
## "attack" — ignored (but still stored, harmlessly) for "ability"/"defend".
## Party Assembly's Front/Back toggle — checks the roster first, then the
## Champion (find_hero only searches `heroes`, and the Champion needs this
## toggle too since their row has no other picker interaction).
func set_hero_formation(hero_id: String, formation: String) -> void:
	var h := find_hero(hero_id)
	if not h:
		return
	h.formation = formation
	save()
	state_changed.emit()


## `ally_id` is the hero a "guard" action protects.
func set_hero_action(hero_id: String, action: String, target: int = 0, ally_id: String = "") -> void:
	var ns: Dictionary = run.get("node_state", {})
	var state: Dictionary = ns.get("combat_state", {})
	if state.is_empty():
		return
	var pending: Dictionary = state["pending_actions"]
	pending[hero_id] = {"action": action, "target": target, "ally": ally_id}
	if run.get("training", false):
		if action == "attack":
			_see_hint("tut_attack")
		elif (action == "ability" or action.begins_with("skill:")) and Combat.action_block(state, find_hero(hero_id), action) == "":
			_see_hint("tut_skill")
		elif action in ["defend", "guard"] and (state["monsters"] as Array).any(func(m): return m.get("_winding", false) or m.get("_charged", false)):
			_see_hint("tut_windup")
	save()
	state_changed.emit()


func _apply_combat_outcome(outcome: Dictionary) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var state: Dictionary = ns.get("combat_state", {})
	if outcome["done"]:
		var result: Dictionary = outcome["result"]
		var tally := ("auto" if state.get("auto_used", false) else "hand") + ("_w" if result["won"] else "_l")
		session[tally] = int(session.get(tally, 0)) + 1
		if not result["won"] and not bool(result.get("retreated", false)):
			result["defeat_reasons"] = Combat.defeat_reasons(state)
		if run.has("tower"):
			# The Tower pays per floor (first clear), not per fight.
			result["reward_options"] = []
			result["bonus_crystal"] = 0
			if result["won"]:
				result["tower"] = _complete_tower_floor(int(run["tower"]))
		var kind := current_node_kind()
		if result["won"]:
			coins += int(result["coin"])
			crystals += int(result["crystal"]) + int(result["bonus_crystal"])
			_attune_gear(state.get("party", []))
			if kind == "boss":
				run["boss_rounds"] = int(result["rounds"])
				var bname := str(result["monster_name"]).split(",")[0]
				if not bosses_defeated.has(bname):
					bosses_defeated.append(bname)
				bosses_won += 1
				_bump("boss:" + bname)
			elif kind == "elite":
				elites_won += 1
				if not run.has("tower"):
					result["boon_offer"] = roll_boon_offer()
			# Quest tallies — every monster in a won fight is by definition dead,
			# so state["monsters"] (still the pre-cleanup fight roster) is a
			# reliable "what did we just kill" list.
			for m in state.get("monsters", []):
				var mname := str(m.get("name", ""))
				if mname != "":
					monster_kill_counts[mname] = int(monster_kill_counts.get(mname, 0)) + 1
			var flawless := true
			for h in state.get("party", []):
				if h.hp <= 0:
					flawless = false
					break
			if flawless:
				flawless_wins += 1
				# Played by hand (no Auto) with no one down: a bonus on top.
				if not state.get("auto_used", false) and not run.has("tower"):
					result["hand_bonus"] = maxi(1, int(round(int(result["coin"]) * GameData.HAND_BONUS)))
					coins += int(result["hand_bonus"])
					# Essence too: it's the currency a guild runs short of.
					result["hand_bonus_ess"] = maxi(1, int(round(int(result["crystal"]) * GameData.HAND_BONUS)))
					crystals += int(result["hand_bonus_ess"])
			# An escort NPC (start_combat's ~25% chance on a "combat" node) pays
			# out a small bonus only if it survived the whole fight — dying
			# mid-fight is a softer failure than a party wipe, so it never
			# affects the fight's own win/loss.
			if kind != "boss" and not run.has("tower"):
				_note_injuries("critical" if kind == "elite" else "wounded")
			var escort: Dictionary = state.get("escort", {})
			if not escort.is_empty() and float(escort.get("hp", 0.0)) > 0.0:
				add_reputation(2)
				crystals += 1
				result["escort_saved"] = str(escort["name"])
		# Hero history (kills/knockouts are tallied inside Combat as they
		# happen; boss/elite wins are only known here) and any traits it earns.
		if result["won"] and kind in ["boss", "elite"]:
			for h in state.get("party", []):
				h.history[kind + "_kills"] = int(h.history.get(kind + "_kills", 0)) + 1
		var earned: Array[String] = []
		for h in state.get("party", []):
			earned.append_array(check_earned_quirks(h))
		if not earned.is_empty():
			result["flavor"] = (str(result.get("flavor", "")) + " " + " ".join(earned)).strip_edges()
		ns["result"] = result
	run["node_state"] = ns
	save()
	state_changed.emit()


## Resolves whichever actor's turn is next (see Combat.resolve_turn — a
## living hero's pending action, or a living monster's retaliation). Once it
## reports the fight done, applies the same roster-level bookkeeping
## engage_node used to do in one shot (coin/crystal gain, boss_rounds
## tracking).
func resolve_turn_now() -> void:
	var ns: Dictionary = run.get("node_state", {})
	var state: Dictionary = ns.get("combat_state", {})
	if state.is_empty():
		return
	_apply_combat_outcome(Combat.resolve_turn(state))


## Ends the current fight by player choice, forfeiting rewards — heroes keep
## whatever HP they currently have, no one is downed or removed.
func combat_retreat() -> void:
	var ns: Dictionary = run.get("node_state", {})
	var state: Dictionary = ns.get("combat_state", {})
	if state.is_empty():
		return
	_apply_combat_outcome(Combat.retreat_combat(state))


func pick_combat_reward(idx: int) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var result: Dictionary = ns.get("result", {})
	var options: Array = result.get("reward_options", [])
	if ns.get("reward_chosen", false) or idx < 0 or idx >= options.size():
		return
	var opt: Dictionary = options[idx]
	if opt["loot_type"] == "item":
		var it: Item = opt["obj"]
		it.id = "it" + str(next_id)
		next_id += 1
		items.append(it)
	else:
		var r: Relic = opt["obj"]
		r.id = "rl" + str(next_id)
		next_id += 1
		r.equipped = Combat.equipped_relics().size() < relic_slot_cap()
		relics.append(r)
	ns["reward_chosen"] = true
	save()
	state_changed.emit()


# ---------------- Campfire / event / treasure nodes ----------------

## Campfire: one of Rest (heal), Train (XP) or Sharpen (abilities ready).
func campfire_choose(choice: String) -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.get("resolved", false):
		return
	var party := current_party().filter(func(h): return h.hp > 0)
	var log: Array[String] = []
	match choice:
		"rest":
			for h in party:
				h.hp = min(Combat.max_hp(h), h.hp + int(ceil(Combat.max_hp(h) * GameData.CAMPFIRE_HEAL_PCT)))
			log.append(tr("The party rests by the fire and recovers %d%% HP.") % int(GameData.CAMPFIRE_HEAL_PCT * 100))
		"train":
			for h in party:
				Combat.gain_xp(h, GameData.CAMPFIRE_TRAIN_XP)
			log.append(tr("The party drills together: +%d XP each.") % GameData.CAMPFIRE_TRAIN_XP)
		"sharpen":
			run["momentum_bonus"] = int(run.get("momentum_bonus", 0)) + 4
			log.append(tr("Weapons sharpened, focus restored — the next fight starts with +4 Momentum."))
	ns["type"] = "campfire"
	ns["resolved"] = true
	ns["log"] = log
	run["node_state"] = ns
	save()
	state_changed.emit()


func ensure_event() -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.has("event"):
		return
	ns["type"] = "event"
	var seen: Array = run.get("events_seen", [])
	# Region events ("biome") only happen in their region.
	var here: Array = GameData.RIFT_EVENTS.filter(func(e): return str(e.get("biome", run_biome())) == run_biome())
	var fresh: Array = here.filter(func(e): return not seen.has(e["id"]))
	if fresh.is_empty():
		fresh = here
	ns["event"] = fresh[randi() % fresh.size()]
	seen.append(str(ns["event"]["id"]))
	run["events_seen"] = seen
	ns["resolved"] = false
	run["node_state"] = ns


func can_afford(cost: Dictionary) -> bool:
	return coins >= int(cost.get("coins", 0)) and crystals >= int(cost.get("crystals", 0))


func resolve_event(choice_idx: int) -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.get("resolved", false) or not ns.has("event"):
		return
	var choices: Array = ns["event"]["choices"]
	if choice_idx < 0 or choice_idx >= choices.size():
		return
	var c: Dictionary = choices[choice_idx]
	var cost: Dictionary = c.get("cost", {})
	if not can_afford(cost):
		return
	coins -= int(cost.get("coins", 0))
	crystals -= int(cost.get("crystals", 0))
	var log: Array[String] = []
	if c.has("check"):
		var chk: Dictionary = c["check"]
		var info := event_check(chk)
		var passed := randf() < float(info["chance"])
		log.append(tr("%s check (%s, %d vs %d): %s.") % [tr(str(GameData.ATTR_LABEL[chk["attr"]])), tr(str(info["hero"])), int(info["value"]), int(info["target"]), tr(str("passed" if passed else "failed"))])
		log.append_array(_apply_event_effect(chk["win"] if passed else chk["lose"]))
	elif c.has("gamble"):
		var g: Dictionary = c["gamble"]
		var won := randf() < float(g["chance"])
		log.append(tr("Luck is with you.") if won else tr("Luck is not with you."))
		log.append_array(_apply_event_effect(g["win"] if won else g["lose"]))
	else:
		log.append_array(_apply_event_effect(c.get("effect", {})))
	if log.is_empty():
		log.append(tr("You move on."))
	ns["resolved"] = true
	ns["log"] = log
	run["node_state"] = ns
	save()
	state_changed.emit()


## An event attribute check: the party member with the best score, that
## score, the target, and the chance to pass.
func event_check(chk: Dictionary) -> Dictionary:
	var attr := str(chk["attr"])
	var party := current_party().filter(func(h): return h.hp > 0)
	var avg_lv := 1.0
	if not party.is_empty():
		avg_lv = party.reduce(func(acc, h): return acc + h.level, 0) / float(party.size())
	# Attributes grow ~3 points a level, so the bar rises with the party.
	var target := int(chk["target"]) + int(round(GameData.EVENT_CHECK_PER_LEVEL * avg_lv)) + (0 if str(run.get("diff_id", "lesser")) == "lesser" and str(run.get("rift_rank", "")) == "" else 3)
	var best: Hero = null
	for h in current_party():
		if h.hp > 0 and (best == null or Combat.hero_attr(h, attr) > Combat.hero_attr(best, attr)):
			best = h
	var value := Combat.hero_attr(best, attr) if best else GameData.ATTR_BASELINE
	var chance := clampf(GameData.EVENT_CHECK_BASE + GameData.EVENT_CHECK_PER_POINT * (value - target), 0.1, 0.95)
	return {"hero": best.name.split(" the ")[0] if best else "nobody", "value": value, "target": target, "chance": chance}


func _event_amount(v) -> int:
	return randi_range(int(v[0]), int(v[1])) if v is Array else int(v)


func _apply_event_effect(e: Dictionary) -> Array[String]:
	var log: Array[String] = []
	var party := current_party().filter(func(h): return h.hp > 0)
	if e.has("coins"):
		var n := _event_amount(e["coins"])
		coins += n
		log.append(tr("+%d Gold.") % n)
	if e.has("crystals"):
		var n2 := _event_amount(e["crystals"])
		crystals += n2
		log.append(tr("+%d Essence.") % n2)
	if e.has("reputation"):
		var r := int(e["reputation"])
		add_reputation(r)
		log.append(tr("%+d Renown.") % r)
	if e.has("xp_all"):
		for h in party:
			Combat.gain_xp(h, int(e["xp_all"]))
		log.append(tr("Every hero gains %d XP.") % int(e["xp_all"]))
	if e.has("heal_pct"):
		for h in party:
			h.hp = min(Combat.max_hp(h), h.hp + int(ceil(Combat.max_hp(h) * float(e["heal_pct"]))))
		log.append(tr("The party heals %d%% HP.") % int(float(e["heal_pct"]) * 100))
	if e.has("hurt_pct"):
		for h in party:
			h.hp = max(1, h.hp - int(ceil(Combat.max_hp(h) * float(e["hurt_pct"]))))
		log.append(tr("Everyone loses %d%% HP.") % int(float(e["hurt_pct"]) * 100))
	if e.get("ready", false):
		run["momentum_bonus"] = int(run.get("momentum_bonus", 0)) + 3
		log.append(tr("The next fight starts with +3 Momentum."))
	if e.has("tonic"):
		var add := add_tonic("healing", int(e["tonic"]))
		log.append(tr("+%d Healing Tonic.") % add if add > 0 else tr("You can't carry another tonic."))
	if e.has("shield"):
		run["shield"] = int(run.get("shield", 0)) + int(e["shield"])
		log.append(tr("A %d-point shield against hazards.") % int(e["shield"]))
	for kind in ["item", "relic"]:
		if e.has(kind):
			var rr := Combat.weighted_rarity()
			if _rarity_order(rr) < _rarity_order(str(e[kind])):
				rr = str(e[kind])
			var lt: Dictionary = {"loot_type": "item", "obj": Combat.gen_item(rr)} if kind == "item" else {"loot_type": "relic", "obj": Combat.gen_relic(rr)}
			_grant_loot(lt)
			log.append(tr("You receive: %s (%s).") % [tr(str(lt["obj"].name)), tr(str(rr.capitalize()))])
	if e.has("loot"):
		var rarity := Combat.weighted_rarity()
		if _rarity_order(rarity) < _rarity_order(str(e["loot"])):
			rarity = str(e["loot"])
		var loot: Dictionary = Combat.gen_loot(rarity)
		_grant_loot(loot)
		log.append(tr("You receive: %s (%s).") % [tr(str(loot["obj"].name)), tr(str(rarity.capitalize()))])
	return log


func _rarity_order(r: String) -> int:
	return ["common", "rare", "epic", "legendary"].find(r)


## Adds a rolled loot entry ({loot_type, obj}) to the guild's stash.
func _grant_loot(loot: Dictionary) -> void:
	if loot["loot_type"] == "item":
		var it: Item = loot["obj"]
		it.id = "it" + str(next_id)
		next_id += 1
		items.append(it)
	else:
		var r: Relic = loot["obj"]
		r.id = "rl" + str(next_id)
		next_id += 1
		r.equipped = Combat.equipped_relics().size() < relic_slot_cap()
		relics.append(r)


## Treasure: pick one of two loot drops, no fight.
func ensure_treasure() -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.has("options"):
		return
	ns["type"] = "treasure"
	ns["options"] = [Combat.gen_loot(Combat.weighted_rarity()), Combat.gen_loot(Combat.weighted_rarity())]
	ns["picked"] = false
	run["node_state"] = ns


func pick_treasure(idx: int) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var options: Array = ns.get("options", [])
	if ns.get("picked", false) or idx < 0 or idx >= options.size():
		return
	_grant_loot(options[idx])
	ns["picked"] = true
	save()
	state_changed.emit()


func ensure_hazard() -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.has("hazard"):
		return
	# A mapped rift's "hazard_severity_up" modifier (0-2) biases the roll
	# toward worse hazards by filtering out the mildest ones first, rather
	# than reordering HAZARD_TYPES itself — falls back to the full list if
	# filtering would leave nothing (never happens at today's 3 severity
	# steps against 5 hazard types spanning dmg_mult 0.8-1.3, but kept safe).
	var severity_up := int(_diff().get("hazard_severity_up", 0))
	var min_mult: float = [0.0, 1.0, 1.2][clampi(severity_up, 0, 2)]
	var eligible: Array = GameData.HAZARD_TYPES.filter(func(h): return float(h["dmg_mult"]) >= min_mult)
	if eligible.is_empty():
		eligible = GameData.HAZARD_TYPES
	var hz: Dictionary = eligible[randi() % eligible.size()]
	ns["hazard"] = hz
	ns["resolved"] = false
	run["node_state"] = ns
	var hz_id := str(hz["id"])
	if not hazards_seen.has(hz_id):
		hazards_seen.append(hz_id)


## Shared core for all 3 hazard choices — `dmg_scale` multiplies the normal
## damage roll (1.0 = unchanged), `bonus_chance_override` replaces the
## hazard's own bonus_chance when >= 0.0 (a negative value means "use the
## hazard's own chance unmodified").
## What a hazard choice would do, without doing it: the hazard's damage is
## fixed (no roll), so this is exact. `dmg_scale` is 1.0 to push through, 2.0
## to risk it. {anchor, total, absorbed, per_hero, downs: [hero names]}.
## _apply_hazard uses the same numbers, so the preview can't drift from it.
func hazard_preview(dmg_scale: float) -> Dictionary:
	ensure_hazard()
	var party: Array[Hero] = []
	party.assign(current_party().filter(func(h): return not h.is_downed() and h.hp > 0))
	if not run.get("anchor_used", false) and anchor_artifact():
		return {"anchor": true, "total": 0, "absorbed": 0, "per_hero": 0, "downs": [], "party": party}
	var hz: Dictionary = run["node_state"]["hazard"]
	var dmg: float = (6.0 + int(_diff()["floors"]) * 2.0) * float(hz["dmg_mult"]) * dmg_scale
	var guard: float = min(0.9, hazard_severity_reduction() + Combat.party_skill_total(party, "hazard_guard_pct") + Combat.relic_special_total("hazard_guard_pct") + Combat.relic_drawback_total("hazard_guard_pct") + Combat.synergy_value_for("hazard_guard_pct") + Combat.bond_bonus_for(party, "hazard_guard_pct"))
	dmg = round(dmg * (1.0 - guard))
	var absorbed: int = min(int(run.get("shield", 0)), int(dmg))
	dmg -= absorbed
	var per: float = dmg / party.size() if party.size() > 0 else 0.0
	var downs: Array[String] = []
	for h in party:
		if dmg > 0 and int(round(h.hp - per)) <= 0:
			downs.append(h.name.split(" the ")[0])
	return {"anchor": false, "total": int(dmg), "absorbed": absorbed, "per_hero": int(round(per)), "downs": downs, "party": party}


func _apply_hazard(dmg_scale: float, bonus_chance_override: float) -> void:
	var pv := hazard_preview(dmg_scale)
	var party: Array[Hero] = pv["party"]
	var ns: Dictionary = run["node_state"]
	var hz: Dictionary = ns["hazard"]
	var log: Array[String] = []
	if pv["anchor"]:
		run["anchor_used"] = true
		log.append(tr("The Anchor Artifact snuffs the hazard before it strikes."))
	else:
		var absorbed: int = pv["absorbed"]
		run["shield"] = int(run.get("shield", 0)) - absorbed
		if absorbed > 0:
			log.append(tr("Relic wards absorb %d of the hazard.") % absorbed)
		var dmg: int = pv["total"]
		if dmg > 0 and party.size() > 0:
			var per: float = float(dmg) / party.size()
			for h in party:
				h.hp = max(1 if hazards_nonlethal() else 0, int(round(h.hp - per)))
				if h.hp <= 0:
					knock_out(h)
			log.append(tr("The hazard deals %d damage across the party.") % dmg)
			_note_injuries("wounded")
	var bonus_chance: float = float(hz["bonus_chance"]) if bonus_chance_override < 0.0 else bonus_chance_override
	if randf() < bonus_chance:
		var c := randi() % 5 + 2
		if hz["bonus_type"] == "coins":
			coins += c
			log.append(tr("You scavenge %d stray Gold.") % c)
		else:
			crystals += c
			log.append(tr("Stray Essence found in the rubble: +%d.") % c)
	ns["resolved"] = true
	ns["log"] = log
	run["node_state"] = ns
	save()
	state_changed.emit()


## The safe default: full damage roll, the hazard's own normal bonus chance.
func push_through_hazard() -> void:
	_apply_hazard(1.0, -1.0)


## The gambler's choice: double damage exposure, guaranteed bonus reward.
func risk_hazard() -> void:
	_apply_hazard(2.0, 1.0)


func can_afford_hazard_bypass() -> bool:
	return crystals >= HAZARD_BYPASS_COST


## Pay Crystals to skip the hazard entirely — no damage, no reward, no
## resistance/anchor math (there's nothing to resist or block).
func bypass_hazard() -> void:
	if not can_afford_hazard_bypass():
		return
	ensure_hazard()
	var ns: Dictionary = run["node_state"]
	crystals -= HAZARD_BYPASS_COST
	ns["resolved"] = true
	ns["log"] = [tr("You pay %d Essence and bypass the hazard entirely.") % HAZARD_BYPASS_COST]
	run["node_state"] = ns
	save()
	state_changed.emit()


func ensure_shop_offers() -> void:
	var ns: Dictionary = run.get("node_state", {})
	if ns.get("type") == "shop":
		return
	var boosted := pending_shop_boost
	var offers: Array = []
	for i in 3:
		offers.append(_gen_shop_offer((boosted or shop_guaranteed_epic()) and i == 0))
	if boosted:
		pending_shop_boost = false
	run["node_state"] = {"type": "shop", "offers": offers, "rerolls": 0}


func _gen_shop_offer(force_epic: bool = false) -> Dictionary:
	var rarity := "epic" if force_epic else Combat.weighted_rarity()
	var loot: Dictionary = {"loot_type": "relic", "obj": Combat.gen_relic(rarity)} if force_epic else Combat.gen_loot(rarity)
	var rar := GameData.find_rarity(rarity)
	loot["price"] = max(4, int(round((10.0 + 15.0 * float(rar["mult"])) * (1.0 - merchant_price_reduction()))))
	loot["bought"] = false
	return loot


## Rerolling a shop costs more each time in the same shop.
func shop_reroll_cost() -> int:
	return 8 + 6 * int(run.get("node_state", {}).get("rerolls", 0))


## Replaces every offer not yet bought with a fresh one.
func reroll_shop() -> void:
	var ns: Dictionary = run.get("node_state", {})
	var cost := shop_reroll_cost()
	if ns.get("type") != "shop" or coins < cost:
		return
	coins -= cost
	var offers: Array = ns["offers"]
	for i in offers.size():
		if not offers[i].get("bought", false):
			offers[i] = _gen_shop_offer()
	ns["rerolls"] = int(ns.get("rerolls", 0)) + 1
	save()
	state_changed.emit()


func buy_shop_offer(idx: int) -> void:
	var ns: Dictionary = run.get("node_state", {})
	var offers: Array = ns.get("offers", [])
	if idx < 0 or idx >= offers.size():
		return
	var off: Dictionary = offers[idx]
	if off.get("bought", false):
		return
	if coins < int(off["price"]):
		return
	coins -= int(off["price"])
	off["bought"] = true
	if off["loot_type"] == "item":
		var it: Item = off["obj"]
		it.id = "it" + str(next_id)
		next_id += 1
		items.append(it)
	else:
		var r: Relic = off["obj"]
		r.id = "rl" + str(next_id)
		next_id += 1
		r.equipped = Combat.equipped_relics().size() < relic_slot_cap()
		relics.append(r)
	save()
	state_changed.emit()


func advance_node() -> void:
	if not pending_injuries().is_empty():
		return   # decide what happens to the downed first (see _note_injuries)
	run["pos"] = int(run["pos"]) + 1
	run["node_state"] = {}
	auto_resolve_single_option()
	save()
	state_changed.emit()


func seal_rift() -> void:
	_rescue_left_behind()
	if int(run.get("finale", 0)) > 0 and int(run["finale"]) == campaign_act:
		_complete_act(campaign_act)
	var diff := _diff()
	var fast_clear: bool = int(run.get("boss_rounds", 99)) <= 6
	var seal_mult: float = seal_bonus_mult()
	var earned := int(round(float(diff["seal_essence"]) * seal_mult))
	crystals += earned
	var cache := 0
	if randf() < float(diff["cache_chance"]) + cache_chance_bonus():
		cache = int(round(float(GameData.RIFT_CACHE_GOLD.get(str(diff["id"]), 70)) * (1.3 if black_market_unlocked() else 1.0)))
		coins += cache
	var mapped_rank: String = str(run.get("rift_rank", ""))
	if mapped_rank != "":
		best_rift_rank_sealed = max(best_rift_rank_sealed, GameData.rift_rank_index(mapped_rank))
		_on_rift_sealed(GameData.rift_rank_index(mapped_rank))
		_check_challenge(GameData.rift_rank_index(mapped_rank))
	var just_unlocked_greater := rifts_sealed == 2
	rifts_sealed += 1
	add_reputation(GameData.SEAL_RENOWN_BASE + (GameData.rift_rank_index(mapped_rank) / 3 if mapped_rank != "" else 0))
	# Guild Board tallies (see _quest_current).
	if mapped_rank != "":
		_bump("rank_seals:%d" % GameData.rift_rank_index(mapped_rank))
	if str(diff.get("id", "")) == "greater":
		_bump("greater_seals")
	if not bool(run.get("any_ko", false)):
		_bump("flawless_rifts")
	if (run.get("hero_ids", []) as Array).size() <= 2:
		_bump("small_seals")
	var flavor := GameData.narrative_line("fast_clear" if fast_clear else "rift_sealed")
	if just_unlocked_greater:
		flavor += " " + GameData.narrative_line("greater_rift_unlocked")
	# Rift history + bonds: every roster hero who saw this rift through counts
	# it, and every pair of them grows their bond (see GameData.BOND_LEVEL_RIFTS).
	var sealers: Array[Hero] = []
	sealers.assign(current_party())
	for i in sealers.size():
		sealers[i].history["rifts_cleared"] = int(sealers[i].history.get("rifts_cleared", 0)) + 1
		for j in range(i + 1, sealers.size()):
			var key := _bond_key(sealers[i].id, sealers[j].id)
			var before := GameData.bond_level(int(bonds.get(key, 0)))
			bonds[key] = int(bonds.get(key, 0)) + 1
			if GameData.bond_level(int(bonds[key])) > before:
				flavor += tr(" %s and %s's bond deepens (Lv%d).") % [tr(str(sealers[i].name.split(" the ")[0])), tr(str(sealers[j].name.split(" the ")[0])), before + 1]
				push_toast(sealers[i], tr("Bond deepened — Lv%d") % (before + 1), tr("%s & %s: +%d%% party damage while both stand") % [tr(str(sealers[i].name.split(" the ")[0])), tr(str(sealers[j].name.split(" the ")[0])), int(round(GameData.BOND_DMG_PER_LEVEL * (before + 1) * 100))])
	for h in sealers:
		change_morale(h, GameData.MORALE_SEAL)
		for line in check_earned_quirks(h):
			flavor += " " + line
	triage_used_this_cycle = false
	refresh_recruit_pool()
	run["sealed"] = {"essence": earned, "fast_clear": fast_clear, "cache": cache, "flavor": flavor}
	if run.has("daily"):
		run["sealed"]["daily"] = _complete_daily()
	save()
	state_changed.emit()


## Earned by playing (sealing 3 rifts, lesser/greater/endless all count),
## not by spending Guild Management currency like every other unlock today.
## Pays out a finished Endless Rift (survivors) run: a little gold, Essence
## (which also levels the champions), loot for elites and wardens, and every lost
## champion freed on the way. The guild spends a day on it (wages, healing).
## Returns what was earned for the result screen.
func finish_survivors(r: SurvivorsRun) -> Dictionary:
	var pay := r.rewards()
	coins += int(pay["coins"])
	crystals += int(pay["crystals"])
	var freed: Array = []
	for id in r.rescued:
		if not champions.has(id):
			unlock_champion(id)
			freed.append(GameData.champion_full_name(id))
	var names: Array = []
	for h in r.heroes:
		names.append(h["hero"].name.split(" the ")[0])
	var loot_names: Array = []
	for i in int(pay["loot"]):
		var loot := Combat.gen_loot(Combat.weighted_rarity())
		_grant_loot(loot)
		loot_names.append(loot["obj"].name)
	for name in r.kill_counts:
		monster_kill_counts[name] = int(monster_kill_counts.get(name, 0)) + int(r.kill_counts[name])
	var t := int(r.time)
	var best := t > int(endless_best.get(r.biome, 0))
	best_endless_time = maxi(best_endless_time, t)
	endless_best[r.biome] = maxi(int(endless_best.get(r.biome, 0)), t)
	endless_runs += 1
	# First-time milestones: gold, Essence, an Endless relic, a guild title.
	var got: Array = []
	for m in GameData.ENDLESS_MILESTONES:
		if endless_milestones.has(int(m["at"])) or t < int(m["at"]) or (m.get("sealed", false) and not r.won):
			continue
		endless_milestones.append(int(m["at"]))
		coins += int(m["coins"])
		crystals += int(m["crystals"])
		var line := tr("%s: %s+%d essence") % [tr(str(m["name"])), tr("+%d gold, ") % int(m["coins"]) if int(m["coins"]) > 0 else "", int(m["crystals"])]
		if m.has("relic"):
			var rl := Combat.relic_from_unique(GameData.ENDLESS_RELICS[m["relic"]])
			rl.equipped = Combat.equipped_relics().size() < relic_slot_cap()
			relics.append(rl)
			line += tr(", the relic %s") % tr(str(rl.name))
		if m.has("title"):
			line += tr(", the title \"%s\"") % tr(str(m["title"]))
		got.append(line)
	runs_finished += 1
	pass_time()
	run_history.push_front({"day": day, "kind": "Endless Rift", "result": "Sealed" if r.won else "Survived", "floor": "", "time": t, "kills": r.kills,
		"heroes": names, "boons": [], "coins": int(pay["coins"]), "crystals": int(pay["crystals"])})
	if run_history.size() > GameData.RUN_HISTORY_MAX:
		run_history.resize(GameData.RUN_HISTORY_MAX)
	save()
	state_changed.emit()
	return {"coins": int(pay["coins"]), "crystals": int(pay["crystals"]), "freed": freed, "loot": loot_names, "best": best, "milestones": got}


## The guild's Endless Rift title (the last milestone title earned), or "".
func endless_title() -> String:
	var t := ""
	for m in GameData.ENDLESS_MILESTONES:
		if m.has("title") and endless_milestones.has(int(m["at"])):
			t = str(m["title"])
	return t


# ---------------- Downed mid-rift ----------------

## Adds every roster hero in the party who's down and not yet decided on to
## run["injured"] — the rift can't continue until each is dealt with.
func _note_injuries(severity: String) -> void:
	var injured: Array = run.get("injured", [])
	for hid in run.get("hero_ids", []):
		var h := find_hero(str(hid))
		if h and h.hp <= 0 and not injured.any(func(e): return str(e["id"]) == h.id):
			injured.append({"id": h.id, "severity": severity})
	run["injured"] = injured


func pending_injuries() -> Array:
	return run.get("injured", [])


func _injury(hero_id: String) -> Dictionary:
	for e in run.get("injured", []):
		if str(e["id"]) == hero_id:
			return e
	return {}


func _resolve_injury(hero_id: String, leave_party: bool) -> void:
	run["injured"] = (run.get("injured", []) as Array).filter(func(e): return str(e["id"]) != hero_id)
	if leave_party:
		run["hero_ids"] = (run.get("hero_ids", []) as Array).filter(func(x): return str(x) != hero_id)


## Idle roster heroes who could go fetch someone: not in the rift, not
## recovering, not already away — the lowest level first.
func idle_heroes() -> Array[Hero]:
	var out: Array[Hero] = []
	var in_rift: Array = run.get("hero_ids", [])
	for h in heroes:
		if not in_rift.has(h.id) and h.is_available():
			out.append(h)
	out.sort_custom(func(a, b): return a.level < b.level)
	return out


## Who in the party can patch a downed hero up mid-rift ("" if nobody).
func field_healer() -> String:
	if bool(run.get("heal_used", false)):
		return ""
	var min_rank := GameData.rank_index(GameData.FIELD_HEALER_MIN_RANK)
	for hid in run.get("hero_ids", []):
		var h := find_hero(str(hid))
		if h and h.hp > 0 and GameData.hero_role(h) == "cleric" and GameData.rank_index(h.rank) >= min_rank:
			return h.name.split(" the ")[0]
	if field_triage_available():
		return tr("Field Triage")
	return ""


## Carry them out: a day passes and they head home.
func injury_carry(hero_id: String) -> String:
	if _injury(hero_id).is_empty():
		return ""
	_resolve_injury(hero_id, true)
	if not Combat.party_has_unique_relic("lantern_of_the_lost"):
		pass_time()
	save()
	state_changed.emit()
	return ""


func injury_reinforce(hero_id: String) -> String:
	var e := _injury(hero_id)
	if e.is_empty():
		return ""
	var sev := str(e["severity"])
	var need := int(GameData.INJURY_REINFORCEMENTS[sev])
	var idle := idle_heroes()
	if idle.size() < need:
		return tr("Needs %d idle hero%s at camp") % [need, GameData.pl(need, "es")]
	for i in need:
		idle[i].busy_runs = int(GameData.INJURY_BUSY_RUNS[sev])
	_resolve_injury(hero_id, true)
	save()
	state_changed.emit()
	return ""


func injury_heal(hero_id: String) -> String:
	if _injury(hero_id).is_empty():
		return ""
	if field_healer() == "":
		return tr("No healer can do it")
	var h := find_hero(hero_id)
	h.down_runs = 0
	h.battered = true
	h.hp = max(1, int(round(Combat.max_hp(h) * GameData.FIELD_HEAL_HP_PCT)))
	run["heal_used"] = true
	_resolve_injury(hero_id, false)
	save()
	state_changed.emit()
	return ""


func injury_leave(hero_id: String) -> String:
	if _injury(hero_id).is_empty():
		return ""
	if rifts_sealed < 3:
		return tr("A new guild can't leave anyone behind")
	var lb: Array = run.get("left_behind", [])
	lb.append(hero_id)
	run["left_behind"] = lb
	_resolve_injury(hero_id, true)
	save()
	state_changed.emit()
	return ""


## Sealing the rift finds everyone left behind alive; they come home to recover.
func _rescue_left_behind() -> void:
	for hid in run.get("left_behind", []):
		var h := find_hero(str(hid))
		if h:
			push_toast(h, tr("Found alive"), tr("%s is carried home from the sealed rift") % tr(str(h.name.split(" the ")[0])))
	run["left_behind"] = []


## The run ended without a seal: anyone left in the rift is lost. Their gear
## is recovered and returns to the Inventory.
func _lose_left_behind() -> void:
	for hid in run.get("left_behind", []):
		var h := find_hero(str(hid))
		if not h:
			continue
		for it in items:
			if it.equipped_to == h.id:
				it.equipped_to = ""
				it.equipped_idx = -1
		push_toast(h, tr("Lost in the rift"), tr("%s was left behind and never came back") % tr(str(h.name.split(" the ")[0])))
		_memorialize(h, tr("Left behind in a %s") % tr(str(_run_label())))
		heroes.erase(h)
		run["heroes_lost"] = int(run.get("heroes_lost", 0)) + 1
	run["left_behind"] = []


## True for any hero worth a bed — actually downed, or merely wounded (hp
## below max but still able to fight). Beds are a shared resource across
## both, matching the original design intent ("heroes without a bed still
## recover, just at the normal slower passive rate").
func needs_recovery(h: Hero) -> bool:
	return h.is_downed() or (h.hp > 0 and h.hp < Combat.max_hp(h))


func assign_to_bed(hero_id: String) -> void:
	var h := find_hero(hero_id)
	if not h or h.bedded or not needs_recovery(h):
		return
	if occupied_beds() >= medical_bed_cap():
		return
	# A bed takes one run off a downed hero's recovery (never below one), and
	# heals a wounded one fully the next time time passes (see pass_time).
	if h.is_downed():
		h.down_runs = max(1, h.down_runs - 1)
	h.bedded = true
	save()
	state_changed.emit()


func occupied_beds() -> int:
	var n := 0
	for h in heroes:
		if h.bedded and needs_recovery(h):
			n += 1
	return n


## Safety net, run once per render(): a hero at 0 HP who somehow isn't
## counting down (older saves) starts recovering, and a bed held by someone
## who no longer needs it is freed.
func resolve_recovery() -> void:
	var changed := false
	for h in heroes:
		if h.hp <= 0 and h.down_runs <= 0:
			knock_out(h)
			changed = true
		elif h.bedded and not needs_recovery(h):
			h.bedded = false
			changed = true
	if changed:
		save()


## Guild time moves one step whenever a rift run ends (or the guild rests
## instead): downed heroes count down their recovery and wounded ones heal.
func pass_time() -> void:
	day += 1
	var in_rift: Array = run.get("hero_ids", []) if not run.is_empty() else []
	for hid in in_rift:
		var hr := find_hero(str(hid))
		if hr:
			hr.last_rift_day = day
	rival_day()
	if day % GameData.PAYDAY_DAYS == 0:
		run_payday()
	maybe_hero_request()
	for h in heroes:
		if h.busy_runs > 0:
			h.busy_runs -= 1
		if in_rift.has(h.id):
			continue   # a day passing mid-rift (carrying someone out) doesn't rest the party
		var mx := Combat.max_hp(h)
		if h.down_runs > 0:
			h.down_runs -= 1
			if h.down_runs == 0:
				h.hp = mx
				h.bedded = false
		elif h.hp > 0 and h.hp < mx:
			h.hp = mx if h.bedded or full_heal_between_runs() else min(mx, h.hp + int(ceil(mx * GameData.WOUND_HEAL_PER_RUN)))
			if h.hp >= mx:
				h.bedded = false
	resolve_guild_board()
	_on_day_passed()


## Rest instead of running a rift: time passes (see pass_time) without a
## fight — heroes recover.
func rest_guild() -> void:
	if not run.is_empty():
		return
	pass_time()
	save()
	state_changed.emit()


## "" when a ladder rank can be entered, else why not: each rank opens once
## the one below it is sealed, and C and up need the Greater Rift (Act II).
func ladder_rank_lock(rank_id: String) -> String:
	var idx := GameData.rift_rank_index(rank_id)
	if str(GameData.RIFT_RANKS[idx]["base"]) == "greater" and not greater_rift_unlocked():
		return tr("Opens when you complete Act I")
	if idx > best_rift_rank_sealed + 1:
		return tr("Seal a Rank %s rift first") % tr(str(GameData.RIFT_RANKS[idx - 1]["id"]))
	return ""


## The highest rank the guild can enter right now.
func highest_open_rank() -> String:
	var out := "F"
	for r in GameData.RIFT_RANKS:
		if ladder_rank_lock(str(r["id"])) == "":
			out = str(r["id"])
	return out


func start_ladder_rift(rank_id: String, hero_ids: Array[String], starting_relic: Relic) -> void:
	start_run(str(GameData.find_rift_rank(rank_id)["base"]), hero_ids, starting_relic, rank_id)


func retreat_now() -> void:
	if run.has("tower"):
		_end_tower()
		return
	_record_run("Retreated")
	_lose_left_behind()
	run = {}
	_clamp_hp_to_max()
	pass_time()
	save()
	state_changed.emit()


func finish_run() -> void:
	if run.has("tower"):
		_end_tower()
		return
	var outcome := _run_outcome()
	if outcome == "Defeated":
		for h in current_party():
			change_morale(h, GameData.MORALE_DEFEAT)
	_record_run(outcome)
	_lose_left_behind()
	run = {}
	_clamp_hp_to_max()
	pass_time()
	save()
	state_changed.emit()


## A new guild's first three: a warrior, a cleric and a ranger or mage
## (Rank F), so a player's first step is a rift, not the recruit board.
func hire_starters() -> void:
	for roles in [["warrior"], ["cleric"], ["ranger", "mage"]]:
		for tries in 80:
			var h := Combat.gen_hero("F", 1)
			if GameData.hero_role(h) in roles:
				heroes.append(h)
				break
	coins += weekly_wages()   # the founders pay their first week, so a new guild doesn't open in the red
