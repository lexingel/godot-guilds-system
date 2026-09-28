class_name BattleView
extends RosterView
## The combat node: arena, unit plates, intents, command bar, turn
## playback animations and the fight result screen.


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
	if GameState.reduce_motion:
		return
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
	wrapper.pivot_offset = Vector2(wrapper.custom_minimum_size.x * 0.5, wrapper.custom_minimum_size.y)
	var tween := create_tween()
	tween.tween_property(wrapper, "position:y", start_y + 10.0, 0.25)
	tween.parallel().tween_property(wrapper, "rotation", -0.35, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
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
	if GameState.reduce_motion:
		return
	var base: Vector2 = arena.position
	var mag: float = 8.0 if heavy else 3.0
	var tween := create_tween()
	if heavy:
		tween.tween_interval(0.07)   # hit-stop: a beat of stillness before the shake
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
	if GameState.reduce_motion:
		wrapper.modulate = color.lerp(Color.WHITE, 0.5)   # a steady tint instead of a flash
		return
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
	if GameState.reduce_motion:
		return
	var rest := wrapper.position
	var tween := create_tween()
	tween.bind_node(wrapper)
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(wrapper, "position:y", rest.y - 3.0, 1.4)
	tween.tween_property(wrapper, "position:y", rest.y, 1.4)


## Heavy hits get a bigger number that pops before it floats away.
func _spawn_damage_number(wrapper: Control, text: String, color: Color, big: bool = false) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", DISPLAY_FONT)
	l.add_theme_font_size_override("font_size", 26 if big else 18)
	l.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if big else color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("outline_size", 4)
	l.position = Vector2(wrapper.custom_minimum_size.x * 0.5 - 14, wrapper.custom_minimum_size.y * 0.2)
	l.pivot_offset = Vector2(14, 14)
	wrapper.add_child(l)
	var tween := create_tween()
	if big:
		l.scale = Vector2(1.6, 1.6)
		tween.tween_property(l, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(l, "position:y", l.position.y - 30, 0.6)
	tween.parallel().tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.2)
	await _await_or_timeout(tween.finished, 1.5)
	if is_instance_valid(l):   # gone already if the screen was rebuilt meanwhile
		l.queue_free()


## Floats every effect that fired this turn (Combat._proc: "Counter!",
## "Intercept!", a passive or Legendary's name...) over its hero, staggered so
## several procs on one hero stack instead of overlapping. Fire-and-forget:
## never awaited, so it can't hold up the turn's own animation chain.
## Combat hotkeys (see _combat_hotkeys, filled while the action bar builds).
## Gamepad buttons stand in for hotkeys. In a fight: A repeats the last
## action, X Defend, Y the Ability, LB/RB the two role skills, the D-pad
## cycles targets, Start opens More, Select toggles Auto. Everywhere: B goes back; in camp
## LB/RB switch tabs. Menus are otherwise driven by focus (D-pad + A).
const PAD_BATTLE := {JOY_BUTTON_A: "Space", JOY_BUTTON_X: "5", JOY_BUTTON_Y: "4", JOY_BUTTON_LEFT_SHOULDER: "2", JOY_BUTTON_RIGHT_SHOULDER: "3",
	JOY_BUTTON_DPAD_LEFT: "Tab", JOY_BUTTON_DPAD_RIGHT: "Tab", JOY_BUTTON_BACK: "A", JOY_BUTTON_START: "M"}
var _pad_mode := false   # the last input came from a gamepad: keep a button focused after each rebuild


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		if not _pad_mode:
			_pad_mode = true
			_pad_focus.call_deferred()
	elif event is InputEventMouseMotion and event.relative.length() > 2.0:
		_pad_mode = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		var pk := ""
		if screen == "rift_run" and PAD_BATTLE.has(event.button_index) and _ally_pick == "":
			pk = PAD_BATTLE[event.button_index]
		elif event.button_index == JOY_BUTTON_B:
			pk = "Escape"
		elif screen != "rift_run" and event.button_index in [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]:
			call("_pad_cycle_tab", 1 if event.button_index == JOY_BUTTON_RIGHT_SHOULDER else -1)
			get_viewport().set_input_as_handled()
			return
		if pk != "" and _combat_hotkeys.has(pk):
			get_viewport().set_input_as_handled()
			_combat_hotkeys[pk].call()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := OS.get_keycode_string(event.keycode)
	if _combat_hotkeys.has(key):
		get_viewport().set_input_as_handled()
		_combat_hotkeys[key].call()


## True if `n` or one of its parents is about to be freed (a screen rebuild
## queues the old one for deletion; it lingers until the frame ends).
func _dying(n: Node) -> bool:
	while n != null:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false


var _pad_focus_text := ""   # the focused button's text, to find it again after a rebuild


## Keeps a button focused for gamepad players: the one that was focused
## before the screen rebuilt if it's still there, else the first one.
func _pad_focus() -> void:
	if not _pad_mode or not is_inside_tree():
		return
	var owner_now := get_viewport().gui_get_focus_owner()
	if owner_now != null and owner_now.is_visible_in_tree() and not _dying(owner_now):
		return
	var first: Button = null
	for n in find_children("*", "Button", true, false):
		var b := n as Button
		if b == null or b.disabled or not b.is_visible_in_tree() or b.focus_mode == Control.FOCUS_NONE or _dying(b):
			continue
		if _pad_focus_text != "" and b.text == _pad_focus_text:
			b.grab_focus()
			return
		if first == null:
			first = b
	if first:
		first.grab_focus()


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


## What heroes said this turn, as speech bubbles over their heads (they read
## at any battle speed).
func _spawn_barks(state: Dictionary, hero_wrappers: Dictionary) -> void:
	for b in state.get("_barks", []):
		var wrapper: Control = hero_wrappers.get(str(b["hero"]))
		if wrapper == null or not is_instance_valid(wrapper):
			continue
		var bubble := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(Palette.TEXT, 0.95)
		st.set_corner_radius_all(8)
		st.content_margin_left = 8
		st.content_margin_right = 8
		st.content_margin_top = 3
		st.content_margin_bottom = 4
		bubble.add_theme_stylebox_override("panel", st)
		var l := _label(str(b["text"]), 12)
		l.add_theme_color_override("font_color", Palette.INK)
		bubble.add_child(l)
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bubble.position = Vector2(-20, -UNIT_PLATE_H - 34)
		bubble.z_index = 5
		wrapper.add_child(bubble)
		var tw := bubble.create_tween()
		tw.set_ignore_time_scale(true)
		bubble.modulate.a = 0.0
		tw.tween_property(bubble, "modulate:a", 1.0, 0.15)
		tw.tween_interval(1.8)
		tw.tween_property(bubble, "modulate:a", 0.0, 0.3)
		tw.tween_callback(bubble.queue_free)


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


## This round's turn order (Combat._compute_turn_order) as a row of
## portraits: heroes framed violet, monsters red, the one acting now larger
## with a gold frame, spent turns dimmed.
func _turn_order_strip(state: Dictionary) -> Control:
	var turn_order: Array = state.get("turn_order", [])
	var turn_idx: int = int(state.get("turn_idx", 0))
	var party: Array[Hero] = state["party"]
	var monsters: Array = state["monsters"]

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var rl := _label("Turn order", 12, true)
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rl)
	for i in turn_order.size():
		var entry: Dictionary = turn_order[i]
		var is_hero: bool = str(entry["type"]) == "hero"
		var icon_path := ""
		var tip := ""
		if is_hero:
			var h := _hero_by_id(party, str(entry["id"]))
			if h:
				icon_path = GameData.portrait_for_hero(h.cls_id, h.pool_id)
				tip = h.name
				if h.hp <= 0:
					continue
		else:
			var mi: int = int(entry["id"])
			if mi < monsters.size():
				icon_path = GameData.sprite_for_monster(str(monsters[mi]["name"]))
				tip = str(monsters[mi]["name"])
				if float(monsters[mi]["hp"]) <= 0:
					continue
		if icon_path == "":
			continue
		var is_current := i == turn_idx
		var tile := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Palette.SURFACE3 if is_current else Palette.SURFACE
		style.set_border_width_all(2)
		style.border_color = Palette.EMBER_BRIGHT if is_current else (Palette.VIOLET if is_hero else Palette.EMBER_DANGER)
		style.set_corner_radius_all(5)
		style.set_content_margin_all(2)
		tile.add_theme_stylebox_override("panel", style)
		tile.tooltip_text = (tr("Acting now: ") if is_current else "") + tip
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sz := 44 if is_current else 34
		var icon := _icon_trimmed(icon_path, sz) if is_hero else _icon(icon_path, sz)
		if is_hero:
			_hero_look(icon, _hero_by_id(party, str(entry["id"])))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if i < turn_idx:
			tile.modulate = Color(1, 1, 1, 0.35)
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
	var shields_before: Dictionary = (state.get("hero_shields", {}) as Dictionary).duplicate()
	var burn_before: Dictionary = (state.get("hero_burn", {}) as Dictionary).duplicate()
	var chill_before: Dictionary = (state.get("_chilled", {}) as Dictionary).duplicate()
	var monster_hp_before: Array = []
	for m in monsters:
		monster_hp_before.append(float(m["hp"]))
	arena.pivot_offset = arena.custom_minimum_size * 0.5

	if str(turn.get("type", "")) == "hero":
		var h := _hero_by_id(party, str(turn["id"]))
		var pend: Dictionary = state["pending_actions"].get(str(turn["id"]), {})
		var action: String = str(pend.get("action", "attack"))
		var tgt := int(pend.get("target", 0))
		var ally_id := str(pend.get("ally", ""))

		var log_before: int = (state["log"] as Array).size()
		GameState.resolve_turn_now()
		_spawn_procs(state, hero_wrappers)
		_spawn_barks(state, hero_wrappers)
		_turn_sfx((state["log"] as Array).slice(log_before))

		if h == null or h.hp <= 0:
			return   # died earlier this round (e.g. a monster's turn) — the turn was just skipped, nothing to animate

		if hero_wrappers.has(h.id):
			var hw: Control = hero_wrappers[h.id]
			var tint := Fx.element_color(h.type)
			var tw: Control = monster_wrappers.get(tgt, _first_wrapper(monster_wrappers))
			match action:
				"attack":
					await _anim_hero_attack(h, hw, hero_rects.get(h.id), tw, tint, arena)
				"ability", "call":
					await _anim_hero_ability(h, action, hw, hero_rects.get(h.id), tw, tint, arena, state, hero_wrappers, monster_wrappers, hp_before, shields_before, monster_hp_before)
				_ when action.begins_with("skill:"):
					var sk := GameData.find_role_skill(action.substr(6))
					if str(sk.get("target", "")) == "foe":
						await _anim_hero_attack(h, hw, hero_rects.get(h.id), tw, tint, arena)
					else:
						Fx.sparkles(arena, _center(hw), tint.lerp(Color.WHITE, 0.4), 22, hw.custom_minimum_size.x * 0.7, false, 0.5)
						await _tween_skill_flash(hw)
				"defend":
					Fx.dome(arena, _center(hw), hw.custom_minimum_size.x * 1.15)
					await _tween_defend(hw)
				"guard":
					await _anim_guard(hw, hero_wrappers.get(ally_id), arena)

		for i in monsters.size():
			if not is_instance_valid(arena):
				return   # the screen was rebuilt mid-animation (e.g. Quick fight)
			if not monster_wrappers.has(i):
				continue
			var dmg: float = float(monster_hp_before[i]) - float(monsters[i]["hp"])
			if dmg > 0:
				var mw: Control = monster_wrappers[i]
				var heavy: bool = dmg >= float(monsters[i]["max_hp"]) * 0.25
				var burst_color: Color = Palette.ELEMENT_PARTICLE_COLOR.get(h.type, Color(1, 1, 1))
				AudioManager.play_sfx(GameData.SFX_PATH["hit_heavy" if heavy else "hit"])
				Fx.burst(arena, "impact", _center(mw), mw.custom_minimum_size.y * (0.7 if heavy else 0.45), burst_color.lerp(Color.WHITE, 0.4), 26.0)
				_spawn_impact_particles(mw, mw.custom_minimum_size * 0.5, burst_color, heavy)
				_knockback(mw, 1.0, heavy)
				_plate_set_hp(_monster_plates.get(i), float(monsters[i]["hp"]))
				if heavy:
					_camera_punch(arena)
				await _impact_beat(arena, heavy)
				if monster_rects.has(i):
					await _play_frames(monster_rects[i], GameData.monster_anim_frames(str(monsters[i]["name"]), "hurt"))
				await _flash_white(mw)
				await _spawn_damage_number(mw, "-%d" % int(round(dmg)), Palette.HAZARD, heavy)
				if float(monster_hp_before[i]) > 0.0 and float(monsters[i]["hp"]) <= 0.0:
					var mp = _monster_plates.get(i)
					if mp != null and is_instance_valid(mp):
						mp.visible = false
					Fx.burst(arena, "explosion", _center(mw) + Vector2(0, mw.custom_minimum_size.y * 0.15), mw.custom_minimum_size.y * 0.8, Color(0.75, 0.7, 0.8), 18.0)
					await _tween_dissolve(mw)

	else:
		var i: int = int(turn["id"])
		var mw: Control = monster_wrappers.get(i)
		# Who it's about to hit: a line from the foe to its target first.
		var intent: Dictionary = Combat.monster_intent(state, i) if i < monsters.size() and float(monsters[i]["hp"]) > 0 else {}
		if mw and not intent.is_empty() and not intent.get("charging", false) and intent.get("target") != null:
			var th: Hero = intent["target"]
			if hero_wrappers.has(th.id):
				Fx.line(arena, _center(mw), _center(hero_wrappers[th.id]), Palette.HAZARD if intent.get("heavy_blow", false) else Color(1.0, 0.65, 0.55), 0.45)
				await _await_or_timeout(get_tree().create_timer(0.18).timeout, 1.0)

		var log_before2: int = (state["log"] as Array).size()
		GameState.resolve_turn_now()
		_spawn_procs(state, hero_wrappers)
		_spawn_barks(state, hero_wrappers)
		var new_lines: Array = (state["log"] as Array).slice(log_before2)
		_turn_sfx(new_lines)

		if i >= monsters.size() or mw == null or not is_instance_valid(mw):
			return
		var m: Dictionary = monsters[i]
		if " ".join(new_lines).contains("gathers its strength"):
			# Winding up: red motes pulled in and a slow red glow, no strike yet.
			Fx.sparkles(arena, _center(mw), Palette.HAZARD, 26, mw.custom_minimum_size.x * 0.6, true, 0.6)
			var gt := create_tween()
			gt.tween_property(mw, "modulate", Color(1.6, 0.7, 0.6), 0.3)
			gt.tween_property(mw, "modulate", Color(1, 1, 1), 0.3)
			await _await_or_timeout(gt.finished, 1.0)
			return

		var victims: Array = party.filter(func(x): return int(hp_before.get(x.id, x.hp)) > x.hp and hero_wrappers.has(x.id))
		var heavy_blow: bool = bool(intent.get("heavy_blow", false))
		var mtint := Fx.element_color(str(m.get("type", "")))
		var start_x: float = mw.position.x
		var dashed := false
		if not victims.is_empty():
			var vw: Control = hero_wrappers[victims[0].id]
			if _monster_is_ranged(str(m["name"])):
				if monster_rects.has(i):
					_play_frames(monster_rects[i], GameData.monster_anim_frames(str(m["name"]), "attack"))
				await _await_or_timeout(Fx.projectile(arena, "bolt", _center(mw) - Vector2(mw.custom_minimum_size.x * 0.3, 10), _center(vw), 30.0, mtint.lerp(Color(1, 0.4, 0.5), 0.3), 0.26).finished, 1.0)
			else:
				dashed = true
				await _dash(mw, vw.position.x + vw.custom_minimum_size.x * 0.85, 0.16 if not heavy_blow else 0.22)
				if monster_rects.has(i):
					await _play_frames(monster_rects[i], GameData.monster_anim_frames(str(m["name"]), "attack"), 0.06)
		elif monster_rects.has(i):
			await _play_frames(monster_rects[i], GameData.monster_anim_frames(str(m["name"]), "attack"))
		if heavy_blow and not victims.is_empty():
			var vw2: Control = hero_wrappers[victims[0].id]
			Fx.ring(arena, vw2.position + Vector2(vw2.custom_minimum_size.x * 0.5, vw2.custom_minimum_size.y), vw2.custom_minimum_size.x * 1.3, Palette.HAZARD, 0.45)
			_camera_punch(arena, 1.06)

		var retaliation_color: Color = Palette.ELEMENT_PARTICLE_COLOR.get(str(m.get("type", "")), Color(1, 1, 1))
		for h in party:
			if not is_instance_valid(arena):
				return
			var before: int = int(hp_before.get(h.id, h.hp))
			var dmg2: int = before - h.hp
			if dmg2 > 0 and hero_wrappers.has(h.id):
				var hwv: Control = hero_wrappers[h.id]
				var heavy2: bool = float(dmg2) >= Combat.max_hp(h) * 0.25
				if heavy2:
					AudioManager.cue("hit_heavy", tr("[Heavy blow on %s]") % tr(str(h.name.split(" the ")[0])), Palette.HAZARD)
				else:
					AudioManager.play_sfx(GameData.SFX_PATH["hit"])
				Fx.burst(arena, "claw", _center(hwv), hwv.custom_minimum_size.y * (0.75 if heavy2 else 0.55), Color.WHITE, 24.0, 0.0, true)
				_spawn_impact_particles(hwv, hwv.custom_minimum_size * 0.5, retaliation_color, heavy2)
				_knockback(hwv, -1.0, heavy2)
				_plate_set_hp(_hero_plates.get(h.id), h.hp)
				if not burn_before.has(h.id) and (state.get("hero_burn", {}) as Dictionary).has(h.id):
					Fx.burst(arena, "flame", _center(hwv) + Vector2(0, hwv.custom_minimum_size.y * 0.2), hwv.custom_minimum_size.y * 0.45, Color.WHITE, 14.0)
				if not chill_before.has(h.id) and (state.get("_chilled", {}) as Dictionary).has(h.id):
					Fx.sigil(arena, _center(hwv), hwv.custom_minimum_size.x * 0.9, Palette.CRYSTALS, 0.5)
				await _impact_beat(arena, heavy2)
				var frames := GameData.hero_combat_frames(h.cls_id, h.pool_id, "hurt")
				if not frames.is_empty() and hero_rects.has(h.id):
					await _play_frames(hero_rects[h.id], frames)
				else:
					await _tween_hurt(hwv)
				await _spawn_damage_number(hwv, "-%d" % dmg2, Palette.HAZARD, heavy2)
				if before > 0 and h.hp <= 0:
					AudioManager.cue("knockout", tr("[%s is down]") % tr(str(h.name.split(" the ")[0])), Palette.HAZARD)
					await _tween_collapse(hwv)
		if dashed and is_instance_valid(mw):
			_dash(mw, start_x, 0.2)

	# A won fight is only detectable by re-checking node_state — Combat.resolve_turn's
	# return value never reaches here directly, only GameState.resolve_turn_now()'s
	# side effect on run["node_state"]["result"] does. Plays once, right after the
	# turn that actually finished the fight, before the caller's render() replaces
	# the arena with the victory screen.
	_sync_plates(state)
	var ns_after: Dictionary = GameState.run.get("node_state", {})
	if ns_after.has("result") and bool(ns_after["result"].get("won", false)):
		AudioManager.play_sfx(GameData.SFX_PATH["victory"])
		for h in party:
			if h.hp > 0 and hero_wrappers.has(h.id):
				Fx.sparkles(arena, _center(hero_wrappers[h.id]), Palette.RANK_S, 12, 40.0)
				await _tween_victory_pose(hero_wrappers[h.id])


# ---------------- Choreography ----------------

func _center(w: Control) -> Vector2:
	return w.position + w.custom_minimum_size * 0.5


func _first_wrapper(wrappers: Dictionary) -> Control:
	for k in wrappers:
		if is_instance_valid(wrappers[k]):
			return wrappers[k]
	return null


## Melee heroes (Warrior, Rogue) close in to strike; the rest attack from range.
const MELEE_ROLES := ["warrior", "rogue"]
## Foes that shoot instead of rushing their target.
func _monster_is_ranged(name: String) -> bool:
	return GameData.RANGED_FOE_WORDS.any(func(w): return name.contains(w))


## Slides a wrapper horizontally to `to_x` (a dash in or the return trip).
func _dash(w: Control, to_x: float, dur: float = 0.15) -> void:
	if not is_instance_valid(w):
		return
	var t := create_tween()
	t.tween_property(w, "position:x", to_x, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN if to_x != w.position.x else Tween.EASE_OUT)
	await _await_or_timeout(t.finished, dur + 1.0)


## A shove away from the hit (dir +1 pushes right, -1 left), springing back.
func _knockback(w: Control, dir: float, heavy: bool) -> void:
	if GameState.reduce_motion:
		return
	var sx := w.position.x
	var t := create_tween()
	t.tween_property(w, "position:x", sx + dir * (16.0 if heavy else 8.0), 0.06).set_ease(Tween.EASE_OUT)
	t.tween_property(w, "position:x", sx, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A quick zoom-in on the arena for the big moments.
func _camera_punch(arena: Control, amount: float = 1.035) -> void:
	if GameState.reduce_motion:
		return
	var t := create_tween()
	t.tween_property(arena, "scale", Vector2(amount, amount), 0.06).set_ease(Tween.EASE_OUT)
	t.tween_property(arena, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SINE)


func _anim_hero_attack(h: Hero, hw: Control, rect: TextureRect, tw: Control, tint: Color, arena: Control) -> void:
	AudioManager.play_sfx(GameData.SFX_PATH["attack"])
	var frames := GameData.hero_combat_frames(h.cls_id, h.pool_id, "attack")
	var role := GameData.hero_role(h)
	if tw == null:
		if not frames.is_empty() and rect:
			await _play_frames(rect, frames)
		else:
			await _tween_lunge(hw)
		return
	if role in MELEE_ROLES:
		var sx := hw.position.x
		await _dash(hw, tw.position.x - hw.custom_minimum_size.x * 0.9, 0.14)
		if not frames.is_empty() and rect:
			await _play_frames(rect, frames, 0.05)
		Fx.burst(arena, "slash", _center(tw), tw.custom_minimum_size.y * 0.95, tint.lerp(Color.WHITE, 0.55), 16.0, randf_range(-0.5, 0.3))
		_dash(hw, sx, 0.18)
	else:
		if not frames.is_empty() and rect:
			await _play_frames(rect, frames, 0.06)
		else:
			await _tween_lunge(hw)
		var arrow := role == "ranger"
		var col: Color = Color.WHITE if arrow else (Palette.RANK_S if role == "cleric" else tint.lerp(Color.WHITE, 0.25))
		var from := _center(hw) + Vector2(hw.custom_minimum_size.x * 0.3, -hw.custom_minimum_size.y * 0.1)
		await _await_or_timeout(Fx.projectile(arena, "arrow" if arrow else "bolt", from, _center(tw), 44.0 if arrow else 34.0, col, 0.26).finished, 1.0)


## An Ability: a charge-up on the caster, their skill frames, then the
## ability type's signature effect in their element's colour.
func _anim_hero_ability(h: Hero, action: String, hw: Control, rect: TextureRect, tw: Control, tint: Color, arena: Control, state: Dictionary, hero_wrappers: Dictionary, monster_wrappers: Dictionary, hp_before: Dictionary, shields_before: Dictionary, monster_hp_before: Array) -> void:
	AudioManager.play_sfx(GameData.SFX_PATH["attack"])
	var ab: Dictionary = GameData.SUBCLASS_ABILITIES.get(h.pool_id, {})
	var bucket: String = "call" if action == "call" else str(GameData.ABILITY_AWAKENING_BUCKET.get(str(ab.get("effect", "")), "buff"))
	var role := GameData.hero_role(h)
	var charge := Palette.RANK_S if action == "call" else tint
	Fx.sparkles(arena, _center(hw), charge, 24, hw.custom_minimum_size.x * 0.7, true, 0.35)
	var g := create_tween()
	g.tween_property(hw, "modulate", Color(1.0 + charge.r * 0.6, 1.0 + charge.g * 0.6, 1.0 + charge.b * 0.6), 0.25)
	await _await_or_timeout(g.finished, 1.0)
	var frames := GameData.hero_combat_frames(h.cls_id, h.pool_id, "skill")
	if not frames.is_empty() and rect:
		await _play_frames(rect, frames, 0.06)
	else:
		await _tween_skill_flash(hw)
	if is_instance_valid(hw):
		create_tween().tween_property(hw, "modulate", Color.WHITE, 0.2)
	var foes: Array = monster_wrappers.values().filter(func(w): return is_instance_valid(w))
	match bucket:
		"single_dmg":
			if tw:
				if role in MELEE_ROLES:
					var sx := hw.position.x
					await _dash(hw, tw.position.x - hw.custom_minimum_size.x * 0.9, 0.12)
					Fx.burst(arena, "slash", _center(tw), tw.custom_minimum_size.y, tint.lerp(Color.WHITE, 0.4), 24.0, -0.4)
					Fx.burst(arena, "slash", _center(tw), tw.custom_minimum_size.y * 0.9, tint.lerp(Color.WHITE, 0.4), 24.0, 1.2, true)
					_camera_punch(arena)
					_dash(hw, sx, 0.2)
				elif role == "cleric":
					await _await_or_timeout(Fx.burst(arena, "holy", _center(tw) - Vector2(0, tw.custom_minimum_size.y * 0.1), tw.custom_minimum_size.y * 1.3, Color.WHITE, 22.0).finished, 1.5)
				else:
					await _await_or_timeout(Fx.projectile(arena, "arrow" if role == "ranger" else "bolt", _center(hw), _center(tw), 44.0, tint.lerp(Color.WHITE, 0.2), 0.24).finished, 1.0)
					Fx.burst(arena, "impact", _center(tw), tw.custom_minimum_size.y * 0.9, tint.lerp(Color.WHITE, 0.3), 24.0)
					_camera_punch(arena)
		"aoe_dmg", "call":
			if action == "call":
				Fx.burst(arena, "holy", _center(hw) - Vector2(0, hw.custom_minimum_size.y * 0.1), hw.custom_minimum_size.y * 1.4, Color.WHITE, 20.0)
			for fw in foes:
				Fx.burst(arena, "explosion", _center(fw), fw.custom_minimum_size.y * 0.85, Color.WHITE.lerp(tint, 0.35) if action != "call" else Color.WHITE, 18.0)
				Fx.ring(arena, fw.position + Vector2(fw.custom_minimum_size.x * 0.5, fw.custom_minimum_size.y), fw.custom_minimum_size.x * 1.2, tint, 0.4)
			_camera_punch(arena, 1.05)
			await _await_or_timeout(get_tree().create_timer(0.25).timeout, 1.0)
		"support":
			var helped := false
			for hid in hero_wrappers:
				var ally := _hero_by_id(state["party"], str(hid))
				if ally == null or not is_instance_valid(hero_wrappers[hid]):
					continue
				var aw: Control = hero_wrappers[hid]
				if ally.hp > int(hp_before.get(ally.id, ally.hp)):
					helped = true
					Fx.sparkles(arena, _center(aw) + Vector2(0, aw.custom_minimum_size.y * 0.3), Palette.RANK_E, 22, aw.custom_minimum_size.x * 0.6)
					Fx.burst(arena, "holy", _center(aw), aw.custom_minimum_size.y * 1.1, Color(0.7, 1.3, 0.8), 22.0)
				if float(state.get("hero_shields", {}).get(ally.id, 0.0)) > float(shields_before.get(ally.id, 0.0)):
					helped = true
					Fx.dome(arena, _center(aw), aw.custom_minimum_size.x * 1.15, Color(0.7, 0.9, 1.0), 0.6)
			if not helped:
				Fx.sparkles(arena, _center(hw), Palette.RANK_E, 20, 50.0)
			await _await_or_timeout(get_tree().create_timer(0.35).timeout, 1.0)
		"buff":
			for hid in hero_wrappers:
				var bw: Control = hero_wrappers[hid]
				if is_instance_valid(bw):
					Fx.ring(arena, bw.position + Vector2(bw.custom_minimum_size.x * 0.5, bw.custom_minimum_size.y), bw.custom_minimum_size.x, Palette.RANK_S, 0.45)
					Fx.sparkles(arena, _center(bw) + Vector2(0, bw.custom_minimum_size.y * 0.3), tint.lerp(Palette.RANK_S, 0.5), 14, bw.custom_minimum_size.x * 0.5)
			await _await_or_timeout(get_tree().create_timer(0.35).timeout, 1.0)
		_:
			# Debuffs and utility: a curse sigil on the target.
			if tw:
				await _await_or_timeout(Fx.sigil(arena, _center(tw), tw.custom_minimum_size.x * 1.1, Palette.VIOLET_BRIGHT, 0.5).finished, 1.5)


## Guard: the guard leaps in front of the ally, raises a shield, and hops back.
func _anim_guard(hw: Control, aw: Control, arena: Control) -> void:
	if aw == null or not is_instance_valid(aw):
		await _tween_defend(hw)
		return
	var start := hw.position
	var dest := Vector2(aw.position.x + aw.custom_minimum_size.x * 0.4, start.y)
	var t := create_tween()
	t.tween_property(hw, "position", Vector2((start.x + dest.x) * 0.5, start.y - 24.0), 0.12).set_ease(Tween.EASE_OUT)
	t.tween_property(hw, "position", dest, 0.12).set_ease(Tween.EASE_IN)
	await _await_or_timeout(t.finished, 1.0)
	if not is_instance_valid(hw):
		return
	Fx.dome(arena, _center(hw), hw.custom_minimum_size.x * 1.2, Color(0.75, 0.9, 1.0), 0.4)
	await _await_or_timeout(get_tree().create_timer(0.35).timeout, 1.0)
	if is_instance_valid(hw):
		var back := create_tween()
		back.tween_property(hw, "position", start, 0.2)
		await _await_or_timeout(back.finished, 1.0)


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
	if GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.disconnect(_on_state_changed)
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
						if not _auto_battle:
							break
						state["pending_actions"][h.id] = Combat.auto_action(state, h)
		force = false
		if GameState.combat_speed >= INSTANT_SPEED:
			GameState.resolve_turn_now()   # Instant: no playback, the screen updates once at the end
			if GameState.run.get("node_state", {}).has("result"):
				break
			continue
		await _play_turn_bounded(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena)
		if GameState.run.get("node_state", {}).has("result"):
			break
		await _await_or_timeout(get_tree().create_timer(0.15).timeout, 1.0)
	if not GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.connect(_on_state_changed)
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
		var bw := _battle_width()
		v.add_child(_banner(GameData.BATTLE_BACKGROUNDS[pre_bg_idx], bw, roundf(clampf(bw * 0.36, 280.0, 420.0))))
		var kind_label := tr("Boss") if is_boss else (tr("Elite") if kind == "elite" else tr("Combat"))
		v.add_child(_label(tr("A %s encounter awaits.") % tr(str(kind_label)), 16))
		var guild_bits: Array[String] = []
		if GameState.lvl("ops.drill") > 0:
			guild_bits.append(tr("+%d%% damage and HP") % (GameState.lvl("ops.drill") * 4))
		if GameState.vanguard():
			guild_bits.append("Vanguard first strike")
		if GameState.abilities_ready_each_fight():
			guild_bits.append("+3 starting Momentum")
		if not guild_bits.is_empty():
			var gl := _label(tr("Drill Yard: ") + ", ".join(guild_bits), 12, true)
			gl.add_theme_color_override("font_color", Palette.RANK_E)
			v.add_child(gl)
		if kind == "combat":
			var qf := _icon_button("res://assets/skills/sword_dual.png", "Quick fight  (Q)", func():
				GameState.quick_fight()
			)
			qf.tooltip_text = "Play the whole fight out instantly on Auto and jump to the result"
			v.add_child(qf)
			_combat_hotkeys["Q"] = func(): GameState.quick_fight()
		_combat_hotkeys["Space"] = func(): GameState.engage_node()
		v.add_child(_icon_domain_button("ember", "res://assets/skills/sword_a.png", "Engage  (Space)", func():
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
		_render_battle(v, ns["combat_state"])
		return

	var result: Dictionary = ns["result"]
	# The result screen is one centered column, not the arena's full width.
	var rcol := _vbox(12)
	rcol.custom_minimum_size.x = 720
	rcol.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(rcol)
	v = rcol
	# The full fight log stays one click away instead of leading the screen.
	var log_row := HBoxContainer.new()
	log_row.add_theme_constant_override("separation", 8)
	log_row.add_child(_icon(GameData.sprite_for_monster(str(result["monster_name"])), 28))
	log_row.add_child(_label(tr("%s · %d round%s") % [tr(str(result["monster_name"])), int(result.get("rounds", 0)), tr(str(_pl(int(result.get("rounds", 0)))))], 14))
	log_row.add_child(_tool_button("res://assets/skills/eye_gem.png", "Hide log" if _combat_log_open else "Fight log", "Show or hide the full fight log", func():
		_combat_log_open = not _combat_log_open
		render()
	))
	v.add_child(log_row)
	if _combat_log_open:
		var log_party: Array[Hero] = GameState.current_party()
		v.add_child(_log_richtext(result["log"], log_party, [{"name": result["monster_name"]}]))

	if result["won"] and result.has("tower"):
		v.add_child(_tower_victory(result))
		return
	if result["won"]:
		# A single violet-domain banner frame for the whole victory moment
		# (heading + currency gained + reward cards) instead of plain stacked
		# labels — the same "wrap it in one bordered panel" treatment the
		# battle screen just got, so a win reads as a distinct occasion
		# rather than more of the same log-and-button stack.
		var victory_frame := PanelContainer.new()
		victory_frame.theme_type_variation = &"CardPanelViolet"
		var victory_col := _vbox(8)
		victory_frame.add_child(victory_col)

		# A level-up chime, once per won fight (keyed by the node position).
		var win_key := "win%d:%d" % [int(GameState.run.get("seed", 0)), int(GameState.run.get("pos", 0))]
		if result.has("heroes") and not _sfx_seen.has(win_key):
			_sfx_seen[win_key] = true
			if (result["heroes"] as Array).any(func(hs): return int(hs["lv1"]) > int(hs["lv0"])):
				AudioManager.play_sfx(GameData.SFX_PATH["level_up"])
		var vt := _label("Victory!", 28)
		vt.add_theme_color_override("font_color", Palette.RANK_S)
		victory_col.add_child(vt)
		var bonus_crystal: int = result.get("bonus_crystal", 0)
		var gains_row := HBoxContainer.new()
		gains_row.add_theme_constant_override("separation", 14)
		gains_row.add_child(_icon(GameData.CURRENCY_ICON_PATH["coins"], 18))
		gains_row.add_child(_label("+%d" % int(result["coin"]), 14))
		gains_row.add_child(_icon(GameData.CURRENCY_ICON_PATH["crystals"], 18))
		var crystal_text := "+%d" % int(result["crystal"])
		if int(result.get("guild_crystal", 0)) > 0:
			crystal_text += tr(" (%d from Amplifiers)") % int(result["guild_crystal"])
		if int(result.get("crystal_cache", 0)) > 0:
			crystal_text += tr("  +%d Essence cache (Resonance)") % int(result["crystal_cache"])
			bonus_crystal -= int(result["crystal_cache"])
		if bonus_crystal > 0:
			crystal_text += tr("  +%d extracted") % bonus_crystal
		gains_row.add_child(_label(crystal_text, 14))
		victory_col.add_child(gains_row)
		if result.has("heroes"):
			victory_col.add_child(_victory_party(result))
		if int(result.get("hand_bonus", 0)) > 0:
			var hb := _label(tr("Flawless, by hand: +%d Gold (no one went down and you played every turn).") % int(result["hand_bonus"]), 12)
			hb.add_theme_color_override("font_color", Palette.RANK_S)
			victory_col.add_child(hb)
		if str(result.get("escort_saved", "")) != "":
			victory_col.add_child(_label(tr("%s made it through safely — +2 Renown, +1 Token.") % tr(str(result["escort_saved"])), 12, true))
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
				var icon_path: String = GameData.relic_icon(obj) if is_relic else GameData.item_icon(obj)
				var note := _loot_fit_note(obj, is_relic, GameState.current_party())
				reward_row.add_child(_reward_tile(icon_path, _loot_display_name(obj), str(obj.rarity), desc, func(idx=i, legendary=(obj.rarity == "legendary")):
					GameState.pick_combat_reward(idx)
					if legendary:
						_flavor_toast = GameData.narrative_line("legendary_drop")
					render()
				, "" if is_relic else _item_card(obj, note[2]), note))
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
		if GameState.boon_pending():
			victory_col.add_child(_boon_offer_row(result))
		if (options.is_empty() or ns.get("reward_chosen", false)) and not GameState.boon_pending():
			var cont := _icon_domain_button("violet", GameData.BUTTON_ICON_PATH["confirm"], "Continue", func():
				if is_boss:
					GameState.seal_rift()
				else:
					GameState.advance_node()
				render()
			)
			cont.disabled = not GameState.pending_injuries().is_empty()
			if cont.disabled:
				cont.tooltip_text = "Decide what happens to the downed hero first (above)"
			victory_col.add_child(cont)
		v.add_child(victory_frame)
	else:
		var defeat_text := tr("You withdraw from the fight.") if result.get("retreated", false) else tr("Defeat — the party is downed and recovering.")
		if GameState.run.has("tower"):
			defeat_text = "The trial ends. Your heroes step out of the tower unharmed — this floor will be waiting, exactly as it was."
		var defeat_key := "defeat%d:%d" % [int(GameState.run.get("seed", 0)), int(GameState.run.get("pos", 0))]
		if not result.get("retreated", false) and not _sfx_seen.has(defeat_key):
			_sfx_seen[defeat_key] = true
			AudioManager.play_sfx(GameData.SFX_PATH["defeat"])
		v.add_child(_label(defeat_text))
		var reasons: Array = result.get("defeat_reasons", [])
		if not reasons.is_empty():
			v.add_child(_defeat_card(reasons))
		if str(result.get("flavor", "")) != "":
			v.add_child(_label(str(result["flavor"]), 12, true))
		var in_tower := GameState.run.has("tower")
		if not in_tower:
			for line in _run_summary_lines():
				v.add_child(_label(line, 12, true))
		v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["confirm"], tr("Back to the Tower") if in_tower else tr("Return to camp"), func():
			GameState.finish_run()
			screen = "tower" if in_tower else "camp"
			render()
		))


## "Why you lost": the fight's top causes, each with what to do about it.
func _defeat_card(reasons: Array) -> Control:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Palette.SURFACE2
	st.border_color = Palette.HAZARD
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", st)
	var col := _vbox(8)
	var head := _label("Why you lost", 16)
	head.add_theme_color_override("font_color", Palette.HAZARD)
	col.add_child(head)
	for r in reasons:
		var t := _wrap_label("• " + tr(str(r[0])), 14)
		col.add_child(t)
		var tip := _wrap_label(str(r[1]), 12, true)
		col.add_child(tip)
	p.add_child(col)
	return p


## The boon pick after an elite: three cards (family, what it does, what it
## would complete) and a Skip.
func _boon_offer_row(result: Dictionary) -> Control:
	var col := _vbox(6)
	var head := _label("Choose a boon — it lasts the rest of this rift", 14)
	head.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	col.add_child(head)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	var counts := GameState.boon_family_counts()
	var offer: Array = result.get("boon_offer", [])
	for i in offer.size():
		var b := GameData.find_boon(str(offer[i]))
		var fam: Dictionary = GameData.BOON_FAMILIES[b["family"]]
		var have := int(counts.get(b["family"], 0))
		var card := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Palette.SURFACE2
		st.border_color = fam["color"]
		st.set_border_width_all(2)
		st.set_corner_radius_all(8)
		st.set_content_margin_all(10)
		card.add_theme_stylebox_override("panel", st)
		card.custom_minimum_size = Vector2(200, 0)
		var cv := _vbox(4)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		top.add_child(_icon(str(fam["icon"]), 24))
		var nm := _label(str(b["name"]), 15)
		nm.add_theme_color_override("font_color", fam["color"])
		top.add_child(nm)
		cv.add_child(top)
		cv.add_child(_label(tr("%s · you have %d") % [tr(str(fam["name"])), have], 11, true))
		var d := _wrap_label(str(b["desc"]), 12)
		d.custom_minimum_size.x = 180
		cv.add_child(d)
		for step in GameData.BOON_SETS[b["family"]]:
			if have + 1 == int(step[0]):
				var sl := _wrap_label(tr("Completes %s: %s") % [tr(str(step[1]["name"])), tr(str(step[1]["desc"]))], 11)
				sl.add_theme_color_override("font_color", Palette.RANK_S)
				sl.custom_minimum_size.x = 180
				cv.add_child(sl)
		cv.add_child(_button("Take", func(k=i):
			GameState.pick_boon(k)
			render()
		))
		card.add_child(cv)
		row.add_child(card)
	col.add_child(row)
	col.add_child(_button("Skip the boon", func():
		GameState.pick_boon(-1)
		render()
	))
	return col


## The run's boons as family chips (count + tooltip listing boons and sets).
func _boon_chips() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var counts := GameState.boon_family_counts()
	for fam_id in counts:
		var fam: Dictionary = GameData.BOON_FAMILIES[fam_id]
		var chip := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(fam["color"], 0.18)
		st.border_color = fam["color"]
		st.set_border_width_all(1)
		st.set_corner_radius_all(6)
		st.content_margin_left = 6
		st.content_margin_right = 8
		chip.add_theme_stylebox_override("panel", st)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		h.add_child(_icon(str(fam["icon"]), 16))
		h.add_child(_label("%s %d" % [tr(str(fam["name"])), int(counts[fam_id])], 12))
		chip.add_child(h)
		var lines: Array[String] = []
		for id in GameState.run.get("boons", []):
			var b := GameData.find_boon(str(id))
			if b.get("family", "") == fam_id:
				lines.append("%s — %s" % [tr(str(b["name"])), tr(str(b["desc"]))])
		for step in GameData.BOON_SETS[fam_id]:
			var got := int(counts[fam_id]) >= int(step[0])
			lines.append(tr("%s %d-piece %s — %s") % [tr(str("✓" if got else "○")), int(step[0]), tr(str(step[1]["name"])), tr(str(step[1]["desc"]))])
		chip.tooltip_text = "\n".join(lines)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		row.add_child(chip)
	return row


## A cleared Tower floor: what it paid (first clear, relic, title) and the way back.
func _tower_victory(result: Dictionary) -> Control:
	var t: Dictionary = result["tower"]
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"CardPanelViolet"
	var col := _vbox(8)
	frame.add_child(col)
	var head := _label(tr("Floor %d cleared!") % int(t["floor"]), 28)
	head.add_theme_color_override("font_color", Palette.RANK_S)
	col.add_child(head)
	var gains := HBoxContainer.new()
	gains.add_theme_constant_override("separation", 14)
	for pair in [["coins", "coins"], ["crystals", "crystals"]]:
		if int(t[pair[0]]) > 0:
			gains.add_child(_icon(GameData.CURRENCY_ICON_PATH[pair[1]], 18))
			gains.add_child(_label("+%d" % int(t[pair[0]]), 14))
	col.add_child(gains)
	if not bool(t["first"]):
		col.add_child(_label("A weekly re-clear pays half.", 12, true))
	if str(t["relic"]) != "":
		var rl := _label(tr("Guardian's relic: %s") % tr(str(t["relic"])), 16)
		rl.add_theme_color_override("font_color", Palette.RANK_S)
		col.add_child(rl)
		col.add_child(_wrap_label(str(GameData.TOWER_RELICS[int(t["floor"])]["desc"]) + tr(" It's on the Relic Altar."), 12, true))
	if str(t["title"]) != "":
		var tl := _label(tr("New guild title: %s") % tr(str(t["title"])), 16)
		tl.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		col.add_child(tl)
	if result.has("heroes"):
		col.add_child(_victory_party(result))
	var next := GameState.tower_next_floor()
	col.add_child(_icon_domain_button("violet", GameData.BUTTON_ICON_PATH["confirm"], tr("Back to the Tower") + (tr(" — floor %d next") % next if next > 0 else ""), func():
		GameState.finish_run()
		screen = "tower"
		render()
	))
	return frame


## A short recap for the two screens a run can end on (sealed or wiped/
## retreated) — floor reached, net currency change this run (Gold/Essence
## can be spent as well as earned mid-run, e.g. at a shop, so "net
## change" is the honest framing, not "earned"), and heroes lost if any. Deliberately reads only numbers that already exist or are a cheap
## snapshot diff — no new combat-hot-path instrumentation.
func _run_summary_lines() -> Array[String]:
	var lines: Array[String] = []
	var layers: Array = GameState.run.get("layers", [])
	if not layers.is_empty():
		lines.append(tr("Floor %d/%d reached") % [int(GameState.run.get("pos", 0)) + 1, layers.size()])
	var coin_delta := GameState.coins - int(GameState.run.get("start_coins", GameState.coins))
	var crystal_delta := GameState.crystals - int(GameState.run.get("start_crystals", GameState.crystals))
	lines.append(tr("%+d Gold, %+d Essence this run") % [coin_delta, crystal_delta])
	var lost := int(GameState.run.get("heroes_lost", 0))
	if lost > 0:
		lines.append(tr("%d hero%s lost") % [lost, tr(str(_pl(lost, "es")))])
	return lines


# ----------------------------------------------------------------------------
# Battle screen layout
# ----------------------------------------------------------------------------

var _hero_plates: Dictionary = {}      # hero id -> unit plate (live HP updates during playback)
var _monster_plates: Dictionary = {}   # monster index -> unit plate
var _combat_target: int = -1           # the foe Attack / key 1 hits; click a foe or Tab to change
var _combat_log_open: bool = false
var _ally_pick: String = ""       # "guard"/"tonic": the command bar is asking which ally; "tonic_kind": which tonic
var _tonic_kind: String = "healing"
var _guard_picker_for: String = ""     # the hero that picker belongs to
var _banner_state: Dictionary = {}     # the fight + round whose "Round N" slide-in already played
var _banner_round: int = -1
var _boss_intro_for: Dictionary = {}   # the combat state whose boss intro already played (by reference)

const UNIT_PLATE_H := 44.0   # name/HP row + bar + status row


## Arena width: the content column, capped so a huge window doesn't blow the
## pixel art up past readability.
func _battle_width() -> float:
	var vw: float = get_viewport().get_visible_rect().size.x
	return clampf(vw - 72.0, minf(700.0, vw - 32.0), 1180.0)


## A compact unit plate: name and HP on one line, an HP bar with a trailing
## "damage taken" chip behind it, a thin shield bar, and a row of status
## icons. _plate_set_hp() animates it while a turn plays out.
func _unit_plate(name_text: String, hp: int, max_val: int, width: float, shield: float = 0.0, statuses: Array = []) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(width, UNIT_PLATE_H)
	wrap.size = wrap.custom_minimum_size
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Name shrinks (clipped) to leave the HP number its full width.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	top.size = Vector2(width, 16)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_l := _label(name_text, 12)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.custom_minimum_size.x = 20
	_shadow(name_l)
	top.add_child(name_l)
	var hp_l := _label("%d/%d" % [max(0, hp), max_val], 12)
	hp_l.add_theme_color_override("font_color", Palette.TEXT)
	_shadow(hp_l)
	top.add_child(hp_l)
	wrap.add_child(top)

	var chip := _flat_bar(max_val, hp, width, 8, Color(1.0, 0.93, 0.8))
	chip.position = Vector2(0, 17)
	wrap.add_child(chip)
	var fill := _flat_bar(max_val, hp, width, 8, _hp_color(float(max(0, hp)) / float(max(1, max_val))), true)
	fill.position = chip.position
	wrap.add_child(fill)
	if shield > 0.0:
		var sb := _flat_bar(max_val, int(min(shield, max_val)), width, 3, Palette.CRYSTALS)
		sb.position = Vector2(0, 26)
		sb.tooltip_text = tr("Shield: absorbs the next %d damage") % int(round(shield))
		wrap.add_child(sb)

	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 3)
	icons.position = Vector2(0, 30)
	for s in statuses:
		var badge := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color(Palette.INK, 0.85)
		st.border_color = s.get("color", Palette.LINE)
		st.set_border_width_all(1)
		st.set_corner_radius_all(999)
		st.set_content_margin_all(1)
		badge.add_theme_stylebox_override("panel", st)
		badge.add_child(_icon(str(s["icon"]), 12))
		badge.tooltip_text = str(s["tip"])
		icons.add_child(badge)
	wrap.add_child(icons)

	wrap.set_meta("fill", fill)
	wrap.set_meta("chip", chip)
	wrap.set_meta("hp_label", hp_l)
	wrap.set_meta("max", max_val)
	return wrap


func _shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)


## Drops the bar to `hp` at once and lets the pale "damage taken" chip catch
## up a beat later; a heal raises both together.
func _plate_set_hp(plate, hp: float) -> void:
	if plate == null or not is_instance_valid(plate):
		return
	var fill: ProgressBar = plate.get_meta("fill")
	var chip: ProgressBar = plate.get_meta("chip")
	var max_val: int = plate.get_meta("max")
	var v := clampf(hp, 0.0, float(max_val))
	(plate.get_meta("hp_label") as Label).text = "%d/%d" % [int(round(v)), max_val]
	(fill.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = _hp_color(v / float(max(1, max_val)))
	if v >= fill.value:
		fill.value = v
		chip.value = v
		return
	fill.value = v
	var tw := chip.create_tween()
	tw.tween_interval(0.25)
	tw.tween_property(chip, "value", v, 0.45).set_ease(Tween.EASE_OUT)


func _sync_plates(state: Dictionary) -> void:
	for h in state["party"]:
		_plate_set_hp(_hero_plates.get(h.id), h.hp)
	var monsters: Array = state["monsters"]
	for i in monsters.size():
		_plate_set_hp(_monster_plates.get(i), float(monsters[i]["hp"]))


## A flat ellipse on the ground under a unit — the acting hero's ring, the
## selected target's ring, or the hover highlight.
func _ground_ring(cx: float, feet: float, w: float, color: Color, filled: bool = false) -> Panel:
	var ring := Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(color, 0.25) if filled else Color(0, 0, 0, 0)
	st.border_color = color
	st.set_border_width_all(2)
	st.set_corner_radius_all(999)
	ring.add_theme_stylebox_override("panel", st)
	ring.size = Vector2(w, w * 0.3)
	ring.position = Vector2(cx - w * 0.5, feet - w * 0.15)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ring


func _pulse(node: CanvasItem, lo: float = 0.45, period: float = 0.7) -> void:
	var tw := node.create_tween().set_loops()
	tw.bind_node(node)
	tw.tween_property(node, "modulate:a", lo, period).set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "modulate:a", 1.0, period).set_trans(Tween.TRANS_SINE)


## Statuses shown under a hero's HP bar.
func _hero_statuses(state: Dictionary, h: Hero) -> Array:
	var out: Array = []
	if state.get("_defending", {}).has(h.id):
		out.append({"icon": "res://assets/skills/shield_basic.png", "tip": tr("Defending — takes reduced damage this round"), "color": Palette.VIOLET_BRIGHT})
	var sh := float(state.get("hero_shields", {}).get(h.id, 0.0))
	if sh > 0.0:
		out.append({"icon": "res://assets/skills/shield_blue.png", "tip": tr("Shield — absorbs the next %d damage") % int(round(sh)), "color": Palette.CRYSTALS})
	var burn: Dictionary = state.get("hero_burn", {})
	if burn.has(h.id):
		out.append({"icon": "res://assets/relics/escalate_pct.png", "tip": tr("Burning — %d damage a round for %d more round(s). A Healing Tonic puts it out.") % [int(round(float(burn[h.id]["value"]) * Combat.max_hp(h))), int(burn[h.id]["rounds"])], "color": Palette.HAZARD})
	if state.get("_chilled", {}).has(h.id):
		out.append({"icon": GameData.RELIC_TYPE_ICON_PATH["Frost"], "tip": tr("Chilled — acts late next round"), "color": Palette.CRYSTALS})
	if state.get("_stunned", {}).has(h.id):
		out.append({"icon": "res://assets/relics/u_stopped_clock.png", "tip": tr("Stunned — loses their next turn"), "color": Palette.HAZARD})
	var poison: Dictionary = state.get("hero_poison", {})
	if poison.has(h.id):
		out.append({"icon": "res://assets/skills/shard_green.png", "tip": tr("Poisoned — %d damage a round for %d more round(s)") % [int(round(float(poison[h.id]["value"]) * Combat.max_hp(h))), int(poison[h.id]["rounds"])], "color": Palette.RANK_E})
	var guarding: Dictionary = state.get("_guarding", {})
	if guarding.has(h.id):
		var g := _hero_by_id(state["party"], str(guarding[h.id]))
		if g:
			out.append({"icon": "res://assets/skills/shield_blue.png", "tip": tr("Guarded by %s this round") % tr(str(g.name)), "color": Palette.VIOLET_BRIGHT})
	if guarding.values().has(h.id):
		out.append({"icon": "res://assets/skills/shield_split.png", "tip": tr("Guarding an ally this round (takes their hits, 25% weaker)"), "color": Palette.VIOLET_BRIGHT})
	if state.get("_weakened", {}).has(h.id):
		out.append({"icon": "res://assets/skills/face_hood.png", "tip": tr("Cursed — deals %d%% less damage for %d more round(s). Sanctuary cleanses it.") % [int(GameData.CURSE_WEAKEN * 100), int(state["_weakened"][h.id])], "color": Palette.HAZARD})
	if state.get("_riposte", {}).has(h.id):
		out.append({"icon": "res://assets/skills/sword_silver.png", "tip": tr("Riposte — answers the next %d hit(s) with a counter-strike") % int(state["_riposte"][h.id]["left"]), "color": Palette.EMBER_BRIGHT})
	if state.get("_undying", {}).has(h.id):
		out.append({"icon": "res://assets/skills/heart.png", "tip": tr("Undying — half damage and can't fall this round"), "color": Palette.EMBER_BRIGHT})
	if state.get("_evade_next", {}).has(h.id):
		out.append({"icon": "res://assets/skills/cloak_a.png", "tip": tr("Will dodge the next hit aimed at them"), "color": Palette.CRYSTALS})
	if state.get("_branded", {}).has(h.id):
		out.append({"icon": "res://assets/skills/gem_red.png", "tip": tr("Branded — takes %d%% more damage for %d more round(s). Guard them.") % [int(GameData.BRAND_TAKEN * 100), int(state["_branded"][h.id])], "color": Palette.HAZARD})
	if str(state.get("_taunt", "")) == h.id:
		out.append({"icon": "res://assets/skills/helm.png", "tip": tr("Taunting — every foe's attacks come here this round, %d%% weaker") % int(float(state.get("_taunt_cut", 0.0)) * 100), "color": Palette.VIOLET_BRIGHT})
	if Combat.qualifies_for_ability(h) and Combat.action_block(state, h, "ability") == "":
		out.append({"icon": GameData.ability_icon(h.pool_id), "tip": tr("Enough Momentum for their Ability"), "color": Palette.EMBER_BRIGHT})
	return out


## Statuses shown under a monster's HP bar: its type, boss mechanics or
## monster ability, and a ward if it has one.
func _monster_statuses(state: Dictionary, i: int) -> Array:
	var m: Dictionary = state["monsters"][i]
	var out: Array = []
	for key in ["mechanic", "mechanic2"]:
		var mech: Dictionary = m.get(key, {})
		var icon: String = GameData.BOSS_MECHANIC_ICON.get(str(mech.get("id", "")), "")
		if icon != "":
			out.append({"icon": icon, "tip": "%s — %s" % [tr(str(mech["name"])), tr(str(mech["desc"]))], "color": Palette.ELITE})
	if m.has("phase"):
		var ph: Dictionary = GameData.BOSS_PHASES[m["phase"]]
		out.append({"icon": ph["icon"], "tip": "%s — %s%s" % [tr(str(ph["name"])), tr(str(ph["desc"])), tr(str(" (active)" if m.get("_phased", false) else ""))], "color": Palette.HAZARD if m.get("_phased", false) else Palette.ELITE})
	for a in m.get("affixes", []):
		var af: Dictionary = GameData.ELITE_AFFIXES[a]
		out.append({"icon": af["icon"], "tip": "%s — %s" % [tr(str(af["name"])), tr(str(af["desc"]))], "color": Palette.ELITE})
	var ability: Dictionary = m.get("ability", {})
	if m.get("mechanic", {}).is_empty() and not ability.is_empty() and not m.has("affixes"):
		var a_icon: String = GameData.MONSTER_ABILITY_ICON.get(str(ability["kind"]), "")
		if a_icon != "":
			out.append({"icon": a_icon, "tip": str(ability["name"]), "color": Palette.ELITE})
	var armor := float(m.get("armor", 0.0))
	if armor > 0.0:
		out.append({"icon": "res://assets/skills/armor_chest.png", "tip": tr("Armored — shrugs off %d%% of basic attacks (each hit chips it). Abilities ignore armor.") % int(round(armor * 100)), "color": Palette.LINE})
	match str(m.get("status", "")):
		"burn": out.append({"icon": "res://assets/relics/escalate_pct.png", "tip": tr("Its hits can set a hero ablaze (damage over time)"), "color": Palette.HAZARD})
		"chill": out.append({"icon": GameData.RELIC_TYPE_ICON_PATH["Frost"], "tip": tr("Its hits can chill a hero (acts late next round)"), "color": Palette.CRYSTALS})
	if m.get("_charged", false) or m.get("_winding", false):
		out.append({"icon": "res://assets/skills/sword_big.png", "tip": tr("Winding up a heavy blow. Shield Bash, Frost Nova or Backstab can punish it."), "color": Palette.HAZARD})
	if state.get("_m_stunned", {}).has(i):
		out.append({"icon": "res://assets/skills/star.png", "tip": tr("Stunned — loses its next %s") % tr(str(("action" if int(state["_m_stunned"][i]) <= 1 else tr("%d actions") % int(state["_m_stunned"][i])))), "color": Palette.EMBER_BRIGHT})
	var mb: Dictionary = state.get("_m_burn", {}).get(i, {})
	if not mb.is_empty():
		out.append({"icon": "res://assets/relics/escalate_pct.png", "tip": tr("Burning — %d damage a round for %d more round(s)") % [int(round(float(mb["dmg"]))), int(mb["rounds"])], "color": Palette.HAZARD})
	if float(m.get("_marked", 0.0)) > 0.0:
		out.append({"icon": "res://assets/skills/eye_gem.png", "tip": tr("Marked — takes %d%% more damage from heroes") % int(round(float(m["_marked"]) * 100)), "color": Palette.HAZARD})
	var kit: Array = m.get("kit", [])
	if not kit.is_empty():
		var moves: Array = kit.map(func(k): return str(GameData.INTENT_INFO[k]["name"]))
		out.append({"icon": "res://assets/skills/eye_gem.png", "tip": tr("Can also: %s (telegraphed a round ahead)") % tr(str(", ".join(moves))), "color": Palette.LINE})
	var ward := float(state.get("monster_shields", {}).get(i, 0.0))
	if ward > 0.0:
		out.append({"icon": "res://assets/skills/shield_blue.png", "tip": tr("Ward — absorbs the next %d damage") % int(round(ward)), "color": Palette.CRYSTALS})
	return out


func _render_battle(v: VBoxContainer, state: Dictionary) -> void:
	var monsters: Array = state["monsters"]
	var party: Array[Hero] = state["party"]
	var living_heroes: Array[Hero] = []
	living_heroes.assign(party.filter(func(h): return h.hp > 0))
	var W := _battle_width()
	var H: float = roundf(clampf(W * 0.36, 280.0, 420.0))
	_hero_plates = {}
	_monster_plates = {}

	var turn_order: Array = state.get("turn_order", [])
	var turn_idx: int = int(state.get("turn_idx", 0))
	var current_turn: Dictionary = turn_order[turn_idx] if turn_idx < turn_order.size() else {}
	var current_hero: Hero = null
	if str(current_turn.get("type", "")) == "hero":
		var candidate := _hero_by_id(party, str(current_turn["id"]))
		if candidate and candidate.hp > 0:
			current_hero = candidate
	var acting_monster: int = int(current_turn["id"]) if str(current_turn.get("type", "")) == "monster" else -1
	if current_hero == null or current_hero.id != _guard_picker_for:
		_ally_pick = ""
	_guard_picker_for = current_hero.id if current_hero else ""

	var living_idx: Array[int] = []
	for i in monsters.size():
		if float(monsters[i]["hp"]) > 0:
			living_idx.append(i)
	if current_hero and not living_idx.has(_combat_target):
		var pt := int(state["pending_actions"].get(current_hero.id, {}).get("target", -1))
		_combat_target = pt if living_idx.has(pt) else (living_idx[0] if not living_idx.is_empty() else -1)

	var arena := Control.new()
	arena.custom_minimum_size = Vector2(W, H)
	arena.clip_contents = true
	var bg := TextureRect.new()
	bg.texture = load(GameData.BATTLE_BACKGROUNDS[int(state["background_idx"]) % GameData.BATTLE_BACKGROUNDS.size()])
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.size = Vector2(W, H)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(bg)

	var hero_wrappers: Dictionary = {}
	var hero_rects: Dictionary = {}
	var monster_wrappers: Dictionary = {}
	var monster_rects: Dictionary = {}
	var ground := H * 0.86

	# What each monster will do this round, summed per targeted hero.
	var incoming := {}   # hero id -> {dmg, heavy, from: [names]}
	for i in living_idx:
		var intent := Combat.monster_intent(state, i)
		if intent.is_empty():
			continue
		var hit_list: Array = intent.get("targets", []) if intent.has("targets") else ([intent["target"]] if intent.get("target") != null and int(intent["dmg"]) > 0 or intent.get("charging", false) else [])
		for t in hit_list:
			var e: Dictionary = incoming.get(t.id, {"dmg": 0, "heavy": false, "from": []})
			e["dmg"] = int(e["dmg"]) + int(intent["dmg"])
			e["heavy"] = bool(e["heavy"]) or bool(intent["heavy"]) or intent.get("charging", false)
			(e["from"] as Array).append("%s (%s)" % [tr(str(monsters[i]["name"])), tr(str(tr("winding up a heavy blow") if intent.get("charging", false) else str(int(intent["dmg"]))))])
			incoming[t.id] = e

	# --- Heroes: back row on the left, front row nearest the enemy. ---
	var line: Array[Hero] = []
	for h in living_heroes:
		if h.formation == "back" and GameData.portrait_for_hero(h.cls_id, h.pool_id) != "":
			line.append(h)
	for h in living_heroes:
		if h.formation != "back" and GameData.portrait_for_hero(h.cls_id, h.pool_id) != "":
			line.append(h)
	var hz_x := W * 0.03
	var hz_w := W * 0.49
	# One pixel scale for every combatant: heroes and monsters share the same
	# 200px canvas, drawn at a clean factor of it (the boss a step larger).
	var px := _battle_px_scale(H)
	var h_slot: float = minf(150.0, hz_w / max(1, line.size()))
	var h_start: float = hz_x + hz_w - h_slot * line.size()
	var target_rings := {}   # hero id -> hover ring shown while an intent aimed at them is hovered
	for k in line.size():
		var h: Hero = line[k]
		var is_back := h.formation == "back"
		var size: float = roundf(200.0 * px)
		var feet: float = ground - (H * 0.06 if is_back else 0.0)
		var cx: float = h_start + h_slot * (k + 0.5) + (10.0 if h == current_hero else 0.0)
		var ring_w: float = size * 0.8
		var hover_ring := _ground_ring(cx, feet, ring_w, Palette.HAZARD, true)
		hover_ring.visible = false
		arena.add_child(hover_ring)
		target_rings[h.id] = hover_ring
		if h == current_hero:
			var ring := _ground_ring(cx, feet, ring_w, Palette.EMBER_BRIGHT)
			arena.add_child(ring)
			_pulse(ring)
		var rect := _hero_icon(h, int(size))
		rect.flip_h = GameData.faces_away(GameData.portrait_for_hero(h.cls_id, h.pool_id))
		var wrapper := _wrap_icon(rect)
		wrapper.position = Vector2(cx - size * 0.5, feet - size)
		_add_ground_shadow(arena, wrapper.position, size)
		arena.add_child(wrapper)
		if (state.get("hero_burn", {}) as Dictionary).has(h.id):
			var fl := Fx.loop(wrapper, "flame", Vector2(size * 0.5, size * 0.72), size * 0.34, Color(1, 1, 1, 0.85))
			fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_start_idle_sway(wrapper)
		hero_wrappers[h.id] = wrapper
		hero_rects[h.id] = rect
		var pw: float = minf(h_slot - 16.0, 124.0)
		var sh := float(state.get("hero_shields", {}).get(h.id, 0.0))
		var plate := _unit_plate(h.name.split(" the ")[0], h.hp, Combat.max_hp(h), pw, sh, _hero_statuses(state, h))
		plate.position = Vector2(cx - pw * 0.5, feet - size - UNIT_PLATE_H - 2.0)
		if h == current_hero:
			plate.get_child(0).get_child(0).add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		arena.add_child(plate)
		_hero_plates[h.id] = plate
		if incoming.has(h.id):
			var e: Dictionary = incoming[h.id]
			var chip := _intent_chip("-%d" % int(e["dmg"]) if int(e["dmg"]) > 0 else tr("Next round!"), bool(e["heavy"]), tr("Incoming this round: %s") % tr(str(", ".join(e["from"]))))
			chip.position = plate.position + Vector2(pw - 38.0, -20.0)
			arena.add_child(chip)

	# --- Monsters: defeated foes leave the field. ---
	var big_i := -1
	if state.get("is_boss", false) or state.get("is_elite", false):
		for i in monsters.size():
			if big_i < 0 or float(monsters[i]["max_hp"]) > float(monsters[big_i]["max_hp"]):
				big_i = i
	var mz_x := W * 0.56
	var mz_w := W * 0.41
	var m_slot: float = mz_w / max(1, monsters.size())
	var next_round: int = int(state.get("round_num", 0))
	for i in monsters.size():
		var m: Dictionary = monsters[i]
		if float(m["hp"]) <= 0:
			continue
		# Monster art is drawn on the same 200px canvas as the heroes, so one
		# scale for all keeps every sprite at the heroes' pixel size (and a
		# small creature small); the boss/elite is drawn a size class up.
		var m_rect := _sprite_fit(GameData.sprite_for_monster(str(m["name"])), minf(1.0, px + 0.25) if i == big_i else px, m_slot * 1.1)
		m_rect.flip_h = GameData.faces_away(GameData.sprite_for_monster(str(m["name"])))
		var msz: Vector2 = m_rect.custom_minimum_size
		var ring_w: float = minf(msz.x, msz.y * 1.2) * 0.8
		var cx: float = mz_x + m_slot * (i + 0.5)
		var feet: float = ground - (H * 0.06 if i % 2 == 1 else 0.0)
		if i == _combat_target and current_hero:
			var tring := _ground_ring(cx, feet, ring_w, Palette.HAZARD)
			arena.add_child(tring)
			_pulse(tring)
		if i == acting_monster:
			arena.add_child(_ground_ring(cx, feet, ring_w, Palette.EMBER_BRIGHT))
		var m_wrapper := _wrap_icon(m_rect)
		m_wrapper.position = Vector2(cx - msz.x * 0.5, feet - msz.y)
		_add_ground_shadow(arena, Vector2(cx - ring_w * 0.625, feet - ring_w * 1.25), ring_w * 1.25)
		arena.add_child(m_wrapper)
		_start_idle_sway(m_wrapper)
		monster_wrappers[i] = m_wrapper
		monster_rects[i] = m_rect
		for mech_check in [m.get("mechanic", {}), m.get("mechanic2", {})]:
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
		var pw: float = minf(m_slot - 10.0, 132.0)
		var plate := _unit_plate(str(m["name"]), int(m["hp"]), int(m["max_hp"]), pw, 0.0, _monster_statuses(state, i))
		plate.position = Vector2(cx - pw * 0.5, feet - msz.y - UNIT_PLATE_H - 2.0)
		arena.add_child(plate)
		_monster_plates[i] = plate

		var intent := Combat.monster_intent(state, i)
		if not intent.is_empty():
			var t: Hero = intent["target"]
			var chip: PanelContainer
			var ikind := str(intent.get("kind", "attack"))
			if GameData.INTENT_INFO.has(ikind):
				var info: Dictionary = GameData.INTENT_INFO[ikind]
				var label := str(info["name"])
				if intent.has("targets"):
					label = "%s %d → %s" % [tr(str(info["name"])), int(intent["dmg"]), tr(str("front" if ikind == "sunder" else "all"))]
				elif t != null:
					label = ("%s %d → %s" % [tr(str(info["name"])), int(intent["dmg"]), tr(str(t.name.split(" the ")[0]))]) if int(intent["dmg"]) > 0 else ("%s → %s" % [tr(str(info["name"])), tr(str(t.name.split(" the ")[0]))])
				var tip := str(info["desc"]) % int(GameData.SWEEP_MULT * 100) if ikind == "sweep" else str(info["desc"]).replace("%%", "%")
				chip = _intent_chip(label, ikind in ["sweep", "snipe", "roar", "harvest", "drown", "immolate", "sunder", "brand"], "%s — %s" % [tr(str(info["name"])), tr(str(tip))], str(info["icon"]))
			elif intent.get("charging", false):
				chip = _intent_chip("Winding up", true, tr("Gathering strength this round. Next round it lands a heavy blow (×%s damage) that stuns its target unless they Defend. Defend, Guard, or move the likely target to the back row.") % tr(str(GameData.HEAVY_BLOW_MULT)))
			elif intent.get("heavy_blow", false):
				chip = _intent_chip("⚠ %d → %s" % [int(intent["dmg"]), tr(str(t.name.split(" the ")[0]))], true,
					tr("HEAVY BLOW on %s for about %d — it stuns unless they Defend. Defend (5) halves it; Guard (6) takes it for them; Shield Bash breaks it.") % [tr(str(t.name)), int(intent["dmg"])])
			else:
				chip = _intent_chip("%d → %s" % [int(intent["dmg"]), tr(str(t.name.split(" the ")[0]))], bool(intent["heavy"]),
					tr("Attacks %s this round for about %d%s") % [tr(str(t.name)), int(intent["dmg"]), tr(str(tr(" — a heavy hit, consider Defending") if intent["heavy"] else ""))])
			chip.position = plate.position + Vector2(0, -22.0)
			var ring: Control = target_rings.get(t.id) if t != null else null
			if ring:
				chip.mouse_entered.connect(func(): if is_instance_valid(ring): ring.visible = true)
				chip.mouse_exited.connect(func(): if is_instance_valid(ring): ring.visible = false)
			arena.add_child(chip)

	# Round chip + frame.
	var enc_name := str(monsters[0].get("encounter", {}).get("name", "")) if not monsters.is_empty() else ""
	var round_chip := _label(tr("Round %d%s") % [next_round, (" · " + tr(enc_name)) if enc_name != "" else ""], 16)
	if enc_name != "":
		round_chip.tooltip_text = str(monsters[0]["encounter"]["hint"])
		round_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	round_chip.add_theme_font_override("font", DISPLAY_FONT)
	_shadow(round_chip)
	round_chip.position = Vector2(14, 8)
	arena.add_child(round_chip)
	# The rank's rules that bite in this fight, top-right of the arena.
	var fight_rank := str(GameState.run.get("rift_rank", ""))
	if fight_rank != "":
		var rbox := HBoxContainer.new()
		rbox.add_theme_constant_override("separation", 6)
		rbox.add_child(_rule_chip(tr("Rank %s") % tr(str(fight_rank)), tr("This rift is Rank %s on the rift ladder.") % tr(str(fight_rank)), Palette.RANK_S))
		for rr in _rank_rules(fight_rank):
			if str(rr[0]) == "foes" or (str(rr[0]) == "boss_double_mechanic" and GameState.current_node_kind() == "boss"):
				rbox.add_child(_rule_chip(str(rr[1]), str(rr[2]), Palette.HAZARD))
		rbox.position = Vector2(W - rbox.get_combined_minimum_size().x - 14.0, 10.0)
		arena.add_child(rbox)
	var frame := Panel.new()
	var fst := StyleBoxFlat.new()
	fst.bg_color = Color(0, 0, 0, 0)
	fst.border_color = Palette.LINE
	fst.set_border_width_all(2)
	frame.add_theme_stylebox_override("panel", fst)
	frame.size = Vector2(W, H)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Actions (bound to this render's live arena nodes).
	var run_turns := func(pre: Callable):
		_run_combat_turns(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena, true, pre)
	var attack_cb := Callable()
	if current_hero:
		var hid := current_hero.id
		attack_cb = func(ti: int):
			_combat_target = ti
			run_turns.call(func(): GameState.set_hero_action(hid, "attack", ti))
		# Click a foe to attack it; hovering lights it up.
		for i in monster_wrappers:
			var w: Control = monster_wrappers[i]
			var hit := Button.new()
			hit.flat = true
			for sn in ["normal", "hover", "pressed", "focus", "disabled"]:
				hit.add_theme_stylebox_override(sn, StyleBoxEmpty.new())
			hit.position = w.position
			hit.size = w.size
			hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			hit.tooltip_text = tr("Attack %s") % tr(str(monsters[i]["name"]))
			hit.mouse_entered.connect(func(): if is_instance_valid(w): w.modulate = Color(1.35, 1.2, 1.2))
			hit.mouse_exited.connect(func(): if is_instance_valid(w): w.modulate = Color.WHITE)
			hit.pressed.connect(attack_cb.bind(i))
			arena.add_child(hit)
	arena.add_child(frame)

	var col := _vbox(8)
	col.custom_minimum_size.x = W
	col.add_child(arena)

	var warn := Combat.describe_incoming(state)
	if warn != "":
		var warn_row := HBoxContainer.new()
		warn_row.add_theme_constant_override("separation", 6)
		warn_row.add_child(_icon("res://assets/skills/icon_boss_skull.png", 16))
		var wl := _wrap_label(warn, 13)
		wl.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		warn_row.add_child(wl)
		col.add_child(warn_row)

	col.add_child(_turn_order_strip(state))
	var tut := _tutorial_step(state, current_hero)
	_tut_key = str(tut.get("key", ""))
	if not tut.is_empty():
		col.add_child(_tutorial_panel(tut))
	col.add_child(_command_bar(state, current_hero, living_heroes, hero_wrappers, attack_cb, run_turns))
	if _combat_log_open:
		var full_log: Array = state["log"]
		col.add_child(_log_richtext(full_log.slice(max(0, full_log.size() - 14)), party, monsters, 140.0))
	v.add_child(col)

	_play_round_banner(arena, state, W, H)

	# Auto-play any turn that needs no input (a monster's, a skipped hero, or
	# every turn while Auto is on).
	if (current_hero == null or _auto_battle) and not living_heroes.is_empty():
		if current_hero != null:
			state["auto_used"] = true   # no hand-played bonus for this fight
		_run_combat_turns(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena)


var _tut_key := ""   # the command key the guided first fight is pointing at
var _more_open := false   # the command bar's "More" group (Guard, Move, Tonics, Call) is showing
var _mom_pips: Array = []   # the Momentum meter's pips, for the hover preview
var _mom_shown := -1        # the Momentum the meter showed last time, to flash what was just earned


## The guided first fight (training rift): the next step to teach, or {}.
## {text, key, step}; steps tick off in GameState.set_hero_action.
func _tutorial_step(state: Dictionary, h: Hero) -> Dictionary:
	if not GameState.run.get("training", false) or GameState.hints_seen.has("tut_done") or GameState.tips_off:
		return {}
	var seen := GameState.hints_seen
	if seen.has("tut_attack") and seen.has("tut_skill") and seen.has("tut_windup"):
		return {"step": 4, "text": tr("That's the core of every fight: read the tags above the foes, build Momentum with attacks and defence, and spend it on skills. Auto (A) plays turns for you whenever you like."), "key": ""}
	if h == null:
		return {}
	var who := h.name.split(" the ")[0]
	var monsters: Array = state["monsters"]
	if not seen.has("tut_windup"):
		for i in monsters.size():
			if float(monsters[i]["hp"]) > 0 and (monsters[i].get("_winding", false) or monsters[i].get("_charged", false)):
				var it := Combat.monster_intent(state, i)
				var t: Hero = it.get("target") if not it.is_empty() else null
				var tname := t.name.split(" the ")[0] if t else tr("a hero")
				var own := t == h
				return {"step": 3, "key": "5" if own else "6", "text": tr("Wind-ups. %s is winding up a heavy blow at %s: see the red tag above it. It lands next round and stuns unless the target Defends. %s") % [str(monsters[i]["name"]), tname,
					tr("Press Defend (5) — %s takes half and earns Momentum.") % tr(str(who)) if own else tr("Press Guard (6) and pick %s — %s takes the blow instead, 25%% weaker.") % [tr(str(tname)), tr(str(who))]]}
	if not seen.has("tut_attack"):
		return {"step": 1, "key": "1", "text": tr("Attack. It's %s's turn: press Attack (1) or click a foe. Every attack adds 1 Momentum — the pips under %s's name.") % [tr(str(who)), tr(str(who))]}
	if not seen.has("tut_skill"):
		for sk in GameData.hero_role_skills(h):
			if Combat.action_block(state, h, "skill:" + str(sk["id"])) == "":
				return {"step": 2, "key": "2", "text": tr("Skills. You have %d Momentum. %s's skill %s (2) spends %d of it for a stronger move — hover it to read it, then use it.") % [int(state.get("momentum", 0)), tr(str(who)), tr(str(sk["name"])), int(sk["cost"])]}
		return {"step": 2, "key": "", "text": tr("Skills cost Momentum. Keep attacking until a skill (2-4) lights up, then use it.")}
	return {}


func _tutorial_panel(tut: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.theme_type_variation = &"CardPanelEmber"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var tag := _label(tr("Step %d of 3") % int(tut["step"]) if int(tut["step"]) <= 3 else tr("Well fought"), 15)
	tag.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	tag.custom_minimum_size.x = 110
	row.add_child(tag)
	var txt := _wrap_label(str(tut["text"]), 14)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(txt)
	var done := int(tut["step"]) > 3
	var b := _button(tr("Got it") if done else tr("Skip tutorial"), func():
		GameState.dismiss_hint("tut_done")
		render()
	)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	p.add_child(row)
	return p


## The on-screen size of one art pixel in the arena: a clean factor (0.5,
## 0.75 or 1) so nearest filtering keeps pixels even, the same for everyone.
func _battle_px_scale(arena_h: float) -> float:
	var raw := 0.31 * arena_h / 200.0
	return 1.0 if raw >= 0.875 else (0.75 if raw >= 0.625 else 0.5)


## A small dark chip with a sword (or skull, for a heavy hit) and text.
func _intent_chip(text: String, heavy: bool, tip: String, icon: String = "") -> PanelContainer:
	var chip := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(Palette.INK, 0.88)
	st.border_color = Palette.HAZARD if heavy else Palette.LINE
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	st.content_margin_left = 4
	st.content_margin_right = 5
	chip.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon(icon if icon != "" else ("res://assets/skills/icon_boss_skull.png" if heavy else "res://assets/skills/sword_a.png"), 14))
	var l := _label(text, 12)
	l.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if heavy else Palette.TEXT)
	row.add_child(l)
	chip.add_child(row)
	chip.tooltip_text = tip
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	return chip


## One command button: icon over a caption, a hotkey badge in the corner, a
## dark cooldown overlay with the rounds left when it can't be used yet.
func _cmd_button(icon_path: String, caption: String, key: String, cb: Callable, tip: String, selected: bool = false, block: String = "", cost: int = 0) -> Button:
	var b := _button("", cb)
	if key != "" and key == _tut_key:
		selected = true
		_pulse(b, 0.55, 0.5)
	b.custom_minimum_size = Vector2(92, 72)
	b.tooltip_text = tip
	b.disabled = block != ""
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for sn in ["normal", "hover", "pressed", "focus", "disabled"]:
		var st := StyleBoxFlat.new()
		st.bg_color = Palette.SURFACE3 if sn in ["hover", "pressed"] else Palette.SURFACE
		st.border_color = Palette.EMBER_BRIGHT if selected else (Palette.VIOLET_BRIGHT if sn == "hover" else Palette.LINE)
		st.set_border_width_all(2)
		st.set_corner_radius_all(6)
		if sn == "focus":
			st.bg_color = Color(0, 0, 0, 0)
		b.add_theme_stylebox_override(sn, st)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := _icon(icon_path, 30)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var cap := _label(caption, 12)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cap.clip_text = true
	col.add_child(cap)
	b.add_child(col)
	if key != "":
		var kb := _label(key, 11)
		kb.add_theme_color_override("font_color", Palette.MUTED)
		kb.position = Vector2(6, 3)
		b.add_child(kb)
	if cost > 0:
		var cl := _label("%d◆" % cost, 11)
		cl.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if block == "" else Palette.MUTED)
		cl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		cl.offset_left = -36
		cl.offset_right = -5
		cl.offset_top = 3
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.add_child(cl)
	if block != "":
		ic.modulate = Color(0.45, 0.45, 0.5)
		cap.add_theme_color_override("font_color", Palette.MUTED2)
	return b


## The party's Momentum as ten pips (filled up to `n`).
func _momentum_meter(n: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.tooltip_text = tr("Momentum %d/%d — the party's shared pool for skills and Abilities. Attacks, kills, and hits taken while Defending or Guarding build it.") % [n, GameData.MOMENTUM_MAX]
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var l := _label("Momentum", 11)
	l.add_theme_color_override("font_color", Palette.MUTED)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	_mom_pips.clear()
	for k in GameData.MOMENTUM_MAX:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(7, 9)
		pip.color = Palette.EMBER_BRIGHT if k < n else Color(Palette.LINE, 0.6)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pip)
		_mom_pips.append(pip)
		# Pips earned since the last look flash once.
		if _mom_shown >= 0 and k >= _mom_shown and k < n:
			pip.modulate = Color(2.2, 2.2, 1.6)
			pip.create_tween().tween_property(pip, "modulate", Color.WHITE, 0.6)
	_mom_shown = n
	return row


## Hovering an action previews the Momentum it leaves: pips it spends turn
## dark red, pips it earns show pale.
func _momentum_hover(b: Control, n: int, delta: int) -> void:
	b.mouse_entered.connect(func(): _paint_pips(n, delta))
	b.mouse_exited.connect(func(): _paint_pips(n, 0))
	b.focus_entered.connect(func(): _paint_pips(n, delta))
	b.focus_exited.connect(func(): _paint_pips(n, 0))


func _paint_pips(n: int, delta: int) -> void:
	var after := clampi(n + delta, 0, GameData.MOMENTUM_MAX)
	for k in _mom_pips.size():
		var pip: ColorRect = _mom_pips[k]
		if not is_instance_valid(pip):
			return
		if k < mini(n, after):
			pip.color = Palette.EMBER_BRIGHT
		elif k < n:
			pip.color = Palette.EMBER_DEEP        # would be spent
		elif k < after:
			pip.color = Color(Palette.EMBER_BRIGHT, 0.45)   # would be earned
		else:
			pip.color = Color(Palette.LINE, 0.6)


## Replaces the command buttons with "Guard whom?": one button per ally
## (keys 1-4) showing the damage already headed their way, and Cancel.
func _guard_picker(row: Container, state: Dictionary, current_hero: Hero, living_heroes: Array[Hero], run_turns: Callable) -> void:
	for c in row.get_children():
		if c.get_index() > 0:
			c.queue_free()
	_combat_hotkeys.clear()
	var action := _ally_pick
	if action == "tonic_kind":
		var ask_k := _label("Which tonic?", 15)
		ask_k.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		ask_k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ask_k)
		var hid_k := current_hero.id
		var nk := 0
		for def in GameData.TONIC_TYPES:
			var tid: String = def["id"]
			var have := GameState.tonic_count(tid)
			nk += 1
			var choose := func():
				if str(def["target"]) == "ally":
					_tonic_kind = tid
					_ally_pick = "tonic"
					render()
				else:
					_ally_pick = ""
					run_turns.call(func(): GameState.set_hero_action(hid_k, "tonic:" + tid))
			var tb := _button("%s ×%d" % [tr(str(def["name"])), have], choose)
			tb.tooltip_text = tr("%s (key %d)") % [tr(str(def["desc"])), nk]
			tb.disabled = have <= 0
			tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(tb)
			if have > 0:
				_combat_hotkeys[str(nk)] = choose
		var cancel_k := func():
			_ally_pick = ""
			render()
		row.add_child(_button("Cancel", cancel_k))
		_combat_hotkeys["Escape"] = cancel_k
		return
	var ask := _label(tr("Guard whom?") if action == "guard" else tr("%s for whom?") % tr(str(GameData.find_tonic(_tonic_kind).get("name", "Tonic"))), 15)
	ask.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	ask.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ask)
	var incoming := {}
	var monsters: Array = state["monsters"]
	for i in monsters.size():
		var it := Combat.monster_intent(state, i)
		if not it.is_empty() and not it.get("guarded", false):
			for t in (it.get("targets", []) if it.has("targets") else ([it["target"]] if it.get("target") != null else [])):
				incoming[t.id] = int(incoming.get(t.id, 0)) + int(it["dmg"])
	var hid := current_hero.id
	var n := 0
	for a in living_heroes:
		if a == current_hero and action == "guard":
			continue
		n += 1
		var pick := func(aid=a.id):
			_ally_pick = ""
			run_turns.call(func(): GameState.set_hero_action(hid, action if action == "guard" else "tonic:" + _tonic_kind, 0, aid))
		var text := "%s  %d/%d" % [tr(str(a.name.split(" the ")[0])), a.hp, Combat.max_hp(a)]
		if incoming.has(a.id):
			text += tr("  (%d dmg incoming)") % int(incoming[a.id])
		var b := _button(text, pick)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = tr("Key %d") % n
		row.add_child(b)
		# A tonic on a hero at full HP would heal nothing.
		if action == "tonic" and _tonic_kind == "healing" and a.hp >= Combat.max_hp(a):
			b.disabled = true
			b.tooltip_text = "Already at full HP"
			continue
		_combat_hotkeys[str(n)] = pick
	var cancel := func():
		_ally_pick = ""
		render()
	row.add_child(_button("Cancel", cancel))
	_combat_hotkeys["Escape"] = cancel


## Small square utility button (speed, log, retreat).
func _tool_button(icon_path: String, text: String, tip: String, cb: Callable) -> Button:
	var b := _button(text, cb)
	b.icon = load(icon_path)
	b.expand_icon = false
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(44, 40)
	b.add_theme_font_size_override("font_size", 14)
	return b


func _command_bar(state: Dictionary, current_hero: Hero, living_heroes: Array[Hero], hero_wrappers: Dictionary, attack_cb: Callable, run_turns: Callable) -> Control:
	var monsters: Array = state["monsters"]
	var panel := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Palette.SURFACE2
	st.border_color = Palette.LINE
	st.set_border_width_all(1)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", st)
	# Wraps instead of running off the side (the full kit is wider than a
	# narrow window).
	var row: Container = HFlowContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 8)
	panel.add_child(row)

	if current_hero:
		var who := HBoxContainer.new()
		who.add_theme_constant_override("separation", 8)
		who.custom_minimum_size.x = 200
		who.add_child(_hero_icon(current_hero, 56))
		var info := _vbox(2)
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		var nm := _label(tr("%s's turn") % tr(str(current_hero.name.split(" the ")[0])), 15)
		nm.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		info.add_child(nm)
		info.add_child(_label(tr("Lv%d %s · %d/%d HP") % [current_hero.level, tr(str(GameData.find_class(current_hero.pool_id).get("name", ""))), current_hero.hp, Combat.max_hp(current_hero)], 12, true))
		info.add_child(_momentum_meter(int(state.get("momentum", 0))))
		who.add_child(info)
		row.add_child(who)

		var pending: Dictionary = state["pending_actions"].get(current_hero.id, {"action": "attack"})
		var last_action := str(pending.get("action", "attack"))
		var hid := current_hero.id
		var tgt := _combat_target
		var tgt_name := str(monsters[tgt]["name"]) if tgt >= 0 and tgt < monsters.size() else "—"
		var do_attack := func(): if tgt >= 0: attack_cb.call(tgt)
		var weak_reach: bool = current_hero.formation == "back" and GameData.MELEE_ROLES.has(current_hero.cls_id)
		# A likely kill earns +1 more (the preview and the tip both say so).
		var atk_kills := tgt >= 0 and Combat.attack_would_kill(state, current_hero, tgt)
		var atk_tip := tr("Attack %s (1): +%d Momentum%s. Click a foe to pick another, Tab to cycle.") % [tr(str(tgt_name)), 2 if atk_kills else 1, tr(str(tr(" (+1 for the kill: this hit should finish it)") if atk_kills else ""))]
		if weak_reach:
			atk_tip += tr("\nFrom the back row a %s hits at half strength.") % tr(str(current_hero.cls_id))
		var mom := int(state.get("momentum", 0))
		var ab_atk := _cmd_button("res://assets/skills/sword_a.png", "Attack" if not weak_reach else "Attack ½", "1", do_attack, atk_tip, last_action == "attack")
		_momentum_hover(ab_atk, mom, 2 if atk_kills else 1)
		row.add_child(ab_atk)
		_combat_hotkeys["1"] = do_attack
		if last_action == "attack":
			_combat_hotkeys["Space"] = do_attack
		# Role skills (2, 3) and the subclass Ability (4) spend Momentum.
		var skill_defs: Array = []
		for sk in GameData.hero_role_skills(current_hero):
			var tw_arch := Combat.hero_main_arch(current_hero)
			skill_defs.append(["skill:" + str(sk["id"]), str(sk["icon"]), tr(str(sk["name"])), "%s%s%s" % [tr(str(sk["desc"])), "" if str(sk["row"]) == "any" else tr("\n%s row.") % tr(str(sk["row"])).capitalize(), (tr("\n%s twist: %s.") % [tr(GameData.ARCHETYPES[tw_arch]), tr(GameData.ARCH_TWIST[tw_arch])]) if tw_arch != "" else ""], int(sk["cost"])])
		while skill_defs.size() < 2 and GameData.ROLE_SKILLS.has(current_hero.cls_id) and skill_defs.size() < (GameData.ROLE_SKILLS[current_hero.cls_id] as Array).size():
			var locked_sk: Dictionary = GameData.ROLE_SKILLS[current_hero.cls_id][skill_defs.size()]
			skill_defs.append(["skill:" + str(locked_sk["id"]), str(locked_sk["icon"]), str(locked_sk["name"]), tr("%s\nLearned at level %d.") % [tr(str(locked_sk["desc"])), int(locked_sk["level"])], int(locked_sk["cost"])])
		if Combat.qualifies_for_ability(current_hero):
			var ab: Dictionary = GameData.SUBCLASS_ABILITIES.get(current_hero.pool_id, {})
			skill_defs.append(["ability", GameData.ability_icon(current_hero.pool_id), str(ab.get("name", "Ability")), str(ab.get("desc", "")), GameData.ABILITY_MOMENTUM_COST])
		var keys := ["2", "3", "4"]
		for k in skill_defs.size():
			var d: Array = skill_defs[k]
			var act_id: String = d[0]
			var key: String = keys[k] if act_id != "ability" else "4"
			var block := Combat.action_block(state, current_hero, act_id)
			var sk_target: bool = act_id == "ability" or str(GameData.find_role_skill(act_id.substr(6)).get("target", "")) == "foe"
			var do_skill := func(): run_turns.call(func(): GameState.set_hero_action(hid, act_id, tgt if sk_target else 0))
			var tip := tr("%s (%s) — %d Momentum. %s%s") % [tr(str(d[2])), tr(str(key)), int(d[4]), tr(str(d[3])), tr(str(("\n" + block) if block != "" else ""))]
			var sb := _cmd_button(str(d[1]), str(d[2]), key, do_skill, tip, last_action == act_id, block, int(d[4]))
			sb.custom_minimum_size.x = 104
			_momentum_hover(sb, mom, -int(d[4]) if block == "" else 0)
			row.add_child(sb)
			if block == "":
				_combat_hotkeys[key] = do_skill
				if last_action == act_id:
					_combat_hotkeys["Space"] = do_skill
		var do_defend := func(): run_turns.call(func(): GameState.set_hero_action(hid, "defend"))
		row.add_child(_cmd_button("res://assets/skills/shield_basic.png", "Defend", "5", do_defend, "Defend (5) — take half damage from hits this round. Each hit taken while Defending gives +1 Momentum (+2 for a heavy blow).", last_action == "defend"))
		_combat_hotkeys["5"] = do_defend
		if last_action == "defend":
			_combat_hotkeys["Space"] = do_defend
		# Guard, Move, Tonics and the Champion's Call sit behind "More" (their
		# keys 6-9 work either way); the guided fight opens it when it points there.
		var call_ready := GameState.champion_call_ready(current_hero)
		var show_more: bool = _more_open or _tut_key in ["6", "7", "8", "9"] or last_action == "guard"
		var more_tip := tr("More (M, or Start on a gamepad) — Guard (6), Move (7), Tonics (8)%s") % tr(str((tr(", Champion's Call (9)") if call_ready else "")))
		var toggle_more := func():
			_more_open = not show_more
			render()
		var more_btn := _cmd_button("res://assets/skills/gear.png", "Less" if show_more else ("More ★" if call_ready else "More"), "M", toggle_more, more_tip, false)
		more_btn.custom_minimum_size.x = 72
		if call_ready and not show_more:
			more_btn.modulate = Color(1.15, 1.0, 0.7)
		row.add_child(more_btn)
		_combat_hotkeys["M"] = more_btn.pressed.emit
		var more_row: Container = row if show_more else HBoxContainer.new()   # hidden buttons still register their keys
		var allies: Array = living_heroes.filter(func(a): return a != current_hero)
		if not allies.is_empty():
			var start_guard := func():
				if _combat_animating:
					return
				_ally_pick = "guard"
				render()
			var gb := _cmd_button("res://assets/skills/shield_blue.png", "Guard", "6", start_guard, "Guard (6) — pick an ally: attacks aimed at them this round hit you instead, 25% weaker, for +1 Momentum each.", last_action == "guard")
			more_row.add_child(gb)
			_combat_hotkeys["6"] = start_guard
		if GameState.champion_call_ready(current_hero):
			var call := GameState.champion_call(current_hero)
			var do_call := func(): run_turns.call(func(): GameState.set_hero_action(hid, "call"))
			var cb := _cmd_button("res://assets/skills/icon_boss_skull.png", str(call["name"]), "9", do_call, tr("Champion's Call (9) — %s. Once per rift.") % tr(str(call["desc"])), false)
			cb.modulate = Color(1.15, 1.0, 0.7)
			more_row.add_child(cb)
			_combat_hotkeys["9"] = do_call
		var to_row := "back" if current_hero.formation != "back" else "front"
		var do_swap := func(): run_turns.call(func(): GameState.set_hero_action(hid, "swap"))
		var move_label := tr("To %s") % tr(to_row)   # Turkish puts the row first: "arka sıraya"
		more_row.add_child(_cmd_button("res://assets/skills/wing.png", move_label[0].to_upper() + move_label.substr(1), "7", do_swap, tr("Move (7) — step to the %s row. The front row draws most attacks; melee heroes hit at half strength from the back; some skills need a row.") % tr(to_row), false))
		_combat_hotkeys["7"] = do_swap
		if GameState.tonic_count() > 0:
			var start_tonic := func():
				if _combat_animating:
					return
				_ally_pick = "tonic_kind"
				render()
			more_row.add_child(_cmd_button("res://assets/ui/icon_tonic.png", tr("Tonics ×%d") % GameState.tonic_count(), "8", start_tonic, "Tonics (8) — Healing, Iron or Focus. Uses this hero's turn.", false))
			_combat_hotkeys["8"] = start_tonic
		if more_row != row:
			more_row.queue_free()
		if not _combat_hotkeys.has("Space"):
			_combat_hotkeys["Space"] = do_attack
		var living_idx: Array[int] = []
		for i in monsters.size():
			if float(monsters[i]["hp"]) > 0:
				living_idx.append(i)
		if living_idx.size() > 1:
			_combat_hotkeys["Tab"] = func():
				if _combat_animating:
					return
				_combat_target = living_idx[(living_idx.find(_combat_target) + 1) % living_idx.size()]
				render()
		var hint := _label(tr("Target: %s\nSpace repeats your last action") % tr(str(tgt_name)), 12, true)
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(hint)
		if _ally_pick != "":
			_guard_picker(row, state, current_hero, living_heroes, run_turns)
	else:
		var l := _label(tr("The party is down.") if living_heroes.is_empty() else tr("Enemy turn…"), 14, true)
		l.custom_minimum_size = Vector2(200, 72)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tools.add_child(_tool_button("res://assets/skills/boots.png", _speed_label(), "Battle speed: ×1, ×2, ×3 or Instant (click to change; also in Settings)", func():
		GameState.combat_speed = 1.0 if GameState.combat_speed >= INSTANT_SPEED else GameState.combat_speed + 1.0
		Engine.time_scale = minf(GameState.combat_speed, 3.0)
		GameState.save_settings()
		if not _combat_animating:
			render()
	))
	var auto_btn := _tool_button("res://assets/skills/sword_dual.png", "Auto" if not _auto_battle else "Auto ✓", tr("Auto (A) — heroes act on their own: Defend against heavy blows, use Abilities when ready, focus the weakest foe. A fight won by hand, with no one down, pays +%d%% Gold.") % int(GameData.HAND_BONUS * 100), func():
		_auto_battle = not _auto_battle
		if not _combat_animating:
			render()
	)
	auto_btn.toggle_mode = true
	auto_btn.button_pressed = _auto_battle
	tools.add_child(auto_btn)
	_combat_hotkeys["A"] = auto_btn.pressed.emit
	tools.add_child(_tool_button("res://assets/skills/eye_gem.png", "Log", "Show or hide the fight log", func():
		_combat_log_open = not _combat_log_open
		if not _combat_animating:
			render()
	))
	tools.add_child(_tool_button("res://assets/skills/wing.png", "", "Retreat — leave the fight (the run ends)", func():
		if _combat_animating:
			return
		_combat_animating = true
		if GameState.state_changed.is_connected(_on_state_changed):
			GameState.state_changed.disconnect(_on_state_changed)
		await _play_retreat(living_heroes, hero_wrappers)
		GameState.combat_retreat()
		if not GameState.state_changed.is_connected(_on_state_changed):
			GameState.state_changed.connect(_on_state_changed)
		_combat_animating = false
		if screen == "rift_run":
			render()
	))
	row.add_child(tools)
	return panel


## Round N slides in across the arena once per round; a boss gets a name
## card the first time its fight is shown.
## One extra sound for what a turn did (the hit/attack sounds already play):
## the most notable event in its new log lines wins.
func _turn_sfx(lines: Array) -> void:
	var text := " ".join(lines)
	for pair in [["gathers its strength", "windup"], ["stunned", "stun"], ["ablaze", "burn"], ["chilled", "chill"],
			["strikes every foe", "relic"], ["Phoenix", "relic"], ["uses ", "ability"], ["shield", "shield"],
			["mends", "heal"], ["Tonic", "heal"]]:
		# The log is in the player's language: look for the phrase in either.
		if text.contains(pair[0]) or text.contains(tr(pair[0])):
			# A wind-up is the one to hear: it lands next round unless met.
			AudioManager.cue(pair[1], tr("[A foe gathers its strength]") if pair[1] == "windup" else "")
			return


func _play_round_banner(arena: Control, state: Dictionary, W: float, H: float) -> void:
	var round_num := int(state.get("round_num", 0))
	if state.has("_phase_banner"):
		var pb: Array = state["_phase_banner"]
		state.erase("_phase_banner")
		AudioManager.cue("boss", tr("[%s roars: a second phase]") % tr(str(str(pb[0]).split(",")[0])), Palette.HAZARD)
		_title_card(arena, W, H, str(pb[1]), tr("%s enters its second phase") % tr(str(str(pb[0]).split(",")[0])), Palette.HAZARD)
		return
	if (state.get("is_boss", false) or state.get("is_elite", false)) and not is_same(_boss_intro_for, state):
		_boss_intro_for = state
		AudioManager.cue("boss", tr("[A boss roars]") if state.get("is_boss", false) else tr("[An elite snarls]"), Palette.VIOLET)
		_banner_state = state
		_banner_round = round_num
		var boss: Dictionary = state["monsters"][0]
		for m in state["monsters"]:
			if float(m["max_hp"]) > float(boss["max_hp"]):
				boss = m
		var tags: Array[String] = []
		for k in ["mechanic", "mechanic2"]:
			if not boss.get(k, {}).is_empty():
				tags.append(str(boss[k]["name"]))
		for a in boss.get("affixes", []):
			tags.append(str(GameData.ELITE_AFFIXES[a]["name"]))
		var who := tr("Elite") if state.get("is_elite", false) else (tr("Tower Guardian") if GameState.run.has("tower") else tr("Rift Warden"))
		_title_card(arena, W, H, str(boss["name"]), who + (" · " + ", ".join(tags) if not tags.is_empty() else ""), Palette.EMBER_BRIGHT)
		return
	if (is_same(_banner_state, state) and _banner_round == round_num) or round_num <= 0:
		return
	_banner_state = state
	_banner_round = round_num
	var l := _label(tr("Round %d") % round_num, 34)
	l.add_theme_color_override("font_color", Palette.TEXT)
	_shadow(l)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(W, 48)
	l.position = Vector2(-W * 0.25, H * 0.36)
	l.modulate.a = 0.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(l)
	var tw := l.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(l, "position:x", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 1.0, 0.2)
	tw.tween_interval(0.5)
	tw.tween_property(l, "position:x", W * 0.25, 0.3).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


## A big name sliding across a dark band mid-arena (boss/elite intro, a boss
## changing phase).
func _title_card(arena: Control, W: float, H: float, title: String, subtitle: String, color: Color) -> void:
	var card := _vbox(2)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band := ColorRect.new()
	band.color = Color(0, 0, 0, 0.6)
	band.size = Vector2(W, 96)
	band.position = Vector2(0, H * 0.32)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena.add_child(band)
	var nm := _label(title, 30)
	nm.add_theme_color_override("font_color", color)
	_shadow(nm)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(nm)
	var sub := _label(subtitle, 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shadow(sub)
	card.add_child(sub)
	card.size = Vector2(W, 80)
	card.position = Vector2(W, H * 0.32 + 10)
	arena.add_child(card)
	var tw := card.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(card, "position:x", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.4)
	tw.tween_property(card, "modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(band, "modulate:a", 0.0, 0.4)
	tw.tween_callback(card.queue_free)
	tw.tween_callback(band.queue_free)
	AudioManager.play_sfx(GameData.SFX_PATH["hit_heavy"])


## A defeated monster flashes, sinks and fades out.
func _tween_dissolve(wrapper: Control) -> void:
	var tw := create_tween()
	tw.tween_property(wrapper, "modulate", Color(2.0, 1.2, 1.2, 1.0), 0.06)
	tw.tween_property(wrapper, "modulate", Color(1, 0.3, 0.3, 0.0), 0.35)
	tw.parallel().tween_property(wrapper, "position:y", wrapper.position.y + 12.0, 0.35)
	await _await_or_timeout(tw.finished, 1.0)


var _xp_anim_for: Dictionary = {}   # the result whose XP bars already filled (by reference)


## One row per hero on the victory screen: portrait, XP bar filling up (with
## a LEVEL UP chip), damage dealt and kills — the top damage dealer gets MVP.
func _victory_party(result: Dictionary) -> Control:
	var heroes: Array = result["heroes"]
	var animate := not is_same(_xp_anim_for, result)
	_xp_anim_for = result
	var mvp := -1
	for i in heroes.size():
		if mvp < 0 or int(heroes[i]["dealt"]) > int(heroes[mvp]["dealt"]):
			mvp = i
	var box := _vbox(6)
	box.add_child(_label(tr("+%d XP each") % int(result.get("xp_gain", 0)), 13, true))
	for i in heroes.size():
		var e: Dictionary = heroes[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var portrait := _icon_trimmed(GameData.portrait_for_hero(str(e["cls_id"]), str(e["pool_id"])), 40)
		if not e["alive"]:
			portrait.modulate = Color(0.5, 0.5, 0.5, 0.8)
		row.add_child(portrait)
		var mid := _vbox(3)
		mid.custom_minimum_size.x = 260
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		top.add_child(_label(tr("%s  Lv%d") % [tr(str(str(e["name"]).split(" the ")[0])), int(e["lv1"])], 13))
		var leveled := int(e["lv1"]) > int(e["lv0"])
		if leveled:
			var up := _label("LEVEL UP!", 12)
			up.add_theme_color_override("font_color", Palette.RANK_S)
			top.add_child(up)
			_pulse(up, 0.4, 0.5)
		if i == mvp and int(e["dealt"]) > 0:
			var mv := HBoxContainer.new()
			mv.add_theme_constant_override("separation", 2)
			mv.add_child(_icon("res://assets/skills/star.png", 14))
			var ml := _label("MVP", 12)
			ml.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
			mv.add_child(ml)
			mv.tooltip_text = "Most damage dealt this fight"
			top.add_child(mv)
		mid.add_child(top)
		var at_cap := int(e["lv1"]) >= 10
		var bar := _flat_bar(100, 0, 260, 6, Palette.VIOLET_BRIGHT)
		var end_v := 100.0 if at_cap else 100.0 * float(e["xp1"]) / float(max(1, int(e["next1"])))
		var start_v := 0.0 if leveled else 100.0 * float(e["xp0"]) / float(max(1, int(e["next0"])))
		bar.value = start_v if animate else end_v
		bar.tooltip_text = tr("Max level") if at_cap else tr("%d / %d XP to Lv%d") % [int(e["xp1"]), int(e["next1"]), int(e["lv1"]) + 1]
		if animate:
			bar.create_tween().tween_property(bar, "value", end_v, 0.8).set_delay(0.25 + 0.12 * i).set_ease(Tween.EASE_OUT)
		mid.add_child(bar)
		row.add_child(mid)
		row.add_child(_label(tr("%d dmg · %d kill%s") % [int(e["dealt"]), int(e["kills"]), tr(str(_pl(int(e["kills"]))))], 12, true))
		box.add_child(row)
	var bark: Dictionary = result.get("bark", {})
	if not bark.is_empty():
		var q := _label("%s: \u201c%s\u201d" % [tr(str(bark["name"])), tr(str(bark["text"]))], 13)
		q.add_theme_color_override("font_color", Palette.VIOLET_BRIGHT)
		box.add_child(q)
	return box
