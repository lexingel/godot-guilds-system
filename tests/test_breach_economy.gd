extends "res://tests/base_test.gd"
## Gold under Riftbreak pressure: six weeks of a guild that loses every
## breach and spends all it can spare (keeping the coming payday's bill, as
## the Rift Hall's forecast shows) on repairs and Defenses research must still
## make payroll from ordinary rift income. Income per run is the balance
## sim's (`balance_sim -- ranks`) for the rank.

const WEEKS := 6
## [label, hero ranks, level, best sealed rank index, act, Gold per run]
const GUILDS := [["Act II, Rank D guild", ["D", "D", "C", "D", "E", "D"], 5, 2, 2, 300],
	["Act III, Rank B guild", ["C", "C", "B", "B", "C", "B", "C", "D"], 8, 4, 3, 575]]


func run() -> void:
	for g in GUILDS:
		for breaches in [false, true]:
			_guild(g, breaches)


func _guild(g: Array, breaches: bool) -> void:
		seed(77)
		GameState.active_slot = 9
		GameState.reset()
		GameState.guild_name = "T"
		GameState.pending_toasts.clear()
		for r in g[1]:
			var h := Combat.gen_hero(r, int(g[2]))
			h.id = "h%d" % GameState.next_id
			GameState.next_id += 1
			GameState.heroes.append(h)
		GameState.best_rift_rank_sealed = int(g[3])
		GameState.campaign_act = int(g[4]) if breaches else 1
		for key in ["ops.barracks", "ops.infirmary", "infra.amplifiers", "log.trade", "res.vault"]:
			GameState.upgrades[key] = 2   # a guild this far along has built something
		GameState.coins = 400
		GameState.day = 1
		var unpaid_weeks := 0
		var walked := 0
		var lost := 0
		var min_after_payday := 1 << 30
		var research := 0
		for d in WEEKS * GameData.PAYDAY_DAYS:
			if GameState.breach_broken():
				var ids: Array = GameState.defense_candidates().slice(0, 2).map(func(h): return h.id)
				GameState.resolve_breach({"held": false, "integrity": 0.0, "fallen": ids})   # takes the day
				lost += 1
			elif d % 7 == 6:
				GameState.pass_time()   # a rest day
			else:
				GameState.coins += int(g[5])
				for h in GameState.heroes:
					h.last_rift_day = GameState.day   # the roster takes turns on the runs (no idle-week morale)
				GameState.pass_time()   # a rift run
			if GameState.day % GameData.PAYDAY_DAYS == 0:
				var rep: Dictionary = GameState.payday_report
				unpaid_weeks += 1 if not (rep.get("unpaid", []) as Array).is_empty() else 0
				walked += (rep.get("left", []) as Array).size()
				min_after_payday = mini(min_after_payday, GameState.coins)
			# Spend what's spare above the coming bill: repairs first, then Defenses research.
			var spare := func(): return GameState.coins - int(GameState.payday_forecast()["bill"])
			for key in GameState.damaged.keys():
				while GameState.damaged.has(key) and spare.call() >= GameState.repair_cost(key):
					GameState.repair_building(key)
			for key in ["def.armory", "def.engineering", "def.palisade", "def.watch"]:
				var node := GameData.find_branch_node(key)
				var cost := int(node["cost_base"]) + int(node["cost_step"]) * int(GameState.upgrades.get(key, 0))
				if int(GameState.upgrades.get(key, 0)) < int(node["max"]) and spare.call() >= cost:
					GameState.upgrade_node(key)
					research += 1
		print("   %s%s: %d breaches lost, %d research levels, lowest Gold after payday %d, %d unpaid weeks, %d walked out" % [g[0], "" if breaches else " (no breaches)", lost, research, min_after_payday, unpaid_weeks, walked])
		if breaches:
			check(lost >= 2, "%s: the breaches came (%d lost)" % [g[0], lost])
		check(unpaid_weeks == 0 and walked == 0, "%s: payroll holds%s (%d unpaid weeks)" % [g[0], " through every lost breach" if breaches else "", unpaid_weeks])
