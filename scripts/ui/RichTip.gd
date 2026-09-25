class_name RichTip
extends Control
## Card-style tooltips: any Control whose `tooltip_text` holds BBCode (starts
## with "[") shows it as a bordered RichTextLabel card instead of Godot's
## plain one-line tooltip. Attach with UiKit._rich_tip(); DragIcon and
## DropButton (which already carry their own scripts) call card() directly.

func _make_custom_tooltip(for_text: String) -> Object:
	return RichTip.card(for_text)


## Null (= Godot's default tooltip) for plain text, a card for BBCode.
static func card(bbcode: String) -> Control:
	if not bbcode.begins_with("["):
		return null
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.SURFACE
	style.border_color = Palette.LINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.scroll_active = false
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rt.custom_minimum_size = Vector2(280, 0)
	rt.add_theme_font_size_override("normal_font_size", 12)
	rt.add_theme_font_size_override("bold_font_size", 14)
	rt.add_theme_font_size_override("italics_font_size", 12)
	rt.add_theme_color_override("default_color", Palette.TEXT)
	rt.text = bbcode
	panel.add_child(rt)
	return panel
