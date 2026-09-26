class_name RiftRunView
extends BattleView
## Inside a rift: the path map, run bar, shop and hazard nodes, and the
## mid-rift Gear Up panel. Combat lives in BattleView.

## One marker on the path map — an icon in a domain-colored ring, matching
## MAP_NODE_COLOR's existing per-kind hues. `cb` is an empty (invalid)
## Callable for a marker that's purely informational (a future floor's
## still-open preview, or any already-resolved floor) — only the current
## floor's still-open fork options are actually clickable.
const MAP_NODE_DESC := {
	"combat": "Combat — 1-3 monsters. Coins, Crystals and a loot pick.",
	"elite": "Elite — one tough foe (double HP, harder hits). +40% rewards.",
	"shop": "Shop — spend Coins on items and relics. No fighting.",
	"hazard": "Hazard — a trap that hurts the party (hazard guard helps). May drop Coins or Crystals.",
	"boss": "Boss — the rift's warden, with a special mechanic. Win to seal the rift.",
	"campfire": "Campfire — rest (heal), train (XP) or sharpen (abilities ready). No fighting.",
	"event": "Event — a strange encounter with a few choices; each says what it does.",
	"treasure": "Treasure — pick one of two loot drops. No fighting.",
}


func _path_node_marker(kind: String, is_current: bool, cb: Callable) -> Control:
	const MARKER_SIZE := 34.0
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(MARKER_SIZE, MARKER_SIZE)
	wrap.size = Vector2(MARKER_SIZE, MARKER_SIZE)

	var ring := PanelContainer.new()
	var ring_style := StyleBoxFlat.new()
	ring_style.bg_color = Palette.INK
	var border_w := 3 if is_current else 2
	ring_style.border_width_left = border_w
	ring_style.border_width_top = border_w
	ring_style.border_width_right = border_w
	ring_style.border_width_bottom = border_w
	ring_style.border_color = MAP_NODE_COLOR.get(kind, Palette.LINE)
	ring_style.corner_radius_top_left = 999
	ring_style.corner_radius_top_right = 999
	ring_style.corner_radius_bottom_left = 999
	ring_style.corner_radius_bottom_right = 999
	ring.add_theme_stylebox_override("panel", ring_style)
	ring.custom_minimum_size = Vector2(MARKER_SIZE, MARKER_SIZE)
	ring.size = Vector2(MARKER_SIZE, MARKER_SIZE)
	wrap.add_child(ring)

	var icon_path: String = MAP_NODE_ICON.get(kind, "")
	if icon_path != "":
		var icon_size := MARKER_SIZE * 0.6
		var icon_node := _icon(icon_path, int(icon_size))
		icon_node.position = Vector2((MARKER_SIZE - icon_size) * 0.5, (MARKER_SIZE - icon_size) * 0.5)
		wrap.add_child(icon_node)
	else:
		var l := _label(MAP_NODE_LABEL.get(kind, "?"), 13)
		l.add_theme_color_override("font_color", Color(0, 0, 0, 1))
		l.position = Vector2(MARKER_SIZE * 0.32, MARKER_SIZE * 0.16)
		wrap.add_child(l)

	var desc: String = MAP_NODE_DESC.get(kind, str(kind).capitalize())
	ring.tooltip_text = desc
	if cb.is_valid():
		var btn := Button.new()
		btn.flat = true
		btn.custom_minimum_size = Vector2(MARKER_SIZE, MARKER_SIZE)
		btn.size = Vector2(MARKER_SIZE, MARKER_SIZE)
		var clear_style := StyleBoxEmpty.new()
		for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(style_name, clear_style)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = desc + "\n(click to take this path)"
		btn.pressed.connect(cb)
		wrap.add_child(btn)

	return wrap


## The whole rift path as a visual map — a background illustration with icon
## markers positioned along a gentle winding line and thin connector
## segments between consecutive floors, replacing the old flat row of
## letter-in-circle markers (a reskin of run["layers"]/["chosen"], not new
## state). A floor with an unresolved fork (2 possible encounter types, none
## picked yet) shows both options; if it's the floor the player is actually
## standing on, both options are clickable right here — picking one calls
## GameState.choose_node_type directly from the map, the same
## click-a-node-on-the-map interaction every reference map screen uses. This
## replaces the separate "Choose your path" button list that used to render
## further down in _render_rift_run.
func _render_rift_map(v: VBoxContainer) -> void:
	var layers: Array = GameState.run["layers"]
	var chosen: Dictionary = GameState.run.get("chosen", {})
	var pos: int = int(GameState.run["pos"])

	# Spans the column (the combat arena's width), not a fixed 900px strip.
	var map_size := Vector2(maxf(700.0, v.custom_minimum_size.x), 150)
	var map_ctrl := Control.new()
	map_ctrl.custom_minimum_size = map_size

	var bg := TextureRect.new()
	bg.texture = load("res://assets/screens/riftpath_bg.png")
	bg.custom_minimum_size = map_size
	bg.size = map_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_ctrl.add_child(bg)

	var n := layers.size()
	var margin := 40.0
	var step: float = (map_size.x - margin * 2.0) / float(max(1, n - 1))
	var base_y := map_size.y * 0.55
	var anchors: Array[Vector2] = []
	for i in n:
		var ax: float = margin + step * i
		var ay: float = base_y + sin(float(i) * 1.1) * 22.0
		anchors.append(Vector2(ax, ay))

	# Where each floor's node(s) sit: one marker once resolved, else one per
	# fork option stacked around the anchor. Every option can lead to every
	# option on the next floor, so links run all-to-all between floors.
	var spread := 30.0
	var slots: Array = []   # per floor: [[kind, Vector2], ...]
	for i in n:
		var opts_i: Array = layers[i]["options"]
		var resolved_i: String = str(chosen[i]) if chosen.has(i) else (str(opts_i[0]) if opts_i.size() == 1 else "")
		var here: Array = []
		if resolved_i != "":
			here.append([resolved_i, anchors[i]])
		else:
			for oi in opts_i.size():
				here.append([str(opts_i[oi]), Vector2(anchors[i].x, anchors[i].y + (float(oi) - float(opts_i.size() - 1) / 2.0) * spread)])
		slots.append(here)
	# Links first, so markers draw on top: gold along the path already
	# walked, dim for what's still ahead.
	for i in n - 1:
		for a in slots[i]:
			for b in slots[i + 1]:
				var line := Line2D.new()
				var walked := i + 1 <= pos and chosen.has(i + 1) or (i + 1 <= pos and (layers[i + 1]["options"] as Array).size() == 1)
				line.width = 3.0 if walked else 2.0
				var c: Color = Palette.EMBER_BRIGHT if walked else Palette.LINE
				line.default_color = Color(c.r, c.g, c.b, 0.9 if walked else 0.7)
				line.add_point(a[1])
				line.add_point(b[1])
				map_ctrl.add_child(line)
	for i in n:
		var num := _label(str(i + 1), 10, true)
		num.position = Vector2(anchors[i].x - 4, map_size.y - 16)
		map_ctrl.add_child(num)

	for i in n:
		var opts: Array = layers[i]["options"]
		var resolved: String = str(chosen[i]) if chosen.has(i) else (str(opts[0]) if opts.size() == 1 else "")
		var anchor: Vector2 = anchors[i]
		if resolved != "":
			var marker := _path_node_marker(resolved, i == pos, Callable())
			marker.position = anchor - marker.size * 0.5
			if i < pos:
				marker.modulate = Color(1, 1, 1, 0.55)
			map_ctrl.add_child(marker)
		else:
			for oi in opts.size():
				var opt := str(opts[oi])
				var oy: float = anchor.y + (float(oi) - float(opts.size() - 1) / 2.0) * spread
				var cb := Callable()
				if i == pos:
					cb = func(picked=opt):
						GameState.choose_node_type(picked)
						render()
				var marker2 := _path_node_marker(opt, i == pos, cb)
				marker2.position = Vector2(anchor.x, oy) - marker2.size * 0.5
				map_ctrl.add_child(marker2)

	v.add_child(map_ctrl)

	# Legend for the node icons actually on this map (hover any node for more).
	var kinds: Array[String] = []
	for layer in layers:
		for k in layer["options"]:
			if not kinds.has(str(k)):
				kinds.append(str(k))
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 16)
	if pos < n and (layers[pos]["options"] as Array).size() > 1 and not chosen.has(pos):
		var hint := _label("Choose your path — click a node on the map.", 13)
		hint.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		legend.add_child(hint)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.add_child(spacer)
	for k in ["combat", "elite", "shop", "hazard", "campfire", "event", "treasure", "boss"]:
		if not kinds.has(k):
			continue
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)
		item.tooltip_text = MAP_NODE_DESC.get(k, "")
		item.mouse_filter = Control.MOUSE_FILTER_STOP
		item.add_child(_icon(MAP_NODE_ICON[k], 16))
		var kl := _label(k.capitalize(), 12)
		kl.add_theme_color_override("font_color", MAP_NODE_COLOR.get(k, Palette.TEXT))
		item.add_child(kl)
		legend.add_child(item)
	v.add_child(legend)


# ---------------- Rift Run ----------------
## The strip at the top of every rift screen (StS/Hades-style run HUD):
## rift name, node pips, run tags (Hardcore, incense, rank, relic ward),
## then — outside combat, where the arena already shows HP — every party
## member's portrait with an HP bar, and the equipped relics (hover for
## what each does). HP carries across nodes, so this is the number that
## decides whether to take the elite or the shop.
func _run_bar(in_combat: bool) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.SURFACE2
	style.border_color = Palette.LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var col := _vbox(6)
	var diff := GameState._diff()
	var pos: int = int(GameState.run["pos"])
	var total_layers: int = (GameState.run["layers"] as Array).size()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	var cycle_label := (" (cycle %d)" % (int(GameState.run["cycle"]) + 1)) if GameState.run.get("endless", false) else ""
	top.add_child(_label("%s%s" % [diff["name"], cycle_label], 16))
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	for li in total_layers:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(10, 10)
		pip.color = Palette.EMBER_BRIGHT if li == pos else (Palette.VIOLET if li < pos else Palette.GUNMETAL_DEEP)
		pips.add_child(pip)
	var pip_wrap := CenterContainer.new()
	pip_wrap.add_child(pips)
	top.add_child(pip_wrap)
	var tags: Array[String] = []
	var rank: String = str(GameState.run.get("rift_rank", ""))
	if rank != "":
		tags.append("Rank %s" % rank)
	if GameState.run.get("hardcore", false):
		tags.append("Hardcore")
	if not GameState.active_incense.is_empty():
		tags.append(str(GameState.active_incense["name"]))
	if int(GameState.run.get("shield", 0)) > 0:
		tags.append("Relic ward %d" % int(GameState.run["shield"]))
	if not tags.is_empty():
		top.add_child(_label(" · ".join(tags), 12, true))
	# Retreat lives up here, out of the way, and asks once before ending the
	# run (it used to be a big button at the bottom of every node). In combat
	# the command bar has its own.
	if not in_combat and GameState.run.get("sealed") == null:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(spacer)
		if _confirm_retreat:
			var q := _label("Leave the rift? You keep your loot but earn no Seal Tokens.", 12)
			q.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
			top.add_child(q)
			top.add_child(_icon_domain_button("ember", "res://assets/skills/wing.png", "Leave rift", func():
				_confirm_retreat = false
				GameState.retreat_now()
				screen = "terminal"
				render()
			))
			top.add_child(_button("Stay", func(): _confirm_retreat = false; render()))
		else:
			var rb := _icon_button("res://assets/skills/wing.png", "Retreat", func(): _confirm_retreat = true; render())
			rb.tooltip_text = "Leave the rift now — keep your loot, no Seal Tokens"
			top.add_child(rb)
	col.add_child(top)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	if not in_combat:
		for h in GameState.current_party():
			var hv := _vbox(2)
			var hrow := HBoxContainer.new()
			hrow.add_theme_constant_override("separation", 4)
			var portrait := GameData.portrait_for_hero(h.cls_id, h.pool_id)
			if portrait != "":
				var pic := _icon_trimmed(portrait, 28)
				if h.hp <= 0 or h.is_downed():
					pic.modulate = Color(1, 1, 1, 0.35)
				hrow.add_child(pic)
			var nv := _vbox(0)
			nv.add_child(_label(h.name.split(" the ")[0] + (" (C)" if h.is_champion else ""), 10))
			nv.add_child(_label("%d/%d%s" % [max(0, h.hp), Combat.max_hp(h), " · down" if h.hp <= 0 or h.is_downed() else ""], 9, true))
			hrow.add_child(nv)
			hv.add_child(hrow)
			hv.add_child(_hp_bar(h.hp, Combat.max_hp(h), 70.0))
			bottom.add_child(hv)
	var relics := Combat.equipped_relics()
	if not relics.is_empty():
		var rrow := HBoxContainer.new()
		rrow.add_theme_constant_override("separation", 3)
		for r in relics:
			var ricon := _icon(GameData.RELIC_TYPE_ICON_PATH.get(r.type, GameData.CHEST_ICON_PATH), 22)
			ricon.mouse_filter = Control.MOUSE_FILTER_PASS
			ricon.tooltip_text = "%s — %s" % [_loot_display_name(r), _loot_desc(r, true)]
			rrow.add_child(ricon)
		if in_combat:
			top.add_child(rrow)
		else:
			bottom.add_child(rrow)
	if bottom.get_child_count() > 0:
		col.add_child(bottom)
	panel.add_child(col)
	return panel


func _render_rift_run(v: VBoxContainer) -> void:
	if GameState.run.is_empty():
		screen = "terminal"
		render()
		return
	if GameState.run.get("is_riftbreak", false):
		var rb_label := _label("⚠ Riftbreak! An unaddressed rift's threat has spilled out and forced this fight.", 14)
		rb_label.add_theme_color_override("font_color", Palette.HAZARD)
		v.add_child(rb_label)
		var rb_flavor := str(GameState.run.get("riftbreak_flavor", ""))
		if rb_flavor != "":
			v.add_child(_label(rb_flavor, 12, true))
	var kind := GameState.current_node_kind()
	v.add_child(_run_bar(kind in ["combat", "boss", "elite"]))
	# The battle screen already shows every hero's HP twice over (arena
	# nameplates + the action menu) and has its own Retreat button — repeating
	# a third party-HP list and a second Retreat button above/below it just
	# forced extra scrolling to reach the actual action buttons every round.
	# The path map is hidden here too — it's one more thing to scroll past
	# on a screen that's already the most cramped in the game.
	var is_combat_kind := kind in ["combat", "boss", "elite"]
	if not is_combat_kind:
		_render_rift_map(v)

	var sealed = GameState.run.get("sealed")
	if sealed != null:
		var sealed_dict: Dictionary = sealed
		var sealed_row := HBoxContainer.new()
		sealed_row.add_child(_icon(GameData.CHEST_ICON_PATH, 28))
		var stone_tier: String = str(sealed_dict.get("got_stone", ""))
		sealed_row.add_child(_label("Rift Sealed! +%d Seal Tokens%s%s%s" % [
			int(sealed_dict["tokens"]),
			" (fast clear)" if sealed_dict.get("fast_clear", false) else "",
			" · Rift Detector found!" if sealed_dict.get("got_detector", false) else "",
			" · %s-Rank Evolution Stone found!" % stone_tier if stone_tier != "" else "",
		]))
		v.add_child(sealed_row)
		var bounty: Dictionary = sealed_dict.get("bounty", {})
		if not bounty.is_empty():
			v.add_child(_label("Bounty claimed: +%d Coins, +%d Reputation" % [int(bounty.get("coins", 0)), int(bounty.get("reputation", 0))], 12, true))
		if str(sealed_dict.get("flavor", "")) != "":
			v.add_child(_label(str(sealed_dict["flavor"]), 12, true))
		if sealed_dict.get("continuing", false):
			v.add_child(_label("Endless cycle %d begins..." % int(sealed_dict["cycle"])))
			v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["confirm"], "Continue Endless Run", func():
				GameState.continue_endless()
				render()
			))
		else:
			for line in _run_summary_lines():
				v.add_child(_label(line, 12, true))
			v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["confirm"], "Return to Terminal", func():
				GameState.finish_run()
				screen = "terminal"
				render()
			))
		return

	if not is_combat_kind:
		v.add_child(_hsep())
		_render_mid_rift_gear(v)
		v.add_child(_hsep())

	# An unresolved fork (kind == "") is now chosen directly on the path map
	# rendered above — its two options are clickable node markers right
	# there, so there's nothing further to render here until a pick is made.
	match kind:
		"combat", "boss", "elite": _render_combat_node(v)
		"shop": _render_shop_node(v)
		"hazard": _render_hazard_node(v)
		"campfire": _render_campfire_node(v)
		"event": _render_event_node(v)
		"treasure": _render_treasure_node(v)



## The 3 shop offers as an icon-forward card grid instead of stacked
## full-width text rows — each card leads with a large item/relic icon
## (matching a typical shop-stall layout) with name/desc/price underneath.
func _render_shop_node(v: VBoxContainer) -> void:
	GameState.ensure_shop_offers()
	var ns: Dictionary = GameState.run["node_state"]
	v = _node_split(v, GameData.SHOP_BG)
	var offers: Array = ns["offers"]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(_label("Rift Hallway Shop", 18))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var cost := GameState.shop_reroll_cost()
	var reroll := _icon_button(GameData.BUTTON_ICON_PATH["dice"], "Reroll offers (%dc)" % cost, func():
		GameState.reroll_shop()
		render()
	)
	reroll.tooltip_text = "Replace every offer you haven't bought. Costs more each time."
	reroll.disabled = GameState.coins < cost or offers.all(func(o): return o.get("bought", false))
	head.add_child(reroll)
	v.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var party := GameState.current_party()
	for i in offers.size():
		var off: Dictionary = offers[i]
		var obj = off["obj"]
		var is_relic: bool = off["loot_type"] == "relic"
		var desc: String = _loot_desc(obj, is_relic)
		var bought: bool = off.get("bought", false)
		var icon_path: String = GameData.RELIC_TYPE_ICON_PATH[obj.type] if is_relic else GameData.item_icon(obj)

		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanelViolet"
		card.custom_minimum_size.x = 260
		var cv := _vbox(4)
		var icon_wrap := CenterContainer.new()
		icon_wrap.add_child(_icon(icon_path, 40))
		cv.add_child(icon_wrap)
		var nl := _label(_loot_display_name(obj), 14)
		nl.add_theme_color_override("font_color", ITEM_RARITY_COLOR.get(str(obj.rarity), Palette.TEXT))
		cv.add_child(nl)
		cv.add_child(_wrap_label(desc, 12, true))
		# Who it's for (hover an item to compare it with that hero's gear).
		var note := _loot_fit_note(obj, is_relic, party)
		if not is_relic:
			_rich_tip(card, _item_card(obj, note[2]))
		var fl := _wrap_label(str(note[0]), 12)
		fl.add_theme_color_override("font_color", note[1])
		cv.add_child(fl)
		if bought:
			cv.add_child(_label("Bought", 12, true))
		else:
			var buy := _icon_domain_button("ember", GameData.CURRENCY_ICON_PATH["coins"], "Buy — %dc" % int(off["price"]), func(idx=i):
				GameState.buy_shop_offer(idx)
				render()
			)
			buy.disabled = GameState.coins < int(off["price"])
			cv.add_child(buy)
		card.add_child(cv)
		grid.add_child(card)
	v.add_child(grid)
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["confirm"], "Continue", func():
		GameState.advance_node()
		render()
	))


## Hazard severity reads purely off dmg_mult (the one number that already
## drives how much this hazard actually hurts) — under 1.0 means the hazard
## is net-favorable to push through, up to +15% is a normal risk, anything
## higher is a real spike worth pausing on.
func _hazard_severity_color(dmg_mult: float) -> Color:
	if dmg_mult < 1.0:
		return Palette.RANK_E
	elif dmg_mult <= 1.15:
		return Palette.EMBER_BRIGHT
	return Palette.HAZARD


func _hazard_severity_label(dmg_mult: float) -> String:
	if dmg_mult < 1.0:
		return "Mild"
	elif dmg_mult <= 1.15:
		return "Moderate"
	return "Severe"


func _node_continue(v: VBoxContainer) -> void:
	v.add_child(_icon_domain_button("violet", GameData.BUTTON_ICON_PATH["confirm"], "Continue", func():
		GameState.advance_node()
		render()
	))


func _node_log(v: VBoxContainer, ns: Dictionary) -> void:
	for line in ns.get("log", []):
		v.add_child(_wrap_label(str(line), 13))


## Campfire: three one-off choices, each saying exactly what it does.
func _render_campfire_node(v: VBoxContainer) -> void:
	var ns: Dictionary = GameState.run["node_state"]
	v = _node_split(v, GameData.CAMP_BG)
	v.add_child(_label("Campfire", 18))
	if ns.get("resolved", false):
		_node_log(v, ns)
		_node_continue(v)
		return
	v.add_child(_wrap_label("A sheltered corner of the rift. There's time for one thing before moving on.", 13, true))
	var party := GameState.current_party().filter(func(h): return h.hp > 0)
	var hurt := party.filter(func(h): return h.hp < Combat.max_hp(h))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_hazard_option("res://assets/skills/heart.png", "Rest",
		["Every hero heals %d%% HP" % int(GameData.CAMPFIRE_HEAL_PCT * 100), "%d of %d hurt right now" % [hurt.size(), party.size()]], [],
		func(): GameState.campfire_choose("rest"); render()))
	row.add_child(_hazard_option("res://assets/skills/star.png", "Train",
		["Every hero gains %d XP" % GameData.CAMPFIRE_TRAIN_XP], [],
		func(): GameState.campfire_choose("train"); render()))
	var cooling := party.filter(func(h): return h.ability_cooldown > 0).size()
	row.add_child(_hazard_option("res://assets/skills/sword_silver.png", "Sharpen",
		["Every ability is ready for the next fight", "%d on cooldown right now" % cooling], [],
		func(): GameState.campfire_choose("sharpen"); render()))
	v.add_child(row)


## Event: the scene, then one card per choice with its outcome spelled out.
func _render_event_node(v: VBoxContainer) -> void:
	GameState.ensure_event()
	var ns: Dictionary = GameState.run["node_state"]
	var ev: Dictionary = ns["event"]
	v = _node_split(v, "res://assets/screens/riftpath_bg.png")
	v.add_child(_label(str(ev["name"]), 18))
	v.add_child(_wrap_label(str(ev["text"]), 13, true))
	if ns.get("resolved", false):
		_node_log(v, ns)
		_node_continue(v)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var choices: Array = ev["choices"]
	for i in choices.size():
		var c: Dictionary = choices[i]
		var afford := GameState.can_afford(c.get("cost", {}))
		var lines: Array = [str(c["desc"])]
		if not afford:
			lines.append("You can't afford this")
		row.add_child(_hazard_option(GameData.BUTTON_ICON_PATH["dice"] if c.has("gamble") else GameData.BUTTON_ICON_PATH["confirm"], str(c["label"]),
			lines, [], func(idx=i): GameState.resolve_event(idx); render(), not afford))
	v.add_child(row)


## Treasure: pick one of two drops (same cards as a victory reward).
func _render_treasure_node(v: VBoxContainer) -> void:
	GameState.ensure_treasure()
	var ns: Dictionary = GameState.run["node_state"]
	v = _node_split(v, GameData.INVENTORY_BG)
	v.add_child(_label("Treasure", 18))
	if ns.get("picked", false):
		v.add_child(_label("You take your pick and pack it away.", 13, true))
		_node_continue(v)
		return
	v.add_child(_wrap_label("A forgotten stash. There's only room to carry one of these.", 13, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var options: Array = ns["options"]
	for i in options.size():
		var opt: Dictionary = options[i]
		var obj = opt["obj"]
		var is_relic: bool = opt["loot_type"] == "relic"
		var icon_path: String = GameData.RELIC_TYPE_ICON_PATH[obj.type] if is_relic else GameData.item_icon(obj)
		var note := _loot_fit_note(obj, is_relic, GameState.current_party())
		row.add_child(_reward_tile(icon_path, _loot_display_name(obj), str(obj.rarity), _loot_desc(obj, is_relic), func(idx=i):
			GameState.pick_treasure(idx)
			render()
		, "" if is_relic else _item_card(obj, note[2]), note))
	v.add_child(row)


## Shop and hazard nodes: the node's art on the left at its own 320x200
## shape, the choices beside it — everything on screen without scrolling.
## Returns the right-hand column to build into.
func _node_split(v: VBoxContainer, art_path: String) -> VBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var art := _banner(art_path, 320, 200)
	art.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(art)
	var right := _vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	v.add_child(row)
	return right


func _hazard_damage_text(pv: Dictionary) -> String:
	if pv["anchor"]:
		return "Your Anchor Artifact blocks it — no damage"
	if int(pv["total"]) <= 0:
		return "No damage (fully warded)"
	var t := "%d damage, about %d per hero" % [int(pv["total"]), int(pv["per_hero"])]
	if int(pv["absorbed"]) > 0:
		t += " (wards absorb %d)" % int(pv["absorbed"])
	return t


## One hazard choice: its button, what it does, and a red warning naming
## anyone it would knock out.
func _hazard_option(icon_path: String, title: String, lines: Array, downs: Array, cb: Callable, disabled: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 260
	var cv := _vbox(6)
	var b := _icon_button(icon_path, title, cb)
	b.size_flags_horizontal = Control.SIZE_FILL
	b.disabled = disabled
	cv.add_child(b)
	for line in lines:
		cv.add_child(_wrap_label(str(line), 12, disabled))
	if not downs.is_empty():
		var w := _wrap_label("Knocks out: %s" % ", ".join(downs), 12)
		w.add_theme_color_override("font_color", Palette.HAZARD)
		cv.add_child(w)
	card.add_child(cv)
	return card


## "Gear Up" toggle on non-combat rift nodes (shop/hazard/fork) — same
## weapon/gear paper-doll widgets as the Roster tab, scoped to the current
## party, so newly bought/found loot can go on before the next fight instead
## of forcing a Retreat (which ends the run) to reach the Inventory tab.
func _render_mid_rift_gear(v: VBoxContainer) -> void:
	v.add_child(_icon_button("res://assets/skills/armor_chest.png", "Hide Gear" if rift_gear_open else "Gear Up", func():
		rift_gear_open = not rift_gear_open
		render()
	))
	if not rift_gear_open:
		return
	for h in GameState.current_party():
		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanelViolet"
		var cv := _vbox(4)
		cv.add_child(_label(h.name, 13))
		var weapon_row := HBoxContainer.new()
		weapon_row.add_theme_constant_override("separation", 8)
		for i in GameData.weapon_slots(h.pool_id):
			weapon_row.add_child(_equip_slot_frame(h, "weapon", i))
		cv.add_child(weapon_row)
		if expanded_slot.begins_with("%s:weapon:" % h.id):
			_render_equip_picker(cv, h, "weapon", int(expanded_slot.split(":")[2]))
		var gear_row := HBoxContainer.new()
		gear_row.add_theme_constant_override("separation", 8)
		for i in GameData.gear_slots(h.rank):
			gear_row.add_child(_equip_slot_frame(h, "gear", i))
		cv.add_child(gear_row)
		if expanded_slot.begins_with("%s:gear:" % h.id):
			_render_equip_picker(cv, h, "gear", int(expanded_slot.split(":")[2]))
		card.add_child(cv)
		v.add_child(card)


func _render_hazard_node(v: VBoxContainer) -> void:
	GameState.ensure_hazard()
	var ns: Dictionary = GameState.run["node_state"]
	var hz: Dictionary = ns["hazard"]
	var bg_path: String = GameData.HAZARD_BG.get(str(hz["id"]), "")
	if bg_path != "":
		v = _node_split(v, bg_path)

	var dmg_mult: float = float(hz["dmg_mult"])
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(_label(str(hz["name"]), 16))
	var sev_label := _label(_hazard_severity_label(dmg_mult), 12)
	sev_label.add_theme_color_override("font_color", _hazard_severity_color(dmg_mult))
	name_row.add_child(sev_label)
	v.add_child(name_row)

	if not ns.get("resolved", false):
		# Each choice spells out exactly what it does (the damage is fixed,
		# so GameState.hazard_preview is the real number, not an estimate).
		var bonus_pct := int(round(float(hz["bonus_chance"]) * 100.0))
		var bonus_kind := "Coins" if str(hz["bonus_type"]) == "coins" else "Crystals"
		var push := GameState.hazard_preview(1.0)
		var risk := GameState.hazard_preview(2.0)
		var choice_row := HBoxContainer.new()
		choice_row.add_theme_constant_override("separation", 10)
		choice_row.add_child(_hazard_option("res://assets/skills/boots.png", "Push Through",
			[_hazard_damage_text(push), "%d%% chance of 2-6 %s" % [bonus_pct, bonus_kind]], push["downs"],
			func(): GameState.push_through_hazard(); render()))
		choice_row.add_child(_hazard_option(GameData.CURRENCY_ICON_PATH["crystals"], "Bypass",
			["No damage, no reward", "Costs %d Crystals (you have %d)" % [GameState.HAZARD_BYPASS_COST, GameState.crystals]], [],
			func(): GameState.bypass_hazard(); render(), not GameState.can_afford_hazard_bypass()))
		choice_row.add_child(_hazard_option(GameData.BUTTON_ICON_PATH["dice"], "Risk it for Loot",
			[_hazard_damage_text(risk), "Guaranteed 2-6 %s" % bonus_kind], risk["downs"],
			func(): GameState.risk_hazard(); render()))
		v.add_child(choice_row)
	else:
		for line in ns.get("log", []):
			v.add_child(_label(str(line), 12))
		v.add_child(_icon_domain_button("violet", GameData.BUTTON_ICON_PATH["confirm"], "Continue", func():
			GameState.advance_node()
			render()
		))
