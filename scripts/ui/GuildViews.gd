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
	var tier_line := "%s — %d levels purchased" % [tier["name"], tier["total"]]
	if not tier["next"].is_empty():
		tier_line += " (%d to %s)" % [int(tier["next"]["min"]) - int(tier["total"]), tier["next"]["name"]]
	var tier_row := HBoxContainer.new()
	tier_row.add_theme_constant_override("separation", 6)
	var tier_icon_path: String = GameData.GUILD_TIER_ICON.get(str(tier["name"]), "")
	if tier_icon_path != "":
		tier_row.add_child(_icon(tier_icon_path, 18))
	tier_row.add_child(_label(tier_line, 12, true))

	if term_tab == "camp":
		_render_camp(v)
		v.add_child(tier_row)
		return

	match term_tab:
		"inventory": _render_inventory(v)
		"recruits": _render_recruits(v)
		"medical": _render_medical_bay(v)
		"management": _render_management(v)
		"bestiary": _render_bestiary(v)
		"compendium": _render_compendium(v)
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
	var SCENE_SIZE := Vector2(scene_w, roundf(scene_w * 157.0 / 400.0))
	var scene := Control.new()
	scene.custom_minimum_size = SCENE_SIZE

	var bg := TextureRect.new()
	bg.texture = load(GameData.CAMP_BG)
	bg.custom_minimum_size = SCENE_SIZE
	bg.size = SCENE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)
	_start_daynight_cycle(bg)

	# Rect positions hand-picked against camp_bg.png's native 400x157 canvas
	# (cropped from the original 400x184 generation, which had a literal
	# cinematic letterbox band baked into the top/bottom ~15px — an artifact
	# of asking PixelLab for a "cinematic" shot; cropping it out is what fixed
	# the flame and buildings reading as cut off along the top edge), scaled
	# up to SCENE_SIZE below. Command Tent/Rift Gate/Trading Post/Scholar's
	# Lodge each cover several destinations and set hub_cluster instead of
	# navigating directly.
	var area_entries := [
		["Scholar's Lodge", Rect2(0, 80, 90, 60), func(): hub_cluster = "scholars_lodge"; render()],
		["Medical Tent", Rect2(90, 75, 105, 65), func(): term_tab = "medical"; render()],
		["Hero Recruits", Rect2(185, 80, 55, 73), func(): term_tab = "recruits"; render()],
		["Rift Gate", Rect2(235, 60, 63, 87), func(): hub_cluster = "rift_gate"; render()],
		["Trading Post", Rect2(298, 80, 60, 60), func(): hub_cluster = "trading_post"; render()],
		["Command Tent", Rect2(358, 60, 42, 80), func(): hub_cluster = "command"; render()],
	]
	var scene_scale := SCENE_SIZE / Vector2(400, 157)
	var badges := _camp_badges()
	var plaques: Array = []
	for entry in area_entries:
		var label_text: String = entry[0]
		var native_rect: Rect2 = entry[1]
		var cb: Callable = entry[2]
		var rect := Rect2(
			native_rect.position.x * scene_scale.x, native_rect.position.y * scene_scale.y,
			native_rect.size.x * scene_scale.x, native_rect.size.y * scene_scale.y
		)
		var hotspot := _camp_area_hotspot(rect, rect, label_text, cb, false)
		hotspot.position = rect.position
		scene.add_child(hotspot)
		plaques.append([label_text, rect])

	# Name plaques along the bottom edge of each building, added after every
	# hotspot so no building's hover area paints over a neighbour's plaque.
	for pq in plaques:
		var prect: Rect2 = pq[1]
		var plaque := _camp_plaque(str(pq[0]))
		plaque.position = Vector2(prect.get_center().x - plaque.size.x * 0.5, minf(prect.end.y - 6.0, SCENE_SIZE.y - plaque.size.y - 4.0))
		scene.add_child(plaque)
		var badge: Array = badges.get(str(pq[0]), [])
		if not badge.is_empty():
			var chip := _count_badge(str(badge[0]), str(badge[1]))
			chip.position = plaque.position + Vector2(plaque.size.x - 10.0, -12.0)
			scene.add_child(chip)

	# Pixel-scanned against camp_bg.png directly (flame-colored pixels cluster
	# at x:189-223, y:106-130 on the native 400x157 canvas) — previously
	# reused the Hero Recruits hotspot rect, which happens to overlap the
	# fire horizontally but put the emitter ~15px below the flame's own
	# bottom edge, in the log pile instead of the fire.
	var fire_native_pos := Vector2(206, 112)
	_start_ember_loop(scene, fire_native_pos * scene_scale)
	v.add_child(scene)


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
		out["Command Tent"] = [str(needy.size()), "\n".join(needy)]
	var hurt := GameState.heroes.filter(func(h): return GameState.needs_recovery(h) and not h.bedded)
	if not hurt.is_empty():
		out["Medical Tent"] = [str(hurt.size()), "%d hero(es) wounded or downed" % hurt.size()]
	if GameState.heroes.size() < GameState.hero_slot_cap():
		var affordable := GameState.recruit_pool.filter(func(h): return GameState.coins >= int(GameData.find_rank(h.rank)["cost"]))
		if not affordable.is_empty():
			out["Hero Recruits"] = [str(affordable.size()), "%d recruit(s) you can afford" % affordable.size()]
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
		out["Trading Post"] = [str(craftable), "%d craft(s) ready at the Crafting Hall" % craftable]
	var claimable := GameState.guild_board.filter(func(q): return GameState.quest_progress(q) >= int(q["target"]))
	if not claimable.is_empty():
		out["Scholar's Lodge"] = [str(claimable.size()), "%d Guild Board quest(s) ready to claim" % claimable.size()]
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
	for entry in entries:
		row.add_child(_hub_card(entry[0], entry[1], entry[2]))
	v.add_child(row)


func _render_recruits(v: VBoxContainer) -> void:
	var champ := GameState.ensure_champion()
	var champ_row := HBoxContainer.new()
	champ_row.add_theme_constant_override("separation", 10)
	champ_row.add_child(_framed_portrait(champ.cls_id, champ.pool_id, 56.0))
	var champ_mid := _vbox(2)
	champ_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	champ_mid.add_child(_label("Champion: %s" % champ.name, 13))
	champ_mid.add_child(_label("Rank %s · always joins free" % champ.rank, 11, true))
	champ_row.add_child(champ_mid)
	champ_row.add_child(_button("Reroll (%dc)" % GameData.CHAMPION_REROLL_COST, func():
		var err := GameState.reroll_champion()
		if err != "":
			push_warning(err)
		render()
	))
	v.add_child(champ_row)
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
	v.add_child(_wrap_label("Rank odds: %s%s" % [GameData.rank_odds_text(), "  ·  Headhunter Guarantee active (a C+ recruit is assured each refresh)" if GameState.headhunter_guarantee() else ""], 11, true))
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
		row.add_child(_button("Reroll (%dc)" % GameData.RECRUIT_REROLL_COST, func(id=h.id):
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
		v.add_child(_icon_button("res://assets/skills/heart.png", "Field Triage (heal whole roster, once per rift cycle)%s" % ("" if not GameState.triage_used_this_cycle else " [used]"), func():
			var err := GameState.field_triage_action()
			if err != "":
				push_warning(err)
			render()
		))

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
func _render_bestiary(v: VBoxContainer) -> void:
	v.add_child(_label("Bestiary", 20))

	v.add_child(_label("Monsters", 14, true))
	var monster_row := HBoxContainer.new()
	monster_row.add_theme_constant_override("separation", 8)
	for mname in GameData.MONSTER_NAMES + GameData.ELITE_NAMES:
		var seen: bool = GameState.monsters_seen.has(mname)
		var icon := _icon(GameData.sprite_for_monster(mname), 40)
		if not seen:
			icon.modulate = Color(0.25, 0.25, 0.25, 1.0)
		var wrap := _wrap_icon(icon)
		wrap.tooltip_text = mname if seen else "???"
		monster_row.add_child(wrap)
	v.add_child(monster_row)

	v.add_child(_hsep())
	v.add_child(_label("Bosses", 14, true))
	var boss_row := HBoxContainer.new()
	boss_row.add_theme_constant_override("separation", 8)
	for bname in GameData.BOSS_NAMES:
		var defeated: bool = GameState.bosses_defeated.has(bname)
		var bicon := _icon(GameData.sprite_for_monster(bname), 40)
		if not defeated:
			bicon.modulate = Color(0.25, 0.25, 0.25, 1.0)
		var bwrap := _wrap_icon(bicon)
		bwrap.tooltip_text = bname if defeated else "???"
		boss_row.add_child(bwrap)
	v.add_child(boss_row)

	v.add_child(_hsep())
	v.add_child(_label("Hazards", 14, true))
	var hazard_row := HBoxContainer.new()
	hazard_row.add_theme_constant_override("separation", 8)
	for hz in GameData.HAZARD_TYPES:
		var hz_id := str(hz["id"])
		var seen: bool = GameState.hazards_seen.has(hz_id)
		var hicon := _icon(GameData.HAZARD_BG.get(hz_id, ""), 40)
		if not seen:
			hicon.modulate = Color(0.25, 0.25, 0.25, 1.0)
		var hwrap := _wrap_icon(hicon)
		hwrap.tooltip_text = str(hz["name"]) if seen else "???"
		hazard_row.add_child(hwrap)
	v.add_child(hazard_row)


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
		["Guild Management", "Spend Crystals across 4 branches (Operations/Infrastructure/Logistics/Research) to raise hero-slot caps, relic-slot caps, recovery speed, fee reductions, and more. A Guild Tier banner tracks total levels purchased."],
		["Rift Map & Riftbreak", "6 rifts rotate on the map, each with a rank (F through SSS) and a countdown — higher rank means a shorter fuse. An unaddressed rift Riftbreaks, forcing an encounter (or a resource penalty) the next time you return to the Terminal."],
		["Hero Bonds", "Certain subclass pairs (e.g. Duelist + Blade-Dancer) grant a bonus while both are alive in the active party — shown in Party Assembly when both halves are picked."],
		["Party Synergy", "Resonance: 2+ party members currently building the same skill kind reinforce each other. Eclectic: a 3+ party with no kind repeated gets a small universal bonus instead. Never both at once — shown in Party Assembly."],
		["Ability Awakening", "Spend Skill Points once to grant a hero's Active Ability a secondary effect (varies by ability — a shorter cooldown, a lingering debuff, a party dodge boost, a self-shield, or a small permanent damage stack) instead of only ever growing the skill tree's numbers."],
		["Elemental Weakness", "Every hero subclass and every monster carries one of 5 elemental types. Attacking a weak-matched type deals bonus damage; attacking a strong-matched type deals less."],
		["Formation", "Heroes and monsters can sit front or back row. Retaliation is biased toward the front row; back-row monsters take reduced damage from hero attacks."],
		["Bestiary", "Every monster, boss, and hazard you've encountered is tracked as a silhouette-to-full-color reveal — pure record-keeping, no reward tied to completion."],
		["Hero Scars", "A knocked-out hero has a chance to pick up a lasting scar (mild stat penalty) on top of their base trait, up to 2 at once. Scrubbed the same way as a trait, once unlocked."],
		["Greater Rift", "Unlocked after sealing 3 rifts of any kind — a new difficulty tier between Lesser and Endless."],
		["Guild Board & Milestones", "Contracts and Dailies are quick rotating objectives paying Coins/Crystals/Tokens/Reputation. Milestones are a static checklist, auto-granted the moment they're met. Reputation occasionally arms a guaranteed Epic relic at the next Shop. Rift Map rifts occasionally carry a bounty, paid out when that specific rift is cleared. A rare escort NPC can also tag along on a fight — surviving pays a small bonus."],
	]
	for entry in entries:
		v.add_child(_label(str(entry[0]), 15))
		v.add_child(_wrap_label(str(entry[1]), 12, true))
		v.add_child(_hsep())


# ---------------- Quests: Guild Board & Milestones ----------------
func _render_quests(v: VBoxContainer) -> void:
	v.add_child(_label("Guild Board", 20))
	v.add_child(_wrap_label("Contracts are quick and modest. Dailies are tougher with bigger rewards, including Reputation — every 20 Reputation arms a guaranteed Epic relic at your next Shop.", 12, true))
	v.add_child(_hsep())
	for q in GameState.guild_board:
		var progress := GameState.quest_progress(q)
		var target := int(q["target"])
		var done := progress >= target
		var text := "[%s] %s\nReward: %s" % [str(q["tier"]).capitalize(), GameState.quest_desc(q), GameState.quest_reward_desc(q["reward"])]
		# Unfinished: a progress bar. Finished: a Claim button — no greyed
		# "In Progress" button that read as already done.
		var status: Control
		if done:
			status = _icon_domain_button("ember", GameData.BUTTON_ICON_PATH["confirm"], "Claim", func(qid=str(q["id"])):
				GameState.claim_quest(qid)
				render()
			)
		else:
			var pv := _vbox(2)
			pv.custom_minimum_size.x = 140
			pv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var pl := _label("%d / %d" % [min(progress, target), target], 12, true)
			pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			pv.add_child(pl)
			pv.add_child(_flat_bar(target, min(progress, target), 140, 6, Palette.VIOLET_BRIGHT))
			status = pv
		var actions: Array[Control] = [status]
		v.add_child(_info_row(text, 13, actions))
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
	var cv := _vbox(4)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	if icon_path != "":
		header.add_child(_icon(icon_path, 28))
	header.add_child(_label(str(n["name"]), 13))
	cv.add_child(header)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = node_max
	bar.value = cur
	bar.show_percentage = false
	bar.custom_minimum_size.y = 10
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Palette.SURFACE
	bar_bg.corner_radius_top_left = 4
	bar_bg.corner_radius_top_right = 4
	bar_bg.corner_radius_bottom_left = 4
	bar_bg.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("background", bar_bg)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Palette.VIOLET_BRIGHT if maxed else Palette.VIOLET
	bar_fill.corner_radius_top_left = 4
	bar_fill.corner_radius_top_right = 4
	bar_fill.corner_radius_bottom_left = 4
	bar_fill.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("fill", bar_fill)
	cv.add_child(bar)
	cv.add_child(_label("Level %d/%d" % [cur, node_max], 11, true))

	var cur_desc := Combat.describe_node_effect(n["id"], cur)
	cv.add_child(_wrap_label(cur_desc, 11))
	if not maxed:
		cv.add_child(_wrap_label("Next: %s" % Combat.describe_node_effect(n["id"], cur + 1), 11, true))

	if not maxed:
		var cost: int = int(n["cost_base"]) + int(n["cost_step"]) * cur
		cv.add_child(_icon_button(icon_path, "Upgrade (%dcr)" % cost, func(k=key):
			var err := GameState.upgrade_node(k)
			if err != "":
				push_warning(err)
			render()
		))
	var cap: Dictionary = n.get("cap", {})
	if not cap.is_empty() and maxed and not GameState.has_cap(key):
		cv.add_child(_icon_button(icon_path, "%s (%dcr) — %s" % [cap["name"], int(cap["cost"]), cap["desc"]], func(k=key):
			var err := GameState.buy_cap(k)
			if err != "":
				push_warning(err)
			render()
		))
	elif not cap.is_empty() and GameState.has_cap(key):
		cv.add_child(_label("%s unlocked" % cap["name"], 12))

	card.add_child(cv)
	return card
