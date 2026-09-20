class_name DropButton
extends Button
## A Button that also accepts a Control drag-and-drop drop, for slots that
## stay clickable (existing behavior) while also being a drop target — e.g. a
## Roster equip slot that still opens its picker on click but now also
## accepts a dragged inventory item. `can_accept`/`on_drop` mirror the
## standard _can_drop_data/_drop_data contract as Callables so callers don't
## need their own Button subclass per slot kind.

var can_accept: Callable = Callable()
var on_drop: Callable = Callable()

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return can_accept.is_valid() and can_accept.call(data)

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if on_drop.is_valid():
		on_drop.call(data)
