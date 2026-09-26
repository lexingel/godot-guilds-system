class_name UiKit
extends Control
## Bottom of Main's inheritance chain (UiKit <- RosterView <- BattleView <- RiftRunView <-
## GuildViews <- Main): every piece of UI state, shared widget builders and
## text helpers. Nothing here may call a screen renderer; render() is a
## virtual that Main overrides so widgets/callbacks can still trigger it.

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
var _revealed_rewards: Array = []   # the reward_options array whose flip-reveal already played (by reference)
var selected_item_id: String = ""   # the Inventory item whose card shows in the right pane
var roster_tab: String = "overview"   # overview | gear | skills | history — the hero card's open tab
var _combat_hotkeys: Dictionary = {}   # key string ("1", "Space") -> Callable for the current hero's actions; rebuilt every render


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
	size = max(size, 12)   # type floor: nothing on screen below 12px
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
	var label_h := 30.0 if label_text != "" else 0.0   # room for a 2-line caption
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
		# Wraps to at most two lines, a little wider than the tile; the wrap
		# and trim have to be set before sizing or the label grows to fit.
		var lbl := _label(label_text, 12, disabled)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.max_lines_visible = 2
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_constant_override("line_spacing", -3)
		var cap_w := size + 22.0
		lbl.custom_minimum_size = Vector2(cap_w, label_h)
		lbl.size = Vector2(cap_w, label_h)
		lbl.position = Vector2((size - cap_w) * 0.5, size + 1.0)
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
func _reward_tile(icon_path: String, name_text: String, rarity_text: String, desc_text: String, cb: Callable, tip_bbcode: String = "") -> Control:
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
	if tip_bbcode != "":
		_rich_tip(btn, tip_bbcode)
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
	t.tooltip_text = _item_card(it, compare_for)
	t.mouse_default_cursor_shape = Control.CURSOR_MOVE
	t.drag_payload = {"kind": "inventory_item", "item_id": it.id, "slot_type": it.slot_type()}
	return t


## A sprite drawn at `scale` (width capped at `max_w`), with the rect sized
## to the sprite itself rather than a square — so it can stand on a ground
## line instead of floating in a centered box.
func _sprite_fit(path: String, scale: float, max_w: float = INF) -> TextureRect:
	var tex: Texture2D = load(path)
	var sz := tex.get_size()
	var k := minf(scale, max_w / sz.x)
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.custom_minimum_size = (sz * k).round()
	t.size = t.custom_minimum_size
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
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
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
		var utext := "%s [%s]" % [str(udef.get("desc", "")), GameData.ARCHETYPES.get(str(udef.get("arch", "")), "Unique")]
		if it.kind != "":
			utext = "%s · %s" % [Combat.describe_skill(it.kind, it.value), utext]
		if it.item_rank != "":
			utext = "Rank %s · %s" % [it.item_rank, utext]
		return utext
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


## Party Assembly's formation hint: the role's in-position bonus when the
## hero stands in their natural row, otherwise which row they'd rather be in.
func _position_text(h: Hero) -> String:
	var pos: Dictionary = GameData.ROLE_POSITION.get(GameData.hero_role(h), {})
	if pos.is_empty():
		return ""
	if h.formation != pos["row"]:
		return "Out of position — suits the %s row (%s)" % [pos["row"], pos["name"]]
	var parts: Array[String] = []
	for e in pos["effects"]:
		parts.append(Combat.describe_effect(e))
	return "%s row · %s: %s" % [str(pos["row"]).capitalize(), pos["name"], "; ".join(parts)]


## A subclass passive as BBCode — "Killer's Eye: +14% damage vs foes below
## 40% HP" plus a colored archetype chip (render with _rich_line).
func _passive_bb(pool_id: String) -> String:
	var p := GameData.subclass_passive(pool_id)
	if p.is_empty():
		return "None"
	var parts: Array[String] = []
	for e in p["effects"]:
		parts.append(Combat.describe_effect(e))
	return "[b]%s[/b]: %s  %s" % [str(p["name"]).replace("[", "[lb]"), "; ".join(parts).replace("[", "[lb]"), _arch_chip(str(p["arch"]))]


## The hero's archetype counts as colored chips, biggest first.
func _build_bb(h: Hero) -> String:
	var counts := Combat.hero_archetype_counts(h)
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return int(counts[a]) > int(counts[b]))
	var parts: Array[String] = []
	for k in keys:
		parts.append("%s ×%d" % [_arch_chip(str(k)), int(counts[k])])
	return "  ".join(parts)


## The single archetype a hero leans into most ("" if none) — the colored
## badge on roster portraits and party cards.
func _main_arch(h: Hero) -> String:
	var counts := Combat.hero_archetype_counts(h)
	var best := ""
	for k in counts:
		if best == "" or int(counts[k]) > int(counts[best]):
			best = k
	return best


## _info_row with a BBCode body (see _rich_line).
func _rich_info_row(bbcode: String, size: int, actions: Array[Control], leading: Control = null) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if leading:
		row.add_child(leading)
	row.add_child(_rich_line(bbcode, size))
	for a in actions:
		row.add_child(a)
	return row


## A wrapping RichTextLabel line for BBCode text (colored chips etc.) —
## the rich counterpart of _wrap_label. Ignores the mouse so tooltips and
## drops on whatever sits underneath still work.
func _rich_line(bbcode: String, size: int = 11, muted: bool = false) -> RichTextLabel:
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.mouse_filter = Control.MOUSE_FILTER_PASS
	size = max(size, 12)
	rt.add_theme_font_size_override("normal_font_size", size)
	rt.add_theme_font_size_override("bold_font_size", size)
	rt.add_theme_color_override("default_color", Palette.MUTED if muted else Palette.TEXT)
	rt.text = _kw_hints(bbcode)
	return rt


## Wraps the first mention of each glossary keyword (GameData.KEYWORDS) in
## a [hint] so hovering it explains the term; underlined so it reads as
## hoverable. Only touches text outside BBCode tags.
func _kw_hints(bbcode: String) -> String:
	var out := bbcode
	for k in GameData.keyword_regexes():
		var re: RegEx = k[2]
		var search_from := 0
		while true:
			var m := re.search(out, search_from)
			if m == null:
				break
			var inside_tag := out.rfind("[", m.get_start()) > out.rfind("]", m.get_start())
			if inside_tag:
				search_from = m.get_end()
				continue
			# Quoted: an apostrophe in an unquoted hint value breaks the parse and
			# the whole line then renders as raw BBCode.
			var wrapped := "[hint=\"%s — %s\"][u]%s[/u][/hint]" % [k[0], k[1], m.get_string()]
			out = out.substr(0, m.get_start()) + wrapped + out.substr(m.get_end())
			break
	return out


## A tooltip card's glossary footer: every keyword the card mentions, once.
func _kw_footer(text: String) -> String:
	var lines: Array[String] = []
	for k in GameData.keyword_regexes():
		var re: RegEx = k[2]
		if re.search(text) != null:
			lines.append("[b]%s[/b] — %s" % [k[0], k[1]])
	if lines.is_empty():
		return ""
	return "\n\n[color=#%s]Keywords[/color]\n[color=#%s]%s[/color]" % [Palette.MUTED2.to_html(false), Palette.MUTED.to_html(false), "\n".join(lines)]


## "−3% mend; +15% damage while below 50% HP" — a scar's wound and its upside.
func _scar_text(scar_name: String) -> String:
	var parts: Array[String] = []
	var wound: Dictionary = GameData.SCAR_TABLE.get(scar_name, {})
	for kind in wound:
		parts.append(Combat.describe_skill(kind, float(wound[kind])))
	for e in GameData.SCAR_UPSIDES.get(scar_name, []):
		parts.append(Combat.describe_effect(e))
	return "; ".join(parts)


## History, earned traits, the nearest trait still to earn, and grown bonds —
## as BBCode lines (render with _rich_line).
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
			lines.append("Earned: [b]%s[/b] — %s  %s" % [t["name"], what.replace("[", "[lb]"), _arch_chip(str(t["arch"]))])
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


const ITEM_RARITY_COLOR := {"common": Palette.MUTED, "rare": Palette.RANK_D, "epic": Palette.VIOLET_BRIGHT, "legendary": Palette.RANK_S}
const ARCH_COLOR := {"opener": Palette.CRYSTALS, "attrition": Palette.EMBER, "guardian": Palette.RANK_E,
	"evasion": Palette.VIOLET_BRIGHT, "sustain": Palette.TOKENS, "executioner": Palette.HAZARD}


func _bb(c: Color, text: String) -> String:
	return "[color=#%s]%s[/color]" % [c.to_html(false), text.replace("[", "[lb]")]


func _arch_chip(arch: String) -> String:
	return _bb(ARCH_COLOR.get(arch, Palette.MUTED), "◆ " + str(GameData.ARCHETYPES.get(arch, arch))) if arch != "" else ""


## An item as a tooltip card (RichTip): rarity-colored name, type/rank line,
## base stat, one line per affix, situational effects in italics with their
## archetype, a Legendary's text + drawback in red, and — given a hero —
## what equipping it would change (▲ gains / ▼ losses vs the slot's item).
func _item_card(it: Item, compare_for: Hero = null, slot: int = -2) -> String:
	var lines: Array[String] = []
	var rc: Color = ITEM_RARITY_COLOR.get(it.rarity, Palette.TEXT)
	lines.append("[b]%s[/b]" % _bb(rc, it.name))
	var sub := "%s %s" % [it.rarity.capitalize(), GameData.ITEM_CATEGORY_LABEL.get(it.category, it.category)]
	if it.item_rank != "":
		sub += " · Rank %s" % it.item_rank
	lines.append(_bb(Palette.MUTED, sub))
	if it.implicit_kind != "":
		lines.append(_bb(Palette.MUTED, "Base: " + Combat.describe_skill(it.implicit_kind, it.implicit_value)))
	for pair in [[it.kind, it.value], [it.secondary_kind, it.secondary_value], [it.tertiary_kind, it.tertiary_value]]:
		if str(pair[0]) != "":
			lines.append(Combat.describe_skill(str(pair[0]), float(pair[1])))
	if it.unique_id != "":
		var udef := GameData.find_unique_item(it.unique_id)
		for e in udef.get("effects", []):
			lines.append("[i]%s[/i]  %s" % [Combat.describe_effect(e).replace("[", "[lb]"), _arch_chip(str(udef.get("arch", "")))])
		if it.drawback_kind != "":
			lines.append(_bb(Palette.HAZARD, "Drawback: " + Combat.describe_skill(it.drawback_kind, it.drawback_value)))
		if it.locked_role != "":
			lines.append(_bb(Palette.MUTED, "%s only" % it.locked_role.capitalize()))
	for e in it.effects:
		lines.append("[i]%s[/i]  %s" % [Combat.describe_effect(e).replace("[", "[lb]"), _arch_chip(str(e.get("arch", "")))])
	if it.socketed_kind != "":
		lines.append(_bb(Palette.CRYSTALS, "Socket: " + Combat.describe_skill(it.socketed_kind, it.socketed_value)))
	if compare_for != null and it.equipped_to != compare_for.id:
		if slot == -2:
			slot = _best_swap_slot(compare_for, it.slot_type())
		var current: Item = _find_equipped_at(compare_for.id, it.slot_type(), slot) if slot >= 0 else null
		lines.append("")
		lines.append(_bb(Palette.MUTED, "If equipped on %s%s:" % [compare_for.name.split(" the ")[0], (" (replacing %s)" % current.name) if current else ""]))
		var a := _item_stat_map(it)
		var b := _item_stat_map(current)
		var any := false
		for kind in GameData.BUILD_KINDS:
			var d: float = float(a.get(kind, 0.0)) - float(b.get(kind, 0.0))
			if absf(d) >= 0.001:
				# hazard guard reads inverted ("-8% hazard severity" is good), so
				# judge better/worse by the raw delta, not the text's sign.
				lines.append(_bb(Palette.RANK_E if d > 0 else Palette.HAZARD, ("▲ " if d > 0 else "▼ ") + Combat.describe_skill(kind, d)))
				any = true
		if current:
			var lost: Array = GameData.find_unique_item(current.unique_id).get("effects", []) if current.unique_id != "" else current.effects
			for e in lost:
				lines.append(_bb(Palette.HAZARD, "▼ loses: " + Combat.describe_effect(e)))
				any = true
		if not any:
			lines.append(_bb(Palette.MUTED, "No stat change"))
	var card := "\n".join(lines)
	return card + _kw_footer(card)


## "Party power 142 / Recommended 150 — Even fight", colored like a traffic
## light. Bands match the tuned difficulty curve: under ~1.1x the rift wins
## more often than not, ~1.1-1.5x is a real fight, 1.5x+ is comfortable.
func _power_readout(power: int, rec: int, prefix: String = "Party power") -> Label:
	var ratio := float(power) / float(max(1, rec))
	var verdict := "Risky" if ratio < 1.1 else ("Even fight" if ratio < 1.5 else "Favored")
	var color: Color = Palette.HAZARD if ratio < 1.1 else (Palette.COINS if ratio < 1.5 else Palette.RANK_E)
	var l := _label("%s %d / Recommended %d — %s" % [prefix, power, rec, verdict], 13)
	l.add_theme_color_override("font_color", color)
	return l


## Champion + the 4 strongest heroes able to go right now.
func _best_party_power() -> int:
	var ready: Array = GameState.heroes.filter(func(h): return not h.is_downed())
	ready.sort_custom(func(a, b): return Combat.power_of(a) > Combat.power_of(b))
	var party: Array = ready.slice(0, 4)
	var champ := GameState.ensure_champion()
	if champ:
		party.append(champ)
	return Combat.party_power(party)


## A Roster stat line's tooltip: the total, then every source feeding it
## (Combat.hero_skill_sources), then situational bonuses that only apply in
## the right moment (Combat.hero_effects stat entries of this kind).
func _stat_breakdown_card(h: Hero, kind: String, total: float) -> String:
	var lines: Array[String] = ["[b]%s[/b]" % Combat.describe_skill(kind, total).replace("[", "[lb]")]
	for src in Combat.hero_skill_sources(h, kind):
		var v: float = src[1]
		lines.append("%s  %s" % [_bb(Palette.RANK_E if v > 0 else Palette.HAZARD, "%s%d%%" % ["+" if v > 0 else "-", int(round(absf(v) * 100))]), str(src[0]).replace("[", "[lb]")])
	var situational: Array[String] = []
	for e in Combat.hero_effects(h):
		if e.get("kind", "") == kind:
			situational.append("[i]%s[/i]  %s" % [Combat.describe_effect(e).replace("[", "[lb]"), _bb(Palette.MUTED, str(e.get("source", "")))])
	if not situational.is_empty():
		lines.append("")
		lines.append(_bb(Palette.MUTED, "Situational:"))
		lines.append_array(situational)
	var card := "\n".join(lines)
	return card + _kw_footer(card)


## Gives `node` a card tooltip (see RichTip) — attaches the RichTip script
## when the node has none of its own.
func _rich_tip(node: Control, bbcode: String) -> void:
	if node.get_script() == null:
		node.set_script(RichTip)
	node.tooltip_text = bbcode
	if node.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		node.mouse_filter = Control.MOUSE_FILTER_PASS


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
			lines.append(Combat.describe_skill(kind, d))
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
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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
func _camp_area_hotspot(hit_rect: Rect2, glow_rect: Rect2, label_text: String, cb: Callable, with_plaque: bool = true) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = hit_rect.size
	wrap.size = hit_rect.size

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

	btn.tooltip_text = label_text
	if with_plaque:
		var plaque := _camp_plaque(label_text)
		plaque.position = Vector2((hit_rect.size.x - plaque.size.x) * 0.5, hit_rect.size.y - plaque.size.y - 6.0)
		wrap.add_child(plaque)
	return wrap


## A small dark name plaque for a camp building (click-through: the
## building's own hotspot underneath handles the click).
func _camp_plaque(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(Palette.INK, 0.82)
	st.border_color = Palette.EMBER_DEEP
	st.set_border_width_all(1)
	st.set_corner_radius_all(4)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", st)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(text, 13)
	l.add_theme_color_override("font_color", Palette.EMBER_BRIGHT)
	p.add_child(l)
	p.size = p.get_combined_minimum_size()
	return p


## A plain ProgressBar with flat, square-cornered styles; `transparent_bg`
## drops the dark track (a bar stacked over another needs none).
func _flat_bar(max_val: int, value: int, width: float, height: float, color: Color, transparent_bg: bool = false) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = max(1, max_val)
	bar.value = clampi(value, 0, max(1, max_val))
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, height)
	bar.size = bar.custom_minimum_size
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0) if transparent_bg else Color(Palette.INK, 0.9)
	if not transparent_bg:
		bg.border_color = Color(0, 0, 0, 0.8)
		bg.set_border_width_all(1)
		bg.set_expand_margin_all(1)
	bar.add_theme_stylebox_override("background", bg)
	var fs := StyleBoxFlat.new()
	fs.bg_color = color
	bar.add_theme_stylebox_override("fill", fs)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	return bar


## A small round ember badge with a count (or "!") and a tooltip.
func _count_badge(text: String, tooltip: String) -> Control:
	var badge := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.EMBER
	style.border_color = Palette.INK
	style.set_border_width_all(2)
	style.set_corner_radius_all(999)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", style)
	badge.tooltip_text = tooltip
	var l := _label(text, 12)
	l.add_theme_color_override("font_color", Palette.INK)
	badge.add_child(l)
	return badge


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


## True while a craft's brief reveal flourish is playing — guards against a
## second click firing GameState.craft_items/craft_relics again before
## render() rebuilds this screen, the same idea as combat's _combat_animating.
var _crafting_animating: bool = false


# ---------------- Compendium ----------------
const _KIND_LABEL := {
	"dmg_pct": "Damage", "hp_pct": "HP", "first_round_pct": "First-Strike Damage",
	"escalate_pct": "Escalating Damage", "mend_pct": "Mend (HP over time)",
	"hazard_guard_pct": "Hazard Guard", "dodge_pct": "Dodge Chance",
	"wipe_guard": "Wipe Guard (survive a wipe)", "boss_alpha_strike": "Boss Alpha Strike",
	"loot_rarity_pct": "Loot Rarity", "counter_pct": "Counter-Attack Chance",
	"cooldown_shave_pct": "Ability Cooldown Shave", "kill_shield_pct": "On-Kill Shield",
}


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


## A skill node's effect line — flat stat for ordinary nodes; for a keystone
## or signature, its effects plus (keystones only) the flat drawback.
func _node_effect_text(n: Dictionary) -> String:
	var parts: Array[String] = []
	for e in n.get("effects", []):
		parts.append(Combat.describe_effect(e))
	if str(n["kind"]) != "":
		var flat := Combat.describe_skill(str(n["kind"]), float(n["value"]))
		parts.append(("Drawback: " + flat) if float(n["value"]) < 0.0 else flat)
	if n.has("arch"):
		parts.append("[%s]" % GameData.ARCHETYPES.get(str(n["arch"]), ""))
	return "\n".join(parts)


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


func _rarity_rank(rarity_id: String) -> int:
	for i in GameData.RARITIES.size():
		if GameData.RARITIES[i]["id"] == rarity_id:
			return i
	return 0


## Overridden by Main (the screen router); declared here so every layer
## can call it.
func render() -> void:
	pass
