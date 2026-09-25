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
	v.add_child(_banner(GameData.ROSTER_BG, 760, 190))
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes recruited yet."))
		return

	var still_here: Array[Hero] = []
	still_here.assign(GameState.heroes.filter(func(h): return h.id == selected_hero_id))
	if still_here.is_empty():
		selected_hero_id = ""

	v.add_child(_sort_cycle_button(roster_sort, [
		{"id": "power", "label": "Power"},
		{"id": "level", "label": "Level"},
		{"id": "rank", "label": "Rank"},
	], func(new_id): roster_sort = new_id))

	var stones_text := GameData.evolution_stones_text(GameState.evolution_stones)
	if stones_text != "":
		v.add_child(_label("Evolution Stones: %s" % stones_text, 11, true))

	var portrait_row := HBoxContainer.new()
	portrait_row.add_theme_constant_override("separation", 12)
	for h in _sorted_heroes():
		portrait_row.add_child(_roster_portrait_button(h))
	v.add_child(portrait_row)

	if selected_hero_id == "":
		v.add_child(_label("Click a hero above for their details.", 12, true))
		return
	var h: Hero = still_here[0]

	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelViolet"
	var cv := _vbox(4)
	cv.add_child(_title_strip(h.name))
	cv.add_child(_label("Lv%d %s (%s) · %d/%d HP" % [h.level, h.cls_id.capitalize(), h.rank, h.hp, Combat.max_hp(h)]))

	# Two-column dashboard — portrait/stats/trait on the left, the full
	# weapon+gear paper-doll as a grid on the right — replaces what used to
	# be five separate full-width rows (portrait, then a labeled Weapon row,
	# then a labeled Gear row) stacked one under another.
	var dash := HBoxContainer.new()
	dash.add_theme_constant_override("separation", 14)

	var left_v := _vbox(4)
	left_v.custom_minimum_size.x = 180
	left_v.add_child(_framed_portrait(h.cls_id, h.pool_id, 96.0))
	left_v.add_child(_label("Power %d" % Combat.power_of(h), 13))
	left_v.add_child(_label("HP %d/%d" % [h.hp, Combat.max_hp(h)], 12, true))
	for kind in GameData.BUILD_KINDS:
		var total := Combat.hero_skill_total(h, kind)
		if total != 0.0:
			left_v.add_child(_wrap_label(Combat.describe_skill(kind, total), 11, true))
	left_v.add_child(_wrap_label("Passive — %s" % _passive_text(h.pool_id), 11))
	left_v.add_child(_wrap_label(_position_text(h), 11, true))
	var build := _build_text(h)
	if build != "":
		left_v.add_child(_wrap_label("Build: %s" % build, 11, true))
	left_v.add_child(_wrap_label("Trait: %s" % (h.trait_name if h.trait_name != "" else "Steadfast"), 12, true))
	for line in _history_lines(h):
		left_v.add_child(_wrap_label(line, 11, true))
	for scar_name in h.scars:
		left_v.add_child(_info_row("Scar: %s — %s" % [scar_name, _scar_text(scar_name)], 11, [_icon_button("res://assets/skills/potion_blue.png", "Scrub (30c)", func(id=h.id, sn=scar_name):
			var err := GameState.scrub_scar(id, sn)
			if err != "":
				push_warning(err)
			render()
		)], null, true))
	dash.add_child(left_v)

	var right_v := _vbox(4)
	right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_v.add_child(_label("Equipment", 12, true))
	var equip_grid := GridContainer.new()
	equip_grid.columns = 3
	equip_grid.add_theme_constant_override("h_separation", 8)
	equip_grid.add_theme_constant_override("v_separation", 8)
	for i in GameData.weapon_slots(h.pool_id):
		equip_grid.add_child(_equip_slot_frame(h, "weapon", i))
	for i in GameData.gear_slots(h.rank):
		equip_grid.add_child(_equip_slot_frame(h, "gear", i))
	right_v.add_child(equip_grid)
	if expanded_slot.begins_with("%s:weapon:" % h.id):
		_render_equip_picker(right_v, h, "weapon", int(expanded_slot.split(":")[2]))
	if expanded_slot.begins_with("%s:gear:" % h.id):
		_render_equip_picker(right_v, h, "gear", int(expanded_slot.split(":")[2]))

	var fitting_items: Array[Item] = []
	fitting_items.assign(GameState.items.filter(func(it): return it.equipped_to == "" and GameState.item_fits_hero(it, h)))
	if not fitting_items.is_empty():
		right_v.add_child(_label("Inventory — drag onto a slot to equip", 11, true))
		var inv_flow := HFlowContainer.new()
		inv_flow.add_theme_constant_override("h_separation", 6)
		inv_flow.add_theme_constant_override("v_separation", 6)
		for it in fitting_items:
			inv_flow.add_child(_draggable_item_icon(it, 32, h))
		right_v.add_child(inv_flow)
	dash.add_child(right_v)
	cv.add_child(dash)

	var actions := HBoxContainer.new()
	actions.add_child(_icon_button(GameData.BUTTON_ICON_PATH["dice"], "Reroll Trait (60c)", func(id=h.id):
		var err := GameState.reroll_trait(id)
		if err != "":
			push_warning(err)
		render()
	))
	if h.trait_name != "":
		actions.add_child(_icon_button("res://assets/skills/potion_blue.png", "Scrub Trait (30c)", func(id=h.id):
			var err := GameState.scrub_trait(id)
			if err != "":
				push_warning(err)
			render()
		))
	cv.add_child(actions)

	# Evolution runs on Evolution Stones for the B/A/S jump (dropped by Rift
	# Map clears — see GameState.seal_rift/evolve_hero). The player picks the
	# path: "Evolve" opens every candidate with what it would change (stat,
	# element, Ability, passive), each with its own confirm button.
	var evolve_choices: Array = []
	if h.level >= 10:
		var cur_cls := GameData.find_class(h.pool_id)
		if not cur_cls.is_empty():
			evolve_choices = GameData.evolution_choices(cur_cls)
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
					"%s — Rank %s, %s" % [str(c["name"]), str(c["rank"]), str(c["type"])],
					"Main stat: %s" % Combat.describe_skill(str(c["kind"]), Combat.hero_innate_value(c, GameData.rank_index(str(c["rank"])))),
					"Passive: %s" % _passive_text(str(c["id"])),
				]
				if not ab.is_empty():
					lines.append("Ability: %s — %s" % [str(ab["name"]), str(ab["desc"])])
				lines.append(str(c["flavor"]))
				cv.add_child(_info_row("\n".join(lines), 11, [_icon_button("res://assets/skills/star.png", "Choose", func(id=h.id, pid=str(c["id"])):
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

	card.add_child(cv)
	v.add_child(card)


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
func _render_skill_tree_graph(cv: VBoxContainer, h: Hero, kind: String) -> void:
	var tree: Array = GameData.tier1_for_role(h.cls_id) + GameData.KIND_SKILL_PACKAGE.get(kind, [])
	var tier1: Array = tree.filter(func(n): return int(n["tier"]) == 1)
	var tier2: Array = tree.filter(func(n): return int(n["tier"]) == 2)
	var tier3: Array = tree.filter(func(n): return int(n["tier"]) == 3)
	var tier4: Array = tree.filter(func(n): return int(n["tier"]) == 4)

	# 5th column: the tree's keystone (row 0) and the role signature (row 1).
	var tier5: Array = [GameData.keystone_node(kind), GameData.signature_node(h.cls_id)].filter(func(n): return not n.is_empty())

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	for col_label in ["Tier 1", "Tier 2", "Path", "Mastery", "Keystone"]:
		var lbl := _label(col_label, 11, true)
		lbl.custom_minimum_size.x = 72
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(lbl)
	cv.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)

	var singly_gated_tier2: Array = tier2.filter(func(n): return (n["requires"] as Array).size() == 1)
	var other_tier2: Array = tier2.filter(func(n): return (n["requires"] as Array).size() != 1)
	var fork_rows: int = max(tier1.size(), tier3.size())
	var row_count: int = max(fork_rows, 1) + other_tier2.size()

	for row_i in row_count:
		if row_i < fork_rows:
			if row_i < tier1.size():
				var t1: Dictionary = tier1[row_i]
				grid.add_child(_skill_node_tile(h, kind, t1))
				var dep := singly_gated_tier2.filter(func(n): return (n["requires"] as Array).has(t1["id"]))
				grid.add_child(_skill_node_tile(h, kind, dep[0]) if not dep.is_empty() else Control.new())
			else:
				grid.add_child(Control.new())
				grid.add_child(Control.new())
			if row_i < tier3.size():
				var fork: Dictionary = tier3[row_i]
				grid.add_child(_skill_node_tile(h, kind, fork))
				var finisher := tier4.filter(func(n): return (n["requires"] as Array).has(fork["id"]))
				grid.add_child(_skill_node_tile(h, kind, finisher[0]) if not finisher.is_empty() else Control.new())
			else:
				grid.add_child(Control.new())
				grid.add_child(Control.new())
		else:
			grid.add_child(Control.new())
			grid.add_child(_skill_node_tile(h, kind, other_tier2[row_i - fork_rows]))
			grid.add_child(Control.new())
			grid.add_child(Control.new())
		grid.add_child(_skill_node_tile(h, kind, tier5[row_i]) if row_i < tier5.size() else Control.new())

	cv.add_child(grid)


## One hero's clickable portrait for the Roster row — a PanelContainer
## (bordered/highlighted when selected) with a flat invisible Button on top,
## same layered-hotspot approach as the camp/management screens.
func _roster_portrait_button(h: Hero) -> Control:
	var w := 72.0
	var ht := 100.0
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(w, ht)
	wrap.size = Vector2(w, ht)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(w, ht)
	panel.size = Vector2(w, ht)
	if selected_hero_id == h.id:
		var sel_style := StyleBoxFlat.new()
		sel_style.bg_color = Palette.SURFACE2
		sel_style.border_width_left = 2
		sel_style.border_width_top = 2
		sel_style.border_width_right = 2
		sel_style.border_width_bottom = 2
		sel_style.border_color = Palette.VIOLET
		sel_style.corner_radius_top_left = 8
		sel_style.corner_radius_top_right = 8
		sel_style.corner_radius_bottom_left = 8
		sel_style.corner_radius_bottom_right = 8
		sel_style.content_margin_top = 4
		panel.add_theme_stylebox_override("panel", sel_style)
	var pv := _vbox(2)
	var portrait_path := GameData.portrait_for_hero(h.cls_id, h.pool_id)
	if portrait_path != "":
		var icon_wrap := CenterContainer.new()
		icon_wrap.add_child(_icon_trimmed(portrait_path, 48))
		pv.add_child(icon_wrap)
	pv.add_child(_label(h.name.split(" the ")[0], 10))
	pv.add_child(_label("%d/%d HP" % [h.hp, Combat.max_hp(h)], 9, true))
	panel.add_child(pv)
	wrap.add_child(panel)

	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = Vector2(w, ht)
	btn.size = Vector2(w, ht)
	var clear_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style_name, clear_style)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(func(id=h.id):
		selected_hero_id = "" if selected_hero_id == id else id
		expanded_slot = ""
		render()
	)
	wrap.add_child(btn)
	return wrap


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
	var icon_path: String = GameData.ITEM_CATEGORY_ICON_PATH[equipped.category] if equipped else ""
	var cb := func():
		expanded_slot = "" if is_open else slot_key
		render()
	var can_accept := func(data):
		if typeof(data) != TYPE_DICTIONARY or data.get("kind", "") != "inventory_item":
			return false
		if data.get("slot_type", "") != slot_type:
			return false
		var candidate := GameState.find_item(str(data.get("item_id", "")))
		return candidate != null and GameState.item_fits_hero(candidate, h)
	var on_drop := func(data):
		GameState.equip_item(h.id, slot_type, idx, str(data.get("item_id", "")))
		render()
	var drop_target := {"can_accept": can_accept, "on_drop": on_drop}
	return _action_slot(icon_path, "", is_open, false, cb, size, label_text, "", "", drop_target)


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
		pv.add_child(_info_row("%s (%s) — %s" % [_loot_display_name(equipped), GameData.ITEM_CATEGORY_LABEL[equipped.category], _loot_desc(equipped, false)], 12, [], _icon(GameData.ITEM_CATEGORY_ICON_PATH[equipped.category], 18)))
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
		var equip_btn := _icon_button(GameData.ITEM_CATEGORY_ICON_PATH[it.category], "Equip", func(hid=h.id, st=slot_type, i=idx, iid=it.id):
			GameState.equip_item(hid, st, i, iid)
			expanded_slot = ""
			render()
		)
		pv.add_child(_info_row("%s (%s) — %s" % [_loot_display_name(it), GameData.ITEM_CATEGORY_LABEL[it.category], _loot_desc(it, false)], 12, [equip_btn], _icon(GameData.ITEM_CATEGORY_ICON_PATH[it.category], 18)))
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
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "< Back to Inventory", func(): inv_category = ""; render()))
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
	v.add_child(_label("Items", 16))
	var unequipped_items: Array[Item] = []
	unequipped_items.assign(GameState.items.filter(func(it): return it.equipped_to == ""))
	v.add_child(_sort_cycle_button(inv_sort, [
		{"id": "rarity", "label": "Rarity"},
		{"id": "value", "label": "Value"},
		{"id": "name", "label": "Name"},
	], func(new_id): inv_sort = new_id))
	match inv_sort:
		"rarity":
			unequipped_items.sort_custom(func(a, b): return _rarity_rank(a.rarity) > _rarity_rank(b.rarity))
		"value":
			unequipped_items.sort_custom(func(a, b): return a.value > b.value)
		"name":
			unequipped_items.sort_custom(func(a, b): return a.name < b.name)
	if unequipped_items.is_empty():
		v.add_child(_label("No unequipped items.", 12))
	for it in unequipped_items:
		var actions: Array[Control] = []
		for h2 in GameState.heroes:
			var slot := it.slot_type()
			if not GameState.item_fits_hero(it, h2):
				continue
			var target_idx := _best_swap_slot(h2, slot)
			if target_idx < 0:
				continue
			var is_free := _first_free_slot(h2, slot) >= 0
			var verb := "Equip → %s" if is_free else "Swap → %s"
			actions.append(_icon_button(GameData.ITEM_CATEGORY_ICON_PATH[it.category], verb % h2.name.split(" the ")[0], func(hid=h2.id, iid=it.id, s=slot, idx=target_idx):
				GameState.equip_item(hid, s, idx, iid)
				render()
			))
		actions.append(_icon_button(GameData.CURRENCY_ICON_PATH["coins"], "Sell", func(id=it.id):
			GameState.sell_item(id)
			render()
		))
		v.add_child(_info_row("%s (%s) — %s" % [_loot_display_name(it), GameData.ITEM_CATEGORY_LABEL[it.category], _loot_desc(it, false)], 12, actions, _icon(GameData.ITEM_CATEGORY_ICON_PATH[it.category], 20)))

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
	v.add_child(_label("Relics — %d/%d slots equipped" % [Combat.equipped_relics().size(), GameState.relic_slot_cap()], 16))
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
		actions.append(_icon_button(GameData.RELIC_TYPE_ICON_PATH[r.type], "Unequip" if r.equipped else "Equip", func(id=r.id):
			GameState.toggle_equip_relic(id)
			render()
		))
		if r.level < GameState.RELIC_MAX_LEVEL:
			var rar := GameData.find_rarity(r.rarity)
			var cost := int(round(15.0 * float(rar["mult"]) * r.level))
			actions.append(_icon_button(GameData.CURRENCY_ICON_PATH["crystals"], "Upgrade (%dcr)" % cost, func(id=r.id):
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
