class_name GuildViews
extends RiftRunView
## Camp-side screens: the camp hub, recruits, medical bay, crafting,
## bestiary, compendium, quests and guild management.

# ---------------- Terminal ----------------
func _render_terminal(v: VBoxContainer) -> void:
	var tier := Combat.guild_tier_info()
	var tier_name := str(tier["name"])
	# Guild Tier is purely derived (not stored), so "just reached a new tier"
	# is detected by comparing against the last tier seen at render time —
	# UI-only state, not persisted, same as _flavor_toast above.
	if _last_guild_tier_name != "" and _last_guild_tier_name != tier_name:
		GameState.pending_toasts.append({"cls_id": "", "pool_id": "", "title": "Guild tier reached", "text": GameData.narrative_line("guild_tier_reached")})
	_last_guild_tier_name = tier_name

	if term_tab == "camp":
		if GameState.heroes.is_empty():
			_coach(v, "welcome", "Welcome to your guild", "Rifts are tearing open across the land. Hire your first hero at the Scouts' Lodge (key 2), then head to the Rift Gate to seal a rift.")
		elif GameState.runs_started >= 1 and GameState.run.is_empty():
			_coach(v, "after_first_run", "Back at camp", "Equip what you found on the Roster's Hero tab (key 1), spend skill points under Skills, and hire more heroes when you can afford them. Every rift run or rest is one day.")
		_render_camp(v)
		_render_getting_started(v)
		return
	var tab_feature: String = {"inventory": "inventory", "medical": "medical", "bestiary": "bestiary", "quests": "quests", "management": "management"}.get(term_tab, "")
	if tab_feature != "" and not GameState.feature_unlocked(tab_feature):
		_locked_feature(v, tab_feature)
		return

	match term_tab:
		"inventory": _render_inventory(v)
		"recruits": _render_recruits(v)
		"medical": _render_medical_bay(v)
		"management": _render_management(v)
		"bestiary": _render_bestiary(v)
		"compendium": _render_compendium(v)
		"records": _render_records(v)
		"memorial": _render_memorial(v)
		"quests": _render_quests(v)
		_: _render_roster(v)


## The guild hub: 6 large, distinct painted buildings (Darkest-Dungeon-style
## reference) instead of either the earlier 11-tiny-prop scene (2 props got
## stuck standing in for destinations their art didn't read as) or the
## card-grid that replaced it (functional, but flat/impersonal). Fewer,
## bigger objects fixes what the first attempt got wrong: every building
## here is large enough to render with a real distinct silhouette. A
## building that covers more than one destination (Command Tent, Rift Gate,
## Trading Post, Scholar's Lodge) opens a small in-place picker
## (_render_hub_cluster) instead of needing precise sub-hotspots on the
## painted art — sidesteps the exact coordinate-precision problem that
## caused the mismatched props last time.
func _render_camp(v: VBoxContainer) -> void:
	if hub_cluster != "":
		_render_hub_cluster(v)
		return

	var scene_w: float = v.custom_minimum_size.x
	var native: Vector2 = GameData.HAMLET_SIZE
	var SCENE_SIZE := Vector2(scene_w, roundf(scene_w * native.y / native.x))
	var sc := SCENE_SIZE / native
	var scene := Control.new()
	scene.custom_minimum_size = SCENE_SIZE

	var bg := TextureRect.new()
	bg.texture = load(GameData.HAMLET_BG)
	bg.custom_minimum_size = SCENE_SIZE
	bg.size = SCENE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)
	_start_daynight_cycle(bg)

	# Buildings are children of the backdrop (so the day/night tint reaches
	# them); their click areas and plaques go on the scene above.
	var badges := _camp_badges()
	var targets := _hamlet_targets()
	var plaques: Array = []
	for b in GameData.HAMLET_BUILDINGS:
		var tex: Texture2D = load(GameState.hamlet_texture(b))
		var size := tex.get_size() * sc
		var anchor: Vector2 = b["pos"]
		var rect := Rect2(Vector2(anchor.x * sc.x - size.x * 0.5, anchor.y * sc.y - size.y), size)
		var art := TextureRect.new()
		art.texture = tex
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.position = rect.position
		art.size = rect.size
		bg.add_child(art)
		if b["id"] == "campfire":
			_start_ember_loop(scene, Vector2(anchor.x * sc.x, (anchor.y - 16.0) * sc.y))
			continue
		var tip := str(b["name"])
		if str(b.get("tier", "")) == "node":
			tip += " — tier %d/3 (%s Lv%d; grows at Lv3 and Lv5)" % [GameState.hamlet_tier(b), str(GameData.find_branch_node(str(b["node"]))["name"]), GameState.lvl(str(b["node"]))]
		elif b["tier"] == "guild":
			tip += " — grows with your guild tier"
		elif b["tier"] == "act":
			tip += " — grows with the campaign"
		var hotspot := _camp_area_hotspot(rect, rect, tip, targets.get(b["id"], func(): pass), false)
		hotspot.position = rect.position
		scene.add_child(hotspot)
		plaques.append([str(b["name"]), rect, b["row"] == "back"])

	for pq in plaques:
		var prect: Rect2 = pq[1]
		var plaque := _camp_plaque(str(pq[0]))
		var py: float = prect.position.y - plaque.size.y - 2.0 if pq[2] else minf(prect.end.y - plaque.size.y - 2.0, SCENE_SIZE.y - plaque.size.y - 2.0)
		plaque.position = Vector2(clampf(prect.get_center().x - plaque.size.x * 0.5, 2.0, SCENE_SIZE.x - plaque.size.x - 2.0), py)
		scene.add_child(plaque)
		var badge: Array = badges.get(str(pq[0]), [])
		if not badge.is_empty():
			var chip := _count_badge(str(badge[0]), str(badge[1]))
			chip.position = plaque.position + Vector2(plaque.size.x - 10.0, -12.0)
			scene.add_child(chip)

	# Guild tier banner in the sky's top-right; the status board top-left
	# (below the scene on a narrow screen).
	var tier_panel := _guild_tier_banner()
	scene.add_child(tier_panel)
	tier_panel.position = Vector2(SCENE_SIZE.x - tier_panel.get_combined_minimum_size().x - 10.0, 10.0)
	var board := _guild_status_board()
	if _narrow():
		v.add_child(scene)
		v.add_child(board)
	else:
		board.position = Vector2(10, 10)
		board.custom_minimum_size.x = minf(360.0, SCENE_SIZE.x * 0.42)
		scene.add_child(board)
		v.add_child(scene)


## Where each hamlet building leads.
func _hamlet_targets() -> Dictionary:
	return {
		"scouts": func(): term_tab = "recruits"; render(),
		"hall": func(): hub_cluster = "guild_hall"; render(),
		"lab": func(): hub_cluster = "arcane_lab"; render(),
		"barracks": func(): term_tab = "roster"; render(),
		"infirmary": func(): term_tab = "medical"; render(),
		"drill": func(): term_tab = "roster"; roster_tab = "skills"; render(),
		"board": func(): term_tab = "quests"; render(),
		"gate": func(): hub_cluster = "rift_gate"; render(),
		"market": func(): term_tab = "inventory"; inv_category = "items"; render(),
		"vault": func(): term_tab = "inventory"; inv_category = "relics"; render(),
	}


func _guild_tier_banner() -> PanelContainer:
	var tier := Combat.guild_tier_info()
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(Palette.INK, 0.78)
	st.border_color = Palette.VIOLET_DEEP
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var icon_path: String = GameData.GUILD_TIER_ICON.get(str(tier["name"]), "")
	if icon_path != "":
		row.add_child(_icon(icon_path, 22))
	var col := _vbox(0)
	var t := _label(str(tier["name"]), 14)
	t.add_theme_color_override("font_color", Palette.RANK_S)
	col.add_child(t)
	var sub := "%d levels" % int(tier["total"])
	if not (tier["next"] as Dictionary).is_empty():
		sub += " · %d to %s" % [int(tier["next"]["min"]) - int(tier["total"]), str(tier["next"]["name"]).replace(" Guild", "")]
	if GameState.tower_title() != "":
		sub += " · " + GameState.tower_title()
	col.add_child(_label(sub, 11, true))
	row.add_child(col)
	p.add_child(row)
	p.tooltip_text = "Guild tier grows with Guild Management levels; the Guild Hall grows with it."
	return p


## What needs you right now: each line opens where to act on it.
func _guild_status_board() -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(Palette.INK, 0.8)
	st.border_color = Palette.EMBER_DEEP
	st.set_border_width_all(1)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", st)
	var col := _vbox(0)
	var head := _label("Guild status", 15)
	head.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	col.add_child(head)
	var lines := _guild_status_lines()
	if lines.is_empty():
		col.add_child(_label("All quiet. The rifts are waiting.", 12, true))
	for ln in lines.slice(0, 6):
		var b := Button.new()
		b.flat = true
		b.text = "›  " + str(ln[0])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", ln[1])
		b.add_theme_color_override("font_hover_color", Palette.EMBER_BRIGHT)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var tight := StyleBoxEmpty.new()
		tight.content_margin_top = 1
		tight.content_margin_bottom = 1
		for sn in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(sn, tight)
		b.tooltip_text = str(ln[0])
		b.pressed.connect(ln[2])
		col.add_child(b)
	p.add_child(col)
	return p


## [text, colour, action] for the status board, most urgent first.
func _guild_status_lines() -> Array:
	var out: Array = []
	var go_term := func(tab: String): return func(): term_tab = tab; render()
	var go_screen := func(s: String): return func(): screen = s; render()
	if GameState.heroes.is_empty():
		out.append(["Hire your first hero at the Scouts' Lodge", Palette.EMBER_BRIGHT, go_term.call("recruits")])
	var act := GameState.current_act()
	if not act.is_empty():
		if GameState.finale_ready():
			out.append(["Finale open: %s" % act["finale"], Palette.EMBER_BRIGHT, go_screen.call("rift_hall")])
		else:
			for o in act["objectives"]:
				if not GameState.campaign_objective_met(o):
					var prog := "" if str(o["type"]) == "map_rank" else " (%d/%d)" % [mini(GameState.campaign_objective_progress(o), int(o["target"])), int(o["target"])]
					out.append(["Act %s: %s%s" % [GameState._roman(int(act["act"])), o["label"], prog], Palette.TEXT, go_screen.call("rift_hall")])
					break
	if GameState.feature_unlocked("rift_map"):
		var soon: Dictionary = {}
		for slot in GameState.rift_map:
			if slot.has("rank") and (soon.is_empty() or int(slot.get("runs_left", 9)) < int(soon.get("runs_left", 9))):
				soon = slot
		if not soon.is_empty():
			var rl := int(soon.get("runs_left", 1))
			out.append(["Rank %s rift closes after %d run%s" % [soon["rank"], rl, "" if rl == 1 else "s"], Palette.HAZARD if rl <= 1 else Palette.MUTED, go_screen.call("rift_map")])
	var claimable := GameState.guild_board.filter(func(q): return GameState.quest_progress(q) >= int(q["target"]))
	if not claimable.is_empty() and GameState.feature_unlocked("quests"):
		out.append(["%d quest%s ready to claim" % [claimable.size(), "" if claimable.size() == 1 else "s"], Palette.RANK_E, go_term.call("quests")])
	var down := GameState.heroes.filter(func(h): return h.is_downed())
	var hurt := GameState.heroes.filter(func(h): return GameState.needs_recovery(h) and not h.is_downed())
	if not down.is_empty() or not hurt.is_empty():
		var bits: Array[String] = []
		if not down.is_empty():
			bits.append("%d recovering" % down.size())
		if not hurt.is_empty():
			bits.append("%d wounded" % hurt.size())
		var free := GameState.medical_bed_cap() - GameState.occupied_beds()
		out.append(["%s · %d bed%s free" % [", ".join(bits), free, "" if free == 1 else "s"], Palette.HAZARD if not down.is_empty() else Palette.MUTED, go_term.call("medical")])
	var sp := GameState.heroes.filter(func(h): return h.skill_points > 0 or h.attr_points > 0)
	if not sp.is_empty():
		out.append(["%d hero%s with points to spend" % [sp.size(), "" if sp.size() == 1 else "es"], Palette.TEXT, go_term.call("roster")])
	if GameState.feature_unlocked("management"):
		var best := ""
		var best_cost := 1 << 30
		for br in GameData.BRANCHES:
			for n in br["nodes"]:
				var key := "%s.%s" % [br["id"], n["id"]]
				var lv := GameState.lvl(key)
				if lv < int(n["max"]):
					var c: int = int(n["cost_base"]) + int(n["cost_step"]) * lv
					if c < best_cost:
						best_cost = c
						best = "%s Lv%d" % [n["name"], lv + 1]
		if best != "" and GameState.crystals >= best_cost:
			out.append(["Upgrade ready: %s (%d Crystals)" % [best, best_cost], Palette.CRYSTALS, go_term.call("management")])
	if GameState.feature_unlocked("tower"):
		var f := GameState.tower_next_floor()
		if f > 0:
			out.append(["Tower of Trials: floor %d next" % f, Palette.MUTED, go_screen.call("tower")])
	return out


# ---------------- Records & Memorial ----------------

func _render_records(v: VBoxContainer) -> void:
	v.add_child(_label("Records", 20))
	var done := GameData.MILESTONES.filter(func(m): return GameState.milestones_claimed.has(str(m["id"]))).size()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in [["achievements", "Achievements %d/%d" % [done, GameData.MILESTONES.size()]], ["stats", "Statistics"], ["history", "Run history"]]:
		var b := _button(str(t[1]), func(id=t[0]):
			records_tab = id
			render()
		)
		b.toggle_mode = true
		b.button_pressed = records_tab == t[0]
		tabs.add_child(b)
	v.add_child(tabs)
	match records_tab:
		"stats": _render_stats(v)
		"history": _render_history(v)
		_: _render_achievements(v)


func _render_achievements(v: VBoxContainer) -> void:
	for m in GameData.MILESTONES:
		var got := GameState.milestones_claimed.has(str(m["id"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var mark := _label("✓" if got else "○", 16)
		mark.add_theme_color_override("font_color", Palette.RANK_E if got else Palette.MUTED)
		mark.custom_minimum_size.x = 20
		row.add_child(mark)
		var lab := _wrap_label(str(m["label"]), 13)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not got:
			lab.add_theme_color_override("font_color", Palette.MUTED)
		row.add_child(lab)
		var prog := mini(GameState.milestone_progress(m), int(m["target"]))
		var rw: Dictionary = m["reward"]
		var bits: Array[String] = []
		for k in ["coins", "crystals", "tokens", "reputation"]:
			if int(rw.get(k, 0)) > 0:
				bits.append("+%d %s" % [int(rw[k]), {"coins": "Coins", "crystals": "Crystals", "tokens": "Tokens", "reputation": "Rep"}[k]])
		var right := _label(("Done" if got else "%d/%d" % [prog, int(m["target"])]) + "  ·  " + ", ".join(bits), 12, true)
		row.add_child(right)
		v.add_child(row)


func _render_stats(v: VBoxContainer) -> void:
	var kills := 0
	var top_foe := ""
	var top_n := 0
	for k in GameState.monster_kill_counts:
		var n := int(GameState.monster_kill_counts[k])
		kills += n
		if n > top_n:
			top_n = n
			top_foe = str(k)
	var best_hero := ""
	var best_p := 0
	for h in GameState.heroes:
		if Combat.power_of(h) > best_p:
			best_p = Combat.power_of(h)
			best_hero = "%s (power %d)" % [h.name.split(" the ")[0], best_p]
	var rows := [
		["Days passed", str(GameState.day)],
		["Runs finished", str(GameState.runs_finished)],
		["Rifts sealed", str(GameState.rifts_sealed)],
		["Monsters defeated", str(kills)],
		["Elites / Bosses defeated", "%d / %d" % [GameState.elites_won, GameState.bosses_won]],
		["Flawless fights", str(GameState.flawless_wins)],
		["Campaign", "complete" if GameState.campaign_done() else "Act %s" % GameState._roman(GameState.campaign_act)],
		["Tower of Trials, best floor", str(GameState.tower_best)],
		["Endless Rift, best cycle", str(GameState.best_endless_cycle)],
		["Daily Rifts cleared", "%d (streak %d)" % [GameState.daily_clears, GameState.daily_streak]],
		["Items and relics crafted", str(GameState.crafts_performed)],
		["Reputation", str(GameState.reputation)],
		["Heroes lost", str(GameState.heroes_lost_total)],
		["Strongest hero", best_hero if best_hero != "" else "—"],
		["Most-defeated foe", "%s (%d)" % [top_foe, top_n] if top_foe != "" else "—"],
	]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	for r in rows:
		grid.add_child(_label(str(r[0]), 13, true))
		grid.add_child(_label(str(r[1]), 13))
	v.add_child(grid)


func _render_history(v: VBoxContainer) -> void:
	if GameState.run_history.is_empty():
		v.add_child(_label("No runs yet. Your last %d runs will be listed here." % GameData.RUN_HISTORY_MAX, 13, true))
		return
	for e in GameState.run_history:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var res := str(e["result"])
		var rl := _label(res, 13)
		rl.custom_minimum_size.x = 80
		rl.add_theme_color_override("font_color", Palette.RANK_E if res == "Sealed" else (Palette.HAZARD if res == "Defeated" else Palette.MUTED))
		row.add_child(rl)
		var what := "Day %d · %s · floor %s" % [int(e["day"]), e["kind"], e["floor"]]
		if int(e.get("cycle", 0)) > 0:
			what += " · cycle %d" % (int(e["cycle"]) + 1)
		var wl := _label(what, 13)
		wl.custom_minimum_size.x = 300
		row.add_child(wl)
		row.add_child(_label("%+dc  %+dcr" % [int(e["coins"]), int(e["crystals"])], 12, true))
		var tip := "Party: " + ", ".join(e["heroes"])
		if not (e.get("boons", []) as Array).is_empty():
			tip += "\nBoons: " + ", ".join((e["boons"] as Array).map(func(b): return str(GameData.find_boon(str(b)).get("name", b))))
		row.tooltip_text = tip
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		v.add_child(row)


func _render_memorial(v: VBoxContainer) -> void:
	v.add_child(_label("Memorial", 20))
	v.add_child(_wrap_label("Heroes lost for good. Their names stay with the guild.", 13, true))
	if GameState.fallen.is_empty():
		v.add_child(_label("No one has fallen. May it stay that way.", 14))
		return
	for f in GameState.fallen:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var portrait := GameData.portrait_for_hero(str(f["cls_id"]), str(f["pool_id"]))
		if portrait != "":
			var ic := _icon_trimmed(portrait, 44)
			ic.modulate = Color(0.55, 0.55, 0.6)
			row.add_child(ic)
		var col := _vbox(2)
		col.add_child(_label("%s — Rank %s, Level %d" % [f["name"], f["rank"], int(f["level"])], 14))
		col.add_child(_wrap_label("%s, on day %d. %d rift%s sealed, %d foe%s felled." % [f["cause"], int(f["day"]), int(f["rifts"]), "" if int(f["rifts"]) == 1 else "s", int(f["kills"]), "" if int(f["kills"]) == 1 else "s"], 12, true))
		row.add_child(col)
		v.add_child(row)


## A short first-guild checklist under the camp scene, each step ticking off
## from real game state. Gone once every step is done, the guild has sealed
## a few rifts, or the player hides it.
func _render_getting_started(v: VBoxContainer) -> void:
	if GameState.guide_hidden or GameState.rifts_sealed >= 3:
		return
	var steps := [
		["Recruit a hero at the Scouts' Lodge", not GameState.heroes.is_empty()],
		["Assemble a party at the Rift Gate and enter a rift", not GameState.monsters_seen.is_empty()],
		["Equip an item on a hero (Roster > Hero)", GameState.items.any(func(it): return it.equipped_to != "")],
		["Spend a skill point (Roster > Skills)", GameState.heroes.any(func(h): return h.skills.values().has(true))],
		["Seal your first rift by beating its boss", GameState.rifts_sealed >= 1],
	]
	var done: int = steps.filter(func(s): return s[1]).size()
	if done == steps.size():
		return
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanelViolet"
	var cv := _vbox(4)
	var head := HBoxContainer.new()
	head.add_child(_label("Getting started — %d/%d" % [done, steps.size()], 15))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_button("Hide", func():
		GameState.guide_hidden = true
		GameState.save()
		render()
	))
	cv.add_child(head)
	for s in steps:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		if s[1]:
			row.add_child(_icon(GameData.BUTTON_ICON_PATH["confirm"], 14))
		else:
			var dot := _label("•", 13)
			dot.custom_minimum_size.x = 14
			dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(dot)
		row.add_child(_label(str(s[0]), 13, s[1]))
		cv.add_child(row)
	panel.add_child(cv)
	v.add_child(panel)


## Notification counts per camp building: {building label: [badge text,
## tooltip]} — only for things the player can act on right now.
func _camp_badges() -> Dictionary:
	var out := {}
	var needy: Array[String] = []
	for h in GameState.heroes:
		var reasons: Array[String] = []
		if h.skill_points > 0:
			reasons.append("%d SP" % h.skill_points)
		if h.level >= 10:
			var choices := GameData.evolution_choices(GameData.find_class(h.pool_id))
			if not choices.is_empty():
				var nr := GameData.find_rank(str(choices[0]["rank"]))
				var needs_stone: bool = str(choices[0]["rank"]) in ["B", "A", "S"]
				if GameState.crystals >= int(nr["cost"]) and (not needs_stone or int(GameState.evolution_stones.get(str(choices[0]["rank"]), 0)) > 0):
					reasons.append("can evolve")
		for st in ["weapon", "gear"]:
			if _first_free_slot(h, st) >= 0 and GameState.items.any(func(it): return it.equipped_to == "" and it.slot_type() == st and GameState.item_fits_hero(it, h)):
				reasons.append("empty %s slot" % st)
				break
		if not reasons.is_empty():
			needy.append("%s: %s" % [h.name.split(" the ")[0], ", ".join(reasons)])
	if not needy.is_empty():
		out["Barracks"] = [str(needy.size()), "\n".join(needy)]
	var hurt := GameState.heroes.filter(func(h): return GameState.needs_recovery(h) and not h.bedded)
	if not hurt.is_empty():
		out["Infirmary"] = [str(hurt.size()), "%d hero(es) wounded or downed" % hurt.size()]
	if GameState.heroes.size() < GameState.hero_slot_cap():
		var affordable := GameState.recruit_pool.filter(func(h): return GameState.coins >= int(GameData.find_rank(h.rank)["cost"]))
		if not affordable.is_empty():
			out["Scouts' Lodge"] = [str(affordable.size()), "%d recruit(s) you can afford" % affordable.size()]
	var craftable := 0
	var groups := {}
	for it in GameState.items:
		if it.equipped_to == "" and it.rarity in ["common", "rare"]:
			var k := "i:%s:%s" % [it.category, it.rarity]
			groups[k] = int(groups.get(k, 0)) + 1
	for r in GameState.relics:
		if not r.equipped and r.rarity in ["common", "rare"]:
			var k2 := "r:%s:%s" % [r.type, r.rarity]
			groups[k2] = int(groups.get(k2, 0)) + 1
	for k in groups:
		craftable += int(groups[k]) / 3
	if craftable > 0:
		out["Arcane Lab"] = [str(craftable), "%d craft(s) ready at the Crafting Hall" % craftable]
	var free_relic_slots := GameState.relic_slot_cap() - Combat.equipped_relics().size()
	var spare_relics := GameState.relics.filter(func(r): return not r.equipped).size()
	if free_relic_slots > 0 and spare_relics > 0:
		out["Relic Vault"] = [str(min(free_relic_slots, spare_relics)), "%d relic slot(s) empty — equip a relic from Inventory" % free_relic_slots]
	var claimable := GameState.guild_board.filter(func(q): return GameState.quest_progress(q) >= int(q["target"]))
	if not claimable.is_empty():
		out["Quest Board"] = [str(claimable.size()), "%d Guild Board quest(s) ready to claim" % claimable.size()]
	if not GameState.pending_riftbreak_ranks.is_empty():
		out["Rift Gate"] = ["!", "A rift has broken open — a Riftbreak fight is waiting"]
	return out


## The small in-place picker a multi-destination building opens instead of
## navigating straight away — reuses _hub_card for visual consistency with
## anything else card-styled in the game.
func _render_hub_cluster(v: VBoxContainer) -> void:
	var title := ""
	var entries: Array = []
	match hub_cluster:
		"command":
			title = "Command Tent"
			entries = [
				[GameData.CAMP_HUB_ICON_PATH["roster"], "Roster", func(): hub_cluster = ""; term_tab = "roster"; render()],
				[GameData.CAMP_HUB_ICON_PATH["management"], "Guild Management", func(): hub_cluster = ""; term_tab = "management"; render()],
			]
		"guild_hall":
			title = "Guild Hall"
			entries = [
				[GameData.CAMP_HUB_ICON_PATH["management"], "Guild Management", func(): hub_cluster = ""; term_tab = "management"; render()],
				[GameData.CAMP_HUB_ICON_PATH["compendium"], "Compendium", func(): hub_cluster = ""; term_tab = "compendium"; render()],
				["res://assets/skills/trophy.png", "Records", func(): hub_cluster = ""; term_tab = "records"; render()],
				["res://assets/skills/helm.png", "Memorial", func(): hub_cluster = ""; term_tab = "memorial"; render()],
			]
		"arcane_lab":
			title = "Arcane Lab"
			entries = [
				[GameData.CAMP_HUB_ICON_PATH["crafting"], "Crafting Hall", func(): hub_cluster = ""; screen = "crafting_hall"; render()],
				[GameData.CAMP_HUB_ICON_PATH["bestiary"], "Bestiary", func(): hub_cluster = ""; term_tab = "bestiary"; render()],
			]
		"rift_gate":
			title = "Rift Gate"
			entries = [
				[GameData.CAMP_HUB_ICON_PATH["rift"], "Rift Hall", func(): hub_cluster = ""; screen = "rift_hall"; render()],
				[GameData.CAMP_HUB_ICON_PATH["rift_map"], "Rift Map", func(): hub_cluster = ""; screen = "rift_map"; render()],
			]
		"trading_post":
			title = "Trading Post"
			entries = [
				[GameData.CAMP_HUB_ICON_PATH["inventory"], "Inventory", func(): hub_cluster = ""; term_tab = "inventory"; render()],
				[GameData.CAMP_HUB_ICON_PATH["crafting"], "Crafting Hall", func(): hub_cluster = ""; screen = "crafting_hall"; render()],
			]
		"scholars_lodge":
			title = "Scholar's Lodge"
			entries = [
				[GameData.CAMP_HUB_ICON_PATH["bestiary"], "Bestiary", func(): hub_cluster = ""; term_tab = "bestiary"; render()],
				[GameData.CAMP_HUB_ICON_PATH["compendium"], "Compendium", func(): hub_cluster = ""; term_tab = "compendium"; render()],
				[GameData.CAMP_HUB_ICON_PATH["quests"], "Guild Board", func(): hub_cluster = ""; term_tab = "quests"; render()],
			]
	v.add_child(_label(title, 18))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var entry_feature := {"Guild Management": "management", "Rift Map": "rift_map", "Inventory": "inventory", "Crafting Hall": "crafting", "Bestiary": "bestiary", "Guild Board": "quests"}
	for entry in entries:
		var fid: String = entry_feature.get(str(entry[1]), "")
		if fid != "" and not GameState.feature_unlocked(fid):
			var card := _hub_card(entry[0], "%s (locked)" % entry[1], func(): pass)
			card.modulate = Color(1, 1, 1, 0.45)
			card.tooltip_text = GameData.FEATURE_UNLOCKS[fid]["hint"]
			row.add_child(card)
		else:
			row.add_child(_hub_card(entry[0], entry[1], entry[2]))
	v.add_child(row)


## A Champion as a card: who they are, their Boon and Call, and — for the
## current one — oath progress and Swear In; for an offer, a Choose button.
func _champion_card(c: Hero, current: bool, offer_idx: int = -1) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelEmber" if current else &"CardPanelViolet"
	if not current:
		card.custom_minimum_size.x = 270
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_framed_portrait(c.cls_id, c.pool_id, 64.0 if current else 52.0))
	var col := _vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := _label(c.name, 15 if current else 14)
	nm.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if current else Palette.TEXT)
	col.add_child(nm)
	col.add_child(_label("Rank %s · Lv%d %s · Power %d" % [c.rank, c.level, GameState.champion_role(c).capitalize(), Combat.power_of(c)], 12, true))
	var boon := _wrap_label("Boon: " + GameState.champion_boon_text(c), 12)
	boon.add_theme_color_override("font_color", Palette.RANK_E)
	col.add_child(boon)
	var call := GameState.champion_call(c)
	col.add_child(_wrap_label("Call: %s — %s (once per rift)" % [call["name"], call["desc"]], 12))
	if current:
		var need := GameData.CHAMPION_OATH_SEALS
		if c.oath >= need:
			if GameState.champion_can_swear():
				col.add_child(_wrap_label("%s has fought through %d rifts with you and offers to swear to the guild." % [c.name, need], 12))
				var swear := _icon_domain_button("ember", GameData.BUTTON_ICON_PATH["confirm"], "Swear in — joins your roster", func():
					var err := GameState.swear_in_champion()
					if err != "":
						push_warning(err)
					render()
				)
				swear.disabled = not GameState.run.is_empty()
				swear.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				col.add_child(swear)
			else:
				col.add_child(_wrap_label("Ready to swear in — free a roster slot first.", 12, true))
		else:
			col.add_child(_label("Oath %d/%d — seal %d more rift%s together and they'll join your roster for good" % [c.oath, need, need - c.oath, "" if need - c.oath == 1 else "s"], 12, true))
	else:
		var pick := _button("Choose", func(i=offer_idx):
			GameState.choose_champion(i)
			render()
		)
		pick.disabled = not GameState.run.is_empty()
		pick.tooltip_text = "Can't swap mid-rift" if pick.disabled else "Replace the current Champion"
		pick.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(pick)
	row.add_child(col)
	card.add_child(row)
	return card


func _render_recruits(v: VBoxContainer) -> void:
	_coach(v, "recruits", "Hiring heroes", "Your Champion joins every rift for free. Below it, hire heroes with Recruit — higher ranks are stronger. A party can take up to 4 heroes plus the Champion.")
	var champ := GameState.ensure_champion()
	v.add_child(_label("Champion — joins every rift for free", 16))
	v.add_child(_champion_card(champ, true))
	var champ_weapon_row := HBoxContainer.new()
	champ_weapon_row.add_theme_constant_override("separation", 8)
	for i in GameData.weapon_slots(champ.pool_id):
		champ_weapon_row.add_child(_equip_slot_frame(champ, "weapon", i))
	for i in GameData.gear_slots(champ.rank):
		champ_weapon_row.add_child(_equip_slot_frame(champ, "gear", i))
	v.add_child(champ_weapon_row)
	if expanded_slot.begins_with("%s:weapon:" % champ.id):
		_render_equip_picker(v, champ, "weapon", int(expanded_slot.split(":")[2]))
	if expanded_slot.begins_with("%s:gear:" % champ.id):
		_render_equip_picker(v, champ, "gear", int(expanded_slot.split(":")[2]))

	if not GameState.champion_offers.is_empty():
		v.add_child(_label("Or swap in another Champion (their gear comes back to you, the oath starts over):", 13, true))
		var offers := HFlowContainer.new()
		offers.add_theme_constant_override("h_separation", 10)
		offers.add_theme_constant_override("v_separation", 10)
		for i in GameState.champion_offers.size():
			offers.add_child(_champion_card(GameState.champion_offers[i], false, i))
		v.add_child(offers)
	var reroll := _icon_button(GameData.CURRENCY_ICON_PATH["coins"], "New offers (%dc)" % GameData.CHAMPION_REROLL_COST, func():
		var err := GameState.reroll_champion()
		if err != "":
			push_warning(err)
		render()
	)
	reroll.disabled = GameState.coins < GameData.CHAMPION_REROLL_COST
	reroll.tooltip_text = "A free set of offers also arrives every time you seal a rift."
	v.add_child(reroll)
	v.add_child(_wrap_label("Rank odds: %s%s" % [GameData.rank_odds_text(), "  ·  Scouts' Lodge: a C+ recruit is assured each refresh" if GameState.headhunter_guarantee() else ""], 11, true))
	v.add_child(_hsep())

	v.add_child(_label("Hero Recruits — %d/%d roster slots" % [GameState.heroes.size(), GameState.hero_slot_cap()]))
	for h in GameState.recruit_pool:
		var rank := GameData.find_rank(h.rank)
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Palette.SURFACE2
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Palette.LINE
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_right = 8
		style.corner_radius_bottom_left = 8
		style.content_margin_left = 8.0
		style.content_margin_top = 6.0
		style.content_margin_right = 8.0
		style.content_margin_bottom = 6.0
		card.add_theme_stylebox_override("panel", style)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_framed_portrait(h.cls_id, h.pool_id, 56.0))
		var mid := _vbox(2)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_child(_label(h.name, 13))
		mid.add_child(_label("Rank %s %s · %dc" % [h.rank, h.cls_id.capitalize(), int(rank["cost"])], 11, true))
		mid.add_child(_rich_line("Passive — " + _passive_bb(h.pool_id), 10, true))
		row.add_child(mid)
		row.add_child(_button("Reroll (%dc)" % GameState.recruit_reroll_cost(), func(id=h.id):
			var err := GameState.reroll_recruit_offer(id)
			if err != "":
				push_warning(err)
			render()
		))
		row.add_child(_icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["recruits"], "Recruit", func(id=h.id):
			var err := GameState.recruit_hero(id)
			if err != "":
				push_warning(err)
			render()
		))
		card.add_child(row)
		v.add_child(card)


func _render_medical_bay(v: VBoxContainer) -> void:
	v.add_child(_label("Medical Bay — %d/%d beds occupied" % [GameState.occupied_beds(), GameState.medical_bed_cap()], 16))
	if GameState.field_triage_available():
		v.add_child(_wrap_label("Field Triage: once per rift, get a downed hero back up mid-rift.", 12, true))

	var scene_size := Vector2(700, 200)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size

	var bg := TextureRect.new()
	bg.texture = load(GameData.MEDICAL_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)

	var bedded: Array[Hero] = []
	bedded.assign(GameState.heroes.filter(func(h): return GameState.needs_recovery(h) and h.bedded))
	var waiting: Array[Hero] = []
	waiting.assign(GameState.heroes.filter(func(h): return GameState.needs_recovery(h) and not h.bedded))

	var cap := GameState.medical_bed_cap()
	var bed_w := 64.0
	var bed_h := 40.0
	var gap: float = (scene_size.x - cap * bed_w) / (cap + 1)
	for i in cap:
		var bx: float = gap + i * (bed_w + gap)
		var by := scene_size.y - bed_h - 24.0
		var bed_rect := _icon(GameData.BED_ICON, int(bed_w))
		var bed_wrap := _wrap_icon(bed_rect)
		bed_wrap.position = Vector2(bx, by)

		if i < bedded.size():
			var h: Hero = bedded[i]
			bed_rect.modulate = Color(0.8, 0.85, 1.0)
			scene.add_child(bed_wrap)
			var name_label := _label(h.name.split(" the ")[0], 10, true)
			name_label.position = Vector2(bx - 10, by + bed_h + 2)
			scene.add_child(name_label)
			var time_label := _label(_recovery_text(h, true), 10, true)
			time_label.position = Vector2(bx - 10, by + bed_h + 16)
			scene.add_child(time_label)
		else:
			scene.add_child(bed_wrap)
			var bed_btn := _button("", func(idx=i):
				medical_picker_bed = -1 if medical_picker_bed == idx else idx
				render()
			)
			bed_btn.flat = true
			bed_btn.custom_minimum_size = Vector2(bed_w, bed_h)
			bed_btn.size = Vector2(bed_w, bed_h)
			bed_btn.position = Vector2(bx, by)
			var clear_style := StyleBoxEmpty.new()
			for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
				bed_btn.add_theme_stylebox_override(style_name, clear_style)
			bed_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			scene.add_child(bed_btn)
			var empty_label := _label("Empty", 10, true)
			empty_label.position = Vector2(bx + 6, by + bed_h + 2)
			scene.add_child(empty_label)

	v.add_child(scene)

	if medical_picker_bed >= 0 and medical_picker_bed < cap:
		var picker := _vbox(4)
		if waiting.is_empty():
			picker.add_child(_label("No wounded heroes waiting for a bed.", 12, true))
		else:
			picker.add_child(_label("Assign to bed %d:" % (medical_picker_bed + 1), 12, true))
			for h in waiting:
				var status := "downed" if h.is_downed() else "wounded"
				var row := HBoxContainer.new()
				row.add_child(_label("%s — %d/%d HP (%s)" % [h.name, h.hp, Combat.max_hp(h), status]))
				row.add_child(_icon_domain_button("ember", "res://assets/skills/heart.png", "Assign", func(id=h.id):
					GameState.assign_to_bed(id)
					medical_picker_bed = -1
					render()
				))
				picker.add_child(row)
		v.add_child(picker)

	if medical_picker_bed == -1 and not waiting.is_empty():
		v.add_child(_label("Recovering without a bed (slower) — click an empty bed to assign one:", 12, true))
		for h in waiting:
			v.add_child(_label("%s — %d/%d HP · %s" % [h.name, h.hp, Combat.max_hp(h), _recovery_text(h, false)], 12))

	# Time only passes when a run ends — resting passes it without one.
	v.add_child(_hsep())
	var rest := _icon_button("res://assets/skills/heart.png", "Rest the guild (pass one run's time)", func():
		GameState.rest_guild()
		render()
	)
	rest.tooltip_text = "Heroes recover as if a run had ended. The Rift Map's rifts count down too — one that closes spills out as a Riftbreak."
	rest.disabled = not GameState.run.is_empty()
	v.add_child(rest)
	v.add_child(_wrap_label("Recovery counts rift runs, not real time: a downed hero sits out %d run(s) (a bed takes one off); a wounded hero regains %d%% HP each run (all of it in a bed)." % [GameState.recovery_runs(), int(GameData.WOUND_HEAL_PER_RUN * 100)], 12, true))


## "back in 2 runs" / "full after next run" — recovery in runs, not seconds.
func _recovery_text(h: Hero, bedded: bool) -> String:
	if h.is_downed():
		return "back in %d run%s" % [h.down_runs, "" if h.down_runs == 1 else "s"]
	if bedded:
		return "full after next run"
	return "+%d%% HP per run" % int(GameData.WOUND_HEAL_PER_RUN * 100)


## Plays a short "pop into existence" reveal on a freshly-appended icon
## (the item/relic Crafting Hall just produced) before the caller's render()
## replaces the whole screen — scale up from tiny + a bright flash, not a
## looping effect since it only ever plays once per craft.
func _play_craft_flourish(v: VBoxContainer, icon_path: String) -> void:
	AudioManager.play_sfx(GameData.SFX_PATH["craft"])
	var rect := _icon(icon_path, 40)
	var wrap := _wrap_icon(rect)
	wrap.scale = Vector2(0.2, 0.2)
	wrap.modulate = Color(1.6, 1.5, 1.9)
	v.add_child(wrap)
	var tween := create_tween()
	tween.tween_property(wrap, "scale", Vector2(1, 1), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(wrap, "modulate", Color(1, 1, 1), 0.4)
	await _await_or_timeout(tween.finished, 1.0)


## A workbench hub for turning excess common/rare loot into something better
## instead of just selling it: feed 3 unequipped items (same category+rarity)
## or 3 unequipped relics (same type+rarity) into one craft for 1 of the next
## rarity up. Reuses Combat.gen_item/gen_relic entirely — no new loot tables.
## "2/3 — need 1 more" until a craft is possible, then how many crafts.
func _craft_count(count: int) -> String:
	if count < 3:
		return "%d/3 — need %d more" % [count, 3 - count]
	return "%d owned — ready to craft%s" % [count, " (x%d)" % (count / 3) if count >= 6 else ""]


func _render_crafting_hall(v: VBoxContainer) -> void:
	v.add_child(_label("Crafting Hall", 20))
	v.add_child(_label("Combine 3 of the same kind and rarity into 1 of the next rarity up.", 12, true))

	var scene_size := Vector2(700, 200)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size
	var bg := TextureRect.new()
	bg.texture = load(GameData.CRAFTING_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)
	v.add_child(scene)

	var craft_icon: String = GameData.CAMP_HUB_ICON_PATH["crafting"]

	v.add_child(_label("Items", 16))
	var item_groups: Dictionary = {}
	for it in GameState.items:
		if it.equipped_to != "" or not GameState.CRAFT_RARITY_UP.has(it.rarity):
			continue
		var key := "%s|%s" % [it.category, it.rarity]
		item_groups[key] = int(item_groups.get(key, 0)) + 1
	if item_groups.is_empty():
		v.add_child(_label("No craftable (unequipped Common/Rare) items.", 12))
	for key in item_groups.keys():
		var parts: PackedStringArray = key.split("|")
		var category: String = parts[0]
		var rarity: String = parts[1]
		var count: int = item_groups[key]
		var next_rarity: String = str(GameState.CRAFT_RARITY_UP[rarity])
		var craft_btn := _icon_button(craft_icon, "Craft → %s" % GameData.find_rarity(next_rarity)["name"], func(c=category, r=rarity):
			if _crafting_animating:
				return
			_crafting_animating = true
			if GameState.state_changed.is_connected(render):
				GameState.state_changed.disconnect(render)
			GameState.craft_items(c, r)
			await _play_craft_flourish(v, GameData.ITEM_CATEGORY_ICON_PATH[c])
			if not GameState.state_changed.is_connected(render):
				GameState.state_changed.connect(render)
			_crafting_animating = false
			render()
		)
		craft_btn.disabled = count < 3
		v.add_child(_info_row("%s %s — %s" % [GameData.find_rarity(rarity)["name"], GameData.ITEM_CATEGORY_LABEL[category], _craft_count(count)], 13, [craft_btn], _icon(GameData.ITEM_CATEGORY_ICON_PATH[category], 20), count < 3))

	v.add_child(_hsep())
	v.add_child(_label("Relics", 16))
	var relic_groups: Dictionary = {}
	for r in GameState.relics:
		if r.equipped or not GameState.CRAFT_RARITY_UP.has(r.rarity):
			continue
		var rkey := "%s|%s" % [r.type, r.rarity]
		relic_groups[rkey] = int(relic_groups.get(rkey, 0)) + 1
	if relic_groups.is_empty():
		v.add_child(_label("No craftable (unequipped Common/Rare) relics.", 12))
	for rkey in relic_groups.keys():
		var rparts: PackedStringArray = rkey.split("|")
		var rtype: String = rparts[0]
		var rrarity: String = rparts[1]
		var rcount: int = relic_groups[rkey]
		var rnext_rarity: String = str(GameState.CRAFT_RARITY_UP[rrarity])
		var rcraft_btn := _icon_button(craft_icon, "Craft → %s" % GameData.find_rarity(rnext_rarity)["name"], func(t=rtype, r2=rrarity):
			if _crafting_animating:
				return
			_crafting_animating = true
			if GameState.state_changed.is_connected(render):
				GameState.state_changed.disconnect(render)
			GameState.craft_relics(t, r2)
			await _play_craft_flourish(v, GameData.RELIC_TYPE_ICON_PATH[t])
			if not GameState.state_changed.is_connected(render):
				GameState.state_changed.connect(render)
			_crafting_animating = false
			render()
		)
		rcraft_btn.disabled = rcount < 3
		v.add_child(_info_row("%s %s — %s" % [GameData.find_rarity(rrarity)["name"], rtype, _craft_count(rcount)], 13, [rcraft_btn], _icon(GameData.RELIC_TYPE_ICON_PATH[rtype], 20), rcount < 3))




## Pure checklist, no reward tied to completion — three sections (Monsters,
## Bosses, Hazards) each grayed-out/silhouetted until GameState's matching
## _seen/_defeated array records it, full color once encountered. Reuses
## existing art everywhere (monster sprites, HAZARD_BG illustrations) — no
## new generation beyond the one hub icon.
const MONSTER_ABILITY_DESC := {
	"poison": "poisons its target for a few rounds",
	"healer": "heals its allies each round",
	"shielded": "starts the fight behind a ward",
	"frenzy": "hits harder when badly hurt",
	"drain": "heals itself from the damage it deals",
	"reflect": "reflects part of the damage it takes",
}


## A card per creature: art and what it does once you've met it, a dark
## silhouette and "???" until then.
func _render_bestiary(v: VBoxContainer) -> void:
	v.add_child(_label("Bestiary", 20))
	var groups := [
		["Monsters", GameData.MONSTER_NAMES, "Monster"],
		["Elites", GameData.ELITE_NAMES, "Elite"],
		["Rift Wardens", GameData.BOSS_NAMES, "Boss"],
	]
	for g in groups:
		var names: Array = g[1]
		var seen_n: int = names.filter(func(n): return GameState.monsters_seen.has(n)).size()
		v.add_child(_label("%s — %d/%d met" % [g[0], seen_n, names.size()], 15))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		for mname in names:
			flow.add_child(_bestiary_card(str(mname), str(g[2])))
		v.add_child(flow)
		v.add_child(_hsep())

	v.add_child(_label("Hazards — %d/%d met" % [GameData.HAZARD_TYPES.filter(func(h): return GameState.hazards_seen.has(str(h["id"]))).size(), GameData.HAZARD_TYPES.size()], 15))
	var hflow := HFlowContainer.new()
	hflow.add_theme_constant_override("h_separation", 8)
	hflow.add_theme_constant_override("v_separation", 8)
	for hz in GameData.HAZARD_TYPES:
		var seen: bool = GameState.hazards_seen.has(str(hz["id"]))
		var card := PanelContainer.new()
		card.custom_minimum_size.x = 180
		var cv := _vbox(4)
		var art := _banner(GameData.HAZARD_BG.get(str(hz["id"]), ""), 156, 70)
		if not seen:
			art.modulate = Color(0.2, 0.2, 0.25)
		cv.add_child(art)
		cv.add_child(_label(str(hz["name"]) if seen else "???", 13))
		if seen:
			var mult := float(hz["dmg_mult"])
			var sev := _label("%s · finds %s" % [_hazard_severity_label(mult), "Coins" if str(hz["bonus_type"]) == "coins" else "Crystals"], 12)
			sev.add_theme_color_override("font_color", _hazard_severity_color(mult))
			cv.add_child(sev)
		card.add_child(cv)
		hflow.add_child(card)
	v.add_child(hflow)


func _bestiary_card(mname: String, tier: String) -> PanelContainer:
	var seen: bool = GameState.monsters_seen.has(mname)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(180, 0)
	var cv := _vbox(3)
	var art := _sprite_fit(GameData.sprite_for_monster(mname), 90.0 / 200.0, 156.0)
	if not seen:
		art.modulate = Color(0.08, 0.07, 0.12)
	var art_row := CenterContainer.new()
	art_row.custom_minimum_size.y = 94
	art_row.add_child(art)
	cv.add_child(art_row)
	var nl := _label(mname if seen else "???", 13)
	cv.add_child(nl)
	var tl := _label(tier, 12, true)
	tl.add_theme_color_override("font_color", Palette.ELITE if tier != "Monster" else Palette.MUTED)
	cv.add_child(tl)
	if seen:
		var ability: Dictionary = GameData.MONSTER_ABILITIES.get(mname, {})
		if not ability.is_empty():
			cv.add_child(_wrap_label("%s — %s" % [str(ability["name"]), MONSTER_ABILITY_DESC.get(str(ability["kind"]), "")], 12, true))
		elif tier == "Boss":
			var beaten: bool = GameState.bosses_defeated.has(mname)
			cv.add_child(_wrap_label("Brings a random warden mechanic each fight. %s" % ("Defeated." if beaten else "Not yet defeated."), 12, true))
	card.add_child(cv)
	return card


func _compendium_tab_row(v: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for entry in [["items", "Items"], ["relics", "Relics"], ["crafting", "Crafting"], ["systems", "Systems"]]:
		var tid: String = entry[0]
		var tlabel: String = entry[1]
		var btn := _icon_button("", tlabel, func(id=tid):
			compendium_tab = id
			render()
		)
		btn.disabled = compendium_tab == tid
		row.add_child(btn)
	v.add_child(row)
	v.add_child(_hsep())


func _render_compendium(v: VBoxContainer) -> void:
	v.add_child(_label("Compendium", 20))
	_compendium_tab_row(v)
	match compendium_tab:
		"items": _render_compendium_items(v)
		"relics": _render_compendium_relics(v)
		"crafting": _render_compendium_crafting(v)
		_: _render_compendium_systems(v)


func _render_compendium_items(v: VBoxContainer) -> void:
	v.add_child(_wrap_label("Items are hero-bound gear. Weapon items fill a hero's weapon slots (1, or 2 for a dual-wield class); Armor and Focus items share one \"gear\" slot pool that grows with hero rank.", 12, true))
	for category in GameData.ITEM_CATEGORIES:
		v.add_child(_hsep())
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(_icon(str(GameData.ITEM_CATEGORY_ICON_PATH.get(category, "")), 28))
		head.add_child(_label(str(GameData.ITEM_CATEGORY_LABEL.get(category, category)), 16))
		v.add_child(head)
		for kind in GameData.ITEM_CATEGORY_KINDS.get(category, []):
			v.add_child(_wrap_label("• %s" % str(_KIND_LABEL.get(kind, kind)), 12, true))


func _render_compendium_relics(v: VBoxContainer) -> void:
	v.add_child(_wrap_label("Relics are party-wide. Each relic has an elemental type; equipping 3+ of one type grants that type's synergy bonus. A relic's type also nudges (60% weight) which power domain its rolled special favors.", 12, true))
	for rtype in GameData.RELIC_TYPES:
		v.add_child(_hsep())
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(_icon(str(GameData.RELIC_TYPE_ICON_PATH.get(rtype, "")), 28))
		var domain := str(GameData.TYPE_DOMAIN.get(rtype, ""))
		head.add_child(_label("%s — %s domain" % [rtype, domain.capitalize()], 15))
		v.add_child(head)
		var synergy: Dictionary = GameData.SYNERGY_BONUS.get(rtype, {})
		if not synergy.is_empty():
			v.add_child(_wrap_label("Synergy (3+ equipped): %s" % str(synergy.get("label", "")), 12, true))
		var matchup: Dictionary = GameData.TYPE_MATCHUPS.get(rtype, {})
		if not matchup.is_empty():
			var strong: Array = matchup.get("strong_vs", [])
			var weak: Array = matchup.get("weak_vs", [])
			v.add_child(_wrap_label("Strong vs %s · Weak vs %s" % [", ".join(strong), ", ".join(weak)], 12, true))


func _render_compendium_crafting(v: VBoxContainer) -> void:
	v.add_child(_wrap_label("The Crafting Hall combines 3 unequipped items or relics of the same category/type and rarity into 1 of the next rarity up.", 12, true))
	for rarity in GameState.CRAFT_RARITY_UP:
		v.add_child(_wrap_label("• 3× %s → 1× %s" % [str(rarity).capitalize(), str(GameState.CRAFT_RARITY_UP[rarity]).capitalize()], 13))
	v.add_child(_wrap_label("Legendary items/relics are fixed hand-authored drops — not craftable from Epics.", 12, true))


func _render_compendium_systems(v: VBoxContainer) -> void:
	var entries := [
		["Guild Management", "Spend Crystals on 9 upgrades across 4 branches. Every level adds its effect; Lv3 and Lv5 unlock a perk (a first-strike bonus, a boss Crystal cache, extra relic slots…). Guild Tier tracks total levels."],
		["Daily Rift", "Once you have sealed a rift, the Rift Hall offers one Daily Rift attempt per day. Its rule, starting boon, region and layout come from the date, so every guild faces the same rift that day. Sealing it pays bonus Crystals and Seal Tokens and grows your streak. Records (in the Guild Hall) track achievements, lifetime statistics and your last 30 runs; the Memorial remembers heroes lost for good."],
		["Boss phases", "Every boss changes once it drops to half health: Call the Horde (two foes join), Fury (hits 20% harder and winds up more often) or Last Bastion (a ward worth 12% of its health). Its plate shows which, and the warning bar calls it out as it gets close, so save burst and Defend for the turn."],
		["Elite affixes", "Elites roll an affix: Vampiric, Thorned, Shielded, Venomous, Juggernaut, Blazing, Hasted (acts twice) or Commander (brings two escorts). Endless and B-rank+ mapped rifts give them two. Hover the badges on their plate to read them."],
		["Boons", "Beating an elite in a rift offers 1 of 3 boons that last until that rift ends. Boons come in seven families (Ember, Frost, Blood, Steel, Storm, Shadow, Holy); owning 2 of a family adds a set bonus and 4 a strong capstone, so a run can grow into a build. Not offered in the Tower."],
		["Guild Orders", "Lv2 of the Infirmary, Drill Yard, Trade Network and Scouts' Lodge each unlock an order you can call inside a rift: Supply Drop (heal 35% between fights), Rally (act first and hit 30% harder this round), Requisition (reroll a fight's loot) and Scout Ahead (reroll a fork). 1 order per rift, 2 at Renowned tier, 3 at Legendary."],
		["Rift Map & Riftbreak", "6 rifts rotate on the map, each with a rank (F through SSS) and a countdown — higher rank means a shorter fuse. An unaddressed rift Riftbreaks, forcing an encounter (or a resource penalty) the next time you return to the Terminal."],
		["Hero Bonds", "Certain subclass pairs (e.g. Duelist + Blade-Dancer) grant a bonus while both are alive in the active party — shown in Party Assembly when both halves are picked."],
		["Party Synergy", "Resonance: 2+ party members currently building the same skill kind reinforce each other. Eclectic: a 3+ party with no kind repeated gets a small universal bonus instead. Never both at once — shown in Party Assembly."],
		["Ability Awakening", "Spend Skill Points once to grant a hero's Active Ability a secondary effect (varies by ability — a shorter cooldown, a lingering debuff, a party dodge boost, a self-shield, or a small permanent damage stack) instead of only ever growing the skill tree's numbers."],
		["Elemental Weakness", "Every hero subclass and every monster carries one of 5 elemental types. Attacking a weak-matched type deals bonus damage; attacking a strong-matched type deals less."],
		["Formation", "Heroes and monsters can sit front or back row. Retaliation is biased toward the front row; back-row monsters take reduced damage from hero attacks."],
		["Bestiary", "Every monster, boss, and hazard you've encountered is tracked as a silhouette-to-full-color reveal — pure record-keeping, no reward tied to completion."],
		["Hero Scars", "A knocked-out hero has a chance to pick up a lasting scar (mild stat penalty) on top of their base trait, up to 2 at once. Scrubbed the same way as a trait, once unlocked."],
		["Greater Rift", "Unlocked after sealing 3 rifts of any kind — a new difficulty tier between Lesser and Endless."],
		["Tower of Trials", "Opens with Act II, in the Rift Hall. 100 fixed floors, one fight each: a floor is always the same fight, so a loss is something to plan around. Heroes fight at full HP and leave as they came (no downing, scars or days passing). Most floors carry a rule (armored or burning foes, a swarm, a party cap). Every 10th floor is a guardian that gives a unique relic, and floors 10/25/50/75/100 earn guild titles. Only a first clear pays; floors 91-100 reshuffle their rules every week and pay half for a re-clear."],
		["Foes & regions", "Each rift is in a region (the Vale, the Marshes, the Ashen Wastes) with its own foes. Some foes wind up a heavy blow a turn ahead (x2.5, stuns unless the target Defends); armored foes shrug off part of every basic attack (each hit chips the armor; abilities ignore it); fire foes can burn and frost foes can chill (act late). A Field Tonic cleanses burn, chill, poison and stun."],
		["Campaign", "Three acts, each ending in a finale rift against a named foe. Meet an act\'s objectives (shown in the Rift Hall) to open its finale; sealing it pays a reward and a Legendary relic. Act I opens Greater Rifts, Act II the Endless Rift."],
		["Relics", "Relics sit on the Relic Altar (Inventory) and empower the whole party. Every relic has a special; rare and epic ones also have a trigger that fires in battle (on a kill, every third round, when an ally falls...). 2 relics of one element start a set, 3 complete it, and 3 different elements make a Prism. Level a relic to 5 to awaken a new effect, or reroll any effect for Crystals. Legendary relics have unique powers."],
		["Champions", "A free guest fighter joins every rift. Pick one of three offers each cycle (a new set arrives with every seal). They level with your strongest hero, give the whole party their Boon while standing, and have one Champion Call per rift (key 7 on their turn). Seal 3 rifts with the same Champion and they can swear in to your roster for good."],
		["Attributes", "Might (damage, HP), Agility (speed, dodge, first strike) and Focus (ability power, mend). Heroes gain 3 points per level to spend on the Roster's Hero tab; gear adds more, and better gear needs a minimum in its attribute to equip. Train up to 8 extra points with Coins, or reset a hero's points for 5 Seal Tokens per level (gear they no longer qualify for comes off)."],
		["Guild Board & Milestones", "The Guild Board posts 6 quests (hunts, boss bounties, rift seals, trials); take up to 3 at a time. Unaccepted postings are replaced every 3 days (a day passes with each rift run or rest). Milestones are a static checklist, auto-granted the moment they're met. Reputation occasionally arms a guaranteed Epic relic at the next Shop. Rift Map rifts occasionally carry a bounty, paid out when that specific rift is cleared. A rare escort NPC can also tag along on a fight — surviving pays a small bonus."],
	]
	for entry in entries:
		v.add_child(_label(str(entry[0]), 15))
		v.add_child(_wrap_label(str(entry[1]), 12, true))
		v.add_child(_hsep())


# ---------------- Quests: Guild Board & Milestones ----------------
const INK := Color("3b2414")
const INK_SOFT := Color("6b4a2e")
const QUEST_CATEGORY := {"hunt": "Hunt", "elite": "Hunt", "bounty": "Wanted", "seal_map": "Seal the Rift", "seal_rank": "Seal the Rift",
	"seal_greater": "Seal the Rift", "trial_small": "Trial", "trial_flawless": "Trial", "trial_hardcore": "Trial", "craft": "Supply", "flawless_win": "Trial"}


## The Guild Board: quests pinned as parchment notes on a wooden board —
## taken ones first (red pin, TAKEN stamp), then this posting's offers.
func _render_quests(v: VBoxContainer) -> void:
	var board_w: float = v.custom_minimum_size.x
	var taken: Array = GameState.active_quests()
	var posted: Array = GameState.guild_board.filter(func(q): return str(q["status"]) == "posted")
	var failed: Array = GameState.guild_board.filter(func(q): return str(q["status"]) == "failed")
	var notes: Array = taken + failed + posted
	var cols := 3
	var pad_x := roundf(board_w * 0.075)
	var pad_top := 96.0
	var gap := 16.0
	var note_w := floorf((board_w - pad_x * 2.0 - gap * (cols - 1)) / cols)
	var note_h := 262.0
	var rows: int = max(1, ceili(notes.size() / float(cols)))
	var board_h := pad_top + rows * (note_h + gap) + 46.0
	var board := Control.new()
	board.custom_minimum_size = Vector2(board_w, board_h)
	var bg := TextureRect.new()
	bg.texture = load(GameData.QUEST_BOARD_BG)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.size = Vector2(board_w, board_h)
	board.add_child(bg)
	# The header, chalked onto a plank at the top.
	var head := _vbox(0)
	head.position = Vector2(pad_x, 34)
	head.size = Vector2(board_w - pad_x * 2.0, 60)
	var title := _label("Guild Board", 22)
	title.add_theme_color_override("font_color", Color("f1e2c0"))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	var days_left: int = max(0, GameState.board_refresh_day - GameState.day)
	var sub := _label("Day %d  ·  Taken %d/%d  ·  new postings in %d day%s" % [GameState.day, taken.size(), GameData.QUEST_ACTIVE_MAX, days_left, "" if days_left == 1 else "s"], 13)
	sub.add_theme_color_override("font_color", Color("e0cfa8"))
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	sub.add_theme_constant_override("shadow_offset_y", 1)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.tooltip_text = "A day passes with every rift run or rest. Unaccepted postings are replaced when the board refreshes; quests you've taken stay."
	sub.mouse_filter = Control.MOUSE_FILTER_STOP
	head.add_child(sub)
	board.add_child(head)
	for i in notes.size():
		var q: Dictionary = notes[i]
		var jitter := hash(str(q["id"]))
		var note := _quest_note(q, note_w, note_h, taken.size())
		note.position = Vector2(pad_x + (i % cols) * (note_w + gap) + float(jitter % 9) - 4.0, pad_top + (i / cols) * (note_h + gap) + float((jitter / 9) % 9) - 4.0)
		note.rotation = deg_to_rad(float((jitter / 81) % 7) * 0.7 - 2.1)
		board.add_child(note)
	if notes.is_empty():
		var empty := _label("Nothing posted — new postings in %d day%s." % [days_left, "" if days_left == 1 else "s"], 14)
		empty.add_theme_color_override("font_color", Color("e0cfa8"))
		empty.position = Vector2(pad_x, pad_top + 20)
		board.add_child(empty)
	v.add_child(board)
	v.add_child(_wrap_label("Every 20 Reputation arms a guaranteed Epic relic at your next Shop.", 12, true))
	v.add_child(_hsep())

	v.add_child(_label("Milestones", 16))
	for m in GameData.MILESTONES:
		var mid := str(m["id"])
		var claimed: bool = GameState.milestones_claimed.has(mid)
		var mprogress := GameState.milestone_progress(m)
		var mtarget := int(m["target"])
		var status := "Claimed" if claimed else "%d/%d" % [min(mprogress, mtarget), mtarget]
		v.add_child(_wrap_label("%s [%s]" % [str(m["label"]), status], 12, claimed))
	v.add_child(_hsep())


## One quest as a pinned parchment note.
func _quest_note(q: Dictionary, w: float, h: float, taken_count: int) -> Control:
	var status := str(q["status"])
	var type := str(q["type"])
	var progress := GameState.quest_progress(q)
	var target := int(q["target"])
	var done := status == "active" and progress >= target
	var note := Control.new()
	note.custom_minimum_size = Vector2(w, h)
	note.size = Vector2(w, h)
	note.pivot_offset = Vector2(w, h) * 0.5
	var paper := TextureRect.new()
	var paper_by_cat := {"Hunt": "quest_note_torn", "Wanted": "quest_note_poster"}
	paper.texture = load("res://assets/ui/%s.png" % paper_by_cat.get(QUEST_CATEGORY.get(type, ""), "quest_note"))
	paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	paper.stretch_mode = TextureRect.STRETCH_SCALE
	paper.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	paper.size = Vector2(w, h)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if status == "failed":
		paper.modulate = Color(0.7, 0.68, 0.66)
	note.add_child(paper)
	var col := _vbox(4)
	col.position = Vector2(18, 24)
	col.size = Vector2(w - 36, h - 40)
	var cat := _label(str(QUEST_CATEGORY.get(type, "Quest")).to_upper() if type == "bounty" else str(QUEST_CATEGORY.get(type, "Quest")), 18 if type == "bounty" else 16)
	cat.add_theme_font_override("font", DISPLAY_FONT)
	cat.add_theme_color_override("font_color", Color("7a1f14") if type == "bounty" else INK)
	cat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cat)
	if type == "bounty":
		var mug := TextureRect.new()
		mug.texture = load(GameData.sprite_for_monster(str(q["param"])))
		mug.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mug.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mug.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mug.custom_minimum_size = Vector2(0, 56)
		col.add_child(mug)
	var desc := GameState.quest_desc(q)
	desc = desc.substr(desc.find(": ") + 2) if desc.find(": ") >= 0 else desc
	var dl := _wrap_label(desc[0].to_upper() + desc.substr(1), 13)
	dl.add_theme_color_override("font_color", INK)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(dl)
	var stars := _label("★".repeat(int(q["diff"])) + "☆".repeat(3 - int(q["diff"])), 13)
	stars.add_theme_color_override("font_color", Color("9a5a12"))
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stars.tooltip_text = "Difficulty"
	stars.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(stars)
	var rl := _wrap_label("Reward: " + GameState.quest_reward_desc(q["reward"]), 12)
	rl.add_theme_color_override("font_color", INK_SOFT)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(rl)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)
	match status:
		"posted":
			var full := taken_count >= GameData.QUEST_ACTIVE_MAX
			var take := _button("Take on", func(id=str(q["id"])):
				var err := GameState.accept_quest(id)
				if err != "":
					push_warning(err)
				render()
			)
			take.disabled = full
			take.tooltip_text = "You already have %d quests — finish or abandon one first" % GameData.QUEST_ACTIVE_MAX if full else "Only progress made after taking it counts"
			take.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(take)
		"active":
			if done:
				var claim := _icon_domain_button("ember", GameData.BUTTON_ICON_PATH["confirm"], "Claim reward", func(id=str(q["id"])):
					GameState.claim_quest(id)
					render()
				)
				claim.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				col.add_child(claim)
			else:
				var pr := _label("%d / %d" % [progress, target], 12)
				pr.add_theme_color_override("font_color", INK)
				pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				col.add_child(pr)
				var bar := _flat_bar(target, progress, w - 60, 6, Color("8a3a1a"))
				bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				col.add_child(bar)
				var ab := _button("Abandon", func(id=str(q["id"])):
					GameState.abandon_quest(id)
					render()
				)
				ab.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				ab.add_theme_font_size_override("font_size", 12)
				col.add_child(ab)
		"failed":
			var rm := _button("Take it down", func(id=str(q["id"])):
				GameState.abandon_quest(id)
				render()
			)
			rm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(rm)
	note.add_child(col)
	# The pin: red on quests you've taken, brass on postings.
	var pin := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("b3261e") if status == "active" else (Color("777777") if status == "failed" else Color("c89b3c"))
	ps.set_corner_radius_all(8)
	ps.border_color = Color(0, 0, 0, 0.55)
	ps.set_border_width_all(2)
	pin.add_theme_stylebox_override("panel", ps)
	pin.size = Vector2(16, 16)
	pin.position = Vector2(w * 0.5 - 8, 6)
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(pin)
	# A stamp across the corner for taken / done / failed.
	var stamp_text := "DONE" if done else ("TAKEN" if status == "active" else ("FAILED" if status == "failed" else ""))
	if stamp_text != "":
		var st := _label(stamp_text, 18)
		st.add_theme_font_override("font", DISPLAY_FONT)
		st.add_theme_color_override("font_color", Color(0.2, 0.55, 0.2, 0.8) if done else (Color(0.7, 0.12, 0.1, 0.6) if status == "active" else Color(0.25, 0.25, 0.25, 0.75)))
		st.position = Vector2(14, h - 58) if done else Vector2(10, 30)
		st.rotation = deg_to_rad(-14)
		if not done:
			st.add_theme_font_size_override("font_size", 14)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		note.add_child(st)
	return note


func _render_management(v: VBoxContainer) -> void:
	if mgmt_branch == "":
		_render_management_hub(v)
		return

	var branch: Dictionary = {}
	for b in GameData.BRANCHES:
		if b["id"] == mgmt_branch:
			branch = b
	v.add_child(_banner(GameData.BRANCH_BANNER[mgmt_branch], 700, 150))
	v.add_child(_label("%s — %s" % [branch["name"], branch["sub"]], 16))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for n in branch["nodes"]:
		grid.add_child(_management_node_card(branch, n))
	v.add_child(grid)


## The 4 Guild Management branches as clickable stations on a war-room scene
## (a soldier's kit for Operations, gears/blueprints for Infrastructure, a
## coin pouch/ledger for Logistics, a spellbook/crystal for Research) — same
## background-prop-as-button + hover-glow pattern as the camp screen.
func _render_management_hub(v: VBoxContainer) -> void:
	var scene_size := Vector2(700, 340)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size

	var bg := TextureRect.new()
	bg.texture = load(GameData.MANAGEMENT_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)

	# hit_rect (a generous quadrant of the round table, easy to click) +
	# native_rect (the station's own tight prop bounds in the source 320x200
	# art — helmet+sword north, gears+blueprint east, coin pouch+ledger
	# south, crystal+book west — used only to place the hover glow).
	var branch_entries := [
		["ops", "Operations", Rect2(180, 0, 280, 115), Rect2(97, 7, 96, 45)],
		["infra", "Infrastructure", Rect2(460, 60, 240, 170), Rect2(223, 52, 62, 71)],
		["log", "Logistics", Rect2(180, 210, 280, 130), Rect2(102, 133, 121, 34)],
		["res", "Research", Rect2(0, 60, 220, 170), Rect2(30, 50, 57, 67)],
	]
	var camp_scale := Vector2(700.0 / 320.0, 340.0 / 200.0)
	for entry in branch_entries:
		var bid: String = entry[0]
		var label_text: String = entry[1]
		var hit_rect: Rect2 = entry[2]
		var native_rect: Rect2 = entry[3]
		var glow_rect := Rect2(
			native_rect.position.x * camp_scale.x, native_rect.position.y * camp_scale.y,
			native_rect.size.x * camp_scale.x, native_rect.size.y * camp_scale.y
		)
		var hotspot := _camp_area_hotspot(hit_rect, glow_rect, label_text, func(id=bid):
			mgmt_branch = id
			render()
		)
		hotspot.position = hit_rect.position
		scene.add_child(hotspot)

	v.add_child(scene)

	var reset_btn := _icon_button("res://assets/skills/shard_green.png", "Click again to confirm reset" if confirm_reset else "Reset Guild", func():
		if not confirm_reset:
			confirm_reset = true
			render()
			get_tree().create_timer(3.0).timeout.connect(func():
				confirm_reset = false
				if screen == "terminal" and term_tab == "management" and mgmt_branch == "":
					render()
			)
			return
		confirm_reset = false
		GameState.reset()
		GameState.save()
		screen = "onboard"
		render()
	)
	v.add_child(reset_btn)


## One upgrade node as a card — icon/name header, a level progress bar
## (replaces the old "(Lvl 2/5)" text-only readout), current + next-level
## effect text, then the Upgrade/capstone action — instead of a single
## full-width text row, so a branch's 4-5 nodes read as a grid of cards
## rather than a stack of near-identical lines.
func _management_node_card(branch: Dictionary, n: Dictionary) -> PanelContainer:
	var key := "%s.%s" % [branch["id"], n["id"]]
	var cur := GameState.lvl(key)
	var node_max := int(n["max"])
	var maxed := cur >= node_max
	var icon_path: String = GameData.MANAGEMENT_NODE_ICON.get(key, "")

	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelViolet"
	card.custom_minimum_size.x = 330
	var cv := _vbox(5)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	if icon_path != "":
		header.add_child(_icon(icon_path, 28))
	var nm := _label(str(n["name"]), 15)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(nm)
	header.add_child(_label("Lv %d/%d" % [cur, node_max], 12, true))
	cv.add_child(header)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = node_max
	bar.value = cur
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Palette.SURFACE
	bar_bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Palette.VIOLET_BRIGHT if maxed else Palette.VIOLET
	bar_fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", bar_fill)
	cv.add_child(bar)

	var now := _wrap_label(Combat.describe_node_effect(n["id"], cur), 13)
	now.add_theme_color_override("font_color", Palette.TEXT if cur > 0 else Palette.MUTED)
	cv.add_child(now)
	cv.add_child(_wrap_label("Each level: %s" % n["every"], 11, true))
	var perks: Dictionary = n["perks"]
	for pl in perks:
		var got := cur >= int(pl)
		var is_order := str(perks[pl]).begins_with("Order:")
		var pr := _wrap_label("%s Lv%d — %s" % ["✓" if got else ("⚑" if is_order else "★"), int(pl), perks[pl]], 12)
		pr.add_theme_color_override("font_color", Palette.RANK_E if got else (Palette.EMBER_BRIGHT if is_order else Palette.RANK_S))
		cv.add_child(pr)

	var building: Array = GameData.HAMLET_BUILDINGS.filter(func(hb): return str(hb.get("node", "")) == key)
	if not building.is_empty():
		cv.add_child(_wrap_label("⌂ Camp: the %s is rebuilt at Lv3 and Lv5 (now tier %d/3)" % [building[0]["name"], GameState.hamlet_tier(building[0])], 11, true))
	else:
		cv.add_child(_wrap_label("⌂ Camp: every level grows the Guild Hall (guild tier)", 11, true))

	if not maxed:
		var cost: int = int(n["cost_base"]) + int(n["cost_step"]) * cur
		var next_perk := str(perks.get(cur + 1, ""))
		var ub := _icon_button(icon_path, "Upgrade to Lv%d — %d Crystals" % [cur + 1, cost], func(k=key):
			var err := GameState.upgrade_node(k)
			if err != "":
				push_warning(err)
			render()
		)
		ub.disabled = GameState.crystals < cost
		ub.tooltip_text = "Next: %s%s" % [Combat.describe_node_effect(n["id"], cur + 1), ("\nUnlocks: " + next_perk) if next_perk != "" else ""]
		cv.add_child(ub)
	else:
		var ml := _label("Fully upgraded", 12)
		ml.add_theme_color_override("font_color", Palette.RANK_E)
		cv.add_child(ml)

	card.add_child(cv)
	return card
