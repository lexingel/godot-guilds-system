class_name DropZone
extends PanelContainer
## A panel that accepts a Control drag-and-drop drop — DropButton's
## can_accept/on_drop contract, for drop areas that aren't buttons (Party
## Assembly's Front/Back rows). Children should use MOUSE_FILTER_PASS/IGNORE
## so a drop over them still reaches this panel.

var can_accept: Callable = Callable()
var on_drop: Callable = Callable()
## Called on a plain click anywhere on the zone (children that aren't
## buttons pass their clicks up to it).
var clicked: Callable = Callable()
var _press_at := Vector2(-1, -1)


func _gui_input(event: InputEvent) -> void:
	if not clicked.is_valid() or not (event is InputEventMouseButton) or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press_at = event.position
	elif _press_at.x >= 0.0 and event.position.distance_to(_press_at) < 6.0:
		_press_at = Vector2(-1, -1)
		clicked.call()

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return can_accept.is_valid() and can_accept.call(data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if on_drop.is_valid():
		on_drop.call(data)
