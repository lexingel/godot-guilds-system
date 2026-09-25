class_name DropZone
extends PanelContainer
## A panel that accepts a Control drag-and-drop drop — DropButton's
## can_accept/on_drop contract, for drop areas that aren't buttons (Party
## Assembly's Front/Back rows). Children should use MOUSE_FILTER_PASS/IGNORE
## so a drop over them still reaches this panel.

var can_accept: Callable = Callable()
var on_drop: Callable = Callable()

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return can_accept.is_valid() and can_accept.call(data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if on_drop.is_valid():
		on_drop.call(data)
