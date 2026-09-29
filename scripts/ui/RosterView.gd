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
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes recruited yet."))
		return

	var still_here: Array[Hero] = []
	still_here.assign(GameState.heroes.filter(func(h): return h.id == selected_hero_id))
	if still_here.is_empty():
		selected_hero_id = ""

	# Two panes: the hero list on the left, the selected hero's card on the
	# right — stacked on the narrow canvas, with the list wrapping into rows.
	var split: BoxContainer = VBoxContainer.new() if _narrow() else HBoxContainer.new()
	split.add_theme_constant_override("separation", 14)
	var left: Container
	if _narrow():
		left = HFlowContainer.new()
		left.add_theme_constant_override("h_separation", 6)
		left.add_theme_constant_override("v_separation", 6)
	else:
		left = _vbox(6)
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
	var sorted := _sorted_heroes()
	if selected_hero_id == "":
		selected_hero_id = sorted[0].id
		still_here.assign([sorted[0]])
	for hh in sorted:
		left.add_child(_roster_row(hh))
	right.add_child(_hero_card(still_here[0]))


## A hero's page: header, tabs (Hero · Skills · History) and the open tab.
## The Roster shows it beside the list; a rift shows it for the party
## (see _render_rift_hero_page), where camp-only actions stay hidden.
func _hero_card(h: Hero) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelViolet"
	var cv := _vbox(4)
	cv.add_child(_title_strip(h.name))
	var voice := GameData.hero_voice(h)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	chips.add_child(_rule_chip(tr("Lv%d %s") % [h.level, tr(str(h.cls_id.capitalize()))], "", Palette.LINE))
	chips.add_child(_rule_chip(tr("Rank %s") % tr(str(h.rank)), "", Palette.RANK_S))
	chips.add_child(_rule_chip(tr("Power %d") % Combat.power_of(h), "", Palette.VIOLET))
	var hpw := _vbox(2)
	hpw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hpw.add_child(_label(tr("%d/%d HP") % [h.hp, Combat.max_hp(h)], 11, true))
	hpw.add_child(_hp_bar(h.hp, Combat.max_hp(h), 150.0))
	chips.add_child(hpw)
	cv.add_child(chips)

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
		var tb := _button(tr(str(td[1])) + ("  •" if td[2] else ""), func(t=str(td[0])):
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
			cv.add_child(_rich_line(tr("Passive — ") + _passive_bb(h.pool_id), 12))
			cv.add_child(_wrap_label(_position_text(h), 12, true))
			var build := _build_bb(h)
			if build != "":
				cv.add_child(_rich_line(tr("Build: ") + build, 12, true))
			cv.add_child(_hsep())
			var arch := Combat.hero_main_arch(h)
			for sk in GameData.ROLE_SKILLS.get(h.cls_id, []):
				var sk_row := HBoxContainer.new()
				sk_row.add_theme_constant_override("separation", 8)
				var sic := _icon(str(sk["icon"]), 28)
				if h.level < int(sk["level"]):
					sic.modulate = Color(1, 1, 1, 0.4)
				sk_row.add_child(sic)
				var sk_mid := _vbox(0)
				sk_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sk_mid.add_child(_label(tr("Skill: %s · %d Momentum%s") % [tr(str(sk["name"])), int(sk["cost"]), tr(str("" if str(sk["row"]) == "any" else tr(" · %s row") % tr(str(sk["row"]))))], 12))
				sk_mid.add_child(_wrap_label(tr(str(sk["desc"])) + (tr(" %s twist: %s.") % [tr(str(GameData.ARCHETYPES[arch])), tr(str(GameData.ARCH_TWIST[arch]))] if arch != "" else ""), 11, true))
				sk_row.add_child(sk_mid)
				if h.level < int(sk["level"]):
					sk_row.add_child(_label(tr("Unlocks at Lv%d") % int(sk["level"]), 11, true))
				cv.add_child(sk_row)
			if GameData.SUBCLASS_ABILITIES.has(h.pool_id):
				var ab: Dictionary = GameData.SUBCLASS_ABILITIES[h.pool_id]
				var ab_row := HBoxContainer.new()
				ab_row.add_theme_constant_override("separation", 8)
				ab_row.add_child(_icon(GameData.ability_icon(h.pool_id), 28))
				var ab_mid := _vbox(0)
				ab_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				ab_mid.add_child(_label(tr("Ability: %s") % tr(str(ab["name"])), 12))
				ab_mid.add_child(_wrap_label(str(ab["desc"]), 11, true))
				ab_row.add_child(ab_mid)
				if h.level < 3:
					ab_row.add_child(_label("Unlocks at Lv3", 11, true))
				elif h.ability_awakened:
					ab_row.add_child(_label(tr("Awakened (%s)") % tr(str(GameData.awakening_bonus_text(h.pool_id))), 11, true))
				else:
					ab_row.add_child(_icon_button("res://assets/skills/gem_red.png", tr("Awaken (%d SP, %s)") % [GameData.ABILITY_AWAKENING_COST, tr(str(GameData.awakening_bonus_text(h.pool_id)))], func(id=h.id):
						var err := GameState.awaken_ability(id)
						if err != "":
							push_warning(err)
						render()
					))
				cv.add_child(ab_row)
				if not evolve_choices.is_empty() or h.prior_pool_id != "":
					cv.add_child(_label("Evolving replaces this Ability, but skill trees carry over.", 10, true))
			# Evolving costs Crystals; the B/A/S jump also needs a rift of that rank
			# sealed once. The player picks the path: "Evolve" opens every candidate
			# with what it would change, each with its own confirm button.
			if not evolve_choices.is_empty() and screen != "rift_run":   # evolving waits for camp
				var next_rank_id: String = evolve_choices[0]["rank"]
				var next_rank := GameData.find_rank(next_rank_id)
				var gate := GameState.evolve_rank_gate(next_rank_id)
				var evolve_label := tr("Evolve (%d Essence)") % int(next_rank["cost"]) if gate == "" else tr("Evolve — %s") % tr(str(gate))
				var picking := evolve_picker_hero_id == h.id
				cv.add_child(_icon_button("res://assets/skills/star.png", "Hide evolution paths" if picking else evolve_label, func(id=h.id):
					evolve_picker_hero_id = "" if evolve_picker_hero_id == id else id
					render()
				))
				if picking:
					for c in evolve_choices:
						var ab: Dictionary = GameData.SUBCLASS_ABILITIES.get(str(c["id"]), {})
						var lines: Array[String] = [
							tr("[b]%s[/b] — Rank %s, %s") % [tr(str(c["name"])), tr(str(c["rank"])), tr(str(c["type"]))],
							tr("Main stat: %s") % tr(str(Combat.describe_skill(str(c["kind"]), Combat.hero_innate_value(c, GameData.rank_index(str(c["rank"])))))),
							tr("Passive: %s") % tr(str(_passive_bb(str(c["id"])))),
						]
						if not ab.is_empty():
							lines.append(tr("Ability: %s — %s") % [tr(str(ab["name"])), tr(str(ab["desc"]))])
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
				pills.add_child(_icon_button("res://assets/skills/eye_gem.png", tr("Hide %s") % tr(str(summary["label"])) if is_open else str(summary["label"]), func(k=kind):
					expanded_skill_tree_kind = "" if expanded_skill_tree_kind == k else k
					render()
				))
			cv.add_child(pills)

			if not expanded_skill_tree_kind.is_empty() and tree_summaries.any(func(s): return s["kind"] == expanded_skill_tree_kind):
				cv.add_child(_hsep())
				cv.add_child(_label(tr("Skill Points: %d") % h.skill_points, 12))
				_render_skill_tree_graph(cv, h, expanded_skill_tree_kind)
				# Per-tree, not "respec everything" — a hero holds at most 2 trees
				# (current + one prior evolution stage), so undoing just the one
				# fork choice you regret no longer means nuking the other tree too.
				var tree_prefix := "%s:" % tr(str(expanded_skill_tree_kind))
				var tree_spent := h.skills.keys().any(func(k): return h.skills[k] and str(k).begins_with(tree_prefix))
				if tree_spent and screen != "rift_run":
					cv.add_child(_icon_button(GameData.BUTTON_ICON_PATH["dice"], tr("Respec this tree (%d Gold)") % GameState.tree_respec_cost(h, expanded_skill_tree_kind), func(id=h.id, k=expanded_skill_tree_kind):
						var err := GameState.respec_hero(id, k)
						if err != "":
							push_warning(err)
						render()
					))
		"history":
			var who := _label(tr("%s · Morale %d %s") % [tr(str(GameData.VOICE_NAME[voice])), h.morale, tr(str(GameData.morale_tier(h.morale)[1]))], 13)
			who.tooltip_text = tr("Personality (from their born quirk) — e.g. “%s”") % tr(str(GameData.BARKS[voice]["victory"][0]))
			who.mouse_filter = Control.MOUSE_FILTER_STOP
			cv.add_child(who)
			cv.add_child(_hsep())
			var hist_lines := _history_lines(h)
			for line in hist_lines:
				cv.add_child(_rich_line(line, 12, true))
			if hist_lines.is_empty():
				cv.add_child(_label("No deeds yet — send this hero into a rift.", 11, true))
		_:
			_render_hero_sheet(cv, h, fitting_items)

	card.add_child(cv)
	return card


## The hero sheet: a paper doll (weapons left, the hero in the middle, gear
## right), attributes and every stat beside it, and the gear this hero can
## use underneath — equip by clicking a slot or dragging a tile onto it.
func _render_hero_sheet(cv: VBoxContainer, h: Hero, fitting_items: Array[Item]) -> void:
	var sheet: BoxContainer = VBoxContainer.new() if _narrow() else HBoxContainer.new()
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
		cc.add_child(_hero_icon(h, 190))
	stage.add_child(cc)
	mid.add_child(stage)
	var pw := _label(tr("Power %d") % Combat.power_of(h), 15)
	pw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(pw)
	var changes := GameState.equip_best_changes(h)
	if changes > 0:
		var eb := _button(tr("Equip best (%d)") % changes, func(id=h.id):
			var before := Combat.power_of(h)
			GameState.equip_best(id)
			GameState.pending_toasts.append({"cls_id": h.cls_id, "pool_id": h.pool_id, "title": tr("Equipped best gear"), "text": tr("Power %d → %d") % [before, Combat.power_of(h)]})
			render())
		eb.tooltip_text = "Fill this hero's slots with the strongest free gear that fits them. Gear worn by other heroes is left alone."
		mid.add_child(eb)
	doll.add_child(mid)
	var gcol := _vbox(6)
	gcol.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in GameData.gear_slots(h.rank):
		gcol.add_child(_equip_slot_frame(h, "gear", i, 58.0))
	# The next gear slot, locked, with the rank that opens it.
	for r in range(GameData.rank_index(h.rank) + 1, GameData.RANKS.size()):
		var rid := str(GameData.RANKS[r]["id"])
		if GameData.gear_slots(rid) > GameData.gear_slots(h.rank):
			var locked := _vbox(2)
			locked.tooltip_text = tr("Another gear slot opens at rank %s") % tr(str(rid))
			locked.mouse_filter = Control.MOUSE_FILTER_STOP
			var fr := _icon(GameData.RARITY_FRAME_PATH["common"], 58)
			fr.stretch_mode = TextureRect.STRETCH_SCALE
			fr.modulate = Color(1, 1, 1, 0.3)
			fr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			locked.add_child(fr)
			var ll := _label(tr("Rank %s") % tr(str(rid)), 12, true)
			ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
			locked.add_child(ll)
			gcol.add_child(locked)
			break
	doll.add_child(gcol)
	sheet.add_child(doll)

	var side := _vbox(10)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_child(_attr_panel(h))
	side.add_child(_stat_panel(h))
	sheet.add_child(side)
	cv.add_child(sheet)

	if expanded_slot.begins_with("%s:weapon:" % h.id) or expanded_slot.begins_with("%s:gear:" % h.id):
		var parts := expanded_slot.split(":")
		_equip_picker_modal(h, parts[1], int(parts[2]))

	cv.add_child(_hsep())
	if fitting_items.is_empty():
		cv.add_child(_label("No unequipped gear this hero can use.", 12, true))
	else:
		var usable := fitting_items.filter(func(it): return GameState.attr_req_met(it, h)).size()
		cv.add_child(_label(tr("Unequipped gear that fits · %d usable%s — drag onto a slot, or click a slot") % [usable, tr(" · %d need more attributes") % (fitting_items.size() - usable) if fitting_items.size() > usable else ""], 12, true))
		var sorted := fitting_items.duplicate()
		sorted.sort_custom(func(x, y): return _rarity_rank(x.rarity) > _rarity_rank(y.rarity))
		var inv_flow := HFlowContainer.new()
		inv_flow.add_theme_constant_override("h_separation", 6)
		inv_flow.add_theme_constant_override("v_separation", 6)
		for it in sorted:
			inv_flow.add_child(_item_tile(it, 48, h))
		cv.add_child(inv_flow)

	cv.add_child(_quirk_row(h))


## The hero's quirks as chips (good ones in the healthy colour, wounds in
## the danger colour), with Treat on the treatable ones.
func _quirk_row(h: Hero) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	var head := _label("Quirks:", 12, true)
	row.add_child(head)
	if h.quirks.is_empty():
		row.add_child(_label("none yet", 12, true))
	for q in h.quirks:
		var t := GameData.quirk(q)
		var bad: bool = t.get("treatable", false)
		var chip := _label(q, 12)
		chip.add_theme_color_override("font_color", Palette.HAZARD if bad else Palette.good())
		chip.tooltip_text = "%s (%s) — %s" % [tr(str(q)), tr(str({"born": "born with it", "scar": "a scar", "earned": "earned"}.get(str(t.get("origin", "")), ""))), tr(str(GameState.quirk_text(q)))]
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(chip)
		if bad and GameState.lvl("res.lab") >= 1:
			row.add_child(_icon_button("res://assets/skills/potion_blue.png", tr("Treat (%d Gold)") % GameState.quirk_treat_cost(), func(id=h.id, qq=q):
				var err := GameState.treat_quirk(id, qq)
				if err != "":
					push_warning(err)
				render()
			))
	return row


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
		var pts := _label(tr("%d point%s to spend") % [h.attr_points, tr(str(_pl(h.attr_points)))], 13)
		pts.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		pts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(pts)
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(sp)
		var auto := _button("Auto", func(id=h.id): GameState.auto_assign_attrs(id); render())
		auto.tooltip_text = tr("Spend them the %s way") % tr(str(GameData.hero_role(h).capitalize()))
		head.add_child(auto)
	v.add_child(head)
	for a in GameData.ATTRIBUTES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.tooltip_text = "%s — %s" % [tr(str(GameData.ATTR_LABEL[a])), tr(str(GameData.ATTR_DESC[a]))]
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
			row.add_child(_label(tr("(%+d gear)") % gear, 12, true))
		var sp2 := Control.new()
		sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(sp2)
		var per: Dictionary = GameData.ATTR_EFFECTS[a]
		var bits: Array[String] = []
		var long_bits: Array[String] = []
		for k in per:
			var val: float = (total - GameData.ATTR_BASELINE) * float(per[k]) * 100.0
			if is_zero_approx(val):
				continue
			long_bits.append(Combat.describe_skill(str(k), val / 100.0))
			if val >= 1.0:   # the sheet lists real gains; the rest is in the tooltip
				bits.append("%+.0f%% %s" % [val, tr(str(_ATTR_SHORT.get(k, k)))])
		row.tooltip_text += tr("\n%d is the baseline: above it adds, below it takes a little away.\n") % GameData.ATTR_BASELINE + "\n".join(long_bits)
		row.add_child(_attr_bar(total))
		var note := ", ".join(bits) if not bits.is_empty() else (tr("at the baseline") if total == GameData.ATTR_BASELINE else (tr("below the baseline") if total < GameData.ATTR_BASELINE else tr("small gains")))
		var nlab := _label(note, 12, true)
		nlab.custom_minimum_size.x = 150
		row.add_child(nlab)
		if h.attr_points > 0:
			var plus := _button("+", func(id=h.id, at=a): GameState.spend_attr_point(id, at); render())
			plus.custom_minimum_size = Vector2(36, 30)
			plus.tooltip_text = "+1 %s" % tr(str(GameData.ATTR_LABEL[a]))
			row.add_child(plus)
		v.add_child(row)
	# Camp training (Gold) and a full reset (Essence).
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	if not h.is_champion and screen != "rift_run":   # training and resets wait for camp
		var tcost := GameState.attr_train_cost(h)
		var maxed := h.attr_trained >= GameData.ATTR_TRAIN_CAP
		var train := _icon_button(GameData.CURRENCY_ICON_PATH["coins"], tr("Trained %d/%d") % [h.attr_trained, GameData.ATTR_TRAIN_CAP] if maxed else tr("Train +1 — %d") % tcost, func(id=h.id):
			var err := GameState.train_attr(id)
			if err != "":
				push_warning(err)
			render()
		)
		train.disabled = maxed or GameState.coins < tcost or GameState.training_left() <= 0
		train.tooltip_text = tr("Buy an attribute point with Gold (%d/%d trained; each costs %d more). Training Yard: %d of %d left this week.") % [h.attr_trained, GameData.ATTR_TRAIN_CAP, GameData.ATTR_TRAIN_COST, GameState.training_left(), GameState.training_slots()]
		if not maxed and GameState.training_left() <= 0:
			train.text = "Yard full this week"
		foot.add_child(train)
	var fsp := Control.new()
	fsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fsp)
	var refund := GameState.attr_points_spent(h)
	if refund > 0 and not h.is_champion and screen != "rift_run":
		var cost := GameState.attr_respec_cost(h)
		var reset: Button
		if _confirm_respec_id == h.id:
			reset = _icon_button(GameData.CURRENCY_ICON_PATH["crystals"], tr("Confirm — %d") % cost, func(id=h.id):
				_confirm_respec_id = ""
				var err := GameState.respec_attrs(id)
				if err != "":
					push_warning(err)
				render()
			)
			foot.add_child(_button("Keep", func(): _confirm_respec_id = ""; render()))
		else:
			reset = _icon_button(GameData.CURRENCY_ICON_PATH["crystals"], tr("Reset %d") % cost, func(id=h.id):
				_confirm_respec_id = id
				render()
			)
			reset.disabled = GameState.crystals < cost
		reset.tooltip_text = tr("Refund all %d spent points for %d Essence (you have %d)") % [refund, cost, GameState.crystals]
		foot.add_child(reset)
	if foot.get_child_count() > 1:
		v.add_child(foot)
	panel.add_child(v)
	return panel


## An attribute as a bar: a tick at the baseline, filled warm above it and
## grey below it, so a low score reads as "not much yet", not as a penalty.
func _attr_bar(total: int) -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(90, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := maxf(25.0, total)
	bar.draw.connect(func():
		var w := bar.size.x
		bar.draw_rect(Rect2(0, 0, w, 10), Color(Palette.INK, 0.8))
		var base_x := w * GameData.ATTR_BASELINE / top
		var x := w * clampf(total / top, 0.0, 1.0)
		if total >= GameData.ATTR_BASELINE:
			bar.draw_rect(Rect2(0, 1, base_x, 8), Palette.GUNMETAL)
			bar.draw_rect(Rect2(base_x, 1, x - base_x, 8), Palette.EMBER_BRIGHT)
		else:
			bar.draw_rect(Rect2(0, 1, x, 8), Palette.GUNMETAL)
		bar.draw_rect(Rect2(base_x - 1, 0, 2, 10), Palette.TEXT))
	return bar


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
		if absf(total) < 0.01:   # under 1% changes nothing you'd notice; it's still in the breakdown
			continue
		add.call(str(_KIND_LABEL.get(kind, kind)), "%+.0f%%" % (total * 100.0), _stat_breakdown_card(h, kind, total))
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
	var cost := GameState.skill_node_cost(h, kind, n)
	var missing_sp: bool = h.skill_points < cost
	var missing_rift: bool = n.has("rift_rank") and GameState.best_rift_rank_sealed < GameData.rift_rank_index(str(n["rift_rank"]))
	var missing_stone: bool = n.get("stone", false) and GameState.crystals < GameData.STONEBOUND_CRYSTALS
	var can_learn := not learned and not missing_level and not missing_prereq and not missing_sp and not locked_out and not missing_rift and not missing_stone

	var reason := "Learned"
	if not learned:
		if locked_out:
			reason = "Locked out by your other path"
		elif missing_level:
			reason = tr("Requires Lv%d") % int(n["req_level"])
		elif missing_prereq:
			reason = "Needs prerequisite"
		elif missing_rift:
			reason = tr("Seal a Rank %s+ rift first") % tr(str(n["rift_rank"]))
		elif missing_stone:
			reason = tr("Needs %d Essence") % GameData.STONEBOUND_CRYSTALS
		elif missing_sp:
			reason = tr("Needs %d SP") % cost
		else:
			reason = tr("Learn (%d SP%s)") % [cost, tr(" + %d Essence") % GameData.STONEBOUND_CRYSTALS if n.get("stone", false) else ""]
		if cost < int(n["cost"]):
			reason += "\nCheaper: your quirks suit this path"

	var combo_line := ""
	if n.has("combo_kind"):
		var combo_active := learned and GameState.party_has_other_kind_capstone(h.id, str(n["combo_kind"]))
		combo_line = tr("\n%s+%s if a party ally has reached %s's capstone") % [
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
	var tier5: Array = ([GameData.keystone_node(kind), GameData.signature_node(h.cls_id)] + GameData.rift_nodes(kind)).filter(func(n): return not n.is_empty())

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 10)
	# Column headers are the grid's own first row (they used to be a separate
	# HBox that spread across the full width and drifted off the columns).
	for col_label in ["Tier 1", "Tier 2", "Path", "Mastery", "Keystone & Rift"]:
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
	var row_count: int = max(max(fork_rows, 1) + other_tier2.size(), tier5.size())

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
			grid.add_child(cell.call(other_tier2[row_i - fork_rows] if row_i - fork_rows < other_tier2.size() else {}))
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
		if not tiles.has(nid) or nid in ["signature", "stonebound"]:
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
		var pi := _hero_icon(h, 48)
		pi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if not h.is_available():
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
		var chip := _label("◆ " + tr(str(GameData.ARCHETYPES[arch])), 12)
		chip.add_theme_color_override("font_color", ARCH_COLOR.get(arch, Palette.MUTED))
		top.add_child(chip)
	col.add_child(top)
	col.add_child(_label(tr("Lv%d %s (%s) · %d/%d HP%s") % [h.level, tr(str(h.cls_id.capitalize())), tr(str(h.rank)), h.hp, Combat.max_hp(h), tr(str((tr(" · away %d run%s") % [h.busy_runs, tr(str(_pl(h.busy_runs)))]) if h.busy_runs > 0 else ""))], 12, true))
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
	var slot_key := "%s:%s:%d" % [tr(str(h.id)), tr(str(slot_type)), idx]
	var is_open := expanded_slot == slot_key
	var label_text := equipped.name.split(" ")[0] if equipped else (tr("Weapon") if slot_type == "weapon" else tr("Gear"))
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


## The picker for the open equip slot: a pop-up with what's worn there
## (and Unequip), then a card for every free item that fits this hero and
## slot, each with how it compares to the worn one. Esc or a click outside
## closes it.
func _equip_picker_modal(h: Hero, slot_type: String, idx: int) -> void:
	var close := func():
		expanded_slot = ""
		render()
	_combat_hotkeys["Escape"] = close
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP]:
		dim.set_offset(side, -80)   # past root's page margins
	for side in [SIDE_RIGHT, SIDE_BOTTOM]:
		dim.set_offset(side, 80)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close.call())
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var vs := get_viewport_rect().size
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelViolet"
	card.custom_minimum_size.x = minf(836.0, vs.x - 48.0)
	var cv := _vbox(12)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var title := _label(tr("%s — choose a weapon") % h.name.split(" the ")[0] if slot_type == "weapon" else tr("%s — choose gear") % h.name.split(" the ")[0], 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Close", close))
	cv.add_child(head)
	var equipped := _find_equipped_at(h.id, slot_type, idx)
	if equipped:
		var wear := HBoxContainer.new()
		wear.add_theme_constant_override("separation", 10)
		wear.add_child(_item_tile(equipped, 40, h))
		var wl := _vbox(0)
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wl.add_child(_label(tr("Wearing"), 11, true))
		var wn := _label(tr(str(_loot_display_name(equipped))), 14)
		wn.add_theme_color_override("font_color", ITEM_RARITY_COLOR.get(equipped.rarity, Palette.TEXT))
		wl.add_child(wn)
		wear.add_child(wl)
		wear.add_child(_icon_button("res://assets/skills/armor_chest.png", "Unequip", func(hid=h.id, st=slot_type, i=idx):
			GameState.equip_item(hid, st, i, "")
			render()))
		cv.add_child(wear)
		cv.add_child(_hsep())
	var candidates: Array = GameState.items.filter(func(it): return it.equipped_to == "" and it.slot_type() == slot_type and GameState.item_fits_hero(it, h))
	candidates.sort_custom(func(x, y):
		var ux := GameState.attr_req_met(x, h)
		var uy := GameState.attr_req_met(y, h)
		return ux and not uy if ux != uy else _rarity_rank(x.rarity) > _rarity_rank(y.rarity))
	if candidates.is_empty():
		cv.add_child(_label(tr("No unequipped %s this hero can use.") % tr(str(("weapons" if slot_type == "weapon" else "gear"))), 13, true))
	else:
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		for it in candidates:
			grid.add_child(_equip_choice_card(h, it, slot_type, idx))
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var per_row := maxi(1, int((card.custom_minimum_size.x - 24.0) / 260.0))
		sc.custom_minimum_size.y = minf(300.0 * ceili(float(candidates.size()) / per_row), minf(470.0, vs.y - 280.0))
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(grid)
		cv.add_child(sc)
	card.add_child(cv)
	center.add_child(card)
	root.add_child(overlay)


## How equipping `it` into slot idx changes `h`: [text, better?] per stat
## (every build stat is better higher, whatever its wording says), then the
## situational effects gained (better) and lost (worse).
func _compare_lines(it: Item, h: Hero, idx: int) -> Array:
	var current: Item = _find_equipped_at(h.id, it.slot_type(), idx) if idx >= 0 else null
	var a := _item_stat_map(it)
	var b := _item_stat_map(current)
	var out: Array = []
	for kind in GameData.BUILD_KINDS:
		var d: float = float(a.get(kind, 0.0)) - float(b.get(kind, 0.0))
		if absf(d) >= 0.001:
			out.append([Combat.describe_skill(kind, d), d > 0.0])
	for e in (GameData.find_unique_item(it.unique_id).get("effects", []) if it.unique_id != "" else it.effects):
		out.append([tr("gains: ") + Combat.describe_effect(e), true])
	if current:
		for e in (GameData.find_unique_item(current.unique_id).get("effects", []) if current.unique_id != "" else current.effects):
			out.append([tr("loses: ") + Combat.describe_effect(e), false])
	return out


## One free item in the picker: icon, name, slot and attribute need, how it
## compares with what's worn (gains green, losses red), and Equip. The full
## description is on hover.
func _equip_choice_card(h: Hero, it: Item, slot_type: String, idx: int) -> PanelContainer:
	var usable := GameState.attr_req_met(it, h)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size.x = 250
	var v := _vbox(6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(_item_tile(it, 44, h))
	var names := _vbox(1)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := _wrap_label(tr(str(_loot_display_name(it))), 13)
	nm.add_theme_color_override("font_color", ITEM_RARITY_COLOR.get(it.rarity, Palette.TEXT))
	names.add_child(nm)
	var sub := tr(str(GameData.ITEM_CATEGORY_LABEL[it.category]))
	if it.attr_req > 0:
		sub += " · " + tr("needs %d %s") % [it.attr_req, tr(str(GameData.ATTR_LABEL[it.attr]))]
	var sl := _label(sub, 11, true)
	if not usable:
		sl.add_theme_color_override("font_color", Palette.HAZARD)
	names.add_child(sl)
	top.add_child(names)
	v.add_child(top)
	var cmp := _compare_lines(it, h, idx)
	for k in mini(cmp.size(), 5):
		var l := _wrap_label(str(cmp[k][0]), 11)
		l.add_theme_color_override("font_color", Palette.RANK_E if cmp[k][1] else Palette.HAZARD)
		v.add_child(l)
	if cmp.size() > 5:
		v.add_child(_label(tr("+%d more (hover)") % (cmp.size() - 5), 11, true))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	var eb := _icon_button(GameData.item_icon(it), "Equip", func(hid=h.id, st=slot_type, i=idx, iid=it.id):
		GameState.equip_item(hid, st, i, iid)
		expanded_slot = ""
		render())
	eb.disabled = not usable
	if not usable:
		eb.tooltip_text = tr("Needs %d %s") % [it.attr_req, tr(str(GameData.ATTR_LABEL[it.attr]))]
	v.add_child(eb)
	card.add_child(v)
	_rich_tip(card, _item_card(it, h, idx))
	return card


func _render_inventory(v: VBoxContainer) -> void:
	if inv_category == "":
		_render_inventory_hub(v)
		return
	match inv_category:
		"relics": _render_inventory_relics(v)
		"supplies":
			inv_view = "supplies"
			_render_inventory_items(v)
		_: _render_inventory_items(v)


## The 3 Inventory categories as clickable stations on a storage-vault scene
## (a chest for Items, a glowing altar for Relics, a table with a spyglass
## for Supplies) — same background-prop-as-button + hover-glow pattern as
## the camp/management screens.
func _render_inventory_hub(v: VBoxContainer) -> void:
	var scene_size := HUB_SCENE
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
		["supplies", "Supplies", Rect2(470, 0, 230, 340), Rect2(210, 65, 110, 95)],
	]
	var camp_scale := HUB_ART_SCALE
	for entry in cat_entries:
		var cid: String = entry[0]
		var label_text: String = entry[1]
		var hit_rect: Rect2 = _hub_rect(entry[2])
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
	var loose: Array = GameState.items.filter(func(it): return it.equipped_to == "")
	# Gear | Supplies — the gear grid and the tonic shop each get
	# the full width instead of sharing one long page.
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	for td in [["gear", tr("Gear  %d") % loose.size()], ["supplies", tr("Supplies  %d") % GameState.tonic_count()]]:
		var tb := _button(str(td[1]), func(t=str(td[0])):
			inv_view = t
			selected_item_id = ""
			render()
		)
		tb.toggle_mode = true
		tb.button_pressed = inv_view == td[0]
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_row.add_child(tb)
	v.add_child(tab_row)
	if inv_view == "supplies":
		_render_inventory_supplies(v)
		return

	var unequipped_items: Array[Item] = []
	unequipped_items.assign(loose.filter(func(it): return inv_filter == "all" or it.category == inv_filter))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	for f in [["all", "All"], ["weapon", "Weapons"], ["armor", "Armor"], ["focus", "Focus"]]:
		var n: int = loose.filter(func(it): return f[0] == "all" or it.category == f[0]).size()
		var chip := _button("%s %d" % [tr(str(f[1])), n], func(id=str(f[0])):
			inv_filter = id
			render()
		)
		chip.toggle_mode = true
		chip.button_pressed = inv_filter == f[0]
		head.add_child(chip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
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
		v.add_child(_label("No unequipped items here — loot drops in rifts.", 13, true))
		return
	v.add_child(_label("Click an item to see it and equip it.  + fills someone's empty slot.", 12, true))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for it in unequipped_items:
		grid.add_child(_inv_tile(it))
	v.add_child(grid)
	var sel: Array = unequipped_items.filter(func(it): return it.id == selected_item_id)
	if sel.is_empty():
		selected_item_id = ""
	else:
		_item_modal(sel[0])


## One inventory tile: rarity-framed icon, name, and the attribute it adds.
func _inv_tile(it: Item) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(112, 146)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func(id=it.id):
		selected_item_id = id
		render()
	)
	var col := _vbox(3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	var box := Control.new()
	box.custom_minimum_size = Vector2(60, 60)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := _icon(GameData.RARITY_FRAME_PATH.get(it.rarity, GameData.RARITY_FRAME_PATH["common"]), 60)
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(frame)
	var ic := _icon(GameData.item_icon(it), 44)
	ic.position = Vector2(8, 8)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	_rarity_letter(box, it.rarity, 60)
	var note := _loot_fit_note(it, false, GameState.heroes)
	if str(note[0]).begins_with("Fills"):
		var dot := _count_badge("+", str(note[0]))
		dot.position = Vector2(46, -6)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		(dot.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = Palette.RANK_E
		box.add_child(dot)
	col.add_child(box)
	var nl := _label(_loot_display_name(it), 12)
	nl.add_theme_color_override("font_color", ITEM_RARITY_COLOR.get(it.rarity, Palette.TEXT))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.max_lines_visible = 3
	nl.custom_minimum_size.x = 100
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nl)
	if it.attr != "" and it.attr_bonus > 0:
		var al := _label("+%d %s" % [it.attr_bonus, tr(str(GameData.ATTR_LABEL[it.attr]))], 12, true)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		al.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(al)
	b.add_child(col)
	b.tooltip_text = tr("%s — click for details") % tr(str(_loot_display_name(it)))
	return b


## The selected item as a pop-up over the screen: its full card, who can
## equip it, and Sell. Esc, Close or a click outside dismisses it.
func _item_modal(it: Item) -> void:
	var close := func():
		selected_item_id = ""
		render()
	_combat_hotkeys["Escape"] = close
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP]:
		dim.set_offset(side, -80)   # past root's page margins
	for side in [SIDE_RIGHT, SIDE_BOTTOM]:
		dim.set_offset(side, 80)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close.call()
	)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelViolet"
	card.custom_minimum_size.x = 440
	var cv := _vbox(10)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var box := Control.new()
	box.custom_minimum_size = Vector2(72, 72)
	var frame := _icon(GameData.RARITY_FRAME_PATH.get(it.rarity, GameData.RARITY_FRAME_PATH["common"]), 72)
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	box.add_child(frame)
	var ic := _icon(GameData.item_icon(it), 54)
	ic.position = Vector2(9, 9)
	box.add_child(ic)
	top.add_child(box)
	var desc := _rich_line(_item_card(it), 13)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.custom_minimum_size.x = 340
	top.add_child(desc)
	cv.add_child(top)
	var slot := it.slot_type()
	var equip_row := HFlowContainer.new()
	equip_row.add_theme_constant_override("h_separation", 6)
	equip_row.add_theme_constant_override("v_separation", 6)
	var blocked: Array[String] = []
	for h2 in GameState.heroes:
		if not GameState.item_fits_hero(it, h2):
			continue
		var target_idx := _best_swap_slot(h2, slot)
		if target_idx < 0:
			continue
		if not GameState.attr_req_met(it, h2):
			blocked.append(h2.name.split(" the ")[0])
			continue
		var verb := tr("Equip → %s") if _first_free_slot(h2, slot) >= 0 else tr("Swap → %s")
		equip_row.add_child(_icon_button(GameData.item_icon(it), verb % h2.name.split(" the ")[0], func(hid=h2.id, iid=it.id, idx=target_idx):
			selected_item_id = ""
			GameState.equip_item(hid, slot, idx, iid)
			render()
		))
	if equip_row.get_child_count() > 0:
		cv.add_child(_label("Equip on", 13, true))
		cv.add_child(equip_row)
	if not blocked.is_empty():
		cv.add_child(_wrap_label(tr("Needs %d %s: %s") % [it.attr_req, tr(str(GameData.ATTR_LABEL.get(it.attr, it.attr))), tr(str(", ".join(blocked)))], 12, true))
	if it.unique_id == "":
		var rcost := GameState.reforge_cost(it)
		cv.add_child(_label(tr("Reforge — reroll one stat (%d Essence)") % rcost, 13, true))
		var ref_row := HFlowContainer.new()
		ref_row.add_theme_constant_override("h_separation", 6)
		ref_row.add_theme_constant_override("v_separation", 6)
		var lines := [it.kind, it.secondary_kind, it.tertiary_kind]
		for li in lines.size():
			if str(lines[li]) == "":
				continue
			var rb := _icon_button(GameData.CURRENCY_ICON_PATH["crystals"], (tr("Reroll %s value") if li == 0 else tr("Reroll %s")) % _KIND_LABEL.get(lines[li], lines[li]), func(id=it.id, l=li):
				var err := GameState.reforge_item(id, l)
				if err != "":
					push_warning(err)
				render()
			)
			rb.disabled = GameState.crystals < rcost
			rb.tooltip_text = tr("The value rerolls; the kind stays.") if li == 0 else tr("Rerolls into any stat this item doesn't already have (or the same one).")
			ref_row.add_child(rb)
		cv.add_child(ref_row)
	cv.add_child(_hsep())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	bottom.add_child(_icon_button(GameData.CURRENCY_ICON_PATH["coins"], "Sell", func(id=it.id):
		selected_item_id = ""
		GameState.sell_item(id)
		render()
	))
	if GameState.recycle_unlocked():
		bottom.add_child(_icon_button(GameData.CURRENCY_ICON_PATH["crystals"], tr("Salvage +%d") % GameState.salvage_value(it), func(id=it.id):
			selected_item_id = ""
			GameState.salvage_item(id)
			render()
		))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(sp)
	bottom.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Close", close))
	cv.add_child(bottom)
	card.add_child(cv)
	center.add_child(card)
	root.add_child(overlay)


func _render_inventory_supplies(v: VBoxContainer) -> void:
	v.add_child(_label(tr("Tonics — belt %d/%d · drink one in a fight on a hero's turn (Tonics, key 8)") % [GameState.tonic_count(), GameData.TONIC_CAP], 16))
	for def in GameData.TONIC_TYPES:
		var tid: String = def["id"]
		var buy := _icon_button(GameData.CURRENCY_ICON_PATH["coins"], "Buy", func():
			var err := GameState.buy_tonic(tid)
			if err != "":
				_flavor_toast = err
			render()
		)
		buy.disabled = GameState.tonic_count() >= GameData.TONIC_CAP or GameState.coins < int(def["cost"])
		v.add_child(_info_row(tr("%s (%d Gold) — %s · carrying %d") % [tr(str(def["name"])), int(def["cost"]), tr(str(def["desc"])), GameState.tonic_count(tid)], 12, [buy], _icon(str(def["icon"]), 24)))


## Inventory → Relics: the Relic Altar. Equipped relics sit in the altar's
## slots, and the rest of the collection as a
## grid of tiles; clicking any relic opens its card in a pop-up.
func _render_inventory_relics(v: VBoxContainer) -> void:
	var equipped := Combat.equipped_relics()
	var cap := GameState.relic_slot_cap()
	var altar := PanelContainer.new()
	altar.theme_type_variation = &"CardPanelViolet"
	var av := _vbox(10)
	av.add_child(_label(tr("Relic Altar — %d/%d slots · every relic empowers the whole party") % [equipped.size(), cap], 16))
	var slots := HFlowContainer.new()
	slots.add_theme_constant_override("h_separation", 10)
	slots.add_theme_constant_override("v_separation", 10)
	for i in cap:
		slots.add_child(_relic_slot_card(equipped[i] if i < equipped.size() else null))
	av.add_child(slots)
	altar.add_child(av)
	v.add_child(altar)

	var rest: Array = GameState.relics.filter(func(r): return not r.equipped)
	rest.sort_custom(func(a, b): return _rarity_rank(a.rarity) > _rarity_rank(b.rarity) or (a.rarity == b.rarity and a.level > b.level))
	v.add_child(_label(tr("Collection (%d)") % rest.size(), 16))
	if rest.is_empty():
		v.add_child(_label("No spare relics — they drop from fights, treasure and shops.", 12, true))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for r in rest:
		grid.add_child(_relic_tile(r))
	v.add_child(grid)
	var sel: Array = GameState.relics.filter(func(r): return r.id == selected_item_id)
	if not sel.is_empty():
		_relic_modal(sel[0])


func _relic_effect_lines(r: Relic) -> Array[String]:
	var out: Array[String] = []
	if r.unique_id != "":
		out.append(str(GameData.find_unique_relic(r.unique_id).get("desc", "")))
	else:
		for s in r.specials:
			out.append(str(s["label"]))
		if not r.trigger.is_empty():
			out.append(Combat.describe_effect(r.trigger))
	return out


## An altar slot: the equipped relic's icon, name and effects, or an empty socket.
func _relic_slot_card(r: Relic) -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(270, 130)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if r == null:
		b.disabled = true
		var e := _label("Empty slot — pick a relic from your collection", 12, true)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size.x = 220
		row.add_child(e)
		b.add_child(row)
		return b
	b.pressed.connect(func(id=r.id):
		selected_item_id = id
		render()
	)
	row.add_child(_relic_icon_box(r, 56))
	var col := _vbox(2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := _label(_loot_display_name(r), 13)
	nm.add_theme_color_override("font_color", ITEM_RARITY_COLOR.get(r.rarity, Palette.TEXT))
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.custom_minimum_size.x = 170
	col.add_child(nm)
	col.add_child(_label(tr("%s · Lv%d%s") % [tr(str(r.type)), r.level, tr(str(tr(" · Awakened") if r.awakened else ""))], 12, true))
	var lines := _relic_effect_lines(r)
	for line in lines:
		var l := _label(("• " if lines.size() > 1 else "") + line, 12)
		l.custom_minimum_size.x = 190
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
	row.add_child(col)
	b.add_child(row)
	b.tooltip_text = tr("%s\n%s\nClick for details") % [_loot_display_name(r), "\n".join(lines)]
	return b


func _relic_icon_box(r: Relic, size: int) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(size, size)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := _icon(GameData.RARITY_FRAME_PATH.get(r.rarity, GameData.RARITY_FRAME_PATH["common"]), size)
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(frame)
	var inner := int(size * 0.72)
	var ic := _icon(GameData.relic_icon(r), inner)
	ic.position = Vector2((size - inner) * 0.5, (size - inner) * 0.5)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	var gem := _icon(GameData.RELIC_TYPE_ICON_PATH.get(r.type, ""), 18)
	gem.position = Vector2(size - 16, size - 16)
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(gem)
	return box


## A collection tile: framed icon with the element gem, name and level.
func _relic_tile(r: Relic) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(112, 134)
	b.pressed.connect(func(id=r.id):
		selected_item_id = id
		render()
	)
	var col := _vbox(3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	var box := _relic_icon_box(r, 60)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(box)
	var nl := _label(_loot_display_name(r), 12)
	nl.add_theme_color_override("font_color", ITEM_RARITY_COLOR.get(r.rarity, Palette.TEXT))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.max_lines_visible = 2
	nl.custom_minimum_size.x = 100
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nl)
	var ll := _label(tr("Lv%d%s") % [r.level, tr(str(" ★" if r.awakened else ""))], 12, true)
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ll)
	b.add_child(col)
	b.tooltip_text = tr("%s — click for details") % tr(str(_loot_display_name(r)))
	return b


## A relic's full card over the screen: effects, level, and every action.
func _relic_modal(r: Relic) -> void:
	var close := func():
		selected_item_id = ""
		render()
	_combat_hotkeys["Escape"] = close
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP]:
		dim.set_offset(side, -80)
	for side in [SIDE_RIGHT, SIDE_BOTTOM]:
		dim.set_offset(side, 80)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			close.call()
	)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanelViolet"
	card.custom_minimum_size.x = 460
	var cv := _vbox(8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.add_child(_relic_icon_box(r, 76))
	var tcol := _vbox(3)
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nm := _label(_loot_display_name(r), 16)
	nm.add_theme_color_override("font_color", ITEM_RARITY_COLOR.get(r.rarity, Palette.TEXT))
	tcol.add_child(nm)
	tcol.add_child(_label(tr("%s %s relic · Lv%d/%d%s") % [tr(str(r.rarity.capitalize())), tr(str(r.type)), r.level, GameState.RELIC_MAX_LEVEL, tr(str(tr(" · Awakened") if r.awakened else ""))], 12, true))
	tcol.add_child(_label(tr("+%d party damage · +%d rift shield") % [r.dmg, r.hp], 13))
	top.add_child(tcol)
	cv.add_child(top)
	var rcost := GameState.relic_reroll_cost(r)
	var effects := _vbox(4)
	if r.unique_id != "":
		effects.add_child(_wrap_label(str(GameData.find_unique_relic(r.unique_id).get("desc", "")), 13))
		if r.combo_with != "":
			var partner := str(GameData.find_unique_relic(r.combo_with).get("name", ""))
			effects.add_child(_wrap_label(tr("Combo: stronger with %s%s") % [tr(str(partner)), tr(str(" (active!)" if Combat.party_has_unique_relic(r.combo_with) else ""))], 12, true))
	else:
		var rows: Array = []
		for i in r.specials.size():
			rows.append([str(r.specials[i]["label"]), i])
		if not r.trigger.is_empty():
			rows.append([Combat.describe_effect(r.trigger), -1])
		for row_def in rows:
			var er := HBoxContainer.new()
			er.add_theme_constant_override("separation", 8)
			var el := _wrap_label(("⚡ " if int(row_def[1]) < 0 else "• ") + tr(str(row_def[0])), 13)
			el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			er.add_child(el)
			var rb := _icon_button(GameData.CURRENCY_ICON_PATH["crystals"], "Reroll", func(id=r.id, idx=int(row_def[1])):
				var err := GameState.reroll_relic(id, idx)
				if err != "":
					push_warning(err)
				render()
			)
			rb.disabled = GameState.crystals < rcost
			rb.tooltip_text = tr("Reroll this effect for %d Essence (each reroll costs more)") % rcost
			er.add_child(rb)
			effects.add_child(er)
		if r.level < GameState.RELIC_MAX_LEVEL and not r.awakened:
			effects.add_child(_label(tr("Reaches Lv%d: awakens with one more effect.") % GameState.RELIC_MAX_LEVEL, 12, true))
	cv.add_child(effects)
	cv.add_child(_hsep())
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 6)
	acts.add_theme_constant_override("v_separation", 6)
	var used := Combat.equipped_relics().size()
	if r.equipped:
		acts.add_child(_icon_button(GameData.relic_icon(r), "Unequip", func(id=r.id):
			GameState.toggle_equip_relic(id)
			render()
		))
	else:
		var eb := _icon_domain_button("ember", GameData.relic_icon(r), "Place on the altar", func(id=r.id):
			GameState.toggle_equip_relic(id)
			selected_item_id = ""
			render()
		)
		eb.disabled = used >= GameState.relic_slot_cap()
		eb.tooltip_text = tr("Every altar slot is full — take a relic off first") if eb.disabled else ""
		acts.add_child(eb)
	if r.level < GameState.RELIC_MAX_LEVEL:
		var ucost := GameState.relic_upgrade_cost(r)
		var ub := _icon_button(GameData.CURRENCY_ICON_PATH["crystals"], tr("Upgrade — %d") % ucost, func(id=r.id):
			var err := GameState.upgrade_relic(id)
			if err != "":
				push_warning(err)
			render()
		)
		ub.disabled = GameState.crystals < ucost
		acts.add_child(ub)
	if not r.equipped:
		acts.add_child(_icon_button(GameData.CURRENCY_ICON_PATH["coins"], "Sell", func(id=r.id):
			selected_item_id = ""
			GameState.sell_relic(id)
			render()
		))
		if GameState.recycle_unlocked():
			acts.add_child(_icon_button("res://assets/skills/ingot_gold.png", "Scrap", func(id=r.id):
				selected_item_id = ""
				GameState.scrap_relic(id)
				render()
			))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acts.add_child(sp)
	acts.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Close", close))
	cv.add_child(acts)
	card.add_child(cv)
	center.add_child(card)
	root.add_child(overlay)
