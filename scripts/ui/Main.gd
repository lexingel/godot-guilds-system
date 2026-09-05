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
var selected_ability: String = ""
var expanded_skill_hero: String = ""


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


func _label(text: String, size: int = 14) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
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
		cv.add_child(_label("%s — Floors %d · Rec. Power %d" % [d["name"], d["floors"], d["rec_power"]], 16))
		cv.add_child(_button("Assemble Party", func(diff_id=d["id"]):
			pending_party.clear()
			screen = "party_assembly"
			_pending_diff_id = diff_id
			render()
		))
		card.add_child(cv)
		v.add_child(card)
	v.add_child(_label("Greater Rift / Ascendant Rift / Endless Rift — coming in a later pass.", 12))
	v.add_child(_button("Back to Terminal", func():
		screen = "terminal"
		render()
	))


var _pending_diff_id: String = "lesser"


# ---------------- Party Assembly ----------------
func _render_party_assembly(v: VBoxContainer) -> void:
	_topbar(v)
	v.add_child(_label("Assemble Party (pick up to 4)", 20))
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
		var status := " (downed)" if h.is_downed() else ""
		row.add_child(_label("%s — Lv%d %s · %d/%d HP%s" % [h.name, h.level, h.cls_id.capitalize(), h.hp, Combat.max_hp(h), status]))
		v.add_child(row)
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes yet — recruit some from the Guild Terminal first."))

	v.add_child(_hsep())
	v.add_child(_label("Starting Relic (pick one, optional)"))
	if pending_relic_options.is_empty():
		for i in GameState.STARTING_RELIC_CHOICES:
			pending_relic_options.append(Combat.gen_relic(Combat.weighted_rarity()))
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
	v.add_child(_button("Enter the Rift", func():
		if pending_party.is_empty():
			return
		var chosen: Relic = pending_relic_options[pending_relic_choice] if pending_relic_choice >= 0 else null
		var ids: Array[String] = []
		ids.assign(pending_party)
		GameState.start_run(_pending_diff_id, ids, chosen)
		pending_relic_options.clear()
		pending_relic_choice = -1
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
	v.add_child(_label("%s — Floor %d/%d" % [diff["name"], int(GameState.run["floor"]) + 1, diff["floors"]], 18))

	if GameState.run.get("sealed") != null:
		v.add_child(_label("Rift Sealed! +%d Seal Tokens." % int(GameState.run["sealed"]["tokens"])))
		v.add_child(_button("Return to Terminal", func():
			GameState.finish_run()
			screen = "terminal"
			render()
		))
		return

	v.add_child(_hsep())
	for h in GameState.current_party():
		v.add_child(_label("%s — %d/%d HP%s" % [h.name, h.hp, Combat.max_hp(h), " (downed)" if h.is_downed() else ""]))
	v.add_child(_hsep())

	match GameState.run["node_kind"]:
		"combat", "boss": _render_combat_node(v)
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
	var is_boss := GameState.run["node_kind"] == "boss"
	if not ns.has("result"):
		v.add_child(_label("A %s encounter awaits." % ("Boss" if is_boss else "Combat")))
		var abil_row := HBoxContainer.new()
		for role in GameData.ABILITIES:
			var ab: Dictionary = GameData.ABILITIES[role]
			var available := GameState.current_party().any(func(h): return h.cls_id == role and h.level >= 3)
			if available:
				var btn := CheckButton.new()
				btn.text = ab["name"]
				btn.button_pressed = selected_ability == role
				btn.toggled.connect(func(on: bool):
					selected_ability = role if on else ""
					render()
				)
				abil_row.add_child(btn)
		v.add_child(abil_row)
		v.add_child(_button("Engage", func():
			GameState.engage_node(selected_ability)
			selected_ability = ""
			render()
		))
		return

	var result: Dictionary = ns["result"]
	var log_box := _vbox(2)
	for line in result["log"]:
		log_box.add_child(_label(str(line), 12))
	v.add_child(log_box)

	if result["won"]:
		v.add_child(_label("Victory! +%d Coins, +%d Crystals" % [result["coin"], result["crystal"]]))
		var options: Array = result.get("reward_options", [])
		if not options.is_empty() and not ns.get("reward_chosen", false):
			v.add_child(_label("Choose a reward:"))
			for i in options.size():
				var opt: Dictionary = options[i]
				var obj = opt["obj"]
				var desc: String = obj.desc() if opt["loot_type"] == "relic" else Combat.describe_skill(obj.kind, obj.value)
				v.add_child(_button("%s — %s" % [obj.name, desc], func(idx=i):
					GameState.pick_combat_reward(idx)
					render()
				))
		else:
			v.add_child(_button("Continue", func():
				if is_boss:
					GameState.seal_rift()
				else:
					GameState.advance_node()
				render()
			))
	else:
		v.add_child(_label("Defeat — the party is downed and recovering."))
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
		var row := HBoxContainer.new()
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
	var tabs := HBoxContainer.new()
	tabs.add_child(_button("Roster", func(): term_tab = "roster"; render()))
	tabs.add_child(_button("Hero Recruits", func(): term_tab = "recruits"; render()))
	tabs.add_child(_button("Rift Hall", func(): screen = "rift_hall"; render()))
	v.add_child(tabs)
	v.add_child(_hsep())

	if term_tab == "recruits":
		_render_recruits(v)
	else:
		_render_roster(v)


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


func _render_roster(v: VBoxContainer) -> void:
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes recruited yet."))
		return
	for h in GameState.heroes:
		var card := PanelContainer.new()
		var cv := _vbox(4)
		cv.add_child(_label("%s — Lv%d %s (%s) · %d/%d HP" % [h.name, h.level, h.cls_id.capitalize(), h.rank, h.hp, Combat.max_hp(h)]))
		cv.add_child(_label("Trait: %s" % (h.trait_name if h.trait_name != "" else "Steadfast"), 12))
		cv.add_child(_label("Power %d" % Combat.power_of(h), 12))

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
		cv.add_child(actions)

		if expanded_skill_hero == h.id:
			cv.add_child(_hsep())
			cv.add_child(_label("Skill Points: %d" % h.skill_points, 12))
			var tree: Array = GameData.CLASS_SKILLS.get(h.cls_id, [])
			for n in tree:
				var learned: bool = h.skills.get(n["id"], false)
				var srow := HBoxContainer.new()
				srow.add_child(_label("%s — %s (Lv%d, %d SP)%s" % [n["name"], Combat.describe_skill(n["kind"], n["value"]), n["req_level"], n["cost"], " [learned]" if learned else ""], 12))
				if not learned:
					srow.add_child(_button("Learn", func(hid=h.id, sid=n["id"]):
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

		var equipped_items := GameState.items.filter(func(it): return it.equipped_to == h.id)
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

		card.add_child(cv)
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
	var unequipped_items := GameState.items.filter(func(it): return it.equipped_to == "")
	if unequipped_items.is_empty():
		v.add_child(_label("No unequipped items.", 12))
	for it in unequipped_items:
		var row := HBoxContainer.new()
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
		v.add_child(rrow)
