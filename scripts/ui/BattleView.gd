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
	l.queue_free()


## Floats every effect that fired this turn (Combat._proc: "Counter!",
## "Intercept!", a passive or Legendary's name...) over its hero, staggered so
## several procs on one hero stack instead of overlapping. Fire-and-forget:
## never awaited, so it can't hold up the turn's own animation chain.
## Combat hotkeys (see _combat_hotkeys, filled while the action bar builds).
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
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
		tile.tooltip_text = ("Acting now: " if is_current else "") + tip
		tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sz := 44 if is_current else 34
		var icon := _icon_trimmed(icon_path, sz) if is_hero else _icon(icon_path, sz)
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
				_plate_set_hp(_monster_plates.get(i), float(monsters[i]["hp"]))
				await _impact_beat(arena, heavy)
				if monster_rects.has(i):
					await _play_frames(monster_rects[i], GameData.monster_anim_frames(str(monsters[i]["name"]), "hurt"))
				await _flash_white(monster_wrappers[i])
				await _spawn_damage_number(monster_wrappers[i], "-%d" % int(round(dmg)), Palette.HAZARD, heavy)
				if float(monster_hp_before[i]) > 0.0 and float(monsters[i]["hp"]) <= 0.0:
					var mp = _monster_plates.get(i)
					if mp != null and is_instance_valid(mp):
						mp.visible = false
					await _tween_dissolve(monster_wrappers[i])

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
				_plate_set_hp(_hero_plates.get(h.id), h.hp)
				await _impact_beat(arena, heavy2)
				var frames := GameData.hero_combat_frames(h.cls_id, h.pool_id, "hurt")
				if not frames.is_empty() and hero_rects.has(h.id):
					await _play_frames(hero_rects[h.id], frames)
				else:
					await _tween_hurt(hero_wrappers[h.id])
				await _spawn_damage_number(hero_wrappers[h.id], "-%d" % dmg2, Palette.HAZARD, heavy2)
				if before > 0 and h.hp <= 0:
					AudioManager.play_sfx(GameData.SFX_PATH["knockout"])
					await _tween_collapse(hero_wrappers[h.id])

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
		var bw := _battle_width()
		v.add_child(_banner(GameData.BATTLE_BACKGROUNDS[pre_bg_idx], bw, roundf(clampf(bw * 0.36, 280.0, 420.0))))
		var kind_label := "Boss" if is_boss else ("Elite" if kind == "elite" else "Combat")
		v.add_child(_label("A %s encounter awaits." % kind_label, 16))
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
	log_row.add_child(_label("%s · %d round%s" % [str(result["monster_name"]), int(result.get("rounds", 0)), "" if int(result.get("rounds", 0)) == 1 else "s"], 14))
	log_row.add_child(_tool_button("res://assets/skills/eye_gem.png", "Hide log" if _combat_log_open else "Fight log", "Show or hide the full fight log", func():
		_combat_log_open = not _combat_log_open
		render()
	))
	v.add_child(log_row)
	if _combat_log_open:
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
		if bonus_crystal > 0:
			crystal_text += " (+%d bonus)" % bonus_crystal
		gains_row.add_child(_label(crystal_text, 14))
		victory_col.add_child(gains_row)
		if result.has("heroes"):
			victory_col.add_child(_victory_party(result))
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


# ----------------------------------------------------------------------------
# Battle screen layout
# ----------------------------------------------------------------------------

var _hero_plates: Dictionary = {}      # hero id -> unit plate (live HP updates during playback)
var _monster_plates: Dictionary = {}   # monster index -> unit plate
var _combat_target: int = -1           # the foe Attack / key 1 hits; click a foe or Tab to change
var _combat_log_open: bool = false
var _guard_picking: bool = false       # the command bar is asking which ally to guard
var _guard_picker_for: String = ""     # the hero that picker belongs to
var _banner_state: Dictionary = {}     # the fight + round whose "Round N" slide-in already played
var _banner_round: int = -1
var _boss_intro_for: Dictionary = {}   # the combat state whose boss intro already played (by reference)

const UNIT_PLATE_H := 44.0   # name/HP row + bar + status row


## Arena width: the content column, capped so a huge window doesn't blow the
## pixel art up past readability.
func _battle_width() -> float:
	var vw: float = get_viewport().get_visible_rect().size.x
	return clampf(vw - 72.0, 700.0, 1180.0)


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
		sb.tooltip_text = "Shield: absorbs the next %d damage" % int(round(shield))
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
		out.append({"icon": "res://assets/skills/shield_basic.png", "tip": "Defending — takes reduced damage this round", "color": Palette.VIOLET_BRIGHT})
	var sh := float(state.get("hero_shields", {}).get(h.id, 0.0))
	if sh > 0.0:
		out.append({"icon": "res://assets/skills/shield_blue.png", "tip": "Shield — absorbs the next %d damage" % int(round(sh)), "color": Palette.CRYSTALS})
	var poison: Dictionary = state.get("hero_poison", {})
	if poison.has(h.id):
		out.append({"icon": "res://assets/skills/shard_green.png", "tip": "Poisoned — %d damage a round for %d more round(s)" % [int(round(float(poison[h.id]["value"]) * Combat.max_hp(h))), int(poison[h.id]["rounds"])], "color": Palette.RANK_E})
	var guarding: Dictionary = state.get("_guarding", {})
	if guarding.has(h.id):
		var g := _hero_by_id(state["party"], str(guarding[h.id]))
		if g:
			out.append({"icon": "res://assets/skills/shield_blue.png", "tip": "Guarded by %s this round" % g.name, "color": Palette.VIOLET_BRIGHT})
	if guarding.values().has(h.id):
		out.append({"icon": "res://assets/skills/shield_split.png", "tip": "Guarding an ally this round (takes their hits, 25% weaker)", "color": Palette.VIOLET_BRIGHT})
	if h.ability_cooldown == 0 and Combat.qualifies_for_ability(h):
		out.append({"icon": GameData.ability_icon(h.pool_id), "tip": "Ability ready", "color": Palette.EMBER_BRIGHT})
	return out


## Statuses shown under a monster's HP bar: its type, boss mechanics or
## monster ability, and a ward if it has one.
func _monster_statuses(state: Dictionary, i: int) -> Array:
	var m: Dictionary = state["monsters"][i]
	var out: Array = []
	var type_icon: String = GameData.RELIC_TYPE_ICON_PATH.get(str(m.get("type", "")), "")
	if type_icon != "":
		out.append({"icon": type_icon, "tip": "%s type" % str(m["type"]), "color": Palette.LINE})
	for key in ["mechanic", "mechanic2"]:
		var mech: Dictionary = m.get(key, {})
		var icon: String = GameData.BOSS_MECHANIC_ICON.get(str(mech.get("id", "")), "")
		if icon != "":
			out.append({"icon": icon, "tip": "%s — %s" % [str(mech["name"]), str(mech["desc"])], "color": Palette.ELITE})
	var ability: Dictionary = m.get("ability", {})
	if m.get("mechanic", {}).is_empty() and not ability.is_empty():
		var a_icon: String = GameData.MONSTER_ABILITY_ICON.get(str(ability["kind"]), "")
		if a_icon != "":
			out.append({"icon": a_icon, "tip": str(ability["name"]), "color": Palette.ELITE})
	var ward := float(state.get("monster_shields", {}).get(i, 0.0))
	if ward > 0.0:
		out.append({"icon": "res://assets/skills/shield_blue.png", "tip": "Ward — absorbs the next %d damage" % int(round(ward)), "color": Palette.CRYSTALS})
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
		_guard_picking = false
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
		var t: Hero = intent["target"]
		var e: Dictionary = incoming.get(t.id, {"dmg": 0, "heavy": false, "from": []})
		e["dmg"] = int(e["dmg"]) + int(intent["dmg"])
		e["heavy"] = bool(e["heavy"]) or bool(intent["heavy"])
		(e["from"] as Array).append("%s (%d)" % [str(monsters[i]["name"]), int(intent["dmg"])])
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
	var h_slot: float = minf(150.0, hz_w / max(1, line.size()))
	var h_start: float = hz_x + hz_w - h_slot * line.size()
	var target_rings := {}   # hero id -> hover ring shown while an intent aimed at them is hovered
	for k in line.size():
		var h: Hero = line[k]
		var is_back := h.formation == "back"
		var size: float = roundf(H * (0.26 if is_back else 0.29))
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
		var rect := _icon_trimmed(GameData.portrait_for_hero(h.cls_id, h.pool_id), int(size))
		var wrapper := _wrap_icon(rect)
		wrapper.position = Vector2(cx - size * 0.5, feet - size)
		_add_ground_shadow(arena, wrapper.position, size)
		arena.add_child(wrapper)
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
			var chip := _intent_chip("-%d" % int(e["dmg"]), bool(e["heavy"]), "Incoming this round: %s" % ", ".join(e["from"]))
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
		var m_rect := _sprite_fit(GameData.sprite_for_monster(str(m["name"])), H * (0.46 if i == big_i else 0.33) / 200.0, m_slot * 1.1)
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
			var chip := _intent_chip("%d → %s" % [int(intent["dmg"]), t.name.split(" the ")[0]], bool(intent["heavy"]),
				"Attacks %s this round for about %d%s" % [t.name, int(intent["dmg"]), " — a heavy hit, consider Defending" if intent["heavy"] else ""])
			chip.position = plate.position + Vector2(0, -22.0)
			var ring: Control = target_rings.get(t.id)
			if ring:
				chip.mouse_entered.connect(func(): if is_instance_valid(ring): ring.visible = true)
				chip.mouse_exited.connect(func(): if is_instance_valid(ring): ring.visible = false)
			arena.add_child(chip)

	# Round chip + frame.
	var round_chip := _label("Round %d" % next_round, 16)
	round_chip.add_theme_font_override("font", DISPLAY_FONT)
	_shadow(round_chip)
	round_chip.position = Vector2(14, 8)
	arena.add_child(round_chip)
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
			hit.tooltip_text = "Attack %s" % str(monsters[i]["name"])
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
	col.add_child(_command_bar(state, current_hero, living_heroes, hero_wrappers, attack_cb, run_turns))
	if _combat_log_open:
		var full_log: Array = state["log"]
		col.add_child(_log_richtext(full_log.slice(max(0, full_log.size() - 14)), party, monsters, 140.0))
	v.add_child(col)

	_play_round_banner(arena, state, W, H)

	# Auto-play any turn that needs no input (a monster's, or a skipped hero).
	if current_hero == null and not living_heroes.is_empty():
		_run_combat_turns(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena)


## A small dark chip with a sword (or skull, for a heavy hit) and text.
func _intent_chip(text: String, heavy: bool, tip: String) -> PanelContainer:
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
	row.add_child(_icon("res://assets/skills/icon_boss_skull.png" if heavy else "res://assets/skills/sword_a.png", 14))
	var l := _label(text, 12)
	l.add_theme_color_override("font_color", Palette.EMBER_BRIGHT if heavy else Palette.TEXT)
	row.add_child(l)
	chip.add_child(row)
	chip.tooltip_text = tip
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	return chip


## One command button: icon over a caption, a hotkey badge in the corner, a
## dark cooldown overlay with the rounds left when it can't be used yet.
func _cmd_button(icon_path: String, caption: String, key: String, cb: Callable, tip: String, selected: bool = false, cooldown: int = 0) -> Button:
	var b := _button("", cb)
	b.custom_minimum_size = Vector2(92, 72)
	b.tooltip_text = tip
	b.disabled = cooldown > 0
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
	if cooldown > 0:
		ic.modulate = Color(0.45, 0.45, 0.5)
		cap.add_theme_color_override("font_color", Palette.MUTED2)
		var cd := _label(str(cooldown), 22)
		cd.add_theme_font_override("font", DISPLAY_FONT)
		cd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd.offset_bottom = -14
		_shadow(cd)
		b.add_child(cd)
	return b


## Replaces the command buttons with "Guard whom?": one button per ally
## (keys 1-4) showing the damage already headed their way, and Cancel.
func _guard_picker(row: HBoxContainer, state: Dictionary, current_hero: Hero, living_heroes: Array[Hero], run_turns: Callable) -> void:
	for c in row.get_children():
		if c.get_index() > 0:
			c.queue_free()
	_combat_hotkeys.clear()
	var ask := _label("Guard whom?", 15)
	ask.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	ask.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ask)
	var incoming := {}
	var monsters: Array = state["monsters"]
	for i in monsters.size():
		var it := Combat.monster_intent(state, i)
		if not it.is_empty() and not it.get("guarded", false):
			var t: Hero = it["target"]
			incoming[t.id] = int(incoming.get(t.id, 0)) + int(it["dmg"])
	var hid := current_hero.id
	var n := 0
	for a in living_heroes:
		if a == current_hero:
			continue
		n += 1
		var pick := func(aid=a.id):
			_guard_picking = false
			run_turns.call(func(): GameState.set_hero_action(hid, "guard", 0, aid))
		var text := "%s  %d/%d" % [a.name.split(" the ")[0], a.hp, Combat.max_hp(a)]
		if incoming.has(a.id):
			text += "  (%d dmg incoming)" % int(incoming[a.id])
		var b := _button(text, pick)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.tooltip_text = "Key %d" % n
		row.add_child(b)
		_combat_hotkeys[str(n)] = pick
	var cancel := func():
		_guard_picking = false
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
	b.add_theme_font_size_override("font_size", 12)
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	if current_hero:
		var who := HBoxContainer.new()
		who.add_theme_constant_override("separation", 8)
		who.custom_minimum_size.x = 200
		who.add_child(_icon_trimmed(GameData.portrait_for_hero(current_hero.cls_id, current_hero.pool_id), 56))
		var info := _vbox(2)
		info.alignment = BoxContainer.ALIGNMENT_CENTER
		var nm := _label("%s's turn" % current_hero.name.split(" the ")[0], 15)
		nm.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		info.add_child(nm)
		info.add_child(_label("Lv%d %s · %d/%d HP" % [current_hero.level, GameData.find_class(current_hero.pool_id).get("name", ""), current_hero.hp, Combat.max_hp(current_hero)], 12, true))
		who.add_child(info)
		row.add_child(who)

		var pending: Dictionary = state["pending_actions"].get(current_hero.id, {"action": "attack"})
		var last_action := str(pending.get("action", "attack"))
		var hid := current_hero.id
		var tgt := _combat_target
		var tgt_name := str(monsters[tgt]["name"]) if tgt >= 0 and tgt < monsters.size() else "—"
		var do_attack := func(): if tgt >= 0: attack_cb.call(tgt)
		row.add_child(_cmd_button("res://assets/skills/sword_a.png", "Attack", "1", do_attack, "Attack %s (1). Click a foe to pick another, Tab to cycle." % tgt_name, last_action == "attack"))
		_combat_hotkeys["1"] = do_attack
		if last_action == "attack":
			_combat_hotkeys["Space"] = do_attack
		if Combat.qualifies_for_ability(current_hero):
			var ab: Dictionary = GameData.SUBCLASS_ABILITIES.get(current_hero.pool_id, {})
			var cd: int = current_hero.ability_cooldown
			var do_ability := func(): run_turns.call(func(): GameState.set_hero_action(hid, "ability"))
			var ab_tip := "%s (2) — %s%s" % [str(ab.get("name", "Ability")), str(ab.get("desc", "")), ("\nReady in %d round(s)." % cd) if cd > 0 else ""]
			var ab_btn := _cmd_button(GameData.ability_icon(current_hero.pool_id), str(ab.get("name", "Ability")), "2", do_ability, ab_tip, last_action == "ability", cd)
			ab_btn.custom_minimum_size.x = 120
			row.add_child(ab_btn)
			if cd == 0:
				_combat_hotkeys["2"] = do_ability
				if last_action == "ability":
					_combat_hotkeys["Space"] = do_ability
		var do_defend := func(): run_turns.call(func(): GameState.set_hero_action(hid, "defend"))
		row.add_child(_cmd_button("res://assets/skills/shield_basic.png", "Defend", "3", do_defend, "Defend (3) — take half damage from hits this round.", last_action == "defend"))
		_combat_hotkeys["3"] = do_defend
		if last_action == "defend":
			_combat_hotkeys["Space"] = do_defend
		var allies: Array = living_heroes.filter(func(a): return a != current_hero)
		if not allies.is_empty():
			var start_guard := func():
				if _combat_animating:
					return
				_guard_picking = true
				render()
			var gb := _cmd_button("res://assets/skills/shield_blue.png", "Guard", "4", start_guard, "Guard (4) — pick an ally: attacks aimed at them this round hit you instead, 25% weaker.", last_action == "guard")
			row.add_child(gb)
			_combat_hotkeys["4"] = start_guard
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
		var hint := _label("Target: %s\nSpace repeats your last action" % tgt_name, 12, true)
		hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(hint)
		if _guard_picking:
			_guard_picker(row, state, current_hero, living_heroes, run_turns)
	else:
		var l := _label("The party is down." if living_heroes.is_empty() else "Enemy turn…", 14, true)
		l.custom_minimum_size = Vector2(200, 72)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(l)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tools.add_child(_tool_button("res://assets/skills/boots.png", "×%d" % int(GameState.combat_speed), "Combat speed (click to change)", func():
		GameState.combat_speed = 1.0 if GameState.combat_speed >= 3.0 else GameState.combat_speed + 1.0
		Engine.time_scale = GameState.combat_speed
		GameState.save_settings()
		if not _combat_animating:
			render()
	))
	tools.add_child(_tool_button("res://assets/skills/eye_gem.png", "Log", "Show or hide the fight log", func():
		_combat_log_open = not _combat_log_open
		if not _combat_animating:
			render()
	))
	tools.add_child(_tool_button("res://assets/skills/wing.png", "", "Retreat — leave the fight (the run ends)", func():
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
		if screen == "rift_run":
			render()
	))
	row.add_child(tools)
	return panel


## Round N slides in across the arena once per round; a boss gets a name
## card the first time its fight is shown.
func _play_round_banner(arena: Control, state: Dictionary, W: float, H: float) -> void:
	var round_num := int(state.get("round_num", 0))
	if state.get("is_boss", false) and not is_same(_boss_intro_for, state):
		_boss_intro_for = state
		_banner_state = state
		_banner_round = round_num
		var boss: Dictionary = state["monsters"][0]
		for m in state["monsters"]:
			if float(m["max_hp"]) > float(boss["max_hp"]):
				boss = m
		var card := _vbox(2)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var band := ColorRect.new()
		band.color = Color(0, 0, 0, 0.6)
		band.size = Vector2(W, 96)
		band.position = Vector2(0, H * 0.32)
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arena.add_child(band)
		var nm := _label(str(boss["name"]), 30)
		nm.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
		_shadow(nm)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(nm)
		var mechs: Array[String] = []
		for k in ["mechanic", "mechanic2"]:
			if not boss.get(k, {}).is_empty():
				mechs.append(str(boss[k]["name"]))
		var sub := _label("Rift Warden" + (" · " + ", ".join(mechs) if not mechs.is_empty() else ""), 14)
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
		return
	if (is_same(_banner_state, state) and _banner_round == round_num) or round_num <= 0:
		return
	_banner_state = state
	_banner_round = round_num
	var l := _label("Round %d" % round_num, 34)
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
	box.add_child(_label("+%d XP each" % int(result.get("xp_gain", 0)), 13, true))
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
		top.add_child(_label("%s  Lv%d" % [str(e["name"]).split(" the ")[0], int(e["lv1"])], 13))
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
		bar.tooltip_text = "Max level" if at_cap else "%d / %d XP to Lv%d" % [int(e["xp1"]), int(e["next1"]), int(e["lv1"]) + 1]
		if animate:
			bar.create_tween().tween_property(bar, "value", end_v, 0.8).set_delay(0.25 + 0.12 * i).set_ease(Tween.EASE_OUT)
		mid.add_child(bar)
		row.add_child(mid)
		row.add_child(_label("%d dmg · %d kill%s" % [int(e["dealt"]), int(e["kills"]), "" if int(e["kills"]) == 1 else "s"], 12, true))
		box.add_child(row)
	return box
