@tool
## One target base location. Multiple locations share BaseCore health at runtime.
class_name BasePointDefinition
extends Resource

@export_group("Identity")
@export var base_id: StringName = &"base_1"
@export var display_name: String = "据点 1"
## Zero means derive a stable display number from LevelResource serialization order.
@export_range(0, 999, 1) var display_number: int = 0

@export_group("Location")
@export var cell: Vector3i = Vector3i.ZERO


func get_marker_label(resolved_number: int) -> String:
	return "据点 %d" % maxi(1, resolved_number)
