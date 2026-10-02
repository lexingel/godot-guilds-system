class_name GuildViews
extends RiftRunView
## Camp-side screens: the camp hub, recruits, medical bay, crafting,
## bestiary, compendium, quests and guild management.

# ---------------- Terminal ----------------
func _render_camp_screen(v: VBoxContainer) -> void:
	var tier := Combat.guild_tier_info()
	var tier_name := str(tier["name"])
	# Guild Tier is purely derived (not stored), so "just reached a new tier"
	# is detected by comparing against the last tier seen at render time —
	# UI-only state, not persisted, same as _flavor_toast above.
	if _last_guild_tier_name != "" and _last_guild_tier_name != tier_name:
		GameState.pending_toasts.append({"cls_id": "", "pool_id": "", "title": tr("Guild tier reached"), "text": GameData.narrative_line("guild_tier_reached")})
	_last_guild_tier_name = tier_name

	if term_tab == "camp":
		if GameState.runs_started == 0:
			_coach(v, "welcome", "Welcome to your guild", "Rifts are tearing open across the land. Your first three heroes have signed on (Roster, key 1). Head to the Rift Hall (key 3) to seal a rift.")
		elif GameState.runs_started >= 1 and GameState.run.is_empty():
			_coach(v, "after_first_run", "Back at camp", "Equip what you found on the Roster's Hero tab (key 1), spend skill points under Skills, and hire more heroes when you can afford them. Every rift run or rest is one day.")
		_render_camp(v)
		return
	var tab_feature: String = {"inventory": "inventory", "medical": "medical", "bestiary": "bestiary", "quests": "quests", "management": "management", "champions": "champions"}.get(term_tab, "")
	if tab_feature != "" and not GameState.feature_unlocked(tab_feature):
		_locked_feature(v, tab_feature)
		return

	match term_tab:
		"inventory": _render_inventory(v)
		"recruits": _render_recruits(v)
		"champions": _render_champions(v)
		"medical": _render_medical_bay(v)
		"management": _render_management(v)
		"bestiary": _render_bestiary(v)
		"compendium": _render_compendium(v)
		"records": _render_records(v)
		"memorial": _render_memorial(v)
		"ledger": _render_ledger(v)
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

	var bleed := _bleed_ui()
	var win := get_viewport().get_visible_rect().size
	var native: Vector2 = GameData.HAMLET_SIZE
	# Framed (portrait window): a whole-number scale keeps the pixels square.
	# Full-window: the village spans the window's width standing on its
	# bottom edge, and its night sky carries on up behind the menus.
	var whole: float = maxf(1.0, floorf(v.custom_minimum_size.x / native.x))
	if bleed:
		whole = minf(win.x / native.x, (win.y - 150.0) / 125.0)
	var SCENE_SIZE := (native * whole).round()
	var sc := Vector2(whole, whole)
	var scene := Control.new()   # the clickable buildings and their plaques
	var art_host: Control = scene   # the picture, tinted by the day/night drift
	if bleed:
		var origin := Vector2(roundf((win.x - SCENE_SIZE.x) * 0.5), win.y - SCENE_SIZE.y)
		scene.position = origin
		scene.size = SCENE_SIZE
		scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scene_ui.add_child(scene)
		art_host = Control.new()
		art_host.position = origin
		art_host.size = SCENE_SIZE
		art_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_scene_art.add_child(art_host)
		var sky := ColorRect.new()
		sky.color = GameData.HAMLET_SKY
		sky.position = -origin
		sky.size = win
		sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_host.add_child(sky)
	else:
		scene.custom_minimum_size = SCENE_SIZE
		scene.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var bg := TextureRect.new()
	bg.texture = load(GameData.HAMLET_BG)
	bg.custom_minimum_size = SCENE_SIZE
	bg.size = SCENE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	art_host.add_child(bg)
	_start_daynight_cycle(art_host if bleed else bg)

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
		var tip := tr(str(b["name"])) + (tr(" — the %s") % tr(str(b["building"])) if b.has("building") else "")
		if str(b.get("tier", "")) == "node":
			tip += tr(" — tier %d/3 (%s Lv%d; grows at Lv3 and Lv5)") % [GameState.hamlet_tier(b), tr(str(GameData.find_branch_node(str(b["node"]))["name"])), GameState.lvl(str(b["node"]))]
		elif b["tier"] == "guild":
			tip += tr(" — grows with your guild tier")
		elif b["tier"] == "act":
			tip += tr(" — grows with the campaign")
		var hotspot := _camp_area_hotspot(rect, rect, tip, targets.get(b["id"], func(): pass), false)
		hotspot.position = rect.position
		scene.add_child(hotspot)
		plaques.append([str(b["name"]), rect, b["row"] == "back", str(PLAQUE_BADGE.get(b["id"], "")), hotspot.get_child(1)])

	# Names show on hover once the player knows the camp. They stay up for
	# the first runs, on touch screens (no hover there), and on a building
	# with something to do (its count badge hangs off the name).
	var all_names := GameState.runs_started <= 3 or _compact() or DisplayServer.is_touchscreen_available()
	for pq in plaques:
		var prect: Rect2 = pq[1]
		var plaque := _camp_plaque(str(pq[0]))
		var py: float = prect.position.y - plaque.size.y - 2.0 if pq[2] else minf(prect.end.y - plaque.size.y - 2.0, SCENE_SIZE.y - plaque.size.y - 2.0)
		plaque.position = Vector2(clampf(prect.get_center().x - plaque.size.x * 0.5, 2.0, SCENE_SIZE.x - plaque.size.x - 2.0), py)
		scene.add_child(plaque)
		var badge: Array = badges.get(str(pq[3]), [])
		if not badge.is_empty():
			var chip := _count_badge(str(badge[0]), str(badge[1]))
			chip.position = plaque.position + Vector2(plaque.size.x - 10.0, -12.0)
			scene.add_child(chip)
		elif not all_names:
			plaque.modulate.a = 0.0
			var hot: Button = pq[4]
			hot.mouse_entered.connect(func(): create_tween().tween_property(plaque, "modulate:a", 1.0, 0.12))
			hot.mouse_exited.connect(func(): create_tween().tween_property(plaque, "modulate:a", 0.0, 0.12))

	# The night moving: stars twinkling across the sky, mist drifting past
	# the hills, fireflies over the grass, the campfire's light flickering.
	var sky_top := -art_host.position.y if bleed else 0.0
	_motes(art_host, Rect2(Vector2(-art_host.position.x if bleed else 0.0, sky_top), Vector2(win.x if bleed else SCENE_SIZE.x, 50.0 * whole - sky_top)),
		Color(1, 1, 1, 0.9), 34, Vector2.ZERO, 3.0, Vector2(maxf(2.0, whole * 0.8), maxf(3.0, whole)))
	_motes(art_host, Rect2(Vector2(0, 95.0 * whole), Vector2(SCENE_SIZE.x, 40.0 * whole)), Color(0.75, 0.75, 0.95, 0.07), 9, Vector2(9, 0), 22.0, Vector2(2.5, 4.5), 8.0, true)
	_motes(art_host, Rect2(Vector2(0, 135.0 * whole), Vector2(SCENE_SIZE.x, 40.0 * whole)), Color(0.85, 1.0, 0.45, 0.9), 16, Vector2(12, 0), 4.0, Vector2(maxf(2.0, whole * 0.7), maxf(2.0, whole)))
	var fire: Vector2 = GameData.HAMLET_BUILDINGS.filter(func(b): return b["id"] == "campfire")[0]["pos"]
	_glow(art_host, Vector2(fire.x, fire.y - 14.0) * whole, 34.0 * whole, Color(1.0, 0.55, 0.2, 0.3), "flicker")

	# The status board (with the getting-started steps) top-left over the
	# scene; below it on a narrow screen. Full-window: under the menus.
	if bleed:
		var board_w := _guild_status_board()
		board_w.custom_minimum_size.x = 360
		board_w.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		board_w.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		v.add_child(board_w)
		return
	var board := _guild_status_board()
	if _narrow():
		v.add_child(scene)
		v.add_child(board)
	else:
		board.position = Vector2(10, 10)
		board.custom_minimum_size.x = minf(360.0, SCENE_SIZE.x * 0.42)
		scene.add_child(board)
		v.add_child(scene)


## Which tab's badge each building wears (its count of things to do).
const PLAQUE_BADGE := {"scouts": "recruits", "barracks": "roster", "infirmary": "medical", "lab": "crafting", "vault": "inventory", "board": "quests"}


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
		"gate": func(): screen = "rift_hall"; render(),
		"market": func(): term_tab = "inventory"; inv_category = "items"; render(),
		"vault": func(): term_tab = "inventory"; inv_category = "relics"; render(),
	}


## What needs you right now: each line opens where to act on it.
func _guild_status_board() -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(Palette.INK, 0.8)
	st.set_corner_radius_all(6)
	st.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", st)
	var col := _vbox(0)
	var head := _label("Guild status", 15)
	head.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	col.add_child(head)
	if not GameState.heroes.is_empty():
		col.add_child(_week_strip())
	# The first-guild checklist rides here (it was a second card): the next
	# step still to do, opening where to do it.
	var guide := _getting_started_steps()
	if not guide.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size.y = 4
		col.add_child(gap)
		var gh := HBoxContainer.new()
		var gl := _label(tr("Getting started — %d/%d") % [int(guide["done"]), int(guide["total"])], 12)
		gl.tooltip_text = "\n".join((guide["steps"] as Array).map(func(s): return "○ " + tr(str(s[0]))))
		gl.mouse_filter = Control.MOUSE_FILTER_STOP
		gl.add_theme_color_override("font_color", Palette.MUTED)
		gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gh.add_child(gl)
		var hide := LinkButton.new()
		hide.text = tr("Hide")
		hide.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		hide.add_theme_font_size_override("font_size", 12)
		hide.add_theme_color_override("font_color", Palette.MUTED)
		hide.tooltip_text = tr("Hide the getting-started steps")
		hide.pressed.connect(func():
			GameState.guide_hidden = true
			GameState.save()
			render())
		gh.add_child(hide)
		col.add_child(gh)
	var lines: Array = (guide.get("steps", []) as Array).slice(0, 1) + _guild_status_lines()
	if lines.is_empty():
		col.add_child(_label("All quiet. The rifts are waiting.", 12, true))
	for ln in lines.slice(0, 7 if not guide.is_empty() else 6):
		var b := Button.new()
		b.flat = true
		b.text = ("○  " if ln.size() > 3 else "›  ") + tr(str(ln[0]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 14)
		# One colour for the list, red only for what's urgent (it used five).
		b.add_theme_color_override("font_color", Palette.HAZARD if ln[1] == Palette.HAZARD else Palette.TEXT)
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


## This week: days to payday, the bill against the treasury, and what the
## guild has made since the last one. Click for the Ledger.
func _week_strip() -> Control:
	var f := GameState.payday_forecast()
	var box := _vbox(1)
	var top := _label(tr("This week · payday in %d day%s") % [int(f["days"]), tr(str(_pl(int(f["days"]))))], 12)
	top.add_theme_color_override("font_color", Palette.MUTED)
	box.add_child(top)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	bar.max_value = maxi(1, int(f["bill"]))
	bar.value = mini(int(f["have"]), int(f["bill"]))
	var fill := StyleBoxFlat.new()
	fill.bg_color = Palette.RANK_E if int(f["short"]) == 0 else Palette.HAZARD
	var back := StyleBoxFlat.new()
	back.bg_color = Color(Palette.LINE, 0.6)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", back)
	box.add_child(bar)
	var bill := tr("Bill %d (wages %d + upkeep %d) · %s") % [int(f["bill"]), int(f["wages"]), int(f["upkeep"]), tr(str("covered" if int(f["short"]) == 0 else tr("short %d") % int(f["short"])))]
	var bl := _label(bill, 12)
	bl.add_theme_color_override("font_color", Palette.COINS if int(f["short"]) == 0 else Palette.HAZARD)
	box.add_child(bl)
	var since := int(f["since"])
	box.add_child(_label(tr("Since last payday: %s%d Gold") % [tr(str("+" if since >= 0 else "")), since], 11, true))
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.tooltip_text = tr("Wages go out every %d days, heroes in roster order, then facility upkeep. Unpaid heroes lose morale; unpaid upkeep costs Renown. Click for the Ledger.") % GameData.PAYDAY_DAYS
	box.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			term_tab = "ledger"
			render())
	return box


## [text, colour, action] for the status board, most urgent first.
func _guild_status_lines() -> Array:
	var out: Array = []
	var go_term := func(tab: String): return func(): term_tab = tab; render()
	var go_screen := func(s: String): return func(): screen = s; render()
	if GameState.heroes.is_empty():
		out.append(["Hire your first hero in Recruits", Palette.EMBER_BRIGHT, go_term.call("recruits")])
	if GameState.breach_broken():
		out.append([tr("The rift has broken! Defend near %s") % GameState.breach_place(), Palette.HAZARD, go_screen.call("defense")])
	elif GameState.breach_active():
		var dl := GameState.breach_days_left()
		out.append([tr("A Rank %s rift breaks in %d day%s") % [tr(GameState.breach_rank_id()), dl, tr(str(_pl(dl)))], Palette.EMBER_BRIGHT, go_screen.call("rift_hall")])
	if not GameState.damaged.is_empty():
		out.append([tr("%d building%s damaged: repair in Manage") % [GameState.damaged.size(), tr(str(_pl(GameState.damaged.size())))], Palette.HAZARD, go_term.call("management")])
	var act := GameState.current_act()
	if not act.is_empty():
		if GameState.finale_ready():
			out.append([tr("Finale open: %s") % tr(str(act["finale"])), Palette.EMBER_BRIGHT, go_screen.call("rift_hall")])
		else:
			for o in act["objectives"]:
				if not GameState.campaign_objective_met(o):
					var prog := "" if str(o["type"]) == "map_rank" else " (%d/%d)" % [mini(GameState.campaign_objective_progress(o), int(o["target"])), int(o["target"])]
					out.append([tr("Act %s: %s%s") % [tr(str(GameState._roman(int(act["act"])))), tr(str(o["label"])), tr(str(prog))], Palette.TEXT, go_screen.call("rift_hall")])
					break
	if not GameState.heroes.is_empty():
		if not GameState.hero_request.is_empty():
			out.append([GameState.request_title() + tr(" — answer before payday"), Palette.EMBER_BRIGHT, go_term.call("ledger")])
		if not GameState.rival_event.is_empty():
			out.append([GameState.rival_event_title() + (tr(" — by payday") if GameState.rival_event.get("accepted", false) else tr(" — answer before payday")), Palette.RANK_S, go_term.call("ledger")])
		var low := GameState.heroes.filter(func(h): return h.morale < 40)
		if not low.is_empty():
			out.append([tr("%d hero%s with low morale") % [low.size(), tr(str(_pl(low.size(), "es")))], Palette.HAZARD, go_term.call("ledger")])
		var due_soon := GameState.guild_board.filter(func(q): return str(q["status"]) == "active" and GameState.quest_progress(q) < int(q["target"]) and int(q.get("due", 1 << 30)) - GameState.day <= 2)
		if not due_soon.is_empty():
			out.append([tr("%d contract%s due within 2 days") % [due_soon.size(), tr(str(_pl(due_soon.size())))], Palette.HAZARD, go_term.call("quests")])
	var claimable := GameState.guild_board.filter(func(q): return GameState.quest_progress(q) >= int(q["target"]))
	if not claimable.is_empty() and GameState.feature_unlocked("quests"):
		out.append([tr("%d quest%s ready to claim") % [claimable.size(), tr(str(_pl(claimable.size())))], Palette.RANK_E, go_term.call("quests")])
	var down := GameState.heroes.filter(func(h): return h.is_downed())
	var hurt := GameState.heroes.filter(func(h): return GameState.needs_recovery(h) and not h.is_downed())
	if not down.is_empty() or not hurt.is_empty():
		var bits: Array[String] = []
		if not down.is_empty():
			bits.append(tr("%d recovering") % down.size())
		if not hurt.is_empty():
			bits.append(tr("%d wounded") % hurt.size())
		var free := GameState.medical_bed_cap() - GameState.occupied_beds()
		out.append([tr("%s · %d bed%s free") % [tr(str(", ".join(bits))), free, tr(str(_pl(free)))], Palette.HAZARD if not down.is_empty() else Palette.MUTED, go_term.call("medical")])
	var sp := GameState.heroes.filter(func(h): return h.skill_points > 0 or h.attr_points > 0)
	if not sp.is_empty():
		out.append([tr("%d hero%s with points to spend") % [sp.size(), tr(str(_pl(sp.size(), "es")))], Palette.TEXT, go_term.call("roster")])
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
						best = tr("%s Lv%d") % [tr(str(n["name"])), lv + 1]
		if best != "" and GameState.crystals >= best_cost:
			out.append([tr("Upgrade ready: %s (%d Essence)") % [tr(str(best)), best_cost], Palette.CRYSTALS, go_term.call("management")])
	if GameState.feature_unlocked("tower"):
		var f := GameState.tower_next_floor()
		if f > 0:
			out.append([tr("Tower of Trials: floor %d next") % f, Palette.MUTED, go_screen.call("tower")])
	return out


# ---------------- Records & Memorial ----------------

func _render_records(v: VBoxContainer) -> void:
	v.add_child(_label("Records", 20))
	var done := GameData.MILESTONES.filter(func(m): return GameState.milestones_claimed.has(str(m["id"]))).size()
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	for t in [["achievements", tr("Achievements %d/%d") % [done, GameData.MILESTONES.size()]], ["stats", "Statistics"], ["history", "Run history"]]:
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
		for k in ["coins", "crystals", "reputation"]:
			if int(rw.get(k, 0)) > 0:
				bits.append("+%d %s" % [int(rw[k]), tr(str({"coins": "Gold", "crystals": "Essence", "reputation": "Renown"}[k]))])
		var right := _label((tr("Done") if got else "%d/%d" % [prog, int(m["target"])]) + "  ·  " + ", ".join(bits), 12, true)
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
			best_hero = tr("%s (power %d)") % [tr(str(h.name.split(" the ")[0])), best_p]
	var rows := [
		["Days passed", str(GameState.day)],
		["Runs finished", str(GameState.runs_finished)],
		["Rifts sealed", str(GameState.rifts_sealed)],
		["Monsters defeated", str(kills)],
		["Elites / Bosses defeated", "%d / %d" % [GameState.elites_won, GameState.bosses_won]],
		["Flawless fights", str(GameState.flawless_wins)],
		["Campaign", "complete" if GameState.campaign_done() else tr("Act %s") % tr(str(GameState._roman(GameState.campaign_act)))],
		["Tower of Trials, best floor", str(GameState.tower_best)],
		["Endless Rift, best time", "%d:%02d" % [GameState.best_endless_time / 60, GameState.best_endless_time % 60]],
		["Daily twists sealed", tr("%d (streak %d)") % [GameState.daily_clears, GameState.daily_streak]],
		["Items and relics crafted", str(GameState.crafts_performed)],
		["Renown", str(GameState.reputation)],
		["Heroes lost", str(GameState.heroes_lost_total)],
		["Strongest hero", best_hero if best_hero != "" else "—"],
		["Most-defeated foe", "%s (%d)" % [tr(str(top_foe)), top_n] if top_foe != "" else "—"],
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
		v.add_child(_label(tr("No runs yet. Your last %d runs will be listed here.") % GameData.RUN_HISTORY_MAX, 13, true))
		return
	for e in GameState.run_history:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var res := str(e["result"])
		var rl := _label(res, 13)
		rl.custom_minimum_size.x = 80
		rl.add_theme_color_override("font_color", Palette.good() if res == "Sealed" else (Palette.HAZARD if res == "Defeated" else Palette.MUTED))
		row.add_child(rl)
		var what := tr("Day %d · %s · floor %s") % [int(e["day"]), tr(str(e["kind"])), tr(str(e["floor"]))]
		if e.has("time"):
			what = tr("Day %d · %s · %d:%02d · %d kills") % [int(e["day"]), tr(str(e["kind"])), int(e["time"]) / 60, int(e["time"]) % 60, int(e.get("kills", 0))]
		var wl := _label(what, 13)
		wl.custom_minimum_size.x = 300
		row.add_child(wl)
		row.add_child(_label(tr("%+d Gold  %+d Essence") % [int(e["coins"]), int(e["crystals"])], 12, true))
		var tip := tr("Party: ") + ", ".join(e["heroes"])
		if not (e.get("boons", []) as Array).is_empty():
			tip += tr("\nBoons: ") + ", ".join((e["boons"] as Array).map(func(b): return str(GameData.find_boon(str(b)).get("name", b))))
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
		col.add_child(_label(tr("%s — Rank %s, Level %d") % [tr(str(f["name"])), tr(str(f["rank"])), int(f["level"])], 14))
		col.add_child(_wrap_label(tr("%s, on day %d. %d rift%s sealed, %d foe%s felled.") % [tr(str(f["cause"])), int(f["day"]), int(f["rifts"]), tr(str(_pl(int(f["rifts"])))), int(f["kills"]), tr(str(_pl(int(f["kills"]))))], 12, true))
		row.add_child(col)
		v.add_child(row)


var _dismiss_confirm: String = ""   # hero id awaiting a second click on Dismiss


## A matter waiting for your answer: a hero's request ("request") or the
## rival's move ("rival"), with faces, the story, and the two answers. In the
## camp pop-up (`popup`) it also offers Decide later.
func _matter_card(kind: String, popup: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"CardPanelEmber" if kind == "request" else &"CardPanelViolet"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var faces := _vbox(6)
	var title := ""
	var body := ""
	var opts: Array = []   # [[text, why disabled or ""], ...]
	var foot := ""
	var answer: Callable
	if kind == "request":
		var req: Dictionary = GameState.hero_request
		var def: Dictionary = GameData.HERO_REQUESTS[req["type"]]
		for id in req["ids"]:
			var h := GameState.find_hero(str(id))
			if h:
				faces.add_child(_hero_icon(h, 64))
		title = GameState.request_title()
		var first := GameState.find_hero(str(req["ids"][0]))
		body = tr(str(def["text"]))
		if body.contains("%s") and first:
			body = body % tr(str(first.name.split(" the ")[0]))
		var ro: Array = GameState.request_options()
		var gear_short: bool = req["type"] == "gear" and GameState.coins < GameData.REQUEST_GEAR_COST
		opts = [[ro[0], tr("Not enough Gold.") if gear_short else ""], [ro[1], ""]]
		foot = "No answer by payday counts as a no."
		answer = GameState.answer_request
	else:
		var ev: Dictionary = GameState.rival_event
		var lead := GameState.rival_leader()
		faces.add_child(_icon_trimmed(str(lead["portrait"]), 64))
		if str(ev["type"]) == "poach":
			var h := GameState.find_hero(str(ev["hero"]))
			if h:
				faces.add_child(_hero_icon(h, 48))
		title = GameState.rival_event_title()
		body = GameState.rival_event_text()
		opts = GameState.rival_event_options()
		foot = {"poach": "No answer by payday: they choose for themselves.", "challenge": "No answer by payday counts as declining.",
			"snatch": "No answer by payday: they take it."}.get(str(ev["type"]), "")
		if ev.get("accepted", false):
			foot = tr("%d day%s to payday.") % [GameState.days_to_payday(), tr(str(_pl(GameState.days_to_payday())))]
		answer = GameState.answer_rival
	row.add_child(faces)
	var col := _vbox(6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := _wrap_label(title, 16)
	t.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if kind == "request" else Palette.RANK_S)
	col.add_child(t)
	col.add_child(_wrap_label(body, 13))
	var letter := GameState.rival_letter() if kind == "rival" else ""
	if letter != "":   # the leader's own note (the Charter War)
		var ll := _wrap_label(letter, 13)
		ll.add_theme_color_override("font_color", Palette.RANK_S)
		col.add_child(ll)
	var btns := HFlowContainer.new()
	btns.add_theme_constant_override("h_separation", 8)
	btns.add_theme_constant_override("v_separation", 6)
	for k in opts.size():
		var yes := k == 0
		var b := _button(str(opts[k][0]), func():
			var err: String = answer.call(yes)
			if err != "":
				_flavor_toast = err
			render())
		if str(opts[k][1]) != "":
			b.disabled = true
			b.tooltip_text = str(opts[k][1])
		btns.add_child(b)
	if popup:
		btns.add_child(_button("Decide later", func():
			if kind == "request":
				GameState.hero_request["seen"] = true
			else:
				GameState.rival_event["seen"] = true
			GameState.save()
			render()))
	col.add_child(btns)
	if foot != "":
		col.add_child(_label(foot + (tr(" Answer in Guild > Ledger.") if popup else ""), 11, true))
	row.add_child(col)
	p.add_child(row)
	return p


## The matter the camp should pop up now: "request", "rival" or "" (each
## once, until it's answered or put off with Decide later).
func _unseen_matter() -> String:
	if not GameState.hero_request.is_empty() and not GameState.hero_request.get("seen", false):
		return "request"
	if not GameState.rival_event.is_empty() and not GameState.rival_event.get("seen", false):
		return "rival"
	return ""


## The week at a glance: a tile per day from today to payday (a day is a rift run
## or a rest), each with what falls on it.
func _week_board() -> Control:
	var today := GameState.day
	var payday := today + GameState.days_to_payday()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var f := GameState.payday_forecast()
	for d in range(today, payday + 1):
		var events: Array = []   # [short text, colour, full text]
		if d == payday:
			events.append([tr("Payday · %d Gold") % int(f["bill"]), Palette.HAZARD if int(f["short"]) > 0 else Palette.COINS,
				tr("Wages %d + upkeep %d Gold; you have %d.") % [GameState.weekly_wages(), GameState.upkeep(), GameState.coins]])
			if not GameState.hero_request.is_empty():
				events.append([tr("Request closes"), Palette.EMBER_BRIGHT, GameState.request_title()])
			if not GameState.rival_event.is_empty():
				events.append([tr("Dare due") if GameState.rival_event.get("accepted", false) else tr("Rival waits"), Palette.RANK_S, GameState.rival_event_title()])
		for q in GameState.active_quests():
			if int(q.get("due", -1)) == d:
				events.append([tr("Contract due"), Palette.HAZARD, GameState.quest_desc(q)])
		if GameState.breach_active() and not GameState.breach_broken() and int(GameState.breach.get("breaks_on", -1)) == d:
			events.append([tr("Rift breaks"), Palette.HAZARD, tr("A Rank %s rift breaks near %s.") % [tr(GameState.breach_rank_id()), GameState.breach_place()]])
		if d > 0 and d % GameData.CONTEST_DAYS == 0:
			events.append([tr("Contest ends"), Palette.RANK_S, tr("The month's Renown contest with %s ends.") % tr(str(GameState.rival_name))])
		var tile := PanelContainer.new()
		tile.theme_type_variation = &"CardPanelEmber" if d == today else &"CardPanel"
		# A day with nothing on it is just its name: three tall cards, two of
		# them empty, made the week look busier than it was.
		if events.is_empty() and d != today:
			tile.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.custom_minimum_size = Vector2(84, 0)
		var tv := _vbox(2)
		var head := _label(tr("Today") if d == today else tr("Day %d") % d, 13)
		head.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if d == today else Palette.MUTED)
		tv.add_child(head)
		var tips: Array[String] = []
		for e in events:
			var l := _label(str(e[0]), 12)
			l.add_theme_color_override("font_color", e[1])
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tv.add_child(l)
			tips.append(str(e[2]))
		if events.is_empty() and d > today:
			tv.add_child(_label(tr("in %d day%s") % [d - today, tr(str(_pl(d - today)))], 11, true))
		tile.add_child(tv)
		tile.tooltip_text = "\n".join(tips)
		row.add_child(tile)
	row.tooltip_text = tr("A day passes with every rift run or rest.")
	return row


## The Ledger: the week board, what waits for an answer,
## the treasury against payday (and the weekly feast), the payroll (each
## hero's pay rate, morale and Dismiss), the rival and standings, and news.


func _render_ledger(v: VBoxContainer) -> void:
	v.add_child(_label("Guild Ledger", 20))
	_coach(v, "ledger", "Paying the guild", tr("A day passes with every rift run or rest; wages are due every %d days. An unpaid hero loses %d morale, and a hero unpaid twice in a row, or at rock-bottom morale on payday, walks out. Every Guild Management level also costs %d Gold a week in upkeep.") % [GameData.PAYDAY_DAYS, -GameData.MORALE_UNPAID, GameData.UPKEEP_PER_LEVEL])
	v.add_child(_week_board())
	if not GameState.hero_request.is_empty():
		v.add_child(_matter_card("request"))
	if not GameState.rival_event.is_empty():
		v.add_child(_matter_card("rival"))
	v.add_child(_treasury_card())
	v.add_child(_payroll_card())
	v.add_child(_rival_card())

	if not GameState.guild_news.is_empty():
		v.add_child(_hsep())
		v.add_child(_label("Guild news", 16))
		for line in GameState.guild_news:
			v.add_child(_wrap_label(str(line), 12, true))


## A Ledger figure: a big number over a small caption.
func _ledger_figure(value: String, caption: String, color: Color, tip: String = "") -> Control:
	var col := _vbox(0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var n := _label(value, 22)
	n.add_theme_color_override("font_color", color)
	col.add_child(n)
	col.add_child(_label(caption, 12, true))
	if tip != "":
		col.tooltip_text = tip
		col.mouse_filter = Control.MOUSE_FILTER_STOP
	return col


## The vault against the coming payday, the last payday, and the week's
## feast and training.
func _treasury_card() -> PanelContainer:
	var f := GameState.payday_forecast()
	var bill := int(f["bill"])
	var after := GameState.coins - bill
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelEmber" if after < 0 else &"CardPanel"
	var cv := _vbox(8)
	cv.add_child(_label("Treasury", 16))
	var figs := HBoxContainer.new()
	figs.add_theme_constant_override("separation", 16)
	figs.add_child(_ledger_figure(str(GameState.coins), tr("Gold in the vault"), Palette.COINS))
	figs.add_child(_ledger_figure(str(bill), tr("Payday in %d day%s") % [int(f["days"]), tr(str(_pl(int(f["days"]))))], Palette.TEXT,
		tr("Wages %d + upkeep %d Gold (%d a week per Guild Management level).") % [int(f["wages"]), int(f["upkeep"]), GameData.UPKEEP_PER_LEVEL]))
	figs.add_child(_ledger_figure(str(after) if after >= 0 else tr("short %d") % -after, tr("Left after payday"), Palette.good() if after >= 0 else Palette.HAZARD))
	var since := int(f["since"])
	figs.add_child(_ledger_figure("%+d" % since, tr("Since last payday"), Palette.TEXT if since >= 0 else Palette.HAZARD, tr("Gold gained or spent since the last payday.")))
	cv.add_child(figs)
	var bar := _flat_bar(maxi(1, bill), mini(GameState.coins, bill), 0.0, 8.0, Palette.RANK_E if after >= 0 else Palette.HAZARD)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.tooltip_text = tr("The vault against the bill.")
	cv.add_child(bar)
	if after < 0:
		var fix := tr("Put some heroes on half pay below")
		if int(f["runs"]) > 0:
			fix = tr("About %d rift run%s at your recent pay would cover it, or put some heroes on half pay below") % [int(f["runs"]), tr(str(_pl(int(f["runs"]))))]
		var fl := _wrap_label(fix + ".", 12)
		fl.add_theme_color_override("font_color", Palette.HAZARD)
		cv.add_child(fl)
	var rep: Dictionary = GameState.payday_report
	if not rep.is_empty():
		var bits: Array[String] = [tr("%d Gold paid") % int(rep.get("paid", 0))]
		if not (rep.get("unpaid", []) as Array).is_empty():
			bits.append(tr("unpaid: %s") % tr(str(", ".join(rep["unpaid"]))))
		if not (rep.get("left", []) as Array).is_empty():
			bits.append(tr("walked out: %s") % tr(str(", ".join(rep["left"]))))
		cv.add_child(_wrap_label(tr("Last payday (day %d): %s.") % [int(rep.get("day", 0)), tr(str("; ".join(bits)))], 12, true))
		var scene: Array = GameData.PAYDAY_SCENES.get(str(rep.get("scene", "")), [])
		if not scene.is_empty():
			# The Guildhold Chronicle: the cast at the pay table.
			var talk := _vbox(2)
			talk.add_child(_label("At the pay table", 12, true))
			for ln in scene:
				talk.add_child(_rich_line("[color=#%s]%s[/color]  %s" % [Palette.EMBER_BRIGHT.to_html(false), tr(str(ln[0])), tr(str(ln[1]))], 13))
			talk.tooltip_text = tr("Wen keeps the guild's chronicle, Dobbs keeps its books, and Old Hesper is the last of an Accord guild: she had a fever on the Night of Breaking and missed it.")
			talk.mouse_filter = Control.MOUSE_FILTER_STOP
			cv.add_child(talk)
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 14)
	acts.add_theme_constant_override("v_separation", 6)
	var feast := _button(tr("Hold a feast · %d Gold") % GameState.feast_cost(), func():
		var err := GameState.hold_feast()
		if err != "":
			_flavor_toast = err
		render()
	)
	feast.disabled = not GameState.feast_ready() or GameState.coins < GameState.feast_cost()
	feast.tooltip_text = tr("+%d morale for up to %d heroes, lowest morale first. Once a week.") % [GameData.FEAST_MORALE, GameState.feast_seats()] if GameState.feast_ready() else tr("Already feasted this week — the next one after payday.")
	acts.add_child(feast)
	var tl := _label(tr("Training Yard: %d of %d trainings left this week") % [GameState.training_left(), GameState.training_slots()], 12, true)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	acts.add_child(tl)
	cv.add_child(acts)
	card.add_child(cv)
	return card


const PAY_RATE_LABEL := {"half": "Half", "full": "Full", "bonus": "Bonus"}


## Every hero's pay, set here: the weekly trade of Gold against morale.
## Rows run in pay order (the roster's): when Gold runs short, the bottom of
## the list goes unpaid.
func _payroll_card() -> PanelContainer:
	var card := PanelContainer.new()
	var cv := _vbox(8)
	var head := HBoxContainer.new()
	var hl := _label("Payroll", 16)
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	var wl := _label(tr("%d Gold a week") % GameState.weekly_wages(), 14)
	wl.add_theme_color_override("font_color", Palette.COINS)
	head.add_child(wl)
	cv.add_child(head)
	var half: Array = GameData.PAY_RATES["half"]
	var bonus: Array = GameData.PAY_RATES["bonus"]
	cv.add_child(_wrap_label(tr("Half pay saves Gold but costs %d morale each payday; a bonus pays %d%% more for +%d morale. Wages go out top to bottom while the Gold lasts.") % [-int(half[1]), int(round((float(bonus[0]) - 1.0) * 100.0)), int(bonus[1])], 12, true))
	var unpaid := GameState.unpaid_if_payday_now()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	var picked := StyleBoxFlat.new()
	picked.bg_color = Palette.VIOLET_DEEP
	picked.set_corner_radius_all(4)
	picked.content_margin_left = 8
	picked.content_margin_right = 8
	picked.content_margin_top = 4
	picked.content_margin_bottom = 4
	for h in GameState.heroes:
		var short: bool = unpaid.has(h.id)
		var who := HBoxContainer.new()
		who.add_theme_constant_override("separation", 8)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.add_child(_hero_icon(h, 36))
		var names := _vbox(0)
		names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var nl := _label(tr(str(h.name.split(" the ")[0])), 14)
		names.add_child(nl)
		var sub := _label(tr("Rank %s · Lv%d") % [tr(str(h.rank)), h.level] + (tr(" · unpaid if payday came now") if short else ""), 11, not short)
		if short:
			sub.add_theme_color_override("font_color", Palette.HAZARD)
		names.add_child(sub)
		who.add_child(names)
		grid.add_child(who)

		var mc := _vbox(3)
		mc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tier: Array = GameData.morale_tier(h.morale)
		var mcol: Color = Palette.good() if h.morale >= 80 else (Palette.MUTED if h.morale >= 40 else Palette.HAZARD)
		mc.add_child(_flat_bar(100, h.morale, 130.0, 6.0, mcol))
		var ml := _label(tr("Morale %d · %s%s%s") % [h.morale, tr(str(tier[1])), tr(str((tr(" (%+d%% damage)") % int(round(float(tier[2]) * 100))) if float(tier[2]) != 0.0 else "")), tr(" · unpaid %d week%s") % [h.unpaid_weeks, tr(str(_pl(h.unpaid_weeks)))] if h.unpaid_weeks > 0 else ""], 11, true)
		ml.add_theme_color_override("font_color", mcol)
		mc.tooltip_text = tr("Sealing a rift +%d · a lost rift %d · knocked out %d · unpaid %d · a week without a rift %d · a failed contract %d · a feast +%d") % [GameData.MORALE_SEAL, GameData.MORALE_DEFEAT, GameData.MORALE_KNOCKOUT, GameData.MORALE_UNPAID, GameData.MORALE_IDLE_WEEK, GameData.MORALE_QUEST_FAILED, GameData.FEAST_MORALE]
		mc.mouse_filter = Control.MOUSE_FILTER_STOP
		mc.add_child(ml)
		grid.add_child(mc)

		var seg := HBoxContainer.new()
		seg.add_theme_constant_override("separation", 2)
		seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var hid: String = h.id
		for rate in ["half", "full", "bonus"]:
			var r: Array = GameData.PAY_RATES[rate]
			var b := _button(tr("%s %d") % [tr(str(PAY_RATE_LABEL[rate])), GameState.wage_at(h, rate)], func(): GameState.set_pay_rate(hid, rate); render())
			b.add_theme_font_size_override("font_size", 13)
			b.tooltip_text = tr("%s: %d Gold a week%s.") % [tr(str(PAY_RATE_LABEL[rate])), GameState.wage_at(h, rate), tr(", %+d morale each payday") % int(r[1]) if int(r[1]) != 0 else ""]
			if GameState.pay_rate_of(h) == rate:
				for sn in ["normal", "hover", "pressed", "focus"]:
					b.add_theme_stylebox_override(sn, picked)
			seg.add_child(b)
		grid.add_child(seg)

		var confirming: bool = _dismiss_confirm == hid
		var db := _button(tr("Confirm: let them go") if confirming else tr("Dismiss"), func():
			if _dismiss_confirm != hid:
				_dismiss_confirm = hid
			else:
				_dismiss_confirm = ""
				var err := GameState.dismiss_hero(hid)
				if err != "":
					_flavor_toast = err
			render()
		)
		db.flat = not confirming
		db.add_theme_font_size_override("font_size", 12)
		db.tooltip_text = "They leave the guild for good; their gear goes back to the stockpile. No more wages."
		db.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(db)
	cv.add_child(grid)
	card.add_child(cv)
	return card


## The rival guild, this month's Renown contest and the guild standings.
func _rival_card() -> PanelContainer:
	var rival := PanelContainer.new()
	rival.theme_type_variation = &"CardPanelViolet"
	var rv := _vbox(6)
	var rlead := GameState.rival_leader()
	var rhead := HBoxContainer.new()
	rhead.add_theme_constant_override("separation", 10)
	rhead.add_child(_icon(str(rlead["crest"]), 40))
	rhead.add_child(_icon_trimmed(str(rlead["portrait"]), 64))
	var rnames := _vbox(0)
	rnames.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rnames.add_child(_label(tr("Rival: %s") % tr(str(GameState.rival_name)), 16))
	rnames.add_child(_label(tr("Led by %s") % tr(str(rlead["leader"])), 12, true))
	rhead.add_child(rnames)
	rv.add_child(rhead)
	var lead := GameState.reputation - GameState.rival_renown
	var rl := _label(tr("Renown — you %d · them %d (%s)") % [GameState.reputation, GameState.rival_renown, tr("you lead by %d") % lead if lead > 0 else (tr("they lead by %d") % -lead if lead < 0 else tr("level"))], 14)
	rl.add_theme_color_override("font_color", Palette.good() if lead > 0 else (Palette.HAZARD if lead < 0 else Palette.TEXT))
	rl.tooltip_text = tr("Renown is the one race with the rival. They gain it every day and sometimes take a posted contract before you do. At payday the leader gets the pick of next week's recruits (one more offer for you, or one fewer); every 20 you earn arms an Epic relic at your next Shop. Seal rifts and finish contracts to gain it; failed contracts and unpaid upkeep cost it.")
	rl.mouse_filter = Control.MOUSE_FILTER_STOP
	rv.add_child(rl)
	var cs := GameState.contest_status()
	var cl := _label(tr("This month: Renown gained — you %d · them %d · %d day%s left. Prize: %d Gold, %d Renown.") % [int(cs["ours"]), int(cs["theirs"]), int(cs["days_left"]), tr(str(_pl(int(cs["days_left"])))), GameData.CONTEST_PRIZE["coins"], GameData.CONTEST_PRIZE["reputation"]], 13)
	cl.add_theme_color_override("font_color", Palette.good() if int(cs["ours"]) > int(cs["theirs"]) else (Palette.HAZARD if int(cs["ours"]) < int(cs["theirs"]) else Palette.TEXT))
	rv.add_child(cl)
	if GameState.feature_unlocked("rival"):
		rv.add_child(_wrap_label("The Crown's herald counts Renown toward the Royal Charter: one guild, every contract, for a generation.", 12, true))
	rv.add_child(_hsep())
	rv.add_child(_label("Guild Standings", 14))
	var table := GridContainer.new()
	table.columns = 5
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 4)
	for head in ["", "Guild", "Renown", "Tower floor", "Endless best"]:
		table.add_child(_label(head, 12, true))
	var rows: Array = GameState.guild_standings()
	for k in rows.size():
		var r: Dictionary = rows[k]
		var col: Color = Palette.EMBER_BRIGHT if r["you"] else Palette.TEXT
		for cell in ["#%d" % (k + 1), tr(str(r["name"])) + (tr(" (you)") if r["you"] else (tr(" — rival") if r["name"] == GameState.rival_name else "")),
				str(r["renown"]), str(r["tower"]), "%d:%02d" % [int(r["endless"]) / 60, int(r["endless"]) % 60]]:
			var l := _label(cell, 13)
			l.add_theme_color_override("font_color", col)
			table.add_child(l)
	rv.add_child(table)
	rv.add_child(_wrap_label("The other guilds' records grow every day. Top the Renown column for an achievement.", 11, true))
	rival.add_child(rv)
	return rival


## The first-guild checklist for the status board, each step ticking off
## from real game state: {done, total, steps: [text, colour, action, true]}
## for the steps still to do. Empty once every step is done, the guild has
## sealed a few rifts, or the player hides it.
func _getting_started_steps() -> Dictionary:
	if GameState.guide_hidden or GameState.rifts_sealed >= 3:
		return {}
	var go := func(tab: String, sub: String): return func(): term_tab = tab; roster_tab = sub; render()
	var hall := func(): screen = "rift_hall"; render()
	var steps := [
		["Assemble a party in the Rift Hall and enter a rift", not GameState.monsters_seen.is_empty(), hall],
		["Equip an item on a hero (Roster > Heroes)", GameState.items.any(func(it): return it.equipped_to != ""), go.call("roster", "hero")],
		["Spend a skill point (Roster > Heroes > Skills)", GameState.heroes.any(func(h): return h.skills.values().has(true)), go.call("roster", "skills")],
		["Seal your first rift by beating its boss", GameState.rifts_sealed >= 1, hall],
	]
	var todo := steps.filter(func(s): return not s[1]).map(func(s): return [s[0], Palette.TEXT, s[2], true])
	if todo.is_empty():
		return {}
	return {"done": steps.size() - todo.size(), "total": steps.size(), "steps": todo}


## Notification counts per camp building: {building label: [badge text,
## tooltip]} — only for things the player can act on right now.
func _camp_badges() -> Dictionary:
	var out := {}
	var needy: Array[String] = []
	for h in GameState.heroes:
		var reasons: Array[String] = []
		if h.skill_points > 0:
			reasons.append(tr("%d SP") % h.skill_points)
		if h.level >= 10:
			var choices := GameData.evolution_choices(GameData.find_class(h.pool_id))
			if not choices.is_empty():
				var nr := GameData.find_rank(str(choices[0]["rank"]))
				if GameState.crystals >= int(nr["cost"]) and GameState.evolve_rank_gate(str(choices[0]["rank"])) == "":
					reasons.append(tr("can evolve"))
		for st in ["weapon", "gear"]:
			if _first_free_slot(h, st) >= 0 and GameState.items.any(func(it): return it.equipped_to == "" and it.slot_type() == st and GameState.item_fits_hero(it, h)):
				reasons.append(tr("empty %s slot") % tr(str(st)))
				break
		if not reasons.is_empty():
			needy.append("%s: %s" % [tr(str(h.name.split(" the ")[0])), tr(str(", ".join(reasons)))])
	if not needy.is_empty():
		out["roster"] = [str(needy.size()), "\n".join(needy)]
	var hurt := GameState.heroes.filter(func(h): return GameState.needs_recovery(h) and not h.bedded)
	if not hurt.is_empty():
		out["medical"] = [str(hurt.size()), tr("%d hero(es) wounded or downed") % hurt.size()]
	if GameState.heroes.size() < GameState.hero_slot_cap():
		var affordable := GameState.recruit_pool.filter(func(h): return GameState.coins >= int(GameData.find_rank(h.rank)["cost"]))
		if not affordable.is_empty():
			out["recruits"] = [str(affordable.size()), tr("%d recruit(s) you can afford") % affordable.size()]
	var craftable := 0
	var groups := {}
	for it in GameState.items:
		if it.equipped_to == "" and it.rarity in ["common", "rare"]:
			var k := "i:%s:%s" % [tr(str(it.category)), tr(str(it.rarity))]
			groups[k] = int(groups.get(k, 0)) + 1
	for r in GameState.relics:
		if not r.equipped and r.rarity in ["common", "rare"]:
			var k2 := "r:%s:%s" % [tr(str(r.type)), tr(str(r.rarity))]
			groups[k2] = int(groups.get(k2, 0)) + 1
	for k in groups:
		craftable += int(groups[k]) / 3
	if craftable > 0:
		out["crafting"] = [str(craftable), tr("%d craft(s) ready in Crafting") % craftable]
	var free_relic_slots := GameState.relic_slot_cap() - Combat.equipped_relics().size()
	var spare_relics := GameState.relics.filter(func(r): return not r.equipped).size()
	if free_relic_slots > 0 and spare_relics > 0:
		out["inventory"] = [str(min(free_relic_slots, spare_relics)), tr("%d relic slot(s) empty — equip a relic under Items > Relics") % free_relic_slots]
	var claimable := GameState.guild_board.filter(func(q): return GameState.quest_progress(q) >= int(q["target"]))
	if not claimable.is_empty():
		out["quests"] = [str(claimable.size()), tr("%d quest(s) ready to claim") % claimable.size()]
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
				[GameData.CAMP_HUB_ICON_PATH["roster"], "Heroes", func(): hub_cluster = ""; term_tab = "roster"; render()],
				[GameData.CAMP_HUB_ICON_PATH["management"], "Management", func(): hub_cluster = ""; term_tab = "management"; render()],
			]
		"guild_hall":
			title = "Guild Hall"
			entries = [
				[GameData.CAMP_HUB_ICON_PATH["management"], "Management", func(): hub_cluster = ""; term_tab = "management"; render()],
				["res://assets/skills/gem_blue_a.png", "Ledger", func(): hub_cluster = ""; term_tab = "ledger"; render()],
				[GameData.CAMP_HUB_ICON_PATH["compendium"], "Codex", func(): hub_cluster = ""; term_tab = "compendium"; render()],
				["res://assets/skills/trophy.png", "Records", func(): hub_cluster = ""; term_tab = "records"; render()],
				["res://assets/skills/helm.png", "Memorial", func(): hub_cluster = ""; term_tab = "memorial"; render()],
			]
		"arcane_lab":
			title = "Arcane Lab"
			entries = [
				[GameData.CAMP_HUB_ICON_PATH["crafting"], "Crafting", func(): hub_cluster = ""; screen = "crafting_hall"; render()],
				[GameData.CAMP_HUB_ICON_PATH["bestiary"], "Bestiary", func(): hub_cluster = ""; term_tab = "bestiary"; render()],
			]
		"trading_post":
			title = "Trading Post"
			entries = [
				[GameData.CAMP_HUB_ICON_PATH["inventory"], "Items", func(): hub_cluster = ""; term_tab = "inventory"; render()],
				[GameData.CAMP_HUB_ICON_PATH["crafting"], "Crafting", func(): hub_cluster = ""; screen = "crafting_hall"; render()],
			]
		"scholars_lodge":
			title = "Scholar's Lodge"
			entries = [
				[GameData.CAMP_HUB_ICON_PATH["bestiary"], "Bestiary", func(): hub_cluster = ""; term_tab = "bestiary"; render()],
				[GameData.CAMP_HUB_ICON_PATH["compendium"], "Codex", func(): hub_cluster = ""; term_tab = "compendium"; render()],
				[GameData.CAMP_HUB_ICON_PATH["quests"], "Quests", func(): hub_cluster = ""; term_tab = "quests"; render()],
			]
	v.add_child(_label(title, 18))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var entry_feature := {"Management": "management", "Items": "inventory", "Crafting": "crafting", "Bestiary": "bestiary", "Quests": "quests", "Ledger": "management"}
	for entry in entries:
		var fid: String = entry_feature.get(str(entry[1]), "")
		if fid != "" and not GameState.feature_unlocked(fid):
			var card := _hub_card(entry[0], tr("%s (locked)") % tr(str(entry[1])), func(): pass)
			card.modulate = Color(1, 1, 1, 0.45)
			card.tooltip_text = GameData.FEATURE_UNLOCKS[fid]["hint"]
			row.add_child(card)
		else:
			row.add_child(_hub_card(entry[0], entry[1], entry[2]))
	v.add_child(row)


## A champion's card: portrait, Boon, Call and story, with Oversee and Level
## up; a champion not yet freed is a silhouette with where to find them.
func _champion_card(id: String) -> PanelContainer:
	var d := GameData.champion_def(id)
	var freed := GameState.champion_unlocked(id)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelEmber" if GameState.overseer == id else &"CardPanel"
	card.custom_minimum_size.x = 320
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var pic := _icon_trimmed(GameData.champion_portrait(id), 96)
	if not freed:
		pic.modulate = Color(0.05, 0.04, 0.08, 0.9)
	row.add_child(pic)
	var col := _vbox(3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not freed:
		col.add_child(_label("???", 15))
		var act := GameState.champion_roll.find(id) + 1
		var hint := ""
		if act >= 1 and act <= GameData.CHAMPION_STORY_ACTS:
			hint = tr("Freed at the end of Act %s.") % tr(str(GameState._roman(act)))
		else:
			for e in GameState.lost_champions():
				if str(e[0]) == id:
					hint = tr("Lost in the Endless Rift: survive past %d:%02d to find their light.") % [int(e[1]) / 60, int(e[1]) % 60]
		col.add_child(_wrap_label(hint, 12, true))
		row.add_child(col)
		card.add_child(row)
		return card
	var lv := GameState.champion_level(id)
	var nm := _label(GameData.champion_full_name(id), 15)
	nm.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	col.add_child(nm)
	col.add_child(_label(tr("%s · Level %d/%d") % [tr(str(d["role"]).capitalize()), lv, GameData.CHAMPION_LEVEL_MAX], 12, true))
	var boon := _wrap_label(tr("Boon: ") + GameState.champion_boon_text(id), 12)
	boon.add_theme_color_override("font_color", Palette.good())
	col.add_child(boon)
	var call := GameState.champion_call_of(id)
	var times := 2 if lv >= GameData.CHAMPION_EXTRA_CALL_LEVEL else 1
	col.add_child(_wrap_label(tr("Call: %s — %s (%s)") % [tr(str(call["name"])), tr(str(call["desc"])), tr("twice a rift") if times == 2 else tr("once a rift")], 12))
	var lore := _wrap_label(tr(str(d.get("lore", ""))), 11, true)
	lore.tooltip_text = GameState.champion_memory_line(id)   # the Broken Accord: what they remember (also in the Chronicle)
	lore.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(lore)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	var oversee := _button(tr("Overseeing") if GameState.overseer == id else tr("Oversee rifts"), func(i=id):
		GameState.set_overseer(i)
		render()
	)
	oversee.disabled = GameState.overseer == id
	oversee.tooltip_text = tr("The overseer's Boon lifts the whole party in every rift run, and any hero can spend their turn on the Call.")
	btns.add_child(oversee)
	var cost := GameState.champion_level_cost(id)
	if cost >= 0:
		var up := _button(tr("Level up — %d Essence") % cost, func(i=id):
			var err := GameState.level_champion(i)
			if err != "":
				push_warning(err)
			render()
			if err == "":
				_payoff(tr("%s reaches level %d") % [GameData.champion_full_name(i), GameState.champion_level(i)], tr("Boon and Call grow stronger"), Palette.CRYSTALS, "level_up")
		)
		up.disabled = GameState.crystals < cost
		up.tooltip_text = tr("Each level: Boon and Call +%d%%, and +%d%% HP and damage in the Endless Rift. At level %d the Call works twice a rift.") % [int(GameData.CHAMPION_LEVEL_POWER * 100), int(GameData.CHAMPION_LEVEL_STATS * 100), GameData.CHAMPION_EXTRA_CALL_LEVEL]
		btns.add_child(up)
	col.add_child(btns)
	row.add_child(col)
	card.add_child(row)
	return card


func _render_champions(v: VBoxContainer) -> void:
	_coach(v, "champions", "Champions", "Champions are freed by the story and rescued in the Endless Rift. One oversees your rift runs: the whole party gets their Boon, and any hero can spend a turn on their Call. In the Endless Rift your champions are the party. Spend Essence here to level them up.")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.add_child(_label("Champions", 20))
	var ech := _label(tr("Essence: %d") % GameState.crystals, 15)
	ech.add_theme_color_override("font_color", Palette.CRYSTALS)
	ech.tooltip_text = tr("Spend it to level up champions. The Endless Rift pays the most.")
	ech.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ech)
	v.add_child(head)
	var freed := GameState.champion_roll.filter(func(i): return GameState.champion_unlocked(i)).size()
	v.add_child(_wrap_label(tr("%d of %d champions found. Every new guild meets a different twelve.") % [freed, GameState.champion_roll.size()], 12, true))
	# A grid, so every card lines up (a flow sized each row to its own cards).
	var grid := GridContainer.new()
	grid.columns = 1 if _narrow() else 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for id in GameState.champion_roll:
		var c := _champion_card(id)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(c)
	v.add_child(grid)


func _render_recruits(v: VBoxContainer) -> void:
	_coach(v, "recruits", "Hiring heroes", "Recruit heroes below; higher ranks are stronger.")
	v.add_child(_wrap_label(tr("New faces arrive every day and wait a few days; payday fills the board. Each reroll or commission doubles the next until payday (back to %d Gold).%s") % [GameState.recruit_reroll_base(), tr(" The rival may sign your best offer first.") if GameState.feature_unlocked("rival") else ""], 12, true))
	v.add_child(_wrap_label(tr("Rank odds: %s%s") % [tr(str(GameData.rank_odds_text())), tr(str(tr("  ·  Scouts' Lodge: a C+ recruit is assured each payday") if GameState.headhunter_guarantee() else ""))], 11, true))
	v.add_child(_hsep())

	v.add_child(_label(tr("Hero Recruits — %d/%d roster slots") % [GameState.heroes.size(), GameState.hero_slot_cap()]))
	if GameState.heroes.size() >= GameState.hero_slot_cap():
		var full := _wrap_label(tr("Your roster is full. The Barracks (Guild > Manage > Operations) adds 2 slots a level; you can also let a hero go from the Ledger."), 13)
		full.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		v.add_child(full)
	elif GameState.recruit_pool.is_empty():
		v.add_child(_wrap_label(tr("No one is looking for work right now. New faces arrive every day."), 13, true))
	# Ask for a role instead of rerolling until one turns up.
	var com := HFlowContainer.new()
	com.add_theme_constant_override("h_separation", 6)
	com.add_theme_constant_override("v_separation", 6)
	var cl := _label(tr("Commission a recruit (%d Gold):") % GameState.commission_cost(), 12, true)
	cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	com.add_child(cl)
	for role in ["warrior", "rogue", "ranger", "mage", "cleric"]:
		var cb := _button(tr(role.capitalize()), func(r=role):
			var err := GameState.commission_recruit(r)
			if err != "":
				push_warning(err)
			render()
		)
		cb.disabled = GameState.coins < GameState.commission_cost()
		cb.tooltip_text = tr("A %s joins the offers at the usual rank odds (the last offer leaves).") % tr(role)
		com.add_child(cb)
	v.add_child(com)
	for h in GameState.recruit_pool:
		var rank := GameData.find_rank(h.rank)
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Palette.SURFACE2
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
		row.add_child(_framed_portrait(h.cls_id, h.pool_id, 56.0, GameState.look_for(h)))
		var mid := _vbox(2)
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_child(_label(h.name, 13))
		mid.add_child(_label(tr("Rank %s %s · %d Gold · Power %d · %d HP · wage %d/week") % [tr(str(h.rank)), tr(str(h.cls_id.capitalize())), int(rank["cost"]), Combat.power_of(h), Combat.max_hp(h), GameState.wage_of(h)], 11, true))
		mid.add_child(_recruit_traits(h))
		mid.add_child(_rich_line(tr("Passive — ") + _passive_bb(h.pool_id), 10, true))
		row.add_child(mid)
		var left := GameState.offer_days_left(h)
		var stay := _label(tr("Last day") if left <= 0 else (tr("Leaves tomorrow") if left == 1 else tr("Leaves in %d days") % left), 12, left > 1)
		if left <= 1:
			stay.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		stay.tooltip_text = tr("Waits on the board until day %d, then takes work elsewhere.") % (GameState.day + left)
		stay.mouse_filter = Control.MOUSE_FILTER_STOP
		stay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(stay)
		var rr := _button(tr("Reroll (%d Gold)") % GameState.recruit_reroll_cost(), func(id=h.id):
			var err := GameState.reroll_recruit_offer(id)
			if err != "":
				push_warning(err)
			render()
		)
		rr.disabled = GameState.coins < GameState.recruit_reroll_cost()
		rr.tooltip_text = tr("Swap this offer for a new face. The next reroll costs double, until payday.")
		row.add_child(rr)
		var hire := _icon_domain_button("ember", GameData.CAMP_HUB_ICON_PATH["recruits"], "Recruit", func(id=h.id, nm=h.name, rk=h.rank):
			var err := GameState.recruit_hero(id)
			if err != "":
				push_warning(err)
			render()
			if err == "":
				_payoff(tr("%s joins the guild!") % tr(str(nm.split(" the ")[0])), tr("Rank %s") % tr(str(rk)), Palette.rank_color(str(rk)), "level_up")
		)
		var why := tr("Roster is full.") if GameState.heroes.size() >= GameState.hero_slot_cap() else (tr("Not enough Gold.") if GameState.coins < int(rank["cost"]) else "")
		hire.disabled = why != ""
		hire.tooltip_text = why
		row.add_child(hire)
		card.add_child(row)
		v.add_child(card)


## A recruit's make-up at a glance: their attributes (the one they lean
## on stands out) and their born quirk, so two offers of a rank differ.
func _recruit_traits(h: Hero) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	var top := ""
	for a in ["might", "agility", "focus"]:
		if top == "" or int(h.attrs.get(a, 0)) > int(h.attrs.get(top, 0)):
			top = a
	var tip := tr("Leans on %s. Might: damage and HP · Agility: speed, dodge, first strike · Focus: ability power, mending.") % tr(top.capitalize())
	for a in ["might", "agility", "focus"]:
		var al := _label("%s %d" % [tr(a.capitalize()), int(h.attrs.get(a, 0))], 11, a != top)
		if a == top:
			al.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		al.tooltip_text = tip
		al.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(al)
	for q in h.quirks:
		var t := GameData.quirk(q)
		var chip := _label(q, 11)
		chip.add_theme_color_override("font_color", Palette.HAZARD if t.get("treatable", false) else Palette.good())
		chip.tooltip_text = "%s — %s" % [tr(str(q)), tr(str(GameState.quirk_text(q)))]
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(chip)
	return row


func _render_medical_bay(v: VBoxContainer) -> void:
	v.add_child(_label(tr("Medical Bay — %d/%d beds occupied") % [GameState.occupied_beds(), GameState.medical_bed_cap()], 16))
	if GameState.field_triage_available():
		v.add_child(_wrap_label("Field Triage: once per rift, get a downed hero back up mid-rift.", 12, true))
	v.add_child(_hub_banner(GameData.MEDICAL_BG, 120.0 if _narrow() else 160.0))

	var bedded: Array[Hero] = []
	bedded.assign(GameState.heroes.filter(func(h): return GameState.needs_recovery(h) and h.bedded))
	var waiting: Array[Hero] = []
	waiting.assign(GameState.heroes.filter(func(h): return GameState.needs_recovery(h) and not h.bedded))
	var free := GameState.medical_bed_cap() - GameState.occupied_beds()

	# The beds as cards (they used to be drawn at fixed spots on the picture,
	# which put them and their labels off it on a narrow window).
	var beds := HFlowContainer.new()
	beds.add_theme_constant_override("h_separation", 8)
	beds.add_theme_constant_override("v_separation", 8)
	for i in GameState.medical_bed_cap():
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanelViolet"
		card.custom_minimum_size = Vector2(190, 0)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var bed_icon := _icon(GameData.BED_ICON, 40)
		row.add_child(bed_icon)
		var col := _vbox(0)
		if i < bedded.size():
			var h: Hero = bedded[i]
			col.add_child(_label(h.name.split(" the ")[0], 13))
			col.add_child(_label(tr("%d/%d HP · %s") % [h.hp, Combat.max_hp(h), tr(_recovery_text(h, true))], 11, true))
		else:
			bed_icon.modulate = Color(1, 1, 1, 0.45)
			col.add_child(_label(tr("Empty bed"), 13, true))
		row.add_child(col)
		card.add_child(row)
		beds.add_child(card)
	v.add_child(beds)

	if not waiting.is_empty():
		v.add_child(_label(tr("Recovering without a bed (slower):"), 13))
		for h in waiting:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var info := _wrap_label(tr("%s — %d/%d HP (%s) · %s") % [tr(str(h.name)), h.hp, Combat.max_hp(h), tr("downed") if h.is_downed() else tr("wounded"), tr(str(_recovery_text(h, false)))], 12)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(info)
			var put := _icon_domain_button("ember", "res://assets/skills/heart.png", "Put in a bed", func(id=h.id):
				GameState.assign_to_bed(id)
				render()
			)
			put.disabled = free <= 0
			put.tooltip_text = tr("Every bed is taken") if free <= 0 else tr("A downed hero comes back a run sooner; a wounded one is fully healed after the next run.")
			row.add_child(put)
			v.add_child(row)

	# Time only passes when a run ends — resting passes it without one.
	v.add_child(_hsep())
	var rest := _icon_button("res://assets/skills/heart.png", "Rest the guild (pass one run's time)", func():
		GameState.rest_guild()
		render()
	)
	rest.tooltip_text = "Heroes recover as if a run had ended."
	rest.disabled = not GameState.run.is_empty()
	v.add_child(rest)
	v.add_child(_wrap_label(tr("Recovery counts rift runs, not real time: a downed hero sits out %d run(s) (a bed takes one off); a wounded hero regains %d%% HP each run (all of it in a bed).") % [GameState.recovery_runs(), int(GameData.WOUND_HEAL_PER_RUN * 100)], 12, true))


## "back in 2 runs" / "full after next run" — recovery in runs, not seconds.
func _recovery_text(h: Hero, bedded: bool) -> String:
	if h.is_downed():
		return tr("back in %d run%s") % [h.down_runs, tr(str(_pl(h.down_runs)))]
	if bedded:
		return tr("full after next run")
	return tr("+%d%% HP per run") % int(GameData.WOUND_HEAL_PER_RUN * 100)


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
		return tr("%d/3 — need %d more") % [count, 3 - count]
	return tr("%d owned — ready to craft%s") % [count, tr(str(" (x%d)" % (count / 3) if count >= 6 else ""))]


func _render_crafting_hall(v: VBoxContainer) -> void:
	v.add_child(_label("Crafting", 20))
	v.add_child(_label("Combine 3 of the same kind and rarity into 1 of the next rarity up.", 12, true))

	var scene := _hub_banner(GameData.CRAFTING_BG, 200)
	scene.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
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
		var craft_btn := _icon_button(craft_icon, tr("Craft → %s") % tr(str(GameData.find_rarity(next_rarity)["name"])), func(c=category, r=rarity):
			if _crafting_animating:
				return
			_crafting_animating = true
			if GameState.state_changed.is_connected(_on_state_changed):
				GameState.state_changed.disconnect(_on_state_changed)
			GameState.craft_items(c, r)
			await _play_craft_flourish(v, GameData.ITEM_CATEGORY_ICON_PATH[c])
			if not GameState.state_changed.is_connected(_on_state_changed):
				GameState.state_changed.connect(_on_state_changed)
			_crafting_animating = false
			render()
		)
		craft_btn.disabled = count < 3
		v.add_child(_info_row("%s %s — %s" % [tr(str(GameData.find_rarity(rarity)["name"])), tr(str(GameData.ITEM_CATEGORY_LABEL[category])), tr(str(_craft_count(count)))], 13, [craft_btn], _icon(GameData.ITEM_CATEGORY_ICON_PATH[category], 20), count < 3))

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
		var rcraft_btn := _icon_button(craft_icon, tr("Craft → %s") % tr(str(GameData.find_rarity(rnext_rarity)["name"])), func(t=rtype, r2=rrarity):
			if _crafting_animating:
				return
			_crafting_animating = true
			if GameState.state_changed.is_connected(_on_state_changed):
				GameState.state_changed.disconnect(_on_state_changed)
			GameState.craft_relics(t, r2)
			await _play_craft_flourish(v, GameData.RELIC_TYPE_ICON_PATH[t])
			if not GameState.state_changed.is_connected(_on_state_changed):
				GameState.state_changed.connect(_on_state_changed)
			_crafting_animating = false
			render()
		)
		rcraft_btn.disabled = rcount < 3
		v.add_child(_info_row("%s %s — %s" % [tr(str(GameData.find_rarity(rrarity)["name"])), tr(str(rtype)), tr(str(_craft_count(rcount)))], 13, [rcraft_btn], _icon(GameData.RELIC_TYPE_ICON_PATH[rtype], 20), rcount < 3))




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
		v.add_child(_label(tr("%s — %d/%d met") % [tr(str(g[0])), seen_n, names.size()], 15))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 8)
		for mname in names:
			flow.add_child(_bestiary_card(str(mname), str(g[2])))
		v.add_child(flow)
		v.add_child(_hsep())

	v.add_child(_label(tr("Hazards — %d/%d met") % [GameData.HAZARD_TYPES.filter(func(h): return GameState.hazards_seen.has(str(h["id"]))).size(), GameData.HAZARD_TYPES.size()], 15))
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
			var sev := _label(tr("%s · finds %s") % [tr(str(_hazard_severity_label(mult))), tr(str(tr("Gold") if str(hz["bonus_type"]) == "coins" else tr("Essence")))], 12)
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
			cv.add_child(_wrap_label("%s — %s" % [tr(str(ability["name"])), tr(str(MONSTER_ABILITY_DESC.get(str(ability["kind"]), "")))], 12, true))
		var kit: Array = Combat.monster_kit({"name": mname, "tier": {"Monster": "combat", "Elite": "elite", "Boss": "boss"}.get(tier, "combat"), "ability": ability})
		if not kit.is_empty():
			cv.add_child(_wrap_label(tr("Telegraphs: %s") % tr(str(", ".join(kit.map(func(k): return str(GameData.INTENT_INFO[k]["name"]))))), 12, true))
		elif tier == "Boss":
			var beaten: bool = GameState.bosses_defeated.has(mname)
			cv.add_child(_wrap_label(tr("Brings a random warden mechanic each fight. %s") % tr(str((tr("Defeated.") if beaten else tr("Not yet defeated.")))), 12, true))
	card.add_child(cv)
	return card


func _compendium_tab_row(v: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for entry in [["chronicle", "Chronicle"], ["items", "Items"], ["relics", "Relics"], ["crafting", "Crafting"], ["systems", "Systems"]]:
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
		"chronicle": _render_chronicle(v)
		"items": _render_compendium_items(v)
		"relics": _render_compendium_relics(v)
		"crafting": _render_compendium_crafting(v)
		_: _render_compendium_systems(v)


## The Broken Accord as far as the guild knows it: the world everyone knows,
## what each sealed finale revealed, the Grandmaster's ledger pages found in
## rifts, and what the freed champions remember.
func _render_chronicle(v: VBoxContainer) -> void:
	var watch := _button("Watch the opening", func(): call("_play_cinematic", false))
	watch.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(watch)
	v.add_child(_label("The world", 16))
	for e in GameData.CHRONICLE_WORLD:
		v.add_child(_label(str(e[0]), 14))
		v.add_child(_wrap_label(str(e[1]), 12, true))

	v.add_child(_hsep())
	v.add_child(_label("The story so far", 16))
	for r in GameData.CHRONICLE_REVEALS:
		var act := int(r["act"])
		if GameState.campaign_act > act:
			var t := _label(str(r["title"]), 14)
			t.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
			v.add_child(t)
			v.add_child(_wrap_label(str(r["text"]), 13))
		else:
			v.add_child(_label(tr("??? — seal Act %s's finale") % tr(GameState._roman(act)), 13, true))
	if GameState.accord_ending != "":   # how the guild ended it (Act IV)
		var e: Array = GameData.CHRONICLE_ENDING[GameState.accord_ending]
		var et := _label(str(e[0]), 14)
		et.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		v.add_child(et)
		var etext := tr(str(e[1]))
		v.add_child(_wrap_label(etext % tr(GameState.accord_hero) if etext.contains("%s") else etext, 13))
	else:
		v.add_child(_label(tr("??? — seal Act %s's finale") % tr(GameState._roman(4)), 13, true))

	var pages: Array = GameData.LEDGER_PAGES
	v.add_child(_hsep())
	v.add_child(_label(tr("The Grandmaster's ledger — %d/%d pages") % [GameState.accord_pages, pages.size()], 16))
	v.add_child(_wrap_label("Pages turn up in sealed rifts as the campaign goes on; a finale always yields one.", 11, true))
	for i in mini(GameState.accord_pages, pages.size()):
		v.add_child(_wrap_label(str(pages[i]["text"]), 13))
	var missing := pages.size() - GameState.accord_pages
	if missing > 0:
		v.add_child(_label(tr("%d page%s still missing") % [missing, tr(str(_pl(missing)))], 12, true))

	var freed: Array = GameState.champion_roll.filter(func(id): return GameState.champion_unlocked(str(id)))
	v.add_child(_hsep())
	v.add_child(_label(tr("What the champions remember — %d/%d freed") % [freed.size(), GameState.champion_roll.size()], 16))
	if freed.is_empty():
		v.add_child(_wrap_label("Each act's finale frees a champion of the old guilds; more wait in the Endless Rift.", 12, true))
	for id in freed:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var pic := _icon_trimmed(GameData.champion_portrait(str(id)), 40)
		pic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(pic)
		var col := _vbox(0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_label(GameData.champion_full_name(str(id)), 13))
		col.add_child(_wrap_label(tr(str(GameData.CHAMPION_MEMORY.get(str(id), ""))), 12, true))
		row.add_child(col)
		v.add_child(row)


func _render_compendium_items(v: VBoxContainer) -> void:
	v.add_child(_wrap_label("Items are hero-bound gear. Weapon items fill a hero's weapon slots (1, or 2 for a dual-wield class); Armor and Focus items share one \"gear\" slot pool that grows with hero rank. A Common rolls one stat, a Rare one bigger stat and a named effect, an Epic two stats and a stronger effect (some effects only come on Epics). Legendaries are unique.", 12, true))
	for category in GameData.ITEM_CATEGORIES:
		v.add_child(_hsep())
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		head.add_child(_icon(str(GameData.ITEM_CATEGORY_ICON_PATH.get(category, "")), 28))
		head.add_child(_label(str(GameData.ITEM_CATEGORY_LABEL.get(category, category)), 16))
		v.add_child(head)
		var stats: Array = GameData.ITEM_CATEGORY_KINDS.get(category, []).map(func(k): return tr(str(_KIND_LABEL.get(k, k))))
		v.add_child(_wrap_label(tr("Stats: %s") % ", ".join(stats), 13))
		for e in GameData.ITEM_EFFECTS.get(category, []):
			v.add_child(_rich_line("[b]%s[/b]%s — %s" % [tr(str(e["name"])), tr(" (Epic)") if e.get("epic", false) else "", tr(str(Combat.describe_effect(e)))], 12))


const RELIC_DOMAIN_NAME := {"damage": "Damage", "heal": "Mending", "chance": "Chance", "defense": "Defense", "droprate": "Fortune"}


func _render_compendium_relics(v: VBoxContainer) -> void:
	v.add_child(_wrap_label("Relics sit on the Relic Altar (Inventory) and work for the whole party. Each adds damage and a shield, plus a special; Rare and Epic relics also carry a trigger that fires in battle. Rarity scales the numbers (a Rare's by 1.4, an Epic's by 1.9). A relic levelled to 5 awakens a second special, and any special or trigger can be rerolled for Essence.", 12, true))

	v.add_child(_hsep())
	v.add_child(_label("Types and their specials", 16))
	v.add_child(_wrap_label("A relic's type picks its special from its own family 60% of the time (any other family otherwise). Values shown are a Common's.", 12, true))
	for rtype in GameData.RELIC_TYPES:
		var domain := str(GameData.TYPE_DOMAIN.get(rtype, ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var ic := _icon(str(GameData.RELIC_TYPE_ICON_PATH.get(rtype, "")), 28)
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(ic)
		var col := _vbox(2)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_label(tr("%s — %s") % [tr(str(rtype)), tr(str(RELIC_DOMAIN_NAME.get(domain, domain)))], 14))
		for s in GameData.RELIC_SPECIALS.filter(func(x): return x["domain"] == domain):
			col.add_child(_wrap_label("• " + Combat.relic_special_label(str(s["kind"]), float(s["value"])), 12, true))
		row.add_child(col)
		v.add_child(row)

	v.add_child(_hsep())
	v.add_child(_label("Triggers (Rare and Epic)", 16))
	v.add_child(_wrap_label("One per relic, rolled from this list. Values shown are the base; a Rare rolls them about 18% stronger, an Epic about 38%.", 12, true))
	for t in GameData.RELIC_TRIGGERS:
		v.add_child(_wrap_label("• " + Combat.describe_effect(t, true), 12, true))

	# Legendaries: the fixed relics, each with where it comes from. Ones the
	# guild has never held stay dark, but their source shows (a thing to chase).
	GameState.note_relics_found()
	var legends: Array = []
	for u in GameData.UNIQUE_RELICS:
		legends.append([u, "An act's finale, or a very rare drop"])
	for f in GameData.TOWER_RELICS:
		legends.append([GameData.TOWER_RELICS[f], tr("Tower of Trials, floor %d guardian") % int(f)])
	for k in GameData.ENDLESS_RELICS:
		legends.append([GameData.ENDLESS_RELICS[k], "An Endless Rift milestone"])
	var found_n: int = legends.filter(func(e): return GameState.relics_found.has(str(e[0]["id"]))).size()
	v.add_child(_hsep())
	v.add_child(_label(tr("Legendaries — %d/%d found") % [found_n, legends.size()], 16))
	var w: float = v.custom_minimum_size.x if v.custom_minimum_size.x > 0.0 else get_viewport().get_visible_rect().size.x - 80.0
	var grid := GridContainer.new()
	grid.columns = clampi(int(w / 280.0), 1, 4)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for e in legends:
		grid.add_child(_legendary_card(e[0], str(e[1])))
	v.add_child(grid)


func _legendary_card(u: Dictionary, source: String) -> PanelContainer:
	var found: bool = GameState.relics_found.has(str(u["id"]))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var path := "res://assets/relics/u_%s.png" % str(u["id"])
	var ic := _icon(path if ResourceLoader.exists(path) else str(GameData.RELIC_TYPE_ICON_PATH.get(str(u["type"]), "")), 40)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if not found:
		ic.modulate = Color(0.08, 0.07, 0.12)
	row.add_child(ic)
	var col := _vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nl := _label(tr(str(u["name"])) if found else "???", 13)
	if found:
		nl.add_theme_color_override("font_color", ITEM_RARITY_COLOR["legendary"])
	col.add_child(nl)
	if found:
		col.add_child(_wrap_label(tr(str(u["desc"])), 12))
	col.add_child(_wrap_label(tr(source), 12, true))
	row.add_child(col)
	card.add_child(row)
	return card


func _render_compendium_crafting(v: VBoxContainer) -> void:
	v.add_child(_wrap_label("Crafting (Arcane Lab) turns three unequipped items or relics of one kind and rarity into one of the next rarity up.", 12, true))
	v.add_child(_hsep())
	for rarity in GameState.CRAFT_RARITY_UP:
		var up := str(GameState.CRAFT_RARITY_UP[rarity])
		var line := _rich_line("[color=#%s]3 × %s[/color]  →  [color=#%s]1 × %s[/color]   [color=#%s](numbers × %s)[/color]" % [
			(ITEM_RARITY_COLOR[rarity] as Color).to_html(false), tr(str(rarity).capitalize()),
			(ITEM_RARITY_COLOR[up] as Color).to_html(false), tr(up.capitalize()),
			Palette.MUTED.to_html(false), str(GameData.find_rarity(up)["mult"])], 14)
		v.add_child(line)
	for rule in [
		"Items: three of the same category (Weapon, Armor or Focus). The new item rolls fresh stats at the best rank among the three.",
		"Relics: three of the same type (Ember, Frost...). The new relic keeps that type and rolls fresh effects.",
		"Equipped gear never goes in. Legendaries can't be crafted or fed in: they are fixed finds.",
	]:
		v.add_child(_wrap_label("• " + tr(rule), 12, true))

	# What the guild could craft right now.
	var groups := {}
	for it in GameState.items:
		if it.equipped_to == "" and GameState.CRAFT_RARITY_UP.has(it.rarity):
			var k := "%s · %s" % [tr(str(GameData.ITEM_CATEGORY_LABEL.get(it.category, it.category))), tr(str(it.rarity).capitalize())]
			groups[k] = int(groups.get(k, 0)) + 1
	for r in GameState.relics:
		if not r.equipped and GameState.CRAFT_RARITY_UP.has(r.rarity):
			var k2 := "%s %s · %s" % [tr(str(r.type)), tr("relic"), tr(str(r.rarity).capitalize())]
			groups[k2] = int(groups.get(k2, 0)) + 1
	var ready: Array = groups.keys().filter(func(k): return int(groups[k]) >= 3)
	v.add_child(_hsep())
	v.add_child(_label(tr("Ready now — %d") % ready.size(), 16))
	if ready.is_empty():
		v.add_child(_wrap_label("Nothing yet: no three spare pieces of one kind and rarity.", 12, true))
	for k in ready:
		v.add_child(_wrap_label(tr("%s: %d spare, %d craft%s") % [k, int(groups[k]), int(groups[k]) / 3, tr(str(_pl(int(groups[k]) / 3)))], 13))
	if not ready.is_empty() and GameState.feature_unlocked("crafting"):
		var go := _button("Open Crafting", func(): screen = "crafting_hall"; render())
		go.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(go)


func _render_compendium_systems(v: VBoxContainer) -> void:
	var entries := [
		["Guild Management", "Spend Essence on 9 upgrades across 4 branches, and Gold on the Defenses branch (Armory, Engineering, Palisade, Watchtower) for Riftbreaks. Every level adds its effect; some levels unlock a perk (a first-strike bonus, a boss Essence cache, extra relic slots, tier 3 towers…). Guild Tier tracks total levels. A building damaged in a Riftbreak works a level lower until you repair it with Gold."],
		["Daily twist", "Once you have sealed a rift, the Rift Ladder offers a twist each day: a rule and a starting boon that come from the date, so every guild faces the same one. Tick it and your next ladder rift (any rank) carries it; one try a day. Sealing it pays bonus Essence and grows your streak. Records (in the Guild Hall) track achievements, lifetime statistics and your last 30 runs; the Memorial remembers heroes lost for good."],
		["Endless Rift", "A real-time survival run in the region you pick, and only champions go in (up to 4). You steer the first (WASD, arrows, drag or stick); the rest follow and fight on their own, and each fires their signature move on a timer (the ring over their head fills as it recharges). Your equipped relics come along. Every five minutes the rift runs the same cycle: the horde, a swarm, an elite pack (its leader carries a chest), archers and casters, then a lull with a chest nearby, and a warden at the end of it. At 20:00 the Rift Warden comes: beat it to seal the rift. The rift's strength (shown before you enter) starts gentle and grows with every champion you free and every act you pass. A run pays Essence and a little Gold, and costs the guild a day."],
		["Endless picks", "Collect shards to level up and pick 1 of 3; one card is always a signature pick while any are left. Party upgrades (damage, speed, health…), a champion's role skill, a rank in their signature (up to 3: sooner and harder), or one of their two signature mods once it has a rank (Aftershock, Kindled, Frostbite, Expose, Stagger, Leech, Shrapnel, Radiance, Bulwark, Fervor, Renewal, Smokescreen). From level 10, two champions whose signatures are rank 2 can fuse: they fire together, 25% harder, and carry each other's mods. Max an upgrade and the matching role's attack can evolve (Whirlwind, Thousand Cuts, Arrow Storm, Starfall, Sanctum). Chests give one of three rift relics for the run."],
		["Endless ground", "The Vale has pillars that block foes, the Marches have pools that slow everyone, the Wastes have lava that burns foes and your lead. Braziers break when you walk into or hit them, dropping a heal, a magnet for shards or a bomb. Elites and wardens slam: step out of the red circle before it fills. Your first 5, 10 and 15 minutes and your first sealed rift each pay once, with two Endless relics and guild titles."],
		["Hero voices", "A hero's born quirk sets their personality (Bold, Quick, Stoic, Nervous, Devout or Scholarly), shown on their sheet. They speak up in fights when they land a big kill, hang on at low health or see an ally fall, and one of them sums up every win."],
		["Boss phases", "Every boss changes once it drops to half health: Call the Horde (two foes join), Fury (hits 20% harder and winds up more often) or Last Bastion (a ward worth 12% of its health). Its plate shows which, and the warning bar calls it out as it gets close, so save burst and Defend for the turn."],
		["Elite affixes", "Elites roll an affix: Vampiric, Thorned, Shielded, Venomous, Juggernaut, Blazing, Hasted (acts twice) or Commander (brings two escorts). Rank B+ rifts give them two. Hover the badges on their plate to read them."],
		["Boons", "Beating an elite in a rift offers 1 of 3 boons that last until that rift ends. Boons come in seven families (Ember, Frost, Blood, Steel, Storm, Shadow, Holy); owning 2 of a family adds a set bonus and 4 a strong capstone, so a run can grow into a build. Not offered in the Tower."],
		["Guild Orders", "Lv2 of the Infirmary, Drill Yard, Trade Network and Scouts' Lodge each unlock an order you can call inside a rift: Supply Drop (heal 35% between fights), Rally (act first and hit 30% harder this round), Requisition (reroll a fight's loot) and Scout Ahead (reroll a fork). 1 order per rift, 2 at Renowned tier, 3 at Legendary."],
		["Rift Ladder", "Rifts come in ranks, F to SSS. F-D are Lesser rifts, C and up Greater rifts (open after Act I). Each rank hits harder than the last and pays more; from B up they add rules (more elites, harsher hazards, fewer shops, bosses with two mechanics). Seal a rank to open the next. Gear drops at the rank of the rift it came from."],
		["Bonds", "Heroes who seal rifts together grow a bond: level 1, 2 and 3 after 2, 5 and 10 rifts. Each level adds 2% party damage while both stand in a fight (up to the cap). Bonds show on the hero sheet's History tab."],
		["Ability Awakening", "Spend Skill Points once to give a hero's Ability a secondary effect (by ability: +2 Momentum back, a lingering debuff, a party dodge boost, a self-shield, or a small damage stack)."],
		["Formation", "Heroes stand in the front or back row. Foes aim most attacks at the front row; Snipes hunt the back. Warriors and rogues hit at half strength with a basic attack from the back row, and some skills need a row. Move (7) switches rows for a turn. Back-row foes take less damage from attacks."],
		["Controls", "Keyboard: 1-5 switch camp tabs; in a fight 1 Attack, 2-4 skills, 5 Defend, M opens More (6 Guard, 7 Move, 8 Tonics, 9 Call; their keys work either way), Space repeats the last action, Tab cycles targets, A toggles Auto, Esc goes back. Endless Rift: WASD or arrows (or drag), Esc pauses. Riftbreak defense: click a pad to build, the ground to send your champion, Space calls the next wave, Esc pauses. Gamepad: D-pad and A work every menu, B goes back, LB/RB switch camp tabs. In a fight A repeats the last action, X Defends, Y uses the Ability, LB/RB the two skills, Start opens More (Guard, Move, Tonics, Call), the D-pad cycles targets, Select toggles Auto. Endless Rift: left stick or D-pad steer, Start pauses."],
		["Momentum and skills", "Momentum is the party's shared pool (up to 10, starting at 3). Each basic attack adds 1, each kill 1, and each hit taken while Defending or Guarding 1 (2 for a heavy blow). Every hero has two role skills (Lv1 and Lv6) and their subclass Ability (Lv3). Skills cost 2-4 Momentum, Abilities 4."],
		["Enemy moves", "Each round a foe shows its next move above its health bar: an attack on a hero, a wind-up (a heavy blow next round), or a special move: Sweep (hits everyone), Snipe (the most-hurt back-row hero), Curse (40% less damage for 2 rounds), Ward, Mend or Roar. Shield Bash stuns a foe; Shield Bash and Frost Nova break wind-ups."],
		["Designed encounters", "About six regular fights in ten are one of a region's named encounters (Scarecrow Line, Reed Snipers, Forge Guard...), groups whose members play off each other: a warder shielding a brute, a healer behind a wall, snipers behind a tank. The name and a tactical hint open the fight log; hover the round label to read the hint again."],
		["Rift bosses", "Each boss is always the same fight. Vaelith's Harvest hits everyone and heals her, and she calls a Crier and a Warden at half health. Nyxara's Drowning Tide chills and weakens the party. Korrath's Sunder tears the wards off the front row. Drevok Brands a hero to take 50% more damage and calls fire cultists. Sythrane Immolates the party while she regenerates and enrages. Their signature moves are telegraphed like any other."],
		["Bestiary", "Every monster, boss, and hazard you've encountered is tracked as a silhouette-to-full-color reveal — pure record-keeping, no reward tied to completion."],
		["Tower of Trials", "Opens with Act II, in the Rift Hall. 100 fixed floors, one fight each: a floor is always the same fight, so a loss is something to plan around. Heroes fight at full HP and leave as they came (no downing, scars or days passing). Most floors carry a rule (armored or burning foes, a swarm, a party cap). Every 10th floor is a guardian that gives a unique relic, and floors 10/25/50/75/100 earn guild titles. Only a first clear pays; floors 91-100 reshuffle their rules every week and pay half for a re-clear."],
		["Foes & regions", "Each rift is in a region (the Vale, the Marshes, the Ashen Wastes) with its own foes. Some foes wind up a heavy blow a turn ahead (x2.5, stuns unless the target Defends); armored foes shrug off part of every basic attack (each hit chips the armor; abilities ignore it); fire foes can burn and frost foes can chill (act late). A Field Tonic cleanses burn, chill, poison and stun."],
		["Campaign", "Three acts, each ending in a finale rift against a named foe. Meet an act\'s objectives (shown in the Rift Hall) to open its finale; sealing it pays a reward and a Legendary relic. Act I opens Greater Rifts, Act II the Endless Rift."],
		["Relics", "Relics sit on the Relic Altar (Inventory) and empower the whole party. Every relic has a special; rare and epic ones also have a trigger that fires in battle (on a kill, every third round, when an ally falls...). Level a relic to 5 to awaken a new effect, or reroll any effect for Essence. Legendary relics have unique powers."],
		["Quirks", "Everything personal about a hero beyond class, skills and gear: at most one born quirk (it sets their voice), up to 2 scars from being knocked out (a wound with a small upside), and quirks earned by what they've done. Bad born quirks and scars can be treated for Gold at the Arcane Lab."],
		["Riftbreaks", "From Act II a rift swells every so often: a rank, a place and a countdown in days (Rift Hall and the camp's status board). Seal a rift of that rank or higher before it runs out to close it, for a little Essence. Otherwise it breaks, and every rift run waits until your guild defends. Ranks below S break out in a region; from S up they break at your camp. Holding pays Gold and Essence. Losing costs a share of your Essence and of the Gold beyond the coming payday's wages, damages a building (two at the camp) and wounds the posted heroes who fell."],
		["Defending", "Foes walk the roads toward the goal. Build towers on the round pads with supplies (you start with some and earn more for every kill); click a tower to upgrade or sell it. Ballistas shoot far, Fire Braziers splash and burn, Frost Totems slow, Ward Stones shield nearby heroes, Chapels mend them; research in the Defenses branch opens the last three and tier 3. Idle heroes stand at posts: warriors and rogues hold foes in place, rangers and mages shoot. Steer one champion by clicking where to go. Every foe that gets through costs integrity (an elite 3, a warden 10); at 0 the defense is lost. Call a wave early for bonus supplies."],
		["Champions", "Each new guild meets twelve champions, drawn from a pool of twenty-four: three are freed at the end of Acts I, II and III, and nine are lost in the Endless Rift, where a pillar of light marks each one (stand in it to free them). A champion never joins the roster. In rift runs one oversees the party: their Boon lifts everyone, and any hero can spend a turn on their Call (once a rift, twice from level 3). In the Endless Rift your champions are the party, each with their Call as a signature move. Essence levels them up (to 5)."],
		["Attributes", "Might (damage, HP), Agility (speed, dodge, first strike) and Focus (ability power, mend). Heroes gain 3 points per level to spend on the Roster's Hero tab; gear adds more, and better gear needs a minimum in its attribute to equip. Train up to 8 extra points with Gold, or reset a hero's points for 5 Essence per level (gear they no longer qualify for comes off)."],
		["Quests & Milestones", "The quest board posts 6 quests (hunts, boss bounties, rift seals, trials); take up to 3 at a time. Unaccepted postings are replaced every 3 days (a day passes with each rift run or rest). Milestones are a static checklist, auto-granted the moment they're met. Renown occasionally arms a guaranteed Epic relic at the next Shop. A rare escort NPC can also tag along on a fight — surviving pays a small bonus."],
		["Wages, morale and the rival", "Every 7 days (a day = one rift run or rest) heroes draw wages by rank and level, and every Guild Management level costs upkeep; see Guild > Ledger. Unpaid upkeep costs Renown. The Training Yard trains only a few attribute points a week (more with the Drill Yard), and a feast seats a limited number of heroes, lowest morale first (more with the Trade Network). The unpaid lose morale, and a hero unpaid twice in a row, or at rock-bottom morale on payday, walks out. Morale (0-100) rises with sealed rifts and feasts and falls with defeats, knockouts, idle weeks and failed contracts: Inspired heroes deal +10% damage, Shaken -10%, Breaking -20%. Taken contracts are due in 6-10 days. A rival guild gains Renown daily, and once a week it may make a move you answer before payday: court one of your heroes (match their offer, or they choose, staying only at morale 50 or above), dare you to seal a rift by payday (Renown rides on it), or go for a posted contract (take it on or lose it). Requests and the rival's moves pop up at camp and wait in the Ledger, whose week board shows each day to payday. At payday, the leader on Renown gets the better recruits. Every 28 days, whichever guild gained more Renown wins a prize."],
		["Hero requests", "Mid-week a hero may ask for something: time off (away a few days), a raise (a bigger wage for good), Gold for kit, a Training Yard slot, or your side in a feud with another hero. Saying yes costs something; saying no costs morale. Answer in the Ledger before payday, or it counts as a no."],
	]
	for entry in entries:
		v.add_child(_label(str(entry[0]), 15))
		v.add_child(_wrap_label(str(entry[1]), 12, true))
		v.add_child(_hsep())


# ---------------- Quests: Guild Board & Milestones ----------------
const INK := Color("3b2414")
const INK_SOFT := Color("6b4a2e")
const QUEST_CATEGORY := {"hunt": "Hunt", "elite": "Hunt", "bounty": "Wanted", "seal_rank": "Seal the Rift",
	"seal_greater": "Seal the Rift", "trial_small": "Trial", "trial_flawless": "Trial", "craft": "Supply", "flawless_win": "Trial"}


## The Guild Board: quests pinned as parchment notes on a wooden board —
## taken ones first (red pin, TAKEN stamp), then this posting's offers.
func _render_quests(v: VBoxContainer) -> void:
	var board_w: float = v.custom_minimum_size.x
	var taken: Array = GameState.active_quests()
	var posted: Array = GameState.guild_board.filter(func(q): return str(q["status"]) == "posted")
	var failed: Array = GameState.guild_board.filter(func(q): return str(q["status"]) == "failed")
	var notes: Array = taken + failed + posted
	var cols := 3 if board_w >= 600.0 else 2
	var pad_x := roundf(board_w * 0.075)
	var gap := 16.0
	var note_w := floorf((board_w - pad_x * 2.0 - gap * (cols - 1)) / cols)
	var board := PanelContainer.new()
	board.custom_minimum_size.x = board_w
	var bst := StyleBoxTexture.new()
	bst.texture = load(GameData.QUEST_BOARD_BG)
	bst.content_margin_left = pad_x
	bst.content_margin_right = pad_x
	bst.content_margin_top = 34.0
	bst.content_margin_bottom = 46.0
	board.add_theme_stylebox_override("panel", bst)
	board.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var bcol := _vbox(14)
	board.add_child(bcol)
	# The header, chalked onto a plank at the top.
	var head := _vbox(0)
	var title := _label("Quests", 22)
	title.add_theme_color_override("font_color", Color("f1e2c0"))
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(title)
	var days_left: int = max(0, GameState.board_refresh_day - GameState.day)
	var sub := _label(tr("Day %d  ·  Taken %d/%d  ·  new postings in %d day%s") % [GameState.day, taken.size(), GameData.QUEST_ACTIVE_MAX, days_left, tr(str(_pl(days_left)))], 13)
	sub.add_theme_color_override("font_color", Color("e0cfa8"))
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	sub.add_theme_constant_override("shadow_offset_y", 1)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.tooltip_text = "A day passes with every rift run or rest. Unaccepted postings are replaced when the board refreshes; quests you've taken stay."
	sub.mouse_filter = Control.MOUSE_FILTER_STOP
	head.add_child(sub)
	bcol.add_child(head)
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", int(gap))
	grid.add_theme_constant_override("v_separation", int(gap))
	for q in notes:
		grid.add_child(_quest_note(q, note_w, 0.0, taken.size()))
	bcol.add_child(grid)
	if notes.is_empty():
		var empty := _label(tr("Nothing posted — new postings in %d day%s.") % [days_left, tr(str(_pl(days_left)))], 14)
		empty.add_theme_color_override("font_color", Color("e0cfa8"))
		bcol.add_child(empty)
	v.add_child(board)
	v.add_child(_wrap_label("Every 20 Renown arms a guaranteed Epic relic at your next Shop.", 12, true))
	v.add_child(_hsep())

	v.add_child(_label("Milestones", 16))
	for m in GameData.MILESTONES:
		var mid := str(m["id"])
		var claimed: bool = GameState.milestones_claimed.has(mid)
		var mprogress := GameState.milestone_progress(m)
		var mtarget := int(m["target"])
		var status := tr("Claimed") if claimed else "%d/%d" % [min(mprogress, mtarget), mtarget]
		v.add_child(_wrap_label("%s [%s]" % [tr(str(m["label"])), tr(str(status))], 12, claimed))
	v.add_child(_hsep())


## One quest as a pinned parchment note.
func _quest_note(q: Dictionary, w: float, h: float, taken_count: int) -> Control:
	var status := str(q["status"])
	var type := str(q["type"])
	var progress := GameState.quest_progress(q)
	var target := int(q["target"])
	var done := status == "active" and progress >= target
	var note := PanelContainer.new()
	note.custom_minimum_size = Vector2(w, maxf(h, 230.0))
	var paper := StyleBoxTexture.new()
	var paper_by_cat := {"Hunt": "quest_note_torn", "Wanted": "quest_note_poster"}
	paper.texture = load("res://assets/ui/%s.png" % paper_by_cat.get(QUEST_CATEGORY.get(type, ""), "quest_note"))
	paper.content_margin_left = 18.0
	paper.content_margin_right = 18.0
	paper.content_margin_top = 26.0
	paper.content_margin_bottom = 18.0
	if status == "failed":
		paper.modulate_color = Color(0.7, 0.68, 0.66)
	note.add_theme_stylebox_override("panel", paper)
	note.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var col := _vbox(4)
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
	if status == "active" and not done and q.has("due"):
		var left := int(q["due"]) - GameState.day
		var due := _label(tr("Due in %d day%s") % [left, tr(str(_pl(left)))] if left > 0 else tr("Due today"), 12)
		due.add_theme_color_override("font_color", Color("b3261e") if left <= 2 else INK)
		due.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(due)
	elif status == "posted":
		var takes := _label(tr("%d days once taken") % int(GameData.QUEST_DUE_DAYS.get(int(q.get("diff", 1)), 6)), 11)
		takes.add_theme_color_override("font_color", INK)
		takes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(takes)
	var stars := _label("★".repeat(int(q["diff"])) + "☆".repeat(3 - int(q["diff"])), 13)
	stars.add_theme_color_override("font_color", Color("9a5a12"))
	stars.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stars.tooltip_text = "Difficulty"
	stars.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(stars)
	var rl := _wrap_label(tr("Reward: ") + GameState.quest_reward_desc(q["reward"]), 12)
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
			take.tooltip_text = tr("You already have %d quests — finish or abandon one first") % GameData.QUEST_ACTIVE_MAX if full else tr("Only progress made after taking it counts")
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
				ab.add_theme_font_size_override("font_size", 14)
				col.add_child(ab)
		"failed":
			var rm := _button("Take it down", func(id=str(q["id"])):
				GameState.abandon_quest(id)
				render()
			)
			rm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			col.add_child(rm)
	note.add_child(col)
	# Pin and stamp on an overlay over the content (a container child fills it).
	var deco := Control.new()
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_child(deco)
	# The pin: red on quests you've taken, brass on postings.
	var pin := Panel.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color("b3261e") if status == "active" else (Color("777777") if status == "failed" else Color("c89b3c"))
	ps.set_corner_radius_all(8)
	ps.border_color = Color(0, 0, 0, 0.55)
	ps.set_border_width_all(2)
	pin.add_theme_stylebox_override("panel", ps)
	pin.size = Vector2(16, 16)
	pin.position = Vector2((w - 36.0) * 0.5 - 8, -20)
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.add_child(pin)
	# A stamp across the corner for taken / done / failed.
	var stamp_text := tr("DONE") if done else (tr("TAKEN") if status == "active" else (tr("FAILED") if status == "failed" else ""))
	if stamp_text != "":
		var st := _label(stamp_text, 18)
		st.add_theme_font_override("font", DISPLAY_FONT)
		st.add_theme_color_override("font_color", Color(0.2, 0.55, 0.2, 0.8) if done else (Color(0.7, 0.12, 0.1, 0.6) if status == "active" else Color(0.25, 0.25, 0.25, 0.75)))
		st.position = Vector2(-4, 4)
		st.rotation = deg_to_rad(-14)
		if not done:
			st.add_theme_font_size_override("font_size", 14)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		deco.add_child(st)
	return note


var _mgmt_last := "ops"   # the Management branch opened last (the strip opens on it)


func _render_management(v: VBoxContainer) -> void:
	if mgmt_branch == "":
		mgmt_branch = _mgmt_last
	_mgmt_last = mgmt_branch
	v.add_child(_hub_strip(GameData.MANAGEMENT_BG, GameData.BRANCHES.map(func(br): return [str(br["id"]), tr(str(br["name"])).trim_suffix(tr(" Branch"))]), mgmt_branch, func(id):
		mgmt_branch = id
		render()))
	var branch: Dictionary = {}
	for b in GameData.BRANCHES:
		if b["id"] == mgmt_branch:
			branch = b
	v.add_child(_label("%s — %s" % [tr(str(branch["name"])), tr(str(branch["sub"]))], 16))
	var grid := GridContainer.new()
	grid.columns = 1 if _narrow() else 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for n in branch["nodes"]:
		grid.add_child(_management_node_card(branch, n))
	v.add_child(grid)
	v.add_child(_hsep())
	v.add_child(_reset_guild_button())


func _reset_guild_button() -> Control:
	var reset_btn := _icon_button("res://assets/skills/shard_green.png", "Click again to confirm reset" if confirm_reset else "Reset Guild", func():
		if not confirm_reset:
			confirm_reset = true
			render()
			get_tree().create_timer(3.0).timeout.connect(func():
				confirm_reset = false
				if screen == "camp" and term_tab == "management":
					render()
			)
			return
		confirm_reset = false
		GameState.reset()
		GameState.save()
		screen = "onboard"
		render()
	)
	reset_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return reset_btn


## One upgrade node as a card — icon/name header, a level progress bar
## (replaces the old "(Lvl 2/5)" text-only readout), current + next-level
## effect text, then the Upgrade/capstone action — instead of a single
## full-width text row, so a branch's 4-5 nodes read as a grid of cards
## rather than a stack of near-identical lines.
func _management_node_card(branch: Dictionary, n: Dictionary) -> PanelContainer:
	var key := "%s.%s" % [branch["id"], n["id"]]
	var cur := int(GameState.upgrades.get(key, 0))   # as built; a damaged building works lower (GameState.lvl)
	var node_max := int(n["max"])
	var gold := str(n.get("currency", "")) == "gold"
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
	header.add_child(_label(tr("Lv %d/%d") % [cur, node_max], 12, true))
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

	var now := _wrap_label(Combat.describe_node_effect(n["id"], GameState.lvl(key)), 13)
	now.add_theme_color_override("font_color", Palette.TEXT if cur > 0 else Palette.MUTED)
	cv.add_child(now)
	if int(GameState.damaged.get(key, 0)) > 0:
		var dmg := _wrap_label(tr("Damaged in a Riftbreak: works at Lv %d until repaired.") % GameState.lvl(key), 12)
		dmg.add_theme_color_override("font_color", Palette.HAZARD)
		cv.add_child(dmg)
		var rb := _button(tr("Repair a level — %d Gold") % GameState.repair_cost(key), func(k=key, nm=str(n["name"])):
			GameState.repair_building(k)
			render()
			_payoff(tr("%s repaired") % tr(nm), tr("Works at Lv %d") % GameState.lvl(k), Palette.COINS, "craft"))
		rb.disabled = GameState.coins < GameState.repair_cost(key)
		cv.add_child(rb)
	cv.add_child(_wrap_label(tr("Each level: %s · upkeep +%d Gold a week") % [tr(str(n["every"])), GameData.UPKEEP_PER_LEVEL], 11, true))
	var perks: Dictionary = n["perks"]
	for pl in perks:
		var got := cur >= int(pl)
		var is_order := str(perks[pl]).begins_with("Order:")
		var pr := _wrap_label(tr("%s Lv%d — %s") % [tr(str("✓" if got else ("⚑" if is_order else "★"))), int(pl), tr(str(perks[pl]))], 12)
		pr.add_theme_color_override("font_color", Palette.RANK_E if got else (Palette.EMBER_BRIGHT if is_order else Palette.RANK_S))
		cv.add_child(pr)

	var building: Array = GameData.HAMLET_BUILDINGS.filter(func(hb): return str(hb.get("node", "")) == key)
	if not building.is_empty():
		cv.add_child(_wrap_label(tr("⌂ Camp: the %s is rebuilt at Lv3 and Lv5 (now tier %d/3)") % [tr(str(building[0]["name"])), GameState.hamlet_tier(building[0])], 11, true))
	else:
		cv.add_child(_wrap_label("⌂ Camp: every level grows the Guild Hall (guild tier)", 11, true))

	if not maxed:
		var cost: int = int(n["cost_base"]) + int(n["cost_step"]) * cur
		var next_perk := str(perks.get(cur + 1, ""))
		var ub := _icon_button(icon_path, (tr("Upgrade to Lv%d — %d Gold") if gold else tr("Upgrade to Lv%d — %d Essence")) % [cur + 1, cost], func(k=key, nm=str(n["name"]), nid=str(n["id"]), perk=next_perk):
			var err := GameState.upgrade_node(k)
			if err != "":
				push_warning(err)
			render()
			if err == "":
				var lv := int(GameState.upgrades.get(k, 0))
				_payoff(tr("%s — Lv%d") % [tr(nm), lv], tr(perk) if perk != "" else tr(str(Combat.describe_node_effect(nid, lv))), Palette.EMBER_BRIGHT, "unlock")
		)
		ub.disabled = (GameState.coins if gold else GameState.crystals) < cost
		ub.tooltip_text = tr("Next: %s%s") % [tr(str(Combat.describe_node_effect(n["id"], cur + 1))), tr(str((tr("\nUnlocks: ") + next_perk) if next_perk != "" else ""))]
		cv.add_child(ub)
	else:
		var ml := _label("Fully upgraded", 12)
		ml.add_theme_color_override("font_color", Palette.RANK_E)
		cv.add_child(ml)

	card.add_child(cv)
	return card
