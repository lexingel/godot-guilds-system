class_name DragIcon
extends TextureRect
## A TextureRect that starts a Control drag when picked up, carrying whatever
## Variant is set as `drag_payload` to any DropButton it's released over (see
## Main.gd's _action_slot `drop_target` param). Returns null (no drag) when
## drag_payload is unset, so a plain _icon()-built TextureRect can be swapped
## for this without becoming draggable by accident.

var drag_payload: Variant = null

func _get_drag_data(_at_position: Vector2) -> Variant:
	if drag_payload == null:
		return null
	var preview := TextureRect.new()
	preview.texture = texture
	preview.custom_minimum_size = custom_minimum_size
	preview.size = size
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.modulate = Color(1, 1, 1, 0.85)
	set_drag_preview(preview)
	return drag_payload


## BBCode tooltips render as item cards (see RichTip).
func _make_custom_tooltip(for_text: String) -> Object:
	return RichTip.card(for_text)
