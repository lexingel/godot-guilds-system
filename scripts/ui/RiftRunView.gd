class_name RiftRunView
extends RosterView
## Inside a rift: the path map, combat arena + turn animations, shop and
## hazard nodes, and the mid-rift Gear Up panel.

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

	const MAP_SIZE := Vector2(900, 140)
	var map_ctrl := Control.new()
	map_ctrl.custom_minimum_size = MAP_SIZE

	var bg := TextureRect.new()
	bg.texture = load("res://assets/screens/riftpath_bg.png")
	bg.custom_minimum_size = MAP_SIZE
	bg.size = MAP_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map_ctrl.add_child(bg)

	var n := layers.size()
	var margin := 40.0
	var step: float = (MAP_SIZE.x - margin * 2.0) / float(max(1, n - 1))
	var base_y := MAP_SIZE.y * 0.55
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
		num.position = Vector2(anchors[i].x - 4, MAP_SIZE.y - 16)
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
	if pos < n and (layers[pos]["options"] as Array).size() > 1 and not chosen.has(pos):
		v.add_child(_label("Choose your path — click a node above.", 12, true))


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
	top.add_child(_label("Node %d/%d" % [pos + 1, total_layers], 12, true))
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
		top.add_child(_label(" · ".join(tags), 11, true))
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

	if not is_combat_kind:
		v.add_child(_hsep())
		v.add_child(_icon_button("res://assets/skills/wing.png", "Retreat (keep loot, no Seal Tokens)", func():
			GameState.retreat_now()
			screen = "terminal"
			render()
		))


## A one-shot helper purely so two unrelated signals (an animation's own
## finish signal and a timeout) can be awaited as a race — whichever fires
## first resumes `_await_or_timeout` below.
class _SignalRace:
	extends RefCounted
	signal fired


## Bounds an animation wait to `timeout_sec` of real engine time instead of
## trusting `sig` alone — `sig` (a Tween.finished or SceneTreeTimer.timeout)
## has been observed to simply never fire, which used to wedge
## _combat_animating forever behind the early-return guard on the button,
## making every further click a silent no-op until the page was reloaded.
## A prior version of this guarded by polling get_tree().process_frame in a
## loop, on the theory that process_frame is the one signal that must still
## fire for anything on screen to ever change — but that polling loop itself
## was later caught not resuming (traced via targeted print instrumentation
## live in the web build), stalling every one of its own awaits forever.
## Awaiting a genuine race between `sig` and a SceneTreeTimer via a shared
## one-shot signal sidesteps that: it needs no repeated wakeups of its own,
## just one of the two real signals to ever fire once.
func _await_or_timeout(sig: Signal, timeout_sec: float) -> void:
	var racer := _SignalRace.new()
	var settle := func(): racer.fired.emit()
	sig.connect(settle, CONNECT_ONE_SHOT)
	get_tree().create_timer(timeout_sec).timeout.connect(settle, CONNECT_ONE_SHOT)
	await racer.fired
	if sig.is_connected(settle):
		sig.disconnect(settle)


## Frame-swaps `rect.texture` through `frames` once, a short delay between each.
## No explicit reset to the resting pose needed — the render() call right after
## _run_combat_turns always rebuilds portraits from the static portrait path anyway.
func _play_frames(rect: TextureRect, frames: Array[String], frame_time: float = 0.08) -> void:
	for path in frames:
		# A screen navigation (e.g. opening Settings mid-animation) can free
		# `rect` out from under this still-awaiting coroutine — bail instead
		# of writing to a freed node.
		if not is_instance_valid(rect):
			return
		rect.texture = load(path)
		await _await_or_timeout(get_tree().create_timer(frame_time).timeout, frame_time + 1.0)


## Fallback for the two combos with no usable AI-generated motion (Warrior's
## hurt, Ranger's attack): a quick lunge tween on the existing static portrait.
## Animates position:x specifically (not the whole position) so it doesn't
## fight the idle sway's position:y loop running on the same wrapper.
func _tween_lunge(wrapper: Control) -> void:
	var start_x: float = wrapper.position.x
	var tween := create_tween()
	tween.tween_property(wrapper, "position:x", start_x + 12.0, 0.12)
	tween.tween_property(wrapper, "position:x", start_x, 0.12)
	await _await_or_timeout(tween.finished, 1.0)


func _tween_hurt(wrapper: Control) -> void:
	var start_x: float = wrapper.position.x
	var tween := create_tween()
	tween.tween_property(wrapper, "modulate", Color(1, 0.4, 0.4), 0.08)
	tween.parallel().tween_property(wrapper, "position:x", start_x - 6.0, 0.08)
	tween.chain().tween_property(wrapper, "position:x", start_x + 6.0, 0.08)
	tween.chain().tween_property(wrapper, "position:x", start_x, 0.08)
	tween.parallel().tween_property(wrapper, "modulate", Color(1, 1, 1), 0.24)
	await _await_or_timeout(tween.finished, 1.0)


func _flash_white(wrapper: Control) -> void:
	var tween := create_tween()
	tween.tween_property(wrapper, "modulate", Color(2, 2, 2), 0.06)
	tween.tween_property(wrapper, "modulate", Color(1, 1, 1), 0.18)
	await _await_or_timeout(tween.finished, 1.0)


## Fallback for an Ability use when that role has no "skill" frames: a lunge
## like a plain attack, but with an added bright color flash so it still
## reads as "the special one" rather than an identical basic attack.
func _tween_skill_flash(wrapper: Control) -> void:
	var start_x: float = wrapper.position.x
	var tween := create_tween()
	tween.tween_property(wrapper, "modulate", Color(1.6, 1.4, 2.0), 0.1)
	tween.parallel().tween_property(wrapper, "position:x", start_x + 12.0, 0.12)
	tween.chain().tween_property(wrapper, "position:x", start_x, 0.12)
	tween.parallel().tween_property(wrapper, "modulate", Color(1, 1, 1), 0.2)
	await _await_or_timeout(tween.finished, 1.0)


## Defend has no frame-swap animation at any class — it's a brief, frequent
## action every round rather than the fight's visual centerpiece, so a tween
## on the existing static portrait is the right weight here (same "cheapest
## thing that reads" treatment already used for the lunge/hurt fallbacks).
func _tween_defend(wrapper: Control) -> void:
	var start_y: float = wrapper.position.y
	var tween := create_tween()
	tween.tween_property(wrapper, "position:y", start_y + 5.0, 0.1)
	tween.parallel().tween_property(wrapper, "modulate", Color(0.85, 0.9, 1.1), 0.1)
	tween.tween_interval(0.15)
	tween.tween_property(wrapper, "position:y", start_y, 0.12)
	tween.parallel().tween_property(wrapper, "modulate", Color(1, 1, 1), 0.12)
	await _await_or_timeout(tween.finished, 1.0)


## Played once a hero's hp crosses to 0 this round, right after their hurt
## reaction — desaturates and settles into a slumped resting pose instead of
## snapping back to the idle stance the way a non-lethal hit does. Left in
## this end state deliberately (no return tween): render() builds a fresh,
## un-tinted wrapper for this hero the next time they're actually alive.
func _tween_collapse(wrapper: Control) -> void:
	var start_y: float = wrapper.position.y
	var tween := create_tween()
	tween.tween_property(wrapper, "position:y", start_y + 10.0, 0.25)
	tween.parallel().tween_property(wrapper, "modulate", Color(0.4, 0.4, 0.4, 0.75), 0.3)
	await _await_or_timeout(tween.finished, 1.0)


## Played once, on every surviving hero, the instant a fight resolves as a
## win — a small triumphant beat before render() replaces the arena with the
## victory screen. Finite (not looping), since it only ever plays once.
func _tween_victory_pose(wrapper: Control) -> void:
	var start_y: float = wrapper.position.y
	var tween := create_tween()
	tween.tween_property(wrapper, "position:y", start_y - 10.0, 0.15)
	tween.parallel().tween_property(wrapper, "modulate", Color(1.3, 1.3, 1.1), 0.15)
	tween.tween_property(wrapper, "position:y", start_y, 0.15)
	tween.parallel().tween_property(wrapper, "modulate", Color(1, 1, 1), 0.15)
	await _await_or_timeout(tween.finished, 1.0)


## A short, fire-and-forget colored particle burst at an impact point — not
## awaited by callers, so it plays out in the background without adding to
## _play_turn's own pacing. Reused for both a hero's attack landing on a
## monster and a monster's retaliation landing on a hero; only the color and
## `heavy` (a bigger, faster burst) differ per call site.
func _spawn_impact_particles(parent: Control, pos: Vector2, color: Color, heavy: bool = false) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = false
	p.one_shot = true
	p.amount = 14 if heavy else 8
	p.lifetime = 0.4
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 40.0 if heavy else 24.0
	p.initial_velocity_max = 90.0 if heavy else 55.0
	p.gravity = Vector2(0, 140)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0 if heavy else 3.0
	p.color = color
	parent.add_child(p)
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.1).timeout.connect(p.queue_free)


## A quick jitter on the whole arena — reads as the impact "landing" and
## doubles as a lightweight hit-stop (the brief stillness before it settles
## back is the pause, not a real Engine.time_scale change, which would also
## stall every other tween/await currently in flight). Heavier for a hit
## that cleared 25% of the target's max HP — the same "heavy hit" threshold
## Combat.gd's own retaliation math already uses for counter-attacks.
func _impact_beat(arena: Control, heavy: bool = false) -> void:
	var base: Vector2 = arena.position
	var mag: float = 6.0 if heavy else 3.0
	var tween := create_tween()
	for i in 4:
		var off := Vector2(randf_range(-mag, mag), randf_range(-mag, mag))
		tween.tween_property(arena, "position", base + off, 0.03)
	tween.tween_property(arena, "position", base, 0.03)
	await _await_or_timeout(tween.finished, 1.0)


## A finite (not endless) color pulse marking that a boss's mechanic will
## visibly affect the *next* round — the same moment Combat.describe_incoming's
## text telegraph line covers, just on the monster's own sprite too. 3 cycles
## is enough to be noticed without still running by the time a player has
## read the line and picked an action.
func _start_mechanic_pulse(wrapper: Control, color: Color) -> void:
	var tween := create_tween()
	tween.bind_node(wrapper)
	tween.set_loops(3)
	tween.tween_property(wrapper, "modulate", color, 0.5)
	tween.tween_property(wrapper, "modulate", Color(1, 1, 1), 0.5)


## A gentle, endless breathing/sway loop for a hero or monster wrapper so the
## arena doesn't look frozen between rounds — a small vertical bob rather than
## a scale pulse (scaling pixel art by fractional amounts shimmers/aliases
## even with nearest-neighbor filtering, which read as distracting). Uses
## `position` offsets relative to the wrapper's own resting position, and only
## the Y axis, so it doesn't fight the lunge/hurt tweens' X-axis moves (those
## are momentary and both resolve back to the same resting spot). Self-cleans
## up: bind_node() means Godot kills the tween automatically once render()
## frees this wrapper on the next state change, no manual bookkeeping needed.
func _start_idle_sway(wrapper: Control) -> void:
	var rest := wrapper.position
	var tween := create_tween()
	tween.bind_node(wrapper)
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(wrapper, "position:y", rest.y - 3.0, 1.4)
	tween.tween_property(wrapper, "position:y", rest.y, 1.4)


func _spawn_damage_number(wrapper: Control, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", color)
	l.position = Vector2(wrapper.custom_minimum_size.x * 0.5 - 10, -6)
	wrapper.add_child(l)
	var tween := create_tween()
	tween.tween_property(l, "position:y", l.position.y - 24, 0.6)
	tween.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	await _await_or_timeout(tween.finished, 1.5)
	l.queue_free()


## Floats every effect that fired this turn (Combat._proc: "Counter!",
## "Intercept!", a passive or Legendary's name...) over its hero, staggered so
## several procs on one hero stack instead of overlapping. Fire-and-forget:
## never awaited, so it can't hold up the turn's own animation chain.
## Combat hotkeys (see _combat_hotkeys, filled while the action bar builds).
func _unhandled_input(event: InputEvent) -> void:
	if screen != "rift_run" or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := OS.get_keycode_string(event.keycode)
	if _combat_hotkeys.has(key):
		get_viewport().set_input_as_handled()
		_combat_hotkeys[key].call()


func _spawn_procs(state: Dictionary, hero_wrappers: Dictionary) -> void:
	var per_hero := {}
	for p in state.get("_procs", []):
		var wrapper: Control = hero_wrappers.get(str(p["hero"]))
		if wrapper == null or not is_instance_valid(wrapper):
			continue
		var n: int = per_hero.get(p["hero"], 0)
		per_hero[p["hero"]] = n + 1
		var l := _label(str(p["text"]), 13)
		l.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
		l.position = Vector2(-10, -30 - n * 16)
		wrapper.add_child(l)
		var tween := create_tween()
		tween.tween_interval(0.25 * n)
		tween.tween_property(l, "position:y", l.position.y - 20, 1.1)
		tween.parallel().tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.5)
		tween.tween_callback(l.queue_free)


func _spawn_ability_bucket_burst(pool_id: String, wrapper: Control) -> void:
	var ab: Dictionary = GameData.SUBCLASS_ABILITIES.get(pool_id, {})
	var bucket: String = GameData.ABILITY_AWAKENING_BUCKET.get(str(ab.get("effect", "")), "buff")
	var color: Color = ABILITY_BUCKET_COLOR.get(bucket, Color(1, 1, 1))
	_spawn_impact_particles(wrapper, wrapper.custom_minimum_size * 0.5, color, bucket in ["aoe_dmg", "single_dmg"])


func _hero_by_id(party: Array[Hero], hero_id: String) -> Hero:
	for h in party:
		if h.id == hero_id:
			return h
	return null


## A compact row of icons for the current round's turn order (see
## Combat._compute_turn_order) — hero portraits and monster sprites in the
## order they'll act, glowing on the current turn, dimmed once already
## spent, so "whose turn is it" reads at a glance above the action bar.
func _turn_order_strip(state: Dictionary) -> Control:
	var turn_order: Array = state.get("turn_order", [])
	var turn_idx: int = int(state.get("turn_idx", 0))
	var party: Array[Hero] = state["party"]
	var monsters: Array = state["monsters"]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	for i in turn_order.size():
		var entry: Dictionary = turn_order[i]
		var is_hero: bool = str(entry["type"]) == "hero"
		var icon_path := ""
		if is_hero:
			var h := _hero_by_id(party, str(entry["id"]))
			if h:
				icon_path = GameData.portrait_for_hero(h.cls_id, h.pool_id)
		else:
			var mi: int = int(entry["id"])
			if mi < monsters.size():
				icon_path = GameData.sprite_for_monster(str(monsters[mi]["name"]))
		if icon_path == "":
			continue
		var is_current := i == turn_idx
		var tile := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Palette.SURFACE3 if is_current else Palette.SURFACE2
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.border_color = Palette.EMBER_BRIGHT if is_current else Palette.LINE
		style.corner_radius_top_left = 5
		style.corner_radius_top_right = 5
		style.corner_radius_bottom_left = 5
		style.corner_radius_bottom_right = 5
		style.content_margin_left = 2
		style.content_margin_top = 2
		style.content_margin_right = 2
		style.content_margin_bottom = 2
		tile.add_theme_stylebox_override("panel", style)
		var icon := _icon_trimmed(icon_path, 28) if is_hero else _icon(icon_path, 28)
		if i < turn_idx:
			icon.modulate = Color(1, 1, 1, 0.35)
		tile.add_child(icon)
		row.add_child(tile)
	return row


## Plays out one turn's visible consequences (see Combat.resolve_turn) on the
## *live* nodes from the current render() pass (portraits/wrappers built
## moments ago in _render_combat_node) before the caller calls render()
## again, which would otherwise tear all of this down mid-animation. Diffs hp
## before/after GameState.resolve_turn_now() to figure out what happened,
## since Combat.resolve_turn doesn't return that directly. Combat.peek_next_turn
## decides which actor this is (rolling a fresh round first if the previous
## one just ran out — that's why this can't be a plain parameter the caller
## peeked earlier: at the moment a round rolls over there's nothing valid to
## peek until this call itself makes it happen).
## Wraps _play_turn with a hard ceiling on the whole turn's animation chain —
## on top of every individual step already being bounded via
## _await_or_timeout, a still-unexplained WASM coroutine-resumption stall was
## observed (live, via targeted print instrumentation) spanning a *whole*
## animation chain rather than any single step within it, well past the sum
## of every step's own bound. The turn's game math is already fully applied
## by the time this is reached (_play_turn calls GameState.resolve_turn_now()
## before any animation), so giving up on the animation here costs the player
## nothing but visual polish for that one turn — it's strictly better than
## leaving _combat_animating (and every action button behind it) stuck true
## forever.
func _play_turn_bounded(state: Dictionary, hero_wrappers: Dictionary, hero_rects: Dictionary, monster_wrappers: Dictionary, monster_rects: Dictionary, arena: Control, timeout_sec: float = 6.0) -> void:
	var racer := _SignalRace.new()
	var run_it := func():
		await _play_turn(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena)
		if is_instance_valid(racer):
			racer.fired.emit()
	run_it.call()
	get_tree().create_timer(timeout_sec).timeout.connect(func():
		if is_instance_valid(racer):
			racer.fired.emit()
	, CONNECT_ONE_SHOT)
	await racer.fired


func _play_turn(state: Dictionary, hero_wrappers: Dictionary, hero_rects: Dictionary, monster_wrappers: Dictionary, monster_rects: Dictionary, arena: Control) -> void:
	var turn: Dictionary = Combat.peek_next_turn(state)
	var party: Array[Hero] = state["party"]
	var monsters: Array = state["monsters"]
	var hp_before: Dictionary = {}
	for h in party:
		hp_before[h.id] = h.hp
	var monster_hp_before: Array = []
	for m in monsters:
		monster_hp_before.append(float(m["hp"]))

	if str(turn.get("type", "")) == "hero":
		var h := _hero_by_id(party, str(turn["id"]))
		var pending: Dictionary = state["pending_actions"]
		var action: String = str(pending.get(str(turn["id"]), {}).get("action", "attack"))

		GameState.resolve_turn_now()
		_spawn_procs(state, hero_wrappers)

		if h == null or h.hp <= 0:
			return   # died earlier this round (e.g. a monster's turn) — the turn was just skipped, nothing to animate

		if hero_wrappers.has(h.id):
			if action == "attack":
				AudioManager.play_sfx(GameData.SFX_PATH["attack"])
				var frames := GameData.hero_combat_frames(h.cls_id, h.pool_id, "attack")
				if not frames.is_empty() and hero_rects.has(h.id):
					await _play_frames(hero_rects[h.id], frames)
				else:
					await _tween_lunge(hero_wrappers[h.id])
			elif action == "ability":
				AudioManager.play_sfx(GameData.SFX_PATH["attack"])
				var frames := GameData.hero_combat_frames(h.cls_id, h.pool_id, "skill")
				if not frames.is_empty() and hero_rects.has(h.id):
					await _play_frames(hero_rects[h.id], frames)
				else:
					await _tween_skill_flash(hero_wrappers[h.id])
				_spawn_ability_bucket_burst(h.pool_id, hero_wrappers[h.id])
			elif action == "defend":
				await _tween_defend(hero_wrappers[h.id])

		for i in monsters.size():
			if not monster_wrappers.has(i):
				continue
			var dmg: float = float(monster_hp_before[i]) - float(monsters[i]["hp"])
			if dmg > 0:
				var heavy: bool = dmg >= float(monsters[i]["max_hp"]) * 0.25
				var burst_color: Color = Palette.ELEMENT_PARTICLE_COLOR.get(h.type, Color(1, 1, 1))
				AudioManager.play_sfx(GameData.SFX_PATH["hit_heavy" if heavy else "hit"])
				_spawn_impact_particles(monster_wrappers[i], monster_wrappers[i].custom_minimum_size * 0.5, burst_color, heavy)
				await _impact_beat(arena, heavy)
				if monster_rects.has(i):
					await _play_frames(monster_rects[i], GameData.monster_anim_frames(str(monsters[i]["name"]), "hurt"))
				await _flash_white(monster_wrappers[i])
				await _spawn_damage_number(monster_wrappers[i], "-%d" % int(round(dmg)), Palette.HAZARD)

	else:
		var i: int = int(turn["id"])

		GameState.resolve_turn_now()
		_spawn_procs(state, hero_wrappers)

		if i >= monsters.size():
			return

		if monster_rects.has(i):
			await _play_frames(monster_rects[i], GameData.monster_anim_frames(str(monsters[i]["name"]), "attack"))

		var atk_type := str(monsters[i].get("type", ""))
		var retaliation_color: Color = Palette.ELEMENT_PARTICLE_COLOR.get(atk_type, Color(1, 1, 1))
		for h in party:
			var before: int = int(hp_before.get(h.id, h.hp))
			var dmg2: int = before - h.hp
			if dmg2 > 0 and hero_wrappers.has(h.id):
				var heavy2: bool = float(dmg2) >= Combat.max_hp(h) * 0.25
				AudioManager.play_sfx(GameData.SFX_PATH["hit_heavy" if heavy2 else "hit"])
				_spawn_impact_particles(hero_wrappers[h.id], hero_wrappers[h.id].custom_minimum_size * 0.5, retaliation_color, heavy2)
				await _impact_beat(arena, heavy2)
				var frames := GameData.hero_combat_frames(h.cls_id, h.pool_id, "hurt")
				if not frames.is_empty() and hero_rects.has(h.id):
					await _play_frames(hero_rects[h.id], frames)
				else:
					await _tween_hurt(hero_wrappers[h.id])
				await _spawn_damage_number(hero_wrappers[h.id], "-%d" % dmg2, Palette.HAZARD)
				if before > 0 and h.hp <= 0:
					AudioManager.play_sfx(GameData.SFX_PATH["knockout"])
					await _tween_collapse(hero_wrappers[h.id])

	# A won fight is only detectable by re-checking node_state — Combat.resolve_turn's
	# return value never reaches here directly, only GameState.resolve_turn_now()'s
	# side effect on run["node_state"]["result"] does. Plays once, right after the
	# turn that actually finished the fight, before the caller's render() replaces
	# the arena with the victory screen.
	var ns_after: Dictionary = GameState.run.get("node_state", {})
	if ns_after.has("result") and bool(ns_after["result"].get("won", false)):
		AudioManager.play_sfx(GameData.SFX_PATH["victory"])
		for h in party:
			if h.hp > 0 and hero_wrappers.has(h.id):
				await _tween_victory_pose(hero_wrappers[h.id])


## Drives turns automatically: resolves+animates the current turn (even a
## living hero's, when `force_first` is set — used right after the player
## picks that hero's action from the action bar) then keeps resolving+
## animating turns for as long as the next one doesn't need player input (a
## monster's turn, a hero who died earlier this round being skipped, or a
## round boundary with nothing yet to show), stopping at the next living
## hero's turn or once the fight ends. No-ops if already running, so a
## redundant render() firing mid-animation can't start a second overlapping
## run.
##
## The stop-check only peeks state["turn_order"][turn_idx] when that index is
## still in range. When it isn't (this round's order is fully spent), there
## is nothing valid to inspect yet — Combat.peek_next_turn/_start_round is
## what rolls the next one, and only _play_turn (inside the loop body) is
## allowed to trigger that (see its doc comment). Treating an out-of-range
## index as "stop" here — instead of "fall through and resolve" — used to
## make render() and this function call each other forever: render() shows no
## current hero, fires this function, which would immediately break without
## making progress, call render() again, which fires this function again...
##
## `pre_action`, if given, runs after the disconnect above but before the
## loop — this is how an action-bar click gets its GameState.set_hero_action
## in: calling it from the button's own callback would fire state_changed
## (set_hero_action always emits it) *before* this function has a chance to
## disconnect render, re-entering render() mid-click with hero_wrappers/arena
## about to be replaced out from under the very call that's still holding
## references to them.
func _run_combat_turns(state: Dictionary, hero_wrappers: Dictionary, hero_rects: Dictionary, monster_wrappers: Dictionary, monster_rects: Dictionary, arena: Control, force_first: bool = false, pre_action: Callable = Callable()) -> void:
	if _combat_animating:
		return
	_combat_animating = true
	if GameState.state_changed.is_connected(render):
		GameState.state_changed.disconnect(render)
	if pre_action.is_valid():
		pre_action.call()
	var force := force_first
	while true:
		if not force:
			var turn_order: Array = state.get("turn_order", [])
			var turn_idx: int = int(state.get("turn_idx", 0))
			if turn_idx < turn_order.size():
				var current: Dictionary = turn_order[turn_idx]
				if str(current.get("type", "")) == "hero":
					var h := _hero_by_id(state["party"], str(current["id"]))
					if h and h.hp > 0:
						break
		force = false
		await _play_turn_bounded(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena)
		if GameState.run.get("node_state", {}).has("result"):
			break
		await _await_or_timeout(get_tree().create_timer(0.15).timeout, 1.0)
	if not GameState.state_changed.is_connected(render):
		GameState.state_changed.connect(render)
	_combat_animating = false
	# The player may have navigated away (e.g. opened Settings) while this was
	# still animating — render() rebuilds whatever `screen` currently is via
	# _clear_root(), which would tear down that other screen's controls out
	# from under an in-flight click. Only rebuild if we're still looking at
	# the combat screen this animation belongs to.
	if screen == "rift_run":
		render()


## A quick step-back-and-fade on every living hero before the screen swaps to
## the Terminal — Retreat previously had zero animation, an instant cut.
func _play_retreat(heroes: Array[Hero], wrappers: Dictionary) -> void:
	AudioManager.play_sfx(GameData.SFX_PATH["ui_back"])
	for h in heroes:
		if h.hp > 0 and wrappers.has(h.id):
			var w: Control = wrappers[h.id]
			var tween := create_tween()
			tween.tween_property(w, "position:x", w.position.x - 16.0, 0.2)
			tween.parallel().tween_property(w, "modulate:a", 0.0, 0.2)
	await _await_or_timeout(get_tree().create_timer(0.22).timeout, 1.0)


func _render_combat_node(v: VBoxContainer) -> void:
	var ns: Dictionary = GameState.run.get("node_state", {})
	var kind := GameState.current_node_kind()
	var is_boss := kind == "boss"

	if not ns.has("combat_state") and not ns.has("result"):
		GameState.ensure_combat_bg()
		var pre_bg_idx := int(ns.get("bg_idx", 0)) % GameData.BATTLE_BACKGROUNDS.size()
		v.add_child(_banner(GameData.BATTLE_BACKGROUNDS[pre_bg_idx], 700, 220))
		var kind_label := "Boss" if is_boss else ("Elite" if kind == "elite" else "Combat")
		v.add_child(_label("A %s encounter awaits." % kind_label))
		v.add_child(_icon_domain_button("ember", "res://assets/skills/sword_a.png", "Engage", func():
			# engage_node() already emits state_changed, which render() is
			# connected to — an explicit render() call here on top of that
			# double-renders: the first (nested, from the emit) already
			# kicks off the fight's opening auto-advance turn against this
			# render's arena nodes, and the second frees those nodes out
			# from under that still-animating coroutine.
			GameState.engage_node()
		))
		return

	if ns.has("combat_state") and not ns.has("result"):
		var state: Dictionary = ns["combat_state"]
		var monsters: Array = state["monsters"]
		var party: Array[Hero] = state["party"]
		var living_heroes: Array[Hero] = []
		living_heroes.assign(party.filter(func(h): return h.hp > 0))

		# One shared battlefield — heroes on the left, monsters on the right,
		# facing each other across the same ground — rather than the previous
		# stacked monster-band/hero-band diorama. Matches every reference
		# battle screen's side-by-side confrontation instead of a top/bottom
		# split, and now spans the full content width with the action bar
		# stacked below it (also reference-matched: scene on top, commands in
		# a bottom strip) instead of sharing a row with a side menu.
		const ARENA_SIZE := Vector2(700, 220)
		var arena := Control.new()
		arena.custom_minimum_size = ARENA_SIZE

		var bg_path: String = GameData.BATTLE_BACKGROUNDS[int(state["background_idx"]) % GameData.BATTLE_BACKGROUNDS.size()]
		var bg := TextureRect.new()
		bg.texture = load(bg_path)
		bg.custom_minimum_size = ARENA_SIZE
		bg.size = ARENA_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		arena.add_child(bg)

		# Both rows share this baseline Y (bottom of the sprite) so the two
		# sides read as standing on the same ground rather than floating at
		# independent heights.
		var ground_y: float = ARENA_SIZE.y * 0.62

		# Each side's units pack into a narrow zone near ITS OWN edge of the
		# field, leaving a wide fixed no-man's-land in the middle (from 34%
		# to 66% of the width, regardless of how many units are on either
		# side) — a tight per-side spacing next to a deliberately open gap is
		# what actually reads as "two groups facing off" rather than one row
		# of evenly-spaced individuals (the previous 40%/50%+ split put too
		# little daylight between the sides relative to their own internal
		# spacing). Size still scales with the monster's own max HP (clamped)
		# so a boss/elite main unit reads as a bigger threat than a weak add.
		# A small per-position vertical offset applied within each side's row —
		# a flat single line read as too uniform/lined-up next to the
		# reference battle screens, which stagger their party into a loose
		# cluster at varied depths. Paired with DEPTH_SCALE so a unit staggered
		# "back" (negative offset, higher on screen) also shrinks and one
		# staggered "front" (positive, lower) grows — without that, moving a
		# same-size sprite up/down just reads as floating rather than standing
		# further back on the ground, since real perspective ties apparent
		# size to distance. Cycles if a side somehow has more than 4 living
		# units (never happens today, but harmless if it did).
		const DEPTH_STAGGER := [0.0, 20.0, -8.0, 28.0]
		const DEPTH_SCALE := [1.0, 1.1, 0.93, 1.15]

		var monster_wrappers: Dictionary = {}
		var monster_rects: Dictionary = {}
		var monster_zone_x: float = ARENA_SIZE.x * 0.66
		var monster_zone_w: float = ARENA_SIZE.x - monster_zone_x - 24.0
		var monster_step: float = monster_zone_w / max(1, monsters.size())
		for i in monsters.size():
			var m: Dictionary = monsters[i]
			var m_x: float = monster_zone_x + i * monster_step
			var depth_i := i % DEPTH_STAGGER.size()
			var m_ground: float = ground_y + DEPTH_STAGGER[depth_i]
			var m_size: int = clampi(int((56 + float(m["max_hp"]) / 2.5) * DEPTH_SCALE[depth_i]), 56, 110)
			var m_rect := _icon(GameData.sprite_for_monster(str(m["name"])), m_size)
			var m_wrapper := _wrap_icon(m_rect)
			m_wrapper.position = Vector2(m_x, m_ground - m_size)
			_add_ground_shadow(arena, m_wrapper.position, float(m_size))
			if float(m["hp"]) <= 0:
				m_wrapper.modulate = Color(0.35, 0.35, 0.35, 0.7)
			else:
				_start_idle_sway(m_wrapper)
			arena.add_child(m_wrapper)
			monster_wrappers[i] = m_wrapper
			monster_rects[i] = m_rect
			var m_plate_w: float = clampf(monster_step - 10.0, 70.0, 100.0)
			var m_plate := _status_plate(str(m["name"]), max(0, int(m["hp"])), int(m["max_hp"]), m_plate_w)
			var m_plate_pos := Vector2(m_x + m_size * 0.5 - m_plate_w * 0.5, m_ground - m_size - STATUS_PLATE_HEIGHT - 6.0)
			m_plate.position = m_plate_pos
			arena.add_child(m_plate)

			# Intent (Slay the Spire style): who this monster hits this round and
			# how hard — rolled at round start by Combat._start_round, so what's
			# shown is what happens (barring an intercept or escort).
			var intent := Combat.monster_intent(state, i)
			if not intent.is_empty():
				var t: Hero = intent["target"]
				var il := _label("%s %s · %d" % ["HEAVY →" if intent["heavy"] else "→", t.name.split(" the ")[0], int(intent["dmg"])], 11)
				il.add_theme_color_override("font_color", Palette.HAZARD if intent["heavy"] else Palette.TEXT)
				il.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
				il.add_theme_constant_override("shadow_offset_x", 1)
				il.add_theme_constant_override("shadow_offset_y", 1)
				il.size = Vector2(m_plate_w + 30.0, 16)
				il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				il.position = Vector2(m_x + m_size * 0.5 - il.size.x * 0.5, m_ground + 2.0)
				il.tooltip_text = "Attacks %s this round for about %d%s" % [t.name, int(intent["dmg"]), " — a heavy hit, consider Defending" if intent["heavy"] else ""]
				arena.add_child(il)

			# A persistent badge for the boss's own mechanic(s) (Enraged/Warded/
			# Regenerating/Frenzied — an SS-rank+ mapped rift's boss can carry
			# two at once) or, for a regular monster, its MONSTER_ABILITIES
			# archetype (poison/healer/shielded/frenzy) — sitting on its status
			# plate all fight instead of only a transient text hint above the
			# action bar.
			var mechanic: Dictionary = m.get("mechanic", {})
			var mechanic2: Dictionary = m.get("mechanic2", {})
			var ability: Dictionary = m.get("ability", {})
			var badge_specs: Array[Dictionary] = []
			if not mechanic.is_empty():
				badge_specs.append({"icon": GameData.BOSS_MECHANIC_ICON.get(str(mechanic["id"]), ""), "tooltip": "%s — %s" % [str(mechanic["name"]), str(mechanic["desc"])]})
			if not mechanic2.is_empty():
				badge_specs.append({"icon": GameData.BOSS_MECHANIC_ICON.get(str(mechanic2["id"]), ""), "tooltip": "%s — %s" % [str(mechanic2["name"]), str(mechanic2["desc"])]})
			if mechanic.is_empty() and not ability.is_empty():
				badge_specs.append({"icon": GameData.MONSTER_ABILITY_ICON.get(str(ability["kind"]), ""), "tooltip": str(ability["name"])})
			for bi in badge_specs.size():
				var mech_icon_path: String = str(badge_specs[bi]["icon"])
				if mech_icon_path == "":
					continue
				var mech_badge := PanelContainer.new()
				var mech_style := StyleBoxFlat.new()
				mech_style.bg_color = Palette.SURFACE3
				mech_style.border_width_left = 1
				mech_style.border_width_top = 1
				mech_style.border_width_right = 1
				mech_style.border_width_bottom = 1
				mech_style.border_color = Palette.ELITE
				mech_style.corner_radius_top_left = 999
				mech_style.corner_radius_top_right = 999
				mech_style.corner_radius_bottom_left = 999
				mech_style.corner_radius_bottom_right = 999
				mech_badge.add_theme_stylebox_override("panel", mech_style)
				mech_badge.add_child(_icon(mech_icon_path, 14))
				mech_badge.position = m_plate_pos + Vector2(m_plate_w - 16.0 - bi * 20.0, -6.0)
				mech_badge.tooltip_text = str(badge_specs[bi]["tooltip"])
				arena.add_child(mech_badge)

			# A finite color-pulse tell on the monster's own sprite, matching
			# whatever Combat.describe_incoming's text telegraph would say
			# about this exact mechanic this round — previously that warning
			# was text-only above the action bar, easy to miss.
			if float(m["hp"]) > 0:
				# round_num already names the round in progress — see the
				# Round-label comment below for why there's no +1 anymore.
				var next_round: int = int(state.get("round_num", 0))
				for mech_check in [mechanic, mechanic2]:
					if mech_check.is_empty():
						continue
					match mech_check.get("id"):
						"warded":
							if next_round <= 2:
								_start_mechanic_pulse(m_wrapper, Palette.VIOLET_BRIGHT)
						"enrage":
							if next_round > GameData.BOSS_ENRAGE_ROUND:
								_start_mechanic_pulse(m_wrapper, Palette.HAZARD)
						"frenzied":
							_start_mechanic_pulse(m_wrapper, Palette.HAZARD)
						"regen":
							_start_mechanic_pulse(m_wrapper, Palette.RANK_E)

			# Elemental type badge (Elemental Weakness) — opposite side from the
			# mechanic/ability badges above so the two never collide, reusing
			# the same 5 relic-type gem icons already generated for Inventory.
			var m_type := str(m.get("type", ""))
			var m_type_icon: String = GameData.RELIC_TYPE_ICON_PATH.get(m_type, "")
			if m_type_icon != "":
				var type_badge := PanelContainer.new()
				var type_style := StyleBoxFlat.new()
				type_style.bg_color = Palette.SURFACE3
				type_style.border_width_left = 1
				type_style.border_width_top = 1
				type_style.border_width_right = 1
				type_style.border_width_bottom = 1
				type_style.border_color = Palette.LINE
				type_style.corner_radius_top_left = 999
				type_style.corner_radius_top_right = 999
				type_style.corner_radius_bottom_left = 999
				type_style.corner_radius_bottom_right = 999
				type_badge.add_theme_stylebox_override("panel", type_style)
				type_badge.add_child(_icon(m_type_icon, 14))
				type_badge.position = m_plate_pos + Vector2(2.0, -6.0)
				type_badge.tooltip_text = "%s type" % m_type
				arena.add_child(type_badge)

		var hero_wrappers: Dictionary = {}
		var hero_rects: Dictionary = {}
		var hero_zone_x := 24.0
		var hero_zone_w: float = ARENA_SIZE.x * 0.34 - hero_zone_x
		var hero_step: float = hero_zone_w / max(1, living_heroes.size())
		var hero_base_size: float = clampf(84.0 - (living_heroes.size() - 1) * 8.0, 56.0, 84.0)
		var row_i := 0
		for h in party:
			if h.hp <= 0:
				continue
			var portrait_path := GameData.portrait_for_hero(h.cls_id, h.pool_id)
			if portrait_path == "":
				continue
			var h_x: float = hero_zone_x + row_i * hero_step
			var h_depth_i := row_i % DEPTH_STAGGER.size()
			var h_ground: float = ground_y + DEPTH_STAGGER[h_depth_i]
			var hero_size: float = hero_base_size * DEPTH_SCALE[h_depth_i]
			var h_rect := _icon_trimmed(portrait_path, int(hero_size))
			var h_wrapper := _wrap_icon(h_rect)
			h_wrapper.position = Vector2(h_x, h_ground - hero_size)
			_add_ground_shadow(arena, h_wrapper.position, hero_size)
			arena.add_child(h_wrapper)
			_start_idle_sway(h_wrapper)
			hero_wrappers[h.id] = h_wrapper
			hero_rects[h.id] = h_rect
			var h_plate_w: float = clampf(hero_step - 6.0, 70.0, 100.0)
			var h_plate := _status_plate(h.name.split(" the ")[0], h.hp, Combat.max_hp(h), h_plate_w)
			h_plate.position = Vector2(h_x + hero_size * 0.5 - h_plate_w * 0.5, h_ground - hero_size - STATUS_PLATE_HEIGHT - 6.0)
			arena.add_child(h_plate)
			row_i += 1

		# A border frame overlay, drawn last so it sits on top of everything
		# else — gives the arena a clear "this is the screen" edge instead of
		# the background art just stopping with nothing marking the boundary.
		var frame := PanelContainer.new()
		var frame_style := StyleBoxFlat.new()
		frame_style.bg_color = Color(0, 0, 0, 0)
		frame_style.border_width_left = 3
		frame_style.border_width_top = 3
		frame_style.border_width_right = 3
		frame_style.border_width_bottom = 3
		frame_style.border_color = Palette.LINE
		frame.add_theme_stylebox_override("panel", frame_style)
		frame.custom_minimum_size = ARENA_SIZE
		frame.size = ARENA_SIZE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arena.add_child(frame)

		# A round counter banner across the top of the arena — the reference
		# battle screens announce "Round N" at the start of each round; ours
		# stays up the whole round instead of flashing in and fading, since
		# animating it would mean threading another tween through the already
		# carefully-sequenced _run_combat_turns animation chain for a cosmetic
		# touch. round_num is prepared by Combat._start_round before the
		# round's first turn ever runs, so it already names the round in
		# progress — no +1 needed (see Combat.describe_incoming for the same
		# fix).
		var round_label := _label("Round %d" % int(state.get("round_num", 0)), 16)
		round_label.size = Vector2(ARENA_SIZE.x, 22)
		round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		round_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		round_label.add_theme_constant_override("shadow_offset_x", 1)
		round_label.add_theme_constant_override("shadow_offset_y", 1)
		round_label.position = Vector2(0, 6)
		arena.add_child(round_label)

		# Wrap the whole combat scene (arena + telegraph + action menu + log)
		# in one bordered ember-domain frame with a tight internal gap instead
		# of several independently-bordered pieces stacked at the screen's
		# normal spacing — reads as one compact "battle panel" rather than a
		# loose vertical stack, and the tighter gap measurably shrinks the
		# footprint (the previous stack needed a scroll to see the action bar
		# and log on a typical viewport; this doesn't).
		var battle_frame := PanelContainer.new()
		battle_frame.theme_type_variation = &"CardPanelEmber"
		var battle_col := _vbox(6)
		battle_frame.add_child(battle_col)

		battle_col.add_child(arena)

		var incoming := Combat.describe_incoming(state)
		if incoming != "":
			battle_col.add_child(_label(incoming, 12, true))

		# Turn order strip — heroes and monsters genuinely interleaved by
		# speed (Combat._compute_turn_order), not a "whose bar am I editing"
		# tab row anymore.
		battle_col.add_child(_turn_order_strip(state))

		# The action controls live in their own bordered panel below the
		# arena (reusing the same flat style the old side menu used — the
		# shared Theme's texture-based panel is tuned for fixed-size cards
		# and renders wrong at this panel's variable width/height).
		var menu_panel := PanelContainer.new()
		var menu_style := StyleBoxFlat.new()
		menu_style.bg_color = Palette.SURFACE2
		menu_style.border_width_left = 1
		menu_style.border_width_top = 1
		menu_style.border_width_right = 1
		menu_style.border_width_bottom = 1
		menu_style.border_color = Palette.LINE
		menu_style.corner_radius_top_left = 8
		menu_style.corner_radius_top_right = 8
		menu_style.corner_radius_bottom_right = 8
		menu_style.corner_radius_bottom_left = 8
		menu_style.content_margin_left = 10.0
		menu_style.content_margin_top = 10.0
		menu_style.content_margin_right = 10.0
		menu_style.content_margin_bottom = 10.0
		menu_panel.add_theme_stylebox_override("panel", menu_style)
		var menu := _vbox(6)
		menu_panel.add_child(menu)

		var turn_order: Array = state.get("turn_order", [])
		var turn_idx: int = int(state.get("turn_idx", 0))
		var current_turn: Dictionary = turn_order[turn_idx] if turn_idx < turn_order.size() else {}
		var current_hero: Hero = null
		if str(current_turn.get("type", "")) == "hero":
			var candidate := _hero_by_id(party, str(current_turn["id"]))
			if candidate and candidate.hp > 0:
				current_hero = candidate

		if current_hero:
			var pending: Dictionary = state["pending_actions"]
			var act: Dictionary = pending.get(current_hero.id, {"action": "attack", "target": 0})
			var current_action: String = str(act.get("action", "attack"))
			var current_target: int = int(act.get("target", 0))

			menu.add_child(_label("%s's turn" % current_hero.name.split(" the ")[0], 13, true))

			var slots: Array = []
			for i in monsters.size():
				if float(monsters[i]["hp"]) <= 0:
					continue
				var target_name: String = str(monsters[i]["name"]).split(" ")[0]
				var attack_cb := func(hid=current_hero.id, ti=i):
					_run_combat_turns(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena, true, func(): GameState.set_hero_action(hid, "attack", ti))
				var atk_key := str(slots.size() + 1)
				_combat_hotkeys[atk_key] = attack_cb
				if current_action == "attack" and current_target == i:
					_combat_hotkeys["Space"] = attack_cb
				slots.append(_action_slot(GameData.sprite_for_monster(str(monsters[i]["name"])), "",
					current_action == "attack" and current_target == i, false,
					attack_cb, 64.0, "%s · Atk %s" % [atk_key, target_name]
				))
			if Combat.qualifies_for_ability(current_hero):
				var cd: int = current_hero.ability_cooldown
				var ability_name := str(GameData.SUBCLASS_ABILITIES.get(current_hero.pool_id, {}).get("name", "Ability")).split(" ")[0]
				var ability_cb := func(hid=current_hero.id):
					_run_combat_turns(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena, true, func(): GameState.set_hero_action(hid, "ability"))
				var ab_key := str(slots.size() + 1)
				if cd == 0:
					_combat_hotkeys[ab_key] = ability_cb
					if current_action == "ability":
						_combat_hotkeys["Space"] = ability_cb
				slots.append(_action_slot(GameData.ability_icon(current_hero.pool_id), str(cd) if cd > 0 else "",
					current_action == "ability", cd > 0,
					ability_cb, 64.0, "%s · %s" % [ab_key, ability_name]
				))
			var defend_cb := func(hid=current_hero.id):
				_run_combat_turns(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena, true, func(): GameState.set_hero_action(hid, "defend"))
			var def_key := str(slots.size() + 1)
			_combat_hotkeys[def_key] = defend_cb
			if current_action == "defend":
				_combat_hotkeys["Space"] = defend_cb
			if not _combat_hotkeys.has("Space") and _combat_hotkeys.has("1"):
				_combat_hotkeys["Space"] = _combat_hotkeys["1"]
			slots.append(_action_slot("res://assets/skills/shield_basic.png", "",
				current_action == "defend", false,
				defend_cb, 64.0, "%s · Defend" % def_key
			))
			menu.add_child(_slot_row(slots))
			menu.add_child(_label("Keys: 1-%d pick an action · Space repeats the highlighted one" % slots.size(), 10, true))
		elif living_heroes.is_empty():
			menu.add_child(_label("The party is down.", 12, true))
		else:
			menu.add_child(_label("...", 12, true))

		var bottom_row := HBoxContainer.new()
		bottom_row.add_child(_icon_button("res://assets/skills/boots.png", "Speed x%d" % int(GameState.combat_speed), func():
			GameState.combat_speed = 1.0 if GameState.combat_speed >= 3.0 else GameState.combat_speed + 1.0
			Engine.time_scale = GameState.combat_speed
			GameState.save_settings()
			if not _combat_animating:
				render()
		))
		bottom_row.add_child(_icon_button("res://assets/skills/wing.png", "Retreat", func():
			# Guard against a second click firing while a turn's animation is
			# still mid-flight — that would mutate the same `state` dict
			# _play_turn is reading and immediately render() out from under
			# it, freeing the arena nodes its suspended awaits still reference.
			if _combat_animating:
				return
			_combat_animating = true
			if GameState.state_changed.is_connected(render):
				GameState.state_changed.disconnect(render)
			await _play_retreat(living_heroes, hero_wrappers)
			GameState.combat_retreat()
			if not GameState.state_changed.is_connected(render):
				GameState.state_changed.connect(render)
			_combat_animating = false
			# Same reasoning as _run_combat_turns: don't stomp a screen the
			# player has since navigated to.
			if screen == "rift_run":
				render()
		))
		menu.add_child(bottom_row)
		battle_col.add_child(menu_panel)

		# Auto-play any turn that doesn't need player input — a monster's
		# turn, or a hero who died earlier this round being skipped —
		# fire-and-forget from render() itself. _run_combat_turns no-ops if
		# already animating or if it's already a living hero's turn, so this
		# is safe to call on every render without duplicating work.
		if current_hero == null and not living_heroes.is_empty():
			_run_combat_turns(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena)

		# The round log stays available but demoted — a strip below the action
		# bar rather than sharing equal billing with the arena, since none of
		# the reference battle screens foreground a scrolling log (damage
		# numbers/animations carry the moment-to-moment feedback now). Only
		# the most recent lines are rendered (rather than the whole fight's
		# log) and the box is tall enough for a typical round's worth of
		# lines, so reading "what just happened" doesn't actually require
		# scrolling — a fixed height still caps it so a long boss fight's full
		# log can't push the layout down the way it used to. Shrunk from 130
		# to 80 as part of tightening the whole battle panel's footprint.
		var full_log: Array = state["log"]
		var recent_log: Array = full_log.slice(max(0, full_log.size() - 10))
		battle_col.add_child(_log_richtext(recent_log, party, monsters, 80.0))
		v.add_child(battle_frame)
		return

	var result: Dictionary = ns["result"]
	var monster_row := HBoxContainer.new()
	monster_row.add_child(_icon(GameData.sprite_for_monster(str(result["monster_name"])), 28))
	monster_row.add_child(_label(str(result["monster_name"]), 14))
	v.add_child(monster_row)
	var log_party: Array[Hero] = GameState.current_party()
	v.add_child(_log_richtext(result["log"], log_party, [{"name": result["monster_name"]}]))

	var is_riftbreak: bool = GameState.run.get("is_riftbreak", false)
	if result["won"]:
		if is_riftbreak:
			# A Riftbreak is a consequence, not an opportunity — no loot, no
			# reward choice, straight back to the Terminal.
			v.add_child(_label("Threat repelled. The rift's spillover is contained — no loot from a fight like this."))
			v.add_child(_icon_domain_button("ember", GameData.BUTTON_ICON_PATH["confirm"], "Return to Terminal", func():
				GameState.finish_run()
				screen = "terminal"
				render()
			))
			return
		# A single violet-domain banner frame for the whole victory moment
		# (heading + currency gained + reward cards) instead of plain stacked
		# labels — the same "wrap it in one bordered panel" treatment the
		# battle screen just got, so a win reads as a distinct occasion
		# rather than more of the same log-and-button stack.
		var victory_frame := PanelContainer.new()
		victory_frame.theme_type_variation = &"CardPanelViolet"
		var victory_col := _vbox(8)
		victory_frame.add_child(victory_col)

		victory_col.add_child(_label("Victory!", 22))
		var bonus_crystal: int = result.get("bonus_crystal", 0)
		var gains_row := HBoxContainer.new()
		gains_row.add_theme_constant_override("separation", 14)
		gains_row.add_child(_icon(GameData.CURRENCY_ICON_PATH["coins"], 18))
		gains_row.add_child(_label("+%d" % int(result["coin"]), 14))
		gains_row.add_child(_icon(GameData.CURRENCY_ICON_PATH["crystals"], 18))
		var crystal_text := "+%d" % int(result["crystal"])
		if bonus_crystal > 0:
			crystal_text += " (+%d bonus)" % bonus_crystal
		gains_row.add_child(_label(crystal_text, 14))
		victory_col.add_child(gains_row)
		if str(result.get("escort_saved", "")) != "":
			victory_col.add_child(_label("%s made it through safely — +2 Reputation, +1 Token." % str(result["escort_saved"]), 12, true))
		if kind == "boss" or kind == "elite":
			victory_col.add_child(_label(GameData.narrative_line("boss_defeated" if kind == "boss" else "elite_defeated"), 12, true))
		var options: Array = result.get("reward_options", [])
		if not options.is_empty() and not ns.get("reward_chosen", false):
			victory_col.add_child(_label("Choose a reward:", 14))
			var reward_row := HFlowContainer.new()
			reward_row.add_theme_constant_override("h_separation", 10)
			reward_row.add_theme_constant_override("v_separation", 10)
			for i in options.size():
				var opt: Dictionary = options[i]
				var obj = opt["obj"]
				var is_relic: bool = opt["loot_type"] == "relic"
				var desc: String = _loot_desc(obj, is_relic)
				var icon_path: String = GameData.RELIC_TYPE_ICON_PATH[obj.type] if is_relic else GameData.ITEM_CATEGORY_ICON_PATH[obj.category]
				reward_row.add_child(_reward_tile(icon_path, _loot_display_name(obj), str(obj.rarity), desc, func(idx=i, legendary=(obj.rarity == "legendary")):
					GameState.pick_combat_reward(idx)
					if legendary:
						_flavor_toast = GameData.narrative_line("legendary_drop")
					render()
				, "" if is_relic else _item_card(obj)))
			victory_col.add_child(reward_row)
			# Flip each reward card in, one after another, the first time this
			# result is shown (a re-render after that shows them instantly).
			# Legendaries land with a gold flash.
			if not is_same(options, _revealed_rewards):
				_revealed_rewards = options
				# The row is a container, which resets its direct children's
				# scale on every layout — so flip each tile's own (freely
				# positioned) children instead of the tile itself.
				for ri in reward_row.get_child_count():
					var tile: Control = reward_row.get_child(ri)
					var tw := tile.create_tween().set_parallel(true)
					for part in tile.get_children():
						if part is Control:
							part.pivot_offset = tile.custom_minimum_size * 0.5 - part.position
							part.scale = Vector2(0.0, 1.0)
							tw.tween_property(part, "scale", Vector2.ONE, 0.22).set_delay(0.2 + 0.18 * ri).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					if str(options[ri]["obj"].rarity) == "legendary":
						tw.tween_property(tile, "modulate", Color(1.6, 1.35, 0.7), 0.12).set_delay(0.45 + 0.18 * ri)
						tw.tween_property(tile, "modulate", Color.WHITE, 0.45).set_delay(0.6 + 0.18 * ri)
		else:
			victory_col.add_child(_icon_domain_button("violet", GameData.BUTTON_ICON_PATH["confirm"], "Continue", func():
				if is_boss:
					GameState.seal_rift()
				else:
					GameState.advance_node()
				render()
			))
		v.add_child(victory_frame)
	elif is_riftbreak and int(GameState.run.get("riftbreak_worst_index", 0)) >= 6:
		# Worst merged rank was S/SS/SSS — a forced game over, whether the
		# fight was lost outright or the player retreated from it. Either way
		# the rift's threat was never actually contained, so both carry the
		# same consequence. Fires immediately with no confirm step (unlike
		# the voluntary "Reset Guild" button) since this is a consequence,
		# not a choice.
		v.add_child(_label("Due to the rift break, a large portion of the world is in struggle now. Your guild has been erased."))
		v.add_child(_icon_domain_button("violet", GameData.BUTTON_ICON_PATH["confirm"], "Found a New Guild", func():
			GameState.reset()
			GameState.save()
			screen = "onboard"
			render()
		))
	else:
		var defeat_text := "You withdraw from the fight." if result.get("retreated", false) else "Defeat — the party is downed and recovering."
		v.add_child(_label(defeat_text))
		if result.has("riftbreak_compensation_coins"):
			v.add_child(_label("You paid compensation to the other guilds to help close the rift. (-%d Coins, -%d Crystals)" % [int(result["riftbreak_compensation_coins"]), int(result["riftbreak_compensation_crystals"])], 12, true))
		if str(result.get("flavor", "")) != "":
			v.add_child(_label(str(result["flavor"]), 12, true))
		for line in _run_summary_lines():
			v.add_child(_label(line, 12, true))
		v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["confirm"], "Return to Terminal", func():
			GameState.finish_run()
			screen = "terminal"
			render()
		))


## The 3 shop offers as an icon-forward card grid instead of stacked
## full-width text rows — each card leads with a large item/relic icon
## (matching a typical shop-stall layout) with name/desc/price underneath.
func _render_shop_node(v: VBoxContainer) -> void:
	GameState.ensure_shop_offers()
	var ns: Dictionary = GameState.run["node_state"]
	v.add_child(_banner(GameData.SHOP_BG, 700, 190))
	v.add_child(_label("Rift Hallway Shop"))
	var offers: Array = ns["offers"]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for i in offers.size():
		var off: Dictionary = offers[i]
		var obj = off["obj"]
		var is_relic: bool = off["loot_type"] == "relic"
		var desc: String = _loot_desc(obj, is_relic)
		var bought: bool = off.get("bought", false)
		var icon_path: String = GameData.RELIC_TYPE_ICON_PATH[obj.type] if is_relic else GameData.ITEM_CATEGORY_ICON_PATH[obj.category]

		var card := PanelContainer.new()
		card.theme_type_variation = &"CardPanelViolet"
		card.custom_minimum_size.x = 200
		if not is_relic:
			_rich_tip(card, _item_card(obj))
		var cv := _vbox(4)
		var icon_wrap := CenterContainer.new()
		icon_wrap.add_child(_icon(icon_path, 40))
		cv.add_child(icon_wrap)
		cv.add_child(_label(_loot_display_name(obj), 12))
		cv.add_child(_wrap_label(desc, 11, true))
		if bought:
			cv.add_child(_label("Bought", 12, true))
		else:
			cv.add_child(_icon_button(GameData.CURRENCY_ICON_PATH["coins"], "Buy (%dc)" % int(off["price"]), func(idx=i):
				GameState.buy_shop_offer(idx)
				render()
			))
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


## A short recap for the two screens a run can end on (sealed or wiped/
## retreated) — floor reached, net currency change this run (coins/crystals/
## tokens can be spent as well as earned mid-run, e.g. at a shop, so "net
## change" is the honest framing, not "earned"), and heroes lost to Hardcore
## if any. Deliberately reads only numbers that already exist or are a cheap
## snapshot diff — no new combat-hot-path instrumentation.
func _run_summary_lines() -> Array[String]:
	var lines: Array[String] = []
	var layers: Array = GameState.run.get("layers", [])
	if not layers.is_empty():
		lines.append("Floor %d/%d reached" % [int(GameState.run.get("pos", 0)) + 1, layers.size()])
	var coin_delta := GameState.coins - int(GameState.run.get("start_coins", GameState.coins))
	var crystal_delta := GameState.crystals - int(GameState.run.get("start_crystals", GameState.crystals))
	var token_delta := GameState.tokens - int(GameState.run.get("start_tokens", GameState.tokens))
	lines.append("%+d Coins, %+d Crystals, %+d Tokens this run" % [coin_delta, crystal_delta, token_delta])
	var lost := int(GameState.run.get("heroes_lost", 0))
	if lost > 0:
		lines.append("%d hero%s lost" % [lost, "es" if lost > 1 else ""])
	return lines


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
		v.add_child(_banner(bg_path, 700, 190))

	var dmg_mult: float = float(hz["dmg_mult"])
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(_label(str(hz["name"]), 16))
	var sev_label := _label(_hazard_severity_label(dmg_mult), 12)
	sev_label.add_theme_color_override("font_color", _hazard_severity_color(dmg_mult))
	name_row.add_child(sev_label)
	v.add_child(name_row)

	if not ns.get("resolved", false):
		var choice_row := HBoxContainer.new()
		choice_row.add_theme_constant_override("separation", 8)
		choice_row.add_child(_icon_button("res://assets/skills/boots.png", "Push Through", func():
			GameState.push_through_hazard()
			render()
		))
		var bypass_btn := _icon_button(GameData.CURRENCY_ICON_PATH["crystals"], "Bypass (%d Crystals)" % GameState.HAZARD_BYPASS_COST, func():
			GameState.bypass_hazard()
			render()
		)
		bypass_btn.disabled = not GameState.can_afford_hazard_bypass()
		choice_row.add_child(bypass_btn)
		choice_row.add_child(_icon_button(GameData.BUTTON_ICON_PATH["dice"], "Risk it for Loot", func():
			GameState.risk_hazard()
			render()
		))
		v.add_child(choice_row)
	else:
		for line in ns.get("log", []):
			v.add_child(_label(str(line), 12))
		v.add_child(_icon_domain_button("violet", GameData.BUTTON_ICON_PATH["confirm"], "Continue", func():
			GameState.advance_node()
			render()
		))
