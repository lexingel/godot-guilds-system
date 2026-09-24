extends Control
## Root UI controller — mirrors guild-system.html's render() function: one
## place that clears and rebuilds the current screen's Controls from
## GameState, rather than a scene per screen. Uses the Cinzel/Overpass font
## pairing and a themed panel hierarchy (CardPanelViolet/CardPanelEmber/
## StatTileViolet/StatTileEmber) via guild_theme.tres.

@onready var root: MarginContainer = $Root

const DISPLAY_FONT := preload("res://assets/fonts/Cinzel-Bold.ttf")
const BODY_FONT := preload("res://assets/fonts/Overpass-Regular.ttf")

var screen: String = "title"     # title | load_game | credits | onboard | rift_hall | rift_map | party_assembly | rift_run | terminal | crafting_hall | settings
var term_tab: String = "camp"      # camp | roster | inventory | recruits | medical | management | bestiary | compendium | quests
var hub_cluster: String = ""       # "" = camp scene shown; else one of the multi-destination buildings' picker is showing (see _render_hub_cluster)
var pending_crest: int = 1
var pending_guild_name: String = ""
var pending_party: Array[String] = []
var pending_relic_options: Array = []
var pending_relic_choice: int = -1
var selected_hero_id: String = ""
var expanded_skill_tree_kind: String = ""   # "" = no tree section expanded, else which kind's tree is showing — a plain toggle rather than per-hero, so it stays put switching between heroes. A hero can hold several trees (one per evolution stage); only one is expanded at a time.
var evolve_picker_hero_id: String = ""   # "" = closed, else which hero's evolution-path picker is open
var expanded_slot: String = ""     #"<hero_id>:weapon:0"/"<hero_id>:gear:2" — which equip slot's picker is open (hero-scoped since the mid-rift Gear Up panel can show several heroes at once)
var rift_gear_open: bool = false   # "Gear Up" panel toggle on non-combat rift nodes (shop/hazard/fork) — lets the party re-equip between fights without retreating
var confirm_reset: bool = false
var _combat_animating: bool = false
var _flavor_toast: String = ""     # one-shot narrative line (e.g. guild founding) — shown once at the top of the next Terminal render, then cleared
var _s_rank_celebration: Dictionary = {}   # {} = not showing; else GameState.pending_s_rank_reveal's data, held here for the celebration's full on-screen duration (render() fires often — the flag itself is one-shot, this is the "still displaying it" latch)
var _last_guild_tier_name: String = ""   # tracks Guild Tier across renders to detect "just reached a new tier" (tier itself is derived, not stored)
var medical_picker_bed: int = -1   # which empty bed slot is showing its hero picker, -1 = none
var mgmt_branch: String = ""       # "" = branch hub, else a GameData.BRANCHES id
var inv_category: String = ""      # "" = category hub, else "items" | "relics" | "detectors"
var roster_sort: String = "power"          # "power" | "level" | "rank" — cycled via the Roster tab's Sort button
var inv_sort: String = "rarity"            # "rarity" | "value" | "name" — cycled via the Inventory tab's Sort button
var compendium_tab: String = "items"       # "items" | "relics" | "crafting" | "systems"
var _pre_settings_screen: String = "onboard"   # where the Settings gear button returns to
var confirm_delete_slot: int = -1              # which save slot's Delete button is armed, -1 = none
var _last_render_key: String = ""              # screen+term_tab as of the last render() — scroll position is kept across a re-render only when this hasn't changed, so toggling Skills/gear/etc. doesn't jump back to the top but navigating to a different screen still starts scrolled to the top
var _last_scroll_y: float = 0.0


func _ready() -> void:
	GameState.load_settings()
	GameState.load_active_slot()
	AudioManager.set_music_volume(GameState.music_volume)
	AudioManager.set_sfx_volume(GameState.sfx_volume)
	_apply_resolution(GameState.resolution_idx)
	# Deliberately doesn't load_save()/reset() or route past "title" here —
	# every boot lands on the title screen now (New Game/Load Game/Credits/
	# Quit) regardless of whether the active slot has a guild in it, matching
	# the reference title screen rather than auto-resuming. New Game and Load
	# Game both route through _switch_slot(), which is what actually loads
	# (or resets) a slot's state once the player picks one.
	GameState.state_changed.connect(render)
	render()


## Desktop-only: on a Web export the browser/canvas already owns sizing (via
## project.godot's stretch/mode="canvas_items" + aspect="expand", which fits
## the canvas to its container correctly on its own) — forcing an internal
## window resize there fights that and desyncs the visual layout from where
## clicks actually land (confirmed: it's what caused the click-position bug
## reported after this feature first shipped). Real OS window resizing only
## makes sense where the game owns a real OS window, i.e. never on web.
func _apply_resolution(idx: int) -> void:
	if OS.has_feature("web"):
		return
	var opts: Array = GameData.RESOLUTION_OPTIONS
	var opt: Dictionary = opts[idx] if idx >= 0 and idx < opts.size() else opts[0]
	# A maximized/fullscreen OS window silently ignores a `.size` assignment
	# (Godot doesn't auto-restore it), which is why picking a resolution here
	# previously had no visible effect once the window had been maximized.
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(int(opt["w"]), int(opt["h"]))


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
## content column, so it wraps at a sane width via _wrap_label() below instead
## — or via _info_row() when the wrapping text needs to share its row with buttons.
func _label(text: String, size: int = 14, muted: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", DISPLAY_FONT if size >= 18 else BODY_FONT)
	if muted:
		l.add_theme_color_override("font_color", Palette.MUTED)
	return l


## Green above half HP, gold at low-but-not-critical, red once it's dire —
## a quick-scan cue on top of the exact numbers shown alongside every bar.
func _hp_color(ratio: float) -> Color:
	if ratio > 0.5:
		return Palette.RANK_E
	elif ratio > 0.25:
		return Palette.EMBER_BRIGHT
	return Palette.HAZARD


func _hp_bar(current: int, max_val: int, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max(1, max_val)
	bar.value = clampi(current, 0, max_val)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 10)
	bar.size = Vector2(width, 10)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Palette.INK
	bg_style.corner_radius_top_left = 4
	bg_style.corner_radius_top_right = 4
	bg_style.corner_radius_bottom_left = 4
	bg_style.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("background", bg_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = _hp_color(float(max(0, current)) / float(max(1, max_val)))
	fill_style.corner_radius_top_left = 4
	fill_style.corner_radius_top_right = 4
	fill_style.corner_radius_bottom_left = 4
	fill_style.corner_radius_bottom_right = 4
	bar.add_theme_stylebox_override("fill", fill_style)
	return bar


## A plain floating name + HP readout above a hero/monster in the arena — a
## name label over a colored bar with "cur/max" text, no ornate frame. Swapped
## from an earlier wooden-nameplate-prop version to match the reference battle
## screens' simple floating HP bars.
const STATUS_PLATE_HEIGHT := 34.0
func _status_plate(name_text: String, hp: int, max_hp_val: int, width: float = 160.0) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(width, STATUS_PLATE_HEIGHT)
	wrap.size = Vector2(width, STATUS_PLATE_HEIGHT)

	var name_label := _label(name_text, 11)
	name_label.size = Vector2(width, 15)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	wrap.add_child(name_label)

	var bar := _hp_bar(hp, max_hp_val, width)
	bar.position = Vector2(0, 16)
	wrap.add_child(bar)
	var hp_label := _label("%d/%d" % [hp, max_hp_val], 9, true)
	hp_label.size = Vector2(width, 12)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.position = Vector2(0, 27)
	wrap.add_child(hp_label)
	return wrap


## A hero portrait inside GameData.PORTRAIT_FRAME_PATH's ornate frame, sized
## to `size` — shared by the Roster hero card and Recruit offer cards so a
## hero's portrait always reads the same way wherever it appears. Returns an
## empty sized box if this class/pool has no portrait art (never happens for
## the 5 real classes today, but keeps callers from needing their own guard).
func _framed_portrait(cls_id: String, pool_id: String, size: float) -> Control:
	var frame_wrap := Control.new()
	frame_wrap.custom_minimum_size = Vector2(size, size)
	frame_wrap.size = Vector2(size, size)
	var portrait_path := GameData.portrait_for_hero(cls_id, pool_id)
	if portrait_path == "":
		return frame_wrap
	var pf_icon := _icon_trimmed(portrait_path, int(size * 0.82))
	pf_icon.position = Vector2(size * 0.09, size * 0.09)
	frame_wrap.add_child(pf_icon)
	var pf_frame := _icon(GameData.PORTRAIT_FRAME_PATH, int(size))
	pf_frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame_wrap.add_child(pf_frame)
	return frame_wrap


## One battle-action slot: an ornate frame (GameData.RARITY_FRAME_PATH,
## "common" for every action — actions aren't loot, the frame is just the
## established slot language) with the action's icon centered inside, an
## optional cooldown-round badge in the corner, a short caption underneath so
## the action reads without guessing at an icon, and an invisible Button on
## top for input/selection state — same layered-hotspot approach as the camp
## hub's clickable props. Selected state is a filled tint (not just a thin
## border) since the border alone was too easy to miss against the wooden
## shelf background.
func _action_slot(icon_path: String, cooldown_text: String, selected: bool, disabled: bool, cb: Callable, size: float = 48.0, label_text: String = "", frame_path: String = "", tooltip_override: String = "", drop_target: Dictionary = {}) -> Control:
	var label_h := 14.0 if label_text != "" else 0.0
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(size, size + label_h)
	wrap.size = Vector2(size, size + label_h)

	var frame := _icon(frame_path if frame_path != "" else GameData.RARITY_FRAME_PATH["common"], int(size))
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	wrap.add_child(frame)

	if selected:
		var glow := PanelContainer.new()
		var glow_style := StyleBoxFlat.new()
		glow_style.bg_color = Color(Palette.VIOLET.r, Palette.VIOLET.g, Palette.VIOLET.b, 0.32)
		glow_style.border_width_left = 2
		glow_style.border_width_top = 2
		glow_style.border_width_right = 2
		glow_style.border_width_bottom = 2
		glow_style.border_color = Palette.VIOLET
		glow_style.corner_radius_top_left = 4
		glow_style.corner_radius_top_right = 4
		glow_style.corner_radius_bottom_left = 4
		glow_style.corner_radius_bottom_right = 4
		glow.add_theme_stylebox_override("panel", glow_style)
		glow.custom_minimum_size = Vector2(size, size)
		glow.size = Vector2(size, size)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(glow)

	if icon_path != "":
		var icon_size := size * 0.6
		var icon := _icon(icon_path, int(icon_size))
		icon.position = Vector2((size - icon_size) * 0.5, (size - icon_size) * 0.5)
		if disabled:
			icon.modulate = Color(0.5, 0.5, 0.5, 0.7)
		wrap.add_child(icon)

	if cooldown_text != "":
		var badge := PanelContainer.new()
		var badge_style := StyleBoxFlat.new()
		badge_style.bg_color = Palette.HAZARD
		badge_style.corner_radius_top_left = 8
		badge_style.corner_radius_top_right = 8
		badge_style.corner_radius_bottom_left = 8
		badge_style.corner_radius_bottom_right = 8
		badge_style.content_margin_left = 3
		badge_style.content_margin_right = 3
		badge.add_theme_stylebox_override("panel", badge_style)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var badge_label := _label(cooldown_text, 9)
		badge.add_child(badge_label)
		badge.position = Vector2(size * 0.62, size * 0.62)
		wrap.add_child(badge)

	if label_text != "":
		var lbl := _label(label_text, 9, disabled)
		lbl.custom_minimum_size = Vector2(size, label_h)
		lbl.size = Vector2(size, label_h)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.clip_text = true
		lbl.position = Vector2(0, size)
		wrap.add_child(lbl)

	var btn: Button
	if drop_target.is_empty():
		btn = Button.new()
	else:
		var drop_btn := DropButton.new()
		drop_btn.can_accept = drop_target.get("can_accept", Callable())
		drop_btn.on_drop = drop_target.get("on_drop", Callable())
		btn = drop_btn
	btn.flat = true
	btn.custom_minimum_size = wrap.custom_minimum_size
	btn.size = wrap.size
	btn.disabled = disabled
	var clear_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style_name, clear_style)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if tooltip_override != "":
		btn.tooltip_text = tooltip_override
	elif label_text != "":
		btn.tooltip_text = label_text
	btn.pressed.connect(cb)
	wrap.add_child(btn)
	return wrap


## A compact clickable reward-choice card — icon on top, name/rarity/a short
## wrapped description below, replacing the old full-width text button so
## 2-3 rewards read as a row of cards (reference victory screens) instead of
## a stack of buttons taking up the full column height. Same layered-hotspot
## technique as _action_slot: decorative content first, an invisible flat
## Button overlaid last for the actual click handling.
func _reward_tile(icon_path: String, name_text: String, rarity_text: String, desc_text: String, cb: Callable) -> Control:
	const TILE_W := 156.0
	const TILE_H := 122.0
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(TILE_W, TILE_H)
	wrap.size = Vector2(TILE_W, TILE_H)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanelViolet"
	panel.custom_minimum_size = Vector2(TILE_W, TILE_H)
	panel.size = Vector2(TILE_W, TILE_H)
	panel.clip_contents = true
	var col := _vbox(2)
	if icon_path != "":
		var icon_row := HBoxContainer.new()
		icon_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon_row.alignment = BoxContainer.ALIGNMENT_CENTER
		icon_row.add_child(_icon(icon_path, 32))
		col.add_child(icon_row)
	var name_lbl := _label(name_text, 12)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.custom_minimum_size = Vector2(TILE_W - 24.0, 0)
	col.add_child(name_lbl)
	if rarity_text != "":
		var rarity_lbl := _label(rarity_text.capitalize(), 10, true)
		rarity_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(rarity_lbl)
	var desc_lbl := _label(desc_text, 10, true)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.custom_minimum_size = Vector2(TILE_W - 24.0, 0)
	col.add_child(desc_lbl)
	panel.add_child(col)
	wrap.add_child(panel)

	var btn := Button.new()
	btn.flat = true
	btn.custom_minimum_size = wrap.custom_minimum_size
	btn.size = wrap.size
	var clear_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style_name, clear_style)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.tooltip_text = "%s — %s" % [name_text, desc_text]
	btn.pressed.connect(cb)
	wrap.add_child(btn)
	return wrap


## A row of _action_slot controls on a wooden "ability bar" shelf background
## (GameData.ABILITY_BAR_STRIP_PATH, 9-sliced via StyleBoxTexture so it
## stretches to fit however many slots a hero has this fight).
func _slot_row(children: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	# Without this, a VBoxContainer parent stretches the panel to its own
	# full width — the StyleBoxTexture then stretches its tileable middle
	# band across that whole leftover width, showing stray bits of the
	# source art (looks like unrelated furniture) to the right of the actual
	# buttons instead of the bar just hugging its own content.
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var style := StyleBoxTexture.new()
	style.texture = load(GameData.ABILITY_BAR_STRIP_PATH)
	style.texture_margin_left = 60
	style.texture_margin_right = 60
	style.texture_margin_top = 14
	style.texture_margin_bottom = 14
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for c in children:
		row.add_child(c)
	panel.add_child(row)
	return panel


## Pixel-art icon at a fixed size, nearest-neighbor filtered to stay crisp
## (matches the HTML's image-rendering:pixelated).
func _icon(path: String, size: int = 24) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	# Godot 4's default expand_mode (KEEP_SIZE) treats the texture's native
	# resolution as a floor the moment `.size` is assigned — Control.size's
	# setter clamps up to get_combined_minimum_size(), and under KEEP_SIZE that
	# minimum is the texture's own pixel size. So expand_mode has to switch to
	# IGNORE_SIZE *before* `.size`/`custom_minimum_size` are set below, or the
	# clamp bakes in a too-large size that IGNORE_SIZE can no longer shrink
	# back down (bit both a 192x192 UI frame requested at 96 and a 92x200
	# hero portrait requested at 78 before this was reordered).
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.custom_minimum_size = Vector2(size, size)
	# Containers apply custom_minimum_size as actual size automatically, but a
	# plain Control parent (the combat arena's freely-positioned sprites) does
	# not — without this the TextureRect renders at its native texture
	# resolution instead of the intended icon size.
	t.size = Vector2(size, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


## Same visual as _icon(), but for an unequipped Item on the Roster's "drag to
## equip" strip: a DragIcon carrying {"kind": "inventory_item", "item_id",
## "slot_type"} so a matching _equip_slot_frame's drop_target can accept it.
func _draggable_item_icon(it: Item, size: int = 32, compare_for: Hero = null) -> DragIcon:
	var t := DragIcon.new()
	t.texture = load(GameData.ITEM_CATEGORY_ICON_PATH[it.category])
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.custom_minimum_size = Vector2(size, size)
	t.size = Vector2(size, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.tooltip_text = "%s (%s) — %s" % [_loot_display_name(it), GameData.ITEM_CATEGORY_LABEL[it.category], _loot_desc(it, false)]
	if compare_for:
		var cmp := _item_compare_text(it, compare_for)
		if cmp != "":
			t.tooltip_text += "\n\n" + cmp
	t.mouse_default_cursor_shape = Control.CURSOR_MOVE
	t.drag_payload = {"kind": "inventory_item", "item_id": it.id, "slot_type": it.slot_type()}
	return t


## Same as _icon(), but for hero portrait art specifically: crops the texture
## to its opaque pixel bounding box (Image.get_used_rect()) before fitting it
## into the size x size box. The ~100 hero/subclass portraits were generated
## across several batches with wildly inconsistent transparent padding (some
## canvases are cropped tight to the character, others carry 20%+ empty
## margin at fixed heights like 200px) — fitting the raw canvas made
## characters render at very different apparent sizes at the same box size.
## Trimming first makes the visible silhouette itself fill the box
## consistently, regardless of the source canvas's own padding.
func _icon_trimmed(path: String, size: int = 24) -> TextureRect:
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	if img != null:
		var used := img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(used)
			tex = atlas
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.custom_minimum_size = Vector2(size, size)
	t.size = Vector2(size, size)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


## A wide atmospheric header image (stretched to fill, corners rounded to
## match the game's card language) sitting above a screen's actual content —
## purely decorative, no clickable elements on it.
func _banner(path: String, width: float, height: float) -> Control:
	var clip := Control.new()
	clip.custom_minimum_size = Vector2(width, height)
	clip.size = Vector2(width, height)
	clip.clip_contents = true
	var t := TextureRect.new()
	t.texture = load(path)
	t.custom_minimum_size = Vector2(width, height)
	t.size = Vector2(width, height)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip.add_child(t)
	return clip


## Wraps hero/monster names in the combat log in BBCode color so the wall of
## text reads as "who did what to whom" at a glance instead of one uniform
## color — heroes in the accent teal, monsters in the hazard red. [lb] escapes
## any literal '[' first so a stray bracket in a name can't be misread as a
## tag.
func _colorize_log_line(line: String, party: Array[Hero], monsters: Array) -> String:
	var out := line.replace("[", "[lb]")
	for h in party:
		if h.name != "":
			out = out.replace(h.name, "[color=#%s]%s[/color]" % [Palette.VIOLET.to_html(false), h.name])
	for m in monsters:
		var mname: String = str(m.get("name", ""))
		if mname != "":
			out = out.replace(mname, "[color=#%s]%s[/color]" % [Palette.HAZARD.to_html(false), mname])
	return out


## A piece of loot's display text — a Legendary's real effect lives in
## GameData.find_unique_item/relic's authored `desc`, not in kind/value or
## the generic Relic.desc() (built for the normal rolled case), so every
## loot-listing site (reward choice, shop, inventory) routes through here
## instead of duplicating the unique/normal branch three times.
func _loot_desc(obj, is_relic: bool) -> String:
	if is_relic:
		var r: Relic = obj
		if r.unique_id != "":
			var d := str(GameData.find_unique_relic(r.unique_id).get("desc", ""))
			if r.combo_with != "" and Combat.party_has_unique_relic(r.combo_with):
				d += " [combo active!]"
			return d
		return r.desc()
	var it: Item = obj
	if it.unique_id != "":
		var udef := GameData.find_unique_item(it.unique_id)
		return "%s [%s]" % [str(udef.get("desc", "")), GameData.ARCHETYPES.get(str(udef.get("arch", "")), "Unique")]
	var parts: Array[String] = [Combat.describe_skill(it.kind, it.value)]
	if it.secondary_kind != "":
		parts.append(Combat.describe_skill(it.secondary_kind, it.secondary_value))
	if it.tertiary_kind != "":
		parts.append(Combat.describe_skill(it.tertiary_kind, it.tertiary_value))
	for e in it.effects:
		parts.append("%s [%s]" % [Combat.describe_effect(e), GameData.ARCHETYPES.get(str(e.get("arch", "")), "")])
	var text := ", ".join(parts)
	if it.implicit_kind != "":
		text = "Base: %s · %s" % [Combat.describe_skill(it.implicit_kind, it.implicit_value), text]
	if it.item_rank != "":
		text = "Rank %s · %s" % [it.item_rank, text]
	return text


## "Killer's Eye: +14% damage vs foes below 40% HP [Executioner]"
func _passive_text(pool_id: String) -> String:
	var p := GameData.subclass_passive(pool_id)
	if p.is_empty():
		return "None"
	var parts: Array[String] = []
	for e in p["effects"]:
		parts.append(Combat.describe_effect(e))
	return "%s: %s [%s]" % [str(p["name"]), "; ".join(parts), GameData.ARCHETYPES.get(str(p["arch"]), "")]


## "−3% mend; +15% damage while below 50% HP" — a scar's wound and its upside.
func _scar_text(scar_name: String) -> String:
	var parts: Array[String] = []
	var wound: Dictionary = GameData.SCAR_TABLE.get(scar_name, {})
	for kind in wound:
		var s := Combat.describe_skill(kind, absf(float(wound[kind])))
		parts.append("-" + s.trim_prefix("+") if s.begins_with("+") else "less: " + s)
	for e in GameData.SCAR_UPSIDES.get(scar_name, []):
		parts.append(Combat.describe_effect(e))
	return "; ".join(parts)


## History, earned traits, the nearest trait still to earn, and grown bonds.
func _history_lines(h: Hero) -> Array[String]:
	var lines: Array[String] = []
	var hist: Array[String] = []
	for stat in GameData.HISTORY_LABEL:
		var n := int(h.history.get(stat, 0))
		if n > 0:
			hist.append("%d %s" % [n, GameData.HISTORY_LABEL[stat]])
	if not hist.is_empty():
		lines.append("History: " + " · ".join(hist))
	var next_best := {}
	var next_frac := -1.0
	for t in GameData.EARNED_TRAITS:
		if h.earned_traits.has(t["id"]):
			var what: String = Combat.describe_skill(str(t["kind"]), float(t["value"])) if t.has("kind") else "; ".join(t["effects"].map(func(e): return Combat.describe_effect(e)))
			lines.append("Earned: %s — %s [%s]" % [t["name"], what, GameData.ARCHETYPES[t["arch"]]])
		else:
			var frac := float(h.history.get(t["stat"], 0)) / float(t["need"])
			if frac > next_frac:
				next_frac = frac
				next_best = t
	if not next_best.is_empty():
		lines.append("Next trait: %s (%d/%d %s)" % [next_best["name"], int(h.history.get(next_best["stat"], 0)), int(next_best["need"]), GameData.HISTORY_LABEL[next_best["stat"]]])
	var bond_parts: Array[String] = []
	for other in GameState.heroes:
		if other == h:
			continue
		var together := GameState.bond_rifts(h.id, other.id)
		if together > 0:
			bond_parts.append("%s Lv%d (%d rifts)" % [other.name.split(" the ")[0], GameData.bond_level(together), together])
	if not bond_parts.is_empty():
		lines.append("Bonds: " + " · ".join(bond_parts))
	return lines


## "Executioner ×3 · Opener ×1" from Combat.hero_archetype_counts, biggest first.
func _build_text(h: Hero) -> String:
	var counts := Combat.hero_archetype_counts(h)
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s ×%d" % [GameData.ARCHETYPES[k], int(counts[k])])
	return " · ".join(parts)


## Every flat kind->value an item contributes (exactly what
## Combat.hero_item_total sums for it), for side-by-side comparison.
func _item_stat_map(it: Item) -> Dictionary:
	var m := {}
	if it == null:
		return m
	for pair in [[it.kind, it.value], [it.secondary_kind, it.secondary_value], [it.tertiary_kind, it.tertiary_value],
			[it.implicit_kind, it.implicit_value], [it.socketed_kind, it.socketed_value], [it.drawback_kind, it.drawback_value]]:
		if str(pair[0]) != "":
			m[pair[0]] = float(m.get(pair[0], 0.0)) + float(pair[1])
	return m


## "vs Swift Blade: +5% turn speed, -12% damage" — how equipping `it` into
## the slot a quick-equip would pick (_best_swap_slot) changes `h`'s flat
## stats. Situational effects can't be netted as numbers, so they're listed
## as gained/lost instead.
func _item_compare_text(it: Item, h: Hero, slot: int = -2) -> String:
	if slot == -2:
		slot = _best_swap_slot(h, it.slot_type())
	var current: Item = _find_equipped_at(h.id, it.slot_type(), slot) if slot >= 0 else null
	var a := _item_stat_map(it)
	var b := _item_stat_map(current)
	var lines: Array[String] = []
	for kind in GameData.BUILD_KINDS:
		var d: float = float(a.get(kind, 0.0)) - float(b.get(kind, 0.0))
		if absf(d) >= 0.001:
			var s := Combat.describe_skill(kind, absf(d))
			if s.begins_with("+"):
				lines.append(s if d > 0 else "-" + s.substr(1))
			else:
				lines.append(("more: " if d > 0 else "less: ") + s)
	var gained: Array = GameData.find_unique_item(it.unique_id).get("effects", []) if it.unique_id != "" else it.effects
	for e in gained:
		lines.append("gains: " + Combat.describe_effect(e))
	if current:
		var lost: Array = GameData.find_unique_item(current.unique_id).get("effects", []) if current.unique_id != "" else current.effects
		for e in lost:
			lines.append("loses: " + Combat.describe_effect(e))
	if lines.is_empty():
		return ""
	return "%s:\n%s" % ["vs " + current.name if current else "Into an empty slot", "\n".join(lines)]


func _loot_display_name(obj) -> String:
	var uid: String = obj.unique_id
	return "★ %s" % obj.name if uid != "" else obj.name


## Fixed-height, internally-scrolled log — `fit_content` used to grow the
## label a line taller every round, pushing the action buttons further down
## the page each time. scroll_follow keeps the newest line in view without
## the caller needing to manage scroll position.
func _log_richtext(lines: Array, party: Array[Hero], monsters: Array, height: float = 160.0) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.custom_minimum_size = Vector2(0, height)
	rt.size = Vector2(0, height)
	rt.scroll_active = true
	rt.scroll_following = true
	rt.add_theme_font_size_override("normal_font_size", 12)
	var body := ""
	for line in lines:
		body += _colorize_log_line(str(line), party, monsters) + "\n"
	rt.text = body
	return rt


## Wraps an _icon() TextureRect in a plain Control sized to match it — plain
## Controls don't auto-layout their children the way Container nodes do, so a
## combat animation can freely tween the wrapper's position/modulate (a lunge,
## a hit-shake) and freely position a damage-number Label inside it, without
## fighting whatever Container the wrapper itself sits in.
func _wrap_icon(rect: TextureRect) -> Control:
	var c := Control.new()
	c.custom_minimum_size = rect.custom_minimum_size
	c.size = rect.custom_minimum_size
	c.add_child(rect)
	return c


## A soft dark ellipse under a hero/monster's feet so they read as standing on
## the ground rather than floating over the battle background — add this to
## `parent` (the arena) *before* the wrapper it belongs to, so it paints
## underneath (Godot draws siblings in child order).
func _add_ground_shadow(parent: Control, wrapper_pos: Vector2, wrapper_size: float) -> void:
	var shadow := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.35)
	style.corner_radius_top_left = 999
	style.corner_radius_top_right = 999
	style.corner_radius_bottom_left = 999
	style.corner_radius_bottom_right = 999
	shadow.add_theme_stylebox_override("panel", style)
	var shadow_w: float = wrapper_size * 0.8
	var shadow_h: float = shadow_w * 0.32
	shadow.custom_minimum_size = Vector2(shadow_w, shadow_h)
	shadow.size = Vector2(shadow_w, shadow_h)
	shadow.position = Vector2(wrapper_pos.x + (wrapper_size - shadow_w) * 0.5, wrapper_pos.y + wrapper_size - shadow_h * 0.5)
	parent.add_child(shadow)


## Opt-in wrapping variant for long standalone text (combat log lines,
## descriptions) — use where the label is the sole child of its row (a
## VBoxContainer entry). For a row that mixes wrapping text with sibling
## buttons inside an HBoxContainer, use _info_row() instead.
func _wrap_label(text: String, size: int = 14, muted: bool = false) -> Label:
	var l := _label(text, size, muted)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## For a row that mixes a wrapping text label with one or more buttons (item/
## relic/skill rows with a name+description string next to Buy/Equip/Sell) —
## the label gets SIZE_EXPAND_FILL + autowrap so it wraps onto multiple lines
## instead of being clipped by its sibling controls; `leading` is an optional
## icon/checkbox placed before the text, `actions` are placed after it.
func _info_row(text: String, size: int, actions: Array[Control], leading: Control = null, muted: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if leading:
		row.add_child(leading)
	row.add_child(_wrap_label(text, size, muted))
	for a in actions:
		row.add_child(a)
	return row


## Every button in the game is built through here, so playing the click SFX
## here once covers all of them for free — no per-call-site wiring needed,
## and it costs nothing if assets/audio/sfx/ui_click.ogg doesn't exist yet
## (AudioManager.play_sfx no-ops on a missing path).
func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	# Floor every button at a real touch-target height (~40px) regardless of
	# the theme's own padding, so the game is tappable on a touch/mobile
	# viewport without a per-button size review — one choke point fixes it
	# everywhere since every button in the game is built through here.
	b.custom_minimum_size.y = 40
	b.pressed.connect(func():
		AudioManager.play_sfx(GameData.SFX_PATH["ui_click"])
		cb.call()
	)
	return b


## Every non-hotspot button in the game goes through one of these two — an
## icon alongside whatever text the button already had (costs/sort state/
## toggle state stay readable, the icon just adds a scannable visual cue).
## Two separate wrappers (rather than one with a bool flag) so a call site
## converts by just adding a leading icon argument and renaming the function,
## with no trailing-argument fiddling after a multi-line callback closure.
func _icon_button(icon_path: String, text: String, cb: Callable) -> Button:
	var b := _button(text, cb)
	if icon_path != "":
		b.icon = load(icon_path)
	return b


## Same idea as _icon_button, but the button's color follows what the
## action represents instead of always reusing the theme's single accent —
## "violet" for arcane/progression actions, "ember" for economy/danger/combat
## actions, matching the same domain rule panels/stat-tiles already use.
func _icon_domain_button(domain: String, icon_path: String, text: String, cb: Callable) -> Button:
	var b := _button(text, cb)
	b.theme_type_variation = &"ButtonViolet" if domain == "violet" else &"ButtonEmber"
	if icon_path != "":
		b.icon = load(icon_path)
	return b


func _hsep() -> HSeparator:
	return HSeparator.new()


## A small colored heading strip for a card that needs a title set apart from
## its body text (e.g. a Roster hero card) — a plain StyleBoxFlat rather than
## extracting the UI pack's header-bar art, since that art comes fused to a
## specific panel body with baked-in text and isn't reusable standalone.
func _title_strip(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.SURFACE3
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	p.add_theme_stylebox_override("panel", style)
	var l := _label(text, 14)
	l.add_theme_color_override("font_color", Palette.VIOLET)
	p.add_child(l)
	return p


## A brief violet flash over the whole screen the instant a rift run begins —
## echoes the Rift Hall's own portal color, so "stepping through" reads as
## one deliberate beat instead of the screen just quietly changing under you.
## Called right after render() has already built the new rift_run screen, so
## it fades out ON TOP of the arrival rather than covering a blank frame.
func _play_rift_entry_flash() -> void:
	var flash := ColorRect.new()
	flash.color = Color(0.56, 0.24, 0.86, 1.0)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(flash)
	var flash_tw := create_tween()
	flash_tw.tween_property(flash, "color:a", 0.0, 0.45).set_ease(Tween.EASE_OUT)
	flash_tw.tween_callback(flash.queue_free)


func render() -> void:
	GameState.resolve_recovery()
	GameState.resolve_rift_map()
	GameState.resolve_guild_board()
	var newly_claimed := GameState.check_milestones()
	if not newly_claimed.is_empty():
		var m = GameData.MILESTONES.filter(func(x): return str(x["id"]) == newly_claimed[0])[0]
		_flavor_toast = "Milestone reached: %s" % str(m["label"])
	if screen == "terminal" and GameState.run.is_empty() and not GameState.pending_riftbreak_ranks.is_empty():
		GameState.start_riftbreak_encounter()
		if not GameState.run.is_empty():
			screen = "rift_run"
	if not GameState.pending_s_rank_reveal.is_empty() and _s_rank_celebration.is_empty():
		_s_rank_celebration = GameState.pending_s_rank_reveal
		GameState.pending_s_rank_reveal = {}
		AudioManager.play_sfx(GameData.SFX_PATH["victory"])
		get_tree().create_timer(2.5).timeout.connect(func():
			_s_rank_celebration = {}
			render()
		)
	# Toggling something in place (Skills, an equip slot, a Guild Management
	# branch, ...) rebuilds the whole screen via _clear_root() below, which
	# would otherwise silently snap the scroll position back to the top every
	# time — jarring on a long screen. Carry it over whenever we're rebuilding
	# the SAME screen/tab; only a real navigation resets to the top.
	var render_key := "%s|%s" % [screen, term_tab]
	var is_navigation := render_key != _last_render_key
	if not is_navigation:
		for c in root.get_children():
			if c is VBoxContainer:
				for cc in c.get_children():
					if cc is ScrollContainer:
						_last_scroll_y = cc.scroll_vertical
	else:
		_last_scroll_y = 0.0
	_last_render_key = render_key

	_clear_root()
	var outer := _vbox(10)
	root.add_child(outer)
	if screen not in ["title", "load_game", "credits", "onboard"]:
		_topbar(outer, _breadcrumb_for_screen())
	if not _s_rank_celebration.is_empty():
		outer.add_child(_render_s_rank_celebration(_s_rank_celebration))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	scroll.set_deferred("scroll_vertical", _last_scroll_y)
	var v := _vbox(14)
	# Rift Run gets extra width for the combat arena (background + positioned
	# sprites) sitting alongside the log/action column, and the camp hub
	# needs room for its 6-building scene — every other screen stays at the
	# original column width.
	var is_camp_scene := screen == "terminal" and term_tab == "camp" and hub_cluster == ""
	v.custom_minimum_size = Vector2(940 if screen == "rift_run" else (800 if is_camp_scene else 760), 0)
	scroll.add_child(v)

	match screen:
		"title": _render_title(v)
		"load_game": _render_load_game(v)
		"credits": _render_credits(v)
		"onboard": _render_onboard(v)
		"rift_hall": _render_rift_hall(v)
		"rift_map": _render_rift_map_hub(v)
		"party_assembly": _render_party_assembly(v)
		"rift_run": _render_rift_run(v)
		"crafting_hall": _render_crafting_hall(v)
		"settings": _render_settings(v)
		"terminal": _render_terminal(v)
	_update_screen_music()

	# A real navigation (not an in-place data refresh — see is_navigation
	# above) fades the new screen in from transparent instead of just
	# snapping into place, so moving between hubs reads as one continuous
	# world instead of a slideshow of unrelated pages.
	if is_navigation:
		root.modulate = Color(1, 1, 1, 0)
		var fade_tw := create_tween()
		fade_tw.tween_property(root, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)


## Only 2 music tracks are planned for now (combat, camp — see the Suno plan
## in the project doc), so this only ever switches between those two states
## and otherwise leaves whatever's already playing alone, rather than
## stopping/restarting on every screen that doesn't have a track assigned
## yet. Both AudioManager.play_music calls are safe to make unconditionally
## (they already no-op on a repeat of the same path, or a missing file).
func _update_screen_music() -> void:
	if screen == "terminal":
		AudioManager.play_music(GameData.MUSIC_PATH["camp"])
	elif screen == "rift_run":
		var kind := GameState.current_node_kind()
		var ns: Dictionary = GameState.run.get("node_state", {})
		if kind in ["combat", "boss", "elite"] and ns.has("combat_state"):
			AudioManager.play_music(GameData.MUSIC_PATH["combat"])


## Pinned HUD stays outside the ScrollContainer, so the guild identity,
## currencies, and "where am I" breadcrumb never scroll out of view.
func _breadcrumb_for_screen() -> String:
	match screen:
		"rift_hall": return "Rift Hall"
		"rift_map": return "Rift Map"
		"party_assembly": return "Party Assembly"
		"rift_run": return "Rift Run — Floor %d/%d" % [int(GameState.run.get("pos", 0)) + 1, GameState.run.get("layers", []).size()]
		"crafting_hall": return "Crafting Hall"
		"settings": return "Settings"
		"terminal": return "Terminal" if term_tab == "camp" else "Terminal — %s" % term_tab.capitalize()
		_: return ""


## The Rank-S celebration banner shown pinned above the scroll area (outside
## the ScrollContainer, like the HUD) for the ~2.5s render() holds it. A
## pop-in scale/fade plus a looping glow pulse on the portrait ring — no
## full-viewport flash, since this Container-based layout isn't built for
## free-floating overlays and a contained "the banner itself glows" reads
## just as celebratory without fighting that. Tweens are bound to `banner`
## itself so they're auto-killed the moment the next render() frees it,
## rather than lingering bound to Main (which never gets freed).
func _render_s_rank_celebration(data: Dictionary) -> Control:
	var banner := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.RANK_S.r, Palette.RANK_S.g, Palette.RANK_S.b, 0.18)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Palette.RANK_S
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_right = 10
	style.corner_radius_bottom_left = 10
	style.content_margin_left = 14
	style.content_margin_top = 10
	style.content_margin_right = 14
	style.content_margin_bottom = 10
	banner.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var portrait_wrap := PanelContainer.new()
	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(Palette.RANK_S.r, Palette.RANK_S.g, Palette.RANK_S.b, 0.4)
	glow_style.corner_radius_top_left = 30
	glow_style.corner_radius_top_right = 30
	glow_style.corner_radius_bottom_right = 30
	glow_style.corner_radius_bottom_left = 30
	glow_style.shadow_color = Color(Palette.RANK_S.r, Palette.RANK_S.g, Palette.RANK_S.b, 0.8)
	glow_style.shadow_size = 16
	portrait_wrap.add_theme_stylebox_override("panel", glow_style)
	portrait_wrap.add_child(_framed_portrait(str(data["cls_id"]), str(data["pool_id"]), 56.0))
	row.add_child(portrait_wrap)

	var mid := _vbox(2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var headline := _label("★ RANK S ★", 18)
	headline.add_theme_color_override("font_color", Palette.RANK_S)
	mid.add_child(headline)
	var source_text := "joins as Champion!" if str(data["source"]) == "champion" else "is available to recruit!"
	mid.add_child(_label("%s %s" % [str(data["name"]), source_text], 13))
	row.add_child(mid)

	banner.add_child(row)

	banner.scale = Vector2(0.85, 0.85)
	banner.modulate.a = 0.0
	var pop_tw := banner.create_tween()
	pop_tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop_tw.tween_property(banner, "scale", Vector2.ONE, 0.25)
	pop_tw.parallel().tween_property(banner, "modulate:a", 1.0, 0.2)

	var glow_tw := banner.create_tween()
	glow_tw.set_loops()
	glow_tw.tween_property(portrait_wrap, "modulate", Color(1.3, 1.3, 1.0), 0.5)
	glow_tw.tween_property(portrait_wrap, "modulate", Color(1.0, 1.0, 1.0), 0.5)

	return banner


## The header bar — previously just a bare HBoxContainer floating directly on
## the screen background with a plain hairline under it, so the currency
## tiles' own borders were the only bordered thing up there. Wrapped in one
## bordered bar so the whole header reads as a single designed piece instead
## of loose elements, matching the bordered-card language the rest of the UI
## already uses (CardPanelEmber/StatTileEmber).
func _topbar(container: Control, breadcrumb: String = "") -> void:
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Palette.SURFACE2
	bar_style.border_width_bottom = 2
	bar_style.border_color = Palette.EMBER_DEEP
	bar_style.content_margin_left = 12.0
	bar_style.content_margin_right = 12.0
	bar_style.content_margin_top = 8.0
	bar_style.content_margin_bottom = 8.0
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", bar_style)
	var bar_v := _vbox(4)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.add_child(_icon(GameData.CREST_PATH[GameState.guild_crest - 1], 24))
	var name_lbl := _label(GameState.guild_name, 16)
	name_lbl.add_theme_font_override("font", DISPLAY_FONT)
	row.add_child(name_lbl)
	var stat_spacer := Control.new()
	stat_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(stat_spacer)
	for entry in [
		[GameData.CURRENCY_ICON_PATH["coins"], GameState.coins],
		[GameData.CURRENCY_ICON_PATH["crystals"], GameState.crystals],
		[GameData.CURRENCY_ICON_PATH["tokens"], GameState.tokens],
		[GameData.CURRENCY_ICON_PATH["reputation"], GameState.reputation],
	]:
		var stat_row := HBoxContainer.new()
		stat_row.add_child(_icon(entry[0], 18))
		stat_row.add_child(_label(str(entry[1]), 16))
		var tile := PanelContainer.new()
		tile.theme_type_variation = &"StatTileEmber"
		tile.add_child(stat_row)
		row.add_child(tile)
	var settings_btn := TextureButton.new()
	settings_btn.texture_normal = load(GameData.CAMP_HUB_ICON_PATH["settings"])
	settings_btn.ignore_texture_size = true
	settings_btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	settings_btn.custom_minimum_size = Vector2(32, 32)
	settings_btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	settings_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	settings_btn.tooltip_text = "Settings"
	settings_btn.pressed.connect(func():
		AudioManager.play_sfx(GameData.SFX_PATH["ui_click"])
		_pre_settings_screen = screen
		screen = "settings"
		render()
	)
	row.add_child(settings_btn)
	bar_v.add_child(row)
	if breadcrumb != "":
		bar_v.add_child(_label(breadcrumb, 12, true))
	bar.add_child(bar_v)
	container.add_child(bar)


# ---------------- Title ----------------
## The very first thing every boot shows now (see _ready()) — New Game finds
## the first empty save slot and jumps straight into founding a guild there,
## or falls back to the slot list if all 3 are full so the player picks one
## to overwrite. Load Game and Credits are their own screens; Quit is hidden
## on Web (a browser tab can't close itself, and Godot's own quit() there
## just does nothing visible — see _apply_resolution's identical OS.has_feature
## gate for the same "web owns this, not us" reasoning).
func _render_title(v: VBoxContainer) -> void:
	v.add_child(_banner(GameData.TITLE_BG, 760, 320))

	var title_lbl := _label("Guild System", 30)
	title_lbl.add_theme_font_override("font", DISPLAY_FONT)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(title_lbl)
	v.add_child(_hsep())

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var menu := _vbox(8)
	menu.custom_minimum_size.x = 280
	menu.add_child(_icon_domain_button("violet", "", "New Game", func():
		for i in GameState.SLOT_COUNT:
			if GameState.slot_summary(i).get("empty", true):
				_switch_slot(i)
				return
		screen = "load_game"
		render()
	))
	menu.add_child(_button("Load Game", func():
		screen = "load_game"
		render()
	))
	menu.add_child(_button("Credits", func():
		screen = "credits"
		render()
	))
	if not OS.has_feature("web"):
		menu.add_child(_button("Quit", func():
			get_tree().quit()
		))
	center.add_child(menu)
	v.add_child(center)


func _render_load_game(v: VBoxContainer) -> void:
	v.add_child(_label("Load Game", 20))
	_render_slot_list(v)
	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back", func():
		screen = "title"
		render()
	))


func _render_credits(v: VBoxContainer) -> void:
	v.add_child(_label("Credits", 20))
	v.add_child(_label("Guild System", 18))
	v.add_child(_wrap_label("A roguelite guild-management game — recruit heroes, evolve their subclasses, and send them through the Rifts.", 13, true))
	v.add_child(_hsep())
	v.add_child(_label("Built with Godot Engine 4.7", 13))
	v.add_child(_label("Pixel art generated with PixelLab", 13))
	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back", func():
		screen = "title"
		render()
	))


# ---------------- Onboard ----------------
func _render_onboard(v: VBoxContainer) -> void:
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	var slot_lbl := _label("Save Slot %d" % (GameState.active_slot + 1), 12, true)
	slot_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(slot_lbl)
	top_row.add_child(_icon_button(GameData.CAMP_HUB_ICON_PATH["settings"], "Settings", func():
		_pre_settings_screen = "onboard"
		screen = "settings"
		render()
	))
	v.add_child(top_row)

	v.add_child(_label("Name Your Guild", 22))
	var edit := LineEdit.new()
	edit.placeholder_text = "Guild name"
	edit.text = pending_guild_name
	edit.text_changed.connect(func(t: String): pending_guild_name = t)
	v.add_child(edit)

	v.add_child(_label("Choose a Crest", 16))
	var crest_row := HBoxContainer.new()
	crest_row.add_theme_constant_override("separation", 12)
	crest_row.add_child(_icon(GameData.CREST_PATH[pending_crest - 1], 64))
	crest_row.add_child(_icon_button(GameData.BUTTON_ICON_PATH["dice"], "Randomize", func():
		pending_crest = 1 + randi() % GameData.CREST_PATH.size()
		render()
	))
	v.add_child(crest_row)

	v.add_child(_icon_domain_button("violet", GameData.BUTTON_ICON_PATH["confirm"], "Found the Guild", func():
		var n := edit.text.strip_edges()
		if n == "":
			return
		GameState.guild_name = n
		GameState.guild_crest = pending_crest
		GameState.refresh_recruit_pool()
		GameState.save()
		pending_guild_name = ""
		pending_crest = 1
		_flavor_toast = GameData.narrative_line("guild_founded")
		screen = "terminal"
		render()
	))


# ---------------- Rift Hall ----------------
## Lesser and Endless Rift are each a gate on the rift chamber's background
## art, clickable straight into Party Assembly — no intermediate detail view
## since there's nothing else to decide here, unlike Guild Management/
## Inventory's hubs. The chained third gateway in the art gets a hotspot too
## once GameState.greater_rift_unlocked() — inert (no hotspot at all) before that.
func _render_rift_hall(v: VBoxContainer) -> void:
	v.add_child(_label("Rift Hall", 20))

	var scene_size := Vector2(700, 340)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size

	var bg := TextureRect.new()
	bg.texture = load(GameData.RIFTHALL_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)

	var camp_scale := Vector2(700.0 / 320.0, 340.0 / 200.0)
	var lesser: Dictionary = GameData.DIFFICULTIES[0]
	var gate_entries := [
		["%s — Floors %d · Rec. Power %d" % [lesser["name"], lesser["floors"], lesser["rec_power"]],
			Rect2(0, 0, 230, 340), Rect2(18, 65, 68, 98),
			func(): pending_party.clear(); screen = "party_assembly"; _pending_diff_id = str(lesser["id"]); _pending_endless = false; render()],
		["Endless Rift — scales forever. Best cycle: %d" % GameState.best_endless_cycle,
			Rect2(230, 0, 240, 340), Rect2(110, 20, 97, 130),
			func(): pending_party.clear(); screen = "party_assembly"; _pending_diff_id = "endless"; _pending_endless = true; render()],
	]
	# The chained, rubble-blocked archway to the right stays inert until
	# GameState.greater_rift_unlocked() (earned by sealing rifts, not bought
	# with Guild Management currency) — no hotspot at all while locked, same
	# as this gate's behavior before Greater Rift existed.
	if GameState.greater_rift_unlocked():
		var greater: Dictionary = GameData.DIFFICULTIES[1]
		gate_entries.append(["%s — Floors %d · Rec. Power %d" % [greater["name"], greater["floors"], greater["rec_power"]],
			Rect2(470, 0, 230, 340), Rect2(230, 30, 78, 140),
			func(): pending_party.clear(); screen = "party_assembly"; _pending_diff_id = str(greater["id"]); _pending_endless = false; render()])
	for entry in gate_entries:
		var label_text: String = entry[0]
		var hit_rect: Rect2 = entry[1]
		var native_rect: Rect2 = entry[2]
		var cb: Callable = entry[3]
		var glow_rect := Rect2(
			native_rect.position.x * camp_scale.x, native_rect.position.y * camp_scale.y,
			native_rect.size.x * camp_scale.x, native_rect.size.y * camp_scale.y
		)
		var hotspot := _camp_area_hotspot(hit_rect, glow_rect, label_text, cb)
		hotspot.position = hit_rect.position
		scene.add_child(hotspot)

	v.add_child(scene)
	if not GameState.greater_rift_unlocked():
		v.add_child(_label("Greater Rift — Seal %d more Rift(s) to unlock (%d/3)" % [3 - GameState.rifts_sealed, GameState.rifts_sealed], 12))
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back to Terminal", func():
		screen = "terminal"
		render()
	))


## 6 real hotspots positioned directly on the rift-marker glows already
## visible in riftmap_bg.png, matching Rift Hall's own gate-hotspot pattern —
## each a small portal icon (reusing icon_rift.png, the same purple-swirl
## icon Rift Hall's own gate uses) with a persistent "Rank X — mm:ss" caption
## instead of a fixed label, since that's live per-render info a player needs
## to see without hovering. First-draft marker coordinates (native 320x200
## image space, adjustable after a visual check like every other hand-placed
## hotspot this project has added), scaled the same way every other scene's
## hotspots already are.
const RIFT_MAP_MARKER_POS: Array[Vector2] = [
	Vector2(90, 60), Vector2(190, 55), Vector2(60, 100),
	Vector2(160, 90), Vector2(240, 95), Vector2(110, 130),
]

func _render_rift_map_hub(v: VBoxContainer) -> void:
	v.add_child(_label("Rift Map", 20))
	v.add_child(_label("Rifts open at random ranks and stay for a limited time. Leave one unaddressed and its threat spills out as a forced fight next time you're back at the Terminal.", 12, true))

	var scene_size := Vector2(700, 200)
	var scene := Control.new()
	scene.custom_minimum_size = scene_size

	var bg := TextureRect.new()
	bg.texture = load(GameData.RIFTMAP_BG)
	bg.custom_minimum_size = scene_size
	bg.size = scene_size
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scene.add_child(bg)

	var map_scale := Vector2(scene_size.x / 320.0, scene_size.y / 200.0)
	var now := int(Time.get_unix_time_from_system() * 1000)
	var icon_size := 32.0
	for i in GameState.rift_map.size():
		var slot: Dictionary = GameState.rift_map[i]
		if slot.is_empty():
			continue
		var rank := str(slot.get("rank", "F"))
		var remain_ms: int = max(0, int(slot.get("expires_at", 0)) - now)
		var remain_s := remain_ms / 1000
		var mm := remain_s / 60
		var ss := remain_s % 60
		var caption := "Rank %s — %02d:%02d" % [rank, mm, ss]
		var bounty: Dictionary = slot.get("bounty", {})
		if not bounty.is_empty():
			caption += "\n+%dc, +%d Rep" % [int(bounty.get("coins", 0)), int(bounty.get("reputation", 0))]

		var hotspot := _camp_hotspot(GameData.CAMP_HUB_ICON_PATH["rift"], icon_size, caption, func(idx=i, r=rank):
			pending_party.clear()
			pending_relic_options.clear()
			pending_relic_choice = -1
			_pending_rift_rank = r
			_pending_map_slot_idx = idx
			screen = "party_assembly"
			render()
		)
		var marker: Vector2 = RIFT_MAP_MARKER_POS[i % RIFT_MAP_MARKER_POS.size()]
		hotspot.position = Vector2(marker.x * map_scale.x, marker.y * map_scale.y) - Vector2(icon_size, icon_size) / 2.0
		var rank_label := hotspot.get_child(1) as Label
		rank_label.add_theme_color_override("font_color", Palette.rank_color(rank))
		scene.add_child(hotspot)

	v.add_child(scene)

	if not GameState.pending_riftbreak_ranks.is_empty():
		v.add_child(_hsep())
		v.add_child(_label("A Riftbreak is looming — %d unaddressed rift(s) will spill out next time you return to the Terminal." % GameState.pending_riftbreak_ranks.size(), 12, true))

	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back to Terminal", func():
		screen = "terminal"
		render()
	))


var _pending_diff_id: String = "lesser"
var _pending_endless: bool = false
var _pending_hardcore: bool = false
var pending_incense_id: String = ""
## Non-empty only when Party Assembly was entered from the Rift Map hub
## (rather than Rift Hall) — routes "Enter the Rift" to start_map_rift()
## instead of start_run(), hides the Hardcore toggle (retired from mapped
## rifts), and sends "Back" to the map instead of the hall.
var _pending_rift_rank: String = ""
var _pending_map_slot_idx: int = -1


# ---------------- Party Assembly ----------------
func _render_party_assembly(v: VBoxContainer) -> void:
	v.add_child(_label("Assemble Party (pick up to 4)", 20))
	var champ := GameState.ensure_champion()
	var champ_row := HBoxContainer.new()
	var champ_portrait := GameData.portrait_for_hero(champ.cls_id, champ.pool_id)
	if champ_portrait != "":
		champ_row.add_child(_icon(champ_portrait, 48))
	champ_row.add_child(_label("Champion: %s — Rank %s (always joins) · %d/%d HP" % [champ.name, champ.rank, champ.hp, Combat.max_hp(champ)], 13))
	champ_row.add_child(_icon_button("res://assets/skills/shield_orange.png" if champ.formation != "back" else "res://assets/skills/shield_basic.png", "Back" if champ.formation != "back" else "Front", func(id=champ.id, f=champ.formation):
		GameState.set_hero_formation(id, "back" if f != "back" else "front")
		render()
	))
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
			row.add_child(_icon_trimmed(portrait_path, 40))
		var status := " (downed)" if h.is_downed() else ""
		row.add_child(_label("%s — Lv%d %s · %d/%d HP%s" % [h.name, h.level, h.cls_id.capitalize(), h.hp, Combat.max_hp(h), status]))
		row.add_child(_icon_button("res://assets/skills/shield_orange.png" if h.formation != "back" else "res://assets/skills/shield_basic.png", "Back" if h.formation != "back" else "Front", func(id=h.id, f=h.formation):
			GameState.set_hero_formation(id, "back" if f != "back" else "front")
			render()
		))
		v.add_child(row)
	if GameState.heroes.is_empty():
		v.add_child(_label("No heroes yet — recruit some from the Guild Terminal first."))

	# Surface any Hero Bond among the currently-picked heroes (+ the Champion,
	# who always joins) so it's discoverable while assembling a party, not
	# just a silent combat bonus.
	var picked_pool_ids := {champ.pool_id: true}
	for h in GameState.heroes:
		if pending_party.has(h.id):
			picked_pool_ids[h.pool_id] = true
	var active_bonds: Array[String] = []
	for bond in GameData.HERO_BONDS:
		if picked_pool_ids.has(bond["a"]) and picked_pool_ids.has(bond["b"]):
			active_bonds.append(str(bond["name"]))
	if not active_bonds.is_empty():
		v.add_child(_label("Bond active: %s" % ", ".join(active_bonds), 12, true))

	# Party-kind synergy preview (Resonance/Eclectic) — computed here from
	# pending_party rather than GameState.party_resonance_bonus(), since that
	# reads the already-started run and this screen runs BEFORE the run
	# exists. Same rule, just previewed off the picks-in-progress.
	var picked_kind_counts := {}
	for h2 in GameState.heroes:
		if pending_party.has(h2.id):
			var cls2 := GameData.find_class(h2.pool_id)
			if not cls2.is_empty():
				var k2: String = cls2.get("kind", "")
				picked_kind_counts[k2] = int(picked_kind_counts.get(k2, 0)) + 1
	var resonant_kinds: Array[String] = []
	for k2 in picked_kind_counts:
		if int(picked_kind_counts[k2]) >= 2:
			resonant_kinds.append(k2)
	if not resonant_kinds.is_empty():
		var kind_bonuses: Array[String] = []
		for rk in resonant_kinds:
			kind_bonuses.append(Combat.describe_skill(rk, GameData.PARTY_RESONANCE_BONUS))
		v.add_child(_label("Resonance active - shared builds reinforce each other (%s)" % ", ".join(kind_bonuses), 12, true))
	elif picked_kind_counts.size() >= 3:
		v.add_child(_label("Eclectic active - a fully varied party (+%s to everything)" % Combat.describe_skill("dmg_pct", GameData.PARTY_ECLECTIC_BONUS), 12, true))

	v.add_child(_hsep())
	var choice_count := GameState.relic_choice_count()
	if choice_count > 0:
		v.add_child(_label("Starting Relic (pick one, optional)"))
		if pending_relic_options.is_empty():
			# S-rank+ mapped rifts carry a "relic_rarity_floor_down" modifier —
			# it suppresses Guild Management's inherited_power() floor-raise
			# (which normally bumps a rolled Common up to Rare) for this
			# starting-relic roll specifically, so an S+ rift's starting pick
			# can't lean on that safety net the way a normal run's can.
			var floor_suppressed: bool = _pending_rift_rank != "" and bool(GameData.RIFT_RANK_MODIFIERS.get(_pending_rift_rank, {}).get("relic_rarity_floor_down", 0))
			for i in choice_count:
				var rarity := "rare" if (GameState.inherited_power() and not floor_suppressed and Combat.weighted_rarity() == "common") else Combat.weighted_rarity()
				pending_relic_options.append(Combat.gen_relic(rarity))
	for i in pending_relic_options.size():
		var r: Relic = pending_relic_options[i]
		var rb := CheckButton.new()
		rb.button_pressed = pending_relic_choice == i
		rb.toggled.connect(func(on: bool):
			pending_relic_choice = i if on else -1
			render()
		)
		v.add_child(_info_row("%s (%s) — %s" % [r.name, r.type, r.desc()], 14, [], rb))

	if not GameState.consumables.is_empty():
		v.add_child(_hsep())
		v.add_child(_label("Field Incense (pick one, optional) — lasts the whole rift"))
		for c in GameState.consumables:
			var cid: String = str(c["id"])
			var def := GameData.find_incense(str(c["incense_id"]))
			var ib := CheckButton.new()
			ib.button_pressed = pending_incense_id == cid
			ib.toggled.connect(func(on: bool, id=cid):
				pending_incense_id = id if on else ""
				render()
			)
			v.add_child(_info_row("%s — %s" % [def["name"], def["desc"]], 14, [], ib))

	v.add_child(_hsep())
	if _pending_rift_rank == "":
		var hc_toggle := CheckButton.new()
		hc_toggle.text = "Hardcore Mode — ×1.5 rewards, a loss removes your heroes for good"
		hc_toggle.button_pressed = _pending_hardcore
		hc_toggle.toggled.connect(func(on: bool):
			_pending_hardcore = on
			render()
		)
		v.add_child(hc_toggle)
	else:
		v.add_child(_label("Rift Rank %s — Hardcore Mode is retired from mapped rifts." % _pending_rift_rank, 12, true))

	v.add_child(_hsep())
	v.add_child(_icon_domain_button("violet", GameData.CAMP_HUB_ICON_PATH["rift"], "Enter the Rift", func():
		if pending_party.is_empty():
			return
		var chosen: Relic = pending_relic_options[pending_relic_choice] if pending_relic_choice >= 0 else null
		var ids: Array[String] = []
		ids.assign(pending_party)
		if pending_incense_id != "":
			GameState.use_incense(pending_incense_id)
			pending_incense_id = ""
		if _pending_rift_rank != "":
			GameState.start_map_rift(_pending_map_slot_idx, ids, chosen)
		else:
			GameState.start_run(_pending_diff_id, ids, chosen, _pending_hardcore, _pending_endless)
		pending_relic_options.clear()
		pending_relic_choice = -1
		_pending_hardcore = false
		_pending_rift_rank = ""
		_pending_map_slot_idx = -1
		screen = "rift_run"
		render()
		_play_rift_entry_flash()
	))
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back", func():
		screen = "rift_map" if _pending_rift_rank != "" else "rift_hall"
		_pending_rift_rank = ""
		_pending_map_slot_idx = -1
		render()
	))


const MAP_NODE_COLOR := {
	"combat": Palette.HAZARD, "elite": Palette.ELITE, "shop": Palette.COINS,
	"hazard": Palette.CRYSTALS, "boss": Palette.TOKENS,
}
const MAP_NODE_LABEL := {"combat": "C", "elite": "E", "shop": "S", "hazard": "H", "boss": "B"}
const MAP_NODE_ICON := {
	"combat": "res://assets/skills/sword_a.png",
	"elite": "res://assets/skills/sword_big.png",
	"shop": "res://assets/ui/icon_coins.png",
	"hazard": "res://assets/skills/shield_split.png",
	"boss": "res://assets/skills/icon_boss_skull.png",
}


## One marker on the path map — an icon in a domain-colored ring, matching
## MAP_NODE_COLOR's existing per-kind hues. `cb` is an empty (invalid)
## Callable for a marker that's purely informational (a future floor's
## still-open preview, or any already-resolved floor) — only the current
## floor's still-open fork options are actually clickable.
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

	if cb.is_valid():
		var btn := Button.new()
		btn.flat = true
		btn.custom_minimum_size = Vector2(MARKER_SIZE, MARKER_SIZE)
		btn.size = Vector2(MARKER_SIZE, MARKER_SIZE)
		var clear_style := StyleBoxEmpty.new()
		for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(style_name, clear_style)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = str(kind).capitalize()
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

	# Path line first, so the node markers draw on top of it rather than
	# under it.
	for i in n - 1:
		var line := Line2D.new()
		line.width = 3.0
		line.default_color = Color(Palette.LINE.r, Palette.LINE.g, Palette.LINE.b, 0.85)
		line.add_point(anchors[i])
		line.add_point(anchors[i + 1])
		map_ctrl.add_child(line)

	for i in n:
		var opts: Array = layers[i]["options"]
		var resolved: String = str(chosen[i]) if chosen.has(i) else (str(opts[0]) if opts.size() == 1 else "")
		var anchor: Vector2 = anchors[i]
		if resolved != "":
			var marker := _path_node_marker(resolved, i == pos, Callable())
			marker.position = anchor - marker.size * 0.5
			map_ctrl.add_child(marker)
		else:
			var spread := 24.0
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
	var diff := GameState._diff()
	var pos: int = int(GameState.run["pos"])
	var total_layers: int = (GameState.run["layers"] as Array).size()
	var cycle_label := (" (cycle %d)" % (int(GameState.run["cycle"]) + 1)) if GameState.run.get("endless", false) else ""
	v.add_child(_label("%s%s — Node %d/%d" % [diff["name"], cycle_label, pos + 1, total_layers], 18))
	if GameState.run.get("hardcore", false):
		v.add_child(_label("Hardcore Mode active", 12))
	if not GameState.active_incense.is_empty():
		v.add_child(_label("%s active" % str(GameState.active_incense["name"]), 12, true))

	var kind := GameState.current_node_kind()
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
		for h in GameState.current_party():
			v.add_child(_label("%s%s — %d/%d HP%s" % [h.name, " (Champion)" if h.is_champion else "", h.hp, Combat.max_hp(h), " (downed)" if h.is_downed() else ""]))
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


## A colored particle burst on the caster keyed to their Active Ability's
## Awakening bucket (buff/single_dmg/aoe_dmg/support/utility — the same
## grouping GameData.ABILITY_AWAKENING_BUCKET already sorts all 18 effect ids
## into). Gives the 18 different Active Abilities some visual distinction
## beyond the one shared generic "skill" attack/flash animation, without
## needing 18 bespoke sprite frames — every color here is an existing
## Palette token reused for a new purpose, matching ELEMENT_PARTICLE_COLOR's
## own convention.
const ABILITY_BUCKET_COLOR := {
	"buff": Palette.COINS,
	"single_dmg": Palette.EMBER_DANGER,
	"aoe_dmg": Palette.ELITE,
	"support": Palette.RANK_E,
	"utility": Palette.TOKENS,
}
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
				slots.append(_action_slot(GameData.sprite_for_monster(str(monsters[i]["name"])), "",
					current_action == "attack" and current_target == i, false,
					attack_cb, 64.0, "Atk %s" % target_name
				))
			if Combat.qualifies_for_ability(current_hero):
				var cd: int = current_hero.ability_cooldown
				var ability_name := str(GameData.SUBCLASS_ABILITIES.get(current_hero.pool_id, {}).get("name", "Ability")).split(" ")[0]
				var ability_cb := func(hid=current_hero.id):
					_run_combat_turns(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena, true, func(): GameState.set_hero_action(hid, "ability"))
				slots.append(_action_slot(GameData.ability_icon(current_hero.pool_id), str(cd) if cd > 0 else "",
					current_action == "ability", cd > 0,
					ability_cb, 64.0, ability_name
				))
			var defend_cb := func(hid=current_hero.id):
				_run_combat_turns(state, hero_wrappers, hero_rects, monster_wrappers, monster_rects, arena, true, func(): GameState.set_hero_action(hid, "defend"))
			slots.append(_action_slot("res://assets/skills/shield_basic.png", "",
				current_action == "defend", false,
				defend_cb, 64.0, "Defend"
			))
			menu.add_child(_slot_row(slots))
		elif living_heroes.is_empty():
			menu.add_child(_label("The party is down.", 12, true))
		else:
			menu.add_child(_label("...", 12, true))

		var bottom_row := HBoxContainer.new()
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
				))
			victory_col.add_child(reward_row)
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


# ---------------- Terminal ----------------
func _render_terminal(v: VBoxContainer) -> void:
	if _flavor_toast != "":
		v.add_child(_label(_flavor_toast, 12, true))
		_flavor_toast = ""
	var tier := Combat.guild_tier_info()
	var tier_name := str(tier["name"])
	# Guild Tier is purely derived (not stored), so "just reached a new tier"
	# is detected by comparing against the last tier seen at render time —
	# UI-only state, not persisted, same as _flavor_toast above.
	if _last_guild_tier_name != "" and _last_guild_tier_name != tier_name:
		v.add_child(_label(GameData.narrative_line("guild_tier_reached"), 12, true))
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
	v.add_child(tier_row)

	if term_tab == "camp":
		_render_camp(v)
		return

	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "< Back to Camp", func():
		term_tab = "camp"
		medical_picker_bed = -1
		mgmt_branch = ""
		inv_category = ""
		render()
	))
	v.add_child(_hsep())
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
	v.add_child(_label("Guild Name", 12, true))
	v.add_child(_label(GameState.guild_name, 20))

	if hub_cluster != "":
		_render_hub_cluster(v)
		return

	const SCENE_SIZE := Vector2(800, 314)
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
	for entry in area_entries:
		var label_text: String = entry[0]
		var native_rect: Rect2 = entry[1]
		var cb: Callable = entry[2]
		var rect := Rect2(
			native_rect.position.x * scene_scale.x, native_rect.position.y * scene_scale.y,
			native_rect.size.x * scene_scale.x, native_rect.size.y * scene_scale.y
		)
		var hotspot := _camp_area_hotspot(rect, rect, label_text, cb)
		hotspot.position = rect.position
		scene.add_child(hotspot)

	# Pixel-scanned against camp_bg.png directly (flame-colored pixels cluster
	# at x:189-223, y:106-130 on the native 400x157 canvas) — previously
	# reused the Hero Recruits hotspot rect, which happens to overlap the
	# fire horizontally but put the emitter ~15px below the flame's own
	# bottom edge, in the log pile instead of the fire.
	var fire_native_pos := Vector2(206, 112)
	_start_ember_loop(scene, fire_native_pos * scene_scale)
	v.add_child(scene)


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
	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back", func():
		hub_cluster = ""
		render()
	))


## An icon-on-top/label-below card, styled with the game's existing
## parchment-and-ember panel art (the same CardPanelEmber texture the shop
## and victory screens already use) rather than a plain row button — same
## layered visual+click-catcher composition as _camp_area_hotspot (a Panel
## for looks, a flat Button on top for the actual click).
func _hub_card(icon_path: String, label_text: String, cb: Callable) -> Control:
	const CARD_SIZE := Vector2(164, 104)
	var wrap := Control.new()
	wrap.custom_minimum_size = CARD_SIZE

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanelEmber"
	panel.size = CARD_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv := _vbox(6)
	cv.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon_wrap := CenterContainer.new()
	icon_wrap.add_child(_icon(icon_path, 44))
	cv.add_child(icon_wrap)
	var lbl := _label(label_text, 13)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	cv.add_child(lbl)
	panel.add_child(cv)
	wrap.add_child(panel)

	var btn := _button("", cb)
	btn.flat = true
	btn.size = CARD_SIZE
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	wrap.add_child(btn)
	return wrap


## A continuous rising-ember loop at a fixed point (the camp scene's
## campfire) — the bit of ambient motion a static painted scene doesn't have.
## Unlike _spawn_impact_particles (one-shot, self-cleaning after combat),
## this keeps emitting for as long as its parent exists; render()'s
## _clear_root() frees it along with everything else the next time the
## screen rebuilds, so there's nothing to stop manually. `preprocess` seeds
## it already mid-flight on first render instead of every ember popping in
## from the bottom at once.
func _start_ember_loop(parent: Control, pos: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = true
	p.amount = 18
	p.lifetime = 2.4
	p.preprocess = 2.4
	p.direction = Vector2(0, -1)
	p.spread = 20.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 20.0
	p.gravity = Vector2(0, -4)
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.4
	p.color = Palette.EMBER_BRIGHT
	parent.add_child(p)


## A slow, subtle ambient light drift on the hub background — cool night
## tint breathing toward a warm dawn tint and back, continuously. Deliberately
## gentle (not a literal sun-position simulation): the painted scene is fixed
## as a night composition with visible stars, so this isn't a real day cycle,
## just enough slow color movement that the screen doesn't sit as one
## completely static image. bind_node() ties the tween's lifetime to the
## background node, so render()'s _clear_root() cleans it up automatically
## next time the screen rebuilds — same self-cleanup as _start_idle_sway.
func _start_daynight_cycle(bg: CanvasItem) -> void:
	var tween := create_tween()
	tween.bind_node(bg)
	tween.set_loops()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(bg, "modulate", Color(1.1, 0.97, 0.85), 40.0)
	tween.tween_property(bg, "modulate", Color(0.9, 0.95, 1.1), 40.0)


## An invisible clickable region over a prop already drawn in the background
## art — the prop itself stays untouched (no duplicated/cropped copy of it,
## which read as an awkward seam when scaled). Hovering instead fades in a
## soft blurred glow (StyleBoxFlat's built-in shadow, not a hard-edged box)
## around the prop's own silhouette bounds, like it's catching firelight.
func _camp_area_hotspot(hit_rect: Rect2, glow_rect: Rect2, label_text: String, cb: Callable) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(hit_rect.size.x, hit_rect.size.y + 16)
	wrap.size = Vector2(hit_rect.size.x, hit_rect.size.y + 16)

	var glow_style := StyleBoxFlat.new()
	glow_style.bg_color = Color(0, 0, 0, 0)
	glow_style.shadow_color = Color(1.0, 0.85, 0.55, 0.0)
	glow_style.shadow_size = 14
	glow_style.corner_radius_top_left = 10
	glow_style.corner_radius_top_right = 10
	glow_style.corner_radius_bottom_left = 10
	glow_style.corner_radius_bottom_right = 10

	var glow := Panel.new()
	glow.add_theme_stylebox_override("panel", glow_style)
	glow.position = glow_rect.position - hit_rect.position
	glow.size = glow_rect.size
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(glow)

	var btn := Button.new()
	btn.flat = true
	btn.text = ""
	btn.custom_minimum_size = hit_rect.size
	btn.size = hit_rect.size
	var clear_style := StyleBoxEmpty.new()
	for style_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style_name, clear_style)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(cb)
	btn.mouse_entered.connect(func():
		var tw := create_tween()
		tw.tween_method(func(a): glow_style.shadow_color = Color(1.0, 0.85, 0.55, a), 0.0, 0.3, 0.15)
	)
	btn.mouse_exited.connect(func():
		var tw := create_tween()
		tw.tween_method(func(a): glow_style.shadow_color = Color(1.0, 0.85, 0.55, a), 0.3, 0.0, 0.15)
	)
	wrap.add_child(btn)

	var caption := _label(label_text, 11, true)
	caption.position = Vector2(0, hit_rect.size.y + 1)
	caption.custom_minimum_size = Vector2(hit_rect.size.x, 0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(caption)

	return wrap


## The camp's one icon-based hotspot (Rift Hall, no matching background
## prop) — a bare TextureButton (no Button chrome/box) with a caption label
## underneath and a hover brighten for click affordance.
func _camp_hotspot(icon_path: String, size: float, label_text: String, cb: Callable) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(size, size + 18)
	wrap.size = Vector2(size, size + 18)

	var tb := TextureButton.new()
	tb.texture_normal = load(icon_path)
	tb.ignore_texture_size = true
	tb.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	tb.custom_minimum_size = Vector2(size, size)
	tb.size = Vector2(size, size)
	tb.pivot_offset = Vector2(size, size) / 2.0
	tb.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tb.pressed.connect(cb)
	tb.mouse_entered.connect(func():
		var tw := create_tween()
		tw.tween_property(tb, "scale", Vector2(1.1, 1.1), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	)
	tb.mouse_exited.connect(func():
		var tw := create_tween()
		tw.tween_property(tb, "scale", Vector2(1, 1), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	)
	wrap.add_child(tb)

	var caption := _label(label_text, 11, true)
	caption.position = Vector2(0, size + 2)
	caption.custom_minimum_size = Vector2(size, 0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(caption)

	return wrap


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
		mid.add_child(_wrap_label("Passive — %s" % _passive_text(h.pool_id), 10, true))
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
	var now_ms := int(Time.get_unix_time_from_system() * 1000)
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
			var until: int = h.downed_until if h.is_downed() else h.heal_until
			var secs: int = max(0, int((until - now_ms) / 1000.0))
			var name_label := _label(h.name, 10, true)
			name_label.position = Vector2(bx - 10, by + bed_h + 2)
			scene.add_child(name_label)
			var time_label := _label("%ds" % secs, 10, true)
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
		v.add_child(_label("Recovering without a bed (slower):", 12, true))
		for h in waiting:
			v.add_child(_label("%s — %d/%d HP" % [h.name, h.hp, Combat.max_hp(h)], 12))


## True while a craft's brief reveal flourish is playing — guards against a
## second click firing GameState.craft_items/craft_relics again before
## render() rebuilds this screen, the same idea as combat's _combat_animating.
var _crafting_animating: bool = false


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
		v.add_child(_info_row("%s %s x%d" % [GameData.find_rarity(rarity)["name"], GameData.ITEM_CATEGORY_LABEL[category], count], 12, [craft_btn], _icon(GameData.ITEM_CATEGORY_ICON_PATH[category], 20)))

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
		v.add_child(_info_row("%s %s x%d" % [GameData.find_rarity(rrarity)["name"], rtype, rcount], 12, [rcraft_btn], _icon(GameData.RELIC_TYPE_ICON_PATH[rtype], 20)))

	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back to Camp", func():
		screen = "terminal"
		term_tab = "camp"
		render()
	))


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


# ---------------- Compendium ----------------
const _KIND_LABEL := {
	"dmg_pct": "Damage", "hp_pct": "HP", "first_round_pct": "First-Strike Damage",
	"escalate_pct": "Escalating Damage", "mend_pct": "Mend (HP over time)",
	"hazard_guard_pct": "Hazard Guard", "dodge_pct": "Dodge Chance",
	"wipe_guard": "Wipe Guard (survive a wipe)", "boss_alpha_strike": "Boss Alpha Strike",
	"loot_rarity_pct": "Loot Rarity", "counter_pct": "Counter-Attack Chance",
	"cooldown_shave_pct": "Ability Cooldown Shave", "kill_shield_pct": "On-Kill Shield",
}


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
		var text := "[%s] %s — %d/%d\nReward: %s" % [str(q["tier"]).capitalize(), GameState.quest_desc(q), progress, target, GameState.quest_reward_desc(q["reward"])]
		var claim_btn := _icon_button(GameData.BUTTON_ICON_PATH["confirm"], "Claim" if done else "In Progress", func(qid=str(q["id"])):
			GameState.claim_quest(qid)
			render()
		)
		claim_btn.disabled = not done
		v.add_child(_info_row(text, 13, [claim_btn]))
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


# ---------------- Settings ----------------
func _volume_row(label_text: String, value: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := _label(label_text, 14)
	lbl.custom_minimum_size = Vector2(120, 0)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = round(value * 100)
	slider.custom_minimum_size = Vector2(180, 0)
	row.add_child(slider)
	var pct := _label("%d%%" % int(round(value * 100)), 12, true)
	pct.custom_minimum_size = Vector2(40, 0)
	row.add_child(pct)
	# Deliberately not wired through render() — rebuilding the whole tree on
	# every drag tick would tear the slider out from under an in-progress
	# drag. The percent label updates directly instead.
	slider.value_changed.connect(func(new_value: float):
		pct.text = "%d%%" % int(new_value)
		on_change.call(new_value / 100.0)
	)
	return row


func _switch_slot(slot: int) -> void:
	GameState.set_active_slot(slot)
	term_tab = "camp"
	mgmt_branch = ""
	inv_category = ""
	confirm_reset = false
	confirm_delete_slot = -1
	if not GameState.load_save():
		GameState.reset()
	if GameState.guild_name != "":
		screen = "terminal" if GameState.run.is_empty() else "rift_run"
	else:
		pending_crest = 1 + randi() % GameData.CREST_PATH.size()
		screen = "onboard"
	render()


func _render_settings(v: VBoxContainer) -> void:
	v.add_child(_label("Settings", 20))

	v.add_child(_label("Audio", 15))
	v.add_child(_volume_row("Music", GameState.music_volume, func(val: float):
		GameState.music_volume = val
		AudioManager.set_music_volume(val)
		GameState.save_settings()
	))
	v.add_child(_volume_row("SFX", GameState.sfx_volume, func(val: float):
		GameState.sfx_volume = val
		AudioManager.set_sfx_volume(val)
		GameState.save_settings()
	))

	v.add_child(_hsep())
	v.add_child(_label("Display", 15))
	if OS.has_feature("web"):
		# Resolution switching is a desktop-only concept — on Web the browser
		# tab/window already sizes the canvas correctly on its own.
		v.add_child(_wrap_label("The game fits your browser window automatically.", 12, true))
	else:
		var res_opts: Array = GameData.RESOLUTION_OPTIONS
		var res_idx := GameState.resolution_idx
		v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["sort"], "Resolution: %s" % str(res_opts[res_idx]["label"]), func():
			var next_idx: int = (res_idx + 1) % res_opts.size()
			GameState.resolution_idx = next_idx
			GameState.save_settings()
			_apply_resolution(next_idx)
			render()
		))

	v.add_child(_hsep())
	v.add_child(_label("Save Slots", 15))
	_render_slot_list(v)

	v.add_child(_hsep())
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "Back", func():
		screen = _pre_settings_screen
		render()
	))


## Shared by Settings' "Save Slots" section and the title screen's Load Game
## list — same slot rows (Play/Delete), just embedded in two different
## screens, so the delayed delete-confirm timeout's render() gate has to
## check "whichever of them is still showing", not one hardcoded screen name.
func _render_slot_list(v: VBoxContainer) -> void:
	for slot in GameState.SLOT_COUNT:
		var summary := GameState.slot_summary(slot)
		var is_active := slot == GameState.active_slot
		var is_empty: bool = summary.get("empty", true)
		var text := "Slot %d — Empty" % (slot + 1)
		if not is_empty:
			var sealed := int(summary.get("rifts_sealed", 0))
			text = "Slot %d — %s (%d rift%s sealed)" % [slot + 1, str(summary.get("guild_name", "")), sealed, "" if sealed == 1 else "s"]
		if is_active:
			text += "  (Active)"
		var actions: Array[Control] = []
		if not is_active:
			actions.append(_icon_button(GameData.BUTTON_ICON_PATH["confirm"], "Play", func(s=slot):
				_switch_slot(s)
			))
			if not is_empty:
				actions.append(_icon_button("res://assets/skills/shard_green.png", "Click again to confirm delete" if confirm_delete_slot == slot else "Delete", func(s=slot):
					if confirm_delete_slot != s:
						confirm_delete_slot = s
						render()
						get_tree().create_timer(3.0).timeout.connect(func():
							if confirm_delete_slot == s:
								confirm_delete_slot = -1
								if screen == "settings" or screen == "load_game":
									render()
						)
						return
					GameState.delete_slot(s)
					confirm_delete_slot = -1
					render()
				))
		v.add_child(_info_row(text, 13, actions))


func _render_management(v: VBoxContainer) -> void:
	if mgmt_branch == "":
		_render_management_hub(v)
		return

	var branch: Dictionary = {}
	for b in GameData.BRANCHES:
		if b["id"] == mgmt_branch:
			branch = b
	v.add_child(_icon_button(GameData.BUTTON_ICON_PATH["back"], "< Back to Branches", func(): mgmt_branch = ""; render()))
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


## A small button that cycles through `options` (each {id, label}) and calls
## `on_change(new_id)` — shared by the Roster and Inventory tabs' Sort
## controls so both screens follow the same "click to cycle" pattern instead
## of a dropdown neither otherwise uses in this UI.
func _sort_cycle_button(current: String, options: Array, on_change: Callable) -> Button:
	var idx := 0
	for i in options.size():
		if options[i]["id"] == current:
			idx = i
	return _icon_button(GameData.BUTTON_ICON_PATH["sort"], "Sort: %s" % str(options[idx]["label"]), func():
		var next_idx: int = (idx + 1) % options.size()
		on_change.call(options[next_idx]["id"])
		render()
	)


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


## A skill node's effect line — flat stat for ordinary nodes; for a keystone
## or signature, its effects plus (keystones only) the flat drawback.
func _node_effect_text(n: Dictionary) -> String:
	var parts: Array[String] = []
	for e in n.get("effects", []):
		parts.append(Combat.describe_effect(e))
	if str(n["kind"]) != "":
		var flat := Combat.describe_skill(str(n["kind"]), absf(float(n["value"])))
		parts.append(("Drawback: -" + flat.trim_prefix("+")) if float(n["value"]) < 0.0 else flat)
	if n.has("arch"):
		parts.append("[%s]" % GameData.ARCHETYPES.get(str(n["arch"]), ""))
	return "\n".join(parts)


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


## Which slot a quick-equip from Inventory should target: the first free one,
## or — once every slot is full, the normal late-game state — whichever
## occupied slot holds the lowest-rarity item, so gearing up doesn't silently
## stop working just because there's nothing empty left to fill.
func _best_swap_slot(h: Hero, slot_type: String) -> int:
	var free := _first_free_slot(h, slot_type)
	if free >= 0:
		return free
	var worst_idx := -1
	var worst_rank := 999
	for it in GameState.items:
		if it.equipped_to == h.id and it.slot_type() == slot_type and _rarity_rank(it.rarity) < worst_rank:
			worst_rank = _rarity_rank(it.rarity)
			worst_idx = it.equipped_idx
	return worst_idx


func _find_equipped_at(hero_id: String, slot_type: String, idx: int) -> Item:
	for it in GameState.items:
		if it.equipped_to == hero_id and it.slot_type() == slot_type and it.equipped_idx == idx:
			return it
	return null


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


func _rarity_rank(rarity_id: String) -> int:
	for i in GameData.RARITIES.size():
		if GameData.RARITIES[i]["id"] == rarity_id:
			return i
	return 0


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
