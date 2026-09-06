extends Control
## Root UI controller — mirrors guild-system.html's render() function: one
## place that clears and rebuilds the current screen's Controls from
## GameState, rather than a scene per screen. Kept as plain Controls with no
## custom Theme (visual polish is explicitly deferred past this slice).

@onready var root: MarginContainer = $Root

var screen: String = "onboard"     # onboard | rift_hall | party_assembly | rift_run | terminal
var term_tab: String = "roster"    # roster | recruits
var pending_party: Array[String] = []
var pending_relic_options: Array = []
var pending_relic_choice: int = -1
var selected_hero_id: String = ""
var expanded_skill_hero: String = ""
var confirm_reset: bool = false


func _ready() -> void:
	if not GameState.load_save():
		GameState.reset()
	if GameState.guild_name != "":
		screen = "terminal" if GameState.run.is_empty() else "rift_run"
	GameState.state_changed.connect(render)
	render()


func _clear_root() -> void:
	for c in root.get_children():
		c.queue_free()


func _vbox(gap: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	return v


## No autowrap by default: a wrapping Label's minimum size shrinks to ~one
## word, so inside an HBoxContainer row it gets squeezed to near-zero width
## and wraps every word onto its own line. Long text (combat log lines, item
## descriptions) instead sits in a VBoxContainer stretched to the fixed-width
## content column, so it wraps at a sane width via wrap_text() below instead.
func _label(text: String, size: int = 14, muted: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if muted:
		l.add_theme_color_override("font_color", Palette.MUTED)
	return l


## Pixel-art icon at a fixed size, nearest-neighbor filtered to stay crisp
## (matches the HTML's image-rendering:pixelated).
func _icon(path: String, size: int = 24) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	t.custom_minimum_size = Vector2(size, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


## Opt-in wrapping variant for long standalone text (combat log lines,
## descriptions) — safe to use only where the label is the sole child of its
## row (a VBoxContainer entry, not sharing an HBoxContainer with buttons).
func _wrap_label(text: String, size: int = 14) -> Label:
	var l := _label(text, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _hsep() -> HSeparator:
	return HSeparator.new()


func render() -> void:
	_clear_root()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var v := _vbox(14)
	v.custom_minimum_size = Vector2(760, 0)
	scroll.add_child(v)

	match screen:
		"onboard": _render_onboard(v)
		"rift_hall": _render_rift_hall(v)
		"party_assembly": _render_party_assembly(v)
		"rift_run": _render_rift_run(v)
		"terminal": _render_terminal(v)


func _topbar(v: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_label("%s — %d Coins · %d Crystals · %d Tokens" % [GameState.guild_name, GameState.coins, GameState.crystals, GameState.tokens], 16))
	v.add_child(row)
	v.add_child(_hsep())


# ---------------- Onboard ----------------
func _render_onboard(v: VBoxContainer) -> void:
	v.add_child(_label("Name Your Guild", 22))
	var edit := LineEdit.new()
	edit.placeholder_text = "Guild name"
	v.add_child(edit)
	v.add_child(_button("Found the Guild", func():
		var n := edit.text.strip_edges()
		if n == "":
			return
		GameState.guild_name = n
		GameState.refresh_recruit_pool()
		GameState.save()
		screen = "terminal"
		render()
	))


# ---------------- Rift Hall ----------------
func _render_rift_hall(v: VBoxContainer) -> void:
	_topbar(v)
	v.add_child(_label("Rift Hall", 20))
	for d in GameData.DIFFICULTIES:
		var card := PanelContainer.new()
		var cv := _vbox(4)
		var did: String = d["id"]
		cv.add_child(_label("%s — Floors %d · Rec. Power %d" % [d["name"], d["floors"], d["rec_power"]], 16))
		cv.add_child(_button("Assemble Party", func(diff_id=did):
			pending_party.clear()
			screen = "party_assembly"
			_pending_diff_id = diff_id
			_pending_endless = false
			render()
		))
		card.add_child(cv)
		v.add_child(card)

	var endless_card := PanelContainer.new()
	var ecv := _vbox(4)
	ecv.add_child(_label("Endless Rift — scales forever. Best cycle: %d" % GameState.best_endless_cycle, 16))
	ecv.add_child(_button("Assemble Party", func():
		pending_party.clear()
		screen = "party_assembly"
		_pending_diff_id = "endless"
		_pending_endless = true
		render()
	))
	endless_card.add_child(ecv)
	v.add_child(endless_card)

	v.add_child(_label("Greater Rift / Ascendant Rift — coming in a later pass.", 12))
	v.add_child(_button("Back to Terminal", func():
		screen = "terminal"
		render()
	))


var _pending_diff_id: String = "lesser"
var _pending_endless: bool = false
var _pending_hardcore: bool = false


# ---------------- Party Assembly ----------------
func _render_party_assembly(v: VBoxContainer) -> void:
	_topbar(v)
	v.add_child(_label("Assemble Party (pick up to 4)", 20))
	var champ := GameState.ensure_champion()
	var champ_row := HBoxContainer.new()
	var champ_portrait := GameData.portrait_for_hero(champ.cls_id, champ.pool_id)
	if champ_portrait != "":
		champ_row.add_child(_icon(champ_portrait, 48))
	champ_row.add_child(_label("Champion: %s — Rank %s (always joins) · %d/%d HP" % [champ.name, champ.rank, champ.hp, Combat.max_hp(champ)], 13))
	v.add_child(champ_row)
	for h in GameState.heroes:
		var row := HBoxContainer.new()
		var picked := pending_party.has(h.id)
		var cb := CheckBox.new()
		cb.button_pressed = picked
		cb.disabled = h.is_downed()
		cb.toggled.connect(func(on: bool):
			if on and pending_party.size() < 4:
				pending_party.append(h.id)
			else:
				pending_party.erase(h.id)
			render()
		)
		row.add_child(cb)
		var portrait_path := GameData.portrait_for_hero(h.cls_id, h.pool_id)
		if portrait_path != "":
			row.add_child(_icon(portrait_path, 40))
		var status := " (downed)" if h.is_downed() else ""
		row.add_child(_label("%s — Lv%d %s · %d/%d HP%s" % [h.name, h.level, h.cls_id.capitalize(), h.hp, Combat.max_hp(h), status]))
		v.add_child(row)
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes yet — recruit some from the Guild Terminal first."))

	v.add_child(_hsep())
	var choice_count := GameState.relic_choice_count()
	if choice_count > 0:
		v.add_child(_label("Starting Relic (pick one, optional)"))
		if pending_relic_options.is_empty():
			for i in choice_count:
				var rarity := "rare" if (GameState.inherited_power() and Combat.weighted_rarity() == "common") else Combat.weighted_rarity()
				pending_relic_options.append(Combat.gen_relic(rarity))
	for i in pending_relic_options.size():
		var r: Relic = pending_relic_options[i]
		var row2 := HBoxContainer.new()
		var rb := CheckButton.new()
		rb.button_pressed = pending_relic_choice == i
		rb.toggled.connect(func(on: bool):
			pending_relic_choice = i if on else -1
			render()
		)
		row2.add_child(rb)
		row2.add_child(_label("%s (%s) — %s" % [r.name, r.type, r.desc()]))
		v.add_child(row2)

	v.add_child(_hsep())
	var hc_toggle := CheckButton.new()
	hc_toggle.text = "Hardcore Mode — ×1.5 rewards, a loss removes your heroes for good"
	hc_toggle.button_pressed = _pending_hardcore
	hc_toggle.toggled.connect(func(on: bool):
		_pending_hardcore = on
		render()
	)
	v.add_child(hc_toggle)

	v.add_child(_hsep())
	v.add_child(_button("Enter the Rift", func():
		if pending_party.is_empty():
			return
		var chosen: Relic = pending_relic_options[pending_relic_choice] if pending_relic_choice >= 0 else null
		var ids: Array[String] = []
		ids.assign(pending_party)
		GameState.start_run(_pending_diff_id, ids, chosen, _pending_hardcore, _pending_endless)
		pending_relic_options.clear()
		pending_relic_choice = -1
		_pending_hardcore = false
		screen = "rift_run"
		render()
	))
	v.add_child(_button("Back", func():
		screen = "rift_hall"
		render()
	))


# ---------------- Rift Run ----------------
func _render_rift_run(v: VBoxContainer) -> void:
	if GameState.run.is_empty():
		screen = "terminal"
		render()
		return
	_topbar(v)
	var diff := GameState._diff()
	var pos: int = int(GameState.run["pos"])
	var total_layers: int = (GameState.run["layers"] as Array).size()
	var cycle_label := (" (cycle %d)" % (int(GameState.run["cycle"]) + 1)) if GameState.run.get("endless", false) else ""
	v.add_child(_label("%s%s — Node %d/%d" % [diff["name"], cycle_label, pos + 1, total_layers], 18))
	if GameState.run.get("hardcore", false):
		v.add_child(_label("Hardcore Mode active", 12))

	var sealed = GameState.run.get("sealed")
	if sealed != null:
		var sealed_dict: Dictionary = sealed
		var sealed_row := HBoxContainer.new()
		sealed_row.add_child(_icon(GameData.CHEST_ICON_PATH, 28))
		sealed_row.add_child(_label("Rift Sealed! +%d Seal Tokens%s%s" % [
			int(sealed_dict["tokens"]),
			" (fast clear)" if sealed_dict.get("fast_clear", false) else "",
			" · Rift Detector found!" if sealed_dict.get("got_detector", false) else "",
		]))
		v.add_child(sealed_row)
		if sealed_dict.get("continuing", false):
			v.add_child(_label("Endless cycle %d begins..." % int(sealed_dict["cycle"])))
			v.add_child(_button("Continue Endless Run", func():
				GameState.continue_endless()
				render()
			))
		else:
			v.add_child(_button("Return to Terminal", func():
				GameState.finish_run()
				screen = "terminal"
				render()
			))
		return

	v.add_child(_hsep())
	for h in GameState.current_party():
		v.add_child(_label("%s%s — %d/%d HP%s" % [h.name, " (Champion)" if h.is_champion else "", h.hp, Combat.max_hp(h), " (downed)" if h.is_downed() else ""]))
	v.add_child(_hsep())

	var options := GameState.current_layer_options()
	var kind := GameState.current_node_kind()
	if kind == "" and options.size() > 1:
		v.add_child(_label("Choose your path:"))
		for opt in options:
			v.add_child(_button(str(opt).capitalize(), func(picked=str(opt)):
				GameState.choose_node_type(picked)
				render()
			))
	else:
		match kind:
			"combat", "boss", "elite": _render_combat_node(v)
			"shop": _render_shop_node(v)
			"hazard": _render_hazard_node(v)

	v.add_child(_hsep())
	v.add_child(_button("Retreat (keep loot, no Seal Tokens)", func():
		GameState.retreat_now()
		screen = "terminal"
		render()
	))


func _render_combat_node(v: VBoxContainer) -> void:
	var ns: Dictionary = GameState.run.get("node_state", {})
	var kind := GameState.current_node_kind()
	var is_boss := kind == "boss"

	if not ns.has("combat_state") and not ns.has("result"):
		var kind_label := "Boss" if is_boss else ("Elite" if kind == "elite" else "Combat")
		v.add_child(_label("A %s encounter awaits." % kind_label))
		v.add_child(_button("Engage", func():
			GameState.engage_node()
			render()
		))
		return

	if ns.has("combat_state") and not ns.has("result"):
		var state: Dictionary = ns["combat_state"]
		var monster_row := HBoxContainer.new()
		monster_row.add_child(_icon(GameData.sprite_for_monster(str(state["monster_name"])), 28))
		monster_row.add_child(_label("%s — %d/%d HP" % [str(state["monster_name"]), max(0, int(state["monster_hp"])), int(state["monster_max_hp"])], 14))
		v.add_child(monster_row)
		v.add_child(_label("Party — %d/%d HP" % [int(state["hp_pool"]), int(state["total_max_at_start"])], 14, true))
		var log_box := _vbox(2)
		for line in state["log"]:
			log_box.add_child(_wrap_label(str(line), 12))
		v.add_child(log_box)

		var action_row := HBoxContainer.new()
		action_row.add_child(_button("Attack", func():
			GameState.combat_action("attack")
			render()
		))
		var ability_id: String = state["ability_id"]
		if ability_id != "":
			var ab: Dictionary = GameData.ABILITIES[ability_id]
			var ab_btn := _button(str(ab["name"]), func():
				GameState.combat_action("ability")
				render()
			)
			ab_btn.disabled = not bool(state["ability_available"])
			action_row.add_child(ab_btn)
		action_row.add_child(_button("Defend", func():
			GameState.combat_action("defend")
			render()
		))
		action_row.add_child(_button("Retreat", func():
			GameState.combat_action("retreat")
			render()
		))
		v.add_child(action_row)
		return

	var result: Dictionary = ns["result"]
	var monster_row := HBoxContainer.new()
	monster_row.add_child(_icon(GameData.sprite_for_monster(str(result["monster_name"])), 28))
	monster_row.add_child(_label(str(result["monster_name"]), 14))
	v.add_child(monster_row)
	var log_box := _vbox(2)
	for line in result["log"]:
		log_box.add_child(_wrap_label(str(line), 12))
	v.add_child(log_box)

	if result["won"]:
		var bonus_crystal: int = result.get("bonus_crystal", 0)
		var victory_text := "Victory! +%d Coins, +%d Crystals" % [result["coin"], result["crystal"]]
		if bonus_crystal > 0:
			victory_text += " (+%d bonus)" % bonus_crystal
		v.add_child(_label(victory_text))
		var options: Array = result.get("reward_options", [])
		if not options.is_empty() and not ns.get("reward_chosen", false):
			v.add_child(_label("Choose a reward:"))
			for i in options.size():
				var opt: Dictionary = options[i]
				var obj = opt["obj"]
				var is_relic: bool = opt["loot_type"] == "relic"
				var desc: String = obj.desc() if is_relic else Combat.describe_skill(obj.kind, obj.value)
				var icon_path: String = GameData.RELIC_TYPE_ICON_PATH[obj.type] if is_relic else GameData.ITEM_CATEGORY_ICON_PATH[obj.category]
				var btn := _button("%s — %s" % [obj.name, desc], func(idx=i):
					GameState.pick_combat_reward(idx)
					render()
				)
				btn.icon = load(icon_path)
				v.add_child(btn)
		else:
			v.add_child(_button("Continue", func():
				if is_boss:
					GameState.seal_rift()
				else:
					GameState.advance_node()
				render()
			))
	else:
		var defeat_text := "You withdraw from the fight." if result.get("retreated", false) else "Defeat — the party is downed and recovering."
		v.add_child(_label(defeat_text))
		v.add_child(_button("Return to Terminal", func():
			GameState.finish_run()
			screen = "terminal"
			render()
		))


func _render_shop_node(v: VBoxContainer) -> void:
	GameState.ensure_shop_offers()
	var ns: Dictionary = GameState.run["node_state"]
	v.add_child(_label("Rift Hallway Shop"))
	var offers: Array = ns["offers"]
	for i in offers.size():
		var off: Dictionary = offers[i]
		var obj = off["obj"]
		var desc: String = obj.desc() if off["loot_type"] == "relic" else Combat.describe_skill(obj.kind, obj.value)
		var bought: bool = off.get("bought", false)
		var is_relic: bool = off["loot_type"] == "relic"
		var icon_path: String = GameData.RELIC_TYPE_ICON_PATH[obj.type] if is_relic else GameData.ITEM_CATEGORY_ICON_PATH[obj.category]
		var row := HBoxContainer.new()
		row.add_child(_icon(icon_path, 20))
		row.add_child(_label("%s — %s (%dc)%s" % [obj.name, desc, off["price"], " [bought]" if bought else ""]))
		if not bought:
			row.add_child(_button("Buy", func(idx=i):
				GameState.buy_shop_offer(idx)
				render()
			))
		v.add_child(row)
	v.add_child(_button("Continue", func():
		GameState.advance_node()
		render()
	))


func _render_hazard_node(v: VBoxContainer) -> void:
	GameState.ensure_hazard()
	var ns: Dictionary = GameState.run["node_state"]
	var hz: Dictionary = ns["hazard"]
	v.add_child(_label(hz["name"]))
	if not ns.get("resolved", false):
		v.add_child(_button("Push Through", func():
			GameState.push_through_hazard()
			render()
		))
	else:
		for line in ns.get("log", []):
			v.add_child(_label(str(line), 12))
		v.add_child(_button("Continue", func():
			GameState.advance_node()
			render()
		))


# ---------------- Terminal ----------------
func _render_terminal(v: VBoxContainer) -> void:
	_topbar(v)
	var tier := Combat.guild_tier_info()
	var tier_line := "%s — %d levels purchased" % [tier["name"], tier["total"]]
	if not tier["next"].is_empty():
		tier_line += " (%d to %s)" % [int(tier["next"]["min"]) - int(tier["total"]), tier["next"]["name"]]
	v.add_child(_label(tier_line, 12, true))
	var tabs := HBoxContainer.new()
	tabs.add_child(_button("Roster", func(): term_tab = "roster"; render()))
	tabs.add_child(_button("Hero Recruits", func(): term_tab = "recruits"; render()))
	tabs.add_child(_button("Medical Bay", func(): term_tab = "medical"; render()))
	tabs.add_child(_button("Guild Management", func(): term_tab = "management"; render()))
	tabs.add_child(_button("Rift Hall", func(): screen = "rift_hall"; render()))
	v.add_child(tabs)
	v.add_child(_hsep())

	match term_tab:
		"recruits": _render_recruits(v)
		"medical": _render_medical_bay(v)
		"management": _render_management(v)
		_: _render_roster(v)


func _render_recruits(v: VBoxContainer) -> void:
	v.add_child(_label("Hero Recruits — %d/%d roster slots" % [GameState.heroes.size(), GameState.hero_slot_cap()]))
	for h in GameState.recruit_pool:
		var rank := GameData.find_rank(h.rank)
		var row := HBoxContainer.new()
		row.add_child(_label("%s — Rank %s %s (%dc)" % [h.name, h.rank, h.cls_id.capitalize(), int(rank["cost"])]))
		row.add_child(_button("Recruit", func(id=h.id):
			var err := GameState.recruit_hero(id)
			if err != "":
				push_warning(err)
			render()
		))
		v.add_child(row)


func _render_medical_bay(v: VBoxContainer) -> void:
	v.add_child(_label("Medical Bay — %d/%d beds occupied" % [GameState.occupied_beds(), GameState.medical_bed_cap()], 16))
	if GameState.field_triage_available():
		v.add_child(_button("Field Triage (heal whole roster, once per rift cycle)%s" % ("" if not GameState.triage_used_this_cycle else " [used]"), func():
			var err := GameState.field_triage_action()
			if err != "":
				push_warning(err)
			render()
		))
	var wounded: Array[Hero] = []
	wounded.assign(GameState.heroes.filter(func(h): return h.hp < Combat.max_hp(h)))
	if wounded.is_empty():
		v.add_child(_label("No wounded heroes.", 12))
	for h in wounded:
		var row := HBoxContainer.new()
		var status := "Bedded, healing fast" if (h.bedded and h.is_downed()) else ("Downed — recovering" if h.is_downed() else "Wounded")
		row.add_child(_label("%s — %d/%d HP (%s)" % [h.name, h.hp, Combat.max_hp(h), status]))
		if h.is_downed() and not h.bedded:
			row.add_child(_button("Assign to Bed", func(id=h.id):
				GameState.assign_to_bed(id)
				render()
			))
		v.add_child(row)


func _render_management(v: VBoxContainer) -> void:
	for b in GameData.BRANCHES:
		v.add_child(_label("%s — %s" % [b["name"], b["sub"]], 16))
		for n in b["nodes"]:
			var key := "%s.%s" % [b["id"], n["id"]]
			var cur := GameState.lvl(key)
			var maxed := cur >= int(n["max"])
			var row := _vbox(2)
			var cur_desc := Combat.describe_node_effect(n["id"], cur)
			var line := "%s (Lvl %d/%d) — %s" % [n["name"], cur, n["max"], cur_desc]
			if not maxed:
				line += " → %s" % Combat.describe_node_effect(n["id"], cur + 1)
			row.add_child(_label(line, 12))
			var brow := HBoxContainer.new()
			if not maxed:
				var cost: int = int(n["cost_base"]) + int(n["cost_step"]) * cur
				brow.add_child(_button("Upgrade (%dcr)" % cost, func(k=key):
					var err := GameState.upgrade_node(k)
					if err != "":
						push_warning(err)
					render()
				))
			var cap: Dictionary = n.get("cap", {})
			if not cap.is_empty() and maxed and not GameState.has_cap(key):
				brow.add_child(_button("%s (%dcr) — %s" % [cap["name"], int(cap["cost"]), cap["desc"]], func(k=key):
					var err := GameState.buy_cap(k)
					if err != "":
						push_warning(err)
					render()
				))
			elif not cap.is_empty() and GameState.has_cap(key):
				brow.add_child(_label("%s unlocked" % cap["name"], 12))
			row.add_child(brow)
			v.add_child(row)
		v.add_child(_hsep())

	var reset_btn := _button("Click again to confirm reset" if confirm_reset else "Reset Guild", func():
		if not confirm_reset:
			confirm_reset = true
			render()
			get_tree().create_timer(3.0).timeout.connect(func():
				confirm_reset = false
				if screen == "terminal" and term_tab == "management":
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


func _render_roster(v: VBoxContainer) -> void:
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes recruited yet."))
		return
	for h in GameState.heroes:
		var card := PanelContainer.new()
		var cv := _vbox(4)
		cv.add_child(_label("%s — Lv%d %s (%s) · %d/%d HP" % [h.name, h.level, h.cls_id.capitalize(), h.rank, h.hp, Combat.max_hp(h)]))
		cv.add_child(_label("Trait: %s" % (h.trait_name if h.trait_name != "" else "Steadfast"), 12, true))
		cv.add_child(_label("Power %d" % Combat.power_of(h), 12, true))

		var actions := HBoxContainer.new()
		actions.add_child(_button("Reroll Trait (60c)", func(id=h.id):
			var err := GameState.reroll_trait(id)
			if err != "":
				push_warning(err)
			render()
		))
		if h.trait_name != "":
			actions.add_child(_button("Scrub Trait (30c)", func(id=h.id):
				var err := GameState.scrub_trait(id)
				if err != "":
					push_warning(err)
				render()
			))
		actions.add_child(_button("Skills" if expanded_skill_hero != h.id else "Hide Skills", func(id=h.id):
			expanded_skill_hero = "" if expanded_skill_hero == id else id
			render()
		))
		if h.level >= 10:
			var cur_cls := GameData.find_class(h.pool_id)
			if not cur_cls.is_empty() and not GameState.evolution_target(cur_cls).is_empty():
				var next_cls := GameState.evolution_target(cur_cls)
				var next_rank := GameData.find_rank(next_cls["rank"])
				actions.add_child(_button("Evolve → %s (%dcr)" % [next_cls["name"], int(next_rank["cost"])], func(id=h.id):
					var err := GameState.evolve_hero(id)
					if err != "":
						push_warning(err)
					render()
				))
		cv.add_child(actions)

		if expanded_skill_hero == h.id:
			cv.add_child(_hsep())
			cv.add_child(_label("Skill Points: %d" % h.skill_points, 12))
			var tree: Array = GameData.CLASS_SKILLS.get(h.cls_id, [])
			for n in tree:
				var skill_id: String = n["id"]
				var learned: bool = h.skills.get(skill_id, false)
				var srow := HBoxContainer.new()
				srow.add_child(_label("%s — %s (Lv%d, %d SP)%s" % [n["name"], Combat.describe_skill(n["kind"], n["value"]), n["req_level"], n["cost"], " [learned]" if learned else ""], 12))
				if not learned:
					srow.add_child(_button("Learn", func(hid=h.id, sid=skill_id):
						var err := GameState.learn_skill(hid, sid)
						if err != "":
							push_warning(err)
						render()
					))
				cv.add_child(srow)
			var spent: int = h.skills.values().count(true)
			if spent > 0:
				cv.add_child(_button("Respec (%dc)" % GameState.respec_cost(spent), func(id=h.id):
					var err := GameState.respec_hero(id)
					if err != "":
						push_warning(err)
					render()
				))

		var equipped_items: Array[Item] = []
		equipped_items.assign(GameState.items.filter(func(it): return it.equipped_to == h.id))
		if not equipped_items.is_empty():
			var erow := HBoxContainer.new()
			for it in equipped_items:
				erow.add_child(_button("%s (%s) — unequip" % [it.name, GameData.ITEM_CATEGORY_LABEL[it.category]], func(id=it.id):
					var target: Item = null
					for x in GameState.items:
						if x.id == id:
							target = x
							break
					if target:
						GameState.equip_item(h.id, target.slot_type(), target.equipped_idx, "")
					render()
				))
			cv.add_child(erow)

		var hero_row := HBoxContainer.new()
		var portrait_path := GameData.portrait_for_hero(h.cls_id, h.pool_id)
		if portrait_path != "":
			hero_row.add_child(_icon(portrait_path, 64))
		hero_row.add_child(cv)
		card.add_child(hero_row)
		v.add_child(card)

	v.add_child(_hsep())
	_render_inventory(v)


func _first_free_slot(h: Hero, slot_type: String) -> int:
	var cap := GameData.weapon_slots(h.pool_id) if slot_type == "weapon" else GameData.gear_slots(h.rank)
	var used := {}
	for it in GameState.items:
		if it.equipped_to == h.id and it.slot_type() == slot_type:
			used[it.equipped_idx] = true
	for i in cap:
		if not used.has(i):
			return i
	return -1


func _render_inventory(v: VBoxContainer) -> void:
	v.add_child(_label("Inventory", 16))
	var unequipped_items: Array[Item] = []
	unequipped_items.assign(GameState.items.filter(func(it): return it.equipped_to == ""))
	if unequipped_items.is_empty():
		v.add_child(_label("No unequipped items.", 12))
	for it in unequipped_items:
		var row := HBoxContainer.new()
		row.add_child(_icon(GameData.ITEM_CATEGORY_ICON_PATH[it.category], 20))
		row.add_child(_label("%s (%s) — %s" % [it.name, GameData.ITEM_CATEGORY_LABEL[it.category], Combat.describe_skill(it.kind, it.value)], 12))
		for h2 in GameState.heroes:
			var slot := it.slot_type()
			var free_idx := _first_free_slot(h2, slot)
			if free_idx >= 0:
				row.add_child(_button("Equip → %s" % h2.name.split(" the ")[0], func(hid=h2.id, iid=it.id, s=slot, idx=free_idx):
					GameState.equip_item(hid, s, idx, iid)
					render()
				))
		row.add_child(_button("Sell", func(id=it.id):
			GameState.sell_item(id)
			render()
		))
		v.add_child(row)

	v.add_child(_hsep())
	v.add_child(_label("Relics — %d/%d slots equipped" % [Combat.equipped_relics().size(), GameState.relic_slot_cap()], 16))
	for r in GameState.relics:
		var rrow := HBoxContainer.new()
		rrow.add_child(_icon(GameData.RELIC_TYPE_ICON_PATH[r.type], 20))
		rrow.add_child(_label("%s (%s, Lv%d) — %s" % [r.name, r.type, r.level, r.desc()], 12))
		rrow.add_child(_button("Unequip" if r.equipped else "Equip", func(id=r.id):
			GameState.toggle_equip_relic(id)
			render()
		))
		if r.level < GameState.RELIC_MAX_LEVEL:
			var rar := GameData.find_rarity(r.rarity)
			var cost := int(round(15.0 * float(rar["mult"]) * r.level))
			rrow.add_child(_button("Upgrade (%dcr)" % cost, func(id=r.id):
				var err := GameState.upgrade_relic(id)
				if err != "":
					push_warning(err)
				render()
			))
		if not r.equipped:
			rrow.add_child(_button("Sell", func(id=r.id):
				GameState.sell_relic(id)
				render()
			))
			if GameState.recycle_unlocked():
				rrow.add_child(_button("Scrap", func(id=r.id):
					GameState.scrap_relic(id)
					render()
				))
		v.add_child(rrow)

	v.add_child(_hsep())
	v.add_child(_label("Rift Detectors", 16))
	if GameState.detectors.is_empty():
		v.add_child(_label("No Detectors.", 12))
	for d in GameState.detectors:
		var drow := HBoxContainer.new()
		var det_id: String = d["id"]
		drow.add_child(_label("%s Detector" % str(d["tier"]).capitalize(), 12))
		drow.add_child(_button("Sell", func(id=det_id):
			GameState.sell_detector(id)
			render()
		))
		drow.add_child(_button("Use for Shop Boost", func(id=det_id):
			var err := GameState.use_detector_for_shop_boost(id)
			if err != "":
				push_warning(err)
			render()
		))
		v.add_child(drow)
