extends Node
## Whole-campaign sim: plays new guilds day by day through the real GameState
## calls the UI makes (one rift or rest a day, Quick fight in every fight,
## matters answered, Riftbreaks defended) and reports pacing, the Gold
## economy and fight win rates. Never touches the player's saves (slot 9).
##   godot --headless --path . res://tests/sim/campaign_sim.tscn
##   ... -- investor | casual     only that profile
##   ... -- days=60 seeds=4       length and sample size
##   ... -- bold                  always enter the highest open rank (no
##                                stepping down when it reads Deadly)
##   ... -- hp=1.2 dmg=1.2        try a RANK_THREAT without editing the data
##   ... -- attr=agility          every attribute point into one attribute
##   ... -- hand                  fight like a careful player (see _hand_action)
##                                instead of Quick fight
## Profiles: "investor" spends like a player who reads the tooltips (quests,
## skills, upgrades, training, recruits, champion levels); "casual" takes
## quests, spends skill and attribute points, equips gear and hires up to 6,
## but never buys an upgrade, training or a champion level.

const TARGETS := """Targets: wages+upkeep 35-50%% of Gold income (weeks 2-6) · Act I done day 4-7 · Act II day 18-28 · investor clears 65-80%% of runs at its top rank"""

var days := 60
var seeds := 4
var profile := ""
var log_days := false
var bold := false
var hand := false
var force_attr := ""
var hand_bonus := 0      # fights that paid the flawless-by-hand bonus
var curve := {}          # power/recommended bucket -> [sealed, lost], ladder runs only
# Per guild:
var gross_gold := {}     # week -> Gold earned (runs, quests, defenses)
var bill_paid := {}      # week -> wages + upkeep paid
var fights := {}         # rank -> [won, lost]
var runs := {}           # rank -> [sealed, lost]
var rounds := {}         # rank -> [fights, total rounds, fights over in round 1]
var act_day := {}        # act finished -> day
var notes: Array[String] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("days="):
			days = int(a.substr(5))
		elif a.begins_with("seeds="):
			seeds = int(a.substr(6))
		elif a in ["investor", "casual"]:
			profile = a
		elif a.begins_with("hp="):
			GameData.RANK_THREAT_HP = float(a.substr(3))
		elif a.begins_with("dmg="):
			GameData.RANK_THREAT_DMG = float(a.substr(4))
		elif a.begins_with("attr="):
			force_attr = a.substr(5)
		elif a == "hand":
			hand = true
		elif a == "bold":
			bold = true
		elif a == "log":
			log_days = true
	print(TARGETS % [])
	print("Rank threat: hp x%.2f, dmg x%.2f" % [GameData.RANK_THREAT_HP, GameData.RANK_THREAT_DMG])
	for p in (["investor", "casual"] if profile == "" else [profile]):
		var all_fights := {}
		var all_runs := {}
		var all_rounds := {}
		var ratios: Array = []
		var acts := {2: [], 3: [], 4: []}
		for s in seeds:
			_guild(p, 7000 + s)
			for r in fights:
				var t: Array = all_fights.get(r, [0, 0])
				all_fights[r] = [t[0] + fights[r][0], t[1] + fights[r][1]]
			for r in rounds:
				var t2: Array = all_rounds.get(r, [0, 0, 0])
				all_rounds[r] = [t2[0] + rounds[r][0], t2[1] + rounds[r][1], t2[2] + rounds[r][2]]
			for r in runs:
				var t: Array = all_runs.get(r, [0, 0])
				all_runs[r] = [t[0] + runs[r][0], t[1] + runs[r][1]]
			for w in range(2, 7):
				if float(gross_gold.get(w, 0)) > 0:
					ratios.append(float(bill_paid.get(w, 0)) / float(gross_gold[w]))
			for a in acts:
				acts[a].append(int(act_day.get(a, -1)))
		print("== %s%s%s%s, %d guilds x %d days" % [p, " (bold)" if bold else "", " (by hand)" if hand else " (Quick fight)", (" all points in " + force_attr) if force_attr != "" else "", seeds, days])
		print("   Act I done on days %s · Act II %s · Act III %s   (-1 = not reached)" % [acts[2], acts[3], acts[4]])
		ratios.sort()
		if not ratios.is_empty():
			print("   wages+upkeep / Gold income, weeks 2-6: median %d%% (min %d%%, max %d%%)" % [int(ratios[ratios.size() / 2] * 100), int(ratios[0] * 100), int(ratios[-1] * 100)])
		var ranks := all_fights.keys()
		ranks.sort_custom(func(a, b): return GameData.rift_rank_index(str(a)) < GameData.rift_rank_index(str(b)))
		print("   fights won: %s" % "  ".join(ranks.map(func(r): return "%s %d/%d" % [r, all_fights[r][0], all_fights[r][0] + all_fights[r][1]])))
		if hand:
			print("   flawless-by-hand bonus paid in %d fights" % hand_bonus)
		print("   fight length (avg rounds, %% over in round 1): %s" % "  ".join(ranks.filter(func(r): return all_rounds.has(r)).map(func(r): return "%s %.1f/%d%%" % [r, float(all_rounds[r][1]) / maxf(1.0, all_rounds[r][0]), int(100.0 * all_rounds[r][2] / maxf(1.0, all_rounds[r][0]))])))
		print("   runs sealed: %s" % "  ".join(ranks.filter(func(r): return all_runs.has(r)).map(func(r): return "%s %d/%d" % [r, all_runs[r][0], all_runs[r][0] + all_runs[r][1]])))
	var ks := curve.keys()
	ks.sort()
	print("Clear rate by party power / recommended (all profiles): %s" % "  ".join(ks.map(func(k): return "%.1f: %d/%d" % [k / 10.0, curve[k][0], curve[k][0] + curve[k][1]])))
	get_tree().quit()


func _guild(p: String, s: int) -> void:
	seed(s)
	gross_gold = {}
	bill_paid = {}
	fights = {}
	runs = {}
	rounds = {}
	act_day = {}
	notes = []
	GameState.active_slot = 9
	GameState.reset()
	GameState.guild_name = "Sim"
	GameState.tips_off = true
	GameState.hire_starters()
	GameState.refresh_recruit_pool()
	var act := GameState.campaign_act
	while GameState.day < days:
		var pay0 := int(GameState.payday_report.get("day", -1))
		var c0 := GameState.coins
		_day(p)
		var spent := _spent
		_spent = 0
		var paid := 0
		if int(GameState.payday_report.get("day", -1)) != pay0:
			paid = int(GameState.payday_report["paid"]) + (int(GameState.payday_report["upkeep"]) if GameState.payday_report["upkeep_paid"] else 0)
			var pw := (int(GameState.payday_report["day"]) - 1) / GameData.PAYDAY_DAYS
			bill_paid[pw] = int(bill_paid.get(pw, 0)) + paid
		var w := (GameState.day - 1) / GameData.PAYDAY_DAYS   # days 1-7 are week 0, paid on day 7
		gross_gold[w] = int(gross_gold.get(w, 0)) + maxi(0, GameState.coins - c0 + spent + paid)
		if GameState.campaign_act != act:
			act = GameState.campaign_act
			act_day[act] = GameState.day
	GameState.active_slot = 9
	var last := (GameState.day - 1) / GameData.PAYDAY_DAYS
	print("   [%s seed %d] day %d act %d · %d Gold %d Essence · roster %d · week %d bill %d of income %d%s" % [p, s, GameState.day, GameState.campaign_act, GameState.coins, GameState.crystals, GameState.heroes.size(),
		last - 1, int(bill_paid.get(last - 1, 0)), int(gross_gold.get(last - 1, 0)), ("  · " + "; ".join(notes)) if not notes.is_empty() else ""])


var _party_power := 0
var _spent := 0   # Gold spent at camp and in shops today (not a loss of income)


func _day(p: String) -> void:
	GameState.check_feature_unlocks()
	GameState.check_milestones()
	GameState.pending_stories.clear()
	GameState.pending_toasts.clear()
	_answer_matters()
	_quests()
	var g0 := GameState.coins
	if p == "investor":
		_invest()
	else:
		_idle_spend()
	_spent += maxi(0, g0 - GameState.coins)
	if GameState.breach_broken():
		_defend()
		return
	var party := _pick_party()
	if party.is_empty():
		GameState.rest_guild()
		return
	# The number the Party screen shows: relics, synergies and bonds included.
	_party_power = Combat.party_power(party.map(func(id): return GameState.find_hero(id)))
	var rank := "finale"
	if GameState.finale_ready() and (bold or _party_power >= GameState.finale_recommended_power() * 0.8):
		GameState.start_finale(party, null)
	else:
		rank = GameState.highest_open_rank()
		if not bold and _party_power < Combat.recommended_power("", rank) * 0.8 and GameData.rift_rank_index(rank) > 0:
			rank = str(GameData.RIFT_RANKS[GameData.rift_rank_index(rank) - 1]["id"])
		if GameState.daily_available():
			GameState.start_daily(rank, party, null)
		else:
			GameState.start_ladder_rift(rank, party, null)
	var res := _play_run(rank)
	if rank != "finale":
		var b := clampi(int(round(float(_party_power) / Combat.recommended_power("", rank) * 10.0)), 4, 16)
		var ct: Array = curve.get(b, [0, 0])
		ct[0 if res == "sealed" else 1] += 1
		curve[b] = ct
	var rt: Array = runs.get(rank, [0, 0])
	rt[0 if res == "sealed" else 1] += 1
	runs[rank] = rt
	if log_days:
		print("     day %d %s (party power %d, recommended %d): %s · %d Gold" % [GameState.day, rank, _party_power, Combat.recommended_power("", rank) if rank != "finale" else 0, res, GameState.coins])


func _answer_matters() -> void:
	if not GameState.hero_request.is_empty() and randf() < 0.9:
		if GameState.answer_request(randf() < 0.6) != "":
			GameState.answer_request(false)
	if not GameState.rival_event.is_empty() and not GameState.rival_event.get("answered", false):
		var opts: Array = GameState.rival_event_options()
		if opts.is_empty():
			GameState.rival_event["seen"] = true
		elif GameState.answer_rival(str(opts[0][1]) == "" and randf() < 0.6) != "":
			GameState.answer_rival(false)


func _idle_spend() -> void:
	for h in GameState.heroes:
		_spend_attrs(h)
		_learn_all(h)
		GameState.equip_best(h.id)
	var bill := GameState.weekly_wages() + GameState.upkeep()
	if GameState.heroes.size() < mini(6, GameState.hero_slot_cap()) and not GameState.recruit_pool.is_empty():
		var offer: Hero = GameState.recruit_pool[0]
		if GameState.coins - int(GameData.find_rank(offer.rank)["cost"]) > bill + 60:
			GameState.recruit_hero(offer.id)
	if GameState.feast_ready() and GameState.heroes.any(func(h): return h.morale < 45) and GameState.coins > bill + GameState.feast_cost():
		GameState.hold_feast()


func _quests() -> void:
	for q in GameState.guild_board.duplicate():
		if str(q["status"]) == "active" and GameState.quest_progress(q) >= int(q["target"]):
			GameState.claim_quest(str(q["id"]))
	if GameState.feature_unlocked("quests"):
		for q in GameState.guild_board:
			if str(q["status"]) == "posted":
				GameState.accept_quest(str(q["id"]))


## Spends like a player who reads the tooltips: quests, skill and attribute
## points, evolutions, training, the cheapest facility upgrade, recruits up
## to the cap (keeping next payday's bill in hand), a champion level.
func _invest() -> void:
	for h in GameState.heroes:
		_spend_attrs(h)
		_learn_all(h)
		if h.level >= 10:
			var cls := GameData.find_class(h.pool_id)
			var choices: Array = GameData.evolution_choices(cls) if not cls.is_empty() else []
			if not choices.is_empty():
				GameState.evolve_hero(h.id, str(choices[0]["id"]))
	var bill := GameState.weekly_wages() + GameState.upkeep()
	for round_i in 3:
		var best_key := ""
		var best_cost := 1 << 30
		for b in GameData.BRANCHES:
			for n in b["nodes"]:
				var key := "%s.%s" % [b["id"], n["id"]]
				var cur := int(GameState.upgrades.get(key, 0))
				if cur >= int(n["max"]):
					continue
				var gold: bool = str(n.get("currency", "")) == "gold"
				var cost := int(n["cost_base"]) + int(n["cost_step"]) * cur
				var ok: bool = (GameState.coins - cost > bill + 150 and GameState.campaign_act >= 2) if gold else GameState.crystals >= cost
				if ok and cost < best_cost and GameState.feature_unlocked("management"):
					best_cost = cost
					best_key = key
		if best_key == "" or GameState.upgrade_node(best_key) != "":
			break
	while GameState.heroes.size() < GameState.hero_slot_cap() and not GameState.recruit_pool.is_empty():
		var offers: Array = GameState.recruit_pool.filter(func(o): return GameState.coins - int(GameData.find_rank(o.rank)["cost"]) > bill + 100)
		if offers.is_empty():
			break
		offers.sort_custom(func(a, b): return int(GameData.find_rank(a.rank)["cost"]) > int(GameData.find_rank(b.rank)["cost"]))
		if GameState.recruit_hero(offers[0].id) != "":
			break
		bill = GameState.weekly_wages() + GameState.upkeep()
	for h in GameState.heroes:
		if GameState.training_left() > 0 and GameState.coins - GameState.attr_train_cost(h) > bill + 200:
			GameState.train_attr(h.id)
			_spend_attrs(h)
	for id in GameState.champions:
		var c := GameState.champion_level_cost(str(id))
		if c > 0 and GameState.crystals > c + 200:
			GameState.level_champion(str(id))
	if GameState.feast_ready() and GameState.heroes.any(func(h): return h.morale < 45) and GameState.coins > bill + GameState.feast_cost():
		GameState.hold_feast()
	for h in GameState.heroes:
		GameState.equip_best(h.id)


func _spend_attrs(h: Hero) -> void:
	if force_attr == "":
		Combat.auto_spend_attrs(h)
		return
	for i in h.attr_points:
		GameState.spend_attr_point(h.id, force_attr)


## Skill points: the hero's own tree first, in order.
func _learn_all(h: Hero) -> void:
	var kinds: Array = GameData.KIND_SKILL_PACKAGE.keys()
	kinds.erase(h.innate_kind)
	kinds.push_front(h.innate_kind)
	for pass_i in 3:
		for kind in kinds:
			for id in ["edge", "hide"] + (GameData.KIND_SKILL_PACKAGE[kind] as Array).map(func(n): return str(n["id"])):
				if h.skill_points > 0:
					GameState.learn_skill(h.id, str(kind), str(id))


func _pick_party() -> Array[String]:
	var ok: Array = GameState.heroes.filter(func(h): return not h.is_champion and not h.is_downed() and h.busy_runs <= 0 and h.hp > Combat.max_hp(h) * 0.35)
	ok.sort_custom(func(a, b): return Combat.power_of(a) > Combat.power_of(b))
	var out: Array[String] = []
	for h in ok.slice(0, 4):
		out.append(h.id)
	return out


func _tally(rank: String, won: bool) -> void:
	var t: Array = fights.get(rank, [0, 0])
	t[0 if won else 1] += 1
	fights[rank] = t


func _play_run(rank: String) -> String:
	for step in 120:
		if GameState.run.is_empty():
			return "?"
		if GameState.run.get("sealed") is Dictionary and not (GameState.run["sealed"] as Dictionary).is_empty():
			GameState.finish_run()
			return "sealed"
		if not GameState.pending_injuries().is_empty():
			for inj in GameState.pending_injuries():
				var hid := str(inj.get("hero_id", inj.get("id", "")))
				if GameState.injury_heal(hid) != "":
					GameState.injury_carry(hid)
			continue
		var kind := GameState.current_node_kind()
		if kind == "":
			var opts := GameState.current_layer_options()
			var prefs := ["boss", "combat", "event", "shop", "elite", "treasure", "campfire", "hazard"]
			if _party_hp() < 0.55:
				prefs = ["boss", "campfire", "event", "treasure", "shop", "combat", "hazard", "elite"]
			for pr in prefs:
				if opts.has(pr):
					kind = pr
					break
			if kind == "":
				kind = str(opts[0])
			GameState.choose_node_type(kind)
			continue
		var ns: Dictionary = GameState.run.get("node_state", {})
		match kind:
			"combat", "elite", "boss":
				if not ns.has("result"):
					if hand:
						_hand_fight()
					else:
						GameState.quick_fight()
					continue
				var result: Dictionary = ns["result"]
				if not ns.get("tallied", false):
					ns["tallied"] = true
					_tally(rank, bool(result.get("won", false)))
					var rt: Array = rounds.get(rank, [0, 0, 0])
					rounds[rank] = [rt[0] + 1, rt[1] + int(result.get("rounds", 0)), rt[2] + (1 if int(result.get("rounds", 0)) <= 1 else 0)]
				if not result.get("won", false):
					GameState.finish_run()
					return "lost at " + kind
				if not ns.get("reward_chosen", false) and not (result.get("reward_options", []) as Array).is_empty():
					GameState.pick_combat_reward(0)
				if GameState.boon_pending():
					GameState.pick_boon(0)
				if not GameState.pending_injuries().is_empty():
					continue
				if kind == "boss":
					GameState.seal_rift()
				else:
					GameState.advance_node()
			"event":
				GameState.ensure_event()
				var ev: Dictionary = GameState.run["node_state"]["event"]
				if not GameState.run["node_state"].get("resolved", false):
					var choices: Array = ev["choices"]
					var ci := randi() % choices.size()
					if not GameState.can_afford(choices[ci].get("cost", {})):
						ci = choices.size() - 1
					GameState.resolve_event(ci)
				GameState.advance_node()
			"campfire":
				GameState.campfire_choose("rest" if _party_hp() < 0.8 else "train")
				GameState.advance_node()
			"treasure":
				GameState.ensure_treasure()
				GameState.pick_treasure(0)
				GameState.advance_node()
			"shop":
				GameState.ensure_shop_offers()
				var offers: Array = GameState.run["node_state"].get("offers", [])
				for i in offers.size():
					if GameState.coins - int(offers[i]["price"]) > GameState.weekly_wages() + GameState.upkeep() + 40:
						var c0 := GameState.coins
						GameState.buy_shop_offer(i)
						_spent += maxi(0, c0 - GameState.coins)
						break
				GameState.advance_node()
			"hazard":
				GameState.ensure_hazard()
				GameState.push_through_hazard()
				GameState.advance_node()
			_:
				GameState.advance_node()
	notes.append("day %d: run stuck" % GameState.day)
	GameState.retreat_now()
	return "stuck"


## A fight played turn by turn the way the battle screen's buttons would.
func _hand_fight() -> void:
	GameState.engage_node()
	var st: Dictionary = GameState.run.get("node_state", {}).get("combat_state", {})
	for i in 600:
		if st.is_empty() or GameState.run.get("node_state", {}).has("result"):
			break
		var nxt := Combat.peek_next_turn(st)
		if str(nxt["type"]) == "hero":
			var h := Combat._find_party_hero(st["party"], str(nxt["id"]))
			if h and h.hp > 0:
				st["pending_actions"][h.id] = _hand_action(st, h)
		GameState.resolve_turn_now()
	if float(GameState.run.get("node_state", {}).get("result", {}).get("hand_bonus_ess", 0)) > 0:
		hand_bonus += 1


## What a careful player does on top of Auto: Defend against any hit that
## would drop this hero (Auto only braces for wind-up blows), Guard a hurt ally
## from a hit that would drop them when this hero can take it, and focus the
## foe that hurts most per point of health left instead of the weakest.
func _hand_action(st: Dictionary, h: Hero) -> Dictionary:
	var monsters: Array = st["monsters"]
	var threat_on := Combat.incoming_hits(st)
	var mine := int(threat_on.get(h.id, 0))
	if mine > 0 and mine >= h.hp:
		return {"action": "defend", "target": 0}
	for x in st["party"]:
		var hit := int(threat_on.get(x.id, 0))
		if x != h and x.hp > 0 and hit >= x.hp and Combat.guard_of(st, x) == null and h.hp - mine > hit * Combat.GUARD_DAMAGE_MULT * 1.2:
			return {"action": "guard", "target": 0, "ally": x.id}
	var a := Combat.auto_action(st, h)
	if str(a["action"]) == "attack" or str(a["action"]) in ["skill:pierce", "skill:strike", "skill:backstab", "skill:volley"]:
		var best := -1
		var best_v := -1.0
		for mi in monsters.size():
			var m: Dictionary = monsters[mi]
			if float(m["hp"]) <= 0:
				continue
			var v := float(m["dmg"]) * (2.0 if m.get("_winding", false) or m.get("_charged", false) else 1.0) / maxf(1.0, float(m["hp"]))
			if v > best_v:
				best_v = v
				best = mi
		if best >= 0:
			a["target"] = best
	return a


func _defend() -> void:
	var posted: Array = GameState.defense_candidates().slice(0, 2)
	var r := DefenseRun.new(str(GameState.breach["region"]), int(GameState.breach["rank"]), posted, null, 7, GameState.defense_opts())
	for k in 6000:
		if r.over:
			break
		if k % 25 == 0:
			r.autoplay()
			if r.build_t > 0.0 and r.wave > 0:
				r.call_early()
		r.step(0.1)
		r.events.clear()
	GameState.resolve_breach(r.result())


func _party_hp() -> float:
	var cur := 0.0
	var mx := 0.0
	for h in GameState.current_party():
		cur += maxf(0, h.hp)
		mx += Combat.max_hp(h)
	return cur / maxf(1.0, mx)
