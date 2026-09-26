class_name RosterView
extends UiKit
## Roster (hero card, skill trees, equip slots) and Inventory screens.

func _sorted_heroes() -> Array[Hero]:
	var out: Array[Hero] = []
	out.assign(GameState.heroes)
	match roster_sort:
		"power":
			out.sort_custom(func(a, b): return Combat.power_of(a) > Combat.power_of(b))
		"level":
			out.sort_custom(func(a, b): return a.level > b.level)
		"rank":
			out.sort_custom(func(a, b): return float(GameData.find_rank(a.rank)["mult"]) > float(GameData.find_rank(b.rank)["mult"]))
	return out


func _render_roster(v: VBoxContainer) -> void:
	v.add_child(_banner(GameData.ROSTER_BG, v.custom_minimum_size.x, 120))
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes recruited yet."))
		return

	var still_here: Array[Hero] = []
	still_here.assign(GameState.heroes.filter(func(h): return h.id == selected_hero_id))
	if still_here.is_empty():
		selected_hero_id = ""

	# Two panes: the hero list on the left, the selected hero's card on the right.
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	var left := _vbox(6)
	left.custom_minimum_size.x = 300
	var right := _vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	split.add_child(right)
	v.add_child(split)

	var sort_btn := _sort_cycle_button(roster_sort, [
		{"id": "power", "label": "Power"},
		{"id": "level", "label": "Level"},
		{"id": "rank", "label": "Rank"},
	], func(new_id): roster_sort = new_id)
	sort_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(sort_btn)
	var stones_text := GameData.evolution_stones_text(GameState.evolution_stones)
	if stones_text != "":
		left.add_child(_wrap_label("Evolution Stones: %s" % stones_text, 12, true))
	var sorted := _sorted_heroes()
	if selected_hero_id == "":
		selected_hero_id = sorted[0].id
		still_here.assign([sorted[0]])
	for hh in sorted:
		left.add_child(_roster_row(hh))
	var h: Hero = still_here[0]

	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelViolet"
	var cv := _vbox(4)
	cv.add_child(_title_strip(h.name))
	cv.add_child(_label("Lv%d %s (%s) · %d/%d HP · Power %d" % [h.level, h.cls_id.capitalize(), h.rank, h.hp, Combat.max_hp(h), Combat.power_of(h)]))

	# Tabs (Overview · Gear · Skills · History) instead of one long card that
	# stacked every section. A dot marks a tab with something to act on:
	# unequipped gear that fits, or unspent SP / an available evolution.
	var evolve_choices: Array = []
	if h.level >= 10:
		var cur_cls := GameData.find_class(h.pool_id)
		if not cur_cls.is_empty():
			evolve_choices = GameData.evolution_choices(cur_cls)
	var fitting_items: Array[Item] = []
	fitting_items.assign(GameState.items.filter(func(it): return it.equipped_to == "" and GameState.item_fits_hero(it, h)))
	if roster_tab in ["overview", "gear"]:
		roster_tab = "hero"
	if expanded_slot.begins_with(h.id + ":"):
		roster_tab = "hero"
	if evolve_picker_hero_id == h.id:
		roster_tab = "skills"
	var tab_defs := [
		["hero", "Hero", h.attr_points > 0 or fitting_items.any(func(it): return _first_free_slot(h, it.slot_type()) >= 0 and GameState.attr_req_met(it, h))],
		["skills", "Skills", h.skill_points > 0 or not evolve_choices.is_empty()],
		["history", "History", false],
	]
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	for td in tab_defs:
		var tb := _button(str(td[1]) + ("  •" if td[2] else ""), func(t=str(td[0])):
			roster_tab = t
			if t == "skills" and expanded_skill_tree_kind == "":
				expanded_skill_tree_kind = h.innate_kind
			render()
		)
		tb.toggle_mode = true
		tb.button_pressed = roster_tab == td[0]
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_row.add_child(tb)
	cv.add_child(tab_row)
	cv.add_child(_hsep())

	match roster_tab:
		"skills":
			if GameData.SUBCLASS_ABILITIES.has(h.pool_id):
				var ab: Dictionary = GameData.SUBCLASS_ABILITIES[h.pool_id]
				var ab_row := HBoxContainer.new()
				ab_row.add_theme_constant_override("separation", 8)
				ab_row.add_child(_icon(GameData.ability_icon(h.pool_id), 28))
				var ab_mid := _vbox(0)
				ab_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				ab_mid.add_child(_label("Ability: %s" % str(ab["name"]), 12))
				ab_mid.add_child(_wrap_label(str(ab["desc"]), 11, true))
				ab_row.add_child(ab_mid)
				if h.level < 3:
					ab_row.add_child(_label("Unlocks at Lv3", 11, true))
				elif h.ability_awakened:
					ab_row.add_child(_label("Awakened (%s)" % GameData.awakening_bonus_text(h.pool_id), 11, true))
				else:
					ab_row.add_child(_icon_button("res://assets/skills/gem_red.png", "Awaken (%d SP, %s)" % [GameData.ABILITY_AWAKENING_COST, GameData.awakening_bonus_text(h.pool_id)], func(id=h.id):
						var err := GameState.awaken_ability(id)
						if err != "":
							push_warning(err)
						render()
					))
				cv.add_child(ab_row)
				if not evolve_choices.is_empty() or h.prior_pool_id != "":
					cv.add_child(_label("Evolving replaces this Ability, but skill trees carry over.", 10, true))
			# Evolution runs on Evolution Stones for the B/A/S jump (dropped by Rift
			# Map clears — see GameState.seal_rift/evolve_hero). The player picks the
			# path: "Evolve" opens every candidate with what it would change (stat,
			# element, Ability, passive), each with its own confirm button.
			if not evolve_choices.is_empty():
				var next_rank_id: String = evolve_choices[0]["rank"]
				var next_rank := GameData.find_rank(next_rank_id)
				var needs_stone: bool = next_rank_id in ["B", "A", "S"]
				var stone_count: int = int(GameState.evolution_stones.get(next_rank_id, 0))
				var evolve_label := "Evolve (%dcr, %d %s-Stone)" % [int(next_rank["cost"]), stone_count, next_rank_id] if needs_stone else "Evolve (%dcr)" % int(next_rank["cost"])
				var picking := evolve_picker_hero_id == h.id
				cv.add_child(_icon_button("res://assets/skills/star.png", "Hide evolution paths" if picking else evolve_label, func(id=h.id):
					evolve_picker_hero_id = "" if evolve_picker_hero_id == id else id
					render()
				))
				if picking:
					for c in evolve_choices:
						var ab: Dictionary = GameData.SUBCLASS_ABILITIES.get(str(c["id"]), {})
						var lines: Array[String] = [
							"[b]%s[/b] — Rank %s, %s" % [str(c["name"]), str(c["rank"]), str(c["type"])],
							"Main stat: %s" % Combat.describe_skill(str(c["kind"]), Combat.hero_innate_value(c, GameData.rank_index(str(c["rank"])))),
							"Passive: %s" % _passive_bb(str(c["id"])),
						]
						if not ab.is_empty():
							lines.append("Ability: %s — %s" % [str(ab["name"]), str(ab["desc"])])
						lines.append(str(c["flavor"]))
						cv.add_child(_rich_info_row("\n".join(lines), 11, [_icon_button("res://assets/skills/star.png", "Choose", func(id=h.id, pid=str(c["id"])):
							var err := GameState.evolve_hero(id, pid)
							if err != "":
								push_warning(err)
							else:
								evolve_picker_hero_id = ""
								_flavor_toast = GameData.narrative_line("hero_evolved")
							render()
						)], _icon_trimmed(GameData.portrait_for_hero(str(c["role"]), str(c["id"])), 32) if GameData.portrait_for_hero(str(c["role"]), str(c["id"])) != "" else null))

			var reinforce_count: int = int(GameState.evolution_stones.get(h.rank, 0))
			var reinforce_used: int = int(h.stone_bonus_used.get(h.pool_id, 0))
			if reinforce_count > 0 and reinforce_used < GameData.EVOLUTION_STONE_BONUS_SP_CAP:
				cv.add_child(_icon_button("res://assets/skills/gem_red.png", "Reinforce (+1 SP, %d/%d used)" % [reinforce_used, GameData.EVOLUTION_STONE_BONUS_SP_CAP], func(id=h.id):
					var err := GameState.reinforce_hero(id)
					if err != "":
						push_warning(err)
					render()
				))
			# One pill per tree the hero has unlocked — evolving keeps every past
			# stage's tree reachable instead of replacing it, so a heavily-evolved
			# hero can have several; only one tree's grid shows at a time (accordion
			# style) to avoid stacking multiple full grids on screen at once.
			var tree_summaries: Array = GameData.hero_tree_summaries(h)
			var pills := HBoxContainer.new()
			pills.add_theme_constant_override("separation", 6)
			for summary in tree_summaries:
				var kind: String = summary["kind"]
				var is_open: bool = expanded_skill_tree_kind == kind
				pills.add_child(_icon_button("res://assets/skills/eye_gem.png", "Hide %s" % str(summary["label"]) if is_open else str(summary["label"]), func(k=kind):
					expanded_skill_tree_kind = "" if expanded_skill_tree_kind == k else k
					render()
				))
			cv.add_child(pills)

			if not expanded_skill_tree_kind.is_empty() and tree_summaries.any(func(s): return s["kind"] == expanded_skill_tree_kind):
				cv.add_child(_hsep())
				cv.add_child(_label("Skill Points: %d" % h.skill_points, 12))
				_render_skill_tree_graph(cv, h, expanded_skill_tree_kind)
				# Per-tree, not "respec everything" — a hero holds at most 2 trees
				# (current + one prior evolution stage), so undoing just the one
				# fork choice you regret no longer means nuking the other tree too.
				var tree_prefix := "%s:" % expanded_skill_tree_kind
				var tree_spent := h.skills.keys().any(func(k): return h.skills[k] and str(k).begins_with(tree_prefix))
				if tree_spent:
					cv.add_child(_icon_button(GameData.BUTTON_ICON_PATH["dice"], "Respec this tree (%dc)" % GameState.tree_respec_cost(h, expanded_skill_tree_kind), func(id=h.id, k=expanded_skill_tree_kind):
						var err := GameState.respec_hero(id, k)
						if err != "":
							push_warning(err)
						render()
					))
		"history":
			var hist_lines := _history_lines(h)
			for line in hist_lines:
				cv.add_child(_rich_line(line, 12, true))
			if hist_lines.is_empty():
				cv.add_child(_label("No deeds yet — send this hero into a rift.", 11, true))
			for scar_name in h.scars:
				cv.add_child(_info_row("Scar: %s — %s" % [scar_name, _scar_text(scar_name)], 11, [_icon_button("res://assets/skills/potion_blue.png", "Scrub (30c)", func(id=h.id, sn=scar_name):
					var err := GameState.scrub_scar(id, sn)
					if err != "":
						push_warning(err)
					render()
				)], null, true))
		_:
			_render_hero_sheet(cv, h, fitting_items)

	card.add_child(cv)
	right.add_child(card)


## The hero sheet: a paper doll (weapons left, the hero in the middle, gear
## right), attributes and every stat beside it, and the gear this hero can
## use underneath — equip by clicking a slot or dragging a tile onto it.
func _render_hero_sheet(cv: VBoxContainer, h: Hero, fitting_items: Array[Item]) -> void:
	var sheet := HBoxContainer.new()
	sheet.add_theme_constant_override("separation", 18)
	var doll := HBoxContainer.new()
	doll.add_theme_constant_override("separation", 10)
	var wcol := _vbox(6)
	wcol.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in GameData.weapon_slots(h.pool_id):
		wcol.add_child(_equip_slot_frame(h, "weapon", i, 58.0))
	doll.add_child(wcol)
	var mid := _vbox(6)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	var stage := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Palette.SURFACE
	st.border_color = Palette.LINE
	st.set_border_width_all(1)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(10)
	stage.add_theme_stylebox_override("panel", st)
	stage.custom_minimum_size = Vector2(170, 220)
	var cc := CenterContainer.new()
	var portrait := GameData.portrait_for_hero(h.cls_id, h.pool_id)
	if portrait != "":
		cc.add_child(_icon_trimmed(portrait, 190))
	stage.add_child(cc)
	mid.add_child(stage)
	var pw := _label("Power %d" % Combat.power_of(h), 15)
	pw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(pw)
	doll.add_child(mid)
	var gcol := _vbox(6)
	gcol.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in GameData.gear_slots(h.rank):
		gcol.add_child(_equip_slot_frame(h, "gear", i, 58.0))
	doll.add_child(gcol)
	sheet.add_child(doll)

	var side := _vbox(10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(_attr_panel(h))
	side.add_child(_stat_panel(h))
	sheet.add_child(side)
	cv.add_child(sheet)

	if expanded_slot.begins_with("%s:weapon:" % h.id):
		_render_equip_picker(cv, h, "weapon", int(expanded_slot.split(":")[2]))
	if expanded_slot.begins_with("%s:gear:" % h.id):
		_render_equip_picker(cv, h, "gear", int(expanded_slot.split(":")[2]))

	cv.add_child(_hsep())
	if fitting_items.is_empty():
		cv.add_child(_label("No unequipped gear this hero can use.", 12, true))
	else:
		var usable := fitting_items.filter(func(it): return GameState.attr_req_met(it, h)).size()
		cv.add_child(_label("Inventory — drag onto a slot to equip (%d usable, %d need more attributes)" % [usable, fitting_items.size() - usable], 12, true))
		var sorted := fitting_items.duplicate()
		sorted.sort_custom(func(x, y): return _rarity_rank(x.rarity) > _rarity_rank(y.rarity))
		var inv_flow := HFlowContainer.new()
		inv_flow.add_theme_constant_override("h_separation", 6)
		inv_flow.add_theme_constant_override("v_separation", 6)
		for it in sorted:
			inv_flow.add_child(_item_tile(it, 48, h))
		cv.add_child(inv_flow)

	cv.add_child(_hsep())
	cv.add_child(_rich_line("Passive — " + _passive_bb(h.pool_id), 12))
	cv.add_child(_wrap_label(_position_text(h), 12, true))
	var build := _build_bb(h)
	if build != "":
		cv.add_child(_rich_line("Build: " + build, 12, true))
	var trait_row := HBoxContainer.new()
	trait_row.add_theme_constant_override("separation", 8)
	var tl := _label("Trait: %s" % (h.trait_name if h.trait_name != "" else "Steadfast"), 12, true)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trait_row.add_child(tl)
	trait_row.add_child(_icon_button(GameData.BUTTON_ICON_PATH["dice"], "Reroll Trait (60c)", func(id=h.id):
		var err := GameState.reroll_trait(id)
		if err != "":
			push_warning(err)
		render()
	))
	if h.trait_name != "":
		trait_row.add_child(_icon_button("res://assets/skills/potion_blue.png", "Scrub Trait (30c)", func(id=h.id):
			var err := GameState.scrub_trait(id)
			if err != "":
				push_warning(err)
			render()
		))
	cv.add_child(trait_row)


## Might / Agility / Focus with a + per attribute while there are points to
## spend, and Auto (the role's usual spread).
const _ATTR_SHORT := {"dmg_pct": "dmg", "hp_pct": "HP", "speed_pct": "speed", "dodge_pct": "dodge",
	"first_round_pct": "first strike", "ability_power": "ability power", "mend_pct": "mend"}


func _attr_panel(h: Hero) -> PanelContainer:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Palette.SURFACE
	st.border_color = Palette.EMBER_DEEP if h.attr_points > 0 else Palette.LINE
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", st)
	var v := _vbox(4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(_label("Attributes", 15))
	if h.attr_points > 0:
		var pts := _label("%d point%s to spend" % [h.attr_points, "" if h.attr_points == 1 else "s"], 13)
		pts.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		pts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(pts)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(sp)
		var auto := _button("Auto", func(id=h.id): GameState.auto_assign_attrs(id); render())
		auto.tooltip_text = "Spend them the %s way" % GameData.hero_role(h).capitalize()
		head.add_child(auto)
	v.add_child(head)
	for a in GameData.ATTRIBUTES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.tooltip_text = "%s — %s" % [GameData.ATTR_LABEL[a], GameData.ATTR_DESC[a]]
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		var nl := _label(GameData.ATTR_LABEL[a], 14)
		nl.custom_minimum_size.x = 76
		row.add_child(nl)
		var total := Combat.hero_attr(h, a)
		var gear: int = total - int(h.attrs.get(a, GameData.ATTR_BASELINE))
		var vl := _label(str(total), 15)
		vl.custom_minimum_size.x = 28
		row.add_child(vl)
		if gear != 0:
			row.add_child(_label("(%+d gear)" % gear, 12, true))
		var sp2 := Control.new()
		sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp2)
		var per: Dictionary = GameData.ATTR_EFFECTS[a]
		var bits: Array[String] = []
		var long_bits: Array[String] = []
		for k in per:
			var val: float = (total - GameData.ATTR_BASELINE) * float(per[k]) * 100.0
			bits.append(("%+.1f%% %s" if absf(val) < 1.0 else "%+.0f%% %s") % [val, _ATTR_SHORT.get(k, k)])
			long_bits.append(Combat.describe_skill(str(k), val / 100.0))
		row.tooltip_text += "
" + "
".join(long_bits)
		row.add_child(_label(", ".join(bits), 12, true))
		if h.attr_points > 0:
			var plus := _button("+", func(id=h.id, at=a): GameState.spend_attr_point(id, at); render())
			plus.custom_minimum_size = Vector2(36, 30)
			plus.tooltip_text = "+1 %s" % GameData.ATTR_LABEL[a]
			row.add_child(plus)
		v.add_child(row)
	panel.add_child(v)
	return panel


## HP, damage and speed, then every bonus the hero has — hover any line for
## where it comes from.
func _stat_panel(h: Hero) -> PanelContainer:
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Palette.SURFACE
	st.border_color = Palette.LINE
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", st)
	var v := _vbox(4)
	v.add_child(_label("Stats", 15))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 3)
	var add := func(name: String, value: String, tip: String):
		var nl := _label(name, 12, true)
		var vl := _label(value, 13)
		if tip != "":
			_rich_tip(nl, tip)
			_rich_tip(vl, tip)
		grid.add_child(nl)
		grid.add_child(vl)
	add.call("HP", "%d / %d" % [h.hp, Combat.max_hp(h)], _stat_breakdown_card(h, "hp_pct", Combat.hero_skill_total(h, "hp_pct")))
	add.call("Damage", str(Combat.dmg_of(h)), _stat_breakdown_card(h, "dmg_pct", Combat.hero_skill_total(h, "dmg_pct")))
	add.call("Speed", "%.1f" % Combat.spd_of(h), _stat_breakdown_card(h, "speed_pct", Combat.hero_skill_total(h, "speed_pct")))
	for kind in GameData.BUILD_KINDS:
		if kind in ["dmg_pct", "hp_pct", "speed_pct"]:
			continue
		var total := Combat.hero_skill_total(h, kind)
		if absf(total) < 0.0005:
			continue
		add.call(str(_KIND_LABEL.get(kind, kind)), "%+.1f%%" % (total * 100.0), _stat_breakdown_card(h, kind, total))
	v.add_child(grid)
	panel.add_child(v)
	return panel


## One skill node as a compact hex tile (icon + short name caption) instead
## of a full-width text row — hover/long-press for the full effect text and
## gating reason via tooltip. A ready-to-learn node glows (via _action_slot's
## `selected`), a learned one gets a warm gold tint, anything else just dims.
## `kind` identifies which of the hero's unlocked trees `n` belongs to (used
## to compute Hero.skills's namespaced storage key) — irrelevant for the
## universal Tier-1 roots, which GameData.skill_storage_key leaves bare.
func _skill_node_tile(h: Hero, kind: String, n: Dictionary) -> Control:
	var skill_id: String = n["id"]
	var key := GameData.skill_storage_key(kind, skill_id)
	var learned: bool = h.skills.get(key, false)
	var missing_level: bool = h.level < int(n["req_level"])
	var missing_prereq := false
	for req in n["requires"]:
		if not h.skills.get(GameData.skill_storage_key(kind, req), false):
			missing_prereq = true
	if not n.get("requires_any", []).is_empty() and not n["requires_any"].any(func(r): return h.skills.get(GameData.skill_storage_key(kind, r), false)):
		missing_prereq = true
	var locked_out := false
	for excl in n.get("excludes", []):
		if h.skills.get(GameData.skill_storage_key(kind, excl), false):
			locked_out = true
	var missing_sp: bool = h.skill_points < int(n["cost"])
	var can_learn := not learned and not missing_level and not missing_prereq and not missing_sp and not locked_out

	var reason := "Learned"
	if not learned:
		if locked_out:
			reason = "Locked out by your other path"
		elif missing_level:
			reason = "Requires Lv%d" % int(n["req_level"])
		elif missing_prereq:
			reason = "Needs prerequisite"
		elif missing_sp:
			reason = "Needs %d SP" % int(n["cost"])
		else:
			reason = "Learn (%d SP)" % int(n["cost"])

	var combo_line := ""
	if n.has("combo_kind"):
		var combo_active := learned and GameState.party_has_other_kind_capstone(h.id, str(n["combo_kind"]))
		combo_line = "\n%s+%s if a party ally has reached %s's capstone" % [
			"(Active) " if combo_active else "",
			Combat.describe_skill(str(n["kind"]), float(n.get("combo_bonus", 0.0))),
			str(n["combo_kind"]),
		]
	var tile := _action_slot(str(n["icon"]), "", can_learn, not can_learn and not learned, func(hid=h.id, k=kind, sid=skill_id):
		var err := GameState.learn_skill(hid, k, sid)
		if err != "":
			push_warning(err)
		render()
	, 60.0, str(n["name"]), GameData.SKILL_NODE_FRAME_PATH, "%s\n%s\n%s%s" % [str(n["name"]), _node_effect_text(n), reason, combo_line])
	if learned:
		tile.modulate = Color(1.15, 1.02, 0.68)
	var card := "[b]%s[/b]\n%s\n%s%s" % [str(n["name"]).replace("[", "[lb]"), _node_effect_text(n).replace("[", "[lb]"), _bb(Palette.MUTED, reason), combo_line.replace("[", "[lb]")]
	for c in tile.get_children():
		if c is BaseButton:
			_rich_tip(c, card + _kw_footer(card))
	return tile


## One tree, as a 4-column grid (Tier 1 → Tier 2 → Path → Mastery) instead
## of a flat scrolling list. Tier 1/Tier 2 alignment is unchanged — each
## singly-gated Tier-2 node sits in the same row as the Tier-1 node its
## `requires` points at; a Tier-2 node needing BOTH roots (or neither) gets
## its own row below. Tier 3 is normally a hard-exclusive fork (nodes that
## each `excludes` the others), placed one per row so "Path" reads as
## options stacked rather than one column; Tier 4 holds each fork's own
## finisher, found the same way — whichever Tier-4 node's `requires` points
## at that row's Tier-3 node. Fork rows are sized off `max(tier1, tier3)`,
## not tier1 alone, so a kind with more forks than the usual 2 (dodge_pct's
## 3-way fork) still gets a row for its extra fork+finisher pair instead of
## that pair silently never rendering.
const COL_W := 84.0   # skill tree column width (tile + room for its caption)


func _render_skill_tree_graph(cv: VBoxContainer, h: Hero, kind: String) -> void:
	var tree: Array = GameData.tier1_for_role(h.cls_id) + GameData.KIND_SKILL_PACKAGE.get(kind, [])
	var tier1: Array = tree.filter(func(n): return int(n["tier"]) == 1)
	var tier2: Array = tree.filter(func(n): return int(n["tier"]) == 2)
	var tier3: Array = tree.filter(func(n): return int(n["tier"]) == 3)
	var tier4: Array = tree.filter(func(n): return int(n["tier"]) == 4)

	# 5th column: the tree's keystone (row 0) and the role signature (row 1).
	var tier5: Array = [GameData.keystone_node(kind), GameData.signature_node(h.cls_id)].filter(func(n): return not n.is_empty())

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 10)
	# Column headers are the grid's own first row (they used to be a separate
	# HBox that spread across the full width and drifted off the columns).
	for col_label in ["Tier 1", "Tier 2", "Path", "Mastery", "Keystone"]:
		var lbl := _label(col_label, 11, true)
		lbl.custom_minimum_size.x = COL_W
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(lbl)
	# Every cell is centered in a fixed-width column; `tiles` remembers each
	# node's tile so the link lines can find it.
	var tiles := {}
	var cell := func(n: Dictionary) -> Control:
		var c := CenterContainer.new()
		c.custom_minimum_size.x = COL_W
		if not n.is_empty():
			var tile := _skill_node_tile(h, kind, n)
			tiles[str(n["id"])] = tile
			c.add_child(tile)
		return c

	var singly_gated_tier2: Array = tier2.filter(func(n): return (n["requires"] as Array).size() == 1)
	var other_tier2: Array = tier2.filter(func(n): return (n["requires"] as Array).size() != 1)
	var fork_rows: int = max(tier1.size(), tier3.size())
	var row_count: int = max(fork_rows, 1) + other_tier2.size()

	for row_i in row_count:
		if row_i < fork_rows:
			if row_i < tier1.size():
				var t1: Dictionary = tier1[row_i]
				grid.add_child(cell.call(t1))
				var dep := singly_gated_tier2.filter(func(n): return (n["requires"] as Array).has(t1["id"]))
				grid.add_child(cell.call(dep[0] if not dep.is_empty() else {}))
			else:
				grid.add_child(cell.call({}))
				grid.add_child(cell.call({}))
			if row_i < tier3.size():
				var fork: Dictionary = tier3[row_i]
				grid.add_child(cell.call(fork))
				var finisher := tier4.filter(func(n): return (n["requires"] as Array).has(fork["id"]))
				grid.add_child(cell.call(finisher[0] if not finisher.is_empty() else {}))
			else:
				grid.add_child(cell.call({}))
				grid.add_child(cell.call({}))
		else:
			grid.add_child(cell.call({}))
			grid.add_child(cell.call(other_tier2[row_i - fork_rows]))
			grid.add_child(cell.call({}))
			grid.add_child(cell.call({}))
		grid.add_child(cell.call(tier5[row_i] if row_i < tier5.size() else {}))

	# Prerequisite links, drawn behind the tiles (SkillTreeLines).
	var lines := SkillTreeLines.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var learned := func(id: String) -> bool: return h.skills.get(GameData.skill_storage_key(kind, id), false)
	for n in tree + tier5:
		var nid := str(n["id"])
		# The role signature hangs off the Tier-1 roots, which would draw a
		# line straight across the whole tree — its tooltip says what it needs.
		if not tiles.has(nid) or nid == "signature":
			continue
		for r in n.get("requires", []) + n.get("requires_any", []):
			if tiles.has(str(r)):
				var state := 2 if learned.call(str(r)) and learned.call(nid) else (1 if learned.call(str(r)) else 0)
				lines.edges.append([tiles[str(r)], tiles[nid], state])
	# A MarginContainer stacks its children over the same rect, so the lines
	# layer sits exactly behind the grid and sizes itself with it.
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.add_child(lines)
	holder.add_child(grid)
	cv.add_child(holder)
	grid.sort_children.connect(lines.queue_redraw)


## One hero in the Roster list: portrait, name, level/class, an HP bar and
## their build chip, with a dot when they have something to act on (unspent
## SP, gear that fits an empty slot). The selected row is outlined.
func _roster_row(h: Hero) -> Control:
	var selected := selected_hero_id == h.id
	var b := _button("", func(id=h.id):
		selected_hero_id = id
		expanded_slot = ""
		render()
	)
	b.custom_minimum_size = Vector2(300, 64)
	b.toggle_mode = true
	b.button_pressed = selected
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait_path := GameData.portrait_for_hero(h.cls_id, h.pool_id)
	if portrait_path != "":
		var pi := _icon_trimmed(portrait_path, 48)
		pi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if h.is_downed() or h.hp <= 0:
			pi.modulate = Color(0.5, 0.5, 0.5, 0.8)
		row.add_child(pi)
	var col := _vbox(2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var nm := _label(h.name.split(" the ")[0], 14)
	if selected:
		nm.add_theme_color_override("font_color", Palette.VIOLET_BRIGHT)
	top.add_child(nm)
	var arch := _main_arch(h)
	if arch != "":
		var chip := _label("◆ " + str(GameData.ARCHETYPES[arch]), 12)
		chip.add_theme_color_override("font_color", ARCH_COLOR.get(arch, Palette.MUTED))
		top.add_child(chip)
	col.add_child(top)
	col.add_child(_label("Lv%d %s (%s) · %d/%d HP" % [h.level, h.cls_id.capitalize(), h.rank, h.hp, Combat.max_hp(h)], 12, true))
	col.add_child(_flat_bar(Combat.max_hp(h), h.hp, 170, 4, _hp_color(float(h.hp) / float(max(1, Combat.max_hp(h))))))
	row.add_child(col)
	var needs := h.skill_points > 0
	for st in ["weapon", "gear"]:
		if _first_free_slot(h, st) >= 0 and GameState.items.any(func(it): return it.equipped_to == "" and it.slot_type() == st and GameState.item_fits_hero(it, h)):
			needs = true
	if needs:
		var dot := _count_badge("!", "Unspent skill points or gear that fits an empty slot")
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(dot)
	b.add_child(row)
	return b


## One equip-slot frame for the Roster paper-doll: a rarity-tinted border
## (RARITY_FRAME_PATH — "common" when empty) with the equipped item's category
## icon centered inside (blank when empty) and a short caption underneath
## (the item's first name word, or "Weapon"/"Gear" when empty) so the slot
## reads without opening anything. Clicking toggles this slot's inline
## equip-picker below the row — same expand/collapse pattern already used for
## the Skills button and Medical Bay's bed picker.
func _equip_slot_frame(h: Hero, slot_type: String, idx: int, size: float = 56.0) -> Control:
	var equipped := _find_equipped_at(h.id, slot_type, idx)
	var slot_key := "%s:%s:%d" % [h.id, slot_type, idx]
	var is_open := expanded_slot == slot_key
	var label_text := equipped.name.split(" ")[0] if equipped else ("Weapon" if slot_type == "weapon" else "Gear")
	var icon_path: String = GameData.item_icon(equipped) if equipped else ""
	var cb := func():
		expanded_slot = "" if is_open else slot_key
		render()
	var can_accept := func(data):
		if typeof(data) != TYPE_DICTIONARY or data.get("kind", "") != "inventory_item":
			return false
		if data.get("slot_type", "") != slot_type:
			return false
		var candidate := GameState.find_item(str(data.get("item_id", "")))
		return candidate != null and GameState.item_fits_hero(candidate, h) and GameState.attr_req_met(candidate, h)
	var on_drop := func(data):
		GameState.equip_item(h.id, slot_type, idx, str(data.get("item_id", "")))
		render()
	var drop_target := {"can_accept": can_accept, "on_drop": on_drop}
	var frame_path: String = GameData.RARITY_FRAME_PATH.get(equipped.rarity, "") if equipped else ""
	return _action_slot(icon_path, "", is_open, false, cb, size, label_text, frame_path, _item_card(equipped, h) if equipped else "", drop_target)


## The picker for whichever equip slot is currently expanded: shows the
## equipped item (with Unequip + matching Socket options) if any, then every
## unequipped item that fits this hero and slot with an Equip button — reuses
## GameState.equip_item/item_fits_hero exactly like the old Inventory-tab
## "Equip →" flow did, just triggered from the hero's own card instead.
func _render_equip_picker(cv: VBoxContainer, h: Hero, slot_type: String, idx: int) -> void:
	var equipped := _find_equipped_at(h.id, slot_type, idx)
	var picker := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.SURFACE3
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Palette.VIOLET
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 8
	style.content_margin_top = 6
	style.content_margin_right = 8
	style.content_margin_bottom = 6
	picker.add_theme_stylebox_override("panel", style)
	var pv := _vbox(4)

	if equipped:
		var eq_row := _info_row("%s (%s) — %s" % [_loot_display_name(equipped), GameData.ITEM_CATEGORY_LABEL[equipped.category], _loot_desc(equipped, false)], 12, [], _icon(GameData.item_icon(equipped), 18))
		_rich_tip(eq_row, _item_card(equipped))
		pv.add_child(eq_row)
		var eactions := HBoxContainer.new()
		eactions.add_child(_icon_button("res://assets/skills/armor_chest.png", "Unequip", func(hid=h.id, st=slot_type, i=idx):
			GameState.equip_item(hid, st, i, "")
			render()
		))
		if equipped.socketed_kind != "":
			eactions.add_child(_label("Socketed: %s" % Combat.describe_skill(equipped.socketed_kind, equipped.socketed_value), 11, true))
		else:
			for r in GameState.runestones:
				var rdef := GameData.find_runestone(str(r["runestone_id"]))
				if rdef.get("category", "") != slot_type:
					continue
				eactions.add_child(_icon_button("res://assets/skills/ring.png", "Socket %s" % str(rdef["name"]), func(rid=r["id"], iid=equipped.id):
					var err := GameState.socket_runestone(rid, iid)
					if err != "":
						push_warning(err)
					render()
				))
		pv.add_child(eactions)
		pv.add_child(_hsep())

	var candidates: Array[Item] = []
	candidates.assign(GameState.items.filter(func(it): return it.equipped_to == "" and it.slot_type() == slot_type and GameState.item_fits_hero(it, h)))
	if candidates.is_empty():
		pv.add_child(_label("No unequipped %s available." % ("weapons" if slot_type == "weapon" else "gear"), 11, true))
	for it in candidates:
		var equip_btn := _icon_button(GameData.item_icon(it), "Equip", func(hid=h.id, st=slot_type, i=idx, iid=it.id):
			GameState.equip_item(hid, st, i, iid)
			expanded_slot = ""
			render()
		)
		var cand_row := _info_row("%s (%s) — %s" % [_loot_display_name(it), GameData.ITEM_CATEGORY_LABEL[it.category], _loot_desc(it, false)], 12, [equip_btn], _icon(GameData.item_icon(it), 18))
		_rich_tip(cand_row, _item_card(it, h, idx))
		pv.add_child(cand_row)
		var cmp := _item_compare_text(it, h, idx)
		if cmp != "":
			pv.add_child(_wrap_label(cmp.replace(":\n", ": ").replace("\n", " · "), 10, true))

	pv.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Close", func():
		expanded_slot = ""
		render()
	))
	picker.add_child(pv)
	cv.add_child(picker)


func _render_inventory(v: VBoxContainer) -> void:
	if inv_category == "":
		_render_inventory_hub(v)
		return
	match inv_category:
		"relics": _render_inventory_relics(v)
		"detectors": _render_inventory_detectors(v)
		_: _render_inventory_items(v)


## The 3 Inventory categories as clickable stations on a storage-vault scene
## (a chest for Items, a glowing altar for Relics, a table with a spyglass
## for Detectors) — same background-prop-as-button + hover-glow pattern as
## the camp/management screens.
func _render_inventory_hub(v: VBoxContainer) -> void:
	var scene_size := Vector2(700, 340)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size
	scene.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var bg := TextureRect.new()
	bg.texture = load(GameData.INVENTORY_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)

	# hit_rect (generous, easy-to-click) + native_rect (the station's own
	# tight bounds in the source 320x200 art, for the hover glow).
	var cat_entries := [
		["items", "Items", Rect2(0, 0, 230, 340), Rect2(3, 103, 97, 70)],
		["relics", "Relics", Rect2(230, 0, 240, 340), Rect2(133, 58, 62, 100)],
		["detectors", "Rift Detectors", Rect2(470, 0, 230, 340), Rect2(210, 65, 110, 95)],
	]
	var camp_scale := Vector2(700.0 / 320.0, 340.0 / 200.0)
	for entry in cat_entries:
		var cid: String = entry[0]
		var label_text: String = entry[1]
		var hit_rect: Rect2 = entry[2]
		var native_rect: Rect2 = entry[3]
		var glow_rect := Rect2(
			native_rect.position.x * camp_scale.x, native_rect.position.y * camp_scale.y,
			native_rect.size.x * camp_scale.x, native_rect.size.y * camp_scale.y
		)
		var hotspot := _camp_area_hotspot(hit_rect, glow_rect, label_text, func(id=cid):
			inv_category = id
			render()
		)
		hotspot.position = hit_rect.position
		scene.add_child(hotspot)

	v.add_child(scene)


func _render_inventory_items(v: VBoxContainer) -> void:
	var unequipped_items: Array[Item] = []
	unequipped_items.assign(GameState.items.filter(func(it): return it.equipped_to == "" and (inv_filter == "all" or it.category == inv_filter)))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(_label("Items (%d)" % unequipped_items.size(), 20))
	# Category filter chips.
	for f in [["all", "All"], ["weapon", "Weapons"], ["armor", "Armor"], ["focus", "Focus"]]:
		var n: int = GameState.items.filter(func(it): return it.equipped_to == "" and (f[0] == "all" or it.category == f[0])).size()
		var chip := _button("%s %d" % [f[1], n], func(id=str(f[0])):
			inv_filter = id
			selected_item_id = ""
			render()
		)
		chip.toggle_mode = true
		chip.button_pressed = inv_filter == f[0]
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(chip)
	head.add_child(_sort_cycle_button(inv_sort, [
		{"id": "rarity", "label": "Rarity"},
		{"id": "value", "label": "Value"},
		{"id": "name", "label": "Name"},
	], func(new_id): inv_sort = new_id))
	v.add_child(head)
	match inv_sort:
		"rarity":
			unequipped_items.sort_custom(func(a, b): return _rarity_rank(a.rarity) > _rarity_rank(b.rarity))
		"value":
			unequipped_items.sort_custom(func(a, b): return a.value > b.value)
		"name":
			unequipped_items.sort_custom(func(a, b): return a.name < b.name)
	if unequipped_items.is_empty():
		v.add_child(_label("No unequipped items.", 12))
	elif not unequipped_items.any(func(it): return it.id == selected_item_id):
		selected_item_id = unequipped_items[0].id
	# Two panes: a grid of item tiles, and the selected item's card + actions.
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.custom_minimum_size.x = 460
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail := _vbox(8)
	detail.custom_minimum_size.x = 380
	if not unequipped_items.is_empty():
		split.add_child(grid)
		split.add_child(detail)
		v.add_child(split)
	for it in unequipped_items:
		var tile := _action_slot(GameData.item_icon(it), "", it.id == selected_item_id, false, func(id=it.id):
			selected_item_id = id
			render()
		, 56.0, "", GameData.RARITY_FRAME_PATH.get(it.rarity, ""), _loot_display_name(it))
		# A green dot: fills an empty slot on someone who can use it.
		var note := _loot_fit_note(it, false, GameState.heroes)
		if str(note[0]).begins_with("Fills"):
			var dot := _count_badge("+", str(note[0]))
			dot.position = Vector2(40, -4)
			(dot.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Palette.RANK_E
			tile.add_child(dot)
		grid.add_child(tile)
		if it.id != selected_item_id:
			continue
		var actions: Array[Control] = []
		for h2 in GameState.heroes:
			var slot := it.slot_type()
			if not GameState.item_fits_hero(it, h2):
				continue
			var target_idx := _best_swap_slot(h2, slot)
			if target_idx < 0 or not GameState.attr_req_met(it, h2):
				continue
			var is_free := _first_free_slot(h2, slot) >= 0
			var verb := "Equip → %s" if is_free else "Swap → %s"
			actions.append(_icon_button(GameData.item_icon(it), verb % h2.name.split(" the ")[0], func(hid=h2.id, iid=it.id, s=slot, idx=target_idx):
				GameState.equip_item(hid, s, idx, iid)
				render()
			))
		actions.append(_icon_button(GameData.CURRENCY_ICON_PATH["coins"], "Sell", func(id=it.id):
			GameState.sell_item(id)
			render()
		))
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanelViolet"
		var cv := _vbox(10)
		cv.add_child(_rich_line(_item_card(it), 13))
		var act_flow := HFlowContainer.new()
		act_flow.add_theme_constant_override("h_separation", 6)
		act_flow.add_theme_constant_override("v_separation", 6)
		for a in actions:
			act_flow.add_child(a)
		cv.add_child(act_flow)
		card.add_child(cv)
		detail.add_child(card)

	v.add_child(_hsep())
	v.add_child(_label("Field Incense — used at Party Assembly, lasts the whole rift", 16))
	if not GameState.consumables.is_empty():
		v.add_child(_label("Owned:", 12, true))
		for c in GameState.consumables:
			var def := GameData.find_incense(str(c["incense_id"]))
			v.add_child(_wrap_label("%s — %s" % [def["name"], def["desc"]], 12))
	for def in GameData.INCENSE_TYPES:
		var buy_btn := _icon_button(GameData.CURRENCY_ICON_PATH["coins"], "Buy", func(iid=def["id"]):
			var err := GameState.buy_incense(iid)
			if err != "":
				push_warning(err)
			render()
		)
		v.add_child(_info_row("%s (%dcr) — %s" % [def["name"], int(def["cost"]), def["desc"]], 12, [buy_btn]))

	v.add_child(_hsep())
	v.add_child(_label("Runestones — socket into an equipped item from its Roster card", 16))
	if not GameState.runestones.is_empty():
		v.add_child(_label("Owned:", 12, true))
		for r in GameState.runestones:
			var rdef := GameData.find_runestone(str(r["runestone_id"]))
			v.add_child(_wrap_label("%s — %s" % [rdef["name"], rdef["desc"]], 12))
	for rdef in GameData.RUNESTONE_TYPES:
		var buy_btn := _icon_button(GameData.CURRENCY_ICON_PATH["coins"], "Buy", func(rid=rdef["id"]):
			var err := GameState.buy_runestone(rid)
			if err != "":
				push_warning(err)
			render()
		)
		v.add_child(_info_row("%s (%dcr) — %s" % [rdef["name"], int(rdef["cost"]), rdef["desc"]], 12, [buy_btn]))


func _render_inventory_relics(v: VBoxContainer) -> void:
	var used := Combat.equipped_relics().size()
	var cap := GameState.relic_slot_cap()
	v.add_child(_label("Relics — %d/%d slots equipped" % [used, cap], 16))
	if used < cap and GameState.relics.any(func(r): return not r.equipped):
		var hint := _label("%d slot(s) empty — equipped relics apply to every hero in every rift." % (cap - used), 13)
		hint.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		v.add_child(hint)
	v.add_child(_sort_cycle_button(inv_sort, [
		{"id": "rarity", "label": "Rarity"},
		{"id": "level", "label": "Level"},
		{"id": "name", "label": "Name"},
	], func(new_id): inv_sort = new_id))
	var relics_sorted: Array[Relic] = []
	relics_sorted.assign(GameState.relics)
	match inv_sort:
		"rarity":
			relics_sorted.sort_custom(func(a, b): return _rarity_rank(a.rarity) > _rarity_rank(b.rarity))
		"level", "value":
			relics_sorted.sort_custom(func(a, b): return a.level > b.level)
		"name":
			relics_sorted.sort_custom(func(a, b): return a.name < b.name)
	for r in relics_sorted:
		var actions: Array[Control] = []
		var eq_cb := func(id=r.id):
			GameState.toggle_equip_relic(id)
			render()
		if r.equipped:
			actions.append(_icon_button(GameData.RELIC_TYPE_ICON_PATH[r.type], "Unequip", eq_cb))
		else:
			var eb := _icon_domain_button("ember", GameData.RELIC_TYPE_ICON_PATH[r.type], "Equip", eq_cb)
			eb.disabled = used >= cap
			eb.tooltip_text = "All relic slots are full — unequip one first" if used >= cap else ""
			actions.append(eb)
		if r.level < GameState.RELIC_MAX_LEVEL:
			var rar := GameData.find_rarity(r.rarity)
			var cost := int(round(15.0 * float(rar["mult"]) * r.level))
			actions.append(_icon_button(GameData.CURRENCY_ICON_PATH["crystals"], "Upgrade — %d" % cost, func(id=r.id):
				var err := GameState.upgrade_relic(id)
				if err != "":
					push_warning(err)
				render()
			))
		if not r.equipped:
			actions.append(_icon_button(GameData.CURRENCY_ICON_PATH["coins"], "Sell", func(id=r.id):
				GameState.sell_relic(id)
				render()
			))
			if GameState.recycle_unlocked():
				actions.append(_icon_button("res://assets/skills/ingot_gold.png", "Scrap", func(id=r.id):
					GameState.scrap_relic(id)
					render()
				))
		v.add_child(_info_row("%s (%s, Lv%d) — %s" % [_loot_display_name(r), r.type, r.level, _loot_desc(r, true)], 12, actions, _icon(GameData.RELIC_TYPE_ICON_PATH[r.type], 20)))


func _render_inventory_detectors(v: VBoxContainer) -> void:
	v.add_child(_label("Rift Detectors", 16))
	if GameState.detectors.is_empty():
		v.add_child(_label("No Detectors.", 12))
	for d in GameState.detectors:
		var drow := HBoxContainer.new()
		var det_id: String = d["id"]
		drow.add_child(_label("%s Detector" % str(d["tier"]).capitalize(), 12))
		drow.add_child(_icon_button(GameData.CURRENCY_ICON_PATH["coins"], "Sell", func(id=det_id):
			GameState.sell_detector(id)
			render()
		))
		drow.add_child(_icon_button("res://assets/skills/star.png", "Use for Shop Boost", func(id=det_id):
			var err := GameState.use_detector_for_shop_boost(id)
			if err != "":
				push_warning(err)
			render()
		))
		v.add_child(drow)
